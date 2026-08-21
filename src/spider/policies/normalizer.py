"""URL Normalizer and Crawler Trap Detector."""

from __future__ import annotations

import posixpath
import re
import urllib.parse
from typing import List, Set


class UrlNormalizer:
    """7-step syntactic and semantic URL normalization pipeline."""

    TRACKING_PARAMS: Set[str] = {
        "utm_source",
        "utm_medium",
        "utm_campaign",
        "utm_term",
        "utm_content",
        "fbclid",
        "gclid",
        "sessionid",
        "sid",
        "ref",
        "spm",
    }

    @classmethod
    def normalize(cls, url: str) -> str:
        """Normalizes URL to standard canonical representation."""
        parsed = urllib.parse.urlsplit(url.strip())
        scheme, netloc = _normalize_scheme_and_netloc(parsed.scheme, parsed.netloc)
        clean_path = _normalize_path(parsed.path)
        clean_query = _filter_and_sort_query(parsed.query, cls.TRACKING_PARAMS)
        return urllib.parse.urlunsplit((scheme, netloc, clean_path, clean_query, ""))


def _normalize_scheme_and_netloc(scheme: str, netloc: str) -> tuple[str, str]:
    clean_scheme = scheme.lower()
    clean_netloc = netloc.lower()
    if clean_scheme == "http" and clean_netloc.endswith(":80"):
        clean_netloc = clean_netloc[:-3]
    elif clean_scheme == "https" and clean_netloc.endswith(":443"):
        clean_netloc = clean_netloc[:-4]
    return clean_scheme, clean_netloc


def _normalize_path(path: str) -> str:
    if not path:
        return "/"
    clean_path = posixpath.normpath(path)
    if path.endswith("/") and not clean_path.endswith("/"):
        clean_path += "/"
    return clean_path


def _filter_and_sort_query(query: str, tracking_params: Set[str]) -> str:
    if not query:
        return ""
    params = urllib.parse.parse_qsl(query, keep_blank_values=True)
    filtered = [(k, v) for k, v in params if k.lower() not in tracking_params]
    filtered.sort(key=lambda item: item[0])
    return urllib.parse.urlencode(filtered)


class TrapDetector:
    """Detects repeating directory cycles, excessive path depth, and query explosion."""

    def __init__(self, max_depth: int = 8, max_params: int = 6) -> None:
        self.max_depth: int = max_depth
        self.max_params: int = max_params

    def is_trap(self, url: str) -> bool:
        """Returns True if the URL is identified as a crawler trap."""
        parsed = urllib.parse.urlsplit(url)
        segments = [s for s in parsed.path.split("/") if s]

        # 1. Depth check
        if len(segments) > self.max_depth:
            return True

        # 2. Cycle detection (repeating directory segments e.g. /a/b/a/b/)
        if _has_repeating_segments(segments):
            return True

        # 3. Query explosion check
        params = urllib.parse.parse_qsl(parsed.query)
        if len(params) > self.max_params:
            return True

        # 4. Sensitive auth/admin path check
        if _is_sensitive_path(parsed.path):
            return True

        return False


def _has_repeating_segments(segments: List[str]) -> bool:
    if len(segments) < 4:
        return False
    counts: dict[str, int] = {}
    for s in segments:
        counts[s] = counts.get(s, 0) + 1
        if counts[s] >= 3:
            return True
    return False


def _is_sensitive_path(path: str) -> bool:
    sensitive_pattern = (
        r"/(?:login|signin|signup|register|auth|admin|checkout|payment|password|reset)"
    )
    return bool(re.search(sensitive_pattern, path.lower()))
