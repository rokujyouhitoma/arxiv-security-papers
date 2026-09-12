---
ID: 255
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 汎用CSVテーブルストレージエンジン (CsvTableStorage) のサポートと cti_cwes CSV化 (ID: 255)

## 1. 概要 / Summary

AI（LLM）やGit差分での可読性・可監査性を劇的に向上させるため、データベースインフラストラクチャにテーブル全体を単一のCSVファイルとして永続化・クエリ実行可能な汎用ストレージエンジン `CsvTableStorage` (`src/database/storage/csv_storage.py`) を追加した。
また、本エンジンを `StorageEngineFactory` に登録（`ENGINE: "csv_table"` / 拡張子 `.csv` 自動判定）し、`cti_cwes` などのカタログテーブルをCSVバックエンドとして運用可能にした。

### 背景と目的
- **AI-Readable Open Data**: バイナリ形式 (`.vdb`) では AI エージェントが直接テキストとして閲覧・検索できず、SQLシェルを介す必要があった。CSVストレージにより、テーブル全体がプレーンテキスト化され、AIがプロンプトやコンテキストとして直接利用可能になる。
- **Git-Trackable**: MITRE CWE の更新履歴を行単位の `git diff` で追跡可能にする。
- **ゼロ外部依存 & ドメイン分離**: Python標準の `csv` モジュールのみを使用し、`src/database` にはドメイン固有コードを一切含めず純粋な汎用ストレージエンジンとして実装した。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: `docs/designs/DSN-05-database_architecture.md` (Section 21 Storage Engines)
- 関連設計書: `docs/designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md`
- 関連設計書: `docs/designs/DSN-24-centralized_database_registry.md`
- 関連規約: `AGENTS.md` (ゼロ外部依存、Xenon CC Rank A <= 5、クリーンアーキテクチャ)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 汎用データベースインフラ層 (Domain-Agnostic)
- [x] [NEW] `src/database/storage/csv_storage.py` (汎用 `CsvTableStorage` クラス)
- [x] [MODIFY] `src/database/storage/factory.py` (`csv_table` / `.csv` の登録と自動判別)
- [x] [MODIFY] `src/database/storage/__init__.py` (`CsvTableStorage` のエクスポート)
- [x] [NEW] `tests/database/storage/test_csv_storage.py` (単体テスト: CRUD, アトミック書き込み, 排他制御, 型パース)

### ドメイン・設定層 (Domain Specific)
- [x] [MODIFY] `src/settings.py` (`cti_catalog_db` 内の `cti_cwes` に `csv_table` 設定追加)
- [x] [MODIFY] `src/domain/security/cti/storage.py` (CSVストレージとのエクスポート/同期・連携機能)
- [x] [NEW] `outputs/database/catalog/cti_cwes.csv` (944件のCWEマスターデータCSV)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/255-support-csv-table-storage-engine`

### 4.1 CsvTableStorage 仕様設計 (`src/database/storage/csv_storage.py`)
1. **インターフェース**:
   - `JsonTableStorage` と同一のインターフェース互換性を提供：
     - `__init__(file_path: str, primary_key: str = "id", fieldnames: Optional[List[str]] = None)`
     - `get_by_pk(pk_value: str) -> Optional[Dict[str, Any]]` ($O(1)$)
     - `contains_pk(pk_value: str) -> bool`
     - `upsert(record: Dict[str, Any], auto_flush: bool = True) -> None`
     - `upsert_many(records: List[Dict[str, Any]], auto_flush: bool = True) -> None`
     - `delete(pk_value: str, auto_flush: bool = True) -> bool`
     - `all_records() -> List[Dict[str, Any]]`
     - `count() -> int`
     - `flush() -> None`
     - `@property metadata -> List[Dict[str, Any]]` (SQL Executor / TableCatalog互換)
2. **クラッシュセーフ & 排他制御**:
   - `file_flock` による POSIX `fcntl.flock` 排他ロック。
   - `flush()` 実行時は `.tmp.<pid>.<uuid>` に全件書き込み後、`os.replace` によるアトミック置換。
3. **RFC 4180 準拠 & 型シリアライズ**:
   - Python標準 `csv.reader` / `csv.writer` (`quoting=csv.QUOTE_MINIMAL`) を使用し、改行やカンマを含む長文を正確に保護。
   - 辞書・リストは JSON 文字列としてシリアライズ、数値・真偽値の自動パース。
4. **セキュリティ**:
   - `_validate_safe_workspace_path` によるパストラバーサル防止。

### 4.2 Factory 統合 (`src/database/storage/factory.py`)
- `_EXT_MAP` に `".csv": "csv_table"` を登録。
- `StorageEngineFactory._registry["csv_table"]` に `_create_csv_table` を追加。

### 4.3 `cti_cwes` データの移行 & CSV生成
- 既存の 944 件の CWE データを `outputs/database/catalog/cti_cwes.csv` に出力。
- `src/settings.py` のカタログ設定と連携。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/database/storage/csv_storage.py` が新規作成され、`JsonTableStorage` と同等のCRUD操作およびアトミックフラッシュが動作すること。
- [x] `StorageEngineFactory.create_by_engine_name("csv_table", ...)` および `.create_from_uri("path/to/table.csv")` で正しく初期化できること。
- [x] ゼロ外部依存（標準ライブラリ `csv` のみ）かつ Xenon CC Rank A (<= 5) を満たすこと。
- [x] `tests/database/storage/test_csv_storage.py` の単体テストが全件 PASS すること。
- [x] `outputs/database/catalog/cti_cwes.csv` に 944 件の CWE データが RFC 4180 準拠のプレーンテキストとして出力され、AI/人間が直接閲覧できること。
- [x] `make static_analysis` および `make test` が 100% PASS すること。

