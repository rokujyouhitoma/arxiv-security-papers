#!/usr/bin/env python3
"""MITRE CWE (Common Weakness Enumeration) Catalog Spider.

Pure-Python, zero external dependencies.
Adheres to MITRE terms with 5.0s politeness delay and HTTP 304 cache integration.
"""

from __future__ import annotations

from typing import Any, AsyncIterator, Dict, List, Optional, Set, Union

from spider.core.downloader import Request, Response
from spider.core.engine import ScrapedItem
from spider.spiders.base import BaseSpider


def _filter_dict_list(items: Any) -> List[Dict[str, Any]]:
    if not isinstance(items, list):
        return []
    return [v for v in items if isinstance(v, dict)]


def _extract_dict_payload(data: Dict[str, Any]) -> List[Dict[str, Any]]:
    for key in ("weaknesses", "Weaknesses", "data"):
        val = data.get(key)
        if isinstance(val, list):
            return _filter_dict_list(val)
    return []


def _extract_cwe_records(response: Response) -> List[Dict[str, Any]]:
    """Extracts raw weakness dictionaries from response."""
    try:
        data = response.json()
    except Exception:
        return []
    if isinstance(data, list):
        return _filter_dict_list(data)
    if isinstance(data, dict):
        return _extract_dict_payload(data)
    return []


def _normalize_cwe_id(raw_val: Any) -> str:
    """Normalizes raw ID or integer into standard 'CWE-XXX' format."""
    s = str(raw_val or "").strip().upper()
    if not s:
        return ""
    if not s.startswith("CWE-"):
        return f"CWE-{s}"
    return s


def _extract_numeric_id(cwe_id: str) -> str:
    """Extracts numeric portion of CWE-ID for URL construction."""
    return cwe_id.replace("CWE-", "")


def _safe_str(d: Dict[str, Any], key: str, default: str = "") -> str:
    val = d.get(key)
    return str(val).strip() if val is not None else default


def _parse_mitigation_dict(m: Dict[str, Any]) -> Optional[Dict[str, str]]:
    desc = _safe_str(m, "description") or _safe_str(m, "text")
    if not desc:
        return None
    phase = _safe_str(m, "phase") or _safe_str(m, "Phase")
    strategy = _safe_str(m, "strategy") or _safe_str(m, "Strategy")
    return {"phase": phase, "strategy": strategy, "description": desc}


def _parse_mitigation_entry(m: Any) -> Optional[Dict[str, str]]:
    if isinstance(m, dict):
        return _parse_mitigation_dict(m)
    if isinstance(m, str) and m.strip():
        return {"phase": "", "strategy": "", "description": m.strip()}
    return None


def _extract_mitigations(record: Dict[str, Any]) -> List[Dict[str, str]]:
    """Extracts structured mitigations from weakness record."""
    raw = record.get("potential_mitigations")
    if raw is None:
        raw = record.get("mitigations")
    if not isinstance(raw, list):
        return []
    results: List[Dict[str, str]] = []
    for m in raw:
        entry = _parse_mitigation_entry(m)
        if entry is not None:
            results.append(entry)
    return results


def _extract_rel_target(r: Dict[str, Any]) -> str:
    target = r.get("cwe_id")
    if target is None:
        target = r.get("target_id")
    return _normalize_cwe_id(target)


def _extract_rel_nature(r: Dict[str, Any]) -> str:
    nature = _safe_str(r, "nature")
    if not nature:
        nature = _safe_str(r, "relation_type")
    return nature if nature else "ChildOf"


def _parse_rel_entry(r: Any) -> Optional[Dict[str, str]]:
    if not isinstance(r, dict):
        return None
    target_id = _extract_rel_target(r)
    if not target_id:
        return None
    return {"target_cwe_id": target_id, "relation_type": _extract_rel_nature(r)}


def _extract_relationships(record: Dict[str, Any]) -> List[Dict[str, str]]:
    """Extracts parent/child and peer relationships from record."""
    raw = record.get("related_weaknesses")
    if raw is None:
        raw = record.get("relationships")
    if not isinstance(raw, list):
        return []
    rels: List[Dict[str, str]] = []
    for r in raw:
        parsed = _parse_rel_entry(r)
        if parsed is not None:
            rels.append(parsed)
    return rels


def _clean_str_list(items: List[Any]) -> List[str]:
    res: List[str] = []
    for x in items:
        if x:
            res.append(str(x).strip())
    return res


def _extract_attack_ids(record: Dict[str, Any]) -> List[str]:
    """Extracts related attack pattern IDs (CAPEC)."""
    raw = record.get("related_attack_patterns")
    if raw is None:
        raw = record.get("capec_ids")
    if isinstance(raw, list):
        return _clean_str_list(raw)
    return []


def _build_cwe_tags(cwe_id: str, is_top25: bool) -> List[str]:
    """Constructs security domain tags for CWE records."""
    num_id = _extract_numeric_id(cwe_id)
    tags = ["weakness", "mitre-cwe", f"cwe-{num_id}"]
    if is_top25:
        tags.append("cwe-top25")
        tags.append("critical-weakness")
    return tags


def _build_cwe_payload(
    cwe_id: str,
    name: str,
    record: Dict[str, Any],
    mitigations: List[Dict[str, str]],
    relationships: List[Dict[str, str]],
    attack_ids: List[str],
) -> Dict[str, Any]:
    """Constructs the canonical payload dictionary for ScrapedItem."""
    desc = _safe_str(record, "description")
    top25_val = record.get("top25_rank") or record.get("rank")
    top25_rank = (
        int(top25_val) if top25_val is not None and str(top25_val).isdigit() else None
    )
    is_top25 = bool(record.get("is_top25") or top25_rank is not None)
    abstraction = _safe_str(record, "abstraction", "Base")
    status = _safe_str(record, "status", "Incomplete")

    return {
        "type": "weakness",
        "source": "mitre-cwe",
        "cwe_id": cwe_id,
        "clean_id": cwe_id,
        "title": f"[{cwe_id}] {name}",
        "name": name,
        "abstract": desc,
        "description": desc,
        "abstraction": abstraction,
        "status": status,
        "top25_rank": top25_rank,
        "is_top25": is_top25,
        "mitigations": mitigations,
        "relationships": relationships,
        "related_attack_ids": attack_ids,
        "tags": _build_cwe_tags(cwe_id, is_top25),
    }


def _extract_raw_id(record: Dict[str, Any]) -> Any:
    for k in ("id", "cwe_id", "ID"):
        v = record.get(k)
        if v is not None:
            return v
    return None


def _extract_raw_name(record: Dict[str, Any]) -> str:
    name = _safe_str(record, "name")
    return name if name else _safe_str(record, "Name")


def _map_cwe_item(record: Dict[str, Any]) -> Optional[ScrapedItem]:
    """Normalizes raw CWE dictionary into ScrapedItem."""
    cwe_id = _normalize_cwe_id(_extract_raw_id(record))
    name = _extract_raw_name(record)
    if not cwe_id or not name:
        return None

    num_id = _extract_numeric_id(cwe_id)
    mitigations = _extract_mitigations(record)
    relationships = _extract_relationships(record)
    attack_ids = _extract_attack_ids(record)

    payload = _build_cwe_payload(
        cwe_id, name, record, mitigations, relationships, attack_ids
    )

    return ScrapedItem(
        item_id=f"cwe_{cwe_id.lower()}",
        source_url=f"https://cwe.mitre.org/data/definitions/{num_id}.html",
        title=payload["title"],
        payload=payload,
    )


class CweSpider(BaseSpider):
    """Spider for crawling MITRE Common Weakness Enumeration (CWE) Catalog."""

    name: str = "cwe_spider"
    download_delay: float = 5.0
    allowed_domains: Set[str] = {"cwe.mitre.org", "cwe-api.mitre.org"}
    start_urls: List[str] = ["https://cwe-api.mitre.org/api/v1/cwe/weakness"]

    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        """Parses MITRE CWE JSON feed and yields normalized ScrapedItems."""
        try:
            records = _extract_cwe_records(response)
        except Exception:
            return

        for record in records:
            item = _map_cwe_item(record)
            if item is not None:
                yield item
