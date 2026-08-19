#!/usr/bin/env python3
"""
SQL Execution Engine for Pure Python Vector Database.
Evaluates DDL, DQL, DML, DCL, and TCL AST nodes against underlying vector storages and schemas.
"""

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
    RevokeStatement,
    SelectStatement,
    SQLCommandType,
    SQLStatement,
    UpdateStatement,
)
from .parser import SQLParser
from .security import AccessController
from .transaction import TransactionManager


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
        stmt = self.parser.parse(sql)
        return self.execute_statement(stmt, role=effective_role)

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
                    record.get(c.get("field") or c.get("column") or ""),
                    c.get("value"),
                )
                for c in sub_clauses
            ):
                return True
        return False

    def _matches_where_clause(
        self, record: Dict[str, Any], clauses: List[Dict[str, Any]]
    ) -> bool:
        """Evaluates WHERE conditions against a record dictionary."""
        if not clauses:
            return True

        if any(c.get("logic") == "OR_BRANCH" for c in clauses):
            return self._matches_or_branches(record, clauses)

        for c in clauses:
            field = c.get("field") or c.get("column") or ""
            op = c.get("op") or c.get("operator") or "="
            val = c.get("value")
            actual = record.get(field)
            if not self._eval_comparison(op, actual, val):
                return False
        return True

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

    def _determine_table_dim(self, columns: List[Any]) -> int:
        for col in columns:
            if col.data_type.upper().startswith("VECTOR"):
                m = re.search(r"VECTOR\(([0-9]+)\)", col.data_type.upper())
                if m:
                    return int(m.group(1))
        return 128

    def _exec_create_table(
        self, stmt: CreateTableStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "ADMIN"
        )
        if stmt.table_name in self.tables and not stmt.if_not_exists:
            raise SQLExecutionError(f"Table '{stmt.table_name}' already exists")

        dim = self._determine_table_dim(stmt.columns)
        base_dir = "outputs/database"
        if self.tables:
            first_table = next(iter(self.tables.values()))
            if first_table.storage and first_table.storage.file_path:
                base_dir = os.path.dirname(first_table.storage.file_path)

        storage_path = os.path.join(base_dir, f"{stmt.table_name}.vdb")
        if os.path.exists(storage_path):
            try:
                os.remove(storage_path)
            except Exception:
                pass
        storage = VectorStorage(storage_path, dim=dim)
        self.tables[stmt.table_name] = TableCatalog(
            name=stmt.table_name,
            storage=storage,
            index=HNSWIndex(dim=dim),
            schema={"columns": [col.name for col in stmt.columns]},
        )
        return {
            "command": "CREATE_TABLE",
            "status": "ok",
            "table": stmt.table_name,
            "dimension": dim,
        }

    def _exec_drop_table(
        self, stmt: DropTableStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "ADMIN"
        )
        if stmt.table_name not in self.tables:
            if not stmt.if_exists:
                raise SQLExecutionError(f"Table '{stmt.table_name}' not found")
            return {"command": "DROP_TABLE", "status": "ok", "dropped": False}

        del self.tables[stmt.table_name]
        return {"command": "DROP_TABLE", "status": "ok", "dropped": True}

    def _build_btree_index(self, table: TableCatalog, col_name: str) -> BPlusTree:
        btree = BPlusTree(column_name=col_name)
        for row_id, meta in enumerate(table.storage.metadata):
            val = meta.get(col_name)
            if val is not None and isinstance(val, (int, float, str)):
                btree.insert(val, row_id)
        return btree

    def _exec_create_index(
        self, stmt: CreateIndexStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "ADMIN"
        )
        table = self._get_table(stmt.table_name)
        idx_type = stmt.index_type.upper()
        if idx_type == "BTREE":
            btree = self._build_btree_index(table, stmt.column_name)
            table.btree_indexes[stmt.column_name] = btree
            table.btree_index_names[stmt.column_name] = stmt.index_name
        else:
            table.index = HNSWIndex(dim=table.storage.dim)
            table.index.build_from_storage(table.storage.get_all_vectors())
        return {
            "command": "CREATE_INDEX",
            "status": "ok",
            "index_name": stmt.index_name,
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
        self, table: TableCatalog, knn_query: Optional[Dict[str, Any]]
    ) -> List[Dict[str, Any]]:
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

    def _exec_select(
        self, stmt: SelectStatement, effective_role: str
    ) -> Dict[str, Any]:
        self.access_controller.enforce_permission(
            effective_role, stmt.table_name, "SELECT"
        )
        table = self._get_table(stmt.table_name)
        rows = self._query_knn_or_scan(table, stmt.knn_query)
        filtered_rows = [
            r for r in rows if self._matches_where_clause(r, stmt.where_clauses)
        ]
        if stmt.order_by:
            filtered_rows.sort(
                key=lambda x: x.get(stmt.order_by or "", 0), reverse=stmt.order_desc
            )
        if stmt.limit is not None:
            filtered_rows = filtered_rows[: stmt.limit]

        final_rows = [
            (
                dict(r)
                if "*" in stmt.columns
                else {col: r.get(col) for col in stmt.columns}
            )
            for r in filtered_rows
        ]
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
        return None

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
