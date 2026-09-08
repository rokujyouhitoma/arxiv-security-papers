#!/usr/bin/env python3
"""CISA Known Exploited Vulnerabilities (KEV) Catalog Spider.

Pure-Python, zero external dependencies.
Adheres to CISA feed terms with 5.0s politeness delay and HTTP 304 cache integration.
"""

from __future__ import annotations

from typing import Any, AsyncIterator, Dict, List, Optional, Set, Union

from spider.core.downloader import Request, Response
from spider.core.engine import ScrapedItem
from spider.spiders.base import BaseSpider


def _extract_cisa_records(response: Response) -> List[Dict[str, Any]]:
    """Extracts raw vulnerability dictionaries from response."""
    data = response.json()
    if not isinstance(data, dict):
        return []
    vulns = data.get("vulnerabilities")
    if not isinstance(vulns, list):
        return []
    return [v for v in vulns if isinstance(v, dict)]


class CisaKevSpider(BaseSpider):
    """Spider for crawling CISA Known Exploited Vulnerabilities (KEV) Catalog."""

    name: str = "cisa_kev_spider"
    download_delay: float = 5.0
    allowed_domains: Set[str] = {"cisa.gov", "www.cisa.gov"}
    start_urls: List[str] = [
        "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
    ]

    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        """Parses CISA KEV JSON feed and yields normalized ScrapedItems."""
        try:
            records = _extract_cisa_records(response)
        except Exception:
            return

        for record in records:
            item = _map_cisa_kev_item(record)
            if item is not None:
                yield item


def _build_cisa_tags(is_ransomware: bool) -> List[str]:
    """Constructs security domain tags for CISA KEV records."""
    tags = ["vulnerability", "cisa-kev", "exploited-in-the-wild"]
    if is_ransomware:
        tags.append("ransomware")
    return tags


def _safe_field(v: Dict[str, Any], key: str) -> str:
    """Safely extracts trimmed string from dictionary."""
    val = v.get(key)
    return str(val).strip() if val is not None else ""


def _extract_cisa_title(v: Dict[str, Any], cve_id: str, product: str) -> str:
    """Extracts title with fallback."""
    vuln_name = _safe_field(v, "vulnerabilityName")
    return vuln_name if vuln_name else f"[{cve_id}] {product} Vulnerability"


def _extract_cisa_refs(v: Dict[str, Any]) -> List[str]:
    """Extracts reference URL list from notes."""
    notes = _safe_field(v, "notes")
    return [notes] if notes.startswith("http") else []


def _extract_cisa_meta(v: Dict[str, Any], cve_id: str) -> Dict[str, Any]:
    """Extracts scalar metadata from CISA record."""
    product = _safe_field(v, "product")
    return {
        "vendor": _safe_field(v, "vendorProject"),
        "product": product,
        "title": _extract_cisa_title(v, cve_id, product),
        "refs": _extract_cisa_refs(v),
        "date_added": _safe_field(v, "dateAdded"),
        "short_desc": _safe_field(v, "shortDescription"),
        "action": _safe_field(v, "requiredAction"),
        "due_date": _safe_field(v, "dueDate"),
        "ransomware": _safe_field(v, "knownRansomwareCampaignUse"),
    }


def _build_payload(
    cve_id: str, meta: Dict[str, Any], tags: List[str]
) -> Dict[str, Any]:
    """Builds the normalized ScrapedItem payload."""
    vendor = meta["vendor"]
    product = meta["product"]
    desc = meta["short_desc"]
    return {
        "type": "vulnerability",
        "source": "cisa-kev",
        "cve_id": cve_id,
        "clean_id": cve_id,
        "title": meta["title"],
        "abstract": desc,
        "description": desc,
        "overview": desc,
        "published_date": meta["date_added"],
        "due_date": meta["due_date"],
        "kev_status": True,
        "affected_vendors": [vendor] if vendor else [],
        "affected_products": [product] if product else [],
        "required_action": meta["action"],
        "remediation": meta["action"],
        "known_ransomware_campaign_use": meta["ransomware"],
        "references": meta["refs"],
        "tags": tags,
    }


def _map_cisa_kev_item(v: Dict[str, Any]) -> Optional[ScrapedItem]:
    """Normalizes raw CISA KEV vulnerability dictionary into ScrapedItem."""
    cve_id = _safe_field(v, "cveID").upper()
    if not cve_id:
        return None

    meta = _extract_cisa_meta(v, cve_id)
    is_ransomware = meta["ransomware"].lower() == "known"
    tags = _build_cisa_tags(is_ransomware)
    payload = _build_payload(cve_id, meta, tags)

    return ScrapedItem(
        item_id=f"cisa_kev_{cve_id}",
        source_url=f"https://nvd.nist.gov/vuln/detail/{cve_id}",
        title=meta["title"],
        payload=payload,
    )
