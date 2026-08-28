#!/usr/bin/env python3
"""
Zero-Dependency Analytics Storage Layer.
Provides atomic file snapshot persistence (latest_metrics.json) and
SQLite time-series storage with self-applying zero-dependency migrations.
"""

import contextlib
import json
import logging
import os
import tempfile
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
]


class AnalyticsStorage:
    """
    High-performance storage manager for pre-aggregated analytics and KPIs.
    """

    def __init__(
        self,
        workspace_dir: Optional[str] = None,
        analytics_dir: Optional[str] = None,
        db_name: str = "analytics.db",
        snapshot_name: str = "latest_metrics.json",
    ) -> None:
        self.workspace_dir = workspace_dir or os.path.abspath(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        )
        self.analytics_dir = analytics_dir or os.path.join(
            self.workspace_dir, "outputs", "analytics"
        )
        self.db_path = os.path.join(self.analytics_dir, db_name)
        self.snapshot_path = os.path.join(self.analytics_dir, snapshot_name)
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

    def save_snapshot(self, data: Dict[str, Any]) -> str:
        """
        Atomically saves pre-aggregated metrics snapshot to latest_metrics.json.
        Guarantees that readers never observe partially written data.
        """
        self._ensure_dir()
        data_to_write = dict(data)
        if "updated_at_epoch" not in data_to_write:
            data_to_write["updated_at_epoch"] = time.time()

        serialized = json.dumps(data_to_write, indent=2, ensure_ascii=False)

        # Write to temporary file in same directory for atomic replace
        temp_fd, temp_path = tempfile.mkstemp(
            dir=self.analytics_dir, prefix="metrics_snapshot_", suffix=".tmp"
        )
        try:
            with os.fdopen(temp_fd, "w", encoding="utf-8") as f:
                f.write(serialized)
                f.flush()
                os.fsync(f.fileno())
            os.replace(temp_path, self.snapshot_path)
            logger.info("Saved analytics snapshot to %s", self.snapshot_path)
        except Exception as ex:
            if os.path.exists(temp_path):
                try:
                    os.unlink(temp_path)
                except OSError:
                    pass
            raise RuntimeError(f"Atomic snapshot save failed: {ex}") from ex

        # Also persist to SQLite database tables
        self._persist_to_db(data_to_write)
        return self.snapshot_path

    def _persist_to_db(self, data: Dict[str, Any]) -> None:
        """Records snapshot metrics into SQLite tables."""
        try:
            with self._get_connection() as conn:
                cur = conn.cursor()
                now_str = time.strftime("%Y-%m-%d %H:%M:%S JST", time.localtime())
                now_epoch = time.time()

                # 1. Threat Trends
                top_threats = data.get("top_threat_vectors", [])
                for t in top_threats:
                    cur.execute(
                        """
                        INSERT INTO threat_trends (
                            name, category, count, prev_count, growth_pct, sample_ids, updated_at
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(name) DO UPDATE SET
                            count=excluded.count,
                            prev_count=excluded.prev_count,
                            growth_pct=excluded.growth_pct,
                            sample_ids=excluded.sample_ids,
                            updated_at=excluded.updated_at
                        """,
                        (
                            t.get("name", "Unknown"),
                            t.get("category", "General"),
                            int(t.get("count", 0)),
                            int(t.get("prev_count", 0)),
                            float(str(t.get("growth", "0")).replace("%", "").replace("+", "") or 0.0),
                            json.dumps(t.get("sample_ids", [])),
                            now_str,
                        ),
                    )

                # 2. Strategic KPIs
                for k, v in data.items():
                    if k == "top_threat_vectors":
                        continue
                    cat = "ST" if "token" in k or "tier" in k else ("SA" if "latency" in k or "density" in k else "SM")
                    num_val = None
                    text_val = str(v)
                    if isinstance(v, (int, float)):
                        num_val = float(v)
                    cur.execute(
                        """
                        INSERT INTO strategic_kpis (
                            kpi_key, kpi_category, num_value, text_value, metadata_json, updated_at
                        )
                        VALUES (?, ?, ?, ?, ?, ?)
                        ON CONFLICT(kpi_key) DO UPDATE SET
                            num_value=excluded.num_value,
                            text_value=excluded.text_value,
                            updated_at=excluded.updated_at
                        """,
                        (k, cat, num_val, text_val, "{}", now_str),
                    )

                # 3. Append to history log
                cur.execute(
                    """
                    INSERT INTO metrics_history (snapshot_json, collected_at, created_epoch)
                    VALUES (?, ?, ?)
                    """,
                    (json.dumps(data, ensure_ascii=False), now_str, now_epoch),
                )
                conn.commit()
        except Exception as e:
            logger.warning("Failed to persist analytics metrics to SQLite: %s", e)

    def load_latest_metrics(self) -> Optional[Dict[str, Any]]:
        """
        Loads pre-aggregated metrics in O(1) time.
        Returns None if no snapshot exists yet.
        """
        if not os.path.exists(self.snapshot_path):
            return None
        try:
            with open(self.snapshot_path, "r", encoding="utf-8") as f:
                content = f.read().strip()
                if not content:
                    return None
                data = json.loads(content)
                if isinstance(data, dict):
                    return data
                return None
        except Exception as ex:
            logger.warning("Failed to load snapshot %s: %s", self.snapshot_path, ex)
            return None
