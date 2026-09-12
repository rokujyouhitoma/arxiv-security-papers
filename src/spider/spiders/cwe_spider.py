"""Backward-compatible re-export for CweSpider (Moved to src/domain/security/spiders/)."""

from domain.security.spiders.cwe_spider import (
    CweSpider,
    _build_cwe_tags,
    _map_cwe_item,
    _normalize_cwe_id,
)

__all__ = [
    "CweSpider",
    "_map_cwe_item",
    "_normalize_cwe_id",
    "_build_cwe_tags",
]
