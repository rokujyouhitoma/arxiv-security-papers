#!/usr/bin/env python3
"""IACR ePrint Cryptology Archive Crawling Spider."""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from typing import AsyncIterator, List, Optional, Set, Union

from spider.core.downloader import Request, Response
from spider.core.engine import ScrapedItem
from spider.spiders.base import BaseSpider


class IacrSpider(BaseSpider):
    """Spider for crawling IACR Cryptology ePrint Archive."""

    name: str = "iacr_spider"
    start_urls: List[str] = [
        "https://eprint.iacr.org/rss/rss.xml",
    ]
    allowed_domains: Set[str] = {"eprint.iacr.org"}

    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        try:
            root = ET.fromstring(response.text)
            for item_elem in root.findall(".//item"):
                scraped = _map_iacr_item(item_elem, response.url)
                if scraped is not None:
                    yield scraped
        except Exception:
            pass


def _map_iacr_item(item_elem: ET.Element, fallback_url: str) -> Optional[ScrapedItem]:
    link = _get_elem_text(item_elem, "link")
    clean_id = _extract_iacr_clean_id(link)
    if not clean_id:
        return None

    title = _get_elem_text(item_elem, "title", default="Untitled")
    desc = _get_elem_text(item_elem, "description")
    pub = _get_elem_text(item_elem, "pubDate")

    return ScrapedItem(
        item_id=f"iacr_{clean_id}",
        source_url=link or f"https://eprint.iacr.org/{clean_id}",
        title=title,
        payload={
            "clean_id": clean_id,
            "source": "iacr",
            "abstract": desc,
            "authors": [],
            "published_date": pub,
            "pdf_url": f"https://eprint.iacr.org/{clean_id}.pdf",
            "tags": ["cryptography", "zero-knowledge"],
        },
    )


def _get_elem_text(elem: ET.Element, tag: str, default: str = "") -> str:
    child = elem.find(tag)
    if child is not None and child.text:
        return child.text.strip()
    return default


def _extract_iacr_clean_id(link: str) -> str:
    match = re.search(r"(\d{4}/\d{3,5})", link)
    if match:
        return match.group(1).replace("/", "_")
    return ""
