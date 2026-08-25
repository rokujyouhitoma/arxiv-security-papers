"""Unit tests for SearchWorker and SearchLifecycleHook in Process Supervisor."""

import threading
import time
from unittest.mock import MagicMock, patch

from supervisor.config import SupervisorConfig
from supervisor.workers.search_worker import SearchLifecycleHook, SearchWorker


def test_search_lifecycle_hook(tmp_path) -> None:
    sock_path = str(tmp_path / "search_hook_test.sock")
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        search_socket=sock_path,
    )

    with patch("supervisor.workers.search_worker.SearchService") as mock_service_cls:
        mock_service = MagicMock()
        mock_service_cls.return_value = mock_service
        mock_service.handle_command.return_value = {"status": "ok", "message": "pong"}

        hook = SearchLifecycleHook(cfg)
        assert hook.setup() is True
        mock_service.start.assert_called_once()

        assert hook.health_check() is True
        mock_service.handle_command.assert_called_with({"cmd": "ping"})

        hook.on_flush()
        hook.teardown()
        mock_service.stop.assert_called_once()

        # Error cases
        mock_service.start.side_effect = RuntimeError("start fail")
        assert hook.setup() is False

        mock_service.handle_command.side_effect = RuntimeError("ping fail")
        assert hook.health_check() is False

        mock_service.stop.side_effect = RuntimeError("stop fail")
        hook.teardown()


def test_search_worker_run_loop(tmp_path) -> None:
    sock_path = str(tmp_path / "search_worker_test.sock")
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        search_socket=sock_path,
    )
    pulses = []

    with patch("supervisor.workers.search_worker.SearchService") as mock_service_cls:
        mock_service = MagicMock()
        mock_service_cls.return_value = mock_service
        mock_service.handle_command.return_value = {"status": "ok", "message": "pong"}

        worker = SearchWorker(
            worker_id="search_test_01",
            config=cfg,
            pulse_callback=lambda pid, meta: pulses.append(meta),
        )

        t = threading.Thread(target=worker.run, daemon=True)
        t.start()
        time.sleep(0.2)
        assert worker.alive is True
        worker.alive = False
        t.join(timeout=2.0)

        assert len(pulses) > 0
        assert pulses[0]["service"] == "search"
