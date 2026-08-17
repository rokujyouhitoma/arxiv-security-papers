#!/usr/bin/env python3
"""
Abstract Syntax Tree (AST) Nodes & Enums for Pure Python SQL Engine.
Supports 5 major SQL categories: DDL, DQL, DML, DCL, TCL.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Sequence


class SQLCommandType(str, Enum):
    # DDL
    CREATE_TABLE = "CREATE_TABLE"
    DROP_TABLE = "DROP_TABLE"
    CREATE_INDEX = "CREATE_INDEX"

    # DQL
    SELECT = "SELECT"

    # DML
    INSERT = "INSERT"
    UPDATE = "UPDATE"
    DELETE = "DELETE"

    # DCL
    GRANT = "GRANT"
    REVOKE = "REVOKE"

    # TCL
    BEGIN = "BEGIN"
    COMMIT = "COMMIT"
    ROLLBACK = "ROLLBACK"


@dataclass
class ColumnDef:
    name: str
    data_type: str  # e.g., "VARCHAR", "INT", "FLOAT", "VECTOR(128)", "JSON", "TEXT"
    is_primary_key: bool = False
    is_nullable: bool = True


@dataclass
class SQLStatement:
    command_type: SQLCommandType
    raw_sql: str


# DDL
@dataclass
class CreateTableStatement(SQLStatement):
    table_name: str = ""
    columns: List[ColumnDef] = field(default_factory=list)
    if_not_exists: bool = False


@dataclass
class DropTableStatement(SQLStatement):
    table_name: str = ""
    if_exists: bool = False


@dataclass
class CreateIndexStatement(SQLStatement):
    index_name: str = ""
    table_name: str = ""
    column_name: str = ""
    index_type: str = "HNSW"  # HNSW, INVERTED, BTREE


# DQL
@dataclass
class SelectStatement(SQLStatement):
    table_name: str = ""
    columns: List[str] = field(default_factory=list)
    where_clauses: List[Dict[str, Any]] = field(default_factory=list)
    knn_query: Optional[Dict[str, Any]] = (
        None  # {"column": str, "vector": [...], "top_k": int}
    )
    order_by: Optional[str] = None
    order_desc: bool = False
    limit: Optional[int] = None


# DML
@dataclass
class InsertStatement(SQLStatement):
    table_name: str = ""
    columns: List[str] = field(default_factory=list)
    values: List[Any] = field(default_factory=list)


@dataclass
class UpdateStatement(SQLStatement):
    table_name: str = ""
    assignments: Dict[str, Any] = field(default_factory=dict)
    where_clauses: List[Dict[str, Any]] = field(default_factory=list)


@dataclass
class DeleteStatement(SQLStatement):
    table_name: str = ""
    where_clauses: List[Dict[str, Any]] = field(default_factory=list)


# DCL
@dataclass
class GrantStatement(SQLStatement):
    permission: str = ""  # SELECT, INSERT, UPDATE, DELETE, ALL
    table_name: str = ""
    role: str = ""


@dataclass
class RevokeStatement(SQLStatement):
    permission: str = ""
    table_name: str = ""
    role: str = ""


# TCL
@dataclass
class BeginStatement(SQLStatement):
    pass


@dataclass
class CommitStatement(SQLStatement):
    pass


@dataclass
class RollbackStatement(SQLStatement):
    pass
