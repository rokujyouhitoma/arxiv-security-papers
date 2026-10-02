"""Pure Python Packrat PEG YAML Frontmatter Parser Façade.

Conforms to Google OKF (Open Knowledge Format) v0.2 specification.
Provides cached parsing and resilient fallbacks with zero external dependencies.
"""

import re
import threading
from functools import lru_cache
from typing import Any, Dict, Optional

from pipeline.transformer.generated_yaml_frontmatter_parser import YAMLFrontmatterParser

_parser_lock = threading.Lock()
_global_parser: Optional[YAMLFrontmatterParser] = None


def _get_frontmatter_parser() -> YAMLFrontmatterParser:
    """Thread-safe singleton getter for YAMLFrontmatterParser."""
    global _global_parser
    if _global_parser is None:
        with _parser_lock:
            if _global_parser is None:
                _global_parser = YAMLFrontmatterParser()
    return _global_parser


def _extract_frontmatter_block(text: str) -> Optional[str]:
    """Extracts raw frontmatter block including delimiters if present."""
    trimmed = text.lstrip()
    if not trimmed.startswith("---"):
        return None
    end_idx = trimmed.find("\n---", 3)
    if end_idx == -1:
        end_idx = trimmed.find("\n...", 3)
    if end_idx == -1:
        return trimmed
    return trimmed[: end_idx + 4]


def _extract_regex_tags(raw_block: str) -> list[str]:
    """Helper to extract tags from malformed YAML block."""
    tags_m = re.search(r'tags:\s*\n((?:\s*-\s*["\']?[^\r\n]+["\']?\s*\n)+)', raw_block)
    if not tags_m:
        return []
    raw_tags = tags_m.group(1).strip().split("\n")
    return [re.sub(r'^\s*-\s*["\']?|["\']?\s*$', "", t) for t in raw_tags if t.strip()]


def _fallback_regex_frontmatter(raw_block: str) -> Dict[str, Any]:
    """Fallback extractor using regex when PEG parser encounters unexpected syntax."""
    res: Dict[str, Any] = {}
    patterns = {
        "type": r'type:\s*["\']?([^"\'\r\n]+)["\']?',
        "title": r'title:\s*["\'](.*?)["\']\s*$',
        "title_ja": r'title_ja:\s*["\'](.*?)["\']\s*$',
        "description": r'description:\s*["\'](.*?)["\']\s*$',
        "resource": r'resource:\s*["\']?([^"\'\r\n]+)["\']?',
        "timestamp": r'timestamp:\s*["\']?([^"\'\r\n]+)["\']?',
    }
    for k, pat in patterns.items():
        m = re.search(pat, raw_block, re.MULTILINE)
        if m:
            res[k] = m.group(1).replace(r"\"", '"').replace(r"\'", "'")
    tags = _extract_regex_tags(raw_block)
    if tags:
        res["tags"] = tags
    return res


@lru_cache(maxsize=1024)
def _parse_cached_frontmatter(raw_block: str) -> Dict[str, Any]:
    """Internal memoized parser for raw frontmatter text blocks."""
    parser = _get_frontmatter_parser()
    try:
        parsed = parser.parse(raw_block)
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return _fallback_regex_frontmatter(raw_block)


def parse_okf_frontmatter(markdown_text: str) -> Dict[str, Any]:
    """Parses YAML frontmatter from OKF markdown text into a dictionary.

    Args:
        markdown_text: Full OKF markdown document containing --- frontmatter block.

    Returns:
        Structured dictionary of frontmatter metadata keys and values.
    """
    block = _extract_frontmatter_block(markdown_text)
    if not block:
        return {}
    return dict(_parse_cached_frontmatter(block))


def clear_frontmatter_cache() -> None:
    """Clears the internal LRU cache of parsed frontmatters."""
    _parse_cached_frontmatter.cache_clear()
