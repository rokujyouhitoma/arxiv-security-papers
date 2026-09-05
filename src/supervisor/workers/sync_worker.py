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
from datetime import datetime, timezone
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

    @staticmethod
    def _safe_close_iter(resp_iter: Any) -> None:
        """Safely closes a WSGI iterator if it implements the close() protocol."""
        if hasattr(resp_iter, "close"):
            try:
                resp_iter.close()
            except Exception:
                pass

    @staticmethod
    def _is_streaming_response(headers: List[tuple[str, str]]) -> bool:
        """Determines whether the response should be streamed without full buffering."""
        headers_blob = " ".join(f"{k}:{v}" for k, v in headers).lower()
        return "text/event-stream" in headers_blob or "chunked" in headers_blob

    def _stream_chunks_loop(self, client_sock: socket.socket, resp_iter: Any) -> int:
        """Iterates over WSGI iterator chunks and pushes them immediately to client socket."""
        chunk_count = 0
        for chunk in resp_iter:
            if not chunk:
                continue
            client_sock.sendall(chunk)
            chunk_count += 1
            self.last_active_epoch = time.time()
            self.pulse(
                {
                    "is_handling_request": True,
                    "streaming": True,
                    "chunks": chunk_count,
                }
            )
        return chunk_count

    @staticmethod
    def _send_stream_headers(
        client_sock: socket.socket, status: str, headers: List[tuple[str, str]]
    ) -> None:
        """Sends HTTP status line and headers for a streaming connection."""
        header_str = f"HTTP/1.1 {status}\r\n"
        for hk, hv in headers:
            header_str += f"{hk}: {hv}\r\n"
        header_str += "\r\n"
        client_sock.sendall(header_str.encode("iso-8859-1"))

    def _log_stream_start(self, method: str, full_url: str, status: str) -> None:
        now_str = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
        print(
            f"[{now_str}] [WORKER-STREAM-START] worker={self.worker_id} {method} {full_url} -> {status}",
            file=sys.stderr,
            flush=True,
        )

    def _log_stream_disconnect(self, exc: Exception, chunk_count: int) -> None:
        dis_str = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
        print(
            f"[{dis_str}] [WORKER-STREAM-DISCONNECT] worker={self.worker_id} "
            f"client disconnected ({type(exc).__name__}) after {chunk_count} chunks",
            file=sys.stderr,
            flush=True,
        )

    def _stream_wsgi_iterator(
        self,
        client_sock: socket.socket,
        status: str,
        headers: List[tuple[str, str]],
        resp_iter: Any,
        method: str,
        full_url: str,
    ) -> None:
        """Streams chunks from WSGI iterator directly to client socket without blocking."""
        self._log_stream_start(method, full_url, status)
        chunk_count = 0
        try:
            self._send_stream_headers(client_sock, status, headers)
            chunk_count = self._stream_chunks_loop(client_sock, resp_iter)
        except (BrokenPipeError, ConnectionResetError, socket.error) as exc:
            self._log_stream_disconnect(exc, chunk_count)
        finally:
            self._safe_close_iter(resp_iter)

    def _send_buffered_response(
        self,
        client_sock: socket.socket,
        status: str,
        headers: List[tuple[str, str]],
        resp_iter: Any,
    ) -> None:
        try:
            resp_body = b"".join(resp_iter)
        finally:
            self._safe_close_iter(resp_iter)
        response_bytes = self._format_http_response(status, headers, resp_body)
        client_sock.sendall(response_bytes)

    def _execute_wsgi_request(
        self, environ: Dict[str, Any]
    ) -> tuple[str, List[tuple[str, str]], bytes]:
        """Legacy helper: executes WSGI app callable and returns status, headers, body."""
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
            try:
                resp_body = b"".join(resp_iter)
            finally:
                self._safe_close_iter(resp_iter)
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

    def _invoke_app(
        self, environ: Dict[str, Any]
    ) -> tuple[str, List[tuple[str, str]], Any]:
        """Invokes the WSGI app and yields status, response headers, and iterator."""
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
        else:
            resp_iter = [b'{"status":"ok","message":"Supervisor Generic Worker"}']
            response_headers.append(("Content-Type", "application/json"))

        return status_holder[0], response_headers, resp_iter

    def _send_app_response(
        self,
        client_sock: socket.socket,
        status: str,
        headers: List[tuple[str, str]],
        resp_iter: Any,
        method: str,
        full_url: str,
    ) -> None:
        """Dispatches response to streaming or buffered writer depending on content type."""
        if self._is_streaming_response(headers):
            self._stream_wsgi_iterator(
                client_sock, status, headers, resp_iter, method, full_url
            )
        else:
            self._send_buffered_response(client_sock, status, headers, resp_iter)

    def _post_request_cleanup(self) -> None:
        """Updates request count, last active timestamp, and evaluates worker retirement."""
        self.requests_handled += 1
        self.last_active_epoch = time.time()
        if self._should_retire():
            self.alive = False

    def _log_req_start(self, method: str, full_url: str) -> None:
        now_str = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
        print(
            f"[{now_str}] [WORKER-REQ-START] worker={self.worker_id} {method} {full_url}",
            file=sys.stderr,
            flush=True,
        )

    def _log_req_done(
        self, method: str, full_url: str, status: str, elapsed_ms: float
    ) -> None:
        done_str = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
        print(
            f"[{done_str}] [WORKER-REQ-DONE] worker={self.worker_id} "
            f"{method} {full_url} -> {status} ({elapsed_ms:.2f}ms)",
            file=sys.stderr,
            flush=True,
        )

    def _dispatch_client_payload(self, client_sock: socket.socket) -> None:
        raw = client_sock.recv(65536)
        if not raw:
            return
        environ = self._parse_http_payload(client_sock, raw)
        if not environ:
            return

        method = environ.get("REQUEST_METHOD", "GET")
        path = environ.get("PATH_INFO", "/")
        query = environ.get("QUERY_STRING", "")
        full_url = f"{path}?{query}" if query else path

        t0 = time.perf_counter()
        self._log_req_start(method, full_url)

        status, response_headers, resp_iter = self._invoke_app(environ)
        self._send_app_response(
            client_sock, status, response_headers, resp_iter, method, full_url
        )

        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        self._log_req_done(method, full_url, status, elapsed_ms)
        self._post_request_cleanup()

    def handle_client(self, client_sock: socket.socket) -> None:
        """Processes a single HTTP connection through the target callable application."""
        client_sock.settimeout(self.config.timeout)
        self.last_active_epoch = time.time()
        self.pulse({"is_handling_request": True, "request_start": time.monotonic()})
        remote_addr = self._get_remote_addr(client_sock)
        now_str = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
        print(
            f"[{now_str}] [WORKER-ACCEPT] worker={self.worker_id} fd={client_sock.fileno()} client={remote_addr}",
            file=sys.stderr,
            flush=True,
        )
        try:
            self._dispatch_client_payload(client_sock)
        except Exception as err:
            err_str = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
            print(
                f"[{err_str}] [WORKER-ERROR] worker={self.worker_id} error={type(err).__name__}: {err}",
                file=sys.stderr,
                flush=True,
            )
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
