#!/usr/bin/env python3
"""
SQL Execution Engine for Pure Python Vector Database.
Evaluates DDL, DQL, DML, DCL, and TCL AST nodes against underlying vector storages and schemas.
"""

import os
import re
from typing import Any, Dict, List, Optional, Tuple

from ..embedding import DeterministicEmbedding
from ..index import HNSWIndex
from ..storage import VectorStorage
from .ast import (
    BeginStatement,
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

    def _matches_where_clause(
        self, record: Dict[str, Any], clauses: List[Dict[str, Any]]
    ) -> bool:
        """Evaluates WHERE conditions against a record dictionary."""
        if not clauses:
            return True

        if any(c.get("logic") == "OR_BRANCH" for c in clauses):
            for branch in clauses:
                if branch.get("logic") == "OR_BRANCH":
                    if self._matches_where_clause(record, branch.get("clauses", [])):
                        return True
            return False

        for clause in clauses:
            col = clause["column"]
            op = clause["operator"].upper()
            expected = clause["value"]
            actual = record.get(col)

            if op == "=":
                if str(actual) != str(expected):
                    return False
            elif op == "!=":
                if str(actual) == str(expected):
                    return False
            elif actual is None:
                return False
            elif op == ">=":
                try:
                    if float(str(actual)) < float(str(expected)):
                        return False
                except (ValueError, TypeError):
                    if str(actual) < str(expected):
                        return False
            elif op == "<=":
                try:
                    if float(str(actual)) > float(str(expected)):
                        return False
                except (ValueError, TypeError):
                    if str(actual) > str(expected):
                        return False
            elif op == ">":
                try:
                    if float(str(actual)) <= float(str(expected)):
                        return False
                except (ValueError, TypeError):
                    if str(actual) <= str(expected):
                        return False
            elif op == "<":
                try:
                    if float(str(actual)) >= float(str(expected)):
                        return False
                except (ValueError, TypeError):
                    if str(actual) >= str(expected):
                        return False
            elif op == "LIKE":
                pattern = str(expected).replace("%", ".*")
                if not re.search(pattern, str(actual or ""), re.IGNORECASE):
                    return False
            elif op in ("IN", "NOT IN"):
                in_list = (
                    expected if isinstance(expected, (list, tuple, set)) else [expected]
                )
                in_str_list = [str(x) for x in in_list]
                is_member = (actual in in_list) or (str(actual) in in_str_list)
                if op == "IN" and not is_member:
                    return False
                if op == "NOT IN" and is_member:
                    return False
        return True

    def execute_statement(
        self, stmt: SQLStatement, role: Optional[str] = None
    ) -> Dict[str, Any]:
        effective_role = role or self.access_controller.current_role
        cmd = stmt.command_type

        # 1. TCL
        if cmd == SQLCommandType.BEGIN:
            snapshots = {}
            for t_name, table in self.tables.items():
                snapshots[t_name] = {
                    "vectors": list(table.storage.get_all_vectors()),
                    "metadata": [dict(m) for m in table.storage.metadata],
                }
            self.tx_manager.begin(current_state_snapshot=snapshots)
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
                "message": f"Committed {len(mutations)} staged operations",
            }

        if cmd == SQLCommandType.ROLLBACK:
            snapshot = self.tx_manager.rollback()
            if snapshot:
                for t_name, state in snapshot.items():
                    if t_name in self.tables:
                        table = self.tables[t_name]
                        table.storage.write_all(state["vectors"], state["metadata"])
                        table.index = HNSWIndex(dim=table.storage.dim)
                        table.index.build_from_storage(state["vectors"])
            return {
                "command": "ROLLBACK",
                "status": "ok",
                "message": "Transaction aborted",
            }

        # 2. DCL
        if isinstance(stmt, GrantStatement):
            self.access_controller.enforce_permission(
                effective_role, stmt.table_name, "ADMIN"
            )
            self.access_controller.grant(stmt.permission, stmt.table_name, stmt.role)
            return {
                "command": "GRANT",
                "status": "ok",
                "message": f"Granted '{stmt.permission}' on '{stmt.table_name}' to role '{stmt.role}'",
            }

        if isinstance(stmt, RevokeStatement):
            self.access_controller.enforce_permission(
                effective_role, stmt.table_name, "ADMIN"
            )
            self.access_controller.revoke(stmt.permission, stmt.table_name, stmt.role)
            return {
                "command": "REVOKE",
                "status": "ok",
                "message": f"Revoked '{stmt.permission}' on '{stmt.table_name}' from role '{stmt.role}'",
            }

        # 3. DDL
        if isinstance(stmt, CreateTableStatement):
            self.access_controller.enforce_permission(
                effective_role, stmt.table_name, "ADMIN"
            )
            if stmt.table_name in self.tables and not stmt.if_not_exists:
                raise SQLExecutionError(f"Table '{stmt.table_name}' already exists")

            dim = 128
            for col in stmt.columns:
                if col.data_type.upper().startswith("VECTOR"):
                    # Extract dimension if specified e.g. VECTOR(256)
                    import re

                    m = re.search(r"VECTOR\(([0-9]+)\)", col.data_type.upper())
                    if m:
                        dim = int(m.group(1))

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

        if isinstance(stmt, DropTableStatement):
            self.access_controller.enforce_permission(
                effective_role, stmt.table_name, "ADMIN"
            )
            if stmt.table_name not in self.tables:
                if not stmt.if_exists:
                    raise SQLExecutionError(f"Table '{stmt.table_name}' not found")
                return {"command": "DROP_TABLE", "status": "ok", "dropped": False}

            del self.tables[stmt.table_name]
            return {"command": "DROP_TABLE", "status": "ok", "dropped": True}

        if isinstance(stmt, CreateIndexStatement):
            self.access_controller.enforce_permission(
                effective_role, stmt.table_name, "ADMIN"
            )
            table = self._get_table(stmt.table_name)
            table.index = HNSWIndex(dim=table.storage.dim)
            table.index.build_from_storage(table.storage.get_all_vectors())
            return {
                "command": "CREATE_INDEX",
                "status": "ok",
                "index_name": stmt.index_name,
                "table": stmt.table_name,
                "type": stmt.index_type,
            }

        # 4. DQL
        if isinstance(stmt, SelectStatement):
            self.access_controller.enforce_permission(
                effective_role, stmt.table_name, "SELECT"
            )
            table = self._get_table(stmt.table_name)
            rows: List[Dict[str, Any]] = []

            # Check KNN vector query
            if stmt.knn_query:
                query_vec = self.embedding.normalize(stmt.knn_query["vector"])
                top_k = stmt.knn_query["top_k"]
                matches = table.index.search(query_vec, top_k=top_k)
                for idx, sim in matches:
                    if idx < len(table.storage.metadata):
                        meta = dict(table.storage.get_metadata(idx))
                        meta["score"] = round(sim, 4)
                        meta["_idx"] = idx
                        rows.append(meta)
            else:
                # Full scan / metadata scan
                for idx, meta in enumerate(table.storage.metadata):
                    item = dict(meta)
                    item["_idx"] = idx
                    rows.append(item)

            # Apply WHERE filtering
            filtered_rows = [
                r for r in rows if self._matches_where_clause(r, stmt.where_clauses)
            ]

            # Apply ORDER BY
            if stmt.order_by:
                order_col = stmt.order_by
                filtered_rows.sort(
                    key=lambda x: x.get(order_col, 0),
                    reverse=stmt.order_desc,
                )

            # Apply LIMIT
            if stmt.limit is not None:
                filtered_rows = filtered_rows[: stmt.limit]

            # Project columns
            final_rows: List[Dict[str, Any]] = []
            for r in filtered_rows:
                if "*" in stmt.columns:
                    proj = dict(r)
                else:
                    proj = {col: r.get(col) for col in stmt.columns}
                final_rows.append(proj)

            return {
                "command": "SELECT",
                "status": "ok",
                "count": len(final_rows),
                "rows": final_rows,
            }

        # 5. DML
        if isinstance(stmt, InsertStatement):
            self.access_controller.enforce_permission(
                effective_role, stmt.table_name, "INSERT"
            )
            table = self._get_table(stmt.table_name)

            col_val_map = dict(zip(stmt.columns, stmt.values))
            doc_id = str(col_val_map.get("id", len(table.storage.metadata)))

            # Extract vector if present
            raw_vec = col_val_map.get("vector")
            if not raw_vec and "text" in col_val_map:
                raw_vec = self.embedding.embed_text(str(col_val_map["text"]))
            elif not raw_vec:
                raw_vec = [0.0] * table.storage.dim

            vector = self.embedding.normalize(raw_vec)

            # Stage or Execute
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

        if isinstance(stmt, UpdateStatement):
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
                # Persist updated metadata
                table.storage.write_all(
                    table.storage.get_all_vectors(), table.storage.metadata
                )

            return {
                "command": "UPDATE",
                "status": "ok",
                "updated_count": updated_count,
            }

        if isinstance(stmt, DeleteStatement):
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

            return {
                "command": "DELETE",
                "status": "ok",
                "deleted_count": deleted_count,
            }

        raise SQLExecutionError(f"Unhandled statement type: {cmd}")

    def _get_table(self, table_name: str) -> TableCatalog:
        table = self.tables.get(table_name)
        if not table:
            raise SQLExecutionError(f"Table '{table_name}' does not exist")
        return table
