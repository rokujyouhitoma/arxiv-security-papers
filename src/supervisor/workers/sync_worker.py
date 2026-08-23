#!/usr/bin/env python3
"""
Synchronous Worker (SyncWorker) implementation.
Handles one request/task at a time per worker process with pre-fork socket sharing.
"""

from __future__ import annotations

import io
import socket
import sys
import time
from typing import Any, Callable, Dict, List, Optional

from ..config import SupervisorConfig
from .base import BaseWorker


class SyncWorker(BaseWorker):
    """
    Standard synchronous worker handling connections sequentially.
    """

    def __init__(
        self,
        worker_id: str,
        config: SupervisorConfig,
        server_socket: Optional[socket.socket] = None,
        app_target: Optional[Callable[..., Any]] = None,
        wsgi_app: Optional[Callable[..., Any]] = None,
        pulse_callback: Optional[
            Callable[[int, Optional[Dict[str, Any]]], None]
        ] = None,
    ) -> None:
        target = app_target if app_target is not None else wsgi_app
        super().__init__(
            worker_id=worker_id,
            config=config,
            server_socket=server_socket,
            app_target=target,
            pulse_callback=pulse_callback,
        )

    @property
    def wsgi_app(self) -> Optional[Callable[..., Any]]:
        return self.app_target

    def _build_wsgi_environ(
        self,
        client_sock: socket.socket,
        method: str,
        path: str,
        query: str,
        headers: Dict[str, str],
        body_bytes: bytes,
    ) -> Dict[str, Any]:
        """Constructs PEP 3333 WSGI environment dictionary."""
        remote_addr = "-"
        try:
            peer = client_sock.getpeername()
            if isinstance(peer, tuple):
                remote_addr = str(peer[0])
        except OSError:
            pass

        environ: Dict[str, Any] = {
            "REQUEST_METHOD": method,
            "SCRIPT_NAME": "",
            "PATH_INFO": path,
            "QUERY_STRING": query,
            "SERVER_NAME": self.config.bind_host,
            "SERVER_PORT": str(self.config.bind_port),
            "SERVER_PROTOCOL": "HTTP/1.1",
            "wsgi.version": (1, 0),
            "wsgi.url_scheme": "http",
            "wsgi.input": io.BytesIO(body_bytes),
            "wsgi.errors": sys.stderr,
            "wsgi.multithread": False,
            "wsgi.multiprocess": True,
            "wsgi.run_once": False,
            "REMOTE_ADDR": remote_addr,
            "CONTENT_LENGTH": str(len(body_bytes)),
        }

        for k, v in headers.items():
            h_key = "HTTP_" + k.upper().replace("-", "_")
            if h_key == "HTTP_CONTENT_TYPE":
                environ["CONTENT_TYPE"] = v
            elif h_key == "HTTP_CONTENT_LENGTH":
                environ["CONTENT_LENGTH"] = v
            else:
                environ[h_key] = v

        return environ

    def handle_client(self, client_sock: socket.socket) -> None:
        """Processes a single HTTP connection through the target callable application."""
        client_sock.settimeout(self.config.timeout)
        try:
            raw = client_sock.recv(65536)
            if not raw:
                return

            header_part, _, body_part = raw.partition(b"\r\n\r\n")
            lines = header_part.decode("iso-8859-1").split("\r\n")
            if not lines:
                return

            request_line = lines[0].split(" ")
            if len(request_line) < 2:
                return
            method, full_path = request_line[0], request_line[1]
            path, _, query = full_path.partition("?")

            headers: Dict[str, str] = {}
            for line in lines[1:]:
                if ":" in line:
                    k, _, v = line.partition(":")
                    headers[k.strip().lower()] = v.strip()

            environ = self._build_wsgi_environ(
                client_sock, method, path, query, headers, body_part
            )

            status_holder: List[str] = ["200 OK"]
            response_headers: List[tuple[str, str]] = []

            def start_response(
                status: str,
                resp_headers: List[tuple[str, str]],
                exc_info: Optional[Any] = None,
            ) -> Callable[[bytes], None]:
                status_holder[0] = status
                response_headers.extend(resp_headers)
                return lambda data: None

            if self.app_target:
                resp_iter = self.app_target(environ, start_response)
                resp_body = b"".join(resp_iter)
            else:
                resp_body = b'{"status":"ok","message":"Supervisor Generic Worker"}'
                response_headers.append(("Content-Type", "application/json"))

            resp_header_str = f"HTTP/1.1 {status_holder[0]}\r\n"
            has_len = False
            for hk, hv in response_headers:
                if hk.lower() == "content-length":
                    has_len = True
                resp_header_str += f"{hk}: {hv}\r\n"
            if not has_len:
                resp_header_str += f"Content-Length: {len(resp_body)}\r\n"
            resp_header_str += "Connection: close\r\n\r\n"

            client_sock.sendall(resp_header_str.encode("iso-8859-1") + resp_body)
            self.requests_handled += 1
        except Exception:
            pass
        finally:
            try:
                client_sock.close()
            except OSError:
                pass

    def run(self) -> None:
        """Main execution loop: accept connections, handle request, pulse heartbeat."""
        self.init_signals()
        if self.server_socket:
            self.server_socket.settimeout(1.0)

        while self.alive:
            self.pulse()
            if not self.server_socket:
                time.sleep(0.1)
                continue

            try:
                client_sock, _ = self.server_socket.accept()
            except (socket.timeout, BlockingIOError):
                continue
            except OSError:
                if not self.alive:
                    break
                continue

            self.handle_client(client_sock)

        self.close()
