"""R7RS Characters and Strings primitives and predicates for ILISP.

This module implements the full specification of R7RS-small Section 6.6 (Characters)
and Section 6.7 (Strings), including case-insensitive comparisons, Unicode operations,
conversions, and mutable buffer operations.
"""

from __future__ import annotations

from typing import Any, List, Optional, Union

from ilisp.types import (
    Char,
    MutableString,
    Vector,
    is_char,
    is_string,
    string_val,
    to_lisp_list,
    to_py_list,
)

# ==========================================
# 1. R7RS 6.6 Characters
# ==========================================


def char_p(obj: Any) -> bool:
    """Predicate returning True if obj is a Scheme Char."""
    return is_char(obj)


def _check_char(arg: Any, proc_name: str) -> Char:
    if not isinstance(arg, Char):
        raise TypeError(
            f"{proc_name}: expected char, got {type(arg).__name__}: {arg!r}"
        )
    return arg


def char_eq_p(*args: Any) -> bool:
    """(char=? c1 c2 c3 ...)"""
    if len(args) < 2:
        raise TypeError("char=?: requires at least 2 arguments")
    chars = [_check_char(c, "char=?").val for c in args]
    return all(c == chars[0] for c in chars[1:])


def char_lt_p(*args: Any) -> bool:
    """(char<? c1 c2 c3 ...)"""
    if len(args) < 2:
        raise TypeError("char<?: requires at least 2 arguments")
    chars = [_check_char(c, "char<?").val for c in args]
    return all(chars[i] < chars[i + 1] for i in range(len(chars) - 1))


def char_gt_p(*args: Any) -> bool:
    """(char>? c1 c2 c3 ...)"""
    if len(args) < 2:
        raise TypeError("char>?: requires at least 2 arguments")
    chars = [_check_char(c, "char>?").val for c in args]
    return all(chars[i] > chars[i + 1] for i in range(len(chars) - 1))


def char_le_p(*args: Any) -> bool:
    """(char<=? c1 c2 c3 ...)"""
    if len(args) < 2:
        raise TypeError("char<=?: requires at least 2 arguments")
    chars = [_check_char(c, "char<=?").val for c in args]
    return all(chars[i] <= chars[i + 1] for i in range(len(chars) - 1))


def char_ge_p(*args: Any) -> bool:
    """(char>=? c1 c2 c3 ...)"""
    if len(args) < 2:
        raise TypeError("char>=?: requires at least 2 arguments")
    chars = [_check_char(c, "char>=?").val for c in args]
    return all(chars[i] >= chars[i + 1] for i in range(len(chars) - 1))


# Case-insensitive character comparisons
def char_ci_eq_p(*args: Any) -> bool:
    """(char-ci=? c1 c2 c3 ...)"""
    if len(args) < 2:
        raise TypeError("char-ci=?: requires at least 2 arguments")
    chars = [_check_char(c, "char-ci=?").val.casefold() for c in args]
    return all(c == chars[0] for c in chars[1:])


def char_ci_lt_p(*args: Any) -> bool:
    """(char-ci<? c1 c2 c3 ...)"""
    if len(args) < 2:
        raise TypeError("char-ci<?: requires at least 2 arguments")
    chars = [_check_char(c, "char-ci<?").val.casefold() for c in args]
    return all(chars[i] < chars[i + 1] for i in range(len(chars) - 1))


def char_ci_gt_p(*args: Any) -> bool:
    """(char-ci>? c1 c2 c3 ...)"""
    if len(args) < 2:
        raise TypeError("char-ci>?: requires at least 2 arguments")
    chars = [_check_char(c, "char-ci>?").val.casefold() for c in args]
    return all(chars[i] > chars[i + 1] for i in range(len(chars) - 1))


def char_ci_le_p(*args: Any) -> bool:
    """(char-ci<=? c1 c2 c3 ...)"""
    if len(args) < 2:
        raise TypeError("char-ci<=?: requires at least 2 arguments")
    chars = [_check_char(c, "char-ci<=?").val.casefold() for c in args]
    return all(chars[i] <= chars[i + 1] for i in range(len(chars) - 1))


def char_ci_ge_p(*args: Any) -> bool:
    """(char-ci>=? c1 c2 c3 ...)"""
    if len(args) < 2:
        raise TypeError("char-ci>=?: requires at least 2 arguments")
    chars = [_check_char(c, "char-ci>=?").val.casefold() for c in args]
    return all(chars[i] >= chars[i + 1] for i in range(len(chars) - 1))


# Character classification predicates
def char_alphabetic_p(c: Any) -> bool:
    """(char-alphabetic? c)"""
    return _check_char(c, "char-alphabetic?").val.isalpha()


def char_numeric_p(c: Any) -> bool:
    """(char-numeric? c)"""
    return _check_char(c, "char-numeric?").val.isdigit()


def char_whitespace_p(c: Any) -> bool:
    """(char-whitespace? c)"""
    return _check_char(c, "char-whitespace?").val.isspace()


def char_upper_case_p(c: Any) -> bool:
    """(char-upper-case? c)"""
    return _check_char(c, "char-upper-case?").val.isupper()


def char_lower_case_p(c: Any) -> bool:
    """(char-lower-case? c)"""
    return _check_char(c, "char-lower-case?").val.islower()


def digit_value(c: Any) -> Any:
    """(digit-value c) -> integer in 0..9 or False."""
    ch = _check_char(c, "digit-value").val
    if "0" <= ch <= "9":
        return ord(ch) - ord("0")
    if ch.isdigit():
        try:
            import unicodedata

            return unicodedata.digit(ch)
        except (ValueError, TypeError):
            return False
    return False


def char_to_integer(c: Any) -> int:
    """(char->integer c)"""
    return ord(_check_char(c, "char->integer").val)


def integer_to_char(n: Any) -> Char:
    """(integer->char n)"""
    if not isinstance(n, int):
        raise TypeError(
            f"integer->char: expected integer, got {type(n).__name__}: {n!r}"
        )
    try:
        return Char(chr(n))
    except (ValueError, OverflowError) as err:
        raise ValueError(
            f"integer->char: invalid Unicode codepoint {n}: {err}"
        ) from err


def char_upcase(c: Any) -> Char:
    """(char-upcase c)"""
    return Char(_check_char(c, "char-upcase").val.upper())


def char_downcase(c: Any) -> Char:
    """(char-downcase c)"""
    return Char(_check_char(c, "char-downcase").val.lower())


def char_foldcase(c: Any) -> Char:
    """(char-foldcase c)"""
    return Char(_check_char(c, "char-foldcase").val.casefold())


# ==========================================
# 2. R7RS 6.7 Strings
# ==========================================


def string_p(obj: Any) -> bool:
    """Predicate returning True if obj is a Scheme string."""
    return is_string(obj)


def _check_string(arg: Any, proc_name: str) -> Union[str, MutableString]:
    if not is_string(arg):
        raise TypeError(
            f"{proc_name}: expected string, got {type(arg).__name__}: {arg!r}"
        )
    return arg  # type: ignore[no-any-return]


def make_string(k: Any, char: Optional[Any] = None) -> MutableString:
    """(make-string k [char]) -> MutableString."""
    if not isinstance(k, int) or k < 0:
        raise TypeError(
            f"make-string: length must be a non-negative integer, got {k!r}"
        )
    fill_ch = " "
    if char is not None:
        fill_ch = _check_char(char, "make-string").val
    return MutableString(fill_ch * k)


def string_constructor(*args: Any) -> MutableString:
    """(string c1 c2 ...) -> MutableString."""
    chars: List[str] = []
    for c in args:
        chars.append(_check_char(c, "string").val)
    return MutableString("".join(chars))


def string_length(s: Any) -> int:
    """(string-length s)"""
    return len(_check_string(s, "string-length"))


def string_ref(s: Any, k: Any) -> Char:
    """(string-ref s k) -> Char."""
    s_obj = _check_string(s, "string-ref")
    if not isinstance(k, int):
        raise TypeError(f"string-ref: index must be integer, got {k!r}")
    if not (0 <= k < len(s_obj)):
        raise IndexError(f"string-ref: index {k} out of range 0..{len(s_obj) - 1}")
    return Char(s_obj[k])


def string_set_bang(s: Any, k: Any, char: Any) -> Any:
    """(string-set! string k char)"""
    if not isinstance(s, MutableString):
        if isinstance(s, str):
            raise TypeError("string-set!: cannot alter immutable string literal")
        raise TypeError(f"string-set!: expected mutable string, got {type(s).__name__}")
    if not isinstance(k, int):
        raise TypeError(f"string-set!: index must be integer, got {k!r}")
    if not (0 <= k < len(s)):
        raise IndexError(f"string-set!: index {k} out of range 0..{len(s) - 1}")
    ch = _check_char(char, "string-set!")
    s[k] = ch
    return None


def string_eq_p(*args: Any) -> bool:
    """(string=? s1 s2 s3 ...)"""
    if len(args) < 2:
        raise TypeError("string=?: requires at least 2 arguments")
    strs = [string_val(_check_string(s, "string=?")) for s in args]
    return all(s == strs[0] for s in strs[1:])


def string_lt_p(*args: Any) -> bool:
    """(string<? s1 s2 s3 ...)"""
    if len(args) < 2:
        raise TypeError("string<?: requires at least 2 arguments")
    strs = [string_val(_check_string(s, "string<?")) for s in args]
    return all(strs[i] < strs[i + 1] for i in range(len(strs) - 1))


def string_gt_p(*args: Any) -> bool:
    """(string>? s1 s2 s3 ...)"""
    if len(args) < 2:
        raise TypeError("string>?: requires at least 2 arguments")
    strs = [string_val(_check_string(s, "string>?")) for s in args]
    return all(strs[i] > strs[i + 1] for i in range(len(strs) - 1))


def string_le_p(*args: Any) -> bool:
    """(string<=? s1 s2 s3 ...)"""
    if len(args) < 2:
        raise TypeError("string<=?: requires at least 2 arguments")
    strs = [string_val(_check_string(s, "string<=?")) for s in args]
    return all(strs[i] <= strs[i + 1] for i in range(len(strs) - 1))


def string_ge_p(*args: Any) -> bool:
    """(string>=? s1 s2 s3 ...)"""
    if len(args) < 2:
        raise TypeError("string>=?: requires at least 2 arguments")
    strs = [string_val(_check_string(s, "string>=?")) for s in args]
    return all(strs[i] >= strs[i + 1] for i in range(len(strs) - 1))


# Case-insensitive string comparisons
def string_ci_eq_p(*args: Any) -> bool:
    """(string-ci=? s1 s2 s3 ...)"""
    if len(args) < 2:
        raise TypeError("string-ci=?: requires at least 2 arguments")
    strs = [string_val(_check_string(s, "string-ci=?")).casefold() for s in args]
    return all(s == strs[0] for s in strs[1:])


def string_ci_lt_p(*args: Any) -> bool:
    """(string-ci<? s1 s2 s3 ...)"""
    if len(args) < 2:
        raise TypeError("string-ci<?: requires at least 2 arguments")
    strs = [string_val(_check_string(s, "string-ci<?")).casefold() for s in args]
    return all(strs[i] < strs[i + 1] for i in range(len(strs) - 1))


def string_ci_gt_p(*args: Any) -> bool:
    """(string-ci>? s1 s2 s3 ...)"""
    if len(args) < 2:
        raise TypeError("string-ci>?: requires at least 2 arguments")
    strs = [string_val(_check_string(s, "string-ci>?")).casefold() for s in args]
    return all(strs[i] > strs[i + 1] for i in range(len(strs) - 1))


def string_ci_le_p(*args: Any) -> bool:
    """(string-ci<=? s1 s2 s3 ...)"""
    if len(args) < 2:
        raise TypeError("string-ci<=?: requires at least 2 arguments")
    strs = [string_val(_check_string(s, "string-ci<=?")).casefold() for s in args]
    return all(strs[i] <= strs[i + 1] for i in range(len(strs) - 1))


def string_ci_ge_p(*args: Any) -> bool:
    """(string-ci>=? s1 s2 s3 ...)"""
    if len(args) < 2:
        raise TypeError("string-ci>=?: requires at least 2 arguments")
    strs = [string_val(_check_string(s, "string-ci>=?")).casefold() for s in args]
    return all(strs[i] >= strs[i + 1] for i in range(len(strs) - 1))


# Substring and copy operations
def substring(s: Any, start: Any, end: Any) -> MutableString:
    """(substring string start end) -> MutableString."""
    raw = string_val(_check_string(s, "substring"))
    if not isinstance(start, int) or not isinstance(end, int):
        raise TypeError("substring: start and end must be integers")
    if not (0 <= start <= end <= len(raw)):
        raise IndexError(
            f"substring: range {start}..{end} invalid for string of length {len(raw)}"
        )
    return MutableString(raw[start:end])


def string_copy(
    s: Any, start: Optional[Any] = None, end: Optional[Any] = None
) -> MutableString:
    """(string-copy string [start [end]]) -> MutableString."""
    raw = string_val(_check_string(s, "string-copy"))
    s_idx = 0 if start is None else start
    e_idx = len(raw) if end is None else end
    if not isinstance(s_idx, int) or not isinstance(e_idx, int):
        raise TypeError("string-copy: start and end must be integers")
    if not (0 <= s_idx <= e_idx <= len(raw)):
        raise IndexError(
            f"string-copy: range {s_idx}..{e_idx} invalid for string of length {len(raw)}"
        )
    return MutableString(raw[s_idx:e_idx])


def string_copy_bang(
    to_s: Any,
    at: Any,
    from_s: Any,
    start: Optional[Any] = None,
    end: Optional[Any] = None,
) -> Any:
    """(string-copy! to at from [start [end]])"""
    if not isinstance(to_s, MutableString):
        if isinstance(to_s, str):
            raise TypeError("string-copy!: cannot alter immutable string literal")
        raise TypeError(
            f"string-copy!: expected mutable string 'to', got {type(to_s).__name__}"
        )
    if not isinstance(at, int):
        raise TypeError("string-copy!: 'at' index must be integer")

    raw_from = string_val(_check_string(from_s, "string-copy!"))
    s_idx = 0 if start is None else start
    e_idx = len(raw_from) if end is None else end
    if not isinstance(s_idx, int) or not isinstance(e_idx, int):
        raise TypeError("string-copy!: start and end must be integers")
    if not (0 <= s_idx <= e_idx <= len(raw_from)):
        raise IndexError(
            f"string-copy!: from range {s_idx}..{e_idx} invalid for length {len(raw_from)}"
        )

    span = e_idx - s_idx
    if at < 0 or at + span > len(to_s):
        raise IndexError(
            f"string-copy!: destination range {at}..{at + span} exceeds target length {len(to_s)}"
        )

    for i in range(span):
        to_s[at + i] = raw_from[s_idx + i]
    return None


def string_fill_bang(
    s: Any,
    char: Any,
    start: Optional[Any] = None,
    end: Optional[Any] = None,
) -> Any:
    """(string-fill! string char [start [end]])"""
    if not isinstance(s, MutableString):
        if isinstance(s, str):
            raise TypeError("string-fill!: cannot alter immutable string literal")
        raise TypeError(
            f"string-fill!: expected mutable string, got {type(s).__name__}"
        )

    ch = _check_char(char, "string-fill!")
    s_idx = 0 if start is None else start
    e_idx = len(s) if end is None else end
    if not isinstance(s_idx, int) or not isinstance(e_idx, int):
        raise TypeError("string-fill!: start and end must be integers")
    if not (0 <= s_idx <= e_idx <= len(s)):
        raise IndexError(
            f"string-fill!: range {s_idx}..{e_idx} invalid for string of length {len(s)}"
        )

    for i in range(s_idx, e_idx):
        s[i] = ch
    return None


def string_append(*args: Any) -> MutableString:
    """(string-append s1 s2 ...) -> MutableString."""
    res_parts: List[str] = []
    for s in args:
        res_parts.append(string_val(_check_string(s, "string-append")))
    return MutableString("".join(res_parts))


# Conversions
def string_to_list(
    s: Any, start: Optional[Any] = None, end: Optional[Any] = None
) -> Any:
    """(string->list string [start [end]]) -> list of Char."""
    raw = string_val(_check_string(s, "string->list"))
    s_idx = 0 if start is None else start
    e_idx = len(raw) if end is None else end
    if not isinstance(s_idx, int) or not isinstance(e_idx, int):
        raise TypeError("string->list: start and end must be integers")
    if not (0 <= s_idx <= e_idx <= len(raw)):
        raise IndexError(
            f"string->list: range {s_idx}..{e_idx} invalid for string of length {len(raw)}"
        )
    chars = [Char(raw[i]) for i in range(s_idx, e_idx)]
    return to_lisp_list(chars)


def list_to_string(lst: Any) -> MutableString:
    """(list->string list-of-chars) -> MutableString."""
    py_list = to_py_list(lst)
    chars = [_check_char(c, "list->string").val for c in py_list]
    return MutableString("".join(chars))


def string_to_vector(
    s: Any, start: Optional[Any] = None, end: Optional[Any] = None
) -> Vector:
    """(string->vector string [start [end]]) -> Vector of Char."""
    raw = string_val(_check_string(s, "string->vector"))
    s_idx = 0 if start is None else start
    e_idx = len(raw) if end is None else end
    if not isinstance(s_idx, int) or not isinstance(e_idx, int):
        raise TypeError("string->vector: start and end must be integers")
    if not (0 <= s_idx <= e_idx <= len(raw)):
        raise IndexError(
            f"string->vector: range {s_idx}..{e_idx} invalid for string of length {len(raw)}"
        )
    chars = [Char(raw[i]) for i in range(s_idx, e_idx)]
    return Vector(chars)


def vector_to_string(
    vec: Any, start: Optional[Any] = None, end: Optional[Any] = None
) -> MutableString:
    """(vector->string vector [start [end]]) -> MutableString."""
    if not isinstance(vec, Vector):
        raise TypeError(f"vector->string: expected vector, got {type(vec).__name__}")
    s_idx = 0 if start is None else start
    e_idx = len(vec) if end is None else end
    if not isinstance(s_idx, int) or not isinstance(e_idx, int):
        raise TypeError("vector->string: start and end must be integers")
    if not (0 <= s_idx <= e_idx <= len(vec)):
        raise IndexError(
            f"vector->string: range {s_idx}..{e_idx} invalid for vector of length {len(vec)}"
        )
    chars = [_check_char(vec[i], "vector->string").val for i in range(s_idx, e_idx)]
    return MutableString("".join(chars))


# Case conversions
def string_upcase(s: Any) -> MutableString:
    """(string-upcase string) -> MutableString."""
    return MutableString(string_val(_check_string(s, "string-upcase")).upper())


def string_downcase(s: Any) -> MutableString:
    """(string-downcase string) -> MutableString."""
    return MutableString(string_val(_check_string(s, "string-downcase")).lower())


def string_foldcase(s: Any) -> MutableString:
    """(string-foldcase string) -> MutableString."""
    return MutableString(string_val(_check_string(s, "string-foldcase")).casefold())


# Iteration / Mapping
def string_map(proc: Any, *strings: Any) -> MutableString:
    """(string-map proc string1 string2 ...) -> MutableString."""
    if not strings:
        raise TypeError("string-map: requires at least one string argument")
    raw_strs = [string_val(_check_string(s, "string-map")) for s in strings]
    min_len = min(len(s) for s in raw_strs)
    result_chars: List[str] = []
    for i in range(min_len):
        args = [Char(s[i]) for s in raw_strs]
        res = proc(*args)
        ch = _check_char(res, "string-map")
        result_chars.append(ch.val)
    return MutableString("".join(result_chars))


def string_for_each(proc: Any, *strings: Any) -> Any:
    """(string-for-each proc string1 string2 ...)"""
    if not strings:
        raise TypeError("string-for-each: requires at least one string argument")
    raw_strs = [string_val(_check_string(s, "string-for-each")) for s in strings]
    min_len = min(len(s) for s in raw_strs)
    for i in range(min_len):
        args = [Char(s[i]) for s in raw_strs]
        proc(*args)
    return None
