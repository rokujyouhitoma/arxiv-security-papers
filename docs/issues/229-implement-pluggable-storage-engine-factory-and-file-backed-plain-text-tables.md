---
ID: 229
種別: Feature
優先度: High
ステータス: Open (In Progress)
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

## 2. セキュリティ脅威モデルと多層防御設計 (Threat Modeling & Security Architecture)

実ファイルマウントおよびプラガブルストレージの動的インスタンス化に伴うセキュリティリスクを以下の多層防御により遮断する：

| 脅威カテゴリ (STRIDE) | 潜在リスク (Threat Scenario) | 緩和策・セキュリティ仕様 (Mitigations) |
| :--- | :--- | :--- |
| **Tampering / Traversal (改ざん・不正アクセス)** | `LOCATION` パスやファイル指定によるリポジトリ外部の機密ファイル（`/etc/passwd`, 秘密鍵等）の読み取り | **厳格なリポジトリルート境界検証**:<br>`os.path.realpath()` を用いて対象パスを正規化し、プロジェクトのワークスペースルート内部に存在することを `os.path.commonpath()` で強制検証。シンボリックリンクによる境界突破を 100% 遮断。 |
| **Denial of Service (DoS)** | 巨大テキストファイルの無制限読み込みによるプロセス OOM、ファイルディスクリプタ枯渇 | **二重防御（サイズ上限 ＆ LRUキャッシュ）**:<br>1. 1 ファイルあたり最大 20MB の読み込み上限（超過時は安全にトランケーションまたはスキップ）。<br>2. 本文テキストのキャッシュは最大 500 件の LRU キャッシュ（`collections.OrderedDict`）とし、メモリ消費を数十MB以内に固定。<br>3. ファイルオープンは必ずコンテキストマネージャ（`with open(...)`）を使用し FD リークをゼロ化。 |
| **Injection (インジェクション)** | `CREATE TABLE ... USING <engine>` 句への悪意ある文字列注入や不正モジュールロード | **ホワイトリスト識別子検証**:<br>指定可能なエンジン名を `{'binary_vdb', 'json_lines', 'json_table', 'file_plain_text'}` のホワイトリストに限定。任意の動的クラス名やモジュールパス指定を拒絶。 |
| **Information Disclosure (情報漏洩)** | パースエラー時のスタックトレースによるサーバー内部フルパス露出 | **エラーメッセージのサニタイズ**:<br>例外発生時はリポジトリ相対パスへのマスキングを行い、内部環境の絶対パス漏洩を防止。 |

---

## 3. トレーサビリティ / Traceability

- **設計仕様書**:
  - **データベース基盤**: [DSN-05: 第21.6節 実ファイル連動 プレーンテキスト/Markdown仮想ストレージ仕様](../../docs/designs/DSN-05-database_engine_architecture.md#216-実ファイル連動-プレーンテキストmarkdown仮想ストレージ仕様-file-backed-plaintext-engine)
  - **データベース基盤**: [DSN-05: 第21.7節 プラガブルストレージ切り替え・共存アーキテクチャ](../../docs/designs/DSN-05-database_engine_architecture.md#217-プラグ可能ストレージ切り替え共存アーキテクチャuri自動判別--ddl-using-句ハイブリッドモデル)
  - **パイプライン・台帳**: [DSN-03: 第2.4節 重複防止台帳 ＆ 第4.6節 実態6フェーズライフサイクル](../../docs/designs/DSN-03-pipeline_architecture.md#24-重複防止台帳-processed_papersjson-から-srcdatabase-統合への進化)
- **関連Issue**: Issue #228 (JSONストレージ基盤およびライフサイクル可観測性刷新), Issue #214 (MultiTable VDB)
- **品質規程**: `.agents/AGENTS.md` (ゼロ外部依存, 相対パスリンク厳守, Xenon Rank A CC<=5, mypy --strict)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### (1) データベース基盤層 (`src/database/`)
- [ ] `src/database/storage/factory.py` [NEW]:
  - `StorageEngineFactory`: URI / パス拡張子によるエンジン自動判定およびシングルトン管理
- [ ] `src/database/storage/plain_text_storage.py` [NEW]:
  - `FileBackedPlainTextStorage`: 実ファイル群の仮想テーブルマウント、メタデータインデックス、遅延プロパティ読み込み
- [ ] `src/database/storage/__init__.py`: ファクトリおよび新ストレージのエクスポート
- [ ] `src/database/sql/parser.py`: `CREATE TABLE ... USING <engine> [LOCATION '<path>']` 構文の AST 解析拡張
- [ ] `src/database/sql/executor.py`: マルチストレージエンジンインスタンスの保持、透過的ルーティング、クロスエンジン結合（JOIN）

### (2) テスト ＆ 品質検証
- [ ] `tests/database/storage/test_storage_factory.py` [NEW]:
  - `.vdb`, `.jsonl`, `.json`, `.txt`/`.md`/ディレクトリの自動判別およびカスタム登録テスト
- [ ] `tests/database/storage/test_plain_text_storage.py` [NEW]:
  - YAML フロントマターの高速抽出、遅延読み込み動作、パスバリデーション、LRU メモリ制限テスト
- [ ] `tests/database/sql/test_multi_engine_join.py` [NEW]:
  - バイナリテーブル（`.vdb`）と PlainText 仮想テーブル（`file_plain_text`）のクロス JOIN 統合テスト

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/229-implement-pluggable-storage-engine-factory-and-file-backed-plain-text-tables`

### Step 1: `StorageEngineFactory` の実装 (`src/database/storage/factory.py`)
1. **URI / 拡張子判定**:
   ```python
   class StorageEngineFactory:
       @classmethod
       def create_from_uri(cls, uri_or_path: str, **kwargs: Any) -> BaseStorageEngine:
           # 1. *.vdb -> MultiTableVectorStorage
           # 2. *.jsonl -> JsonLinesStorage
           # 3. *.json -> JsonTableStorage
           # 4. os.path.isdir() or *.md, *.txt -> FileBackedPlainTextStorage
   ```
2. **エンジン登録 API**:
   - `register_engine(name: str, engine_cls: Type[BaseStorageEngine])` により、将来の新規バックエンド（Arrow 等）にもゼロ修正で拡張可能な Open-Closed 設計とする。

### Step 2: `FileBackedPlainTextStorage` の実装 (`src/database/storage/plain_text_storage.py`)
1. **初期スキャン ＆ インデックス構築**:
   - 指定ディレクトリ（例: `outputs/okf_papers/`）配下の `*.md` / `*.txt` を再帰スキャン。
   - 先頭 2KB のみ読み取り、YAML フロントマター（`title`, `description`, `tags`, `provenance` 等）を軽量パースしてインメモリ辞書 `_meta_index[clean_id]` に保持。
2. **遅延評価 I/O (`read_column`)**:
   - `body_markdown`、`raw_text`、`raw_abstract` 列が要求された時のみ実ファイル全体を開く。
   - 最大 500 件保持する LRU キャッシュ（`OrderedDict`）に格納し、同一トランザクション内での重複 I/O を排除。

### Step 3: SQL パーサーとエグゼキューターの拡張
1. **SQL DDL 構文拡張 (`src/database/sql/parser.py`)**:
   - `CREATE TABLE <name> (...) USING <engine_name> [LOCATION '<path>']` のパースに対応。
   - `engine_name` を AST の `CreateTableStatement.engine` にバインド。
2. **クエリエグゼキューター統合 (`src/database/sql/executor.py`)**:
   - テーブル名ごとに割り当てられたストレージエンジンを保持（`_table_engines: Dict[str, BaseStorageEngine]`）。
   - `SELECT ... FROM t1 JOIN t2 ON ...` 実行時、`t1` がバイナリ VDB、`t2` が `FileBackedPlainTextStorage` であっても、インメモリイテレータを介して透過的にハッシュ結合。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] **プラガブルエンジン判別完全性**:
  - `StorageEngineFactory.create_from_uri()` が `.vdb`, `.jsonl`, `.json`, ディレクトリ/`.md`/`.txt` を 100% 正しく判別・生成すること。
- [ ] **実ファイル仮想マウント性能 ＆ メモリフットプリント**:
  - 500 件以上の Markdown / テキストファイル群をマウントしても、初期スキャン完了時間が **0.5秒未満**、メモリ消費増が **5MB 未満** であること。
  - 本文列の遅延読み込みが正しく動作し、SELECT で本文列を指定しないクエリ（メタデータのみの検索）では本文ディスク I/O が一切発生しないこと。
- [ ] **マルチエンジン結合 (Cross-Engine JOIN)**:
  - 単一 SQL クエリで `binary_vdb` テーブルと `file_plain_text` 仮想テーブルを JOIN し、正しい結合レコードが返却されること。
- [ ] **セキュリティ多層防御**:
  - ワークスペース外部へのパストラバーサルを試みる `LOCATION` 指定が `SecurityException` で安全に拒絶されること。
- [ ] **コード品質 ＆ 静的解析**:
  - 全新規コードが `mypy --strict` でエラー 0 件であること。
  - 全関数のサイクロマティック複雑度が Xenon **Rank A (CC <= 5)** を達成していること。
  - `make check_format` および `make test` が 100% PASS すること。
