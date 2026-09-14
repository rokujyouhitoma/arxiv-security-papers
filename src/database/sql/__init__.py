#!/usr/bin/env python3
"""
Pure Python SQL Engine Subpackage.
Supports DDL, DQL, DML, DCL, and TCL commands for vector and relational operations.
"""

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
from .parser import SQLParseError, SQLParser
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
]
