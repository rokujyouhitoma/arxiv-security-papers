#!/usr/bin/env python3
"""
MITRE ATT&CK CTI SQLite Catalog Storage.
Provides persistent storage, B-Tree indexes, and FTS5 full-text search
for MITRE ATT&CK tactics, techniques, mitigations, and relationships.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import json
import os
from contextlib import contextmanager
from typing import Any, Dict, Generator, List, Optional, Tuple

from database import (
    SQLiteConnection,
    SQLiteCursor,
    SQLiteOperationalError,
    SQLiteRow,
    get_sqlite_connection,
)


class CTICatalogStorage:
    """SQLite-backed persistent store for MITRE ATT&CK CTI domain data."""

    DEFAULT_DB_PATH = os.path.join(
        os.path.dirname(__file__),
        "..",
        "..",
        "..",
        "..",
        "outputs",
        "database",
        "catalog",
        "cti_catalog.db",
    )

    def __init__(self, db_path: Optional[str] = None) -> None:
        self.db_path = os.path.abspath(db_path or self.DEFAULT_DB_PATH)
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        self._init_schema()

    @contextmanager
    def _connection(self) -> Generator[SQLiteConnection, None, None]:
        conn = get_sqlite_connection(
            self.db_path, init_schema=False, enable_wal=True, timeout=30.0
        )
        try:
            yield conn
        finally:
            conn.close()

    def _init_schema(self) -> None:
        """Initializes relational tables and full-text search virtual tables."""
        with self._connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS cti_tactics (
                    tactic_id TEXT PRIMARY KEY,
                    shortname TEXT UNIQUE NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT,
                    external_url TEXT
                )
                """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS cti_techniques (
                    technique_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT,
                    is_subtechnique INTEGER DEFAULT 0,
                    parent_technique_id TEXT,
                    platforms_json TEXT,
                    tactics_json TEXT,
                    external_url TEXT,
                    stix_id TEXT NOT NULL
                )
                """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS cti_mitigations (
                    mitigation_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT,
                    external_url TEXT,
                    stix_id TEXT NOT NULL
                )
                """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS cti_relationships (
                    source_id TEXT NOT NULL,
                    target_id TEXT NOT NULL,
                    rel_type TEXT NOT NULL,
                    PRIMARY KEY (source_id, target_id, rel_type)
                )
                """)
            cursor.execute(
                "CREATE INDEX IF NOT EXISTS idx_tech_parent ON cti_techniques(parent_technique_id)"
            )
            cursor.execute(
                "CREATE INDEX IF NOT EXISTS idx_rel_target ON cti_relationships(target_id)"
            )

            self._create_fts_table(cursor)
            conn.commit()

    def _create_fts_table(self, cursor: SQLiteCursor) -> None:
        """Attempts to create FTS5 virtual table, safely catching missing extensions."""
        try:
            cursor.execute("""
                CREATE VIRTUAL TABLE IF NOT EXISTS cti_techniques_fts USING fts5(
                    technique_id,
                    name,
                    description,
                    content='cti_techniques',
                    content_rowid='rowid'
                )
                """)
        except SQLiteOperationalError:
            # Fallback when FTS5 extension is not compiled into sqlite3
            pass

    def insert_tactics(self, tactics: List[Dict[str, Any]]) -> None:
        """Batch inserts or replaces MITRE ATT&CK tactics."""
        rows = [
            (
                t["tactic_id"],
                t["shortname"],
                t["name"],
                t.get("description", ""),
                t.get("external_url", ""),
            )
            for t in tactics
        ]
        with self._connection() as conn:
            conn.executemany(
                """
                INSERT OR REPLACE INTO cti_tactics
                (tactic_id, shortname, name, description, external_url)
                VALUES (?, ?, ?, ?, ?)
                """,
                rows,
            )
            conn.commit()

    def insert_techniques(self, techniques: List[Dict[str, Any]]) -> None:
        """Batch inserts or replaces MITRE ATT&CK techniques."""
        rows = [
            (
                t["technique_id"],
                t["name"],
                t.get("description", ""),
                1 if t.get("is_subtechnique") else 0,
                t.get("parent_technique_id"),
                json.dumps(t.get("platforms", [])),
                json.dumps(t.get("tactics", [])),
                t.get("external_url", ""),
                t.get("stix_id", ""),
            )
            for t in techniques
        ]
        with self._connection() as conn:
            conn.executemany(
                """
                INSERT OR REPLACE INTO cti_techniques
                (technique_id, name, description, is_subtechnique, parent_technique_id,
                 platforms_json, tactics_json, external_url, stix_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                rows,
            )
            self._rebuild_fts(conn)
            conn.commit()

    def _rebuild_fts(self, conn: SQLiteConnection) -> None:
        """Rebuilds FTS5 index if available."""
        try:
            conn.execute(
                "INSERT INTO cti_techniques_fts(cti_techniques_fts) VALUES('rebuild')"
            )
        except SQLiteOperationalError:
            pass

    def insert_mitigations(self, mitigations: List[Dict[str, Any]]) -> None:
        """Batch inserts or replaces MITRE ATT&CK mitigations."""
        rows = [
            (
                m["mitigation_id"],
                m["name"],
                m.get("description", ""),
                m.get("external_url", ""),
                m.get("stix_id", ""),
            )
            for m in mitigations
        ]
        with self._connection() as conn:
            conn.executemany(
                """
                INSERT OR REPLACE INTO cti_mitigations
                (mitigation_id, name, description, external_url, stix_id)
                VALUES (?, ?, ?, ?, ?)
                """,
                rows,
            )
            conn.commit()

    def insert_relationships(self, relationships: List[Tuple[str, str, str]]) -> None:
        """Batch inserts or replaces MITRE ATT&CK relationships (source, target, rel_type)."""
        with self._connection() as conn:
            conn.executemany(
                """
                INSERT OR REPLACE INTO cti_relationships (source_id, target_id, rel_type)
                VALUES (?, ?, ?)
                """,
                relationships,
            )
            conn.commit()

    def get_technique(self, technique_id: str) -> Optional[Dict[str, Any]]:
        """Fetches a single technique by ID (e.g. 'T1059' or 'T1059.001')."""
        with self._connection() as conn:
            row = conn.execute(
                "SELECT * FROM cti_techniques WHERE technique_id = ?",
                (technique_id.upper(),),
            ).fetchone()
            if not row:
                return None
            return self._row_to_technique(row)

    def get_all_techniques(self) -> Dict[str, Dict[str, Any]]:
        """Retrieves all techniques indexed by technique_id."""
        result: Dict[str, Dict[str, Any]] = {}
        with self._connection() as conn:
            cursor = conn.execute(
                "SELECT * FROM cti_techniques ORDER BY technique_id ASC"
            )
            for row in cursor.fetchall():
                tech = self._row_to_technique(row)
                result[tech["technique_id"]] = tech
        return result

    def get_techniques_by_tactic(self, tactic_shortname: str) -> List[Dict[str, Any]]:
        """Finds all techniques associated with a given tactic (e.g. 'execution')."""
        pattern = f'%"{tactic_shortname.lower()}"%'
        with self._connection() as conn:
            cursor = conn.execute(
                "SELECT * FROM cti_techniques WHERE LOWER(tactics_json) LIKE ? ORDER BY technique_id",
                (pattern,),
            )
            return [self._row_to_technique(r) for r in cursor.fetchall()]

    def get_mitigations_for_technique(self, technique_id: str) -> List[Dict[str, Any]]:
        """Finds all mitigations (Course of Action) mapped to a specific technique."""
        with self._connection() as conn:
            query = """
                SELECT m.* FROM cti_mitigations m
                JOIN cti_relationships r ON m.mitigation_id = r.source_id
                WHERE r.target_id = ? AND r.rel_type = 'mitigates'
                ORDER BY m.mitigation_id ASC
            """
            cursor = conn.execute(query, (technique_id.upper(),))
            return [
                {
                    "mitigation_id": row["mitigation_id"],
                    "name": row["name"],
                    "description": row["description"],
                    "external_url": row["external_url"],
                    "stix_id": row["stix_id"],
                }
                for row in cursor.fetchall()
            ]

    def get_all_tactics(self) -> List[Dict[str, Any]]:
        """Returns all registered tactics."""
        with self._connection() as conn:
            cursor = conn.execute("SELECT * FROM cti_tactics ORDER BY tactic_id ASC")
            return [
                {
                    "tactic_id": row["tactic_id"],
                    "shortname": row["shortname"],
                    "name": row["name"],
                    "description": row["description"],
                    "external_url": row["external_url"],
                }
                for row in cursor.fetchall()
            ]

    def _search_fts(
        self, conn: SQLiteConnection, cleaned: str, limit: int
    ) -> Optional[List[Dict[str, Any]]]:
        try:
            fts_query = """
                SELECT t.* FROM cti_techniques t
                JOIN cti_techniques_fts f ON t.rowid = f.rowid
                WHERE cti_techniques_fts MATCH ?
                ORDER BY rank LIMIT ?
            """
            safe_match = f'"{cleaned}"'
            cursor = conn.execute(fts_query, (safe_match, limit))
            rows = cursor.fetchall()
            return [self._row_to_technique(r) for r in rows] if rows else None
        except SQLiteOperationalError:
            return None

    def _search_like(
        self, conn: SQLiteConnection, cleaned: str, limit: int
    ) -> List[Dict[str, Any]]:
        pattern = f"%{cleaned}%"
        like_query = """
            SELECT * FROM cti_techniques
            WHERE technique_id LIKE ? OR name LIKE ? OR description LIKE ?
            ORDER BY technique_id ASC LIMIT ?
        """
        cursor = conn.execute(like_query, (pattern, pattern, pattern, limit))
        return [self._row_to_technique(r) for r in cursor.fetchall()]

    def search_techniques(
        self, query_str: str, limit: int = 15
    ) -> List[Dict[str, Any]]:
        """Full-text / keyword search against technique ID, name, and description."""
        cleaned = query_str.strip()
        if not cleaned:
            return []

        with self._connection() as conn:
            fts_res = self._search_fts(conn, cleaned, limit)
            if fts_res is not None:
                return fts_res
            return self._search_like(conn, cleaned, limit)

    def count_summary(self) -> Dict[str, int]:
        """Returns row counts across all CTI catalog tables."""
        with self._connection() as conn:
            return {
                "tactics": int(
                    conn.execute("SELECT COUNT(*) FROM cti_tactics").fetchone()[0]
                ),
                "techniques": int(
                    conn.execute("SELECT COUNT(*) FROM cti_techniques").fetchone()[0]
                ),
                "mitigations": int(
                    conn.execute("SELECT COUNT(*) FROM cti_mitigations").fetchone()[0]
                ),
                "relationships": int(
                    conn.execute("SELECT COUNT(*) FROM cti_relationships").fetchone()[0]
                ),
            }

    @staticmethod
    def _parse_json_list(raw_val: Any) -> List[str]:
        if not raw_val:
            return []
        try:
            parsed = json.loads(raw_val)
            return parsed if isinstance(parsed, list) else []
        except (ValueError, TypeError):
            return []

    @classmethod
    def _row_to_technique(cls, row: SQLiteRow) -> Dict[str, Any]:
        return {
            "technique_id": row["technique_id"],
            "name": row["name"],
            "description": row["description"] or "",
            "is_subtechnique": bool(row["is_subtechnique"]),
            "parent_technique_id": row["parent_technique_id"],
            "platforms": cls._parse_json_list(row["platforms_json"]),
            "tactics": cls._parse_json_list(row["tactics_json"]),
            "external_url": row["external_url"] or "",
            "stix_id": row["stix_id"],
        }
