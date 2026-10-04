"""Comprehensive tests for R7RS 6.6 & 7.1.1 (scheme char) library."""

from typing import Any

from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import Char


def eval_code(code: str) -> Any:
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    result = None
    for expr in exprs:
        result = eval_expr(expr, env)
    return result


def test_char_classification_predicates() -> None:
    """Test char-alphabetic?, char-numeric?, char-whitespace?, char-upper-case?, char-lower-case?."""
    assert eval_code("(char-alphabetic? #\\a)") is True
    assert eval_code("(char-alphabetic? #\\Z)") is True
    assert eval_code("(char-alphabetic? #\\0)") is False

    assert eval_code("(char-numeric? #\\0)") is True
    assert eval_code("(char-numeric? #\\9)") is True
    assert eval_code("(char-numeric? #\\a)") is False

    assert eval_code("(char-whitespace? #\\space)") is True
    assert eval_code("(char-whitespace? #\\newline)") is True
    assert eval_code("(char-whitespace? #\\tab)") is True
    assert eval_code("(char-whitespace? #\\x)") is False

    assert eval_code("(char-upper-case? #\\A)") is True
    assert eval_code("(char-upper-case? #\\a)") is False

    assert eval_code("(char-lower-case? #\\a)") is True
    assert eval_code("(char-lower-case? #\\A)") is False


def test_digit_value() -> None:
    """Test (digit-value c) returns integer 0..9 or #f."""
    for i in range(10):
        assert eval_code(f"(digit-value #\\{i})") == i

    assert eval_code("(digit-value #\\a)") is False
    assert eval_code("(digit-value #\\space)") is False


def test_char_case_conversions() -> None:
    """Test char-upcase, char-downcase, char-foldcase."""
    assert eval_code("(char-upcase #\\a)") == Char("A")
    assert eval_code("(char-upcase #\\A)") == Char("A")

    assert eval_code("(char-downcase #\\Z)") == Char("z")
    assert eval_code("(char-downcase #\\z)") == Char("z")

    assert eval_code("(char-foldcase #\\A)") == Char("a")
    assert eval_code("(char-foldcase #\\a)") == Char("a")


def test_char_case_insensitive_comparisons() -> None:
    """Test char-ci=?, char-ci<?, char-ci>?, char-ci<=?, char-ci>=? with multiple args."""
    assert eval_code("(char-ci=? #\\a #\\A #\\a)") is True
    assert eval_code("(char-ci=? #\\a #\\b)") is False

    assert eval_code("(char-ci<? #\\a #\\B #\\c)") is True
    assert eval_code("(char-ci<? #\\a #\\A)") is False

    assert eval_code("(char-ci>? #\\z #\\Y #\\x)") is True
    assert eval_code("(char-ci>? #\\x #\\X)") is False

    assert eval_code("(char-ci<=? #\\a #\\A #\\b #\\B)") is True
    assert eval_code("(char-ci>=? #\\b #\\B #\\a #\\A)") is True


def test_string_case_conversions() -> None:
    """Test string-upcase, string-downcase, string-foldcase."""
    assert str(eval_code('(string-upcase "Hello, World 123!")')) == "HELLO, WORLD 123!"
    assert (
        str(eval_code('(string-downcase "Hello, World 123!")')) == "hello, world 123!"
    )
    assert str(eval_code('(string-foldcase "Straße")')) == "strasse"


def test_string_case_insensitive_comparisons() -> None:
    """Test string-ci=?, string-ci<?, string-ci>?, string-ci<=?, string-ci>=?."""
    assert eval_code('(string-ci=? "abc" "ABC" "AbC")') is True
    assert eval_code('(string-ci=? "abc" "abd")') is False

    assert eval_code('(string-ci<? "abc" "DEF" "ghi")') is True
    assert eval_code('(string-ci<? "abc" "ABC")') is False

    assert eval_code('(string-ci>? "zzz" "YYY" "xxx")') is True
    assert eval_code('(string-ci>? "zzz" "ZZZ")') is False

    assert eval_code('(string-ci<=? "abc" "ABC" "def" "DEF")') is True
    assert eval_code('(string-ci>=? "def" "DEF" "abc" "ABC")') is True


def test_scheme_char_full_import() -> None:
    """Test importing all 17 identifiers from (scheme char) library."""
    code = """
    (import (scheme char))
    (list
      (char-alphabetic? #\\m)
      (digit-value #\\7)
      (char-ci=? #\\x #\\X)
      (string-ci=? "scheme" "SCHEME"))
    """
    res = eval_code(code)
    from ilisp.types import to_py_list

    assert to_py_list(res) == [True, 7, True, True]


def test_scheme_char_prefix_import() -> None:
    """Test importing (scheme char) with prefix modifier."""
    code = """
    (import (prefix (scheme char) ch:))
    (list
      (ch:char-upcase #\\k)
      (ch:string-upcase "ilisp"))
    """
    res = eval_code(code)
    from ilisp.types import to_py_list

    assert to_py_list(res) == [Char("K"), "ILISP"]
