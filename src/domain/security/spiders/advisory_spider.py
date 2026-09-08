#!/usr/bin/env python3
"""Security Advisory and Vulnerability Intelligence Spider."""

from __future__ import annotations

import re
from typing import AsyncIterator, List, Optional, Set, Union

from spider.core.downloader import Request, Response
from spider.core.engine import ScrapedItem
from spider.core.selector import XmlNode, XmlSelector
from spider.spiders.base import BaseSpider


class AdvisorySpider(BaseSpider):
    """Spider for crawling CVE alerts and security advisory feeds."""

    name: str = "advisory_spider"
    download_delay: float = 5.0
    start_urls: List[str] = [
        "https://cve.mitre.org/data/downloads/allitems.xml",
    ]
    allowed_domains: Set[str] = {"cve.mitre.org", "nvd.nist.gov"}

    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        selector = XmlSelector(response.text)
        for item_node in selector.find_all("item"):
            scraped = _map_advisory_item(item_node, response.url)
            if scraped is not None:
                yield scraped


def _map_advisory_item(item_node: XmlNode, fallback_url: str) -> Optional[ScrapedItem]:
    title = item_node.find_text("title", "Advisory")
    desc = item_node.find_text("description", "")
    link = item_node.find_text("link", fallback_url)

    cve_match = re.search(r"(CVE-\d{4}-\d{4,7})", f"{title} {desc}")
    clean_id = cve_match.group(1) if cve_match else "ADV-UNKNOWN"
    cve_id = clean_id if clean_id != "ADV-UNKNOWN" else ""

    return ScrapedItem(
        item_id=f"advisory_{clean_id}",
        source_url=link,
        title=title,
        payload={
            "type": "security_advisory",
            "clean_id": clean_id,
            "cve_id": cve_id,
            "source": "cve-mitre",
            "abstract": desc,
            "description": desc,
            "authors": ["Security Response Team"],
            "published_date": "",
            "references": [link] if link else [],
            "tags": [
                "vulnerability",
                "cve",
                "threat-intelligence",
                "security-advisory",
            ],
        },
    )
