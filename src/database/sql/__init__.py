#!/usr/bin/env python3
"""
Pure Python SQL Engine Subpackage.
Supports DDL, DQL, DML, DCL, and TCL commands for vector and relational operations.
"""

from .admin_parser import SQLAdminParser, parse_admin
from .ast import (
    BeginStatement,
    ColumnDef,
    CommitStatement,
    CreateIndexStatement,
    CreateTableStatement,
    DeleteStatement,
    DropTableStatement,
    GrantStatement,
    InsertStatement,
    RevokeStatement,
    RollbackStatement,
    SelectStatement,
    SQLCommandType,
    SQLStatement,
    UpdateStatement,
)
from .ddl_parser import SQLDDLParser, parse_ddl
from .dml_parser import SQLDMLParser, parse_dml
from .dql_parser import SQLDQLParser, parse_dql
from .executor import SQLExecutionError, SQLExecutor, TableCatalog
from .expr_parser import (
    BetweenExpr,
    BinaryOpExpr,
    CaseExpr,
    ColumnRefExpr,
    FunctionCallExpr,
    InExpr,
    IsNullExpr,
    LikeExpr,
    LiteralExpr,
    SQLExpr,
    SQLExpressionParser,
    UnaryOpExpr,
    parse_sql_expr,
)
from .parser import SQLParseError, SQLParser, parse_sql
from .security import AccessController, DCLPermissionDeniedError
from .transaction import TransactionError, TransactionManager

__all__ = [
    "SQLCommandType",
    "SQLStatement",
    "CreateTableStatement",
    "DropTableStatement",
    "CreateIndexStatement",
    "SelectStatement",
    "InsertStatement",
    "UpdateStatement",
    "DeleteStatement",
    "GrantStatement",
    "RevokeStatement",
    "BeginStatement",
    "CommitStatement",
    "RollbackStatement",
    "ColumnDef",
    "SQLParser",
    "SQLParseError",
    "SQLExecutor",
    "SQLExecutionError",
    "TableCatalog",
    "AccessController",
    "DCLPermissionDeniedError",
    "TransactionManager",
    "TransactionError",
    "SQLExpr",
    "LiteralExpr",
    "ColumnRefExpr",
    "UnaryOpExpr",
    "BinaryOpExpr",
    "BetweenExpr",
    "InExpr",
    "IsNullExpr",
    "LikeExpr",
    "FunctionCallExpr",
    "CaseExpr",
    "SQLExpressionParser",
    "parse_sql_expr",
    "SQLDQLParser",
    "parse_dql",
    "SQLDMLParser",
    "parse_dml",
    "SQLDDLParser",
    "parse_ddl",
    "SQLAdminParser",
    "parse_admin",
    "parse_sql",
]
