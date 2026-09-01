"""Spider Contracts testing framework for validating spider extraction schemas."""

from __future__ import annotations

import re
from typing import Any, Dict, Optional, Sequence

from ..core.engine import ScrapedItem


def _parse_returns_contract(docstring: str, contracts: Dict[str, Any]) -> None:
    returns_match = re.search(r"@returns\s+(items|requests)\s+(\d+)\s*(\d*)", docstring)
    if returns_match:
        contracts["returns_type"] = returns_match.group(1)
        contracts["returns_min"] = int(returns_match.group(2))
        contracts["returns_max"] = (
            int(returns_match.group(3)) if returns_match.group(3) else None
        )


def _parse_url_and_scrapes(docstring: str, contracts: Dict[str, Any]) -> None:
    url_match = re.search(r"@url\s+([^\s]+)", docstring)
    if url_match:
        contracts["url"] = url_match.group(1)
    scrapes_match = re.search(r"@scrapes\s+([^\n\r]+)", docstring)
    if scrapes_match:
        contracts["scrapes_fields"] = [
            f.strip() for f in scrapes_match.group(1).split(",") if f.strip()
        ]


def _item_has_field(item: ScrapedItem, field: str) -> bool:
    if field == "title":
        return bool(item.title)
    return field in item.payload


def _item_valid_for_fields(item: ScrapedItem, required_fields: Sequence[str]) -> bool:
    return all(_item_has_field(item, f) for f in required_fields)


class SpiderContractVerifier:
    """Verifies declarative contracts defined in Spider docstrings."""

    @staticmethod
    def extract_contracts(docstring: Optional[str]) -> Dict[str, Any]:
        """Extracts @url, @returns, @scrapes directives from docstring."""
        if not docstring:
            return {}
        contracts: Dict[str, Any] = {}
        _parse_url_and_scrapes(docstring, contracts)
        _parse_returns_contract(docstring, contracts)
        return contracts

    @staticmethod
    def verify_items(
        items: Sequence[ScrapedItem], required_fields: Sequence[str]
    ) -> bool:
        """Verifies that all scraped items contain required fields."""
        if not items and required_fields:
            return False
        return all(_item_valid_for_fields(item, required_fields) for item in items)
