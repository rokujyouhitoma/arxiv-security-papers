---
ID: 212
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] src/database における SQLite 準拠「:memory:」インメモリデータベースモードのサポート (ID: 212)

## 1. 概要 / Summary

本システムのゼロ外部依存・ハイブリッドデータベース基盤（`src/database/` / DSN-14）において、標準 Python `sqlite3` や SQLite 公式仕様と同様に、接続文字列・パス指定として **`":memory:"`** を完全サポートする。

現在、`database.connect(":memory:")` や `get_sqlite_connection(":memory:")`、`VectorStorage(":memory:")` を呼び出すと、内部で `os.path.abspath(":memory:")` が実行され、カレントディレクトリ直下に物理ファイル `":memory:"` を作成・読み込みしようとする重大な不具合・非互換が存在する。

本機能拡張により、以下を実現する：
1. **ディスク I/O ゼロの完全インメモリ実行**: ユニットテスト、高速キャッシュ、テンポラリ集計、および CI パイプラインにおいて、物理ディスクへの書き込みやクリーンアップ処理（`rm -rf`）を一切不要とする。
2. **`MemoryVFS` との完全統合**: 既存の仮想ファイルシステム抽象化層（`src/database/storage/vfs.py` の `MemoryVFS`）と透過的に連携し、Pager、Slotted Page、B+Tree、WAL、および VectorStorage をメモリ上（`io.BytesIO` バッファ）で完結させる。
3. **PEP 249 / `sqlite3` 互換 API の完全準拠**: `sqlite3.connect(":memory:")` と全く同一の挙動を `database.connect(":memory:")` および `get_sqlite_connection(":memory:")` で保証する。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 ゼロ外部依存・純粋Python SQLite互換＆分散ベクトルデータベース基盤包括的アーキテクチャ設計書](../designs/DSN-14-pure_python_sqlite_and_distributed_vector_db.md) (Section 2.1 VFS層, Section 2.2 Pager層, Section 5.1 PEP 249)
- 関連コンポーネント:
  - `src/database/storage/vfs.py` (`MemoryVFS`, `MemoryVFSFile`)
  - `src/database/storage/storage.py` (`VectorStorage`)
  - `src/database/ipc/driver.py` (`Connection`, `connect`)
  - `src/database/compat/sqlite_engine.py` (`get_sqlite_connection`, `_open_raw_sqlite_connection`)
  - `src/database/pager/pager.py` (`Pager`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [src/database/compat/sqlite_engine.py](../../src/database/compat/sqlite_engine.py) (`_open_raw_sqlite_connection` で `:memory:` 時に `os.path.abspath` / `os.makedirs` をスキップし `sqlite3.connect(":memory:")` を直接返却)
- [ ] [src/database/storage/storage.py](../../src/database/storage/storage.py) (`VectorStorage` における `:memory:` 判定、`io.BytesIO` バッファへの切り替え、mmap の安全バイパス)
- [ ] [src/database/ipc/driver.py](../../src/database/ipc/driver.py) (`Connection` / `connect` における `:memory:` 判定とインメモリストレージバインド)
- [ ] [src/database/pager/pager.py](../../src/database/pager/pager.py) (`Pager` の初期化時に `path == ":memory:"` の場合、自動的に `MemoryVFS` を採用)
- [ ] [tests/database/test_in_memory_mode.py](../../tests/database/test_in_memory_mode.py) (新規単体テスト: PEP 249, sqlite3 互換, VectorStorage, Pager の `:memory:` 動作検証)

---

## 4. 実装方針と詳細ステップ / Implementation Plan

Target Branch: `feat/212-support-in-memory-database-mode`

### Step 1: `sqlite_engine.py` の `:memory:` パス解決バイパス
1. `_open_raw_sqlite_connection(db_path: str, read_only: bool, timeout: float)`:
   - `if db_path in (":memory:", ""):` を先頭で判定。
   - `os.path.abspath` および `os.makedirs` の呼び出しを完全にスキップ。
   - `sqlite3.connect(":memory:", timeout=timeout)` を即座に返却。
   - WAL プラグマ（`PRAGMA journal_mode=WAL`）はインメモリモードでは `memory` または `off` となるため、不整合を起こさないようガード。

### Step 2: `VectorStorage` のインメモリモード実装 (`src/database/storage/storage.py`)
1. `VectorStorage.__init__(self, file_path: str, dim: int = 128)`:
   - `self.is_memory = (file_path == ":memory:")`
   - `if not self.is_memory: self.file_path = os.path.abspath(file_path)`
   - インメモリモード時:
     - 物理ファイルを作成せず、内部バッファ `self._memory_buffer = io.BytesIO()` を確保。
     - `mmap` はディスクファイル用のため、インメモリモード時は `self._mmap = None` とし、ベクトル読み書きはバッファスライスまたは `self._memory_vectors: List[np.ndarray / bytes]` で高速処理。
     - `save()` / `flush()` は `io.BytesIO` 内でのみ更新し、ディスク書き込みを行わない。

### Step 3: PEP 249 ドライバ `Connection` / `connect` の統合 (`src/database/ipc/driver.py`)
1. `connect(database: str = "outputs/database/papers.vdb", ...)`:
   - `database=":memory:"` を許可。
   - `Connection(file_path=":memory:", ...)` がインメモリ `VectorStorage` およびプロトコルハンドラーを初期化。
   - `conn.cursor().execute(...)` でインメモリテーブル作成・クエリ・ロールバックが透過的に動作することを保証。

### Step 4: `Pager` / `VFS` のインメモリ自動解決 (`src/database/pager/pager.py`)
1. `Pager.__init__(self, path: str, ...)`:
   - `if path == ":memory:" and vfs is None:` の場合、デフォルトの `PosixVFS` ではなく `MemoryVFS()` を自動バインド。
   - スロッテッドページや B+Tree の全ページキャッシュがプロセス終了とともに自動破棄されるクリーンなインメモリライフサイクルを確立。

### Step 5: 包括的テストスイートの作成 (`tests/database/test_in_memory_mode.py`)
1. `test_sqlite_engine_in_memory`: `get_sqlite_connection(":memory:")` でテーブル作成、UDF (KNN, COSINE_SIM, EMBED) 実行、データ挿入・検索がディスクファイルを作成せず完結することの検証。
2. `test_vector_storage_in_memory`: `VectorStorage(":memory:")` でベクトルの追加、最近傍探索、メタデータ保存がインメモリで動作することの検証。
3. `test_pep249_driver_in_memory`: `database.connect(":memory:")` から PEP 249 カーソル経由で SQL が正常動作することの検証。
4. `test_pager_in_memory`: `Pager(":memory:")` がディスクにファイルを残さず `MemoryVFS` で 4KB ページ管理を行うことの検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `database.connect(":memory:")` により、ディスク上に物理ファイルを作成することなくインメモリ接続が確立できること。
- [ ] `get_sqlite_connection(":memory:")` がカレントディレクトリに `":memory:"` ファイルを作成せず、純粋な SQLite インメモリ DB を返却すること。
- [ ] `VectorStorage(":memory:")` が `io.BytesIO` 駆動で正常にベクトル追加・検索・メタデータ操作を行えること。
- [ ] `Pager(":memory:")` が `MemoryVFS` を自動選択し、メモリ上でスロッテッドページ I/O を完結できること。
- [ ] 新規単体テスト（`tests/database/test_in_memory_mode.py`）が全件 PASS すること。
- [ ] 既存の全データベーステスト（`tests/database/`）および全体テストスイートにリグレッションが発生しないこと。
- [ ] `make check_format` および `make static_analysis`（mypy --strict, radon/xenon Grade A CC <= 5）を 100% 満たすこと。
