"""Hand-written recursive descent S-expression Reader with Source Maps.

This module provides a deterministic, zero-dependency Tokenizer and Reader
for Kernel ILISP, recording SourceLocation metadata and supporting standard
Scheme reader macros (', `, ,, ,@, #;).
"""

from __future__ import annotations

from typing import Any, List, Optional

from ilisp.types import NIL, Cons, SourceLocation, Symbol


class LispSyntaxError(Exception):
    """Exception raised when an invalid S-expression is encountered."""

    def __init__(self, message: str, loc: Optional[SourceLocation] = None) -> None:
        self.message = message
        self.loc = loc
        loc_str = f" at {loc}" if loc else ""
        super().__init__(f"{message}{loc_str}")


class Token:
    """Lexical token produced by Tokenizer."""

    __slots__ = ("kind", "value", "loc")

    def __init__(self, kind: str, value: Any, loc: SourceLocation) -> None:
        self.kind = kind
        self.value = value
        self.loc = loc

    def __repr__(self) -> str:
        return f"Token({self.kind}, {self.value!r}, {self.loc})"


class Reader:
    """Hand-written recursive descent parser for S-expressions."""

    def __init__(self, text: str, filename: str = "<stdin>") -> None:
        self.text: str = text
        self.filename: str = filename
        self.pos: int = 0
        self.line: int = 1
        self.col: int = 1

    def _current_loc(self) -> SourceLocation:
        return SourceLocation(self.filename, self.line, self.col)

    def _peek_char(self) -> Optional[str]:
        if self.pos < len(self.text):
            return self.text[self.pos]
        return None

    def _next_char(self) -> Optional[str]:
        if self.pos < len(self.text):
            ch = self.text[self.pos]
            self.pos += 1
            if ch == "\n":
                self.line += 1
                self.col = 1
            else:
                self.col += 1
            return ch
        return None

    def _skip_whitespace_and_comments(self) -> None:
        while self.pos < len(self.text):
            ch = self.text[self.pos]
            if ch in " \t\r\n":
                self._next_char()
            elif ch == ";":
                # Line comment
                while self.pos < len(self.text) and self.text[self.pos] != "\n":
                    self._next_char()
                if self.pos < len(self.text) and self.text[self.pos] == "\n":
                    self._next_char()
            elif (
                ch == "#"
                and self.pos + 1 < len(self.text)
                and self.text[self.pos + 1] == ";"
            ):
                # S-expression comment: discard the next S-expression
                self._next_char()  # '#'
                self._next_char()  # ';'
                self.read()  # parse and discard
            else:
                break

    def read(self) -> Any:
        """Read and return the next single S-expression, or EOF marker if end reached."""
        self._skip_whitespace_and_comments()
        loc = self._current_loc()
        ch = self._peek_char()
        if ch is None:
            return EOF

        # Parenthesized list
        if ch == "(":
            self._next_char()
            return self._read_list(loc)

        if ch == ")":
            self._next_char()
            raise LispSyntaxError("Unexpected closing parenthesis ')'", loc)

        # Reader macros
        if ch == "'":
            self._next_char()
            datum = self.read()
            return Cons(Symbol.intern("quote"), Cons(datum, NIL, loc=loc), loc=loc)

        if ch == "`":
            self._next_char()
            datum = self.read()
            return Cons(Symbol.intern("quasiquote"), Cons(datum, NIL, loc=loc), loc=loc)

        if ch == ",":
            self._next_char()
            if self._peek_char() == "@":
                self._next_char()
                datum = self.read()
                return Cons(
                    Symbol.intern("unquote-splicing"),
                    Cons(datum, NIL, loc=loc),
                    loc=loc,
                )
            datum = self.read()
            return Cons(Symbol.intern("unquote"), Cons(datum, NIL, loc=loc), loc=loc)

        # String literal
        if ch == '"':
            return self._read_string(loc)

        # Hash literals: #t, #f, #\char
        if ch == "#":
            return self._read_hash_literal(loc)

        # Atom (Number or Symbol)
        return self._read_atom(loc)

    def _read_string(self, loc: SourceLocation) -> str:
        self._next_char()  # consume opening '"'
        chars: List[str] = []
        while True:
            ch = self._next_char()
            if ch is None:
                raise LispSyntaxError("Unterminated string literal", loc)
            if ch == '"':
                break
            if ch == "\\":
                esc = self._next_char()
                if esc == "n":
                    chars.append("\n")
                elif esc == "t":
                    chars.append("\t")
                elif esc == "r":
                    chars.append("\r")
                elif esc == '"':
                    chars.append('"')
                elif esc == "\\":
                    chars.append("\\")
                elif esc is None:
                    raise LispSyntaxError("Unterminated string escape sequence", loc)
                else:
                    chars.append(esc)
            else:
                chars.append(ch)
        return "".join(chars)

    def _read_hash_literal(self, loc: SourceLocation) -> Any:
        self._next_char()  # consume '#'
        ch = self._peek_char()
        if ch == "t" or ch == "T":
            self._next_char()
            return True
        if ch == "f" or ch == "F":
            self._next_char()
            return False
        if ch == "\\":
            self._next_char()  # consume '\'
            return self._read_char_literal(loc)
        if ch == "(":
            self._next_char()  # consume '('
            return self._read_vector(loc)
        raise LispSyntaxError(f"Unsupported hash literal sequence '#{ch}'", loc)

    def _read_vector(self, loc: SourceLocation) -> Any:
        elements: List[Any] = []
        while True:
            self._skip_whitespace_and_comments()
            ch = self._peek_char()
            if ch is None:
                raise LispSyntaxError("Unclosed vector '#('", loc)
            if ch == ")":
                self._next_char()
                break
            elements.append(self.read())
        from ilisp.types import Vector

        return Vector(elements)

    def _read_char_literal(self, loc: SourceLocation) -> str:
        # Character literal, e.g. #\a, #\space, #\newline
        name_chars: List[str] = []
        while self.pos < len(self.text):
            ch = self.text[self.pos]
            if ch in " \t\r\n();\"'`":
                break
            name_chars.append(self._next_char() or "")
        name = "".join(name_chars)
        if not name:
            raise LispSyntaxError("Empty character literal", loc)
        if len(name) == 1:
            return name
        lower = name.lower()
        if lower == "space":
            return " "
        if lower == "newline":
            return "\n"
        if lower == "tab":
            return "\t"
        if lower == "return":
            return "\r"
        raise LispSyntaxError(f"Unknown named character literal '#\\{name}'", loc)

    def _read_atom(self, loc: SourceLocation) -> Any:
        token_chars: List[str] = []
        while self.pos < len(self.text):
            ch = self.text[self.pos]
            if ch in " \t\r\n();\"'`":
                break
            token_chars.append(self._next_char() or "")
        token = "".join(token_chars)
        if not token:
            raise LispSyntaxError("Unexpected empty token", loc)

        # Number parsing
        # Try integer
        try:
            if token.startswith("0x") or token.startswith("0X"):
                return int(token, 16)
            return int(token)
        except ValueError:
            pass

        # Try float
        try:
            return float(token)
        except ValueError:
            pass

        # Otherwise intern as Symbol
        return Symbol.intern(token)

    def _read_list(self, loc: SourceLocation) -> Any:
        elements: List[Any] = []
        is_dotted = False
        dotted_cdr: Any = NIL

        while True:
            self._skip_whitespace_and_comments()
            ch = self._peek_char()
            if ch is None:
                raise LispSyntaxError("Unclosed parenthesis '('", loc)
            if ch == ")":
                self._next_char()
                break
            if ch == ".":
                # Check if it's a dot separator or symbol starting with dot
                save_pos = self.pos
                save_line = self.line
                save_col = self.col
                self._next_char()  # consume '.'
                next_ch = self._peek_char()
                if next_ch is not None and next_ch in " \t\r\n();\"'`":
                    # Dotted pair
                    if is_dotted:
                        raise LispSyntaxError(
                            "Multiple '.' in pair expression", self._current_loc()
                        )
                    if not elements:
                        raise LispSyntaxError(
                            "Unexpected '.' at start of list", self._current_loc()
                        )
                    is_dotted = True
                    dotted_cdr = self.read()
                    self._skip_whitespace_and_comments()
                    close_ch = self._peek_char()
                    if close_ch != ")":
                        raise LispSyntaxError(
                            "Expected ')' after dotted pair cdr", self._current_loc()
                        )
                    self._next_char()
                    break
                else:
                    # Symbol starting with dot (e.g. .ident)
                    self.pos = save_pos
                    self.line = save_line
                    self.col = save_col

            elem = self.read()
            elements.append(elem)

        # Construct Cons chain
        result: Any = dotted_cdr if is_dotted else NIL
        for item in reversed(elements):
            result = Cons(item, result, loc=loc)
        return result


class EOFType:
    """Marker indicating end-of-file for reader."""

    def __repr__(self) -> str:
        return "#<eof>"


EOF = EOFType()


def read_one(text: str, filename: str = "<stdin>") -> Any:
    """Read a single S-expression from string."""
    reader = Reader(text, filename=filename)
    return reader.read()


def read_all(text: str, filename: str = "<stdin>") -> List[Any]:
    """Read all S-expressions from string until EOF."""
    reader = Reader(text, filename=filename)
    results: List[Any] = []
    while True:
        datum = reader.read()
        if datum is EOF:
            break
        results.append(datum)
    return results
