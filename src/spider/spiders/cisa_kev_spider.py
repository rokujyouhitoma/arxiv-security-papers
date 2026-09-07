"""Backward-compatible re-export for CisaKevSpider (Moved to src/domain/security/spiders/)."""

from domain.security.spiders.cisa_kev_spider import (
    CisaKevSpider,
    _build_cisa_tags,
    _extract_cisa_meta,
    _map_cisa_kev_item,
)

__all__ = [
    "CisaKevSpider",
    "_map_cisa_kev_item",
    "_extract_cisa_meta",
    "_build_cisa_tags",
]
