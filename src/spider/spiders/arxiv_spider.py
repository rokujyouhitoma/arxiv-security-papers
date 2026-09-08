"""Backward-compatible re-export for ArxivSpider (Moved to src/domain/security/spiders/)."""

from domain.security.spiders.arxiv_spider import (
    ArxivSpider,
    _extract_arxiv_clean_id,
    _map_atom_entry_to_scraped_item,
)

__all__ = [
    "ArxivSpider",
    "_map_atom_entry_to_scraped_item",
    "_extract_arxiv_clean_id",
]
