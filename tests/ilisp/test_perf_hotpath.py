"""Regression, compatibility, and performance tests for ILISP Issue #939 (Phase 1)."""

from __future__ import annotations

import time
from pathlib import Path

import pytest

from ilisp import Symbol, run_string, to_py_list
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import LispSyntaxError, read_all, read_one
from ilisp.types import Cons, Primitive


class TestSpecialFormShadowingAndTCO:
    """Verify native special forms respect R7RS lexical shadowing and TCO."""

    def test_special_form_lexical_shadowing(self) -> None:
        assert run_string("(let ((and (lambda (a b) (+ a b)))) (and 3 4))") == 7
        assert run_string("(let ((or *)) (or 6 7))") == 42
        assert run_string("(let ((when list)) (when 1 2 3))") is not None
        assert to_py_list(run_string("(let ((when list)) (when 1 2 3))")) == [1, 2, 3]
        assert run_string("(let ((unless +)) (unless 10 20))") == 30
        assert run_string("(let ((case -)) (case 50 8))") == 42
        assert run_string("(let ((do *)) (do 7 8))") == 56
        assert run_string("(let ((=> #f)) (cond (#t =>)))") is False
        assert run_string("(let ((else #f)) (cond (else 1) (#t 99)))") == 99

    def test_let_star_duplicate_binding_closure_capture(self) -> None:
        code = """
        (let* ((x 1)
               (f (lambda () x))
               (x 2))
          (list (f) x))
        """
        assert to_py_list(run_string(code)) == [1, 2]

    def test_let_star_sequential_non_duplicate(self) -> None:
        code = """
        (let* ((a 1) (b (+ a 2)) (c (+ b 3)) (d (+ c 4)))
          (+ a b c d))
        """
        assert run_string(code) == 20

    def test_deep_tail_recursion_in_native_forms(self) -> None:
        code_when_and_or = """
        (define (loop-when n acc)
          (when (> n 0)
            (and #t
                 (or #f
                     (let ((nxt (- n 1)))
                       (if (= nxt 0) (+ acc 1) (loop-when nxt (+ acc 1))))))))
        (loop-when 20000 0)
        """
        assert run_string(code_when_and_or) == 20000

        code_named_let = """
        (let loop ((i 30000) (s 0))
          (case (modulo i 2)
            ((0) (if (= i 0) s (loop (- i 1) (+ s 2))))
            (else (loop (- i 1) (+ s 1)))))
        """
        assert run_string(code_named_let) == 45000

    def test_case_arrow_and_do_loop(self) -> None:
        code_case = """
        (list
          (case (+ 1 2)
            ((1 2) 'small)
            ((3 4) => (lambda (v) (* v 100)))
            (else 'other))
          (case 99
            ((1) 'one)
            (else => (lambda (v) (+ v 1))))
          (case 'b
            ((a) 1)
            ((b c) 2)))
        """
        assert to_py_list(run_string(code_case)) == [300, 100, 2]

        code_do = """
        (do ((i 0 (+ i 1))
             (sum 0 (+ sum i)))
            ((> i 10) sum))
        """
        assert run_string(code_do) == 55

        # Closure inside do captures per-iteration binding
        code_do_closure = """
        (let ((fns (do ((i 0 (+ i 1))
                        (acc '() (cons (lambda () i) acc)))
                       ((= i 3) (reverse acc)))))
          (map (lambda (f) (f)) fns))
        """
        assert to_py_list(run_string(code_do_closure)) == [0, 1, 2]


class TestNativeListAndHigherOrderPrimitives:
    """Verify native Python list and HOF primitives match R7RS semantics."""

    def test_cxr_not_overwritten_by_stdlib(self) -> None:
        env = make_initial_env(preload_stdlib=True)
        for sym_name in (
            "caar",
            "cadr",
            "cdar",
            "cddr",
            "length",
            "reverse",
            "append",
            "map",
            "for-each",
            "filter",
            "fold-left",
            "memq",
            "memv",
            "member",
            "assq",
            "assv",
            "assoc",
        ):
            assert type(env.lookup(Symbol.intern(sym_name))) is Primitive

    def test_append_edge_cases(self) -> None:
        assert run_string("(append)") is not None
        assert run_string("(null? (append))") is True
        assert run_string("(append 42)") == 42
        res = run_string("(append '(1 2) 3)")
        assert isinstance(res, Cons)
        assert res.car == 1 and res.cdr.car == 2 and res.cdr.cdr == 3

    def test_member_assoc_comparators_and_python_callables(self) -> None:
        code = """
        (list
          (member "B" '("a" "b" "c") string-ci=?)
          (assoc "KEY" '(("other" . 1) ("key" . 99)) string-ci=?)
          (memv 2 '(1 2 3))
          (assv 2 '((1 . a) (2 . b))))
        """
        res = to_py_list(run_string(code))
        assert to_py_list(res[0]) == ["b", "c"]
        assert res[1].car == "key" and res[1].cdr == 99
        assert to_py_list(res[2]) == [2, 3]
        assert res[3].cdr == Symbol.intern("b")

        env = make_initial_env(preload_stdlib=True)
        env.define(Symbol.intern("py-inc"), lambda x: x + 1)
        env.define(Symbol.intern("py-even"), lambda x: x % 2 == 0)
        assert to_py_list(eval_expr(read_one("(map py-inc '(1 2 3))"), env)) == [
            2,
            3,
            4,
        ]
        assert to_py_list(eval_expr(read_one("(filter py-even '(1 2 3 4))"), env)) == [
            2,
            4,
        ]

    def test_multi_list_map_and_for_each_shortest_stop(self) -> None:
        code = """
        (let ((sum 0))
          (for-each (lambda (a b) (set! sum (+ sum (* a b))))
                    '(1 2 3 4 5)
                    '(10 20 30))
          (list sum (map + '(1 2 3 4) '(10 20))))
        """
        res = to_py_list(run_string(code))
        assert res[0] == 140
        assert to_py_list(res[1]) == [11, 22]


class TestFastReaderEdgeCases:
    """Verify fast string scanner preserves SourceLocation, comments, labels, and errors."""

    def test_reader_syntax_and_locations(self) -> None:
        code = (
            ";; leading comment\n"
            "#| outer #| inner\n"
            "|# end |#\n"
            "  #;(discarded (+ 1 2))\n"
            "(#!fold-case HELLO\n"
            " #!no-fold-case World\n"
            ' "plain\nstring"\n'
            " |bar\\x20;sym|)"
        )
        res = read_one(code, filename="edge.scm")
        assert isinstance(res, Cons)
        assert res.loc is not None
        assert res.loc.file == "edge.scm"
        assert res.loc.line == 5
        assert res.loc.col == 1
        items = to_py_list(res)
        assert items[0] == Symbol.intern("hello")
        assert items[1] == Symbol.intern("World")
        assert items[2] == "plain\nstring"
        assert items[3] == Symbol.intern("bar sym")

    def test_reader_datum_labels_and_dot_interop(self) -> None:
        cyc = read_one("#0=(1 . #0#)")
        assert isinstance(cyc, Cons)
        assert cyc.car == 1 and cyc.cdr is cyc

        dot_ok = read_one("(. obj method 1)")
        assert isinstance(dot_ok, Cons)
        assert dot_ok.car == Symbol.intern(".")

        with pytest.raises(LispSyntaxError):
            read_one("( . b)")
        with pytest.raises(LispSyntaxError):
            read_one('"unterminated')
        with pytest.raises(LispSyntaxError):
            read_one("#| unterminated")

    def test_c_driver_runner_read_speed(self) -> None:
        runner = Path("ulisp/build/c_driver_runner.scm")
        if not runner.exists():
            pytest.skip("ulisp/build/c_driver_runner.scm not built")
        src = runner.read_text(encoding="utf-8")
        t0 = time.perf_counter()
        exprs = read_all(src, filename=str(runner))
        elapsed = time.perf_counter() - t0
        assert len(exprs) > 3000
        assert elapsed < 2.0, f"read_all took too long: {elapsed:.3f}s"
