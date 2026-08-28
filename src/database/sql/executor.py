#!/usr/bin/env python3
"""
SQL Execution Engine for Pure Python Vector Database.
Evaluates DDL, DQL, DML, DCL, and TCL AST nodes against underlying vector storages and schemas.
"""

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
    CreateIndexStatement,
    CreateTableStatement,
    DeleteStatement,
    DropTableStatement,
    ExplainStatement,
    GrantStatement,
    InsertStatement,
    JoinType,
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


class SQLExecutionError(Exception):
    """Raised when SQL execution fails."""

    pass


class TableCatalog:
    """Represents in-memory and on-disk catalog for a database table."""

    def __init__(
        self,
        name: str,
        storage: VectorStorage,
        index: Optional[HNSWIndex] = None,
        schema: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.name = name
        self.storage = storage
        self.index = index or HNSWIndex(dim=storage.dim)
        self.schema = schema or {}
        self.btree_indexes: Dict[str, BPlusTree] = {}
        self.btree_index_names: Dict[str, str] = {}
        self.stats: TableStats = TableStats(name)
        self.recompute_stats()

    def recompute_stats(self) -> None:
        """Refreshes catalog statistics from storage metadata."""
        if self.storage and self.storage.metadata:
            self.stats.analyze_from_metadata(self.storage.metadata)


class SQLExecutor:
    """
    Coordinates SQL parsing, access control enforcement, transaction staging,
    and storage execution.
    Supports Advanced SQL: Multi-table JOINs, CTE (WITH RECURSIVE), JSON operators, and Projections.
    """

    def __init__(
        self,
        default_storage: Optional[VectorStorage] = None,
        default_index: Optional[HNSWIndex] = None,
        embedding: Optional[DeterministicEmbedding] = None,
        catalog: Optional[TableCatalog] = None,
        access_controller: Optional[AccessController] = None,
        tx_manager: Optional[TransactionManager] = None,
    ) -> None:
        self.parser = SQLParser()
        self.access_controller = access_controller or AccessController()
        self.tx_manager = tx_manager or TransactionManager()
        self.embedding = embedding or DeterministicEmbedding(dim=128)

        # Default tables
        self.tables: Dict[str, TableCatalog] = {}
        if catalog is not None:
            self.tables[catalog.name] = catalog
        elif default_storage:
            table_name = "papers"
            self.tables[table_name] = TableCatalog(
                name=table_name,
                storage=default_storage,
                index=default_index or HNSWIndex(dim=default_storage.dim),
            )

    def execute(
        self,
        sql: str,
        role: Optional[str] = None,
        params: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Parses and executes a raw SQL statement with RBAC enforcement and TCL support.
        """
        effective_role = role or self.access_controller.current_role
        logger.info("⚡ [SQL Exec] [%s] %s", effective_role, sql.strip())
        try:
            print(f"⚡ [SQL Exec] [{effective_role}] {sql.strip()}", flush=True)
        except OSError:
            pass
        stmt = self.parser.parse(sql)
        return self.execute_statement(stmt, role=effective_role)

    def _extract_literal(self, expr: str) -> Optional[Any]:
        if (expr.startswith("'") and expr.endswith("'")) or (
            expr.startswith('"') and expr.endswith('"')
        ):
            return expr[1:-1]
        if expr.isdigit():
            return int(expr)
        try:
            val_f = float(expr)
            if "." in expr:
                return val_f
        except ValueError:
            pass
        return None

    def _extract_arithmetic(self, record: Dict[str, Any], expr: str) -> Optional[Any]:
        arith_m = re.match(r"^([a-zA-Z0-9_\.\->>\'\"]+)\s*([\+\-])\s*([0-9]+)$", expr)
        if not arith_m:
            return None
        base_col = arith_m.group(1).strip()
        op = arith_m.group(2)
        num = int(arith_m.group(3))
        base_val = self._extract_field_value(record, base_col)
        try:
            base_num = int(base_val) if base_val is not None else 0
            return base_num + num if op == "+" else base_num - num
        except (ValueError, TypeError):
            return base_val

    def _parse_json_field(self, raw_obj: Any) -> Optional[Dict[str, Any]]:
        if isinstance(raw_obj, str):
            try:
                raw_obj = json.loads(raw_obj)
            except Exception:
                return None
        return raw_obj if isinstance(raw_obj, dict) else None

    def _extract_json_op(self, record: Dict[str, Any], expr: str) -> Optional[Any]:
        json_unquote = "->>" in expr
        json_extract = "->" in expr
        if not (json_unquote or json_extract):
            return None
        op_delim = "->>" if json_unquote else "->"
        col_part, path_part = expr.split(op_delim, 1)
        col_part = col_part.strip()
        path_key = path_part.strip().strip("'\"")

        raw_obj = record.get(col_part)
        if raw_obj is None and "." in col_part:
            _, unqualified = col_part.split(".", 1)
            raw_obj = record.get(unqualified)

        dict_obj = self._parse_json_field(raw_obj)
        if dict_obj:
            val = dict_obj.get(path_key)
            if val is not None:
                return str(val) if json_unquote else val
        return None

    def _extract_field_value(self, record: Dict[str, Any], expr: str) -> Any:
        """
        Extracts value from record supporting dot qualification and JSON operators.
        """
        if not expr:
            return None
        expr = expr.strip()

        lit = self._extract_literal(expr)
        if lit is not None:
            return lit

        arith = self._extract_arithmetic(record, expr)
        if arith is not None:
            return arith

        if "->" in expr or "->>" in expr:
            return self._extract_json_op(record, expr)

        if expr in record:
            return record[expr]

        if "." in expr:
            _, unqualified = expr.split(".", 1)
            if unqualified in record:
                return record[unqualified]

        return None

    def _eval_relational(self, op: str, actual: Any, expected: Any) -> bool:
        try:
            act_f, exp_f = float(str(actual)), float(str(expected))
            if op == ">=":
                return act_f >= exp_f
            if op == "<=":
                return act_f <= exp_f
            if op == ">":
                return act_f > exp_f
            if op == "<":
                return act_f < exp_f
        except (ValueError, TypeError):
            act_s, exp_s = str(actual), str(expected)
            if op == ">=":
                return act_s >= exp_s
            if op == "<=":
                return act_s <= exp_s
            if op == ">":
                return act_s > exp_s
            if op == "<":
                return act_s < exp_s
        return False

    def _eval_like(self, actual: Any, expected: Any) -> bool:
        pattern = str(expected).replace("%", ".*")
        return bool(re.search(pattern, str(actual or ""), re.IGNORECASE))

    def _eval_membership(self, op: str, actual: Any, expected: Any) -> bool:
        in_list = expected if isinstance(expected, (list, tuple, set)) else [expected]
        is_member = (actual in in_list) or (str(actual) in [str(x) for x in in_list])
        return is_member if op == "IN" else not is_member

    def _eval_comparison(self, op: str, actual: Any, expected: Any) -> bool:
        if op == "=":
            return str(actual) == str(expected)
        if op == "!=":
            return str(actual) != str(expected)
        if actual is None:
            return False
        if op in (">=", "<=", ">", "<"):
            return self._eval_relational(op, actual, expected)
        if op == "LIKE":
            return self._eval_like(actual, expected)
        if op in ("IN", "NOT IN"):
            return self._eval_membership(op, actual, expected)
        return True

    def _matches_or_branches(
        self, record: Dict[str, Any], branches: List[Dict[str, Any]]
    ) -> bool:
        for branch in branches:
            sub_clauses = branch.get("clauses", [])
            if all(
                self._eval_comparison(
                    c.get("op") or c.get("operator") or "=",
                    self._extract_field_value(
                        record, c.get("field") or c.get("column") or ""
                    ),
                    c.get("value"),
                )
                for c in sub_clauses
            ):
                return True
        return False

    def _evaluate_single_condition(
        self, record: Dict[str, Any], c: Dict[str, Any]
    ) -> bool:
        field = c.get("field") or c.get("column") or ""
        op = c.get("op") or c.get("operator") or "="
        expected_val = c.get("value")

        actual = self._extract_field_value(record, field)

        if isinstance(expected_val, str) and (
            expected_val in record or "." in expected_val or "->" in expected_val
        ):
            col_val = self._extract_field_value(record, expected_val)
            if col_val is not None:
                expected_val = col_val

        return self._eval_comparison(op, actual, expected_val)

    def _matches_where_clause(
        self, record: Dict[str, Any], clauses: List[Dict[str, Any]]
    ) -> bool:
        """Evaluates WHERE conditions against a record dictionary."""
        if not clauses:
            return True

        if any(c.get("logic") == "OR_BRANCH" for c in clauses):
            return self._matches_or_branches(record, clauses)

        return all(self._evaluate_single_condition(record, c) for c in clauses)

    def _restore_rollback_snapshot(self, snapshot: Optional[Dict[str, Any]]) -> None:
        if not snapshot or not isinstance(snapshot, dict):
            return
        for tname, sdata in snapshot.items():
            if tname in self.tables:
                tcat = self.tables[tname]
                tcat.storage.metadata = [dict(m) for m in sdata.get("meta", [])]
                vecs = sdata.get("vecs", [])
                tcat.storage.write_all(vecs, tcat.storage.metadata)
                tcat.index = HNSWIndex(dim=tcat.storage.dim)
                tcat.index.build_from_storage(vecs)

    def _exec_tcl(self, cmd: SQLCommandType) -> Dict[str, Any]:
        if cmd == SQLCommandType.BEGIN:
            snapshot = {
                tname: {
                    "meta": [dict(m) for m in tcat.storage.metadata],
                    "vecs": tcat.storage.get_all_vectors(),
                }
                for tname, tcat in self.tables.items()
            }
            self.tx_manager.begin(snapshot)
            return {
                "command": "BEGIN",
                "status": "ok",
                "message": "Transaction started",
            }
        if cmd == SQLCommandType.COMMIT:
            mutations = self.tx_manager.commit()
            return {
                "command": "COMMIT",
                "status": "ok",
                "mutations_applied": len(mutations),
            }
        if cmd == SQLCommandType.ROLLBACK:
            snapshot_res = self.tx_manager.rollback()
            self._restore_rollback_snapshot(snapshot_res)
            return {
                "command": "ROLLBACK",
                "status": "ok",
                "mutations_reverted": 1,
            }
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

        storage_path = os.path.join("outputs", "database", f"{stmt.table_name}.vdb")
        os.makedirs(os.path.dirname(storage_path), exist_ok=True)
        if os.path.exists(storage_path):
            try:
                os.remove(storage_path)
            except OSError:
                pass
        storage = VectorStorage(file_path=storage_path, dim=self.embedding.dim)
        catalog = TableCatalog(
            name=stmt.table_name,
            storage=storage,
            schema={col.name: col.data_type for col in stmt.columns},
        )
        self.tables[stmt.table_name] = catalog
        return {
            "command": "CREATE_TABLE",
            "status": "ok",
            "table": stmt.table_name,
            "columns": len(stmt.columns),
        }

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
        storage_file = getattr(tcat.storage, "file_path", None) or getattr(
            tcat.storage, "storage_path", None
        )
        if storage_file and os.path.exists(storage_file):
            try:
                os.remove(storage_file)
            except OSError:
                pass
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

        return {
            "command": "CREATE_INDEX",
            "status": "ok",
            "index": stmt.index_name,
            "table": stmt.table_name,
            "column": stmt.column_name,
            "type": idx_type,
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
        return {
            "command": "EXPLAIN",
            "status": "ok",
            "rows": explain_rows,
        }

    def _query_knn_or_scan(
        self,
        table_name: str,
        knn_query: Optional[Dict[str, Any]],
        temporary_tables: Optional[Dict[str, List[Dict[str, Any]]]] = None,
    ) -> List[Dict[str, Any]]:
        if temporary_tables and table_name in temporary_tables:
            return [dict(r) for r in temporary_tables[table_name]]

        table = self._get_table(table_name)
        rows: List[Dict[str, Any]] = []
        if knn_query:
            query_vec = self.embedding.normalize(knn_query["vector"])
            for idx, sim in table.index.search(query_vec, top_k=knn_query["top_k"]):
                if idx < len(table.storage.metadata):
                    meta = dict(table.storage.get_metadata(idx))
                    meta["score"] = round(sim, 4)
                    meta["_idx"] = idx
                    rows.append(meta)
        else:
            for idx, meta in enumerate(table.storage.metadata):
                item = dict(meta)
                item["_idx"] = idx
                rows.append(item)
        return rows

    def _prefix_record(
        self, record: Dict[str, Any], table_ref: TableRef
    ) -> Dict[str, Any]:
        """Prefixes record keys with table name and alias for robust multi-table resolution."""
        prefixed: Dict[str, Any] = dict(record)
        name = table_ref.name
        alias = table_ref.alias

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
            matched = False
            for right_row in j_prefixed_rows:
                combined = {**left_row, **right_row}
                if self._matches_where_clause(combined, join.on_conditions):
                    next_rows.append(combined)
                    matched = True
            if not matched and join.join_type == JoinType.LEFT:
                empty_right = {
                    k: None
                    for k in (j_prefixed_rows[0].keys() if j_prefixed_rows else [])
                }
                next_rows.append({**left_row, **empty_right})
        return next_rows

    def _project_row(
        self, r: Dict[str, Any], columns: List[str], table_name: str
    ) -> Dict[str, Any]:
        if "*" in columns and len(columns) == 1:
            return {
                k: v
                for k, v in r.items()
                if "." not in k or k.startswith(f"{table_name}.")
            }
        projected = {}
        for col_expr in columns:
            col_expr = col_expr.strip()
            as_m = re.search(r"\s+AS\s+([a-zA-Z0-9_]+)$", col_expr, re.IGNORECASE)
            if as_m:
                out_key = as_m.group(1).strip()
                raw_col = col_expr[: as_m.start()].strip()
                projected[out_key] = self._extract_field_value(r, raw_col)
            else:
                out_key = col_expr
                if "." in out_key and "->" not in out_key:
                    _, out_key = out_key.split(".", 1)
                projected[out_key] = self._extract_field_value(r, col_expr)
        return projected

    def _sort_and_paginate(
        self,
        rows: List[Dict[str, Any]],
        order_by: Optional[str],
        order_desc: bool,
        limit: Optional[int],
    ) -> List[Dict[str, Any]]:
        result = rows
        if order_by:
            result.sort(
                key=lambda x: self._extract_field_value(x, order_by) or 0,
                reverse=order_desc,
            )
        if limit is not None:
            result = result[:limit]
        return result

    def _scan_and_join_tables(
        self,
        stmt: SelectStatement,
        effective_role: str,
        temp_tables: Dict[str, List[Dict[str, Any]]],
    ) -> List[Dict[str, Any]]:
        table_ref = stmt.table_ref or TableRef(name=stmt.table_name)
        if table_ref.name not in temp_tables:
            self.access_controller.enforce_permission(
                effective_role, table_ref.name, "SELECT"
            )

        raw_rows = self._query_knn_or_scan(
            table_ref.name, stmt.knn_query, temporary_tables=temp_tables
        )
        current_rows = [self._prefix_record(r, table_ref) for r in raw_rows]

        for join in stmt.joins or []:
            current_rows = self._join_table_rows(
                current_rows, join, effective_role, temp_tables
            )
        return current_rows

    def _exec_select(
        self,
        stmt: SelectStatement,
        effective_role: str,
        temporary_tables: Optional[Dict[str, List[Dict[str, Any]]]] = None,
    ) -> Dict[str, Any]:
        temp_tables = dict(temporary_tables or {})
        if stmt.ctes:
            self._evaluate_all_ctes(stmt.ctes, effective_role, temp_tables)

        current_rows = self._scan_and_join_tables(stmt, effective_role, temp_tables)

        filtered_rows = [
            r for r in current_rows if self._matches_where_clause(r, stmt.where_clauses)
        ]

        paged_rows = self._sort_and_paginate(
            filtered_rows, stmt.order_by, stmt.order_desc, stmt.limit
        )

        table_ref = stmt.table_ref or TableRef(name=stmt.table_name)
        final_rows = [
            self._project_row(r, stmt.columns, table_ref.name) for r in paged_rows
        ]

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

    def _exec_insert(
        self, stmt: InsertStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "INSERT"
        )
        table = self._get_table(stmt.table_name)
        col_val_map = dict(zip(stmt.columns, stmt.values))
        doc_id = str(col_val_map.get("id", len(table.storage.metadata)))

        raw_vec = col_val_map.get("vector")
        if not raw_vec and "text" in col_val_map:
            raw_vec = self.embedding.embed_text(str(col_val_map["text"]))
        elif not raw_vec:
            raw_vec = [0.0] * table.storage.dim

        vector = self.embedding.normalize(raw_vec)
        if self.tx_manager.is_active:
            self.tx_manager.stage_mutation(
                "INSERT", {"table": stmt.table_name, "data": col_val_map}
            )
        else:
            idx = table.storage.append(vector, col_val_map)
            table.index.add_item(idx, vector)

        return {
            "command": "INSERT",
            "status": "ok",
            "table": stmt.table_name,
            "id": doc_id,
            "inserted_count": 1,
        }

    def _exec_update(
        self, stmt: UpdateStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "UPDATE"
        )
        table = self._get_table(stmt.table_name)
        updated_count = 0
        for idx, meta in enumerate(table.storage.metadata):
            if self._matches_where_clause(meta, stmt.where_clauses):
                for k, v in stmt.assignments.items():
                    meta[k] = v
                updated_count += 1

        if updated_count > 0 and not self.tx_manager.is_active:
            table.storage.write_all(
                table.storage.get_all_vectors(), table.storage.metadata
            )

        return {"command": "UPDATE", "status": "ok", "updated_count": updated_count}

    def _exec_delete(
        self, stmt: DeleteStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "DELETE"
        )
        table = self._get_table(stmt.table_name)
        new_vecs: List[Tuple[float, ...]] = []
        new_meta: List[Dict[str, Any]] = []
        deleted_count = 0

        for idx, meta in enumerate(table.storage.metadata):
            if stmt.where_clauses and self._matches_where_clause(
                meta, stmt.where_clauses
            ):
                deleted_count += 1
            else:
                new_vecs.append(table.storage.get_vector(idx))
                new_meta.append(meta)

        if deleted_count > 0 and not self.tx_manager.is_active:
            table.storage.write_all(new_vecs, new_meta)
            table.index = HNSWIndex(dim=table.storage.dim)
            table.index.build_from_storage(new_vecs)

        return {"command": "DELETE", "status": "ok", "deleted_count": deleted_count}

    def _exec_security_or_schema(
        self, stmt: SQLStatement, role: str
    ) -> Optional[Dict[str, Any]]:
        if isinstance(stmt, ExplainStatement):
            return self._exec_explain(stmt, role)
        if isinstance(stmt, GrantStatement):
            return self._exec_grant(stmt, role)
        if isinstance(stmt, RevokeStatement):
            return self._exec_revoke(stmt, role)
        if isinstance(stmt, CreateTableStatement):
            return self._exec_create_table(stmt, role)
        if isinstance(stmt, DropTableStatement):
            return self._exec_drop_table(stmt, role)
        if isinstance(stmt, CreateIndexStatement):
            return self._exec_create_index(stmt, role)
        if isinstance(stmt, ShowStatement):
            return self._exec_show(stmt, role)
        return None

    def _exec_show(self, stmt: ShowStatement, effective_role: str) -> Dict[str, Any]:
        target = stmt.target.upper()
        if target in ("DATABASES", "SCHEMAS"):
            db_rows = [{"Database": "arxiv_security_db"}, {"Database": "main"}]
            return {
                "command": "SHOW",
                "status": "ok",
                "target": "DATABASES",
                "count": len(db_rows),
                "rows": db_rows,
            }

        table_rows = []
        for tname, tbl in sorted(self.tables.items()):
            if stmt.like_pattern and stmt.like_pattern not in tname:
                continue
            r_count = len(tbl.storage.metadata)
            f_size = (
                os.path.getsize(tbl.storage.file_path)
                if os.path.exists(tbl.storage.file_path)
                else 0
            )
            if target == "TABLE_STATUS":
                table_rows.append(
                    {
                        "Name": tname,
                        "Engine": "Pure Python Pager",
                        "Rows": r_count,
                        "Data_length": f_size,
                        "Create_time": "2026-08-28 00:00:00",
                    }
                )
            else:
                table_rows.append(
                    {
                        "Table": tname,
                        "Rows": r_count,
                        "Size_bytes": f_size,
                    }
                )

        return {
            "command": "SHOW",
            "status": "ok",
            "target": target,
            "count": len(table_rows),
            "rows": table_rows,
        }

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

        if isinstance(stmt, SelectStatement):
            return self._exec_select(stmt, effective_role)
        if isinstance(stmt, InsertStatement):
            return self._exec_insert(stmt, effective_role)
        if isinstance(stmt, UpdateStatement):
            return self._exec_update(stmt, effective_role)
        if isinstance(stmt, DeleteStatement):
            return self._exec_delete(stmt, effective_role)

        raise SQLExecutionError(f"Unhandled statement type: {cmd}")

    def _get_table(self, table_name: str) -> TableCatalog:
        table = self.tables.get(table_name)
        if not table:
            raise SQLExecutionError(f"Table '{table_name}' does not exist")
        return table
