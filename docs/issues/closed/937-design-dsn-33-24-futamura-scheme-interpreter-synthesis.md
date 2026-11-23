---
ID: 937
種別: Docs / Architecture
優先度: High
ステータス: Closed
---

# [DOCS/ARCH] DSN-33-24 三位一体・二村射影 Scheme インタプリタ自動生成・双対導出 ＆ メタ循環統合アーキテクチャ設計書の策定および既存 DSN-33 系設計書の同期更新 (ID: 937)

## 1. 概要 / Summary
ULisp（Scheme AOT メタコンパイラ）において、二村射影（Futamura Projections）の数理的・工学的基盤を活用し、以下の **3つのアプローチ（ケースA・ケースB・ケースC）すべてを統合した Scheme インタプリタ生成・合成アーキテクチャ** を規定する新規枝番号設計書 **`DSN-33-24`** を策定する。併せて、`DSN-33` 親仕様書、関連する全 `DSN-33-*` 枝番号設計書（`11`〜`13`, `21`〜`23`, `31`〜`32`, `41`）、および文書管理台帳 `MNG-01` を同期更新する。

### 規定する 3 大インタプリタ生成・導出パラダイム（Triad Synthesis Architecture）
1. **ケースA（Paradigm A: 逆方向・随伴導出 / Compiler-VM Composition & Residual Interpreter）**:
   - 既存のコンパイラ変換関手 $\mathrm{Comp}: L_{\text{Scheme}} \to L_{\text{Residual-ANF}} \to L_{\text{LIR}}$ と、低水準ターゲット仮想マシン $\mathrm{Interp}_{\text{LIR}}$（`ulisp/vm/lir_interpreter.scm` および `lir-eval`）または残余 ANF 評価器（`eval-residual-anf-expr`）を関数合成（$\mathrm{Interp}_{\text{Scheme}} = \mathrm{Interp}_{\text{LIR}} \circ \mathrm{Comp}$）することで、コンパイラパイプラインの语义論と 100% 一致する高信頼 Scheme インタプリタおよび R7RS `(scheme eval)` 第一級環境評価器を導出する。
2. **ケースB（Paradigm B: 動的・オンライン第1二村射影 / Endogenous Meta-Tracing JIT Scheme Interpreter）**:
   - 純粋 Scheme で記述された Scheme 評価器ループ（`eval` / `apply` / 環境探索）に `jit-merge-point!` および `jit-guard-type!`（`ulisp/jit/core/annotations.scm`）を自動計装（`auto_instrument.scm`）する。
   - 実行時のホットループ到達時に、限定継続（`shift`/`reset`）を用いた内因的メタトレーサが評価器の実行経路を捕捉し、トレース部分評価器（`ulisp/jit/optimizer/pe.scm`）が **オンライン第1二村射影（$\mathrm{mix}_{\text{trace}}(\mathrm{Interp}_{\text{Scheme}}, \mathrm{Loop}_{\text{Scheme}})$）** を遂行して、ディスパッチ消去・ガード特殊化・インメモリ x86-64 W^X 機械語実行を行う JIT 付き Scheme インタプリタバイナリを生成する。
3. **ケースC（Paradigm C: 静的・オフライン部分評価 & Direct Cogen による第1・第2・第3二村射影）**:
   - 4値束縛時間束（`{Static-Bot, Now, Later, Dynamic}`）に基づくオフライン BTA とステージ多相評価器 `eval-in-stage` / `stage-poly-lower`（`ulisp/compiler/eval_in_language.scm`）、および `ulisp/workbench/cogen.scm` の Direct Cogen エンジンを Scheme 自己評価器（Meta-Circular Scheme Interpreter）に適用する。
   - **メタ段階特殊化による高速インタプリタ生成**: 言語仕様・マクロ展開器・静的 FrameDescriptor 解決・標準ライブラリ環境を `Now`（Static）、ユーザー入力式・実行時引数を `Later`（Dynamic）として部分評価し、メタ解釈オーバーヘッドを完全蒸発させたスタンドアロン Scheme インタプリタを自動生成する。
   - **第1・第2二村射影の自己適用（Tower Collapse & Self-Cogen）**: 生成された Scheme インタプリタにソースプログラムを固定して第1二村射影（Tower Collapse）を行うパスと、`ulisp-cogen`（第2二村射影）により Scheme インタプリタ定義から直接スタンドアロン Scheme コンパイラ CLI を再導出する完全閉路（コンパイラ ⇄ インタプリタ双対性）を定式化する。

---

## 2. トレーサビリティと影響範囲 / Scope and Affected Files
- **新規作成**:
  - [x] [docs/designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md](../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md)
- **既存設計書・台帳の同期更新**:
  - [x] [docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [x] [docs/designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [x] [docs/designs/DSN-33-12-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md](../designs/DSN-33-12-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
  - [x] [docs/designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
  - [x] [docs/designs/DSN-33-21-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md](../designs/DSN-33-21-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
  - [x] [docs/designs/DSN-33-22-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md](../designs/DSN-33-22-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [x] [docs/designs/DSN-33-23-ulisp_endogenous_meta_tracing_jit_architecture.md](../designs/DSN-33-23-ulisp_endogenous_meta_tracing_jit_architecture.md)
  - [x] [docs/designs/DSN-33-31-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md](../designs/DSN-33-31-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)
  - [x] [docs/designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [x] [docs/designs/DSN-33-41-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md](../designs/DSN-33-41-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md)
  - [x] [docs/processes/MNG-01-document_ledger.md](../processes/MNG-01-document_ledger.md)
  - [x] [docs/issues/README.md](README.md)

---

## 3. セキュリティ脅威分析と設計要件 / Security & Threat Model
1. **CWE-94 / CWE-95 (Eval Injection / 越境コード注入)**:
   - ステージ多相評価器および動的 `eval` 環境において、未信頼のゲスト入力がホストコンパイラの特権束縛やシステムコールに直接アクセスできないよう、第一級不変環境ボックス（`<environment>`）と CSP 越境バリデータ（`stage-csp-error?`）によるサンドボックス分離を規定する。
2. **CWE-400 (Uncontrolled Resource Consumption / 部分評価・JIT トレース爆発)**:
   - ケースA（LIR VM 燃料 `*lir-vm-default-fuel*`）、ケースB（最大トレース長 `*jit-max-trace-length*`・最大ガード数 `*jit-max-guard-count*`）、ケースC（CTFE ステップ上限 `*ctfe-default-step-limit*`・Cogen 再帰上限 `*cogen-max-recursion-depth*`）の3層すべてに決定論的なリソース上限を設ける。
3. **CWE-119 / CWE-787 (JIT W^X 違反 / メモリ破壊)**:
   - ケースBのインメモリ JIT 実行において Write XOR Execute (`PROT_READ | PROT_WRITE` $\to$ `PROT_READ | PROT_EXEC`) を厳格に強制し、ガード失敗時は安全な Deoptimization トランポリンによってケースA/Cのインタプリタ状態へ無損失復帰する。

---

## 4. 実装方針 / Implementation Plan
Target Branch: `docs/937-design-dsn-33-24-futamura-scheme-interpreter-synthesis`

1. `docs/designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md` を新規作成し、以下を網羅的に記述する：
   - 第1章：エグゼクティブサマリー ＆ コンパイラとインタプリタの双対性・二村射影の方向性整理
   - 第2章：三位一体（Triad）Scheme インタプリタ生成アーキテクチャの全体像と数理定式化
   - 第3章：ケースA詳細設計（$\mathrm{Interp}_{\text{LIR}} \circ \mathrm{Comp}$ 合成導出、残余 ANF インタプリタ、R7RS 第一級環境 `eval.scm` 統合）
   - 第4章：ケースB詳細設計（内因的メタトレーシング JIT による動的・オンライン第1二村射影 Scheme インタプリタ）
   - 第5章：ケースC詳細設計（4値 BTA・Stage-Poly オフライン部分評価による特殊化インタプリタ生成 ＆ Direct Cogen 第1・第2二村射影の自己適用閉路）
   - 第6章：3方式横断の単一ソース意味論オラクル（Quadruple-Differential Oracle）と不変条件検証
   - 第7章：脅威モデル・セキュリティ境界（CWE-94, CWE-400, CWE-617, W^X）
   - 第8章：段階的実装ロードマップ（Phase I1〜I4）と品質ゲート
2. `DSN-33`（親仕様書）、`DSN-33-21`、`DSN-33-22`、`DSN-33-23` 等の関連仕様書ヘッダおよび責務マトリクスに `DSN-33-24` を追加し、相互参照を同期する。
3. `docs/processes/MNG-01-document_ledger.md` に `[DSN-33-24]` を登録する。
4. 品質ゲート（`make py_compile`、絶対パス混入 0 件検証、リンク整合性検証）を実行する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `docs/designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md` が作成され、ケースA・B・Cすべての数理モデル、モジュール設計、S式実装仕様、Mermaid アーキテクチャ図が含まれていること。
- [x] 既存の `DSN-33` および全枝番号仕様書（`DSN-33-11`〜`41`）、`MNG-01` 台帳に `DSN-33-24` が正しく登録・相互参照されていること。
- [x] `docs/`, `outputs/`, `.agents/` 配下の全 Markdown において絶対パス違反が 0 件であること。
- [x] `make py_compile && make static_analysis` がエラー 0 件で PASS すること。
