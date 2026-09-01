"""Unit tests for Search IPC Service and Client."""

import os
from unittest.mock import MagicMock

from search.client import SearchClient
from search.server.service import SearchService


def test_search_service_and_client_roundtrip(tmp_path) -> None:
    sock_path = str(tmp_path / "search_test.sock")

    # Mock VectorEngine
    mock_engine = MagicMock()
    mock_engine.documents = [
        {"id": "2401.00001", "title": "Test Paper", "tags": ["cryptography"]}
    ]
    mock_engine.documents_by_id = {"2401.00001": mock_engine.documents[0]}
    mock_engine.search_with_profile.return_value = (
        [{"id": "2401.00001", "score": 0.95}],
        {"mode": "hybrid", "total_ms": 2.5},
    )
    mock_engine.search_vector_ann.return_value = [{"id": "2401.00001", "score": 0.9}]
    mock_engine.search_rrf_hybrid.return_value = [{"id": "2401.00001", "score": 0.85}]
    mock_engine.proximity_graph.get_neighbors.return_value = [
        {"id": "2401.00002", "title": "Related Paper"}
    ]
    mock_engine.vector_storage_path = str(tmp_path / "vectors.vdb")
    mock_engine.vector_storage.metadata = {"2401.00001": 0}

    service = SearchService(
        socket_path=sock_path,
        workspace_dir=str(tmp_path),
        vector_engine=mock_engine,
    )
    service.start()
    assert os.path.exists(sock_path)

    try:
        client = SearchClient(socket_path=sock_path, workspace_dir=str(tmp_path))

        # Ping
        assert client.ping() is True

        # Search hybrid, vector, rrf, empty
        assert client.search(query="zero trust", top_k=5)["status"] == "success"
        assert client.search(query="zero trust", mode="vector")["status"] == "success"
        assert client.search(query="zero trust", mode="rrf")["status"] == "success"
        assert client.search(query="")["results"] == []

        # Get Paper
        paper = client.get_paper("2401.00001")
        assert paper is not None
        assert paper["id"] == "2401.00001"

        # Get Nonexistent Paper
        none_paper = client.get_paper("9999.99999")
        assert none_paper is None

        # Get Related
        related_res = client.get_related("2401.00001")
        assert related_res is not None
        assert related_res["status"] == "success"
        assert len(related_res["related_papers"]) == 1

        # Get Related for non-existent paper
        none_related = client.get_related("9999.99999")
        assert none_related is None

        # Get Stats
        stats = client.get_stats()
        assert stats["status"] == "success"
        assert stats["total_papers"] == 1
        assert len(stats["categories"]) == 1

        # Direct service handle_command edge cases
        assert service.handle_command({"cmd": "invalid"})["status"] == "error"
        assert (
            service.handle_command({"cmd": "get_paper", "id": ""})["status"] == "error"
        )
        assert (
            service.handle_command({"cmd": "get_related", "id": ""})["status"]
            == "error"
        )
        assert (
            service.handle_command({"cmd": "get_related", "id": "9999"})["status"]
            == "error"
        )

        # Fallback doc scan in service if not in documents_by_id
        mock_engine.documents_by_id = {}
        assert (
            service.handle_command({"cmd": "get_paper", "id": "2401.00001"})["status"]
            == "success"
        )
    finally:
        client.close()
        service.stop()
        assert not os.path.exists(sock_path)


def test_search_client_fallback_when_no_service(tmp_path) -> None:
    sock_path = str(tmp_path / "non_existent.sock")
    client = SearchClient(
        socket_path=sock_path,
        workspace_dir=str(tmp_path),
        allow_inprocess_fallback=True,
    )

    # Mock fallback engine
    mock_engine = MagicMock()
    mock_engine.documents = [{"id": "2401.00001", "tags": ["web-security"]}]
    mock_engine.documents_by_id = {"2401.00001": mock_engine.documents[0]}
    mock_engine.search_with_profile.return_value = (
        [{"id": "2401.00001", "score": 1.0}],
        {"mode": "hybrid", "total_ms": 1.0},
    )
    mock_engine.search_vector_ann.return_value = [{"id": "2401.00001", "score": 1.0}]
    mock_engine.search_rrf_hybrid.return_value = [{"id": "2401.00001", "score": 1.0}]
    mock_engine.proximity_graph.get_neighbors.return_value = [{"id": "2401.00002"}]
    client._fallback_engine = mock_engine

    # Fallback ping
    assert client.ping() is True

    # Fallback search
    assert client.search(query="test", top_k=10)["status"] == "success"
    assert client.search(query="test", mode="vector")["status"] == "success"
    assert client.search(query="test", mode="rrf")["status"] == "success"
    assert client.search(query="")["results"] == []

    # Fallback get_paper
    paper = client.get_paper("2401.00001")
    assert paper is not None
    assert paper["id"] == "2401.00001"
    assert client.get_paper("non_existent") is None

    # Fallback get_related
    assert client.get_related("2401.00001")["status"] == "success"
    assert client.get_related("non_existent") is None

    # Fallback get_stats
    assert client.get_stats()["status"] == "success"

    # Fallback unknown command
    assert client._fallback_handle_command({"cmd": "unknown"})["status"] == "error"

    client.close()


def test_search_lifecycle_hook(tmp_path) -> None:
    sock_path = str(tmp_path / "hook_search.sock")
    from search.server.service import SearchLifecycleHook

    hook = SearchLifecycleHook(socket_path=sock_path, workspace_dir=str(tmp_path))

    # Setup
    assert hook.setup() is True
    assert os.path.exists(sock_path)
    assert hook.health_check() is True

    # Flush (no-op)
    hook.on_flush()

    # Teardown
    hook.teardown()
    assert not os.path.exists(sock_path)
    assert hook.health_check() is False


def test_search_ipc_pagination_and_total_hits(tmp_path) -> None:
    """Validates pagination offset, limit, and total_hits propagation over Unix domain socket IPC."""
    sock_path = str(tmp_path / "search_pagination.sock")
    mock_engine = MagicMock()
    mock_engine.search_with_profile.return_value = (
        [{"id": f"paper_{i}", "score": 0.9 - i * 0.01} for i in range(5)],
        {
            "mode": "hybrid",
            "total_hits": 42,
            "offset": 10,
            "limit": 5,
            "has_more": True,
        },
    )

    service = SearchService(
        socket_path=sock_path,
        workspace_dir=str(tmp_path),
        vector_engine=mock_engine,
    )
    service.start()

    try:
        client = SearchClient(socket_path=sock_path, workspace_dir=str(tmp_path))
        res = client.search(query="pentest", top_k=5, offset=10)
        assert res["status"] == "success"
        assert res["total"] == 5
        assert res["total_hits"] == 42
        assert res["offset"] == 10
        assert res["limit"] == 5
        assert res["has_more"] is True
        assert len(res["results"]) == 5

        # Verify mock received offset argument
        mock_engine.search_with_profile.assert_called_with(
            query="pentest", top_k=5, category=None, offset=10
        )
    finally:
        client.close()
        service.stop()
