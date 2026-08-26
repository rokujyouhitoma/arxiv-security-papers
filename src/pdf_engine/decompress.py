"""Stream decompression and filter decoding pipeline conforming to ISO 32000-1 Clause 7.4."""

import re
import zlib
from typing import Any, Dict, Optional


def paeth_predictor(a: int, b: int, c: int) -> int:
    """Computes PNG Paeth predictor function (ISO 32000-1 Table 8)."""
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _apply_sub_filter(row: bytearray, bpp: int) -> None:
    for i in range(bpp, len(row)):
        row[i] = (row[i] + row[i - bpp]) & 0xFF


def _apply_up_filter(row: bytearray, prev_row: bytearray) -> None:
    for i in range(len(row)):
        row[i] = (row[i] + prev_row[i]) & 0xFF


def _apply_avg_filter(row: bytearray, prev_row: bytearray, bpp: int) -> None:
    for i in range(len(row)):
        left = row[i - bpp] if i >= bpp else 0
        up = prev_row[i]
        row[i] = (row[i] + ((left + up) >> 1)) & 0xFF


def _apply_paeth_filter(row: bytearray, prev_row: bytearray, bpp: int) -> None:
    for i in range(len(row)):
        left = row[i - bpp] if i >= bpp else 0
        up = prev_row[i]
        up_left = prev_row[i - bpp] if i >= bpp else 0
        row[i] = (row[i] + paeth_predictor(left, up, up_left)) & 0xFF


def decode_png_predictor(data: bytes, columns: int, bpp: int = 1) -> bytes:
    """Reconstructs unfiltered data from PNG predictor stream (Predictor >= 10)."""
    stride = columns * bpp + 1
    if stride <= 1 or len(data) < stride:
        return data

    num_rows = len(data) // stride
    out = bytearray(num_rows * columns * bpp)
    prev_row = bytearray(columns * bpp)

    for r in range(num_rows):
        row_raw = data[r * stride : (r + 1) * stride]
        filter_type = row_raw[0]
        cur_row = bytearray(row_raw[1:])

        if filter_type == 1:
            _apply_sub_filter(cur_row, bpp)
        elif filter_type == 2:
            _apply_up_filter(cur_row, prev_row)
        elif filter_type == 3:
            _apply_avg_filter(cur_row, prev_row, bpp)
        elif filter_type == 4:
            _apply_paeth_filter(cur_row, prev_row, bpp)

        out[r * len(cur_row) : (r + 1) * len(cur_row)] = cur_row
        prev_row = cur_row

    return bytes(out)


def decode_tiff_predictor(data: bytes, columns: int, bpp: int = 1) -> bytes:
    """Decodes TIFF Predictor 2 (horizontal differencing)."""
    out = bytearray(data)
    row_bytes = columns * bpp
    num_rows = len(data) // row_bytes if row_bytes > 0 else 0

    for r in range(num_rows):
        start = r * row_bytes
        for i in range(start + bpp, start + row_bytes):
            out[i] = (out[i] + out[i - bpp]) & 0xFF

    return bytes(out)


def decode_ascii_hex(data: bytes) -> bytes:
    """Decodes /ASCIIHexDecode stream (ISO 32000-1 Clause 7.4.2)."""
    text = data.decode("ascii", errors="ignore")
    cleaned = re.sub(r"[^0-9A-Fa-f]", "", text.split(">")[0])
    if len(cleaned) % 2 != 0:
        cleaned += "0"
    return bytes.fromhex(cleaned)


def decode_ascii85(data: bytes) -> bytes:
    """Decodes /ASCII85Decode stream (ISO 32000-1 Clause 7.4.3)."""
    clean_data = data.split(b"~>")[0]
    clean_data = re.sub(rb"\s+", b"", clean_data)
    out = bytearray()
    acc = 0
    cnt = 0

    for b in clean_data:
        if b == ord("z") and cnt == 0:
            out.extend(b"\x00\x00\x00\x00")
            continue
        if 33 <= b <= 117:
            acc = acc * 85 + (b - 33)
            cnt += 1
            if cnt == 5:
                out.extend(acc.to_bytes(4, "big"))
                acc = 0
                cnt = 0

    if cnt > 1:
        for _ in range(5 - cnt):
            acc = acc * 85 + 84
        out.extend(acc.to_bytes(4, "big")[: cnt - 1])

    return bytes(out)


class StreamDecompressor:
    """Unified PDF Stream Decompression and Filter Engine."""

    @classmethod
    def decompress(
        cls,
        raw_bytes: bytes,
        filter_name: Optional[Any],
        decode_parms: Optional[Dict[str, Any]] = None,
    ) -> bytes:
        """Decompresses raw stream payload applying appropriate filter chain."""
        if not filter_name or not raw_bytes:
            return raw_bytes

        filters = filter_name if isinstance(filter_name, list) else [filter_name]
        data = raw_bytes

        for filt in filters:
            fname = filt.strip("/") if isinstance(filt, str) else ""
            if fname in ("FlateDecode", "Fl"):
                data = cls._decompress_flate(data, decode_parms)
            elif fname in ("ASCIIHexDecode", "AHx"):
                data = decode_ascii_hex(data)
            elif fname in ("ASCII85Decode", "A85"):
                data = decode_ascii85(data)

        return data

    @classmethod
    def _decompress_flate(
        cls, data: bytes, decode_parms: Optional[Dict[str, Any]]
    ) -> bytes:
        try:
            decompressed = zlib.decompress(data)
        except zlib.error:
            # Fallback for streams with raw deflate (no zlib wrapper)
            try:
                decompressed = zlib.decompress(data, -zlib.MAX_WBITS)
            except zlib.error:
                return data

        if not decode_parms:
            return decompressed

        predictor = int(
            decode_parms.get("/Predictor", decode_parms.get("Predictor", 1))
        )
        columns = int(decode_parms.get("/Columns", decode_parms.get("Columns", 1)))
        colors = int(decode_parms.get("/Colors", decode_parms.get("Colors", 1)))
        bpc = int(
            decode_parms.get(
                "/BitsPerComponent", decode_parms.get("BitsPerComponent", 8)
            )
        )
        bpp = max(1, (colors * bpc + 7) // 8)

        if predictor >= 10:
            return decode_png_predictor(decompressed, columns, bpp)
        if predictor == 2:
            return decode_tiff_predictor(decompressed, columns, bpp)

        return decompressed
