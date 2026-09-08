---
ID: 212
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] src/database における SQLite 準拠「:memory:」インメモリデータベースモードのサポート (ID: 212)

## 1. 概要 / Summary

本システムのゼロ外部依存・ハイブリッドデータベース基盤（`src/database/` / DSN-14）において、標準 Python `sqlite3` や SQLite 公式仕様と同様に、接続文字列・パス指定として **`":memory:"`** を完全サポートする。

現在、`database.connect(":memory:")` や `get_sqlite_connection(":memory:")`、`VectorStorage(":memory:")` を呼び出すと、内部で `os.path.abspath(":memory:")` が実行され、カレントディレクトリ直下に物理ファイル `":memory:"` を作成・読み込みしようとする重大な不具合・非互換が存在する。

本機能拡張により、以下を実現する：
1. **ディスク I/O ゼロの完全インメモリ実行**: ユニットテスト、高速キャッシュ、テンポラリ集計、および CI パイプラインにおいて、物理ディスクへの書き込みやクリーンアップ処理（`rm -rf`）を一切不要とする。
2. **`MemoryVFS` との完全統合**: 既存の仮想ファイルシステム抽象化層（`src/database/storage/vfs.py` の `MemoryVFS`）と透過的に連携し、Pager、Slotted Page、B+Tree、WAL、および VectorStorage をメモリ上（`io.BytesIO` バッファ）で完結させる。
3. **PEP 249 / `sqlite3` 互換 API の完全準拠**: `sqlite3.connect(":memory:")` と全く同一の挙動を `database.connect(":memory:")` および `get_sqlite_connection(":memory:")` で保証する。
4. **SQL Executor における動的テーブル作成のメモリ局所化**: `SQLExecutor` で `:memory:` ストレージ利用時に発行された `CREATE TABLE` / `DROP TABLE` をディスク `outputs/database/<table_name>.vdb` に永続化せず、メモリ内カタログとして透過管理する。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 ゼロ外部依存・純粋Python SQLite互換＆分散ベクトルデータベース基盤包括的アーキテクチャ設計書](../designs/DSN-14-pure_python_sqlite_and_distributed_vector_db.md) (Section 2.1 VFS層, Section 2.2 Pager層, Section 5.1 PEP 249)
- 関連コンポーネント:
  - `src/database/storage/vfs.py` (`MemoryVFS`, `MemoryVFSFile`)
  - `src/database/storage/storage.py` (`VectorStorage`)
  - `src/database/storage/pager.py` (`Pager`, `PageCache`)
  - `src/database/compat/sqlite_engine.py` (`get_sqlite_connection`, `_open_raw_sqlite_connection`)
  - `src/database/sql/executor.py` (`SQLExecutor`, `TableCatalog`)
  - `src/database/ipc/driver.py` (`Connection`, `connect`)

---

## 3. 多角的エージェント審議レビュー (Multi-Agent Perspectives)

1. **Project Manager (PM)**:
   - CI 実行時のファイルシステム汚染とテスト並列実行時のファイル競合を解消し、テスト実行速度の大幅向上（30%以上の短縮）をコミットする。
2. **Systems Architect**:
   - 既存の抽象レイヤ（`VFS` / `MemoryVFS`）の設計思想を忠実に継承し、`Pager` と `VectorStorage` の双方が `:memory:` をネイティブに解釈できる共通アーキテクチャを確立する。
3. **Information Security Specialist**:
   - `:memory:` 文字列の厳格な完全一致検証（パストラバーサルやサフィックスインジェクション攻撃の排除）およびコネクション終了時のメモリバッファ明示破棄による機密情報残留防止を策定。
4. **Software QA Specialist**:
   - ディスクアクセス監視テスト（テスト実行中にカレントディレクトリや `outputs/database/` にファイルが一切生成されないことの検証）を含む網羅的テストスイートを定義。
5. **Database / Data Infrastructure Specialist**:
   - SQLite 標準の `sync_from_vector_storage` および `sync_to_vector_storage` がメモリ内 `sqlite3.Connection` と `VectorStorage(":memory:")` 間で双方向同期できることを担保。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/compat/sqlite_engine.py](../../src/database/compat/sqlite_engine.py)
  - `_open_raw_sqlite_connection`: `db_path in (":memory:", "")` の判定追加。`os.path.abspath` / `os.makedirs` をバイパスし、`sqlite3.connect(":memory:", timeout=timeout)` を返却。
  - `get_sqlite_connection`: `:memory:` 時の WAL プラグマ適正化（インメモリ時は WAL 設定をスキップまたは安全処理）。
- [x] [src/database/storage/storage.py](../../src/database/storage/storage.py)
  - `VectorStorage.__init__`: `self.is_memory = (file_path == ":memory:")` フラグ導入。`os.path.abspath` をバイパス。
  - `VectorStorage.open_mmap` / `close`: インメモリ時は mmap をスキップし、`io.BytesIO` バッファおよびメモリ内ベクトルリストを管理。
  - `VectorStorage.write_all`: インメモリ時は `os.makedirs` や一時ファイル書き出しを行わず、`self._memory_vectors` および `io.BytesIO` 内でアトミック更新。
  - `VectorStorage.get_vector` / `get_all_vectors`: インメモリリストからの O(1) 高速参照。
  - `VectorStorage.to_bytes`: インメモリバイナリデータ（OKFVEC01フォーマット）のシリアライズ提供。
- [x] [src/database/storage/pager.py](../../src/database/storage/pager.py)
  - `Pager.__init__`: `file_path == ":memory:"` かつ `vfs is None` の場合、自動的に `get_vfs("memory")` をバインド。
- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py)
  - `SQLExecutor._create_new_table_storage`: `default_storage` がインメモリの場合、新規作成テーブルのストレージも `file_path=":memory:"` としてメモリ上に構築。
  - `SQLExecutor._remove_table_file`: `:memory:` ストレージに対するディスク削除処理のスキップ。
  - `SQLExecutor._build_show_table_row`: `:memory:` ストレージのサイズ計算において `os.path.getsize` を呼ばず、メモリバイト長を参照。
- [x] [src/database/ipc/driver.py](../../src/database/ipc/driver.py)
  - `Connection` / `connect`: `database=":memory:"` のサポート確認と透過的バインド。
- [x] [tests/database/test_in_memory_mode.py](../../tests/database/test_in_memory_mode.py)
  - 新規単体テスト群: `get_sqlite_connection(":memory:")`, `VectorStorage(":memory:")`, `Pager(":memory:")`, `SQLExecutor`, `database.connect(":memory:")` の全機能テスト。

---

## 5. セキュリティ脅威モデルと多層防御対策 / Threat Model & Mitigations

| 脅威カテゴリ (STRIDE) | 潜在リスク (Threat Vector) | 対策実装 (Mitigation) | 検証方法 |
| :--- | :--- | :--- | :--- |
| **Tampering / Spoofing** | `:memory:` に対するパス走査攻撃（例: `":memory:/../malicious.db"`） | `db_path in (":memory:", "")` または `file_path == ":memory:"` の**完全一致のみ**をインメモリと判定。それ以外は既存のパス正規化・セキュリティ検証を通過させる。 | 単体テストで不正サフィックス付きパスを検証 |
| **Denial of Service (DoS)** | インメモリバッファへの無制限データ挿入によるメモリ枯渇 (OOM) | `VectorStorage.MAX_VECTOR_COUNT` (10,000,000) および `MAX_DIMENSION` (4096) の境界チェックをインメモリでも等しく適用。 | 境界超過時の `ValueError` 発生テスト |
| **Information Disclosure** | 接続・インスタンス間におけるインメモリデータの意図しない共有・漏洩 | SQLite 標準の独立性に従い、接続ごとに独立したメモリ空間を確保。`VectorStorage(":memory:")` もインスタンスごとに独立したバッファを生成。 | 2つの独立接続間でのデータ不干渉テスト |
| **Information Leakage** | `close()` 後もプロセス内メモリに機密ベクトルデータが残留 | `VectorStorage.close()` 時に `_memory_vectors.clear()`, `metadata.clear()`, `if self._memory_buffer: self._memory_buffer.close()` を明示実行。 | ライフサイクル終了後のバッファ破棄テスト |

---

## 6. 実装方針と詳細ステップ / Implementation Plan

Target Branch: `feat/212-support-in-memory-database-mode`

### Step 1: `sqlite_engine.py` の `:memory:` パス解決バイパス
1. `_open_raw_sqlite_connection(db_path: str, read_only: bool, timeout: float)`:
   - 先頭で `if db_path in (":memory:", ""):` を判定。
   - `os.path.abspath` および `os.makedirs` をスキップし、`sqlite3.connect(":memory:", timeout=timeout)` を返却。
2. `get_sqlite_connection(...)`:
   - `enable_wal=True` 指定時でも、インメモリ接続（`db_path in (":memory:", "")`）の場合は WAL モードプラグマをスキップ（SQLite の仕様上 `:memory:` では `journal_mode=memory` となるため警告や不要な I/O を防ぐ）。

### Step 2: `VectorStorage` のインメモリモード実装 (`src/database/storage/storage.py`)
1. `VectorStorage.__init__(self, file_path: str, dim: int = 128)`:
   - `self.is_memory = (file_path == ":memory:")`
   - `if not self.is_memory: self.file_path = os.path.abspath(file_path)`
   - `self._memory_buffer: Optional[io.BytesIO] = io.BytesIO() if self.is_memory else None`
   - `self._memory_vectors: List[Tuple[float, ...]] = []`
2. `open_mmap(self)` / `close(self)`:
   - `open_mmap`: `self.is_memory` の場合は何もしない（`self._mmap = None`）。
   - `close`: `self.is_memory` の場合は `self._memory_vectors.clear()`, `self.metadata.clear()`, `if self._memory_buffer: self._memory_buffer.close()`.
3. `write_all(self, vectors, metadata)`:
   - `self.is_memory` の場合:
     - メタデータと次元のバリデーションを実施。
     - `self._memory_vectors = [tuple(v) for v in vectors]`
     - `self.metadata = meta_list`
     - `self.count = len(vectors)`
     - `self.id_to_idx` を再構築。
     - `self._serialize_to_memory_buffer()` を呼び出し、内部の `io.BytesIO` にヘッダー＋Float32バイナリ＋JSONメタデータを書き出し。
4. `get_vector(self, idx)` / `get_all_vectors(self)` / `to_bytes(self)`:
   - `get_vector`: `self.is_memory` 時は `self._memory_vectors[idx]` を O(1) で返却。
   - `get_all_vectors`: `self.is_memory` 時は `list(self._memory_vectors)` を返却。
   - `to_bytes`: `self._memory_buffer.getvalue()` を返却。

### Step 3: `Pager` / `VFS` のインメモリ自動解決 (`src/database/storage/pager.py`)
1. `Pager.__init__(self, file_path: str, ...)`:
   - `if file_path == ":memory:" and vfs is None and vfs_name is None:`
   - `self.vfs = get_vfs("memory")` を自動採用。
   - WAL パスも `":memory:.vdb-wal"` として `MemoryVFS` 上で仮想的に管理。

### Step 4: `SQLExecutor` におけるインメモリテーブル作成のサポート (`src/database/sql/executor.py`)
1. `_init_default_tables`:
   - `self.default_storage = default_storage` を保持。
2. `_create_new_table_storage(stmt)`:
   - `if self.default_storage and getattr(self.default_storage, "is_memory", False):`
   - 新規テーブル用ストレージを `VectorStorage(file_path=":memory:", dim=self.embedding.dim)` として初期化。
3. `_remove_table_file`:
   - `if storage_file and storage_file != ":memory:" and os.path.exists(storage_file):`
4. `_build_show_table_row`:
   - `storage.file_path == ":memory:"` の場合、ファイルサイズを `len(storage.to_bytes())` で算出。

### Step 5: PEP 249 ドライバの結合確認 (`src/database/ipc/driver.py`)
1. `connect(":memory:")`:
   - `Connection(file_path=":memory:")` がインメモリ `VectorStorage` と `VectorDBProtocolHandler` を起動し、標準 PEP 249 操作が正常動作することを確認。

### Step 6: 包括的テストスイートの作成 (`tests/database/test_in_memory_mode.py`)
1. `test_sqlite_engine_in_memory`:
   - `get_sqlite_connection(":memory:")` の動作確認。
   - 物理ディスク（カレントディレクトリ）に `":memory:"` ファイルが作成されないことの検証。
   - UDF (`COSINE_SIM`, `KNN_SCORE`, `EMBED`) の動作確認。
2. `test_vector_storage_in_memory`:
   - `VectorStorage(":memory:")` における append, append_batch, get_vector, get_all_vectors, write_all の検証。
   - ディスク書き込みが発生しないことの検証。
   - `to_bytes()` のバイナリフォーマット検証。
3. `test_bidirectional_sync_in_memory`:
   - インメモリ `VectorStorage` とインメモリ SQLite 間の `sync_from_vector_storage` / `sync_to_vector_storage` の動作検証。
4. `test_pager_in_memory`:
   - `Pager(":memory:")` が `MemoryVFS` で動作し、ページ I/O がメモリ完結することの検証。
5. `test_sql_executor_in_memory`:
   - `SQLExecutor` でインメモリ時に `CREATE TABLE` / `INSERT` / `SELECT` / `DROP TABLE` がディスクを汚さず動作することの検証。
6. `test_pep249_driver_in_memory`:
   - `database.connect(":memory:")` でのカーソル操作、コミット、ロールバック検証。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `database.connect(":memory:")` により、ディスク上に物理ファイルを作成することなくインメモリ接続が確立できること。
- [x] `get_sqlite_connection(":memory:")` がカレントディレクトリに `":memory:"` ファイルを作成せず、純粋な SQLite インメモリ DB を返却すること。
- [x] `VectorStorage(":memory:")` が `io.BytesIO` および内部リスト駆動で正常にベクトル追加・検索・メタデータ操作を行えること。
- [x] `Pager(":memory:")` が `MemoryVFS` を自動選択し、メモリ上でスロッテッドページ I/O を完結できること。
- [x] `SQLExecutor` において `:memory:` 動作時に `CREATE TABLE` を発行してもディスク上に `.vdb` ファイルが生成されないこと。
- [x] 新規単体テスト（`tests/database/test_in_memory_mode.py`）が全件 PASS すること。
- [x] 既存の全データベーステスト（`tests/database/`）および全体テストスイートにリグレッションが発生しないこと。
- [x] `make check_format` および `make static_analysis`（mypy --strict, radon/xenon Grade A CC <= 5）を 100% 満たすこと。

---

## 8. 検証手順 / Verification Commands

```bash
# 1. 新規インメモリテストの実行
pytest -v tests/database/test_in_memory_mode.py

# 2. 既存の全データベーステストの回帰検証
pytest -v tests/database/

# 3. 物理ファイル非生成の確認（カレントディレクトリに :memory: が存在しないこと）
ls -la ":memory:" 2>&1 | grep -q "No such file"

# 4. コード品質・静的解析ゲート
make check_format
make static_analysis
```
