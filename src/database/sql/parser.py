#!/usr/bin/env python3
"""
Pure Python SQL Lexer & Parser.
Parses standard SQL statements into typed AST objects without external dependencies.
"""

import ast as py_ast
import re
from typing import Any, Dict, List, Optional, Tuple

from .ast import (
    BeginStatement,
    ColumnDef,
    CommitStatement,
    CreateIndexStatement,
    CreateTableStatement,
    CTEDefinition,
    DeleteStatement,
    DropTableStatement,
    ExplainStatement,
    GrantStatement,
    InsertStatement,
    JoinClause,
    JoinType,
    RevokeStatement,
    RollbackStatement,
    SelectStatement,
    ShowStatement,
    SQLCommandType,
    SQLStatement,
    TableRef,
    UpdateStatement,
)


class SQLParseError(Exception):
    """Raised when SQL syntax cannot be parsed."""

    pass


def _resolve_show_target(upper_sql: str) -> str:
    """Resolves target entity for SHOW command."""
    if "SHOW DATABASES" in upper_sql or "SHOW SCHEMAS" in upper_sql:
        return "DATABASES"
    if "SHOW TABLE STATUS" in upper_sql:
        return "TABLE_STATUS"
    if "SHOW TABLES" in upper_sql:
        return "TABLES"
    raise SQLParseError(f"Unsupported SHOW query: {upper_sql}")


def _parse_like_clause(part: str) -> Optional[Dict[str, Any]]:
    """Parses LIKE condition."""
    like_m = re.match(
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+LIKE\s+('[^']*'|\"[^\"]*\")$",
        part,
        re.IGNORECASE,
    )
    if like_m:
        return {
            "column": like_m.group(1),
            "operator": "LIKE",
            "value": like_m.group(2).strip("'\""),
        }
    return None


def _parse_in_clause(part: str) -> Optional[Dict[str, Any]]:
    """Parses IN/NOT IN condition."""
    in_m = re.match(
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+(NOT\s+IN|IN)\s*\((.*?)\)$",
        part,
        re.IGNORECASE,
    )
    if in_m:
        items = [x.strip().strip("'\"") for x in in_m.group(3).split(",")]
        return {
            "column": in_m.group(1),
            "operator": in_m.group(2).upper(),
            "value": items,
        }
    return None


def _parse_cmp_clause(part: str) -> Optional[Dict[str, Any]]:
    """Parses standard comparison condition."""
    cmp_pattern = (
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s*(>=|<=|!=|=|>|<)\s*"
        r"('[^']*'|\"[^\"]*\"|[a-zA-Z0-9_\.\->>\'\"]+|[0-9\.]+)$"
    )
    eq_m = re.match(cmp_pattern, part)
    if eq_m:
        clean_val = eq_m.group(3).strip("'\"")
        v: Any = _parse_val_type(clean_val)
        return {"column": eq_m.group(1), "operator": eq_m.group(2), "value": v}
    return None


def _parse_where_clause_item(part: str) -> Optional[Dict[str, Any]]:
    """Parses a single WHERE predicate term (LIKE, IN, or comparison)."""
    part = part.strip()
    if not part:
        return None
    return _parse_like_clause(part) or _parse_in_clause(part) or _parse_cmp_clause(part)


def _parse_val_type(clean_val: str) -> Any:
    """Parses numeric literal or returns string."""
    if clean_val.isdigit():
        return int(clean_val)
    try:
        return float(clean_val)
    except ValueError:
        return clean_val


class SQLParser:
    """
    Parses SQL string queries into structured SQLStatement AST nodes.
    Supports advanced features: CTE (WITH RECURSIVE), JOINs, JSON operators (->, ->>), and Aliases.
    """

    def _parse_tcl(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if re.match(r"^BEGIN(\s+TRANSACTION)?$", upper_sql):
            return BeginStatement(command_type=SQLCommandType.BEGIN, raw_sql=sql)
        if re.match(r"^COMMIT$", upper_sql):
            return CommitStatement(command_type=SQLCommandType.COMMIT, raw_sql=sql)
        if re.match(r"^ROLLBACK$", upper_sql):
            return RollbackStatement(command_type=SQLCommandType.ROLLBACK, raw_sql=sql)
        return None

    def _parse_ddl(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if upper_sql.startswith("CREATE TABLE"):
            return self._parse_create_table(sql)
        if upper_sql.startswith("DROP TABLE"):
            return self._parse_drop_table(sql)
        if upper_sql.startswith("CREATE INDEX"):
            return self._parse_create_index(sql)
        return None

    def _parse_dml_dql_part(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if upper_sql.startswith("WITH"):
            return self._parse_cte(sql)
        if upper_sql.startswith("SELECT"):
            return self._parse_select(sql)
        if upper_sql.startswith("INSERT INTO"):
            return self._parse_insert(sql)
        return None

    def _parse_dml_dql(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        part1 = self._parse_dml_dql_part(upper_sql, sql)
        if part1 is not None:
            return part1
        if upper_sql.startswith("UPDATE"):
            return self._parse_update(sql)
        if upper_sql.startswith("DELETE FROM"):
            return self._parse_delete(sql)
        return None

    def _parse_dcl_explain(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if upper_sql.startswith("EXPLAIN"):
            return self._parse_explain(sql)
        if upper_sql.startswith("GRANT"):
            return self._parse_grant(sql)
        if upper_sql.startswith("REVOKE"):
            return self._parse_revoke(sql)
        if upper_sql.startswith("SHOW"):
            return self._parse_show(sql)
        return None

    def _parse_show(self, sql: str) -> SQLStatement:
        upper_sql = sql.upper().strip()
        target = _resolve_show_target(upper_sql)

        from_m = re.search(r"FROM\s+([a-zA-Z0-9_]+)", sql, re.IGNORECASE)
        from_db = from_m.group(1) if from_m else None

        like_m = re.search(r"LIKE\s+['\"](.*?)['\"]", sql, re.IGNORECASE)
        like_pat = like_m.group(1) if like_m else None

        return ShowStatement(
            command_type=SQLCommandType.SHOW,
            raw_sql=sql,
            target=target,
            from_database=from_db,
            like_pattern=like_pat,
        )

    def _parse_ddl_dml(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        return (
            self._parse_dcl_explain(upper_sql, sql)
            or self._parse_ddl(upper_sql, sql)
            or self._parse_dml_dql(upper_sql, sql)
        )

    def parse(self, sql_query: str) -> SQLStatement:
        sql = sql_query.strip().rstrip(";")
        if not sql:
            raise SQLParseError("Empty SQL query")

        upper_sql = sql.upper()
        tcl_stmt = self._parse_tcl(upper_sql, sql)
        if tcl_stmt is not None:
            return tcl_stmt

        stmt = self._parse_ddl_dml(upper_sql, sql)
        if stmt is not None:
            return stmt

        raise SQLParseError(f"Unsupported or unrecognized SQL statement: '{sql}'")

    def _parse_explain(self, sql: str) -> ExplainStatement:
        m = re.match(
            r"^EXPLAIN(\s+QUERY\s+PLAN)?\s+(.*)$", sql, re.IGNORECASE | re.DOTALL
        )
        if not m:
            raise SQLParseError(f"Malformed EXPLAIN syntax: {sql}")
        query_plan = bool(m.group(1))
        sub_sql = m.group(2).strip()
        sub_stmt = self.parse(sub_sql)
        return ExplainStatement(
            command_type=SQLCommandType.EXPLAIN,
            raw_sql=sql,
            statement=sub_stmt,
            query_plan=query_plan,
        )

    def _parse_column_def(self, raw_col: str) -> Optional[ColumnDef]:
        """Parses a single column definition within CREATE TABLE."""
        raw_col = raw_col.strip()
        if not raw_col:
            return None
        parts = raw_col.split()
        c_name = parts[0]
        c_type = parts[1] if len(parts) > 1 else "TEXT"
        is_pk = "PRIMARY KEY" in raw_col.upper()
        is_nullable = "NOT NULL" not in raw_col.upper()
        return ColumnDef(
            name=c_name,
            data_type=c_type,
            is_primary_key=is_pk,
            is_nullable=is_nullable,
        )

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

        col_defs = [
            c_def
            for raw_col in cols_body.split(",")
            if (c_def := self._parse_column_def(raw_col)) is not None
        ]

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
            r"CREATE\s+INDEX\s+([a-zA-Z0-9_]+)\s+ON\s+([a-zA-Z0-9_]+)"
            r"\s*\(([a-zA-Z0-9_]+)\)(\s+USING\s+([a-zA-Z0-9_]+))?",
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

    def _find_matching_paren(self, text: str, start_pos: int) -> int:
        paren_depth = 1
        for idx in range(start_pos, len(text)):
            ch = text[idx]
            paren_depth += 1 if ch == "(" else (-1 if ch == ")" else 0)
            if paren_depth == 0:
                return idx + 1
        raise SQLParseError("Unbalanced parentheses in subquery definition")

    def _extract_single_cte(
        self, rest: str, is_recursive: bool
    ) -> Optional[Tuple[CTEDefinition, str]]:
        cte_head_m = re.match(
            r"^([a-zA-Z0-9_]+)(?:\s*\((.*?)\))?\s+AS\s*\(", rest, re.IGNORECASE
        )
        if not cte_head_m:
            return None

        cte_name = cte_head_m.group(1)
        raw_cols = cte_head_m.group(2)
        cols = [c.strip() for c in raw_cols.split(",")] if raw_cols else []

        start_pos = cte_head_m.end()
        end_pos = self._find_matching_paren(rest, start_pos)
        sub_query_sql = rest[start_pos : end_pos - 1].strip()
        sub_stmt = self._parse_select(sub_query_sql)

        cte_def = CTEDefinition(
            name=cte_name,
            statement=sub_stmt,
            columns=cols,
            is_recursive=is_recursive,
        )

        remaining = rest[end_pos:].strip()
        if remaining.startswith(","):
            remaining = remaining[1:].strip()
        return cte_def, remaining

    def _parse_cte(self, sql: str) -> SelectStatement:
        """
        Parses WITH [RECURSIVE] name [(cols...)] AS (SELECT ...) [, ...] SELECT ...
        """
        is_recursive = bool(re.match(r"^WITH\s+RECURSIVE\s+", sql, re.IGNORECASE))
        header_match = re.match(r"^WITH(\s+RECURSIVE)?\s+", sql, re.IGNORECASE)
        if not header_match:
            raise SQLParseError(f"Malformed WITH syntax: {sql}")

        rest = sql[header_match.end() :].strip()
        ctes: List[CTEDefinition] = []

        while True:
            res = self._extract_single_cte(rest, is_recursive)
            if not res:
                break
            cte_def, rest = res
            ctes.append(cte_def)

        if not rest.upper().startswith("SELECT"):
            raise SQLParseError(
                f"Expected SELECT query following CTE definitions, got: {rest}"
            )

        main_stmt = self._parse_select(rest)
        main_stmt.ctes = ctes
        main_stmt.raw_sql = sql
        return main_stmt

    def _parse_select(self, sql: str) -> SelectStatement:
        union_split = self._split_top_level_union(sql)
        if union_split:
            left_sql, _, right_sql = union_split
            left_stmt = self._parse_single_select(left_sql)
            left_stmt.union_all = self._parse_select(right_sql)
            return left_stmt

        return self._parse_single_select(sql)

    def _check_union_at_pos(self, sql: str, i: int) -> Optional[Tuple[str, str, str]]:
        """Checks for UNION ALL or UNION match at index i."""
        union_all_m = re.match(r"^\s+UNION\s+ALL\s+", sql[i:], re.IGNORECASE)
        if union_all_m:
            left_part = sql[:i].strip()
            right_part = sql[i + union_all_m.end() :].strip()
            return left_part, "UNION ALL", right_part

        union_m = re.match(r"^\s+UNION\s+", sql[i:], re.IGNORECASE)
        if union_m:
            left_part = sql[:i].strip()
            right_part = sql[i + union_m.end() :].strip()
            return left_part, "UNION", right_part
        return None

    def _update_depth_and_check(
        self, sql: str, i: int, char: str, paren_depth: int
    ) -> Tuple[int, Optional[Tuple[str, str, str]]]:
        """Updates paren_depth and checks for union at position i."""
        if char == "(":
            return paren_depth + 1, None
        if char == ")":
            return paren_depth - 1, None
        if paren_depth == 0:
            return 0, self._check_union_at_pos(sql, i)
        return paren_depth, None

    def _split_top_level_union(self, sql: str) -> Optional[Tuple[str, str, str]]:
        paren_depth = 0
        for i, char in enumerate(sql):
            paren_depth, match = self._update_depth_and_check(sql, i, char, paren_depth)
            if match is not None:
                return match
        return None

    def _extract_limit_clause(self, clean_sql: str) -> Tuple[str, Optional[int]]:
        """Extracts and strips LIMIT value."""
        limit_m = re.search(r"\s+LIMIT\s+([0-9]+)$", clean_sql, re.IGNORECASE)
        if limit_m:
            return clean_sql[: limit_m.start()].strip(), int(limit_m.group(1))
        return clean_sql, None

    def _extract_order_by_clause(
        self, clean_sql: str
    ) -> Tuple[str, Optional[str], bool]:
        """Extracts and strips ORDER BY column and sort direction."""
        order_m = re.search(
            r"\s+ORDER\s+BY\s+([a-zA-Z0-9_\.\->>\'\"]+)(?:\s+(ASC|DESC))?$",
            clean_sql,
            re.IGNORECASE,
        )
        if order_m:
            order_by = order_m.group(1).strip()
            order_desc = (order_m.group(2) or "").upper() == "DESC"
            return clean_sql[: order_m.start()].strip(), order_by, order_desc
        return clean_sql, None, False

    def _extract_where_clause(self, clean_sql: str) -> Tuple[str, Optional[str]]:
        """Extracts and strips WHERE condition."""
        where_m = re.search(r"\s+WHERE\s+(.+)$", clean_sql, re.IGNORECASE)
        if where_m:
            return clean_sql[: where_m.start()].strip(), where_m.group(1).strip()
        return clean_sql, None

    def _extract_knn_query(
        self, where_raw: str
    ) -> Tuple[str, Optional[Dict[str, Any]]]:
        """Extracts KNN function and cleans where_raw string."""
        knn_m = re.search(
            r"KNN\s*\(\s*([a-zA-Z0-9_\.]+)\s*,\s*(\[.*?\])\s*,\s*([0-9]+)\s*\)",
            where_raw,
            re.IGNORECASE,
        )
        if not knn_m:
            return where_raw, None

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
        cleaned_raw = where_raw.replace(knn_m.group(0), "").strip()
        cleaned_raw = re.sub(
            r"^(AND|OR)\s+", "", cleaned_raw, flags=re.IGNORECASE
        ).strip()
        cleaned_raw = re.sub(
            r"\s+(AND|OR)$", "", cleaned_raw, flags=re.IGNORECASE
        ).strip()
        return cleaned_raw, knn_query

    def _parse_single_select(self, sql: str) -> SelectStatement:
        clean_sql = re.sub(r"\s+", " ", sql).strip()
        clean_sql, limit_val = self._extract_limit_clause(clean_sql)
        clean_sql, order_by, order_desc = self._extract_order_by_clause(clean_sql)
        clean_sql, where_raw = self._extract_where_clause(clean_sql)

        select_m = re.match(
            r"^SELECT\s+(.+?)\s+FROM\s+(.+)$", clean_sql, re.IGNORECASE | re.DOTALL
        )
        if not select_m:
            raise SQLParseError(f"Malformed SELECT syntax: {sql}")

        columns = self._parse_column_list(select_m.group(1).strip())
        table_ref, joins = self._parse_from_and_joins(select_m.group(2).strip())

        where_clauses: List[Dict[str, Any]] = []
        knn_query: Optional[Dict[str, Any]] = None

        if where_raw:
            where_raw, knn_query = self._extract_knn_query(where_raw)
            where_clauses.extend(self._extract_where_clauses(where_raw))

        return SelectStatement(
            command_type=SQLCommandType.SELECT,
            raw_sql=sql,
            table_name=table_ref.name,
            table_ref=table_ref,
            columns=columns,
            where_clauses=where_clauses,
            knn_query=knn_query,
            joins=joins,
            order_by=order_by,
            order_desc=order_desc,
            limit=limit_val,
        )

    def _parse_column_list(self, cols_raw: str) -> List[str]:
        """Parses comma-separated column projections including json path expressions."""
        if cols_raw == "*":
            return ["*"]
        return [tok.strip() for tok in cols_raw.split(",") if tok.strip()]

    def _resolve_join_type(self, join_kw: str) -> JoinType:
        """Resolves JoinType enum from join keyword."""
        if "LEFT" in join_kw:
            return JoinType.LEFT
        if "RIGHT" in join_kw:
            return JoinType.RIGHT
        if "CROSS" in join_kw:
            return JoinType.CROSS
        return JoinType.INNER

    def _parse_join_part(self, join_kw: str, join_body: str) -> JoinClause:
        """Parses target table and ON conditions for a single JOIN clause."""
        join_type = self._resolve_join_type(join_kw)
        on_m = re.search(r"\s+ON\s+(.+)$", join_body, re.IGNORECASE)
        if not on_m:
            target_table_ref = self._parse_single_table_ref(join_body)
            return JoinClause(
                join_type=join_type, table=target_table_ref, on_conditions=[]
            )
        tbl_part = join_body[: on_m.start()].strip()
        target_table_ref = self._parse_single_table_ref(tbl_part)
        on_conds = self._extract_simple_clauses(on_m.group(1).strip())
        return JoinClause(
            join_type=join_type, table=target_table_ref, on_conditions=on_conds
        )

    def _parse_from_and_joins(self, from_raw: str) -> Tuple[TableRef, List[JoinClause]]:
        """Parses FROM table [AS alias] [JOIN table2 [AS alias2] ON cond1 = cond2 ...]"""
        join_regex = r"\s+(INNER\s+JOIN|LEFT\s+OUTER\s+JOIN|LEFT\s+JOIN|RIGHT\s+JOIN|CROSS\s+JOIN|JOIN)\s+"
        parts = re.split(join_regex, from_raw, flags=re.IGNORECASE)

        table_ref = self._parse_single_table_ref(parts[0].strip())
        joins: List[JoinClause] = []
        idx = 1
        while idx < len(parts):
            join_kw = parts[idx].strip().upper()
            join_body = parts[idx + 1].strip()
            idx += 2
            joins.append(self._parse_join_part(join_kw, join_body))

        return table_ref, joins

    def _parse_single_table_ref(self, text: str) -> TableRef:
        m = re.match(
            r"^([a-zA-Z0-9_]+)(?:\s+(?:AS\s+)?([a-zA-Z0-9_]+))?$",
            text.strip(),
            re.IGNORECASE,
        )
        if not m:
            return TableRef(name=text.strip())
        return TableRef(name=m.group(1), alias=m.group(2))

    def _extract_where_clauses(self, where_raw: str) -> List[Dict[str, Any]]:
        clauses: List[Dict[str, Any]] = []
        if not where_raw:
            return clauses

        or_parts = re.split(r"\s+OR\s+", where_raw, flags=re.IGNORECASE)
        if len(or_parts) > 1:
            for part in or_parts:
                sub_clauses = self._extract_simple_clauses(part)
                clauses.append({"logic": "OR_BRANCH", "clauses": sub_clauses})
            return clauses

        return self._extract_simple_clauses(where_raw)

    def _extract_simple_clauses(self, text: str) -> List[Dict[str, Any]]:
        clauses: List[Dict[str, Any]] = []
        if not text:
            return clauses

        and_parts = re.split(r"\s+AND\s+", text, flags=re.IGNORECASE)
        for part in and_parts:
            item = _parse_where_clause_item(part)
            if item is not None:
                clauses.append(item)
        return clauses

    def _parse_insert_values(self, vals_raw: str) -> List[Any]:
        """Safely parses literal values using python ast or fallback split."""
        try:
            parsed_tuple = py_ast.literal_eval(f"({vals_raw})")
            if not isinstance(parsed_tuple, tuple):
                return [parsed_tuple]
            return list(parsed_tuple)
        except Exception:
            return [v.strip().strip("'\"") for v in vals_raw.split(",")]

    def _parse_insert(self, sql: str) -> InsertStatement:
        m = re.match(
            r"INSERT\s+INTO\s+([a-zA-Z0-9_]+)\s*\((.*?)\)\s*VALUES\s*\((.*?)\)",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed INSERT syntax: {sql}")

        table_name = m.group(1).strip()
        columns = [c.strip() for c in m.group(2).strip().split(",")]
        values = self._parse_insert_values(m.group(3).strip())

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

    def _parse_set_assignments(self, set_raw: str) -> Dict[str, Any]:
        """Parses SET k1=v1, k2=v2 assignments."""
        assignments: Dict[str, Any] = {}
        for item in set_raw.split(","):
            if "=" in item:
                k, v_raw = item.split("=", 1)
                clean_v = v_raw.strip().strip("'\"")
                assignments[k.strip()] = _parse_val_type(clean_v)
        return assignments

    def _parse_update(self, sql: str) -> UpdateStatement:
        m = re.match(
            r"UPDATE\s+([a-zA-Z0-9_]+)\s+SET\s+(.+?)(?:\s+WHERE\s+(.+))?$",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed UPDATE syntax: {sql}")

        table_name = m.group(1).strip()
        assignments = self._parse_set_assignments(m.group(2).strip())
        where_raw = m.group(3)
        where_clauses = self._extract_where_clauses(where_raw) if where_raw else []

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
        where_clauses = self._extract_where_clauses(where_raw) if where_raw else []

        return DeleteStatement(
            command_type=SQLCommandType.DELETE,
            raw_sql=sql,
            table_name=table_name,
            where_clauses=where_clauses,
        )

    def _parse_grant(self, sql: str) -> GrantStatement:
        m = re.match(
            r"GRANT\s+(.+?)(?:\s+ON\s+([a-zA-Z0-9_\*]+))?\s+TO\s+([a-zA-Z0-9_]+)$",
            sql,
            re.IGNORECASE,
        )
        if not m:
            raise SQLParseError(f"Malformed GRANT syntax: {sql}")

        perm = m.group(1).strip().upper()
        if perm in ("ALL PRIVILEGES", "ALL"):
            perm = "ALL"
        table_name = m.group(2) or "*"
        role_name = m.group(3).strip()

        return GrantStatement(
            command_type=SQLCommandType.GRANT,
            raw_sql=sql,
            permission=perm,
            table_name=table_name,
            role=role_name,
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
