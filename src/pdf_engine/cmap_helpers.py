"""Backward compatibility shim for pdf_engine.cmap_helpers.

This module re-exports symbols from the modularized pdf_engine.cmap.helpers.
New code should import from pdf_engine.cmap directly.
"""

from pdf_engine.cmap.helpers import (
    _build_cmap_mapping,
    _decode_bfchar_pair,
    _decode_bfrange_array,
    _decode_bfrange_single,
    _decode_hex_to_unicode,
    _dispatch_cmap_item,
    _fallback_char,
    _map_bfrange_char,
    _populate_array_range,
    _populate_bfrange_offsets,
    _process_bfchar_block,
    _process_bfrange_block,
    _safe_chr,
    _safe_hex_to_str,
)

__all__ = [
    "_build_cmap_mapping",
    "_decode_bfchar_pair",
    "_decode_bfrange_array",
    "_decode_bfrange_single",
    "_decode_hex_to_unicode",
    "_dispatch_cmap_item",
    "_fallback_char",
    "_map_bfrange_char",
    "_populate_array_range",
    "_populate_bfrange_offsets",
    "_process_bfchar_block",
    "_process_bfrange_block",
    "_safe_chr",
    "_safe_hex_to_str",
]
