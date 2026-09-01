"""Backward-compatible re-export for ArxivSpider (Moved to src/domain/security/spiders/)."""

from domain.security.spiders.arxiv_spider import (
    ArxivSpider,
    _extract_arxiv_clean_id,
    _extract_entry_authors,
    _extract_entry_id,
    _extract_entry_text,
    _map_atom_entry_to_scraped_item,
)

__all__ = [
    "ArxivSpider",
    "_map_atom_entry_to_scraped_item",
    "_extract_entry_id",
    "_extract_entry_text",
    "_extract_entry_authors",
    "_extract_arxiv_clean_id",
]
