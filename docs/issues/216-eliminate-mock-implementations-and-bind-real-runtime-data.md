---
ID: 216
種別: Architecture / Refactor
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] index.html および Web ゲートウェイにおけるモック実装・ダミー固定値の完全排除と実態データ・実DB連携への全面刷新 (ID: 216)

## 1. 概要 / Summary

エンタープライズ統合コンソール (`site/index.html` / `site/app.js`) およびそのバックエンド Web ゲートウェイ (`src/web/gateway/handlers.py`) において、プロトタイプ開発期に導入されたハードコード値、架空テーブル定義、ダミーSQLクエリ、固定配列によるグラフ合成などの「モック実装」が複数領域に残存している。

システムが実稼働（Pure-Python Database Engine / MultiTableVectorStorage / PropertyGraphEngine / OTLP Traces / Real Crawlers）へと移行した現在、これら一切のモック実装・ダミー固定値を完全に特定・一覧化し、すべて実態ファイル、実コンテナ、実プロセス、実SQL実行結果へと置き換え、真の運用コンソールへと全面刷新する。

---

## 2. モック実装の網羅的一覧と特定 (Inventory of Mocks)

コードベースおよびフロントエンドの精査により特定されたモック・固定値の一覧は以下の通りである。

### Category A: データベース台帳 & SQLインスペクション
* **[M1] `graph_db` の架空テーブルハードコード** (`src/web/gateway/handlers.py` L1078-L1117):
  - `tbox_classes` (行数: 33 固定), `tbox_properties` (行数: 50 固定), `reified_claims` (行数: `e_count // 3`), `evidences` (行数: `e_count // 2`) が辞書リテラルでハードコードされている。
  - 実態: `outputs/database/knowledge_graph.vdb` に実在するテーブルは `vertices` と `edges` の2テーブルのみ。
* **[M2] `SHOW TABLES FROM <db>;` / `SHOW DATABASES;` の SQL 偽装** (`src/web/gateway/handlers.py` L951-L974, L1131-L1149, `src/analytics/storage.py`, `src/domain/security/cti/storage.py`):
  - 実際に SQL パーサー・エグゼキュータを実行せず、辞書リテラルで `"query": "SHOW TABLES FROM graph_db;"` とハードコードされたダミー配列をそのまま返却している。
* **[M3] `site/app.js` の KPI フォールバック値** (`site/app.js` L1014-L1026):
  - `read_iops || 3420`, `write_iops || 485`, `avg_latency_ms || 0.42`, `p99 || 2.8`, `wal_flush || 128.4`, `MVCC + SS2PL` などのダミー数値・文字列がフォールバックとして埋め込まれている。
* **[M4] 廃止された旧ストレージ構成への参照** (`src/web/gateway/handlers.py` L667-L671):
  - `_resolve_graph_file_size` にて、Issue #214 で `knowledge_graph.vdb` へ統合・廃止された旧 `vertices.vdb` / `edges.vdb` へのフォールバックが残存している。
* **[M5] データベース間でのテーブル重複・境界曖昧性** (`src/web/gateway/handlers.py` L980-L995):
  - `_collect_database_tables` にて、`arxiv_security_db` のテーブル台帳に `graph_db` の `vertices` / `edges` が `tables.extend(g_tables)` され混在している。

### Category B: 知識グラフ・トポロジーメッシュ
* **[M6] `MESH_DOMAIN_DEFINITIONS` による架空オントロジーメッシュ合成** (`src/web/gateway/handlers.py` L180-L356):
  - `/api/graph/mesh` において、`PropertyGraphEngine`（`knowledge_graph.vdb`）の実データをクエリせず、Python 側でハードコードされた `MESH_DOMAIN_DEFINITIONS` のキーワード一覧から `ent_os_hardware`, `clm_memory_side_channel`, `dec_sandboxing_aslr` 等の固定ノード・エッジを合成している。
  - 実態: `knowledge_graph.vdb` には既に 194 vertices, 233 edges（実論文・エンティティ・因果関係）が蓄積されており、実データを直接描画すべきである。
* **[M7] `site/app.js` の Hop Budget ヒストグラムのダミーフォールバック** (`site/app.js` L853-L860):
  - グラフ探索結果が空の場合に `hopCounts = [18, 42, 68, 34, 12]` という固定ダミー値を描画している。

### Category C: システム観測・プロダクト分析 (Traversal / ROI / SLO)
* **[M8] `renderTraversalMatrix` の 100 ドット固定判定** (`site/app.js` L966-L979):
  - `for (let i = 0; i < 100; i++) { if (i < 88) dot.classList.add('success'); else dot.classList.add('deadend'); }`
  - 常に 88% 成功 / 12% デッドエンドを固定描画しており、実ランダムウォーク結果や実グラフ探索ログに基づかない完全なモックである。
* **[M9] `walkHistory` の固定配列** (`site/app.js` L811):
  - `const walkHistory = [74.2, 74.2, 74.2, 74.2, 74.2, 74.2, 74.2, 74.2];` という固定値でグラフが初期描画されている。
* **[M10] `_introspect_strategic_metrics` の固定値フォールバック** (`src/web/gateway/handlers.py` L606-L631):
  - `"token_savings_pct": data.get("token_savings_pct") or "-74.2%"`
  - `"uptime_target": "99.9% 4x Daily SLA"`
  - `"pipeline_slo_pct": 100.0`
* **[M11] `site/index.html` 内の静的テキスト固定値** (`site/index.html` L879):
  - `14,169件のセキュリティ論文` などの静的ハードコード（実件数 API `/api/stats` と非連動）。

### Category D: パイプライン・スケジューラー監視
* **[M12] `_compute_loop_timestamps` の擬似タイムスタンプ計算** (`src/web/gateway/handlers.py` L1656-L1668):
  - 現在時刻から `((h // 6) + 1) * 6 % 24` で次回実行時刻を数学的に擬似算出しているだけで、実際のスケジューラー（cron / timer）や最後のバッチ実行ログ（`outputs/log.md`）と非連動。

---

## 3. トレーサビリティ / Traceability
- [AGENTS.md](../../.agents/AGENTS.md):
  - 「Section 1: Governance & PM-Led Multi-Agent Framework (AU システム監査員による実証性検証)」
  - 「Section 6: Raw Data Preservation & Idempotency Rules」
- [DSN-05-database_engine_architecture.md](../designs/DSN-05-database_engine_architecture.md): Chapter 19 (OKFMTC01 Multi-Table Container & PEP 249 Driver)
- [DSN-21-graph_and_system_dashboard.md](../designs/DSN-21-graph_and_system_dashboard.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (全モック関数・固定辞書の撤廃と実コンテナ・実エンジン連携)
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py) (実クエリ実行・実テーブルメタデータ返却)
- [ ] [site/app.js](../../site/app.js) (固定配列・モックドット生成・ハードコードフォールバックの撤廃)
- [ ] [site/index.html](../../site/index.html) (静的テキストの動的プレースホルダー化)
- [ ] [tests/web/test_zero_mock_integrity.py](../../tests/web/test_zero_mock_integrity.py) (全エンドポイントのモック排除・実データ整合性検証テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `refactor/216-eliminate-mock-implementations-and-bind-real-runtime-data`

### Phase 1: データベース台帳 & SQLインスペクションのモック撤廃 (Category A)
1. `src/web/gateway/handlers.py`:
   - `_introspect_graph_database()` から `tbox_classes`, `tbox_properties`, `reified_claims`, `evidences` を完全削除。
   - `_resolve_graph_file_size()` から旧 `vertices.vdb`, `edges.vdb` へのフォールバックを撤廃。
   - `_collect_database_tables()` での `arxiv_security_db` と `graph_db` のテーブル重複を解消。
2. `src/database/sql/executor.py`:
   - `SHOW DATABASES` および `SHOW TABLES FROM <db>` を実コンテナ（`knowledge_graph.vdb` 等）をロードして動的に解決し、実クエリ結果を返却。
3. `site/app.js`:
   - ダミーフォールバック値（`3420 IOPS`, `0.42 ms` 等）を削除し、未取得時は `--` 表示とする。

### Phase 2: グラフメッシュのモック撤廃 (Category B)
1. `src/web/gateway/handlers.py`:
   - `MESH_DOMAIN_DEFINITIONS` および `_build_dynamic_paper_mesh()` のキーワードモック合成を廃止。
   - `/api/graph/mesh` において `PropertyGraphEngine` を実体化し、`knowledge_graph.vdb` から実ノードおよび実エッジ（ABox / TBox / 因果関係）を直接取得して返却。
2. `site/app.js`:
   - `hopCounts = [18, 42, 68, 34, 12]` のダミー配列を削除し、実際のノード・エッジ隣接リストから計算された実測値のみを描画。

### Phase 3: システム観測・プロダクト分析のモック撤廃 (Category C)
1. `site/app.js`:
   - `renderTraversalMatrix()` の 88/12 固定ドット生成を廃止。実グラフ探索ログ（またはエージェントの検証結果）から動的に算出・描画。
   - `walkHistory` の初期配列 `[74.2, ...]` を空または実ログ読み込み値に変更。
2. `src/web/gateway/handlers.py`:
   - `_introspect_strategic_metrics()` の `-74.2%` 等のハードコードフォールバックを排除。未計測時は `0.0` または `N/A` を返却。
3. `site/index.html`:
   - `14,169件` などのハードコード静的数値を削除し、`/api/stats` から取得した実件数をバインド。

### Phase 4: パイプライン監視のモック撤廃 (Category D)
1. `src/web/gateway/handlers.py`:
   - `_compute_loop_timestamps()` の時計計算モックを改修し、実際に `outputs/log.md` または `outputs/wal/` のタイムスタンプから最終実行時刻を取得。次回予定はスケジューラー定義に基づいて算出。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] [M1]〜[M12] で特定された全てのモック・固定値・ダミー配列・偽装クエリがコードベースから完全撤廃されていること。
- [ ] `http://localhost:8000/index.html` の全タブ（Search, Graph, Database, System, Supervisor）に表示されるデータが、ディスク上の実ファイル・実コンテナ・実プロセス・実SQL実行結果と 100% 一致していること。
- [ ] `site/app.js` および `handlers.py` にハードコードされたダミーフォールバック値（IOPS, レイテンシ, ドット数, ノード配列）が存在しないこと。
- [ ] `tests/web/test_zero_mock_integrity.py` を新規作成し、全APIエンドポイントにおいてモックデータが返却されていないことを自動テストで検証できること。
- [ ] `make check_format` および `make static_analysis` (CC <= 5 / Xenon Grade A) が 100% PASS すること。
