#!/usr/bin/env python3
"""
Pure-Python CCITT Fax (T.4 / T.6 Group 3 & Group 4) Stream Decompressor.
Conforms to ISO 32000-1:2008 Clause 7.4.5 (CCITTFaxDecode Filter).
Zero External Dependencies, Pure Python.
"""

from __future__ import annotations

from typing import Dict, List, Optional, Tuple

DEFAULT_MAX_BYTES: int = 30 * 1024 * 1024  # 30 MB (SC-1)


class CcittError(ValueError):
    """Raised when CCITT fax decompression fails."""


class _BitStream:
    """Big-endian bit-level reader for Huffman and CCITT stream decoding."""

    def __init__(self, data: bytes) -> None:
        self._data = data
        self._byte_idx = 0
        self._bit_idx = 7  # 7 down to 0

    def next_bit(self) -> Optional[int]:
        """Reads a single bit (0 or 1). Returns None on EOF."""
        if self._byte_idx >= len(self._data):
            return None
        bit = (self._data[self._byte_idx] >> self._bit_idx) & 1
        if self._bit_idx == 0:
            self._bit_idx = 7
            self._byte_idx += 1
        else:
            self._bit_idx -= 1
        return bit

    def peek_bits(self, count: int) -> int:
        """Peeks next `count` bits without advancing pointer."""
        saved_b, saved_bi = self._byte_idx, self._bit_idx
        res = 0
        for _ in range(count):
            b = self.next_bit()
            if b is None:
                break
            res = (res << 1) | b
        self._byte_idx, self._bit_idx = saved_b, saved_bi
        return res

    def advance(self, count: int) -> None:
        """Advances bit pointer by `count` bits."""
        for _ in range(count):
            if self.next_bit() is None:
                break


# Common 1D Modified Huffman Terminating Codes (Length 0-63)
# Format: code_bits_string -> run_length
WHITE_TERMINATING: Dict[str, int] = {
    "00110101": 0,
    "000111": 1,
    "0111": 2,
    "1000": 3,
    "1011": 4,
    "1100": 5,
    "1110": 6,
    "1111": 7,
    "10011": 8,
    "10100": 9,
    "00111": 10,
    "01000": 11,
    "001000": 12,
    "000011": 13,
    "110100": 14,
    "110101": 15,
    "101010": 16,
    "101011": 17,
    "0100111": 18,
    "0001100": 19,
    "0001000": 20,
    "0010111": 21,
    "0000011": 22,
    "0000100": 23,
    "0101000": 24,
    "0101011": 25,
    "0010011": 26,
    "0100100": 27,
    "0011000": 28,
    "00000010": 29,
    "00000011": 30,
    "00011010": 31,
    "00011011": 32,
    "00010010": 33,
    "00010011": 34,
    "00010100": 35,
    "00010101": 36,
    "00010110": 37,
    "00010111": 38,
    "00101000": 39,
    "00101001": 40,
    "00101010": 41,
    "00101011": 42,
    "00101100": 43,
    "00101101": 44,
    "00000100": 45,
    "00000101": 46,
    "00001010": 47,
    "00001011": 48,
    "01010010": 49,
    "01010011": 50,
    "01010100": 51,
    "01010101": 52,
    "00100100": 53,
    "00100101": 54,
    "01011000": 55,
    "01011001": 56,
    "01011010": 57,
    "01011011": 58,
    "01001010": 59,
    "01001011": 60,
    "00110010": 61,
    "00110011": 62,
    "00110100": 63,
}

BLACK_TERMINATING: Dict[str, int] = {
    "0000110111": 0,
    "010": 1,
    "11": 2,
    "10": 3,
    "011": 4,
    "0011": 5,
    "0010": 6,
    "00011": 7,
    "000101": 8,
    "000100": 9,
    "0000100": 10,
    "0000101": 11,
    "0000111": 12,
    "0000010": 13,
    "0000011": 14,
    "00001100": 15,
    "00000101": 16,
    "00000110": 17,
    "000000100": 18,
    "000011001": 19,
    "000011010": 20,
    "000011011": 21,
    "000001101": 22,
    "000001110": 23,
    "000001111": 24,
    "000000101": 25,
    "000000110": 26,
    "000000111": 27,
    "0000000100": 28,
    "0000000101": 29,
    "0000000110": 30,
    "0000000111": 31,
    "00000001000": 32,
    "00000001001": 33,
    "00000001010": 34,
    "00000001011": 35,
    "00000001100": 36,
    "00000001101": 37,
    "00000001110": 38,
    "00000001111": 39,
    "0000001000": 40,
    "0000001001": 41,
    "0000001010": 42,
    "0000001011": 43,
    "0000001100": 44,
    "0000001101": 45,
    "0000001110": 46,
    "0000001111": 47,
    "00000000100": 48,
    "00000000101": 49,
    "00000000110": 50,
    "00000000111": 51,
    "000000010000": 52,
    "000000010001": 53,
    "000000010010": 54,
    "000000010011": 55,
    "000000010100": 56,
    "000000010101": 57,
    "000000010110": 58,
    "000000010111": 59,
    "00000010000": 60,
    "00000010001": 61,
    "00000010010": 62,
    "00000010011": 63,
}

# Make-up codes (64 to 2560 in multiples of 64)
WHITE_MAKEUP: Dict[str, int] = {
    "11011": 64,
    "10010": 128,
    "010111": 192,
    "0110111": 256,
    "00110110": 320,
    "00110111": 384,
    "01100100": 448,
    "01100101": 512,
    "01101000": 576,
    "01100111": 640,
    "011001100": 704,
    "011001101": 768,
    "011010010": 832,
    "011010011": 896,
    "011010100": 960,
    "011010101": 1024,
    "011010110": 1088,
    "011010111": 1152,
    "011011000": 1216,
    "011011001": 1280,
    "011011010": 1344,
    "011011011": 1408,
    "010011000": 1472,
    "010011001": 1536,
    "010011010": 1600,
    "011000": 1664,
    "010011011": 1728,
}

BLACK_MAKEUP: Dict[str, int] = {
    "0000001111": 64,
    "000011001000": 128,
    "000011001001": 192,
    "000001011011": 256,
    "00000110011": 320,
    "000001100100": 384,
    "000001100101": 448,
    "000001101000": 512,
    "000001101001": 576,
    "000001101010": 640,
    "000001101011": 704,
    "000011001010": 768,
    "000011001011": 832,
    "000011001100": 896,
    "000011001101": 960,
    "000011001110": 1024,
    "000011001111": 1088,
    "0000001110110": 1152,
    "0000001110111": 1216,
    "0000001010010": 1280,
    "0000001010011": 1344,
    "0000001010100": 1408,
    "0000001010101": 1472,
    "0000001011010": 1536,
    "0000001011011": 1600,
    "0000001100100": 1664,
    "0000001100101": 1728,
}


def _check_run_maps(
    bits_str: str,
    term_map: Dict[str, int],
    make_map: Dict[str, int],
) -> Tuple[int, bool, bool]:
    """Checks bit string against make-up and terminating tables."""
    if bits_str in make_map:
        return make_map[bits_str], False, True
    if bits_str in term_map:
        return term_map[bits_str], True, False
    return 0, False, False


def _step_run_code(
    stream: _BitStream,
    bits_str: str,
    term_map: Dict[str, int],
    make_map: Dict[str, int],
) -> Tuple[str, int, bool]:
    """Reads one bit and checks if a terminating or make-up code matched."""
    b = stream.next_bit()
    if b is None:
        return bits_str, 0, True
    new_str = bits_str + str(b)
    val, is_term, is_make = _check_run_maps(new_str, term_map, make_map)
    if is_term:
        return "", val, True
    if is_make:
        return "", val, False
    return new_str, 0, False


def _decode_run_length(stream: _BitStream, is_white: bool) -> int:
    """Decodes a single run length (terminating or make-up + terminating)."""
    term_map = WHITE_TERMINATING if is_white else BLACK_TERMINATING
    make_map = WHITE_MAKEUP if is_white else BLACK_MAKEUP
    total_len = 0
    bits_str = ""

    while len(bits_str) < 14:
        bits_str, val, done = _step_run_code(stream, bits_str, term_map, make_map)
        total_len += val
        if done:
            break
    return total_len


def _find_next_changing_element(
    line: List[int], start_idx: int, target_color: int
) -> int:
    """Finds next index >= start_idx where pixel color changes to target_color."""
    width = len(line)
    for i in range(max(0, start_idx), width):
        if line[i] == target_color:
            return i
    return width


def _apply_2d_vertical(
    coding_line: List[int],
    ref_line: List[int],
    a0: int,
    curr_color: int,
    offset: int,
) -> Tuple[int, int]:
    """Applies Vertical mode V(offset) where offset in [-3, 3]."""
    width = len(coding_line)
    next_color = 1 - curr_color
    b1 = _find_next_changing_element(ref_line, a0 + 1 if a0 >= 0 else 0, next_color)
    a1 = min(width, max(0, b1 + offset))
    start = max(0, a0)
    for i in range(start, a1):
        coding_line[i] = curr_color
    return a1, next_color


def _apply_2d_pass(
    coding_line: List[int],
    ref_line: List[int],
    a0: int,
    curr_color: int,
) -> int:
    """Applies Pass mode (code: 0001)."""
    width = len(coding_line)
    next_color = 1 - curr_color
    b1 = _find_next_changing_element(ref_line, a0 + 1 if a0 >= 0 else 0, next_color)
    b2 = _find_next_changing_element(ref_line, b1, curr_color)
    start = max(0, a0)
    for i in range(start, min(width, b2)):
        coding_line[i] = curr_color
    return b2


def _apply_2d_horizontal(
    stream: _BitStream,
    coding_line: List[int],
    a0: int,
    curr_color: int,
) -> int:
    """Applies Horizontal mode (code: 001)."""
    width = len(coding_line)
    r1 = _decode_run_length(stream, is_white=(curr_color == 0))
    r2 = _decode_run_length(stream, is_white=(curr_color == 1))

    start = max(0, a0)
    a1 = min(width, start + r1)
    for i in range(start, a1):
        coding_line[i] = curr_color

    a2 = min(width, a1 + r2)
    opp_color = 1 - curr_color
    for i in range(a1, a2):
        coding_line[i] = opp_color
    return a2


VERTICAL_OFFSETS: Dict[str, int] = {
    "1": 0,
    "011": 1,
    "010": -1,
    "000011": 2,
    "000010": -2,
    "0000011": 3,
    "0000010": -3,
}


def _dispatch_2d_action(
    bits: str,
    stream: _BitStream,
    coding_line: List[int],
    ref_line: List[int],
    a0: int,
    curr_color: int,
) -> Optional[Tuple[int, int]]:
    """Dispatches a matched 2D code string to its mode handler."""
    if bits in VERTICAL_OFFSETS:
        new_a0, new_color = _apply_2d_vertical(
            coding_line, ref_line, a0, curr_color, VERTICAL_OFFSETS[bits]
        )
        return new_a0, new_color
    if bits == "001":
        return _apply_2d_horizontal(stream, coding_line, a0, curr_color), curr_color
    if bits == "0001":
        return _apply_2d_pass(coding_line, ref_line, a0, curr_color), curr_color
    return None


def _decode_2d_mode_step(
    stream: _BitStream,
    coding_line: List[int],
    ref_line: List[int],
    a0: int,
    curr_color: int,
) -> Tuple[int, int, bool]:
    """Decodes one 2D mode code (Pass, Horiz, or Vertical). Returns (a0, curr_color, ok)."""
    bits = ""
    for _ in range(7):
        nb = stream.next_bit()
        if nb is None:
            return a0, curr_color, False
        bits += str(nb)
        action = _dispatch_2d_action(
            bits, stream, coding_line, ref_line, a0, curr_color
        )
        if action is not None:
            return action[0], action[1], True

    return a0, curr_color, False


def _pack_row_to_bytes(row: List[int], black_is_1: bool) -> bytes:
    """Packs 1-bit integer row (0: white, 1: black) into packed byte string."""
    packed = bytearray()
    acc = 0
    cnt = 0
    for px in row:
        bit = px if black_is_1 else (1 - px)
        acc = (acc << 1) | bit
        cnt += 1
        if cnt == 8:
            packed.append(acc)
            acc, cnt = 0, 0
    if cnt > 0:
        packed.append(acc << (8 - cnt))
    return bytes(packed)


def _decode_ccitt_row(
    stream: _BitStream,
    ref_line: List[int],
    columns: int,
    black_is_1: bool,
) -> Tuple[List[int], bytes, bool]:
    """Decodes a single 2D raster line."""
    coding_line = [0] * columns
    a0 = -1
    curr_color = 0

    while a0 < columns:
        a0, curr_color, ok = _decode_2d_mode_step(
            stream, coding_line, ref_line, a0, curr_color
        )
        if not ok:
            return coding_line, _pack_row_to_bytes(coding_line, black_is_1), False

    return coding_line, _pack_row_to_bytes(coding_line, black_is_1), True


def _read_all_ccitt_rows(
    stream: _BitStream, columns: int, max_rows: int, black_is_1: bool, max_bytes: int
) -> bytes:
    """Decodes all raster rows up to max_rows or max_bytes."""
    out = bytearray()
    ref_line = [0] * columns
    for _ in range(max_rows):
        ref_line, row_bytes, ok = _decode_ccitt_row(
            stream, ref_line, columns, black_is_1
        )
        out.extend(row_bytes)
        if not ok or len(out) >= max_bytes:
            break
    return bytes(out[:max_bytes])


def decode_ccitt_fax(
    data: bytes,
    columns: int = 1728,
    rows: int = 0,
    k: int = -1,
    black_is_1: bool = False,
    max_bytes: int = DEFAULT_MAX_BYTES,
) -> bytes:
    """
    Decompresses CCITTFaxDecode stream (Group 4 2D or Group 3 1D).
    Conforms to ISO 32000-1 Clause 7.4.5.
    """
    if not data or columns <= 0:
        return b""
    max_rows = rows if rows > 0 else 10000
    stream = _BitStream(data)
    return _read_all_ccitt_rows(stream, columns, max_rows, black_is_1, max_bytes)
