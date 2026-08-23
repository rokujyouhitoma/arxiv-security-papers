#!/usr/bin/env python3
"""
AsyncIO Worker (AsyncWorker) implementation.
Handles high-concurrency non-blocking connections using native Python asyncio event loop.
"""

from __future__ import annotations

import asyncio
import socket
from typing import Any, Callable, Dict, List, Optional

from ..config import SupervisorConfig
from .base import BaseWorker


class AsyncWorker(BaseWorker):
    """
    Asynchronous event-loop worker handling concurrent streaming and I/O-bound requests.
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
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    @property
    def wsgi_app(self) -> Optional[Callable[..., Any]]:
        return self.app_target

    async def _handle_stream(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            raw_data = await asyncio.wait_for(
                reader.read(65536), timeout=self.config.timeout
            )
            if not raw_data:
                writer.close()
                return

            header_part, _, body_part = raw_data.partition(b"\r\n\r\n")
            lines = header_part.decode("iso-8859-1").split("\r\n")
            if not lines:
                writer.close()
                return

            request_line = lines[0].split(" ")
            method, full_path = request_line[0], (
                request_line[1] if len(request_line) > 1 else "/"
            )
            path, _, query = full_path.partition("?")

            headers: Dict[str, str] = {}
            for line in lines[1:]:
                if ":" in line:
                    k, _, v = line.partition(":")
                    headers[k.strip().lower()] = v.strip()

            # Construct WSGI environ
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
                "wsgi.input": asyncio.get_event_loop().run_in_executor(
                    None, lambda: None
                ),
                "wsgi.multithread": False,
                "wsgi.multiprocess": True,
                "wsgi.run_once": False,
                "CONTENT_LENGTH": str(len(body_part)),
            }

            status_holder = ["200 OK"]
            response_headers: List[tuple[str, str]] = []

            def start_response(
                status: str, r_headers: List[tuple[str, str]], exc_info: Any = None
            ) -> None:
                status_holder[0] = status
                response_headers.extend(r_headers)

            if self.wsgi_app:
                resp_iter = self.wsgi_app(environ, start_response)
                resp_body = b"".join(resp_iter)
            else:
                resp_body = b'{"status":"ok","engine":"asyncio"}'
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

            writer.write(resp_header_str.encode("iso-8859-1") + resp_body)
            await writer.drain()
            self.requests_handled += 1
        except Exception:
            pass
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def _async_main(self) -> None:
        if not self.server_socket:
            while self.alive:
                self.pulse()
                await asyncio.sleep(0.5)
            return

        self.server_socket.setblocking(False)
        server = await asyncio.start_server(
            self._handle_stream, sock=self.server_socket
        )

        async def heartbeat_loop() -> None:
            while self.alive:
                self.pulse({"event_loop": "asyncio"})
                await asyncio.sleep(0.5)

        hb_task = asyncio.create_task(heartbeat_loop())
        while self.alive:
            await asyncio.sleep(0.2)

        hb_task.cancel()
        server.close()
        await server.wait_closed()

    def run(self) -> None:
        """Main execution loop initializing and running asyncio event loop."""
        self.init_signals()
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)
        try:
            self._loop.run_until_complete(self._async_main())
        finally:
            self._loop.close()
            self.close()
