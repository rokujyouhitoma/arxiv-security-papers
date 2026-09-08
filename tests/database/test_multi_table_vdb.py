#!/usr/bin/env python3
"""
Unit tests for MultiTableVectorStorage (OKFMTC01 container format).
"""

import os

import pytest

from database.storage.multi_storage import (
    MultiTableSecurityError,
    MultiTableVectorStorage,
)


def test_multi_table_create_and_list() -> None:
    storage = MultiTableVectorStorage(":memory:")
    storage.create_table("vertices", dim=16)
    storage.create_table("edges", dim=8)
    assert storage.has_table("vertices")
    assert storage.has_table("edges")
    assert storage.list_tables() == ["edges", "vertices"]


def test_multi_table_heterogeneous_dimensions() -> None:
    storage = MultiTableVectorStorage(":memory:")
    v_tbl = storage.create_table("vertices", dim=16)
    e_tbl = storage.create_table("edges", dim=8)
    assert v_tbl.dim == 16
    assert e_tbl.dim == 8


def test_multi_table_write_and_read() -> None:
    storage = MultiTableVectorStorage(":memory:")
    v_tbl = storage.create_table("vertices", dim=4)
    v_tbl.write_all([(1.0, 2.0, 3.0, 4.0)], [{"id": "v1", "name": "Node1"}])
    e_tbl = storage.create_table("edges", dim=4)
    e_tbl.write_all([(0.1, 0.2, 0.3, 0.4)], [{"src_id": "v1", "dst_id": "v2"}])
    assert v_tbl.count == 1
    assert e_tbl.count == 1
    assert v_tbl.get_metadata(0)["name"] == "Node1"


def test_multi_table_save_and_reload_disk(tmp_path: object) -> None:
    fpath = os.path.join(str(tmp_path), "container.vdb")
    storage = MultiTableVectorStorage(fpath)
    v_tbl = storage.create_table("vertices", dim=4)
    v_tbl.write_all([(1.0, 2.0, 3.0, 4.0)], [{"id": "v1"}])
    storage.save()
    assert os.path.exists(fpath)

    new_storage = MultiTableVectorStorage(fpath)
    assert new_storage.list_tables() == ["vertices"]
    assert new_storage.get_table("vertices").count == 1


def test_multi_table_drop_table() -> None:
    storage = MultiTableVectorStorage(":memory:")
    storage.create_table("temp_table", dim=4)
    assert storage.has_table("temp_table")
    assert storage.drop_table("temp_table")
    assert not storage.has_table("temp_table")


def test_multi_table_tamper_magic_detection() -> None:
    storage = MultiTableVectorStorage(":memory:")
    storage.create_table("tbl1", dim=4)
    raw = bytearray(storage.to_bytes())
    raw[0:4] = b"EVIL"
    with pytest.raises(MultiTableSecurityError):
        new_storage = MultiTableVectorStorage(":memory:")
        new_storage.load_from_bytes(bytes(raw))


def test_multi_table_tamper_crc_detection() -> None:
    storage = MultiTableVectorStorage(":memory:")
    storage.create_table("tbl1", dim=4)
    raw = bytearray(storage.to_bytes())
    # Corrupt catalog JSON at the end
    raw[-2] = (raw[-2] + 1) % 256
    with pytest.raises(MultiTableSecurityError):
        new_storage = MultiTableVectorStorage(":memory:")
        new_storage.load_from_bytes(bytes(raw))
