"""Pure Python SPA Content Extractor without Headless Browsers."""

from __future__ import annotations

import json
import re
from typing import Any, Dict, List


class SpaContentExtractor:
    """Zero-browser SPA parser extracting Hydration State JSON and sniffing API endpoints."""

    @staticmethod
    def extract_hydration_state(html: str) -> Dict[str, Any]:
        """Extracts JSON data from Next.js, Nuxt, Redux, or JSON-LD embedded tags."""
        result: Dict[str, Any] = {}

        # 1. Next.js (__NEXT_DATA__)
        next_match = re.search(
            r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.DOTALL
        )
        if next_match:
            try:
                result["next_data"] = json.loads(next_match.group(1))
            except Exception:
                pass

        # 2. Nuxt.js (__NUXT_DATA__ or window.__NUXT__)
        nuxt_match = re.search(
            r'<script id="__NUXT_DATA__"[^>]*>(.*?)</script>', html, re.DOTALL
        )
        if nuxt_match:
            try:
                result["nuxt_data"] = json.loads(nuxt_match.group(1))
            except Exception:
                pass

        # 3. Redux / Global State (window.__INITIAL_STATE__ = {...})
        redux_match = re.search(
            r"window\.__INITIAL_STATE__\s*=\s*(\{.*?\});", html, re.DOTALL
        )
        if redux_match:
            try:
                result["initial_state"] = json.loads(redux_match.group(1))
            except Exception:
                pass

        # 4. JSON-LD (Schema.org)
        jsonld_matches = re.findall(
            r'<script type="application/ld\+json"[^>]*>(.*?)</script>', html, re.DOTALL
        )
        jsonld_list = []
        for ld in jsonld_matches:
            try:
                jsonld_list.append(json.loads(ld))
            except Exception:
                pass
        if jsonld_list:
            result["json_ld"] = jsonld_list

        return result

    @staticmethod
    def sniff_api_endpoints(html: str, base_url: str = "") -> List[str]:
        """Extracts REST API endpoints referenced in client-side scripts."""
        endpoints: List[str] = []
        patterns = [
            r'fetch\(["\'](/api/[^"\']+)["\']',
            r'axios\.(?:get|post)\(["\'](/api/[^"\']+)["\']',
            r'["\'](/api/v\d+/[^"\']+)["\']',
            r'["\'](/v\d+/(?:papers|articles|advisories|cve)[^"\']*)["\']',
        ]
        for pat in patterns:
            found = re.findall(pat, html)
            for ep in found:
                if base_url and ep.startswith("/"):
                    full = base_url.rstrip("/") + ep
                    endpoints.append(full)
                else:
                    endpoints.append(ep)

        return sorted(list(set(endpoints)))
