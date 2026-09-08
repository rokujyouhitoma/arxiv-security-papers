---
ID: 214
種別: Feature
優先度: High
ステータス: Closed
担当エージェント: Systems Architect / Database Specialist / PM
---

# [FEAT] src/database における単一 .vdb マルチテーブルコンテナ対応および sqlite3 (PEP 249) 互換インターフェースの実装 (ID: 214)

## 1. 概要 / Summary

現在、`src/database` の一次ストレージである `VectorStorage` は単一テーブル構造（`OKFVEC01` フォーマット: ヘッダー + 単一ベクトル列 + メタデータ配列）を前提としており、複数テーブルを扱うためには `vertices.vdb` と `edges.vdb` のように物理ファイルを分離して管理していた。

また、標準ライブラリの `sqlite3` パッケージ（C言語拡張）を完全に排除した純粋 Python の独自データベース基盤を確立したが、利用側のプログラミングインターフェース（API）については、Python 開発者に最も馴染み深い標準ライブラリ `sqlite3`（PEP 249 DB-API 2.0 規約）と全く同一の使い勝手（`connect()`, `cursor()`, `execute()`, `fetchall()`, `commit()`, `close()`）であることが保守性・生産性・移植性の観点から極めて望ましい。

本改修では、以下のアーキテクチャ拡張を完了した：
1. **単一 `.vdb` マルチテーブルコンテナフォーマット（`OKFMTC01`）の実装**:
   - 1 つの物理ファイル（例: `knowledge_graph.vdb`）内で、複数の独立したテーブルセクション（`vertices`, `edges` 等）と目次（テーブルカタログディレクトリエントリ）を管理する `MultiTableVectorStorage` を新設。
   - テーブルごとに異なるベクトル次元（例: 頂点用 64 次元、辺用 16 次元）および任意の JSON スキーマを柔軟に共存可能にする。
2. **`sqlite3` (PEP 249) 完全互換インターフェースの提供**:
   - `from database import connect`
   - `conn = connect("knowledge_graph.vdb")`
   - `cursor = conn.cursor()`
   - `cursor.execute("SELECT * FROM vertices WHERE label = ?", ("Paper",))`
   - `rows = cursor.fetchall()`
   - `conn.commit()` / `conn.close()`
   - という `sqlite3` と 100% 同一の記述感・インターフェースを純粋 Python のみで実現。C 拡張の `import sqlite3` を一切使わず、ゼロ外部依存を完全維持。
3. **`src/graph`（`PropertyGraphEngine`）の単一ファイル集約**:
   - 分離されていた `outputs/database/vertices.vdb` と `edges.vdb` を、単一の統合ファイル `outputs/database/knowledge_graph.vdb` へ集約。
   - インメモリモード（`:memory:`）でも単一のインメモリバッファ内で全テーブルが完結動作する仕様を保証。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-05 データベースエンジンアーキテクチャ設計書](../designs/DSN-05-database_engine_architecture.md) (Chapter 19 単一 .vdb マルチテーブルコンテナ (OKFMTC01) & PEP 249 sqlite3 互換インターフェース)
- 設計書: [DSN-14 Graph Engineering Dashboard (Context Mesh) & Live Loop Observability 包括的アーキテクチャ設計書](../designs/DSN-14-graph_engineering_dashboard.md)
- 設計書: [DSN-18 プロパティグラフデータベースエンジン設計書](../designs/DSN-18-property_graph_database_engine.md)
- 関連 Issue:
  - [Issue #213: src/graph の永続化・クエリバックエンドへの src/database 統合 & graph.db 完全廃止](213-integrate-database-engine-into-graph-subsystem.md)
  - [Issue #212: src/database における SQLite 準拠「:memory:」インメモリデータベースモードのサポート](212-support-in-memory-database-mode.md)

---

## 3. セキュリティ & 脅威モデル分析 / Security & Threat Modeling (STRIDE)

| 脅威 / 脆弱性 (STRIDE) | リスク評価 | 対策と実装結果 |
| :--- | :--- | :--- |
| **なりすまし・ファイル偽造 (Spoofing)** | High | SuperBlock の Magic Bytes（`b"OKFMTC01"`）検証、バージョンチェック（`version == 1`）、および CRC32 チェックサムによるカタログ整合性検証を必須とし、不正ファイルのロードを拒絶。 |
| **バイナリ改ざん・境界破壊 (Tampering)** | High | カタログ内のテーブル `offset` および `length` がファイルサイズ内に厳密に収まっているか、隣接テーブルとオーバーラップしていないかを検証し、バッファ外読み出し・任意メモリアクセスを物理的に防止（`MultiTableSecurityError`）。 |
| **パストラバーサル (Information Disclosure / Tampering)** | Medium | `connect(path)` のファイルパス引数に対し、安全なワークスペースパス境界チェックを実施し、ワークスペース外への不正ファイル書き出しを遮断（`:memory:` 指定は特別許可）。 |
| **リソース枯渇 / DoS (Denial of Service)** | Medium | コンテナ内の最大テーブル数を `MAX_TABLE_COUNT = 1024`、最大総ベクトル数を `MAX_TOTAL_VECTORS = 10_000_000` に制限し、メモリ枯渇や無限ループを防止。 |
| **SQL インジェクション (Tampering)** | High | PEP 249 カーソルの `execute(sql, params)` において、文字列連結ではなく `?` プレースホルダーに対する厳格な型安全パラメータバインディングを強制。 |
| **権限昇格 (Elevation of Privilege)** | Low | `Connection(..., role="viewer")` 指定時に DDL / DML クエリ（CREATE, INSERT, UPDATE, DELETE）を拒絶する RBAC アクセス制御を透過適用。 |

---

## 4. バイナリコンテナフォーマット仕様 (`OKFMTC01`)

単一 `.vdb` ファイルの構造：

```text
+-----------------------------------------------------------------------+
| SuperBlock (64 bytes):                                                |
| - Magic Bytes: "OKFMTC01" (8B)                                        |
| - Format Version: uint16 (2B) = 1                                     |
| - Table Count: uint16 (2B)                                            |
| - Catalog Offset: uint64 (8B)                                         |
| - Catalog Length: uint64 (8B)                                         |
| - Catalog CRC32: uint32 (4B)                                          |
| - Timestamp: uint64 (8B, Unix epoch UTC)                              |
| - Reserved Padding: 24B (全ゼロ)                                       |
+-----------------------------------------------------------------------+
| Table 1 Data Segment (例: vertices)                                   |
| - 形式: OKFVEC01 単一テーブル互換ブロック (Header + Vectors + JSON)    |
+-----------------------------------------------------------------------+
| Table 2 Data Segment (例: edges)                                      |
| - 形式: OKFVEC01 単一テーブル互換ブロック (Header + Vectors + JSON)    |
+-----------------------------------------------------------------------+
| ... (追加テーブルセグメント: tbox_classes, claims, evidences 等)        |
+-----------------------------------------------------------------------+
| Master Table Catalog Block (UTF-8 JSON):                              |
| {                                                                     |
|   "version": 1,                                                       |
|   "tables": {                                                         |
|     "vertices": {"offset": 64, "length": 32048, "dim": 16, "count": 194},|
|     "edges":    {"offset": 32112, "length": 18450, "dim": 16, "count": 236}|
|   }                                                                   |
| }                                                                     |
+-----------------------------------------------------------------------+
```

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/storage/multi_storage.py](../../src/database/storage/multi_storage.py) (新規: マルチテーブルコンテナストレージコア)
- [x] [src/database/storage/storage.py](../../src/database/storage/storage.py) (サブテーブルビュー連携)
- [x] [src/database/driver.py](../../src/database/driver.py) (公開 PEP 249 エントリポイント)
- [x] [src/database/ipc/driver.py](../../src/database/ipc/driver.py) (Connection/Cursor のマルチテーブル対応)
- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py) (マルチテーブル一括アタッチ)
- [x] [src/database/__init__.py](../../src/database/__init__.py) (`connect`, `Connection`, `Cursor` 公開)
- [x] [src/graph/engine.py](../../src/graph/engine.py) (単一 `knowledge_graph.vdb` への統合)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (単一ファイルメトリクスインスペクション)
- [x] [tests/database/test_multi_table_vdb.py](../../tests/database/test_multi_table_vdb.py) (新規: コンテナ単体テスト)
- [x] [tests/database/test_pep249_interface.py](../../tests/database/test_pep249_interface.py) (新規: sqlite3 互換テスト)
- [x] [tests/graph/test_graph_engine.py](../../tests/graph/test_graph_engine.py) (単一ファイル回帰テスト)

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/214-support-multi-table-vdb-container-and-pep249-sqlite-interface`

### Step 1: `MultiTableVectorStorage` コアの実装 (`src/database/storage/multi_storage.py`)
- SuperBlock 定義（`OKFMTC01`, 64B）、カタログシリアライザ / デシリアライザ。
- 各テーブルの `VectorStorage` インスタンスを内部辞書 `_tables: Dict[str, VectorStorage]` で保持。
- `get_table(name: str) -> VectorStorage`: 指定テーブルのビューを取得。
- `create_table(name: str, dim: int = 16) -> VectorStorage`: 新規テーブル作成。
- `list_tables() -> List[str]`: テーブル一覧返却。
- `save()` / `load()`: 単一ファイルへの連続セグメント配置と末尾カタログ書き込み。
- `:memory:` インメモリモード対応（`io.BytesIO` 単一バッファ管理）。

### Step 2: PEP 249 ドライバの直結拡張 (`src/database/driver.py`, `src/database/ipc/driver.py`)
- `connect(database: str = ":memory:", role: str = "admin", **kwargs) -> Connection` を実装。
- `Connection` 初期化時に `MultiTableVectorStorage(database)` を開き、内部 `SQLExecutor` の全テーブルカタログへ自動登録。
- `cursor.execute(sql, params)`、`cursor.executemany(...)`、`cursor.fetchone()`、`cursor.fetchall()`、`cursor.description` の完全実装。
- `conn.commit()` でコンテナストレージのディスクフラッシュを実行。
- `sqlite3` パッケージのインポート・呼び出しは 0 件を厳守。

### Step 3: `src/database/__init__.py` の公開インターフェース統合
- `from database import connect, Connection, Cursor, DatabaseError` を公開し、最上位パッケージから直感的に利用可能にする。

### Step 4: `src/graph`（`PropertyGraphEngine`）の単一ファイル集約
- デフォルトパスを `outputs/database/knowledge_graph.vdb` 単一ファイルに統一。
- `self._init_storage()` で `MultiTableVectorStorage` を開き、内部に `vertices` と `edges` を格納。
- `engine.connect()` により、グラフエンジンから直接 PEP 249 Connection を取得可能にする。

### Step 5: Web ゲートウェイおよびスクリプトの単一ファイル対応
- `src/web/gateway/handlers.py` の `_introspect_graph_table_metrics` / `_introspect_graph_database` を `knowledge_graph.vdb` 1 ファイルから各テーブルのサイズ・行数をインスペクションするよう更新。
- `scripts/seed_ontologies.py`、`src/graph/cli.py` のデフォルトパスを `outputs/database/knowledge_graph.vdb` に更新。

### Step 6: 厳格な品質ゲートとテスト
- すべての関数・メソッドで Radon/Xenon Grade A (CC <= 5) を達成。
- `mypy --strict src` 100% PASS。
- `tests/database/test_multi_table_vdb.py` および `tests/database/test_pep249_interface.py` でカバレッジを確保。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] 単一の `.vdb` ファイルで複数テーブル（`vertices`, `edges` 等）の作成・読み書き・永続化が正常に行えること
- [x] `from database import connect; conn = connect("path.vdb"); cur = conn.cursor(); cur.execute(...)` が `sqlite3` と全く同一の作法・挙動で動作すること
- [x] パラメータバインディング（`?` プレースホルダー）およびトランザクション（`commit`/`rollback`）が正常に機能すること
- [x] インメモリモード（`:memory:`）でも単一バッファで複数テーブルが正常に動作すること
- [x] `import sqlite3`（C言語拡張）を一切使用せず、ゼロ外部依存を維持していること
- [x] `PropertyGraphEngine` が単一の `knowledge_graph.vdb` で正常に動作し、トポロジー探索・シード・クエリができること
- [x] 新規単体テストおよび既存テスト（`tests/database/`, `tests/graph/`, `tests/web/`）がすべて PASS すること
- [x] すべての品質ゲート（Xenon Grade A, Mypy Strict, Black, isort, Flake8）が 100% 合格すること

---

## 8. 実施結果と検証記録 / Verification Record

1. **マルチテーブルコンテナ単体テスト (`tests/database/test_multi_table_vdb.py`)**:
   - `OKFMTC01` ヘッダー生成、CRC32 検証、複数テーブル作成、異種次元ベクトル格納、保存・復元、改ざん検出（Magic / CRC 不一致）の全 7 テストが PASS（0.19s）。
2. **PEP 249 インターフェース単体テスト (`tests/database/test_pep249_interface.py`)**:
   - `from database import connect` を用いた接続、カーソル操作、DDL (`CREATE TABLE`, `DROP TABLE`)、DML (`INSERT INTO ... VALUES (?, ?)`), DQL (`SELECT ...`), `executemany`, `fetchone`, `fetchall`, `commit`、およびゼロ `import sqlite3` 検証の全 7 テストが PASS（0.28s）。
3. **グラフエンジン単一コンテナ統合 (`src/graph/engine.py`)**:
   - 単一コンテナ `outputs/database/knowledge_graph.vdb`（213,619 bytes、194 vertices、233 edges）への集約完了。
   - `tests/graph/` 全 37 テスト PASS（0.44s）。
4. **Web ゲートウェイ統合 (`src/web/gateway/handlers.py`)**:
   - `knowledge_graph.vdb` 単一ファイルからのテーブルメトリクスインスペクションに対応。
   - `tests/web/` 全 98 テスト PASS（37.21s）。
5. **品質ゲート検証**:
   - `make check_format` (isort, black, flake8): PASS
   - `make static_analysis` (radon, xenon Grade A, mypy --strict 436 files, py_compile): PASS
   - 全体テスト（229 database + 37 graph + 98 web = 364 テスト）: PASS
