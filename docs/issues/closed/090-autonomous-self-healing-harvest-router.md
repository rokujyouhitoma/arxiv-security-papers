# [FEAT] 自律型自己修復 & 動的ルート変異ハーベスター (Autonomous Self-Healing & Dynamic Route Mutation Harvester) の実装 (ID: 090)

| 項目 | 内容 |
| :--- | :--- |
| **ID** | 090 |
| **種別** | Feature |
| **優先度** | High |
| **ステータス** | Closed (Resolved) |
| **起票日** | 2026-08-27 |
| **完了日** | 2026-08-27 |
| **担当ロール** | Network Specialist (NET) / IT Service Manager (OPS) |
| **対象ブランチ** | `feat/090-autonomous-self-healing-harvest-router` |

---

## 1. 概要 / Summary
自律型インテリジェンス・オーケストレーター（`src/orchestrator/harvest/`）に、外部データソース（arXiv API, IACR, NVD/CVE, Web Spider 等）の通信障害・HTTP 429 レート制限・ネットワーク遅延を自律検知し、サーキットブレーカー（Circuit Breaker）と動的ルート変異（Dynamic Route Mutation / Auto-Fallback）により無停止でデータ収集を継続する「自律型自己修復ハーベストルーター（`AdaptiveHarvestRouter`）」を実装する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/orchestrator/harvest/adaptive_router.py` (新規: CircuitState, CircuitBreaker, HarvestRoute, AdaptiveHarvestRouter)
- `src/orchestrator/harvest/__init__.py` (ルーターシンボルのエクスポート)
- `src/orchestrator/harvest/coordinator.py` (AdaptiveHarvestRouter 統合と自動フォールバック)
- `src/orchestrator/cli.py` (CLI サブコマンド `harvest status / test` の追加)
- `tests/orchestrator/test_adaptive_harvest_router.py` (新規: 単体 & 統合テスト)
- `docs/issues/README.md` (Issue 台帳更新)
- `docs/designs/DSN-11-intelligence_orchestration_engine.md` (設計書更新)

---

## 3. 要件定義と脅威モデル / Requirements & Threat Model
- **機能要件**:
  - `CircuitState` Enum（`CLOSED`, `OPEN`, `HALF_OPEN`）。
  - `CircuitBreaker`（失敗閾値、クールダウン期間、プローブ遷移）。
  - `HarvestRoute`（ルートID、優先度、ヘルススコア EMA、ハンドラ関数）。
  - `AdaptiveHarvestRouter`（多重ルート管理、優先度順試行、動的ルート変異、ヘルス統計収集）。
  - `HarvestCoordinator` への統合（プライマリ API 障害時の RSS/Spider/ローカル代替ルート自律切り替え）。
  - CLI `orchestrator harvest status` および `orchestrator harvest test`。
- **非機能・セキュリティ要件**:
  - ゼロ外部依存（Python標準ライブラリのみ）。
  - 指数バックオフ + ジッターによる外部サーバー過負荷防止。
  - 型安全性（`mypy --strict` 0 エラー）および xenon Grade A/B 適合。

---

## 4. 実装方針 / Implementation Plan
1. **`src/orchestrator/harvest/adaptive_router.py`**:
   - CircuitState, CircuitBreaker, HarvestRoute, AdaptiveHarvestRouter を実装。
2. **`src/orchestrator/harvest/coordinator.py`**:
   - `HarvestCoordinator` に `AdaptiveHarvestRouter` を統合。
3. **`src/orchestrator/cli.py`**:
   - `harvest` サブコマンド（`status`, `test`）を追加。
4. **`tests/orchestrator/test_adaptive_harvest_router.py`**:
   - サーキットブレーカー状態遷移、ルート変異フォールバック、ヘルススコア計算、CLI コマンドのテストスイートを作成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] プライマリソース障害時にサーキットが OPEN に遷移し、次点ルートへ自動変異すること。
- [x] クールダウン後に HALF_OPEN プローブが成功し、CLOSED へ自己修復復帰すること。
- [x] `tests/orchestrator/test_adaptive_harvest_router.py` を含む全テストが 100% PASS すること。
- [x] `make check` (mypy strict, xenon, flake8, black) をクリアすること。
