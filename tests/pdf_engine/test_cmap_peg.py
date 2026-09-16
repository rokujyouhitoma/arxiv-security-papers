from pdf_engine.font import ToUnicodeParser
from pdf_engine.generated_cmap_parser import PDFCMapParser


def test_cmap_bfchar_basic() -> None:
    cmap_text = b"""
    /CIDInit /ProcSet findresource begin
    12 dict begin
    begincmap
    1 beginbfchar
      <0020> <0020>
    endbfchar
    2 beginbfchar
      <0041> <0041>
      <0042> <0042>
    endbfchar
    endcmap
    """
    res = ToUnicodeParser.parse(cmap_text)
    assert res[0x20] == " "
    assert res[0x41] == "A"
    assert res[0x42] == "B"


def test_cmap_bfrange_incremental() -> None:
    cmap_text = b"""
    begincmap
    1 beginbfrange
      <0030> <0039> <0030>
    endbfrange
    endcmap
    """
    res = ToUnicodeParser.parse(cmap_text)
    for i in range(10):
        code = 0x30 + i
        assert res[code] == chr(0x30 + i)


def test_cmap_bfrange_array() -> None:
    cmap_text = b"""
    begincmap
    1 beginbfrange
      <0001> <0003> [ <0061> <0062> <0063> ]
    endbfrange
    endcmap
    """
    res = ToUnicodeParser.parse(cmap_text)
    assert res[1] == "a"
    assert res[2] == "b"
    assert res[3] == "c"


def test_cmap_comments_and_surrounding_junk() -> None:
    cmap_text = b"""
    % PDF CMap File Header Comment
    /CIDInit /ProcSet findresource begin
    12 dict begin
    begincmap
    /CIDSystemInfo <<
      /Registry (Adobe)
      /Ordering (UCS)
      /Supplement 0
    >> def
    /CMapName /Adobe-Identity-UCS def
    /CMapType 2 def
    1 begincodespacerange
      <0000> <FFFF>
    endcodespacerange
    1 beginbfchar
      <00A9> <00A9> % copyright sign
    endbfchar
    endcmap
    CMapName currentdict /CMap defineresource pop
    end
    end
    """
    res = ToUnicodeParser.parse(cmap_text)
    assert res[0xA9] == "©"


def test_cmap_empty_and_corrupt() -> None:
    assert ToUnicodeParser.parse(b"") == {}
    assert ToUnicodeParser.parse(b"just random bytes without cmap keywords") == {}
    assert ToUnicodeParser.parse(b"beginbfchar incomplete syntax") == {}


def test_cmap_direct_parser_instance() -> None:
    parser = PDFCMapParser()
    data = """
    beginbfchar
      <0048> <0048>
      <0069> <0069>
    endbfchar
    """
    res = parser.parse(data)
    assert res == {0x48: "H", 0x69: "i"}
