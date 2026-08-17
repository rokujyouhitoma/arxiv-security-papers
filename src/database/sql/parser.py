#!/usr/bin/env python3
"""
Pure Python SQL Lexer & Parser.
Parses standard SQL statements into typed AST objects without external dependencies.
"""

import ast as py_ast
import json
import re
from typing import Any, Dict, List, Optional, Tuple

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


class SQLParseError(Exception):
    """Raised when SQL syntax cannot be parsed."""

    pass


class SQLParser:
    """
    Parses SQL string queries into structured SQLStatement AST nodes.
    """

    def parse(self, sql_query: str) -> SQLStatement:
        sql = sql_query.strip().rstrip(";")
        if not sql:
            raise SQLParseError("Empty SQL query")

        upper_sql = sql.upper()

        # TCL
        if re.match(r"^BEGIN(\s+TRANSACTION)?$", upper_sql):
            return BeginStatement(command_type=SQLCommandType.BEGIN, raw_sql=sql)
        if re.match(r"^COMMIT$", upper_sql):
            return CommitStatement(command_type=SQLCommandType.COMMIT, raw_sql=sql)
        if re.match(r"^ROLLBACK$", upper_sql):
            return RollbackStatement(command_type=SQLCommandType.ROLLBACK, raw_sql=sql)

        # DDL
        if upper_sql.startswith("CREATE TABLE"):
            return self._parse_create_table(sql)
        if upper_sql.startswith("DROP TABLE"):
            return self._parse_drop_table(sql)
        if upper_sql.startswith("CREATE INDEX"):
            return self._parse_create_index(sql)

        # DQL
        if upper_sql.startswith("SELECT"):
            return self._parse_select(sql)

        # DML
        if upper_sql.startswith("INSERT INTO"):
            return self._parse_insert(sql)
        if upper_sql.startswith("UPDATE"):
            return self._parse_update(sql)
        if upper_sql.startswith("DELETE FROM"):
            return self._parse_delete(sql)

        # DCL
        if upper_sql.startswith("GRANT"):
            return self._parse_grant(sql)
        if upper_sql.startswith("REVOKE"):
            return self._parse_revoke(sql)

        raise SQLParseError(f"Unsupported or unrecognized SQL statement: '{sql}'")

    def _parse_create_table(self, sql: str) -> CreateTableStatement:
        m = re.match(
            r"CREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_]+)\s*\((.*)\)",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed CREATE TABLE syntax: {sql}")

        if_not_exists = bool(m.group(1))
        table_name = m.group(2)
        cols_body = m.group(3).strip()

        col_defs: List[ColumnDef] = []
        # Split top-level commas
        for raw_col in cols_body.split(","):
            raw_col = raw_col.strip()
            if not raw_col:
                continue
            parts = raw_col.split()
            c_name = parts[0]
            c_type = parts[1] if len(parts) > 1 else "TEXT"
            is_pk = "PRIMARY KEY" in raw_col.upper()
            is_nullable = "NOT NULL" not in raw_col.upper()
            col_defs.append(
                ColumnDef(
                    name=c_name,
                    data_type=c_type,
                    is_primary_key=is_pk,
                    is_nullable=is_nullable,
                )
            )

        return CreateTableStatement(
            command_type=SQLCommandType.CREATE_TABLE,
            raw_sql=sql,
            table_name=table_name,
            columns=col_defs,
            if_not_exists=if_not_exists,
        )

    def _parse_drop_table(self, sql: str) -> DropTableStatement:
        m = re.match(
            r"DROP\s+TABLE\s+(IF\s+EXISTS\s+)?([a-zA-Z0-9_]+)",
            sql,
            re.IGNORECASE,
        )
        if not m:
            raise SQLParseError(f"Malformed DROP TABLE syntax: {sql}")

        if_exists = bool(m.group(1))
        table_name = m.group(2)
        return DropTableStatement(
            command_type=SQLCommandType.DROP_TABLE,
            raw_sql=sql,
            table_name=table_name,
            if_exists=if_exists,
        )

    def _parse_create_index(self, sql: str) -> CreateIndexStatement:
        m = re.match(
            r"CREATE\s+INDEX\s+([a-zA-Z0-9_]+)\s+ON\s+([a-zA-Z0-9_]+)\s*\(([a-zA-Z0-9_]+)\)(\s+USING\s+([a-zA-Z0-9_]+))?",
            sql,
            re.IGNORECASE,
        )
        if not m:
            raise SQLParseError(f"Malformed CREATE INDEX syntax: {sql}")

        idx_name = m.group(1)
        table_name = m.group(2)
        col_name = m.group(3)
        idx_type = m.group(5) or "HNSW"

        return CreateIndexStatement(
            command_type=SQLCommandType.CREATE_INDEX,
            raw_sql=sql,
            index_name=idx_name,
            table_name=table_name,
            column_name=col_name,
            index_type=idx_type.upper(),
        )

    def _parse_select(self, sql: str) -> SelectStatement:
        # Pattern matching SELECT <cols> FROM <table> [WHERE ...] [ORDER BY ...] [LIMIT ...]
        m = re.match(
            r"SELECT\s+(.+?)\s+FROM\s+([a-zA-Z0-9_]+)(?:\s+WHERE\s+(.+?))?(?:\s+ORDER\s+BY\s+([a-zA-Z0-9_]+)(?:\s+(ASC|DESC))?)?(?:\s+LIMIT\s+([0-9]+))?$",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed SELECT syntax: {sql}")

        cols_raw = m.group(1).strip()
        table_name = m.group(2).strip()
        where_raw = m.group(3)
        order_by = m.group(4)
        order_desc = (m.group(5) or "").upper() == "DESC"
        limit_val = int(m.group(6)) if m.group(6) else None

        columns = ["*"] if cols_raw == "*" else [c.strip() for c in cols_raw.split(",")]

        where_clauses: List[Dict[str, Any]] = []
        knn_query: Optional[Dict[str, Any]] = None

        if where_raw:
            # Check for KNN function: KNN(vector_col, [...], 10)
            knn_m = re.search(
                r"KNN\s*\(\s*([a-zA-Z0-9_]+)\s*,\s*(\[.*?\])\s*,\s*([0-9]+)\s*\)",
                where_raw,
                re.IGNORECASE,
            )
            if knn_m:
                knn_col = knn_m.group(1)
                try:
                    knn_vec = py_ast.literal_eval(knn_m.group(2))
                except Exception as e:
                    raise SQLParseError(f"Invalid vector in KNN clause: {e}") from e
                top_k = int(knn_m.group(3))
                knn_query = {
                    "column": knn_col,
                    "vector": [float(x) for x in knn_vec],
                    "top_k": top_k,
                }
                where_raw = where_raw.replace(knn_m.group(0), "").strip()
                where_raw = re.sub(
                    r"^(AND|OR)\s+", "", where_raw, flags=re.IGNORECASE
                ).strip()
                where_raw = re.sub(
                    r"\s+(AND|OR)$", "", where_raw, flags=re.IGNORECASE
                ).strip()

            # Parse simple equality clauses (only columns starting with letters/underscore)
            eq_matches = re.findall(
                r"([a-zA-Z_][a-zA-Z0-9_]*)\s*(=|!=|>|<)\s*('[^']*'|\"[^\"]*\"|[0-9\.]+)",
                where_raw,
            )
            for col, op, val in eq_matches:
                clean_val = val.strip("'\"")
                if clean_val.isdigit():
                    v: Any = int(clean_val)
                else:
                    try:
                        v = float(clean_val)
                    except ValueError:
                        v = clean_val
                where_clauses.append({"column": col, "operator": op, "value": v})

        return SelectStatement(
            command_type=SQLCommandType.SELECT,
            raw_sql=sql,
            table_name=table_name,
            columns=columns,
            where_clauses=where_clauses,
            knn_query=knn_query,
            order_by=order_by,
            order_desc=order_desc,
            limit=limit_val,
        )

    def _parse_insert(self, sql: str) -> InsertStatement:
        m = re.match(
            r"INSERT\s+INTO\s+([a-zA-Z0-9_]+)\s*\((.+?)\)\s*VALUES\s*\((.+)\)",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed INSERT INTO syntax: {sql}")

        table_name = m.group(1).strip()
        cols_raw = m.group(2).strip()
        vals_raw = m.group(3).strip()

        columns = [c.strip() for c in cols_raw.split(",")]
        # Use python ast literal parsing for safe evaluation of lists, strings, dicts
        try:
            # Wrap as tuple
            parsed_tuple = py_ast.literal_eval(f"({vals_raw})")
            if not isinstance(parsed_tuple, tuple):
                values = [parsed_tuple]
            else:
                values = list(parsed_tuple)
        except Exception:
            # Fallback split
            values = [v.strip().strip("'\"") for v in vals_raw.split(",")]

        if len(columns) != len(values):
            raise SQLParseError(
                f"Column count ({len(columns)}) does not match values count ({len(values)})"
            )

        return InsertStatement(
            command_type=SQLCommandType.INSERT,
            raw_sql=sql,
            table_name=table_name,
            columns=columns,
            values=values,
        )

    def _parse_update(self, sql: str) -> UpdateStatement:
        m = re.match(
            r"UPDATE\s+([a-zA-Z0-9_]+)\s+SET\s+(.+?)(?:\s+WHERE\s+(.+))?$",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed UPDATE syntax: {sql}")

        table_name = m.group(1).strip()
        set_raw = m.group(2).strip()
        where_raw = m.group(3)

        assignments: Dict[str, Any] = {}
        for item in set_raw.split(","):
            if "=" in item:
                k, v = item.split("=", 1)
                assignments[k.strip()] = v.strip().strip("'\"")

        where_clauses: List[Dict[str, Any]] = []
        if where_raw:
            eq_matches = re.findall(
                r"([a-zA-Z0-9_]+)\s*(=|!=)\s*('[^']*'|\"[^\"]*\"|[0-9\.]+)",
                where_raw,
            )
            for col, op, val in eq_matches:
                where_clauses.append(
                    {"column": col, "operator": op, "value": val.strip("'\"")}
                )

        return UpdateStatement(
            command_type=SQLCommandType.UPDATE,
            raw_sql=sql,
            table_name=table_name,
            assignments=assignments,
            where_clauses=where_clauses,
        )

    def _parse_delete(self, sql: str) -> DeleteStatement:
        m = re.match(
            r"DELETE\s+FROM\s+([a-zA-Z0-9_]+)(?:\s+WHERE\s+(.+))?$",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed DELETE syntax: {sql}")

        table_name = m.group(1).strip()
        where_raw = m.group(2)

        where_clauses: List[Dict[str, Any]] = []
        if where_raw:
            eq_matches = re.findall(
                r"([a-zA-Z0-9_]+)\s*(=|!=)\s*('[^']*'|\"[^\"]*\"|[0-9\.]+)",
                where_raw,
            )
            for col, op, val in eq_matches:
                where_clauses.append(
                    {"column": col, "operator": op, "value": val.strip("'\"")}
                )

        return DeleteStatement(
            command_type=SQLCommandType.DELETE,
            raw_sql=sql,
            table_name=table_name,
            where_clauses=where_clauses,
        )

    def _parse_grant(self, sql: str) -> GrantStatement:
        m = re.match(
            r"GRANT\s+([a-zA-Z0-9_]+)\s+ON\s+([a-zA-Z0-9_]+)\s+TO\s+([a-zA-Z0-9_]+)",
            sql,
            re.IGNORECASE,
        )
        if not m:
            raise SQLParseError(f"Malformed GRANT syntax: {sql}")

        return GrantStatement(
            command_type=SQLCommandType.GRANT,
            raw_sql=sql,
            permission=m.group(1).upper(),
            table_name=m.group(2),
            role=m.group(3),
        )

    def _parse_revoke(self, sql: str) -> RevokeStatement:
        m = re.match(
            r"REVOKE\s+([a-zA-Z0-9_]+)\s+ON\s+([a-zA-Z0-9_]+)\s+FROM\s+([a-zA-Z0-9_]+)",
            sql,
            re.IGNORECASE,
        )
        if not m:
            raise SQLParseError(f"Malformed REVOKE syntax: {sql}")

        return RevokeStatement(
            command_type=SQLCommandType.REVOKE,
            raw_sql=sql,
            permission=m.group(1).upper(),
            table_name=m.group(2),
            role=m.group(3),
        )
