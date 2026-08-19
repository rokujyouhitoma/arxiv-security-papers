#!/usr/bin/env python3
"""
Column Encoding and Compression Algorithms for PAX Columnar Storage.
Provides Run-Length Encoding (RLE), Dictionary Encoding, and Plain Binary Encoding.
"""

import enum
import struct
from typing import Any, List, Tuple


class ColumnEncodingType(enum.IntEnum):
    """Encoding algorithms for PAX Mini-Pages."""

    PLAIN = 0
    RLE = 1
    DICTIONARY = 2


class ColumnEncoder:
    """Encodes a list of homogeneous column values into compressed binary format."""

    @staticmethod
    def encode_plain(values: List[Any], val_type: str) -> bytes:
        """Encodes values in native uncompressed binary representation."""
        buf = bytearray()
        if val_type in ("int", "integer"):
            for v in values:
                buf.extend(struct.pack("<q", int(v)))
        elif val_type in ("float", "real"):
            for v in values:
                buf.extend(struct.pack("<d", float(v)))
        elif val_type in ("str", "text"):
            for v in values:
                s_bytes = str(v).encode("utf-8")
                buf.extend(struct.pack("<H", len(s_bytes)) + s_bytes)
        else:
            for v in values:
                s_bytes = str(v).encode("utf-8")
                buf.extend(struct.pack("<H", len(s_bytes)) + s_bytes)
        return bytes(buf)

    @staticmethod
    def encode_rle(values: List[Any], val_type: str) -> bytes:
        """
        Run-Length Encodes a column: sequence of (run_length: uint16, value).
        """
        if not values:
            return b""

        runs: List[Tuple[int, Any]] = []
        curr_val = values[0]
        curr_count = 0

        for v in values:
            if v == curr_val and curr_count < 65535:
                curr_count += 1
            else:
                runs.append((curr_count, curr_val))
                curr_val = v
                curr_count = 1
        runs.append((curr_count, curr_val))

        buf = bytearray(struct.pack("<H", len(runs)))
        for count, val in runs:
            if val_type in ("int", "integer"):
                buf.extend(struct.pack("<Hq", count, int(val)))
            elif val_type in ("float", "real"):
                buf.extend(struct.pack("<Hd", count, float(val)))
            else:
                s_bytes = str(val).encode("utf-8")
                buf.extend(struct.pack("<HH", count, len(s_bytes)) + s_bytes)
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
    def decode_plain(data: bytes, count: int, val_type: str) -> List[Any]:
        """Decodes plain binary payload into values."""
        results: List[Any] = []
        pos = 0

        if val_type in ("int", "integer"):
            for _ in range(count):
                if pos + 8 > len(data):
                    break
                val = struct.unpack_from("<q", data, pos)[0]
                pos += 8
                results.append(val)
        elif val_type in ("float", "real"):
            for _ in range(count):
                if pos + 8 > len(data):
                    break
                val = struct.unpack_from("<d", data, pos)[0]
                pos += 8
                results.append(val)
        else:
            for _ in range(count):
                if pos + 2 > len(data):
                    break
                s_len = struct.unpack_from("<H", data, pos)[0]
                pos += 2
                s_str = data[pos : pos + s_len].decode("utf-8")
                pos += s_len
                results.append(s_str)
        return results

    @staticmethod
    def decode_rle(data: bytes, total_count: int, val_type: str) -> List[Any]:
        """Decodes Run-Length Encoded binary payload into values."""
        if len(data) < 2:
            return []

        run_count = struct.unpack_from("<H", data, 0)[0]
        pos = 2
        results: List[Any] = []

        for _ in range(run_count):
            if val_type in ("int", "integer"):
                if pos + 10 > len(data):
                    break
                c, v = struct.unpack_from("<Hq", data, pos)
                pos += 10
                results.extend([v] * c)
            elif val_type in ("float", "real"):
                if pos + 10 > len(data):
                    break
                c, v = struct.unpack_from("<Hd", data, pos)
                pos += 10
                results.extend([v] * c)
            else:
                if pos + 4 > len(data):
                    break
                c, s_len = struct.unpack_from("<HH", data, pos)
                pos += 4
                s_str = data[pos : pos + s_len].decode("utf-8")
                pos += s_len
                results.extend([s_str] * c)

        return results[:total_count]

    @staticmethod
    def decode_dictionary(data: bytes, total_count: int) -> List[str]:
        """Decodes Dictionary encoded binary payload into text values."""
        if len(data) < 2:
            return []

        dict_len = struct.unpack_from("<H", data, 0)[0]
        pos = 2
        dict_table: List[str] = []

        for _ in range(dict_len):
            if pos + 2 > len(data):
                break
            s_len = struct.unpack_from("<H", data, pos)[0]
            pos += 2
            s_str = data[pos : pos + s_len].decode("utf-8")
            pos += s_len
            dict_table.append(s_str)

        results: List[str] = []
        for _ in range(total_count):
            if pos + 2 > len(data):
                break
            idx = struct.unpack_from("<H", data, pos)[0]
            pos += 2
            results.append(dict_table[idx] if idx < len(dict_table) else "")

        return results
