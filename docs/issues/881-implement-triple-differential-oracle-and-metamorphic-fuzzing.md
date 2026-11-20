---
ID: 881
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 3重差分テストオラクルとメタモルフィック摂動検証スイートの実装 (ID: 881)

## 1. 概要 / Summary
DSN-33-03 §3.6 および §4.4 に基づき、高水準オラクル（Now 即時値 $V_{\text{now}}$）、中間オラクル（LIR Reference VM 値 $V_{\text{vm}}$）、低水準ターゲット（ネイティブバイナリ値 $V_{\text{native}}$）の 3 者が常に一致することを検証する 3 重差分テストフレームワークを実装する。また、束縛時間摂動（全静的・PSDS・全動的）テストを自動実行する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §3.6, §4.4](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#36-単一ソース意味論オラクルsingle-source-semantic-oracleと多層差分検証)
- 関連 Issue: #834 (Reference VM), #831 (Differential Fuzzing)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/tests/test_stage_oracle.scm](ulisp/tests/test_stage_oracle.scm)
- [ ] [ulisp/vm/lir_interpreter.scm](ulisp/vm/lir_interpreter.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/881-implement-triple-differential-oracle-and-metamorphic-fuzzing`

1. 任意の式に対し、$V_{\text{now}}$, $V_{\text{vm}}$, $V_{\text{native}}$ を取得して比較するテストランナーを作成。
2. 同一式に対する静的・動的引数分割を変化させるメタモルフィック摂動スイートを構築。
3. 不一致検知時に差分 AST をダンプして問題パスを局所特定。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] $V_{\text{now}} \equiv V_{\text{vm}} \equiv V_{\text{native}}$ のアサーションが 100% 成立すること。
- [ ] メタモルフィック摂動テストが PASS すること。
