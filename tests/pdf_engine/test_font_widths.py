"""
Unit tests for PDF Font /Widths array decoding and accurate space inference.
Conforms to ISO 32000-1 Clause 9.6.2.1.
"""

from pdf_engine.contracts import GlyphBox, PdfPage
from pdf_engine.font import FontDecoder
from pdf_engine.interpreter import TextInterpreter
from pdf_engine.layout import SpatialLayoutEngine, _should_insert_space


def test_font_decoder_widths_parsing() -> None:
    font_dict = {
        "/FirstChar": 65,  # 'A'
        "/LastChar": 67,  # 'C'
        "/Widths": [700, 650, 720],
        "/BaseFont": "/Times-Roman",
    }
    decoder = FontDecoder(font_dict)
    assert decoder.first_char == 65
    assert decoder.last_char == 67
    assert decoder.widths == [700.0, 650.0, 720.0]

    # Char 'A' (65): 700 / 1000 * 10pt = 7.0
    assert abs(decoder.get_char_width(65, font_size=10.0) - 7.0) < 1e-5
    # Char 'B' (66): 650 / 1000 * 10pt = 6.5
    assert abs(decoder.get_char_width(66, font_size=10.0) - 6.5) < 1e-5
    # Out of range char 'D' (68): fallback 500 / 1000 * 10pt = 5.0
    assert abs(decoder.get_char_width(68, font_size=10.0) - 5.0) < 1e-5


def test_font_decoder_text_width_calculation() -> None:
    font_dict = {
        "/FirstChar": 65,
        "/LastChar": 66,
        "/Widths": [500, 600],
    }
    decoder = FontDecoder(font_dict)
    # "AB" -> 65 (500) + 66 (600) = 1100 / 1000 * 12pt = 13.2
    assert abs(decoder.get_text_width(b"AB", font_size=12.0) - 13.2) < 1e-5
    # Empty bytes
    assert decoder.get_text_width(b"", font_size=12.0) == 0.0


def test_font_decoder_courier_monospace_fallback() -> None:
    font_dict = {"/BaseFont": "/Courier-Bold"}
    decoder = FontDecoder(font_dict)
    # Courier fallback 600 / 1000 * 10pt = 6.0
    assert abs(decoder.get_char_width(65, font_size=10.0) - 6.0) < 1e-5


def test_font_decoder_cid_width() -> None:
    to_unicode = {0x0041: "A", 0x0042: "B", 0x3042: "あ"}
    font_dict = {
        "/FirstChar": 0x0041,
        "/LastChar": 0x0042,
        "/Widths": [500, 600],
    }
    decoder = FontDecoder(font_dict, to_unicode_map=to_unicode)
    # CID 0x0041: 500 -> 5.0 at 10pt
    raw = (0x0041).to_bytes(2, "big")
    assert abs(decoder.get_text_width(raw, font_size=10.0) - 5.0) < 1e-5


def test_interpreter_renders_accurate_widths_and_spacing() -> None:
    font_dict = {
        "/FirstChar": ord("a"),
        "/LastChar": ord("z"),
        "/Widths": [500.0] * 26,
    }
    decoder = FontDecoder(font_dict)
    page = PdfPage(
        page_num=1,
        width=612.0,
        height=792.0,
        resources={"_font_decoders": {"/F1": decoder}},
        contents=[b"BT /F1 10 Tf 100 700 Td (hello) Tj ET"],
    )
    interpreter = TextInterpreter(page)
    glyphs = interpreter.extract_glyphs()
    assert len(glyphs) == 1
    g = glyphs[0]
    assert g.text == "hello"
    # 5 chars * (500/1000 * 10) = 25.0
    assert abs(g.width - 25.0) < 1e-5
    # Ending tm[4] should be 100 + 25 = 125.0
    assert abs(interpreter.tm[4] - 125.0) < 1e-5


def test_should_insert_space_with_accurate_widths() -> None:
    # Glyph 1: "secu", x=100, width=20, font_size=10
    g1 = GlyphBox(
        text="secu",
        x=100.0,
        y=500.0,
        width=20.0,
        height=10.0,
        font_size=10.0,
        font_name="F1",
    )
    # Glyph 2: "rity", x=120.5 (gap = 0.5 < 1.8), should NOT insert space
    g2 = GlyphBox(
        text="rity",
        x=120.5,
        y=500.0,
        width=20.0,
        height=10.0,
        font_size=10.0,
        font_name="F1",
    )
    assert not _should_insert_space(g1, g2)

    # Glyph 3: "paper", x=143.0 (gap = 2.5 >= 1.8), SHOULD insert space
    g3 = GlyphBox(
        text="paper",
        x=143.0,
        y=500.0,
        width=25.0,
        height=10.0,
        font_size=10.0,
        font_name="F1",
    )
    assert _should_insert_space(g2, g3)

    # Render line with SpatialLayoutEngine
    rendered = SpatialLayoutEngine.reconstruct([g1, g2, g3], 612.0, 792.0)
    assert "security paper" in rendered
