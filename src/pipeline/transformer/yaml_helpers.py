"""Helper functions for Pure PEG YAML Frontmatter parsing."""

import json
from typing import Any, Dict, List, Tuple, Union


def _unescape_double_quotes(raw: str) -> str:
    """Unescapes a double-quoted YAML string safely using JSON semantics."""
    try:
        return str(json.loads(raw))
    except Exception:
        return raw[1:-1].replace(r"\"", '"').replace(r"\\", "\\")


def _unescape_single_quotes(raw: str) -> str:
    """Unescapes a single-quoted YAML string."""
    return raw[1:-1].replace("''", "'")


def _parse_bool_or_none(s: str) -> Tuple[bool, Any]:
    """Parses boolean or null literal."""
    low = s.lower()
    if low in ("true", "yes", "on"):
        return True, True
    if low in ("false", "no", "off"):
        return True, False
    if low in ("null", "~", ""):
        return True, None
    return False, None


def _parse_number(s: str) -> Tuple[bool, Union[int, float]]:
    """Attempts to parse string as integer or float."""
    try:
        if "." in s or "e" in s.lower():
            return True, float(s)
        return True, int(s)
    except ValueError:
        return False, 0


def _parse_scalar(val: str) -> Any:
    """Converts a raw YAML scalar string into a typed Python object."""
    stripped = val.strip()
    is_bool_or_none, parsed_bn = _parse_bool_or_none(stripped)
    if is_bool_or_none:
        return parsed_bn
    is_num, parsed_num = _parse_number(stripped)
    if is_num:
        return parsed_num
    return stripped


def _make_kv_pair(key: str, val: Any) -> Tuple[str, Any]:
    """Constructs a key-value tuple."""
    return key.strip(), val


def _build_frontmatter_dict(items: List[Any]) -> Dict[str, Any]:
    """Builds a structured dictionary from evaluated frontmatter AST items."""
    result: Dict[str, Any] = {}
    for item in items:
        if isinstance(item, tuple) and len(item) == 2:
            k, v = item
            result[k] = v
        elif isinstance(item, dict):
            result.update(item)
    return result
