"""
Unit tests for PDF Parser, XRef, and Navigator hardening.
Conforms to ISO 32000-1 Clause 7.3 & 7.5.
"""

from pdf_engine.contracts import IndirectRef, PdfStream, TokenType
from pdf_engine.navigator import PageTreeNavigator
from pdf_engine.parser import PdfLexer
from pdf_engine.xref import XRefResolver


def test_lexer_line_continuation_escape() -> None:
    # Test line continuation: backslash followed by \r\n and \n
    data_crlf = b"(Hello \\\r\nWorld)"
    lexer_crlf = PdfLexer(data_crlf)
    tok_crlf = lexer_crlf.next_token()
    assert tok_crlf == (TokenType.STRING_LITERAL, b"Hello World")

    data_lf = b"(Hello \\\nWorld)"
    lexer_lf = PdfLexer(data_lf)
    tok_lf = lexer_lf.next_token()
    assert tok_lf == (TokenType.STRING_LITERAL, b"Hello World")


def test_lexer_octal_overflow_modulo() -> None:
    # \400 = 256 in decimal -> modulo 256 is 0 (b'\x00')
    data = b"(\\400)"
    lexer = PdfLexer(data)
    tok = lexer.next_token()
    assert tok == (TokenType.STRING_LITERAL, b"\x00")


def test_lexer_hex_string_sanitization() -> None:
    # Hex string with whitespace, null bytes and garbage
    data = b"< 48 65 \x00 6c 6c 6f >"
    lexer = PdfLexer(data)
    tok = lexer.next_token()
    assert tok == (TokenType.STRING_HEX, b"Hello")


def test_xref_indirect_stream_length() -> None:
    # PDF snippet with stream where /Length is an IndirectRef (2 0 R)
    data = (
        b"%PDF-1.4\n"
        b"1 0 obj\n<< /Length 2 0 R >>\nstream\nHello World\nendstream\nendobj\n"
        b"2 0 obj\n11\nendobj\n"
        b"xref\n0 3\n0000000000 65535 f \n0000000009 00000 n \n0000000072 00000 n \n"
        b"trailer\n<< /Size 3 >>\nstartxref\n91\n%%EOF"
    )
    xref = XRefResolver(data)
    xref.parse_all_xrefs()
    stream_obj = xref.resolve_object(IndirectRef(1, 0))
    assert isinstance(stream_obj, PdfStream)
    assert stream_obj.data == b"Hello World"


def test_navigator_resolves_array_contents_streams() -> None:
    # Fake PDF data where page /Contents is [10 0 R, 20 0 R]
    data = (
        b"%PDF-1.4\n"
        b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
        b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
        b"3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents [10 0 R 20 0 R] >>\nendobj\n"
        b"10 0 obj\n<< /Length 5 >>\nstream\nPart1\nendstream\nendobj\n"
        b"20 0 obj\n<< /Length 5 >>\nstream\nPart2\nendstream\nendobj\n"
    )
    xref = XRefResolver(data)
    for obj_num in (1, 2, 3, 10, 20):
        marker = f"{obj_num} 0 obj".encode("ascii")
        xref.offsets[obj_num] = data.find(marker)
    xref.trailer["/Root"] = IndirectRef(1, 0)

    nav = PageTreeNavigator(xref)
    pages = nav.extract_all_pages()
    assert len(pages) == 1
    p = pages[0]
    assert len(p.contents) == 2
    assert p.contents[0] == b"Part1"
    assert p.contents[1] == b"Part2"
