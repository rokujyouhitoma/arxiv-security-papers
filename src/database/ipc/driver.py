#!/usr/bin/env python3
"""
PEP 249 (Python Database API Specification v2.0) Compliant Driver for Vector DB.
Allows standard database operations using `connect()`, `Cursor`, `Connection` interfaces.
"""

from typing import Any, Dict, List, Optional, Sequence, Tuple

from ..storage.storage import VectorStorage
from .client import VectorDBClient
from .protocol import VectorDBProtocolHandler


class DatabaseError(Exception):
    """Base exception for PEP 249 database errors."""

    pass


class OperationalError(DatabaseError):
    pass


class ProgrammingError(DatabaseError):
    pass


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

    def execute(self, sql: str, params: Optional[Sequence[Any]] = None) -> "Cursor":
        """Executes a SQL query with optional positional parameter bindings."""
        query = sql
        if params:
            # Replace '?' with string/numeric/list representations
            for p in params:
                if isinstance(p, (list, tuple)):
                    rep = str(list(p))
                elif isinstance(p, (int, float)):
                    rep = str(p)
                else:
                    rep = f"'{p}'"
                query = query.replace("?", rep, 1)

        resp = self._connection._client.execute_sql(query, role=self._connection.role)
        if resp.get("status") != "ok":
            raise ProgrammingError(resp.get("error", "SQL Execution failed"))

        result = resp.get("result", {})
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

        return self

    def fetchone(self) -> Optional[Tuple[Any, ...]]:
        """Fetches the next row as a tuple."""
        if self._pos >= len(self._rows):
            return None
        row = self._rows[self._pos]
        self._pos += 1
        return tuple(row.values())

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

    def __enter__(self) -> "Cursor":
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.close()


class Connection:
    """
    PEP 249 compliant Connection object for Vector DB.
    """

    def __init__(
        self,
        file_path: str,
        role: str = "admin",
        dim: int = 128,
    ) -> None:
        self.file_path = file_path
        self.role = role
        self._storage = VectorStorage(file_path, dim=dim)
        self._handler = VectorDBProtocolHandler(storage=self._storage)
        self._client = VectorDBClient(handler=self._handler)
        self._closed = False

    def cursor(self) -> Cursor:
        if self._closed:
            raise OperationalError("Connection is closed")
        return Cursor(self)

    def commit(self) -> None:
        if self._closed:
            raise OperationalError("Connection is closed")
        self._client.execute_sql("COMMIT", role=self.role)

    def rollback(self) -> None:
        if self._closed:
            raise OperationalError("Connection is closed")
        self._client.execute_sql("ROLLBACK", role=self.role)

    def close(self) -> None:
        if not self._closed:
            self._storage.close()
            self._closed = True

    def __enter__(self) -> "Connection":
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.close()


def connect(
    database: str = "outputs/database/papers.vdb",
    role: str = "admin",
    dim: int = 128,
) -> Connection:
    """
    PEP 249 entry point connecting to a Vector DB file.
    Usage:
        import database
        conn = database.connect("outputs/database/papers.vdb")
        cursor = conn.cursor()
        cursor.execute("SELECT id, title FROM papers WHERE KNN(vector, [0.1, ...], 5)")
        print(cursor.fetchall())
    """
    return Connection(file_path=database, role=role, dim=dim)
