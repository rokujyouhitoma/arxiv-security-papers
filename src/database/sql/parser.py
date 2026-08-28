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

    def _parse_dml_dql(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if upper_sql.startswith("WITH"):
            return self._parse_cte(sql)
        if upper_sql.startswith("SELECT"):
            return self._parse_select(sql)
        if upper_sql.startswith("INSERT INTO"):
            return self._parse_insert(sql)
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
        target = "TABLES"
        from_db = None
        like_pat = None

        if "SHOW DATABASES" in upper_sql or "SHOW SCHEMAS" in upper_sql:
            target = "DATABASES"
        elif "SHOW TABLE STATUS" in upper_sql:
            target = "TABLE_STATUS"
        elif "SHOW TABLES" in upper_sql:
            target = "TABLES"
        else:
            raise SQLParseError(f"Unsupported SHOW query: {sql}")

        from_m = re.search(r"FROM\s+([a-zA-Z0-9_]+)", sql, re.IGNORECASE)
        if from_m:
            from_db = from_m.group(1)

        like_m = re.search(r"LIKE\s+['\"](.*?)['\"]", sql, re.IGNORECASE)
        if like_m:
            like_pat = like_m.group(1)

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
        idx = start_pos
        while idx < len(text) and paren_depth > 0:
            if text[idx] == "(":
                paren_depth += 1
            elif text[idx] == ")":
                paren_depth -= 1
            idx += 1
        if paren_depth != 0:
            raise SQLParseError("Unbalanced parentheses in subquery definition")
        return idx

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
        # Check for top-level UNION ALL or UNION (outside parentheses)
        union_split = self._split_top_level_union(sql)
        if union_split:
            left_sql, union_type, right_sql = union_split
            left_stmt = self._parse_single_select(left_sql)
            right_stmt = self._parse_select(right_sql)
            left_stmt.union_all = right_stmt
            return left_stmt

        return self._parse_single_select(sql)

    def _split_top_level_union(self, sql: str) -> Optional[Tuple[str, str, str]]:
        paren_depth = 0
        i = 0
        while i < len(sql):
            char = sql[i]
            if char == "(":
                paren_depth += 1
            elif char == ")":
                paren_depth -= 1
            elif paren_depth == 0:
                # Check for UNION ALL
                union_all_m = re.match(r"^\s+UNION\s+ALL\s+", sql[i:], re.IGNORECASE)
                if union_all_m:
                    left_part = sql[:i].strip()
                    right_part = sql[i + union_all_m.end() :].strip()
                    return left_part, "UNION ALL", right_part

                # Check for UNION
                union_m = re.match(r"^\s+UNION\s+", sql[i:], re.IGNORECASE)
                if union_m:
                    left_part = sql[:i].strip()
                    right_part = sql[i + union_m.end() :].strip()
                    return left_part, "UNION", right_part
            i += 1
        return None

    def _parse_single_select(self, sql: str) -> SelectStatement:
        # Tokenize SELECT: SELECT <cols> FROM <tables/joins> [WHERE] [ORDER BY] [LIMIT]
        clean_sql = re.sub(r"\s+", " ", sql).strip()

        # Extract LIMIT
        limit_val = None
        limit_m = re.search(r"\s+LIMIT\s+([0-9]+)$", clean_sql, re.IGNORECASE)
        if limit_m:
            limit_val = int(limit_m.group(1))
            clean_sql = clean_sql[: limit_m.start()].strip()

        # Extract ORDER BY
        order_by = None
        order_desc = False
        order_m = re.search(
            r"\s+ORDER\s+BY\s+([a-zA-Z0-9_\.\->>\'\"]+)(?:\s+(ASC|DESC))?$",
            clean_sql,
            re.IGNORECASE,
        )
        if order_m:
            order_by = order_m.group(1).strip()
            order_desc = (order_m.group(2) or "").upper() == "DESC"
            clean_sql = clean_sql[: order_m.start()].strip()

        # Extract WHERE
        where_raw = None
        where_m = re.search(r"\s+WHERE\s+(.+)$", clean_sql, re.IGNORECASE)
        if where_m:
            where_raw = where_m.group(1).strip()
            clean_sql = clean_sql[: where_m.start()].strip()

        # Now clean_sql should be: SELECT <cols> FROM <from_and_joins>
        select_m = re.match(
            r"^SELECT\s+(.+?)\s+FROM\s+(.+)$", clean_sql, re.IGNORECASE | re.DOTALL
        )
        if not select_m:
            raise SQLParseError(f"Malformed SELECT syntax: {sql}")

        cols_raw = select_m.group(1).strip()
        from_and_joins_raw = select_m.group(2).strip()

        columns = self._parse_column_list(cols_raw)
        table_ref, joins = self._parse_from_and_joins(from_and_joins_raw)

        where_clauses: List[Dict[str, Any]] = []
        knn_query: Optional[Dict[str, Any]] = None

        if where_raw:
            # KNN function
            knn_m = re.search(
                r"KNN\s*\(\s*([a-zA-Z0-9_\.]+)\s*,\s*(\[.*?\])\s*,\s*([0-9]+)\s*\)",
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
        cols: List[str] = []
        # Split by comma but preserve json strings/functions
        tokens = [c.strip() for c in cols_raw.split(",")]
        for tok in tokens:
            if tok:
                cols.append(tok)
        return cols

    def _parse_from_and_joins(self, from_raw: str) -> Tuple[TableRef, List[JoinClause]]:
        """
        Parses FROM table [AS alias] [JOIN table2 [AS alias2] ON cond1 = cond2 ...]
        """
        # Split by JOIN keywords: (INNER JOIN|LEFT JOIN|LEFT OUTER JOIN|RIGHT JOIN|CROSS JOIN|JOIN)
        join_regex = r"\s+(INNER\s+JOIN|LEFT\s+OUTER\s+JOIN|LEFT\s+JOIN|RIGHT\s+JOIN|CROSS\s+JOIN|JOIN)\s+"
        parts = re.split(join_regex, from_raw, flags=re.IGNORECASE)

        # Primary table
        primary_part = parts[0].strip()
        table_ref = self._parse_single_table_ref(primary_part)

        joins: List[JoinClause] = []
        idx = 1
        while idx < len(parts):
            join_kw = parts[idx].strip().upper()
            join_body = parts[idx + 1].strip()
            idx += 2

            join_type = JoinType.INNER
            if "LEFT" in join_kw:
                join_type = JoinType.LEFT
            elif "RIGHT" in join_kw:
                join_type = JoinType.RIGHT
            elif "CROSS" in join_kw:
                join_type = JoinType.CROSS

            # Extract ON condition: table_name [AS alias] ON cond...
            on_m = re.search(r"\s+ON\s+(.+)$", join_body, re.IGNORECASE)
            if not on_m:
                target_table_ref = self._parse_single_table_ref(join_body)
                joins.append(
                    JoinClause(
                        join_type=join_type,
                        table=target_table_ref,
                        on_conditions=[],
                    )
                )
            else:
                on_raw = on_m.group(1).strip()
                tbl_part = join_body[: on_m.start()].strip()
                target_table_ref = self._parse_single_table_ref(tbl_part)
                on_conds = self._extract_simple_clauses(on_raw)
                joins.append(
                    JoinClause(
                        join_type=join_type,
                        table=target_table_ref,
                        on_conditions=on_conds,
                    )
                )

        return table_ref, joins

    def _parse_single_table_ref(self, text: str) -> TableRef:
        # e.g., "vertices p", "vertices AS p", "vertices"
        m = re.match(
            r"^([a-zA-Z0-9_]+)(?:\s+(?:AS\s+)?([a-zA-Z0-9_]+))?$",
            text.strip(),
            re.IGNORECASE,
        )
        if not m:
            return TableRef(name=text.strip())
        name = m.group(1)
        alias = m.group(2)
        return TableRef(name=name, alias=alias)

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

        # Split AND clauses
        and_parts = re.split(r"\s+AND\s+", text, flags=re.IGNORECASE)
        for part in and_parts:
            part = part.strip()
            if not part:
                continue

            # 1. LIKE: col LIKE '%pattern%'
            like_m = re.match(
                r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+LIKE\s+('[^']*'|\"[^\"]*\")$",
                part,
                re.IGNORECASE,
            )
            if like_m:
                col = like_m.group(1)
                val = like_m.group(2).strip("'\"")
                clauses.append({"column": col, "operator": "LIKE", "value": val})
                continue

            # 2. IN: col IN ('a', 'b') or col IN (1, 2)
            in_m = re.match(
                r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+(NOT\s+IN|IN)\s*\((.*?)\)$",
                part,
                re.IGNORECASE,
            )
            if in_m:
                col = in_m.group(1)
                op = in_m.group(2).upper()
                items_raw = in_m.group(3)
                items = [x.strip().strip("'\"") for x in items_raw.split(",")]
                clauses.append({"column": col, "operator": op, "value": items})
                continue

            # 3. Standard comparison operators: >=, <=, !=, =, >, <
            # Supports left column, right column, literals, JSON extraction
            cmp_pattern = (
                r"^([a-zA-Z0-9_\.\->>\'\"]+)\s*(>=|<=|!=|=|>|<)\s*"
                r"('[^']*'|\"[^\"]*\"|[a-zA-Z0-9_\.\->>\'\"]+|[0-9\.]+)$"
            )
            eq_m = re.match(cmp_pattern, part)
            if eq_m:
                col = eq_m.group(1)
                op = eq_m.group(2)
                val = eq_m.group(3)
                clean_val = val.strip("'\"")
                if clean_val.isdigit():
                    v: Any = int(clean_val)
                else:
                    try:
                        v = float(clean_val)
                    except ValueError:
                        v = clean_val
                clauses.append({"column": col, "operator": op, "value": v})
                continue

        return clauses

    def _parse_insert(self, sql: str) -> InsertStatement:
        m = re.match(
            r"INSERT\s+INTO\s+([a-zA-Z0-9_]+)\s*\((.*?)\)\s*VALUES\s*\((.*?)\)",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed INSERT syntax: {sql}")

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
                k, v_raw = item.split("=", 1)
                clean_v = v_raw.strip().strip("'\"")
                if clean_v.isdigit():
                    v_val: Any = int(clean_v)
                else:
                    try:
                        v_val = float(clean_v)
                    except ValueError:
                        v_val = clean_v
                assignments[k.strip()] = v_val

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
