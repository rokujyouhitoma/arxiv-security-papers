#!/usr/bin/env python3
"""
SQL Execution Engine for Pure Python Vector Database.
Evaluates DDL, DQL, DML, DCL, and TCL AST nodes against underlying vector storages and schemas.
"""

import collections
import copy
import fnmatch
import functools
import json
import logging
import math
import os
import re
from typing import Any, Callable, Dict, List, Optional, Sequence, Set, Tuple, Union

from ..btree import BPlusTree
from ..embedding import DeterministicEmbedding
from ..index import HNSWIndex
from ..planner import QueryPlanner, TableStats
from ..storage import MultiTableVectorStorage, VectorStorage
from .ast import (
    AlterTableAction,
    AlterTableStatement,
    AnalyzeStatement,
    AttachStatement,
    ColumnDef,
    CreateIndexStatement,
    CreateTableStatement,
    CreateTriggerStatement,
    CreateViewStatement,
    CreateVirtualTableStatement,
    DeleteStatement,
    DetachStatement,
    DropIndexStatement,
    DropTableStatement,
    DropTriggerStatement,
    DropViewStatement,
    ExplainStatement,
    ForeignKeyDef,
    GrantStatement,
    InsertStatement,
    JoinClause,
    JoinType,
    PragmaStatement,
    ReindexStatement,
    RevokeStatement,
    SavepointStatement,
    SelectStatement,
    ShowStatement,
    SQLCommandType,
    SQLStatement,
    TableRef,
    UpdateStatement,
    VacuumStatement,
)
from .functions import BUILTIN_FUNCTIONS
from .json_tree import iter_json_each, iter_json_tree
from .parser import SQLParser, _split_comma_expressions, parse_sql
from .security import AccessController
from .transaction import TransactionManager
from .window import compute_window_functions, extract_window_functions

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
    projected: Dict[str, Any] = {}
    for c in returning_cols:
        c_clean = c.strip()
        val = record.get(c_clean)
        if val is None and "." in c_clean:
            val = record.get(c_clean.split(".")[-1])
        out_col = c_clean.split(".")[-1] if "." in c_clean else c_clean
        projected[out_col] = val
    return projected


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
    cnt = 0
    if getattr(table, "index", None) is not None:
        vecs = table.storage.get_all_vectors()
        table.index = HNSWIndex(dim=table.storage.dim)
        table.index.build_from_storage(vecs)
        cnt += 1
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


class SQLIntegrityError(SQLExecutionError):
    """Raised when a relational constraint (UNIQUE, PRIMARY KEY, NOT NULL, CHECK, FK) is violated."""

    pass


class SQLOperationalError(SQLExecutionError):
    """Raised when an operational database error occurs (e.g. invalid transaction operation)."""

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

    @staticmethod
    def _is_vector_column(col: ColumnDef) -> bool:
        dt = (col.data_type or "").upper()
        return "VECTOR" in dt or "EMBEDDING" in dt

    @staticmethod
    def _resolve_table_index(
        storage: Any,
        index: Optional[HNSWIndex],
        columns: Optional[List[ColumnDef]],
    ) -> Optional[HNSWIndex]:
        if index is not None:
            return index
        if any(TableCatalog._is_vector_column(col) for col in (columns or [])):
            return HNSWIndex(dim=int(getattr(storage, "dim", 128)))
        return None

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
        strict: bool = False,
        generated_columns: Optional[Dict[str, ColumnDef]] = None,
        column_collations: Optional[Dict[str, str]] = None,
        foreign_keys: Optional[List[ForeignKeyDef]] = None,
        columns: Optional[List[ColumnDef]] = None,
    ) -> None:
        self.name = name
        self.storage = storage
        self.index = self._resolve_table_index(storage, index, columns)
        self.schema = schema if schema is not None else {}
        self.strict = strict
        self._init_catalog_columns(
            generated_columns, column_collations, foreign_keys, columns
        )
        self._init_catalog_metadata(raw_sql, storage_engine, location, database_scope)
        self.btree_indexes: Dict[str, BPlusTree] = {}
        self.btree_index_names: Dict[str, str] = {}
        self.index_definitions: List[Dict[str, str]] = []
        self.unique_val_sets: Dict[str, Set[str]] = {}
        self.stats: TableStats = TableStats(name)
        self.recompute_stats()

    def _init_catalog_columns(
        self,
        generated_columns: Optional[Dict[str, ColumnDef]],
        column_collations: Optional[Dict[str, str]],
        foreign_keys: Optional[List[ForeignKeyDef]],
        columns: Optional[List[ColumnDef]] = None,
    ) -> None:
        self.generated_columns = generated_columns or {}
        self.column_collations = column_collations or {}
        self.foreign_keys = foreign_keys or []
        self.columns: List[ColumnDef] = columns if columns is not None else []

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

    def get_unique_set(self, col_name: str) -> Set[str]:
        """Returns or builds cached set of unique column string values."""
        if col_name not in self.unique_val_sets:
            s: Set[str] = set()
            for m in getattr(self.storage, "metadata", []):
                val = m.get(col_name)
                if val is not None:
                    s.add(str(val))
            self.unique_val_sets[col_name] = s
        return self.unique_val_sets[col_name]

    def invalidate_unique_sets(self) -> None:
        """Invalidates unique constraint caches upon table mutation."""
        self.unique_val_sets.clear()

    def record_inserted_unique_values(self, row: Dict[str, Any]) -> None:
        """Updates active unique sets in O(1) after successful row insertion."""
        if not self.unique_val_sets:
            return
        for col_name, u_set in self.unique_val_sets.items():
            if col_name in row and row[col_name] is not None:
                u_set.add(str(row[col_name]))

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
    try:
        return int(expr)
    except ValueError:
        pass
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


def _eval_binary_arith_op(op: str, v1: float, v2: float) -> Optional[float]:
    ops: Dict[str, Callable[[float, float], Optional[float]]] = {
        "+": lambda a, b: a + b,
        "-": lambda a, b: a - b,
        "*": lambda a, b: a * b,
        "/": lambda a, b: a / b if b != 0 else None,
        "%": lambda a, b: math.fmod(a, b) if b != 0 else None,
    }
    fn = ops.get(op)
    return fn(v1, v2) if fn is not None else None


def _cast_arith_result(
    res: Optional[float], v1: Any, v2: Any, op: str
) -> Optional[Any]:
    if res is None:
        return None
    if isinstance(v1, int) and isinstance(v2, int) and op != "/":
        return int(res)
    return res


def _resolve_arith_operand(record: Dict[str, Any], r_str: str) -> Any:
    lit = _extract_literal(r_str)
    return lit if lit is not None else _extract_field_value(record, r_str)


def _safe_eval_arith(op: str, v1: Any, v2: Any) -> Optional[Any]:
    try:
        res = _eval_binary_arith_op(op, float(v1), float(v2))
        return _cast_arith_result(res, v1, v2, op)
    except (ValueError, TypeError):
        return None


def _extract_arithmetic(record: Dict[str, Any], expr: str) -> Optional[Any]:
    arith_m = re.match(
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s*([\+\-\*\/\%])\s*([a-zA-Z0-9_\.\->>\'\"0-9\.]+)$",
        expr.strip(),
    )
    if not arith_m:
        return None
    l_str, op, r_str = (
        arith_m.group(1).strip(),
        arith_m.group(2),
        arith_m.group(3).strip(),
    )
    v1 = _extract_field_value(record, l_str)
    v2 = _resolve_arith_operand(record, r_str)
    if None in (v1, v2):
        return None
    return _safe_eval_arith(op, v1, v2)


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
    # Normalize JSONPath: '$.key' or "$.key" → key; also plain 'key'
    key = path_part.strip().strip("'\"")
    # Strip leading $. or $ so that "$.user" becomes "user"
    if key.startswith("$."):
        key = key[2:]
    elif key.startswith("$"):
        key = key[1:]
    val = dict_obj.get(key)
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


def _lookup_dot_parts(record: Dict[str, Any], expr: str) -> Any:
    if "." not in expr:
        return None
    parts = expr.split(".")
    if parts[-1] in record:
        return record[parts[-1]]
    one_stripped = ".".join(parts[1:])
    return record.get(one_stripped)


def _lookup_record_col(record: Dict[str, Any], expr: str) -> Any:
    if expr in record:
        return record[expr]
    if any(c in expr for c in (" ", "*", "/", "+", "-")):
        return None
    return _lookup_dot_parts(record, expr)


def _dispatch_builtin_func(func_name: str, args: List[Any]) -> Any:
    try:
        return BUILTIN_FUNCTIONS[func_name](*args)
    except Exception:
        return None


def _extract_function_call(record: Dict[str, Any], expr: str) -> Any:
    """Evaluates built-in SQL function call if expression matches FUNC(...)."""
    m = re.match(r"^([a-zA-Z0-9_]+)\s*\((.*)\)$", expr, re.DOTALL)
    if not m or m.group(1).upper() not in BUILTIN_FUNCTIONS:
        return None
    raw_args = m.group(2).strip()
    args_strs = _split_comma_expressions(raw_args) if raw_args else []
    args = [_extract_field_value(record, a) for a in args_strs]
    return _dispatch_builtin_func(m.group(1).upper(), args)


def _eval_raw_condition_truth(record: Dict[str, Any], cond_str: str) -> bool:
    val = _extract_field_value(record, cond_str)
    return bool(val and val != 0 and val != "0" and val is not False)


def _eval_binary_condition(record: Dict[str, Any], m: Any) -> bool:
    op = re.sub(r"\s+", " ", m.group(2).strip().upper())
    act = _extract_field_value(record, m.group(1).strip())
    exp = _extract_field_value(record, m.group(3).strip()) if m.group(3) else None
    return _eval_comparison(op, act, exp)


def _eval_case_condition_match(
    record: Dict[str, Any], cond_str: str, base_val: Any = None
) -> bool:
    """Matches single condition in CASE WHEN branch."""
    cond_str = cond_str.strip()
    if base_val is not None:
        return str(base_val) == str(_extract_field_value(record, cond_str))
    m = re.match(
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s*(=|!=|<>|>=|<=|>|<|LIKE|NOT\s+LIKE|IS\s+NULL|IS\s+NOT\s+NULL)\s*(.*)$",
        cond_str,
        re.IGNORECASE,
    )
    if not m:
        return _eval_raw_condition_truth(record, cond_str)
    return _eval_binary_condition(record, m)


def _eval_when_branches(
    record: Dict[str, Any], rest_body: str, base_val: Any
) -> Tuple[bool, Any]:
    """Iterates through WHEN ... THEN branches."""
    branch_pat = re.compile(
        r"\bWHEN\b(.*?)\bTHEN\b(.*?)(?=\bWHEN\b|\bELSE\b|$)",
        re.IGNORECASE | re.DOTALL,
    )
    for m in branch_pat.finditer(rest_body):
        cond_str = m.group(1).strip()
        then_str = m.group(2).strip()
        if _eval_case_condition_match(record, cond_str, base_val):
            return True, _extract_field_value(record, then_str)
    return False, None


def _extract_case_else_val(record: Dict[str, Any], body: str) -> Any:
    else_m = re.search(r"\bELSE\b(.*)$", body, re.IGNORECASE | re.DOTALL)
    return _extract_field_value(record, else_m.group(1).strip()) if else_m else None


def _is_valid_case_syntax(expr: str) -> bool:
    return bool(
        re.match(r"^CASE\b", expr, re.IGNORECASE)
        and re.search(r"\bEND$", expr, re.IGNORECASE)
    )


def _extract_case_base_val(record: Dict[str, Any], body: str, when_start: int) -> Any:
    base_part = body[:when_start].strip()
    return _extract_field_value(record, base_part) if base_part else None


def _extract_case_when(record: Dict[str, Any], expr: str) -> Any:
    """Evaluates CASE [base] WHEN ... THEN ... [ELSE ...] END expression."""
    if not _is_valid_case_syntax(expr):
        return None
    body = expr[4:-3].strip()
    when_pos = re.search(r"\bWHEN\b", body, re.IGNORECASE)
    if not when_pos:
        return None
    base_val = _extract_case_base_val(record, body, when_pos.start())
    matched, res = _eval_when_branches(record, body[when_pos.start() :], base_val)
    return res if matched else _extract_case_else_val(record, body)


def _extract_comparison_expr(record: Dict[str, Any], expr: str) -> Optional[bool]:
    """Evaluates comparison expressions like 'score > 90' to boolean."""
    m = re.match(
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s*(=|!=|<>|>=|<=|>|<|LIKE|NOT\s+LIKE)\s+(.+)$",
        expr.strip(),
        re.IGNORECASE,
    )
    if not m:
        return None
    return _eval_case_condition_match(record, expr)


def _eval_core_expr_features(record: Dict[str, Any], expr: str) -> Any:
    case_res = _extract_case_when(record, expr)
    if case_res is not None:
        return case_res
    func_res = _extract_function_call(record, expr)
    if func_res is not None:
        return func_res
    return _extract_comparison_expr(record, expr)


def _extract_concat_expr(record: Dict[str, Any], expr: str) -> Optional[str]:
    if "||" not in expr:
        return None
    parts = expr.split("||")
    out: List[str] = []
    for p in parts:
        v = _extract_field_value(record, p.strip())
        if v is None:
            return None
        out.append(str(v))
    return "".join(out)


def _eval_extended_ops(record: Dict[str, Any], expr: str) -> Any:
    arith = _extract_arithmetic(record, expr)
    if arith is not None:
        return arith
    if "->" in expr:
        return _extract_json_op(record, expr)
    return None


def _extract_complex_expr(record: Dict[str, Any], expr: str) -> Any:
    """Evaluates CASE, function call, comparison, arithmetic, concat, or JSON operators."""
    concat_res = _extract_concat_expr(record, expr)
    if concat_res is not None:
        return concat_res
    core_res = _eval_core_expr_features(record, expr)
    if core_res is not None:
        return core_res
    return _eval_extended_ops(record, expr)


def _extract_direct_or_literal(record: Dict[str, Any], expr: str) -> Tuple[bool, Any]:
    if not expr:
        return True, None
    s = expr.strip()
    if s in record:
        return True, record[s]
    if s.upper() == "NULL":
        return True, None
    lit = _extract_literal(s)
    if lit is not None:
        return True, lit
    return False, s


def _extract_field_value(record: Dict[str, Any], expr: str) -> Any:
    """Extracts value from record supporting literals, functions, CASE, arithmetic, and JSON."""
    found, val = _extract_direct_or_literal(record, expr)
    if found:
        return val
    c_val = _extract_complex_expr(record, val)
    if c_val is not None:
        return c_val
    return _lookup_record_col(record, val)


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


def _eval_numeric_fast(op: str, actual: Any, expected: Any) -> Optional[bool]:
    if isinstance(actual, (int, float)) and isinstance(expected, (int, float)):
        if not isinstance(actual, bool) and not isinstance(expected, bool):
            return _eval_numeric_rel(op, float(actual), float(expected))
    return None


def _eval_relational_fallback(op: str, actual: Any, expected: Any) -> bool:
    try:
        return _eval_numeric_rel(op, float(str(actual)), float(str(expected)))
    except (ValueError, TypeError):
        return _eval_string_rel(op, str(actual), str(expected))


def _eval_relational(op: str, actual: Any, expected: Any) -> bool:
    num_res = _eval_numeric_fast(op, actual, expected)
    if num_res is not None:
        return num_res
    if isinstance(actual, str) and isinstance(expected, str):
        return _eval_string_rel(op, actual, expected)
    return _eval_relational_fallback(op, actual, expected)


def _collate_transform(val: Any, collation: Optional[str]) -> Any:
    """Applies collation transformation to string values."""
    if not isinstance(val, str) or not collation:
        return val
    col = collation.upper()
    if col == "NOCASE":
        return val.lower()
    if col == "RTRIM":
        return val.rstrip(" ")
    return val


def _eval_is_null(op: str, actual: Any) -> bool:
    is_n = actual is None or actual == ""
    return is_n if op == "IS NULL" else not is_n


def _eval_between(
    op: str, actual: Any, expected: Any, collate: Optional[str] = None
) -> bool:
    if not isinstance(expected, (list, tuple)) or len(expected) != 2:
        return False
    v1, v2 = expected
    try:
        act_f, v1_f, v2_f = float(str(actual)), float(str(v1)), float(str(v2))
        res = v1_f <= act_f <= v2_f
    except (ValueError, TypeError):
        act_s = str(_collate_transform(actual, collate))
        v1_s = str(_collate_transform(v1, collate))
        v2_s = str(_collate_transform(v2, collate))
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


def _normalize_in_list(expected: Any, collate: Optional[str]) -> List[Any]:
    in_list = expected if isinstance(expected, (list, tuple, set)) else [expected]
    return [_collate_transform(x, collate) for x in in_list]


def _check_membership_raw(norm_actual: Any, norm_list: List[Any]) -> bool:
    if norm_actual in norm_list:
        return True
    return str(norm_actual) in [str(x) for x in norm_list]


def _eval_membership(
    op: str, actual: Any, expected: Any, collate: Optional[str] = None
) -> bool:
    norm_actual = _collate_transform(actual, collate)
    norm_list = _normalize_in_list(expected, collate)
    is_member = _check_membership_raw(norm_actual, norm_list)
    return is_member if op == "IN" else not is_member


def _eval_null_or_between(
    op: str, actual: Any, expected: Any, collate: Optional[str] = None
) -> Optional[bool]:
    if op in ("IS NULL", "IS NOT NULL"):
        return _eval_is_null(op, actual)
    if op in ("BETWEEN", "NOT BETWEEN"):
        return _eval_between(op, actual, expected, collate)
    return None


def _eval_pattern_match(
    op: str, actual: Any, expected: Any, c_dict: Optional[Dict[str, Any]] = None
) -> Optional[bool]:
    if op in ("GLOB", "NOT GLOB"):
        return _eval_glob(op, actual, expected)
    if op in ("LIKE", "NOT LIKE"):
        return _eval_like(op, actual, expected, (c_dict or {}).get("escape"))
    return None


def _eval_pattern_or_null(
    op: str, actual: Any, expected: Any, c_dict: Optional[Dict[str, Any]] = None
) -> Optional[bool]:
    collate = (c_dict or {}).get("collate")
    res = _eval_null_or_between(op, actual, expected, collate)
    return res if res is not None else _eval_pattern_match(op, actual, expected, c_dict)


def _eval_comparison_branches(
    op: str, actual: Any, expected: Any, c_dict: Optional[Dict[str, Any]] = None
) -> bool:
    pat_res = _eval_pattern_or_null(op, actual, expected, c_dict)
    if pat_res is not None:
        return pat_res
    if op in (">=", "<=", ">", "<"):
        return _eval_relational(op, actual, expected)
    collate = (c_dict or {}).get("collate")
    if op in ("IN", "NOT IN"):
        return _eval_membership(op, actual, expected, collate)
    return True


def _eval_equality(op: str, norm_actual: Any, norm_expected: Any) -> Optional[bool]:
    if op == "=":
        return str(norm_actual) == str(norm_expected)
    if op in ("!=", "<>"):
        return str(norm_actual) != str(norm_expected)
    return None


def _eval_comparison(
    op: str, actual: Any, expected: Any, c_dict: Optional[Dict[str, Any]] = None
) -> bool:
    if op in ("IS NULL", "IS NOT NULL"):
        return _eval_is_null(op, actual)
    collate = (c_dict or {}).get("collate")
    norm_act = _collate_transform(actual, collate)
    norm_exp = _collate_transform(expected, collate)
    eq_res = _eval_equality(op, norm_act, norm_exp)
    if eq_res is not None:
        return eq_res
    if actual is None:
        return False
    return _eval_comparison_branches(op, norm_act, norm_exp, c_dict)


def _inject_collate_into_dict(d: Dict[str, Any], collations: Dict[str, str]) -> None:
    col = d.get("column")
    if "collate" not in d and col and col in collations:
        d["collate"] = collations[col]


def _enrich_where_clause_item(
    c: Dict[str, Any], collations: Dict[str, str]
) -> Dict[str, Any]:
    new_c = dict(c)
    _inject_collate_into_dict(new_c, collations)
    if "clauses" in new_c:
        new_c["clauses"] = [
            _enrich_where_clause_item(sub, collations) for sub in new_c["clauses"]
        ]
    return new_c


def _enrich_where_clauses_with_collations(
    clauses: List[Dict[str, Any]], collations: Dict[str, str]
) -> List[Dict[str, Any]]:
    if not collations or not clauses:
        return clauses
    return [_enrich_where_clause_item(c, collations) for c in clauses]


def _is_column_reference(expected_val: str, record: Dict[str, Any]) -> bool:
    return expected_val in record or "." in expected_val or "->" in expected_val


def _resolve_condition_expected_val(record: Dict[str, Any], expected_val: Any) -> Any:
    """Resolves column reference in expected value if present."""
    if isinstance(expected_val, str) and _is_column_reference(expected_val, record):
        col_val = _extract_field_value(record, expected_val)
        if col_val is not None:
            return col_val
    return expected_val


def _substitute_correlated_vars(sql: str, record: Dict[str, Any]) -> str:
    for k, v in record.items():
        if "." in k:
            sql = re.sub(
                rf"\b{re.escape(k)}\b",
                f"'{v}'" if isinstance(v, str) else str(v),
                sql,
            )
    return sql


def _val_in_inner_rows(actual: Any, inner_rows: List[Dict[str, Any]]) -> bool:
    flat_vals = [v for r in inner_rows for v in r.values()]
    if actual in flat_vals:
        return True
    str_actual = str(actual)
    return any(str(x) == str_actual for x in flat_vals)


def _eval_subquery_membership(
    actual: Any, inner_rows: List[Dict[str, Any]], op: str
) -> bool:
    is_in = _val_in_inner_rows(actual, inner_rows)
    return is_in if op == "IN" else not is_in


def _eval_exists_op(op: str, inner_rows: List[Dict[str, Any]]) -> bool:
    has_rows = len(inner_rows) > 0
    return has_rows if op == "EXISTS" else not has_rows


def _exec_subquery(
    executor: Any, subquery_sql: str, record: Dict[str, Any], role: str
) -> List[Dict[str, Any]]:
    sub_sql = _substitute_correlated_vars(subquery_sql, record)
    res = executor.execute(sub_sql, role=role)
    return list(res.get("rows", []))


def _eval_subquery_predicate(
    record: Dict[str, Any],
    c: Dict[str, Any],
    executor: Any,
    role: str,
    temp_tables: Any,
) -> bool:
    subquery_sql = str(c.get("subquery") or "")
    if not executor or not subquery_sql:
        return False
    op = _get_cond_op(c).upper()
    inner_rows = _exec_subquery(executor, subquery_sql, record, role)
    if "EXISTS" in op:
        return _eval_exists_op(op, inner_rows)
    actual = _extract_field_value(record, _get_cond_field(c))
    return _eval_subquery_membership(actual, inner_rows, op)


def _get_cond_field(c: Dict[str, Any]) -> str:
    return str(c.get("field") or c.get("column") or "")


def _get_cond_op(c: Dict[str, Any]) -> str:
    return str(c.get("op") or c.get("operator") or "=")


def _collect_match_target_texts(record: Dict[str, Any], field: str) -> List[str]:
    actual = _extract_field_value(record, field)
    if actual is not None:
        return [str(actual)]
    return [
        str(v)
        for k, v in record.items()
        if not k.startswith("_") and isinstance(v, (str, int, float))
    ]


def _match_single_term(q_tok: str, target_words: Set[str]) -> bool:
    if q_tok.endswith("*"):
        prefix = q_tok[:-1]
        return any(w.startswith(prefix) for w in target_words)
    return q_tok in target_words


def _check_terms_match(q_tokens: List[str], target_words: Set[str]) -> bool:
    return all(_match_single_term(tok, target_words) for tok in q_tokens)


def _get_storage_bm25(
    record: Dict[str, Any], field: str, query: str, executor: Any
) -> Optional[float]:
    idx = record.get("_idx")
    tables = getattr(executor, "tables", None)
    if idx is None or not tables:
        return None
    table_cat = tables.get(field)
    storage = getattr(table_cat, "storage", None)
    bm25_fn = getattr(storage, "bm25", None)
    if callable(bm25_fn):
        return float(bm25_fn(int(idx), query))
    return None


def _calc_token_freq_score(tok: str, texts: List[str]) -> float:
    clean_tok = tok[:-1] if tok.endswith("*") else tok
    tf = sum(len(re.findall(rf"\b{re.escape(clean_tok)}", t.lower())) for t in texts)
    return tf * 1.5 / (tf + 0.5)


def _calc_bm25_from_storage_or_freq(
    record: Dict[str, Any], field: str, query: str, executor: Any
) -> float:
    s_score = _get_storage_bm25(record, field, query, executor)
    if s_score is not None:
        return s_score
    q_tokens = [t for t in re.findall(r"\b\w+\*?", query.lower()) if t]
    texts = _collect_match_target_texts(record, field)
    score = sum(_calc_token_freq_score(tok, texts) for tok in q_tokens)
    return round(max(0.1, score), 4)


def _extract_target_words(target_texts: List[str]) -> Set[str]:
    words: Set[str] = set()
    for t in target_texts:
        words.update(re.findall(r"\b\w+\b", t.lower()))
    return words


def _eval_match_predicate(
    record: Dict[str, Any], field: str, query: str, executor: Any = None
) -> bool:
    q_tokens = [t for t in re.findall(r"\b\w+\*?", query.lower()) if t]
    if not q_tokens:
        return False
    target_texts = _collect_match_target_texts(record, field)
    all_words = _extract_target_words(target_texts)
    if not _check_terms_match(q_tokens, all_words):
        return False
    score = _calc_bm25_from_storage_or_freq(record, field, query, executor)
    record["rank"] = -score
    record["score"] = score
    record[f"bm25({field})"] = score
    return True


def _evaluate_single_condition(
    record: Dict[str, Any],
    c: Dict[str, Any],
    executor: Any = None,
    role: str = "admin",
    temp_tables: Any = None,
) -> bool:
    if "subquery" in c:
        return _eval_subquery_predicate(record, c, executor, role, temp_tables)
    field = _get_cond_field(c)
    op = _get_cond_op(c)
    expected_val = _resolve_condition_expected_val(record, c.get("value"))
    if op == "MATCH":
        return _eval_match_predicate(record, field, str(expected_val), executor)
    actual = _extract_field_value(record, field)
    return _eval_comparison(op, actual, expected_val, c)


def _matches_or_branches(
    record: Dict[str, Any],
    branches: List[Dict[str, Any]],
    executor: Any = None,
    role: str = "admin",
    temp_tables: Any = None,
) -> bool:
    for branch in branches:
        sub_clauses = branch.get("clauses", [])
        if all(
            _evaluate_single_condition(record, c, executor, role, temp_tables)
            for c in sub_clauses
        ):
            return True
    return False


def _matches_where_clause(
    record: Dict[str, Any],
    clauses: List[Dict[str, Any]],
    executor: Any = None,
    role: str = "admin",
    temp_tables: Any = None,
) -> bool:
    if not clauses:
        return True
    if any(c.get("logic") == "OR_BRANCH" for c in clauses):
        return _matches_or_branches(record, clauses, executor, role, temp_tables)
    return all(
        _evaluate_single_condition(record, c, executor, role, temp_tables)
        for c in clauses
    )


def _check_strict_int(table_name: str, col: str, dt: str, val: Any) -> None:
    if isinstance(val, bool) or not isinstance(val, int):
        raise SQLExecutionError(
            f"cannot store {type(val).__name__} in {dt} column {col} in STRICT table {table_name}"
        )


def _check_strict_real(table_name: str, col: str, val: Any) -> None:
    if isinstance(val, bool) or not isinstance(val, (int, float)):
        raise SQLExecutionError(
            f"cannot store {type(val).__name__} in REAL column {col} in STRICT table {table_name}"
        )


def _check_strict_text(table_name: str, col: str, val: Any) -> None:
    if not isinstance(val, str):
        raise SQLExecutionError(
            f"cannot store {type(val).__name__} in TEXT column {col} in STRICT table {table_name}"
        )


def _check_strict_blob(table_name: str, col: str, val: Any) -> None:
    if not isinstance(val, (bytes, bytearray)):
        raise SQLExecutionError(
            f"cannot store {type(val).__name__} in BLOB column {col} in STRICT table {table_name}"
        )


def _check_strict_type(table_name: str, col: str, dt: str, val: Any) -> None:
    if dt in ("INT", "INTEGER"):
        _check_strict_int(table_name, col, dt, val)
    elif dt == "REAL":
        _check_strict_real(table_name, col, val)
    elif dt == "TEXT":
        _check_strict_text(table_name, col, val)
    elif dt == "BLOB":
        _check_strict_blob(table_name, col, val)


def _validate_strict_row(
    table_name: str,
    schema: Dict[str, Any],
    row: Dict[str, Any],
) -> None:
    for col, val in row.items():
        if val is None:
            continue
        dt = str(schema.get(col, "ANY")).strip().upper()
        _check_strict_type(table_name, col, dt, val)


def _check_strict_table_rows(
    table: TableCatalog, table_name: str, rows: List[Dict[str, Any]]
) -> None:
    if not table.strict:
        return
    for r in rows:
        _validate_strict_row(table_name, table.schema, r)


def _check_generated_column_writes(
    table: TableCatalog, write_cols: Sequence[str]
) -> None:
    if not table.generated_columns:
        return
    for c in write_cols:
        if c in table.generated_columns:
            raise SQLExecutionError(
                f"cannot write to generated column '{c}' in table '{table.name}'"
            )


def _compute_generated_columns(table: TableCatalog, row: Dict[str, Any]) -> None:
    if not table.generated_columns:
        return
    for col_name, col_def in table.generated_columns.items():
        if col_def.generated_expr is not None:
            row[col_name] = _extract_field_value(row, col_def.generated_expr)


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
        from core.settings import get_table_scope_from_settings

        return get_table_scope_from_settings(tname)
    except Exception:
        return "default"


def _matches_scope_and_pattern(
    tbl: Any, tname: str, db_name: str, pattern: Optional[str]
) -> bool:
    if pattern and pattern not in tname:
        return False
    return db_name == "all" or _resolve_table_scope(tbl, tname) == db_name


def _filter_tables_by_database_scope(
    tables: Dict[str, Any], db_name: str, pattern: Optional[str]
) -> List[Tuple[str, Any]]:
    return [
        (tname, tbl)
        for tname, tbl in sorted(tables.items())
        if _matches_scope_and_pattern(tbl, tname, db_name, pattern)
    ]


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


def _parse_group_concat_args(norm: str) -> Tuple[str, str]:
    inner = norm[norm.find("(") + 1 : norm.rfind(")")].strip()
    parts = [p.strip() for p in _split_comma_expressions(inner)]
    col = parts[0] if parts else ""
    sep = parts[1].strip("'\"") if len(parts) > 1 else ","
    return col, sep


def _compute_agg_group_concat(
    upper: str, norm: str, group_rows: List[Dict[str, Any]]
) -> Optional[Any]:
    if not (
        _is_valid_agg_call(upper, "GROUP_CONCAT(")
        or _is_valid_agg_call(upper, "STRING_AGG(")
    ):
        return None
    col, sep = _parse_group_concat_args(norm)
    values = [
        str(v) for r in group_rows if (v := _extract_field_value(r, col)) is not None
    ]
    return sep.join(values)


def _compute_agg_func(
    upper: str, norm: str, group_rows: List[Dict[str, Any]]
) -> Optional[Any]:
    c_val = _compute_agg_count_sum_avg(upper, norm, group_rows)
    if c_val is not None:
        return c_val
    m_val = _compute_agg_min_max(upper, norm, group_rows)
    if m_val is not None:
        return m_val
    return _compute_agg_group_concat(upper, norm, group_rows)


def _strip_as_alias(col_expr: str) -> str:
    as_m = re.search(r"\s+AS\s+([a-zA-Z0-9_]+)$", col_expr, re.IGNORECASE)
    return col_expr[: as_m.start()].strip() if as_m else col_expr.strip()


def _is_window_expression(norm: str) -> bool:
    return " OVER (" in norm or " OVER(" in norm


def _is_aggregate_expression(col_expr: str) -> bool:
    norm = _strip_as_alias(col_expr).upper()
    if _is_window_expression(norm):
        return False
    return any(
        norm.startswith(fn)
        for fn in (
            "COUNT(",
            "SUM(",
            "AVG(",
            "MIN(",
            "MAX(",
            "GROUP_CONCAT(",
            "STRING_AGG(",
        )
    )


def _has_aggregate_columns(stmt: SelectStatement) -> bool:
    return any(_is_aggregate_expression(c) for c in stmt.columns)


def _compute_agg_col(col_expr: str, group_rows: List[Dict[str, Any]]) -> Any:
    norm = _strip_as_alias(col_expr)
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


def _populate_agg_row(
    target_cols: List[str], g_rows: List[Dict[str, Any]]
) -> Dict[str, Any]:
    row_dict: Dict[str, Any] = {}
    for col_expr in target_cols:
        val = _compute_agg_col(col_expr, g_rows)
        raw_col = _strip_as_alias(col_expr)
        row_dict[col_expr] = val
        row_dict[raw_col] = val
    return row_dict


def _group_and_aggregate_rows(
    rows: List[Dict[str, Any]], stmt: SelectStatement
) -> List[Dict[str, Any]]:
    target_cols = _extract_target_columns(stmt)
    if not stmt.group_by:
        return [_populate_agg_row(target_cols, rows)]

    groups = _cluster_rows(rows, stmt.group_by)
    result: List[Dict[str, Any]] = []
    for _gkey, g_rows in groups.items():
        result.append(_populate_agg_row(target_cols, g_rows))
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


def _bind_list_val(val: List[Any], param_iter: Any) -> List[Any]:
    out = []
    for v in val:
        out.append(next(param_iter) if v == "?" else v)
    return out


def _bind_single_val(val: Any, param_iter: Any) -> Any:
    if val == "?":
        return next(param_iter)
    if isinstance(val, list):
        return _bind_list_val(val, param_iter)
    return val


def _bind_single_clause(c: Dict[str, Any], param_iter: Any) -> Dict[str, Any]:
    if c.get("logic") == "OR_BRANCH":
        sub_clauses = c.get("clauses", [])
        bound_sub = [_bind_single_clause(sub_c, param_iter) for sub_c in sub_clauses]
        return {**c, "clauses": bound_sub}
    return {**c, "value": _bind_single_val(c.get("value"), param_iter)}


def _bind_insert_rows(
    stmt: InsertStatement, param_iter: Any, sc: InsertStatement
) -> None:
    sc.rows_values = [
        [next(param_iter) if v == "?" else v for v in row] for row in stmt.rows_values
    ]
    if stmt.values:
        sc.values = list(sc.rows_values[0])


def _bind_insert_values(
    stmt: InsertStatement, param_iter: Any, sc: InsertStatement
) -> None:
    sc.values = [next(param_iter) if v == "?" else v for v in stmt.values]
    if stmt.rows_values:
        sc.rows_values = [list(sc.values)]


def _bind_insert_stmt(stmt: InsertStatement, param_iter: Any) -> InsertStatement:
    sc = copy.copy(stmt)
    if stmt.rows_values:
        _bind_insert_rows(stmt, param_iter, sc)
    elif stmt.values:
        _bind_insert_values(stmt, param_iter, sc)
    return sc


def _bind_int_placeholder(val: Any, param_iter: Any) -> Optional[int]:
    if val == "?":
        return int(next(param_iter))
    return int(val) if isinstance(val, int) else None


def _bind_select_stmt(stmt: SelectStatement, param_iter: Any) -> SelectStatement:
    sc = copy.copy(stmt)
    if stmt.where_clauses:
        sc.where_clauses = [
            _bind_single_clause(c, param_iter) for c in stmt.where_clauses
        ]
    sc.limit = _bind_int_placeholder(getattr(sc, "limit", None), param_iter)
    sc.offset = _bind_int_placeholder(getattr(sc, "offset", None), param_iter)
    return sc


def _bind_assignments(assignments: Dict[str, Any], param_iter: Any) -> Dict[str, Any]:
    return {k: (next(param_iter) if v == "?" else v) for k, v in assignments.items()}


def _bind_update_stmt(stmt: UpdateStatement, param_iter: Any) -> UpdateStatement:
    sc = copy.copy(stmt)
    if stmt.assignments:
        sc.assignments = _bind_assignments(stmt.assignments, param_iter)
    if stmt.where_clauses:
        sc.where_clauses = [
            _bind_single_clause(c, param_iter) for c in stmt.where_clauses
        ]
    sc.limit = _bind_int_placeholder(getattr(sc, "limit", None), param_iter)
    return sc


def _bind_delete_stmt(stmt: DeleteStatement, param_iter: Any) -> DeleteStatement:
    sc = copy.copy(stmt)
    if stmt.where_clauses:
        sc.where_clauses = [
            _bind_single_clause(c, param_iter) for c in stmt.where_clauses
        ]
    sc.limit = _bind_int_placeholder(getattr(sc, "limit", None), param_iter)
    return sc


def _bind_statement_params(stmt: SQLStatement, params: Sequence[Any]) -> SQLStatement:
    param_iter = iter(params)
    if isinstance(stmt, InsertStatement):
        return _bind_insert_stmt(stmt, param_iter)
    if isinstance(stmt, SelectStatement):
        return _bind_select_stmt(stmt, param_iter)
    if isinstance(stmt, UpdateStatement):
        return _bind_update_stmt(stmt, param_iter)
    if isinstance(stmt, DeleteStatement):
        return _bind_delete_stmt(stmt, param_iter)
    return stmt


def _format_fallback_sequence(p: Any) -> Optional[str]:
    if isinstance(p, (list, tuple)):
        return str(list(p))
    return None


def _format_fallback_primitive(p: Any) -> Optional[str]:
    if p is None:
        return "NULL"
    if isinstance(p, bool):
        return "TRUE" if p else "FALSE"
    if isinstance(p, (int, float)):
        return str(p)
    return None


def _format_fallback_param(p: Any) -> str:
    prim = _format_fallback_primitive(p)
    if prim is not None:
        return prim
    seq = _format_fallback_sequence(p)
    if seq is not None:
        return seq
    if isinstance(p, dict):
        return f"'{json.dumps(p, ensure_ascii=False)}'"
    escaped = str(p).replace("'", "''")
    return f"'{escaped}'"


def _bind_params_fallback(sql: str, params: Optional[Sequence[Any]]) -> str:
    if not params:
        return sql
    query = sql
    for p in params:
        query = query.replace("?", _format_fallback_param(p), 1)
    return query


def _is_right_tbl_qualifier(expr: str, right_tbl_name: str) -> bool:
    if not isinstance(expr, str):
        return False
    return expr.lower().startswith(f"{right_tbl_name.lower()}.")


def _resolve_equi_key_by_prefix(
    col: str, val: str, right_name: str
) -> Optional[Tuple[str, str]]:
    if _is_right_tbl_qualifier(val, right_name) and not _is_right_tbl_qualifier(
        col, right_name
    ):
        return col, val
    if _is_right_tbl_qualifier(col, right_name) and not _is_right_tbl_qualifier(
        val, right_name
    ):
        return val, col
    return None


def _has_field_or_col(rec: Dict[str, Any], f: str) -> bool:
    return f in rec or _lookup_record_col(rec, f) is not None


def _resolve_equi_key_by_lookup(
    col: str, val: str, s_left: Dict[str, Any], s_right: Dict[str, Any]
) -> Optional[Tuple[str, str]]:
    if _has_field_or_col(s_left, col) and _has_field_or_col(s_right, val):
        return col, val
    if _has_field_or_col(s_left, val) and _has_field_or_col(s_right, col):
        return val, col
    return None


def _resolve_equi_key_pair(
    col: str,
    val: Any,
    right_name: str,
    s_left: Dict[str, Any],
    s_right: Dict[str, Any],
) -> Optional[Tuple[str, str]]:
    if not isinstance(col, str) or not isinstance(val, str):
        return None
    p_res = _resolve_equi_key_by_prefix(col, val, right_name)
    if p_res is not None:
        return p_res
    return _resolve_equi_key_by_lookup(col, val, s_left, s_right)


def _check_single_equi_cond(
    c: Dict[str, Any],
    right_name: str,
    s_left: Dict[str, Any],
    s_right: Dict[str, Any],
) -> Optional[Tuple[str, str]]:
    if _get_cond_op(c) != "=":
        return None
    return _resolve_equi_key_pair(
        _get_cond_field(c), c.get("value"), right_name, s_left, s_right
    )


def _has_or_branch(conditions: List[Dict[str, Any]]) -> bool:
    for c in conditions:
        if c.get("logic") == "OR_BRANCH":
            return True
    return False


def _filter_remaining_conds(
    conditions: List[Dict[str, Any]], skip_idx: int
) -> List[Dict[str, Any]]:
    out = []
    for i, cond in enumerate(conditions):
        if i != skip_idx:
            out.append(cond)
    return out


def _find_equi_join_keys(
    conditions: List[Dict[str, Any]],
    right_name: str,
    s_left: Dict[str, Any],
    s_right: Dict[str, Any],
) -> Optional[Tuple[str, str, List[Dict[str, Any]]]]:
    if _has_or_branch(conditions):
        return None
    for idx, c in enumerate(conditions):
        pair = _check_single_equi_cond(c, right_name, s_left, s_right)
        if pair is not None:
            rem = _filter_remaining_conds(conditions, idx)
            return pair[0], pair[1], rem
    return None


def _build_hash_bucket(
    rows: List[Dict[str, Any]], key_expr: str
) -> Dict[str, List[Dict[str, Any]]]:
    bucket: Dict[str, List[Dict[str, Any]]] = collections.defaultdict(list)
    for r in rows:
        v = _extract_field_value(r, key_expr)
        if v is not None:
            bucket[str(v)].append(r)
    return bucket


def _probe_hash_bucket_row(
    left_row: Dict[str, Any],
    candidates: List[Dict[str, Any]],
    rem_conds: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    row_matches: List[Dict[str, Any]] = []
    for right_row in candidates:
        combined = CombinedRow(left_row, right_row)
        if not rem_conds or _matches_where_clause(combined, rem_conds):
            row_matches.append(combined)
    return row_matches


def _is_hash_joinable(
    join: Any,
    current_rows: List[Dict[str, Any]],
    j_prefixed_rows: List[Dict[str, Any]],
) -> bool:
    if join.join_type not in (JoinType.INNER, JoinType.LEFT):
        return False
    return bool(current_rows and j_prefixed_rows and join.on_conditions)


def _pop_storage_metadata(storage: Any, idx: Optional[int]) -> None:
    if not hasattr(storage, "metadata") or not storage.metadata:
        return
    if idx is not None and idx < len(storage.metadata):
        storage.metadata.pop(idx)
    else:
        storage.metadata.pop()


def _pop_memory_vectors(storage: Any, idx: Optional[int]) -> None:
    if not hasattr(storage, "_memory_vectors") or not storage._memory_vectors:
        return
    if idx is not None and idx < len(storage._memory_vectors):
        storage._memory_vectors.pop(idx)
    else:
        storage._memory_vectors.pop()


def _pop_storage_id_mapping(storage: Any, row: Any) -> None:
    if isinstance(row, dict) and "id" in row and hasattr(storage, "id_to_idx"):
        storage.id_to_idx.pop(str(row["id"]), None)


def _undo_single_insert(table: TableCatalog, payload: Dict[str, Any]) -> None:
    idx = payload.get("idx")
    st = table.storage
    _pop_storage_metadata(st, idx)
    _pop_memory_vectors(st, idx)
    if hasattr(st, "count") and st.count > 0:
        st.count -= 1
    _pop_storage_id_mapping(st, payload.get("row"))
    table.invalidate_unique_sets()


def _undo_single_update(table: TableCatalog, payload: Dict[str, Any]) -> None:
    idx = payload.get("idx")
    old_row = payload.get("old_row")
    if (
        idx is not None
        and old_row is not None
        and hasattr(table.storage, "metadata")
        and idx < len(table.storage.metadata)
    ):
        table.storage.metadata[idx].clear()
        table.storage.metadata[idx].update(old_row)
        table.invalidate_unique_sets()


def _undo_single_delete(table: TableCatalog, payload: Dict[str, Any]) -> None:
    all_meta = payload.get("all_meta")
    all_vecs = payload.get("all_vecs")
    if all_meta is not None and all_vecs is not None:
        table.storage.write_all(all_vecs, all_meta)
        table.invalidate_unique_sets()
        if table.index is not None:
            table.index = HNSWIndex(dim=table.storage.dim)
            table.index.build_from_storage(all_vecs)


def _dispatch_single_undo(tables: Dict[str, TableCatalog], act: Any) -> None:
    tname = getattr(act, "table_name", "")
    table = tables.get(tname)
    if not table:
        return
    act_type = getattr(act, "action_type", "")
    payload = getattr(act, "payload", {})
    if act_type == "INSERT":
        _undo_single_insert(table, payload)
    elif act_type == "UPDATE":
        _undo_single_update(table, payload)
    elif act_type == "DELETE":
        _undo_single_delete(table, payload)


def _apply_undo_actions(
    tables: Dict[str, TableCatalog], undo_actions: List[Any]
) -> int:
    for act in reversed(undo_actions):
        _dispatch_single_undo(tables, act)
    return len(undo_actions)


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
        self.attached_databases: Dict[str, Dict[str, Any]] = {}
        self.tables: Dict[str, TableCatalog] = {}
        self.views: Dict[str, CreateViewStatement] = {}
        self.triggers: Dict[str, CreateTriggerStatement] = {}
        self.foreign_keys_enabled: bool = True
        self.user_version: int = 0
        self.collations: Dict[str, Callable[[str, str], int]] = {}
        self._init_default_tables(
            catalog,
            default_storage,
            default_index,
            default_table_name=default_table_name,
        )
        if self.multi_storage is not None:
            self.multi_storage.attach_to_executor(self)

    def create_collation(
        self,
        name: str,
        callback: Optional[Callable[[str, str], int]],
    ) -> None:
        """Registers or removes a user-defined collation function."""
        clean_name = name.strip().upper()
        if callback is None:
            self.collations.pop(clean_name, None)
        else:
            self.collations[clean_name] = callback

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

    def _resolve_exec_params(
        self, params: Optional[Union[Sequence[Any], Dict[str, Any]]]
    ) -> Optional[Sequence[Any]]:
        if not params:
            return None
        if isinstance(params, dict):
            p = params.get("params") or params.get("query_params")
            return p if isinstance(p, Sequence) else None
        return params

    def _parse_and_bind_stmt(
        self, sql: str, params: Optional[Sequence[Any]]
    ) -> SQLStatement:
        if not params:
            return parse_sql(sql)
        if "KNN(" in sql.upper():
            return parse_sql(_bind_params_fallback(sql, params))
        try:
            return _bind_statement_params(parse_sql(sql), params)
        except Exception:
            return parse_sql(_bind_params_fallback(sql, params))

    def execute(
        self,
        sql: str,
        role: Optional[str] = None,
        params: Optional[Union[Sequence[Any], Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        effective_role = role or self.access_controller.current_role
        logger.info("⚡ [SQL Exec] [%s] %s", effective_role, sql.strip())
        seq_params = self._resolve_exec_params(params)
        stmt = self._parse_and_bind_stmt(sql, seq_params)
        return self.execute_statement(stmt, role=effective_role)

    def _restore_table_snapshot(self, tname: str, sdata: Dict[str, Any]) -> None:
        if tname in self.tables:
            tcat = self.tables[tname]
            tcat.storage.metadata = [dict(m) for m in sdata.get("meta", [])]
            vecs = sdata.get("vecs", [])
            tcat.storage.write_all(vecs, tcat.storage.metadata)
            tcat.index = HNSWIndex(dim=tcat.storage.dim)
            tcat.index.build_from_storage(vecs)
            tcat.invalidate_unique_sets()

    def _restore_legacy_snapshot(self, legacy: Dict[str, Any]) -> int:
        for tname, sdata in legacy.items():
            self._restore_table_snapshot(tname, sdata)
        return len(legacy)

    def _restore_tuple_snapshot(
        self, legacy_snapshot: Any, undo_actions: List[Any]
    ) -> int:
        if undo_actions:
            return _apply_undo_actions(self.tables, undo_actions)
        if isinstance(legacy_snapshot, dict):
            return self._restore_legacy_snapshot(legacy_snapshot)
        return 0

    def _restore_rollback_snapshot(self, snapshot_res: Any) -> int:
        if isinstance(snapshot_res, tuple):
            return self._restore_tuple_snapshot(snapshot_res[0], snapshot_res[1])
        if isinstance(snapshot_res, dict):
            return self._restore_legacy_snapshot(snapshot_res)
        return 0

    def _exec_begin_tx(self) -> Dict[str, Any]:
        self.tx_manager.begin(None)
        return {"command": "BEGIN", "status": "ok", "message": "Transaction started"}

    def _capture_tables_snapshot(self) -> Dict[str, Any]:
        return {}

    def _exec_savepoint(self, stmt: SavepointStatement) -> Dict[str, Any]:
        if stmt.action == "SAVEPOINT":
            self.tx_manager.create_savepoint(stmt.name, None)
            return {"command": "SAVEPOINT", "status": "ok", "name": stmt.name}
        if stmt.action == "ROLLBACK_TO":
            rb_res = self.tx_manager.rollback_to_savepoint(stmt.name)
            self._restore_rollback_snapshot(rb_res)
            return {"command": "ROLLBACK_TO", "status": "ok", "name": stmt.name}
        if stmt.action == "RELEASE":
            self.tx_manager.release_savepoint(stmt.name)
            return {"command": "RELEASE", "status": "ok", "name": stmt.name}
        raise SQLExecutionError(f"Unknown savepoint action: {stmt.action}")

    def _exec_commit_tx(self) -> Dict[str, Any]:
        mutations = self.tx_manager.commit()
        if self.multi_storage is not None:
            self.multi_storage.save()
        return {
            "command": "COMMIT",
            "status": "ok",
            "mutations_applied": len(mutations),
        }

    def _exec_rollback_tx(self) -> Dict[str, Any]:
        try:
            snapshot_res = self.tx_manager.rollback()
        except Exception as exc:
            raise SQLOperationalError(
                "cannot rollback - no transaction is active"
            ) from exc
        reverted = self._restore_rollback_snapshot(snapshot_res)
        return {
            "command": "ROLLBACK",
            "status": "ok",
            "mutations_reverted": max(1, reverted),
        }

    def _exec_tcl(self, stmt: SQLStatement) -> Dict[str, Any]:
        cmd = stmt.command_type
        if isinstance(stmt, SavepointStatement):
            return self._exec_savepoint(stmt)
        if cmd == SQLCommandType.BEGIN:
            return self._exec_begin_tx()
        if cmd == SQLCommandType.COMMIT:
            return self._exec_commit_tx()
        if cmd == SQLCommandType.ROLLBACK:
            return self._exec_rollback_tx()
        raise SQLExecutionError(f"Unknown TCL command: {cmd}")

    def _calc_hidden_attr(self, c: Any) -> int:
        if not getattr(c, "generated_expr", None):
            return 0
        return 3 if getattr(c, "is_stored", False) else 2

    def _should_skip_pragma_row(self, c: Any, is_xinfo: bool) -> bool:
        """Returns True if this column should be omitted from table_info output."""
        is_gen = bool(getattr(c, "generated_expr", None))
        is_stored = bool(getattr(c, "is_stored", False))
        return not is_xinfo and is_gen and not is_stored

    def _build_pragma_base_row(self, c: Any, cid: int) -> Dict[str, Any]:
        """Builds the base PRAGMA row dict without the xinfo-only 'hidden' field."""
        return {
            "cid": cid,
            "name": c.name,
            "type": c.data_type,
            "notnull": 1 if not c.is_nullable else 0,
            "dflt_value": None,
            "pk": 1 if c.is_primary_key else 0,
        }

    def _build_pragma_row(
        self, c: Any, cid: int, is_xinfo: bool
    ) -> Optional[Dict[str, Any]]:
        if self._should_skip_pragma_row(c, is_xinfo):
            return None
        row = self._build_pragma_base_row(c, cid)
        if is_xinfo:
            row["hidden"] = self._calc_hidden_attr(c)
        return row

    def _col_defs_to_pragma_rows(
        self, col_defs: List[Any], is_xinfo: bool = False
    ) -> List[Dict[str, Any]]:
        rows: List[Dict[str, Any]] = []
        cid = 0
        for c in col_defs:
            row = self._build_pragma_row(c, cid, is_xinfo)
            if row is not None:
                rows.append(row)
                cid += 1
        return rows

    def _infer_meta_pragma_rows(
        self, tcat: TableCatalog, is_xinfo: bool = False
    ) -> List[Dict[str, Any]]:
        first_meta = tcat.storage.metadata[0] if tcat.storage.metadata else {}
        rows: List[Dict[str, Any]] = []
        for cid, k in enumerate(first_meta.keys()):
            row = {
                "cid": cid,
                "name": k,
                "type": "TEXT",
                "notnull": 0,
                "dflt_value": None,
                "pk": 1 if k == "id" else 0,
            }
            if is_xinfo:
                row["hidden"] = 0
            rows.append(row)
        return rows

    def _exec_pragma_table_info(
        self, table_name: Optional[str], is_xinfo: bool = False
    ) -> Dict[str, Any]:
        if not table_name or table_name not in self.tables:
            return {"command": "PRAGMA", "status": "ok", "rows": [], "count": 0}
        tcat = self.tables[table_name]
        col_defs = getattr(tcat, "columns", None) or []
        rows = (
            self._col_defs_to_pragma_rows(col_defs, is_xinfo=is_xinfo)
            if col_defs
            else self._infer_meta_pragma_rows(tcat, is_xinfo=is_xinfo)
        )
        return {"command": "PRAGMA", "status": "ok", "rows": rows, "count": len(rows)}

    def _exec_pragma_index_list(self, table_name: Optional[str]) -> Dict[str, Any]:
        if not table_name or table_name not in self.tables:
            return {"command": "PRAGMA", "status": "ok", "rows": [], "count": 0}
        tcat = self.tables[table_name]
        rows: List[Dict[str, Any]] = []
        for seq, idef in enumerate(getattr(tcat, "index_definitions", [])):
            rows.append(
                {
                    "seq": seq,
                    "name": idef.get("name", ""),
                    "unique": 1 if idef.get("unique") else 0,
                    "origin": "c",
                    "partial": 0,
                }
            )
        return {"command": "PRAGMA", "status": "ok", "rows": rows, "count": len(rows)}

    def _exec_pragma_database_list(self) -> Dict[str, Any]:
        main_path = (
            getattr(self.default_storage, "file_path", ":memory:")
            if self.default_storage
            else ":memory:"
        )
        rows = [{"seq": 0, "name": "main", "file": main_path}]
        for idx, name in enumerate(sorted(self.attached_databases.keys()), start=1):
            info = self.attached_databases[name]
            rows.append(
                {"seq": idx, "name": name, "file": info.get("file", ":memory:")}
            )
        return {"command": "PRAGMA", "status": "ok", "rows": rows, "count": len(rows)}

    def _exec_pragma_foreign_keys(self, val: Optional[str]) -> Dict[str, Any]:
        if val is not None:
            self.foreign_keys_enabled = val.upper() in ("ON", "1", "TRUE", "YES")
        flag_int = 1 if self.foreign_keys_enabled else 0
        return {
            "command": "PRAGMA",
            "status": "ok",
            "rows": [{"foreign_keys": flag_int}],
            "count": 1,
        }

    def _exec_pragma_foreign_key_list(
        self, table_name: Optional[str]
    ) -> Dict[str, Any]:
        if not table_name or table_name not in self.tables:
            return {"command": "PRAGMA", "status": "ok", "rows": [], "count": 0}
        tcat = self.tables[table_name]
        fks = getattr(tcat, "foreign_keys", []) or []
        rows: List[Dict[str, Any]] = []
        for i, fk in enumerate(fks):
            rows.append(
                {
                    "id": i,
                    "seq": 0,
                    "table": fk.parent_table,
                    "from": fk.child_column,
                    "to": fk.parent_column,
                    "on_update": fk.on_update,
                    "on_delete": fk.on_delete,
                    "match": "NONE",
                }
            )
        return {"command": "PRAGMA", "status": "ok", "rows": rows, "count": len(rows)}

    def _exec_pragma_user_version(self, val: Optional[str]) -> Dict[str, Any]:
        if val is not None:
            self.user_version = int(val) if val.isdigit() else 0
            return {"command": "PRAGMA", "status": "ok", "rows": [], "count": 0}
        return {
            "command": "PRAGMA",
            "status": "ok",
            "rows": [{"user_version": self.user_version}],
            "count": 1,
        }

    def _exec_pragma_flag(
        self, pname: str, val: Optional[str] = None
    ) -> Optional[Dict[str, Any]]:
        if pname == "foreign_keys":
            return self._exec_pragma_foreign_keys(val)
        if pname == "integrity_check":
            return {
                "command": "PRAGMA",
                "status": "ok",
                "rows": [{"integrity_check": "ok"}],
                "count": 1,
            }
        return None

    def _dispatch_meta_pragma(
        self, pname: str, stmt: PragmaStatement
    ) -> Optional[Dict[str, Any]]:
        handlers = {
            "table_info": lambda: self._exec_pragma_table_info(
                stmt.argument, is_xinfo=False
            ),
            "table_xinfo": lambda: self._exec_pragma_table_info(
                stmt.argument, is_xinfo=True
            ),
            "foreign_key_list": lambda: self._exec_pragma_foreign_key_list(
                stmt.argument or stmt.value
            ),
            "user_version": lambda: self._exec_pragma_user_version(
                stmt.value if stmt.value is not None else stmt.argument
            ),
            "index_list": lambda: self._exec_pragma_index_list(stmt.argument),
            "database_list": lambda: self._exec_pragma_database_list(),
        }
        handler = handlers.get(pname)
        return handler() if handler is not None else None

    def _exec_pragma(self, stmt: PragmaStatement, role: str) -> Dict[str, Any]:
        pname = stmt.pragma_name.lower()
        meta_res = self._dispatch_meta_pragma(pname, stmt)
        if meta_res is not None:
            return meta_res
        flag_res = self._exec_pragma_flag(pname, stmt.value)
        if flag_res is not None:
            return flag_res
        return {"command": "PRAGMA", "status": "ok", "rows": [], "count": 0}

    def _exec_vacuum_table(self, tcat: TableCatalog) -> None:
        storage = tcat.storage
        if hasattr(storage, "compact"):
            storage.compact()
        elif hasattr(storage, "save"):
            storage.save()

    def _copy_table_to_container(
        self, tcat: TableCatalog, container: MultiTableVectorStorage, tbl_name: str
    ) -> None:
        dim = getattr(tcat.storage, "dim", 16)
        dest_tbl = container.create_table(tbl_name, dim=dim)
        vecs = tcat.storage.get_all_vectors()
        meta = [dict(m) for m in tcat.storage.metadata]
        dest_tbl.write_all(vecs, meta)

    def _resolve_vacuum_target_tables(self, target_table: Optional[str]) -> List[str]:
        if target_table and target_table in self.tables:
            return [target_table]
        return list(self.tables.keys())

    def _exec_vacuum_into(self, stmt: VacuumStatement) -> Dict[str, Any]:
        dest_file = stmt.into_file or ""
        if os.path.exists(dest_file):
            raise SQLExecutionError(
                f"cannot VACUUM - target file already exists: {dest_file}"
            )
        container = MultiTableVectorStorage(file_path=dest_file)
        for tname in self._resolve_vacuum_target_tables(stmt.target_table):
            self._copy_table_to_container(self.tables[tname], container, tname)
        container.save()
        container.close()
        tgt = stmt.target_table if stmt.target_table else "all"
        return {"command": "VACUUM", "status": "ok", "target": tgt, "into": dest_file}

    def _exec_vacuum(self, stmt: VacuumStatement, role: str) -> Dict[str, Any]:
        if stmt.into_file:
            return self._exec_vacuum_into(stmt)
        if stmt.target_table and stmt.target_table in self.tables:
            self._exec_vacuum_table(self.tables[stmt.target_table])
            tgt = stmt.target_table
        else:
            for tcat in self.tables.values():
                self._exec_vacuum_table(tcat)
            tgt = "all"
        return {"command": "VACUUM", "status": "ok", "target": tgt}

    def _analyze_single_table(self, tbl_name: str) -> Tuple[List[str], int]:
        if tbl_name in self.tables:
            tcat = self.tables[tbl_name]
            tcat.recompute_stats()
            return [tbl_name], tcat.stats.total_rows
        return self._analyze_by_index(tbl_name)

    def _analyze_by_index(self, idx_name: str) -> Tuple[List[str], int]:
        for tbl_name, tcat in self.tables.items():
            has_btree = idx_name in tcat.btree_indexes
            has_def = any(d.get("name") == idx_name for d in tcat.index_definitions)
            if has_btree or has_def:
                tcat.recompute_stats()
                return [tbl_name], tcat.stats.total_rows
        return [], 0

    def _analyze_all_tables(self) -> Tuple[List[str], int]:
        tables: List[str] = []
        total = 0
        for name, tcat in self.tables.items():
            tcat.recompute_stats()
            tables.append(name)
            total += tcat.stats.total_rows
        return tables, total

    def _exec_analyze(self, stmt: AnalyzeStatement, role: str) -> Dict[str, Any]:
        if stmt.target_name:
            tables, total = self._analyze_single_table(stmt.target_name)
        else:
            tables, total = self._analyze_all_tables()
        return {
            "command": "ANALYZE",
            "status": "ok",
            "tables_analyzed": tables,
            "total_rows": total,
        }

    def _find_view(self, name: str) -> Optional[CreateViewStatement]:
        for vname, vstmt in self.views.items():
            if vname.lower() == name.lower():
                return vstmt
        return None

    def _find_instead_of_trigger(
        self, table_name: str, event: str
    ) -> Optional[CreateTriggerStatement]:
        for trig in self.triggers.values():
            if (
                trig.table_name.lower() == table_name.lower()
                and trig.timing.upper() == "INSTEAD OF"
                and trig.event.upper() == event.upper()
            ):
                return trig
        return None

    def _exec_create_trigger(
        self, stmt: CreateTriggerStatement, role: str
    ) -> Dict[str, Any]:
        if stmt.timing.upper() == "INSTEAD OF":
            if not self._find_view(stmt.table_name):
                raise SQLExecutionError(
                    f"cannot create INSTEAD OF trigger on table: {stmt.table_name}"
                )
        self.triggers[stmt.trigger_name.lower()] = stmt
        return {
            "command": "CREATE_TRIGGER",
            "status": "ok",
            "trigger": stmt.trigger_name,
        }

    def _exec_drop_trigger(
        self, stmt: DropTriggerStatement, role: str
    ) -> Dict[str, Any]:
        key = stmt.trigger_name.lower()
        if key in self.triggers:
            del self.triggers[key]
            return {
                "command": "DROP_TRIGGER",
                "status": "ok",
                "trigger": stmt.trigger_name,
            }
        if stmt.if_exists:
            return {
                "command": "DROP_TRIGGER",
                "status": "ok",
                "trigger": stmt.trigger_name,
                "message": "Trigger did not exist",
            }
        raise SQLExecutionError(f"Trigger '{stmt.trigger_name}' does not exist")

    @staticmethod
    def _format_trigger_val(val: Any) -> str:
        if val is None:
            return "NULL"
        if isinstance(val, str):
            return f"'{val}'"
        return str(val)

    @classmethod
    def _substitute_var_prefix(
        cls, sql: str, prefix: str, record: Dict[str, Any]
    ) -> str:
        res = sql
        for k, v in record.items():
            val_str = cls._format_trigger_val(v)
            res = re.sub(
                rf"\b{prefix}\.{re.escape(k)}\b", val_str, res, flags=re.IGNORECASE
            )
        return res

    def _substitute_trigger_vars(
        self,
        sql: str,
        record: Optional[Dict[str, Any]] = None,
        new_record: Optional[Dict[str, Any]] = None,
        old_record: Optional[Dict[str, Any]] = None,
    ) -> str:
        n_rec = new_record if new_record is not None else (record or {})
        o_rec = old_record if old_record is not None else (record or {})
        res = self._substitute_var_prefix(sql, "NEW", n_rec)
        return self._substitute_var_prefix(res, "OLD", o_rec)

    def _fire_single_trigger(
        self,
        trig: CreateTriggerStatement,
        record: Optional[Dict[str, Any]] = None,
        role: str = "admin",
        new_record: Optional[Dict[str, Any]] = None,
        old_record: Optional[Dict[str, Any]] = None,
    ) -> None:
        for raw_sql in trig.body_sqls:
            sub_sql = self._substitute_trigger_vars(
                raw_sql, record=record, new_record=new_record, old_record=old_record
            )
            self.execute(sub_sql, role=role)

    def _fire_triggers(
        self,
        timing: str,
        event: str,
        table_name: str,
        record: Optional[Dict[str, Any]] = None,
        role: str = "admin",
    ) -> None:
        for trig in list(self.triggers.values()):
            if (
                trig.timing.upper() == timing.upper()
                and trig.event.upper() == event.upper()
                and trig.table_name.lower() == table_name.lower()
            ):
                self._fire_single_trigger(trig, record, role)

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

    def _create_attached_storage(self, table_name: str) -> Optional[Any]:
        if "." not in table_name:
            return None
        schema, tbl = table_name.split(".", 1)
        if schema in self.attached_databases:
            return self.attached_databases[schema]["storage"].create_table(
                tbl, dim=self.embedding.dim
            )
        return None

    def _create_default_storage(self, stmt: CreateTableStatement) -> Any:
        attached_st = self._create_attached_storage(stmt.table_name)
        if attached_st is not None:
            return attached_st
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

    @staticmethod
    def _extract_table_gen_columns(columns: List[ColumnDef]) -> Dict[str, ColumnDef]:
        return {c.name: c for c in columns if c.generated_expr is not None}

    @staticmethod
    def _extract_table_collations(columns: List[ColumnDef]) -> Dict[str, str]:
        return {c.name: c.collate for c in columns if c.collate is not None}

    def _create_new_table_storage(self, stmt: CreateTableStatement) -> None:
        storage = self._instantiate_table_storage(stmt)
        catalog = TableCatalog(
            name=stmt.table_name,
            storage=storage,
            schema={col.name: col.data_type for col in stmt.columns},
            raw_sql=stmt.raw_sql,
            storage_engine=stmt.storage_engine,
            location=stmt.location,
            strict=stmt.strict,
            generated_columns=self._extract_table_gen_columns(stmt.columns),
            column_collations=self._extract_table_collations(stmt.columns),
            foreign_keys=stmt.foreign_keys,
            columns=stmt.columns,
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
        if stmt.default_value is not None:
            c_def.default_value = stmt.default_value
        table.columns.append(c_def)
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

    def _validate_index_hint(self, table_name: str, indexed_by: Optional[str]) -> None:
        """Validates that indexed_by exists on table_name if provided."""
        if not indexed_by or table_name not in self.tables:
            return
        table = self.tables[table_name]
        avail = set(table.btree_indexes.keys()).union(table.btree_index_names.values())
        avail.update(d.get("name", "") for d in table.index_definitions)
        if indexed_by not in avail:
            raise SQLExecutionError(f"no such index: {indexed_by}")

    @staticmethod
    def _build_explain_indexes(table: TableCatalog) -> Dict[str, str]:
        avail = {
            col: table.btree_index_names.get(col, f"idx_{col}")
            for col in table.btree_indexes.keys()
        }
        for d in table.index_definitions:
            if "column" in d and "name" in d:
                avail[d["column"]] = d["name"]
        return avail

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
        avail_indexes = self._build_explain_indexes(table)
        try:
            explain_rows = QueryPlanner.explain(
                sub_stmt, table.stats, available_indexes=avail_indexes
            )
        except ValueError as e:
            raise SQLExecutionError(str(e))
        return {"command": "EXPLAIN", "status": "ok", "rows": explain_rows}

    @staticmethod
    def _has_non_zero_vector(vecs: Sequence[Sequence[float]]) -> bool:
        return any(any(x != 0.0 for x in v) for v in vecs)

    @staticmethod
    def _ensure_table_vector_index(table: TableCatalog) -> None:
        if table.index is not None:
            return
        vecs = table.storage.get_all_vectors()
        if not vecs or not SQLExecutor._has_non_zero_vector(vecs):
            raise SQLExecutionError(
                f"Table '{table.name}' does not have a vector index for KNN search."
            )
        table.index = HNSWIndex(dim=table.storage.dim)
        table.index.build_from_storage(vecs)

    def _query_knn_rows(
        self, table: TableCatalog, knn_query: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        self._ensure_table_vector_index(table)
        assert table.index is not None
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
            if "." in name:
                prefixed[f"{name.split('.', 1)[1]}.{k}"] = v
            if alias:
                prefixed[f"{alias}.{k}"] = v
        return prefixed

    @staticmethod
    def _extract_recursive_stmt(anchor_stmt: Any) -> Optional[Any]:
        rec_stmt: Optional[Any] = getattr(anchor_stmt, "union_all", None)
        anchor_stmt.union_all = None
        if getattr(anchor_stmt, "compounds", None):
            if not rec_stmt and anchor_stmt.compounds:
                rec_stmt = anchor_stmt.compounds[0][1]
            empty_compounds: List[Tuple[str, Any]] = []
            anchor_stmt.compounds = empty_compounds
        return rec_stmt

    def _evaluate_recursive_cte(
        self,
        cte: Any,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        anchor_stmt = cte.statement
        rec_stmt = self._extract_recursive_stmt(anchor_stmt)

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

    def _resolve_table_func_args(
        self,
        tbl_ref: TableRef,
        ctx: Dict[str, Any],
    ) -> Tuple[Any, Optional[str]]:
        args = tbl_ref.function_args
        arg0_expr = args[0] if args else "null"
        val0 = _extract_field_value(ctx, arg0_expr)
        if len(args) <= 1:
            return val0, None
        val_path = _extract_field_value(ctx, args[1])
        return val0, (str(val_path) if val_path is not None else None)

    def _generate_table_func_rows(
        self,
        tbl_ref: TableRef,
        parent_row: Optional[Dict[str, Any]] = None,
    ) -> List[Dict[str, Any]]:
        """Generates dynamic rows for table-valued functions json_each / json_tree."""
        func = (
            iter_json_each if tbl_ref.function_name == "json_each" else iter_json_tree
        )
        val0, p_str = self._resolve_table_func_args(tbl_ref, parent_row or {})
        raw_rows = func(val0, p_str)
        return [self._prefix_record(r, tbl_ref) for r in raw_rows]

    def _join_table_func_rows(
        self,
        current_rows: List[Dict[str, Any]],
        join: Any,
    ) -> List[Dict[str, Any]]:
        next_rows: List[Dict[str, Any]] = []
        for left_row in current_rows:
            right_rows = self._generate_table_func_rows(join.table, left_row)
            matched = self._match_join_row(left_row, right_rows, join)
            next_rows.extend(matched)
        return next_rows

    def _execute_hash_join(
        self,
        current_rows: List[Dict[str, Any]],
        j_prefixed_rows: List[Dict[str, Any]],
        join: Any,
        left_key: str,
        right_key: str,
        rem_conds: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        bucket = _build_hash_bucket(j_prefixed_rows, right_key)
        is_left_join = join.join_type == JoinType.LEFT
        next_rows: List[Dict[str, Any]] = []

        for left_row in current_rows:
            lv = _extract_field_value(left_row, left_key)
            candidates = bucket.get(str(lv), []) if lv is not None else []
            matched = _probe_hash_bucket_row(left_row, candidates, rem_conds)
            if not matched and is_left_join:
                next_rows.extend(self._left_join_fallback(left_row, j_prefixed_rows))
            else:
                next_rows.extend(matched)
        return next_rows

    def _try_hash_join(
        self,
        current_rows: List[Dict[str, Any]],
        j_prefixed_rows: List[Dict[str, Any]],
        join: Any,
    ) -> Optional[List[Dict[str, Any]]]:
        if not _is_hash_joinable(join, current_rows, j_prefixed_rows):
            return None
        r_name = getattr(join.table, "display_name", "") or join.table.name
        keys = _find_equi_join_keys(
            join.on_conditions, r_name, current_rows[0], j_prefixed_rows[0]
        )
        if keys is None:
            return None
        left_k, right_k, rem = keys
        return self._execute_hash_join(
            current_rows, j_prefixed_rows, join, left_k, right_k, rem
        )

    def _nested_loop_join(
        self,
        current_rows: List[Dict[str, Any]],
        j_prefixed_rows: List[Dict[str, Any]],
        join: Any,
    ) -> List[Dict[str, Any]]:
        next_rows: List[Dict[str, Any]] = []
        for left_row in current_rows:
            next_rows.extend(self._match_join_row(left_row, j_prefixed_rows, join))
        return next_rows

    def _join_table_rows(
        self,
        current_rows: List[Dict[str, Any]],
        join: Any,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        join_tbl_ref = join.table
        if join_tbl_ref.function_name in ("json_each", "json_tree"):
            return self._join_table_func_rows(current_rows, join)

        if join_tbl_ref.name not in temp_tables:
            self.access_controller.enforce_permission(
                effective_role, join_tbl_ref.name, "SELECT"
            )

        j_raw = self._query_knn_or_scan(
            join_tbl_ref.name, None, temporary_tables=temp_tables
        )
        j_pref = [self._prefix_record(r, join_tbl_ref) for r in j_raw]
        hash_res = self._try_hash_join(current_rows, j_pref, join)
        if hash_res is not None:
            return hash_res
        return self._nested_loop_join(current_rows, j_pref, join)

    def _project_column_item(self, r: Dict[str, Any], col_expr: str) -> Tuple[str, Any]:
        as_m = re.search(r"\s+AS\s+([a-zA-Z0-9_]+)$", col_expr, re.IGNORECASE)
        if as_m:
            out_key = as_m.group(1).strip()
            raw_col = col_expr[: as_m.start()].strip()
            return out_key, _extract_field_value(r, raw_col)

        out_key = col_expr
        if "." in out_key and "->" not in out_key:
            out_key = out_key.split(".")[-1]
        return out_key, _extract_field_value(r, col_expr)

    def _project_wildcard(self, r: Dict[str, Any], table_name: str) -> Dict[str, Any]:
        return {
            k: v
            for k, v in r.items()
            if not k.startswith("_")
            and ("." not in k or k.startswith(f"{table_name}."))
        }

    def _project_row(
        self, r: Dict[str, Any], columns: List[str], table_name: str
    ) -> Dict[str, Any]:
        if "*" in columns and len(columns) == 1:
            return self._project_wildcard(r, table_name)
        # Use an ordered list of (key, value) pairs to preserve column order and
        # handle duplicate short names (e.g. e.name vs d.name both → "name").
        # When a short name collides, fall back to the original qualified expression
        # as the output key so that both values are preserved in the result tuple.
        pairs: List[Tuple[str, Any]] = []
        used_keys: set[str] = set()
        for col_expr in columns:
            k, v = self._project_column_item(r, col_expr.strip())
            if k in used_keys:
                # Collision: use original expression as key to keep both values
                k = col_expr.strip()
            used_keys.add(k)
            pairs.append((k, v))
        return dict(pairs)

    @staticmethod
    def _deduplicate_rows(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        seen: set[Tuple[Any, ...]] = set()
        unique: List[Dict[str, Any]] = []
        for r in rows:
            key = tuple(r.values())
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
    def _sort_key(
        row: Dict[str, Any],
        order_by: str,
        order_collate: Optional[str] = None,
    ) -> Any:
        val = _extract_field_value(row, order_by)
        if val is None:
            return 0
        return _collate_transform(val, order_collate)

    def _sort_custom_collate(
        self,
        rows: List[Dict[str, Any]],
        order_by: str,
        order_desc: bool,
        cmp_fn: Callable[[str, str], int],
    ) -> None:
        def custom_cmp(r1: Dict[str, Any], r2: Dict[str, Any]) -> int:
            v1 = _extract_field_value(r1, order_by)
            v2 = _extract_field_value(r2, order_by)
            if v1 is None and v2 is None:
                return 0
            if v1 is None:
                return -1
            if v2 is None:
                return 1
            return cmp_fn(str(v1), str(v2))

        rows.sort(key=functools.cmp_to_key(custom_cmp), reverse=order_desc)

    def _sort_and_paginate(
        self,
        rows: List[Dict[str, Any]],
        order_by: Optional[str],
        order_desc: bool,
        limit: Optional[int],
        offset: Optional[int] = None,
        order_collate: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        if order_by:
            clean_col = order_collate.upper() if order_collate else ""
            if clean_col in self.collations:
                self._sort_custom_collate(
                    rows, order_by, order_desc, self.collations[clean_col]
                )
            else:
                rows.sort(
                    key=lambda x: self._sort_key(x, order_by, order_collate),
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

    def _scan_regular_initial_rows(
        self,
        table_ref: TableRef,
        stmt: SelectStatement,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        self._validate_index_hint(table_ref.name, table_ref.indexed_by)
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

    @staticmethod
    def _is_tableless_select(table_ref: TableRef, stmt: SelectStatement) -> bool:
        return not table_ref.name and not stmt.table_name

    def _get_initial_select_rows(
        self,
        table_ref: TableRef,
        stmt: SelectStatement,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        if stmt.values_rows is not None:
            return [dict(zip(stmt.columns, r)) for r in stmt.values_rows]
        if table_ref.function_name in ("json_each", "json_tree"):
            return self._generate_table_func_rows(table_ref)
        if self._is_tableless_select(table_ref, stmt):
            return [{}]
        return self._scan_regular_initial_rows(
            table_ref, stmt, effective_role, temp_tables
        )

    def _apply_single_join(
        self,
        current_rows: List[Dict[str, Any]],
        join: JoinClause,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        if join.table and join.table.indexed_by:
            self._validate_index_hint(join.table.name, join.table.indexed_by)
        return self._join_table_rows(current_rows, join, effective_role, temp_tables)

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
            current_rows = self._apply_single_join(
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
        final_rows = self._apply_compound_operations(
            final_rows, stmt, effective_role, temp_tables
        )

        return {
            "command": "SELECT",
            "status": "ok",
            "count": len(final_rows),
            "rows": final_rows,
        }

    @staticmethod
    def _align_compound_rows(
        target_keys: List[str], rows: List[Dict[str, Any]]
    ) -> List[Dict[str, Any]]:
        if not target_keys:
            return rows
        aligned: List[Dict[str, Any]] = []
        for r in rows:
            vals = list(r.values())
            if len(vals) == len(target_keys):
                aligned.append(dict(zip(target_keys, vals)))
            else:
                aligned.append(r)
        return aligned

    @staticmethod
    def _row_to_hashable(r: Dict[str, Any]) -> Tuple[Any, ...]:
        return tuple(r.values())

    def _build_row_hash_set(self, rows: List[Dict[str, Any]]) -> Set[Tuple[Any, ...]]:
        return {self._row_to_hashable(r) for r in rows}

    def _combine_union_rows(
        self,
        final_rows: List[Dict[str, Any]],
        stmt: SelectStatement,
        role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        target_keys = list(final_rows[0].keys()) if final_rows else list(stmt.columns)
        if stmt.union_all:
            res = self._exec_select(stmt.union_all, role, temporary_tables=temp_tables)
            final_rows.extend(
                self._align_compound_rows(target_keys, res.get("rows", []))
            )
            return final_rows
        if stmt.union:
            res = self._exec_select(stmt.union, role, temporary_tables=temp_tables)
            right_rows = self._align_compound_rows(target_keys, res.get("rows", []))
            return self._deduplicate_rows(final_rows + right_rows)
        return final_rows

    def _combine_intersect_rows(
        self,
        final_rows: List[Dict[str, Any]],
        intersect_stmt: Optional[SelectStatement],
        role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        if not intersect_stmt:
            return final_rows
        res = self._exec_select(intersect_stmt, role, temporary_tables=temp_tables)
        right_set = self._build_row_hash_set(res.get("rows", []))
        matched = [r for r in final_rows if self._row_to_hashable(r) in right_set]
        return self._deduplicate_rows(matched)

    def _combine_except_rows(
        self,
        final_rows: List[Dict[str, Any]],
        except_stmt: Optional[SelectStatement],
        role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        if not except_stmt:
            return final_rows
        res = self._exec_select(except_stmt, role, temporary_tables=temp_tables)
        right_set = self._build_row_hash_set(res.get("rows", []))
        diff = [r for r in final_rows if self._row_to_hashable(r) not in right_set]
        return self._deduplicate_rows(diff)

    def _fold_intersect_or_except(
        self,
        current_rows: List[Dict[str, Any]],
        op: str,
        right_rows: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        r_set = self._build_row_hash_set(right_rows)
        keep_in = op == "INTERSECT"
        filtered = [
            r for r in current_rows if (self._row_to_hashable(r) in r_set) == keep_in
        ]
        return self._deduplicate_rows(filtered)

    def _fold_single_compound_op(
        self,
        current_rows: List[Dict[str, Any]],
        op: str,
        right_rows: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        if op == "UNION ALL":
            return current_rows + right_rows
        if op == "UNION":
            return self._deduplicate_rows(current_rows + right_rows)
        return self._fold_intersect_or_except(current_rows, op, right_rows)

    def _apply_compound_pipeline(
        self,
        final_rows: List[Dict[str, Any]],
        stmt: SelectStatement,
        role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        target_keys = list(final_rows[0].keys()) if final_rows else list(stmt.columns)
        current_rows = list(final_rows)
        for op, right_stmt in stmt.compounds:
            res = self._exec_select(right_stmt, role, temporary_tables=temp_tables)
            right_rows = self._align_compound_rows(target_keys, res.get("rows", []))
            current_rows = self._fold_single_compound_op(current_rows, op, right_rows)
        return current_rows

    def _apply_compound_operations(
        self,
        final_rows: List[Dict[str, Any]],
        stmt: SelectStatement,
        role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        if getattr(stmt, "compounds", None):
            return self._apply_compound_pipeline(final_rows, stmt, role, temp_tables)
        rows = self._combine_union_rows(final_rows, stmt, role, temp_tables)
        rows = self._combine_intersect_rows(rows, stmt.intersect, role, temp_tables)
        return self._combine_except_rows(rows, stmt.except_, role, temp_tables)

    def _try_fast_count_select(
        self, stmt: SelectStatement, role: str, temp_tables: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        if not temp_tables and self._is_simple_count_query(stmt):
            return self._exec_fast_count(stmt, role)
        return None

    def _filter_select_rows(
        self,
        rows: List[Dict[str, Any]],
        where_clauses: Any,
        role: str = "admin",
        temp_tables: Any = None,
    ) -> List[Dict[str, Any]]:
        return [
            r
            for r in rows
            if _matches_where_clause(
                r, where_clauses, executor=self, role=role, temp_tables=temp_tables
            )
        ]

    @staticmethod
    def _apply_group_and_having(
        rows: List[Dict[str, Any]], stmt: SelectStatement
    ) -> List[Dict[str, Any]]:
        if not stmt.group_by and not _has_aggregate_columns(stmt):
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

    @staticmethod
    def _collect_table_refs(stmt: SelectStatement) -> List[TableRef]:
        refs: List[TableRef] = []
        if stmt.table_ref:
            refs.append(stmt.table_ref)
        for j in stmt.joins or []:
            if j.table:
                refs.append(j.table)
        return refs

    def _evaluate_derived_tables(
        self, stmt: SelectStatement, role: str, temp_tables: Dict[str, Any]
    ) -> None:
        for tref in self._collect_table_refs(stmt):
            sub = getattr(tref, "subquery", None)
            if sub is not None and tref.name not in temp_tables:
                sub_res = self._exec_select(sub, role, temporary_tables=temp_tables)
                temp_tables[tref.name] = list(sub_res.get("rows", []))

    def _prepare_select_views_and_ctes(
        self, stmt: SelectStatement, role: str, temp_tables: Dict[str, Any]
    ) -> None:
        if self.views:
            self._evaluate_referenced_views(stmt, role, temp_tables)
        if stmt.ctes:
            self._evaluate_all_ctes(stmt.ctes, role, temp_tables)
        self._evaluate_derived_tables(stmt, role, temp_tables)

    def _resolve_effective_order_collate(
        self, stmt: SelectStatement, tbl_collations: Dict[str, str]
    ) -> Optional[str]:
        if stmt.order_collate:
            return stmt.order_collate
        return tbl_collations.get(stmt.order_by) if stmt.order_by else None

    def _filter_and_window_select_rows(
        self,
        current_rows: List[Dict[str, Any]],
        stmt: SelectStatement,
        tbl_collations: Dict[str, str],
        role: str,
        temp_tables: Dict[str, Any],
    ) -> List[Dict[str, Any]]:
        where_conds = _enrich_where_clauses_with_collations(
            stmt.where_clauses, tbl_collations
        )
        filtered = self._filter_select_rows(
            current_rows, where_conds, role=role, temp_tables=temp_tables
        )
        grouped = self._apply_group_and_having(filtered, stmt)
        win_specs = extract_window_functions(stmt.columns)
        return list(compute_window_functions(grouped, win_specs))

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

        self._prepare_select_views_and_ctes(stmt, effective_role, temp_tables)
        current_rows = self._scan_and_join_tables(stmt, effective_role, temp_tables)
        tbl = self.tables.get(stmt.table_name)
        tbl_collations = tbl.column_collations if tbl else {}

        windowed_rows = self._filter_and_window_select_rows(
            current_rows, stmt, tbl_collations, effective_role, temp_tables
        )
        lim, off = self._resolve_paginate_limits(stmt)
        eff_collate = self._resolve_effective_order_collate(stmt, tbl_collations)
        paged_rows = self._sort_and_paginate(
            windowed_rows, stmt.order_by, stmt.order_desc, lim, off, eff_collate
        )
        return self._build_select_result(paged_rows, stmt, effective_role, temp_tables)

    def _parse_raw_vector(self, raw_vec: Any) -> Any:
        if isinstance(raw_vec, str) and raw_vec.startswith("["):
            try:
                return json.loads(raw_vec)
            except Exception:
                return raw_vec
        return raw_vec

    def _resolve_insert_vector(
        self, col_val_map: Dict[str, Any], dim: int
    ) -> List[float]:
        raw_vec = self._parse_raw_vector(col_val_map.get("vector"))
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

    def _resolve_insert_columns(
        self, stmt: InsertStatement, table: TableCatalog
    ) -> List[str]:
        if stmt.columns:
            _check_generated_column_writes(table, stmt.columns)
            return stmt.columns
        return [c for c in table.schema.keys() if c not in table.generated_columns]

    @staticmethod
    def _apply_single_col_default(c: ColumnDef, row: Dict[str, Any]) -> None:
        if c.name not in row and c.default_value is not None:
            row[c.name] = c.default_value

    @staticmethod
    def _apply_column_defaults(table: TableCatalog, row: Dict[str, Any]) -> None:
        for c in table.columns:
            SQLExecutor._apply_single_col_default(c, row)

    @staticmethod
    def _coerce_int_val(val: Any) -> Any:
        if isinstance(val, bool):
            return val
        try:
            return int(val)
        except (ValueError, TypeError):
            return val

    @staticmethod
    def _coerce_real_val(val: Any) -> Any:
        try:
            return float(val)
        except (ValueError, TypeError):
            return val

    @staticmethod
    def _is_null_literal(val: Any) -> bool:
        return val is None or (isinstance(val, str) and val.upper() == "NULL")

    @staticmethod
    def _coerce_value_to_type(val: Any, data_type: str) -> Any:
        """Coerce a raw value to the Python type matching the SQLite column affinity.

        SQLite stores values with type affinity; integers and reals should not
        be stored as plain strings so that TYPEOF(), IS NULL, and arithmetic
        all behave identically to SQLite.
        """
        if SQLExecutor._is_null_literal(val):
            return None
        dt = data_type.upper().split("(")[0].strip()
        if dt in {"INT", "INTEGER", "BIGINT", "SMALLINT", "TINYINT", "INT2", "INT8"}:
            return SQLExecutor._coerce_int_val(val)
        if dt in {"REAL", "FLOAT", "DOUBLE", "NUMERIC", "DECIMAL", "NUMBER"}:
            return SQLExecutor._coerce_real_val(val)
        return val

    @staticmethod
    def _apply_type_coercion(table: TableCatalog, row: Dict[str, Any]) -> None:
        """Coerce all row values to their declared column types in-place."""
        type_map = {c.name: c.data_type for c in table.columns}
        for col, val in list(row.items()):
            if col in type_map:
                row[col] = SQLExecutor._coerce_value_to_type(val, type_map[col])

    @staticmethod
    def _materialize_insert_rows(
        stmt: InsertStatement, cols: List[str]
    ) -> List[Dict[str, Any]]:
        if stmt.rows_values:
            return [dict(zip(cols, row)) for row in stmt.rows_values]
        if stmt.values:
            return [dict(zip(cols, stmt.values))]
        return []

    def _build_insert_row_dicts(
        self, stmt: InsertStatement, table: TableCatalog, role: str
    ) -> List[Dict[str, Any]]:
        if stmt.select_stmt is not None:
            rows = self._build_from_select(stmt, role)
        else:
            cols = self._resolve_insert_columns(stmt, table)
            rows = self._materialize_insert_rows(stmt, cols)
        for r in rows:
            self._apply_column_defaults(table, r)
            self._apply_type_coercion(table, r)
        return rows

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

    @staticmethod
    def _evaluate_upsert_update_set(
        raw_update: Dict[str, Any], existing: Dict[str, Any]
    ) -> Dict[str, Any]:
        evaluated: Dict[str, Any] = {}
        ctx = dict(existing)
        for col, expr_val in raw_update.items():
            if isinstance(expr_val, str):
                evaluated[col] = _extract_field_value(ctx, expr_val)
            else:
                evaluated[col] = expr_val
        return evaluated

    def _handle_conflict(
        self,
        table: TableCatalog,
        conflict_idx: int,
        row: Dict[str, Any],
        stmt: InsertStatement,
    ) -> Optional[Dict[str, Any]]:
        if stmt.upsert_action != "UPDATE":
            return None
        existing = table.storage.metadata[conflict_idx]
        raw_update = stmt.upsert_update_set or row
        evaluated = self._evaluate_upsert_update_set(raw_update, existing)
        existing.update(evaluated)
        return dict(existing)

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

    def _insert_non_vector_row(
        self, table: TableCatalog, row: Dict[str, Any]
    ) -> Dict[str, Any]:
        if hasattr(table.storage, "upsert"):
            table.storage.upsert(row)
        elif hasattr(table.storage, "append"):
            table.storage.append(row)
        return dict(row)

    def _prepare_insert_vector(
        self, table: TableCatalog, row: Dict[str, Any]
    ) -> Sequence[float]:
        has_vector_input = "vector" in row or "embedding" in row
        if table.index is not None:
            return self._resolve_insert_vector(row, table.storage.dim)
        if has_vector_input:
            vector = self._resolve_insert_vector(row, table.storage.dim)
            table.index = HNSWIndex(dim=table.storage.dim)
            for prev_idx, prev_v in enumerate(table.storage.get_all_vectors()):
                table.index.add_item(prev_idx, prev_v)
            return vector
        return (0.0,) * getattr(table.storage, "dim", 128)

    def _insert_vector_row(
        self, table: TableCatalog, row: Dict[str, Any], stmt: InsertStatement
    ) -> Dict[str, Any]:
        vector = self._prepare_insert_vector(table, row)
        idx = table.storage.append(vector, row)
        if self.tx_manager.is_active:
            self.tx_manager.stage_mutation(
                "INSERT", {"table": stmt.table_name, "data": row}
            )
            self.tx_manager.record_undo(
                "INSERT", stmt.table_name, {"idx": idx, "row": dict(row)}
            )
        if table.index is not None:
            table.index.add_item(idx, vector)
        return dict(row)

    @staticmethod
    def _validate_single_not_null(table_name: str, col: ColumnDef, val: Any) -> None:
        if not col.is_nullable and val is None:
            raise SQLIntegrityError(
                f"NOT NULL constraint failed: {table_name}.{col.name}"
            )

    @staticmethod
    def _validate_not_null_constraints(
        table: TableCatalog, row: Dict[str, Any]
    ) -> None:
        for col in table.columns:
            SQLExecutor._validate_single_not_null(table.name, col, row.get(col.name))

    @staticmethod
    def _is_matching_unique_val(existing_val: Any, new_val: Any) -> bool:
        if existing_val is None or new_val is None:
            return False
        return str(existing_val) == str(new_val)

    @staticmethod
    def _check_column_uniqueness(
        table: TableCatalog, col_name: str, new_val: Any
    ) -> None:
        if new_val is None:
            return
        if str(new_val) in table.get_unique_set(col_name):
            raise SQLIntegrityError(
                f"UNIQUE constraint failed: {table.name}.{col_name}"
            )

    @staticmethod
    def _validate_unique_and_pk_constraints(
        table: TableCatalog, row: Dict[str, Any]
    ) -> None:
        for col in table.columns:
            is_uniq = getattr(col, "is_unique", False) or col.is_primary_key
            if is_uniq and col.name in row:
                SQLExecutor._check_column_uniqueness(table, col.name, row[col.name])

    @staticmethod
    def _validate_row_constraints(table: TableCatalog, row: Dict[str, Any]) -> None:
        SQLExecutor._validate_not_null_constraints(table, row)
        SQLExecutor._validate_unique_and_pk_constraints(table, row)

    def _insert_or_upsert_row(
        self, table: TableCatalog, row: Dict[str, Any], stmt: InsertStatement
    ) -> Optional[Dict[str, Any]]:
        is_conflict, conflict_res = self._try_upsert_conflict(table, row, stmt)
        if is_conflict:
            return conflict_res
        self._validate_row_constraints(table, row)
        if not hasattr(table.storage, "dim"):
            return self._insert_non_vector_row(table, row)
        return self._insert_vector_row(table, row, stmt)

    def _apply_insert_loop(
        self,
        table: TableCatalog,
        row_dicts: List[Dict[str, Any]],
        stmt: InsertStatement,
        effective_role: str,
    ) -> List[Dict[str, Any]]:
        modified: List[Dict[str, Any]] = []
        for r in row_dicts:
            self._fire_triggers("BEFORE", "INSERT", stmt.table_name, r, effective_role)
            res_rec = self._insert_or_upsert_row(table, r, stmt)
            if res_rec is not None:
                table.record_inserted_unique_values(res_rec)
                modified.append(res_rec)
                self._fire_triggers(
                    "AFTER", "INSERT", stmt.table_name, res_rec, effective_role
                )
        return modified

    def _exec_view_select(
        self, vstmt: CreateViewStatement, effective_role: str
    ) -> Dict[str, Any]:
        if vstmt.select_stmt is None:
            return {"columns": [], "rows": []}
        return self._exec_select(vstmt.select_stmt, effective_role)

    @staticmethod
    def _item_to_col_name(c: Any) -> Optional[str]:
        raw = getattr(c, "alias", None) or getattr(c, "expr", None) or c
        s = str(raw)
        return None if s == "*" else s

    @classmethod
    def _collect_extracted_columns(cls, columns: List[Any]) -> List[str]:
        cols: List[str] = []
        for c in columns:
            name = cls._item_to_col_name(c)
            if name:
                cols.append(name)
        return cols

    def _fallback_view_columns(
        self, vstmt: CreateViewStatement, effective_role: str
    ) -> List[str]:
        rows = self._exec_view_select(vstmt, effective_role).get("rows", [])
        return [k for k in rows[0].keys() if not k.startswith("_")] if rows else []

    def _resolve_view_columns(
        self, vstmt: CreateViewStatement, effective_role: str
    ) -> List[str]:
        if not vstmt.select_stmt:
            return []
        cols = self._collect_extracted_columns(vstmt.select_stmt.columns)
        if cols:
            return cols
        return self._fallback_view_columns(vstmt, effective_role)

    def _build_view_insert_rows(
        self, stmt: InsertStatement, vstmt: CreateViewStatement, effective_role: str
    ) -> List[Dict[str, Any]]:
        cols = stmt.columns or self._resolve_view_columns(vstmt, effective_role)
        if stmt.rows_values:
            return [dict(zip(cols, row)) for row in stmt.rows_values]
        if stmt.values:
            return [dict(zip(cols, stmt.values))]
        return []

    def _exec_insert_view(
        self, stmt: InsertStatement, vstmt: CreateViewStatement, effective_role: str
    ) -> Dict[str, Any]:
        trig = self._find_instead_of_trigger(stmt.table_name, "INSERT")
        if not trig:
            raise SQLExecutionError(f"cannot modify view '{stmt.table_name}'")
        row_dicts = self._build_view_insert_rows(stmt, vstmt, effective_role)
        for r in row_dicts:
            self._fire_single_trigger(trig, record=r, role=effective_role, new_record=r)
        return {
            "command": "INSERT",
            "status": "ok",
            "table": stmt.table_name,
            "id": "",
            "inserted_count": len(row_dicts),
        }

    def _exec_insert(
        self, stmt: InsertStatement, effective_role: str
    ) -> Dict[str, Any]:
        vstmt = self._find_view(stmt.table_name)
        if vstmt:
            return self._exec_insert_view(stmt, vstmt, effective_role)
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "INSERT"
        )
        self._ensure_table_exists_for_insert(stmt.table_name)
        table = self._get_table(stmt.table_name)
        row_dicts = self._build_insert_row_dicts(stmt, table, effective_role)
        for r in row_dicts:
            _compute_generated_columns(table, r)
        _check_strict_table_rows(table, stmt.table_name, row_dicts)
        modified_records = self._apply_insert_loop(
            table, row_dicts, stmt, effective_role
        )
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
        order_collate: Optional[str] = None,
    ) -> List[int]:
        if order_by:
            indices.sort(
                key=lambda i: self._sort_key(metadata[i], order_by, order_collate),
                reverse=order_desc,
            )
        if limit is not None:
            return indices[:limit]
        return indices

    def _find_update_indices(
        self, table: TableCatalog, stmt: UpdateStatement
    ) -> List[int]:
        where_conds = _enrich_where_clauses_with_collations(
            stmt.where_clauses, table.column_collations
        )
        matching = [
            idx
            for idx, meta in enumerate(table.storage.metadata)
            if _matches_where_clause(meta, where_conds)
        ]
        return self._sort_and_limit_indices(
            table.storage.metadata,
            matching,
            stmt.order_by,
            stmt.order_desc,
            stmt.limit,
        )

    def _enforce_update_from_perms(
        self, stmt: UpdateStatement, effective_role: str
    ) -> None:
        if stmt.from_table:
            self.access_controller.enforce_permission(
                effective_role, stmt.from_table.name, "SELECT"
            )
            for j in stmt.joins:
                self.access_controller.enforce_permission(
                    effective_role, j.table.name, "SELECT"
                )

    def _build_from_joined_rows(
        self, stmt: UpdateStatement, effective_role: str
    ) -> List[Dict[str, Any]]:
        if not stmt.from_table:
            return []
        from_raw = self._query_knn_or_scan(stmt.from_table.name, None)
        curr = [self._prefix_record(r, stmt.from_table) for r in from_raw]
        for j in stmt.joins:
            curr = self._join_table_rows(curr, j, effective_role, {})
        return curr

    def _match_update_from_row(
        self,
        base_meta: Dict[str, Any],
        table_ref: TableRef,
        joined_rows: List[Dict[str, Any]],
        where_clauses: List[Dict[str, Any]],
    ) -> Optional[Dict[str, Any]]:
        prefixed_base = self._prefix_record(base_meta, table_ref)
        for j_row in joined_rows:
            combined = {**j_row, **prefixed_base}
            if _matches_where_clause(combined, where_clauses):
                return combined
        return None

    def _compute_update_assignments(
        self,
        stmt: UpdateStatement,
        eval_ctx: Dict[str, Any],
    ) -> Dict[str, Any]:
        applied: Dict[str, Any] = {}
        for col, expr in stmt.raw_assignments.items():
            if expr == "?" and col in stmt.assignments:
                applied[col] = stmt.assignments[col]
            else:
                applied[col] = _extract_field_value(eval_ctx, expr)
        return applied

    def _apply_single_update(
        self,
        table: TableCatalog,
        idx: int,
        stmt: UpdateStatement,
        eval_ctx: Dict[str, Any],
        effective_role: str,
    ) -> Dict[str, Any]:
        meta = table.storage.metadata[idx]
        old_rec = dict(meta)
        if self.tx_manager.is_active:
            self.tx_manager.record_undo(
                "UPDATE", stmt.table_name, {"idx": idx, "old_row": old_rec}
            )
        self._fire_triggers(
            "BEFORE", "UPDATE", stmt.table_name, old_rec, effective_role
        )
        assignments = (
            self._compute_update_assignments(stmt, eval_ctx)
            if stmt.raw_assignments
            else stmt.assignments
        )
        _check_generated_column_writes(table, list(assignments.keys()))
        new_rec = dict(meta)
        new_rec.update(assignments)
        _compute_generated_columns(table, new_rec)
        if table.strict:
            _validate_strict_row(table.name, table.schema, new_rec)
        meta.clear()
        meta.update(new_rec)
        self._apply_single_update_cascades(
            stmt.table_name, old_rec, new_rec, effective_role
        )
        self._fire_triggers("AFTER", "UPDATE", stmt.table_name, new_rec, effective_role)
        return new_rec

    def _exec_update_standard(
        self, table: TableCatalog, stmt: UpdateStatement, effective_role: str
    ) -> List[Dict[str, Any]]:
        indices = self._find_update_indices(table, stmt)
        updated: List[Dict[str, Any]] = []
        for i in indices:
            meta = table.storage.metadata[i]
            ctx = dict(meta)
            updated.append(
                self._apply_single_update(table, i, stmt, ctx, effective_role)
            )
        return updated

    def _iterate_update_from_rows(
        self,
        table: TableCatalog,
        stmt: UpdateStatement,
        t_ref: TableRef,
        joined_rows: List[Dict[str, Any]],
        role: str,
    ) -> List[Dict[str, Any]]:
        updated: List[Dict[str, Any]] = []
        for i, meta in enumerate(table.storage.metadata):
            match_ctx = self._match_update_from_row(
                meta, t_ref, joined_rows, stmt.where_clauses
            )
            if match_ctx is not None:
                updated.append(
                    self._apply_single_update(table, i, stmt, match_ctx, role)
                )
                if stmt.limit is not None and len(updated) >= stmt.limit:
                    break
        return updated

    def _exec_update_with_from(
        self, table: TableCatalog, stmt: UpdateStatement, effective_role: str
    ) -> List[Dict[str, Any]]:
        assert stmt.from_table is not None
        joined_rows = self._build_from_joined_rows(stmt, effective_role)
        t_ref = TableRef(name=stmt.table_name)
        return self._iterate_update_from_rows(
            table, stmt, t_ref, joined_rows, effective_role
        )

    def _apply_view_update_triggers(
        self,
        trig: CreateTriggerStatement,
        matching_rows: List[Dict[str, Any]],
        assignments: Dict[str, Any],
        effective_role: str,
    ) -> None:
        for old_rec in matching_rows:
            new_rec = dict(old_rec)
            new_rec.update(assignments)
            self._fire_single_trigger(
                trig, role=effective_role, new_record=new_rec, old_record=old_rec
            )

    @staticmethod
    def _filter_view_rows(
        rows: List[Dict[str, Any]], where_clauses: List[Any]
    ) -> List[Dict[str, Any]]:
        if not where_clauses:
            return rows
        return [r for r in rows if _matches_where_clause(r, where_clauses)]

    def _exec_update_view(
        self, stmt: UpdateStatement, vstmt: CreateViewStatement, effective_role: str
    ) -> Dict[str, Any]:
        trig = self._find_instead_of_trigger(stmt.table_name, "UPDATE")
        if not trig:
            raise SQLExecutionError(f"cannot modify view '{stmt.table_name}'")
        v_res = self._exec_view_select(vstmt, effective_role)
        matching = self._filter_view_rows(v_res.get("rows", []), stmt.where_clauses)
        self._apply_view_update_triggers(
            trig, matching, stmt.assignments, effective_role
        )
        return {
            "command": "UPDATE",
            "status": "ok",
            "updated_count": len(matching),
        }

    def _exec_update_table(
        self, stmt: UpdateStatement, effective_role: str
    ) -> Dict[str, Any]:
        self._validate_index_hint(stmt.table_name, stmt.indexed_by)
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "UPDATE"
        )
        self._enforce_update_from_perms(stmt, effective_role)
        table = self._get_table(stmt.table_name)
        if stmt.from_table:
            updated_records = self._exec_update_with_from(table, stmt, effective_role)
        else:
            updated_records = self._exec_update_standard(table, stmt, effective_role)

        if updated_records:
            table.invalidate_unique_sets()
            if not self.tx_manager.is_active:
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

    def _exec_update(
        self, stmt: UpdateStatement, effective_role: str
    ) -> Dict[str, Any]:
        vstmt = self._find_view(stmt.table_name)
        if vstmt:
            return self._exec_update_view(stmt, vstmt, effective_role)
        return self._exec_update_table(stmt, effective_role)

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
        where_conds = _enrich_where_clauses_with_collations(
            stmt.where_clauses, table.column_collations
        )
        matching = [
            idx
            for idx, meta in enumerate(table.storage.metadata)
            if not where_conds or _matches_where_clause(meta, where_conds)
        ]
        limited = self._sort_and_limit_indices(
            table.storage.metadata,
            matching,
            stmt.order_by,
            stmt.order_desc,
            stmt.limit,
        )
        return set(limited)

    def _fire_record_list_triggers(
        self,
        records: List[Dict[str, Any]],
        timing: str,
        event: str,
        table_name: str,
        role: str,
    ) -> None:
        for r in records:
            self._fire_triggers(timing, event, table_name, r, role)

    def _persist_deleted_state(
        self,
        table: TableCatalog,
        new_vecs: List[Any],
        new_meta: List[Dict[str, Any]],
        has_deleted: bool,
    ) -> None:
        if has_deleted:
            table.invalidate_unique_sets()
            if not self.tx_manager.is_active:
                table.storage.write_all(new_vecs, new_meta)
                if table.index is not None:
                    table.index = HNSWIndex(dim=table.storage.dim)
                    table.index.build_from_storage(new_vecs)

    def _find_child_foreign_keys(
        self, parent_table_name: str
    ) -> List[Tuple[TableCatalog, ForeignKeyDef]]:
        results: List[Tuple[TableCatalog, ForeignKeyDef]] = []
        for tcat in self.tables.values():
            for fk in tcat.foreign_keys:
                if fk.parent_table.lower() == parent_table_name.lower():
                    results.append((tcat, fk))
        return results

    def _cascade_delete_for_fk(
        self,
        child_cat: TableCatalog,
        fk: ForeignKeyDef,
        parent_val: Any,
        role: str,
        visited: Set[Tuple[str, Any]],
    ) -> None:
        action = fk.on_delete.upper()
        if action == "NO ACTION":
            return
        val_str = f"'{parent_val}'" if isinstance(parent_val, str) else str(parent_val)
        if action == "CASCADE":
            del_sql = (
                f"DELETE FROM {child_cat.name} WHERE {fk.child_column} = {val_str};"
            )
            self.execute(del_sql, role=role)
        elif action == "SET NULL":
            upd_sql = (
                f"UPDATE {child_cat.name} SET {fk.child_column} = NULL "
                f"WHERE {fk.child_column} = {val_str};"
            )
            self.execute(upd_sql, role=role)

    def _cascade_delete_record(
        self,
        rec: Dict[str, Any],
        child_refs: List[Tuple[TableCatalog, ForeignKeyDef]],
        role: str,
        visited: Set[Tuple[str, Any]],
    ) -> None:
        for child_cat, fk in child_refs:
            parent_val = rec.get(fk.parent_column)
            if parent_val is None:
                continue
            key = (child_cat.name.lower(), parent_val)
            if key in visited:
                continue
            visited.add(key)
            self._cascade_delete_for_fk(child_cat, fk, parent_val, role, visited)

    def _check_fk_restrict_match(
        self, child_cat: TableCatalog, fk: ForeignKeyDef, rec: Dict[str, Any]
    ) -> None:
        parent_val = rec.get(fk.parent_column)
        if parent_val is None:
            return
        for m in child_cat.storage.metadata:
            if str(m.get(fk.child_column)) == str(parent_val):
                raise SQLExecutionError(
                    f"FOREIGN KEY constraint failed: cannot delete from '{fk.parent_table}' "
                    f"due to RESTRICT reference in '{child_cat.name}'"
                )

    def _check_fk_restrict_for_ref(
        self, child_cat: TableCatalog, fk: ForeignKeyDef, deleted: List[Dict[str, Any]]
    ) -> None:
        if fk.on_delete.upper() == "RESTRICT":
            for rec in deleted:
                self._check_fk_restrict_match(child_cat, fk, rec)

    def _validate_fk_delete_restrict(
        self, parent_table_name: str, deleted: List[Dict[str, Any]]
    ) -> None:
        if not self.foreign_keys_enabled or not deleted:
            return
        for child_cat, fk in self._find_child_foreign_keys(parent_table_name):
            self._check_fk_restrict_for_ref(child_cat, fk, deleted)

    def _apply_fk_delete_cascades(
        self,
        parent_table_name: str,
        deleted_records: List[Dict[str, Any]],
        role: str,
    ) -> None:
        if not self.foreign_keys_enabled or not deleted_records:
            return
        child_refs = self._find_child_foreign_keys(parent_table_name)
        if not child_refs:
            return
        visited: Set[Tuple[str, Any]] = set()
        for rec in deleted_records:
            self._cascade_delete_record(rec, child_refs, role, visited)

    def _execute_fk_update_action(
        self,
        child_name: str,
        child_col: str,
        action: str,
        old_str: str,
        new_str: str,
        role: str,
    ) -> None:
        if action == "CASCADE":
            upd_sql = (
                f"UPDATE {child_name} SET {child_col} = {new_str} "
                f"WHERE {child_col} = {old_str};"
            )
            self.execute(upd_sql, role=role)
        elif action == "SET NULL":
            upd_sql = (
                f"UPDATE {child_name} SET {child_col} = NULL "
                f"WHERE {child_col} = {old_str};"
            )
            self.execute(upd_sql, role=role)

    @staticmethod
    def _has_fk_matching_row(table: TableCatalog, col: str, val: Any) -> bool:
        s_val = str(val)
        return any(str(m.get(col)) == s_val for m in table.storage.metadata)

    def _cascade_update_for_fk(
        self,
        child_cat: TableCatalog,
        fk: ForeignKeyDef,
        old_val: Any,
        new_val: Any,
        role: str,
    ) -> None:
        action = fk.on_update.upper()
        if action == "NO ACTION":
            return
        if not self._has_fk_matching_row(child_cat, fk.child_column, old_val):
            return
        if action == "RESTRICT":
            raise SQLExecutionError(
                f"FOREIGN KEY constraint failed: cannot update '{fk.parent_table}' "
                f"due to RESTRICT reference in '{child_cat.name}'"
            )
        old_str = self._format_trigger_val(old_val)
        new_str = self._format_trigger_val(new_val)
        self._execute_fk_update_action(
            child_cat.name, fk.child_column, action, old_str, new_str, role
        )

    def _apply_single_fk_update(
        self,
        child_cat: TableCatalog,
        fk: ForeignKeyDef,
        old_rec: Dict[str, Any],
        new_rec: Dict[str, Any],
        role: str,
    ) -> None:
        old_val = old_rec.get(fk.parent_column)
        new_val = new_rec.get(fk.parent_column)
        if old_val is not None and old_val != new_val:
            self._cascade_update_for_fk(child_cat, fk, old_val, new_val, role)

    def _apply_single_update_cascades(
        self,
        parent_table_name: str,
        old_rec: Dict[str, Any],
        new_rec: Dict[str, Any],
        role: str,
    ) -> None:
        if not self.foreign_keys_enabled:
            return
        child_refs = self._find_child_foreign_keys(parent_table_name)
        for child_cat, fk in child_refs:
            self._apply_single_fk_update(child_cat, fk, old_rec, new_rec, role)

    def _apply_view_delete_triggers(
        self,
        trig: CreateTriggerStatement,
        matching_rows: List[Dict[str, Any]],
        effective_role: str,
    ) -> None:
        for old_rec in matching_rows:
            self._fire_single_trigger(trig, role=effective_role, old_record=old_rec)

    def _exec_delete_view(
        self, stmt: DeleteStatement, vstmt: CreateViewStatement, effective_role: str
    ) -> Dict[str, Any]:
        trig = self._find_instead_of_trigger(stmt.table_name, "DELETE")
        if not trig:
            raise SQLExecutionError(f"cannot modify view '{stmt.table_name}'")
        v_res = self._exec_view_select(vstmt, effective_role)
        matching = self._filter_view_rows(v_res.get("rows", []), stmt.where_clauses)
        self._apply_view_delete_triggers(trig, matching, effective_role)
        return {
            "command": "DELETE",
            "status": "ok",
            "deleted_count": len(matching),
        }

    def _record_delete_undo(
        self, table_name: str, table: TableCatalog, deleted: bool
    ) -> None:
        if self.tx_manager.is_active and deleted:
            self.tx_manager.record_undo(
                "DELETE",
                table_name,
                {
                    "all_meta": [dict(m) for m in table.storage.metadata],
                    "all_vecs": table.storage.get_all_vectors(),
                },
            )

    def _exec_delete(
        self, stmt: DeleteStatement, effective_role: str
    ) -> Dict[str, Any]:
        vstmt = self._find_view(stmt.table_name)
        if vstmt:
            return self._exec_delete_view(stmt, vstmt, effective_role)
        self._validate_index_hint(stmt.table_name, stmt.indexed_by)
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "DELETE"
        )
        table = self._get_table(stmt.table_name)
        del_indices = self._find_delete_indices(table, stmt)
        new_vecs, new_meta, deleted = self._split_live_and_deleted(
            table.storage, del_indices
        )
        self._record_delete_undo(stmt.table_name, table, bool(deleted))

        self._validate_fk_delete_restrict(stmt.table_name, deleted)
        self._fire_record_list_triggers(
            deleted, "BEFORE", "DELETE", stmt.table_name, effective_role
        )
        self._persist_deleted_state(table, new_vecs, new_meta, bool(deleted))
        self._apply_fk_delete_cascades(stmt.table_name, deleted, effective_role)
        self._fire_record_list_triggers(
            deleted, "AFTER", "DELETE", stmt.table_name, effective_role
        )

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
        if isinstance(stmt, CreateVirtualTableStatement):
            return self._exec_create_virtual_table(stmt, role)
        if isinstance(stmt, CreateTableStatement):
            return self._exec_create_table(stmt, role)
        if isinstance(stmt, DropTableStatement):
            return self._exec_drop_table(stmt, role)
        if isinstance(stmt, AlterTableStatement):
            return self._exec_alter_table(stmt, role)
        return None

    def _parse_single_module_arg(
        self, arg: str, location: Optional[str], kwargs: Dict[str, Any]
    ) -> Optional[str]:
        if "=" in arg:
            k, v = arg.split("=", 1)
            k, v = k.strip().lower(), v.strip().strip("'\"")
            if k in ("path", "location", "file", "filename", "file_path", "root_dir"):
                return v
            kwargs[k] = v
            return location
        val = arg.strip("'\"")
        if location is None:
            return val
        kwargs[f"arg_{len(kwargs)}"] = val
        return location

    def _parse_vtab_kv_arg(
        self, clean: str, loc: Optional[str], kwargs: Dict[str, Any]
    ) -> Optional[str]:
        k, v = clean.split("=", 1)
        k, v = k.strip().lower(), v.strip().strip("'\"")
        if k in ("path", "location", "file", "filename", "file_path", "root_dir"):
            return v
        kwargs[k] = v
        return loc

    def _parse_single_vtab_arg(
        self,
        clean: str,
        is_fts5: bool,
        loc: Optional[str],
        kwargs: Dict[str, Any],
        cols: List[str],
    ) -> Optional[str]:
        if "=" in clean:
            return self._parse_vtab_kv_arg(clean, loc, kwargs)
        if is_fts5:
            cols.append(clean.split()[0].strip("'\""))
            return loc
        return self._parse_single_module_arg(clean, loc, kwargs)

    def _parse_virtual_module_args(
        self, raw_args: List[str], module_name: str = ""
    ) -> Tuple[Optional[str], Dict[str, Any]]:
        loc: Optional[str] = None
        kwargs: Dict[str, Any] = {}
        cols: List[str] = []
        is_fts5 = module_name.lower() == "fts5"
        for raw in raw_args:
            clean = raw.strip()
            if clean:
                loc = self._parse_single_vtab_arg(clean, is_fts5, loc, kwargs, cols)
        if cols:
            kwargs["columns"] = cols
        return loc, kwargs

    @staticmethod
    def _schema_from_fieldnames(storage: Any) -> Dict[str, str]:
        fn = getattr(storage, "fieldnames", None)
        names = fn() if callable(fn) else fn
        return {col: "TEXT" for col in names} if names else {}

    @classmethod
    def _resolve_vtab_schema(cls, storage: Any) -> Dict[str, str]:
        schema = getattr(storage, "schema", None)
        if isinstance(schema, dict):
            return dict(schema)
        return cls._schema_from_fieldnames(storage)

    def _exec_create_virtual_table(
        self, stmt: CreateVirtualTableStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "CREATE_TABLE"
        )
        if stmt.table_name in self.tables:
            if stmt.if_not_exists:
                return {
                    "command": "CREATE_VIRTUAL_TABLE",
                    "status": "ok",
                    "message": f"Table '{stmt.table_name}' already exists (skipped)",
                }
            raise SQLExecutionError(f"Table '{stmt.table_name}' already exists.")

        from database.storage.factory import StorageEngineFactory

        location, kwargs = self._parse_virtual_module_args(
            stmt.module_args, stmt.module_name
        )
        kwargs.setdefault("dim", self.embedding.dim)
        kwargs.setdefault("table_name", stmt.table_name)

        storage = StorageEngineFactory.create_by_engine_name(
            stmt.module_name, location=location, **kwargs
        )
        schema = self._resolve_vtab_schema(storage)

        catalog = TableCatalog(
            name=stmt.table_name,
            storage=storage,
            schema=schema,
            raw_sql=stmt.raw_sql,
            storage_engine=stmt.module_name,
            location=location,
        )
        self.tables[stmt.table_name] = catalog

        return {
            "command": "CREATE_VIRTUAL_TABLE",
            "status": "ok",
            "table": stmt.table_name,
            "module": stmt.module_name,
        }

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

    def _exec_schema_trigger_stmt(
        self, stmt: SQLStatement, role: str
    ) -> Optional[Dict[str, Any]]:
        if isinstance(stmt, CreateTriggerStatement):
            return self._exec_create_trigger(stmt, role)
        if isinstance(stmt, DropTriggerStatement):
            return self._exec_drop_trigger(stmt, role)
        return None

    def _exec_schema_stmt(
        self, stmt: SQLStatement, role: str
    ) -> Optional[Dict[str, Any]]:
        return (
            self._exec_schema_table_stmt(stmt, role)
            or self._exec_schema_index_stmt(stmt, role)
            or self._exec_schema_view_stmt(stmt, role)
            or self._exec_schema_trigger_stmt(stmt, role)
        )

    def _exec_mount_stmt(
        self, stmt: SQLStatement, role: str
    ) -> Optional[Dict[str, Any]]:
        if isinstance(stmt, AttachStatement):
            return self._exec_attach(stmt, role)
        if isinstance(stmt, DetachStatement):
            return self._exec_detach(stmt, role)
        return None

    def _exec_admin_stmt(
        self, stmt: SQLStatement, role: str
    ) -> Optional[Dict[str, Any]]:
        if isinstance(stmt, PragmaStatement):
            return self._exec_pragma(stmt, role)
        if isinstance(stmt, VacuumStatement):
            return self._exec_vacuum(stmt, role)
        if isinstance(stmt, AnalyzeStatement):
            return self._exec_analyze(stmt, role)
        return self._exec_mount_stmt(stmt, role)

    def _validate_attach_schema(self, schema: str) -> None:
        if schema.lower() in ("main", "temp"):
            raise SQLExecutionError(f"cannot attach to reserved schema name '{schema}'")
        if schema in self.attached_databases:
            raise SQLExecutionError(f"database {schema} is already attached")

    def _init_attached_storage(self, file_path: str) -> MultiTableVectorStorage:
        storage = MultiTableVectorStorage(file_path=file_path)
        if file_path != ":memory:" and os.path.exists(file_path):
            try:
                storage.load()
            except Exception as e:
                logger.warning("Could not load attached DB %s: %s", file_path, e)
        return storage

    def _exec_attach(self, stmt: AttachStatement, role: str) -> Dict[str, Any]:
        schema = stmt.schema_name
        self._validate_attach_schema(schema)
        storage = self._init_attached_storage(stmt.filename)
        self.attached_databases[schema] = {
            "file": stmt.filename,
            "storage": storage,
            "tables": {},
        }
        self.known_databases[schema] = stmt.filename
        return {"command": "ATTACH", "status": "ok", "rows": [], "count": 0}

    def _validate_detach_schema(self, schema: str) -> None:
        if schema.lower() in ("main", "temp"):
            raise SQLExecutionError(f"cannot detach schema '{schema}'")
        if schema not in self.attached_databases:
            raise SQLExecutionError(f"no such database: {schema}")

    def _flush_attached_storage(self, storage: Any) -> None:
        if storage is not None and hasattr(storage, "save"):
            try:
                storage.save()
            except Exception:
                pass

    def _purge_schema_tables(self, schema: str) -> None:
        prefix = f"{schema}."
        for k in list(self.tables.keys()):
            if k.startswith(prefix):
                del self.tables[k]

    def _cleanup_detached_db(self, schema: str) -> None:
        db_info = self.attached_databases.pop(schema)
        self.known_databases.pop(schema, None)
        self._flush_attached_storage(db_info.get("storage"))
        self._purge_schema_tables(schema)

    def _exec_detach(self, stmt: DetachStatement, role: str) -> Dict[str, Any]:
        schema = stmt.schema_name
        self._validate_detach_schema(schema)
        self._cleanup_detached_db(schema)
        return {"command": "DETACH", "status": "ok", "rows": [], "count": 0}

    def _exec_dcl_stmt(self, stmt: SQLStatement, role: str) -> Optional[Dict[str, Any]]:
        if isinstance(stmt, GrantStatement):
            return self._exec_grant(stmt, role)
        if isinstance(stmt, RevokeStatement):
            return self._exec_revoke(stmt, role)
        return None

    def _exec_security_or_schema(
        self, stmt: SQLStatement, role: str
    ) -> Optional[Dict[str, Any]]:
        sub_res = self._exec_admin_stmt(stmt, role) or self._exec_dcl_stmt(stmt, role)
        if sub_res is not None:
            return sub_res
        if isinstance(stmt, ExplainStatement):
            return self._exec_explain(stmt, role)
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
        all_dbs: List[str] = list(self.known_databases.keys())
        for att_name in sorted(self.attached_databases.keys()):
            if att_name not in all_dbs:
                all_dbs.append(att_name)
        db_rows = [{"Database": d} for d in all_dbs]
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
            SQLCommandType.SAVEPOINT,
            SQLCommandType.RELEASE,
            SQLCommandType.ROLLBACK_TO,
        ):
            return self._exec_tcl(stmt)

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

    def _lookup_attached_by_schema(
        self, schema: str, tbl: str, table_name: str
    ) -> Optional[TableCatalog]:
        if schema.lower() == "main":
            return self.tables.get(tbl) or self._lookup_multi_storage_table(tbl)
        if schema not in self.attached_databases:
            raise SQLExecutionError(f"unknown database {schema}")
        db_storage = self.attached_databases[schema]["storage"]
        if db_storage.has_table(tbl):
            st = db_storage.get_table(tbl)
            catalog = TableCatalog(name=table_name, storage=st)
            self.tables[table_name] = catalog
            return catalog
        return None

    def _lookup_attached_table(self, table_name: str) -> Optional[TableCatalog]:
        if "." in table_name:
            schema, tbl = table_name.split(".", 1)
            return self._lookup_attached_by_schema(schema, tbl, table_name)
        for name, info in self.attached_databases.items():
            db_storage = info["storage"]
            if db_storage.has_table(table_name):
                st = db_storage.get_table(table_name)
                catalog = TableCatalog(name=table_name, storage=st)
                self.tables[table_name] = catalog
                return catalog
        return None

    def _get_table(self, table_name: str) -> TableCatalog:
        table = self.tables.get(table_name)
        if table:
            return table
        catalog = self._lookup_multi_storage_table(
            table_name
        ) or self._lookup_attached_table(table_name)
        if catalog is not None:
            return catalog
        raise SQLExecutionError(f"Table '{table_name}' does not exist")
