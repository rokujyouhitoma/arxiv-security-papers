# [FEAT] 仮説駆動型 自律調査・検証ループ (Hypothesis-Driven Autonomous Investigation & Verification Engine) の実装 (ID: 086)

| 項目 | 内容 |
| :--- | :--- |
| **ID** | 086 |
| **種別** | Feature |
| **優先度** | High |
| **ステータス** | Closed (Resolved) |
| **起票日** | 2026-08-27 |
| **完了日** | 2026-08-27 |
| **担当ロール** | IT Strategist (ST) / Systems Architect (SA) |
| **対象ブランチ** | `feat/086-hypothesis-driven-autonomous-investigation` |

---

## 1. 概要 / Summary
自律型インテリジェンス・オーケストレーター（`src/orchestrator/analysis/`）に、単なるキーワード集計・要約を超えて、セキュリティ領域の未検証命題を自律定式化し、収集論文群から支持証拠（Supporting Evidence）と反証証拠（Refuting Evidence）を抽出・確信度スコアリングを行って検証する「仮説駆動型 自律調査・検証エンジン（Hypothesis-Driven Investigation Engine）」を実装する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/orchestrator/analysis/hypothesis_engine.py` (新規: 仮説モデル、定式化、証拠抽出、確信度評価、レポート合成)
- `src/orchestrator/contracts.py` (Hypothesis, HypothesisStatus, PhaseContext への仮説リスト統合)
- `src/orchestrator/engine.py` (HypothesisEngine のライフサイクル統合)
- `src/orchestrator/cli.py` (CLI サブコマンド `hypothesis list / add / report` の実装)
- `tests/orchestrator/test_hypothesis_engine.py` (新規: 単体 & 統合テスト)
- `docs/issues/README.md` (Issue 台帳更新)
- `docs/designs/DSN-11-intelligence_orchestration_engine.md` (設計書更新)

---

## 3. 要件定義と脅威モデル / Requirements & Threat Model
- **機能要件**:
  - `HypothesisStatus` Enum（`FORMULATED`, `INVESTIGATING`, `SUPPORTED`, `REFUTED`, `INCONCLUSIVE`）。
  - `Hypothesis` データクラス（命題 statement, 対象トピック, 確信度 confidence_score, 支持/反証根拠リスト, ステータス）。
  - `HypothesisEngine`:
    - `formulate_hypotheses(records)`: 収集論文の相関・急上昇トピックから自律的に仮説を定式化。
    - `evaluate_hypotheses(records)`: 論文テキストから支持/反証証拠を照合し確信度をベイズ的に更新。
    - `synthesize_hypothesis_report(hypo)`: 結論、証拠一覧、セキュリティリスク示唆を含む完全日本語レポートを合成。
    - `generate_investigation_queries(hypo)`: 検証不足トピックに対する次期 PIR / 収集クエリを生成。
- **非機能・セキュリティ要件**:
  - ゼロ外部依存（標準ライブラリのみ）。
  - 型安全性（`mypy --strict` 0 エラー）および xenon Grade A/B 適合。

---

## 4. 実装方針 / Implementation Plan
1. **`src/orchestrator/contracts.py`**:
   - `HypothesisStatus`, `HypothesisEvidence`, `Hypothesis` を定義し、`PhaseContext` に統合。
2. **`src/orchestrator/analysis/hypothesis_engine.py`**:
   - `HypothesisEngine` を新規実装。
3. **`src/orchestrator/engine.py` & `src/orchestrator/cli.py`**:
   - オーケストレーターおよび CLI に仮説調査コマンドを統合。
4. **`tests/orchestrator/test_hypothesis_engine.py`**:
   - 仮説生成、証拠抽出、確信度更新、レポート合成のテストを作成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 未検証セキュリティ仮説の自律定式化と、論文からの支持/反証証拠抽出・スコアリングが動作すること。
- [x] 仮説レポートおよび調査クエリの自動生成が機能すること。
- [x] `tests/orchestrator/test_hypothesis_engine.py` を含む全テストが 100% PASS すること。
- [x] `make check` (mypy strict, xenon, flake8, black) をクリアすること。
