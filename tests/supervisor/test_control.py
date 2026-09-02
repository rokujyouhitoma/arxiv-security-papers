"""Unit tests for Unix domain socket ControlServer and ControlClient IPC."""

import os
from typing import Any, Dict

from supervisor.control import ControlClient, ControlServer


def test_control_server_client_roundtrip(tmp_path) -> None:
    sock_path = str(tmp_path / "test_control.sock")

    def mock_handler(req: Dict[str, Any]) -> Dict[str, Any]:
        cmd = req.get("cmd")
        if cmd == "ping":
            return {"status": "ok", "message": "pong"}
        if cmd == "status":
            return {"status": "ok", "workers": 4}
        if cmd == "scale":
            return {"status": "ok", "scaled": req.get("workers")}
        if cmd == "restart":
            return {"status": "ok", "restarted": req.get("target", "all")}
        return {"status": "error", "error": "unknown"}

    server = ControlServer(socket_path=sock_path, command_handler=mock_handler)
    server.start()

    try:
        client = ControlClient(socket_path=sock_path, timeout=2.0)
        assert client.ping() is True

        st = client.get_status()
        assert st["status"] == "ok"
        assert st["workers"] == 4

        scale_res = client.scale_workers(8)
        assert scale_res["status"] == "ok"
        assert scale_res["scaled"] == 8

        restart_res = client.restart(target="search")
        assert restart_res["status"] == "ok"
        assert restart_res["restarted"] == "search"

        reload_res = client.reload()
        assert reload_res["status"] == "error"
    finally:
        server.stop()
        assert not os.path.exists(sock_path)


def test_control_client_socket_not_found(tmp_path) -> None:
    non_existent = str(tmp_path / "missing.sock")
    client = ControlClient(socket_path=non_existent, timeout=1.0)
    assert client.ping() is False
    res = client.get_status()
    assert res["status"] == "error"
    assert "not found" in res["error"]


def test_control_server_close_in_child_does_not_unlink(tmp_path) -> None:
    sock_path = str(tmp_path / "test_child_safe.sock")
    server = ControlServer(
        socket_path=sock_path, command_handler=lambda req: {"status": "ok"}
    )
    server.start()

    try:
        assert os.path.exists(sock_path)
        # Simulate fork and child worker cleanup
        server.close_in_child()
        # Simulate child calling atexit
        server._atexit_cleanup()
        # Socket must STILL exist because creator pid does not match or atexit was unregistered
        assert os.path.exists(sock_path)
    finally:
        server.stop()
        assert not os.path.exists(sock_path)
