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
    ALTER_TABLE = "ALTER_TABLE"
    CREATE_INDEX = "CREATE_INDEX"
    DROP_INDEX = "DROP_INDEX"
    REINDEX = "REINDEX"
    CREATE_VIEW = "CREATE_VIEW"
    DROP_VIEW = "DROP_VIEW"
    CREATE_TRIGGER = "CREATE_TRIGGER"
    DROP_TRIGGER = "DROP_TRIGGER"
    CREATE_VIRTUAL_TABLE = "CREATE_VIRTUAL_TABLE"

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
    SAVEPOINT = "SAVEPOINT"
    RELEASE = "RELEASE"
    ROLLBACK_TO = "ROLLBACK_TO"

    # Metadata & Inspection    # Admin / Maintenance
    SHOW = "SHOW"
    PRAGMA = "PRAGMA"
    VACUUM = "VACUUM"
    ANALYZE = "ANALYZE"
    ATTACH = "ATTACH"
    DETACH = "DETACH"

    @property
    def category(self) -> str:
        """Returns the high-level SQL category (DDL, DQL, DML, DCL, TCL)."""
        return _resolve_cmd_category(self)


_CMD_CATEGORY_MAP: Dict[SQLCommandType, str] = {
    SQLCommandType.CREATE_TABLE: "DDL",
    SQLCommandType.DROP_TABLE: "DDL",
    SQLCommandType.ALTER_TABLE: "DDL",
    SQLCommandType.CREATE_INDEX: "DDL",
    SQLCommandType.DROP_INDEX: "DDL",
    SQLCommandType.REINDEX: "DDL",
    SQLCommandType.CREATE_VIEW: "DDL",
    SQLCommandType.DROP_VIEW: "DDL",
    SQLCommandType.CREATE_TRIGGER: "DDL",
    SQLCommandType.DROP_TRIGGER: "DDL",
    SQLCommandType.CREATE_VIRTUAL_TABLE: "DDL",
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
    SQLCommandType.PRAGMA: "ADMIN",
    SQLCommandType.VACUUM: "ADMIN",
    SQLCommandType.ANALYZE: "ADMIN",
    SQLCommandType.ATTACH: "DDL",
    SQLCommandType.DETACH: "DDL",
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
    storage_engine: Optional[str] = None
    location: Optional[str] = None


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


class AlterTableAction(str, Enum):
    RENAME_TABLE = "RENAME_TABLE"
    RENAME_COLUMN = "RENAME_COLUMN"
    ADD_COLUMN = "ADD_COLUMN"
    DROP_COLUMN = "DROP_COLUMN"


@dataclass
class AlterTableStatement(SQLStatement):
    table_name: str = ""
    action: AlterTableAction = AlterTableAction.RENAME_TABLE
    new_table_name: Optional[str] = None
    old_column_name: Optional[str] = None
    new_column_name: Optional[str] = None
    column_def: Optional[ColumnDef] = None
    default_value: Any = None
    drop_column_name: Optional[str] = None


@dataclass
class DropIndexStatement(SQLStatement):
    index_name: str = ""
    if_exists: bool = False


@dataclass
class ReindexStatement(SQLStatement):
    target_name: Optional[str] = None  # None: all, or specific table/index name


@dataclass
class CreateViewStatement(SQLStatement):
    view_name: str = ""
    select_stmt: Optional[Any] = None  # SelectStatement
    if_not_exists: bool = False


@dataclass
class DropViewStatement(SQLStatement):
    view_name: str = ""
    if_exists: bool = False


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


@dataclass
class WindowSpec:
    partition_by: List[str] = field(default_factory=list)
    order_by: Optional[str] = None
    order_desc: bool = False


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
    union: Optional[Any] = None  # SelectStatement (UNION distinct)
    union_all: Optional[Any] = None  # SelectStatement (UNION ALL)
    intersect: Optional[Any] = None  # SelectStatement (INTERSECT)
    except_: Optional[Any] = None  # SelectStatement (EXCEPT)
    order_by: Optional[str] = None
    order_desc: bool = False
    limit: Optional[int] = None
    offset: Optional[int] = None
    distinct: bool = False
    group_by: List[str] = field(default_factory=list)
    having: Optional[str] = None


# DML
@dataclass
class InsertStatement(SQLStatement):
    table_name: str = ""
    columns: List[str] = field(default_factory=list)
    values: List[Any] = field(default_factory=list)
    rows_values: List[List[Any]] = field(default_factory=list)
    select_stmt: Optional[Any] = None  # SelectStatement
    upsert_target: Optional[List[str]] = None
    upsert_action: Optional[str] = None  # "NOTHING" or "UPDATE"
    upsert_update_set: Dict[str, Any] = field(default_factory=dict)
    returning_cols: Optional[List[str]] = None


@dataclass
class UpdateStatement(SQLStatement):
    table_name: str = ""
    assignments: Dict[str, Any] = field(default_factory=dict)
    where_clauses: List[Dict[str, Any]] = field(default_factory=list)
    returning_cols: Optional[List[str]] = None
    order_by: Optional[str] = None
    order_desc: bool = False
    limit: Optional[int] = None


@dataclass
class DeleteStatement(SQLStatement):
    table_name: str = ""
    where_clauses: List[Dict[str, Any]] = field(default_factory=list)
    returning_cols: Optional[List[str]] = None
    order_by: Optional[str] = None
    order_desc: bool = False
    limit: Optional[int] = None


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


# Savepoint (SAVEPOINT, RELEASE, ROLLBACK TO)
@dataclass
class SavepointStatement(SQLStatement):
    name: str = ""
    action: str = "SAVEPOINT"  # SAVEPOINT, RELEASE, ROLLBACK_TO


# PRAGMA
@dataclass
class PragmaStatement(SQLStatement):
    pragma_name: str = ""
    argument: Optional[str] = None
    value: Optional[str] = None


# VACUUM
@dataclass
class VacuumStatement(SQLStatement):
    target_table: Optional[str] = None
    into_file: Optional[str] = None


# Trigger (CREATE TRIGGER, DROP TRIGGER)
@dataclass
class CreateTriggerStatement(SQLStatement):
    trigger_name: str = ""
    timing: str = "AFTER"  # BEFORE, AFTER, INSTEAD OF
    event: str = "INSERT"  # INSERT, UPDATE, DELETE
    table_name: str = ""
    for_each_row: bool = True
    body_sqls: List[str] = field(default_factory=list)


@dataclass
class DropTriggerStatement(SQLStatement):
    trigger_name: str = ""
    if_exists: bool = False


# ANALYZE
@dataclass
class AnalyzeStatement(SQLStatement):
    target_name: Optional[str] = None
    schema_name: Optional[str] = None


# ATTACH / DETACH
@dataclass
class AttachStatement(SQLStatement):
    filename: str = ""
    schema_name: str = ""


@dataclass
class DetachStatement(SQLStatement):
    schema_name: str = ""


# VIRTUAL TABLE
@dataclass
class CreateVirtualTableStatement(SQLStatement):
    table_name: str = ""
    module_name: str = ""
    module_args: List[str] = field(default_factory=list)
    if_not_exists: bool = False
