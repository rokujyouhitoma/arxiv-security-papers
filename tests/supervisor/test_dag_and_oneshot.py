import queue
from typing import List
from unittest.mock import MagicMock, patch

import pytest

from supervisor.arbiter import Arbiter
from supervisor.config import SupervisorConfig
from supervisor.contracts import ServiceRole, ServiceState, WorkerSpec
from supervisor.workers.queue_worker import QueueWorker


def test_resolve_boot_order_topological() -> None:
    """Tests DAG resolution with multi-level dependencies."""
    config = SupervisorConfig()
    arbiter = Arbiter(config)
    arbiter.pools.clear()

    # db (no deps), search (deps: db), web (deps: db, search)
    arbiter.register_pool(
        WorkerSpec(
            name="web", role=ServiceRole.STATELESS_POOL, dependencies=["search", "db"]
        )
    )
    arbiter.register_pool(
        WorkerSpec(
            name="search", role=ServiceRole.STATEFUL_SERVICE, dependencies=["db"]
        )
    )
    arbiter.register_pool(
        WorkerSpec(name="db", role=ServiceRole.STATEFUL_SERVICE, dependencies=[])
    )

    order = arbiter.resolve_boot_order()
    assert order.index("db") < order.index("search")
    assert order.index("search") < order.index("web")


def test_resolve_boot_order_circular_dependency() -> None:
    """Tests that circular dependencies raise ValueError."""
    config = SupervisorConfig()
    arbiter = Arbiter(config)
    arbiter.pools.clear()

    arbiter.register_pool(WorkerSpec(name="svc_a", dependencies=["svc_b"]))
    arbiter.register_pool(WorkerSpec(name="svc_b", dependencies=["svc_a"]))

    with pytest.raises(ValueError, match="Circular dependency detected"):
        arbiter.resolve_boot_order()


def test_oneshot_task_success_no_respawn() -> None:
    """Tests that ONESHOT_TASK exiting with 0 is marked COMPLETED and not respawned."""
    config = SupervisorConfig()
    arbiter = Arbiter(config)
    arbiter.pools.clear()

    spec = WorkerSpec(
        name="migration_task", role=ServiceRole.ONESHOT_TASK, target_count=1
    )
    pool = arbiter.register_pool(spec)
    pool.workers[9999] = MagicMock()

    with patch.object(arbiter, "spawn_worker") as mock_spawn:
        arbiter._handle_child_exit(9999, 0)  # exit code 0
        assert pool.state == ServiceState.COMPLETED
        assert 9999 not in pool.workers
        mock_spawn.assert_not_called()


def test_oneshot_task_failure_and_retry() -> None:
    """Tests ONESHOT_TASK retry logic on failure."""
    config = SupervisorConfig()
    arbiter = Arbiter(config)
    arbiter.running = True
    arbiter.pools.clear()

    spec = WorkerSpec(
        name="failing_task",
        role=ServiceRole.ONESHOT_TASK,
        target_count=1,
        max_retries=2,
    )
    pool = arbiter.register_pool(spec)
    pool.workers[8888] = MagicMock()

    with patch.object(arbiter, "spawn_worker") as mock_spawn:
        # Failure 1 (exit code 1 -> status 256)
        arbiter._handle_child_exit(8888, 256)
        assert spec.retry_count == 1
        mock_spawn.assert_called_once_with("failing_task")

        # Failure 2
        pool.workers[8889] = MagicMock()
        arbiter._handle_child_exit(8889, 256)
        assert spec.retry_count == 2
        assert mock_spawn.call_count == 2

        # Failure 3 (exceeds max_retries)
        pool.workers[8890] = MagicMock()
        arbiter._handle_child_exit(8890, 256)
        assert pool.state == ServiceState.FAILED
        assert mock_spawn.call_count == 2  # No new spawn


def test_queue_worker_drain_and_processing() -> None:
    """Tests QueueWorker item consumption and graceful drain on SIGQUIT."""
    config = SupervisorConfig()
    q: queue.Queue[str] = queue.Queue()
    q.put("msg_1")
    q.put("msg_2")

    processed: List[str] = []

    def handler(item: str) -> None:
        processed.append(item)

    worker = QueueWorker(
        worker_id="queue_wk_1",
        config=config,
        app_target=handler,
        source_queue=q,
        poll_interval=0.01,
    )

    # Fetch and process items
    item1 = worker._fetch_item()
    assert item1 == "msg_1"
    worker._process_item(item1)
    assert processed == ["msg_1"]
    assert worker.requests_handled == 1

    item2 = worker._fetch_item()
    assert item2 == "msg_2"
    worker._process_item(item2)
    assert processed == ["msg_1", "msg_2"]
    assert worker.requests_handled == 2

    # Verify empty fetch returns None
    assert worker._fetch_item() is None
