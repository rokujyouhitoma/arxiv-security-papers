#!/usr/bin/env python3
"""
Base Source Adapter Interface and RawItem Data Model.
Provides unified abstractions for multi-source paper and article ingestion.
"""

import re
from abc import ABC, abstractmethod
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional


@dataclass
class RawItem:
    """Standardized representation of a collected paper or article."""

    item_id: str
    clean_id: str
    title: str
    abstract: str
    authors: List[str]
    published: str
    updated: str
    url: str
    pdf_url: Optional[str] = None
    primary_category: str = "general"
    categories: List[str] = field(default_factory=list)
    source_type: str = "arxiv"
    extra_metadata: Dict[str, Any] = field(default_factory=dict)
    fetched_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )

    def to_dict(self) -> Dict[str, Any]:
        """Converts to dictionary compatible with legacy pipeline."""
        data = asdict(self)
        # Add legacy-compatible keys for arXiv pipeline
        data["arxiv_id"] = self.item_id
        data["summary"] = self.abstract
        data["abs_url"] = self.url
        return data

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "RawItem":
        """Constructs a RawItem from a dictionary."""
        item_id = d.get("item_id") or d.get("arxiv_id") or ""
        clean_id = d.get("clean_id") or re.sub(r"v\d+$", "", item_id)
        return cls(
            item_id=item_id,
            clean_id=clean_id,
            title=d.get("title", ""),
            abstract=d.get("abstract") or d.get("summary") or "",
            authors=d.get("authors", []),
            published=d.get("published", ""),
            updated=d.get("updated", ""),
            url=d.get("url") or d.get("abs_url") or "",
            pdf_url=d.get("pdf_url"),
            primary_category=d.get("primary_category", "general"),
            categories=d.get("categories", []),
            source_type=d.get("source_type", "arxiv"),
            extra_metadata=d.get("extra_metadata", {}),
            fetched_at=d.get("fetched_at", datetime.now(timezone.utc).isoformat()),
        )


class BaseSourceAdapter(ABC):
    """Abstract base class for all pluggable data source adapters."""

    @property
    @abstractmethod
    def source_name(self) -> str:
        """Unique identifier for the source adapter."""
        pass

    @abstractmethod
    def fetch_items(
        self,
        query: str = "",
        max_results: int = 100,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        **kwargs: Any,
    ) -> List[RawItem]:
        """
        Fetches metadata for items from the target data source.

        Args:
            query: Search query or category filter.
            max_results: Maximum number of items to retrieve.
            start_date: Optional start date for filtering.
            end_date: Optional end date for filtering.
            **kwargs: Adapter-specific parameters.

        Returns:
            List of standardized RawItem instances.
        """
        pass

    @abstractmethod
    def fetch_content_and_text(self, item: RawItem, raw_dir: str) -> None:
        """
        Fetches the primary content (e.g. PDF/HTML) and extracts full text.

        Args:
            item: The RawItem metadata.
            raw_dir: Output directory to store downloaded/extracted files.
        """
        pass
