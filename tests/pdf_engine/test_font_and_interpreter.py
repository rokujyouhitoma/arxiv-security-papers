"""Unit tests for Font decoders, ToUnicode CMap, and TextInterpreter."""

from pdf_engine.contracts import PdfPage
from pdf_engine.font import FontDecoder, ToUnicodeParser
from pdf_engine.interpreter import TextInterpreter


def test_tounicode_cmap_parsing():
    cmap_sample = b"""
    /CIDInit /ProcSet findresource begin
    12 dict begin
    beginbfchar
      <0001> <0041>
      <0002> <0042>
    endbfchar
    beginbfrange
      <0003> <0005> <0043>
    endbfrange
    end
    """
    mapping = ToUnicodeParser.parse(cmap_sample)
    assert mapping[1] == "A"
    assert mapping[2] == "B"
    assert mapping[3] == "C"
    assert mapping[4] == "D"
    assert mapping[5] == "E"


def test_font_decoder_ligature_normalization():
    to_unicode = {1: "\ufb01", 2: "\ufb02"}  # fi, fl
    decoder = FontDecoder(font_dict={}, to_unicode_map=to_unicode)

    decoded = decoder.decode_bytes(bytes([1, 2]))
    assert decoded == "fifl"


def test_text_interpreter_operators():
    content_stream = b"""
    BT
      /F1 12 Tf
      100 200 Td
      (Hello) Tj
      0 -14 Td
      (World) Tj
    ET
    """
    page = PdfPage(
        page_num=1,
        width=612.0,
        height=792.0,
        contents=[content_stream],
        resources={},
    )
    interpreter = TextInterpreter(page)
    glyphs = interpreter.extract_glyphs()

    assert len(glyphs) == 2
    assert glyphs[0].text == "Hello"
    assert glyphs[0].x == 100.0
    assert glyphs[0].y == 200.0

    assert glyphs[1].text == "World"
    assert glyphs[1].x == 100.0
    assert glyphs[1].y == 186.0
