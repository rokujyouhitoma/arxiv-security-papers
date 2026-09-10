#!/usr/bin/env python3
"""
Pipeline State and Audit Lifecycle Management Subsystem.
Integrates JsonLinesStorage and JsonTableStorage for:
  - O(1) deduplication of processed papers
  - Append-only execution history (pipeline_runs)
  - Automatic Markdown projection to outputs/log.md
  - Migration from legacy processed_papers.json
Conforms to DSN-03, DSN-05 Section 21, DSN-10 Section 13, and zero-mock rule.
"""

import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set

from database.storage.json_storage import JsonLinesStorage, JsonTableStorage


class PipelineStateManager:
    """
    Central coordinator for pipeline lifecycle state, paper catalogs,
    and execution audit trails.
    """

    _instance: Optional["PipelineStateManager"] = None

    def __init__(self, db_dir: str = "outputs/database") -> None:
        self.db_dir = os.path.abspath(db_dir)
        self.runs_file = os.path.join(self.db_dir, "pipeline_state.jsonl")
        self.catalog_file = os.path.join(self.db_dir, "papers_catalog.json")

        self.runs_storage = JsonLinesStorage(self.runs_file)
        self.catalog_storage = JsonTableStorage(
            self.catalog_file, primary_key="clean_id"
        )
        self._arxiv_index: Set[str] = set()
        self._index_initialized: bool = False

    @classmethod
    def get_instance(cls, db_dir: str = "outputs/database") -> "PipelineStateManager":
        """Singleton accessor for pipeline state manager."""
        if cls._instance is None or cls._instance.db_dir != os.path.abspath(db_dir):
            cls._instance = cls(db_dir)
        return cls._instance

    @classmethod
    def reset_instance(cls) -> None:
        """Resets singleton instance for testing."""
        cls._instance = None

    def _ensure_arxiv_index(self) -> None:
        if self._index_initialized:
            return
        for rec in self.catalog_storage.all_records():
            aid = rec.get("arxiv_id")
            if aid:
                self._arxiv_index.add(str(aid))
            clean_id = rec.get("clean_id")
            if clean_id:
                self._arxiv_index.add(str(clean_id))
        self._index_initialized = True

    @staticmethod
    def to_clean_id(raw_id: str) -> str:
        """Converts arXiv ID (e.g. '2608.13465v1') to clean ID ('2608_13465')."""
        base = raw_id.split("v")[0] if "v" in raw_id else raw_id
        return base.replace(".", "_").strip()

    def is_paper_processed(self, paper_id: str) -> bool:
        """O(1) check whether an arXiv paper has been processed."""
        self._ensure_arxiv_index()
        raw_key = paper_id.strip()
        if raw_key in self._arxiv_index:
            return True
        clean_key = self.to_clean_id(raw_key)
        return clean_key in self._arxiv_index

    @classmethod
    def _resolve_clean_id(cls, raw_id: str, clean_id: str) -> str:
        if clean_id:
            return clean_id
        return cls.to_clean_id(raw_id) if raw_id else ""

    def _normalize_paper_meta(
        self, paper_meta: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        raw_id = str(paper_meta.get("arxiv_id", ""))
        clean_id = self._resolve_clean_id(raw_id, str(paper_meta.get("clean_id", "")))
        if not clean_id:
            return None

        record = dict(paper_meta)
        record["clean_id"] = clean_id
        if "arxiv_id" not in record and raw_id:
            record["arxiv_id"] = raw_id
        return record

    def register_paper(
        self, paper_meta: Dict[str, Any], auto_flush: bool = True
    ) -> None:
        """Registers or updates a paper in the catalog."""
        self._ensure_arxiv_index()
        record = self._normalize_paper_meta(paper_meta)
        if record is None:
            return

        self.catalog_storage.upsert(record, auto_flush=auto_flush)
        clean_id = record["clean_id"]
        self._arxiv_index.add(clean_id)
        if "arxiv_id" in record:
            self._arxiv_index.add(record["arxiv_id"])

    def record_run_start(self, run_id: str, category: str = "cs.CR") -> None:
        """Records the beginning of a pipeline execution batch."""
        entry = {
            "run_id": run_id,
            "event": "START",
            "timestamp_utc": datetime.now(timezone.utc).strftime(
                "%Y-%m-%d %H:%M:%S UTC"
            ),
            "category": category,
            "status": "RUNNING",
        }
        self.runs_storage.append(entry)

    def record_run_complete(
        self,
        run_id: str,
        status: str,
        fetched: int,
        processed: int,
        duration_sec: float,
        details: str = "",
    ) -> None:
        """Records the completion of a pipeline execution batch."""
        entry = {
            "run_id": run_id,
            "event": "COMPLETE",
            "timestamp_utc": datetime.now(timezone.utc).strftime(
                "%Y-%m-%d %H:%M:%S UTC"
            ),
            "status": status,
            "papers_fetched": fetched,
            "papers_processed": processed,
            "duration_sec": round(duration_sec, 2),
            "details": details,
        }
        self.runs_storage.append(entry)

    def get_recent_runs(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Retrieves recent completed runs in reverse chronological order."""
        return self.runs_storage.scan(
            predicate=lambda r: r.get("event") == "COMPLETE" or "papers_processed" in r,
            limit=limit,
            reverse=True,
        )

    @staticmethod
    def _render_run_row(run: Dict[str, Any]) -> str:
        rid = run.get("run_id", "-")
        ts = run.get("timestamp_utc", "-")
        st = run.get("status", "UNKNOWN")
        cat = run.get("category", "cs.CR")
        fetched = run.get("papers_fetched", 0)
        proc = run.get("papers_processed", 0)
        dur = run.get("duration_sec", 0.0)
        details = run.get("details", "").replace("\n", " ")
        return (
            f"| `{rid}` | {ts} | **{st}** | {cat} "
            f"| {fetched} | {proc} | {dur}s | {details} |"
        )

    def project_log_markdown(
        self, output_path: str = "outputs/log.md", limit: int = 50
    ) -> None:
        """
        Projects recent pipeline execution runs into outputs/log.md.
        Maintains complete transparency on GitHub with zero external DB.
        """
        recent = self.get_recent_runs(limit=limit)
        header = (
            "# パイプライン実行ログ台帳 (Pipeline Run Ledger)\n\n"
            f"最終投影日時: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}\n\n"
            "| 実行ID | 実行日時 (UTC) | ステータス | カテゴリ | 取得件数 | 処理件数 | 所要時間 | 備考 |\n"
            "| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |\n"
        )
        rows = [self._render_run_row(r) for r in recent]
        body = header + "\n".join(rows) + "\n"

        out_abs = os.path.abspath(output_path)
        os.makedirs(os.path.dirname(out_abs), exist_ok=True)
        tmp_path = f"{out_abs}.tmp.{os.getpid()}"
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.write(body)
        os.replace(tmp_path, out_abs)

    def _convert_legacy_entry(self, aid: str, item: Any) -> Dict[str, Any]:
        cid = self.to_clean_id(aid)
        rec = {"clean_id": cid, "arxiv_id": aid}
        if isinstance(item, dict):
            rec.update(item)
        return rec

    def _parse_legacy_dict(self, mapping: Dict[str, Any]) -> List[Dict[str, Any]]:
        return [self._convert_legacy_entry(aid, item) for aid, item in mapping.items()]

    def _parse_legacy_list(self, items: List[Any]) -> List[Dict[str, Any]]:
        records: List[Dict[str, Any]] = []
        for item in items:
            if isinstance(item, dict):
                aid = str(item.get("arxiv_id", item.get("clean_id", "")))
                if aid:
                    records.append(self._convert_legacy_entry(aid, item))
        return records

    def _parse_legacy_raw(self, raw_data: Any) -> List[Dict[str, Any]]:
        if isinstance(raw_data, dict):
            return self._parse_legacy_dict(raw_data)
        if isinstance(raw_data, list):
            return self._parse_legacy_list(raw_data)
        return []

    def migrate_legacy_processed_papers(
        self, legacy_path: str = "processed_papers.json"
    ) -> int:
        """
        Migrates records from legacy processed_papers.json if catalog is empty.
        Returns count of migrated papers.
        """
        if self.catalog_storage.count() > 0 or not os.path.exists(legacy_path):
            return 0

        with open(legacy_path, "r", encoding="utf-8") as f:
            raw_data = json.load(f)

        records = self._parse_legacy_raw(raw_data)
        if records:
            self.catalog_storage.upsert_many(records, auto_flush=True)
            self._index_initialized = False
            self._ensure_arxiv_index()

        return len(records)
