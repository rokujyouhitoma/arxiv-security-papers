"""Unit tests for XRef resolver and Decompression pipeline."""

import zlib

from pdf_engine.decompress import StreamDecompressor, decode_png_predictor
from pdf_engine.xref import XRefResolver


def test_png_sub_and_up_predictor():
    # 2 rows of 3 bytes + 1 filter byte each
    # Row 0: Sub filter (1), bytes: [10, 10, 10] -> [10, 20, 30]
    # Row 1: Up filter (2), diffs: [5, 5, 5] -> [15, 25, 35]
    raw_stream = bytes([1, 10, 10, 10, 2, 5, 5, 5])
    reconstructed = decode_png_predictor(raw_stream, columns=3, bpp=1)
    assert list(reconstructed) == [10, 20, 30, 15, 25, 35]


def test_flate_decompress_with_predictor():
    original = bytes([1, 10, 10, 10, 2, 5, 5, 5])
    compressed = zlib.compress(original)

    decomp = StreamDecompressor.decompress(
        compressed,
        filter_name="/FlateDecode",
        decode_parms={
            "/Predictor": 12,
            "/Columns": 3,
            "/Colors": 1,
            "/BitsPerComponent": 8,
        },
    )
    assert list(decomp) == [10, 20, 30, 15, 25, 35]


def test_xref_classic_table_resolution():
    header = b"%PDF-1.4\n"
    obj1 = b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
    obj2 = b"2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n"
    off1 = len(header)
    off2 = off1 + len(obj1)
    xref_off = off2 + len(obj2)

    xref_sec = (
        b"xref\n0 3\n"
        b"0000000000 65535 f \n"
        + f"{off1:010d} 00000 n \n".encode("ascii")
        + f"{off2:010d} 00000 n \n".encode("ascii")
    )
    trailer = (
        b"trailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n"
        + str(xref_off).encode("ascii")
        + b"\n%%EOF"
    )

    pdf_sample = header + obj1 + obj2 + xref_sec + trailer

    resolver = XRefResolver(pdf_sample)
    resolver.parse_all_xrefs()

    assert 1 in resolver.offsets
    assert 2 in resolver.offsets

    catalog = resolver.resolve_object(resolver.trailer.get("/Root"))
    assert isinstance(catalog, dict)
    assert catalog.get("/Type") == "/Catalog"
