"""Unit tests for Database IPC Service and Client."""

import os
from typing import Any
from unittest.mock import MagicMock

import pytest

from database.client import DatabaseClient
from database.protocol import VectorDBProtocolError
from database.service import DatabaseLifecycleHook, DatabaseService


def test_database_service_and_client_roundtrip(tmp_path: Any) -> None:
    sock_path = str(tmp_path / "db_test.sock")
    storage_path = str(tmp_path / "papers_test.db")

    service = DatabaseService(
        socket_path=sock_path,
        workspace_dir=str(tmp_path),
        storage_path=storage_path,
    )
    service.start()
    assert os.path.exists(sock_path)

    try:
        client = DatabaseClient(socket_path=sock_path, workspace_dir=str(tmp_path))

        # Ping
        assert client.ping() is True

        # Get Info
        info = client.get_info()
        assert "dimension" in info
        assert "count" in info

        # Insert single vector
        vec = [0.1] * 128
        meta = {
            "id": "paper_001",
            "title": "Zero-Trust Architecture",
            "tags": ["network-security"],
        }
        doc_id = client.insert(vec, meta)
        assert doc_id == "paper_001"

        # Get by ID
        doc = client.get_by_id("paper_001")
        assert doc is not None
        assert doc.get("found") is True

        # Non-existent ID
        assert client.get_by_id("non_existent_id") is None

        # Bulk write
        vecs = [[0.2] * 128, [0.3] * 128]
        metas = [
            {"title": "Paper A", "tags": ["crypto"]},
            {"title": "Paper B", "tags": ["web"]},
        ]
        cnt = client.bulk_write(vecs, metas)
        assert cnt == 2

        # Search KNN
        matches = client.search_knn(vector=vec, top_k=5)
        assert isinstance(matches, list)
        assert len(matches) >= 1

        # Search KNN with text
        matches_text = client.search_knn(text="zero trust", top_k=5)
        assert isinstance(matches_text, list)

        # Execute SQL
        sql_res = client.execute_sql("SELECT COUNT(*) FROM papers;", role="admin")
        assert sql_res.get("status") == "ok"

    finally:
        client.close()
        service.stop()
        assert not os.path.exists(sock_path)


def test_database_client_fallback_when_no_service(tmp_path: Any) -> None:
    sock_path = str(tmp_path / "non_existent_db.sock")
    client = DatabaseClient(socket_path=sock_path, workspace_dir=str(tmp_path))

    # Mock custom handler for fallback
    def mock_dispatch(req: Any) -> Any:
        op = req.get("op")
        if op == "ping":
            return {"status": "ok", "result": {"message": "pong"}}
        if op == "insert":
            return {"status": "ok", "result": {"id": "doc_123"}}
        if op == "get_by_id":
            return {"status": "ok", "result": {"id": "doc_123", "found": True}}
        if op == "bulk_write":
            return {"status": "ok", "result": {"count": 1}}
        if op == "search_knn":
            return {
                "status": "ok",
                "result": {"matches": [{"id": "doc_123", "score": 0.99}]},
            }
        if op == "execute_sql":
            return {"status": "ok", "result": {"rows": [{"cnt": 1}]}}
        return {"status": "error", "error": f"Unknown op: {op}"}

    mock_handler = MagicMock()
    mock_handler.handle_request.side_effect = mock_dispatch
    client._custom_handler = mock_handler

    # Fallback ping
    assert client.ping() is True

    # Fallback insert
    assert client.insert([0.1] * 128, {}) == "doc_123"

    # Fallback get_by_id
    res = client.get_by_id("doc_123")
    assert res is not None
    assert res.get("found") is True

    # Fallback bulk_write
    assert client.bulk_write([[0.1] * 128], [{}]) == 1

    # Fallback search_knn
    matches = client.search_knn(vector=[0.1] * 128, top_k=1)
    assert len(matches) == 1

    # Fallback error handling
    mock_handler.handle_request.side_effect = None
    mock_handler.handle_request.return_value = {
        "status": "error",
        "error": "Query execution failed",
    }
    with pytest.raises(VectorDBProtocolError):
        client.get_info()

    with pytest.raises(VectorDBProtocolError):
        client.insert([0.1] * 128, {})

    client.close()


def test_database_lifecycle_hook(tmp_path: Any) -> None:
    sock_path = str(tmp_path / "hook_db.sock")
    hook = DatabaseLifecycleHook(socket_path=sock_path, workspace_dir=str(tmp_path))

    assert hook.setup() is True
    assert os.path.exists(sock_path)
    assert hook.health_check() is True

    # Flush
    hook.on_flush()

    # Teardown
    hook.teardown()
    assert not os.path.exists(sock_path)
    assert hook.health_check() is False
