---
ID: 213
種別: Feature
優先度: High
ステータス: Closed (Completed)
担当エージェント: Systems Architect / Database Specialist / PM
---

# [FEAT] src/graph の永続化・クエリバックエンドへの src/database (自作DB基盤) 統合 & graph.db 完全廃止 (ID: 213)

## 1. 概要 / Summary

現在、`src/graph`（`PropertyGraphEngine`）は永続化ストレージとして `outputs/database/graph/graph.db` という拡張子 `.db` のファイルパスを使用していたが、実体は単一の巨大な JSON ファイル（約17MB）であり、メモリ内の Python 辞書上に全データを展開して保持していた。

システム内にはすでにゼロ外部依存・純粋 Python 実装のハイブリッドデータベース基盤（`src/database/` / DSN-14: `VectorStorage`, `SQLExecutor`, `TableCatalog`, 4KB スロッテッドページ、Pager/WAL/ARIES クラッシュ復旧、B+Tree）が確立されている。
ユーザーの厳格な制約方針「`sqlite3` は使わず、`src/database` を使う」に基づき、標準ライブラリ `sqlite3` を一切排除し、純粋な `src/database` コアストレージ（`VectorStorage`）および SQL 実行エンジン（`SQLExecutor`）を `src/graph` の一次ストレージ基盤として完全統合した。

本改修では、以下のアーキテクチャ刷新を実施した：
1. **純粋な `src/database` バックエンド採用（`sqlite3` 完全不使用）**:
   - `PropertyGraphEngine` のストレージバックエンドとして `src/database/storage/storage.py`（`VectorStorage`）および `src/database/sql/executor.py`（`SQLExecutor` / `TableCatalog`）を直接統合。
   - 永続化ファイル: `outputs/database/vertices.vdb`（頂点）および `outputs/database/edges.vdb`（有向辺）。
   - `execute_sql(sql, role)` メソッドにより、純粋 Python 実装の SQL クエリ実行（AST パース・テーブルスキャン）を透過提供。
2. **テーブル設計（ドメイン分離 & 2元テーブル）**:
   - `papers` や `cti_catalog` 等の既存テーブルとは明確にドメインを分離し、グラフ専用の `vertices`（頂点）および `edges`（有向辺・因果トリプル）テーブルを定義・管理。
3. **`graph.db` のマイグレーションと完全廃止**:
   - 旧 JSON 形式 `outputs/database/graph/graph.db`（16,272頂点, 3,183辺）の内容を新 `.vdb` ストレージへ安全移行完了後、旧 `graph.db` ファイルを完全削除。
   - `src/graph/`、`src/web/gateway/handlers.py`、`scripts/` から旧 `graph.db` へのフォールバックやパス参照を完全撤廃。
4. **`dashboard.html` / Web ゲートウェイからの `graph.db` 削除**:
   - `handlers.py` の `_introspect_graph_database` 等にハードコードされた `outputs/database/graph/graph.db` を削除し、新 DB（`vertices.vdb`, `edges.vdb`）および `vertices` / `edges` テーブルのライブメトリクスを正確に返却。
5. **後方互換性コードの排除**:
   - レガシーな JSON 読み書き処理（`json.dump` / `json.load`）や判定ロジック等の互換レイヤーはコードベースに残さず、クリーンに `src/database` ベースに一本化。
6. **インデックス再構築コマンドの特定**:
   - OKF 論文群からいつでもグラフ DB をゼロから再構築できるコマンド群（`make build_knowledge_graph`、`scripts/seed_ontologies.py` 等）を特定・確立。
7. **インメモリモード (`:memory:`) 完全対応**:
   - `:memory:` 指定時は `VectorStorage(file_path=":memory:")` と連携し、テスト実行時や探索セッションにおいてディスク I/O ゼロの完全インメモリグラフ実行を保証。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 Graph Engineering Dashboard (Context Mesh) & Live Loop Observability 包括的アーキテクチャ設計書](../designs/DSN-14-graph_engineering_dashboard.md) (Section 1.1 全体アーキテクチャ, Section 11 `/dashboard` インタラクティブ可視化仕様)
- 設計書: [DSN-05 データベースエンジンアーキテクチャ設計書](../designs/DSN-05-database_engine_architecture.md)
- 設計書: [DSN-14 ゼロ外部依存・純粋Python SQLite互換＆分散ベクトルデータベース基盤包括的アーキテクチャ設計書](../designs/DSN-14-pure_python_sqlite_and_distributed_vector_db.md)
- 設計書: [DSN-18 プロパティグラフデータベースエンジン設計書](../designs/DSN-18-property_graph_database_engine.md)
- 関連コンポーネント:
  - `src/graph/engine.py` (`PropertyGraphEngine`)
  - `src/graph/structures.py` (`Vertex`, `Edge`)
  - `src/graph/cli.py` (`build`, `show`, `query`)
  - `src/database/compat/sqlite_engine.py` (`get_sqlite_connection`)
  - `src/web/gateway/handlers.py` (`_introspect_graph_database`, `_introspect_graph_table_metrics`, `handle_cti_graph_mesh`, `handle_graph_query`)
  - `site/dashboard.html` (Database Explorer, CTI Graph, Schema View)

---

## 3. セキュリティ & 脅威モデル分析 / Security & Threat Modeling

| 脅威 / 脆弱性 (STRIDE) | リスク評価 | 対策と実装方針 |
| :--- | :--- | :--- |
| **SQL インジェクション (Tampering)** | High | 頂点・辺の属性、ID、ラベルの登録・更新・検索において、文字列連結による SQL 構築を一切禁止し、必ずプレースホルダー（`?` パラメータバインディング）を用いたプリペアドステートメントを使用する。 |
| **パストラバーサル (Information Disclosure / Tampering)** | Medium | `storage_path` 引数に対して `is_safe_workspace_path` による境界チェックを実施し、ワークスペース外や任意ディレクトリへの SQLite ファイル生成・アクセスを拒絶する（`:memory:` 指定は例外許可）。 |
| **巨大トランザクションによるリソース枯渇 / DoS (Denial of Service)** | Medium | 全量保存・バッチインサート時は `executemany` および適切なチャンクサイズ（例: 1,000件単位のトランザクション制御）を用い、メモリ圧迫と WAL 肥大化を抑制する。 |
| **破損・不正データ注入 (Tampering)** | Low | `properties` カラムに格納する JSON 属性は、ロード時に例外安全な JSON パースを行い、破損行が存在してもエンジン全体のクラッシュを防止する。 |

---

## 4. グラフ・インデックス再構築コマンド仕様 / Rebuild Commands Specification

後方互換性を排除し新規データベーススキーマに移行した後、データを全量再構築するための標準コマンドは以下の通り特定される：

| 目的 | Makefile コマンド | 直接実行コマンド (CLI) | 処理内容 |
| :--- | :--- | :--- | :--- |
| **① ナレッジグラフ全量構築** | `make build_knowledge_graph` | `PYTHONPATH=src .venv/bin/python -m graph.cli build` | `outputs/okf_papers/` 配下の全 OKF 論文からエンティティ・トリプルを抽出し、リレーショナル DB（`knowledge_graph.sqlite`）へ永続化 |
| **② オントロジーシード投入** | — | `PYTHONPATH=src .venv/bin/python scripts/seed_ontologies.py --ingest-papers` | MITRE ATT&CK / CWE のマスターオントロジーおよび OKF 論文をグラフ DB へシード投入 |
| **③ CTI バックフィル & グラフ同期** | `make reannotate_cti` | `PYTHONPATH=src .venv/bin/python src/pipeline/cti_backfill.py` | EIROM 推論ルールに基づき CTI テクニックと緩和策を OKF 論文に刻印し、グラフ DB へ双方向同期 |
| **④ グラフ統計情報の確認** | `make graph_stats` | `PYTHONPATH=src .venv/bin/python -m graph.cli show` | 構築されたリレーショナルグラフ DB の頂点数、エッジ数、ラベル別内訳を表示 |

---

## 5. テーブル定義詳細 / Detailed Schema Design

データベースファイル: `outputs/database/graph/knowledge_graph.sqlite`（または `:memory:`）

### ① `vertices` テーブル（頂点ストア）
```sql
CREATE TABLE IF NOT EXISTS vertices (
    id TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    name TEXT,
    properties TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_vertices_label ON vertices(label);
```

### ② `edges` テーブル（有向辺・因果トリプルストア）
```sql
CREATE TABLE IF NOT EXISTS edges (
    id TEXT PRIMARY KEY,
    src_id TEXT NOT NULL,
    dst_id TEXT NOT NULL,
    label TEXT NOT NULL,
    confidence REAL DEFAULT 1.0,
    weight REAL DEFAULT 1.0,
    properties TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_edges_src ON edges(src_id);
CREATE INDEX IF NOT EXISTS idx_edges_dst ON edges(dst_id);
CREATE INDEX IF NOT EXISTS idx_edges_label ON edges(label);
CREATE INDEX IF NOT EXISTS idx_edges_composite ON edges(src_id, label, dst_id);
```

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/213-integrate-database-engine-into-graph-subsystem`

### Step 1: `src/graph/structures.py` の DB マッピングメソッド拡充
- `Vertex`:
  - `to_db_tuple() -> Tuple[str, str, str, str]`: `(id, label, name, json.dumps(properties))`
  - `@classmethod from_db_row(cls, row: Tuple[Any, ...]) -> Vertex`
- `Edge`:
  - `to_db_tuple() -> Tuple[str, str, str, str, float, float, str]`: `(id, src_id, dst_id, label, confidence, weight, json.dumps(properties))`
  - `@classmethod from_db_row(cls, row: Tuple[Any, ...]) -> Edge`

### Step 2: `src/graph/engine.py` のリレーショナル DB 化 & JSON 廃止
- `_determine_graph_storage_path`:
  - デフォルトパスを `outputs/database/graph/knowledge_graph.sqlite` に変更。
  - レガシーパス（`graph.db`）の存在判定・フォールバックを完全撤廃。
- `PropertyGraphEngine.__init__`:
  - `self.storage_path = _determine_graph_storage_path(...)`
  - `self._conn = get_sqlite_connection(self.storage_path, init_schema=False)` を取得。
  - `self._init_db_schema()`: `vertices` と `edges` テーブルおよびインデックスを作成。
- `load(self, filepath=None)`:
  - リレーショナル DB から `SELECT * FROM vertices` および `SELECT * FROM edges` を実行。
  - メモリ内の Dual CSR（`_vertices`, `_edges`, `_out_edges`, `_in_edges`）を即座に復元。
- `save(self, filepath=None)`:
  - トランザクション内で `DELETE FROM vertices`, `DELETE FROM edges` を実行。
  - `executemany` で全頂点・全辺を一括 `INSERT`。
  - JSON ファイル出力処理（`json.dump`）を完全削除。
- `close()` / リソース解放メソッドの実装。

### Step 3: ワンショットマイグレーション & 旧 `graph.db` の完全削除
- 既存の `outputs/database/graph/graph.db`（約17MBのJSON）を読み込み、新 SQLite DB（`outputs/database/graph/knowledge_graph.sqlite`）へデータを移行するワンショットマイグレーションスクリプトを実行。
- マイグレーション完了後、旧 `outputs/database/graph/graph.db` をディスクから完全に削除・廃止。

### Step 4: 関連モジュール（CLI, ゲートウェイ, スクリプト）の追従
- [src/graph/cli.py](../../src/graph/cli.py):
  - `_resolve_graph_path` を `knowledge_graph.sqlite` に一本化。
- [scripts/seed_ontologies.py](../../scripts/seed_ontologies.py):
  - `--db-path` のデフォルトを新パスに更新。
- [src/pipeline/cti_backfill.py](../../src/pipeline/cti_backfill.py):
  - グラフエンジン連携パスを新パスに追従。
- [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py):
  - `_introspect_graph_database`, `_introspect_graph_table_metrics` から `graph.db` のハードコードを削除。
  - `"file_path": "outputs/database/graph/knowledge_graph.sqlite"` に更新し、実際の SQLite ファイルサイズおよびテーブル（`vertices`, `edges`）情報を返却。
- [site/dashboard.html](../../site/dashboard.html):
  - `graph.db` の旧記述・表示を排除。

### Step 5: テストの拡充 & 品質ゲート検証
- [tests/graph/test_graph_engine.py](../../tests/graph/test_graph_engine.py):
  - SQLite 永続化（INSERT, SELECT, トランザクションコミット）、インメモリモード（`:memory:`）の動作検証。
  - ディスクファイルが SQLite 形式ヘッダ（`SQLite format 3`）であることを検証。
- `make check_format` および `make static_analysis` (radon/xenon CC <= 5, mypy --strict)。
- `pytest tests/graph/` および `pytest tests/web/`。

---

## 7. 完了条件 / Success Criteria (DoD)

- [ ] `PropertyGraphEngine` が `src/database` の SQLite 互換コネクションを介してリレーショナルテーブル（`vertices`, `edges`）でグラフを永続化・クエリできること。
- [ ] `PropertyGraphEngine(storage_path=":memory:")` が物理ファイルをディスクに一切残さず、メモリ内で完全動作すること。
- [ ] 旧 JSON 形式の `outputs/database/graph/graph.db` がリレーショナル DB に移行された上で完全に廃止・削除されていること。
- [ ] `site/dashboard.html` および `src/web/gateway/handlers.py` から `graph.db` へのハードコード・言及が完全に削除され、新 DB 構成（`knowledge_graph.sqlite`）が正しく反映されること。
- [ ] レガシー JSON 読み書き・フォールバックの後方互換性コードがコードベースから一掃されていること。
- [ ] インデックス再構築コマンド（`make build_knowledge_graph`、`scripts/seed_ontologies.py` 等）が特定され、正常に実行できること。
- [ ] `tests/graph/` を含む関連テストがすべて PASS すること。
- [ ] `make check_format` および `make static_analysis`（mypy --strict, radon/xenon Grade A CC <= 5）を 100% 満たすこと。
