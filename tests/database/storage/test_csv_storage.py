#!/usr/bin/env python3
"""
tests/database/storage/test_csv_storage.py

Unit tests for pure-Python CsvTableStorage engine and StorageEngineFactory integration.
"""

from __future__ import annotations

import csv
import os

import pytest

from database.storage import CsvStorageError, CsvTableStorage, StorageEngineFactory


@pytest.fixture
def temp_csv_path(tmp_path):
    return str(tmp_path / "test_table.csv")


def test_csv_table_storage_crud(temp_csv_path):
    storage = CsvTableStorage(file_path=temp_csv_path, primary_key="cwe_id")
    assert storage.count() == 0
    assert not storage.contains_pk("CWE-79")

    # Upsert single record
    rec1 = {
        "cwe_id": "CWE-79",
        "name": "Cross-site Scripting",
        "is_top25": 1,
        "description": "Improper neutralization of input during web page generation",
    }
    storage.upsert(rec1)

    assert storage.count() == 1
    assert storage.contains_pk("CWE-79")
    retrieved = storage.get_by_pk("CWE-79")
    assert retrieved is not None
    assert retrieved["cwe_id"] == "CWE-79"
    assert retrieved["name"] == "Cross-site Scripting"
    assert retrieved["is_top25"] == 1

    # Check file exists and has headers
    assert os.path.exists(temp_csv_path)
    with open(temp_csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        headers = next(reader)
        assert "cwe_id" in headers
        assert "name" in headers

    # Upsert many
    rec2 = {
        "cwe_id": "CWE-89",
        "name": "SQL Injection",
        "is_top25": 1,
        "description": "Improper neutralization of special elements used in an SQL Command",
    }
    rec3 = {
        "cwe_id": "CWE-20",
        "name": "Improper Input Validation",
        "is_top25": 1,
        "description": "Input validation error",
    }
    storage.upsert_many([rec2, rec3])
    assert storage.count() == 3

    # All records sorted by PK
    all_recs = storage.all_records()
    assert len(all_recs) == 3
    assert [r["cwe_id"] for r in all_recs] == ["CWE-20", "CWE-79", "CWE-89"]

    # Delete
    deleted = storage.delete("CWE-79")
    assert deleted is True
    assert storage.count() == 2
    assert not storage.contains_pk("CWE-79")

    # Re-instantiate from file (persistence test)
    storage2 = CsvTableStorage(file_path=temp_csv_path, primary_key="cwe_id")
    assert storage2.count() == 2
    assert storage2.contains_pk("CWE-89")
    assert storage2.get_by_pk("CWE-89")["name"] == "SQL Injection"


def test_csv_table_storage_special_characters(temp_csv_path):
    storage = CsvTableStorage(file_path=temp_csv_path, primary_key="id")
    special_text = 'Line 1\nLine 2 with "quotes", commas, and UTF-8 日本語'
    storage.upsert({"id": "item1", "notes": special_text, "tags": ["tag1", "tag2"]})

    # Reload from file
    storage2 = CsvTableStorage(file_path=temp_csv_path, primary_key="id")
    rec = storage2.get_by_pk("item1")
    assert rec is not None
    assert rec["notes"] == special_text
    assert rec["tags"] == ["tag1", "tag2"]


def test_csv_table_storage_missing_pk(temp_csv_path):
    storage = CsvTableStorage(file_path=temp_csv_path, primary_key="id")
    with pytest.raises(CsvStorageError):
        storage.upsert({"name": "No ID"})


def test_factory_integration(temp_csv_path):
    # Using engine name
    storage1 = StorageEngineFactory.create_by_engine_name(
        "csv_table", location=temp_csv_path, primary_key="cwe_id"
    )
    assert isinstance(storage1, CsvTableStorage)
    storage1.upsert({"cwe_id": "CWE-1", "name": "Test"})

    # Using URI auto-detection (.csv)
    storage2 = StorageEngineFactory.create_from_uri(temp_csv_path, primary_key="cwe_id")
    assert isinstance(storage2, CsvTableStorage)
    assert storage2.contains_pk("CWE-1")
