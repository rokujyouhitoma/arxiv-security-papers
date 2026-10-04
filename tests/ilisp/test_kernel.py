"""Comprehensive Unit Test Suite for Kernel ILISP (Phase 1).

Tests all 23 core primitives, 6 special forms, Reader with source locations,
SequenceView zero-copy interop, Trampoline TCO, and define-macro.
"""

from __future__ import annotations

import pytest

from ilisp import (
    NIL,
    Cell,
    Cons,
    LispSyntaxError,
    SequenceView,
    Symbol,
    read_one,
    run_string,
    to_py_list,
)


class TestReader:
    """Tests for hand-written recursive descent S-expression Reader."""

    def test_read_numbers(self) -> None:
        assert read_one("42") == 42
        assert read_one("-17") == -17
        assert read_one("0x2a") == 42
        assert read_one("3.14") == 3.14

    def test_read_booleans_and_chars(self) -> None:
        assert read_one("#t") is True
        assert read_one("#f") is False
        assert read_one("#\\a") == "a"
        assert read_one("#\\space") == " "
        assert read_one("#\\newline") == "\n"

    def test_read_strings(self) -> None:
        assert read_one('"hello world"') == "hello world"
        assert read_one('"line1\\nline2"') == "line1\nline2"
        assert read_one('"tab\\tquote\\""') == 'tab\tquote"'

    def test_read_symbols(self) -> None:
        sym = read_one("foo-bar_123")
        assert isinstance(sym, Symbol)
        assert sym.name == "foo-bar_123"
        assert sym is Symbol.intern("foo-bar_123")

    def test_read_lists_and_dotted_pairs(self) -> None:
        res = read_one("(1 2 3)")
        assert isinstance(res, Cons)
        assert to_py_list(res) == [1, 2, 3]

        dotted = read_one("(a . b)")
        assert isinstance(dotted, Cons)
        assert dotted.car == Symbol.intern("a")
        assert dotted.cdr == Symbol.intern("b")

    def test_reader_macros(self) -> None:
        q = read_one("'x")
        assert repr(q) == "(quote x)"

        qq = read_one("`(a ,b ,@c)")
        assert repr(qq) == "(quasiquote (a (unquote b) (unquote-splicing c)))"

    def test_comments(self) -> None:
        code = """
        ; Line comment
        (1 ; inline comment
         2 #; (discarded-sexp 3 4)
         5)
        """
        res = read_one(code)
        assert to_py_list(res) == [1, 2, 5]

    def test_source_locations(self) -> None:
        datum = read_one("(+ 1 2)", filename="test.scm")
        assert isinstance(datum, Cons)
        assert datum.loc is not None
        assert datum.loc.file == "test.scm"
        assert datum.loc.line == 1

    def test_syntax_errors(self) -> None:
        with pytest.raises(LispSyntaxError):
            read_one("(1 2")
        with pytest.raises(LispSyntaxError):
            read_one(")")
        with pytest.raises(LispSyntaxError):
            read_one('"unclosed string')


class TestTypesAndSequenceView:
    """Tests for Core AST types, Cell boxing, and SequenceView."""

    def test_nil(self) -> None:
        assert repr(NIL) == "()"
        assert bool(NIL) is True
        assert len(NIL) == 0

    def test_cell(self) -> None:
        c = Cell(10)
        assert c.get() == 10
        c.set(20)
        assert c.get() == 20

    def test_sequence_view(self) -> None:
        py_list = [10, 20, 30]
        view = SequenceView(py_list)
        assert len(view) == 3
        assert view.car == 10
        cdr_view = view.cdr
        assert isinstance(cdr_view, SequenceView)
        assert cdr_view.car == 20
        assert cdr_view.cdr.car == 30
        assert cdr_view.cdr.cdr is NIL


class TestCorePrimitives:
    """Tests for all 23 core primitives and arithmetic/relational operators."""

    def test_pair_and_list_primitives(self) -> None:
        assert run_string("(cons 1 2)") == Cons(1, 2)
        assert run_string("(car (cons 1 2))") == 1
        assert run_string("(cdr (cons 1 2))") == 2
        assert run_string("(pair? (cons 1 2))") is True
        assert run_string("(pair? '())") is False
        assert run_string("(null? '())") is True
        assert run_string("(null? (cons 1 2))") is False
        assert to_py_list(run_string("(list 1 2 3)")) == [1, 2, 3]

    def test_symbol_and_string_primitives(self) -> None:
        assert run_string("(symbol? 'foo)") is True
        assert run_string('(symbol? "foo")') is False
        assert run_string("(symbol->string 'hello)") == "hello"
        assert run_string('(string? "abc")') is True
        assert run_string("(string? 'abc)") is False
        assert run_string('(string-append "foo" "bar")') == "foobar"
        assert run_string('(string=? "abc" "abc")') is True
        assert run_string('(string=? "abc" "def")') is False

    def test_equality_and_boolean_primitives(self) -> None:
        assert run_string("(eq? 'a 'a)") is True
        assert run_string("(eq? 'a 'b)") is False
        assert run_string("(eq? '() '())") is True
        assert run_string("(eqv? 42 42)") is True
        assert run_string("(eqv? 42 42.0)") is False
        assert run_string("(boolean? #t)") is True
        assert run_string("(boolean? 0)") is False
        assert run_string("(not #f)") is True
        assert run_string("(not #t)") is False
        assert run_string("(not '())") is False
        assert run_string("(not 0)") is False

    def test_arithmetic_and_comparison_primitives(self) -> None:
        assert run_string("(+ 1 2 3 4)") == 10
        assert run_string("(- 10 3 2)") == 5
        assert run_string("(- 5)") == -5
        assert run_string("(* 2 3 4)") == 24
        assert run_string("(quotient 14 3)") == 4
        assert run_string("(remainder 14 3)") == 2
        assert run_string("(= 10 10)") is True
        assert run_string("(= 10 20)") is False
        assert run_string("(< 5 10)") is True
        assert run_string("(> 5 10)") is False


class TestSpecialFormsAndClosures:
    """Tests for quote, if, lambda, define, set!, begin."""

    def test_quote(self) -> None:
        assert run_string("'hello") == Symbol.intern("hello")
        assert repr(run_string("'(1 2 3)")) == "(1 2 3)"

    def test_if(self) -> None:
        assert run_string("(if #t 10 20)") == 10
        assert run_string("(if #f 10 20)") == 20
        assert run_string("(if 0 10 20)") == 10  # 0 is truthy in Scheme!
        assert run_string("(if '() 10 20)") == 10  # '() is truthy in Scheme!
        assert run_string("(if #f 10)") is NIL

    def test_begin(self) -> None:
        assert run_string("(begin 1 2 3)") == 3

    def test_define_and_set(self) -> None:
        code = """
        (begin
          (define x 100)
          (set! x 200)
          x)
        """
        assert run_string(code) == 200

    def test_lambda_and_closures(self) -> None:
        code = """
        (begin
          (define (make-adder x)
            (lambda (y) (+ x y)))
          (define add5 (make-adder 5))
          (add5 10))
        """
        assert run_string(code) == 15

    def test_closure_mutation_state(self) -> None:
        code = """
        (begin
          (define (make-counter)
            (define n 0)
            (lambda ()
              (set! n (+ n 1))
              n))
          (define c1 (make-counter))
          (c1)
          (c1)
          (c1))
        """
        assert run_string(code) == 3

    def test_varargs_and_dotted_parameters(self) -> None:
        code = """
        (begin
          (define (f head . rest)
            (cons head rest))
          (f 1 2 3 4))
        """
        res = run_string(code)
        assert repr(res) == "(1 2 3 4)"


class TestTrampolineTCO:
    """Tests for Tail Call Optimization preventing Python call stack overflow."""

    def test_deep_tail_recursion(self) -> None:
        # Standard Python recursion depth limit is 1000.
        # This test runs 5,000 iterations in constant stack space.
        code = """
        (begin
          (define (loop n acc)
            (if (= n 0)
                acc
                (loop (- n 1) (+ acc 1))))
          (loop 5000 0))
        """
        assert run_string(code) == 5000


class TestMacroExpansion:
    """Tests for define-macro syntax substitution."""

    def test_when_macro(self) -> None:
        code = """
        (begin
          (define-macro (when-m test . body)
            (cons 'if (cons test (cons (cons 'begin body) '()))))
          (define x 0)
          (when-m (= 1 1)
            (set! x 10)
            (set! x (+ x 5)))
          x)
        """
        assert run_string(code) == 15

    def test_unless_macro(self) -> None:
        code = """
        (begin
          (define-macro (unless-m test . body)
            (cons 'if (cons test (cons '() (cons (cons 'begin body) '())))))
          (define result "initial")
          (unless-m (= 1 2)
            (set! result "executed"))
          result)
        """
        assert run_string(code) == "executed"


class TestPythonInterop:
    """Tests for Python zero-copy SequenceView and py-* functions."""

    def test_sequence_view_interop(self) -> None:
        code = """
        (begin
          (define lst (py-eval "[100, 200, 300]"))
          (define v (sequence-view lst))
          (+ (car v) (car (cdr v))))
        """
        assert run_string(code) == 300

    def test_py_import_and_call(self) -> None:
        code = """
        (begin
          (define math (py-import 'math))
          (py-call math 'sqrt 16))
        """
        assert run_string(code) == 4.0
