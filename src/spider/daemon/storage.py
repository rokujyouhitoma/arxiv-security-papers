#!/usr/bin/env python3
"""
Database persistence storage for resident Spider Daemon executions.
Maintains crawler execution history, live status, and metrics in pure-Python Vector DB container (.vdb).
"""

from __future__ import annotations

import datetime
import json
import os
from typing import Any, Dict, List, Optional

from database.ipc.driver import Connection, connect

from .contracts import CrawlJob, CrawlResult


def _utc_now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


class SpiderExecutionStorage:
    """
    Manages persistent execution logs and operational status for crawlers.
    Pure-Python Vector Database (.vdb / OKFMTC01) backed implementation.
    """

    DEFAULT_SPIDERS = ("arxiv", "cwe", "cve_nvd", "cisa_kev")

    def __init__(self, db_path: Optional[str] = None) -> None:
        if db_path is None:
            base_dir = os.path.abspath(
                os.path.join(
                    os.path.dirname(
                        os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
                    ),
                    "outputs",
                    "database",
                )
            )
            os.makedirs(base_dir, exist_ok=True)
            self.db_path = os.path.join(base_dir, "spider_execution.vdb")
        else:
            os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)
            self.db_path = db_path

        self._init_tables()

    def _get_connection(self) -> Connection:
        return connect(database=self.db_path)

    def _init_tables(self) -> None:
        with self._get_connection() as conn:
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE IF NOT EXISTS spider_execution_logs (
                    job_id TEXT,
                    spider_name TEXT,
                    status TEXT,
                    started_at TEXT,
                    finished_at TEXT,
                    duration_seconds REAL,
                    item_count INTEGER,
                    http_status_counts TEXT,
                    error_message TEXT,
                    params TEXT
                )
                """)
            conn.commit()

    def record_start(self, job: CrawlJob) -> None:
        """Records the beginning of a crawl job with RUNNING status."""
        params_json = json.dumps(job.params or {})
        with self._get_connection() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                REPLACE INTO spider_execution_logs
                (job_id, spider_name, status, started_at, params)
                VALUES (?, ?, 'RUNNING', ?, ?)
                """,
                (job.job_id, job.spider_name, _utc_now_iso(), params_json),
            )
            conn.commit()

    def record_finish(self, result: CrawlResult) -> None:
        """Updates the execution log entry with final status and statistics."""
        status = "SUCCESS" if result.success else "FAILED"
        stats_json = json.dumps(result.stats or {})
        with self._get_connection() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                UPDATE spider_execution_logs
                SET status = ?,
                    finished_at = ?,
                    duration_seconds = ?,
                    item_count = ?,
                    http_status_counts = ?,
                    error_message = ?
                WHERE job_id = ?
                """,
                (
                    status,
                    _utc_now_iso(),
                    result.duration_seconds,
                    result.item_count,
                    stats_json,
                    result.error,
                    result.job_id,
                ),
            )
            conn.commit()

    def _rows_to_dicts(self, cur: Any, rows: List[Any]) -> List[Dict[str, Any]]:
        cols = [d[0] for d in cur.description] if cur.description else []
        return [dict(zip(cols, r)) for r in rows]

    def list_history(
        self, limit: int = 20, spider_name: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Retrieves recent execution history, optionally filtered by spider name."""
        with self._get_connection() as conn:
            cur = conn.cursor()
            if spider_name:
                cur.execute(
                    """
                    SELECT * FROM spider_execution_logs
                    WHERE spider_name = ?
                    ORDER BY started_at DESC
                    LIMIT ?
                    """,
                    (spider_name, max(1, limit)),
                )
            else:
                cur.execute(
                    """
                    SELECT * FROM spider_execution_logs
                    ORDER BY started_at DESC
                    LIMIT ?
                    """,
                    (max(1, limit),),
                )
            rows = cur.fetchall()
            return self._rows_to_dicts(cur, rows)

    def _query_latest_row(
        self, conn: Connection, name: str
    ) -> Optional[Dict[str, Any]]:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT * FROM spider_execution_logs
            WHERE spider_name = ?
            ORDER BY started_at DESC
            LIMIT 1
            """,
            (name,),
        )
        row = cur.fetchone()
        if not row:
            return None
        cols = [d[0] for d in cur.description] if cur.description else []
        return dict(zip(cols, row))

    def _build_spider_status(
        self, name: str, latest: Optional[Dict[str, Any]]
    ) -> Dict[str, Any]:
        if not latest:
            return {
                "spider_name": name,
                "status": "IDLE",
                "last_run": None,
                "duration_seconds": 0.0,
                "item_count": 0,
                "error_message": None,
            }
        return {
            "spider_name": name,
            "status": latest.get("status", "IDLE"),
            "last_run": latest.get("started_at"),
            "finished_at": latest.get("finished_at"),
            "duration_seconds": latest.get("duration_seconds", 0.0),
            "item_count": latest.get("item_count", 0),
            "error_message": latest.get("error_message"),
        }

    def get_status_summary(self) -> Dict[str, Any]:
        """Returns the latest operational status for all known spiders."""
        summary: Dict[str, Any] = {}
        with self._get_connection() as conn:
            for name in self.DEFAULT_SPIDERS:
                latest = self._query_latest_row(conn, name)
                summary[name] = self._build_spider_status(name, latest)
        return summary
