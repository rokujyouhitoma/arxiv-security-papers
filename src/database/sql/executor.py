#!/usr/bin/env python3
"""
SQL Execution Engine for Pure Python Vector Database.
Evaluates DDL, DQL, DML, DCL, and TCL AST nodes against underlying vector storages and schemas.
"""

import fnmatch
import json
import logging
import os
import re
from typing import Any, Dict, List, Optional, Tuple

from ..btree import BPlusTree
from ..embedding import DeterministicEmbedding
from ..index import HNSWIndex
from ..planner import QueryPlanner, TableStats
from ..storage import VectorStorage
from .ast import (
    AlterTableAction,
    AlterTableStatement,
    CreateIndexStatement,
    CreateTableStatement,
    CreateViewStatement,
    DeleteStatement,
    DropIndexStatement,
    DropTableStatement,
    DropViewStatement,
    ExplainStatement,
    GrantStatement,
    InsertStatement,
    JoinClause,
    JoinType,
    ReindexStatement,
    RevokeStatement,
    SelectStatement,
    ShowStatement,
    SQLCommandType,
    SQLStatement,
    TableRef,
    UpdateStatement,
)
from .parser import SQLParser
from .security import AccessController
from .transaction import TransactionManager

logger = logging.getLogger(__name__)


def _safe_remove_file(path: Optional[str]) -> None:
    if not path or path == ":memory:":
        return
    if os.path.exists(path):
        try:
            os.remove(path)
        except OSError:
            pass


def _project_single_record(
    record: Dict[str, Any], returning_cols: List[str]
) -> Dict[str, Any]:
    return {c: record.get(c) for c in returning_cols}


def _project_returning_rows(
    records: List[Dict[str, Any]], returning_cols: Optional[List[str]]
) -> List[Dict[str, Any]]:
    """Projects requested columns for RETURNING clause."""
    if not returning_cols:
        return []
    if "*" in returning_cols:
        return [dict(r) for r in records]
    return [_project_single_record(r, returning_cols) for r in records]


def _resolve_stmt_target_table(stmt: SelectStatement) -> str:
    if stmt.table_name:
        return stmt.table_name
    if stmt.table_ref:
        return stmt.table_ref.name
    return ""


def _extract_join_tables(joins: List[JoinClause]) -> List[str]:
    res: List[str] = []
    for j in joins:
        if j.table:
            res.append(j.table.name)
    return res


def _rename_metadata_col(table: Any, old_col: str, new_col: str) -> None:
    for meta in table.storage.metadata:
        if old_col in meta:
            meta[new_col] = meta.pop(old_col)


def _update_index_for_renamed_col(table: Any, old_col: str, new_col: str) -> None:
    if old_col in table.btree_indexes:
        table.btree_indexes[new_col] = table.btree_indexes.pop(old_col)
    if old_col in table.btree_index_names:
        table.btree_index_names[new_col] = table.btree_index_names.pop(old_col)
    for idef in table.index_definitions:
        if idef.get("column") == old_col:
            idef["column"] = new_col


def _remove_index_for_dropped_col(table: Any, col_name: str) -> None:
    table.btree_indexes.pop(col_name, None)
    table.btree_index_names.pop(col_name, None)
    table.index_definitions = [
        d for d in table.index_definitions if d.get("column") != col_name
    ]


def _save_table_storage(table: Any) -> None:
    if hasattr(table.storage, "save") and callable(table.storage.save):
        table.storage.save()
    elif hasattr(table.storage, "write_all") and callable(table.storage.write_all):
        vecs = table.storage.get_all_vectors()
        table.storage.write_all(vecs, table.storage.metadata)


def _drop_from_index_defs(table: Any, index_name: str) -> bool:
    found = False
    for idef in list(table.index_definitions):
        if idef.get("name") == index_name:
            table.index_definitions.remove(idef)
            col = idef.get("column")
            if col:
                table.btree_indexes.pop(col, None)
                table.btree_index_names.pop(col, None)
            found = True
    return found


def _drop_from_btree_names(table: Any, index_name: str) -> bool:
    cols = [c for c, iname in table.btree_index_names.items() if iname == index_name]
    for c in cols:
        table.btree_indexes.pop(c, None)
        table.btree_index_names.pop(c, None)
    return bool(cols)


def _drop_matching_index_from_table(table: Any, index_name: str) -> bool:
    res1 = _drop_from_index_defs(table, index_name)
    res2 = _drop_from_btree_names(table, index_name)
    return res1 or res2


def _rebuild_table_indexes(table: Any) -> int:
    vecs = table.storage.get_all_vectors()
    table.index = HNSWIndex(dim=table.storage.dim)
    table.index.build_from_storage(vecs)
    cnt = 1
    for col, iname in list(table.btree_index_names.items()):
        btree = BPlusTree(column_name=col)
        for idx, meta in enumerate(table.storage.metadata):
            val = meta.get(col)
            if val is not None:
                btree.insert(val, idx)
        table.btree_indexes[col] = btree
        cnt += 1
    return cnt


def _rebuild_named_btree_index(table: Any, index_name: str) -> int:
    cnt = 0
    for col, iname in list(table.btree_index_names.items()):
        if iname == index_name:
            btree = BPlusTree(column_name=col)
            for idx, meta in enumerate(table.storage.metadata):
                val = meta.get(col)
                if val is not None:
                    btree.insert(val, idx)
            table.btree_indexes[col] = btree
            cnt += 1
    return cnt


class SQLExecutionError(Exception):
    """Raised when SQL execution fails."""

    pass


class LazyRow(Dict[str, Any]):
    """Dictionary proxy that transparently resolves missing or prefixed fields from a lazy source."""

    def __init__(
        self,
        base: Dict[str, Any],
        source: Optional[Any] = None,
        table_prefix: str = "",
    ) -> None:
        super().__init__(base)
        self._source = source
        self._table_prefix = table_prefix

    def _fetch_from_source(self, raw_key: str, key: str) -> Tuple[bool, Any]:
        try:
            val = self._source[raw_key]  # type: ignore
            self[key] = val
            return True, val
        except (KeyError, TypeError):
            return False, None

    def _resolve_lazy_key(self, key: str) -> Tuple[bool, Any]:
        if self._source is None:
            return False, None
        raw_key = key.split(".", 1)[-1] if "." in key else key
        if hasattr(self._source, "__contains__") and raw_key in self._source:
            return self._fetch_from_source(raw_key, key)
        return False, None

    def __contains__(self, key: object) -> bool:
        if super().__contains__(key):
            return True
        if isinstance(key, str):
            found, _ = self._resolve_lazy_key(key)
            return found
        return False

    def __getitem__(self, key: str) -> Any:
        if super().__contains__(key):
            return super().__getitem__(key)
        found, val = self._resolve_lazy_key(key)
        if found:
            return val
        raise KeyError(key)

    def get(self, key: str, default: Any = None) -> Any:
        try:
            return self[key]
        except KeyError:
            return default


class CombinedRow(Dict[str, Any]):
    """Row combining left and right join sides while preserving lazy resolution."""

    def __init__(self, left: Dict[str, Any], right: Dict[str, Any]) -> None:
        super().__init__(left)
        self.update(right)
        self._left = left
        self._right = right

    def __contains__(self, key: object) -> bool:
        return super().__contains__(key) or key in self._right or key in self._left

    def __getitem__(self, key: str) -> Any:
        if super().__contains__(key):
            return super().__getitem__(key)
        if key in self._right:
            val = self._right[key]
            self[key] = val
            return val
        if key in self._left:
            val = self._left[key]
            self[key] = val
            return val
        raise KeyError(key)

    def get(self, key: str, default: Any = None) -> Any:
        try:
            return self[key]
        except KeyError:
            return default


def _calc_memory_storage_size(storage: Any) -> int:
    if hasattr(storage, "to_bytes"):
        return len(storage.to_bytes())
    return 0


def _calc_file_storage_size(loc: str) -> int:
    if loc and os.path.exists(loc):
        return os.path.getsize(loc)
    return 0


def _parse_col_pair(col_str: str) -> Tuple[str, str]:
    parts = col_str.split(None, 1)
    return (parts[0], parts[1]) if len(parts) == 2 else (col_str, "")


def _format_col_line(name: str, col_type: str, max_len: int) -> str:
    return f"    {name.ljust(max_len)}  {col_type}".rstrip()


def _split_column_defs(body: str) -> List[Tuple[str, str]]:
    cols: List[Tuple[str, str]] = []
    for chunk in body.split(","):
        cleaned = chunk.strip()
        if cleaned:
            cols.append(_parse_col_pair(cleaned))
    return cols


def _format_ddl_columns(body: str) -> str:
    """Formats comma-separated column definitions with aligned types."""
    col_pairs = _split_column_defs(body)
    if not col_pairs:
        return ""
    max_len = max(len(name) for name, _ in col_pairs)
    return ",\n".join(_format_col_line(n, t, max_len) for n, t in col_pairs)


def prettify_ddl(raw_sql: str) -> str:
    """Prettifies a CREATE TABLE statement with indented and aligned columns."""
    clean = raw_sql.strip().rstrip(";")
    if "(" not in clean or ")" not in clean:
        return clean + ";"

    head, _, tail = clean.partition("(")
    body, _, foot = tail.rpartition(")")

    formatted_cols = _format_ddl_columns(body)
    foot_clean = foot.strip()
    if foot_clean:
        return f"{head.strip()} (\n{formatted_cols}\n) {foot_clean};"
    return f"{head.strip()} (\n{formatted_cols}\n);"


def _extract_pk_col(raw_sql: str) -> Optional[str]:
    if "PRIMARY KEY" not in raw_sql.upper():
        return None
    _, _, tail = raw_sql.partition("(")
    body, _, _ = tail.rpartition(")")
    for chunk in body.split(","):
        if "PRIMARY KEY" in chunk.upper():
            parts = chunk.strip().split()
            if parts:
                return parts[0]
    return None


class TableCatalog:
    """Represents in-memory and on-disk catalog for a database table."""

    def __init__(
        self,
        name: str,
        storage: Any,
        index: Optional[HNSWIndex] = None,
        schema: Optional[Dict[str, Any]] = None,
        raw_sql: Optional[str] = None,
        storage_engine: Optional[str] = None,
        location: Optional[str] = None,
        database_scope: Optional[str] = None,
    ) -> None:
        self.name = name
        self.storage = storage
        default_dim = int(getattr(storage, "dim", 128))
        self.index = index if index is not None else HNSWIndex(dim=default_dim)
        self.schema = schema if schema is not None else {}
        self._init_catalog_metadata(raw_sql, storage_engine, location, database_scope)
        self.btree_indexes: Dict[str, BPlusTree] = {}
        self.btree_index_names: Dict[str, str] = {}
        self.index_definitions: List[Dict[str, str]] = []
        self.stats: TableStats = TableStats(name)
        self.recompute_stats()

    def _init_catalog_metadata(
        self,
        raw_sql: Optional[str],
        storage_engine: Optional[str],
        location: Optional[str],
        database_scope: Optional[str] = None,
    ) -> None:
        self.raw_sql = raw_sql or ""
        self.storage_engine = storage_engine or ""
        self.location = location or ""
        self.database_scope = database_scope

    def recompute_stats(self) -> None:
        """Refreshes catalog statistics from storage metadata."""
        if self.storage and self.storage.metadata:
            self.stats.analyze_from_metadata(self.storage.metadata)

    def get_ddl(self) -> str:
        """Returns the prettified CREATE TABLE DDL statement."""
        if self.raw_sql:
            return prettify_ddl(self.raw_sql)
        cols = [f"{col} {dtype}" for col, dtype in self.schema.items()]
        body = ", ".join(cols)
        ddl = f"CREATE TABLE {self.name} ({body})"
        if self.storage_engine:
            ddl += f" USING {self.storage_engine}"
        if self.location:
            ddl += f" LOCATION '{self.location}'"
        return prettify_ddl(ddl)

    def _format_single_index_ddl(self, defn: Dict[str, str]) -> str:
        if defn.get("raw_sql"):
            return defn["raw_sql"].strip().rstrip(";") + ";"
        iname, col, itype = defn["name"], defn["column"], defn["type"]
        return f"CREATE INDEX {iname} ON {self.name} ({col}) USING {itype};"

    def _get_pk_index_ddl(self) -> Optional[str]:
        pk = _extract_pk_col(self.raw_sql)
        if not pk:
            return None
        iname = f"pk_{self.name}_{pk}"
        if any(d.get("name") == iname for d in self.index_definitions):
            return None
        return f"CREATE UNIQUE INDEX {iname} ON {self.name} ({pk}) USING BTREE;"

    def _has_hnsw_index(self) -> bool:
        return any(d.get("type") == "HNSW" for d in self.index_definitions)

    def _append_vector_ddl_if_needed(self, ddls: List[str]) -> None:
        if getattr(self.index, "dim", 0) > 0 and not self._has_hnsw_index():
            ddls.append(
                f"CREATE INDEX idx_{self.name}_vector ON {self.name} (vector) USING HNSW;"
            )

    def get_index_ddls(self) -> List[str]:
        """Returns formatted CREATE INDEX statements for all active indexes."""
        ddls = [self._format_single_index_ddl(d) for d in self.index_definitions]
        pk_ddl = self._get_pk_index_ddl()
        if pk_ddl:
            ddls.insert(0, pk_ddl)
        self._append_vector_ddl_if_needed(ddls)
        return ddls


def _extract_quoted_str(expr: str) -> Optional[str]:
    if (expr.startswith("'") and expr.endswith("'")) or (
        expr.startswith('"') and expr.endswith('"')
    ):
        return expr[1:-1]
    return None


def _extract_numeric_literal(expr: str) -> Optional[Any]:
    if expr.isdigit():
        return int(expr)
    try:
        if "." in expr:
            return float(expr)
    except ValueError:
        pass
    return None


def _extract_literal(expr: str) -> Optional[Any]:
    quoted = _extract_quoted_str(expr)
    if quoted is not None:
        return quoted
    return _extract_numeric_literal(expr)


def _extract_arithmetic(record: Dict[str, Any], expr: str) -> Optional[Any]:
    arith_m = re.match(r"^([a-zA-Z0-9_\.\->>\'\"]+)\s*([\+\-])\s*([0-9]+)$", expr)
    if not arith_m:
        return None
    base_col, op, num_str = (
        arith_m.group(1).strip(),
        arith_m.group(2),
        int(arith_m.group(3)),
    )
    base_val = _extract_field_value(record, base_col)
    try:
        base_num = int(base_val) if base_val is not None else 0
        return base_num + num_str if op == "+" else base_num - num_str
    except (ValueError, TypeError):
        return base_val


def _parse_json_field(raw_obj: Any) -> Optional[Dict[str, Any]]:
    if isinstance(raw_obj, str):
        try:
            raw_obj = json.loads(raw_obj)
        except Exception:
            return None
    return raw_obj if isinstance(raw_obj, dict) else None


def _get_raw_json_col(record: Dict[str, Any], col_part: str) -> Any:
    raw_obj = record.get(col_part)
    if raw_obj is None and "." in col_part:
        return record.get(col_part.split(".", 1)[1])
    return raw_obj


def _extract_json_val(
    dict_obj: Dict[str, Any], path_part: str, json_unquote: bool
) -> Optional[Any]:
    val = dict_obj.get(path_part.strip().strip("'\""))
    if val is None:
        return None
    return str(val) if json_unquote else val


def _extract_json_op(record: Dict[str, Any], expr: str) -> Optional[Any]:
    if "->" not in expr:
        return None
    json_unquote = "->>" in expr
    col_part, path_part = expr.split("->>" if json_unquote else "->", 1)
    raw_obj = _get_raw_json_col(record, col_part.strip())
    dict_obj = _parse_json_field(raw_obj)
    if not dict_obj:
        return None
    return _extract_json_val(dict_obj, path_part, json_unquote)


def _lookup_record_col(record: Dict[str, Any], expr: str) -> Any:
    if expr in record:
        return record[expr]
    return record.get(expr.split(".", 1)[1]) if "." in expr else None


def _extract_field_value(record: Dict[str, Any], expr: str) -> Any:
    """Extracts value from record supporting dot qualification and JSON operators."""
    if not expr:
        return None
    expr = expr.strip()
    lit = _extract_literal(expr)
    if lit is not None:
        return lit
    arith = _extract_arithmetic(record, expr)
    if arith is not None:
        return arith
    if "->" in expr:
        return _extract_json_op(record, expr)
    return _lookup_record_col(record, expr)


def _eval_numeric_rel(op: str, act_f: float, exp_f: float) -> bool:
    if op == ">=":
        return act_f >= exp_f
    if op == "<=":
        return act_f <= exp_f
    if op == ">":
        return act_f > exp_f
    if op == "<":
        return act_f < exp_f
    return False


def _eval_string_rel(op: str, act_s: str, exp_s: str) -> bool:
    if op == ">=":
        return act_s >= exp_s
    if op == "<=":
        return act_s <= exp_s
    if op == ">":
        return act_s > exp_s
    if op == "<":
        return act_s < exp_s
    return False


def _eval_relational(op: str, actual: Any, expected: Any) -> bool:
    try:
        return _eval_numeric_rel(op, float(str(actual)), float(str(expected)))
    except (ValueError, TypeError):
        return _eval_string_rel(op, str(actual), str(expected))


def _eval_is_null(op: str, actual: Any) -> bool:
    is_n = actual is None or actual == ""
    return is_n if op == "IS NULL" else not is_n


def _eval_between(op: str, actual: Any, expected: Any) -> bool:
    if not isinstance(expected, (list, tuple)) or len(expected) != 2:
        return False
    v1, v2 = expected
    try:
        act_f, v1_f, v2_f = float(str(actual)), float(str(v1)), float(str(v2))
        res = v1_f <= act_f <= v2_f
    except (ValueError, TypeError):
        act_s, v1_s, v2_s = str(actual), str(v1), str(v2)
        res = v1_s <= act_s <= v2_s
    return res if op == "BETWEEN" else not res


def _eval_glob(op: str, actual: Any, expected: Any) -> bool:
    matched = fnmatch.fnmatchcase(str(actual or ""), str(expected or ""))
    return matched if op == "GLOB" else not matched


def _build_like_regex(expected: Any, escape: Optional[str] = None) -> str:
    exp_str = str(expected or "")
    if escape:
        parts = re.split(re.escape(escape) + "(.)", exp_str)
        escaped_pattern = ""
        for i, p in enumerate(parts):
            if i % 2 == 1:
                escaped_pattern += re.escape(p)
            else:
                escaped_pattern += re.escape(p).replace("%", ".*").replace("_", ".")
        return f"^{escaped_pattern}$"
    escaped_pattern = re.escape(exp_str).replace("%", ".*").replace("_", ".")
    return f"^{escaped_pattern}$"


def _eval_like(
    op: str, actual: Any, expected: Any, escape: Optional[str] = None
) -> bool:
    pattern = _build_like_regex(expected, escape)
    matched = bool(re.search(pattern, str(actual or ""), re.IGNORECASE))
    return matched if "NOT" not in op else not matched


def _eval_membership(op: str, actual: Any, expected: Any) -> bool:
    in_list = expected if isinstance(expected, (list, tuple, set)) else [expected]
    is_member = (actual in in_list) or (str(actual) in [str(x) for x in in_list])
    return is_member if op == "IN" else not is_member


def _eval_null_or_between(op: str, actual: Any, expected: Any) -> Optional[bool]:
    if op in ("IS NULL", "IS NOT NULL"):
        return _eval_is_null(op, actual)
    if op in ("BETWEEN", "NOT BETWEEN"):
        return _eval_between(op, actual, expected)
    return None


def _eval_pattern_or_null(
    op: str, actual: Any, expected: Any, c_dict: Optional[Dict[str, Any]] = None
) -> Optional[bool]:
    res = _eval_null_or_between(op, actual, expected)
    if res is not None:
        return res
    if op in ("GLOB", "NOT GLOB"):
        return _eval_glob(op, actual, expected)
    if op in ("LIKE", "NOT LIKE"):
        return _eval_like(op, actual, expected, (c_dict or {}).get("escape"))
    return None


def _eval_comparison_branches(
    op: str, actual: Any, expected: Any, c_dict: Optional[Dict[str, Any]] = None
) -> bool:
    pat_res = _eval_pattern_or_null(op, actual, expected, c_dict)
    if pat_res is not None:
        return pat_res
    if op in (">=", "<=", ">", "<"):
        return _eval_relational(op, actual, expected)
    if op in ("IN", "NOT IN"):
        return _eval_membership(op, actual, expected)
    return True


def _eval_comparison(
    op: str, actual: Any, expected: Any, c_dict: Optional[Dict[str, Any]] = None
) -> bool:
    if op in ("IS NULL", "IS NOT NULL"):
        return _eval_is_null(op, actual)
    if op == "=":
        return str(actual) == str(expected)
    if op in ("!=", "<>"):
        return str(actual) != str(expected)
    if actual is None:
        return False
    return _eval_comparison_branches(op, actual, expected, c_dict)


def _is_column_reference(expected_val: str, record: Dict[str, Any]) -> bool:
    return expected_val in record or "." in expected_val or "->" in expected_val


def _resolve_condition_expected_val(record: Dict[str, Any], expected_val: Any) -> Any:
    """Resolves column reference in expected value if present."""
    if isinstance(expected_val, str) and _is_column_reference(expected_val, record):
        col_val = _extract_field_value(record, expected_val)
        if col_val is not None:
            return col_val
    return expected_val


def _evaluate_single_condition(record: Dict[str, Any], c: Dict[str, Any]) -> bool:
    field = c.get("field") or c.get("column") or ""
    op = c.get("op") or c.get("operator") or "="
    expected_val = _resolve_condition_expected_val(record, c.get("value"))
    actual = _extract_field_value(record, field)
    return _eval_comparison(op, actual, expected_val, c)


def _matches_or_branches(
    record: Dict[str, Any], branches: List[Dict[str, Any]]
) -> bool:
    for branch in branches:
        sub_clauses = branch.get("clauses", [])
        if all(_evaluate_single_condition(record, c) for c in sub_clauses):
            return True
    return False


def _matches_where_clause(
    record: Dict[str, Any], clauses: List[Dict[str, Any]]
) -> bool:
    if not clauses:
        return True
    if any(c.get("logic") == "OR_BRANCH" for c in clauses):
        return _matches_or_branches(record, clauses)
    return all(_evaluate_single_condition(record, c) for c in clauses)


def _inspect_table_slice(tname: str, storage: Any, target: str) -> Dict[str, Any]:
    r_count = len(getattr(storage, "metadata", []))
    f_size = len(storage.to_bytes()) if hasattr(storage, "to_bytes") else 0
    if target == "TABLE_STATUS":
        return {
            "Name": tname,
            "Engine": "MultiTableVectorStorage (OKFMTC01)",
            "Rows": r_count,
            "Data_length": f_size,
            "Create_time": "2026-09-08 00:00:00",
        }
    return {"Table": tname, "Rows": r_count, "Size_bytes": f_size}


def _load_multitable_rows(path: str, target: str) -> List[Dict[str, Any]]:
    from ..storage.multi_storage import MultiTableVectorStorage

    rows: List[Dict[str, Any]] = []
    with MultiTableVectorStorage(path) as container:
        container.load()
        for tname in sorted(container.list_tables()):
            tbl = container.get_table(tname)
            rows.append(_inspect_table_slice(tname, tbl, target))
    return rows


def _inspect_single_storage_table(path: str, target: str) -> List[Dict[str, Any]]:
    from ..storage.storage import VectorStorage

    storage = VectorStorage(path, dim=128)
    try:
        tname = os.path.splitext(os.path.basename(path))[0]
        return [_inspect_table_slice(tname, storage, target)]
    finally:
        storage.close()


def _filter_by_like(
    rows: List[Dict[str, Any]], pattern: Optional[str]
) -> List[Dict[str, Any]]:
    if not pattern:
        return rows
    clean = pattern.strip("%'\"").lower()
    return [r for r in rows if clean in r.get("Table", "").lower()]


def _query_external_db_tables(
    db_name: Optional[str],
    known_dbs: Dict[str, str],
    target: str,
    pattern: Optional[str],
) -> Optional[List[Dict[str, Any]]]:
    if not db_name:
        return None
    if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", db_name):
        raise SQLExecutionError(f"Invalid database identifier: {db_name!r}")
    if db_name not in known_dbs:
        return []
    rows = _load_external_db_tables(known_dbs[db_name], target)
    return _filter_by_like(rows, pattern) if rows else []


def _load_external_db_tables(path: str, target: str) -> List[Dict[str, Any]]:
    if not os.path.exists(path):
        return []
    try:
        with open(path, "rb") as f:
            magic = f.read(8)
        if magic == b"OKFMTC01":
            return _load_multitable_rows(path, target)
        if magic == b"OKFVEC01":
            return _inspect_single_storage_table(path, target)
        return []
    except Exception:
        return []


def _resolve_table_scope(tbl: Any, tname: str) -> str:
    scope = getattr(tbl, "database_scope", None)
    if scope:
        return str(scope)
    try:
        from settings import get_table_scope_from_settings

        return get_table_scope_from_settings(tname)
    except Exception:
        return "default"


def _filter_tables_by_database_scope(
    tables: Dict[str, Any], db_name: str, pattern: Optional[str]
) -> List[Tuple[str, Any]]:
    matched: List[Tuple[str, Any]] = []
    for tname, tbl in sorted(tables.items()):
        if _resolve_table_scope(tbl, tname) == db_name:
            if not (pattern and pattern not in tname):
                matched.append((tname, tbl))
    return matched


def _resolve_default_table_name(
    default_storage: VectorStorage, default_table_name: Optional[str]
) -> str:
    if default_table_name:
        return default_table_name
    if default_storage.file_path in (":memory:", ""):
        return "main"
    base = os.path.splitext(os.path.basename(default_storage.file_path))[0]
    if base.endswith("_test"):
        base = base[:-5]
    return base if base.isidentifier() else "main"


def _agg_count(inner: str, group_rows: List[Dict[str, Any]]) -> int:
    if inner in ("*", "1"):
        return len(group_rows)
    return sum(
        1 for r in group_rows if _extract_field_value(r, inner) not in (None, "")
    )


def _agg_numeric_list(inner: str, group_rows: List[Dict[str, Any]]) -> List[float]:
    return [float(_extract_field_value(r, inner) or 0) for r in group_rows]


def _agg_sum_avg(op: str, inner: str, group_rows: List[Dict[str, Any]]) -> float:
    nums = _agg_numeric_list(inner, group_rows)
    if not nums:
        return 0.0
    total = sum(nums)
    return total / len(nums) if op == "AVG" else total


def _agg_min_max(op: str, inner: str, group_rows: List[Dict[str, Any]]) -> Any:
    vals = [
        _extract_field_value(r, inner)
        for r in group_rows
        if _extract_field_value(r, inner) is not None
    ]
    if not vals:
        return None
    return min(vals) if op == "MIN" else max(vals)


def _is_valid_agg_call(upper: str, prefix: str) -> bool:
    return upper.startswith(prefix) and upper.endswith(")")


def _extract_agg_inner(norm: str, prefix_len: int) -> str:
    return norm[prefix_len:-1].strip()


def _compute_agg_count_sum_avg(
    upper: str, norm: str, group_rows: List[Dict[str, Any]]
) -> Optional[Any]:
    if _is_valid_agg_call(upper, "COUNT("):
        return _agg_count(_extract_agg_inner(norm, 6), group_rows)
    if _is_valid_agg_call(upper, "SUM("):
        return _agg_sum_avg("SUM", _extract_agg_inner(norm, 4), group_rows)
    if _is_valid_agg_call(upper, "AVG("):
        return _agg_sum_avg("AVG", _extract_agg_inner(norm, 4), group_rows)
    return None


def _compute_agg_min_max(
    upper: str, norm: str, group_rows: List[Dict[str, Any]]
) -> Optional[Any]:
    if _is_valid_agg_call(upper, "MIN("):
        return _agg_min_max("MIN", _extract_agg_inner(norm, 4), group_rows)
    if _is_valid_agg_call(upper, "MAX("):
        return _agg_min_max("MAX", _extract_agg_inner(norm, 4), group_rows)
    return None


def _compute_agg_func(
    upper: str, norm: str, group_rows: List[Dict[str, Any]]
) -> Optional[Any]:
    c_val = _compute_agg_count_sum_avg(upper, norm, group_rows)
    if c_val is not None:
        return c_val
    return _compute_agg_min_max(upper, norm, group_rows)


def _compute_agg_col(col_expr: str, group_rows: List[Dict[str, Any]]) -> Any:
    norm = col_expr.strip()
    upper = norm.upper()
    val = _compute_agg_func(upper, norm, group_rows)
    if val is not None:
        return val
    first_row = group_rows[0] if group_rows else {}
    return _extract_field_value(first_row, norm)


def _build_group_key(row: Dict[str, Any], group_cols: List[str]) -> Tuple[Any, ...]:
    return tuple(_extract_field_value(row, col) for col in group_cols)


def _cluster_rows(
    rows: List[Dict[str, Any]], group_cols: List[str]
) -> Dict[Tuple[Any, ...], List[Dict[str, Any]]]:
    groups: Dict[Tuple[Any, ...], List[Dict[str, Any]]] = {}
    for r in rows:
        k = _build_group_key(r, group_cols)
        if k not in groups:
            groups[k] = []
        groups[k].append(r)
    return groups


def _extract_target_columns(stmt: SelectStatement) -> List[str]:
    cols = list(stmt.columns)
    for gcol in stmt.group_by:
        if gcol not in cols and "*" not in cols:
            cols.append(gcol)
    return cols


def _group_and_aggregate_rows(
    rows: List[Dict[str, Any]], stmt: SelectStatement
) -> List[Dict[str, Any]]:
    if not stmt.group_by:
        return rows
    groups = _cluster_rows(rows, stmt.group_by)
    target_cols = _extract_target_columns(stmt)
    result: List[Dict[str, Any]] = []
    for _gkey, g_rows in groups.items():
        row_dict: Dict[str, Any] = {}
        for col_expr in target_cols:
            row_dict[col_expr] = _compute_agg_col(col_expr, g_rows)
        result.append(row_dict)
    return result


def _parse_having_expression(expr: str) -> Optional[Tuple[str, str, str]]:
    m = re.match(r"^(.+?)\s*(=|!=|<>|>=|<=|>|<)\s*(.+)$", expr.strip())
    if not m:
        return None
    return m.group(1).strip(), m.group(2).strip(), m.group(3).strip()


def _coerce_having_vals(val_str: str, act_val: Any) -> Tuple[Any, Any]:
    cleaned = val_str.strip("'\"")
    if isinstance(act_val, (int, float)):
        try:
            return act_val, float(cleaned)
        except ValueError:
            return act_val, cleaned
    return str(act_val), cleaned


def _eval_having_eq_neq(act: Any, op: str, exp: Any) -> Optional[bool]:
    if op in ("=", "=="):
        return bool(act == exp)
    if op in ("!=", "<>"):
        return bool(act != exp)
    return None


def _eval_having_rel(act: Any, op: str, exp: Any) -> bool:
    if op == ">":
        return bool(act > exp)
    if op == ">=":
        return bool(act >= exp)
    if op == "<":
        return bool(act < exp)
    if op == "<=":
        return bool(act <= exp)
    return False


def _eval_having_comparison(act: Any, op: str, exp: Any) -> bool:
    eq_res = _eval_having_eq_neq(act, op, exp)
    if eq_res is not None:
        return eq_res
    return _eval_having_rel(act, op, exp)


def _resolve_having_actual_val(row: Dict[str, Any], left_expr: str) -> Any:
    if left_expr in row:
        return row[left_expr]
    for k, v in row.items():
        if k.upper() == left_expr.upper():
            return v
    return _extract_field_value(row, left_expr)


def _matches_having(row: Dict[str, Any], having_expr: str) -> bool:
    parsed = _parse_having_expression(having_expr)
    if not parsed:
        return True
    left_expr, op, right_expr = parsed
    act_val = _resolve_having_actual_val(row, left_expr)
    act, exp = _coerce_having_vals(right_expr, act_val)
    try:
        return _eval_having_comparison(act, op, exp)
    except TypeError:
        return False


def _filter_having_rows(
    rows: List[Dict[str, Any]], having_expr: Optional[str]
) -> List[Dict[str, Any]]:
    if not having_expr:
        return rows
    return [r for r in rows if _matches_having(r, having_expr)]


class SQLExecutor:
    """
    Coordinates SQL parsing, access control enforcement, transaction staging,
    and storage execution.
    """

    def __init__(
        self,
        default_storage: Optional[VectorStorage] = None,
        default_index: Optional[HNSWIndex] = None,
        embedding: Optional[DeterministicEmbedding] = None,
        catalog: Optional[TableCatalog] = None,
        access_controller: Optional[AccessController] = None,
        tx_manager: Optional[TransactionManager] = None,
        multi_storage: Optional[Any] = None,
        known_databases: Optional[Dict[str, str]] = None,
        default_table_name: Optional[str] = None,
    ) -> None:
        self.parser = SQLParser()
        self._init_components(access_controller, tx_manager, embedding)
        self.default_storage = default_storage
        self.multi_storage = multi_storage
        self.default_table_name = default_table_name
        self.known_databases: Dict[str, str] = dict(known_databases or {})
        self.tables: Dict[str, TableCatalog] = {}
        self.views: Dict[str, CreateViewStatement] = {}
        self._init_default_tables(
            catalog,
            default_storage,
            default_index,
            default_table_name=default_table_name,
        )
        if self.multi_storage is not None:
            self.multi_storage.attach_to_executor(self)

    def _init_components(
        self,
        access_controller: Optional[AccessController],
        tx_manager: Optional[TransactionManager],
        embedding: Optional[DeterministicEmbedding],
    ) -> None:
        self.access_controller = access_controller or AccessController()
        self.tx_manager = tx_manager or TransactionManager()
        self.embedding = embedding or DeterministicEmbedding(dim=128)

    def register_database(self, name: str, path: str) -> None:
        """Dynamically register or update a known database path with identifier validation."""
        if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", name):
            raise SQLExecutionError(
                f"Invalid database name '{name}'. Database names must be valid SQL identifiers."
            )
        if len(self.known_databases) >= 64 and name not in self.known_databases:
            raise SQLExecutionError(
                "Maximum number of registered databases (64) exceeded"
            )
        self.known_databases[name] = path

    def _init_default_tables(
        self,
        catalog: Optional[TableCatalog],
        default_storage: Optional[VectorStorage],
        default_index: Optional[HNSWIndex],
        default_table_name: Optional[str] = None,
    ) -> None:
        if catalog is not None:
            self.tables[catalog.name] = catalog
        elif default_storage:
            tbl_name = _resolve_default_table_name(default_storage, default_table_name)
            self.tables[tbl_name] = TableCatalog(
                name=tbl_name,
                storage=default_storage,
                index=default_index or HNSWIndex(dim=default_storage.dim),
            )

    def execute(
        self,
        sql: str,
        role: Optional[str] = None,
        params: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        effective_role = role or self.access_controller.current_role
        logger.info("⚡ [SQL Exec] [%s] %s", effective_role, sql.strip())
        stmt = self.parser.parse(sql)
        return self.execute_statement(stmt, role=effective_role)

    def _restore_table_snapshot(self, tname: str, sdata: Dict[str, Any]) -> None:
        if tname in self.tables:
            tcat = self.tables[tname]
            tcat.storage.metadata = [dict(m) for m in sdata.get("meta", [])]
            vecs = sdata.get("vecs", [])
            tcat.storage.write_all(vecs, tcat.storage.metadata)
            tcat.index = HNSWIndex(dim=tcat.storage.dim)
            tcat.index.build_from_storage(vecs)

    def _restore_rollback_snapshot(self, snapshot: Optional[Dict[str, Any]]) -> None:
        if not snapshot or not isinstance(snapshot, dict):
            return
        for tname, sdata in snapshot.items():
            self._restore_table_snapshot(tname, sdata)

    def _exec_begin_tx(self) -> Dict[str, Any]:
        snapshot = {
            tname: {
                "meta": [dict(m) for m in tcat.storage.metadata],
                "vecs": tcat.storage.get_all_vectors(),
            }
            for tname, tcat in self.tables.items()
        }
        self.tx_manager.begin(snapshot)
        return {"command": "BEGIN", "status": "ok", "message": "Transaction started"}

    def _exec_tcl(self, cmd: SQLCommandType) -> Dict[str, Any]:
        if cmd == SQLCommandType.BEGIN:
            return self._exec_begin_tx()
        if cmd == SQLCommandType.COMMIT:
            mutations = self.tx_manager.commit()
            if self.multi_storage is not None:
                self.multi_storage.save()
            return {
                "command": "COMMIT",
                "status": "ok",
                "mutations_applied": len(mutations),
            }
        if cmd == SQLCommandType.ROLLBACK:
            snapshot_res = self.tx_manager.rollback()
            self._restore_rollback_snapshot(snapshot_res)
            return {"command": "ROLLBACK", "status": "ok", "mutations_reverted": 1}
        raise SQLExecutionError(f"Unknown TCL command: {cmd}")

    def _exec_grant(self, stmt: GrantStatement, effective_role: str) -> Dict[str, Any]:
        self.access_controller.grant(stmt.permission, stmt.table_name, stmt.role)
        return {
            "command": "GRANT",
            "status": "ok",
            "message": f"Granted '{stmt.permission}' on '{stmt.table_name}' to role '{stmt.role}'",
        }

    def _exec_revoke(
        self, stmt: RevokeStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.revoke(stmt.permission, stmt.table_name, stmt.role)
        return {
            "command": "REVOKE",
            "status": "ok",
            "message": f"Revoked '{stmt.permission}' on '{stmt.table_name}' from role '{stmt.role}'",
        }

    def _is_in_memory_mode(self) -> bool:
        if self.default_storage and getattr(self.default_storage, "is_memory", False):
            return True
        return any(
            getattr(t.storage, "is_memory", False)
            or getattr(t.storage, "file_path", "") == ":memory:"
            for t in self.tables.values()
        )

    def _resolve_new_table_path(self, table_name: str) -> str:
        if not self.default_storage or self.default_storage.file_path in (
            ":memory:",
            "",
        ):
            return ":memory:"
        base_dir = os.path.dirname(self.default_storage.file_path) or "."
        return os.path.join(base_dir, f"{table_name}.vdb")

    def _resolve_engine_loc(
        self, stmt: CreateTableStatement, engine_name: str
    ) -> Optional[str]:
        if stmt.location:
            return stmt.location
        if engine_name == "binary_vdb":
            loc = self._resolve_new_table_path(stmt.table_name)
            _safe_remove_file(loc)
            return loc
        return None

    def _build_engine_kwargs(self, stmt: CreateTableStatement) -> Dict[str, Any]:
        kw: Dict[str, Any] = {
            "dim": self.embedding.dim,
            "table_name": stmt.table_name,
        }
        for col in stmt.columns:
            if col.is_primary_key:
                kw["primary_key"] = col.name
                break
        return kw

    def _create_engine_storage(self, stmt: CreateTableStatement) -> Any:
        from database.storage.factory import StorageEngineFactory

        engine_name = stmt.storage_engine or "binary_vdb"
        loc = self._resolve_engine_loc(stmt, engine_name)
        kwargs = self._build_engine_kwargs(stmt)
        return StorageEngineFactory.create_by_engine_name(
            engine_name,
            location=loc,
            **kwargs,
        )

    def _create_default_storage(self, stmt: CreateTableStatement) -> Any:
        if self.multi_storage is not None:
            return self.multi_storage.create_table(
                stmt.table_name, dim=self.embedding.dim
            )
        if self._is_in_memory_mode():
            return VectorStorage(file_path=":memory:", dim=self.embedding.dim)

        storage_path = self._resolve_new_table_path(stmt.table_name)
        os.makedirs(os.path.dirname(os.path.abspath(storage_path)), exist_ok=True)
        _safe_remove_file(storage_path)
        return VectorStorage(file_path=storage_path, dim=self.embedding.dim)

    def _instantiate_table_storage(self, stmt: CreateTableStatement) -> Any:
        if stmt.storage_engine:
            return self._create_engine_storage(stmt)
        return self._create_default_storage(stmt)

    def _create_new_table_storage(self, stmt: CreateTableStatement) -> None:
        storage = self._instantiate_table_storage(stmt)
        catalog = TableCatalog(
            name=stmt.table_name,
            storage=storage,
            schema={col.name: col.data_type for col in stmt.columns},
            raw_sql=stmt.raw_sql,
            storage_engine=stmt.storage_engine,
            location=stmt.location,
        )
        self.tables[stmt.table_name] = catalog

    def _exec_create_table(
        self, stmt: CreateTableStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "CREATE_TABLE"
        )
        if stmt.table_name in self.tables:
            if stmt.if_not_exists:
                return {
                    "command": "CREATE_TABLE",
                    "status": "ok",
                    "message": f"Table '{stmt.table_name}' already exists (skipped)",
                }
            raise SQLExecutionError(f"Table '{stmt.table_name}' already exists.")

        self._create_new_table_storage(stmt)
        return {
            "command": "CREATE_TABLE",
            "status": "ok",
            "table": stmt.table_name,
            "columns": len(stmt.columns),
        }

    def _remove_table_file(self, tcat: TableCatalog) -> None:
        storage_file = getattr(tcat.storage, "file_path", None)
        _safe_remove_file(storage_file)

    def _exec_drop_table(
        self, stmt: DropTableStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "DROP_TABLE"
        )
        if stmt.table_name not in self.tables:
            if stmt.if_exists:
                return {
                    "command": "DROP_TABLE",
                    "status": "ok",
                    "message": f"Table '{stmt.table_name}' does not exist (skipped)",
                }
            raise SQLExecutionError(f"Table '{stmt.table_name}' does not exist.")

        tcat = self.tables.pop(stmt.table_name)
        if self.multi_storage is not None:
            self.multi_storage.drop_table(stmt.table_name)
        else:
            self._remove_table_file(tcat)
        return {
            "command": "DROP_TABLE",
            "status": "ok",
            "table": stmt.table_name,
            "dropped": True,
        }

    def _exec_create_index(
        self, stmt: CreateIndexStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "CREATE_INDEX"
        )
        table = self._get_table(stmt.table_name)
        idx_type = stmt.index_type.upper()
        if idx_type == "HNSW":
            vecs = table.storage.get_all_vectors()
            table.index = HNSWIndex(dim=table.storage.dim)
            table.index.build_from_storage(vecs)
        elif idx_type == "BTREE":
            btree = BPlusTree(column_name=stmt.column_name)
            for idx, meta in enumerate(table.storage.metadata):
                val = meta.get(stmt.column_name)
                if val is not None:
                    btree.insert(val, idx)
            table.btree_indexes[stmt.column_name] = btree
            table.btree_index_names[stmt.column_name] = stmt.index_name
        else:
            raise SQLExecutionError(f"Unsupported index type: {idx_type}")

        table.index_definitions.append(
            {
                "name": stmt.index_name,
                "table": stmt.table_name,
                "column": stmt.column_name,
                "type": idx_type,
                "raw_sql": stmt.raw_sql,
            }
        )

        return {
            "command": "CREATE_INDEX",
            "status": "ok",
            "index": stmt.index_name,
            "table": stmt.table_name,
            "column": stmt.column_name,
            "type": idx_type,
        }

    def _alter_rename_table(
        self, stmt: AlterTableStatement, table: TableCatalog
    ) -> Dict[str, Any]:
        new_name = stmt.new_table_name
        if not new_name:
            raise SQLExecutionError("Target table name for RENAME TO is required.")
        if new_name in self.tables:
            raise SQLExecutionError(f"Table '{new_name}' already exists.")
        self.tables.pop(stmt.table_name)
        table.name = new_name
        self.tables[new_name] = table
        return {"action": "RENAME_TABLE", "table": new_name}

    def _alter_rename_column(
        self, stmt: AlterTableStatement, table: TableCatalog
    ) -> Dict[str, Any]:
        old_col = stmt.old_column_name
        new_col = stmt.new_column_name
        if not old_col or not new_col:
            raise SQLExecutionError("Column names for RENAME COLUMN are required.")
        if table.schema and old_col in table.schema:
            table.schema[new_col] = table.schema.pop(old_col)
        _rename_metadata_col(table, old_col, new_col)
        _update_index_for_renamed_col(table, old_col, new_col)
        _save_table_storage(table)
        return {"action": "RENAME_COLUMN", "old": old_col, "new": new_col}

    def _alter_add_column(
        self, stmt: AlterTableStatement, table: TableCatalog
    ) -> Dict[str, Any]:
        c_def = stmt.column_def
        if not c_def:
            raise SQLExecutionError("Column definition for ADD COLUMN is required.")
        if table.schema is not None:
            table.schema[c_def.name] = c_def.data_type
        for meta in table.storage.metadata:
            meta[c_def.name] = stmt.default_value
        _save_table_storage(table)
        return {"action": "ADD_COLUMN", "column": c_def.name}

    def _alter_drop_column(
        self, stmt: AlterTableStatement, table: TableCatalog
    ) -> Dict[str, Any]:
        col_name = stmt.drop_column_name
        if not col_name:
            raise SQLExecutionError("Column name for DROP COLUMN is required.")
        if table.schema is not None:
            table.schema.pop(col_name, None)
        for meta in table.storage.metadata:
            meta.pop(col_name, None)
        _remove_index_for_dropped_col(table, col_name)
        _save_table_storage(table)
        return {"action": "DROP_COLUMN", "column": col_name}

    def _exec_alter_table(
        self, stmt: AlterTableStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "CREATE_TABLE"
        )
        table = self._get_table(stmt.table_name)
        if stmt.action == AlterTableAction.RENAME_TABLE:
            res = self._alter_rename_table(stmt, table)
        elif stmt.action == AlterTableAction.RENAME_COLUMN:
            res = self._alter_rename_column(stmt, table)
        elif stmt.action == AlterTableAction.ADD_COLUMN:
            res = self._alter_add_column(stmt, table)
        elif stmt.action == AlterTableAction.DROP_COLUMN:
            res = self._alter_drop_column(stmt, table)
        else:
            raise SQLExecutionError(f"Unsupported ALTER TABLE action: {stmt.action}")
        return {"command": "ALTER_TABLE", "status": "ok", **res}

    def _exec_drop_index(
        self, stmt: DropIndexStatement, effective_role: str
    ) -> Dict[str, Any]:
        found = False
        for tbl in self.tables.values():
            if _drop_matching_index_from_table(tbl, stmt.index_name):
                found = True
        if not found and not stmt.if_exists:
            raise SQLExecutionError(f"Index '{stmt.index_name}' does not exist")
        return {
            "command": "DROP_INDEX",
            "status": "ok",
            "index": stmt.index_name,
            "dropped": found,
        }

    def _reindex_single_table_or_target(
        self, tbl: TableCatalog, tname: str, target: Optional[str]
    ) -> int:
        if target is None or target == tname:
            return _rebuild_table_indexes(tbl)
        return _rebuild_named_btree_index(tbl, target)

    def _exec_reindex(
        self, stmt: ReindexStatement, effective_role: str
    ) -> Dict[str, Any]:
        target = stmt.target_name
        reindexed_cnt = sum(
            self._reindex_single_table_or_target(tbl, tname, target)
            for tname, tbl in self.tables.items()
        )
        return {
            "command": "REINDEX",
            "status": "ok",
            "target": target or "ALL",
            "reindexed_count": reindexed_cnt,
        }

    def _exec_create_view(
        self, stmt: CreateViewStatement, effective_role: str
    ) -> Dict[str, Any]:
        if stmt.view_name in self.views:
            if stmt.if_not_exists:
                return {
                    "command": "CREATE_VIEW",
                    "status": "ok",
                    "message": f"View '{stmt.view_name}' already exists (skipped)",
                }
            raise SQLExecutionError(f"View '{stmt.view_name}' already exists.")
        if stmt.view_name in self.tables:
            raise SQLExecutionError(f"Table '{stmt.view_name}' already exists.")
        self.views[stmt.view_name] = stmt
        return {"command": "CREATE_VIEW", "status": "ok", "view": stmt.view_name}

    def _exec_drop_view(
        self, stmt: DropViewStatement, effective_role: str
    ) -> Dict[str, Any]:
        if stmt.view_name not in self.views:
            if stmt.if_exists:
                return {
                    "command": "DROP_VIEW",
                    "status": "ok",
                    "message": f"View '{stmt.view_name}' does not exist (skipped)",
                    "view": stmt.view_name,
                    "dropped": False,
                }
            raise SQLExecutionError(f"View '{stmt.view_name}' does not exist.")
        self.views.pop(stmt.view_name, None)
        return {
            "command": "DROP_VIEW",
            "status": "ok",
            "view": stmt.view_name,
            "dropped": True,
        }

    def _exec_explain(
        self, stmt: ExplainStatement, effective_role: str
    ) -> Dict[str, Any]:
        if not isinstance(stmt.statement, SelectStatement):
            return {
                "command": "EXPLAIN",
                "status": "ok",
                "rows": [{"id": 1, "detail": "EXPLAIN for non-SELECT statement"}],
            }
        sub_stmt = stmt.statement
        self.access_controller.enforce_permission(
            effective_role, sub_stmt.table_name, "SELECT"
        )
        table = self._get_table(sub_stmt.table_name)
        table.recompute_stats()
        avail_indexes = {
            col: table.btree_index_names.get(col, f"idx_{col}")
            for col in table.btree_indexes.keys()
        }
        explain_rows = QueryPlanner.explain(
            sub_stmt, table.stats, available_indexes=avail_indexes
        )
        return {"command": "EXPLAIN", "status": "ok", "rows": explain_rows}

    def _query_knn_rows(
        self, table: TableCatalog, knn_query: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        query_vec = self.embedding.normalize(knn_query["vector"])
        rows: List[Dict[str, Any]] = []
        for idx, sim in table.index.search(query_vec, top_k=knn_query["top_k"]):
            if idx < len(table.storage.metadata):
                meta = dict(table.storage.get_metadata(idx))
                meta["score"] = round(sim, 4)
                meta["_idx"] = idx
                rows.append(meta)
        return rows

    def _scan_all_table_rows(
        self, table: TableCatalog, limit: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        rows: List[Dict[str, Any]] = []
        for idx, meta in enumerate(table.storage.metadata):
            if limit is not None and len(rows) >= limit:
                break
            if hasattr(meta, "to_shallow_dict"):
                item: Dict[str, Any] = LazyRow(meta.to_shallow_dict(), source=meta)
            else:
                item = dict(meta)
            item["_idx"] = idx
            rows.append(item)
        return rows

    def _find_temp_rows(
        self,
        temp_tables: Optional[Dict[str, List[Dict[str, Any]]]],
        table_name: str,
        limit: Optional[int],
    ) -> Optional[List[Dict[str, Any]]]:
        if not temp_tables or table_name not in temp_tables:
            return None
        res = [dict(r) for r in temp_tables[table_name]]
        return res[:limit] if limit is not None else res

    def _query_knn_or_scan(
        self,
        table_name: str,
        knn_query: Optional[Dict[str, Any]],
        temporary_tables: Optional[Dict[str, List[Dict[str, Any]]]] = None,
        limit: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        temp_rows = self._find_temp_rows(temporary_tables, table_name, limit)
        if temp_rows is not None:
            return temp_rows

        table = self._get_table(table_name)
        if knn_query:
            return self._query_knn_rows(table, knn_query)
        return self._scan_all_table_rows(table, limit=limit)

    def _prefix_record(
        self, record: Dict[str, Any], table_ref: TableRef
    ) -> Dict[str, Any]:
        prefixed: Dict[str, Any] = (
            LazyRow(dict(record), source=record._source, table_prefix=table_ref.name)
            if isinstance(record, LazyRow)
            else dict(record)
        )
        name, alias = table_ref.name, table_ref.alias
        for k, v in list(record.items()):
            prefixed[f"{name}.{k}"] = v
            if alias:
                prefixed[f"{alias}.{k}"] = v
        return prefixed

    def _evaluate_recursive_cte(
        self,
        cte: Any,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        anchor_stmt = cte.statement
        rec_stmt = anchor_stmt.union_all
        anchor_stmt.union_all = None

        anchor_res = self._exec_select(
            anchor_stmt, effective_role, temporary_tables=temp_tables
        )
        accumulated = list(anchor_res.get("rows", []))
        work_table = list(anchor_res.get("rows", []))

        for _ in range(50):
            if not work_table or not rec_stmt:
                break
            step_ctx = {**temp_tables, cte.name: work_table}
            rec_res = self._exec_select(
                rec_stmt, effective_role, temporary_tables=step_ctx
            )
            new_rows = rec_res.get("rows", [])
            if not new_rows:
                break
            accumulated.extend(new_rows)
            work_table = new_rows
        return accumulated

    def _evaluate_all_ctes(
        self,
        ctes: List[Any],
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> None:
        for cte in ctes:
            if not cte.is_recursive:
                res = self._exec_select(
                    cte.statement, effective_role, temporary_tables=temp_tables
                )
                temp_tables[cte.name] = res.get("rows", [])
            else:
                temp_tables[cte.name] = self._evaluate_recursive_cte(
                    cte, effective_role, temp_tables
                )

    def _collect_referenced_table_names(self, stmt: SelectStatement) -> List[str]:
        target = _resolve_stmt_target_table(stmt)
        join_tables = _extract_join_tables(stmt.joins)
        return ([target] if target else []) + join_tables

    def _evaluate_referenced_views(
        self,
        stmt: SelectStatement,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> None:
        ref_names = self._collect_referenced_table_names(stmt)
        for name in ref_names:
            if name in self.views and name not in temp_tables:
                v_stmt = self.views[name]
                if v_stmt.select_stmt is not None:
                    res = self._exec_select(
                        v_stmt.select_stmt, effective_role, temporary_tables=temp_tables
                    )
                    temp_tables[name] = res.get("rows", [])

    def _find_matching_join_rows(
        self,
        left_row: Dict[str, Any],
        j_prefixed_rows: List[Dict[str, Any]],
        conditions: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        matched: List[Dict[str, Any]] = []
        for right_row in j_prefixed_rows:
            combined = CombinedRow(left_row, right_row)
            if _matches_where_clause(combined, conditions):
                matched.append(combined)
        return matched

    def _left_join_fallback(
        self, left_row: Dict[str, Any], j_prefixed_rows: List[Dict[str, Any]]
    ) -> List[Dict[str, Any]]:
        keys = j_prefixed_rows[0].keys() if j_prefixed_rows else []
        empty_right = {k: None for k in keys}
        return [{**left_row, **empty_right}]

    def _match_join_row(
        self,
        left_row: Dict[str, Any],
        j_prefixed_rows: List[Dict[str, Any]],
        join: Any,
    ) -> List[Dict[str, Any]]:
        matched = self._find_matching_join_rows(
            left_row, j_prefixed_rows, join.on_conditions
        )
        if not matched and join.join_type == JoinType.LEFT:
            return self._left_join_fallback(left_row, j_prefixed_rows)
        return matched

    def _join_table_rows(
        self,
        current_rows: List[Dict[str, Any]],
        join: Any,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        join_tbl_ref = join.table
        if join_tbl_ref.name not in temp_tables:
            self.access_controller.enforce_permission(
                effective_role, join_tbl_ref.name, "SELECT"
            )

        j_raw_rows = self._query_knn_or_scan(
            join_tbl_ref.name, None, temporary_tables=temp_tables
        )
        j_prefixed_rows = [self._prefix_record(r, join_tbl_ref) for r in j_raw_rows]

        next_rows: List[Dict[str, Any]] = []
        for left_row in current_rows:
            next_rows.extend(self._match_join_row(left_row, j_prefixed_rows, join))
        return next_rows

    def _project_column_item(self, r: Dict[str, Any], col_expr: str) -> Tuple[str, Any]:
        as_m = re.search(r"\s+AS\s+([a-zA-Z0-9_]+)$", col_expr, re.IGNORECASE)
        if as_m:
            out_key = as_m.group(1).strip()
            raw_col = col_expr[: as_m.start()].strip()
            return out_key, _extract_field_value(r, raw_col)

        out_key = col_expr
        if "." in out_key and "->" not in out_key:
            _, out_key = out_key.split(".", 1)
        return out_key, _extract_field_value(r, col_expr)

    def _project_wildcard(self, r: Dict[str, Any], table_name: str) -> Dict[str, Any]:
        return {
            k: v for k, v in r.items() if "." not in k or k.startswith(f"{table_name}.")
        }

    def _project_row(
        self, r: Dict[str, Any], columns: List[str], table_name: str
    ) -> Dict[str, Any]:
        if "*" in columns and len(columns) == 1:
            return self._project_wildcard(r, table_name)
        projected = {}
        for col_expr in columns:
            k, v = self._project_column_item(r, col_expr.strip())
            projected[k] = v
        return projected

    @staticmethod
    def _deduplicate_rows(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        seen: set[Tuple[Any, ...]] = set()
        unique: List[Dict[str, Any]] = []
        for r in rows:
            key = tuple((k, str(v)) for k, v in sorted(r.items()))
            if key not in seen:
                seen.add(key)
                unique.append(r)
        return unique

    @staticmethod
    def _slice_rows(
        rows: List[Dict[str, Any]],
        limit: Optional[int],
        offset: Optional[int],
    ) -> List[Dict[str, Any]]:
        start = 0 if offset is None else offset
        end = None if limit is None else start + limit
        return rows[start:end]

    @staticmethod
    def _sort_key(row: Dict[str, Any], order_by: str) -> Any:
        val = _extract_field_value(row, order_by)
        return 0 if val is None else val

    def _sort_and_paginate(
        self,
        rows: List[Dict[str, Any]],
        order_by: Optional[str],
        order_desc: bool,
        limit: Optional[int],
        offset: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        if order_by:
            rows.sort(
                key=lambda x: self._sort_key(x, order_by),
                reverse=order_desc,
            )
        return self._slice_rows(rows, limit, offset)

    @staticmethod
    def _determine_scan_limit(stmt: SelectStatement) -> Optional[int]:
        conditions = [
            bool(stmt.where_clauses),
            bool(stmt.joins),
            bool(stmt.order_by),
            bool(stmt.distinct),
            bool(stmt.group_by),
            bool(stmt.offset),
        ]
        return None if any(conditions) else stmt.limit

    def _get_initial_select_rows(
        self,
        table_ref: TableRef,
        stmt: SelectStatement,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        if table_ref.name not in temp_tables:
            self.access_controller.enforce_permission(
                effective_role, table_ref.name, "SELECT"
            )
        scan_limit = self._determine_scan_limit(stmt)
        raw_rows = self._query_knn_or_scan(
            table_ref.name,
            stmt.knn_query,
            temporary_tables=temp_tables,
            limit=scan_limit,
        )
        return [self._prefix_record(r, table_ref) for r in raw_rows]

    def _scan_and_join_tables(
        self,
        stmt: SelectStatement,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        table_ref = stmt.table_ref or TableRef(name=stmt.table_name)
        current_rows = self._get_initial_select_rows(
            table_ref, stmt, effective_role, temp_tables
        )

        for join in stmt.joins or []:
            current_rows = self._join_table_rows(
                current_rows, join, effective_role, temp_tables
            )
        return current_rows

    @staticmethod
    def _has_complex_select_clauses(stmt: SelectStatement) -> bool:
        return any(
            (
                stmt.where_clauses,
                stmt.joins,
                stmt.ctes,
                stmt.union_all,
                stmt.group_by,
                stmt.having,
            )
        )

    @classmethod
    def _is_simple_count_query(cls, stmt: SelectStatement) -> bool:
        """Returns True if the SELECT statement is a simple COUNT(*) without joins/filters."""
        if cls._has_complex_select_clauses(stmt):
            return False
        if stmt.limit is not None or len(stmt.columns) != 1:
            return False
        return stmt.columns[0].lower() in ("count(*)", "count(1)")

    @staticmethod
    def _handle_count_star(
        stmt: SelectStatement, count: int
    ) -> Optional[Dict[str, Any]]:
        if stmt.group_by:
            return None
        if len(stmt.columns) == 1 and stmt.columns[0].lower() in (
            "count(*)",
            "count(1)",
        ):
            return {
                "command": "SELECT",
                "status": "ok",
                "count": 1,
                "rows": [{"COUNT(*)": count}],
            }
        return None

    def _resolve_table_count(self, table_name: str, role: str) -> Optional[int]:
        if not table_name or table_name not in self.tables:
            return None
        self.access_controller.enforce_permission(role, table_name, "SELECT")
        storage = self.tables[table_name].storage
        if hasattr(storage, "__len__"):
            return len(storage)
        return len(storage.metadata)

    def _exec_fast_count(
        self, stmt: SelectStatement, effective_role: str
    ) -> Optional[Dict[str, Any]]:
        tname = stmt.table_name or (stmt.table_ref.name if stmt.table_ref else "")
        count_val = self._resolve_table_count(tname, effective_role)
        if count_val is None:
            return None
        return {
            "command": "SELECT",
            "status": "ok",
            "count": 1,
            "rows": [{"COUNT(*)": count_val}],
        }

    def _apply_distinct_and_slice(
        self, rows: List[Dict[str, Any]], stmt: SelectStatement
    ) -> List[Dict[str, Any]]:
        if not stmt.distinct:
            return rows
        deduped = self._deduplicate_rows(rows)
        return self._slice_rows(deduped, stmt.limit, stmt.offset)

    def _build_select_result(
        self,
        paged_rows: List[Dict[str, Any]],
        stmt: SelectStatement,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> Dict[str, Any]:
        cnt_res = self._handle_count_star(stmt, len(paged_rows))
        if cnt_res is not None:
            return cnt_res

        table_ref = stmt.table_ref or TableRef(name=stmt.table_name)
        final_rows = [
            self._project_row(r, stmt.columns, table_ref.name) for r in paged_rows
        ]
        final_rows = self._apply_distinct_and_slice(final_rows, stmt)

        if stmt.union_all:
            union_res = self._exec_select(
                stmt.union_all, effective_role, temporary_tables=temp_tables
            )
            final_rows.extend(union_res.get("rows", []))

        return {
            "command": "SELECT",
            "status": "ok",
            "count": len(final_rows),
            "rows": final_rows,
        }

    def _try_fast_count_select(
        self, stmt: SelectStatement, role: str, temp_tables: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        if not temp_tables and self._is_simple_count_query(stmt):
            return self._exec_fast_count(stmt, role)
        return None

    @staticmethod
    def _filter_select_rows(
        rows: List[Dict[str, Any]], where_clauses: Any
    ) -> List[Dict[str, Any]]:
        return [r for r in rows if _matches_where_clause(r, where_clauses)]

    @staticmethod
    def _apply_group_and_having(
        rows: List[Dict[str, Any]], stmt: SelectStatement
    ) -> List[Dict[str, Any]]:
        if not stmt.group_by:
            return rows
        aggregated_rows = _group_and_aggregate_rows(rows, stmt)
        return _filter_having_rows(aggregated_rows, stmt.having)

    @staticmethod
    def _resolve_paginate_limits(
        stmt: SelectStatement,
    ) -> Tuple[Optional[int], Optional[int]]:
        if stmt.distinct:
            return None, None
        return stmt.limit, stmt.offset

    def _exec_select(
        self,
        stmt: SelectStatement,
        effective_role: str,
        temporary_tables: Optional[Dict[str, List[Dict[str, Any]]]] = None,
    ) -> Dict[str, Any]:
        temp_tables = dict(temporary_tables or {})
        fast_cnt = self._try_fast_count_select(stmt, effective_role, temp_tables)
        if fast_cnt is not None:
            return fast_cnt

        if self.views:
            self._evaluate_referenced_views(stmt, effective_role, temp_tables)

        if stmt.ctes:
            self._evaluate_all_ctes(stmt.ctes, effective_role, temp_tables)

        current_rows = self._scan_and_join_tables(stmt, effective_role, temp_tables)
        filtered_rows = self._filter_select_rows(current_rows, stmt.where_clauses)
        grouped_rows = self._apply_group_and_having(filtered_rows, stmt)
        lim, off = self._resolve_paginate_limits(stmt)
        paged_rows = self._sort_and_paginate(
            grouped_rows, stmt.order_by, stmt.order_desc, lim, off
        )
        return self._build_select_result(paged_rows, stmt, effective_role, temp_tables)

    def _resolve_insert_vector(
        self, col_val_map: Dict[str, Any], dim: int
    ) -> List[float]:
        raw_vec = col_val_map.get("vector")
        if not raw_vec and "text" in col_val_map:
            raw_vec = self.embedding.embed_text(str(col_val_map["text"]))
        elif not raw_vec:
            raw_vec = [0.0] * dim
        return list(self.embedding.normalize(raw_vec))

    def _ensure_table_exists_for_insert(self, table_name: str) -> None:
        if (
            table_name not in self.tables
            and self.multi_storage is not None
            and not self.multi_storage.has_table(table_name)
        ):
            storage = self.multi_storage.create_table(
                table_name, dim=self.embedding.dim
            )
            self.tables[table_name] = TableCatalog(name=table_name, storage=storage)

    @staticmethod
    def _map_select_row_to_cols(
        r: Dict[str, Any], columns: List[str]
    ) -> Dict[str, Any]:
        mapped: Dict[str, Any] = {}
        vals = list(r.values())
        for idx, col in enumerate(columns):
            val = r.get(col) if col in r else (vals[idx] if idx < len(vals) else None)
            mapped[col] = val
        return mapped

    def _build_from_select(
        self, stmt: InsertStatement, role: str
    ) -> List[Dict[str, Any]]:
        if not isinstance(stmt.select_stmt, SelectStatement):
            return []
        sel_res = self._exec_select(stmt.select_stmt, role)
        raw_rows = sel_res.get("rows", [])
        if not stmt.columns:
            return [dict(r) for r in raw_rows]
        return [self._map_select_row_to_cols(r, stmt.columns) for r in raw_rows]

    def _build_insert_row_dicts(
        self, stmt: InsertStatement, role: str
    ) -> List[Dict[str, Any]]:
        if stmt.select_stmt is not None:
            return self._build_from_select(stmt, role)
        if stmt.rows_values:
            return [dict(zip(stmt.columns, row)) for row in stmt.rows_values]
        if stmt.values:
            return [dict(zip(stmt.columns, stmt.values))]
        return []

    @staticmethod
    def _is_conflict(
        meta: Dict[str, Any], row: Dict[str, Any], targets: List[str]
    ) -> bool:
        return all(
            str(meta.get(col)) == str(row.get(col)) for col in targets if col in row
        )

    def _find_conflict_index(
        self,
        metadata: List[Dict[str, Any]],
        row: Dict[str, Any],
        targets: List[str],
    ) -> Optional[int]:
        for idx, meta in enumerate(metadata):
            if self._is_conflict(meta, row, targets):
                return idx
        return None

    def _handle_conflict(
        self,
        table: TableCatalog,
        conflict_idx: int,
        row: Dict[str, Any],
        stmt: InsertStatement,
    ) -> Optional[Dict[str, Any]]:
        if stmt.upsert_action == "NOTHING":
            return None
        if stmt.upsert_action == "UPDATE":
            existing = table.storage.metadata[conflict_idx]
            update_values = stmt.upsert_update_set or row
            existing.update(update_values)
            return dict(existing)
        return None

    @staticmethod
    def _resolve_upsert_targets(
        upsert_target: Optional[List[str]], row: Dict[str, Any]
    ) -> List[str]:
        if upsert_target:
            return upsert_target
        return ["id"] if "id" in row else []

    def _try_upsert_conflict(
        self, table: TableCatalog, row: Dict[str, Any], stmt: InsertStatement
    ) -> Tuple[bool, Optional[Dict[str, Any]]]:
        if stmt.upsert_action is None:
            return False, None
        targets = self._resolve_upsert_targets(stmt.upsert_target, row)
        if not targets:
            return False, None
        conflict_idx = self._find_conflict_index(table.storage.metadata, row, targets)
        if conflict_idx is None:
            return False, None
        return True, self._handle_conflict(table, conflict_idx, row, stmt)

    def _insert_or_upsert_row(
        self, table: TableCatalog, row: Dict[str, Any], stmt: InsertStatement
    ) -> Optional[Dict[str, Any]]:
        is_conflict, conflict_res = self._try_upsert_conflict(table, row, stmt)
        if is_conflict:
            return conflict_res
        vector = self._resolve_insert_vector(row, table.storage.dim)
        if self.tx_manager.is_active:
            self.tx_manager.stage_mutation(
                "INSERT", {"table": stmt.table_name, "data": row}
            )
        else:
            idx = table.storage.append(vector, row)
            table.index.add_item(idx, vector)
        return dict(row)

    def _exec_insert(
        self, stmt: InsertStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "INSERT"
        )
        self._ensure_table_exists_for_insert(stmt.table_name)
        table = self._get_table(stmt.table_name)
        row_dicts = self._build_insert_row_dicts(stmt, effective_role)
        modified_records: List[Dict[str, Any]] = []
        for r in row_dicts:
            res_rec = self._insert_or_upsert_row(table, r, stmt)
            if res_rec is not None:
                modified_records.append(res_rec)
        ret_rows = _project_returning_rows(modified_records, stmt.returning_cols)
        first_id = str(modified_records[0].get("id", "")) if modified_records else ""
        res: Dict[str, Any] = {
            "command": "INSERT",
            "status": "ok",
            "table": stmt.table_name,
            "id": first_id,
            "inserted_count": len(modified_records),
        }
        if stmt.returning_cols is not None:
            res["rows"] = ret_rows
            res["count"] = len(ret_rows)
        return res

    def _sort_and_limit_indices(
        self,
        metadata: List[Dict[str, Any]],
        indices: List[int],
        order_by: Optional[str],
        order_desc: bool,
        limit: Optional[int],
    ) -> List[int]:
        if order_by:
            indices.sort(
                key=lambda i: self._sort_key(metadata[i], order_by),
                reverse=order_desc,
            )
        if limit is not None:
            return indices[:limit]
        return indices

    def _find_update_indices(
        self, table: TableCatalog, stmt: UpdateStatement
    ) -> List[int]:
        matching = [
            idx
            for idx, meta in enumerate(table.storage.metadata)
            if _matches_where_clause(meta, stmt.where_clauses)
        ]
        return self._sort_and_limit_indices(
            table.storage.metadata,
            matching,
            stmt.order_by,
            stmt.order_desc,
            stmt.limit,
        )

    def _exec_update(
        self, stmt: UpdateStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "UPDATE"
        )
        table = self._get_table(stmt.table_name)
        indices = self._find_update_indices(table, stmt)
        updated_records: List[Dict[str, Any]] = []
        for i in indices:
            meta = table.storage.metadata[i]
            meta.update(stmt.assignments)
            updated_records.append(dict(meta))

        if updated_records and not self.tx_manager.is_active:
            table.storage.write_all(
                table.storage.get_all_vectors(), table.storage.metadata
            )

        ret_rows = _project_returning_rows(updated_records, stmt.returning_cols)
        res: Dict[str, Any] = {
            "command": "UPDATE",
            "status": "ok",
            "updated_count": len(updated_records),
        }
        if stmt.returning_cols is not None:
            res["rows"] = ret_rows
            res["count"] = len(ret_rows)
        return res

    @staticmethod
    def _split_live_and_deleted(
        storage: Any, del_indices: set[int]
    ) -> Tuple[List[Tuple[float, ...]], List[Dict[str, Any]], List[Dict[str, Any]]]:
        new_vecs: List[Tuple[float, ...]] = []
        new_meta: List[Dict[str, Any]] = []
        deleted_records: List[Dict[str, Any]] = []
        for idx, meta in enumerate(storage.metadata):
            if idx in del_indices:
                deleted_records.append(dict(meta))
            else:
                new_vecs.append(storage.get_vector(idx))
                new_meta.append(meta)
        return new_vecs, new_meta, deleted_records

    def _find_delete_indices(
        self, table: TableCatalog, stmt: DeleteStatement
    ) -> set[int]:
        matching = [
            idx
            for idx, meta in enumerate(table.storage.metadata)
            if not stmt.where_clauses or _matches_where_clause(meta, stmt.where_clauses)
        ]
        limited = self._sort_and_limit_indices(
            table.storage.metadata,
            matching,
            stmt.order_by,
            stmt.order_desc,
            stmt.limit,
        )
        return set(limited)

    def _exec_delete(
        self, stmt: DeleteStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "DELETE"
        )
        table = self._get_table(stmt.table_name)
        del_indices = self._find_delete_indices(table, stmt)
        new_vecs, new_meta, deleted = self._split_live_and_deleted(
            table.storage, del_indices
        )

        if deleted and not self.tx_manager.is_active:
            table.storage.write_all(new_vecs, new_meta)
            table.index = HNSWIndex(dim=table.storage.dim)
            table.index.build_from_storage(new_vecs)

        ret_rows = _project_returning_rows(deleted, stmt.returning_cols)
        res: Dict[str, Any] = {
            "command": "DELETE",
            "status": "ok",
            "deleted_count": len(deleted),
        }
        if stmt.returning_cols is not None:
            res["rows"] = ret_rows
            res["count"] = len(ret_rows)
        return res

    def _exec_schema_table_stmt(
        self, stmt: SQLStatement, role: str
    ) -> Optional[Dict[str, Any]]:
        if isinstance(stmt, CreateTableStatement):
            return self._exec_create_table(stmt, role)
        if isinstance(stmt, DropTableStatement):
            return self._exec_drop_table(stmt, role)
        if isinstance(stmt, AlterTableStatement):
            return self._exec_alter_table(stmt, role)
        return None

    def _exec_schema_index_stmt(
        self, stmt: SQLStatement, role: str
    ) -> Optional[Dict[str, Any]]:
        if isinstance(stmt, CreateIndexStatement):
            return self._exec_create_index(stmt, role)
        if isinstance(stmt, DropIndexStatement):
            return self._exec_drop_index(stmt, role)
        if isinstance(stmt, ReindexStatement):
            return self._exec_reindex(stmt, role)
        return None

    def _exec_schema_view_stmt(
        self, stmt: SQLStatement, role: str
    ) -> Optional[Dict[str, Any]]:
        if isinstance(stmt, CreateViewStatement):
            return self._exec_create_view(stmt, role)
        if isinstance(stmt, DropViewStatement):
            return self._exec_drop_view(stmt, role)
        return None

    def _exec_schema_stmt(
        self, stmt: SQLStatement, role: str
    ) -> Optional[Dict[str, Any]]:
        return (
            self._exec_schema_table_stmt(stmt, role)
            or self._exec_schema_index_stmt(stmt, role)
            or self._exec_schema_view_stmt(stmt, role)
        )

    def _exec_security_or_schema(
        self, stmt: SQLStatement, role: str
    ) -> Optional[Dict[str, Any]]:
        if isinstance(stmt, ExplainStatement):
            return self._exec_explain(stmt, role)
        if isinstance(stmt, GrantStatement):
            return self._exec_grant(stmt, role)
        if isinstance(stmt, RevokeStatement):
            return self._exec_revoke(stmt, role)
        if isinstance(stmt, ShowStatement):
            return self._exec_show(stmt, role)
        return self._exec_schema_stmt(stmt, role)

    def _calculate_table_size(self, storage: Any) -> int:
        loc = getattr(storage, "file_path", "") or getattr(storage, "root_dir", "")
        if loc in (":memory:", "") or getattr(storage, "is_memory", False):
            return _calc_memory_storage_size(storage)
        return _calc_file_storage_size(loc)

    def _get_storage_row_count(self, storage: Any) -> int:
        if hasattr(storage, "count"):
            cnt = storage.count
            return int(cnt() if callable(cnt) else cnt)
        if hasattr(storage, "metadata"):
            return len(storage.metadata)
        if hasattr(storage, "__len__"):
            return len(storage)
        return 0

    def _build_show_table_row(
        self, tname: str, tbl: TableCatalog, target: str
    ) -> Dict[str, Any]:
        r_count = self._get_storage_row_count(tbl.storage)
        f_size = self._calculate_table_size(tbl.storage)
        if target == "TABLE_STATUS":
            return {
                "Name": tname,
                "Engine": tbl.storage_engine or "Pure Python Pager",
                "Rows": r_count,
                "Data_length": f_size,
                "Create_time": "2026-08-28 00:00:00",
            }
        return {"Table": tname, "Rows": r_count, "Size_bytes": f_size}

    def _resolve_from_database_rows(
        self, db_name: str, like_pat: Optional[str], target: str
    ) -> List[Dict[str, Any]]:
        scoped = _filter_tables_by_database_scope(self.tables, db_name, like_pat)
        if scoped:
            return [self._build_show_table_row(n, t, target) for n, t in scoped]
        ext = _query_external_db_tables(db_name, self.known_databases, target, like_pat)
        return ext if ext is not None else []

    def _resolve_default_table_rows(
        self, like_pat: Optional[str], target: str
    ) -> List[Dict[str, Any]]:
        return [
            self._build_show_table_row(tname, tbl, target)
            for tname, tbl in sorted(self.tables.items())
            if not (like_pat and like_pat not in tname)
        ]

    def _resolve_show_table_rows(
        self, stmt: ShowStatement, target: str
    ) -> List[Dict[str, Any]]:
        if stmt.from_database:
            return self._resolve_from_database_rows(
                stmt.from_database, stmt.like_pattern, target
            )
        return self._resolve_default_table_rows(stmt.like_pattern, target)

    def _exec_show_databases(self) -> Dict[str, Any]:
        dbs = (
            list(self.known_databases.keys())
            if self.known_databases
            else ["default_db", "main"]
        )
        db_rows = [{"Database": d} for d in dbs]
        return {
            "command": "SHOW",
            "status": "ok",
            "target": "DATABASES",
            "count": len(db_rows),
            "rows": db_rows,
        }

    def _exec_show(self, stmt: ShowStatement, effective_role: str) -> Dict[str, Any]:
        target = stmt.target.upper()
        if target in ("DATABASES", "SCHEMAS"):
            return self._exec_show_databases()

        table_rows = self._resolve_show_table_rows(stmt, target)
        return {
            "command": "SHOW",
            "status": "ok",
            "target": target,
            "count": len(table_rows),
            "rows": table_rows,
        }

    def _exec_dml_or_dql(self, stmt: SQLStatement, role: str) -> Dict[str, Any]:
        if isinstance(stmt, SelectStatement):
            return self._exec_select(stmt, role)
        if isinstance(stmt, InsertStatement):
            return self._exec_insert(stmt, role)
        if isinstance(stmt, UpdateStatement):
            return self._exec_update(stmt, role)
        if isinstance(stmt, DeleteStatement):
            return self._exec_delete(stmt, role)
        raise SQLExecutionError(f"Unhandled statement type: {stmt.command_type}")

    def execute_statement(
        self, stmt: SQLStatement, role: Optional[str] = None
    ) -> Dict[str, Any]:
        effective_role = role or self.access_controller.current_role
        cmd = stmt.command_type

        if cmd in (
            SQLCommandType.BEGIN,
            SQLCommandType.COMMIT,
            SQLCommandType.ROLLBACK,
        ):
            return self._exec_tcl(cmd)

        res = self._exec_security_or_schema(stmt, effective_role)
        if res is not None:
            return res

        return self._exec_dml_or_dql(stmt, effective_role)

    def _lookup_multi_storage_table(self, table_name: str) -> Optional[TableCatalog]:
        if self.multi_storage is None:
            return None
        if self.multi_storage.has_table(table_name):
            storage = self.multi_storage.get_table(table_name)
            self.tables[table_name] = TableCatalog(name=table_name, storage=storage)
            return self.tables[table_name]
        if self.default_table_name and table_name == self.default_table_name:
            storage = self.multi_storage.create_table(
                table_name, dim=self.embedding.dim
            )
            self.tables[table_name] = TableCatalog(name=table_name, storage=storage)
            return self.tables[table_name]
        return None

    def _get_table(self, table_name: str) -> TableCatalog:
        table = self.tables.get(table_name)
        if table:
            return table
        catalog = self._lookup_multi_storage_table(table_name)
        if catalog is not None:
            return catalog
        raise SQLExecutionError(f"Table '{table_name}' does not exist")
