#!/usr/bin/env python3
"""
ArXiv Source Adapter.
Wraps arXiv Atom API, rate-limiting, and RSS fallback for multiple categories.
"""

from datetime import datetime
from typing import Any, Dict, List, Optional

from ..arxiv_client import fetch_arxiv_papers, fetch_arxiv_rss_fallback
from ..pdf_extractor import fetch_single_pdf_and_text
from .base import BaseSourceAdapter, RawItem


class ArxivSourceAdapter(BaseSourceAdapter):
    """Source adapter for arXiv preprints across multiple categories."""

    def __init__(self, default_category: str = "cs.CR") -> None:
        self._default_category = default_category

    @property
    def source_name(self) -> str:
        return "arxiv"

    def _resolve_target_query(self, query: str, kwargs: Any) -> str:
        """Resolves target query with category fallback."""
        if query:
            return query
        if "category" in kwargs:
            return f"cat:{kwargs['category']}"
        return f"cat:{self._default_category}"

    def _fetch_raw_paper_dicts(
        self,
        target_query: str,
        max_results: int,
        rate_limiter: Optional[Any] = None,
    ) -> List[Dict[str, Any]]:
        """Fetches paper dicts from API with RSS fallback."""
        raw_dicts = fetch_arxiv_papers(
            query=target_query, max_results=max_results, rate_limiter=rate_limiter
        )
        if not raw_dicts:
            print(
                f"[Ingestion:arXiv] API fetch returned 0 papers or rate-limited for '{target_query}'. "
                "Triggering automatic fallback to arXiv RSS feed..."
            )
            raw_dicts = fetch_arxiv_rss_fallback(max_results=min(max_results, 50))
        return raw_dicts or []

    def fetch_items(
        self,
        query: str = "",
        max_results: int = 100,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        **kwargs: Any,
    ) -> List[RawItem]:
        """Fetches items from arXiv API with fallback to RSS."""
        target_query = self._resolve_target_query(query, kwargs)
        rate_limiter = kwargs.get("rate_limiter")
        raw_dicts = self._fetch_raw_paper_dicts(
            target_query, max_results, rate_limiter=rate_limiter
        )

        items: List[RawItem] = []
        for d in raw_dicts:
            item = RawItem.from_dict(d)
            item.source_type = "arxiv"
            items.append(item)

        return items

    def fetch_content_and_text(self, item: RawItem, raw_dir: str) -> None:
        """Downloads arXiv PDF and extracts text via pdftotext."""
        fetch_single_pdf_and_text(item.to_dict(), raw_dir)
