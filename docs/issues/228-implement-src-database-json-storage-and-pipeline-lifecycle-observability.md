---
ID: 228
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] src/database統合JSONストレージ基盤およびパイプライン・ライフサイクル可観測性刷新 (ID: 228)

## 1. 概要 / Summary

本Issueは、[DSN-05 (第21章)](../../docs/designs/DSN-05-database_engine_architecture.md#21-jsonバックエンドストレージ--git追跡可能オープンデータ永続化仕様-json-backed-storage-architecture)、[DSN-10 (第13章)](../../docs/designs/DSN-10-observability_and_eval_framework.md#13-パイプラインライフサイクル可観測性--4大運用メトリクス仕様-pipeline-lifecycle-observability)、[DSN-03 (第2.4節/第4.6節)](../../docs/designs/DSN-03-pipeline_architecture.md#24-重複防止台帳-processed_papersjson-から-srcdatabase-統合への進化)、および [DSN-21 (第7.2.1項)](../../docs/designs/DSN-21-enterprise_design_system_and_unified_console.md#721-tab-5-system--lifecycle-observability-systemtab-uiux-刷新仕様) に基づき、以下の 3 つの構造的課題を一括解決することを目的とする：

1. **`processed_papers.json` (7.2MB) の I/O 爆縮およびメモリ圧迫の解消**:
   - 論文台帳をプレーンな単一巨大 JSON から `src/database` の JSON バックエンドストレージへ移行し、インメモリ B-Tree キャッシュにより論文重複判定を $O(N)$ から $O(1)$（0.1ms）に短縮する。
2. **人間・AI可読かつ Git 追跡可能な JSON ストレージモデルの確立**:
   - 外部 SQLite バイナリ（`.db`）ではなく、プロジェクト自前の純Pythonデータベース基盤（`src/database`）を活用。
   - 公知データや監査ログについて、人間・AIが直接読め Git で差分追跡可能な JSON / JSONLines 形式をストレージバックエンドとしてマウント・管理する。
   - パイプライン実行履歴（`pipeline_runs`）から `outputs/log.md`（直近 50 件）を自動プロジェクション生成し、GitHub での透明性を 100% 維持する。
3. **`index.html`「📈 システム観測 & ライフサイクル運用」の 4 大運用カード刷新**:
   - 死んだプレースホルダー（`valDeadEndDepth` 等）や内部探索用の `Traversal Matrix`、架空の RDBMS メトリクス（IOPS/Cache Hit）を撤廃。
   - 実パイプライン 6 フェーズ連動バー（収集 ➔ PDF抽出 ➔ OKF変換 ➔ 脅威分析 ➔ 知識蓄積 ➔ 5層サマリー）と、4 大運用カード（運行スケジューラ、成果物ライフサイクル、外部通信健全性、SLA監査ログ台帳）に全面刷新し、ダミー固定値のない真の可観測性を実現する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - **データベース基盤**: [DSN-05: 第21章 JSONバックエンドストレージ ＆ Git追跡可能オープンデータ永続化仕様](../../docs/designs/DSN-05-database_engine_architecture.md#21-jsonバックエンドストレージ--git追跡可能オープンデータ永続化仕様-json-backed-storage-architecture)
  - **可観測性・SLA**: [DSN-10: 第13章 パイプライン・ライフサイクル可観測性 ＆ 4大運用メトリクス仕様](../../docs/designs/DSN-10-observability_and_eval_framework.md#13-パイプラインライフサイクル可観測性--4大運用メトリクス仕様-pipeline-lifecycle-observability)
  - **パイプライン・台帳**: [DSN-03: 第2.4節 重複防止台帳 ＆ 第4.6節 実態6フェーズライフサイクル](../../docs/designs/DSN-03-pipeline_architecture.md#24-重複防止台帳-processed_papersjson-から-srcdatabase-統合への進化)
  - **UI/UX コンソール**: [DSN-21: 第7.2.1項 Tab 5 (System & Lifecycle Observability) UI/UX 刷新仕様](../../docs/designs/DSN-21-enterprise_design_system_and_unified_console.md#721-tab-5-system--lifecycle-observability-systemtab-uiux-刷新仕様)
- **先行関連設計**: [DSN-23 (HSM & Lifecycle)](../../docs/designs/DSN-23-hierarchical_state_machine_and_lifecycle_governance.md)
- **先行関連Issue**: Issue #214 (MultiTable VDB), Issue #216 (Zero-Mock Integrity), Issue #218 (Pure Database Migration)
- **品質規程**: `.agents/AGENTS.md` (ゼロ外部依存, 相対パスリンク厳守, ゼロモック原則, Xenon Rank A, mypy --strict)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### (1) データベース基盤層 (`src/database/`)
- [ ] `src/database/storage/json_storage.py` [NEW]: `JsonTableStorage` および `JsonLinesStorage` の実装
- [ ] `src/database/storage/__init__.py`: 新ストレージクラスのエクスポート
- [ ] `src/database/sql/executor.py`: JSON ストレージバックエンドとのテーブルバインド対応

### (2) パイプライン ＆ 状態管理層 (`src/pipeline/`)
- [ ] `src/pipeline/pipeline_state.py` [NEW]: `src/database` を用いた実行ログおよび処理台帳マネージャー
- [ ] `src/pipeline/arxiv_okf_fetcher.py`: `pipeline_state` との連動、7.2MB の一括ロード/ダンプ廃止
- [ ] `outputs/log.md`: DB からの自動プロジェクション出力（直近 50 件）

### (3) Web ゲートウェイ ＆ UI プレゼンテーション層
- [ ] `src/web/gateway/handlers.py`: `/api/system/lifecycle` エンドポイント新設または `/api/graph/mesh` のライフサイクル項目拡充
- [ ] `site/index.html`: `systemTab` を実態連動 6 フェーズバー ＆ 4 大運用観測カードに刷新
- [ ] `site/app.js`: `syncLifecycleTelemetry()` 実装、死んだ要素の更新コード排除と動的バインド

### (4) テスト ＆ 品質検証
- [ ] `tests/database/test_json_storage.py` [NEW]: JSON / JSONL ストレージエンジンの単体テスト
- [ ] `tests/pipeline/test_pipeline_state.py` [NEW]: パイプライン状態管理と `log.md` 自動生成のテスト
- [ ] `tests/web/test_zero_mock_integrity.py`: ライフサイクル新 UI のゼロモック・実データ保証テスト追加

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/228-implement-src-database-json-storage-and-pipeline-lifecycle-observability`

### Step 1: `src/database/storage/json_storage.py` の実装
- `JsonLinesStorage`: 追記 $O(1)$、行ロック（`fcntl.flock`）、アトミックリネーム（`.tmp` ➔ `os.replace`）。
- `JsonTableStorage`: インメモリ B-Tree / ハッシュインデックスによる主キーキャッシュ（$O(1)$ 検索）。
- `SQLExecutor` からのクエリ（SELECT / INSERT / UPDATE）およびトランザクション連携。

### Step 2: パイプライン状態管理の刷新 (`src/pipeline/pipeline_state.py`)
- `pipeline_runs`（実行日時、ステータス、処理件数、所要時間、カテゴリ）の記録。
- `processed_papers`（clean_id, arxiv_id, title, 日時, パス）のインデックス管理。
- 既存の `processed_papers.json` からの初回移行マイグレーションスクリプト。
- 実行コミット時の `outputs/log.md` 自動再生成（プロジェクション）。

### Step 3: Web ゲートウェイ `/api/system/lifecycle` の実装
- `src/database` から最新 5 件の実行履歴、30 日間 SLO 稼働率、連続成功ストリークを SQL で即時集計。
- 外部 API（arXiv API / RSS / CTI）の健全性ステータスを返却。
- 成果物完全性（OKF ファイル数、原本 PDF/テキスト数、5層サマリー最新日時）を返却。

### Step 4: `site/index.html` ＆ `site/app.js` の UI 刷新
- `systemTab` 内の Dead-End Ledger および Traversal Matrix を完全撤廃。
- 実運用 6 フェーズバー（収集 ➔ PDF抽出 ➔ OKF変換 ➔ 脅威分析 ➔ 知識蓄積 ➔ 5層サマリー）の導入。
- 4 大運用カード（運行スケジューラ、成果物ライフサイクル、外部通信健全性、SLA監査ログ台帳）の動的レンダリング。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/database` に `JsonTableStorage` / `JsonLinesStorage` が実装され、単体テストが 100% PASS すること。
- [ ] `processed_papers.json` (7.2MB) の全件メモリ展開が解消され、論文 ID の重複判定が $O(1)$（0.5ms 未満）で動作すること。
- [ ] パイプライン実行ログが `src/database` に記録され、`outputs/log.md`（直近 50 件）が自動生成されること。
- [ ] `site/index.html` の `systemTab` から未実装プレースホルダーおよびダミー固定値が全廃され、4 大運用カードに実態データが表示されること。
- [ ] `tests/web/test_zero_mock_integrity.py` を含む全テストが PASS すること。
- [ ] `make check_format` および `make static_analysis`（mypy --strict, xenon Rank A CC<=5）が 100% エラー 0 件で PASS すること。
