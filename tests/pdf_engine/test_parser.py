"""Unit tests for PDF Lexer and Object Parser."""

from pdf_engine.contracts import IndirectRef, TokenType
from pdf_engine.parser import PdfLexer, PdfParser


def test_pdf_lexer_tokens():
    raw = b"12 34.5 /Font (Hello \\(World\\)) <48656C6C6F> [ 1 2 ] << /Type /Page >> true false null"
    lexer = PdfLexer(raw)

    tok1 = lexer.next_token()
    assert tok1 == (TokenType.NUMBER, 12)

    tok2 = lexer.next_token()
    assert tok2 == (TokenType.NUMBER, 34.5)

    tok3 = lexer.next_token()
    assert tok3 == (TokenType.NAME, "/Font")

    tok4 = lexer.next_token()
    assert tok4 == (TokenType.STRING_LITERAL, b"Hello (World)")

    tok5 = lexer.next_token()
    assert tok5 == (TokenType.STRING_HEX, b"Hello")

    tok6 = lexer.next_token()
    assert tok6 == (TokenType.ARRAY_START, "[")


def test_pdf_parser_complex_structure():
    raw = b"""
    <<
      /Type /Page
      /Contents [ 12 0 R 13 0 R ]
      /MediaBox [ 0 0 612 792 ]
      /Resources <<
        /Font << /F1 10 0 R >>
      >>
      /Rotate 0
    >>
    """
    parser = PdfParser(raw)
    res = parser.parse_object()

    assert isinstance(res, dict)
    assert res.get("/Type") == "/Page"
    assert res.get("/Contents") == [IndirectRef(12, 0), IndirectRef(13, 0)]
    assert res.get("/MediaBox") == [0, 0, 612, 792]
    assert res.get("/Resources") == {"/Font": {"/F1": IndirectRef(10, 0)}}
    assert res.get("/Rotate") == 0
