"""Pure Python SPA Content Extractor without Headless Browsers."""

from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional


def _safe_json_loads(text: str) -> Optional[Any]:
    try:
        return json.loads(text)
    except Exception:
        return None


def _extract_single_pattern(pattern: str, html: str) -> Optional[Any]:
    m = re.search(pattern, html, re.DOTALL)
    return _safe_json_loads(m.group(1)) if m else None


def _extract_jsonld_list(html: str) -> List[Any]:
    matches = re.findall(
        r'<script type="application/ld\+json"[^>]*>(.*?)</script>', html, re.DOTALL
    )
    items = [_safe_json_loads(ld) for ld in matches]
    return [item for item in items if item is not None]


def _collect_api_endpoints(pattern: str, html: str, base_url: str) -> List[str]:
    found = re.findall(pattern, html)
    results: List[str] = []
    for ep in found:
        if base_url and ep.startswith("/"):
            results.append(base_url.rstrip("/") + ep)
        else:
            results.append(ep)
    return results


class SpaContentExtractor:
    """Zero-browser SPA parser extracting Hydration State JSON and sniffing API endpoints."""

    @staticmethod
    def extract_hydration_state(html: str) -> Dict[str, Any]:
        """Extracts JSON data from Next.js, Nuxt, Redux, or JSON-LD embedded tags."""
        result: Dict[str, Any] = {}

        patterns = {
            "next_data": r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
            "nuxt_data": r'<script id="__NUXT_DATA__"[^>]*>(.*?)</script>',
            "initial_state": r"window\.__INITIAL_STATE__\s*=\s*(\{.*?\});",
        }
        for key, pat in patterns.items():
            val = _extract_single_pattern(pat, html)
            if val is not None:
                result[key] = val

        jsonld = _extract_jsonld_list(html)
        if jsonld:
            result["json_ld"] = jsonld

        return result

    @staticmethod
    def sniff_api_endpoints(html: str, base_url: str = "") -> List[str]:
        """Extracts REST API endpoints referenced in client-side scripts."""
        patterns = [
            r'fetch\(["\'](/api/[^"\']+)["\']',
            r'axios\.(?:get|post)\(["\'](/api/[^"\']+)["\']',
            r'["\'](/api/v\d+/[^"\']+)["\']',
            r'["\'](/v\d+/(?:papers|articles|advisories|cve)[^"\']*)["\']',
        ]
        endpoints: List[str] = []
        for pat in patterns:
            endpoints.extend(_collect_api_endpoints(pat, html, base_url))
        return sorted(set(endpoints))
