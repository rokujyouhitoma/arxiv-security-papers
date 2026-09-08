#!/usr/bin/env python3
"""
PEP 249 (Python Database API Specification v2.0) Compliant Driver for Vector DB.
Allows standard database operations using `connect()`, `Cursor`, `Connection` interfaces,
with full multi-table .vdb container (OKFMTC01) support and zero external C-dependencies.
"""

import json
import os
from typing import Any, Dict, List, Optional, Sequence, Tuple

from ..embedding import DeterministicEmbedding
from ..sql.executor import SQLExecutionError, SQLExecutor
from ..storage.multi_storage import MultiTableVectorStorage
from ..storage.storage import VectorStorage


class DatabaseError(Exception):
    """Base exception for PEP 249 database errors."""

    pass


class OperationalError(DatabaseError):
    pass


class ProgrammingError(DatabaseError):
    pass


class IntegrityError(DatabaseError):
    pass


def _format_sequence(p: Any) -> Optional[str]:
    if isinstance(p, (list, tuple)):
        return str(list(p))
    return None


def _format_scalar(p: Any) -> Optional[str]:
    if p is None:
        return "NULL"
    if isinstance(p, bool):
        return "TRUE" if p else "FALSE"
    if isinstance(p, (int, float)):
        return str(p)
    return _format_sequence(p)


def _format_param_val(p: Any) -> str:
    """Formats a single query parameter safely into SQL literal representation."""
    scalar = _format_scalar(p)
    if scalar is not None:
        return scalar
    if isinstance(p, (dict, list)):
        return f"'{json.dumps(p, ensure_ascii=False)}'"
    escaped = str(p).replace("'", "''")
    return f"'{escaped}'"


def _bind_params(sql: str, params: Optional[Sequence[Any]]) -> str:
    """Substitutes positional '?' placeholders with formatted parameter literals."""
    if not params:
        return sql
    query = sql
    for p in params:
        query = query.replace("?", _format_param_val(p), 1)
    return query


class Cursor:
    """
    PEP 249 compliant Cursor object for executing SQL and fetching results.
    """

    def __init__(self, connection: "Connection") -> None:
        self._connection = connection
        self._rows: List[Dict[str, Any]] = []
        self._pos: int = 0
        self.description: Optional[
            List[Tuple[str, Any, None, None, None, None, None]]
        ] = None
        self.rowcount: int = -1
        self.arraysize: int = 1
        self.lastrowid: Optional[int] = None

    def _update_cursor_metadata(self, result: Dict[str, Any]) -> None:
        self._rows = result.get("rows", [])
        self._pos = 0
        self.rowcount = result.get(
            "updated_count",
            result.get("deleted_count", result.get("inserted_count", len(self._rows))),
        )
        if self._rows:
            sample = self._rows[0]
            self.description = [
                (col, None, None, None, None, None, None) for col in sample.keys()
            ]
        else:
            self.description = None

    def execute(self, sql: str, params: Optional[Sequence[Any]] = None) -> "Cursor":
        """Executes a SQL query with optional positional parameter bindings."""
        if self._connection.is_closed:
            raise OperationalError("Connection is closed")
        query = _bind_params(sql, params)
        resp = self._connection._execute_query(query)
        if resp.get("status") != "ok":
            raise ProgrammingError(resp.get("error", "SQL Execution failed"))
        self._update_cursor_metadata(resp.get("result", {}))
        return self

    def executemany(self, sql: str, seq_of_params: Sequence[Sequence[Any]]) -> "Cursor":
        """Executes a prepared SQL query against a sequence of parameter tuples."""
        for params in seq_of_params:
            self.execute(sql, params)
        return self

    def fetchone(self) -> Optional[Tuple[Any, ...]]:
        """Fetches the next row as a tuple."""
        if self._pos >= len(self._rows):
            return None
        row = self._rows[self._pos]
        self._pos += 1
        return tuple(row.values())

    def fetchmany(self, size: Optional[int] = None) -> List[Tuple[Any, ...]]:
        """Fetches the next batch of rows as tuples."""
        num = self.arraysize if size is None else size
        res = [tuple(r.values()) for r in self._rows[self._pos : self._pos + num]]
        self._pos += len(res)
        return res

    def fetchall(self) -> List[Tuple[Any, ...]]:
        """Fetches all remaining rows as a list of tuples."""
        res = [tuple(r.values()) for r in self._rows[self._pos :]]
        self._pos = len(self._rows)
        return res

    def fetchall_dict(self) -> List[Dict[str, Any]]:
        """Extension: fetches all remaining rows as list of dictionaries."""
        res = self._rows[self._pos :]
        self._pos = len(self._rows)
        return res

    def close(self) -> None:
        self._rows.clear()
        self._pos = 0

    def __iter__(self) -> "Cursor":
        return self

    def __next__(self) -> Tuple[Any, ...]:
        row = self.fetchone()
        if row is None:
            raise StopIteration
        return row

    def __enter__(self) -> "Cursor":
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.close()


def _load_existing_storage(storage: MultiTableVectorStorage, path: str) -> None:
    if (
        path not in (":memory:", "")
        and os.path.exists(path)
        and os.path.getsize(path) > 0
    ):
        storage.load()


def _init_connection_storage(
    target_db: str,
    multi_storage: Optional[MultiTableVectorStorage],
) -> MultiTableVectorStorage:
    if multi_storage is not None:
        return multi_storage
    storage = MultiTableVectorStorage(file_path=target_db)
    _load_existing_storage(storage, target_db)
    return storage


class Connection:
    """
    PEP 249 compliant Connection object for Multi-Table Vector DB Container.
    """

    def __init__(
        self,
        database: str = ":memory:",
        role: str = "admin",
        dim: int = 128,
        client: Optional[Any] = None,
        multi_storage: Optional[MultiTableVectorStorage] = None,
        file_path: Optional[str] = None,
        default_table_name: Optional[str] = None,
        **kwargs: Any,
    ) -> None:
        target_db = file_path or database
        self.database = target_db
        self.file_path = target_db
        self.role = role
        self.dim = dim
        self._client = client
        self._closed = False
        self._storage = _init_connection_storage(target_db, multi_storage)
        self._executor = SQLExecutor(
            multi_storage=self._storage,
            embedding=DeterministicEmbedding(dim=dim),
            default_table_name=default_table_name,
        )

    @property
    def is_closed(self) -> bool:
        return self._closed

    @property
    def tables(self) -> List[str]:
        return self._storage.list_tables()

    def get_table_storage(self, name: str) -> VectorStorage:
        """Retrieves raw VectorStorage table for vector search or HNSW operations."""
        return self._storage.get_table(name)

    def _execute_query(self, query: str) -> Dict[str, Any]:
        if self._client is not None:
            return self._client.execute_sql(query, role=self.role)  # type: ignore[no-any-return]
        try:
            res = self._executor.execute(query, role=self.role)
            return {"status": "ok", "result": res}
        except SQLExecutionError as exc:
            return {"status": "error", "error": str(exc)}
        except Exception as exc:
            return {"status": "error", "error": f"Execution error: {exc}"}

    def cursor(self) -> Cursor:
        if self._closed:
            raise OperationalError("Connection is closed")
        return Cursor(self)

    def execute(self, sql: str, params: Optional[Sequence[Any]] = None) -> Cursor:
        """Executes a SQL query directly on the connection and returns a Cursor."""
        cur = self.cursor()
        return cur.execute(sql, params)

    def executemany(self, sql: str, seq_of_params: Sequence[Sequence[Any]]) -> Cursor:
        """Executes a prepared SQL query against a sequence of parameter tuples."""
        cur = self.cursor()
        return cur.executemany(sql, seq_of_params)

    def commit(self) -> None:
        if self._closed:
            raise OperationalError("Connection is closed")
        if self._client is not None:
            self._client.execute_sql("COMMIT", role=self.role)
            return
        if self._executor.tx_manager.is_active:
            self._executor.execute("COMMIT", role=self.role)
        self._storage.save()

    def rollback(self) -> None:
        if self._closed:
            raise OperationalError("Connection is closed")
        if self._client is not None:
            self._client.execute_sql("ROLLBACK", role=self.role)
            return
        if self._executor.tx_manager.is_active:
            self._executor.execute("ROLLBACK", role=self.role)

    def close(self) -> None:
        if not self._closed:
            self._storage.close()
            self._closed = True

    def __enter__(self) -> "Connection":
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.close()


def connect(
    database: str = ":memory:",
    role: str = "admin",
    dim: int = 128,
    default_table_name: Optional[str] = None,
    **kwargs: Any,
) -> Connection:
    """
    PEP 249 entry point connecting to a Multi-Table Vector DB container.
    Usage:
        import database
        conn = database.connect("data/app.vdb")
        cursor = conn.cursor()
        cursor.execute("CREATE TABLE IF NOT EXISTS vertices (id TEXT, name TEXT)")
        cursor.execute("INSERT INTO vertices VALUES (?, ?)", ("v1", "Alice"))
        conn.commit()
    """
    return Connection(
        database=database,
        role=role,
        dim=dim,
        default_table_name=default_table_name,
        **kwargs,
    )
