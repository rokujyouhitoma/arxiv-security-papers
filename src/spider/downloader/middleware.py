"""Downloader Middlewares for robots.txt, UA rotation, retry, and caching."""

from __future__ import annotations

import urllib.parse
import urllib.robotparser
from typing import Any, Dict, Optional

from ..core.downloader import Request, Response


class UserAgentMiddleware:
    """Sets standard compliant User-Agent headers."""

    def __init__(
        self,
        user_agent: str = "ArXivSecuritySpider/1.0 (+https://github.com/rokujyouhitoma/arxiv-security-papers)",
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
            ua = request.headers.get("User-Agent", "ArXivSecuritySpider")
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


def _get_domain(url: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    return (parsed.hostname or "localhost").lower()
