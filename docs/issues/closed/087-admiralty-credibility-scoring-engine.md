# [FEAT] 情報源信憑性スコアリング Admiralty Engine (NATO STANAG 2022 規格準拠) の実装 (ID: 087)

| 項目 | 内容 |
| :--- | :--- |
| **ID** | 087 |
| **種別** | Feature |
| **優先度** | High |
| **ステータス** | Closed (Resolved) |
| **起票日** | 2026-08-27 |
| **完了日** | 2026-08-27 |
| **担当ロール** | Information Security Specialist (SEC) / Systems Auditor (AUD) |
| **対象ブランチ** | `feat/087-admiralty-credibility-scoring-engine` |

---

## 1. 概要 / Summary
自律型インテリジェンス・オーケストレーター（`src/orchestrator/processing/`）に、NATO STANAG 2022 / 国際インテリジェンス標準規格である Admiralty System（海軍本部コード: A〜F [情報源信頼性] × 1〜6 [情報確実性]）に準拠した「情報源信憑性スコアリングエンジン（Admiralty Credibility Engine）」を実装する。収集された論文・脆弱性情報・プレプリント・アドバイザリの信憑性を多次元評価し、OKF フロントマターへの埋め込みおよび仮説検証（HypothesisEngine）の証拠重み付けに連動させる。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/orchestrator/processing/credibility.py` (新規: AdmiraltyReliability, AdmiraltyCredibility, AdmiraltyRating, AdmiraltyEngine)
- `src/orchestrator/processing/processor.py` (AdmiraltyEngine 連携と OKF フロントマター信憑性メタデータ埋め込み)
- `src/orchestrator/processing/__init__.py` (Admiralty シンボルのエクスポート)
- `src/orchestrator/analysis/hypothesis_engine.py` (Admiralty スコア連動による証拠重み付け)
- `src/orchestrator/cli.py` (CLI サブコマンド `credibility rate / matrix` の追加)
- `tests/orchestrator/test_credibility_engine.py` (新規: 単体 & 統合テスト)
- `docs/issues/README.md` (Issue 台帳更新)
- `docs/designs/DSN-11-intelligence_orchestration_engine.md` (設計書更新)

---

## 3. 要件定義と脅威モデル / Requirements & Threat Model
- **機能要件**:
  - `AdmiraltyReliability` Enum（`A` 完全信頼 〜 `F` 評価不能）および重み付け（1.0 〜 0.5）。
  - `AdmiraltyCredibility` Enum（`1` 独立確認済 〜 `6` 確実性判断不能）および重み付け（1.0 〜 0.5）。
  - `AdmiraltyRating`（`code`: "A1"等, `score`: $w_{\text{rel}} \times w_{\text{cred}}$, 日本語評価理由）。
  - `AdmiraltyEngine.rate_record(record)` による自動判定（公式アドバイザリ=A, 査読/IACR/arXiv=B/C, CVE引用/数式証明/PoC実証=1/2等）。
  - Phase 3 `ProcessingCoordinator` による OKF v0.2 `trust.admiralty_code` / `trust.confidence` の自動反映。
- **非機能・セキュリティ要件**:
  - ゼロ外部依存（Python標準ライブラリのみ）。
  - 型安全性（`mypy --strict` 0 エラー）および xenon Grade A/B 適合。

---

## 4. 実装方針 / Implementation Plan
1. **`src/orchestrator/processing/credibility.py`**:
   - AdmiraltyReliability, AdmiraltyCredibility, AdmiraltyRating, AdmiraltyEngine を実装。
2. **`src/orchestrator/processing/processor.py`**:
   - `ProcessingCoordinator` に `AdmiraltyEngine` を統合。
3. **`src/orchestrator/analysis/hypothesis_engine.py`**:
   - 証拠抽出時にレコードの Admiralty スコアを反映。
4. **`src/orchestrator/cli.py`**:
   - `credibility matrix` / `credibility rate` サブコマンドを追加。
5. **`tests/orchestrator/test_credibility_engine.py`**:
   - マトリクス評価、OKF統合、仮説検証連動のテストスイートを作成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] Admiralty Code (A〜F × 1〜6) の評価マトリクスと数値スコアリングが正しく計算されること。
- [x] Phase 3 OKF ドキュメントおよび Phase 4 仮説検証に信憑性スコアが連動すること。
- [x] `tests/orchestrator/test_credibility_engine.py` を含む全テストが 100% PASS すること。
- [x] `make check` (mypy strict, xenon, flake8, black) をクリアすること。
