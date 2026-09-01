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

    def _skip_comment_line(self) -> None:
        while self.pos < self.length and self.data[self.pos] not in (10, 13):
            self.pos += 1

    def skip_whitespace_and_comments(self) -> None:
        """Skips ASCII whitespaces and comments (% ... line end)."""
        while self.pos < self.length:
            b = self.data[self.pos]
            if b in WHITESPACE:
                self.pos += 1
            elif b == ord("%"):
                self._skip_comment_line()
            else:
                break

    def _match_dict_delimiter(self) -> Optional[Tuple[TokenType, str]]:
        if self.data.startswith(b"<<", self.pos):
            self.pos += 2
            return (TokenType.DICT_START, "<<")
        if self.data.startswith(b">>", self.pos):
            self.pos += 2
            return (TokenType.DICT_END, ">>")
        return None

    def _match_array_delimiter(self, b: int) -> Optional[Tuple[TokenType, str]]:
        if b == ord("["):
            self.pos += 1
            return (TokenType.ARRAY_START, "[")
        if b == ord("]"):
            self.pos += 1
            return (TokenType.ARRAY_END, "]")
        return None

    def _match_complex_token(self, b: int) -> Optional[Tuple[TokenType, Any]]:
        if b == ord("("):
            return self._scan_literal_string()
        if b == ord("<"):
            return self._scan_hex_string()
        if b == ord("/"):
            return self._scan_name()
        return None

    def next_token(self) -> Optional[Tuple[TokenType, Any]]:
        """Extracts the next lexical token from the stream."""
        self.skip_whitespace_and_comments()
        if self.pos >= self.length:
            return None

        d_tok = self._match_dict_delimiter()
        if d_tok:
            return d_tok

        b = self.data[self.pos]
        a_tok = self._match_array_delimiter(b)
        if a_tok:
            return a_tok

        c_tok = self._match_complex_token(b)
        return c_tok if c_tok else self._scan_keyword_or_number()

    def _handle_literal_escape(self, out: bytearray) -> None:
        self.pos += 1
        if self.pos < self.length:
            out.extend(self._decode_escape_seq())

    def _process_literal_char(self, b: int, depth: int, out: bytearray) -> int:
        if b == ord("\\"):
            self._handle_literal_escape(out)
            return depth
        if b == ord("("):
            self.pos += 1
            out.append(b)
            return depth + 1
        if b == ord(")"):
            self.pos += 1
            if depth > 1:
                out.append(b)
            return depth - 1
        self.pos += 1
        out.append(b)
        return depth

    def _scan_literal_string(self) -> Tuple[TokenType, bytes]:
        self.pos += 1  # Skip opening '('
        out = bytearray()
        depth = 1
        while self.pos < self.length and depth > 0:
            b = self.data[self.pos]
            depth = self._process_literal_char(b, depth, out)
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
        while (
            self.pos < self.length
            and len(octal_bytes) < 3
            and ord("0") <= self.data[self.pos] <= ord("7")
        ):
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

    def _parse_word_val(self, word: str) -> Tuple[TokenType, Any]:
        keyword_map = {"true": True, "false": False, "null": None}
        if word in keyword_map:
            return (TokenType.KEYWORD, keyword_map[word])
        try:
            val = float(word) if "." in word else int(word)
            return (TokenType.NUMBER, val)
        except ValueError:
            return (TokenType.KEYWORD, word)

    def _scan_keyword_or_number(self) -> Tuple[TokenType, Any]:
        start = self.pos
        while (
            self.pos < self.length
            and self.data[self.pos] not in WHITESPACE
            and self.data[self.pos] not in DELIMITERS
        ):
            self.pos += 1
        word = self.data[start : self.pos].decode("latin1", errors="replace")
        return self._parse_word_val(word)


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
        return val

    def _is_valid_gen_tok(self, tok: Optional[Tuple[TokenType, Any]]) -> bool:
        return bool(tok and tok[0] == TokenType.NUMBER and isinstance(tok[1], int))

    def _check_indirect_sequence(self, first_num: int) -> Optional[IndirectRef]:
        tok2 = self.lexer.next_token()
        if not self._is_valid_gen_tok(tok2):
            return None
        tok3 = self.lexer.next_token()
        if tok3 == (TokenType.KEYWORD, "R"):
            return IndirectRef(obj_num=first_num, gen_num=tok2[1])  # type: ignore[index]
        return None

    def _resolve_potential_indirect_ref(self, first_num: Union[int, float]) -> Any:
        """Checks if a sequence of two integers followed by 'R' forms an IndirectRef."""
        if not isinstance(first_num, int):
            return first_num

        saved_pos = self.lexer.pos
        ref = self._check_indirect_sequence(first_num)
        if ref is not None:
            return ref

        self.lexer.pos = saved_pos
        return first_num

    def _parse_dict_entry(self, result: Dict[str, Any]) -> bool:
        self.lexer.skip_whitespace_and_comments()
        if self.lexer.data.startswith(b">>", self.lexer.pos):
            self.lexer.pos += 2
            return False
        tok = self.lexer.next_token()
        if tok is None or tok[0] == TokenType.DICT_END:
            return False
        if tok[0] == TokenType.NAME:
            key = str(tok[1])
            result[key] = self.parse_object()
        return True

    def _parse_dictionary(self) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        while self._parse_dict_entry(result):
            pass
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
