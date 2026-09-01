#!/usr/bin/env python3
"""
Column Encoding and Compression Algorithms for PAX Columnar Storage.
Provides Run-Length Encoding (RLE), Dictionary Encoding, and Plain Binary Encoding.
"""

import enum
import struct
from typing import Any, List, Optional, Tuple


class ColumnEncodingType(enum.IntEnum):
    """Encoding algorithms for PAX Mini-Pages."""

    PLAIN = 0
    RLE = 1
    DICTIONARY = 2


def _is_int_type(val_type: str) -> bool:
    return val_type in ("int", "integer")


def _is_float_type(val_type: str) -> bool:
    return val_type in ("float", "real")


class ColumnEncoder:
    """Encodes a list of homogeneous column values into compressed binary format."""

    @staticmethod
    def _encode_numeric_plain(values: List[Any], fmt: str, conv: Any) -> bytearray:
        buf = bytearray()
        for v in values:
            buf.extend(struct.pack(fmt, conv(v)))
        return buf

    @staticmethod
    def _encode_str_plain(values: List[Any]) -> bytearray:
        buf = bytearray()
        for v in values:
            s_bytes = str(v).encode("utf-8")
            buf.extend(struct.pack("<H", len(s_bytes)) + s_bytes)
        return buf

    @staticmethod
    def encode_plain(values: List[Any], val_type: str) -> bytes:
        """Encodes values in native uncompressed binary representation."""
        if _is_int_type(val_type):
            return bytes(ColumnEncoder._encode_numeric_plain(values, "<q", int))
        if _is_float_type(val_type):
            return bytes(ColumnEncoder._encode_numeric_plain(values, "<d", float))
        return bytes(ColumnEncoder._encode_str_plain(values))

    @staticmethod
    def _encode_rle_run(count: int, val: Any, val_type: str) -> bytes:
        if _is_int_type(val_type):
            return struct.pack("<Hq", count, int(val))
        if _is_float_type(val_type):
            return struct.pack("<Hd", count, float(val))
        s_bytes = str(val).encode("utf-8")
        return struct.pack("<HH", count, len(s_bytes)) + s_bytes

    @staticmethod
    def _build_rle_runs(values: List[Any]) -> "List[Tuple[int, Any]]":
        runs: List[Tuple[int, Any]] = []
        curr_val = values[0]
        curr_count = 1
        for v in values[1:]:
            if v == curr_val and curr_count < 65535:
                curr_count += 1
            else:
                runs.append((curr_count, curr_val))
                curr_val = v
                curr_count = 1
        runs.append((curr_count, curr_val))
        return runs

    @staticmethod
    def encode_rle(values: List[Any], val_type: str) -> bytes:
        """
        Run-Length Encodes a column: sequence of (run_length: uint16, value).
        """
        if not values:
            return b""
        runs = ColumnEncoder._build_rle_runs(values)
        buf = bytearray(struct.pack("<H", len(runs)))
        for count, val in runs:
            buf.extend(ColumnEncoder._encode_rle_run(count, val, val_type))
        return bytes(buf)

    @staticmethod
    def encode_dictionary(values: List[str]) -> Tuple[bytes, List[str]]:
        """
        Dictionary encodes a text column into (index_payload, dictionary_table).
        """
        dict_table: List[str] = []
        dict_map: dict[str, int] = {}

        indices: List[int] = []
        for v in values:
            s_val = str(v)
            if s_val not in dict_map:
                idx = len(dict_table)
                dict_map[s_val] = idx
                dict_table.append(s_val)
            indices.append(dict_map[s_val])

        # Pack dictionary table: dict_count (uint16) + [str_len(2B), str_bytes]
        dict_buf = bytearray(struct.pack("<H", len(dict_table)))
        for s in dict_table:
            s_bytes = s.encode("utf-8")
            dict_buf.extend(struct.pack("<H", len(s_bytes)) + s_bytes)

        # Pack indices (uint16 each)
        idx_buf = bytearray()
        for idx in indices:
            idx_buf.extend(struct.pack("<H", idx))

        full_payload = bytes(dict_buf) + bytes(idx_buf)
        return full_payload, dict_table


class ColumnDecoder:
    """Decodes compressed binary payload into a list of column values."""

    @staticmethod
    def _decode_numeric_plain(
        data: bytes, count: int, fmt: str, size: int
    ) -> List[Any]:
        results: List[Any] = []
        pos = 0
        for _ in range(count):
            if pos + size > len(data):
                break
            results.append(struct.unpack_from(fmt, data, pos)[0])
            pos += size
        return results

    @staticmethod
    def _decode_str_plain(data: bytes, count: int) -> List[str]:
        results: List[str] = []
        pos = 0
        for _ in range(count):
            if pos + 2 > len(data):
                break
            s_len = struct.unpack_from("<H", data, pos)[0]
            pos += 2
            results.append(data[pos : pos + s_len].decode("utf-8"))
            pos += s_len
        return results

    @staticmethod
    def decode_plain(data: bytes, count: int, val_type: str) -> List[Any]:
        """Decodes plain binary payload into values."""
        if _is_int_type(val_type):
            return ColumnDecoder._decode_numeric_plain(data, count, "<q", 8)
        if _is_float_type(val_type):
            return ColumnDecoder._decode_numeric_plain(data, count, "<d", 8)
        return ColumnDecoder._decode_str_plain(data, count)

    @staticmethod
    def _decode_rle_numeric_run(
        data: bytes, pos: int, fmt: str
    ) -> "Optional[Tuple[int, Any, int]]":
        if pos + 10 > len(data):
            return None
        c, v = struct.unpack_from(fmt, data, pos)
        return c, v, pos + 10

    @staticmethod
    def _decode_rle_str_run(data: bytes, pos: int) -> "Optional[Tuple[int, Any, int]]":
        if pos + 4 > len(data):
            return None
        c, s_len = struct.unpack_from("<HH", data, pos)
        pos += 4
        return c, data[pos : pos + s_len].decode("utf-8"), pos + s_len

    @staticmethod
    def _decode_rle_run(
        data: bytes, pos: int, val_type: str
    ) -> "Optional[Tuple[int, Any, int]]":
        """Decodes one RLE run; returns (count, value, new_pos) or None if insufficient data."""
        if _is_int_type(val_type):
            return ColumnDecoder._decode_rle_numeric_run(data, pos, "<Hq")
        if _is_float_type(val_type):
            return ColumnDecoder._decode_rle_numeric_run(data, pos, "<Hd")
        return ColumnDecoder._decode_rle_str_run(data, pos)

    @staticmethod
    def decode_rle(data: bytes, total_count: int, val_type: str) -> List[Any]:
        """Decodes Run-Length Encoded binary payload into values."""
        if len(data) < 2:
            return []
        run_count = struct.unpack_from("<H", data, 0)[0]
        pos = 2
        results: List[Any] = []
        for _ in range(run_count):
            result = ColumnDecoder._decode_rle_run(data, pos, val_type)
            if result is None:
                break
            c, v, pos = result
            results.extend([v] * c)
        return results[:total_count]

    @staticmethod
    def _decode_dict_table(
        data: bytes, pos: int, dict_len: int
    ) -> "Tuple[List[str], int]":
        dict_table: List[str] = []
        for _ in range(dict_len):
            if pos + 2 > len(data):
                break
            s_len = struct.unpack_from("<H", data, pos)[0]
            pos += 2
            dict_table.append(data[pos : pos + s_len].decode("utf-8"))
            pos += s_len
        return dict_table, pos

    @staticmethod
    def decode_dictionary(data: bytes, total_count: int) -> List[str]:
        """Decodes Dictionary encoded binary payload into text values."""
        if len(data) < 2:
            return []
        dict_len = struct.unpack_from("<H", data, 0)[0]
        dict_table, pos = ColumnDecoder._decode_dict_table(data, 2, dict_len)
        results: List[str] = []
        for _ in range(total_count):
            if pos + 2 > len(data):
                break
            idx = struct.unpack_from("<H", data, pos)[0]
            pos += 2
            results.append(dict_table[idx] if idx < len(dict_table) else "")
        return results
