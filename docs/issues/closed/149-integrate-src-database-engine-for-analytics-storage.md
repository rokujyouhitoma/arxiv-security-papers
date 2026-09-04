# Issue 149: sqlite利用箇所（analytics.db等）のsrc/database統合と統一データベース基盤化

## 1. 概要 (Overview)
現在、`src/analytics/storage.py` および `src/web/gateway/handlers.py` において Python 標準ライブラリの `sqlite3` が直接インポート・接続されており、リポジトリの統一データベース基盤である `src/database` (DSN-05) とのアーキテクチャ境界が曖昧になっている。
また、`src/database/compat/sqlite_engine.py` の `get_sqlite_connection` はデフォルトで `papers` テーブルを自動生成する仕様となっており、`analytics.db` 等の異なるスキーマを持つデータベース接続時に不要なテーブルが作成されてしまう課題がある。

本 Issue では、`src/database` に汎用的な SQLite 接続管理機能・メタデータ行数集計機能・型エクスポートを拡充し、`analytics.db` を含むすべての SQLite 操作を `src/database` 経由に統一・集約する。

---

## 2. 目的と期待効果 (Goals & Benefits)
- **統一データ基盤の確立 (DSN-05準拠)**:
  - アプリケーション層（`analytics`, `web` 等）が直接 `sqlite3` を操作することを廃止し、`src/database` が提供する公式インターフェースにアクセスを集約。
- **不要スキーマ作成の防止 & 独立性確保**:
  - `papers.db` 以外の SQLite データベース（`analytics.db` 等）接続時に、不要な `papers` テーブルが勝手に作成されないよう初期化オプションと責務を分離。
- **WALモード & 読み取り専用接続の集中管理**:
  - `PRAGMA journal_mode=WAL;` や `file:...?mode=ro` (URI接続) などの接続構成を `src/database` 側で安全にカプセル化。
- **型安全性とクリーンアーキテクチャ**:
  - `SQLiteConnection`, `SQLiteCursor` などの型エイリアスを `src/database` から提供し、`mypy --strict` 準拠の完全な型安全性を維持。

---

## 3. 変更対象コンポーネント (Target Components)

### 3.1 `src/database/compat/sqlite_engine.py` & `src/database/__init__.py`
- `get_sqlite_connection` の拡張:
  - `init_schema: bool = True` (デフォルトは `papers` スキーマ初期化だが、`False` 指定で汎用DB接続可能に)
  - `read_only: bool = False` (URI `mode=ro` 接続サポート)
  - `enable_wal: bool = False` (WAL & synchronous=NORMAL の自動適用)
  - `timeout: float = 5.0`
- ユーティリティ追加:
  - `count_sqlite_table_rows(db_path: str) -> Optional[int]`
  - `sum_sqlite_table_rows(conn: sqlite3.Connection) -> Optional[int]`
  - `get_sqlite_table_names(conn: sqlite3.Connection) -> List[str]`
- 型エイリアス・エクスポート:
  - `SQLiteConnection = sqlite3.Connection`
  - `SQLiteCursor = sqlite3.Cursor`
  - `SQLiteRow = sqlite3.Row`
  - `src/database/__init__.py` の `__all__` に上記を追加。

### 3.2 `src/analytics/storage.py`
- `import sqlite3` を廃止し、`from database import get_sqlite_connection, SQLiteCursor` を使用。
- `get_sqlite_connection(self.db_path, init_schema=False, enable_wal=True)` を利用。
- 過去の接続で誤って生成された可能性のある `papers` テーブルのクリーンアップ処理（`DROP TABLE IF EXISTS papers`）をマイグレーションに追加。

### 3.3 `src/web/gateway/handlers.py`
- `_count_analytics_sqlite_rows` 内の `import sqlite3` および独自接続処理を廃止。
- `from database import count_sqlite_table_rows` を直接呼び出す形に簡潔化。

### 3.4 テストの拡充
- `tests/analytics/test_aggregator.py`: `analytics.db` が `src/database` 経由で正常にマイグレーション・クエリ実行されること、不要な `papers` テーブルが存在しないことを検証。
- `tests/database/test_database_100_percent_coverage.py`: `get_sqlite_connection` の新オプション（`init_schema=False`, `read_only=True`, `enable_wal=True`）および `count_sqlite_table_rows` の網羅テストを追加。

---

## 4. Definition of Done (DoD)
1. `src/` 配下のプロダクションコード（`src/database/compat/` を除く）から `import sqlite3` の直接呼び出しがゼロ件であること。
2. `analytics.db` の生成・保存・読み取りが `src/database` 経由で正常に動作し、無関係な `papers` テーブルが作成されないこと。
3. `src/web/gateway/handlers.py` のアナリティクス行数集計が `src/database` の集計 API 経由で正常に機能すること。
4. 全ユニットテスト（`tests/analytics/`, `tests/database/`, `tests/web/`）が PASS すること。
5. `make check_format` および `make static_analysis` (`mypy --strict`, `xenon A`) を 100% エラーゼロでクリアすること。

---

## 5. 実施結果・検証 (Execution & Verification)
- **完了日**: 2026-09-04
- **実装内容**:
  - `src/database/compat/sqlite_engine.py`: `get_sqlite_connection` を拡張し、`init_schema=False`, `read_only=True`, `enable_wal=True` をサポート。型エイリアス `SQLiteConnection`, `SQLiteCursor`, `SQLiteRow` およびユーティリティ `count_sqlite_table_rows`, `sum_sqlite_table_rows`, `get_sqlite_table_names` を実装。複雑度 (Cyclomatic Complexity) は xenon Rank A を達成。
  - `src/database/__init__.py` & `src/database/sqlite_engine.py`: 全ての型・関数を re-export。
  - `src/analytics/storage.py`: `import sqlite3` を完全に排除し、`src/database` を使用。マイグレーション v4 (`DROP TABLE IF EXISTS papers;`) により既存 `analytics.db` から不要な `papers` テーブルを安全に除去。
  - `src/web/gateway/handlers.py`: 直接の `import sqlite3` を廃止し、`src/database` の `count_sqlite_table_rows` を利用。
- **検証結果**:
  - `tests/analytics`: 4 passed (100%)
  - `tests/database`: 15 passed in coverage suite (100%)
  - `tests/web`: 64 passed (100%)
  - `flake8`, `isort`, `black`, `mypy --strict`, `xenon` (Rank A: 107 blocks, average 3.31), `radon`, `compileall` すべて 100% PASS。
