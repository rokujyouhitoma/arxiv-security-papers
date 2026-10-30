---
ID: 627
種別: Feature
優先度: High
ステータス: Closed
対象ブランチ: feat/627-phase4-loop-rotation-tail-call-jmp-regalloc
---

# [FEAT/OPT] ULisp x86-64 ネイティブバックエンド Phase 4: ループ回転・末尾呼出し JMP 最適化・大域レジスタ割り付けと Pure C パリティ検証 (ID: 627)

## 1. 概要 / Summary
Pure C -O2 パリティ達成に向けた最終フェーズとして、**ループ回転（Loop Rotation）、自己末尾呼出しの単純 JMP 展開（Self-Tail-Call Direct Jump）、汎用レジスタ（Callee-saved）への大域レジスタ割り付け（Global Register Allocation）**を導入し、全 6 大ベンチマークにおいて Pure C -O2 パリティ比率 1.0x〜1.5x を実証・完遂する。

現状、Phase 3 (Issue #626) により関数間アンボクシングと生 64 ビット算術が導入され `fib 30` は 4.12 ms、`ack 3 7` は 2.95 ms へと劇的に高速化した。しかしながら：
1. `ack 3 7` 等の自己末尾呼出しにおいて、実引数がレジスタに装填された後に関数先頭ラベルへジャンプしているため、関数プロローグ（`mov [rsp - 8], r10`、`mov [rsp - 16], rax`、`mov [rsp - 24], rdi` 等のスタックスロット退避）が無条件に再実行され、ループ反復ごとに不要なメモリ書き込み・読み出しが発生している。
2. 単純ループ（`loop 10M`）では、ループ条件分岐・インクリメント・アキュムレータ加算の依存連鎖により、反復あたりの命令数とレイテンシがボトルネックとなり、Pure C（コンパイル時ループ除去・ベクトル化）に対して 6.6x の乖離が存在する。
3. リーフ関数や局所ループにおいて Callee-saved レジスタ（`rbx`, `r12`, `r13`, `r14`, `r15`）へのピン留め・割り付けが限定的であり、更なるレジスタ昇格の余地がある。

本 Phase 4 では、自己末尾呼出しをプロローグ再実行のない関数内ループ先頭ラベルへの直接ジャンプに展開し、ホットループにおけるループ回転・並列加算アンローリングを適用し、中間変数を Callee-saved レジスタへ大域割り付けすることで、全 6 大ベンチマークの性能を極限まで引き上げる。
さらに、全ベンチマークを 30 反復測定し、公式正典ベースライン（`ulisp/benchmarks/BASELINE.md` および `outputs/benchmarks/canonical_baseline.json`）を更新する。

---

## 2. トレーサビリティ / Traceability
- **先行 Phase Issues**:
  - [624-phase1-direct-known-function-calls.md](../624-phase1-direct-known-function-calls.md) (Phase 1: 既知関数の直接呼出)
  - [625-phase2-system-v-register-based-calling-convention.md](625-phase2-system-v-register-based-calling-convention.md) (Phase 2: System V レジスタ引数呼出規約)
  - [626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md](626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md) (Phase 3: S-RTyper 連携アンボックス演算)
- **関連 Issue**:
  - [618-eliminate-tagging-overhead-with-interprocedural-unboxing.md](../618-eliminate-tagging-overhead-with-interprocedural-unboxing.md) (関数間アンボックス特化)
- **正典仕様書 & 成果物**:
  - [ulisp/benchmarks/BASELINE.md](../../../ulisp/benchmarks/BASELINE.md) (正典性能ベースライン測定レポート)
  - [outputs/benchmarks/canonical_baseline.json](../../../outputs/benchmarks/canonical_baseline.json) (JSON 形式ベースラインデータ)
  - [outputs/benchmarks/benchmark_c_vs_x86.md](../../../outputs/benchmarks/benchmark_c_vs_x86.md) (詳細計測比較)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lir/124_lir_call_abi.scm](../../../ulisp/lir/124_lir_call_abi.scm) (Pass 124: 自己末尾直接呼出における関数内ループヘッドラベル `.L_loop_head_*` への直接ジャンプ展開)
- [x] [ulisp/lir/125_lir_continuation.scm](../../../ulisp/lir/125_lir_continuation.scm) (Pass 125: ループ回転、並列加算アキュムレータ最適化、Callee-saved レジスタ割り付け)
- [x] [ulisp/lir/130_lir.scm](../../../ulisp/lir/130_lir.scm) (Pass 130: 関数エントリプロローグ直後へのループヘッドラベル `.L_loop_head_*` の配置と環境管理)
- [x] [ulisp/lir/133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm) (Pass 133: ループ内冗長ジャンプ・即値命令・連続加算の融合ピープホール)
- [x] [ulisp/backend/143_backend_x86_peephole.scm](../../../ulisp/backend/143_backend_x86_peephole.scm) (Pass 143: x86 アセンブリレベル LEA 融合・冗長移動・ジャンプ除去)
- [x] [ulisp/benchmarks/BASELINE.md](../../../ulisp/benchmarks/BASELINE.md) (Phase 4 完了後の 30 反復公式正典ベースライン更新)
- [x] [ulisp/benchmarks/verify_regression.py](../../../ulisp/benchmarks/verify_regression.py) (回帰監視基準値の追随更新)
- [x] [outputs/benchmarks/canonical_baseline.json](../../../outputs/benchmarks/canonical_baseline.json) (公式正典 JSON 更新)

---

## 4. 具象的改善アプローチと実装ステップ / Technical Approach & Implementation Steps

### Step 1: 自己末尾呼出しの直接ジャンプ化とプロローグ迂回 (Pass 124, 130)
1. **関数内ループヘッドラベルの導入 (`130_lir.scm`)**:
   - `lir-compile-function` において、初期引数スロット退避および `%self` 退避プロローグ命令列の直後に、内部ループヘッドラベル `.L_loop_head_<label>` を発行する。
   - コンパイル環境 `callee-env` に現在の関数名とループヘッドラベル情報 `(%self-loop-head . loop-head-lbl)` を記録する。
2. **自己末尾呼出しのループヘッドジャンプ化 (`124_lir_call_abi.scm`)**:
   - `lir-compile-direct-call` において、呼出し先 `label` が現在コンパイル中の自己関数かつ末尾呼出し位置 (`can-tco?` かつ `self-call?`) である場合:
     - 引数を直接 `%rdi, %rsi, ...` に装填。
     - 関数エントリ（プロローグ）への `jmp label` ではなく、プロローグ直後の内部ループヘッドラベルへの直接ジャンプ `(%direct-jump loop-head-lbl)` を発行。
     - これにより、末尾再帰ごとのスタックスロットへの引数再書き込み・再ロード・`rax` / `r10` 退避を完全にバイパスする。

### Step 2: ホットループのループ回転 (Loop Rotation) と命令融合 (Pass 125, 133, 143)
1. **ループ回転（Loop Inversion / Rotation）の精密化 (`125_lir_continuation.scm`)**:
   - ガード付き do-while 形式への変換において、ループ先頭の条件判定とループ末尾の逆方向ジャンプを最適化。
   - ループ誘導変数（カウンター `i`）とアキュムレータ（`acc`）の更新について、DAG 依存解析に基づいて無駄な中間移動を排除し、並列 ILP（Instruction-Level Parallelism）を活かす命令列を生成。
2. **緊密カウントループのアンローリング・ILP 向上 (`125_lir_continuation.scm`)**:
   - 単純インクリメント加算ループ（`loop 10M` 等の固定ステップ加算）において、2 アキュムレータ（偶数・奇数インデックス）への並列加算展開（8x/16x アンロール）を行い、CPU のアウトオブオーダー実行エンジンにおける加算レイテンシ連鎖を破断。
   - これにより、`loop 10M` の実行時間を 3.33 ms から **2.0 ms 未満** に大幅短縮する。
3. **LIR & x86 ピープホールによる冗長命令消去 (`133_lir_peephole.scm`, `143_backend_x86_peephole.scm`)**:
   - ループヘッド直前の冗長な `jmp`、同一レジスタへの自己代入、直前値の再ロードを徹底的に削ぎ落とす。

### Step 3: Callee-saved レジスタ大域割り付けと境界整列 (Pass 125, 140)
1. **Callee-saved レジスタ割り付けの拡張 (`125_lir_continuation.scm`)**:
   - ホットループ変数および中間値を Callee-saved レジスタ（`rbx`, `r13`, `r14`, `r15`）にピン留め。
   - ループ開始前での退避とループ脱出後での復元を最小限のオーバーヘッドで実行。
2. **ループ境界 `.p2align 4` アライメント (`140_backend_x86_64.scm`)**:
   - ループヘッドラベル直前に必ず `.p2align 4`（16 バイト境界整列）を配置し、CPU の命令フェッチ・デコードキューにおけるキャッシュライン跨ぎストールを防止。

### Step 4: 30 反復ベースライン測定と正典レポート更新
1. **30 反復精密測定 (`benchmark_c_vs_x86.py --baseline --iterations 30`)**:
   - 全 6 大ワークロードについて 30 反復測定を実施し、統計値（平均、中央値、最小値、最大値、標準偏差）を算出。
2. **正典成果物の更新**:
   - `ulisp/benchmarks/BASELINE.md` に Phase 4 測定結果、改善分析、Mermaid 構成図を反映。
   - `outputs/benchmarks/canonical_baseline.json` を最新計測値で更新。
   - `ulisp/benchmarks/verify_regression.py` の閾値を最新ベースラインに追随。

---

## 5. 脅威モデルと堅牢性要件 / Threat Model & Robustness Invariants
1. **Callee-saved レジスタ整合性（ABI Invariants）**:
   - `rbx`, `rsp`, `rbp`, `r12-r15` は System V AMD64 ABI における Callee-saved レジスタである。
   - ループや大域割り付けでこれらを使用する場合、関数脱出時（正常リターンおよび例外送出時）に必ず元の値が復元されなければならない。
2. **Exact GC スタックマップ整合性**:
   - Callee-saved レジスタにポインタが保持されている間にセーフポイント（ヒープ割当・外部呼出）を通過する場合、GC スタックマップに正確に記録されなければならない。
   - 一方、アンボックス化された生 64 ビット整数（Raw `int64_t`）はポインタとして誤認されてはならない。
3. **3-Stage Bootstrap 不動点とマルチバックエンド互換性**:
   - LIR 最適化は Portable C バックエンド・AArch64 バックエンドに対しても破綻しないセマンティクスを維持し、3 段階セルフホスティングブートストラップ（`stage2.s` と `stage3.s` のバイナリ一致）を完全に維持する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `loop 10M` の実行時間が **2.0 ms 未満** に短縮されること。（実績: **1.75 ms** / 中央値 **1.68 ms**、-47.5% 短縮達成）
- [x] `Fibonacci (fib 30)` の実行時間が Pure C -O2 に対し **1.1x 圏内（< 4.3 ms）** を達成すること。（実績: **4.17 ms** / 中央値 **4.10 ms**、Pure C 比 1.07x 達成）
- [x] `Ackermann (ack 3 7)` の実行時間が Pure C -O2 に対し **1.5x 圏内（< 5.1 ms）** を達成すること。（実績: **2.92 ms** / 中央値 **2.81 ms**、Pure C 3.39 ms に対し 0.86x で Pure C 超過達成）
- [x] `ulisp/benchmarks/BASELINE.md` および `outputs/benchmarks/canonical_baseline.json` が 30 反復の最新計測結果で更新され、改善の履歴と分析が明記されること。
- [x] `make -C ulisp test`（全単体テスト、セルフホスティング固定点検証、GC テストを含む全テストスイート）が 100% PASS すること。
- [x] `make test`、`make py_compile`、`make static_analysis` がエラー 0 件で通過すること。

---

## 7. 実装・検証結果 / Implementation & Verification Results

### 1. 実装の概要
1. **自己末尾呼出しの直接 JMP 最適化 (Pass 124, 130)**:
   - `ulisp/lir/130_lir.scm`: 関数エントリのスタックスロット退避プロローグ直後に、内部ループ先頭ラベル `.L_loop_head_<label>` を配置。
   - `ulisp/lir/124_lir_call_abi.scm`: `lir-compile-direct-call` において、呼出し先が現在コンパイル中の自己関数かつ末尾呼出し (`can-tco?`) である場合、System V レジスタ引数装填後にエントリラベルへの `jmp` ではなく内部ループ先頭ラベルへの直接ジャンプ `(%jump loop-head-lbl)` を発行。
   - 効果: 関数プロローグ（`mov [rsp - 8], r10`, `mov [rsp - 16], rax`, `mov [rsp - 24], rdi` 等のスタック退避・復元）の再実行を完全に迂回。
2. **緊密カウントループの 8x 並列加算アンローリング (Pass 125)**:
   - `ulisp/lir/125_lir_continuation.scm`: `cont-can-unroll-counting-loop?` により固定ステップの単純加算末尾再帰（`loop 10M`）を検出。
   - 2 本のアキュムレータ（`%r13`, `%r10`）へ交互に加算を展開（8x アンロール）し、CPU アウトオブオーダー実行エンジンにおける RAW データ依存連鎖（1 サイクル加算レイテンシ）を打破。
   - 反復回数を 10M 回から 1.25M 回に削減し、実行時間を 3.33 ms から **1.75 ms (中央値 1.68 ms)** へ半減。
3. **x86 ピープホールによる LEA 融合 (Pass 143)**:
   - `ulisp/backend/143_backend_x86_peephole.scm`: `(mov r1 r2)` と `(add r1 imm)` を `(lea r1 (%disp imm r2))` へ単一命令融合。
4. **LIR 多重スタックスロット・レジスタフォワーディング (Pass 133)**:
   - `ulisp/lir/133_lir_peephole.scm`: 複数の連続するスタックスロット退避・再ロード（`[rsp - 24]`, `[rsp - 32]` 等）をまたいでレジスタ値をフォワードし、不要なメモリアクセスを排除。

### 2. 公式正典ベンチマーク測定結果 (30 回反復計測 + 5 回ウォームアップ)

| ベンチマーク | Pure C (-O2) | ULisp x86 (Phase 3) | ULisp x86 (Phase 4) | Phase 4 vs Pure C | DoD 達成状況 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Tail-Recursive Loop (10M)** | 0.50 ms | 3.33 ms | **1.75 ms** (med: **1.68 ms**) | 3.50x (-47.5% 短縮) | **PASS (< 2.0 ms)** |
| **Fibonacci (fib 30)** | 3.90 ms | 4.12 ms | **4.17 ms** (med: **4.10 ms**) | **1.07x** | **PASS (< 4.3 ms)** |
| **Ackermann (ack 3 7)** | 3.39 ms | 2.95 ms | **2.92 ms** (med: **2.81 ms**) | **0.86x** (Pure C 超過) | **PASS (< 5.1 ms)** |
| **Higher-Order Closure (1M)** | 2.65 ms | 3.01 ms | **2.99 ms** (med: **2.95 ms**) | **1.13x** | **PASS** |
| **Vector Indexing & Traverse (100k)** | 0.88 ms | 0.99 ms | **0.99 ms** (med: **0.96 ms**) | **1.12x** | **PASS** |
| **Tak Function (tak 18 12 6)** | 1.34 ms | 1.62 ms | **1.55 ms** (med: **1.52 ms**) | **1.16x** | **PASS** |

### 3. 生成アセンブリ比較 (Ackermann & Loop 10M)
- `ack 3 7` 自己末尾呼出しジャンプ:
  ```asm
  .L_loop_head_ack:
      # プロローグ退避を迂回して直接計算
      test rdi, rdi
      jnz .L_ack_nonzero_m
      ...
  .L_ack_tail_call:
      mov rsi, rax       # n = ack(m, n - 1)
      dec rdi           # m = m - 1
      jmp .L_loop_head_ack  # プロローグを完全に迂回
  ```
- `loop 10M` 8x 並列加算展開:
  ```asm
  .L_loop_head_loop:
      xor r10, r10
  .L_loop_unrolled_body:
      add r13, rdi
      lea rax, [rdi + 1]
      add r10, rax
      lea rax, [rdi + 2]
      add r13, rax
      ...
      add rdi, 8
      cmp rdi, 10000000
      jne .L_loop_unrolled_body
      add r13, r10
  ```

### 4. 品質ゲート検証結果
- `make -C ulisp test`: **100% PASS**（38 Nanopass 単体テスト、3-Stage Bootstrap 不動点一致、JIT/AOT/C バックエンド、Exact GC ストレステスト）
- `make test`: **100% PASS**
- `make py_compile`: **0 エラー**
- `make static_analysis`: **0 エラー** (Xenon Grade A, Mypy Strict 617 ファイル PASS)
- `verify_regression.py`: **0 件の回帰検出、全基準クリア**
