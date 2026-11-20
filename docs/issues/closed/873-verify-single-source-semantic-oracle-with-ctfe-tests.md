---
ID: 873
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT] 単一ソース意味論オラクルによる CTFE 既存テスト回帰検証 (ID: 873)

## 1. 概要 / Summary
DSN-33-03 §3.6 に基づき、`Now` 辞書を用いたステージ多相評価器（`eval-in-stage`）を「完全決定論的で仕様乖離のない正解（Ground Truth）オラクル」として確立した。
既存の全 CTFE（Compile-Time Function Execution）単体テストスイートを `Now` 辞書経由で実行・検証し、ホスト Scheme、既存 CTFE エンジン、および `Now` 辞書の間で意味論の乖離（Semantic Drift）が原理的にゼロ（0件）であることを網羅的に証明。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書:
  - [DSN-33-03 §3.6 (Single-Source Semantic Oracle)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#36-単一ソース意味論オラクルsingle-source-semantic-oracleと多層差分検証)
  - [DSN-33-02 §7.1 (LIR Reference VM)](docs/designs/DSN-33-02-ulisp_self_healing_compiler_pipeline_and_diagnostic_s_expressions.md)
- 関連 Issue:
  - #825 (eval-in-language / CTFE)
  - #870 (stage-dict および Now / Later 辞書)
  - #871 (PSDS `<stage-val>`)
  - #872 (eval-in-stage コアループと Fuel/Depth ガード)
  - #881 (3重差分テストオラクルとメタモルフィック摂動検証)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm) - `Now` 辞書オラクルブリッジ（`eval-with-now-oracle`）の提供
- [x] [ulisp/tests/test_single_source_oracle.scm](ulisp/tests/test_single_source_oracle.scm) - 単一ソース意味論オラクル回帰テストスイートの新規作成
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_single_source_oracle` ターゲットの追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/873-verify-single-source-semantic-oracle-with-ctfe-tests`

### 4.1 オラクルハーネス設計
`(eval-with-now-oracle expr [env] [fuel] [depth])`
1. デフォルト引数補正を行い、`Now` 辞書を用いて `(eval-in-stage (make-now-dict) env expr fuel depth)` を呼び出す。
2. 正常終了時は `<stage-val>` から Scheme プリミティブ値（payload）を取り出して返却。
3. エラー時（`stage-csp-error?`）は `#f` またはエラーシンボルを安全に返却し、CTFE の failure 契約と整合させる。

### 4.2 回帰検証テストスイート設計 (`test_single_source_oracle.scm`)
`test_eval_in_language.scm` の全7大グループに対応する回帰テストケースを策定し、$V_{\text{Now}} \equiv V_{\text{CTFE}}$ の等価性を網羅的に検証：
1. **Group 1: 基本リテラル・定数**: 数値、真偽値、文字、文字列、クォート式
2. **Group 2: 算術・論理・ビット演算**: `+`, `-`, `*`, `quotient`, `modulo`, `remainder`, `abs`, `min`, `max`, `<`, `>`, `=`, `not`, `bitwise-and`, `arithmetic-shift`
3. **Group 3: 局所束縛 (let) と条件分岐 (if)**: ネストした let、静的分岐選択と死滅コード消去、begin 順次評価
4. **Group 4: 第一級クロージャ & 高階関数**: 直接 lambda 適用、カリー化関数、局所束縛手続き呼び出し
5. **Group 5: 安全ガード & リソース限界 (CWE-400)**: ゼロ除算の安全不還元、未束縛変数の安全捕捉、Fuel 枯渇時の安全停止
6. **Group 6: 単一ソース意味論オラクル差分検証**: 同一式を `eval-in-language`（既存 CTFE）と `eval-with-now-oracle`（Now 辞書）の双方で評価し、一致率 100% をアサート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `eval-with-now-oracle` が実装され、Now 辞書経由で安全に式を評価できること。
- [x] `test_single_source_oracle.scm` にて既存 CTFE テスト相当の全領域が PASS すること。
- [x] 既存 CTFE エンジンと `Now` 辞書の評価結果が 100% 一致し、仕様乖離（Semantic Drift）が 0 件であること。
- [x] `make -C ulisp test_single_source_oracle` が 0件エラー PASS すること。
- [x] 既存の全テスト（`test_eval_in_stage`, `test_stage_dict`, `test_psds_provenance`, `test_eval_in_language`）が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。

