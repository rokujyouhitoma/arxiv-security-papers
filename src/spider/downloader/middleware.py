"""Downloader Middlewares for robots.txt, UA rotation, retry, caching, and offsite boundary defense."""

from __future__ import annotations

import asyncio
import datetime
import email.utils
import urllib.parse
import urllib.robotparser
from typing import Any, Dict, List, Optional, Sequence, Set

from ..core.downloader import AsyncHttpDownloader, Request, Response


def _extract_allowed_domains(spider: Any) -> List[str]:
    allowed_domains: Any = getattr(spider, "allowed_domains", None)
    if not allowed_domains:
        return []
    return [str(d).lower().strip() for d in allowed_domains if d]


def _create_blocked_response(request: Request) -> Response:
    return Response(
        url=request.url,
        status_code=403,
        headers={"X-Blocked-By": "OffsiteMiddleware"},
        body=b"Blocked by OffsiteMiddleware: Host not in allowed_domains",
        request=request,
    )


class OffsiteMiddleware:
    """Blocks requests to domains not specified in spider.allowed_domains to prevent SSRF and offsite crawling."""

    async def process_request(
        self, request: Request, spider: Any
    ) -> Optional[Response]:
        domains = _extract_allowed_domains(spider)
        if not domains:
            return None

        host = _get_domain(request.url)
        if not self._is_valid_domain(host, domains):
            return _create_blocked_response(request)
        return None

    @staticmethod
    def _is_valid_domain(host: str, allowed_domains: Sequence[str]) -> bool:
        return any(host == d or host.endswith("." + d) for d in allowed_domains)


class UserAgentMiddleware:
    """Sets standard compliant User-Agent headers."""

    def __init__(
        self,
        user_agent: str = "GenericSpiderBot/1.0",
    ) -> None:
        self.user_agent: str = user_agent

    async def process_request(
        self, request: Request, spider: Any
    ) -> Optional[Response]:
        if "User-Agent" not in request.headers:
            request.headers["User-Agent"] = self.user_agent
        return None


class RobotsTxtMiddleware:
    """Enforces RFC 9309 robots.txt exclusion rules."""

    def __init__(self) -> None:
        self._parsers: Dict[str, urllib.robotparser.RobotFileParser] = {}

    def set_robots_txt(self, domain: str, content: str) -> None:
        """Sets robots.txt rules for a specific domain."""
        parser = urllib.robotparser.RobotFileParser()
        parser.parse(content.splitlines())
        self._parsers[domain.lower()] = parser

    async def process_request(
        self, request: Request, spider: Any
    ) -> Optional[Response]:
        domain = _get_domain(request.url)
        parser = self._parsers.get(domain)
        if parser is not None:
            ua = request.headers.get("User-Agent", "GenericSpiderBot")
            if not parser.can_fetch(ua, request.url):
                # Dropped by robots.txt
                return Response(
                    url=request.url,
                    status_code=403,
                    headers={"X-Blocked-By": "robots.txt"},
                    body=b"Blocked by robots.txt",
                    request=request,
                )
        return None


class HttpCacheMiddleware:
    """In-memory HTTP caching middleware for 200 OK responses."""

    def __init__(self) -> None:
        self._cache: Dict[str, Response] = {}

    async def process_request(
        self, request: Request, spider: Any
    ) -> Optional[Response]:
        if request.meta.get("use_cache", True) and request.url in self._cache:
            return self._cache[request.url]
        return None

    async def process_response(
        self, request: Request, response: Response, spider: Any
    ) -> Response:
        if response.status_code == 200 and request.meta.get("use_cache", True):
            self._cache[request.url] = response
        return response


def _parse_retry_after(header_val: Optional[str]) -> Optional[float]:
    """Parses Retry-After header as seconds or delta-seconds from HTTP-date."""
    if not header_val:
        return None
    cleaned = header_val.strip()
    try:
        val = float(cleaned)
        return max(0.0, val)
    except ValueError:
        pass

    try:
        dt = email.utils.parsedate_to_datetime(cleaned)
        now = datetime.datetime.now(datetime.timezone.utc)
        delta = (dt - now).total_seconds()
        return max(0.0, delta)
    except Exception:
        return None


def _calculate_retry_delay(
    response: Response,
    retries: int,
    initial_delay: float,
    backoff_factor: float,
    max_delay: float,
) -> float:
    retry_after_str = response.headers.get("retry-after")
    parsed_after = _parse_retry_after(retry_after_str)
    if parsed_after is not None:
        delay = parsed_after
    else:
        delay = initial_delay * (backoff_factor**retries)
    return min(delay, max_delay)


async def _safe_download(
    downloader: Optional[AsyncHttpDownloader], request: Request
) -> Response:
    dl = downloader or AsyncHttpDownloader()
    try:
        return await dl.download(request)
    except Exception as err:
        return Response(
            url=request.url,
            status_code=500,
            headers={"X-Error": str(err)},
            body=b"",
            request=request,
        )


class RetryMiddleware:
    """Retries HTTP 429 and 5xx responses using exponential backoff and Retry-After header."""

    def __init__(
        self,
        max_retry_times: int = 3,
        initial_delay: float = 2.0,
        backoff_factor: float = 2.0,
        max_delay: float = 60.0,
        retry_http_codes: Optional[Set[int]] = None,
        downloader: Optional[AsyncHttpDownloader] = None,
    ) -> None:
        self.max_retry_times = max_retry_times
        self.initial_delay = initial_delay
        self.backoff_factor = backoff_factor
        self.max_delay = max_delay
        self.retry_http_codes = retry_http_codes or {429, 500, 502, 503, 504}
        self.downloader = downloader

    async def process_response(
        self, request: Request, response: Response, spider: Any
    ) -> Response:
        if response.status_code not in self.retry_http_codes:
            return response

        retries = int(request.meta.get("retry_times", 0))
        if retries >= self.max_retry_times:
            return response

        delay = _calculate_retry_delay(
            response,
            retries,
            self.initial_delay,
            self.backoff_factor,
            self.max_delay,
        )
        if delay > 0:
            await asyncio.sleep(delay)

        request.meta["retry_times"] = retries + 1
        new_response = await _safe_download(self.downloader, request)
        return await self.process_response(request, new_response, spider)


def _get_domain(url: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    return (parsed.hostname or "localhost").lower()
