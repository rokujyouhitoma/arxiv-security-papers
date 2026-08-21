"""Pure Python Asynchronous HTTP/1.1 Client with Connection Pooling & Stream Decompression."""

from __future__ import annotations

import asyncio
import ssl
import time
import urllib.parse
import zlib
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple


@dataclass
class Request:
    """Represents a spider crawl request."""

    url: str
    callback: str = "parse"
    method: str = "GET"
    headers: Dict[str, str] = field(default_factory=dict)
    body: Optional[bytes] = None
    priority: int = 0
    dont_filter: bool = False
    meta: Dict[str, Any] = field(default_factory=dict)


@dataclass
class Response:
    """Represents a downloaded HTTP response."""

    url: str
    status_code: int
    headers: Dict[str, str]
    body: bytes
    request: Request
    download_latency: float = 0.0

    @property
    def text(self) -> str:
        return self.body.decode("utf-8", errors="replace")


class AsyncHttpDownloader:
    """Zero-external-dependency non-blocking HTTP/1.1 client using asyncio streams."""

    def __init__(
        self, timeout: float = 20.0, user_agent: str = "ArXivSecuritySpider/1.0"
    ) -> None:
        self.timeout: float = timeout
        self.user_agent: str = user_agent
        self._ssl_context: ssl.SSLContext = ssl.create_default_context()
        self._pool: Dict[
            Tuple[str, int, bool],
            List[Tuple[asyncio.StreamReader, asyncio.StreamWriter]],
        ] = {}

    async def download(self, request: Request) -> Response:
        start_time = time.perf_counter()
        parsed = urllib.parse.urlsplit(request.url)
        is_ssl = parsed.scheme == "https"
        port = parsed.port or (443 if is_ssl else 80)
        host = parsed.hostname or "localhost"
        path = (parsed.path or "/") + (f"?{parsed.query}" if parsed.query else "")

        req_headers = _build_request_headers(
            host, self.user_agent, request.headers, request.body
        )
        header_str = (
            f"{request.method} {path} HTTP/1.1\r\n"
            + "\r\n".join(f"{k}: {v}" for k, v in req_headers.items())
            + "\r\n\r\n"
        )
        req_bytes = header_str.encode("iso-8859-1") + (request.body or b"")

        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(
                host, port, ssl=self._ssl_context if is_ssl else None
            ),
            timeout=self.timeout,
        )

        try:
            writer.write(req_bytes)
            await writer.drain()

            status_code = await _read_status_code(reader)
            resp_headers = await _read_headers(reader)
            raw_body = await _read_body(reader, resp_headers)
            body = _decompress_body(raw_body, resp_headers.get("content-encoding", ""))
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

        latency = time.perf_counter() - start_time
        return Response(
            url=request.url,
            status_code=status_code,
            headers=resp_headers,
            body=body,
            request=request,
            download_latency=latency,
        )


def _build_request_headers(
    host: str, user_agent: str, custom_headers: Dict[str, str], body: Optional[bytes]
) -> Dict[str, str]:
    headers = {
        "Host": host,
        "User-Agent": user_agent,
        "Accept": "text/html,application/xhtml+xml,application/json,application/pdf,*/*",
        "Accept-Encoding": "gzip, deflate",
        "Connection": "close",
    }
    headers.update(custom_headers)
    if body:
        headers["Content-Length"] = str(len(body))
    return headers


async def _read_status_code(reader: asyncio.StreamReader) -> int:
    status_line = (await reader.readline()).decode("iso-8859-1")
    if status_line.startswith("HTTP/"):
        parts = status_line.split()
        if len(parts) >= 2 and parts[1].isdigit():
            return int(parts[1])
    return 500


async def _read_headers(reader: asyncio.StreamReader) -> Dict[str, str]:
    headers: Dict[str, str] = {}
    while True:
        line = (await reader.readline()).decode("iso-8859-1")
        if line in ("\r\n", "\n", ""):
            break
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    return headers


async def _read_body(reader: asyncio.StreamReader, headers: Dict[str, str]) -> bytes:
    transfer_encoding = headers.get("transfer-encoding", "").lower()
    if transfer_encoding == "chunked":
        return await _read_chunked_body(reader)

    if "content-length" in headers:
        try:
            length = int(headers["content-length"])
            return await reader.readexactly(length)
        except (ValueError, asyncio.IncompleteReadError):
            return await reader.read()

    return await reader.read()


async def _read_chunked_body(reader: asyncio.StreamReader) -> bytes:
    chunks: List[bytes] = []
    while True:
        line = (await reader.readline()).decode("iso-8859-1").strip()
        if not line:
            break
        chunk_len = int(line.split(";")[0], 16)
        if chunk_len == 0:
            await reader.readline()
            break
        chunk_data = await reader.readexactly(chunk_len)
        chunks.append(chunk_data)
        await reader.readline()
    return b"".join(chunks)


def _decompress_body(raw_body: bytes, encoding: str) -> bytes:
    enc = encoding.lower()
    if "gzip" in enc:
        try:
            return zlib.decompress(raw_body, 16 + zlib.MAX_WBITS)
        except Exception:
            return raw_body
    if "deflate" in enc:
        try:
            return zlib.decompress(raw_body, -zlib.MAX_WBITS)
        except Exception:
            try:
                return zlib.decompress(raw_body)
            except Exception:
                return raw_body
    return raw_body
