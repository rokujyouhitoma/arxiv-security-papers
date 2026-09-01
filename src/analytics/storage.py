#!/usr/bin/env python3
"""
Zero-Dependency Analytics Storage Layer.
Provides high-performance SQLite time-series & snapshot storage (analytics.db)
with self-applying zero-dependency migrations powered by core database engine.
"""

import contextlib
import json
import logging
import os
import sqlite3
import time
from typing import Any, Dict, List, Optional, Tuple

from database.sqlite_engine import get_sqlite_connection

logger = logging.getLogger(__name__)

# Schema Migrations Table Definition
SCHEMA_MIGRATIONS: List[Tuple[int, str]] = [
    (
        1,
        """
        CREATE TABLE IF NOT EXISTS threat_trends (
            name TEXT PRIMARY KEY,
            category TEXT NOT NULL,
            count INTEGER NOT NULL,
            prev_count INTEGER NOT NULL,
            growth_pct REAL NOT NULL,
            sample_ids TEXT,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS strategic_kpis (
            kpi_key TEXT PRIMARY KEY,
            kpi_category TEXT NOT NULL,
            num_value REAL,
            text_value TEXT,
            metadata_json TEXT,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS metrics_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_json TEXT NOT NULL,
            collected_at TEXT NOT NULL,
            created_epoch REAL NOT NULL
        );
        """,
    ),
    (
        2,
        """
        CREATE INDEX IF NOT EXISTS idx_threat_category ON threat_trends(category);
        CREATE INDEX IF NOT EXISTS idx_kpis_category ON strategic_kpis(kpi_category);
        CREATE INDEX IF NOT EXISTS idx_history_epoch ON metrics_history(created_epoch);
        """,
    ),
    (
        3,
        """
        CREATE TABLE IF NOT EXISTS latest_snapshot (
            snapshot_key TEXT PRIMARY KEY,
            snapshot_json TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            updated_at_epoch REAL NOT NULL
        );
        """,
    ),
]


class AnalyticsStorage:
    """
    Unified single-file storage manager for pre-aggregated analytics and KPIs (analytics.db).
    """

    def __init__(
        self,
        workspace_dir: Optional[str] = None,
        analytics_dir: Optional[str] = None,
        db_name: str = "analytics.db",
    ) -> None:
        self.workspace_dir = workspace_dir or os.path.abspath(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        )
        self.analytics_dir = analytics_dir or os.path.join(
            self.workspace_dir, "outputs", "analytics"
        )
        self.db_path = os.path.join(self.analytics_dir, db_name)
        self._ensure_dir()
        self.initialize_db()

    def _ensure_dir(self) -> None:
        """Ensures the analytics output directory exists."""
        if not os.path.exists(self.analytics_dir):
            os.makedirs(self.analytics_dir, exist_ok=True)

    @contextlib.contextmanager
    def _get_connection(self) -> Any:
        """Yields a configured SQLite connection from core database engine and ensures clean closure."""
        conn = get_sqlite_connection(self.db_path)
        try:
            conn.execute("PRAGMA journal_mode=WAL;")
            conn.execute("PRAGMA synchronous=NORMAL;")
            yield conn
        finally:
            conn.close()

    def initialize_db(self) -> None:
        """Applies pending schema migrations deterministically."""
        try:
            with self._get_connection() as conn:
                cur = conn.cursor()
                cur.execute("PRAGMA user_version;")
                row = cur.fetchone()
                current_version = row[0] if row else 0

                for version, script in SCHEMA_MIGRATIONS:
                    if version > current_version:
                        logger.info(
                            "Applying Analytics DB Migration v%d -> v%d",
                            current_version,
                            version,
                        )
                        conn.executescript(script)
                        conn.execute(f"PRAGMA user_version = {version};")
                        current_version = version
        except Exception as e:
            logger.error("Failed to initialize Analytics DB: %s", e)

    def _upsert_threat_trends(
        self, cur: sqlite3.Cursor, top_threats: List[Dict[str, Any]], now_str: str
    ) -> None:
        """Inserts or updates threat trends records."""
        for t in top_threats:
            growth_raw = str(t.get("growth", "0")).replace("%", "").replace("+", "")
            growth_val = float(growth_raw) if growth_raw else 0.0
            cur.execute(
                """
                INSERT INTO threat_trends (name, category, count, prev_count, growth_pct, sample_ids, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(name) DO UPDATE SET
                    count=excluded.count, prev_count=excluded.prev_count, growth_pct=excluded.growth_pct,
                    sample_ids=excluded.sample_ids, updated_at=excluded.updated_at
                """,
                (
                    t.get("name", "Unknown"),
                    t.get("category", "General"),
                    int(t.get("count", 0)),
                    int(t.get("prev_count", 0)),
                    growth_val,
                    json.dumps(t.get("sample_ids", [])),
                    now_str,
                ),
            )

    def _get_kpi_category(self, k: str) -> str:
        if "token" in k or "tier" in k:
            return "ST"
        if "latency" in k or "density" in k:
            return "SA"
        return "SM"

    def _upsert_single_kpi(self, cur: sqlite3.Cursor, k: str, v: Any, now_str: str) -> None:
        cat = self._get_kpi_category(k)
        num_val = float(v) if isinstance(v, (int, float)) else None
        cur.execute(
            """
            INSERT INTO strategic_kpis (kpi_key, kpi_category, num_value, text_value, metadata_json, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(kpi_key) DO UPDATE SET
                num_value=excluded.num_value, text_value=excluded.text_value, updated_at=excluded.updated_at
            """,
            (k, cat, num_val, str(v), "{}", now_str),
        )

    def _upsert_strategic_kpis(
        self, cur: sqlite3.Cursor, data: Dict[str, Any], now_str: str
    ) -> None:
        """Inserts or updates individual strategic KPI metrics."""
        for k, v in data.items():
            if k != "top_threat_vectors":
                self._upsert_single_kpi(cur, k, v, now_str)

    def save_snapshot(self, data: Dict[str, Any]) -> str:
        """Atomically saves pre-aggregated metrics into single analytics.db database."""
        self._ensure_dir()
        data_to_write = dict(data)
        now_epoch = time.time()
        now_str = time.strftime("%Y-%m-%d %H:%M:%S JST", time.localtime())
        if "updated_at_epoch" not in data_to_write:
            data_to_write["updated_at_epoch"] = now_epoch

        serialized = json.dumps(data_to_write, indent=2, ensure_ascii=False)
        try:
            with self._get_connection() as conn:
                cur = conn.cursor()
                cur.execute(
                    """
                    INSERT INTO latest_snapshot (snapshot_key, snapshot_json, updated_at, updated_at_epoch)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(snapshot_key) DO UPDATE SET
                        snapshot_json=excluded.snapshot_json, updated_at=excluded.updated_at,
                        updated_at_epoch=excluded.updated_at_epoch
                    """,
                    ("latest", serialized, now_str, now_epoch),
                )
                self._upsert_threat_trends(
                    cur, data.get("top_threat_vectors", []), now_str
                )
                self._upsert_strategic_kpis(cur, data, now_str)
                cur.execute(
                    "INSERT INTO metrics_history (snapshot_json, collected_at, created_epoch) VALUES (?, ?, ?)",
                    (serialized, now_str, now_epoch),
                )
                conn.commit()
                logger.info("Saved analytics snapshot into %s", self.db_path)
        except Exception as ex:
            raise RuntimeError(f"Analytics DB save failed: {ex}") from ex

        return self.db_path

    def _parse_snapshot_row(self, row: Any) -> Optional[Dict[str, Any]]:
        if not (row and row["snapshot_json"]):
            return None
        parsed = json.loads(row["snapshot_json"])
        return parsed if isinstance(parsed, dict) else None

    def load_latest_metrics(self) -> Optional[Dict[str, Any]]:
        """
        Loads latest pre-aggregated metrics from latest_snapshot table in analytics.db.
        Returns None if no snapshot exists yet.
        """
        if not os.path.exists(self.db_path):
            return None
        try:
            with self._get_connection() as conn:
                cur = conn.cursor()
                cur.execute(
                    "SELECT snapshot_json FROM latest_snapshot WHERE snapshot_key = ?",
                    ("latest",),
                )
                return self._parse_snapshot_row(cur.fetchone())
        except Exception as ex:
            logger.warning("Failed to load snapshot from %s: %s", self.db_path, ex)
            return None
