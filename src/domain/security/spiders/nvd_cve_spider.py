#!/usr/bin/env python3
"""NIST NVD CVE REST API 2.0 Spider.

Pure-Python, zero external dependencies.
Complies with NIST rate limits (6.5s without API key, 0.8s with API key)
and supports recursive pagination with resultsPerPage=2000.
"""

from __future__ import annotations

import os
from typing import Any, AsyncIterator, Dict, List, Optional, Set, Tuple, Union

from spider.core.downloader import Request, Response
from spider.core.engine import ScrapedItem
from spider.spiders.base import BaseSpider

NVD_API_BASE_URL = "https://services.nvd.nist.gov/rest/json/cves/2.0"


class NvdCveSpider(BaseSpider):
    """Spider for crawling NIST National Vulnerability Database REST API 2.0."""

    name: str = "nvd_cve_spider"
    allowed_domains: Set[str] = {"services.nvd.nist.gov"}

    def __init__(
        self,
        api_key: Optional[str] = None,
        results_per_page: int = 2000,
        *args: Any,
        **kwargs: Any,
    ) -> None:
        super().__init__()
        self.api_key = (api_key or os.environ.get("NVD_API_KEY", "")).strip()
        self.download_delay = 0.8 if self.api_key else 6.5
        self.results_per_page = min(max(1, results_per_page), 2000)

        self.custom_headers: Dict[str, str] = {}
        if self.api_key:
            self.custom_headers["apiKey"] = self.api_key

        self.start_urls: List[str] = [
            f"{NVD_API_BASE_URL}?resultsPerPage={self.results_per_page}"
        ]

    def start_requests(self) -> List[Request]:
        """Yields initial seed requests with authentication headers."""
        headers = dict(self.custom_headers)
        return [
            Request(url=url, headers=headers, callback="parse")
            for url in self.start_urls
        ]

    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        """Parses NVD CVE JSON response, yields items, and paginates recursively."""
        try:
            data = response.json()
            if not isinstance(data, dict):
                return
        except Exception:
            return

        for item in _extract_cve_items(data):
            yield item

        next_req = _build_next_pagination_request(
            data, self.results_per_page, self.custom_headers
        )
        if next_req is not None:
            yield next_req


def _map_cve_wrapper(wrapper: Any) -> Optional[ScrapedItem]:
    if not isinstance(wrapper, dict):
        return None
    cve = wrapper.get("cve")
    return _map_nvd_cve_item(cve) if isinstance(cve, dict) else None


def _extract_cve_items(data: Dict[str, Any]) -> List[ScrapedItem]:
    """Extracts ScrapedItem instances from NVD vulnerabilities list."""
    vulns = data.get("vulnerabilities", [])
    if not isinstance(vulns, list):
        return []
    items = [_map_cve_wrapper(w) for w in vulns]
    return [item for item in items if item is not None]


def _parse_pagination_meta(
    data: Dict[str, Any], default_rpp: int
) -> Optional[Tuple[int, int, int]]:
    try:
        total = int(data.get("totalResults", 0))
        start = int(data.get("startIndex", 0))
        rpp = int(data.get("resultsPerPage", default_rpp))
        return total, start, rpp
    except (ValueError, TypeError):
        return None


def _build_next_pagination_request(
    data: Dict[str, Any], results_per_page: int, headers: Dict[str, str]
) -> Optional[Request]:
    """Calculates next pagination offset and builds Request if more records exist."""
    meta = _parse_pagination_meta(data, results_per_page)
    if meta is None:
        return None
    total, start, rpp = meta
    next_index = start + rpp
    if next_index >= total:
        return None

    return Request(
        url=NVD_API_BASE_URL,
        params={"resultsPerPage": rpp, "startIndex": next_index},
        headers=dict(headers),
        callback="parse",
    )


def _is_matching_lang(d: Dict[str, Any], lang_filter: Optional[str]) -> bool:
    if not lang_filter:
        return True
    lang = d.get("lang")
    return bool(lang and str(lang).lower() == lang_filter)


def _match_desc(d: Any, lang_filter: Optional[str]) -> Optional[str]:
    if not isinstance(d, dict):
        return None
    if not _is_matching_lang(d, lang_filter):
        return None
    val = d.get("value")
    return str(val).strip() if val else None


def _first_valid_desc(
    descriptions: List[Any], lang_filter: Optional[str] = None
) -> str:
    for d in descriptions:
        val = _match_desc(d, lang_filter)
        if val is not None:
            return val
    return ""


def _extract_nvd_description(cve: Dict[str, Any]) -> str:
    """Extracts English description from CVE record with fallbacks."""
    descriptions = cve.get("descriptions", [])
    if not isinstance(descriptions, list):
        return ""
    en_desc = _first_valid_desc(descriptions, lang_filter="en")
    return en_desc if en_desc else _first_valid_desc(descriptions)


def _extract_cvss_score(cvss_data: Dict[str, Any]) -> Optional[float]:
    raw_score = cvss_data.get("baseScore")
    if raw_score is None:
        return None
    try:
        return float(raw_score)
    except (ValueError, TypeError):
        return None


def _extract_cvss_severity(cvss_data: Dict[str, Any], metric: Dict[str, Any]) -> str:
    raw_sev = cvss_data.get("baseSeverity")
    if not raw_sev:
        raw_sev = metric.get("baseSeverity")
    return str(raw_sev or "").upper()


def _parse_cvss_metric(metric: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Extracts CVSS base score, severity, and vector from metric record."""
    cvss_data = metric.get("cvssData")
    if not isinstance(cvss_data, dict):
        return None
    score = _extract_cvss_score(cvss_data)
    if score is None:
        return None
    sev = _extract_cvss_severity(cvss_data, metric)
    vec = str(cvss_data.get("vectorString") or "")
    return {"base_score": score, "severity": sev, "vector_string": vec}


def _extract_metric_list(mlist: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(mlist, list):
        return None
    for m in mlist:
        if isinstance(m, dict):
            res = _parse_cvss_metric(m)
            if res is not None:
                return res
    return None


def _extract_nvd_cvss(cve: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Extracts CVSS metrics checking v3.1, v3.0, and v2.0 in order."""
    metrics = cve.get("metrics")
    if not isinstance(metrics, dict):
        return None
    for key in ("cvssMetricV31", "cvssMetricV30", "cvssMetricV2"):
        res = _extract_metric_list(metrics.get(key))
        if res is not None:
            return res
    return None


def _extract_cwe_from_desc(desc: Any) -> Optional[str]:
    if isinstance(desc, dict):
        val = str(desc.get("value") or "").strip()
        if val.upper().startswith("CWE-"):
            return val
    return None


def _collect_desc_cwes(w: Any, cwes: List[str]) -> None:
    if not isinstance(w, dict):
        return
    for desc in w.get("description", []):
        val = _extract_cwe_from_desc(desc)
        if val and val not in cwes:
            cwes.append(val)


def _extract_nvd_cwes(cve: Dict[str, Any]) -> List[str]:
    """Extracts unique CWE IDs from weaknesses list."""
    cwes: List[str] = []
    weaknesses = cve.get("weaknesses", [])
    if not isinstance(weaknesses, list):
        return cwes
    for w in weaknesses:
        _collect_desc_cwes(w, cwes)
    return cwes


def _clean_cpe_part(part: str) -> Optional[str]:
    s = part.strip()
    return s if s not in ("*", "-", "") else None


def _parse_cpe_criteria(criteria: str) -> Tuple[Optional[str], Optional[str]]:
    """Parses vendor and product from CPE 2.3 criteria string."""
    parts = criteria.split(":")
    if len(parts) >= 5 and parts[0] == "cpe" and parts[1] == "2.3":
        return _clean_cpe_part(parts[3]), _clean_cpe_part(parts[4])
    return None, None


def _collect_match_cpes(match: Any, vendors: Set[str], products: Set[str]) -> None:
    if isinstance(match, dict):
        crit = str(match.get("criteria") or "")
        v, p = _parse_cpe_criteria(crit)
        if v:
            vendors.add(v)
        if p:
            products.add(p)


def _collect_node_cpes(node: Any, vendors: Set[str], products: Set[str]) -> None:
    if not isinstance(node, dict):
        return
    for match in node.get("cpeMatch", []):
        _collect_match_cpes(match, vendors, products)


def _extract_cpe_vendors_products(
    cve: Dict[str, Any],
) -> Tuple[List[str], List[str]]:
    """Extracts affected vendors and products from configurations CPE matches."""
    vendors: Set[str] = set()
    products: Set[str] = set()
    for config in cve.get("configurations", []):
        if isinstance(config, dict):
            for node in config.get("nodes", []):
                _collect_node_cpes(node, vendors, products)
    return sorted(list(vendors)), sorted(list(products))


def _extract_url_ref(r: Any) -> Optional[str]:
    if isinstance(r, dict):
        url = str(r.get("url") or "").strip()
        return url if url.startswith("http") else None
    return None


def _extract_nvd_references(cve: Dict[str, Any]) -> List[str]:
    """Extracts valid reference URLs from CVE record."""
    refs: List[str] = []
    raw_refs = cve.get("references", [])
    if not isinstance(raw_refs, list):
        return refs
    for r in raw_refs:
        url = _extract_url_ref(r)
        if url and url not in refs:
            refs.append(url)
    return refs


def _map_nvd_cve_item(cve: Dict[str, Any]) -> Optional[ScrapedItem]:
    """Maps a raw NVD CVE record into a normalized ScrapedItem."""
    cve_id = str(cve.get("id") or "").strip().upper()
    if not cve_id:
        return None

    desc = _extract_nvd_description(cve)
    cvss = _extract_nvd_cvss(cve)
    cwes = _extract_nvd_cwes(cve)
    vendors, products = _extract_cpe_vendors_products(cve)
    refs = _extract_nvd_references(cve)
    pub_date = str(cve.get("published") or "")[:10]
    title = f"[{cve_id}] Vulnerability"

    payload: Dict[str, Any] = {
        "type": "vulnerability",
        "source": "nvd-cve",
        "cve_id": cve_id,
        "clean_id": cve_id,
        "title": title,
        "abstract": desc,
        "description": desc,
        "overview": desc,
        "published_date": pub_date,
        "cvss": cvss,
        "cwe": cwes,
        "affected_vendors": vendors,
        "affected_products": products,
        "references": refs,
        "tags": ["vulnerability", "nvd-cve", "cve"],
    }

    return ScrapedItem(
        item_id=f"nvd_cve_{cve_id}",
        source_url=f"https://nvd.nist.gov/vuln/detail/{cve_id}",
        title=title,
        payload=payload,
    )
