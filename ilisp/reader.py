"""Hand-written recursive descent S-expression Reader with Source Maps.

This module provides a deterministic, zero-dependency Tokenizer and Reader
for Kernel ILISP, recording SourceLocation metadata and supporting standard
Scheme reader macros (', `, ,, ,@, #;).
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, Dict, List, Optional, Tuple, Union

from ilisp.types import EOF, NIL, Cons, SchemeComplex, SourceLocation, Symbol

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
        self.fold_case: bool = False
        self.labels: Dict[int, Any] = {}

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

        # Vertical bar escaped symbol (R7RS 2.1: |...|)
        if ch == "|":
            return self._read_vertical_bar_symbol(loc)

        # Hash literals: #t, #f, #\char
        if ch == "#":
            return self._read_hash_literal(loc)

        # Atom (Number or Symbol)
        return self._read_atom(loc)

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

        # Check standalone '.' token (not a valid identifier or datum in R7RS)
        if token == ".":
            raise LispSyntaxError("Unexpected standalone '.' token", loc)

        # Number parsing
        # Try integer
        try:
            if token.startswith("0x") or token.startswith("0X"):
                return int(token, 16)
            return int(token)
        except ValueError:
            pass

        # Try special float literals (R7RS 6.2.4: +inf.0, -inf.0, +nan.0)
        low_tok = token.lower()
        if low_tok in ("+inf.0", "+inf"):
            return float("inf")
        if low_tok in ("-inf.0", "-inf"):
            return float("-inf")
        if low_tok in ("+nan.0", "-nan.0", "nan.0", "+nan", "-nan"):
            return float("nan")

        # Try fraction (rational)
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

        # Try Scheme exponent markers (s, f, d, l)
        import re

        m_exp = re.match(r"^([+-]?(?:\d+\.?\d*|\.\d+))[sfdl]([+-]?\d+)$", low_tok)
        if m_exp:
            try:
                return float(f"{m_exp.group(1)}e{m_exp.group(2)}")
            except ValueError:
                pass

        # Try complex number
        c_val = self._parse_complex(low_tok, 10)
        if c_val is not None:
            return c_val

        # Try float
        try:
            return float(token)
        except ValueError:
            pass

        # Otherwise intern as Symbol
        sym_name = token
        if self.fold_case:
            sym_name = sym_name.lower()
        return Symbol.intern(sym_name)

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
