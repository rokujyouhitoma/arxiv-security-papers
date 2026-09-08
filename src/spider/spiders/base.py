"""Base Spider abstract class."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, AsyncIterator, Dict, Iterable, List, Set, Union

from ..core.downloader import Request, Response
from ..core.engine import ScrapedItem


class BaseSpider(ABC):
    """Abstract base class for all domain-specific Spiders."""

    name: str = "base_spider"
    start_urls: List[str] = []
    allowed_domains: Set[str] = set()
    download_delay: float = 0.5
    custom_settings: Dict[str, Any] = {}
    custom_headers: Dict[str, str] = {}

    def __init__(self) -> None:
        self.custom_settings = dict(self.custom_settings)
        self.custom_headers = dict(self.custom_headers)

    def start_requests(self) -> Iterable[Request]:
        """Generates initial Requests from start_urls with custom_headers applied."""
        headers = dict(self.custom_headers) if self.custom_headers else {}
        for url in self.start_urls:
            yield Request(url=url, callback="parse", headers=headers)

    @abstractmethod
    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        """Parses the HTTP response and yields Requests or ScrapedItems."""
        yield  # type: ignore[misc]
