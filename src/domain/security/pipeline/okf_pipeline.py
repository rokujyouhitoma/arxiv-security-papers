"""Security OKF v0.2 Item Pipeline and DSN-14 Database Persistence.

Part of the Security Intelligence domain (src/domain/security/pipeline/).
"""

from __future__ import annotations

import os
import re
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

from spider.core.engine import ScrapedItem
from spider.pipeline.base import BaseItemPipeline

_DATE_REGEX = re.compile(r"^\d{4}-\d{2}-\d{2}")


class SecurityOkfItemPipeline(BaseItemPipeline):
    """Item Pipeline for converting ScrapedItems to Google OKF v0.2 Markdown and DSN-14 DB records."""

    def __init__(
        self, output_dir: Optional[str] = None, enable_db_persistence: bool = False
    ) -> None:
        self.output_dir: str = output_dir or "outputs/okf_papers"
        self.enable_db_persistence: bool = enable_db_persistence

    async def process_item(self, item: ScrapedItem, spider: Any) -> ScrapedItem:
        """Processes scraped item, generates OKF v0.2 Markdown, and persists record."""
        payload = item.payload
        raw_clean_id = str(payload.get("clean_id") or item.item_id)
        clean_id = _sanitize_path_id(raw_clean_id)
        item.payload["clean_id"] = clean_id

        pub_date = str(payload.get("published_date") or "")
        date_folder = _extract_date_folder(pub_date)

        target_dir = os.path.join(self.output_dir, date_folder)
        os.makedirs(target_dir, exist_ok=True)
        okf_file = os.path.join(target_dir, f"{clean_id}.md")

        # Generate OKF v0.2 Markdown content (polymorphic dispatch)
        markdown_content = _build_okf_markdown(item, clean_id, date_folder)
        with open(okf_file, "w", encoding="utf-8") as f:
            f.write(markdown_content)

        item.payload["okf_path"] = okf_file

        if self.enable_db_persistence:
            _persist_to_dsn14_db(item, clean_id, okf_file)

        return item


# Backward-compatible alias
OkfItemPipeline = SecurityOkfItemPipeline


def _sanitize_string(val: Any) -> str:
    """Sanitizes text for YAML frontmatter and Markdown rendering.

    Escapes double quotes, replaces newlines with spaces, and removes control chars.
    """
    if val is None:
        return ""
    text = str(val)
    text = re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", "", text)
    text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
    text = text.replace('"', r"\"")
    return text.strip()


def _sanitize_path_id(clean_id: str) -> str:
    """Sanitizes clean_id to prevent Path Traversal (CWE-22)."""
    base = os.path.basename(str(clean_id or ""))
    sanitized = re.sub(r"[^a-zA-Z0-9_\-\.]", "_", base)
    sanitized = sanitized.strip("._-")
    return sanitized if sanitized else "UNKNOWN_ID"


def _extract_date_folder(pub_date: str) -> str:
    """Extracts YYYY-MM-DD date folder name safely with UTC fallback."""
    if pub_date and _DATE_REGEX.match(pub_date):
        return pub_date[:10]
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _truncate_desc(text: str, limit: int = 150) -> str:
    """Safely sanitizes and truncates description text."""
    sanitized = _sanitize_string(text[:limit])
    if len(text) > limit:
        return f"{sanitized}..."
    return sanitized


def _first_val(payload: Dict[str, Any], keys: Tuple[str, ...], default: str) -> str:
    """Gets the first non-empty string value from payload keys."""
    for k in keys:
        v = payload.get(k)
        if v:
            return str(v)
    return default


def _score_to_severity(score: Optional[float]) -> str:
    """Maps CVSS base score to qualitative severity rating."""
    if score is None:
        return "UNKNOWN"
    thresholds = (
        (9.0, "CRITICAL"),
        (7.0, "HIGH"),
        (4.0, "MEDIUM"),
        (0.01, "LOW"),
    )
    for limit, label in thresholds:
        if score >= limit:
            return label
    return "NONE"


def _parse_dict_cvss(cvss_dict: Dict[str, Any]) -> Tuple[Optional[float], str, str]:
    """Parses CVSS metadata from dictionary structure."""
    raw_score = cvss_dict.get("base_score")
    score: Optional[float] = None
    if raw_score is not None:
        try:
            score = float(raw_score)
        except (ValueError, TypeError):
            pass
    raw_sev = cvss_dict.get("severity")
    severity = str(raw_sev).upper() if raw_sev else _score_to_severity(score)
    vec = str(cvss_dict.get("vector_string") or "")
    return score, severity, vec


def _format_cvss_meta(cvss_val: Any) -> Tuple[Optional[float], str, str]:
    """Extracts base_score, severity, and vector_string from cvss input."""
    if isinstance(cvss_val, dict):
        return _parse_dict_cvss(cvss_val)
    if isinstance(cvss_val, (int, float)):
        score = float(cvss_val)
        return score, _score_to_severity(score), ""
    if isinstance(cvss_val, str):
        try:
            score = float(cvss_val)
            return score, _score_to_severity(score), ""
        except ValueError:
            return None, cvss_val.upper(), ""
    return None, "UNKNOWN", ""


def _clean_seq(seq: Any) -> List[str]:
    """Extracts non-empty stripped strings from a sequence."""
    items: List[str] = []
    for x in seq:
        if x:
            s = str(x).strip()
            if s:
                items.append(s)
    return items


def _normalize_string_list(val: Any) -> List[str]:
    """Converts a value to a list of non-empty strings."""
    if not val:
        return []
    if isinstance(val, (list, tuple, set)):
        return _clean_seq(val)
    cleaned = str(val).strip()
    return [cleaned] if cleaned else []


def _format_paper_authors(raw_authors: Any) -> str:
    """Formats authors list into YAML frontmatter lines."""
    authors = _normalize_string_list(raw_authors)
    if not authors:
        return '    - name: "Unknown"'
    return "\n".join([f'    - name: "{_sanitize_string(a)}"' for a in authors])


def _format_tags_yaml(raw_tags: Any, default_tag: str) -> str:
    """Formats tags into YAML frontmatter array string."""
    tags = _normalize_string_list(raw_tags) or [default_tag]
    return ", ".join([f'"{_sanitize_string(t)}"' for t in tags])


def _format_yaml_val(val: Optional[Any], is_str: bool = False) -> str:
    """Formats YAML scalar value representation."""
    if val is None:
        return "null"
    if is_str:
        return f'"{val}"' if val else "null"
    return str(val)


def _build_paper_okf_markdown(
    item: ScrapedItem, clean_id: str, date_folder: str
) -> str:
    """Builds Google OKF v0.2 Markdown document for academic security papers."""
    payload = item.payload
    abstract = str(payload.get("abstract") or "")
    title = _sanitize_string(item.title)
    desc = _truncate_desc(abstract)
    url = _sanitize_string(item.source_url)
    authors_yaml = _format_paper_authors(payload.get("authors"))
    tags_yaml = _format_tags_yaml(payload.get("tags"), "security")
    now_iso = datetime.now(timezone.utc).isoformat()
    origin = _sanitize_string(payload.get("source") or "spider")
    pub_date = _sanitize_string(payload.get("published_date") or "")
    pdf_url = str(payload.get("pdf_url") or "N/A")

    return f"""---
type: "security-paper"
title: "{title}"
description: "{desc}"
resource: "{url}"
tags: [{tags_yaml}]
timestamp: "{now_iso}"
provenance:
  origin: "{origin}"
  raw_metadata_path: "outputs/raw_data/{date_folder}/{clean_id}_meta.json"
  published_date: "{pub_date}"
  authors:
{authors_yaml}
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# {item.title}

## 概要 (Abstract)
{abstract}

## 詳細リンク (Resource)
- 原文リンク: [{item.source_url}]({item.source_url})
- PDF リンク: [{pdf_url}]({pdf_url})
"""


def _render_cvss_display(
    base_score: Optional[float], severity: str, vector_string: str
) -> str:
    """Renders CVSS display string for threat metrics table."""
    if base_score is not None and vector_string:
        return f"**{base_score} ({severity})** `{vector_string}`"
    if base_score is not None:
        return f"**{base_score} ({severity})**"
    return f"**{severity}**"


def _render_vuln_metrics_table(
    base_score: Optional[float],
    severity: str,
    vector_string: str,
    cwe_list: List[str],
    epss_score: Optional[float],
    kev_status: bool,
    due_date: str,
) -> str:
    """Renders threat metrics markdown table."""
    cvss_disp = _render_cvss_display(base_score, severity, vector_string)
    cwe_disp = ", ".join(cwe_list) if cwe_list else "N/A"
    epss_disp = f"{epss_score * 100:.1f}%" if epss_score is not None else "N/A"
    kev_disp = (
        "**悪用確認済み (Active in the Wild)**" if kev_status else "未確認 / 未登録"
    )
    due_disp = due_date if due_date else "N/A"

    return f"""| 指標 | 評価値 |
| :--- | :--- |
| **CVSS** | {cvss_disp} |
| **CWE** | {cwe_disp} |
| **EPSS 悪用予測** | {epss_disp} |
| **CISA KEV 悪用確認** | {kev_disp} |
| **対策期日 (Due Date)** | {due_disp} |"""


def _render_vuln_affected_products(
    affected_vendors: List[str], affected_products: List[str]
) -> str:
    """Renders affected vendors and products markdown list."""
    if affected_products:
        return "\n".join([f"- `{p}`" for p in affected_products])
    if affected_vendors:
        return "\n".join([f"- **{v}** 製品群" for v in affected_vendors])
    return "- 特記なし (None specified)"


def _render_vuln_references(raw_refs: List[str], fallback_url: str) -> str:
    """Renders references list markdown."""
    refs = raw_refs if raw_refs else ([fallback_url] if fallback_url else [])
    if not refs:
        return "- なし"
    return "\n".join([f"- [{r}]({r})" for r in refs])


def _extract_epss_score(payload: Dict[str, Any]) -> Optional[float]:
    """Safely extracts numeric EPSS score from payload."""
    raw_epss = payload.get("epss_score") or payload.get("epss")
    if raw_epss is None:
        return None
    try:
        return float(raw_epss)
    except (ValueError, TypeError):
        return None


def _render_vuln_frontmatter(
    item_type: str,
    title: str,
    desc: str,
    url: str,
    tags_yaml: str,
    origin: str,
    clean_id: str,
    pub_date: str,
    sec_meta: Dict[str, str],
) -> str:
    """Renders YAML frontmatter string for vulnerability OKF v0.2."""
    now_iso = datetime.now(timezone.utc).isoformat()
    return f"""---
type: "{item_type}"
title: "{title}"
description: "{desc}"
resource: "{url}"
tags: [{tags_yaml}]
timestamp: "{now_iso}"
provenance:
  origin: "{origin}"
  clean_id: "{clean_id}"
  published_date: "{pub_date}"
  source_url: "{url}"
security_metadata:
  cve_id: "{sec_meta['cve_id']}"
  cvss:
    base_score: {sec_meta['base_score']}
    severity: "{sec_meta['severity']}"
    vector_string: "{sec_meta['vector_string']}"
  cwe: [{sec_meta['cwe_yaml']}]
  epss_score: {sec_meta['epss_yaml']}
  kev_status: {sec_meta['kev_yaml']}
  due_date: {sec_meta['due_yaml']}
  affected_vendors: [{sec_meta['vendors_yaml']}]
  affected_products: [{sec_meta['products_yaml']}]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---"""


def _render_vuln_body(
    title: str,
    overview: str,
    metrics_table: str,
    affected_block: str,
    remediation: str,
    ref_block: str,
) -> str:
    """Renders Markdown body for vulnerability OKF v0.2."""
    return f"""# {title}

## 1. 脆弱性概要 (Overview)
{overview}

## 2. 脅威評価メトリクス (Threat Metrics)
{metrics_table}

## 3. 影響を受けるベンダー・製品 (Affected Products)
{affected_block}

## 4. 対策・緩和策 (Required Actions & Mitigations)
{remediation}

## 5. 参考情報・一次ソースリンク (References)
{ref_block}
"""


def _extract_sec_meta_dict(
    payload: Dict[str, Any],
    cve_id: str,
    base_score: Optional[float],
    severity: str,
    vec: str,
    cwe_list: List[str],
    epss_score: Optional[float],
    kev_status: bool,
    due_date: str,
    vendors: List[str],
    products: List[str],
) -> Dict[str, str]:
    """Builds security metadata mapping for YAML serialization."""
    return {
        "cve_id": cve_id,
        "base_score": _format_yaml_val(base_score),
        "severity": severity,
        "vector_string": vec,
        "cwe_yaml": ", ".join([f'"{_sanitize_string(c)}"' for c in cwe_list]),
        "epss_yaml": _format_yaml_val(epss_score),
        "due_yaml": _format_yaml_val(due_date, is_str=True),
        "kev_yaml": "true" if kev_status else "false",
        "vendors_yaml": ", ".join([f'"{_sanitize_string(v)}"' for v in vendors]),
        "products_yaml": ", ".join([f'"{_sanitize_string(p)}"' for p in products]),
    }


def _get_vuln_cve_and_title(item: ScrapedItem, clean_id: str) -> Tuple[str, str]:
    """Resolves sanitized CVE identifier and display title."""
    cve = _sanitize_string(item.payload.get("cve_id"))
    final_cve = cve if cve else clean_id
    title = (
        _sanitize_string(item.title) if item.title else f"[{final_cve}] Vulnerability"
    )
    return final_cve, title


def _build_vulnerability_okf_markdown(
    item: ScrapedItem, clean_id: str, date_folder: str
) -> str:
    """Builds Google OKF v0.2 Markdown document for vulnerability / CTI data."""
    payload = item.payload
    cve_id, title = _get_vuln_cve_and_title(item, clean_id)
    overview = _first_val(
        payload, ("description", "overview", "abstract"), "脆弱性に関する詳細情報。"
    )
    desc = _truncate_desc(overview)
    url = _sanitize_string(item.source_url)
    origin = _first_val(payload, ("source",), "advisory-spider")
    pub_date = _first_val(payload, ("published_date",), "")

    base_score, severity, vec = _format_cvss_meta(payload.get("cvss"))
    cwe_list = _normalize_string_list(payload.get("cwe"))
    epss_score = _extract_epss_score(payload)
    kev_status = bool(payload.get("kev_status", False))
    due_date = _first_val(payload, ("due_date",), "")
    vendors = _normalize_string_list(payload.get("affected_vendors"))
    products = _normalize_string_list(payload.get("affected_products"))

    sec_meta = _extract_sec_meta_dict(
        payload,
        cve_id,
        base_score,
        severity,
        vec,
        cwe_list,
        epss_score,
        kev_status,
        due_date,
        vendors,
        products,
    )

    remediation = _first_val(
        payload,
        ("remediation", "required_action", "mitigation"),
        "ベンダー公式セキュリティパッチまたは緩和策の適用を推奨します。",
    )
    metrics_table = _render_vuln_metrics_table(
        base_score, severity, vec, cwe_list, epss_score, kev_status, due_date
    )
    affected_block = _render_vuln_affected_products(vendors, products)
    ref_block = _render_vuln_references(
        _normalize_string_list(payload.get("references")), item.source_url
    )

    fm = _render_vuln_frontmatter(
        _first_val(payload, ("type",), "vulnerability"),
        title,
        desc,
        url,
        _format_tags_yaml(payload.get("tags"), "vulnerability"),
        origin,
        clean_id,
        pub_date,
        sec_meta,
    )
    body = _render_vuln_body(
        title, overview, metrics_table, affected_block, remediation, ref_block
    )
    return f"{fm}\n\n{body}"


def _build_okf_markdown(item: ScrapedItem, clean_id: str, date_folder: str) -> str:
    """Polymorphic dispatcher for OKF v0.2 Markdown generation."""
    item_type = str(item.payload.get("type") or "security-paper").lower()
    if item_type in ("vulnerability", "security-advisory"):
        return _build_vulnerability_okf_markdown(item, clean_id, date_folder)
    return _build_paper_okf_markdown(item, clean_id, date_folder)


def _persist_to_dsn14_db(item: ScrapedItem, clean_id: str, okf_path: str) -> None:
    """Persists record to appropriate DSN-14 DB table based on item type."""
    try:
        from database.driver import connect

        conn = connect(database="outputs/vector_db/security_papers.vdb")
        cursor = conn.cursor()
        item_type = str(item.payload.get("type") or "security-paper").lower()

        if item_type in ("vulnerability", "security-advisory"):
            cve_id = str(item.payload.get("cve_id") or clean_id)
            cvss_val = item.payload.get("cvss")
            base_score, severity, _ = _format_cvss_meta(cvss_val)
            cursor.execute(
                "INSERT OR REPLACE INTO vulnerabilities "
                "(cve_id, title, severity, cvss_score, source_url, okf_path) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (cve_id, item.title, severity, base_score, item.source_url, okf_path),
            )
        else:
            cursor.execute(
                "INSERT OR REPLACE INTO papers (clean_id, title, url, okf_path) "
                "VALUES (?, ?, ?, ?)",
                (clean_id, item.title, item.source_url, okf_path),
            )
        conn.commit()
    except Exception:
        pass
