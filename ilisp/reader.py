"""Hand-written recursive descent S-expression Reader with Source Maps.

This module provides a deterministic, zero-dependency Tokenizer and Reader
for Kernel ILISP, recording SourceLocation metadata and supporting standard
Scheme reader macros (', `, ,, ,@, #;).
"""

from __future__ import annotations

import contextlib
import gc
import os
import re
from typing import TYPE_CHECKING, Any, Dict, Iterator, List, Optional, Tuple, Union

from ilisp.types import (
    EOF,
    NIL,
    Cons,
    ErrorObject,
    SchemeComplex,
    SchemeException,
    SourceLocation,
    Symbol,
)

if TYPE_CHECKING:
    from ilisp.port import TextualInputPort

_WS_COMMENT_RE = re.compile(r"(?:[ \t\r\n]+|;[^\n]*)+")
_SPACES_RE = re.compile(r" +")
_ATOM_RE = re.compile(r'[^ \t\r\n();"\'`]+')
_EXP_RE = re.compile(r"^([+-]?(?:\d+\.?\d*|\.\d+))[sfdl]([+-]?\d+)$")
_DELIM_CHARS = frozenset(" \t\r\n();\"'`")
_NUM_START_CHARS = frozenset("0123456789+-.nN")
_SIGN_NEXT_CHARS = frozenset("0123456789.iInN")
_DIGIT_CHARS = frozenset("0123456789")


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
        fold_case: bool = False,
    ) -> None:
        if isinstance(source, str):
            from ilisp.port import StringInputPort

            self.port: TextualInputPort = StringInputPort(source, name=filename)
            self.filename: str = filename
            self._src: Optional[str] = source
            self._pos: int = 0
            self._len: int = len(source)
            self._line_start: int = 0
        else:
            self.port = source
            self.filename = source.name
            self._src = None
            self._pos = 0
            self._len = 0
            self._line_start = 0
        self.line: int = 1
        self.col: int = 1
        self._unread_buf: List[str] = []
        self.fold_case: bool = fold_case
        self.labels: Dict[int, Any] = {}

    def _current_loc(self) -> SourceLocation:
        if self._src is not None and not self._unread_buf:
            return SourceLocation(
                self.filename, self.line, self._pos - self._line_start + 1
            )
        return SourceLocation(self.filename, self.line, self.col)

    def _sync_pos(self, new_pos: int) -> None:
        src = self._src
        pos = self._pos
        if src is not None and new_pos > pos:
            nl = src.rfind("\n", pos, new_pos)
            if nl != -1:
                self.line += src.count("\n", pos, new_pos)
                self._line_start = nl + 1
            self._pos = new_pos

    def _peek_char(self) -> Optional[str]:
        if self._unread_buf:
            return self._unread_buf[-1]
        if self._src is not None:
            return self._src[self._pos] if self._pos < self._len else None
        return self.port.peek_char()

    def _next_char(self) -> Optional[str]:
        ch: Optional[str]
        if self._unread_buf:
            ch = self._unread_buf.pop()
            if ch == "\n":
                self.line += 1
                self.col = 1
            else:
                self.col += 1
            return ch
        if self._src is not None:
            if self._pos >= self._len:
                return None
            ch = self._src[self._pos]
            self._pos += 1
            if ch == "\n":
                self.line += 1
                self._line_start = self._pos
            return ch
        ch = self.port.read_char()
        if ch is not None:
            if ch == "\n":
                self.line += 1
                self.col = 1
            else:
                self.col += 1
        return ch

    def _unread_char(self, ch: str) -> None:
        if (
            self._src is not None
            and not self._unread_buf
            and self._pos > 0
            and self._src[self._pos - 1] == ch
            and ch != "\n"
        ):
            self._pos -= 1
            return
        self._unread_buf.append(ch)
        if ch == "\n":
            self.line = max(1, self.line - 1)
            self.col = 1
        else:
            self.col = max(1, self.col - 1)

    def _skip_whitespace_and_comments(self) -> None:
        src = self._src
        if src is not None and not self._unread_buf:
            slen = self._len
            pos = self._pos
            while pos < slen:
                ch = src[pos]
                if ch in " \t\r\n;":
                    m = _WS_COMMENT_RE.match(src, pos)
                    if m is not None:
                        end_p = m.end()
                        nl = src.rfind("\n", pos, end_p)
                        if nl != -1:
                            self.line += src.count("\n", pos, end_p)
                            self._line_start = nl + 1
                        pos = end_p
                        self._pos = pos
                        continue
                if ch == "#" and pos + 1 < slen:
                    nxt = src[pos + 1]
                    if nxt == ";":
                        self._sync_pos(pos + 2)
                        self.read()
                        pos = self._pos
                        continue
                    elif nxt == "|":
                        p = pos + 2
                        depth = 1
                        while depth > 0:
                            idx_open = src.find("#|", p)
                            idx_close = src.find("|#", p)
                            if idx_close == -1:
                                self._sync_pos(slen)
                                raise LispSyntaxError(
                                    "Unterminated block comment '#|'",
                                    self._current_loc(),
                                )
                            if idx_open != -1 and idx_open < idx_close:
                                depth += 1
                                p = idx_open + 2
                            else:
                                depth -= 1
                                p = idx_close + 2
                        self._sync_pos(p)
                        pos = p
                        continue
                    elif nxt == "!":
                        p = pos + 2
                        m_dir = _ATOM_RE.match(src, p)
                        if m_dir is not None:
                            dir_name = m_dir.group(0).lower()
                            p_end = m_dir.end()
                        else:
                            dir_name = ""
                            p_end = p
                        if dir_name == "fold-case":
                            self.fold_case = True
                            self._sync_pos(p_end)
                            pos = p_end
                            continue
                        elif dir_name == "no-fold-case":
                            self.fold_case = False
                            self._sync_pos(p_end)
                            pos = p_end
                            continue
                        elif dir_name.startswith("/"):
                            nl_p = src.find("\n", p_end)
                            p_end = slen if nl_p == -1 else nl_p + 1
                            self._sync_pos(p_end)
                            pos = p_end
                            continue
                        else:
                            self._sync_pos(p_end)
                            pos = p_end
                            continue
                break
            self._pos = pos
            return

        while True:
            ch_slow = self._peek_char()
            if ch_slow is None:
                break
            if ch_slow in " \t\r\n":
                self._next_char()
            elif ch_slow == ";":
                # Line comment
                while True:
                    c = self._next_char()
                    if c is None or c == "\n":
                        break
            elif ch_slow == "#":
                hash_ch = self._next_char()  # consume '#'
                next_ch = self._peek_char()
                if next_ch == ";":
                    self._next_char()  # consume ';'
                    self.read()  # parse and discard next S-expression
                elif next_ch == "|":
                    self._next_char()  # consume '|'
                    depth = 1
                    while depth > 0:
                        c = self._next_char()
                        if c is None:
                            raise LispSyntaxError(
                                "Unterminated block comment '#|'", self._current_loc()
                            )
                        if c == "#":
                            c2 = self._peek_char()
                            if c2 == "|":
                                self._next_char()
                                depth += 1
                        elif c == "|":
                            c2 = self._peek_char()
                            if c2 == "#":
                                self._next_char()
                                depth -= 1
                elif next_ch == "!":
                    self._next_char()  # consume '!'
                    dir_chars: List[str] = []
                    while True:
                        c = self._peek_char()
                        if c is None or c in (
                            " ",
                            "\t",
                            "\r",
                            "\n",
                            "(",
                            ")",
                            '"',
                            ";",
                        ):
                            break
                        dir_chars.append(self._next_char() or "")
                    dir_name = "".join(dir_chars).lower()
                    if dir_name == "fold-case":
                        self.fold_case = True
                    elif dir_name == "no-fold-case":
                        self.fold_case = False
                    elif dir_name.startswith("/"):
                        while True:
                            c = self._next_char()
                            if c is None or c == "\n":
                                break
                else:
                    if hash_ch is not None:
                        self._unread_char(hash_ch)
                    break
            else:
                break

    def read(self) -> Any:
        """Read and return the next single S-expression, or EOF marker if end reached."""
        self._skip_whitespace_and_comments()
        src = self._src
        if src is not None and not self._unread_buf:
            pos = self._pos
            if pos >= self._len:
                return EOF
            ch = src[pos]
            if ch == "(":
                loc = SourceLocation(
                    self.filename, self.line, pos - self._line_start + 1
                )
                self._pos = pos + 1
                return self._read_list_fast(loc, pos)
            if ch == ")":
                loc = self._current_loc()
                self._pos = pos + 1
                raise LispSyntaxError("Unexpected closing parenthesis ')'", loc)
            if ch == "'":
                loc = self._current_loc()
                self._pos = pos + 1
                datum = self.read()
                return Cons(Symbol.intern("quote"), Cons(datum, NIL, loc=loc), loc=loc)
            if ch == "`":
                loc = self._current_loc()
                self._pos = pos + 1
                datum = self.read()
                return Cons(
                    Symbol.intern("quasiquote"), Cons(datum, NIL, loc=loc), loc=loc
                )
            if ch == ",":
                loc = self._current_loc()
                if pos + 1 < self._len and src[pos + 1] == "@":
                    self._pos = pos + 2
                    datum = self.read()
                    return Cons(
                        Symbol.intern("unquote-splicing"),
                        Cons(datum, NIL, loc=loc),
                        loc=loc,
                    )
                self._pos = pos + 1
                datum = self.read()
                return Cons(
                    Symbol.intern("unquote"), Cons(datum, NIL, loc=loc), loc=loc
                )
            if ch == '"':
                return self._read_string_fast()
            if ch == "|":
                return self._read_vertical_bar_symbol(self._current_loc())
            if ch == "#":
                return self._read_hash_literal(self._current_loc())
            return self._read_atom_fast()

        loc = self._current_loc()
        ch_slow = self._peek_char()
        if ch_slow is None:
            return EOF

        # Parenthesized list
        if ch_slow == "(":
            self._next_char()
            return self._read_list(loc)

        if ch_slow == ")":
            self._next_char()
            raise LispSyntaxError("Unexpected closing parenthesis ')'", loc)

        # Reader macros
        if ch_slow == "'":
            self._next_char()
            datum = self.read()
            return Cons(Symbol.intern("quote"), Cons(datum, NIL, loc=loc), loc=loc)

        if ch_slow == "`":
            self._next_char()
            datum = self.read()
            return Cons(Symbol.intern("quasiquote"), Cons(datum, NIL, loc=loc), loc=loc)

        if ch_slow == ",":
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
        if ch_slow == '"':
            return self._read_string(loc)

        # Vertical bar escaped symbol (R7RS 2.1: |...|)
        if ch_slow == "|":
            return self._read_vertical_bar_symbol(loc)

        # Hash literals: #t, #f, #\char
        if ch_slow == "#":
            return self._read_hash_literal(loc)

        # Atom (Number or Symbol)
        return self._read_atom(loc)

    def _read_string_fast(self) -> str:
        src = self._src
        assert src is not None
        pos = self._pos
        p = pos + 1
        q_idx = src.find('"', p)
        if q_idx == -1:
            raise LispSyntaxError("Unterminated string literal", self._current_loc())
        b_idx = src.find("\\", p, q_idx)
        if b_idx == -1:
            s = src[p:q_idx]
            self._sync_pos(q_idx + 1)
            return s
        return self._read_string(self._current_loc())

    def _parse_atom_token(self, token: str, loc: Optional[SourceLocation]) -> Any:
        if token == ".":
            raise LispSyntaxError(
                "Unexpected standalone '.' token",
                loc if loc is not None else self._current_loc(),
            )
        tlen = len(token)
        c0 = token[0]
        if c0 not in _NUM_START_CHARS:
            sym_name = token.lower() if self.fold_case else token
            return Symbol.intern(sym_name)
        if tlen == 1 and c0 in "+-":
            return Symbol.intern(token)
        if c0 in "+-" and tlen > 1 and token[1] not in _SIGN_NEXT_CHARS:
            sym_name = token.lower() if self.fold_case else token
            return Symbol.intern(sym_name)
        if c0 == "." and tlen > 1 and token[1] not in _DIGIT_CHARS:
            sym_name = token.lower() if self.fold_case else token
            return Symbol.intern(sym_name)

        # Number parsing
        try:
            if token.startswith("0x") or token.startswith("0X"):
                return int(token, 16)
            return int(token)
        except ValueError:
            pass

        low_tok = token.lower()
        if low_tok in ("+inf.0", "+inf"):
            return float("inf")
        if low_tok in ("-inf.0", "-inf"):
            return float("-inf")
        if low_tok in ("+nan.0", "-nan.0", "nan.0", "+nan", "-nan"):
            return float("nan")

        if "/" in token:
            parts = token.split("/")
            if len(parts) == 2:
                try:
                    num = int(parts[0])
                    den = int(parts[1])
                    if den != 0:
                        from fractions import Fraction

                        frac = Fraction(num, den)
                        return frac.numerator if frac.denominator == 1 else frac
                except ValueError:
                    pass

        m_exp = _EXP_RE.match(low_tok)
        if m_exp:
            try:
                return float(f"{m_exp.group(1)}e{m_exp.group(2)}")
            except ValueError:
                pass

        c_val = self._parse_complex(low_tok, 10)
        if c_val is not None:
            return c_val

        try:
            return float(token)
        except ValueError:
            pass

        sym_name = low_tok if self.fold_case else token
        return Symbol.intern(sym_name)

    def _read_atom_fast(self) -> Any:
        src = self._src
        assert src is not None
        m = _ATOM_RE.match(src, self._pos)
        if m is None:
            raise LispSyntaxError("Unexpected empty token", self._current_loc())
        self._pos = m.end()
        return self._parse_atom_token(m.group(0), None)

    def _read_list_fast(self, loc: SourceLocation, open_pos: int) -> Any:
        src = self._src
        assert src is not None
        slen = self._len
        elements: List[Any] = []
        is_dotted = False
        dotted_cdr: Any = NIL

        while True:
            self._skip_whitespace_and_comments()
            pos = self._pos
            if pos >= slen:
                raise LispSyntaxError("Unclosed parenthesis '('", loc)
            ch = src[pos]
            if ch == ")":
                self._pos = pos + 1
                break
            if ch == ".":
                next_p = pos + 1
                if next_p < slen and src[next_p] in _DELIM_CHARS:
                    self._pos = next_p
                    if is_dotted:
                        raise LispSyntaxError(
                            "Multiple '.' in pair expression", self._current_loc()
                        )
                    if not elements:
                        if pos == open_pos + 1:
                            elements.append(Symbol.intern("."))
                            continue
                        raise LispSyntaxError(
                            "Unexpected '.' at start of list", self._current_loc()
                        )
                    is_dotted = True
                    dotted_cdr = self.read()
                    if dotted_cdr is EOF:
                        raise LispSyntaxError(
                            "Expected cdr expression after '.' in pair",
                            self._current_loc(),
                        )
                    self._skip_whitespace_and_comments()
                    if self._pos >= slen or src[self._pos] != ")":
                        raise LispSyntaxError(
                            "Expected ')' after dotted pair cdr", self._current_loc()
                        )
                    self._pos += 1
                    break

            elements.append(self.read())

        result: Any = dotted_cdr if is_dotted else NIL
        for item in reversed(elements):
            result = Cons(item, result, loc=loc)
        return result

    def _read_vertical_bar_symbol(self, loc: SourceLocation) -> Symbol:
        self._next_char()  # consume opening '|'
        chars: List[str] = []
        while True:
            ch = self._next_char()
            if ch is None:
                raise LispSyntaxError("Unterminated vertical bar symbol '|...|'", loc)
            if ch == "|":
                break
            if ch == "\\":
                esc = self._next_char()
                if esc is None:
                    raise LispSyntaxError(
                        "Unterminated escape sequence in vertical bar symbol", loc
                    )
                if esc == "n":
                    chars.append("\n")
                elif esc == "t":
                    chars.append("\t")
                elif esc == "r":
                    chars.append("\r")
                elif esc == "|":
                    chars.append("|")
                elif esc == "\\":
                    chars.append("\\")
                elif esc == '"':
                    chars.append('"')
                elif esc == "x":
                    hex_chars: List[str] = []
                    while True:
                        hc = self._next_char()
                        if hc is None:
                            raise LispSyntaxError(
                                "Unterminated hex escape in symbol", loc
                            )
                        if hc == ";":
                            break
                        hex_chars.append(hc)
                    try:
                        chars.append(chr(int("".join(hex_chars), 16)))
                    except Exception:
                        raise LispSyntaxError(
                            f"Invalid hex escape '\\x{''.join(hex_chars)};'", loc
                        )
                else:
                    chars.append(esc)
            else:
                chars.append(ch)
        return Symbol.intern("".join(chars))

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
                elif esc == "a":
                    chars.append("\a")
                elif esc == "b":
                    chars.append("\b")
                elif esc == '"':
                    chars.append('"')
                elif esc == "\\":
                    chars.append("\\")
                elif esc == "|":
                    chars.append("|")
                elif esc == "x":
                    hex_chars: List[str] = []
                    while True:
                        hc = self._next_char()
                        if hc is None:
                            raise LispSyntaxError(
                                "Unterminated hex escape in string", loc
                            )
                        if hc == ";":
                            break
                        hex_chars.append(hc)
                    try:
                        chars.append(chr(int("".join(hex_chars), 16)))
                    except Exception:
                        raise LispSyntaxError(
                            f"Invalid hex escape '\\x{''.join(hex_chars)};'", loc
                        )
                elif esc in (" ", "\t", "\r", "\n"):
                    cur: Optional[str] = esc
                    while cur in (" ", "\t"):
                        cur = self._next_char()
                    if cur == "\r":
                        if self._peek_char() == "\n":
                            self._next_char()
                    while self._peek_char() in (" ", "\t"):
                        self._next_char()
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
        if ch == ":":
            self._next_char()  # consume ':'
            atom = self._read_atom(loc)
            if isinstance(atom, Symbol):
                return Symbol.intern(f":{atom.name}")
            return Symbol.intern(f":{atom}")
        if ch == "t" or ch == "T":
            self._next_char()
            if self._peek_char() in ("r", "R"):
                c1 = self._next_char()
                c2 = self._next_char()
                c3 = self._next_char()
                if (
                    (c1 or "").lower() == "r"
                    and (c2 or "").lower() == "u"
                    and (c3 or "").lower() == "e"
                ):
                    return True
                raise LispSyntaxError("Invalid boolean literal '#t...'", loc)
            return True
        if ch == "f" or ch == "F":
            self._next_char()
            if self._peek_char() in ("a", "A"):
                c1 = self._next_char()
                c2 = self._next_char()
                c3 = self._next_char()
                c4 = self._next_char()
                if (
                    (c1 or "").lower() == "a"
                    and (c2 or "").lower() == "l"
                    and (c3 or "").lower() == "s"
                    and (c4 or "").lower() == "e"
                ):
                    return False
                raise LispSyntaxError("Invalid boolean literal '#f...'", loc)
            return False
        if ch in ("b", "B", "o", "O", "d", "D", "x", "X", "e", "E", "i", "I"):
            tok_chars = ["#"]
            while True:
                pc = self._peek_char()
                if pc is None or pc in " \t\r\n();\"'`":
                    break
                tok_chars.append(self._next_char() or "")
            return self._parse_number_with_prefix("".join(tok_chars), loc)
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
        if ch is not None and ch.isdigit():
            num_chars = [self._next_char() or ""]
            while True:
                pk = self._peek_char()
                if pk is not None and pk.isdigit():
                    num_chars.append(self._next_char() or "")
                else:
                    break
            label_id = int("".join(num_chars))
            marker = self._next_char()
            if marker == "=":
                placeholder = Cons(None, None, loc=loc)
                self.labels[label_id] = placeholder
                datum = self.read()
                if isinstance(datum, Cons):
                    placeholder.car = datum.car
                    placeholder.cdr = datum.cdr
                    return placeholder
                else:
                    self.labels[label_id] = datum
                    return datum
            elif marker == "#":
                if label_id in self.labels:
                    return self.labels[label_id]
                raise LispSyntaxError(
                    f"Undefined datum label reference '#{label_id}#'", loc
                )
            else:
                raise LispSyntaxError(
                    f"Invalid datum label syntax '#{label_id}{marker}'", loc
                )
        raise LispSyntaxError(f"Unsupported hash literal sequence '#{ch}'", loc)

    def _parse_complex(self, num_str: str, radix: int) -> Optional[complex]:
        if not num_str.endswith("i") or num_str == "i":
            return None
        s = num_str[:-1]
        if s == "+":
            return SchemeComplex(0.0, 1.0, exact_imag=True)
        if s == "-":
            return SchemeComplex(0.0, -1.0, exact_imag=True)
        if s == "":
            return None

        def parse_part(part_str: str) -> Optional[Tuple[float, bool, Any]]:
            if not part_str:
                return None
            if part_str == "+":
                return (1.0, True, 1)
            if part_str == "-":
                return (-1.0, True, -1)
            if part_str in ("+inf.0", "+inf"):
                return (float("inf"), False, float("inf"))
            if part_str in ("-inf.0", "-inf"):
                return (float("-inf"), False, float("-inf"))
            if part_str in ("+nan.0", "-nan.0", "nan.0", "+nan", "-nan"):
                return (float("nan"), False, float("nan"))
            if "/" in part_str:
                p = part_str.split("/")
                if len(p) == 2:
                    try:
                        n = int(p[0], radix)
                        d = int(p[1], radix)
                        from fractions import Fraction

                        frac = Fraction(n, d)
                        orig = frac.numerator if frac.denominator == 1 else frac
                        return (float(orig), True, orig)
                    except (ValueError, ZeroDivisionError):
                        return None
            low = part_str.lower()
            for exp_char in ("s", "f", "d", "l"):
                if exp_char in low:
                    low = low.replace(exp_char, "e")
                    break
            try:
                if radix == 10 and ("." in low or "e" in low):
                    fval = float(low)
                    return (fval, False, fval)
                ival = int(low, radix)
                return (float(ival), "." not in part_str, ival)
            except ValueError:
                return None

        sign_idx = -1
        for idx in range(len(s) - 1, 0, -1):
            if s[idx] in ("+", "-"):
                if radix == 10 and s[idx - 1] in (
                    "e",
                    "E",
                    "s",
                    "S",
                    "f",
                    "F",
                    "d",
                    "D",
                    "l",
                    "L",
                ):
                    continue
                sign_idx = idx
                break

        if sign_idx == -1:
            res = parse_part(s)
            if res is None:
                return None
            val, exact, orig = res
            return SchemeComplex(
                0.0, val, exact_real=True, exact_imag=exact, real_val=0, imag_val=orig
            )
        else:
            real_str = s[:sign_idx]
            imag_str = s[sign_idx:]
            r_res = parse_part(real_str)
            i_res = parse_part(imag_str)
            if r_res is None or i_res is None:
                return None
            re_val, re_exact, re_orig = r_res
            im_val, im_exact, im_orig = i_res
            return SchemeComplex(
                re_val,
                im_val,
                exact_real=re_exact,
                exact_imag=im_exact,
                real_val=re_orig,
                imag_val=im_orig,
            )

    def _parse_number_with_prefix(self, token: str, loc: SourceLocation) -> Any:
        tok = token.lower()
        exactness: Optional[bool] = None
        radix = 10
        i = 0
        while i < len(tok) and tok[i] == "#":
            if i + 1 >= len(tok):
                break
            prefix = tok[i + 1]
            if prefix == "e":
                exactness = True
                i += 2
            elif prefix == "i":
                exactness = False
                i += 2
            elif prefix == "b":
                radix = 2
                i += 2
            elif prefix == "o":
                radix = 8
                i += 2
            elif prefix == "d":
                radix = 10
                i += 2
            elif prefix == "x":
                radix = 16
                i += 2
            else:
                break
        num_str = tok[i:]
        comp = self._parse_complex(num_str, radix)
        if comp is not None:
            if exactness is True:
                return SchemeComplex(
                    comp.real, comp.imag, exact_real=True, exact_imag=True
                )
            elif exactness is False:
                return SchemeComplex(
                    comp.real, comp.imag, exact_real=False, exact_imag=False
                )
            return comp
        try:
            val: Any
            if num_str in ("+inf.0", "+inf"):
                val = float("inf")
            elif num_str in ("-inf.0", "-inf"):
                val = float("-inf")
            elif num_str in ("+nan.0", "-nan.0", "nan.0", "+nan", "-nan"):
                val = float("nan")
            elif "/" in num_str:
                parts = num_str.split("/")
                if len(parts) == 2:
                    from fractions import Fraction

                    num = int(parts[0], radix)
                    den = int(parts[1], radix)
                    frac = Fraction(num, den)
                    val = frac.numerator if frac.denominator == 1 else frac
                else:
                    raise ValueError("Invalid fraction")
            elif radix == 10 and ("." in num_str or "e" in num_str):
                val = float(num_str)
            else:
                val = int(num_str, radix)
            if exactness is True and isinstance(val, float):
                val = int(round(val)) if val.is_integer() else val
            elif exactness is False:
                val = float(val)
            return val
        except ValueError:
            raise LispSyntaxError(f"Invalid numeric syntax with prefix '{token}'", loc)

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

    def _read_char_literal(self, loc: SourceLocation) -> Any:
        from ilisp.types import Char

        first_ch = self._next_char()
        if first_ch is None:
            raise LispSyntaxError("Unterminated character literal '#\\'", loc)

        next_ch = self._peek_char()
        if next_ch is None or next_ch in " \t\r\n();\"'`":
            return Char(first_ch)

        name_chars: List[str] = [first_ch]
        while True:
            ch = self._peek_char()
            if ch is None or ch in " \t\r\n();\"'`":
                break
            name_chars.append(self._next_char() or "")
        name = "".join(name_chars)

        lower = name.lower()
        if lower == "space":
            return Char(" ")
        if lower == "newline":
            return Char("\n")
        if lower == "tab":
            return Char("\t")
        if lower == "return":
            return Char("\r")
        if lower == "null":
            return Char("\0")
        if lower == "alarm":
            return Char("\a")
        if lower == "backspace":
            return Char("\b")
        if lower == "escape":
            return Char("\x1b")
        if lower == "delete":
            return Char("\x7f")

        if lower.startswith("x") and len(lower) > 1:
            hex_str = lower[1:]
            try:
                codepoint = int(hex_str, 16)
                return Char(chr(codepoint))
            except (ValueError, OverflowError):
                raise LispSyntaxError(f"Invalid hex character literal '#\\{name}'", loc)

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
        return self._parse_atom_token(token, loc)

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
                        # In Clojure, '(. ...)' is the dot interop operator.
                        # Only accept '.' if it immediately followed '(' without intervening whitespace or comments.
                        # In R7RS, '( . b)' or '(#;a . b)' is an error.
                        if self.line == loc.line and self.col == loc.col + 2:
                            elements.append(Symbol.intern("."))
                            continue
                        raise LispSyntaxError(
                            "Unexpected '.' at start of list", self._current_loc()
                        )
                    is_dotted = True
                    dotted_cdr = self.read()
                    if dotted_cdr is EOF:
                        raise LispSyntaxError(
                            "Expected cdr expression after '.' in pair",
                            self._current_loc(),
                        )
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

    def read_all_fast(self) -> List[Any]:
        """Flat single-pass stack reader for string sources."""
        src = self._src
        if src is None:
            out: List[Any] = []
            while True:
                d = self.read()
                if d is EOF:
                    break
                out.append(d)
            return out

        slen = self._len
        pos = self._pos
        line = self.line
        line_start = self._line_start
        fname = self.filename
        fold_case = self.fold_case
        sym_table = Symbol._table
        sym_new = Symbol
        sym_quote = sym_new("quote")
        sym_qquote = sym_new("quasiquote")
        sym_unq = sym_new("unquote")
        sym_unqs = sym_new("unquote-splicing")
        sym_dot = sym_new(".")
        atom_match = _ATOM_RE.match
        spaces_match = _SPACES_RE.match
        num_starts = _NUM_START_CHARS
        sign_nexts = _SIGN_NEXT_CHARS
        digit_chars = _DIGIT_CHARS
        delims = _DELIM_CHARS

        results: List[Any] = []
        stack: List[Tuple[List[Any], SourceLocation, int, int]] = []
        wraps: List[Tuple[Symbol, SourceLocation]] = []

        was_gc = slen > 4096 and gc.isenabled()
        if was_gc:
            gc.disable()
        try:
            return self._read_all_fast_loop(
                src,
                slen,
                pos,
                line,
                line_start,
                fname,
                fold_case,
                sym_table,
                sym_new,
                sym_quote,
                sym_qquote,
                sym_unq,
                sym_unqs,
                sym_dot,
                atom_match,
                spaces_match,
                num_starts,
                sign_nexts,
                digit_chars,
                delims,
                results,
                stack,
                wraps,
            )
        finally:
            if was_gc:
                gc.enable()

    def _read_all_fast_loop(
        self,
        src: str,
        slen: int,
        pos: int,
        line: int,
        line_start: int,
        fname: str,
        fold_case: bool,
        sym_table: Dict[str, Symbol],
        sym_new: Any,
        sym_quote: Symbol,
        sym_qquote: Symbol,
        sym_unq: Symbol,
        sym_unqs: Symbol,
        sym_dot: Symbol,
        atom_match: Any,
        spaces_match: Any,
        num_starts: frozenset[str],
        sign_nexts: frozenset[str],
        digit_chars: frozenset[str],
        delims: frozenset[str],
        results: List[Any],
        stack: List[Tuple[List[Any], SourceLocation, int, int]],
        wraps: List[Tuple[Symbol, SourceLocation]],
    ) -> List[Any]:
        while pos < slen:
            ch = src[pos]
            if ch == " ":
                if pos + 1 < slen and src[pos + 1] == " ":
                    ms = spaces_match(src, pos)
                    assert ms is not None
                    pos = ms.end()
                else:
                    pos += 1
                continue
            if ch == "\n":
                line += 1
                pos += 1
                line_start = pos
                continue
            if ch in "\t\r":
                pos += 1
                continue
            if ch == ";":
                nl = src.find("\n", pos + 1)
                if nl == -1:
                    pos = slen
                    break
                line += 1
                pos = nl + 1
                line_start = pos
                continue

            if ch == "(":
                stack.append(
                    (
                        [],
                        SourceLocation(fname, line, pos - line_start + 1),
                        pos,
                        len(wraps),
                    )
                )
                pos += 1
                continue

            if ch == ")":
                if not stack:
                    raise LispSyntaxError(
                        "Unexpected closing parenthesis ')'",
                        SourceLocation(fname, line, pos - line_start + 1),
                    )
                elems, fl, _, fwrap = stack[-1]
                if len(wraps) > fwrap:
                    raise LispSyntaxError(
                        "Unexpected closing parenthesis ')'",
                        SourceLocation(fname, line, pos - line_start + 1),
                    )
                stack.pop()
                n_e = len(elems)
                if n_e == 0:
                    val: Any = NIL
                elif n_e == 1:
                    val = Cons(elems[0], NIL, fl)
                elif n_e == 2:
                    val = Cons(elems[0], Cons(elems[1], NIL, fl), fl)
                elif n_e == 3:
                    val = Cons(
                        elems[0], Cons(elems[1], Cons(elems[2], NIL, fl), fl), fl
                    )
                else:
                    val = NIL
                    for item in reversed(elems):
                        val = Cons(item, val, fl)
                pos += 1
                if wraps:
                    while wraps and (not stack or len(wraps) > stack[-1][3]):
                        wsym, wloc = wraps.pop()
                        val = Cons(wsym, Cons(val, NIL, wloc), wloc)
                if stack:
                    stack[-1][0].append(val)
                else:
                    results.append(val)
                continue

            if ch == '"':
                p = pos + 1
                q_idx = src.find('"', p)
                if q_idx == -1:
                    raise LispSyntaxError(
                        "Unterminated string literal",
                        SourceLocation(fname, line, pos - line_start + 1),
                    )
                b_idx = src.find("\\", p, q_idx)
                if b_idx == -1:
                    val = src[p:q_idx]
                    nl = src.rfind("\n", p, q_idx)
                    if nl != -1:
                        line += src.count("\n", p, q_idx)
                        line_start = nl + 1
                    pos = q_idx + 1
                else:
                    self.line = line
                    self._line_start = line_start
                    self._pos = pos
                    val = self._read_string(
                        SourceLocation(fname, line, pos - line_start + 1)
                    )
                    pos = self._pos
                    line = self.line
                    line_start = self._line_start
                if wraps:
                    while wraps and (not stack or len(wraps) > stack[-1][3]):
                        wsym, wloc = wraps.pop()
                        val = Cons(wsym, Cons(val, NIL, wloc), wloc)
                if stack:
                    stack[-1][0].append(val)
                else:
                    results.append(val)
                continue

            if ch == "'":
                wraps.append(
                    (sym_quote, SourceLocation(fname, line, pos - line_start + 1))
                )
                pos += 1
                continue

            if ch == "`":
                wraps.append(
                    (sym_qquote, SourceLocation(fname, line, pos - line_start + 1))
                )
                pos += 1
                continue

            if ch == ",":
                wloc = SourceLocation(fname, line, pos - line_start + 1)
                if pos + 1 < slen and src[pos + 1] == "@":
                    wraps.append((sym_unqs, wloc))
                    pos += 2
                else:
                    wraps.append((sym_unq, wloc))
                    pos += 1
                continue

            if ch == "#":
                if pos + 1 < slen:
                    nxt = src[pos + 1]
                    if nxt in (";", "|", "!"):
                        self.line = line
                        self._line_start = line_start
                        self._pos = pos
                        self.fold_case = fold_case
                        self._skip_whitespace_and_comments()
                        pos = self._pos
                        line = self.line
                        line_start = self._line_start
                        fold_case = self.fold_case
                        continue
                    if nxt in ("t", "T") and (
                        pos + 2 >= slen or src[pos + 2] in delims
                    ):
                        pos += 2
                        val = True
                        if wraps:
                            while wraps and (not stack or len(wraps) > stack[-1][3]):
                                wsym, wloc = wraps.pop()
                                val = Cons(wsym, Cons(val, NIL, wloc), wloc)
                        if stack:
                            stack[-1][0].append(val)
                        else:
                            results.append(val)
                        continue
                    if nxt in ("f", "F") and (
                        pos + 2 >= slen or src[pos + 2] in delims
                    ):
                        pos += 2
                        val = False
                        if wraps:
                            while wraps and (not stack or len(wraps) > stack[-1][3]):
                                wsym, wloc = wraps.pop()
                                val = Cons(wsym, Cons(val, NIL, wloc), wloc)
                        if stack:
                            stack[-1][0].append(val)
                        else:
                            results.append(val)
                        continue
                self.line = line
                self._line_start = line_start
                self._pos = pos
                self.fold_case = fold_case
                val = self._read_hash_literal(
                    SourceLocation(fname, line, pos - line_start + 1)
                )
                pos = self._pos
                line = self.line
                line_start = self._line_start
                if wraps:
                    while wraps and (not stack or len(wraps) > stack[-1][3]):
                        wsym, wloc = wraps.pop()
                        val = Cons(wsym, Cons(val, NIL, wloc), wloc)
                if stack:
                    stack[-1][0].append(val)
                else:
                    results.append(val)
                continue

            if ch == "|":
                self.line = line
                self._line_start = line_start
                self._pos = pos
                self.fold_case = fold_case
                val = self._read_vertical_bar_symbol(
                    SourceLocation(fname, line, pos - line_start + 1)
                )
                pos = self._pos
                line = self.line
                line_start = self._line_start
                if wraps:
                    while wraps and (not stack or len(wraps) > stack[-1][3]):
                        wsym, wloc = wraps.pop()
                        val = Cons(wsym, Cons(val, NIL, wloc), wloc)
                if stack:
                    stack[-1][0].append(val)
                else:
                    results.append(val)
                continue

            # Atom
            m = atom_match(src, pos)
            assert m is not None
            end_p = m.end()
            tok = m.group(0)
            if tok == ".":
                if not stack:
                    raise LispSyntaxError(
                        "Unexpected standalone '.' token",
                        SourceLocation(fname, line, pos - line_start + 1),
                    )
                elems, fl, fop, fwrap = stack[-1]
                if not elems and pos == fop + 1 and len(wraps) == fwrap:
                    elems.append(sym_dot)
                    pos = end_p
                    continue
                if not elems:
                    raise LispSyntaxError(
                        "Unexpected '.' at start of list",
                        SourceLocation(fname, line, end_p - line_start + 1),
                    )
                if len(wraps) > fwrap:
                    raise LispSyntaxError(
                        "Unexpected '.' after reader prefix",
                        SourceLocation(fname, line, pos - line_start + 1),
                    )
                self.line = line
                self._line_start = line_start
                self._pos = end_p
                self.fold_case = fold_case
                dotted_cdr = self.read()
                if dotted_cdr is EOF:
                    raise LispSyntaxError(
                        "Expected cdr expression after '.' in pair",
                        self._current_loc(),
                    )
                self._skip_whitespace_and_comments()
                if self._pos >= slen or src[self._pos] != ")":
                    raise LispSyntaxError(
                        "Expected ')' after dotted pair cdr", self._current_loc()
                    )
                self._pos += 1
                pos = self._pos
                line = self.line
                line_start = self._line_start
                val = dotted_cdr
                for item in reversed(elems):
                    val = Cons(item, val, fl)
                stack.pop()
                if wraps:
                    while wraps and (not stack or len(wraps) > stack[-1][3]):
                        wsym, wloc = wraps.pop()
                        val = Cons(wsym, Cons(val, NIL, wloc), wloc)
                if stack:
                    stack[-1][0].append(val)
                else:
                    results.append(val)
                continue

            pos = end_p
            c0 = tok[0]
            tlen = len(tok)
            if c0 not in num_starts:
                sym_key = tok.lower() if fold_case else tok
                val = sym_table.get(sym_key)
                if val is None:
                    val = sym_new(sym_key)
            elif (
                (tlen == 1 and c0 in "+-")
                or (c0 in "+-" and tlen > 1 and tok[1] not in sign_nexts)
                or (c0 == "." and tlen > 1 and tok[1] not in digit_chars)
            ):
                sym_key = tok.lower() if fold_case else tok
                val = sym_table.get(sym_key)
                if val is None:
                    val = sym_new(sym_key)
            elif tok.isdigit():
                val = int(tok)
            else:
                self.line = line
                self._line_start = line_start
                self._pos = pos
                self.fold_case = fold_case
                val = self._parse_atom_token(tok, None)

            if wraps:
                while wraps and (not stack or len(wraps) > stack[-1][3]):
                    wsym, wloc = wraps.pop()
                    val = Cons(wsym, Cons(val, NIL, wloc), wloc)
            if stack:
                stack[-1][0].append(val)
            else:
                results.append(val)

        self.line = line
        self._line_start = line_start
        self._pos = pos
        self.fold_case = fold_case
        if stack:
            raise LispSyntaxError("Unclosed parenthesis '('", stack[-1][1])
        if wraps:
            raise LispSyntaxError("Unexpected EOF after reader macro", wraps[-1][1])
        return results


def read_one(text: str, filename: str = "<stdin>", fold_case: bool = False) -> Any:
    """Read a single S-expression from string."""
    reader = Reader(text, filename=filename, fold_case=fold_case)
    return reader.read()


def read_all(
    text: str, filename: str = "<stdin>", fold_case: bool = False
) -> List[Any]:
    """Read all S-expressions from string until EOF."""
    reader = Reader(text, filename=filename, fold_case=fold_case)
    return reader.read_all_fast()


def read_all_from_file(filepath: str, fold_case: bool = False) -> List[Any]:
    """Read all S-expressions from a file path."""
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
    except (OSError, IOError) as exc:
        raise SchemeException(
            ErrorObject(
                f"include: cannot read file '{filepath}': {exc}", NIL, kind="file"
            )
        ) from exc
    return read_all(content, filename=filepath, fold_case=fold_case)


_active_include_stack: List[str] = []


def extract_base_dir(node: Any) -> Optional[str]:
    """Extract directory path from AST node source location if available."""
    loc = getattr(node, "loc", None)
    filepath = getattr(loc, "file", None) or getattr(loc, "filename", None)
    if isinstance(filepath, str) and filepath not in ("<stdin>", "<string>", ""):
        return str(os.path.dirname(os.path.abspath(filepath)))
    return None


def extract_caller_file(node: Any) -> Optional[str]:
    """Extract filename from AST node source location if available."""
    loc = getattr(node, "loc", None)
    filepath = getattr(loc, "file", None) or getattr(loc, "filename", None)
    if isinstance(filepath, str) and filepath not in ("<stdin>", "<string>", ""):
        return str(filepath)
    return None


def resolve_include_path(filename: str, base_dir: Optional[str] = None) -> str:
    """Resolve an include file path against base directory, ILISP_LOAD_PATH, or cwd."""
    if os.path.isabs(filename):
        cand = os.path.realpath(filename)
        if os.path.isfile(cand):
            return cand
        raise SchemeException(
            ErrorObject(
                f"include: cannot find or open file '{filename}'", NIL, kind="file"
            )
        )

    candidates: List[str] = []
    if base_dir:
        candidates.append(base_dir)

    load_path_env = os.environ.get("ILISP_LOAD_PATH", "")
    if load_path_env:
        for p in load_path_env.split(os.pathsep):
            if p.strip():
                candidates.append(p.strip())

    candidates.append(os.getcwd())

    for c_dir in candidates:
        cand = os.path.realpath(os.path.join(c_dir, filename))
        if os.path.isfile(cand):
            return cand

    raise SchemeException(
        ErrorObject(f"include: cannot find or open file '{filename}'", NIL, kind="file")
    )


@contextlib.contextmanager
def active_include_context(
    canonical_path: str, caller_loc_file: Optional[str] = None
) -> Iterator[None]:
    """Context manager tracking active include file paths to prevent circular inclusion."""
    caller_added = False
    real_caller: Optional[str] = None
    if caller_loc_file:
        real_caller = os.path.realpath(caller_loc_file)
        if real_caller == canonical_path:
            raise SchemeException(
                ErrorObject(
                    f"include: circular dependency detected: '{canonical_path}' includes itself",
                    NIL,
                    kind="file",
                )
            )
        if real_caller not in _active_include_stack:
            _active_include_stack.append(real_caller)
            caller_added = True

    if canonical_path in _active_include_stack:
        chain = " -> ".join(_active_include_stack + [canonical_path])
        if caller_added and real_caller and real_caller in _active_include_stack:
            _active_include_stack.remove(real_caller)
        raise SchemeException(
            ErrorObject(
                f"include: circular dependency detected: {chain}",
                NIL,
                kind="file",
            )
        )

    _active_include_stack.append(canonical_path)
    try:
        yield
    finally:
        if _active_include_stack and _active_include_stack[-1] == canonical_path:
            _active_include_stack.pop()
        elif canonical_path in _active_include_stack:
            _active_include_stack.remove(canonical_path)

        if caller_added and real_caller:
            if _active_include_stack and _active_include_stack[-1] == real_caller:
                _active_include_stack.pop()
            elif real_caller in _active_include_stack:
                _active_include_stack.remove(real_caller)
