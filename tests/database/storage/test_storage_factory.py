#!/usr/bin/env python3
"""
Unit tests for StorageEngineFactory (Issue #229 / DSN-05 Section 21.7).
Tests URI auto-detection, engine instantiation, custom registration, and security traversal bounds.
Pure Python, zero external dependencies.
"""

import os
import tempfile

import pytest

from database.storage.factory import (
    StorageEngineFactory,
    StorageFactoryError,
    StorageSecurityError,
)
from database.storage.json_storage import JsonLinesStorage, JsonTableStorage
from database.storage.plain_text_storage import FileBackedPlainTextStorage
from database.storage.storage import VectorStorage


def test_factory_uri_auto_detection_vdb() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "test.vdb")
        engine = StorageEngineFactory.create_from_uri(vdb_path, workspace_dir=tmpdir)
        assert isinstance(engine, VectorStorage)
        assert engine.file_path == vdb_path


def test_factory_uri_auto_detection_jsonl() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        jsonl_path = os.path.join(tmpdir, "audit.jsonl")
        engine = StorageEngineFactory.create_from_uri(jsonl_path, workspace_dir=tmpdir)
        assert isinstance(engine, JsonLinesStorage)
        assert engine.file_path == jsonl_path


def test_factory_uri_auto_detection_json() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        json_path = os.path.join(tmpdir, "catalog.json")
        engine = StorageEngineFactory.create_from_uri(json_path, workspace_dir=tmpdir)
        assert isinstance(engine, JsonTableStorage)
        assert engine.file_path == json_path


def test_factory_uri_auto_detection_directory() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        sub_dir = os.path.join(tmpdir, "okf_papers")
        os.makedirs(sub_dir, exist_ok=True)
        engine = StorageEngineFactory.create_from_uri(sub_dir, workspace_dir=tmpdir)
        assert isinstance(engine, FileBackedPlainTextStorage)
        assert engine.root_dir == sub_dir


def test_factory_create_by_engine_name() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        # 1. binary_vdb
        eng_vdb = StorageEngineFactory.create_by_engine_name(
            "binary_vdb", location=os.path.join(tmpdir, "a.vdb"), workspace_dir=tmpdir
        )
        assert isinstance(eng_vdb, VectorStorage)

        # 2. json_lines
        eng_jl = StorageEngineFactory.create_by_engine_name(
            "json_lines", location=os.path.join(tmpdir, "b.jsonl"), workspace_dir=tmpdir
        )
        assert isinstance(eng_jl, JsonLinesStorage)

        # 3. json_table
        eng_jt = StorageEngineFactory.create_by_engine_name(
            "json_table", location=os.path.join(tmpdir, "c.json"), workspace_dir=tmpdir
        )
        assert isinstance(eng_jt, JsonTableStorage)

        # 4. file_plain_text
        eng_pt = StorageEngineFactory.create_by_engine_name(
            "file_plain_text", location=tmpdir, workspace_dir=tmpdir
        )
        assert isinstance(eng_pt, FileBackedPlainTextStorage)


def test_factory_unknown_engine_raises() -> None:
    with pytest.raises(StorageFactoryError, match="Unknown storage engine"):
        StorageEngineFactory.create_by_engine_name("quantum_db")


def test_factory_unknown_extension_raises() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        odd_file = os.path.join(tmpdir, "data.xyz")
        with pytest.raises(
            StorageFactoryError, match="Cannot determine storage engine"
        ):
            StorageEngineFactory.create_from_uri(odd_file, workspace_dir=tmpdir)


def test_factory_custom_engine_registration() -> None:
    class DummyEngine:
        def __init__(self, loc: str) -> None:
            self.loc = loc

    StorageEngineFactory.register_engine(
        "dummy_custom", lambda loc, **kw: DummyEngine(str(loc))
    )
    with tempfile.TemporaryDirectory() as tmpdir:
        target = os.path.join(tmpdir, "dummy.bin")
        engine = StorageEngineFactory.create_by_engine_name(
            "dummy_custom", location=target, workspace_dir=tmpdir
        )
        assert isinstance(engine, DummyEngine)
        assert engine.loc == target


def test_factory_path_traversal_rejection() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        workspace = os.path.join(tmpdir, "workspace")
        outside = os.path.join(tmpdir, "secret.vdb")
        os.makedirs(workspace, exist_ok=True)

        with pytest.raises(StorageSecurityError, match="escapes workspace boundary"):
            StorageEngineFactory.create_from_uri(outside, workspace_dir=workspace)
