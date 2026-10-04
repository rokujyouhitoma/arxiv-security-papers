"""Tests for R7RS 6.13 Input and Output Extensions in ILISP."""

from typing import Any

import pytest

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import to_py_list


def run_code(code: str) -> Any:
    """Helper to evaluate ILISP code with standard environment."""
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    res = None
    for e in exprs:
        res = eval_expr(e, env)
    return res


class TestWriteString:
    """Tests for write-string with optional port, start, and end arguments."""

    def test_write_string_full(self) -> None:
        code = """
        (let ((p (open-output-string)))
          (write-string "hello world" p)
          (get-output-string p))
        """
        assert run_code(code) == "hello world"

    def test_write_string_with_start(self) -> None:
        code = """
        (let ((p (open-output-string)))
          (write-string "hello world" p 6)
          (get-output-string p))
        """
        assert run_code(code) == "world"

    def test_write_string_with_start_and_end(self) -> None:
        code = """
        (let ((p (open-output-string)))
          (write-string "hello world" p 0 5)
          (get-output-string p))
        """
        assert run_code(code) == "hello"

    def test_write_string_bounds_error(self) -> None:
        code = """
        (let ((p (open-output-string)))
          (write-string "hello" p 0 10))
        """
        with pytest.raises(IndexError, match="write-string: invalid range"):
            run_code(code)


class TestWriteSharedAndSimple:
    """Tests for write, write-simple, and write-shared."""

    def test_write_simple_flat_structures(self) -> None:
        code = """
        (let ((p (open-output-string)))
          (write-simple '(1 2 "apple" #(10 20)) p)
          (get-output-string p))
        """
        assert run_code(code) == '(1 2 "apple" #(10 20))'

    def test_write_shared_cyclic_list(self) -> None:
        code = """
        (let ((p (open-output-string))
              (x (list 1 2 3)))
          (set-cdr! (cddr x) x)
          (write-shared x p)
          (get-output-string p))
        """
        res = run_code(code)
        assert res == "#1=(1 2 3 . #1#)"

    def test_write_shared_shared_substructure(self) -> None:
        code = """
        (let ((p (open-output-string))
              (sub (list 'a 'b)))
          (write-shared (cons sub sub) p)
          (get-output-string p))
        """
        res = run_code(code)
        assert res == "(#1=(a b) . #1#)"

    def test_write_cyclic_list(self) -> None:
        code = """
        (let ((p (open-output-string))
              (x (list 'a 'b)))
          (set-cdr! (cdr x) x)
          (write x p)
          (get-output-string p))
        """
        res = run_code(code)
        assert res == "#1=(a b . #1#)"

    def test_write_shared_non_cyclic_not_labeled_in_write(self) -> None:
        code = """
        (let ((p (open-output-string))
              (sub (list 1 2)))
          (write (list sub sub) p)
          (get-output-string p))
        """
        res = run_code(code)
        # R7RS standard write does not label shared structures unless they are cyclic
        assert res == "((1 2) (1 2))"

    def test_write_shared_cyclic_vector(self) -> None:
        code = """
        (let ((p (open-output-string))
              (v (vector 1 2 3)))
          (vector-set! v 0 v)
          (write-shared v p)
          (get-output-string p))
        """
        res = run_code(code)
        assert res == "#1=#(#1# 2 3)"


class TestBinaryIOExtensions:
    """Tests for binary port operations with slices."""

    def test_read_bytevector_slice_and_bang(self) -> None:
        code = """
        (let* ((in-bv (bytevector 10 20 30 40 50))
               (p (open-input-bytevector in-bv))
               (buf (make-bytevector 5 0)))
          (let ((n (read-bytevector! buf p 1 4)))
            (list n (bytevector-u8-ref buf 0)
                    (bytevector-u8-ref buf 1)
                    (bytevector-u8-ref buf 2)
                    (bytevector-u8-ref buf 3)
                    (bytevector-u8-ref buf 4))))
        """
        res = run_code(code)
        # buf was [0, 0, 0, 0, 0]. read 3 bytes (10, 20, 30) into slice [1:4]
        # resulting in [0, 10, 20, 30, 0]
        assert to_py_list(res) == [3, 0, 10, 20, 30, 0]

    def test_write_bytevector_slice(self) -> None:
        code = """
        (let* ((p (open-output-bytevector))
               (bv (bytevector 11 22 33 44 55)))
          (write-bytevector bv p 1 4)
          (let ((out-bv (get-output-bytevector p)))
            (list (bytevector-length out-bv)
                  (bytevector-u8-ref out-bv 0)
                  (bytevector-u8-ref out-bv 1)
                  (bytevector-u8-ref out-bv 2))))
        """
        res = run_code(code)
        assert to_py_list(res) == [3, 22, 33, 44]


class TestBackendAIOIntegration:
    """Test Python AST codegen for I/O operations."""

    def test_compile_write_string(self) -> None:
        code = """
        (let ((p (open-output-string)))
          (write-string "transpiler output test" p 0 10)
          (get-output-string p))
        """
        res = compile_ilisp(code)
        assert res == "transpiler"

    def test_compile_write_simple(self) -> None:
        code = """
        (let ((p (open-output-string)))
          (write-simple '(100 200) p)
          (get-output-string p))
        """
        res = compile_ilisp(code)
        assert res == "(100 200)"
