"""arXiv Computer Science & Cryptography Domain Spider."""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from typing import AsyncIterator, Dict, List, Optional, Set, Union

from ..core.downloader import Request, Response
from ..core.engine import ScrapedItem
from ..core.selector import Selector
from .base import BaseSpider


class ArxivSpider(BaseSpider):
    """Spider for crawling arXiv computer security and cryptography papers."""

    name: str = "arxiv_spider"
    start_urls: List[str] = [
        (
            "https://export.arxiv.org/api/query?"
            "search_query=cat:cs.CR&sortBy=submittedDate&sortOrder=descending&max_results=25"
        ),
        "https://arxiv.org/list/cs.CR/recent",
    ]
    allowed_domains: Set[str] = {"arxiv.org", "export.arxiv.org"}

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
        try:
            root = ET.fromstring(response.text)
            ns = {"atom": "http://www.w3.org/2005/Atom"}
            for entry in root.findall("atom:entry", ns):
                item = _map_atom_entry_to_scraped_item(entry, ns)
                if item is not None:
                    yield item
        except Exception:
            pass

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
                "clean_id": clean_id,
                "source": "arxiv",
                "abstract": abstract,
                "authors": [],
                "published_date": "",
                "pdf_url": f"https://arxiv.org/pdf/{clean_id}.pdf",
                "tags": ["security"],
            },
        )


def _map_atom_entry_to_scraped_item(
    entry: ET.Element, ns: Dict[str, str]
) -> Optional[ScrapedItem]:
    clean_id = _extract_entry_id(entry, ns)
    if not clean_id:
        return None

    title = _extract_entry_text(entry, "atom:title", ns, default="")
    summary = _extract_entry_text(entry, "atom:summary", ns, default="")
    published = _extract_entry_text(entry, "atom:published", ns, default="")
    authors = _extract_entry_authors(entry, ns)

    return ScrapedItem(
        item_id=f"arxiv_{clean_id}",
        source_url=f"https://arxiv.org/abs/{clean_id}",
        title=title,
        payload={
            "clean_id": clean_id,
            "source": "arxiv",
            "abstract": summary,
            "authors": authors,
            "published_date": published,
            "pdf_url": f"https://arxiv.org/pdf/{clean_id}.pdf",
            "tags": ["cryptography", "network-security"],
        },
    )


def _extract_entry_id(entry: ET.Element, ns: Dict[str, str]) -> str:
    arxiv_id_elem = entry.find("atom:id", ns)
    raw_id = (arxiv_id_elem.text or "").strip() if arxiv_id_elem is not None else ""
    return _extract_arxiv_clean_id(raw_id)


def _extract_entry_text(
    entry: ET.Element, tag: str, ns: Dict[str, str], default: str = ""
) -> str:
    elem = entry.find(tag, ns)
    if elem is not None and elem.text:
        return re.sub(r"\s+", " ", elem.text.strip())
    return default


def _extract_entry_authors(entry: ET.Element, ns: Dict[str, str]) -> List[str]:
    authors: List[str] = []
    for auth in entry.findall("atom:author", ns):
        name_elem = auth.find("atom:name", ns)
        if name_elem is not None and name_elem.text:
            authors.append(name_elem.text.strip())
    return authors


def _extract_arxiv_clean_id(raw_id: str) -> str:
    match = re.search(r"(\d{4}\.\d{4,5}(?:v\d+)?)", raw_id)
    if match:
        clean = match.group(1)
        return re.sub(r"v\d+$", "", clean)
    return ""
