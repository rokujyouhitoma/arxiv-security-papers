---
ID: 103
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] Refactor and Reorganize src/database Package Structure (ID: 103)

## 1. 概要 / Summary
現在 `src/database/` 直下には 22 本の Python モジュール（`pager.py`, `slotted_page.py`, `buffer_pool.py`, `wal.py`, `mvcc.py`, `lock_manager.py`, `recovery.py`, `vdbe.py`, `compiler.py`, `codegen.py`, `client.py`, `service.py`, `driver.py`, `protocol.py`, `index.py`, `embedding.py`, `sqlite_bridge.py`, `sqlite_engine.py`, `profiler.py`, `storage.py`, `vfs.py` 等）がフラットに配置されており、内部責務の境界が曖昧になっています。

本 Issue では、クリーンアーキテクチャおよび高凝集・低結合（High Cohesion & Loose Coupling）の原則に基づき、`src/database/` 直下のモジュール群を **6 大サブパッケージ**（`storage/`, `transaction/`, `ipc/`, `vdbe/`, `index/`, `compat/`）へ体系的に再編・整理し、後方互換性ファサードを確立します。

---

## 2. トレーサビリティ / Traceability
- **Governance & Rules**:
  - [AGENTS.md](../../.agents/AGENTS.md) (Section 1: Database / Data Infrastructure Specialist Governance)
- **Design Architecture**:
  - [DSN-01 High-Level Architecture Design](../designs/DSN-01-high_level_design.md) (Section 5: Core Database Layer)
  - [DSN-08 Database Subsystem](../designs/DSN-08-database-subsystem.md) (Storage, Concurrency, IPC, VDBE specifications)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 1. 新設サブパッケージ
- [x] `src/database/storage/`:
  - `__init__.py`
  - `buffer_pool.py` (← `src/database/buffer_pool.py`)
  - `pager.py` (← `src/database/pager.py`)
  - `slotted_page.py` (← `src/database/slotted_page.py`)
  - `storage.py` (← `src/database/storage.py`)
  - `vfs.py` (← `src/database/vfs.py`)
- [x] `src/database/transaction/`:
  - `__init__.py`
  - `mvcc.py` (← `src/database/mvcc.py`)
  - `lock_manager.py` (← `src/database/lock_manager.py`)
  - `wal.py` (← `src/database/wal.py`)
  - `recovery.py` (← `src/database/recovery.py`)
- [x] `src/database/ipc/`:
  - `__init__.py`
  - `client.py` (← `src/database/client.py`)
  - `service.py` (← `src/database/service.py`)
  - `driver.py` (← `src/database/driver.py`)
  - `protocol.py` (← `src/database/protocol.py`)
- [x] `src/database/vdbe/`:
  - `__init__.py`
  - `vdbe.py` (← `src/database/vdbe.py`)
  - `compiler.py` (← `src/database/compiler.py`)
  - `codegen.py` (← `src/database/codegen.py`)
- [x] `src/database/index/`:
  - `__init__.py`
  - `index.py` (← `src/database/index.py`)
  - `embedding.py` (← `src/database/embedding.py`)
- [x] `src/database/compat/`:
  - `__init__.py`
  - `sqlite_bridge.py` (← `src/database/sqlite_bridge.py`)
  - `sqlite_engine.py` (← `src/database/sqlite_engine.py`)
  - `profiler.py` (← `src/database/profiler.py`)

### 2. ファサードおよび互換レイヤー
- [x] `src/database/__init__.py`: 全サブパッケージからの主要クラス・関数 re-export
- [x] `src/database/*.py` (旧ファイル): 後方互換性 shim（`from database.storage.pager import *` 等のエイリアス）

### 3. テストスイート
- [x] `tests/database/` 配下の全テスト（30+ ファイル）

---

## 4. 詳細マッピングと再編アーキテクチャ

```
src/database/
├── __init__.py                # Root Facade (Re-exports all core public APIs)
├── storage/                   # [Physical Storage & Page Cache Layer]
│   ├── __init__.py
│   ├── vfs.py                 # Virtual File System abstraction
│   ├── pager.py               # Pager, Page, PageCache, Disk I/O
│   ├── slotted_page.py        # SlottedPage, TupleRecord, Layout
│   ├── buffer_pool.py         # 2Q BufferPool, BufferFrame
│   └── storage.py             # VectorStorage persistence
├── transaction/               # [Concurrency, Locking, WAL & Crash Recovery]
│   ├── __init__.py
│   ├── mvcc.py                # MVCCManager, Snapshot Isolation
│   ├── lock_manager.py        # SS2PL LockManager, DeadlockDetector
│   ├── wal.py                 # Write-Ahead Log engine, WALFrame
│   └── recovery.py            # ARIES Crash Recovery & Redo/Undo
├── ipc/                       # [IPC Protocol, Client/Server & Driver Layer]
│   ├── __init__.py
│   ├── protocol.py            # Binary & JSON IPC frame contracts
│   ├── client.py              # DatabaseClient, VectorDBClient (UDS)
│   ├── service.py             # DatabaseService arbiter daemon
│   └── driver.py              # PEP 249 DB-API 2.0 connection/cursor
├── vdbe/                      # [Virtual Machine, Compiler & CodeGen]
│   ├── __init__.py
│   ├── vdbe.py                # VDBE Bytecode VM & OpCodes
│   ├── compiler.py            # SQL AST to Bytecode compiler
│   └── codegen.py             # Intermediate code generator
├── index/                     # [Vector & High-Dimensional Indexing]
│   ├── __init__.py
│   ├── index.py               # Pure Python HNSW vector graph index
│   └── embedding.py           # Deterministic semantic embedding
├── compat/                    # [SQLite Compatibility & Profiling]
│   ├── __init__.py
│   ├── sqlite_bridge.py       # sqlite3 C API bridge
│   ├── sqlite_engine.py       # In-memory / temp SQLite engine
│   └── profiler.py            # Query latency & resource profiler
├── btree/                     # (既存: B+Tree)
├── cow/                       # (既存: CoW B-Tree)
├── distributed/               # (既存: Raft / CRDT / Cluster)
├── engine/                    # (既存: Volcano Iterator & Vectorized Execution)
├── lsm/                       # (既存: LSM-Tree & SSTable)
├── pax/                       # (既存: Columnar PAX)
├── planner/                   # (既存: CBO Optimizer)
└── sql/                       # (既存: SQL Parser, AST & Executor)
```

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/103-refactor-database-package-structure`

1. **サブパッケージディレクトリ作成 & ファイル移動**:
   - `mkdir -p src/database/{storage,transaction,ipc,vdbe,index,compat}`
   - 各サブパッケージへファイルを配置し、`__init__.py` でパッケージ内公開クラスを定義。
2. **内部インポートパスの整合化**:
   - 各サブモジュール内の相対・絶対インポートを `from database.storage.pager import Pager` 等に調整。
3. **Root `__init__.py` ファサードの更新**:
   - `src/database/__init__.py` の re-export を新サブパッケージに対応。
4. **互換性 Shim モジュールの維持 (`src/database/*.py`)**:
   - `pager.py`, `client.py`, `wal.py` 等に deprecation warning なしの透過的 re-export を記述し、他パッケージやテストからの既存インポートを 100% 透過。
5. **テスト・品質ゲート一括検証**:
   - `pytest tests/database/` (100% PASS)
   - `make format` & `make check` (flake8, isort, black, xenon) PASS 確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/database/` 直下のモジュールが 6 つの責務別サブパッケージへ再配置されていること
- [x] 各サブパッケージが独立した `__init__.py` を持ち、自己完結していること
- [x] `src/database/__init__.py` および互換 Shim により、既存のすべてのインポート（`from database.client import DatabaseClient` 等）が 100% 動作すること
- [x] `tests/database/` 配下の全テスト（約 35 ファイル、数百テストケース）がエラーなく 100% PASS すること
- [x] `src/web/`, `src/supervisor/`, `src/graph/` 等の連携モジュールが問題なく動作すること
- [x] `make check` の静的解析・品質ゲートがすべて PASS すること
