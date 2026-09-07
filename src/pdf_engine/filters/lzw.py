#!/usr/bin/env python3
"""
Pure-Python LZW (Lempel-Ziv-Welch) Stream Decompressor.
Conforms to ISO 32000-1:2008 Clause 7.4.4 (LZWDecode Filter).
Zero External Dependencies, DoS Decompression Bomb Protected (SC-1).
"""

from __future__ import annotations

from typing import Dict, Optional, Tuple

CLEAR_TABLE: int = 256
EOD_MARKER: int = 257
FIRST_ENTRY: int = 258
MAX_CODE: int = 4095
MAX_CODE_LEN: int = 12
DEFAULT_MAX_BYTES: int = 30 * 1024 * 1024  # 30 MB (SC-1)


class LzwError(ValueError):
    """Raised when LZW stream decompression fails."""


class _LzwBitReader:
    """Reads variable-length big-endian bit codes from byte stream."""

    def __init__(self, data: bytes) -> None:
        self._data = data
        self._pos = 0
        self._bit_buf = 0
        self._bit_count = 0

    def read_code(self, bit_length: int) -> Optional[int]:
        """Reads next `bit_length` bits as an integer. Returns None on EOF."""
        while self._bit_count < bit_length:
            if self._pos >= len(self._data):
                return None
            self._bit_buf = (self._bit_buf << 8) | self._data[self._pos]
            self._pos += 1
            self._bit_count += 8

        shift = self._bit_count - bit_length
        code = (self._bit_buf >> shift) & ((1 << bit_length) - 1)
        self._bit_count = shift
        self._bit_buf &= (1 << shift) - 1
        return code


def _init_lzw_table() -> Dict[int, bytes]:
    """Initializes standard 0-255 byte dictionary."""
    return {i: bytes([i]) for i in range(256)}


def _check_code_length_bump(next_code: int, code_len: int, early_change: int) -> int:
    """Increments code bit-length when dictionary capacity threshold is reached."""
    threshold = (1 << code_len) - early_change
    if next_code >= threshold and code_len < MAX_CODE_LEN:
        return code_len + 1
    return code_len


def _resolve_code_bytes(
    code: int, prev_bytes: bytes, table: Dict[int, bytes], next_code: int
) -> Optional[bytes]:
    """Resolves output bytes for a given LZW code."""
    if code in table:
        return table[code]
    if code == next_code and prev_bytes:
        return prev_bytes + prev_bytes[:1]
    return None


def _handle_dictionary_addition(
    prev_bytes: bytes,
    curr_bytes: bytes,
    table: Dict[int, bytes],
    next_code: int,
    code_len: int,
    early_change: int,
) -> Tuple[int, int]:
    """Inserts new entry into dictionary and checks if code length should expand."""
    if prev_bytes and next_code <= MAX_CODE:
        table[next_code] = prev_bytes + curr_bytes[:1]
        next_code += 1
        code_len = _check_code_length_bump(next_code, code_len, early_change)
    return next_code, code_len


def _process_lzw_code(
    code: int,
    prev_bytes: bytes,
    table: Dict[int, bytes],
    next_code: int,
    code_len: int,
    early_change: int,
    out: bytearray,
) -> Tuple[bytes, int, int, bool]:
    """Processes a single data code. Returns (prev_bytes, next_code, code_len, ok)."""
    curr = _resolve_code_bytes(code, prev_bytes, table, next_code)
    if curr is None:
        return prev_bytes, next_code, code_len, False

    out.extend(curr)
    next_code, code_len = _handle_dictionary_addition(
        prev_bytes, curr, table, next_code, code_len, early_change
    )
    return curr, next_code, code_len, True


def _is_terminal_code(code: Optional[int]) -> bool:
    """Checks if code represents EOF or EOD."""
    return code is None or code == EOD_MARKER


def _reset_table() -> Tuple[Dict[int, bytes], int, int, bytes]:
    """Resets dictionary and decoding state on ClearTable."""
    return _init_lzw_table(), FIRST_ENTRY, 9, b""


class _LzwDecoder:
    """Stateful LZW stream decoder."""

    def __init__(self, data: bytes, early_change: int, max_bytes: int) -> None:
        self.reader = _LzwBitReader(data)
        self.early_change = early_change
        self.max_bytes = max_bytes
        self.table, self.next_code, self.code_len, self.prev_bytes = _reset_table()
        self.out = bytearray()

    def _step(self) -> bool:
        code = self.reader.read_code(self.code_len)
        if _is_terminal_code(code):
            return False
        if code == CLEAR_TABLE:
            self.table, self.next_code, self.code_len, self.prev_bytes = _reset_table()
            return True

        curr_code: int = -1 if code is None else code
        self.prev_bytes, self.next_code, self.code_len, ok = _process_lzw_code(
            curr_code,
            self.prev_bytes,
            self.table,
            self.next_code,
            self.code_len,
            self.early_change,
            self.out,
        )
        return ok

    def decode(self) -> bytes:
        while len(self.out) < self.max_bytes and self._step():
            pass
        return bytes(self.out[: self.max_bytes])


def decode_lzw(
    data: bytes,
    early_change: int = 1,
    max_bytes: int = DEFAULT_MAX_BYTES,
) -> bytes:
    """
    Decompresses LZWDecode stream according to ISO 32000-1 Clause 7.4.4.

    Args:
        data: Compressed raw byte stream.
        early_change: 1 (default) or 0, indicating when code length increments.
        max_bytes: Maximum allowed decompressed byte count (DoS protection).

    Returns:
        Decompressed byte array as `bytes`.
    """
    if not data:
        return b""
    decoder = _LzwDecoder(data, early_change, max_bytes)
    return decoder.decode()
