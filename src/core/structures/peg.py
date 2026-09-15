#!/usr/bin/env python3
"""
Pure Python Packrat PEG (Parsing Expression Grammar) Runtime Engine.
Guarantees O(N) linear parsing time via memoization table.
Provides combinators, semantic action hooks, max-position error tracking,
and DoS/recursion guards.
Conforms to DSN-25 specification.
"""

import re
from abc import ABC, abstractmethod
from typing import (
    Any,
    Callable,
    ClassVar,
    Dict,
    Generic,
    List,
    Optional,
    Pattern,
    Set,
    Tuple,
    TypeVar,
    Union,
    cast,
)

T = TypeVar("T")
R = TypeVar("R")


class PEGSyntaxError(Exception):
    """Exception raised when PEG parsing fails."""

    def __init__(
        self,
        message: str,
        pos: int,
        line: int,
        col: int,
        expected_tokens: Set[str],
        snippet: str,
    ) -> None:
        self.message = message
        self.pos = pos
        self.line = line
        self.col = col
        self.expected_tokens = expected_tokens
        self.snippet = snippet
        super().__init__(self._format_message())

    def _format_message(self) -> str:
        tokens_str = (
            ", ".join(f"'{t}'" for t in sorted(self.expected_tokens))
            if self.expected_tokens
            else "none"
        )
        caret_indent = " " * max(0, self.col - 1)
        return (
            f"Syntax error at line {self.line}, col {self.col}: {self.message}\n"
            f"  {self.snippet}\n"
            f"  {caret_indent}^ expected: {tokens_str}"
        )


class ParseResult(Generic[T]):
    """Immutable result of a single parsing expression attempt."""

    __slots__ = ("success", "value", "next_pos", "error_msg")

    def __init__(
        self,
        success: bool,
        value: Optional[T],
        next_pos: int,
        error_msg: Optional[str] = None,
    ) -> None:
        self.success = success
        self.value = value
        self.next_pos = next_pos
        self.error_msg = error_msg

    def __repr__(self) -> str:
        if self.success:
            return f"ParseResult(OK, val={self.value!r}, next={self.next_pos})"
        return f"ParseResult(FAIL, next={self.next_pos}, err={self.error_msg!r})"


class ParseContext:
    """
    State context for a single PEG parsing run.
    Contains text, packrat memoization table, recursion counter, and error tracking.
    """

    def __init__(
        self,
        text: str,
        max_depth: int = 500,
        max_input_length: int = 65536,
    ) -> None:
        if len(text) > max_input_length:
            raise ValueError(
                f"Input length ({len(text)}) exceeds maximum allowed ({max_input_length})"
            )
        self.text = text
        self.length = len(text)
        self.max_depth = max_depth
        self.depth = 0
        self.max_pos = 0
        self.expected_tokens: Set[str] = set()
        self.memo: Dict[Tuple[int, int], ParseResult[Any]] = {}
        self.in_progress: Set[Tuple[int, int]] = set()

    def update_max_pos(self, pos: int, token: str) -> None:
        """Tracks the furthest position reached for syntax error diagnostics."""
        if pos > self.max_pos:
            self.max_pos = pos
            self.expected_tokens = {token} if token else set()
        elif pos == self.max_pos and token:
            self.expected_tokens.add(token)

    def calculate_line_col(self, pos: int) -> Tuple[int, int, str]:
        """Calculates 1-indexed line and column numbers and returns the line snippet."""
        bounded_pos = max(0, min(pos, self.length))
        prefix = self.text[:bounded_pos]
        lines = prefix.split("\n")
        line_num = len(lines)
        col_num = len(lines[-1]) + 1

        all_lines = self.text.split("\n")
        snippet = all_lines[line_num - 1] if line_num <= len(all_lines) else ""
        return line_num, col_num, snippet


class Parser(ABC, Generic[T]):
    """Abstract Base Class for all PEG Parsing Expressions."""

    _id_counter: ClassVar[int] = 0

    def __init__(self, name: Optional[str] = None) -> None:
        Parser._id_counter += 1
        self.rule_id = Parser._id_counter
        self.name = name

    @abstractmethod
    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[T]:
        """Evaluates the parsing expression at the given position."""
        pass

    def _eval_cached(self, ctx: ParseContext, pos: int) -> ParseResult[T]:
        """Packrat memoization wrapper guaranteeing O(1) lookup per (rule, pos)."""
        key = (self.rule_id, pos)
        if key in ctx.memo:
            return cast(ParseResult[T], ctx.memo[key])

        if key in ctx.in_progress:
            line, col, snippet = ctx.calculate_line_col(pos)
            raise PEGSyntaxError(
                f"Left recursion or infinite loop detected at rule '{self.name or self.rule_id}'",
                pos=pos,
                line=line,
                col=col,
                expected_tokens=set(),
                snippet=snippet,
            )

        if ctx.depth > ctx.max_depth:
            line, col, snippet = ctx.calculate_line_col(pos)
            raise PEGSyntaxError(
                "Maximum parsing recursion depth exceeded",
                pos=pos,
                line=line,
                col=col,
                expected_tokens=set(),
                snippet=snippet,
            )

        ctx.depth += 1
        ctx.in_progress.add(key)
        try:
            res = self.parse_at(ctx, pos)
        finally:
            ctx.depth -= 1
            ctx.in_progress.remove(key)

        ctx.memo[key] = res
        return res

    def parse(self, text: str) -> T:
        """Parses the entire text. Raises PEGSyntaxError on failure or trailing characters."""
        ctx = ParseContext(text)
        res = self._eval_cached(ctx, 0)
        if not res.success:
            line, col, snippet = ctx.calculate_line_col(ctx.max_pos)
            raise PEGSyntaxError(
                res.error_msg or "Unexpected token",
                pos=ctx.max_pos,
                line=line,
                col=col,
                expected_tokens=ctx.expected_tokens,
                snippet=snippet,
            )
        if res.next_pos < ctx.length:
            ctx.update_max_pos(res.next_pos, "EOF")
            line, col, snippet = ctx.calculate_line_col(res.next_pos)
            raise PEGSyntaxError(
                "Unconsumed trailing characters",
                pos=res.next_pos,
                line=line,
                col=col,
                expected_tokens=ctx.expected_tokens,
                snippet=snippet,
            )
        return cast(T, res.value)

    def map(self, fn: Callable[[T], R]) -> "Parser[R]":
        """Attaches a semantic action to transform parse result value."""
        return MappedParser(self, fn)

    def __add__(self, other: "Parser[Any]") -> "Parser[List[Any]]":
        """Sequence operator overload (p1 + p2) with auto-flattening."""
        left_list: List[Parser[Any]] = (
            self.parsers if isinstance(self, Sequence) else [self]
        )
        right_list: List[Parser[Any]] = (
            other.parsers if isinstance(other, Sequence) else [other]
        )
        return Sequence(*(left_list + right_list))

    def __truediv__(self, other: "Parser[Any]") -> "Parser[Any]":
        """Ordered choice operator overload (p1 / p2) with auto-flattening."""
        left_list: List[Parser[Any]] = (
            self.alternatives if isinstance(self, Choice) else [self]
        )
        right_list: List[Parser[Any]] = (
            other.alternatives if isinstance(other, Choice) else [other]
        )
        return Choice(*(left_list + right_list))


class Empty(Parser[None]):
    """Matches the empty string epsilon without consuming input."""

    def __init__(self, name: Optional[str] = None) -> None:
        super().__init__(name or "Empty")

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[None]:
        return ParseResult(True, None, pos)


class Literal(Parser[str]):
    """Matches an exact literal string."""

    def __init__(self, expected: str, name: Optional[str] = None) -> None:
        super().__init__(name or f"'{expected}'")
        self.expected = expected
        self.expected_len = len(expected)

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[str]:
        if ctx.text.startswith(self.expected, pos):
            return ParseResult(True, self.expected, pos + self.expected_len)
        ctx.update_max_pos(pos, self.expected)
        return ParseResult(False, None, pos, f"Expected '{self.expected}'")


class Regex(Parser[str]):
    """Matches a regular expression pattern starting at the current position."""

    def __init__(
        self, pattern: Union[str, Pattern[str]], name: Optional[str] = None
    ) -> None:
        pat_str = pattern.pattern if isinstance(pattern, re.Pattern) else pattern
        super().__init__(name or f"/{pat_str}/")
        self.pattern: Pattern[str] = (
            pattern if isinstance(pattern, re.Pattern) else re.compile(pattern)
        )
        self.pattern_str = pat_str

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[str]:
        m = self.pattern.match(ctx.text, pos)
        if m is not None:
            matched_str = m.group(0)
            return ParseResult(True, matched_str, pos + len(matched_str))
        ctx.update_max_pos(pos, self.pattern_str)
        return ParseResult(False, None, pos, f"Expected pattern /{self.pattern_str}/")


class Sequence(Parser[List[Any]]):
    """Matches a sequence of parsers e1 e2 ... eN."""

    def __init__(self, *parsers: Parser[Any], name: Optional[str] = None) -> None:
        super().__init__(name or "Seq")
        self.parsers = list(parsers)

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[List[Any]]:
        curr_pos = pos
        values: List[Any] = []
        for p in self.parsers:
            res = p._eval_cached(ctx, curr_pos)
            if not res.success:
                return ParseResult(False, None, pos, res.error_msg)
            values.append(res.value)
            curr_pos = res.next_pos
        return ParseResult(True, values, curr_pos)


class Choice(Parser[Any]):
    """Ordered choice e1 / e2 / ... / eN. Tries each alternative in order."""

    def __init__(self, *parsers: Parser[Any], name: Optional[str] = None) -> None:
        super().__init__(name or "Choice")
        self.alternatives = list(parsers)

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[Any]:
        for alt in self.alternatives:
            res = alt._eval_cached(ctx, pos)
            if res.success:
                return res
        return ParseResult(False, None, pos, "No matching choice alternative")


class Repetition(Parser[List[T]]):
    """Matches repetitions of child parser (0+ or 1+)."""

    def __init__(
        self, child: Parser[T], min_count: int = 0, name: Optional[str] = None
    ) -> None:
        super().__init__(name or f"Repetition(min={min_count})")
        self.child = child
        self.min_count = min_count

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[List[T]]:
        curr_pos = pos
        results: List[T] = []
        while True:
            res = self.child._eval_cached(ctx, curr_pos)
            if not res.success or res.next_pos == curr_pos:
                break
            results.append(cast(T, res.value))
            curr_pos = res.next_pos
        if len(results) < self.min_count:
            return ParseResult(
                False,
                None,
                pos,
                f"Expected at least {self.min_count} repetitions, got {len(results)}",
            )
        return ParseResult(True, results, curr_pos)


class OptionalParser(Parser[Optional[T]]):
    """Optional match e?. Always succeeds, consuming input only if child matches."""

    def __init__(
        self,
        child: Parser[T],
        default: Optional[T] = None,
        name: Optional[str] = None,
    ) -> None:
        super().__init__(name or "Optional")
        self.child = child
        self.default = default

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[Optional[T]]:
        res = self.child._eval_cached(ctx, pos)
        if res.success:
            return ParseResult(True, res.value, res.next_pos)
        return ParseResult(True, self.default, pos)


class Predicate(Parser[None]):
    """Syntactic predicate: positive (&e) or negative (!e) lookahead. Never consumes input."""

    def __init__(
        self, child: Parser[Any], is_positive: bool = True, name: Optional[str] = None
    ) -> None:
        super().__init__(name or ("AndPred" if is_positive else "NotPred"))
        self.child = child
        self.is_positive = is_positive

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[None]:
        res = self.child._eval_cached(ctx, pos)
        if self.is_positive:
            if res.success:
                return ParseResult(True, None, pos)
            return ParseResult(False, None, pos, "Positive predicate failed")
        if not res.success:
            return ParseResult(True, None, pos)
        return ParseResult(
            False, None, pos, "Negative predicate matched forbidden input"
        )


class RuleRef(Parser[Any]):
    """Lazy reference wrapper for mutually recursive or forward-declared grammar rules."""

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.target: Optional[Parser[Any]] = None

    def define(self, target: Parser[Any]) -> "RuleRef":
        """Assigns the resolved parser target to this reference."""
        self.target = target
        return self

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[Any]:
        if self.target is None:
            raise RuntimeError(f"RuleRef '{self.name}' has not been defined")
        return self.target._eval_cached(ctx, pos)


class MappedParser(Parser[R], Generic[T, R]):
    """Applies a transformation function to the child parser's successful output."""

    def __init__(self, child: Parser[T], fn: Callable[[T], R]) -> None:
        super().__init__(f"Map({child.name or 'anon'})")
        self.child = child
        self.fn = fn

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[R]:
        res = self.child._eval_cached(ctx, pos)
        if not res.success:
            return ParseResult(False, None, pos, res.error_msg)
        mapped_val = self.fn(cast(T, res.value))
        return ParseResult(True, mapped_val, res.next_pos)


def _unescape_class_char(char: str) -> str:
    escapes = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", "]": "]", "-": "-"}
    return escapes.get(char, char)


def _tokenize_class_spec(spec: str) -> List[str]:
    tokens: List[str] = []
    i = 0
    n = len(spec)
    while i < n:
        if spec[i] == "\\" and i + 1 < n:
            tokens.append(_unescape_class_char(spec[i + 1]))
            i += 2
        else:
            tokens.append(spec[i])
            i += 1
    return tokens


def _parse_class_tokens(tokens: List[str]) -> Tuple[List[Tuple[int, int]], Set[str]]:
    ranges: List[Tuple[int, int]] = []
    chars: Set[str] = set()
    i = 0
    n = len(tokens)
    while i < n:
        if i + 2 < n and tokens[i + 1] == "-":
            start_ord = ord(tokens[i])
            end_ord = ord(tokens[i + 2])
            ranges.append((min(start_ord, end_ord), max(start_ord, end_ord)))
            i += 3
        else:
            chars.add(tokens[i])
            i += 1
    return ranges, chars


class AnyChar(Parser[str]):
    """Matches any single character except EOF (Bryan Ford POPL '04 '.' token)."""

    def __init__(self, name: Optional[str] = None) -> None:
        super().__init__(name or "AnyChar")

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[str]:
        if pos < ctx.length:
            ch = ctx.text[pos]
            return ParseResult(True, ch, pos + 1)
        ctx.update_max_pos(pos, "any character")
        return ParseResult(False, None, pos, "Unexpected EOF")


class CharClass(Parser[str]):
    """Matches a single character within a character class [...] or [^...]."""

    def __init__(
        self, spec: str, inverted: bool = False, name: Optional[str] = None
    ) -> None:
        prefix = "^" if inverted else ""
        super().__init__(name or f"[{prefix}{spec}]")
        self.spec = spec
        self.inverted = inverted
        tokens = _tokenize_class_spec(spec)
        self.ranges, self.chars = _parse_class_tokens(tokens)

    def _matches(self, ch: str) -> bool:
        ch_ord = ord(ch)
        in_range = any(start <= ch_ord <= end for start, end in self.ranges)
        in_chars = ch in self.chars
        found = in_range or in_chars
        return not found if self.inverted else found

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[str]:
        if pos >= ctx.length:
            ctx.update_max_pos(pos, self.name or "char_class")
            return ParseResult(False, None, pos, "Unexpected EOF")
        ch = ctx.text[pos]
        if self._matches(ch):
            return ParseResult(True, ch, pos + 1)
        ctx.update_max_pos(pos, self.name or "char_class")
        return ParseResult(False, None, pos, f"Expected character matching {self.name}")


# Factory aliases and shorthand combinators
Seq = Sequence
Opt = OptionalParser
Lit = Literal
Reg = Regex
Dot = AnyChar
Class = CharClass


def ZeroOrMore(child: Parser[T], name: Optional[str] = None) -> Repetition[T]:
    """Shorthand for 0 or more repetitions (e*)."""
    return Repetition(child, min_count=0, name=name)


def OneOrMore(child: Parser[T], name: Optional[str] = None) -> Repetition[T]:
    """Shorthand for 1 or more repetitions (e+)."""
    return Repetition(child, min_count=1, name=name)


def AndPred(child: Parser[Any], name: Optional[str] = None) -> Predicate:
    """Shorthand for positive lookahead (&e)."""
    return Predicate(child, is_positive=True, name=name)


def NotPred(child: Parser[Any], name: Optional[str] = None) -> Predicate:
    """Shorthand for negative lookahead (!e)."""
    return Predicate(child, is_positive=False, name=name)
