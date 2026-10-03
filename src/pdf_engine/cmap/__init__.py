"""Pure Packrat PEG PDF CMap decoding.

Conforms to ISO 32000-1 Clause 9.10.2 /ToUnicode CMap mapping tables.
Zero external dependencies.
"""

from pdf_engine.cmap.helpers import (
    _build_cmap_mapping,
    _decode_bfchar_pair,
    _decode_bfrange_array,
    _decode_bfrange_single,
    _decode_hex_to_unicode,
)

__all__ = [
    "_build_cmap_mapping",
    "_decode_bfchar_pair",
    "_decode_bfrange_array",
    "_decode_bfrange_single",
    "_decode_hex_to_unicode",
]
