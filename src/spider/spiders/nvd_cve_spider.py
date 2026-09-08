"""Backward-compatible re-export for NvdCveSpider (Moved to src/domain/security/spiders/)."""

from domain.security.spiders.nvd_cve_spider import (
    NvdCveSpider,
    _build_next_pagination_request,
    _extract_cpe_vendors_products,
    _extract_cve_items,
    _extract_nvd_cvss,
    _extract_nvd_cwes,
    _extract_nvd_description,
    _extract_nvd_references,
    _map_nvd_cve_item,
    _parse_cpe_criteria,
    _parse_cvss_metric,
)

__all__ = [
    "NvdCveSpider",
    "_extract_cve_items",
    "_build_next_pagination_request",
    "_extract_nvd_description",
    "_parse_cvss_metric",
    "_extract_nvd_cvss",
    "_extract_nvd_cwes",
    "_parse_cpe_criteria",
    "_extract_cpe_vendors_products",
    "_extract_nvd_references",
    "_map_nvd_cve_item",
]
