#!/usr/bin/env python3
"""
PEP 3333 WSGI Application and HTTP Server for arXiv Security Papers API Gateway.
"""

from __future__ import annotations

import argparse
import errno
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
from datetime import datetime, timezone
from socketserver import ThreadingMixIn
from typing import (
    TYPE_CHECKING,
    Any,
    Callable,
    Dict,
    Iterable,
    List,
    Optional,
    Tuple,
    cast,
)
from wsgiref.simple_server import WSGIServer, make_server

if TYPE_CHECKING:
    from search.vector_engine import VectorEngine

from observability.propagation import (
    TraceContextPropagator,
    clear_current_trace_context,
    generate_span_id,
    generate_trace_id,
    set_current_trace_context,
)

from .handlers import GatewayHandlers
from .logger import WORKSPACE_DIR, log_http_access
from .router import CORS_HEADERS, response_error


class WSGIApplication:
    """
    PEP 3333 compliant WSGI Application router for arXiv Security Papers Gateway.
    """

    def __init__(
        self,
        workspace_dir: Optional[str] = None,
        vector_engine: Optional[VectorEngine] = None,
    ) -> None:
        self.workspace_dir = workspace_dir or WORKSPACE_DIR
        self.handlers = GatewayHandlers(
            workspace_dir=self.workspace_dir, vector_engine=vector_engine
        )

    def _handle_options(self, start_response: Callable[..., Any]) -> List[bytes]:
        start_response("200 OK", CORS_HEADERS)
        return [b""]

    def _route_graph_api(
        self,
        start_response: Callable[..., Any],
        path: str,
        query_params: Dict[str, List[str]],
    ) -> Optional[Any]:
        if path == "/api/graph/mesh":
            return self.handlers.handle_graph_mesh(start_response)
        if path == "/api/graph/cti-mesh":
            return self.handlers.handle_cti_graph_mesh(start_response, query_params)
        if path == "/api/graph/query":
            return self.handlers.handle_graph_query(start_response, query_params)
        return None

    def _route_simple_api(
        self,
        start_response: Callable[..., Any],
        path: str,
        query_params: Dict[str, List[str]],
    ) -> Optional[Any]:
        if path.startswith("/api/graph/"):
            return self._route_graph_api(start_response, path, query_params)
        if path == "/api/trends":
            return self.handlers.handle_trends(start_response, query_params)
        if path == "/api/stats":
            return self.handlers.handle_stats(start_response)
        return None

    def _route_stream_api(
        self,
        start_response: Callable[..., Any],
        path: str,
        query_params: Dict[str, List[str]],
    ) -> Optional[Any]:
        if path == "/api/stream/top":
            return self.handlers.handle_stream_top(start_response, query_params)
        if path == "/api/stream/logs":
            return self.handlers.handle_stream_logs(start_response, query_params)
        if path == "/api/stream/events":
            return self.handlers.handle_stream_events(start_response, query_params)
        return None

    def _route_api_get(
        self,
        environ: Dict[str, Any],
        start_response: Callable[..., Any],
        path: str,
        query_params: Dict[str, List[str]],
    ) -> Optional[Any]:
        if path.startswith("/api/stream/"):
            return self._route_stream_api(start_response, path, query_params)
        remote_addr = environ.get("REMOTE_ADDR", "-")
        if path == "/api/search":
            return self.handlers.handle_search(
                start_response, query_params, remote_addr=remote_addr
            )
        if path.startswith("/api/paper/"):
            return self.handlers.handle_paper(start_response, path)
        return self._route_simple_api(start_response, path, query_params)

    def _route_get(
        self,
        environ: Dict[str, Any],
        start_response: Callable[..., Any],
        path: str,
        query_params: Dict[str, List[str]],
    ) -> Any:
        api_res = self._route_api_get(environ, start_response, path, query_params)
        if api_res is not None:
            return api_res
        if path.startswith("/preview/"):
            return self.handlers.handle_preview(start_response, path)
        if path.startswith("/api/"):
            return response_error(
                start_response, "API endpoint not found", status="404 Not Found"
            )
        return self.handlers.handle_static(start_response, path)

    def _handle_post(
        self, environ: Dict[str, Any], start_response: Callable[..., Any], path: str
    ) -> List[bytes]:
        if path == "/api/mcp":
            return self.handlers.handle_mcp_post(environ, start_response)
        return response_error(
            start_response, "Endpoint not found", status="404 Not Found"
        )

    def _init_trace_context(self, environ: Dict[str, Any]) -> Tuple[str, str]:
        ctx = TraceContextPropagator.extract(environ)
        if ctx and ctx.is_valid:
            tid, sid = ctx.trace_id, ctx.span_id
        else:
            tid = generate_trace_id()
            sid = generate_span_id()
        set_current_trace_context(tid, sid)
        return tid, sid

    def _wrap_response_headers(
        self,
        start_response: Callable[..., Any],
        tid: str,
        sid: str,
        status_holder: List[str],
    ) -> Callable[..., Any]:
        def wrapped_start_response(
            status: str, headers: List[Tuple[str, str]], exc_info: Any = None
        ) -> Any:
            status_holder.append(status)
            clean_headers = [
                h
                for h in headers
                if h[0].lower()
                not in {
                    "connection",
                    "keep-alive",
                    "transfer-encoding",
                    "te",
                    "trailers",
                    "upgrade",
                }
            ]
            clean_headers.append(("X-Trace-ID", tid))
            clean_headers.append(("traceparent", f"00-{tid}-{sid}-01"))
            if exc_info is not None:
                return start_response(status, clean_headers, exc_info)
            return start_response(status, clean_headers)

        return wrapped_start_response

    def _dispatch_request(
        self,
        environ: Dict[str, Any],
        start_response: Callable[..., Any],
    ) -> Any:
        method = environ.get("REQUEST_METHOD", "GET").upper()
        path = environ.get("PATH_INFO", "/")
        query_string = environ.get("QUERY_STRING", "")
        query_params = urllib.parse.parse_qs(query_string)

        if method == "OPTIONS":
            return self._handle_options(start_response)
        if method in ("GET", "HEAD"):
            res = self._route_get(environ, start_response, path, query_params)
            return [b""] if method == "HEAD" else res
        if method == "POST":
            return self._handle_post(environ, start_response, path)
        return response_error(
            start_response,
            f"Method {method} Not Allowed",
            status="405 Method Not Allowed",
        )

    def __call__(
        self, environ: Dict[str, Any], start_response: Callable[..., Any]
    ) -> Iterable[bytes]:
        t0 = time.perf_counter()
        tid, sid = self._init_trace_context(environ)
        status_holder: List[str] = []
        wrapped_sr = self._wrap_response_headers(
            start_response, tid, sid, status_holder
        )

        thread_name = threading.current_thread().name
        method = environ.get("REQUEST_METHOD", "GET").upper()
        path = environ.get("PATH_INFO", "/")
        query = environ.get("QUERY_STRING", "")
        full_path = f"{path}?{query}" if query else path
        now_str = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
        print(
            f"[{now_str}] [GATEWAY-REQ-START] thread={thread_name} {method} {full_path}",
            file=sys.stderr,
            flush=True,
        )

        try:
            return cast(Iterable[bytes], self._dispatch_request(environ, wrapped_sr))
        finally:
            dt_ms = (time.perf_counter() - t0) * 1000.0
            st_code = int(status_holder[0].split()[0]) if status_holder else 500
            done_str = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
            done_msg = (
                f"[{done_str}] [GATEWAY-REQ-DONE] thread={thread_name} "
                f"{method} {full_path} -> {st_code} ({dt_ms:.2f}ms)"
            )
            print(done_msg, file=sys.stderr, flush=True)
            log_http_access(
                method=method,
                path=path,
                status_code=st_code,
                latency_ms=dt_ms,
                client_ip=environ.get("REMOTE_ADDR", "-"),
                user_agent=environ.get("HTTP_USER_AGENT", "-"),
            )
            clear_current_trace_context()


class ThreadingWSGIServer(ThreadingMixIn, WSGIServer):
    """Multi-threaded WSGI Server allowing concurrent handling of SSE streams and HTTP requests."""

    daemon_threads = True
    allow_reuse_address = True
    block_on_close = False


application = WSGIApplication()
app = application


def _find_pid_via_lsof(port: int) -> Optional[int]:
    lsof = shutil.which("lsof")
    if not lsof:
        return None
    try:
        out = subprocess.check_output(
            [lsof, "-ti", f":{port}"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=1.0,
        ).strip()
        lines = out.splitlines()
        return int(lines[0]) if lines else None
    except (subprocess.SubprocessError, ValueError, OSError):
        return None


def _find_pid_via_fuser(port: int) -> Optional[int]:
    fuser = shutil.which("fuser")
    if not fuser:
        return None
    try:
        out = subprocess.check_output(
            [fuser, f"{port}/tcp"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=1.0,
        ).strip()
        parts = out.split()
        return int(parts[0]) if parts else None
    except (subprocess.SubprocessError, ValueError, OSError):
        return None


def _find_pid_using_port(port: int) -> Optional[int]:
    """Attempts to identify the PID currently listening on the target TCP port."""
    return _find_pid_via_lsof(port) or _find_pid_via_fuser(port)


def _is_address_in_use_error(err: OSError) -> bool:
    """Returns True if the OSError corresponds to EADDRINUSE."""
    conflict_errnos = {errno.EADDRINUSE, 98, 48, 10048}
    if err.errno in conflict_errnos:
        return True
    return "address already in use" in str(err).lower()


def _format_port_conflict_message(
    host: str, port: int, pid: Optional[int] = None
) -> str:
    """Formats actionable diagnostic instructions when a port collision occurs."""
    lines = [
        f"❌ [エラー] ポート {port} ({host}) は既に使用されています (Address already in use)。",
    ]
    if pid is not None:
        lines.append(f"   現在ポートを占有しているプロセスPID: {pid}")
        lines.append(f"   解決策 1: 既存プロセスを停止する -> `kill {pid}`")
    else:
        lines.append(
            "   解決策 1: 既存プロセスを停止する -> `pkill -f 'src/web/server.py'` または `make stop_supervisor`"
        )
    lines.append(
        f'   解決策 2: 別のポートを指定して起動する -> `make run_dashboard ARGS="--port {port + 1}"`'
    )
    lines.append(
        '   解決策 3: 空きポートを自動探索して起動する -> `make run_dashboard ARGS="--auto-port"`'
    )
    return "\n".join(lines)


def _try_bind_single_port(
    host: str, port: int
) -> Tuple[Optional[ThreadingWSGIServer], Optional[OSError]]:
    """Attempts to bind ThreadingWSGIServer on a single port."""
    try:
        server = make_server(host, port, application, server_class=ThreadingWSGIServer)
        return server, None
    except OSError as err:
        return None, err


def _check_bind_error(err: Optional[OSError]) -> None:
    if err is None or not _is_address_in_use_error(err):
        if err:
            raise err
        raise RuntimeError("Failed to bind server")


def _scan_and_bind(
    host: str, start_port: int, max_trials: int
) -> Tuple[Optional[ThreadingWSGIServer], int]:
    for offset in range(max_trials):
        current_port = start_port + offset
        server, err = _try_bind_single_port(host, current_port)
        if server is not None:
            return server, current_port
        _check_bind_error(err)
    return None, start_port


def _bind_server_safe(
    host: str, port: int, auto_port: bool = False, max_attempts: int = 10
) -> Tuple[Optional[ThreadingWSGIServer], int]:
    """Binds WSGI server safely, supporting auto_port fallback if enabled."""
    trials = max_attempts if auto_port else 1
    server, bound_port = _scan_and_bind(host, port, trials)
    if server is not None:
        return server, bound_port

    pid = _find_pid_using_port(port)
    msg = _format_port_conflict_message(host, port, pid)
    print(msg, file=sys.stderr, flush=True)
    return None, port


def run_web_server(
    port: int = 8000,
    host: str = "0.0.0.0",
    auto_port: bool = False,
    max_attempts: int = 10,
) -> None:
    """Runs standard PEP 3333 multi-threaded WSGI Server with graceful error handling."""
    httpd, bound_port = _bind_server_safe(
        host=host, port=port, auto_port=auto_port, max_attempts=max_attempts
    )
    if httpd is None:
        sys.exit(1)

    try:
        print(
            f"🚀 arxiv-security-papers multi-threaded WSGI Web Server running at http://localhost:{bound_port}",
            flush=True,
        )
        print(
            f"📊 Graph Engineering Dashboard: http://localhost:{bound_port}/dashboard",
            flush=True,
        )
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Web server stopped gracefully by user.", flush=True)
    finally:
        httpd.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="PEP 3333 WSGI Web Server for arxiv-security-papers"
    )
    parser.add_argument(
        "--port", type=int, default=8000, help="Port to run web server on"
    )
    parser.add_argument(
        "--host", type=str, default="0.0.0.0", help="Host address to bind to"
    )
    parser.add_argument(
        "--auto-port",
        action="store_true",
        help="Automatically bind to the next available port if conflict occurs",
    )
    args = parser.parse_args()
    run_web_server(port=args.port, host=args.host, auto_port=args.auto_port)
