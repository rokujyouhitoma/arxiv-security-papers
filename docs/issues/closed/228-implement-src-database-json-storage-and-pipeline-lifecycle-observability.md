---
ID: 228
種別: Feature
優先度: High
ステータス: Closed (Done)
---

# [FEAT/ENH] src/database統合JSONストレージ基盤およびパイプライン・ライフサイクル可観測性刷新 (ID: 228)

## 1. 概要 / Summary

本Issueは、[DSN-05 (第21章)](../../docs/designs/DSN-05-database_engine_architecture.md#21-jsonバックエンドストレージ--git追跡可能オープンデータ永続化仕様-json-backed-storage-architecture)、[DSN-10 (第13章)](../../docs/designs/DSN-10-observability_and_eval_framework.md#13-パイプラインライフサイクル可観測性--4大運用メトリクス仕様-pipeline-lifecycle-observability)、[DSN-03 (第2.4節/第4.6節)](../../docs/designs/DSN-03-pipeline_architecture.md#24-重複防止台帳-processed_papersjson-から-srcdatabase-統合への進化)、および [DSN-21 (第7.2.1項)](../../docs/designs/DSN-21-enterprise_design_system_and_unified_console.md#721-tab-5-system--lifecycle-observability-systemtab-uiux-刷新仕様) に基づき、以下の 3 つの構造的課題を一括解決することを目的とする：

1. **`processed_papers.json` (7.2MB) の I/O 爆縮およびメモリ圧迫の解消**:
   - 論文台帳をプレーンな単一巨大 JSON から `src/database` の JSON バックエンドストレージ（`JsonTableStorage`）へ移行。
   - インメモリ B-Tree / ハッシュインデックス（`_pk_index`）により、毎回のファイル全件パースを廃止し、論文重複判定を $O(N)$ から $O(1)$（0.05ms 未満）に短縮する。
2. **人間・AI可読かつ Git 追跡可能なオープンデータ永続化モデルの確立**:
   - 外部 SQLite バイナリ（`.db`）ではなく、プロジェクト自前の純Pythonデータベース基盤（`src/database`）を活用。
   - 公知データや監査ログについて、人間・AIが直接読め Git で最小差分追跡可能な JSON / JSONLines 形式（`pipeline_state.jsonl`, `papers_catalog.json`）をストレージバックエンドとしてマウント。
   - パイプライン実行履歴（`pipeline_runs`）から `outputs/log.md`（直近 50 件）を自動プロジェクション生成し、GitHub 上での運用透明性を 100% 維持する。
3. **`index.html`「📈 システム観測 & ライフサイクル運用」の 4 大運用カード刷新**:
   - 死んだプレースホルダー（`valDeadEndDepth` 等）や内部探索用の `Traversal Matrix`、架空の RDBMS メトリクス（IOPS/Cache Hit）を完全撤廃。
   - 実パイプライン 6 フェーズ連動バー（収集 ➔ PDF抽出 ➔ OKF変換 ➔ 脅威分析 ➔ 知識蓄積 ➔ 5層サマリー）と、4 大運用カード（運行スケジューラ、成果物ライフサイクル、外部通信健全性、SLA監査ログ台帳）に全面刷新し、ダミー固定値のない真の可観測性を実現する。

---

## 2. セキュリティ脅威モデルと多層防御設計 (Threat Modeling & Security Architecture)

本機能は外部ファイル I/O、ストレージ排他制御、および Web UI へのメトリクス公開を伴うため、以下の脅威モデルと多層防御策を適用する：

| 脅威カテゴリ (STRIDE) | 潜在リスク (Threat Scenario) | 緩和策・セキュリティ仕様 (Mitigations) |
| :--- | :--- | :--- |
| **Tampering (改ざん・破損)** | バッチプロセス突然停止や並行書き込みによる JSON ファイルの部分書き込み・トランケーション破損 | **アトミック置換 + POSIX 排他ロック**:<br>1. 書き込み時は `<file>.tmp.<pid>.<uuid>` に全量出力後、`os.fsync()` を経て `os.replace()` でアトミック置換。<br>2. プロセス間競合は `fcntl.flock(fd, fcntl.LOCK_EX)`（非POSIX環境では再試行ループ）により 100% 排他制御。 |
| **Denial of Service (DoS)** | 7.2MB 超の JSON パースに伴う CPU 飽和、メモリ枯渇、バッチ実行遅延 | **インメモリキーキャッシュ + 遅延評価**:<br>1. コールドスタート時に主キー（`arxiv_id`, `clean_id`）のみをメモリロードし、本文・詳細メタデータはオンデマンド読み込み。<br>2. 時系列実行ログは 1 行 1 JSON の `JsonLinesStorage` を採用し、追記 I/O を $O(1)$ に固定。 |
| **Elevation of Privilege (特権昇格)** | 不正な `run_id` や `clean_id` によるディレクトリトラバーサル攻撃 | **厳格な正規表現識別子バリデーション**:<br>`clean_id`: `^[a-zA-Z0-9_\-]+$`（スラッシュや `..` を拒絶）<br>`run_id`: `^run_\d{8}_\d{6}(_[a-zA-Z0-9]+)?$` のみ許可。 |
| **Information Disclosure (漏洩)** | Web ゲートウェイのエラーレスポンスによるローカルファイルパス露出 | **パス正規化・サニタイズ**:<br>API 返却値はすべてリポジトリルートからの相対パス（例: `outputs/okf_papers/...`）に正規化し、絶対パス（`/workspace/...`）の流出を遮断。 |

---

## 3. トレーサビリティ / Traceability

- **設計仕様書**:
  - **データベース基盤**: [DSN-05: 第21章 JSONバックエンドストレージ ＆ Git追跡可能オープンデータ永続化仕様](../../docs/designs/DSN-05-database_engine_architecture.md#21-jsonバックエンドストレージ--git追跡可能オープンデータ永続化仕様-json-backed-storage-architecture)
  - **可観測性・SLA**: [DSN-10: 第13章 パイプライン・ライフサイクル可観測性 ＆ 4大運用メトリクス仕様](../../docs/designs/DSN-10-observability_and_eval_framework.md#13-パイプラインライフサイクル可観測性--4大運用メトリクス仕様-pipeline-lifecycle-observability)
  - **パイプライン・台帳**: [DSN-03: 第2.4節 重複防止台帳 ＆ 第4.6節 実態6フェーズライフサイクル](../../docs/designs/DSN-03-pipeline_architecture.md#24-重複防止台帳-processed_papersjson-から-srcdatabase-統合への進化)
  - **UI/UX コンソール**: [DSN-21: 第7.2.1項 Tab 5 (System & Lifecycle Observability) UI/UX 刷新仕様](../../docs/designs/DSN-21-enterprise_design_system_and_unified_console.md#721-tab-5-system--lifecycle-observability-systemtab-uiux-刷新仕様)
- **関連Issue**: Issue #229 (Pluggable Storage & PlainText Tables), Issue #214 (MultiTable VDB), Issue #216 (Zero-Mock Integrity)
- **品質規程**: `.agents/AGENTS.md` (ゼロ外部依存, 相対パスリンク厳守, ゼロモック原則, Xenon Rank A CC<=5, mypy --strict)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### (1) データベース基盤層 (`src/database/`)
- [x] `src/database/storage/json_storage.py` [NEW]:
  - `JsonLinesStorage`: 追記型時系列ストレージ（`pipeline_runs`）
  - `JsonTableStorage`: 主キー更新型カタログストレージ（`processed_papers`）
- [x] `src/database/storage/__init__.py`: クラスエクスポート

### (2) パイプライン ＆ 状態管理層 (`src/pipeline/`)
- [x] `src/pipeline/pipeline_state.py` [NEW]: `PipelineStateManager`（実行監査ログ記録、重複判定、`outputs/log.md` 自動プロジェクション）
- [x] `src/pipeline/arxiv_okf_fetcher.py`: `processed_papers.json` 直読み/直書きを廃止し、`PipelineStateManager` に置換
- [x] `outputs/log.md`: プロジェクションエンジンによる自動再生成

### (3) Web ゲートウェイ ＆ UI プレゼンテーション層
- [x] `src/web/gateway/handlers.py`: `handle_system_lifecycle()` 追加（`/api/system/lifecycle`）
- [x] `site/index.html`: `systemTab` を実態連動 6 フェーズバー ＆ 4 大運用観測カードに置換
- [x] `site/app.js`: `syncLifecycleTelemetry()` 実装、旧 Dead-End/Traversal コード全廃

### (4) テスト ＆ 品質検証
- [x] `tests/database/storage/test_json_storage.py` [NEW]: `JsonLinesStorage` / `JsonTableStorage` のアトミック書き込み、排他ロック、インデックス高速照会テスト
- [x] `tests/pipeline/test_pipeline_state.py` [NEW]: `PipelineStateManager`、既存データ移行、`outputs/log.md` 自動プロジェクション検証
- [x] `tests/web/test_zero_mock_integrity.py`: 新 UI 要素（`#pipelineBar`, `#phaseStep0`, `#cardScheduler` 等）の実データ連携検証

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/228-implement-src-database-json-storage-and-pipeline-lifecycle-observability`

### Step 1: `src/database/storage/json_storage.py` の実装
1. **`JsonLinesStorage`**:
   - `append_record(record: Dict[str, Any]) -> None`: `fcntl.flock(LOCK_EX)` を用いて末尾に追記。
   - `scan_records(limit: Optional[int] = None, reverse: bool = False) -> List[Dict[str, Any]]`: ストリーミング読み込み。
2. **`JsonTableStorage`**:
   - `_pk_index: Dict[str, Dict[str, Any]]`: 初回アクセス時に主キーハッシュマップを構築。
   - `get_by_pk(pk_value: str) -> Optional[Dict[str, Any]]`: $O(1)$ キャッシュ照会。
   - `upsert(pk_value: str, record: Dict[str, Any]) -> None`: インメモリ更新＋一時ファイル `.tmp` 経由の `os.replace` アトミックフラッシュ。

### Step 2: パイプライン状態管理の刷新 (`src/pipeline/pipeline_state.py`)
1. **`PipelineStateManager` クラス**:
   - `is_paper_processed(arxiv_id: str) -> bool`: $O(1)$ 判定。
   - `register_paper(paper_meta: Dict[str, Any]) -> None`: 論文カタログへ登録。
   - `record_run_start(run_id: str, category: str) -> None`: 実行開始記録。
   - `record_run_complete(run_id: str, status: str, fetched: int, processed: int, duration_sec: float) -> None`: 完了記録。
   - `project_log_markdown(output_path: str = "outputs/log.md", limit: int = 50) -> None`: 実行履歴からマークダウン台帳を自動生成。
2. **既存データ移行**:
   - `processed_papers.json`（7.2MB）が存在する場合、初回起動時に `outputs/database/papers_catalog.json` へ安全に移行。

### Step 3: `arxiv_okf_fetcher.py` の統合
- グローバル変数 `PROCESSED_PAPERS_FILE` への直接ロード・書き込みを排除し、`PipelineStateManager` のシングルトンを経由する設計に置換。

### Step 4: Web ゲートウェイ `/api/system/lifecycle` の実装 (`src/web/gateway/handlers.py`)
- 返却データ構造（DSN-10 準拠）：
  ```json
  {
    "status": "success",
    "phases": [
      {"name": "fetch", "status": "idle", "last_active": "..."},
      {"name": "extract_pdf", "status": "idle", "last_active": "..."},
      {"name": "convert_okf", "status": "idle", "last_active": "..."},
      {"name": "threat_analysis", "status": "idle", "last_active": "..."},
      {"name": "graph_ingest", "status": "idle", "last_active": "..."},
      {"name": "summary_generation", "status": "idle", "last_active": "..."}
    ],
    "scheduler": {
      "schedule": "00:00, 06:00, 12:00, 18:00 UTC",
      "next_run_utc": "...",
      "last_run_status": "SUCCESS",
      "streak_days": 160
    },
    "artifacts": {
      "okf_papers_count": 526,
      "raw_pdf_count": 526,
      "latest_summary_tier": "05_annual"
    },
    "external_health": {
      "arxiv_api": "HEALTHY",
      "mitre_attack": "HEALTHY",
      "nvd_cve": "HEALTHY"
    },
    "recent_runs": [...]
  }
  ```

### Step 5: `site/index.html` ＆ `site/app.js` の UI 刷新
1. **HTML 構造の刷新**:
   - `#systemTab` 内の不要な DOM（`#tblTraversalLedger`, `#canvasTraversalMatrix` 等）を削除。
   - 実態 6 フェーズステータスバー（`#lifecyclePhaseBar`）を追加。
   - 4 大運用カード（`#cardScheduler`, `#cardArtifactLifecycle`, `#cardExternalHealth`, `#cardSlaAuditLedger`）をグリッドレイアウトで配置。
2. **JavaScript バインド (`site/app.js`)**:
   - `syncLifecycleTelemetry()` 関数を新設し、`/api/system/lifecycle` からのレスポンスを完全実データで各カードへレンダリング。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] **純Python JSONストレージ性能**:
  - `JsonTableStorage` による論文重複チェックのレスポンスタイムが **0.1ms 未満** であること（ベンチマークテストで立証）。
  - 並行書き込み時にも `fcntl.flock` とアトミックリネームによりデータ破損・データ消失が 0 件であること。
- [x] **パイプライン台帳・プロジェクション完全性**:
  - `outputs/database/pipeline_state.jsonl` にバッチ実行ログが追記され、`outputs/log.md`（直近 50 件）が完全自動生成されること。
  - `outputs/database/papers_catalog.json` に処理済み論文が主キー重複なく整然と Git 追跡可能に記録されること。
- [x] **ゼロモック・可観測性 UI 適合**:
  - `site/index.html` の `systemTab` において、死んだ未実装要素・架空固定値が 0 件であり、実データが表示されること。
  - `tests/web/test_zero_mock_integrity.py` が 100% PASS すること。
- [x] **コード品質 ＆ 静的解析**:
  - 全ての新規・更新コードが `mypy --strict` でエラー 0 件であること。
  - 全関数のサイクロマティック複雑度が Xenon **Rank A (CC <= 5)** を達成していること。
  - `make check_format` および `make test` が 100% PASS すること。
