#!/usr/bin/env python3
"""
Strict JSON Schema and Payload Validator for MCP JSON-RPC 2.0.
Verifies types, detects cyclic references and recursion explosion,
and cleanses NaN / Infinite floating point values to prevent client crashes.
"""

from __future__ import annotations

import math
from typing import Any, Callable, Dict, Optional, Set, Tuple


def _cleanse_dict(d: Dict[Any, Any]) -> Dict[Any, Any]:
    return {k: cleanse_floats(v) for k, v in d.items()}


def _cleanse_seq(seq: Any) -> Any:
    cleaned = [cleanse_floats(item) for item in seq]
    return tuple(cleaned) if isinstance(seq, tuple) else cleaned


def _cleanse_float(val: float) -> Optional[float]:
    if math.isnan(val) or math.isinf(val):
        return None
    return val


def cleanse_floats(payload: Any) -> Any:
    """Recursively replaces NaN and Inf with None to ensure valid JSON."""
    if isinstance(payload, float):
        return _cleanse_float(payload)
    if isinstance(payload, dict):
        return _cleanse_dict(payload)
    if isinstance(payload, (list, tuple)):
        return _cleanse_seq(payload)
    return payload


def _is_invalid_float(obj: float) -> bool:
    return math.isnan(obj) or math.isinf(obj)


def _check_scalar(obj: Any) -> Tuple[bool, Optional[str]]:
    """Checks primitive/scalar JSON values."""
    if obj is None or isinstance(obj, (bool, int, str)):
        return True, None
    if isinstance(obj, float):
        msg = (
            "Non-finite float (NaN or Inf) detected in JSON payload"
            if _is_invalid_float(obj)
            else None
        )
        return True, msg
    return False, None


def _check_dict_entries(
    obj: Dict[Any, Any],
    depth: int,
    check_fn: Callable[[Any, int], Optional[str]],
) -> Optional[str]:
    """Validates key types and recurse on dict values."""
    for k, v in obj.items():
        if not isinstance(k, (str, int)):
            return f"Invalid JSON key type: {type(k).__name__}"
        err = check_fn(v, depth + 1)
        if err:
            return err
    return None


def _check_sequence_entries(
    obj: Any,
    depth: int,
    check_fn: Callable[[Any, int], Optional[str]],
) -> Optional[str]:
    """Recurse on sequence values."""
    for item in obj:
        err = check_fn(item, depth + 1)
        if err:
            return err
    return None


def validate_json_serializable(
    payload: Any, max_depth: int = 20
) -> Tuple[bool, Optional[str]]:
    """
    Validates that payload contains only standard JSON types and does not
    exceed recursion depth limits.
    """
    seen_ids: Set[int] = set()

    def _check(obj: Any, depth: int) -> Optional[str]:
        if depth > max_depth:
            return f"Exceeded maximum nesting depth of {max_depth}"

        obj_id = id(obj)
        if isinstance(obj, (dict, list)):
            if obj_id in seen_ids:
                return "Circular reference detected in payload"
            seen_ids.add(obj_id)

        try:
            is_scalar, scalar_err = _check_scalar(obj)
            if is_scalar:
                return scalar_err
            if isinstance(obj, dict):
                return _check_dict_entries(obj, depth, _check)
            if isinstance(obj, (list, tuple)):
                return _check_sequence_entries(obj, depth, _check)
            return f"Unsupported type in JSON payload: {type(obj).__name__}"
        finally:
            if isinstance(obj, (dict, list)):
                seen_ids.discard(obj_id)

    err = _check(payload, 0)
    return (err is None, err)
