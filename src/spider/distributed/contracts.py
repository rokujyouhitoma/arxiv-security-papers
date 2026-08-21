"""Spider Contracts testing framework for validating spider extraction schemas."""

from __future__ import annotations

import re
from typing import Any, Dict, Optional, Sequence

from ..core.engine import ScrapedItem


class SpiderContractVerifier:
    """Verifies declarative contracts defined in Spider docstrings."""

    @staticmethod
    def extract_contracts(docstring: Optional[str]) -> Dict[str, Any]:
        """Extracts @url, @returns, @scrapes directives from docstring."""
        if not docstring:
            return {}

        contracts: Dict[str, Any] = {}
        url_match = re.search(r"@url\s+([^\s]+)", docstring)
        if url_match:
            contracts["url"] = url_match.group(1)

        returns_match = re.search(
            r"@returns\s+(items|requests)\s+(\d+)\s*(\d*)", docstring
        )
        if returns_match:
            contracts["returns_type"] = returns_match.group(1)
            contracts["returns_min"] = int(returns_match.group(2))
            contracts["returns_max"] = (
                int(returns_match.group(3)) if returns_match.group(3) else None
            )

        scrapes_match = re.search(r"@scrapes\s+([^\n\r]+)", docstring)
        if scrapes_match:
            contracts["scrapes_fields"] = [
                f.strip() for f in scrapes_match.group(1).split(",") if f.strip()
            ]

        return contracts

    @staticmethod
    def verify_items(
        items: Sequence[ScrapedItem], required_fields: Sequence[str]
    ) -> bool:
        """Verifies that all scraped items contain required fields."""
        if not items and required_fields:
            return False

        for item in items:
            payload = item.payload
            for field in required_fields:
                if field == "title" and not item.title:
                    return False
                if field not in payload and field != "title":
                    return False
        return True
