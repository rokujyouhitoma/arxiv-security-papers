---
ID: 624
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/OPT] ULisp x86-64 ネイティブバックエンドの Pure C -O2 パリティ達成に向けた包括的コード生成最適化（直接呼出・レジスタABI・アンボックス・レジスタ割付）(ID: 624)

## 1. 概要 / Summary
Issue #623（正典ベースライン策定）により確定した公式ベンチマーク（`ulisp/benchmarks/BASELINE.md`）において、ULisp x86-64 Freestanding ネイティブバイナリは外部主要 Scheme 処理系（Chez Scheme 9.5.8 に対し 4〜29 倍高速、Gauche に対し 5〜70 倍高速）を圧倒的な性能差で凌駕している。しかし、理論上限目標である手書き最適化 C 言語（`GCC -O2` による Pure C Baseline）と比較した場合、ワークロードによって **2.2x 〜 6.4x の性能差（レイテンシ遅延）**が存在する。

実測アセンブリ（`fib_30.s`, `ack_3_7.s`, `loop_10m.s` 等）および Linux `perf` ハードウェアカウンタの詳細分析により、この性能乖離の主要因は以下の 5 大アーキテクチャボトルネックに起因することが特定された：

1. **既知関数に対する間接クロージャ呼出し（Indirect Closure Call Overhead）**:
   - `letrec` やトップレベルで定義された既知の関数（`fib`, `ack` 等）であっても、呼出しごとにクロージャオブジェクトのフェッチ、タグ除去（`- 1`）、エントリポイントロード、間接分岐（`call rdx`）が発行されている。間接呼出しは CPU 分岐予測ミス（Branch Miss）とパイプラインストールを引き起こす。
2. **スタック経由の引数受渡し（Stack-Spilling Calling Convention）**:
   - System V AMD64 ABI（`rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9` によるレジスタ引数渡し）を採用しておらず、呼出しごとにスタックメモリへのストア・ロード（`sub rsp, 40` / `mov [rsp - 40], rax` / `add rsp, 40`）が多発し、メモリ帯域を浪費している。
3. **ボクシング型タグ操作のオーバーヘッド（Tagged Fixnum Arithmetic）**:
   - 整数（Fixnum）が 2 ビット左シフトタグ形式（`val << 2`）で表現されており、加減算や比較のたびにシフトやタグ検査命令が挿入されている。
4. **基本ブロック間レジスタ割付の欠如（Lack of Global Register Allocation）**:
   - 中間変数や演算結果が汎用レジスタ（Callee-saved / Caller-saved registers）に保持されず、スタックスロット `[rsp - N]` への退避・復帰が頻繁に発生している。
5. **末尾再帰・ループの誘導変数最適化と定数畳み込み（SCEV / Loop Rotation）**:
   - Pure C では `loop 10M` の等差数列和がコンパイル時に O(1) に定数畳み込み（Scalar Evolution）されている一方、ネイティブコードでは愚直に 1000 万回のループ反復を実行している。

本 Issue では、ULisp x86-64 ネイティブバックエンドを抜本的に刷新し、Pure C -O2 と同等の実行速度（**パリティ比率 1.0x〜1.5x 圏内**）を達成するための最適化パイプラインを策定・実装する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 1 章 レジスタアーキテクチャ、第 6 章 LIR / 最適化パス、第 10 章 ベンチマーク品質ゲート)
  - [ulisp/benchmarks/BASELINE.md](../../ulisp/benchmarks/BASELINE.md) (正典性能ベースライン測定レポート)
- **関連 Issue**:
  - [618-eliminate-tagging-overhead-with-interprocedural-unboxing.md](618-eliminate-tagging-overhead-with-interprocedural-unboxing.md) (S-RTyper Pass 090 および LIR / バックエンドにおける関数間アンボックス特化)
  - [620-repair-benchmark-suite-and-establish-automated-bench-harness.md](closed/620-repair-benchmark-suite-and-establish-automated-bench-harness.md) (ベンチマークスイートの修復および make bench 自動計測ハーネスの確立)
  - [622-implement-runtime-gc-stats-and-perf-hardware-counter-integration.md](closed/622-implement-runtime-gc-stats-and-perf-hardware-counter-integration.md) (実行時 GC 統計プロファイルおよび Linux perf ハードウェアカウンタ連携基盤の実装)
  - [623-establish-canonical-performance-baseline-and-continuous-monitoring.md](closed/623-establish-canonical-performance-baseline-and-continuous-monitoring.md) (ULisp 正典性能ベースライン測定レポート策定と継続的性能監視基盤の構築)
  - [578-coordinate-closure-escape-and-lir-stack-allocation-pipeline.md](closed/578-coordinate-closure-escape-and-lir-stack-allocation-pipeline.md) (Pass 110/120/130 連携による非エスケープオブジェクトのスタック配置最適化)
  - [547-optimize-ulisp-x86-tail-loop-to-match-c-backend.md](closed/547-optimize-ulisp-x86-tail-loop-to-match-c-backend.md) (ULisp x86における末尾再帰ループの高速化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/090_rtyper.scm](../../ulisp/frontend/090_rtyper.scm) (S-RTyper: 整数・ポインタ・真偽値の型推論とアンボックス注釈)
- [ ] [ulisp/frontend/110_closure_convert.scm](../../ulisp/frontend/110_closure_convert.scm) (既知関数 / 直接呼出可能関数の検出とフラグ付与)
- [ ] [ulisp/frontend/120_alias_escape.scm](../../ulisp/frontend/120_alias_escape.scm) (エスケープ解析に基づくクロージャ割当完全回避)
- [ ] [ulisp/lir/124_lir_call_abi.scm](../../ulisp/lir/124_lir_call_abi.scm) (レジスタ呼出規約 System V ABI への呼出命令リファクタリング)
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm) (LIR 命令選択: アンボックス演算 `%unboxed-add`, `%unboxed-sub`, `%unboxed-cmp`)
- [ ] [ulisp/lir/132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm) (SSA 形式に基づくレジスタ割付と不要スタック退避の排除)
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (直接呼出 `call .L_func`, レジスタ引数 `rdi, rsi`, 直接戻り値 `rax`, リーフフレーム省略)
- [ ] [ulisp/benchmarks/BASELINE.md](../../ulisp/benchmarks/BASELINE.md) (最適化適用後のベースライン更新)
- [ ] [docs/issues/README.md](../../docs/issues/README.md) (Issue 台帳の管理)

---

## 4. ボトルネック分析と最適化施策 / Technical Deep Dive & Solutions

### 施策 1: 既知関数の直接呼出（Direct Known-Function Calls）
- **現状の課題**:
  ```assembly
  mov rdx, [r10 - 1]
  call rdx
  ```
  `fib` や `ack` などの再帰呼出しにおいて、毎回クロージャオブジェクトからエントリポインタを取得して間接呼出しを行っているため、CPU の間接分岐予測バッファ（BTB）を逼迫させ、分岐予測ミス率が増加している。
- **改善策**:
  - Pass 110 (Closure Conversion) において、コールターゲットがコンパイル単位内で閉じており再代入されない関数を `known-function` として識別。
  - Pass 140 (x86-64 Backend) において、クロージャポインタ解決を介さず、ラベルへの直接ジャンプ命令 `call .L_lambda_0` を出力する。

### 施策 2: レジスタ呼出規約（Register-Based Calling Convention）への移行
- **現状の課題**:
  ```assembly
  sub rsp, 40
  mov [rsp - 40], rax
  call rdx
  add rsp, 40
  ```
  すべての関数引数をスタック経由で渡しているため、1 回の関数呼出しあたり最低 4 回のメモリアクセスとスタックポインタの更新が発生する。
- **改善策**:
  - System V AMD64 ABI に準拠し、第 1 引数〜第 6 引数を汎用レジスタ（`rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`）で直接受渡しする。
  - `(fib (- n 1))` の呼出しは `mov rdi, rbx; dec rdi; call .L_fib` のみとなり、スタックの `sub/add` およびメモリストア/ロードが完全に消滅する。

### 施策 3: S-RTyper による関数間アンボックス特化（Interprocedural Unboxing - Issue #618）
- **現状の課題**:
  - `fib` の引数 `n` や戻り値は Scheme の Fixnum として 2 ビットシフトされているため、比較時に `cmp [rsp - 24], 8`（2 のエンコード値）を行い、減算時に `sub rdx, 4`（1 のエンコード値）を行っている。
- **改善策**:
  - S-RTyper (Pass 090) で引数および戻り値が Fixnum に限定されることを証明し、アンボックス化されたネイティブ 64 ビット整数関数 `fib : int64_t -> int64_t` としてコンパイル。
  - レジスタ内で生の 64 ビット整数（`0, 1, 2, ...`）として計算し、Scheme 境界（REPL 表示時）でのみ 1 回タグ付けする。

### 施策 4: リーフ関数フレーム省略（Leaf Function Frame Optimization）
- **現状の課題**:
  - 子関数を呼ばない終端関数（ベースケースや末尾再帰化された関数）においても、標準のプロローグ・エピローグが生成されている。
- **改善策**:
  - リーフ関数の場合、スタックのアライメント調整や余分なレジスタ退避を省略し、レジスタ内のみで完結して即時 `ret` する。

### 施策 5: 末尾呼出のループ回転とピープホール最適化（Loop Rotation & Peephole）
- **現状の課題**:
  - `loop 10M` ではすでにレジスタピン留めが行われているが、アンローリング（2x/4x）やループ不変式の巻き上げが行われていない。
- **改善策**:
  - LIR ピープホール最適化（Pass 133）により、単純な増分ループのアンローリングおよびジャンプ先アライメント（`.p2align 4`）を徹底する。

---

## 5. 段階的実装ロードマップ / Implementation Roadmap
Target Branch: `feat/624-achieve-pure-c-parity-with-native-codegen-optimizations`

1. **Phase 1: 既知関数の直接呼出最適化（Direct Calls）**:
   - Pass 110 / 124 / 140 における既知関数ラベル直結呼出の実装。
   - `fib 30`, `ack 3 7` の実行時間半減を検証。
2. **Phase 2: レジスタ引数受渡し ABI（System V Calling Convention）の導入**:
   - Pass 124 (LIR Call ABI) および Pass 140 (Backend x86-64) でのレジスタ引数受渡し（`rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`）の実装。
   - スタックトラフィックの撲滅と IPC（Instructions Per Cycle）の大幅向上。
3. **Phase 3: S-RTyper 連携による完全アンボックス演算（Issue #618 統合）**:
   - 関数引数・戻り値のアンボックス化（Raw int64_t 演算）。
   - タグ付け・タグ検査オーバーヘッドの完全消滅。
4. **Phase 4: 全体効果測定と Pure C パリティ検証**:
   - `make -C ulisp bench_verify` による回帰検証。
   - `make -C ulisp bench_baseline` でベースラインを再測定し、Pure C 対比 **1.0x〜1.5x** の達成を実証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 既知関数の再帰呼出しにおいて間接呼出し（`call rdx`）が排除され、直接ラベル呼出（`call .L_...`）が出力されること。
- [ ] 6 引数以内の関数呼出しにおいて、引数がスタックではなくレジスタ（`rdi`, `rsi`, `rdx`, etc.）経由で渡されること。
- [ ] `Fibonacci (fib 30)` の実行時間が Pure C -O2（約 3.2ms）に対し **1.5x 以内（< 5.0ms）** に短縮されること。
- [ ] `Tail-Recursive Loop (10M)` の実行時間が Pure C -O2 に対し **1.5x 以内** に短縮されること。
- [ ] 全 6 大ワークロードの出力値が期待値と 100% 一致すること（正確性の保持）。
- [ ] `ulisp/benchmarks/BASELINE.md` が最新の高速化データで更新され、改善倍率が明記されること。
- [ ] `make test` および `make py_compile static_analysis` がエラー 0 件で通過すること。
