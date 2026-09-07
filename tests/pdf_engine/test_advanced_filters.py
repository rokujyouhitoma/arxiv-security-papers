"""Comprehensive Unit and Integration Tests for PDF Advanced Stream Filters.

Tests LZWDecode, CCITTFaxDecode, and JBIG2Decode pure-Python decoders,
along with StreamDecompressor integration, decompression bomb guards,
and 1-bit raster image handling.
"""

from __future__ import annotations

import struct
from typing import Any, Dict

import pytest

from pdf_engine.decompress import StreamDecompressor
from pdf_engine.filters import (
    CcittError,
    Jbig2Error,
    LzwError,
    decode_ccitt_fax,
    decode_jbig2,
    decode_lzw,
    parse_jbig2_segments,
)
from pdf_engine.filters.ccitt import _BitStream
from pdf_engine.image_extractor import _expand_1bit_to_8bit


def test_exception_hierarchies() -> None:
    assert issubclass(LzwError, ValueError)
    assert issubclass(CcittError, ValueError)
    assert issubclass(Jbig2Error, ValueError)


# ---------------------------------------------------------------------------
# 1. LZWDecode Tests
# ---------------------------------------------------------------------------


class _LzwTestEncoder:
    """Minimal LZW encoder to synthesize valid PDF LZW test streams."""

    @staticmethod
    def encode(data: bytes, early_change: int = 1) -> bytes:
        table: Dict[bytes, int] = {bytes([i]): i for i in range(256)}
        next_code = 258
        code_size = 9

        codes: list[int] = [256]  # ClearTable
        w = b""

        for byte_val in data:
            c = bytes([byte_val])
            wc = w + c
            if wc in table:
                w = wc
            else:
                codes.append(table[w])
                table[wc] = next_code
                next_code += 1

                # EarlyChange handling
                threshold = (1 << code_size) - (1 if early_change == 1 else 0)
                if next_code >= threshold and code_size < 12:
                    code_size += 1

                w = c

        if w:
            codes.append(table[w])
        codes.append(257)  # EOD

        # Pack codes with variable bit sizes
        bit_buf = 0
        bit_count = 0
        out = bytearray()
        cur_code_size = 9
        next_entry = 258

        for code in codes:
            bit_buf = (bit_buf << cur_code_size) | code
            bit_count += cur_code_size
            while bit_count >= 8:
                bit_count -= 8
                out.append((bit_buf >> bit_count) & 0xFF)

            if code == 256:
                cur_code_size = 9
                next_entry = 258
            elif code != 257:
                next_entry += 1
                threshold = (1 << cur_code_size) - (1 if early_change == 1 else 0)
                if next_entry >= threshold and cur_code_size < 12:
                    cur_code_size += 1

        if bit_count > 0:
            out.append((bit_buf << (8 - bit_count)) & 0xFF)

        return bytes(out)


def test_lzw_empty_and_trivial() -> None:
    assert decode_lzw(b"") == b""
    assert decode_lzw(b"\x00") == b""


def test_lzw_encode_decode_roundtrip() -> None:
    original = b"The quick brown fox jumps over the lazy dog. 1234567890! @#$%^&*()"
    encoded = _LzwTestEncoder.encode(original, early_change=1)
    decoded = decode_lzw(encoded, early_change=1)
    assert decoded == original


def test_lzw_repetitive_pattern_roundtrip() -> None:
    original = b"ABABABABABABABABABABABABABABABABABABABAB" * 10
    encoded = _LzwTestEncoder.encode(original, early_change=1)
    decoded = decode_lzw(encoded, early_change=1)
    assert decoded == original


def test_lzw_early_change_zero_roundtrip() -> None:
    original = b"Testing LZW EarlyChange=0 with various bytes sequence ABCDEFGHIJKLMNOP"
    encoded = _LzwTestEncoder.encode(original, early_change=0)
    decoded = decode_lzw(encoded, early_change=0)
    assert decoded == original


def test_lzw_decompression_bomb_guard() -> None:
    # Synthesize highly compressible repetitive pattern
    original = b"A" * 50000
    encoded = _LzwTestEncoder.encode(original)
    # Decompress with strict max_bytes limit
    decoded = decode_lzw(encoded, max_bytes=1000)
    assert len(decoded) == 1000
    assert decoded == b"A" * 1000


def test_lzw_corrupt_data_handling() -> None:
    # Corrupt or invalid bit sequences should not crash, but cleanly terminate or return partial
    corrupt = b"\xff\xff\x00\x11\x22\x33"
    result = decode_lzw(corrupt)
    assert isinstance(result, bytes)


# ---------------------------------------------------------------------------
# 2. CCITTFaxDecode Tests
# ---------------------------------------------------------------------------


def test_bitstream_operations() -> None:
    stream = _BitStream(b"\xa5\x5a")  # 10100101 01011010
    bits = [stream.next_bit() for _ in range(8)]
    assert bits == [1, 0, 1, 0, 0, 1, 0, 1]
    assert stream.peek_bits(4) == 0x5  # 0101
    stream.advance(4)
    remaining = [stream.next_bit() for _ in range(4)]
    assert remaining == [1, 0, 1, 0]
    assert stream.next_bit() is None


def test_ccitt_empty_and_trivial() -> None:
    assert decode_ccitt_fax(b"", columns=100) == b""
    assert decode_ccitt_fax(b"\x00\x00", columns=0) == b""


def test_ccitt_group4_all_white_row() -> None:
    # In Group 4 2D, V(0) is code '1'
    # For an all-white row with all-white reference line, V(0) signals changing elements match!
    # A single '1' bit followed by fill bits: b"\x80"
    data = b"\x80"
    # columns = 16 (2 bytes per row), rows = 1
    decoded = decode_ccitt_fax(data, columns=16, rows=1, k=-1, black_is_1=False)
    assert len(decoded) == 2


def test_ccitt_group4_black_is_1_flag() -> None:
    data = b"\x80"
    decoded_white = decode_ccitt_fax(data, columns=16, rows=1, k=-1, black_is_1=False)
    decoded_black = decode_ccitt_fax(data, columns=16, rows=1, k=-1, black_is_1=True)
    assert len(decoded_white) == 2
    assert len(decoded_black) == 2
    # Inverted bit patterns
    for bw, bb in zip(decoded_white, decoded_black):
        assert bw ^ bb == 0xFF


def test_ccitt_max_bytes_guard() -> None:
    data = b"\x80" * 100
    decoded = decode_ccitt_fax(data, columns=1728, rows=50, max_bytes=500)
    assert len(decoded) <= 500


# ---------------------------------------------------------------------------
# 3. JBIG2Decode Tests
# ---------------------------------------------------------------------------


def _build_test_jbig2_page_info(width: int = 200, height: int = 150) -> bytes:
    # Segment header:
    # seg_num=1 (4B), flags=48 (1B, page info, assoc=1B), count=0 (1B), page=1 (1B), len=19 (4B)
    hdr = struct.pack(">IBBBI", 1, 48, 0, 1, 19)
    # Page info payload: width, height, res_x, res_y, flags, striping
    payload = struct.pack(">IIIIBH", width, height, 300, 300, 0, 0)
    return hdr + payload


def _build_test_jbig2_generic_region(
    width: int = 16, height: int = 8, use_mmr: bool = True, payload: bytes = b"\x80"
) -> bytes:
    # Segment header: seg_num=2, type=38 (Immediate Generic Region), flags=38, count=0, page=1
    seg_data = (
        struct.pack(">IIII", width, height, 0, 0)
        + b"\x00"  # region_flags
        + bytes([0x01 if use_mmr else 0x00])  # generic_flags (bit 0 = MMR)
        + payload
    )
    hdr = struct.pack(">IBBBI", 2, 38, 0, 1, len(seg_data))
    return hdr + seg_data


def test_jbig2_parse_segments() -> None:
    page_info_seg = _build_test_jbig2_page_info(width=300, height=200)
    generic_seg = _build_test_jbig2_generic_region(width=16, height=8)
    eof_seg = struct.pack(">IBBBI", 3, 62, 0, 1, 0)  # Type 62: EOF

    raw_stream = page_info_seg + generic_seg + eof_seg
    segments = parse_jbig2_segments(raw_stream)

    assert len(segments) == 3
    assert segments[0].seg_type == 48
    assert segments[1].seg_type == 38
    assert segments[2].seg_type == 62


def test_jbig2_with_file_header() -> None:
    file_hdr = b"\x97JB2\r\n\x1a\n\x00"
    page_info_seg = _build_test_jbig2_page_info(width=200, height=100)
    segments = parse_jbig2_segments(file_hdr + page_info_seg)
    assert len(segments) == 1
    assert segments[0].seg_type == 48


def test_jbig2_decode_generic_region_mmr() -> None:
    page_info_seg = _build_test_jbig2_page_info(width=16, height=4)
    generic_seg = _build_test_jbig2_generic_region(
        width=16, height=4, use_mmr=True, payload=b"\xf0"
    )
    raw_stream = page_info_seg + generic_seg
    bitmap, w, h = decode_jbig2(raw_stream)
    assert w == 16
    assert h == 4
    assert len(bitmap) == ((16 + 7) // 8) * 4  # 8 bytes total


def test_jbig2_security_bounds_forcedentry() -> None:
    # 1. Reject excessive dimension (> 8192)
    bad_page_seg = _build_test_jbig2_page_info(width=9000, height=500)
    with pytest.raises(Jbig2Error, match="Page dimensions too large"):
        decode_jbig2(bad_page_seg)

    # 2. Reject total pixels > MAX_JBIG2_PIXELS (16M)
    bad_page_seg2 = _build_test_jbig2_page_info(width=5000, height=5000)
    with pytest.raises(Jbig2Error, match="Total page pixels exceed security limits"):
        decode_jbig2(bad_page_seg2)

    # 3. Truncated segment header EOF
    with pytest.raises(Jbig2Error):
        decode_jbig2(b"\x00\x00\x00\x01\x30\x00\x01\x00\x00\x00\xff")


# ---------------------------------------------------------------------------
# 4. StreamDecompressor Integration Tests
# ---------------------------------------------------------------------------


def test_stream_decompressor_lzw() -> None:
    original = b"StreamDecompressor LZW Pipeline Integration Test Payload!"
    encoded = _LzwTestEncoder.encode(original)

    # Singular filter name
    res = StreamDecompressor.decompress(encoded, "/LZWDecode")
    assert res == original

    # Short name
    res2 = StreamDecompressor.decompress(encoded, "LZW")
    assert res2 == original


def test_stream_decompressor_filter_chain() -> None:
    import base64

    original = b"Chained filters test: ASCII85 followed by LZW."
    lzw_encoded = _LzwTestEncoder.encode(original)
    a85_encoded = base64.a85encode(lzw_encoded) + b"~>"

    decompressed = StreamDecompressor.decompress(
        a85_encoded, ["/ASCII85Decode", "/LZWDecode"]
    )
    assert decompressed == original


def test_stream_decompressor_ccitt() -> None:
    data = b"\x80"
    parms: Dict[str, Any] = {"/Columns": 16, "/Rows": 1, "/K": -1}
    decompressed = StreamDecompressor.decompress(data, "/CCITTFaxDecode", parms)
    assert len(decompressed) == 2


def test_stream_decompressor_jbig2() -> None:
    page_info_seg = _build_test_jbig2_page_info(width=16, height=4)
    generic_seg = _build_test_jbig2_generic_region(
        width=16, height=4, use_mmr=True, payload=b"\xf0"
    )
    raw_stream = page_info_seg + generic_seg

    decompressed = StreamDecompressor.decompress(raw_stream, "/JBIG2Decode")
    assert len(decompressed) == 8


# ---------------------------------------------------------------------------
# 5. Image Extractor 1-Bit Expansion Tests
# ---------------------------------------------------------------------------


def test_expand_1bit_to_8bit_grayscale() -> None:
    # 8 pixels: 1 0 1 0 1 0 1 0 = 0xAA
    # black_is_1=False: 0=Black (0), 1=White (255)
    raw_1bit = b"\xaa"
    expanded = _expand_1bit_to_8bit(raw_1bit, width=8, height=1, black_is_1=False)
    assert len(expanded) == 8
    assert list(expanded) == [255, 0, 255, 0, 255, 0, 255, 0]

    # black_is_1=True: 1=Black (0), 0=White (255)
    expanded_inv = _expand_1bit_to_8bit(raw_1bit, width=8, height=1, black_is_1=True)
    assert list(expanded_inv) == [0, 255, 0, 255, 0, 255, 0, 255]
