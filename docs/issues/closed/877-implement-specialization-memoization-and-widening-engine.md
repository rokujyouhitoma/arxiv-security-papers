---
ID: 877
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] 特殊化メモ化エンジンとハードリミット・一般化（Widening）の実装 (ID: 877)

## 1. 概要 / Summary
DSN-33-03 §5.1, §5.2, §5.3 に基づき、多相再帰関数やインタプリタメインループの部分評価における無限展開（コード爆発・コンパイル非停止）を完全に遮断する特殊化メモ化エンジン（Specialization Memoization Engine）を実装する。
キー $\langle \mathrm{FuncSymbol},\; \Pi_{\text{static}}(\mathrm{Args}) \rangle$ による展開キャッシュを管理し、多重特殊化上限 `MAX_SPEC_INSTANCES=8` および再帰深度上限 `MAX_SPEC_DEPTH=4` をハードリミットとして課す。上限到達時には静的引数を動的へ降格する一般化（Widening）を発動し、独立した残余関数（`define-residual-fn`）として切り離して呼び出しコードを生成する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §5.1, §5.2, §5.3 (Specialization Engine & Hard Limits & Generalization)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#5-特殊化エンジンと停止性保証hard-limits--generalization)
  - [DSN-33-01 §3.2 (Nanopass Pass Pipeline)](docs/designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 関連 Issue:
  - #871 (PSDS & Dual Source Span Provenance)
  - #872 (eval-in-stage コアループ)
  - #874 (4値束縛時間束 BTA)
  - #875 (動的分岐配下の純粋性解析と投機的例外自動降格)
  - #876 (CSP 越境バリデータと Dual Span 診断レポーター)
  - #878 (Nanopass 中間言語 L-StagePoly および L-Residual-ANF)
  - #879 (ステージ多相部分評価 Nanopass)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm) - 特殊化メモ化テーブル、$\Pi_{\text{static}}$ 射影、Widening 降格、残余関数レジストリ
- [x] [ulisp/tests/test_specialization_widening.scm](ulisp/tests/test_specialization_widening.scm) - メモ化・深度制御・Widening・残余関数分離の単体テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_specialization_widening` ターゲット追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/877-implement-specialization-memoization-and-widening-engine`

### 4.1 静的骨格射影 $\Pi_{\text{static}}$ とキー生成
1. `(stage-project-static-key sv)`:
   - `pure-static`: ペイロードそのものを抽出（数値、シンボル、真偽値等）。
   - `partially-static` (PSDS): 静的骨格のみを保持し、動的リーフをワイルドカード `*dynamic*` に置換。
   - `pure-dynamic`: `*dynamic*` シンボル。
2. 特殊化シグネチャキー:
   `(list fn-name (map stage-project-static-key args))`

### 4.2 特殊化メモ化コンテキスト `<spec-memo-table>`
1. レコード `<spec-memo-table>`:
   - `instances`: 各関数シンボルごとの特殊化インスタンス数（連想リスト `((fn . count) ...)`）
   - `table`: シグネチャキーから生成された特殊化関数名へのマッピング（`((key . spec-fn-name) ...)`）
   - `residual-fns`: 生成・切り離された残余関数定義のリスト
   - `call-depth`: 現在の特殊化呼び出し深度スタック
2. ハードリミット定数:
   - `*max-spec-instances*`: 8
   - `*max-spec-depth*`: 4

### 4.3 一般化（Widening）と残余関数切り離し
1. インスタンス数 $\ge 8$ または 呼び出し深度 $> 4$ の場合:
   - 静的引数をすべて動的（`make-dynamic-val`）へ降格。
   - メモ化をスキップし、汎用残余関数の直接呼び出し、または汎用フォールバック関数へとルーティング。
2. 特殊化成功時:
   - 新規の一意な特殊化シンボル（例: `fn$spec0`, `fn$spec1`）を採番。
   - 特殊化ボディを残余コードとして生成し、残余関数レジストリに登録。
   - 呼び出し側は `(spec-fn dynamic-args ...)` に置換。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] $\Pi_{\text{static}}$ 射影が静的値・PSDS・動的値を正確に正規化キーへ射影できること。
- [x] 同一の静的シグネチャによる呼び出しがメモ化キャッシュにより再利用され、重複特殊化が排除されること。
- [x] `MAX_SPEC_INSTANCES=8` を超える多相再帰において、一般化（Widening）が発動し無限展開が停止すること。
- [x] `MAX_SPEC_DEPTH=4` を超える深い特殊化再帰において、一般化（Widening）が発動すること。
- [x] 生成された残余関数が残余レジストリに正しく登録され、呼び出しコードが特殊化シンボルに置換されること。
- [x] `make -C ulisp test_specialization_widening` が 0件エラー PASS すること。
- [x] 全既存テスト（`test_csp_boundary_validator` 含む）が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
