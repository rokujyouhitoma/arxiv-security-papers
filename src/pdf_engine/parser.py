"""PDF Binary Lexer and Object Parser conforming to ISO 32000-1 Clause 7.2 & 7.3."""

import re
from typing import Any, Dict, List, Optional, Tuple, Union

from .contracts import IndirectRef, TokenType

WHITESPACE = b"\x00\x09\x0a\x0c\x0d\x20"
DELIMITERS = b"()<>[]{}/%"


class PdfLexer:
    """Zero-copy lexical scanner for PDF binary byte streams."""

    def __init__(self, data: bytes) -> None:
        self.data = data
        self.length = len(data)
        self.pos = 0

    def skip_whitespace_and_comments(self) -> None:
        """Skips ASCII whitespaces and comments (% ... line end)."""
        while self.pos < self.length:
            b = self.data[self.pos]
            if b in WHITESPACE:
                self.pos += 1
            elif b == ord("%"):
                # Skip until end of line (\r or \n)
                while self.pos < self.length and self.data[self.pos] not in (10, 13):
                    self.pos += 1
            else:
                break

    def next_token(self) -> Optional[Tuple[TokenType, Any]]:
        """Extracts the next lexical token from the stream."""
        self.skip_whitespace_and_comments()
        if self.pos >= self.length:
            return None

        b = self.data[self.pos]

        # 1. Dictionaries << >>
        if self.data.startswith(b"<<", self.pos):
            self.pos += 2
            return (TokenType.DICT_START, "<<")
        if self.data.startswith(b">>", self.pos):
            self.pos += 2
            return (TokenType.DICT_END, ">>")

        # 2. Arrays [ ]
        if b == ord("["):
            self.pos += 1
            return (TokenType.ARRAY_START, "[")
        if b == ord("]"):
            self.pos += 1
            return (TokenType.ARRAY_END, "]")

        # 3. Literal Strings (...)
        if b == ord("("):
            return self._scan_literal_string()

        # 4. Hexadecimal Strings <...>
        if b == ord("<"):
            return self._scan_hex_string()

        # 5. Names /Name
        if b == ord("/"):
            return self._scan_name()

        # 6. Numbers or Keywords
        return self._scan_keyword_or_number()

    def _scan_literal_string(self) -> Tuple[TokenType, bytes]:
        self.pos += 1  # Skip opening '('
        out = bytearray()
        depth = 1
        while self.pos < self.length and depth > 0:
            b = self.data[self.pos]
            if b == ord("\\"):
                self.pos += 1
                if self.pos < self.length:
                    escaped_byte = self._decode_escape_seq()
                    out.extend(escaped_byte)
            elif b == ord("("):
                depth += 1
                out.append(b)
                self.pos += 1
            elif b == ord(")"):
                depth -= 1
                if depth > 0:
                    out.append(b)
                self.pos += 1
            else:
                out.append(b)
                self.pos += 1
        return (TokenType.STRING_LITERAL, bytes(out))

    def _decode_escape_seq(self) -> bytes:
        eb = self.data[self.pos]
        escape_map = {
            ord("n"): b"\n",
            ord("r"): b"\r",
            ord("t"): b"\t",
            ord("b"): b"\b",
            ord("f"): b"\f",
            ord("("): b"(",
            ord(")"): b")",
            ord("\\"): b"\\",
        }
        if eb in escape_map:
            self.pos += 1
            return escape_map[eb]

        if ord("0") <= eb <= ord("7"):
            return self._decode_octal_escape()

        self.pos += 1
        return bytes([eb])

    def _decode_octal_escape(self) -> bytes:
        octal_bytes = bytearray()
        while self.pos < self.length and len(octal_bytes) < 3 and ord("0") <= self.data[self.pos] <= ord("7"):
            octal_bytes.append(self.data[self.pos])
            self.pos += 1
        return bytes([int(octal_bytes.decode("ascii"), 8)])

    def _scan_hex_string(self) -> Tuple[TokenType, bytes]:
        self.pos += 1  # Skip '<'
        end_idx = self.data.find(b">", self.pos)
        if end_idx == -1:
            end_idx = self.length
        raw_hex = self.data[self.pos : end_idx]
        self.pos = min(end_idx + 1, self.length)

        cleaned = re.sub(rb"\s+", b"", raw_hex)
        if len(cleaned) % 2 != 0:
            cleaned += b"0"
        try:
            return (
                TokenType.STRING_HEX,
                bytes.fromhex(cleaned.decode("ascii", errors="ignore")),
            )
        except ValueError:
            return (TokenType.STRING_HEX, b"")

    def _scan_name(self) -> Tuple[TokenType, str]:
        self.pos += 1  # Skip '/'
        start = self.pos
        while (
            self.pos < self.length
            and self.data[self.pos] not in WHITESPACE
            and self.data[self.pos] not in DELIMITERS
        ):
            self.pos += 1
        raw_name = self.data[start : self.pos].decode("latin1", errors="replace")
        # Handle ISO 32000-1 #XX hex escape in Name objects
        decoded_name = re.sub(
            r"#([0-9A-Fa-f]{2})",
            lambda m: chr(int(m.group(1), 16)),
            raw_name,
        )
        return (TokenType.NAME, "/" + decoded_name)

    def _scan_keyword_or_number(self) -> Tuple[TokenType, Any]:
        start = self.pos
        while (
            self.pos < self.length
            and self.data[self.pos] not in WHITESPACE
            and self.data[self.pos] not in DELIMITERS
        ):
            self.pos += 1
        word = self.data[start : self.pos].decode("latin1", errors="replace")

        if word == "true":
            return (TokenType.KEYWORD, True)
        if word == "false":
            return (TokenType.KEYWORD, False)
        if word == "null":
            return (TokenType.KEYWORD, None)

        try:
            if "." in word:
                return (TokenType.NUMBER, float(word))
            return (TokenType.NUMBER, int(word))
        except ValueError:
            return (TokenType.KEYWORD, word)


class PdfParser:
    """Recursive-descent object parser constructing Python AST from PDF streams."""

    def __init__(self, data: bytes) -> None:
        self.lexer = PdfLexer(data)

    def parse_object(self) -> Any:
        """Parses a single atomic or composite PDF object."""
        tok = self.lexer.next_token()
        if tok is None:
            return None

        ttype, val = tok
        if ttype == TokenType.NUMBER:
            return self._resolve_potential_indirect_ref(val)
        if ttype == TokenType.DICT_START:
            return self._parse_dictionary()
        if ttype == TokenType.ARRAY_START:
            return self._parse_array()
        if ttype in (
            TokenType.STRING_LITERAL,
            TokenType.STRING_HEX,
            TokenType.NAME,
            TokenType.KEYWORD,
        ):
            return val
        return None

    def _resolve_potential_indirect_ref(self, first_num: Union[int, float]) -> Any:
        """Checks if a sequence of two integers followed by 'R' forms an IndirectRef."""
        if not isinstance(first_num, int):
            return first_num

        saved_pos = self.lexer.pos
        tok2 = self.lexer.next_token()
        if tok2 and tok2[0] == TokenType.NUMBER and isinstance(tok2[1], int):
            tok3 = self.lexer.next_token()
            if tok3 and tok3[0] == TokenType.KEYWORD and tok3[1] == "R":
                return IndirectRef(obj_num=first_num, gen_num=tok2[1])

        self.lexer.pos = saved_pos
        return first_num

    def _parse_dictionary(self) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        while True:
            self.lexer.skip_whitespace_and_comments()
            if self.lexer.data.startswith(b">>", self.lexer.pos):
                self.lexer.pos += 2
                break
            tok = self.lexer.next_token()
            if tok is None or tok[0] == TokenType.DICT_END:
                break
            if tok[0] != TokenType.NAME:
                continue
            key = str(tok[1])
            val = self.parse_object()
            result[key] = val
        return result

    def _parse_array(self) -> List[Any]:
        result: List[Any] = []
        while True:
            self.lexer.skip_whitespace_and_comments()
            if self.lexer.pos < self.lexer.length and self.lexer.data[
                self.lexer.pos
            ] == ord("]"):
                self.lexer.pos += 1
                break
            val = self.parse_object()
            if val is None:
                break
            result.append(val)
        return result
