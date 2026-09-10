---
ID: 229
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] プラガブルストレージエンジンファクトリおよび実ファイル連動プレーンテキスト仮想テーブル基盤の実装 (ID: 229)

## 1. 概要 / Summary

本Issueは、[DSN-05 (第21.6節 ＆ 第21.7節)](../../docs/designs/DSN-05-database_engine_architecture.md#216-実ファイル連動-プレーンテキストmarkdown仮想ストレージ仕様-file-backed-plaintext-engine)に基づき、`src/database` に**バイナリ形式（`.vdb`）とプレーンテキスト形式全般（JSON/JSONL/Markdown/PlainText）をシームレスに共存・切り替え可能とするプラガブルストレージ基盤**を確立することを目的とする。

1. **ストレージエンジンファクトリ (`StorageEngineFactory`) と URI 自動判別**:
   - 接続パスの拡張子（`.vdb`, `.jsonl`, `.json`, `.txt`/`.md`/ディレクトリ）から、`MultiTableVectorStorage`, `JsonLinesStorage`, `JsonTableStorage`, `FileBackedPlainTextStorage` を自動判別・インスタンス化する（ゼロ設定切り替え）。
2. **SQL DDL `USING` 句によるマルチエンジン共存**:
   - `CREATE TABLE ... USING binary_vdb | json_lines | json_table | file_plain_text` 構文をサポートし、単一データベース内でバイナリとプレーンテキストのテーブルを共存させ、透過的な JOIN クエリを実現する。
3. **実ファイル連動 プレーンテキスト仮想テーブル (`FileBackedPlainTextStorage`)**:
   - 物理ディスク上の原本ファイル（`outputs/okf_papers/**/*.md` および `outputs/raw_data/**/*`）を二重保持せず、そのまま仮想テーブル `okf_documents` としてマウント。
   - YAML フロントマターのインメモリキャッシュと長文テキスト（`body_markdown`, `raw_text`, `raw_abstract`）の遅延読み込み（Lazy Loading）により、メモリ消費を極小化しつつ SQL フルテキスト検索を可能にする。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [DSN-05: 第21.6節 実ファイル連動 プレーンテキスト/Markdown仮想ストレージ仕様](../../docs/designs/DSN-05-database_engine_architecture.md#216-実ファイル連動-プレーンテキストmarkdown仮想ストレージ仕様-file-backed-plaintext-engine)
  - [DSN-05: 第21.7節 プラガブルストレージ切り替え・共存アーキテクチャ](../../docs/designs/DSN-05-database_engine_architecture.md#217-プラグ可能ストレージ切り替え共存アーキテクチャuri自動判別--ddl-using-句ハイブリッドモデル)
  - [DSN-03: 第2.4節 重複防止台帳 ＆ 第4.6節 実態6フェーズライフサイクル](../../docs/designs/DSN-03-pipeline_architecture.md#24-重複防止台帳-processed_papersjson-から-srcdatabase-統合への進化)
- **関連Issue**: Issue #228 (JSONストレージ基盤およびライフサイクル可観測性刷新), Issue #214 (MultiTable VDB)
- **品質規程**: `.agents/AGENTS.md` (ゼロ外部依存, 相対パスリンク厳守, Xenon Rank A, mypy --strict)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### (1) データベース基盤層 (`src/database/`)
- [ ] `src/database/storage/factory.py` [NEW]: `StorageEngineFactory`（URI 自動判別およびエンジン登録）
- [ ] `src/database/storage/plain_text_storage.py` [NEW]: `FileBackedPlainTextStorage`（実ファイルマウント & 遅延評価）
- [ ] `src/database/storage/__init__.py`: ファクトリおよび新ストレージのエクスポート
- [ ] `src/database/sql/parser.py`: `CREATE TABLE ... USING <engine>` 構文解析の拡張
- [ ] `src/database/sql/executor.py`: プラガブルストレージエンジンへのクエリ委譲およびマルチエンジン JOIN

### (2) テスト ＆ 品質検証
- [ ] `tests/database/storage/test_storage_factory.py` [NEW]: URI 自動判別およびエンジン選択の単体テスト
- [ ] `tests/database/storage/test_plain_text_storage.py` [NEW]: PlainText/Markdown 仮想テーブルおよび遅延読み込みテスト
- [ ] `tests/database/sql/test_multi_engine_join.py` [NEW]: バイナリテーブルと PlainText 仮想テーブルのクロス JOIN テスト

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/229-implement-pluggable-storage-engine-factory-and-file-backed-plain-text-tables`

### Step 1: `StorageEngineFactory` の実装 (`src/database/storage/factory.py`)
- パス文字列の判定ロジック：
  - `.vdb` ➔ `MultiTableVectorStorage`
  - `.jsonl` ➔ `JsonLinesStorage`
  - `.json` ➔ `JsonTableStorage`
  - ディレクトリ（`os.path.isdir`）または `.txt`/`.md` ➔ `FileBackedPlainTextStorage`
- シングルトン / レジストリパターンによるカスタムエンジンの拡張性確保。

### Step 2: `FileBackedPlainTextStorage` の実装 (`src/database/storage/plain_text_storage.py`)
- ディレクトリ内の `*.md` や `*.txt` をスキャンし、ヘッダー/フロントマターまたはファイル属性（clean_id, title, size, mtime等）のみをパースしてインデックス化。
- `read_column(clean_id, col)` において、`body_markdown`、`raw_text`、`raw_abstract` が要求された場合のみ実ファイルを開いてキャッシュ。

### Step 3: SQL パーサーとエグゼキューターの拡張
- `CREATE TABLE ... USING <engine_name>` の AST ノード拡張（`file_plain_text` 対応）。
- `SQLExecutor` がテーブルごとに異なるストレージエンジンインスタンスを保持し、同一クエリ内で透過的に結合可能にする。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `StorageEngineFactory` が URI/拡張子に応じてバイナリおよびプレーンテキストエンジンを正しく自動判別すること。
- [ ] `CREATE TABLE ... USING <engine>` 構文（`file_plain_text` 含む）が正しくパース・実行されること。
- [ ] `outputs/okf_papers/` や `outputs/raw_data/` の実体テキスト/Markdown ファイルが仮想テーブル `okf_documents` としてマウントされ、SQL で検索できること。
- [ ] `body_markdown` や `raw_text` 等の長文テキストが遅延読み込みされ、不要なファイル I/O が発生しないこと。
- [ ] バイナリテーブル（`.vdb`）と PlainText 仮想テーブルのクロス JOIN が正常に実行できること。
- [ ] 新規追加テストが 100% PASS し、`make check_format` および `make static_analysis`（mypy --strict, xenon Rank A CC<=5）がエラー 0 件で通過すること。
