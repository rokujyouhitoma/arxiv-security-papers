"""Backward-compatible re-export for AdvisorySpider (Moved to src/domain/security/spiders/)."""

from domain.security.spiders.advisory_spider import AdvisorySpider, _map_advisory_item

__all__ = [
    "AdvisorySpider",
    "_map_advisory_item",
]
