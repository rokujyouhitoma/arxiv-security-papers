#!/usr/bin/env python3
"""
PAX (Partition Attributes Across) 4KB Page Binary Layout.
Splits 4KB page into vertical Mini-Pages per column, enabling
selective column decoding, high compression ratios, and cache locality.
"""

import struct
from typing import Any, List, Tuple

from .encoding import ColumnDecoder, ColumnEncoder, ColumnEncodingType

PAX_MAGIC: bytes = b"VDBPAX01"
PAGE_SIZE: int = 4096


def _encode_text_column(
    col_vals: List[Any], val_type: str
) -> Tuple[bytes, ColumnEncodingType]:
    """Finds best encoding between RLE, Dictionary, and Plain for text."""
    rle_b = ColumnEncoder.encode_rle(col_vals, val_type)
    dict_b, _ = ColumnEncoder.encode_dictionary([str(v) for v in col_vals])
    plain_b = ColumnEncoder.encode_plain(col_vals, val_type)

    min_len = min(len(rle_b), len(dict_b), len(plain_b))
    if min_len == len(rle_b):
        return rle_b, ColumnEncodingType.RLE
    if min_len == len(dict_b):
        return dict_b, ColumnEncodingType.DICTIONARY
    return plain_b, ColumnEncodingType.PLAIN


def _encode_numeric_column(
    col_vals: List[Any], val_type: str
) -> Tuple[bytes, ColumnEncodingType]:
    """Finds best encoding between RLE and Plain for numeric types."""
    rle_b = ColumnEncoder.encode_rle(col_vals, val_type)
    plain_b = ColumnEncoder.encode_plain(col_vals, val_type)
    if len(rle_b) < len(plain_b):
        return rle_b, ColumnEncodingType.RLE
    return plain_b, ColumnEncodingType.PLAIN


def _encode_column_mini_page(
    col_vals: List[Any],
    val_type: str,
) -> Tuple[bytes, ColumnEncodingType]:
    """Selects and applies optimal encoding for a column."""
    if val_type in ("str", "text"):
        return _encode_text_column(col_vals, val_type)
    return _encode_numeric_column(col_vals, val_type)


def _decode_mini_page_data(
    data: bytes,
    enc_type: ColumnEncodingType,
    val_type: str,
    row_count: int,
) -> List[Any]:
    """Dispatches decoding based on encoding type."""
    if enc_type == ColumnEncodingType.RLE:
        return ColumnDecoder.decode_rle(data, row_count, val_type)
    if enc_type == ColumnEncodingType.DICTIONARY:
        return ColumnDecoder.decode_dictionary(data, row_count)
    return ColumnDecoder.decode_plain(data, row_count, val_type)


def _build_page_header(
    row_count: int,
    col_count: int,
    mini_pages: List[bytes],
    enc_types: List[int],
) -> bytes:
    """Constructs the PAX 4KB page binary payload."""
    header_size = 12 + 3 * col_count
    col_offsets: List[int] = []
    curr_offset = header_size

    for mp in mini_pages:
        col_offsets.append(curr_offset)
        curr_offset += len(mp)

    if curr_offset > PAGE_SIZE:
        raise ValueError(
            f"PAX page content size {curr_offset} exceeds 4096 bytes (rows: {row_count})"
        )

    buf = bytearray(struct.pack("<8sHH", PAX_MAGIC, row_count, col_count))
    for off in col_offsets:
        buf.extend(struct.pack("<H", off))
    for enc in enc_types:
        buf.extend(struct.pack("<B", enc))
    for mp in mini_pages:
        buf.extend(mp)

    if len(buf) < PAGE_SIZE:
        buf.extend(b"\x00" * (PAGE_SIZE - len(buf)))

    return bytes(buf)


class PAXPage:
    """
    PAX 4KB hybrid columnar page serializer and selective column reader.
    """

    @classmethod
    def create_page(
        cls,
        schema: List[Tuple[str, str]],
        rows: List[List[Any]],
    ) -> bytes:
        """Packs rows into a 4096-byte PAX hybrid columnar page."""
        if not rows:
            return b"\x00" * PAGE_SIZE

        row_count = len(rows)
        col_count = len(schema)

        columns: List[List[Any]] = [
            [row[c_idx] if c_idx < len(row) else None for row in rows]
            for c_idx in range(col_count)
        ]

        mini_pages: List[bytes] = []
        enc_types: List[int] = []
        for c_idx, (_, val_type) in enumerate(schema):
            mp_bytes, enc_type = _encode_column_mini_page(columns[c_idx], val_type)
            mini_pages.append(mp_bytes)
            enc_types.append(int(enc_type))

        return _build_page_header(row_count, col_count, mini_pages, enc_types)

    @classmethod
    def read_column(
        cls,
        page_data: memoryview,
        col_idx: int,
        schema: List[Tuple[str, str]],
    ) -> List[Any]:
        """Selectively decodes ONLY the requested column's Mini-Page."""
        if len(page_data) < 12:
            return []

        magic, row_count, col_count = struct.unpack_from("<8sHH", page_data, 0)
        if magic != PAX_MAGIC or row_count == 0:
            return []
        if col_idx < 0 or col_idx >= col_count:
            raise IndexError(
                f"Column index {col_idx} out of range (total cols: {col_count})"
            )

        off_pos = 12
        col_offsets = [
            struct.unpack_from("<H", page_data, off_pos + i * 2)[0]
            for i in range(col_count)
        ]
        enc_pos = 12 + 2 * col_count
        enc_types = [
            struct.unpack_from("<B", page_data, enc_pos + i)[0]
            for i in range(col_count)
        ]

        start_off = col_offsets[col_idx]
        end_off = (
            col_offsets[col_idx + 1] if col_idx + 1 < col_count else len(page_data)
        )
        mini_page_data = bytes(page_data[start_off:end_off])
        enc_type = ColumnEncodingType(enc_types[col_idx])
        val_type = schema[col_idx][1]

        return _decode_mini_page_data(mini_page_data, enc_type, val_type, row_count)

    @classmethod
    def read_rows(
        cls,
        page_data: memoryview,
        schema: List[Tuple[str, str]],
    ) -> List[List[Any]]:
        """Reconstructs all rows from the PAX page."""
        if len(page_data) < 12:
            return []

        magic, row_count, col_count = struct.unpack_from("<8sHH", page_data, 0)
        if magic != PAX_MAGIC or row_count == 0:
            return []

        columns = [
            cls.read_column(page_data, c_idx, schema) for c_idx in range(col_count)
        ]
        return [
            [columns[c_idx][r_idx] for c_idx in range(col_count)]
            for r_idx in range(row_count)
        ]
