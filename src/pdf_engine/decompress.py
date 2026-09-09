"""Stream decompression and filter decoding pipeline conforming to ISO 32000-1 Clause 7.4."""

import re
import zlib
from typing import Any, Callable, Dict, List, Optional

from core.hsm import HierarchicalStateMachine
from pdf_engine.contracts import (
    EVENT_CHECK_SAFETY,
    EVENT_DECOMPRESS,
    EVENT_FAIL,
    EVENT_FILTER_START,
    EVENT_SAFETY_VIOLATION,
    PdfSafetyLimitExceededError,
    SafetyLimitConfig,
)
from pdf_engine.filters import decode_ccitt_fax, decode_jbig2, decode_lzw


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


def _apply_row_filter(
    filter_type: int, cur_row: bytearray, prev_row: bytearray, bpp: int
) -> None:
    filter_map: Dict[int, Callable[[], None]] = {
        1: lambda: _apply_sub_filter(cur_row, bpp),
        2: lambda: _apply_up_filter(cur_row, prev_row),
        3: lambda: _apply_avg_filter(cur_row, prev_row, bpp),
        4: lambda: _apply_paeth_filter(cur_row, prev_row, bpp),
    }
    action = filter_map.get(filter_type)
    if action:
        action()


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
        cur_row = bytearray(row_raw[1:])
        _apply_row_filter(row_raw[0], cur_row, prev_row, bpp)
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


def _process_ascii85_byte(
    b: int, acc: int, cnt: int, out: bytearray
) -> tuple[int, int]:
    if b == ord("z") and cnt == 0:
        out.extend(b"\x00\x00\x00\x00")
        return 0, 0
    if 33 <= b <= 117:
        acc = acc * 85 + (b - 33)
        cnt += 1
        if cnt == 5:
            out.extend(acc.to_bytes(4, "big"))
            return 0, 0
    return acc, cnt


def _finalize_ascii85(acc: int, cnt: int, out: bytearray) -> None:
    if cnt > 1:
        for _ in range(5 - cnt):
            acc = acc * 85 + 84
        out.extend(acc.to_bytes(4, "big")[: cnt - 1])


def decode_ascii85(data: bytes) -> bytes:
    """Decodes /ASCII85Decode stream (ISO 32000-1 Clause 7.4.3)."""
    clean_data = re.sub(rb"\s+", b"", data.split(b"~>")[0])
    out = bytearray()
    acc = 0
    cnt = 0

    for b in clean_data:
        acc, cnt = _process_ascii85_byte(b, acc, cnt, out)

    _finalize_ascii85(acc, cnt, out)
    return bytes(out)


def _normalize_filter_list(filter_name: Any) -> List[Any]:
    """Ensures filter specification is returned as a list."""
    if isinstance(filter_name, list):
        return filter_name
    return [filter_name]


def _check_filter_depth(
    filters: List[Any],
    cfg: SafetyLimitConfig,
    hsm: Optional[HierarchicalStateMachine],
) -> None:
    """Validates filter chain depth against configured limits."""
    if len(filters) > cfg.max_filter_depth:
        if hsm:
            hsm.send_event(EVENT_SAFETY_VIOLATION)
        raise PdfSafetyLimitExceededError(
            f"Filter chain depth {len(filters)} exceeds safety limit {cfg.max_filter_depth}"
        )


def _check_decomp_size_limit(
    decomp_len: int,
    cfg: SafetyLimitConfig,
    hsm: Optional[HierarchicalStateMachine],
) -> None:
    """Validates decompressed byte size against configured limits."""
    if decomp_len > cfg.max_decompressed_bytes:
        if hsm:
            hsm.send_event(EVENT_SAFETY_VIOLATION)
        raise PdfSafetyLimitExceededError(
            f"Decompressed stream size {decomp_len} exceeds safety limit {cfg.max_decompressed_bytes}"
        )


def _check_expansion_ratio(
    raw_len: int,
    decomp_len: int,
    cfg: SafetyLimitConfig,
    hsm: Optional[HierarchicalStateMachine],
) -> None:
    """Detects Decompression Bombs (CWE-409) via expansion ratio thresholds."""
    ratio = decomp_len / max(1, raw_len)
    if ratio > cfg.max_expansion_ratio:
        if hsm:
            hsm.send_event(EVENT_SAFETY_VIOLATION)
        raise PdfSafetyLimitExceededError(
            f"Expansion ratio {ratio:.1f}x exceeds safety limit {cfg.max_expansion_ratio:.1f}x"
        )


def _is_empty_input(filter_name: Optional[Any], raw_bytes: bytes) -> bool:
    """Checks if stream input or filter specification is empty."""
    if not filter_name:
        return True
    return len(raw_bytes) == 0


def _handle_decompress_error(
    e: Exception, hsm: Optional[HierarchicalStateMachine]
) -> None:
    """Handles exceptions during decompression, ensuring fail-secure transition."""
    if isinstance(e, PdfSafetyLimitExceededError):
        raise e
    if hsm is not None:
        hsm.send_event(EVENT_FAIL)
    raise e


class StreamDecompressor:
    """Unified PDF Stream Decompression and Filter Engine."""

    @classmethod
    def _decompress_lzw(
        cls, data: bytes, decode_parms: Optional[Dict[str, Any]]
    ) -> bytes:
        parms = decode_parms or {}
        early_change = int(parms.get("/EarlyChange", parms.get("EarlyChange", 1)))
        decomp = decode_lzw(data, early_change=early_change)
        if decode_parms:
            return cls._apply_predictor_params(decomp, decode_parms)
        return decomp

    @classmethod
    def _decompress_ccitt(
        cls, data: bytes, decode_parms: Optional[Dict[str, Any]]
    ) -> bytes:
        parms = decode_parms or {}
        k = int(parms.get("/K", parms.get("K", 0)))
        columns = int(parms.get("/Columns", parms.get("Columns", 1728)))
        rows = int(parms.get("/Rows", parms.get("Rows", 0)))
        black_is_1 = bool(parms.get("/BlackIs1", parms.get("BlackIs1", False)))
        return decode_ccitt_fax(
            data, columns=columns, rows=rows, k=k, black_is_1=black_is_1
        )

    @classmethod
    def _decompress_jbig2(
        cls, data: bytes, decode_parms: Optional[Dict[str, Any]]
    ) -> bytes:
        parms = decode_parms or {}
        globals_data = parms.get("/JBIG2Globals", parms.get("JBIG2Globals"))
        raw_globals = globals_data if isinstance(globals_data, bytes) else None
        bitmap, _, _ = decode_jbig2(data, globals_data=raw_globals)
        return bitmap

    @classmethod
    def _apply_single_filter(
        cls, filt: Any, data: bytes, decode_parms: Optional[Dict[str, Any]]
    ) -> bytes:
        fname = filt.strip("/") if isinstance(filt, str) else ""
        handlers: Dict[str, Callable[[bytes, Optional[Dict[str, Any]]], bytes]] = {
            "FlateDecode": cls._decompress_flate,
            "Fl": cls._decompress_flate,
            "LZWDecode": cls._decompress_lzw,
            "LZW": cls._decompress_lzw,
            "CCITTFaxDecode": cls._decompress_ccitt,
            "CCF": cls._decompress_ccitt,
            "JBIG2Decode": cls._decompress_jbig2,
            "ASCIIHexDecode": lambda d, _: decode_ascii_hex(d),
            "AHx": lambda d, _: decode_ascii_hex(d),
            "ASCII85Decode": lambda d, _: decode_ascii85(d),
            "A85": lambda d, _: decode_ascii85(d),
        }
        handler = handlers.get(fname)
        if handler is not None:
            return handler(data, decode_parms)
        return data

    @classmethod
    def _decompress_filter_step(
        cls,
        filt: Any,
        data: bytes,
        raw_len: int,
        decode_parms: Optional[Dict[str, Any]],
        cfg: SafetyLimitConfig,
        hsm: Optional[HierarchicalStateMachine],
    ) -> bytes:
        if hsm:
            hsm.send_event(EVENT_DECOMPRESS)
        decomp = cls._apply_single_filter(filt, data, decode_parms)
        if hsm:
            hsm.send_event(EVENT_CHECK_SAFETY)
        _check_decomp_size_limit(len(decomp), cfg, hsm)
        _check_expansion_ratio(raw_len, len(decomp), cfg, hsm)
        return decomp

    @classmethod
    def _execute_filter_loop(
        cls,
        filters: List[Any],
        raw_bytes: bytes,
        decode_parms: Optional[Dict[str, Any]],
        cfg: SafetyLimitConfig,
        hsm: Optional[HierarchicalStateMachine],
    ) -> bytes:
        data = raw_bytes
        for idx, filt in enumerate(filters):
            if hsm and idx > 0:
                hsm.send_event(EVENT_FILTER_START)
            data = cls._decompress_filter_step(
                filt, data, len(raw_bytes), decode_parms, cfg, hsm
            )
        return data

    @classmethod
    def decompress(
        cls,
        raw_bytes: bytes,
        filter_name: Optional[Any],
        decode_parms: Optional[Dict[str, Any]] = None,
        hsm: Optional[HierarchicalStateMachine] = None,
        config: Optional[SafetyLimitConfig] = None,
    ) -> bytes:
        """Decompresses raw stream payload applying appropriate filter chain."""
        if _is_empty_input(filter_name, raw_bytes):
            return raw_bytes

        cfg = config if config is not None else SafetyLimitConfig()
        filters = _normalize_filter_list(filter_name)
        _check_filter_depth(filters, cfg, hsm)

        try:
            return cls._execute_filter_loop(filters, raw_bytes, decode_parms, cfg, hsm)
        except Exception as e:
            _handle_decompress_error(e, hsm)
            return raw_bytes

    @classmethod
    def _safe_zlib_inflate(cls, data: bytes) -> Optional[bytes]:
        try:
            return zlib.decompress(data)
        except zlib.error:
            try:
                return zlib.decompress(data, -zlib.MAX_WBITS)
            except zlib.error:
                return None

    @classmethod
    def _apply_predictor_params(
        cls, decompressed: bytes, parms: Dict[str, Any]
    ) -> bytes:
        predictor = int(parms.get("/Predictor", parms.get("Predictor", 1)))
        columns = int(parms.get("/Columns", parms.get("Columns", 1)))
        colors = int(parms.get("/Colors", parms.get("Colors", 1)))
        bpc = int(parms.get("/BitsPerComponent", parms.get("BitsPerComponent", 8)))
        bpp = max(1, (colors * bpc + 7) // 8)

        if predictor >= 10:
            return decode_png_predictor(decompressed, columns, bpp)
        if predictor == 2:
            return decode_tiff_predictor(decompressed, columns, bpp)
        return decompressed

    @classmethod
    def _decompress_flate(
        cls, data: bytes, decode_parms: Optional[Dict[str, Any]]
    ) -> bytes:
        decompressed = cls._safe_zlib_inflate(data)
        if decompressed is None:
            return data

        if not decode_parms:
            return decompressed

        return cls._apply_predictor_params(decompressed, decode_parms)
