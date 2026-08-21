"""Spider Adapter integrating DSN-15 spider engine into fetcher ETL pipeline."""

from __future__ import annotations

import asyncio
import json
import os
from datetime import datetime, timezone
from typing import Any, List, Optional

from spider.core.engine import ScrapedItem
from spider.runner import run_spider

from .base import BaseSourceAdapter, RawItem


class SpiderSourceAdapter(BaseSourceAdapter):
    """Source Adapter that executes DSN-15 async Spiders to fetch research items."""

    def __init__(
        self,
        name: str = "spider_arxiv",
        spider_name: str = "arxiv",
        max_requests: int = 15,
    ) -> None:
        self._source_name: str = name
        self.spider_name: str = spider_name
        self.max_requests: int = max_requests

    @property
    def source_name(self) -> str:
        return self._source_name

    def fetch_items(
        self,
        query: str = "",
        max_results: int = 100,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        **kwargs: Any,
    ) -> List[RawItem]:
        """Runs the async spider and maps ScrapedItems into RawItems."""
        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)

        scraped_items: List[ScrapedItem] = loop.run_until_complete(
            run_spider(
                spider_name=self.spider_name,
                max_requests=min(self.max_requests, max_results),
                enable_cache=True,
                persist_db=False,
            )
        )

        raw_items: List[RawItem] = []
        for item in scraped_items:
            clean_id = item.payload.get("clean_id", item.item_id)
            published = (
                item.payload.get("published_date")
                or datetime.now(timezone.utc).isoformat()
            )
            raw_item = RawItem(
                item_id=f"{self.source_name}_{clean_id}",
                clean_id=clean_id,
                title=item.title,
                abstract=item.payload.get("abstract", ""),
                authors=item.payload.get("authors", []),
                published=published,
                updated=published,
                url=item.source_url,
                pdf_url=item.payload.get("pdf_url"),
                primary_category="security",
                categories=item.payload.get("tags", ["security"]),
                source_type=self.source_name,
                extra_metadata=item.payload,
            )
            raw_items.append(raw_item)

        return raw_items

    def fetch_content_and_text(self, item: RawItem, raw_dir: str) -> None:
        """Saves scraped metadata JSON and text into raw_data folder."""
        os.makedirs(raw_dir, exist_ok=True)

        meta_file = os.path.join(raw_dir, f"{item.clean_id}_meta.json")
        txt_file = os.path.join(raw_dir, f"{item.clean_id}.txt")
        raw_abs_file = os.path.join(raw_dir, f"{item.clean_id}_raw_abstract.txt")

        with open(meta_file, "w", encoding="utf-8") as f:
            json.dump(item.extra_metadata, f, ensure_ascii=False, indent=2)

        with open(raw_abs_file, "w", encoding="utf-8") as f:
            f.write(item.abstract)

        with open(txt_file, "w", encoding="utf-8") as f:
            f.write(f"Title: {item.title}\n\nAbstract:\n{item.abstract}")
