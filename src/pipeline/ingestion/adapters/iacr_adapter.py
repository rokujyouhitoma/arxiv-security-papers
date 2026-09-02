#!/usr/bin/env python3
"""
IACR ePrint Cryptology Preprint Source Adapter.
Fetches cryptology research preprints from IACR ePrint RSS/Atom feeds.
"""

import os
import re
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any, List, Optional, Tuple

from ..arxiv_client import _safe_fromstring, safe_urlopen
from .base import BaseSourceAdapter, RawItem


def _get_node_text(elem: Any, tags: List[str]) -> str:
    for tag in tags:
        node = elem.find(tag)
        if node is not None and node.text:
            return str(re.sub(r"\s+", " ", node.text).strip())
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


class IacrEprintSourceAdapter(BaseSourceAdapter):
    """Source adapter for IACR ePrint cryptology archive."""

    IACR_RSS_URL = "https://eprint.iacr.org/rss/rss.xml"

    @property
    def source_name(self) -> str:
        return "iacr_eprint"

    def fetch_items(
        self,
        query: str = "",
        max_results: int = 100,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        **kwargs: Any,
    ) -> List[RawItem]:
        """Fetches latest cryptology preprints from IACR ePrint feed."""
        feed_url = kwargs.get("feed_url") or self.IACR_RSS_URL
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
            return self._parse_feed_xml(content, max_results)
        except Exception:
            # Fallback or empty if feed unreachable
            return []

    def _find_item_nodes(self, root: Any) -> List[Any]:
        """Finds RSS item or Atom entry nodes in IACR XML root."""
        channel = root.find("channel")
        item_nodes: List[Any] = (
            list(channel.findall("item"))
            if channel is not None
            else list(root.findall("item"))
        )
        if not item_nodes:
            ns = {"atom": "http://www.w3.org/2005/Atom"}
            item_nodes = list(root.findall("atom:entry", ns))
        return item_nodes

    def _parse_feed_xml(self, xml_bytes: bytes, max_results: int) -> List[RawItem]:
        """Parses RSS/Atom XML from IACR ePrint into RawItems."""
        try:
            root = _safe_fromstring(xml_bytes)
        except Exception:
            return []

        item_nodes = self._find_item_nodes(root)
        items: List[RawItem] = []
        for elem in item_nodes[:max_results]:
            item = self._parse_iacr_elem(elem)
            if item:
                items.append(item)
        return items

    def _resolve_iacr_item_id(self, link: str, title: str) -> str:
        """Resolves canonical IACR ePrint item identifier."""
        match = re.search(r"(\d{4})/(\d+)", link) or re.search(r"(\d{4})/(\d+)", title)
        if match:
            return f"iacr-{match.group(1)}-{match.group(2)}"
        clean_link = re.sub(r"[^\w-]", "_", link)
        if clean_link:
            return f"iacr-{clean_link[-16:]}"
        return f"iacr-{hash(title) & 0xFFFFFF}"

    def _extract_iacr_fields(self, elem: Any) -> Tuple[str, str, str, List[str], str]:
        """Extracts title, link, abstract, authors, and published fields from IACR element."""
        title = (
            _get_node_text(elem, ["title", "{http://www.w3.org/2005/Atom}title"])
            or "Untitled IACR Paper"
        )
        link = _get_node_link(elem, ["link", "{http://www.w3.org/2005/Atom}link"])
        abstract = _get_node_text(
            elem, ["description", "{http://www.w3.org/2005/Atom}summary"]
        )
        author_text = _get_node_text(
            elem, ["author", "{http://www.w3.org/2005/Atom}author"]
        )
        authors = [author_text] if author_text else []
        published = (
            _get_node_text(elem, ["pubDate", "{http://www.w3.org/2005/Atom}published"])
            or datetime.now(timezone.utc).isoformat()
        )
        return title, link, abstract, authors, published

    def _parse_iacr_elem(self, elem: Any) -> Optional[RawItem]:
        title, link, abstract, authors, published = self._extract_iacr_fields(elem)
        item_id = self._resolve_iacr_item_id(link, title)
        pdf_url = f"{link}.pdf" if link and not link.endswith(".pdf") else link

        return RawItem(
            item_id=item_id,
            clean_id=item_id,
            title=title,
            abstract=abstract,
            authors=authors,
            published=published,
            updated=published,
            url=link or f"https://eprint.iacr.org/{item_id}",
            pdf_url=pdf_url,
            primary_category="cryptography",
            categories=["cryptography", "iacr.eprint"],
            source_type="iacr_eprint",
        )

    def fetch_content_and_text(self, item: RawItem, raw_dir: str) -> None:
        """Stores abstract as text when full PDF is not downloaded."""
        os.makedirs(raw_dir, exist_ok=True)
        txt_path = os.path.join(raw_dir, f"{item.clean_id}.txt")
        with open(txt_path, "w", encoding="utf-8") as f:
            f.write(
                f"Title: {item.title}\nAuthors: {', '.join(item.authors)}\n\nAbstract:\n{item.abstract}\n"
            )
