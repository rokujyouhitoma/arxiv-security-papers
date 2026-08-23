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
