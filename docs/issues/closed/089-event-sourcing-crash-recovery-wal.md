# [FEAT] Event Sourcing 型 クラッシュリカバリ WAL (Write-Ahead Log & State Replay Engine) の実装 (ID: 089)

| 項目 | 内容 |
| :--- | :--- |
| **ID** | 089 |
| **種別** | Feature |
| **優先度** | High |
| **ステータス** | Closed (Resolved) |
| **起票日** | 2026-08-27 |
| **完了日** | 2026-08-27 |
| **担当ロール** | Database / Data Infrastructure Specialist (DB) / Systems Auditor (AUD) |
| **対象ブランチ** | `feat/089-event-sourcing-crash-recovery-wal` |

---

## 1. 概要 / Summary
自律型インテリジェンス・オーケストレーター（`src/orchestrator/`）に、プロセス強制終了・システムクラッシュ・外部APIタイムアウト発生時でも処理状態を 100% 復元・未完了フェーズから再開可能にする「Event Sourcing 型 クラッシュリカバリ WAL（Write-Ahead Log & State Replay Engine: `OrchestratorWAL`）」を実装する。各フェーズのライフサイクルイベントおよび生成物を追記専用ログとして原子的に記録し、スナップショットチェックポイントおよびイベントリプレイによる確実な再開（Resume）を実現する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/orchestrator/wal.py` (新規: OrchestratorEvent, OrchestratorWAL, EventType)
- `src/orchestrator/__init__.py` (WAL シンボルのエクスポート)
- `src/orchestrator/engine.py` (WAL イベント記録および `resume_cycle` リカバリ再開メソッドの追加)
- `src/orchestrator/cli.py` (CLI サブコマンド `recover` の追加)
- `tests/orchestrator/test_wal_recovery.py` (新規: 単体 & 統合テスト)
- `docs/issues/README.md` (Issue 台帳更新)
- `docs/designs/DSN-11-intelligence_orchestration_engine.md` (設計書更新)

---

## 3. 要件定義と脅威モデル / Requirements & Threat Model
- **機能要件**:
  - `OrchestratorEvent`（イベントID、サイクルID、タイムスタンプ、イベント種別、ペイロード）。
  - `OrchestratorWAL`（追記専用 WAL ログファイル管理、アトミックフラッシュ）。
  - `create_checkpoint(context)` によるスナップショット圧縮。
  - `replay_cycle(cycle_id)` によるイベントソーシング型 `PhaseContext` 状態完全再構成。
  - `UniversalIntelligenceOrchestrator.resume_cycle(cycle_id)` による中断フェーズからのリカバリ実行。
  - CLI `orchestrator recover --list` および `orchestrator recover --cycle-id <ID>`。
- **非機能・セキュリティ要件**:
  - ゼロ外部依存（Python標準ライブラリのみ）。
  - ファイルロック / アトミック書き込みによる破損防止。
  - 型安全性（`mypy --strict` 0 エラー）および xenon Grade A/B 適合。

---

## 4. 実装方針 / Implementation Plan
1. **`src/orchestrator/wal.py`**:
   - OrchestratorEvent, OrchestratorWAL を実装。
2. **`src/orchestrator/engine.py`**:
   - `run_cycle` に WAL イベント記録を組み込み、`resume_cycle` を実装。
3. **`src/orchestrator/cli.py`**:
   - `recover` サブコマンドを追加。
4. **`tests/orchestrator/test_wal_recovery.py`**:
   - イベント追記、チェックポイント作成、クラッシュシミュレーションと状態リプレイ、再開実行のテストスイートを作成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 各フェーズの実行イベントが WAL に追記され、チェックポイントが作成できること。
- [x] クラッシュ時の中断状態から `replay_cycle` および `resume_cycle` で正常に再開・完遂できること。
- [x] `tests/orchestrator/test_wal_recovery.py` を含む全テストが 100% PASS すること。
- [x] `make check` (mypy strict, xenon, flake8, black) をクリアすること。
