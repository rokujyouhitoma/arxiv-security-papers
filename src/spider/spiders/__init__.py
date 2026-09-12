"""Spiders core package."""

from __future__ import annotations

import importlib
from typing import Any

from .base import BaseSpider

__all__ = ["BaseSpider"]

_LEGACY_SPIDERS = {
    "AdvisorySpider": "domain.security.spiders.advisory_spider",
    "ArxivSpider": "domain.security.spiders.arxiv_spider",
    "CisaKevSpider": "domain.security.spiders.cisa_kev_spider",
    "CweSpider": "domain.security.spiders.cwe_spider",
    "IacrSpider": "domain.security.spiders.iacr_spider",
    "NvdCveSpider": "domain.security.spiders.nvd_cve_spider",
}


def __getattr__(name: str) -> Any:
    if name in _LEGACY_SPIDERS:
        mod_path = _LEGACY_SPIDERS[name]
        mod = importlib.import_module(mod_path)
        return getattr(mod, name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
