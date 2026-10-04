"""Unit and integration tests for R7RS Vector Extensions in ILISP (R7RS 6.8)."""

from typing import Any

import pytest

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import Vector


def run_code(code: str) -> Any:
    """Helper to evaluate ILISP code with standard environment."""
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    res = None
    for e in exprs:
        res = eval_expr(e, env)
    return res


class TestVectorCopy:
    """Tests for vector-copy primitive."""

    def test_vector_copy_full(self) -> None:
        res = run_code("""
            (define v #(1 2 3 4 5))
            (define v2 (vector-copy v))
            (vector-set! v 0 99)
            (list (vector-ref v 0) (vector-ref v2 0) (vector-length v2))
            """)
        # to_py_list or lisp list comparison
        from ilisp.types import to_py_list

        assert to_py_list(res) == [99, 1, 5]

    def test_vector_copy_slice(self) -> None:
        res = run_code("""
            (define v #(10 20 30 40 50))
            (define sub (vector-copy v 1 4))
            (vector->list sub)
            """)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [20, 30, 40]

    def test_vector_copy_start_only(self) -> None:
        res = run_code("""
            (define v #(10 20 30 40 50))
            (define sub (vector-copy v 2))
            (vector->list sub)
            """)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [30, 40, 50]

    def test_vector_copy_empty_slice(self) -> None:
        res = run_code("""
            (define v #(1 2 3))
            (define sub (vector-copy v 1 1))
            (vector-length sub)
            """)
        assert res == 0

    def test_vector_copy_invalid_range(self) -> None:
        with pytest.raises(IndexError):
            run_code("(vector-copy #(1 2 3) 2 1)")
        with pytest.raises(IndexError):
            run_code("(vector-copy #(1 2 3) -1 2)")
        with pytest.raises(IndexError):
            run_code("(vector-copy #(1 2 3) 0 5)")


class TestVectorCopyBang:
    """Tests for vector-copy! primitive."""

    def test_vector_copy_bang_basic(self) -> None:
        res = run_code("""
            (define to (vector 1 2 3 4 5))
            (define from #(10 20 30))
            (vector-copy! to 1 from 0 2)
            (vector->list to)
            """)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [1, 10, 20, 4, 5]

    def test_vector_copy_bang_overlap_shift_right(self) -> None:
        # Shift elements right: [1, 2, 3, 4, 5] -> copy [0..3] to at=2 -> [1, 2, 1, 2, 3]
        res = run_code("""
            (define v (vector 1 2 3 4 5))
            (vector-copy! v 2 v 0 3)
            (vector->list v)
            """)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [1, 2, 1, 2, 3]

    def test_vector_copy_bang_overlap_shift_left(self) -> None:
        # Shift elements left: [1, 2, 3, 4, 5] -> copy [2..5] to at=0 -> [3, 4, 5, 4, 5]
        res = run_code("""
            (define v (vector 1 2 3 4 5))
            (vector-copy! v 0 v 2 5)
            (vector->list v)
            """)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [3, 4, 5, 4, 5]

    def test_vector_copy_bang_bounds_error(self) -> None:
        with pytest.raises(IndexError):
            # Target range exceeds destination vector length
            run_code("""
                (define to (vector 1 2))
                (define from #(10 20 30))
                (vector-copy! to 1 from 0 3)
                """)


class TestVectorFillBang:
    """Tests for vector-fill! primitive."""

    def test_vector_fill_bang_all(self) -> None:
        res = run_code("""
            (define v (vector 1 2 3 4))
            (vector-fill! v 99)
            (vector->list v)
            """)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [99, 99, 99, 99]

    def test_vector_fill_bang_slice(self) -> None:
        res = run_code("""
            (define v (vector 1 2 3 4 5))
            (vector-fill! v 0 1 4)
            (vector->list v)
            """)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [1, 0, 0, 0, 5]


class TestVectorAppend:
    """Tests for vector-append primitive."""

    def test_vector_append_empty(self) -> None:
        res = run_code("(vector-append)")
        assert isinstance(res, Vector)
        assert len(res) == 0

    def test_vector_append_multiple(self) -> None:
        res = run_code("""
            (define v1 #(1 2))
            (define v2 #())
            (define v3 #(3 4 5))
            (vector->list (vector-append v1 v2 v3))
            """)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [1, 2, 3, 4, 5]


class TestVectorMapAndForEach:
    """Tests for vector-map and vector-for-each primitives."""

    def test_vector_map_single(self) -> None:
        res = run_code("""
            (define v #(1 2 3 4))
            (define mapped (vector-map (lambda (x) (* x 10)) v))
            (vector->list mapped)
            """)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [10, 20, 30, 40]

    def test_vector_map_multiple_and_different_lengths(self) -> None:
        # Truncates to minimum length
        res = run_code("""
            (define v1 #(1 2 3 4 5))
            (define v2 #(10 20 30))
            (define res (vector-map (lambda (a b) (+ a b)) v1 v2))
            (vector->list res)
            """)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [11, 22, 33]

    def test_vector_for_each(self) -> None:
        res = run_code("""
            (define acc 0)
            (define v #(10 20 30 40))
            (vector-for-each (lambda (x) (set! acc (+ acc x))) v)
            acc
            """)
        assert res == 100

    def test_vector_for_each_multiple(self) -> None:
        res = run_code("""
            (define acc 0)
            (define v1 #(1 2 3))
            (define v2 #(10 20 30 40))
            (vector-for-each (lambda (a b) (set! acc (+ acc (* a b)))) v1 v2)
            acc
            """)
        # 1*10 + 2*20 + 3*30 = 10 + 40 + 90 = 140
        assert res == 140


class TestVectorCodegenInterop:
    """Tests compiling vector extension primitives through py_codegen."""

    def test_compile_vector_operations(self) -> None:
        source = """
        (define (transform-vectors v1 v2)
          (let ((appended (vector-append v1 v2)))
            (vector-map (lambda (x) (* x 2)) appended)))
        (transform-vectors #(1 2) #(3 4))
        """
        res = compile_ilisp(source)
        assert isinstance(res, Vector)
        assert res.elements == [2, 4, 6, 8]
