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

    def _handle_client(self, client_sock: socket.socket) -> None:
        client_sock.settimeout(3.0)
        try:
            raw_data = b""
            while True:
                chunk = client_sock.recv(4096)
                if not chunk:
                    break
                raw_data += chunk
                if b"\n" in raw_data:
                    break
            if not raw_data:
                return
            req = json.loads(raw_data.decode("utf-8").strip())
            resp = self.command_handler(req)
            resp_bytes = (json.dumps(resp, ensure_ascii=False) + "\n").encode("utf-8")
            client_sock.sendall(resp_bytes)
        except Exception as e:
            err_resp = {"status": "error", "error": str(e)}
            try:
                client_sock.sendall((json.dumps(err_resp) + "\n").encode("utf-8"))
            except OSError:
                pass
        finally:
            try:
                client_sock.close()
            except OSError:
                pass

    def close_in_child(self) -> None:
        """Closes the server socket in a forked child without unlinking the socket file."""
        self._running = False
        if self._server_sock:
            try:
                self._server_sock.close()
            except OSError:
                pass
            self._server_sock = None

    def _atexit_cleanup(self) -> None:
        """Removes the socket file on interpreter exit (covers abnormal exits)."""
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass

    def stop(self) -> None:
        """Closes server socket and unlinks socket file."""
        self._running = False
        if self._server_sock:
            try:
                self._server_sock.close()
            except OSError:
                pass
            self._server_sock = None
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1.0)


class ControlClient:
    """
    Administrative client interacting with the Supervisor Arbiter via Unix Domain Socket.
    """

    def __init__(self, socket_path: str, timeout: float = 5.0) -> None:
        self.socket_path = socket_path
        self.timeout = timeout

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
            payload = (json.dumps(cmd_dict) + "\n").encode("utf-8")
            sock.sendall(payload)

            raw_data = b""
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                raw_data += chunk
                if b"\n" in raw_data:
                    break
            raw_resp = raw_data.decode("utf-8").strip()
            if not raw_resp:
                return {"status": "error", "error": "Empty response from Arbiter"}
            res: Dict[str, Any] = json.loads(raw_resp)
            return res
        except Exception as e:
            return {"status": "error", "error": f"IPC communication error: {e}"}
        finally:
            sock.close()

    def ping(self) -> bool:
        """Verifies if the arbiter is responsive."""
        resp = self.send_command({"cmd": "ping"})
        return resp.get("status") == "ok" and resp.get("message") == "pong"

    def get_status(self) -> Dict[str, Any]:
        """Retrieves system-wide supervisor status."""
        return self.send_command({"cmd": "status"})

    def scale_workers(self, count: int) -> Dict[str, Any]:
        """Dynamically scales web workers to target count."""
        return self.send_command({"cmd": "scale", "workers": count})

    def reload(self) -> Dict[str, Any]:
        """Triggers graceful rolling reload."""
        return self.send_command({"cmd": "reload"})

    def stop(self) -> Dict[str, Any]:
        """Triggers graceful supervisor shutdown."""
        return self.send_command({"cmd": "stop"})
