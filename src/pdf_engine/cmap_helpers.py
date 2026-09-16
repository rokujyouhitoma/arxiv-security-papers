"""Helper functions for Pure Packrat PEG PDF CMap decoding.

Conforms to ISO 32000-1 Clause 9.10.2 /ToUnicode CMap mapping tables.
Zero external dependencies.
"""

from __future__ import annotations

from typing import Any, Dict, List, Tuple


def _fallback_char(clean_hex: str) -> str:
    try:
        return chr(int(clean_hex, 16))
    except Exception:
        return ""


def _safe_hex_to_str(clean_hex: str) -> str:
    try:
        return bytes.fromhex(clean_hex).decode("utf-16-be", errors="replace")
    except Exception:
        return _fallback_char(clean_hex)


def _decode_hex_to_unicode(hex_str: str) -> str:
    """Decodes hex string into unicode string (UTF-16BE or single char)."""
    clean_hex = hex_str.strip()
    if not clean_hex:
        return ""
    if len(clean_hex) % 2 != 0:
        clean_hex = "0" + clean_hex
    return _safe_hex_to_str(clean_hex)


def _decode_bfchar_pair(src_hex: str, dst_hex: str) -> Tuple[int, str]:
    """Decodes a single bfchar source-destination pair."""
    try:
        src_code = int(src_hex, 16)
        dst_val = _decode_hex_to_unicode(dst_hex)
        return (src_code, dst_val)
    except ValueError:
        return (-1, "")


def _safe_chr(code: int) -> str:
    try:
        return chr(code)
    except ValueError:
        return ""


def _decode_wide_cid(cur_val: int, hex_len: int) -> str:
    try:
        raw_b = cur_val.to_bytes((hex_len + 1) // 2, "big")
        return raw_b.decode("utf-16-be", errors="replace")
    except Exception:
        return ""


def _map_bfrange_char(cur_val: int, hex_len: int) -> str:
    """Maps a numeric CID offset into a character string."""
    if cur_val < 0x110000 and hex_len <= 4:
        return _safe_chr(cur_val)
    return _decode_wide_cid(cur_val, hex_len)


def _populate_bfrange_offsets(
    start: int, end: int, base: int, hex_len: int
) -> Dict[int, str]:
    count = end - start + 1
    if count <= 0 or count > 65536:
        return {}
    mapping: Dict[int, str] = {}
    for offset in range(count):
        char_res = _map_bfrange_char(base + offset, hex_len)
        if char_res:
            mapping[start + offset] = char_res
    return mapping


def _decode_bfrange_single(
    start_hex: str, end_hex: str, base_hex: str
) -> Dict[int, str]:
    """Decodes contiguous incremental range <start> <end> <base>."""
    try:
        start = int(start_hex, 16)
        end = int(end_hex, 16)
        base = int(base_hex, 16)
        return _populate_bfrange_offsets(start, end, base, len(base_hex))
    except ValueError:
        return {}


def _populate_array_range(
    start: int, end: int, dest_hex_list: List[str]
) -> Dict[int, str]:
    mapping: Dict[int, str] = {}
    for offset, dst_hex in enumerate(dest_hex_list):
        cur_code = start + offset
        if cur_code > end:
            break
        dst_str = _decode_hex_to_unicode(dst_hex)
        if dst_str:
            mapping[cur_code] = dst_str
    return mapping


def _decode_bfrange_array(
    start_hex: str, end_hex: str, dest_hex_list: List[str]
) -> Dict[int, str]:
    """Decodes range mapped to array of explicit hex literals <start> <end> [ ... ]."""
    try:
        start = int(start_hex, 16)
        end = int(end_hex, 16)
        return _populate_array_range(start, end, dest_hex_list)
    except ValueError:
        return {}


def _process_bfchar_block(
    pairs: List[Tuple[int, str]], mapping: Dict[int, str]
) -> None:
    for src_code, dst_val in pairs:
        if src_code >= 0 and dst_val:
            mapping[src_code] = dst_val


def _process_bfrange_block(
    ranges: List[Dict[int, str]], mapping: Dict[int, str]
) -> None:
    for range_dict in ranges:
        mapping.update(range_dict)


def _dispatch_cmap_item(item: Any, mapping: Dict[int, str]) -> None:
    if not isinstance(item, tuple) or len(item) != 2:
        return
    kind, payload = item
    if kind == "bfchar":
        _process_bfchar_block(payload, mapping)
    elif kind == "bfrange":
        _process_bfrange_block(payload, mapping)


def _build_cmap_mapping(items: List[Any]) -> Dict[int, str]:
    """Builds a flat CID-to-Unicode mapping table from parsed AST items."""
    mapping: Dict[int, str] = {}
    for item in items:
        _dispatch_cmap_item(item, mapping)
    return mapping
