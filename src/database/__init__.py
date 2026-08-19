#!/usr/bin/env python3
"""
Database Package for arXiv Security Papers.
Provides zero-dependency binary vector storage, pure Python HNSW graph indexing,
deterministic embeddings, SQLite-inspired 4-tier modular architecture
(VFS, Pager/PageCache, VDBE Bytecode VM, SQL Compiler/CodeGen),
PEP 249 DB-API 2.0 driver, and 100% compatible Python standard `sqlite3` client interfaces.
"""

from .btree import BPlusTree, BTreeNode, ScalarKey
from .client import VectorDBClient
from .codegen import CodeGenerator
from .compiler import SQLCompiler
from .driver import Connection, Cursor, DatabaseError, connect
from .embedding import DeterministicEmbedding
from .index import HNSWIndex
from .pager import PAGE_SIZE, Page, PageCache, Pager
from .planner import (
    ColumnStats,
    CostModel,
    ExecutionPlan,
    PlanType,
    QueryPlanner,
    TableStats,
)
from .profiler import DatabaseProfiler, ProfileResult
from .protocol import VectorDBProtocolError, VectorDBProtocolHandler
from .recovery import ARIESRecoveryManager
from .slotted_page import (
    DataType,
    OverflowManager,
    PageCorruptionError,
    PageFullError,
    PageType,
    SlottedPage,
    SlottedPageError,
    TupleSerializer,
)
from .sql import (
    AccessController,
    DCLPermissionDeniedError,
    SQLCommandType,
    SQLExecutionError,
    SQLExecutor,
    SQLParseError,
    SQLParser,
    SQLStatement,
    TableCatalog,
    TransactionError,
    TransactionManager,
)
from .sqlite_bridge import attach_to_sqlite
from .sqlite_engine import (
    get_sqlite_connection,
    register_vector_functions,
    sync_from_vector_storage,
    sync_to_vector_storage,
)
from .storage import VectorStorage, VectorStorageSecurityError
from .vdbe import VDBE, Instruction, OpCode, Statement, StepResult, VDBEProgram
from .vfs import (
    VFS,
    MemoryVFS,
    MemoryVFSFile,
    PosixVFS,
    PosixVFSFile,
    VFSFile,
    get_vfs,
    register_vfs,
)
from .wal import (
    WAL_HEADER_SIZE,
    WAL_MAGIC,
    WAL_VERSION,
    LogRecord,
    LogRecordType,
    WALReader,
    WALWriter,
)

__all__ = [
    # Storage & Indexing
    "VectorStorage",
    "VectorStorageSecurityError",
    "DeterministicEmbedding",
    "HNSWIndex",
    # VFS (OS Abstraction Layer)
    "VFS",
    "VFSFile",
    "PosixVFS",
    "PosixVFSFile",
    "MemoryVFS",
    "MemoryVFSFile",
    "get_vfs",
    "register_vfs",
    # Pager (Storage Backend & Cache)
    "Pager",
    "PageCache",
    "Page",
    "PAGE_SIZE",
    # Write-Ahead Logging & ARIES Recovery
    "LogRecord",
    "LogRecordType",
    "WALWriter",
    "WALReader",
    "WAL_MAGIC",
    "WAL_VERSION",
    "WAL_HEADER_SIZE",
    "ARIESRecoveryManager",
    # Slotted Page Binary Storage
    "SlottedPage",
    "TupleSerializer",
    "OverflowManager",
    "PageType",
    "DataType",
    "SlottedPageError",
    "PageCorruptionError",
    "PageFullError",
    # B+Tree Engine
    "BPlusTree",
    "BTreeNode",
    "ScalarKey",
    # Cost-Based Query Planner
    "QueryPlanner",
    "ExecutionPlan",
    "TableStats",
    "ColumnStats",
    "CostModel",
    "PlanType",
    # VDBE (Core Virtual Machine)
    "VDBE",
    "VDBEProgram",
    "OpCode",
    "Instruction",
    "Statement",
    "StepResult",
    # Compiler (Frontend)
    "SQLCompiler",
    "CodeGenerator",
    # Protocol & Client
    "VectorDBProtocolHandler",
    "VectorDBProtocolError",
    "VectorDBClient",
    # SQL AST & Executor
    "SQLCommandType",
    "SQLStatement",
    "SQLParser",
    "SQLParseError",
    "SQLExecutor",
    "SQLExecutionError",
    "TableCatalog",
    "AccessController",
    "DCLPermissionDeniedError",
    "TransactionManager",
    "TransactionError",
    # Drivers & Bridges
    "connect",
    "Connection",
    "Cursor",
    "DatabaseError",
    "attach_to_sqlite",
    "get_sqlite_connection",
    "register_vector_functions",
    "sync_from_vector_storage",
    "sync_to_vector_storage",
    # Profiler & Metrics
    "DatabaseProfiler",
    "ProfileResult",
]
