#!/usr/bin/env python3
"""
Built-in SQL Functions Registry & Implementations for Pure Python SQL Engine.
Supports SQLite standard core functions, math, string, control, date/time, and JSON functions.
"""

import json
import math
import random
import re
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional


def sql_length(val: Any) -> Optional[int]:
    """Returns character count of string representation."""
    if val is None:
        return None
    return len(str(val))


def sql_lower(val: Any) -> Optional[str]:
    """Converts string to lowercase."""
    if val is None:
        return None
    return str(val).lower()


def sql_upper(val: Any) -> Optional[str]:
    """Converts string to uppercase."""
    if val is None:
        return None
    return str(val).upper()


def _resolve_substr_start(st: int, s_len: int) -> int:
    """Calculates 0-indexed slice start for SQLite 1-indexed substr."""
    if st > 0:
        return st - 1
    if st < 0:
        return max(0, s_len + st)
    return 0


def _slice_with_len(s: str, py_start: int, length: Optional[Any]) -> str:
    if length is None:
        return s[py_start:]
    try:
        l_val = int(length)
    except (ValueError, TypeError):
        return s[py_start:]
    if l_val < 0:
        return s[max(0, py_start + l_val) : py_start]
    return s[py_start : py_start + l_val]


def sql_substr(text: Any, start: Any, length: Optional[Any] = None) -> Optional[str]:
    """Returns substring using 1-indexed SQLite substr conventions."""
    if text is None or start is None:
        return None
    try:
        st = int(start)
    except (ValueError, TypeError):
        return None
    s = str(text)
    py_start = _resolve_substr_start(st, len(s))
    return _slice_with_len(s, py_start, length)


def sql_trim(text: Any, chars: Optional[Any] = None) -> Optional[str]:
    """Strips whitespace or specific characters from both ends."""
    if text is None:
        return None
    return str(text).strip(str(chars) if chars is not None else None)


def sql_ltrim(text: Any, chars: Optional[Any] = None) -> Optional[str]:
    """Strips whitespace or specific characters from left end."""
    if text is None:
        return None
    return str(text).lstrip(str(chars) if chars is not None else None)


def sql_rtrim(text: Any, chars: Optional[Any] = None) -> Optional[str]:
    """Strips whitespace or specific characters from right end."""
    if text is None:
        return None
    return str(text).rstrip(str(chars) if chars is not None else None)


def sql_replace(text: Any, pattern: Any, replacement: Any) -> Optional[str]:
    """Replaces all occurrences of pattern in text."""
    if text is None or pattern is None or replacement is None:
        return None
    return str(text).replace(str(pattern), str(replacement))


def sql_instr(text: Any, substr: Any) -> Optional[int]:
    """Finds 1-indexed position of substr in text, 0 if not found."""
    if text is None or substr is None:
        return None
    pos = str(text).find(str(substr))
    return pos + 1 if pos >= 0 else 0


def sql_abs(val: Any) -> Optional[float]:
    """Returns absolute value."""
    if val is None:
        return None
    try:
        v = abs(float(val))
        return int(v) if v.is_integer() else v
    except (ValueError, TypeError):
        return None


def _format_round_result(res: float, d: int) -> float:
    return int(res) if d == 0 and res.is_integer() else res


def sql_round(val: Any, digits: Optional[Any] = 0) -> Optional[float]:
    """Rounds number to specified digits."""
    if val is None:
        return None
    try:
        v = float(val)
        d = int(digits) if digits is not None else 0
        return _format_round_result(round(v, d), d)
    except (ValueError, TypeError):
        return None


def sql_ceil(val: Any) -> Optional[int]:
    """Returns ceiling integer."""
    if val is None:
        return None
    try:
        return math.ceil(float(val))
    except (ValueError, TypeError):
        return None


def sql_floor(val: Any) -> Optional[int]:
    """Returns floor integer."""
    if val is None:
        return None
    try:
        return math.floor(float(val))
    except (ValueError, TypeError):
        return None


def sql_power(base: Any, exp: Any) -> Optional[float]:
    """Returns base raised to power exp."""
    if base is None or exp is None:
        return None
    try:
        res = math.pow(float(base), float(exp))
        return int(res) if res.is_integer() else res
    except (ValueError, TypeError, OverflowError):
        return None


def sql_sqrt(val: Any) -> Optional[float]:
    """Returns square root."""
    if val is None:
        return None
    try:
        v = float(val)
        if v < 0:
            return None
        res = math.sqrt(v)
        return int(res) if res.is_integer() else res
    except (ValueError, TypeError):
        return None


def sql_sign(val: Any) -> Optional[int]:
    """Returns sign of number: -1, 0, or 1."""
    if val is None:
        return None
    try:
        v = float(val)
        if v > 0:
            return 1
        if v < 0:
            return -1
        return 0
    except (ValueError, TypeError):
        return None


def sql_random() -> int:
    """Returns 64-bit random integer."""
    return random.randint(-9223372036854775808, 9223372036854775807)


def sql_coalesce(*args: Any) -> Any:
    """Returns first non-null argument."""
    for a in args:
        if a is not None:
            return a
    return None


def sql_nullif(x: Any, y: Any) -> Any:
    """Returns NULL if x equals y, otherwise x."""
    if x == y:
        return None
    return x


def sql_ifnull(x: Any, y: Any) -> Any:
    """Returns y if x is NULL, otherwise x."""
    return y if x is None else x


def sql_iif(cond: Any, true_val: Any, false_val: Any) -> Any:
    """Evaluates conditional expression."""
    if cond and cond != "0" and cond != 0 and cond is not False:
        return true_val
    return false_val


def _match_scalar_typeof(val: Any) -> Optional[str]:
    if val is None:
        return "null"
    if isinstance(val, bool) or isinstance(val, int):
        return "integer"
    return None


def sql_typeof(val: Any) -> str:
    """Returns SQLite type name string."""
    scalar = _match_scalar_typeof(val)
    if scalar:
        return scalar
    if isinstance(val, float):
        return "real"
    if isinstance(val, bytes):
        return "blob"
    return "text"


def _parse_time_value(timestr: Any) -> Optional[datetime]:
    """Parses date/time literal string or 'now'."""
    if timestr is None or str(timestr).lower() == "now":
        return datetime.now(timezone.utc)
    s = str(timestr).strip()
    for fmt in (
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d",
        "%H:%M:%S",
    ):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return None


def sql_date(timestr: Any = "now", *modifiers: str) -> Optional[str]:
    """Formats date as YYYY-MM-DD."""
    dt = _parse_time_value(timestr)
    return dt.strftime("%Y-%m-%d") if dt else None


def sql_time(timestr: Any = "now", *modifiers: str) -> Optional[str]:
    """Formats time as HH:MM:SS."""
    dt = _parse_time_value(timestr)
    return dt.strftime("%H:%M:%S") if dt else None


def sql_datetime(timestr: Any = "now", *modifiers: str) -> Optional[str]:
    """Formats datetime as YYYY-MM-DD HH:MM:SS."""
    dt = _parse_time_value(timestr)
    return dt.strftime("%Y-%m-%d %H:%M:%S") if dt else None


def sql_strftime(fmt: Any, timestr: Any = "now", *modifiers: str) -> Optional[str]:
    """Formats datetime using strftime specifier."""
    dt = _parse_time_value(timestr)
    if not dt or fmt is None:
        return None
    return dt.strftime(str(fmt))


def sql_unixepoch(timestr: Any = "now", *modifiers: str) -> Optional[int]:
    """Returns unix epoch timestamp in seconds."""
    dt = _parse_time_value(timestr)
    return int(dt.timestamp()) if dt else None


def _extract_json_path_step(curr: Any, tok: str) -> Any:
    """Traverses a single step in JSON path."""
    if isinstance(curr, dict):
        return curr.get(tok)
    if isinstance(curr, list):
        try:
            return curr[int(tok)]
        except (ValueError, IndexError):
            return None
    return None


def _traverse_json_tokens(data: Any, tokens: Any) -> Any:
    curr = data
    for tok in tokens:
        curr = _extract_json_path_step(curr, tok)
        if curr is None:
            return None
    return curr


def _parse_json_input(json_val: Any) -> Any:
    if isinstance(json_val, str):
        try:
            return json.loads(json_val)
        except Exception:
            return None
    return json_val


def _extract_path_tokens(path: Any) -> List[str]:
    p = str(path).strip().lstrip("$")
    return [t for t in re.split(r"\.|\[|\]", p) if t]


def sql_json_extract(json_val: Any, path: Any) -> Any:
    """Extracts value from JSON object by JSONPath."""
    if json_val is None or path is None:
        return None
    data = _parse_json_input(json_val)
    if data is None:
        return None
    return _traverse_json_tokens(data, _extract_path_tokens(path))


def sql_json_array(*args: Any) -> str:
    """Constructs JSON array from arguments."""
    return json.dumps(list(args))


def sql_json_object(*args: Any) -> Optional[str]:
    """Constructs JSON object from key-value pairs."""
    if len(args) % 2 != 0:
        return None
    d: Dict[str, Any] = {}
    for idx in range(0, len(args), 2):
        d[str(args[idx])] = args[idx + 1]
    return json.dumps(d)


def sql_json_valid(val: Any) -> int:
    """Returns 1 if valid JSON string, 0 otherwise."""
    if val is None:
        return 0
    try:
        json.loads(str(val))
        return 1
    except Exception:
        return 0


BUILTIN_FUNCTIONS: Dict[str, Callable[..., Any]] = {
    # String
    "LENGTH": sql_length,
    "LOWER": sql_lower,
    "UPPER": sql_upper,
    "SUBSTR": sql_substr,
    "SUBSTRING": sql_substr,
    "TRIM": sql_trim,
    "LTRIM": sql_ltrim,
    "RTRIM": sql_rtrim,
    "REPLACE": sql_replace,
    "INSTR": sql_instr,
    # Math
    "ABS": sql_abs,
    "ROUND": sql_round,
    "CEIL": sql_ceil,
    "CEILING": sql_ceil,
    "FLOOR": sql_floor,
    "POWER": sql_power,
    "SQRT": sql_sqrt,
    "SIGN": sql_sign,
    "RANDOM": sql_random,
    # Control
    "COALESCE": sql_coalesce,
    "NULLIF": sql_nullif,
    "IFNULL": sql_ifnull,
    "IIF": sql_iif,
    "TYPEOF": sql_typeof,
    # Date & Time
    "DATE": sql_date,
    "TIME": sql_time,
    "DATETIME": sql_datetime,
    "STRFTIME": sql_strftime,
    "UNIXEPOCH": sql_unixepoch,
    # JSON
    "JSON_EXTRACT": sql_json_extract,
    "JSON_ARRAY": sql_json_array,
    "JSON_OBJECT": sql_json_object,
    "JSON_VALID": sql_json_valid,
}
