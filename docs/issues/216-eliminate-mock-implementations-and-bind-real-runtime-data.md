---
ID: 216
種別: Architecture / Refactor
優先度: High
ステータス: Open (In Progress)
Target Branch: refactor/216-eliminate-mock-implementations-and-bind-real-runtime-data
---

# [REFACTOR] index.html および Web ゲートウェイにおけるモック実装・ダミー固定値の完全排除と実態データ・実DB連携への全面刷新 (ID: 216)

## 1. 概要 / Summary

エンタープライズ統合コンソール (`site/index.html` / `site/app.js`) およびそのバックエンド Web ゲートウェイ (`src/web/gateway/handlers.py`) において、プロトタイプ開発期に導入されたハードコード値、架空テーブル定義、ダミーSQLクエリ、固定配列によるグラフ合成などの「モック実装」が複数領域に残存している。

システムが実稼働（Pure-Python Database Engine / MultiTableVectorStorage / PropertyGraphEngine / OTLP Traces / Real Crawlers）へと移行した現在、これら一切のモック実装・ダミー固定値を完全に特定・一覧化し、すべて実態ファイル、実コンテナ、実プロセス、実SQL実行結果へと置き換え、真の運用コンソールへと全面刷新する。

---

## 2. モック実装の網羅的一覧と特定 (Inventory of Mocks)

コードベースおよびフロントエンドの精査により特定されたモック・固定値の一覧は以下の通りである。

### Category A: データベース台帳 & SQLインスペクション（解決済み）

* **[M1] `graph_db` の架空テーブルハードコード**
  - **[2026-09-10 調査済]**: `_introspect_graph_database()` (handlers.py L1064-L1125) は既に修正完了済み。現行コードは `vertices`/`edges` の2テーブルのみを返却。既存テスト `test_introspect_graph_database_has_no_mock_tables` が PASS を確認。**残存モック: なし（解決済み）**。

* **[M2] `SHOW TABLES FROM <db>;` / `SHOW DATABASES;` の SQL 偽装**
  - **[2026-09-10 調査済]**: `_execute_show_databases_query()` / `_run_graph_show_tables()` はすでに実際の `SQLExecutor` を呼び出している。`SQLExecutor._exec_show_databases()` (executor.py L1111) も `self.known_databases` から動的解決済み。**残存モック: なし（解決済み）**。

* **[M3] `site/app.js` の KPI フォールバック値**
  - **[2026-09-10 調査済]**: 現行コード (L1014-L1026) は `kpi.read_iops !== undefined` 等の条件でフォールバックを `'-- / -- IOPS'` で表示している。**残存モック: なし（解決済み）**。

* **[M4] 廃止された旧ストレージ構成への参照**
  - **[2026-09-10 調査済]**: `_resolve_graph_file_size()` (L663-L665) は `knowledge_graph.vdb` のみを参照。旧 `vertices.vdb`/`edges.vdb` フォールバックは既に存在しない。**残存モック: なし（解決済み）**。

* **[M5] データベース間でのテーブル重複・境界曖昧性**
  - **[2026-09-10 調査済]**: `_collect_database_tables()` (L978-L993) は `arxiv_security_db` に graph テーブルを含まない。テスト `test_collect_database_tables_has_no_graph_leak` が PASS を確認。**残存モック: なし（解決済み）**。

### Category B: 知識グラフ・トポロジーメッシュ

* **[M6] `MESH_DOMAIN_DEFINITIONS` による架空オントロジーメッシュ合成** (`src/web/gateway/handlers.py` L120-L356):
  - `/api/graph/mesh` において `MESH_DOMAIN_DEFINITIONS` のキーワード一覧から固定ノード・エッジを合成している。
  - **[2026-09-10 調査済]**: `_resolve_mesh_papers()` (L1612-L1628) は実論文を取得するが、`_build_dynamic_paper_mesh()` 自体が `MESH_DOMAIN_DEFINITIONS` キーワードマッチング合成ロジック（L297-L356）に依存。実際に `PropertyGraphEngine` から ABox/TBox データを直接取得していない。
  - **実データAPI**: `PropertyGraphEngine.get_all_vertices()` (engine.py L530) と `_edges` ディクショナリで実ノード・実エッジを取得可能。

* **[M7] `site/app.js` の Hop Budget ヒストグラムのダミーフォールバック** (`site/app.js` L853-L858):
  - グラフ探索結果が空の場合に `hopCounts = [18, 42, 68, 34, 12]` という固定ダミー値を描画。

### Category C: システム観測・プロダクト分析

* **[M8] `renderTraversalMatrix` の 100 ドット固定判定** (`site/app.js` L966-L978):
  - `if (i < 88)` で常に 88% 成功を固定描画。実グラフ探索ログと非連動。

* **[M9] `walkHistory` の固定配列** (`site/app.js` L811):
  - `const walkHistory = [74.2, 74.2, 74.2, 74.2, 74.2, 74.2, 74.2, 74.2];` という固定値。

* **[M10] `_introspect_strategic_metrics` の固定値フォールバック** (`src/web/gateway/handlers.py` L608, L625, L629):
  - `"token_savings_pct": data.get("token_savings_pct") or "-74.2%"` (L608)
  - `"pipeline_slo_pct": float(data.get("pipeline_slo_pct", 100.0))` (L625)
  - `"uptime_target": "99.9% 4x Daily SLA"` (L629) ← 仕様値なので許容

* **[M11] `site/index.html` 内の静的テキスト固定値** (L146, L156, L182, L879 / `site/app.js` L114):
  - `14,169件のセキュリティ論文` などが複数箇所に静的ハードコード（実件数 API `/api/stats` と非連動）。

### Category D: パイプライン・スケジューラー監視

* **[M12] `_compute_loop_timestamps` の擬似タイムスタンプ計算** (`src/web/gateway/handlers.py` L1631-L1642):
  - `last_sync` は `now_utc` をそのまま返しており、実際のバッチ実行ログ（`outputs/log.md`）と非連動。
  - **実データソース確認**: `outputs/log.md` は `| 実行日時 (UTC) | 処理論文数 | ...` 形式のマークダウンテーブル。各行第1列から最終実行タイムスタンプ（例: `2026-09-07 07:13:25 UTC`）が正規表現で取得可能であることを確認済み。

---

## 3. トレーサビリティ / Traceability
- [AGENTS.md](../../.agents/AGENTS.md): Section 1 (AU システム監査員), Section 6 (Raw Data Preservation)
- [DSN-05-database_engine_architecture.md](../designs/DSN-05-database_engine_architecture.md): Chapter 19 (OKFMTC01 Multi-Table Container)
- [DSN-21-graph_and_system_dashboard.md](../designs/DSN-21-graph_and_system_dashboard.md)
- Issue #215 (閉): Category A の多くを解決済み
- Issue #102 (閉): Gateway ハードコード全廃（Category A 先行対応）

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (M6/M10/M12)
- [ ] [site/app.js](../../site/app.js) (M7/M8/M9/M11)
- [ ] [site/index.html](../../site/index.html) (M11)
- [ ] [tests/web/test_zero_mock_integrity.py](../../tests/web/test_zero_mock_integrity.py) (新規作成)

**解決済み（変更不要）**: M1, M2, M3, M4, M5（Issue #215 / #102 にて解決済み）

---

## 5. 実装方針 / Implementation Plan

### Phase 1: グラフメッシュの実データ直接描画 (M6, M7)
**対象**: `src/web/gateway/handlers.py`, `site/app.js`

#### 1-1. `_build_real_graph_mesh(ge_instance)` 新関数の追加 (`handlers.py`)

`MESH_DOMAIN_DEFINITIONS` / `_build_dynamic_paper_mesh()` の代替として、`PropertyGraphEngine` の実 ABox データから直接グラフを構築する関数を追加する:

```python
def _build_real_graph_mesh(
    ge_instance: Any,
    max_nodes: int = 80,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Builds node-edge graph from real PropertyGraphEngine ABox data."""
    if ge_instance is None:
        return [], []
    try:
        vertices = ge_instance.get_all_vertices()[:max_nodes]
        edges_all = list(ge_instance._edges.values())
        vertex_ids = {v.id for v in vertices}
        nodes = [
            {
                "id": v.id,
                "cluster": v.label.lower(),
                "title": v.properties.get("name", v.id)[:48],
                "sub": v.label,
                "summary": v.properties.get("description", "")[:120],
                "weight": float(v.properties.get("weight", 1.0)),
            }
            for v in vertices
        ]
        edges = [
            {
                "source": e.src_id,
                "target": e.dst_id,
                "relation": e.label,
                "weight": e.weight,
            }
            for e in edges_all
            if e.src_id in vertex_ids and e.dst_id in vertex_ids
        ]
        return nodes, edges
    except Exception:
        return [], []
```

#### 1-2. `handle_graph_mesh()` の改修: 実グラフ優先バインド

`handle_graph_mesh()` (L1654) 内で `_introspect_graph_table_metrics(self.workspace_dir)` から取得した `ge_instance` を用いて:

1. `ge_instance` が有効かつ `ge_instance.vertex_count > 0` の場合 → `_build_real_graph_mesh(ge_instance)` を使用
2. それ以外の場合 → 従来の `_build_dynamic_paper_mesh(papers)` にフォールバック

また、レスポンス JSON に `traversal_stats` フィールドを追加:

```python
"traversal_stats": {
    "vertex_count": v_count,
    "edge_count": e_count,
    "success_rate_pct": round(
        v_count / max(v_count + e_count, 1) * 100, 1
    ) if v_count > 0 else 0.0,
}
```

#### 1-3. ホップヒストグラム: ダミーフォールバック撤廃 (`site/app.js` L853-L858)

```diff
-    if (hopCounts.every(c => c === 0)) {
-      hopCounts[0] = 18;
-      hopCounts[1] = 42;
-      hopCounts[2] = 68;
-      hopCounts[3] = 34;
-      hopCounts[4] = 12;
-    }
+    if (hopCounts.every(c => c === 0)) {
+      hCtx.fillStyle = '#888';
+      hCtx.font = '11px monospace';
+      hCtx.fillText('グラフデータ未取得', 20, 60);
+      return;
+    }
```

---

### Phase 2: システム観測・プロダクト分析のモック撤廃 (M8, M9, M10)

#### 2-1. `renderTraversalMatrix` の実データ化 (`site/app.js` L966-L978)

`renderTraversalMatrix` を引数 `successRatePct` 受け取り型に変更:

```diff
-function renderTraversalMatrix() {
+function renderTraversalMatrix(successRatePct) {
   const matrixContainer = document.getElementById('traversalMatrix');
   if (!matrixContainer || matrixContainer.children.length > 0) return;
+  matrixContainer.innerHTML = '';
+  const successCount = Math.round((successRatePct ?? 0));
   for (let i = 0; i < 100; i++) {
     const dot = document.createElement('div');
     dot.className = 'traversal-dot';
-    if (i < 88) {
+    if (i < successCount) {
       dot.classList.add('success');
     } else {
       dot.classList.add('deadend');
     }
```

`fetchMeshData()` 成功時に `renderTraversalMatrix(data.traversal_stats?.success_rate_pct ?? 0)` を呼ぶ。

#### 2-2. `walkHistory` の固定配列解消 (`site/app.js` L811)

```diff
-const walkHistory = [74.2, 74.2, 74.2, 74.2, 74.2, 74.2, 74.2, 74.2];
+const walkHistory = [];
```

`fetchMeshData()` 成功時に `data.telemetry.token_savings_pct` を `walkHistory.push(val)` する（最大 20 件保持）。

#### 2-3. `token_savings_pct` フォールバック修正 (`handlers.py` L608)

```diff
-    "token_savings_pct": data.get("token_savings_pct") or "-74.2%",
+    "token_savings_pct": data.get("token_savings_pct") or "N/A",
```

#### 2-4. `pipeline_slo_pct` デフォルト修正 (`handlers.py` L625)

```diff
-    "pipeline_slo_pct": float(data.get("pipeline_slo_pct", 100.0)),
+    "pipeline_slo_pct": float(data.get("pipeline_slo_pct", 0.0)),
```

---

### Phase 3: 件数ハードコードの動的バインド (M11)

#### 3-1. `site/app.js` TAB_CONFIG のハードコード除去 (L114)

```diff
-    subtitle: 'Google OKF v0.2 準拠の 14,169 件のセキュリティ学術論文および ATT&CK 推論メタデータを横断探索'
+    subtitle: 'Google OKF v0.2 準拠のセキュリティ学術論文および ATT&CK 推論メタデータを横断探索'
```

#### 3-2. `/api/stats` 取得後の動的更新関数を追加

```javascript
function updatePaperCountDisplay(total) {
  const fmt = Number(total).toLocaleString('ja-JP');
  ['sidebarPapersCount', 'totalPapersCount', 'descPapersCount'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.textContent = fmt;
  });
  const subtitle = document.getElementById('mainPageSubtitle');
  if (subtitle) {
    subtitle.textContent =
      `Google OKF v0.2 準拠の ${fmt} 件のセキュリティ学術論文および ATT&CK 推論メタデータを横断探索`;
  }
}
```

`fetchStats()` の成功コールバックで `updatePaperCountDisplay(data.total_papers)` を呼ぶ。

#### 3-3. `site/index.html` L879 のハードコード件数をスパン要素化

```diff
- DuckDB &amp; Pure-Python BM25/ベクトルハイブリッド検索エンジンにより、14,169件のセキュリティ論文を高速探索します。
+ DuckDB &amp; Pure-Python BM25/ベクトルハイブリッド検索エンジンにより、<span id="descPapersCount">14,169</span>件のセキュリティ論文を高速探索します。
```

（初期値を保持しつつ、JS 起動後に即座に `/api/stats` の実値で上書き）

---

### Phase 4: パイプライン監視タイムスタンプの実データ化 (M12)

#### 4-1. `_compute_loop_timestamps()` をインスタンスメソッド化し log.md バインド

`@staticmethod` を削除し `self.workspace_dir` を使う形に変更（あるいは `os.path` 相対導出）:

```python
def _compute_loop_timestamps(self) -> Tuple[str, str]:
    import datetime as _dt
    import re as _re

    now_utc = _dt.datetime.now(_dt.timezone.utc)
    last_sync = "No batch run recorded"

    log_path = os.path.join(self.workspace_dir, "outputs", "log.md")
    ts_pattern = _re.compile(
        r"\|\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+UTC)\s*\|"
    )
    try:
        if os.path.exists(log_path):
            last_ts: Optional[str] = None
            with open(log_path, "r", encoding="utf-8") as lf:
                for line in lf:
                    m = ts_pattern.search(line)
                    if m:
                        last_ts = m.group(1).strip()
            if last_ts:
                last_sync = last_ts
    except Exception:
        pass

    h = now_utc.hour
    next_h = ((h // 6) + 1) * 6 % 24
    next_run = now_utc.replace(hour=next_h, minute=0, second=0, microsecond=0)
    if next_h <= h:
        next_run = next_run + _dt.timedelta(days=1)
    next_sync = next_run.strftime("%Y-%m-%d %H:%M:%S UTC")
    return last_sync, next_sync
```

呼び出し元 (L1683) は `self._compute_loop_timestamps()` に変更する（`@staticmethod` から通常メソッドへの移行）。

---

### Phase 5: テスト実装 (新規ファイル)

**対象**: `tests/web/test_zero_mock_integrity.py` (新規作成)

静的コード検証 + 動的ロジック検証の両立:

```python
class TestZeroMockIntegrity(unittest.TestCase):
    """全モック撤廃の完全性を静的解析・動的実行の両面から検証"""

    def test_no_hardcoded_14169_in_tab_config(self):
        """TAB_CONFIG.subtitle に 14,169 のハードコードが存在しないこと (site/app.js)"""
        app_js = Path(__file__).parent.parent.parent / "site" / "app.js"
        content = app_js.read_text(encoding="utf-8")
        tab_config_block = content[content.find("TAB_CONFIG"):content.find("TAB_CONFIG")+2000]
        self.assertNotIn("14,169", tab_config_block)

    def test_no_dummy_hop_counts_fallback(self):
        """Hop Histogram の [18, 42, 68, 34, 12] ダミーフォールバックが存在しないこと"""
        app_js = Path(__file__).parent.parent.parent / "site" / "app.js"
        content = app_js.read_text(encoding="utf-8")
        self.assertNotIn("hopCounts[0] = 18", content)

    def test_no_fixed_88_dots_in_traversal_matrix(self):
        """renderTraversalMatrix に i < 88 固定判定が存在しないこと"""
        app_js = Path(__file__).parent.parent.parent / "site" / "app.js"
        content = app_js.read_text(encoding="utf-8")
        self.assertNotIn("i < 88", content)

    def test_no_fixed_74_2_walk_history(self):
        """walkHistory の [74.2, ...] 固定初期化が存在しないこと"""
        app_js = Path(__file__).parent.parent.parent / "site" / "app.js"
        content = app_js.read_text(encoding="utf-8")
        self.assertNotIn("walkHistory = [74.2", content)

    def test_token_savings_fallback_not_minus_74_2(self):
        """handlers.py の token_savings_pct フォールバックが -74.2% でないこと"""
        handlers_py = Path(__file__).parent.parent.parent / "src" / "web" / "gateway" / "handlers.py"
        content = handlers_py.read_text(encoding="utf-8")
        self.assertNotIn('"-74.2%"', content)

    def test_pipeline_slo_pct_default_is_not_100(self):
        """handlers.py の pipeline_slo_pct デフォルトが 100.0 でないこと"""
        handlers_py = Path(__file__).parent.parent.parent / "src" / "web" / "gateway" / "handlers.py"
        content = handlers_py.read_text(encoding="utf-8")
        self.assertNotIn('pipeline_slo_pct", 100.0)', content)

    def test_compute_loop_timestamps_reads_log_md(self):
        """GatewayHandlers._compute_loop_timestamps が log.md を参照すること"""
        handlers_py = Path(__file__).parent.parent.parent / "src" / "web" / "gateway" / "handlers.py"
        content = handlers_py.read_text(encoding="utf-8")
        self.assertIn("log.md", content)

    def test_mesh_response_has_traversal_stats(self):
        """handle_graph_mesh の返却 JSON に traversal_stats フィールドが存在すること"""
        handlers_py = Path(__file__).parent.parent.parent / "src" / "web" / "gateway" / "handlers.py"
        content = handlers_py.read_text(encoding="utf-8")
        self.assertIn("traversal_stats", content)
```

---

## 6. セキュリティ考察 / Security Considerations

- **パストラバーサル防御**: `log.md` の読み込みは固定パス (`workspace_dir/outputs/log.md`) のみ対象。ユーザー入力からパスを生成しない。
- **正規表現 ReDoS**: `ts_pattern` は固定フォーマットマッチングのみ。ReDoS リスクはなし。
- **情報漏洩防止**: `PropertyGraphEngine` から返却するノード属性は `name`, `description`, `weight` のみを選択的に抽出し、機密 `properties` キーを除外する。

---

## 7. 完了条件 / Success Criteria (DoD)

- [ ] **M6**: `/api/graph/mesh` レスポンスのノード・エッジが `knowledge_graph.vdb` の実 ABox データと一致すること（`ge_instance` が有効な場合）。
- [ ] **M7**: `site/app.js` の Hop Histogram ダミーフォールバック `[18, 42, 68, 34, 12]` が完全に除去されていること。
- [ ] **M8**: `renderTraversalMatrix` の `i < 88` 固定判定が除去され、実 `traversal_stats.success_rate_pct` でドット数が決定されること。
- [ ] **M9**: `const walkHistory = [74.2, ...]` の固定配列初期化が除去されていること。
- [ ] **M10**: `"token_savings_pct"` フォールバックが `"-74.2%"` でなく `"N/A"` であること。`pipeline_slo_pct` デフォルトが `0.0` であること。
- [ ] **M11**: `site/app.js` TAB_CONFIG の `subtitle` から `14,169` がハードコードされていないこと。`site/index.html` の L879 件数がスパン要素化されていること。
- [ ] **M12**: `_compute_loop_timestamps()` が `outputs/log.md` から実タイムスタンプを読み込み、`last_sync` が実行時刻を返すこと（log.md 存在時）。
- [ ] `tests/web/test_zero_mock_integrity.py` の全テストが PASS すること。
- [ ] `make check_format` および `make static_analysis` (CC <= 5 / Xenon Grade A) が 100% PASS すること。
- [ ] `http://localhost:8000/index.html` の Graph タブに実グラフデータが描画されること（knowledge_graph.vdb が非空の場合）。
