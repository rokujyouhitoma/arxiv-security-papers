"""Hand-written recursive descent S-expression Reader with Source Maps.

This module provides a deterministic, zero-dependency Tokenizer and Reader
for Kernel ILISP, recording SourceLocation metadata and supporting standard
Scheme reader macros (', `, ,, ,@, #;).
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, List, Optional, Union

from ilisp.types import EOF, NIL, Cons, SourceLocation, Symbol

if TYPE_CHECKING:
    from ilisp.port import TextualInputPort


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

    def __init__(
        self,
        source: Union[str, TextualInputPort],
        filename: str = "<stdin>",
    ) -> None:
        if isinstance(source, str):
            from ilisp.port import StringInputPort

            self.port: TextualInputPort = StringInputPort(source, name=filename)
            self.filename: str = filename
        else:
            self.port = source
            self.filename = source.name
        self.line: int = 1
        self.col: int = 1
        self._unread_buf: List[str] = []

    def _current_loc(self) -> SourceLocation:
        return SourceLocation(self.filename, self.line, self.col)

    def _peek_char(self) -> Optional[str]:
        if self._unread_buf:
            return self._unread_buf[-1]
        return self.port.peek_char()

    def _next_char(self) -> Optional[str]:
        ch: Optional[str]
        if self._unread_buf:
            ch = self._unread_buf.pop()
        else:
            ch = self.port.read_char()
        if ch is not None:
            if ch == "\n":
                self.line += 1
                self.col = 1
            else:
                self.col += 1
        return ch

    def _unread_char(self, ch: str) -> None:
        self._unread_buf.append(ch)
        if ch == "\n":
            self.line = max(1, self.line - 1)
            self.col = 1
        else:
            self.col = max(1, self.col - 1)

    def _skip_whitespace_and_comments(self) -> None:
        while True:
            ch = self._peek_char()
            if ch is None:
                break
            if ch in " \t\r\n":
                self._next_char()
            elif ch == ";":
                # Line comment
                while True:
                    c = self._next_char()
                    if c is None or c == "\n":
                        break
            elif ch == "#":
                hash_ch = self._next_char()  # consume '#'
                next_ch = self._peek_char()
                if next_ch == ";":
                    self._next_char()  # consume ';'
                    self.read()  # parse and discard next S-expression
                else:
                    if hash_ch is not None:
                        self._unread_char(hash_ch)
                    break
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
        if ch == "u" or ch == "U":
            self._next_char()  # consume 'u'
            next1 = self._next_char()  # expect '8'
            if next1 == "8":
                next2 = self._peek_char()
                if next2 == "(":
                    self._next_char()  # consume '('
                    return self._read_bytevector(loc)
            raise LispSyntaxError(f"Unsupported hash literal sequence '#u{next1}'", loc)
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

    def _read_bytevector(self, loc: SourceLocation) -> Any:
        elements: List[int] = []
        while True:
            self._skip_whitespace_and_comments()
            ch = self._peek_char()
            if ch is None:
                raise LispSyntaxError("Unclosed bytevector '#u8('", loc)
            if ch == ")":
                self._next_char()
                break
            elem = self.read()
            if not isinstance(elem, int) or not (0 <= elem <= 255):
                raise LispSyntaxError(
                    f"Bytevector element must be an octet (exact integer in 0..255), got {elem!r}",
                    loc,
                )
            elements.append(elem)
        from ilisp.types import Bytevector

        return Bytevector(elements)

    def _read_char_literal(self, loc: SourceLocation) -> str:
        # Character literal, e.g. #\a, #\space, #\newline
        name_chars: List[str] = []
        while True:
            ch = self._peek_char()
            if ch is None or ch in " \t\r\n();\"'`":
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
        while True:
            ch = self._peek_char()
            if ch is None or ch in " \t\r\n();\"'`":
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
                    self._unread_char(".")

            elem = self.read()
            elements.append(elem)

        # Construct Cons chain
        result: Any = dotted_cdr if is_dotted else NIL
        for item in reversed(elements):
            result = Cons(item, result, loc=loc)
        return result


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
