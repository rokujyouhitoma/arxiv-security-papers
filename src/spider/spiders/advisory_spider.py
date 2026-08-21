"""Security Advisory and Vulnerability Intelligence Spider."""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from typing import AsyncIterator, List, Optional, Set, Union

from ..core.downloader import Request, Response
from ..core.engine import ScrapedItem
from .base import BaseSpider


class AdvisorySpider(BaseSpider):
    """Spider for crawling CVE alerts and security advisory feeds."""

    name: str = "advisory_spider"
    start_urls: List[str] = [
        "https://cve.mitre.org/data/downloads/allitems.xml",
    ]
    allowed_domains: Set[str] = {"cve.mitre.org", "nvd.nist.gov"}

    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        try:
            root = ET.fromstring(response.text)
            for item in root.findall(".//item"):
                scraped = _map_advisory_item(item, response.url)
                if scraped is not None:
                    yield scraped
        except Exception:
            pass


def _map_advisory_item(item: ET.Element, fallback_url: str) -> Optional[ScrapedItem]:
    title_elem = item.find("title")
    desc_elem = item.find("description")
    link_elem = item.find("link")

    title = (title_elem.text or "").strip() if title_elem is not None else "Advisory"
    desc = (desc_elem.text or "").strip() if desc_elem is not None else ""
    link = (link_elem.text or "").strip() if link_elem is not None else fallback_url

    cve_match = re.search(r"(CVE-\d{4}-\d{4,7})", f"{title} {desc}")
    clean_id = cve_match.group(1) if cve_match else "ADV-UNKNOWN"

    return ScrapedItem(
        item_id=f"advisory_{clean_id}",
        source_url=link,
        title=title,
        payload={
            "clean_id": clean_id,
            "source": "advisory",
            "abstract": desc,
            "authors": ["Security Response Team"],
            "published_date": "",
            "pdf_url": "",
            "tags": ["vulnerability", "cve", "threat-intelligence"],
        },
    )
