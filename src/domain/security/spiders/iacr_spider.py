#!/usr/bin/env python3
"""IACR ePrint Cryptology Archive Crawling Spider."""

from __future__ import annotations

import re
from typing import AsyncIterator, List, Optional, Set, Union

from spider.core.downloader import Request, Response
from spider.core.engine import ScrapedItem
from spider.core.selector import XmlNode, XmlSelector
from spider.spiders.base import BaseSpider


class IacrSpider(BaseSpider):
    """Spider for crawling IACR Cryptology ePrint Archive."""

    name: str = "iacr_spider"
    download_delay: float = 3.0
    start_urls: List[str] = [
        "https://eprint.iacr.org/rss/rss.xml",
    ]
    allowed_domains: Set[str] = {"eprint.iacr.org"}

    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        selector = XmlSelector(response.text)
        for item_node in selector.find_all("item"):
            scraped = _map_iacr_item(item_node, response.url)
            if scraped is not None:
                yield scraped


def _map_iacr_item(item_node: XmlNode, fallback_url: str) -> Optional[ScrapedItem]:
    link = item_node.find_text("link")
    clean_id = _extract_iacr_clean_id(link)
    if not clean_id:
        return None

    title = item_node.find_text("title", default="Untitled")
    desc = item_node.find_text("description")
    pub = item_node.find_text("pubDate")

    return ScrapedItem(
        item_id=f"iacr_{clean_id}",
        source_url=link or f"https://eprint.iacr.org/{clean_id}",
        title=title,
        payload={
            "type": "security-paper",
            "clean_id": clean_id,
            "source": "iacr",
            "abstract": desc,
            "authors": [],
            "published_date": pub,
            "pdf_url": f"https://eprint.iacr.org/{clean_id}.pdf",
            "tags": ["cryptography", "zero-knowledge", "iacr-eprint"],
        },
    )


def _extract_iacr_clean_id(link: str) -> str:
    match = re.search(r"(\d{4}/\d{3,5})", link)
    if match:
        return match.group(1).replace("/", "_")
    return ""
