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
        max_requests: int = 0,
        max_requests_jitter: int = 0,
        max_worker_lifetime: float = 0.0,
        max_worker_lifetime_jitter: float = 0.0,
    ) -> None:
        target = app_target if app_target is not None else wsgi_app
        super().__init__(
            worker_id=worker_id,
            config=config,
            server_socket=server_socket,
            app_target=target,
            pulse_callback=pulse_callback,
            max_requests=max_requests,
            max_requests_jitter=max_requests_jitter,
            max_worker_lifetime=max_worker_lifetime,
            max_worker_lifetime_jitter=max_worker_lifetime_jitter,
        )

    @property
    def wsgi_app(self) -> Optional[Callable[..., Any]]:
        return self.app_target

    @staticmethod
    def _get_remote_addr(client_sock: socket.socket) -> str:
        try:
            peer = client_sock.getpeername()
            if isinstance(peer, tuple):
                return str(peer[0])
        except OSError:
            pass
        return "-"

    @staticmethod
    def _map_header(environ: Dict[str, Any], k: str, v: str) -> None:
        h_key = "HTTP_" + k.upper().replace("-", "_")
        if h_key == "HTTP_CONTENT_TYPE":
            environ["CONTENT_TYPE"] = v
        elif h_key == "HTTP_CONTENT_LENGTH":
            environ["CONTENT_LENGTH"] = v
        else:
            environ[h_key] = v

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
        remote_addr = self._get_remote_addr(client_sock)
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
            self._map_header(environ, k, v)
        return environ

    def _parse_http_payload(
        self, client_sock: socket.socket, raw: bytes
    ) -> Optional[Dict[str, Any]]:
        """Parses HTTP request bytes into WSGI environ dict."""
        header_part, _, body_part = raw.partition(b"\r\n\r\n")
        lines = header_part.decode("iso-8859-1").split("\r\n")
        if not lines:
            return None

        request_line = lines[0].split(" ")
        if len(request_line) < 2:
            return None
        method, full_path = request_line[0], request_line[1]
        path, _, query = full_path.partition("?")

        headers: Dict[str, str] = {}
        for line in lines[1:]:
            if ":" in line:
                k, _, v = line.partition(":")
                headers[k.strip().lower()] = v.strip()

        return self._build_wsgi_environ(
            client_sock, method, path, query, headers, body_part
        )

    def _execute_wsgi_request(
        self, environ: Dict[str, Any]
    ) -> tuple[str, List[tuple[str, str]], bytes]:
        """Executes WSGI app callable and returns status, headers, body."""
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

        return status_holder[0], response_headers, resp_body

    def _format_http_response(
        self, status: str, headers: List[tuple[str, str]], body: bytes
    ) -> bytes:
        """Formats HTTP 1.1 response string with content-length and headers."""
        resp_header_str = f"HTTP/1.1 {status}\r\n"
        has_len = False
        for hk, hv in headers:
            if hk.lower() == "content-length":
                has_len = True
            resp_header_str += f"{hk}: {hv}\r\n"
        if not has_len:
            resp_header_str += f"Content-Length: {len(body)}\r\n"
        resp_header_str += "Connection: close\r\n\r\n"
        return resp_header_str.encode("iso-8859-1") + body

    def _dispatch_client_payload(self, client_sock: socket.socket) -> None:
        raw = client_sock.recv(65536)
        if not raw:
            return
        environ = self._parse_http_payload(client_sock, raw)
        if not environ:
            return
        status, headers, body = self._execute_wsgi_request(environ)
        response_bytes = self._format_http_response(status, headers, body)
        client_sock.sendall(response_bytes)
        self.requests_handled += 1
        self.last_active_epoch = time.time()
        if self._should_retire():
            self.alive = False

    def handle_client(self, client_sock: socket.socket) -> None:
        """Processes a single HTTP connection through the target callable application."""
        client_sock.settimeout(self.config.timeout)
        self.last_active_epoch = time.time()
        self.pulse({"is_handling_request": True, "request_start": time.monotonic()})
        try:
            self._dispatch_client_payload(client_sock)
        except Exception:
            pass
        finally:
            try:
                client_sock.close()
            except OSError:
                pass
            self.pulse({"is_handling_request": False})

    def _accept_client(self) -> Optional[socket.socket]:
        if not self.server_socket:
            return None
        try:
            client_sock, _ = self.server_socket.accept()
            return client_sock
        except (socket.timeout, BlockingIOError):
            return None
        except OSError:
            return None

    def _process_one_connection(self) -> bool:
        """Try to accept and handle a client. Returns False if loop should break."""
        if not self.server_socket:
            time.sleep(0.1)
            return True
        client_sock = self._accept_client()
        if client_sock is None:
            return self.alive
        self.handle_client(client_sock)
        return True

    def run(self) -> None:
        """Main execution loop: accept connections, handle request, pulse heartbeat."""
        self.init_signals()
        if self.server_socket:
            self.server_socket.settimeout(1.0)

        while self.alive:
            self.pulse()
            if not self._process_one_connection():
                break
            if self._should_retire():
                self.alive = False
                break

        self.close()
