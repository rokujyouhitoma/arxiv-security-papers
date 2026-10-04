"""Unit Test Suite for ILISP Standard Library (base.ilisp).

Tests control macros (let, let*, cond, and, or, when, unless),
higher-order list functions (map, filter, fold-left, for-each),
and association list primitives.
"""

from __future__ import annotations

import tempfile

from ilisp import Symbol, run_string, to_py_list


class TestControlMacros:
    """Tests for let, let*, cond, and, or, when, unless macros."""

    def test_when(self) -> None:
        code = """
        (let ((x 0))
          (when (= 1 1)
            (set! x 10)
            (set! x (+ x 5)))
          x)
        """
        assert run_string(code) == 15

        code_falsy = """
        (let ((x 0))
          (when (= 1 2)
            (set! x 99))
          x)
        """
        assert run_string(code_falsy) == 0

    def test_unless(self) -> None:
        code = """
        (let ((x "initial"))
          (unless (= 1 2)
            (set! x "changed"))
          x)
        """
        assert run_string(code) == "changed"

        code_falsy = """
        (let ((x "initial"))
          (unless (= 1 1)
            (set! x "changed"))
          x)
        """
        assert run_string(code_falsy) == "initial"

    def test_let(self) -> None:
        code = """
        (let ((a 10)
              (b 20)
              (c 30))
          (+ a b c))
        """
        assert run_string(code) == 60

    def test_let_star(self) -> None:
        code = """
        (let* ((a 10)
               (b (+ a 5))
               (c (* b 2)))
          c)
        """
        assert run_string(code) == 30

    def test_cond(self) -> None:
        code1 = """
        (cond
          ((= 1 2) 'first)
          ((= 2 3) 'second)
          ((= 3 3) 'third)
          (else 'fallback))
        """
        assert run_string(code1) == Symbol.intern("third")

        code_else = """
        (cond
          ((= 1 2) 'first)
          ((= 2 3) 'second)
          (else 'fallback))
        """
        assert run_string(code_else) == Symbol.intern("fallback")

    def test_and(self) -> None:
        assert run_string("(and)") is True
        assert run_string("(and 10)") == 10
        assert run_string("(and 10 20 30)") == 30
        assert run_string("(and 10 #f 30)") is False

        # Short-circuit verification
        code = """
        (let ((x 0))
          (and #f (set! x 100))
          x)
        """
        assert run_string(code) == 0

    def test_or(self) -> None:
        assert run_string("(or)") is False
        assert run_string("(or 42)") == 42
        assert run_string("(or #f 10 20)") == 10
        assert run_string("(or #f #f #f)") is False

        # Short-circuit verification
        code = """
        (let ((x 0))
          (or 100 (set! x 999))
          x)
        """
        assert run_string(code) == 0


class TestListAndHigherOrderFunctions:
    """Tests for map, filter, fold-left, reverse, length, append."""

    def test_accessors(self) -> None:
        code = """
        (let ((nested '((1 2) (3 4))))
          (list (caar nested)
                (cadr (car nested))
                (car (cdar nested))
                (caar (cdr nested))))
        """
        assert to_py_list(run_string(code)) == [1, 2, 2, 3]

    def test_length_and_reverse(self) -> None:
        assert run_string("(length '())") == 0
        assert run_string("(length '(1 2 3 4 5))") == 5
        assert to_py_list(run_string("(reverse '(1 2 3))")) == [3, 2, 1]
        assert to_py_list(run_string("(reverse '())")) == []

    def test_append(self) -> None:
        assert to_py_list(run_string("(append '(1 2) '(3 4))")) == [1, 2, 3, 4]
        assert to_py_list(run_string("(append '() '(a b))")) == [
            Symbol.intern("a"),
            Symbol.intern("b"),
        ]

    def test_map(self) -> None:
        code = "(map (lambda (x) (* x x)) '(1 2 3 4))"
        assert to_py_list(run_string(code)) == [1, 4, 9, 16]

    def test_filter(self) -> None:
        code = "(filter (lambda (x) (> x 2)) '(1 2 3 4 5))"
        assert to_py_list(run_string(code)) == [3, 4, 5]

    def test_fold_left(self) -> None:
        code_sum = "(fold-left + 0 '(1 2 3 4 5))"
        assert run_string(code_sum) == 15

        code_reverse = "(fold-left (lambda (acc x) (cons x acc)) '() '(1 2 3))"
        assert to_py_list(run_string(code_reverse)) == [3, 2, 1]

    def test_for_each(self) -> None:
        code = """
        (let ((total 0))
          (for-each (lambda (n) (set! total (+ total n))) '(10 20 30))
          total)
        """
        assert run_string(code) == 60


class TestSearchingAndAlist:
    """Tests for member, memq, assoc, assq."""

    def test_memq_and_member(self) -> None:
        assert to_py_list(run_string("(memq 'b '(a b c d))")) == [
            Symbol.intern("b"),
            Symbol.intern("c"),
            Symbol.intern("d"),
        ]
        assert run_string("(memq 'z '(a b c d))") is False
        assert to_py_list(run_string("(member 20 '(10 20 30))")) == [20, 30]

    def test_assoc_and_assq(self) -> None:
        code = """
        (let ((dict (list (cons 'title "Zero-Trust")
                          (cons 'year 2026)
                          (cons 'active #t))))
          (list (cdr (assq 'year dict))
                (cdr (assoc 'title dict))
                (assq 'missing dict)))
        """
        res = to_py_list(run_string(code))
        assert res[0] == 2026
        assert res[1] == "Zero-Trust"
        assert res[2] is False


class TestLoadPrimitive:
    """Tests for dynamic code loading via (load "path")."""

    def test_load_external_file(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".ilisp", delete=False) as f:
            f.write("(define (multiply-triple x) (* x 3))\n")
            filepath = f.name

        code = f"""
        (begin
          (load "{filepath}")
          (multiply-triple 15))
        """
        assert run_string(code) == 45
