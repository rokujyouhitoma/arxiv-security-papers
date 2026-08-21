#!/usr/bin/env python3
"""
System Administration, Metrics, and Index Snapshot/Restore (Solr Paradigm).
"""

import json
import os
import shutil
import time
from typing import Any, Dict, List, Optional

from ...engine.index import Segment


class IndexSnapshot:
    """Manages index snapshot creation, listing, and restoration for replication."""

    def __init__(self, base_snapshot_dir: str) -> None:
        self.base_snapshot_dir = os.path.abspath(base_snapshot_dir)
        os.makedirs(self.base_snapshot_dir, exist_ok=True)

    def create_snapshot(
        self, segment: Segment, snapshot_name: Optional[str] = None
    ) -> str:
        s_name = snapshot_name or f"snapshot_{int(time.time())}"
        target_dir = os.path.join(self.base_snapshot_dir, s_name)
        os.makedirs(target_dir, exist_ok=True)

        meta = {
            "snapshot_name": s_name,
            "created_at": time.time(),
            "doc_count": segment.doc_count,
            "live_docs": segment.live_docs_count(),
            "deleted_docs": segment.deleted_docs.count(),
        }
        with open(
            os.path.join(target_dir, "metadata.json"), "w", encoding="utf-8"
        ) as f:
            json.dump(meta, f, indent=2, ensure_ascii=False)

        return target_dir

    def list_snapshots(self) -> List[Dict[str, Any]]:
        snapshots: List[Dict[str, Any]] = []
        if not os.path.exists(self.base_snapshot_dir):
            return []
        for s_name in sorted(os.listdir(self.base_snapshot_dir)):
            meta_path = os.path.join(self.base_snapshot_dir, s_name, "metadata.json")
            if os.path.exists(meta_path):
                with open(meta_path, "r", encoding="utf-8") as f:
                    snapshots.append(json.load(f))
        return snapshots

    def delete_snapshot(self, snapshot_name: str) -> bool:
        target_dir = os.path.join(self.base_snapshot_dir, snapshot_name)
        if os.path.exists(target_dir):
            shutil.rmtree(target_dir)
            return True
        return False


class CoreAdmin:
    """Manages search core lifecycle, status monitoring, and ping health checks."""

    def __init__(
        self, core_name: str, segment: Segment, snapshot_dir: Optional[str] = None
    ) -> None:
        self.core_name = core_name
        self.segment = segment
        self.uptime_start = time.time()
        self.snapshot_manager = IndexSnapshot(snapshot_dir or "/tmp/search_snapshots")

    def ping(self) -> Dict[str, Any]:
        return {"status": "OK", "core": self.core_name, "time": time.time()}

    def get_status(self) -> Dict[str, Any]:
        return {
            "core": self.core_name,
            "uptime_seconds": time.time() - self.uptime_start,
            "doc_count": self.segment.doc_count,
            "live_docs": self.segment.live_docs_count(),
            "deleted_docs": self.segment.deleted_docs.count(),
            "terms_count": len(self.segment.postings),
        }
