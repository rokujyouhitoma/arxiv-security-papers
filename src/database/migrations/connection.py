#!/usr/bin/env python3
"""
PEP 249 Database Adapters for Migration Engine.
Supports Primary (src/database Pure Python RDBMS) and Secondary (sqlite3).
Conforms to DSN-30 Section 4 specification.
"""

import sqlite3
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, List, Optional, Sequence, Tuple

from .. import driver as pydb_driver
from .models import BackendType


class DatabaseAdapter(ABC):
    """Abstract base adapter for database connection and execution."""

    def __init__(self, db_path: Path | str, backend_type: BackendType) -> None:
        self.db_path = Path(db_path)
        self.backend_type = backend_type
        self._connection: Optional[Any] = None

    @abstractmethod
    def connect(self) -> Any:
        """Establishes and returns underlying PEP 249 connection."""
        pass

    @abstractmethod
    def execute_ddl(self, sql: str) -> None:
        """Executes a DDL statement atomically."""
        pass

    @abstractmethod
    def execute_query(
        self, sql: str, params: Optional[Sequence[Any]] = None
    ) -> List[Tuple[Any, ...]]:
        """Executes a SELECT query and returns all rows."""
        pass

    @abstractmethod
    def is_healthy(self) -> bool:
        """Verifies database connectivity."""
        pass

    @abstractmethod
    def close(self) -> None:
        """Closes the underlying connection."""
        pass


class PyDBAdapter(DatabaseAdapter):
    """
    Primary Target Adapter for src/database Pure Python RDBMS.
    Utilizes SlottedPage storage and ARIES WAL logging.
    """

    def __init__(self, db_path: Path | str) -> None:
        super().__init__(db_path=db_path, backend_type=BackendType.PYDB)

    def connect(self) -> Any:
        if self._connection is None or getattr(self._connection, "is_closed", False):
            # Ensure parent directory exists
            if self.db_path != Path(":memory:") and not self.db_path.parent.exists():
                self.db_path.parent.mkdir(parents=True, exist_ok=True)
            self._connection = pydb_driver.connect(database=str(self.db_path))
        return self._connection

    def execute_ddl(self, sql: str) -> None:
        conn = self.connect()
        cur = conn.cursor()
        try:
            cur.execute(sql)
            conn.commit()
        except Exception:
            conn.rollback()
            raise

    def execute_query(
        self, sql: str, params: Optional[Sequence[Any]] = None
    ) -> List[Tuple[Any, ...]]:
        conn = self.connect()
        cur = conn.cursor()
        cur.execute(sql, params)
        rows: List[Tuple[Any, ...]] = cur.fetchall()
        return rows

    def is_healthy(self) -> bool:
        try:
            conn = self.connect()
            cur = conn.cursor()
            cur.execute("SELECT 1")
            row = cur.fetchone()
            return row is not None and row[0] == 1
        except Exception:
            return False

    def close(self) -> None:
        if self._connection is not None:
            self._connection.close()
            self._connection = None


class SQLiteAdapter(DatabaseAdapter):
    """
    Secondary Target Adapter for standard sqlite3.
    Fully supported for multi-environment deployments and compatibility.
    """

    def __init__(self, db_path: Path | str, timeout: float = 30.0) -> None:
        super().__init__(db_path=db_path, backend_type=BackendType.SQLITE)
        self.timeout = timeout

    def connect(self) -> sqlite3.Connection:
        if self._connection is None:
            # Ensure parent directory exists
            if self.db_path != Path(":memory:") and not self.db_path.parent.exists():
                self.db_path.parent.mkdir(parents=True, exist_ok=True)
            conn = sqlite3.connect(
                str(self.db_path), timeout=self.timeout, isolation_level=None
            )
            conn.execute("PRAGMA foreign_keys = ON;")
            conn.execute("PRAGMA journal_mode = WAL;")
            self._connection = conn
        return self._connection

    def execute_ddl(self, sql: str) -> None:
        conn = self.connect()
        cur = conn.cursor()
        try:
            cur.execute(sql)
            conn.commit()
        except Exception:
            conn.rollback()
            raise

    def execute_query(
        self, sql: str, params: Optional[Sequence[Any]] = None
    ) -> List[Tuple[Any, ...]]:
        conn = self.connect()
        cur = conn.cursor()
        if params is not None:
            cur.execute(sql, params)
        else:
            cur.execute(sql)
        rows: List[Tuple[Any, ...]] = cur.fetchall()
        return rows

    def is_healthy(self) -> bool:
        try:
            conn = self.connect()
            cur = conn.cursor()
            cur.execute("SELECT 1")
            row = cur.fetchone()
            return row is not None and row[0] == 1
        except Exception:
            return False

    def close(self) -> None:
        if self._connection is not None:
            self._connection.close()
            self._connection = None


def get_adapter(
    backend: BackendType | str = BackendType.PYDB,
    db_path: Path | str = "outputs/database/papers_catalog.vdb",
) -> DatabaseAdapter:
    """
    Factory function providing a DatabaseAdapter instance.
    Defaults to Primary backend: PyDB (src/database).
    """
    resolved_backend = (
        BackendType.from_str(backend) if isinstance(backend, str) else backend
    )
    if resolved_backend == BackendType.PYDB:
        return PyDBAdapter(db_path=db_path)
    elif resolved_backend == BackendType.SQLITE:
        return SQLiteAdapter(db_path=db_path)
    raise ValueError(f"Unknown backend type: {resolved_backend}")
