#!/usr/bin/env python3
"""arXiv Computer Science & Cryptography Domain Spider."""

from __future__ import annotations

import re
from typing import AsyncIterator, Iterator, List, Optional, Set, Union

from spider.core.downloader import Request, Response
from spider.core.engine import ScrapedItem
from spider.core.selector import Selector, XmlNode, XmlSelector
from spider.spiders.base import BaseSpider


class ArxivSpider(BaseSpider):
    """Spider for crawling arXiv computer security and cryptography papers."""

    name: str = "arxiv_spider"
    download_delay: float = 3.0
    start_urls: List[str] = [
        "https://export.arxiv.org/api/query",
        "https://arxiv.org/list/cs.CR/recent",
    ]
    allowed_domains: Set[str] = {"arxiv.org", "export.arxiv.org"}

    def start_requests(self) -> Iterator[Request]:
        """Yields initial parameterized API query request and recent papers request."""
        yield Request(
            url="https://export.arxiv.org/api/query",
            params={
                "search_query": "cat:cs.CR",
                "sortBy": "submittedDate",
                "sortOrder": "descending",
                "max_results": "25",
            },
            callback="parse",
        )
        yield Request(url="https://arxiv.org/list/cs.CR/recent", callback="parse")

    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        if "api/query" in response.url or response.text.startswith("<?xml"):
            async for item in self._parse_atom_feed(response):
                yield item
        else:
            async for item in self._parse_html_list(response):
                yield item

    async def _parse_atom_feed(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        selector = XmlSelector(response.text)
        for entry in selector.find_all("entry"):
            item = _map_atom_entry_to_scraped_item(entry)
            if item is not None:
                yield item

    async def _parse_html_list(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        selector = Selector(response.text)
        links = selector.css("a")
        for link in links:
            href = link.get_attr("href")
            if href.startswith("/abs/"):
                clean_id = href.split("/abs/")[-1].strip()
                abs_url = f"https://arxiv.org/abs/{clean_id}"
                yield Request(url=abs_url, callback="parse_abstract")

    async def parse_abstract(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        selector = Selector(response.text)
        title_nodes = selector.css("h1.title")
        abstract_nodes = selector.css("blockquote.abstract")

        title = title_nodes[0].text if title_nodes else "Untitled"
        title = re.sub(r"^Title:\s*", "", title)
        abstract = abstract_nodes[0].text if abstract_nodes else ""
        abstract = re.sub(r"^Abstract:\s*", "", abstract)

        clean_id = response.url.split("/abs/")[-1].strip()
        yield ScrapedItem(
            item_id=f"arxiv_{clean_id}",
            source_url=response.url,
            title=title,
            payload={
                "type": "security-paper",
                "clean_id": clean_id,
                "source": "arxiv",
                "abstract": abstract,
                "authors": [],
                "published_date": "",
                "pdf_url": f"https://arxiv.org/pdf/{clean_id}.pdf",
                "tags": ["security"],
            },
        )


def _map_atom_entry_to_scraped_item(entry: XmlNode) -> Optional[ScrapedItem]:
    raw_id = entry.find_text("id")
    clean_id = _extract_arxiv_clean_id(raw_id)
    if not clean_id:
        return None

    title = entry.find_text("title")
    summary = entry.find_text("summary")
    published = entry.find_text("published")
    authors: List[str] = [
        auth.find_text("name")
        for auth in entry.find_all("author")
        if auth.find_text("name")
    ]

    return ScrapedItem(
        item_id=f"arxiv_{clean_id}",
        source_url=f"https://arxiv.org/abs/{clean_id}",
        title=title,
        payload={
            "type": "security-paper",
            "clean_id": clean_id,
            "source": "arxiv",
            "abstract": summary,
            "authors": authors,
            "published_date": published,
            "pdf_url": f"https://arxiv.org/pdf/{clean_id}.pdf",
            "tags": ["cryptography", "network-security"],
        },
    )


def _extract_arxiv_clean_id(raw_id: str) -> str:
    match = re.search(r"(\d{4}\.\d{4,5}(?:v\d+)?)", raw_id)
    if match:
        clean = match.group(1)
        return re.sub(r"v\d+$", "", clean)
    return ""
