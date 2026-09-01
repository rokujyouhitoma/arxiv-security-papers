#!/usr/bin/env python3
"""
IPC Control Interface Server and Client for Process Supervisor.
Provides Unix domain socket control channel for live status querying,
dynamic worker scaling, rolling configuration reloads, and graceful shutdowns.
"""

from __future__ import annotations

import atexit
import json
import os
import socket
import threading
from typing import Any, Callable, Dict, Optional


class ControlServer:
    """
    Asynchronous Unix Domain Socket Server listening for administrative control commands.
    """

    def __init__(
        self,
        socket_path: str,
        command_handler: Callable[[Dict[str, Any]], Dict[str, Any]],
    ) -> None:
        self.socket_path = socket_path
        self.command_handler = command_handler
        self._server_sock: Optional[socket.socket] = None
        self._thread: Optional[threading.Thread] = None
        self._running = False
        self._creator_pid = os.getpid()

    def start(self) -> None:
        """Binds to the Unix socket and starts the listener thread."""
        os.makedirs(os.path.dirname(os.path.abspath(self.socket_path)), exist_ok=True)
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass

        self._server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._server_sock.bind(self.socket_path)
        self._server_sock.listen(16)
        self._server_sock.settimeout(0.5)
        self._running = True

        # Ensure the socket file is removed even on abnormal process exit
        # (e.g. SIGKILL reaching the Arbiter or an unhandled BaseException).
        atexit.register(self._atexit_cleanup)

        self._thread = threading.Thread(target=self._listen_loop, daemon=True)
        self._thread.start()

    def _listen_loop(self) -> None:
        while self._running and self._server_sock:
            try:
                client_sock, _ = self._server_sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break

            client_thread = threading.Thread(
                target=self._handle_client, args=(client_sock,), daemon=True
            )
            client_thread.start()

    @staticmethod
    def _recv_line(sock: socket.socket) -> bytes:
        raw_data = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            raw_data += chunk
            if b"\n" in raw_data:
                break
        return raw_data

    def _handle_client(self, client_sock: socket.socket) -> None:
        client_sock.settimeout(3.0)
        try:
            raw_data = self._recv_line(client_sock)
            if not raw_data:
                return
            req = json.loads(raw_data.decode("utf-8").strip())
            resp = self.command_handler(req)
            resp_bytes = (json.dumps(resp, ensure_ascii=False) + "\n").encode("utf-8")
            client_sock.sendall(resp_bytes)
        except Exception as e:
            self._send_error_response(client_sock, str(e))
        finally:
            self._safe_close_socket(client_sock)

    @staticmethod
    def _send_error_response(sock: socket.socket, err_msg: str) -> None:
        try:
            err_resp = {"status": "error", "error": err_msg}
            sock.sendall((json.dumps(err_resp) + "\n").encode("utf-8"))
        except OSError:
            pass

    @staticmethod
    def _safe_close_socket(sock: Optional[socket.socket]) -> None:
        if sock:
            try:
                sock.close()
            except OSError:
                pass

    @staticmethod
    def _safe_unlink(path: str) -> None:
        if os.path.exists(path):
            try:
                os.unlink(path)
            except OSError:
                pass

    def close_in_child(self) -> None:
        """Closes the server socket in a forked child without unlinking the socket file."""
        self._running = False
        self._in_child = True
        atexit.unregister(self._atexit_cleanup)
        if self._server_sock:
            self._safe_close_socket(self._server_sock)
            self._server_sock = None

    def _atexit_cleanup(self) -> None:
        """Removes the socket file on interpreter exit (covers abnormal exits)."""
        if not getattr(self, "_in_child", False) and os.getpid() == self._creator_pid:
            self._safe_unlink(self.socket_path)

    def stop(self) -> None:
        """Closes server socket and unlinks socket file."""
        self._running = False
        self._safe_close_socket(self._server_sock)
        self._server_sock = None
        self._safe_unlink(self.socket_path)
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1.0)


class ControlClient:
    """
    Administrative client interacting with the Supervisor Arbiter via Unix Domain Socket.
    """

    def __init__(self, socket_path: str, timeout: float = 5.0) -> None:
        self.socket_path = socket_path
        self.timeout = timeout

    def _exchange_payload(
        self, sock: socket.socket, cmd_dict: Dict[str, Any]
    ) -> Dict[str, Any]:
        payload = (json.dumps(cmd_dict) + "\n").encode("utf-8")
        sock.sendall(payload)
        raw_data = ControlServer._recv_line(sock)
        raw_resp = raw_data.decode("utf-8").strip()
        if not raw_resp:
            return {"status": "error", "error": "Empty response from Arbiter"}
        res: Dict[str, Any] = json.loads(raw_resp)
        return res

    def send_command(self, cmd_dict: Dict[str, Any]) -> Dict[str, Any]:
        """Sends a JSON command to the supervisor arbiter and waits for response."""
        if not os.path.exists(self.socket_path):
            return {
                "status": "error",
                "error": f"Supervisor control socket not found: '{self.socket_path}'. Is Arbiter running?",
            }

        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        try:
            sock.connect(self.socket_path)
            return self._exchange_payload(sock, cmd_dict)
        except Exception as e:
            return {"status": "error", "error": f"IPC communication error: {e}"}
        finally:
            ControlServer._safe_close_socket(sock)

    def ping(self) -> bool:
        """Verifies if the arbiter is responsive."""
        resp = self.send_command({"cmd": "ping"})
        return resp.get("status") == "ok" and resp.get("message") == "pong"

    def get_status(self) -> Dict[str, Any]:
        """Retrieves system-wide supervisor status."""
        return self.send_command({"cmd": "status"})

    def scale_workers(
        self, count: int, pool: str = "", label: str = ""
    ) -> Dict[str, Any]:
        """Dynamically scales workers of target pool to target count."""
        target = pool or label
        cmd: Dict[str, Any] = {"cmd": "scale", "workers": count, "count": count}
        if target:
            cmd["pool"] = target
        return self.send_command(cmd)

    def reload(self) -> Dict[str, Any]:
        """Triggers graceful rolling reload."""
        return self.send_command({"cmd": "reload"})

    def stop(self) -> Dict[str, Any]:
        """Triggers graceful supervisor shutdown."""
        return self.send_command({"cmd": "stop"})
