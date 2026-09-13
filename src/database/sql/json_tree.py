"""Pure Python implementation of SQLite table-valued functions json_each() and json_tree().

Conforms to SQLite 3.38.0+ specifications:
Columns returned: (key, value, type, atom, id, parent, fullkey, path)
"""

import json
import re
from typing import Any, Dict, Generator, List, Optional, Tuple, Union


def _scalar_json_type(val: Any) -> str:
    if val is None:
        return "null"
    if isinstance(val, (bool, int)):
        return "integer"
    if isinstance(val, float):
        return "real"
    return "text"


def _get_sqlite_json_type(val: Any) -> str:
    """Returns SQLite JSON type string."""
    if isinstance(val, list):
        return "array"
    if isinstance(val, dict):
        return "object"
    return _scalar_json_type(val)


def _format_value_and_atom(val: Any, val_type: str) -> Tuple[Any, Any]:
    """Formats value and atom fields according to SQLite json_each/tree specification."""
    if val_type in ("null", "integer", "real", "text"):
        atom_val = (1 if val else 0) if isinstance(val, bool) else val
        return atom_val, atom_val
    return json.dumps(val, ensure_ascii=False), None


def _format_fullkey(parent_fullkey: str, key: Union[str, int]) -> str:
    """Formats fullkey path."""
    if isinstance(key, int):
        return f"{parent_fullkey}[{key}]"
    return f"{parent_fullkey}.{key}"


def _load_raw_json(json_data: Any) -> Any:
    if not isinstance(json_data, str):
        return json_data
    try:
        return json.loads(json_data)
    except Exception:
        return None


def _step_path(curr: Any, tok: str, fullkey: str) -> Tuple[Any, Optional[str]]:
    if isinstance(curr, list):
        try:
            idx = int(tok)
            return curr[idx], f"{fullkey}[{idx}]"
        except (ValueError, IndexError):
            return None, None
    if isinstance(curr, dict) and tok in curr:
        return curr[tok], f"{fullkey}.{tok}"
    return None, None


def _navigate_tokens(data: Any, tokens: List[str]) -> Tuple[Any, str, str]:
    curr = data
    curr_fullkey = "$"
    curr_path = "$"
    for tok in tokens:
        curr_path = curr_fullkey
        curr, next_fullkey = _step_path(curr, tok, curr_fullkey)
        if next_fullkey is None:
            return None, curr_fullkey, curr_path
        curr_fullkey = next_fullkey
    return curr, curr_fullkey, curr_path


def _extract_tokens_from_path(path: str) -> List[str]:
    clean_p = path.strip()
    if not clean_p.startswith("$"):
        clean_p = "$" + clean_p
    return [t for t in re.split(r"\.|\[|\]", clean_p.lstrip("$")) if t]


def _parse_root_data(json_data: Any, path: Optional[str]) -> Tuple[Any, str, str]:
    """Parses JSON data and locates the starting node specified by path."""
    data = _load_raw_json(json_data)
    if data is None:
        return None, "$", "$"
    if not path or path.strip() in ("", "$"):
        return data, "$", "$"
    tokens = _extract_tokens_from_path(path)
    return _navigate_tokens(data, tokens)


def _make_row(
    key: Optional[Union[str, int]],
    val: Any,
    node_id: int,
    parent_id: Optional[int],
    fullkey: str,
    path: str,
) -> Dict[str, Any]:
    """Constructs a single 8-column row dictionary."""
    val_type = _get_sqlite_json_type(val)
    out_val, out_atom = _format_value_and_atom(val, val_type)
    return {
        "key": key,
        "value": out_val,
        "type": val_type,
        "atom": out_atom,
        "id": node_id,
        "parent": parent_id,
        "fullkey": fullkey,
        "path": path,
    }


def _each_list_rows(
    target: List[Any], fullkey: str, parent_id: int
) -> List[Dict[str, Any]]:
    return [
        _make_row(i, v, i + 1, parent_id, _format_fullkey(fullkey, i), fullkey)
        for i, v in enumerate(target)
    ]


def _each_dict_rows(
    target: Dict[str, Any], fullkey: str, parent_id: int
) -> List[Dict[str, Any]]:
    return [
        _make_row(k, v, i + 1, parent_id, _format_fullkey(fullkey, k), fullkey)
        for i, (k, v) in enumerate(target.items())
    ]


def iter_json_each(json_data: Any, path: Optional[str] = None) -> List[Dict[str, Any]]:
    """Evaluates json_each(X) or json_each(X, P)."""
    target, fullkey, _ = _parse_root_data(json_data, path)
    if target is None:
        return []
    if isinstance(target, list):
        return _each_list_rows(target, fullkey, 0)
    if isinstance(target, dict):
        return _each_dict_rows(target, fullkey, 0)
    return [_make_row(None, target, 1, 0, fullkey, fullkey)]


def _walk_children(
    curr_val: Union[List[Any], Dict[str, Any]],
    curr_id: int,
    fullkey: str,
    id_counter: List[int],
) -> Generator[Dict[str, Any], None, None]:
    items = enumerate(curr_val) if isinstance(curr_val, list) else curr_val.items()
    for k, item in items:
        id_counter[0] += 1
        child_id = id_counter[0]
        child_fullkey = _format_fullkey(fullkey, k)
        yield from _walk_tree(
            item, k, child_id, curr_id, child_fullkey, fullkey, id_counter
        )


def _walk_tree(
    curr_val: Any,
    curr_key: Optional[Union[str, int]],
    curr_id: int,
    parent_id: Optional[int],
    fullkey: str,
    path: str,
    id_counter: List[int],
) -> Generator[Dict[str, Any], None, None]:
    """DFS walk for json_tree."""
    yield _make_row(curr_key, curr_val, curr_id, parent_id, fullkey, path)
    if isinstance(curr_val, (list, dict)):
        yield from _walk_children(curr_val, curr_id, fullkey, id_counter)


def iter_json_tree(json_data: Any, path: Optional[str] = None) -> List[Dict[str, Any]]:
    """Evaluates json_tree(X) or json_tree(X, P)."""
    target, fullkey, path_str = _parse_root_data(json_data, path)
    if target is None:
        return []
    id_counter = [0]
    return list(
        _walk_tree(
            curr_val=target,
            curr_key=None,
            curr_id=0,
            parent_id=None,
            fullkey=fullkey,
            path=path_str,
            id_counter=id_counter,
        )
    )
