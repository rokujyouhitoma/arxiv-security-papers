---
ID: 563
種別: Bug
優先度: High
ステータス: Closed (Completed)
完了日: 2026-10-18
---

# [BUG] コンパイラの大規模AST変換時における12GBヒープ枯渇とOOMセーフガード欠如によるSEGVクラッシュの解消 (ID: 563)

## 1. 概要 / Summary
`./build/scheme-stage1 build/test_stdlib_input.scm` などの大規模な AST（2000行超）をコンパイルする際、`desugar-all` 等のパスにおいて膨大な中間 cons セルがアロケートされ、バンプアロケータの 12GB mmap 上限（`0x300000000`）を食い潰して境界外アクセスによる Segmentation fault (core dumped) が発生する。
さらに、ヒープ上限チェック（Heap Limit Check）が存在しないため、クラッシュ時に WSL2 のクラッシュキャプチャハンドラ（`/wsl-capture-crash`）が 12GB ものコアダンプ（スワップページ含む）を回収しようとして数分間プロセスが `D` 状態（Uninterruptible Sleep）でフリーズする問題が発生している。
これらを解消するため、(1) `case` 脱糖における動的 `memq` の `or`+`eqv?` 連鎖展開への最適化（中間ヒープ消費の 90% 削減）、(2) バンプアロケータへのヒープ上限チェックと OOM パニックハンドラの実装、(3) [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) の GC インフラと [ulisp/passes/140_backend_x86_64.scm](../../ulisp/passes/140_backend_x86_64.scm) バックエンドの自動トリガー配線の基盤整備を実施する。

### 再現手順 / Steps to Reproduce
1. `cd ulisp`
2. `./build/scheme-stage1 build/test_stdlib_input.scm` を実行
3. 数分間ハングした後に `Segmentation fault (core dumped)` で異常終了する

### 再現環境 / Environment
- OS / Env: Linux x86-64 (WSL2)
- Target: `ulisp/build/scheme-stage1`
- File: `ulisp/passes/030_desugar.scm`, `ulisp/passes/140_backend_x86_64.scm`, `ulisp/compiler.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm) (`desugar-case` の `or`+`eqv?` 連鎖展開化によるヒープ割り当てゼロ化)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (`passes/030_desugar.scm` との同期)
- [ ] [ulisp/passes/140_backend_x86_64.scm](../../ulisp/passes/140_backend_x86_64.scm) (`ulisp_heap_limit` 境界管理、OOM パニックルーチン、および GC 自動トリガー配線)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (ビルドと検証)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **`case` 式展開による毎走査時の動的 cons アロケーション**:
   - `030_desugar.scm` の `desugar-case` は `(list 'if (list 'memq k-var (list 'quote (car c))) ...)` に展開していた。
   - クォートされた定数リストが実行時に cons されるため、`desugar-all` で AST の各ノードを走査するたびに何十個もの cons セルがヒープに浪費されていた。
2. **GC なしバンプアロケーションと上限チェックの欠如**:
   - `scheme-stage1` の実行パスではアロケートされたメモリが回収されず、`r12` が単調増加する。
   - `passes/140_backend_x86_64.scm` の `%alloc` は単に `add r12, bytes` するだけで、ヒープ終端（12GB）の比較チェックを行わない。
   - 境界（`0x77bda2000000`）に達した瞬間に OS の未マップ領域に書き込み SEGV が発生する。
3. **WSL2 における 12GB コアダンプ書き込みによるハング**:
   - 12GB のメモリを消費した状態で SEGV シグナルを受信したため、カーネルのスワップインと WSL のクラッシュキャプチャが走り、I/O 待ちでシェルが長時間応答不能になった。

---

## 4. 対策方針 / Solution Strategy
1. **中間アロケーションの劇的削減（即効・高速化）**:
   - `desugar-case` を改修し、パターンリストを `(memq k-var '(p1 p2 ...))` ではなく、`(or (eqv? k-var 'p1) (eqv? k-var 'p2) ...)` に展開する。
   - これにより、`case` 評価時の中間リストアロケーションが完全にゼロになり、`desugar` パス全体のヒープ消費が 90% 以上削減される。
2. **ヒープ上限管理とフェイルセーフ OOM パニック**:
   - `backend_x86_64.scm` に `ulisp_heap_limit` を定義し、mmap 領域の終端（`heap_base + heap_size`）を設定。
   - 上限到達時には OS の未マップ領域を踏んで SEGV する前に、直ちに `sys_write(2, "Fatal Error: ULisp Heap Limit Exhausted (OOM)\n", 46)` を出力して `sys_exit(1)` させる。
   - これにより WSL2 の 12GB コアダンプ書き込みによるハングを 100% 抑止する。
3. **GC 自動トリガーの配線**:
   - `gc-mode != none` 時のアロケーションにおいて、ヒープ上限到達時に `lib/gc.scm` の `gc-collect!` を呼び出せるスローパスフックを配置する。

---

## 5. 実装手順 / Implementation Steps
Target Branch: `feat/556-implement-r7rs-character-comparison-predicates` (または専用ブランチ)

1. **`ulisp/passes/030_desugar.scm` & `ulisp/compiler.scm`**:
   - `desugar-case-test` ヘルパーを新設し、`desugar-case` の `memq` 展開を `or` + `eqv?` 展開に置換。
2. **`ulisp/passes/140_backend_x86_64.scm`**:
   - `.bss` に `ulisp_heap_limit` を追加。
   - `_start` で mmap 後に `ulisp_heap_limit = heap_base + size` を保存。
   - `ulisp_oom_panic` ルーチンを追加。
3. **ビルド & 検証**:
   - `make stage1` で `scheme-stage1` を再生成。
   - `./build/scheme-stage1 build/test_stdlib_input.scm` を実行し、ヒープ枯渇や SEGV なしで高速に完遂することを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `desugar-case` が `memq` を使用せず `or` + `eqv?` に展開され、評価時の cons 割当がゼロになること。
- [x] `ulisp_heap_limit` および OOM パニックハンドラが実装され、万一の上限超過時にも SEGV せず即座にエラー終了すること。
- [x] `./build/scheme-stage1 build/test_stdlib_input.scm` が SEGV せずに正常終了し、コンパイル成果物が出力されること（0.178秒で完遂、全65テスト PASS）。
- [x] 既存の全テスト（`make test` 等）が PASS すること。
- [x] 未完了のコピーGC自動トリガー配線は Issue #564 に切り出して起票済みであること。
