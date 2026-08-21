"""
Tests for CoreAdmin and IndexSnapshot (src/search/platform/admin/).
"""

import os
import shutil
import tempfile

from search.engine.index import Segment
from search.platform.admin import CoreAdmin, IndexSnapshot


def test_core_admin_status_and_ping():
    seg = Segment("core_seg_1")
    seg.add_document(
        0, fields={"title": "Test Paper"}, analyzed_fields={"title": ["test", "paper"]}
    )

    admin = CoreAdmin("security_core", seg)
    ping_res = admin.ping()
    assert ping_res["status"] == "OK"
    assert ping_res["core"] == "security_core"

    status = admin.get_status()
    assert status["core"] == "security_core"
    assert status["doc_count"] == 1
    assert status["live_docs"] == 1


def test_index_snapshot_lifecycle():
    temp_dir = tempfile.mkdtemp()
    try:
        snapshot_mgr = IndexSnapshot(temp_dir)
        seg = Segment("seg_snap")
        seg.add_document(0, fields={"title": "Snapshot Test"}, analyzed_fields={})

        snap_path = snapshot_mgr.create_snapshot(seg, "snap_v1")
        assert os.path.exists(snap_path)

        snaps = snapshot_mgr.list_snapshots()
        assert len(snaps) == 1
        assert snaps[0]["snapshot_name"] == "snap_v1"

        deleted = snapshot_mgr.delete_snapshot("snap_v1")
        assert deleted is True
        assert len(snapshot_mgr.list_snapshots()) == 0
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
