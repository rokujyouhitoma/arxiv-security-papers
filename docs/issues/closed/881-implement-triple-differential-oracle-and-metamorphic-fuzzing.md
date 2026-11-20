---
ID: 881
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] 3重差分テストオラクルとメタモルフィック摂動検証スイートの実装 (ID: 881)

## 1. 概要 / Summary
DSN-33-03 §3.6 および §4.4 に基づき、高水準オラクル（Now 即時値 $V_{\text{now}}$）、中間水準オラクル（Later 辞書および LIR 仮想マシン値 $V_{\text{vm}}$）、低水準・平坦化ターゲット（部分評価 `stage-poly-lower` 後の残余実行値 $V_{\text{residual}}$）の 3 者が常に一致することを検証する 3 重差分テストフレームワークを実装する。また、束縛時間摂動（全静的・PSDS・全動的）テストを自動実行し、メタモルフィック健全性定理 $\mathcal{E}\llbracket P \rrbracket(S, D) \equiv \mathcal{E}\llbracket \mathrm{mix}(P, S) \rrbracket(D) \equiv \dots$ を実証する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §3.6 (単一ソース意味論オラクルと多層差分検証)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#36-単一ソース意味論オラクルsingle-source-semantic-oracleと多層差分検証)
  - [DSN-33-03 §4.4 (メタモルフィック健全性定理と自動ファジング)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#44-メタモルフィック健全性定理metamorphic-soundness-theoremと自動ファジング)
- 関連 Issue:
  - #872 (eval-in-stage コアループ)
  - #873 (単一ソース意味論オラクル)
  - #874 (4値束縛時間束 BTA)
  - #879 (ステージ多相部分評価 Nanopass stage-poly-lower の実装)
  - #880 (Pass Manager への Nanopass 文法完全消去アサーションの組み込み)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm) - 3重差分オラクル実行ヘルパー `run-triple-differential-oracle`
- [x] [ulisp/tests/test_stage_oracle.scm](ulisp/tests/test_stage_oracle.scm) - 3重差分およびメタモルフィック摂動テストスイート
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_stage_oracle` ターゲット追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/881-implement-triple-differential-oracle-and-metamorphic-fuzzing`

### 4.1 3重差分テストオラクル `run-triple-differential-oracle`
1. 入力式 $E$ に対し以下を取得:
   - $V_{\text{now}}$: `eval-with-now-oracle` または `(eval-in-stage (make-now-stage-dict) env E)`
   - $V_{\text{later}}$: `(stage-poly-lower E env)` 後の ANF 評価値
   - $V_{\text{lir}}$: LIR プログラム生成および `eval-lir-program` 実行値
2. 3 者が一致すること（$V_{\text{now}} \equiv V_{\text{later}} \equiv V_{\text{lir}}$）をアサート。

### 4.2 メタモルフィック束縛時間摂動（Binding-Time Perturbation）テスト
- 複合計算（乗算ループ・べき乗・アッカーマン風再帰・テーブル検索等）に対して、
  - 摂動 1: 全静的（All Static: 全引数を静的定数として Now 評価）
  - 摂動 2: PSDS（Partially Static Data Structures: 一部引数を静的、残りを動的として部分評価）
  - 摂動 3: 全動的（All Dynamic: 全引数を動的として評価）
- 3つの摂動モード間で最終計算結果が完全一致（100% Bit-accurate Equivalence）することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] $V_{\text{now}} \equiv V_{\text{later}} \equiv V_{\text{lir}}$ の 3 重差分アサーションが 100% 成立すること。
- [x] 全静的・PSDS・全動的のメタモルフィック摂動テストが 0件エラー PASS すること。
- [x] `make -C ulisp test_stage_oracle` が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
