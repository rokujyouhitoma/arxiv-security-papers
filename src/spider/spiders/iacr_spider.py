"""Backward-compatible re-export for IacrSpider (Moved to src/domain/security/spiders/)."""

from domain.security.spiders.iacr_spider import (
    IacrSpider,
    _extract_iacr_clean_id,
    _map_iacr_item,
)

__all__ = [
    "IacrSpider",
    "_map_iacr_item",
    "_extract_iacr_clean_id",
]
