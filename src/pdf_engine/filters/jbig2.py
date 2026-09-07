"""Pure-Python JBIG2 Stream Decoder (Zero External Dependencies).

Implements segment parsing and generic region bitmap decoding (MMR and arithmetic)
for JBIG2 streams in PDF documents (ISO/IEC 14492).
Includes strict bounds checks to mitigate vulnerabilities such as FORCEDENTRY (CVE-2021-30860).
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import List, Optional, Tuple

from pdf_engine.filters.ccitt import decode_ccitt_fax

# Maximum dimension and pixel bounds for defensive decompression
MAX_JBIG2_DIMENSION = 8192
MAX_JBIG2_PIXELS = 16_777_216  # 16 Megapixels
MAX_JBIG2_SEGMENT_COUNT = 1024


class Jbig2Error(ValueError):
    """Raised when JBIG2 stream parsing or decoding fails."""


@dataclass
class Jbig2Segment:
    """Represents a parsed JBIG2 segment."""

    number: int
    seg_type: int
    data: bytes
    page: int
    referred_to: List[int]


@dataclass
class Jbig2PageInfo:
    """Represents page information segment (Type 48)."""

    width: int
    height: int
    res_x: int
    res_y: int
    flags: int
    striping: int


def _get_referred_count(data: bytes, offset: int, count_flag: int) -> Tuple[int, int]:
    """Extract referred segment count from flags or stream."""
    if count_flag <= 4:
        return count_flag, offset + 1
    if count_flag == 7:
        if offset + 5 > len(data):
            raise Jbig2Error("Unexpected EOF in referred-to segment count")
        count = struct.unpack(">I", data[offset + 1 : offset + 5])[0]
        return count, offset + 5
    return 0, offset + 1


def _read_ref_id(data: bytes, offset: int, id_size: int) -> Tuple[int, int]:
    """Read a single referred segment ID."""
    if offset + id_size > len(data):
        raise Jbig2Error("Unexpected EOF reading referred segment ID")
    if id_size == 1:
        return data[offset], offset + 1
    if id_size == 2:
        return struct.unpack(">H", data[offset : offset + 2])[0], offset + 2
    return struct.unpack(">I", data[offset : offset + 4])[0], offset + 4


def _parse_referred_segments(
    data: bytes, offset: int, seg_num: int, count_flag: int
) -> Tuple[List[int], int]:
    """Parse referred-to segment numbers."""
    count, offset = _get_referred_count(data, offset, count_flag)
    if count > MAX_JBIG2_SEGMENT_COUNT:
        raise Jbig2Error(f"Referred-to segment count too high: {count}")

    id_size = 1 if seg_num <= 256 else (2 if seg_num <= 65536 else 4)
    referred: List[int] = []
    for _ in range(count):
        ref_id, offset = _read_ref_id(data, offset, id_size)
        referred.append(ref_id)
    return referred, offset


def _parse_page_association(
    data: bytes, offset: int, page_assoc_large: bool
) -> Tuple[int, int]:
    """Parse page association field."""
    if page_assoc_large:
        if offset + 4 > len(data):
            raise Jbig2Error("Unexpected EOF reading page association")
        page = struct.unpack(">I", data[offset : offset + 4])[0]
        return page, offset + 4
    if offset + 1 > len(data):
        raise Jbig2Error("Unexpected EOF reading page association")
    return data[offset], offset + 1


def _parse_single_segment(
    data: bytes, offset: int
) -> Tuple[Optional[Jbig2Segment], int]:
    """Parse a single JBIG2 segment header and extract its payload."""
    if offset + 6 > len(data):
        return None, len(data)

    seg_num = struct.unpack(">I", data[offset : offset + 4])[0]
    header_flags = data[offset + 4]
    seg_type = header_flags & 0x3F
    page_assoc_large = bool(header_flags & 0x40)
    offset += 5

    count_flag = (data[offset] >> 5) & 0x07
    referred, offset = _parse_referred_segments(data, offset, seg_num, count_flag)
    page, offset = _parse_page_association(data, offset, page_assoc_large)

    if offset + 4 > len(data):
        raise Jbig2Error("Unexpected EOF reading segment length")
    data_len = struct.unpack(">I", data[offset : offset + 4])[0]
    offset += 4

    if data_len == 0xFFFFFFFF:
        raise Jbig2Error("Unknown segment length is not supported")
    if offset + data_len > len(data):
        raise Jbig2Error(f"Segment data length {data_len} exceeds stream bounds")

    seg_data = data[offset : offset + data_len]
    offset += data_len
    return Jbig2Segment(seg_num, seg_type, seg_data, page, referred), offset


def parse_jbig2_segments(data: bytes) -> List[Jbig2Segment]:
    """Parse all JBIG2 segments from raw stream data."""
    offset = 0
    if data.startswith(b"\x97JB2\r\n\x1a\n"):
        offset = 9  # Skip file header (8 bytes magic + 1 byte flags)

    segments: List[Jbig2Segment] = []
    while offset < len(data):
        seg, offset = _parse_single_segment(data, offset)
        if seg is None:
            break
        segments.append(seg)
        if seg.seg_type == 62:  # End of File segment
            break
    return segments


def _parse_page_info(seg_data: bytes) -> Jbig2PageInfo:
    """Parse Page Information segment (Type 48)."""
    if len(seg_data) < 19:
        raise Jbig2Error("Page info segment too short")
    width, height, res_x, res_y, flags, striping = struct.unpack(
        ">IIIIBH", seg_data[:19]
    )
    if width > MAX_JBIG2_DIMENSION or height > MAX_JBIG2_DIMENSION:
        raise Jbig2Error(f"Page dimensions too large: {width}x{height}")
    if width * height > MAX_JBIG2_PIXELS:
        raise Jbig2Error("Total page pixels exceed security limits")
    return Jbig2PageInfo(width, height, res_x, res_y, flags, striping)


def _decode_generic_region_mmr(region_data: bytes, width: int, height: int) -> bytes:
    """Decode a generic region encoded with MMR (CCITT Group 4)."""
    return decode_ccitt_fax(region_data, columns=width, rows=height, k=-1)


# Standard JBIG2 / QM-Coder probability estimation table (ITU-T T.88 / ISO 14492)
_QE_TABLE: List[Tuple[int, int, int, int]] = [
    (0x5601, 1, 1, 1),
    (0x3401, 2, 6, 0),
    (0x1801, 3, 9, 0),
    (0x0AC1, 4, 12, 0),
    (0x0521, 5, 29, 0),
    (0x0221, 38, 33, 0),
    (0x5601, 7, 6, 1),
    (0x5401, 8, 14, 0),
    (0x4801, 9, 14, 0),
    (0x3801, 10, 14, 0),
    (0x3001, 11, 17, 0),
    (0x2401, 12, 18, 0),
    (0x1C01, 13, 20, 0),
    (0x1601, 29, 21, 0),
    (0x5601, 15, 14, 1),
    (0x5401, 16, 14, 0),
    (0x5101, 17, 15, 0),
    (0x4801, 18, 16, 0),
    (0x3801, 19, 17, 0),
    (0x3401, 20, 18, 0),
    (0x3001, 21, 19, 0),
    (0x2801, 22, 19, 0),
    (0x2401, 23, 20, 0),
    (0x2201, 24, 21, 0),
    (0x1C01, 25, 22, 0),
    (0x1801, 26, 23, 0),
    (0x1601, 27, 24, 0),
    (0x1401, 28, 25, 0),
    (0x1201, 29, 26, 0),
    (0x1101, 30, 27, 0),
    (0x0AC1, 31, 28, 0),
    (0x09C1, 32, 29, 0),
    (0x08A1, 33, 30, 0),
    (0x0521, 34, 31, 0),
    (0x0441, 35, 32, 0),
    (0x02A1, 36, 33, 0),
    (0x0221, 37, 34, 0),
    (0x0141, 5, 35, 0),
    (0x0111, 39, 36, 0),
    (0x0085, 40, 37, 0),
    (0x0049, 41, 38, 0),
    (0x0025, 42, 39, 0),
    (0x0015, 43, 40, 0),
    (0x0009, 44, 41, 0),
    (0x0005, 45, 42, 0),
    (0x0001, 45, 43, 0),
    (0x5601, 46, 46, 0),
]


class _MqDecoder:
    """JBIG2 MQ arithmetic entropy decoder."""

    def __init__(self, data: bytes) -> None:
        self._data = data
        self._offset = 0
        self._a = 0x8000
        self._c = 0
        self._b = 0
        self._init_decoder()

    def _byte_in(self) -> int:
        """Fetch next byte, handling marker 0xFF."""
        if self._offset >= len(self._data):
            return 0xFF
        b = self._data[self._offset]
        self._offset += 1
        return b

    def _init_decoder(self) -> None:
        """Initialize C register from input stream."""
        self._b = self._byte_in()
        self._c = (self._b ^ 0xFF) << 16
        self._byte_in_shift()
        self._c <<= 7
        self._a -= 0x8000
        self._c -= 0x8000

    def _byte_in_shift(self) -> None:
        """Shift input byte into C register."""
        self._b = self._byte_in()
        if self._b == 0xFF:
            b2 = self._byte_in()
            if b2 > 0x8F:
                self._c += 0xFF00
            else:
                self._c += (b2 << 9) + 0x100
        else:
            self._c += self._b << 8

    def decode_bit(self, cx: List[int]) -> int:
        """Decode a single bit given context state [index, mps]."""
        idx = cx[0]
        mps = cx[1]
        qe, next_mps, next_lps, switch_mps = _QE_TABLE[idx]
        self._a -= qe

        if (self._c >> 16) < self._a:
            if self._a < 0x8000:
                bit = self._renorm_mps(cx, qe, next_mps)
            else:
                bit = mps
        else:
            bit = self._renorm_lps(cx, qe, next_lps, switch_mps, mps)
        return bit

    def _renorm_mps(self, cx: List[int], qe: int, next_mps: int) -> int:
        """MPS path renormalization."""
        if self._a < qe:
            bit = 1 - cx[1]
        else:
            bit = cx[1]
        cx[0] = next_mps
        self._renorm()
        return bit

    def _renorm_lps(
        self, cx: List[int], qe: int, next_lps: int, switch_mps: int, mps: int
    ) -> int:
        """LPS path renormalization."""
        self._c -= self._a << 16
        if self._a < qe:
            bit = mps
        else:
            bit = 1 - mps
        if switch_mps:
            cx[1] = 1 - cx[1]
        cx[0] = next_lps
        self._a = qe
        self._renorm()
        return bit

    def _renorm(self) -> None:
        """Renormalize A and C registers."""
        while self._a < 0x8000:
            self._a <<= 1
            self._c <<= 1
            if (self._c & 0xFFFF0000) == 0:
                self._byte_in_shift()


def _decode_arith_row(
    output: bytearray,
    decoder: _MqDecoder,
    contexts: List[List[int]],
    y: int,
    width: int,
    row_bytes: int,
) -> None:
    """Decode a single raster row using MQ arithmetic decoder."""
    y_offset = y * row_bytes
    prev_offset = (y - 1) * row_bytes if y > 0 else 0
    for x in range(width):
        ctx = _compute_template0_context(output, x, y, y_offset, prev_offset)
        bit = decoder.decode_bit(contexts[ctx])
        if bit:
            output[y_offset + (x >> 3)] |= 0x80 >> (x & 7)


def _decode_arithmetic_region(seg_data: bytes, width: int, height: int) -> bytes:
    """Decode generic region using MQ arithmetic coder and template 0."""
    row_bytes = (width + 7) // 8
    output = bytearray(row_bytes * height)
    decoder = _MqDecoder(seg_data)
    contexts: List[List[int]] = [[0, 0] for _ in range(65536)]

    for y in range(height):
        _decode_arith_row(output, decoder, contexts, y, width, row_bytes)
    return bytes(output)


def _compute_template0_context(
    buf: bytearray, x: int, y: int, y_off: int, prev_off: int
) -> int:
    """Compute 16-bit neighborhood context for Generic Template 0."""
    ctx = 0
    if y > 0:
        for dx in range(-2, 3):
            px = x + dx
            if px >= 0:
                byte_val = buf[prev_off + (px >> 3)]
                bit = (byte_val >> (7 - (px & 7))) & 1
                ctx = (ctx << 1) | bit
    if x > 0:
        byte_val = buf[y_off + ((x - 1) >> 3)]
        bit = (byte_val >> (7 - ((x - 1) & 7))) & 1
        ctx = (ctx << 1) | bit
    return ctx & 0xFFFF


def _validate_region_dimensions(width: int, height: int) -> None:
    """Validate generic region dimensions against security limits."""
    if width > MAX_JBIG2_DIMENSION or height > MAX_JBIG2_DIMENSION:
        raise Jbig2Error(f"Region dimension {width}x{height} exceeds maximum limit")
    if width * height > MAX_JBIG2_PIXELS:
        raise Jbig2Error("Pixel count exceeds security limits")


def _decode_immediate_generic_region(
    seg_data: bytes,
) -> Tuple[bytes, int, int]:
    """Decode Immediate Generic Region segment (Type 38/39)."""
    if len(seg_data) < 18:
        raise Jbig2Error("Generic region segment data too short")

    width, height, _, _ = struct.unpack(">IIII", seg_data[:16])
    _ = seg_data[16]  # region_flags
    generic_flags = seg_data[17]
    payload = seg_data[18:]

    _validate_region_dimensions(width, height)

    if generic_flags & 0x01:
        bitmap = _decode_generic_region_mmr(payload, width, height)
    else:
        bitmap = _decode_arithmetic_region(payload, width, height)
    return bitmap, width, height


def _eval_jbig2_segment(
    seg: Jbig2Segment, max_pixels: int
) -> Tuple[Optional[Jbig2PageInfo], Optional[Tuple[bytes, int, int]]]:
    """Process a single segment and extract page info or generic bitmap."""
    if seg.seg_type == 48:
        return _parse_page_info(seg.data), None
    if seg.seg_type in (38, 39):
        bitmap, w, h = _decode_immediate_generic_region(seg.data)
        if w * h > max_pixels:
            raise Jbig2Error("Generic region exceeded max_pixels limit")
        return None, (bitmap, w, h)
    return None, None


def _scan_jbig2_segments(
    segments: List[Jbig2Segment], max_pixels: int
) -> Tuple[Optional[Jbig2PageInfo], Optional[Tuple[bytes, int, int]]]:
    """Scan parsed segments for page info and immediate generic regions."""
    page_info: Optional[Jbig2PageInfo] = None
    target_bitmap: Optional[Tuple[bytes, int, int]] = None
    for seg in segments:
        pi, bmp = _eval_jbig2_segment(seg, max_pixels)
        if pi is not None:
            page_info = pi
        if bmp is not None:
            target_bitmap = bmp
    return page_info, target_bitmap


def _finalize_jbig2_output(
    target_bitmap: Optional[Tuple[bytes, int, int]],
    page_info: Optional[Jbig2PageInfo],
) -> Tuple[bytes, int, int]:
    """Return decoded bitmap or blank page info bitmap."""
    if target_bitmap is not None:
        return target_bitmap
    if page_info is not None:
        row_bytes = (page_info.width + 7) // 8
        return bytes(row_bytes * page_info.height), page_info.width, page_info.height
    raise Jbig2Error(
        "No decodable page or generic region segment found in JBIG2 stream"
    )


def decode_jbig2(
    data: bytes,
    globals_data: Optional[bytes] = None,
    max_pixels: int = MAX_JBIG2_PIXELS,
) -> Tuple[bytes, int, int]:
    """Decode a JBIG2 stream and return the decompressed 1-bit bitmap and (width, height)."""
    if globals_data:
        _ = parse_jbig2_segments(globals_data)

    segments = parse_jbig2_segments(data)
    page_info, target_bitmap = _scan_jbig2_segments(segments, max_pixels)
    return _finalize_jbig2_output(target_bitmap, page_info)
