---
ID: 625
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/OPT] ULisp x86-64 ネイティブバックエンド Phase 2: System V AMD64 レジスタ引数受渡し呼出規約（Register-Based Calling Convention）の導入 (ID: 625)

## 1. 概要 / Summary
Pure C -O2 パリティ達成に向けた第 2 フェーズとして、**スタック経由の引数受渡し（Stack-Spilling Calling Convention）を撤廃し、System V AMD64 ABI に準拠したレジスタ引数受渡し**を導入する。

現状の ULisp コンパイラ（`ulisp/lir/124_lir_call_abi.scm`, `ulisp/lir/130_lir.scm`, `ulisp/backend/140_backend_x86_64.scm`）では、すべての関数引数がスタックフレーム（`[rsp - 40]` 等）を経由して渡されており、1 回の関数呼出し毎に最低 4〜6 回のメモリストア・ロード（`sub rsp, 40` / `mov [rsp - 40], rax` / `add rsp, 40`）が多発している。
これにより、L1D キャッシュの帯域を著しく浪費し、メモリトラフィックによる IPC（1サイクルあたり実行命令数）の低下を招いている。

本 Phase 2 では、第 1 引数〜第 6 引数を汎用レジスタ（`rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`）で直接受渡しする呼出規約を確立し、スタックアクセスオーバーヘッドを撲滅する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 1 章 レジスタアーキテクチャ、第 6 章 LIR / 最適化パス)
  - [ulisp/benchmarks/BASELINE.md](../../../ulisp/benchmarks/BASELINE.md) (正典性能ベースライン測定レポート)
- **親ロードマップ & 先行 Phase**:
  - [624-phase1-direct-known-function-calls.md](624-phase1-direct-known-function-calls.md) (Phase 1: 既知関数の直接呼出)
- **後続 Phase Issues**:
  - [626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md](../626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md) (Phase 3: S-RTyper 連携アンボックス演算)
  - [627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md](../627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md) (Phase 4: ループ回転・末尾JMP・レジスタ割付とCパリティ検証)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lir/124_lir_call_abi.scm](../../../ulisp/lir/124_lir_call_abi.scm) (Pass 124: レジスタ呼出規約と呼出元スタック操作の軽量化)
- [x] [ulisp/lir/130_lir.scm](../../../ulisp/lir/130_lir.scm) (Pass 130: 仮引数バインディングと被呼出関数エントリプロローグの刷新)
- [x] [ulisp/lir/127_lir_runtime.scm](../../../ulisp/lir/127_lir_runtime.scm) (Pass 127: `call/cc` 継続引数の `%rdi` レジスタ受渡しと Safepoint 保護)
- [x] [ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm) (Pass 140: `rdi, rsi, rdx, rcx, r8, r9` 引数渡しアセンブリ出力・`%r11` クロージャ呼出)
- [x] [ulisp/backend/142_backend_x86_freestanding.scm](../../../ulisp/backend/142_backend_x86_freestanding.scm) (Pass 142: `ulisp_continuation_invoke` における `%rdi` 経由の継続戻り値復元と Red-Zone 保護)
- [x] [ulisp/backend/150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm) (Pass 150: AArch64 バックエンドにおける引数レジスタマッピング整合)
- [x] [ulisp/backend/160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm) (Pass 160: C バックエンドにおける引数レジスタ変数 `rdi..r9` 整合)
- [x] [ulisp/tests/passes/test_124_lir_call_abi.scm](../../../ulisp/tests/passes/test_124_lir_call_abi.scm) (Pass 124: レジスタ引数呼出単体テスト)
- [x] [ulisp/tests/passes/test_130_lir.scm](../../../ulisp/tests/passes/test_130_lir.scm) (Pass 130: LIR 生成単体テスト)
- [x] [ulisp/tests/passes/test_140_backend_x86_64.scm](../../../ulisp/tests/passes/test_140_backend_x86_64.scm) (Pass 140: x86-64 バックエンド単体テスト)
- [x] [ulisp/benchmarks/BASELINE.md](../../../ulisp/benchmarks/BASELINE.md) (Phase 2 適用後の実行時間記録)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳の進捗同期)

---

## 4. 脅威モデルと堅牢性要件 / Threat Model & Robustness Requirements
1. **System V AMD64 ABI 規約整合性と呼出側・被呼出側レジスタ保存規則 (Callee-saved vs Caller-saved Registers)**:
   - System V ABI において、引数レジスタ `rdi, rsi, rdx, rcx, r8, r9` およびスクラッチレジスタ `rax, r10, r11` はすべて Caller-saved（呼出側退避）である。
   - 被呼出関数（Callee）側でローカル変数を保持する際、あるいは子関数を呼出す際に、引数レジスタの値をそのままレジスタに保持し続けると後続の関数呼出しにより値が破壊される（レジスタ破壊脆弱性・未定義動作・クラッシュ）。
   - したがって、Callee は関数エントリ時点で引数レジスタを自フレームのスタックスロット（`[rsp - 24 - 8*i]`）に退避する。
2. **スタックアラインメント (16-byte Stack Alignment 不変条件)**:
   - System V AMD64 ABI では、`call` 命令実行直前の時点で `rsp % 16 == 0`（リターンアドレス push 後は `rsp % 16 == 8`）でなければならない。
   - 引数受渡しをスタックからレジスタ（1〜6引数）に変更した場合、スタック経由で渡す引数（7引数以降）の個数によって `frame-shift` の計算式が変化する。
3. **正確な GC スタックマップ Safepoint の整合性**:
   - 引数をレジスタ渡しする場合、関数呼出し中やアロケーション中に GC がトリガーされた際、レジスタ上に残されたヒープポインタを GC コレクタが見落とすと、ポインタ更新漏れによる Use-After-Free / メモリ破壊が発生する。
   - コールサイトにおける Safepoint スタックマップのビットマップ計算において、スタックスロットおよび引数レジスタ上の有効な Scheme オブジェクトを正確に追跡する。
4. **Tail Call Optimization (TCO) と循環レジスタコピー (Cycle-Safe Parallel Copy)**:
   - 末尾呼出し（`%direct-jump` / `%jump`）において、一時スタックスロット（`aligned-si - 8*i`）を介して全引数を評価した後に `%rdi..%r9` へ一括ロードすることで、循環依存によるレジスタ上書き破壊を完全に防止する。

---

## 5. 具象的改善アプローチ / Technical Approach

Target Branch: `feat/625-system-v-register-calling-convention`

### Step 1: Pass 124 (`lir/124_lir_call_abi.scm`) におけるレジスタ引数割当と呼出側スタック操作の刷新
1. **呼出サイトにおける引数の評価と配置**:
   - 引数リスト `args` の各式を左から右へ順に評価し、まずローカルの一時スタックスロット（`aligned-si`, `aligned-si - 8`, ...）に格納する。これにより引数評価式中の入れ子関数呼び出しによる引数レジスタ破壊を完全に防止する。
   - 評価完了後、被呼出関数の呼出し直前に：
     - 第 1 〜 第 6 引数（`i = 0..5`）: 対応する System V 引数レジスタ（`%rdi`, `%rsi`, `%rdx`, `%rcx`, `%r8`, `%r9`）へ `%load` 命令を発行してレジスタへ移送する。
     - 第 7 引数以降（`i >= 6`）: スタックフレーム引数領域に格納する。
2. **スタックフレームシフトの最適化**:
   - 引数 6 個以下の関数呼び出しでは、スタック引数退避のための余剰スロット確保を廃止し、16 バイトアラインメントに必要な最小限のシフトのみに抑制する。
3. **末尾呼出し (TCO) のレジスタ転送**:
   - `can-tco?` の場合、一時スロットから対象引数レジスタへのロードを行い、直接 `jmp`（`%direct-jump` または `%jump`）を発行する。

### Step 2: Pass 130 (`lir/130_lir.scm`) における被呼出関数（Callee）引数環境とプロローグの刷新
1. **仮引数環境のバインディング**:
   - `lir-compile-function` において、各仮引数 `params`（インデックス `i`）について：
     - `i < 6`: 引数はレジスタ（`%rdi, %rsi, %rdx, %rcx, %r8, %r9`）で渡される。Callee プロローグで自フレームの安全なスタックスロット（`[rsp - 24]`, `[rsp - 32]`, ...）へ退避する `%store` 命令を発行し、局所環境 `param-env` には当該スタックオフセットをバインドする。
     - `i >= 6`: Caller 側からスタック経由で渡された引数オフセット（`[rsp + offset]`）をバインドする。

### Step 3: Pass 140/142/150/160 バックエンドコード生成の適合
1. **命令選択 (Instruction Selection)**:
   - `%load`, `%store`, `%mov` において汎用レジスタ（`rdi, rsi, rdx, rcx, r8, r9`）の相互転送を出力。
   - `%call-closure` / `%jump`: `%rdx`（第 3 引数レジスタ）の破壊を防ぐため、クロージャコードポインタのロード先にスクラッチレジスタ `%r11` を使用。
   - `%capture-cc` / `ulisp_continuation_invoke`: `call/cc` において第 1 引数 `%rdi` で渡される継続戻り値を `%rax` に復元し、かつスタックフレーム下のローカル領域 `[rsp - 256 .. rsp]` を含めて退避・復元する。

### Step 4: 単体テスト・統合テスト・Nanopass 検証
1. **Pass 124 / 130 / 140 単体テストの拡充**:
   - `tests/passes/test_124_lir_call_abi.scm`: レジスタ引数ロード（`%load %rdi ...`）が出力されることを検証。
   - `tests/passes/test_130_lir.scm`: Callee プロローグにおける引数受取りと環境解決を検証。
   - `tests/passes/test_140_backend_x86_64.scm`: x86-64 命令出力の検証。
2. **全 Nanopass およびセルフホスティング検証**:
   - `make -C ulisp build/ulisp-modular` のクリーンビルド。
   - `make -C ulisp test` の全 38 Nanopass 単体テスト、R7RS ライブラリテスト、3-Stage Bootstrap 固定点の一致（100% PASS）。

### Step 5: ベンチマーク測定と BASELINE.md 更新
1. `python3 ulisp/benchmarks/benchmark_c_vs_x86.py` を実行し、Phase 1 完了時点（`fib 30`: 7.39 ms, `ack 3 7`: 4.03 ms）からの性能向上を実測。
2. `ulisp/benchmarks/BASELINE.md` および `outputs/benchmarks/benchmark_c_vs_x86.md` を更新。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 6 引数以内の関数呼出しにおいて、引数が System V AMD64 レジスタ（`rdi, rsi, rdx, rcx, r8, r9`）経由で受け渡されること。
- [x] 7 引数以上の関数呼出しにおいて、7 番目以降の引数がスタックスロット経由で正しく受け渡されること。
- [x] `fib 30` の実行時間が Phase 1 完了時点（7.39 ms）からさらに短縮されること（実測値: **5.59 ± 0.26 ms (min: 5.29 ms)**、ULisp C -O2 の 10.47 ms に対し **0.53x（約 1.9 倍高速）**を達成）。
- [x] `ack 3 7` の実行時間が < 7.0 ms を維持・短縮すること（実測値: **4.17 ± 0.64 ms (min: 3.73 ms)**）。
- [x] `make -C ulisp build/ulisp-modular` がエラーなく成功すること。
- [x] `make -C ulisp test` の全テストスイート（38 Nanopass、統合テスト、3-Stage Bootstrap 固定点）が 100% PASS すること。
- [x] Issue 625 がクローズされ、Issue 台帳およびリポジトリ品質ゲートがすべてグリーンであること。

---

## 7. 成果サマリ / Results Summary
- **System V AMD64 レジスタ呼出規約の確立**:
  - Pass 124 (`ulisp/lir/124_lir_call_abi.scm`) および Pass 130 (`ulisp/lir/130_lir.scm`) にて第 1〜第 6 引数を `%rdi, %rsi, %rdx, %rcx, %r8, %r9` レジスタ経由で受け渡し、第 7 引数以降をスタックスロット経由で受け渡すハイブリッド ABI を実装。
  - クロージャ間接呼出し時のコードポインタロード先を `%rdx` から `%r11` に変更し、第 3 引数レジスタ `%rdx` の競合破壊を完全に排除。
  - `call/cc`（Pass 127 / Pass 142）における継続引数 `%rdi` 受渡しおよび `[rsp - 256 .. ulisp_stack_base]` の完全スタック保存・復元を実装。
- **性能向上（Initial Baseline ➔ Phase 1 ➔ Phase 2）**:
  - `Fibonacci (fib 30)`: 17.12 ms ➔ 7.39 ms ➔ **5.59 ± 0.26 ms (min: 5.29 ms)**（Initial 比 **3.06x 高速化**、ULisp C -O2 比 **0.53x**）
  - `Ackermann (ack 3 7)`: 5.89 ms ➔ 4.03 ms ➔ **4.17 ± 0.64 ms (min: 3.73 ms)**
  - `Higher-Order Closure (1M)`: 5.22 ms ➔ 4.88 ms ➔ **4.33 ± 0.67 ms (min: 3.63 ms)**
  - `List Alloc & Traverse (100k)`: 2.74 ms ➔ 2.12 ms ➔ **1.75 ± 0.21 ms (min: 1.50 ms)**
  - `Vector Indexing & Traverse (100k)`: 1.95 ms ➔ 1.52 ms ➔ **1.17 ± 0.06 ms (min: 1.10 ms)**
- **テスト・品質保証の厳格化**:
  - コンパイラ・Verifier・全テストスイートにおいて `[FAIL]` または未捕捉コンパイルエラー発生時に即座に非ゼロ終了コード `(exit 1)` で停止する機構を徹底。
  - `make -C ulisp build/ulisp-modular` および `make -C ulisp test`（Phase 1〜7、全 38 Nanopass 単体テスト、R7RS テスト、3-Stage セルフホスティング固定点、分割インクリメンタルビルド）が 0 エラーで 100% PASS。

