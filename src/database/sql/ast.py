#!/usr/bin/env python3
"""
Abstract Syntax Tree (AST) Nodes & Enums for Pure Python SQL Engine.
Supports 5 major SQL categories: DDL, DQL, DML, DCL, TCL.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class SQLCommandType(str, Enum):
    # DDL
    CREATE_TABLE = "CREATE_TABLE"
    DROP_TABLE = "DROP_TABLE"
    CREATE_INDEX = "CREATE_INDEX"

    # DQL
    SELECT = "SELECT"
    EXPLAIN = "EXPLAIN"

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

    # Metadata & Inspection
    SHOW = "SHOW"

    @property
    def category(self) -> str:
        """Returns the high-level SQL category (DDL, DQL, DML, DCL, TCL)."""
        return _resolve_cmd_category(self)


_CMD_CATEGORY_MAP: Dict[SQLCommandType, str] = {
    SQLCommandType.CREATE_TABLE: "DDL",
    SQLCommandType.DROP_TABLE: "DDL",
    SQLCommandType.CREATE_INDEX: "DDL",
    SQLCommandType.SELECT: "DQL",
    SQLCommandType.SHOW: "DQL",
    SQLCommandType.EXPLAIN: "DQL",
    SQLCommandType.INSERT: "DML",
    SQLCommandType.UPDATE: "DML",
    SQLCommandType.DELETE: "DML",
    SQLCommandType.GRANT: "DCL",
    SQLCommandType.REVOKE: "DCL",
    SQLCommandType.BEGIN: "TCL",
    SQLCommandType.COMMIT: "TCL",
    SQLCommandType.ROLLBACK: "TCL",
}


def _resolve_cmd_category(cmd: SQLCommandType) -> str:
    """Returns SQL category string for a command."""
    return _CMD_CATEGORY_MAP.get(cmd, "OTHER")


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

    @property
    def category(self) -> str:
        return self.command_type.category


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


class JoinType(str, Enum):
    INNER = "INNER"
    LEFT = "LEFT"
    RIGHT = "RIGHT"
    CROSS = "CROSS"


@dataclass
class TableRef:
    name: str
    alias: Optional[str] = None

    @property
    def display_name(self) -> str:
        return self.alias or self.name


@dataclass
class JoinClause:
    join_type: JoinType
    table: TableRef
    on_conditions: List[Dict[str, Any]] = field(default_factory=list)


@dataclass
class CTEDefinition:
    name: str
    statement: Any  # SelectStatement
    columns: List[str] = field(default_factory=list)
    is_recursive: bool = False


# DQL
@dataclass
class SelectStatement(SQLStatement):
    table_name: str = ""
    table_ref: Optional[TableRef] = None
    columns: List[str] = field(default_factory=list)
    where_clauses: List[Dict[str, Any]] = field(default_factory=list)
    knn_query: Optional[Dict[str, Any]] = (
        None  # {"column": str, "vector": [...], "top_k": int}
    )
    joins: List[JoinClause] = field(default_factory=list)
    ctes: List[CTEDefinition] = field(default_factory=list)
    union_all: Optional[Any] = None  # SelectStatement
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


# EXPLAIN
@dataclass
class ExplainStatement(SQLStatement):
    statement: Optional[SQLStatement] = None
    query_plan: bool = True


# SHOW (SHOW DATABASES, SHOW TABLES, SHOW TABLE STATUS)
@dataclass
class ShowStatement(SQLStatement):
    target: str = "TABLES"  # DATABASES, TABLES, SCHEMAS, TABLE_STATUS
    from_database: Optional[str] = None
    like_pattern: Optional[str] = None
