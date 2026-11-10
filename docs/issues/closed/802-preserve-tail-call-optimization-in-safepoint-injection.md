---
ID: 802
種別: Bug
優先度: High
ステータス: Closed
完了日: 2026-11-11
---

# [BUG/COMPILER] セーフポイント注入時における末尾呼び出し最適化 (TCO) の保護とスタックオーバーフロー防止 (ID: 802)

## 1. 概要 / Summary
セーフポイント挿入パス（`pass_inject_safepoints.scm`）を本番コンパイラ（`ulisp/compiler.scm`）に結合するにあたり、Scheme (R7RS) の言語仕様における最重要基盤である「末尾呼び出し最適化（Tail-Call Optimization / TCO）」が破壊される重大なリスクが存在する。

Scheme ではループ構造が末尾再帰関数（`named-let`、`letrec`、末尾再帰 `define`）によって表現される。関数の末尾位置（Tail Position）に不用意に `(%synapse-safepoint-poll!)` 式を挿入したり、末尾呼出しの戻り値を `begin` 等でラップするような変換が行われると、後続の最適化パス（Pass 100 `contify`、Pass 125 `lir_continuation`、Pass 126 `lir_control`、Pass 124 `lir_call_abi`）が当該呼び出しを末尾位置と認識できなくなり、スタックフレームの再利用（`jmp` 命令への置換）が行われず、1 ループごとにスタックフレームが累積して致命的なスタックオーバーフロー（CWE-400 / CWE-674: リソース枯渇・無制限再帰）が発生する。

本 Issue では、セーフポイント注入パスおよび LIR 最適化・コード生成パイプラインにおいて末尾位置コンテキストを厳密に判定・保存し、末尾再帰の性質を 100% 損なうことなくループ戻り辺および手続先頭に非破壊的なポーリング命令を注入できる設計を検証・確立する。

---

## 2. 専門家レビュー視点 (Multi-Agent Perspectives)

- **Project Manager (PM)**:
  - TCO の破壊は Scheme コンパイラとしての致命的欠陥であり、本番結合の絶対的ブロッカーである。全品質ゲート（単体テスト、100万回反復テスト、アセンブリ検証、並行ストレステスト）の 100% PASS を最優先で統括する。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - AST 変換（Pass `pass-synapse-inject-safepoints`）と LIR 生成（Pass 125, 126, 129, 130）の境界を整理する。`begin` 形式で式をラップした際にも、LIR 側の `cont-recurse-tail?` や `lir-compile-let` のインプレース引数シャッフルが末尾 `%cont-call` を透過的に検知できるように正規化を行い、TCO の健全性を形式的に保証する。
- **Information Security Specialist**:
  - CWE-400（制御されないリソース消費: スタック枯渇 DoS）および CWE-674（制御されない再帰）を完全に排除する。長時間稼働する並行タスクがスタックオーバーフローで突然死（SIGSEGV / OOM）することを防止する。
- **Systems Architect**:
  - プロローグ注入とループ戻り辺注入の役割分担を明確化し、不要な二重ポーリング（多重オーバーヘッド）を回避する。また、LIR レベルでのセーフポイントポーリング命令生成（`lir-compile-zero-arg`）を完備する。
- **Software Quality Assurance Specialist (SQA)**:
  - 1,000,000 回の末尾再帰反復テストによる固定スタックフレーム動作の検証、およびコンパイル済み x86-64 アセンブリにおける `call` 命令の非出現（`jmp` / ループブロックへの直接ジャンプ確認）をテストスイートに組み込み、リグレッションを恒久的に防ぐ。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm) - 末尾位置コンテキストの厳密判定とバックエッジ注入の適正化
- [x] [ulisp/lir/125_lir_continuation.scm](../../ulisp/lir/125_lir_continuation.scm) - `cont-recurse-tail?` / `cont-loop-rotation-candidate?` における `begin` 透過認識
- [x] [ulisp/lir/126_lir_control.scm](../../ulisp/lir/126_lir_control.scm) - `lir-compile-let` の In-place Tail Loop Argument Shuffle における `begin` 透過
- [x] [ulisp/lir/129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm) - `lir-compile-zero-arg` への `%synapse-safepoint-poll!` 命令選択の追加
- [x] [tests/concurrency/test_pass_inject_safepoints.scm](../../tests/concurrency/test_pass_inject_safepoints.scm) - TCO 保証、100万回反復、およびスタックサイズ上限検証テストの追加
- [x] [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md) - TCO 保護とスタック安全性評価結果の記録

---

## 4. 根本原因分析 (RCA) / Root Cause Analysis
1. **LIR Continuation / Control Flow におけるパターン認識の狭隘性**:
   - `ulisp/lir/125_lir_continuation.scm` の `cont-recurse-tail?` は `(eq? (car expr) '%cont-call)` または `let` のみを想定しており、`(begin (%synapse-safepoint-poll!) (%cont-call ...))` のような `begin` ラッパーを非末尾と判定して `#f` を返していた。
   - `cont-loop-rotation-candidate?` や `cont-can-unroll-counting-loop?` も同様に、本体先頭に `begin` があるとパターン照合が失敗し、最適化が脱落していた。
2. **LIR In-place Argument Shuffle の未対応**:
   - `ulisp/lir/126_lir_control.scm` の `lir-compile-let` は、引数シャッフル最適化時に `(eq? (car body) '%cont-call)` を直接要求しており、`begin` でラップされた場合にスタック退避コードが過剰生成され、パフォーマンスが著しく悪化していた。
3. **LIR プリミティブ命令選択の欠落**:
   - `compiler/primitives.scm` の `zero-arg-prim?` に `%synapse-safepoint-poll!` が定義されているが、`ulisp/lir/129_lir_primitives.scm` の `lir-compile-zero-arg` の `case` 文にハンドラが存在せず、LIR コードが正しく生成されていなかった。
4. **AST レベルでの無差別バックエッジ注入**:
   - `pass_inject_safepoints.scm` において、手続プロローグに既にセーフポイントが存在するにもかかわらず、ループ呼び出し直前にも無差別に `begin` で包むため、TCO 判定やループ最適化パスの妨げになっていた。

---

## 5. 恒久対策 / Permanent Fix
1. **LIR 側の透過的末尾判定の導入**:
   - `cont-recurse-tail?` に `begin` 節を追加し、末尾位置にある式を再帰的に判定する。
   - `cont-loop-rotation-candidate?` および `cont-can-unroll-counting-loop?` において、先頭のセーフポイント式を透過して本体ループ構造を認識できるように拡張する。
   - `lir-compile-let` の In-place Tail Loop Argument Shuffle において、`begin` ブロック末尾の `%cont-call` を透過的に検知・適用する。
2. **`lir-compile-zero-arg` の命令選択完備**:
   - `%synapse-safepoint-poll!` / `%safepoint-poll!` に対し、適切な LIR 命令（メモリフェンスまたは軽量ポーリング）を割り当て、コンパイルエラーや未定義動作を防止する。
3. **セーフポイント注入パスの TCO 保護**:
   - 末尾位置フラグを適切に意識し、末尾再帰呼び出しの TCO 性質を損なわない形でポーリングを配置する。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `fix/802-preserve-tail-call-optimization-in-safepoint-injection`

### Step 1: LIR 命令選択の追加 (`ulisp/lir/129_lir_primitives.scm`)
- `lir-compile-zero-arg` の `case` 文に `%synapse-safepoint-poll!`、`%safepoint-poll!`、`synapse-safepoint-poll!` を追加。
- 実行時にプリエンプションフラグをポーリングする軽量コード（または `#t` 即値ロード＋メモリフェンス）を生成。

### Step 2: LIR Continuation パスにおける `begin` 透過認識 (`ulisp/lir/125_lir_continuation.scm`)
- `cont-recurse-tail?` に `((eq? (car expr) 'begin) ...)` を追加し、`begin` 末尾式の再帰判定をサポート。
- `cont-loop-rotation-candidate?` で先頭の `safepoint-poll` や `begin` をスキップしてループ構造を認識。
- `cont-can-unroll-counting-loop?` で `begin` 内の `%cont-call` を抽出可能にする。

### Step 3: LIR Control パスにおけるインプレースシャッフル透過 (`ulisp/lir/126_lir_control.scm`)
- `lir-compile-let` において、`body` が `begin` でラップされた `%cont-call` である場合でも、インプレース引数シャッフルを適用。

### Step 4: セーフポイント注入パスの精密化 (`ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm`)
- 不要な二重注入の防止と、末尾再帰呼び出しの TCO 保護構造の整備。

### Step 5: テストスイート拡充 (`tests/concurrency/test_pass_inject_safepoints.scm`)
- Group 9（TCO Preservation & Stack Overflow Prevention）を追加：
  1. 1,000,000 回の末尾再帰反復テストがスタックオーバーフローなく完了すること。
  2. 生成された LIR / アセンブリにおいて、末尾再帰呼び出しが `call` ではなく `jmp`（またはローカルジャンプ）になっていることの形式検証。
  3. `cont-recurse-tail?` が `begin` ラップされた `%cont-call` を正しく `#t` と判定することのユニットテスト。

### Step 6: 品質検証 & ドキュメント更新
- `make -C ulisp lint_sexpr`（括弧バランス検査）
- `make -C ulisp test_pass_inject_safepoints`（セーフポイントパス検証）
- `make -C ulisp test_contify`（コンティフィケーション検証）
- `make test_concurrency_stress`（並行ストレステスト 10回連続 PASS）
- [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md) 更新

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/lir/129_lir_primitives.scm` の `lir-compile-zero-arg` に `%synapse-safepoint-poll!` ハンドラが追加され、LIR 生成が正常に行われること。
- [x] `ulisp/lir/125_lir_continuation.scm` の `cont-recurse-tail?` が `begin` 内の末尾 `%cont-call` を透過的に `#t` と判定すること。
- [x] `ulisp/lir/126_lir_control.scm` の In-place Tail Loop Argument Shuffle が `begin` 内の `%cont-call` に対して正常に適用されること。
- [x] セーフポイントが注入された状態でも、末尾再帰関数（`named-let`、`letrec`、末尾再帰 `define`）が固定スタックサイズ（スタック蓄積ゼロ）で動作すること。
- [x] 1,000,000 回反復テストがスタックオーバーフロー（CWE-400/CWE-674）なく完了すること。
- [x] `test_pass_inject_safepoints` および `test_contify` を含むすべてのテストが PASS すること。
- [x] `make test_concurrency_stress`（10回連続実行）が 0 failures で通過すること。
- [x] 相対パス規則が厳密に遵守されていること。
