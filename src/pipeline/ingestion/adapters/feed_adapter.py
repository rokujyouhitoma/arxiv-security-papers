#!/usr/bin/env python3
"""
Generic RSS / Atom Feed Source Adapter.
Enables ingesting security research blogs, conference announcements, and advisory feeds.
"""

import os
import re
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any, List, Optional

from ..arxiv_client import _safe_fromstring, safe_urlopen
from .base import BaseSourceAdapter, RawItem


def _get_node_text(elem: Any, tags: List[str]) -> str:
    for tag in tags:
        node = elem.find(tag)
        if node is not None and node.text:
            cleaned = re.sub(r"<[^>]+>", " ", node.text)
            return str(re.sub(r"\s+", " ", cleaned).strip())
    return ""


def _get_node_link(elem: Any, tags: List[str]) -> str:
    for tag in tags:
        node = elem.find(tag)
        if node is not None:
            href = node.attrib.get("href")
            if href:
                return str(href)
            if node.text:
                return str(node.text.strip())
    return ""


class FeedSourceAdapter(BaseSourceAdapter):
    """Source adapter for generic RSS 2.0 and Atom feeds."""

    def __init__(self, default_feed_url: str = "") -> None:
        self._default_feed_url = default_feed_url

    @property
    def source_name(self) -> str:
        return "rss_feed"

    def fetch_items(
        self,
        query: str = "",
        max_results: int = 100,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        **kwargs: Any,
    ) -> List[RawItem]:
        """Fetches items from specified RSS/Atom feed URL."""
        feed_url = kwargs.get("feed_url") or query or self._default_feed_url
        if not feed_url:
            return []

        try:
            req = urllib.request.Request(
                feed_url,
                headers={
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ArXivSecurityOKFBot/1.0"
                },
            )
            with safe_urlopen(req, timeout=15) as response:
                content = response.read()
            return self._parse_feed(content, max_results, feed_url)
        except Exception:
            return []

    def _parse_feed(
        self, xml_bytes: bytes, max_results: int, feed_url: str
    ) -> List[RawItem]:
        """Parses feed XML into standardized RawItem instances."""
        try:
            root = _safe_fromstring(xml_bytes)
        except Exception:
            return []

        channel = root.find("channel")
        item_nodes = (
            channel.findall("item") if channel is not None else root.findall("item")
        )
        if not item_nodes:
            ns = {"atom": "http://www.w3.org/2005/Atom"}
            item_nodes = root.findall("atom:entry", ns)

        domain_tag = re.sub(r"https?://([^/]+).*", r"\1", feed_url).replace(".", "_")

        items: List[RawItem] = []
        for idx, elem in enumerate(item_nodes[:max_results]):
            item = self._parse_feed_elem(elem, domain_tag, idx, feed_url)
            if item:
                items.append(item)
        return items

    def _parse_feed_elem(
        self, elem: Any, domain_tag: str, idx: int, feed_url: str
    ) -> Optional[RawItem]:
        title = (
            _get_node_text(elem, ["title", "{http://www.w3.org/2005/Atom}title"])
            or f"Feed Item {idx+1}"
        )
        link = _get_node_link(elem, ["link", "{http://www.w3.org/2005/Atom}link"])
        abstract = _get_node_text(
            elem,
            [
                "description",
                "{http://www.w3.org/2005/Atom}summary",
                "{http://www.w3.org/2005/Atom}content",
            ],
        )
        author_text = _get_node_text(
            elem, ["author", "{http://www.w3.org/2005/Atom}author"]
        )
        authors = [author_text] if author_text else [domain_tag]
        published = (
            _get_node_text(
                elem,
                [
                    "pubDate",
                    "{http://www.w3.org/2005/Atom}published",
                    "{http://www.w3.org/2005/Atom}updated",
                ],
            )
            or datetime.now(timezone.utc).isoformat()
        )

        item_id = f"feed-{domain_tag[:12]}-{hash(link or title) & 0xFFFFFF:06x}"

        return RawItem(
            item_id=item_id,
            clean_id=item_id,
            title=title,
            abstract=abstract,
            authors=authors,
            published=published,
            updated=published,
            url=link or feed_url,
            pdf_url=None,
            primary_category="security_advisory",
            categories=["advisory", "feed", domain_tag],
            source_type="rss_feed",
        )

    def fetch_content_and_text(self, item: RawItem, raw_dir: str) -> None:
        """Stores feed abstract and metadata as plain text."""
        os.makedirs(raw_dir, exist_ok=True)
        txt_path = os.path.join(raw_dir, f"{item.clean_id}.txt")
        with open(txt_path, "w", encoding="utf-8") as f:
            f.write(
                f"Title: {item.title}\nSource: {item.url}\nPublished: {item.published}\n\nAbstract:\n{item.abstract}\n"
            )
