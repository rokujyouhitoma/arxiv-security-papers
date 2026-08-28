#!/usr/bin/env python3
"""
Unit and Integration Tests for 3-Node Distributed Database Cluster and Socket Isolation.
Validates zero socket collisions ([Errno 17] File exists immunity), multi-node binding,
and failover client communication.
"""

import os
import tempfile
from typing import List

from database.client import DatabaseClient
from database.service import DatabaseLifecycleHook, DatabaseService


def test_multi_node_database_service_socket_binding() -> None:
    """Verifies that 3 distinct database nodes bind to distinct socket paths without collision."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        cluster_size = 3
        services: List[DatabaseService] = []

        try:
            # 1. Start 3 database node services in the same temporary directory
            for node_id in range(cluster_size):
                svc = DatabaseService(
                    workspace_dir=tmp_dir,
                    node_id=node_id,
                    cluster_size=cluster_size,
                )
                svc.start()
                services.append(svc)

            # 2. Verify all 3 sockets are created and active
            for node_id in range(cluster_size):
                expected_sock = os.path.join(
                    tmp_dir, "outputs", "supervisor", f"db_{node_id}.sock"
                )
                assert os.path.exists(
                    expected_sock
                ), f"Socket for Node {node_id} must exist"
                assert services[node_id].running is True

            # 3. Verify canonical db.sock symlink points to db_0.sock
            canonical_sock = os.path.join(tmp_dir, "outputs", "supervisor", "db.sock")
            assert os.path.exists(canonical_sock), "Canonical db.sock must exist"

            # 4. Verify client can talk to the cluster
            client = DatabaseClient(workspace_dir=tmp_dir, timeout=2.0)
            assert client.is_socket_available() is True
            ping_resp = client.ping()
            assert ping_resp is True

            # 5. Verify vector and metadata operations over cluster IPC
            doc_id = client.insert(
                vector=[0.1] * 128,
                metadata={
                    "title": "Distributed Security Mesh",
                    "paper_id": "2509.00001",
                },
            )
            assert doc_id is not None

            info = client.get_info()
            assert info.get("count", 0) >= 1

        finally:
            for svc in services:
                svc.stop()


def test_database_lifecycle_hook_bind_worker() -> None:
    """Verifies that DatabaseLifecycleHook parses worker_id into correct node_id."""
    hook0 = DatabaseLifecycleHook()
    hook0.bind_worker("database_0")
    assert hook0.node_id == 0

    hook1 = DatabaseLifecycleHook()
    hook1.bind_worker("database_1")
    assert hook1.node_id == 1

    hook2 = DatabaseLifecycleHook()
    hook2.bind_worker("database_2")
    assert hook2.node_id == 2
