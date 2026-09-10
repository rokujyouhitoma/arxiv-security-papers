#!/usr/bin/env python3
"""
Unit tests for JsonLinesStorage and JsonTableStorage.
Tests O(1) in-memory index, append-only JSONL, atomic flush, and error handling.
Pure Python, zero external dependencies.
"""

import os
import tempfile

import pytest

from database.storage.json_storage import (
    JsonLinesStorage,
    JsonStorageError,
    JsonTableStorage,
)


def test_json_lines_storage_append_and_scan() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        jsonl_path = os.path.join(tmp_dir, "test_runs.jsonl")
        storage = JsonLinesStorage(jsonl_path)

        assert storage.count() == 0
        assert storage.scan() == []

        storage.append({"run_id": "run_01", "status": "SUCCESS", "count": 10})
        storage.append({"run_id": "run_02", "status": "FAILED", "count": 0})
        storage.append({"run_id": "run_03", "status": "SUCCESS", "count": 15})

        assert storage.count() == 3

        all_runs = storage.scan()
        assert len(all_runs) == 3
        assert all_runs[0]["run_id"] == "run_01"
        assert all_runs[2]["run_id"] == "run_03"

        # Test predicate filter
        success_runs = storage.scan(predicate=lambda r: r.get("status") == "SUCCESS")
        assert len(success_runs) == 2
        assert all(r["status"] == "SUCCESS" for r in success_runs)

        # Test reverse and limit
        latest = storage.scan(limit=2, reverse=True)
        assert len(latest) == 2
        assert latest[0]["run_id"] == "run_03"
        assert latest[1]["run_id"] == "run_02"


def test_json_lines_storage_append_many() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        jsonl_path = os.path.join(tmp_dir, "batch.jsonl")
        storage = JsonLinesStorage(jsonl_path)

        batch = [{"id": i, "val": f"item_{i}"} for i in range(50)]
        storage.append_many(batch)

        assert storage.count() == 50
        records = storage.scan()
        assert len(records) == 50
        assert records[49]["val"] == "item_49"


def test_json_table_storage_upsert_and_lookup() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "papers_catalog.json")
        storage = JsonTableStorage(json_path, primary_key="clean_id")

        assert storage.count() == 0
        assert not storage.contains_pk("2609_0001")

        p1 = {
            "clean_id": "2609_0001",
            "arxiv_id": "2609.0001v1",
            "title": "Quantum Post-Quantum Cryptography",
        }
        storage.upsert(p1)

        assert storage.count() == 1
        assert storage.contains_pk("2609_0001")
        retrieved = storage.get_by_pk("2609_0001")
        assert retrieved is not None
        assert retrieved["title"] == "Quantum Post-Quantum Cryptography"

        # Test in-place update
        p1_updated = dict(p1)
        p1_updated["title"] = "Quantum Post-Quantum Cryptography (Updated)"
        storage.upsert(p1_updated)

        assert storage.count() == 1
        assert storage.get_by_pk("2609_0001")["title"] == (
            "Quantum Post-Quantum Cryptography (Updated)"
        )


def test_json_table_storage_batch_upsert_and_delete() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "batch_catalog.json")
        storage = JsonTableStorage(json_path, primary_key="arxiv_id")

        records = [
            {"arxiv_id": f"2609.{1000+i}", "title": f"Paper {i}"} for i in range(20)
        ]
        storage.upsert_many(records, auto_flush=True)

        assert storage.count() == 20
        assert storage.contains_pk("2609.1005")

        deleted = storage.delete("2609.1005")
        assert deleted is True
        assert storage.count() == 19
        assert not storage.contains_pk("2609.1005")

        # Delete non-existent
        assert storage.delete("non_existent") is False


def test_json_table_storage_atomic_flush_and_reload() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "persistence.json")
        storage1 = JsonTableStorage(json_path, primary_key="clean_id")

        storage1.upsert({"clean_id": "p_01", "name": "One"})
        storage1.upsert({"clean_id": "p_02", "name": "Two"})

        # Reopen with fresh instance
        storage2 = JsonTableStorage(json_path, primary_key="clean_id")
        assert storage2.count() == 2
        assert storage2.contains_pk("p_01")
        assert storage2.contains_pk("p_02")
        assert storage2.get_by_pk("p_02")["name"] == "Two"


def test_json_table_storage_error_handling() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        json_path = os.path.join(tmp_dir, "err_test.json")
        storage = JsonTableStorage(json_path, primary_key="clean_id")

        # Missing PK error
        with pytest.raises(JsonStorageError, match="Record missing primary key"):
            storage.upsert({"title": "No PK"})

        # Corrupted JSON file
        with open(json_path, "w", encoding="utf-8") as f:
            f.write("invalid json { content")

        bad_storage = JsonTableStorage(json_path, primary_key="clean_id")
        with pytest.raises(JsonStorageError, match="Corrupt JSON table"):
            bad_storage.contains_pk("anything")
