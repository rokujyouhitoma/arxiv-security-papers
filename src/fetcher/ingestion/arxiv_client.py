#!/usr/bin/env python3
"""
arXiv Client Ingestion Module
Handles XML Atom parsing, rate-limit backoff retry, arXiv API querying, and RSS fallback.
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

try:
    import defusedxml.ElementTree as _defused_ET  # type: ignore

    def _safe_fromstring(data: bytes) -> Any:
        """Parse XML safely using defusedxml to prevent XXE attacks."""
        return _defused_ET.fromstring(data)  # type: ignore[attr-defined]

except ImportError:
    import sys as _sys
    import xml.etree.ElementTree as _stdlib_ET

    _sys.stderr.write(
        "[WARN] defusedxml not installed. Falling back to stdlib xml.etree — "
        "ensure input XML is from trusted arXiv sources only.\n"
    )

    def _safe_fromstring(data: bytes) -> Any:  # type: ignore[misc]
        """Fallback XML parser (stdlib). XXE risk mitigated by trusted arXiv origin only."""
        return _stdlib_ET.fromstring(data)

    # Alias for namespace-aware find operations
    import xml.etree.ElementTree as ET

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional


def load_config() -> Dict[str, Any]:
    """Loads configuration dictionary from config.json."""
    possible_paths = [
        os.path.join(os.path.dirname(__file__), "..", "..", "config.json"),
        os.path.join(os.path.dirname(__file__), "..", "config.json"),
        os.path.abspath("config.json"),
    ]
    for path in possible_paths:
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                res = json.load(f)
                return res if isinstance(res, dict) else {}
    return {}


def clean_text(text: Optional[str]) -> str:
    """Removes extra whitespaces and newlines from raw string."""
    if not text:
        return ""
    return re.sub(r"\s+", " ", text).strip()


def parse_arxiv_entry(entry: ET.Element) -> Dict[str, Any]:
    """Parses a single Atom entry XML element into a structured dictionary."""
    namespaces = {
        "atom": "http://www.w3.org/2005/Atom",
        "arxiv": "http://arxiv.org/schemas/atom",
    }

    raw_id_elem = entry.find("atom:id", namespaces)
    raw_id = raw_id_elem.text if raw_id_elem is not None and raw_id_elem.text else ""
    arxiv_id_match = re.search(r"abs/([^/]+)$", raw_id)
    arxiv_id = arxiv_id_match.group(1) if arxiv_id_match else raw_id.split("/")[-1]
    clean_id = re.sub(r"v\d+$", "", arxiv_id)

    title_elem = entry.find("atom:title", namespaces)
    title = clean_text(title_elem.text if title_elem is not None else "")

    summary_elem = entry.find("atom:summary", namespaces)
    summary = clean_text(summary_elem.text if summary_elem is not None else "")

    pub_elem = entry.find("atom:published", namespaces)
    published = pub_elem.text.strip() if pub_elem is not None and pub_elem.text else ""

    upd_elem = entry.find("atom:updated", namespaces)
    updated = upd_elem.text.strip() if upd_elem is not None and upd_elem.text else ""

    authors: List[str] = []
    for author_elem in entry.findall("atom:author", namespaces):
        name_elem = author_elem.find("atom:name", namespaces)
        if name_elem is not None and name_elem.text:
            authors.append(name_elem.text.strip())

    abs_url = f"https://arxiv.org/abs/{arxiv_id}"
    pdf_url = f"https://arxiv.org/pdf/{arxiv_id}.pdf"

    categories: List[str] = []
    for cat_elem in entry.findall("atom:category", namespaces):
        term = cat_elem.attrib.get("term")
        if term:
            categories.append(term)

    primary_cat_elem = entry.find("arxiv:primary_category", namespaces)
    primary_category = (
        primary_cat_elem.attrib.get("term")
        if primary_cat_elem is not None
        else (categories[0] if categories else "cs.CR")
    )

    return {
        "arxiv_id": arxiv_id,
        "clean_id": clean_id,
        "title": title,
        "summary": summary,
        "published": published,
        "updated": updated,
        "authors": authors,
        "abs_url": abs_url,
        "pdf_url": pdf_url,
        "primary_category": primary_category,
        "categories": categories,
        "fetched_at": datetime.now(timezone.utc).isoformat(),
    }


def fetch_arxiv_papers(
    query: str = "cat:cs.CR", max_results: int = 3500
) -> List[Dict[str, Any]]:
    """Fetches papers from arXiv API with exponential backoff retry and chunking."""
    all_papers: List[Dict[str, Any]] = []
    chunk_size = 500
    start = 0

    while start < max_results:
        fetch_count = min(chunk_size, max_results - start)
        encoded_query = urllib.parse.quote(query)
        api_url = (
            f"https://export.arxiv.org/api/query?search_query={encoded_query}"
            f"&sortBy=submittedDate&sortOrder=descending&start={start}&max_results={fetch_count}"
        )
        req = urllib.request.Request(
            api_url,
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ArXivSecurityOKFBot/1.0"
            },
        )

        success = False
        for retry in range(4):
            try:
                with urllib.request.urlopen(req, timeout=30) as response:
                    xml_data = response.read()
                    root = _safe_fromstring(xml_data)
                    namespaces = {"atom": "http://www.w3.org/2005/Atom"}
                    entries = root.findall("atom:entry", namespaces)
                    if not entries:
                        success = True
                        break
                    chunk_papers = [parse_arxiv_entry(e) for e in entries]
                    all_papers.extend(chunk_papers)
                    start += len(chunk_papers)
                    success = True
                    if len(chunk_papers) < fetch_count:
                        return all_papers
                    break
            except urllib.error.HTTPError as he:
                if he.code in (429, 503) and retry < 3:
                    wait_time = (2**retry) * 4
                    print(
                        f"[INFO] arXiv API returned HTTP {he.code}. Retrying in {wait_time}s (attempt {retry+1}/3)...",
                        file=sys.stderr,
                    )
                    time.sleep(wait_time)
                    continue
                else:
                    print(
                        f"[WARN] API fetch failed at start={start} ({he}), breaking...",
                        file=sys.stderr,
                    )
                    break
            except Exception as e:
                print(
                    f"[WARN] API fetch failed at start={start} ({e}), breaking...",
                    file=sys.stderr,
                )
                break

        if not success:
            break

    return all_papers


def fetch_arxiv_rss_fallback(max_results: int = 50) -> List[Dict[str, Any]]:
    """Fallback fetcher using arXiv RSS feed."""
    rss_url = "https://rss.arxiv.org/rss/cs.CR"
    req = urllib.request.Request(
        rss_url,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ArXivSecurityOKFBot/1.0"
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = resp.read()
            root = _safe_fromstring(data)
            items = root.findall(".//item")
            papers = []
            for item in items[:max_results]:
                t_node = item.find("title")
                title = clean_text(
                    t_node.text if t_node is not None and t_node.text else ""
                )
                l_node = item.find("link")
                link = l_node.text if l_node is not None and l_node.text else ""
                d_node = item.find("description")
                description = clean_text(
                    d_node.text if d_node is not None and d_node.text else ""
                )
                arxiv_id_match = re.search(r"abs/([^/]+)$", link)
                arxiv_id = arxiv_id_match.group(1) if arxiv_id_match else "unknown"
                clean_id = re.sub(r"v\d+$", "", arxiv_id)
                papers.append(
                    {
                        "arxiv_id": arxiv_id,
                        "clean_id": clean_id,
                        "title": title,
                        "summary": description,
                        "published": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                        "authors": ["arXiv Security Researcher"],
                        "abs_url": link or f"https://arxiv.org/abs/{arxiv_id}",
                        "pdf_url": f"https://arxiv.org/pdf/{arxiv_id}.pdf",
                        "primary_category": "cs.CR",
                        "categories": ["cs.CR"],
                        "fetched_at": datetime.now(timezone.utc).isoformat(),
                    }
                )
            return papers
    except Exception as e:
        print(f"[WARN] RSS Fallback failed: {e}", file=sys.stderr)
        return []
