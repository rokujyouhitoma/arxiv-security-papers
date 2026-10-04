"""Unit and integration tests for R7RS Characters and Strings in ILISP."""

from typing import Any

import pytest

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all, read_one
from ilisp.types import Char, is_char, is_string


def run_code(code: str) -> Any:
    """Helper to evaluate ILISP code with standard environment."""
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    res = None
    for e in exprs:
        res = eval_expr(e, env)
    return res


class TestCharLiteralsAndPredicates:
    """Test character literals and basic predicates."""

    def test_single_char_literals(self) -> None:
        c1 = read_one(r"#\a")
        assert is_char(c1)
        assert c1.val == "a"
        assert repr(c1) == r"#\a"

        c2 = read_one(r"#\(")
        assert is_char(c2)
        assert c2.val == "("

        c3 = read_one(r"#\Z")
        assert is_char(c3)
        assert c3.val == "Z"

    def test_named_char_literals(self) -> None:
        space = read_one(r"#\space")
        assert is_char(space)
        assert space.val == " "
        assert repr(space) == r"#\space"

        newline = read_one(r"#\newline")
        assert is_char(newline)
        assert newline.val == "\n"
        assert repr(newline) == r"#\newline"

        tab = read_one(r"#\tab")
        assert is_char(tab)
        assert tab.val == "\t"

        alarm = read_one(r"#\alarm")
        assert is_char(alarm)
        assert alarm.val == "\a"

        escape = read_one(r"#\escape")
        assert is_char(escape)
        assert escape.val == "\x1b"

        delete = read_one(r"#\delete")
        assert is_char(delete)
        assert delete.val == "\x7f"

    def test_hex_scalar_literals(self) -> None:
        c = read_one(r"#\x41")
        assert is_char(c)
        assert c.val == "A"

        c_jp = read_one(r"#\x3042")
        assert is_char(c_jp)
        assert c_jp.val == "あ"

    def test_char_predicate_and_equality(self) -> None:
        assert run_code(r"(char? #\a)") is True
        assert run_code(r'(char? "a")') is False
        assert run_code(r"(char? 123)") is False

        assert run_code(r"(char=? #\a #\a)") is True
        assert run_code(r"(char=? #\a #\b)") is False
        assert run_code(r"(char=? #\a #\a #\a)") is True

        assert run_code(r"(char<? #\a #\b #\c)") is True
        assert run_code(r"(char<? #\a #\a)") is False
        assert run_code(r"(char>? #\z #\y #\x)") is True
        assert run_code(r"(char<=? #\a #\a #\b)") is True
        assert run_code(r"(char>=? #\b #\b #\a)") is True

    def test_char_ci_comparisons(self) -> None:
        assert run_code(r"(char-ci=? #\a #\A)") is True
        assert run_code(r"(char-ci=? #\a #\A #\a)") is True
        assert run_code(r"(char-ci<? #\A #\b #\C)") is True
        assert run_code(r"(char-ci>? #\C #\b #\A)") is True
        assert run_code(r"(char-ci<=? #\a #\A #\B)") is True
        assert run_code(r"(char-ci>=? #\B #\b #\A)") is True

    def test_char_classification_predicates(self) -> None:
        assert run_code(r"(char-alphabetic? #\a)") is True
        assert run_code(r"(char-alphabetic? #\1)") is False
        assert run_code(r"(char-numeric? #\1)") is True
        assert run_code(r"(char-numeric? #\a)") is False
        assert run_code(r"(char-whitespace? #\space)") is True
        assert run_code(r"(char-whitespace? #\tab)") is True
        assert run_code(r"(char-whitespace? #\newline)") is True
        assert run_code(r"(char-whitespace? #\a)") is False
        assert run_code(r"(char-upper-case? #\A)") is True
        assert run_code(r"(char-upper-case? #\a)") is False
        assert run_code(r"(char-lower-case? #\a)") is True
        assert run_code(r"(char-lower-case? #\A)") is False

    def test_digit_value(self) -> None:
        assert run_code(r"(digit-value #\0)") == 0
        assert run_code(r"(digit-value #\9)") == 9
        assert run_code(r"(digit-value #\5)") == 5
        assert run_code(r"(digit-value #\a)") is False

    def test_char_integer_conversions(self) -> None:
        assert run_code(r"(char->integer #\a)") == 97
        assert run_code(r"(integer->char 97)") == Char("a")
        assert run_code(r"(integer->char (char->integer #\z))") == Char("z")

    def test_char_case_mappings(self) -> None:
        assert run_code(r"(char-upcase #\a)") == Char("A")
        assert run_code(r"(char-downcase #\A)") == Char("a")
        assert run_code(r"(char-foldcase #\A)") == Char("a")


class TestStringPrimitives:
    """Test R7RS string constructors, predicates, accessors, and mutations."""

    def test_string_predicate(self) -> None:
        assert run_code(r'(string? "hello")') is True
        assert run_code(r"(string? (make-string 3))") is True
        assert run_code(r"(string? #\a)") is False
        assert run_code(r"(string? '(a b c))") is False

    def test_make_string_and_string_constructor(self) -> None:
        s1 = run_code(r"(make-string 3 #\x)")
        assert is_string(s1)
        assert str(s1) == "xxx"

        s2 = run_code(r"(string #\H #\e #\l #\l #\o)")
        assert is_string(s2)
        assert str(s2) == "Hello"

    def test_string_length_and_ref(self) -> None:
        assert run_code(r'(string-length "hello")') == 5
        assert run_code(r'(string-length "")') == 0
        assert run_code(r'(string-ref "hello" 1)') == Char("e")
        assert run_code(r'(string-ref "hello" 4)') == Char("o")

    def test_string_mutation_and_immutability_guard(self) -> None:
        # String literal is immutable in R7RS; altering it must raise an error
        with pytest.raises(Exception):
            run_code(r'(string-set! "hello" 0 #\y)')

        # Mutable strings created by make-string or string-copy can be mutated
        res = run_code(r"""
            (let ((s (make-string 3 #\a)))
              (string-set! s 1 #\b)
              s)
            """)
        assert str(res) == "aba"

    def test_string_comparisons(self) -> None:
        assert run_code(r'(string=? "abc" "abc")') is True
        assert run_code(r'(string=? "abc" "def")') is False
        assert run_code(r'(string<? "abc" "abd")') is True
        assert run_code(r'(string>? "def" "abc")') is True
        assert run_code(r'(string<=? "abc" "abc" "abd")') is True
        assert run_code(r'(string>=? "abd" "abc" "abc")') is True

    def test_string_ci_comparisons(self) -> None:
        assert run_code(r'(string-ci=? "abc" "ABC")') is True
        assert run_code(r'(string-ci<? "ABC" "abd")') is True
        assert run_code(r'(string-ci>? "DEF" "abc")') is True
        assert run_code(r'(string-ci<=? "abc" "ABC" "def")') is True
        assert run_code(r'(string-ci>=? "def" "ABC" "abc")') is True

    def test_substring_and_copy(self) -> None:
        assert str(run_code(r'(substring "hello world" 0 5)')) == "hello"
        assert str(run_code(r'(substring "hello world" 6 11)')) == "world"

        assert str(run_code(r'(string-copy "hello")')) == "hello"
        assert str(run_code(r'(string-copy "hello world" 6)')) == "world"
        assert str(run_code(r'(string-copy "hello world" 0 5)')) == "hello"

    def test_string_copy_bang_and_fill_bang(self) -> None:
        res1 = run_code(r"""
            (let ((s (make-string 5 #\a)))
              (string-copy! s 1 "xyz" 0 3)
              s)
            """)
        assert str(res1) == "axyza"

        res2 = run_code(r"""
            (let ((s (make-string 5 #\a)))
              (string-fill! s #\z 1 4)
              s)
            """)
        assert str(res2) == "azzza"

    def test_string_append(self) -> None:
        assert str(run_code(r'(string-append "foo" "bar" "baz")')) == "foobarbaz"
        assert str(run_code(r"(string-append)")) == ""

    def test_string_case_mappings(self) -> None:
        assert str(run_code(r'(string-upcase "hello")')) == "HELLO"
        assert str(run_code(r'(string-downcase "HELLO")')) == "hello"
        assert str(run_code(r'(string-foldcase "HeLLo")')) == "hello"

    def test_string_list_vector_conversions(self) -> None:
        # string->list and list->string
        res_list = run_code(r'(string->list "abc")')
        from ilisp.types import to_py_list

        py_chars = to_py_list(res_list)
        assert py_chars == [Char("a"), Char("b"), Char("c")]

        assert str(run_code(r"(list->string (list #\a #\b #\c))")) == "abc"

        # string->vector and vector->string
        vec = run_code(r'(string->vector "abc")')
        assert list(vec) == [Char("a"), Char("b"), Char("c")]

        assert str(run_code(r"(vector->string (vector #\x #\y #\z))")) == "xyz"

    def test_string_map_and_for_each(self) -> None:
        res = run_code(r"""
            (string-map (lambda (c) (char-upcase c)) "hello")
            """)
        assert str(res) == "HELLO"

        # Multi-string string-map
        res2 = run_code(r"""
            (string-map (lambda (c1 c2) c1) "abc" "xyz")
            """)
        assert str(res2) == "abc"


class TestEqualityPredicates:
    """Test Scheme eq?, eqv?, and recursive structural equal?."""

    def test_eqv_on_chars(self) -> None:
        assert run_code(r"(eqv? #\a #\a)") is True
        assert run_code(r"(eqv? #\a #\b)") is False
        assert run_code(r'(eqv? #\a "a")') is False

    def test_equal_structural_equivalence(self) -> None:
        # String equality
        assert run_code(r'(equal? "abc" (string #\a #\b #\c))') is True
        # List containing strings and chars
        assert run_code(r'(equal? (list #\a "foo") (list #\a "foo"))') is True
        assert run_code(r'(equal? (list #\a "foo") (list #\b "foo"))') is False
        # Vector containing chars
        assert run_code(r"(equal? (vector #\a #\b) (vector #\a #\b))") is True


class TestModuleCharIntegration:
    """Test importing and using (scheme char) library."""

    def test_import_scheme_char(self) -> None:
        res = run_code(r"""
            (import (scheme char))
            (char-ci=? #\a #\A)
            """)
        assert res is True

        res2 = run_code(r"""
            (import (scheme char))
            (string-upcase "world")
            """)
        assert str(res2) == "WORLD"


class TestBackendACharIntegration:
    """Test Python AST compilation with Char literals and operations."""

    def test_py_codegen_char_literal(self) -> None:
        env = make_initial_env(preload_stdlib=True)
        res = compile_ilisp(r"(define x #\z) x", env=env)
        assert res == Char("z")

    def test_py_codegen_string_and_char_ops(self) -> None:
        code = r"""
        (define s (make-string 4 #\a))
        (string-set! s 2 #\x)
        (string-ref s 2)
        """
        env = make_initial_env(preload_stdlib=True)
        res = compile_ilisp(code, env=env)
        assert res == Char("x")
