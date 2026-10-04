"""Unit and integration tests for R7RS Bytevectors and Binary Ports in ILISP."""

import tempfile
from pathlib import Path
from typing import Any

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.port import binary_port_p, open_input_bytevector, open_output_bytevector
from ilisp.reader import read_all, read_one
from ilisp.types import Bytevector, is_bytevector


def run_code(code: str) -> Any:
    """Helper to evaluate ILISP code with standard environment."""
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    res = None
    for e in exprs:
        res = eval_expr(e, env)
    return res


class TestBytevectorLiteralsAndTypes:
    """Test #u8(...) reader syntax and Bytevector type representations."""

    def test_empty_bytevector_literal(self) -> None:
        bv = read_one("#u8()")
        assert is_bytevector(bv)
        assert len(bv) == 0
        assert repr(bv) == "#u8()"

    def test_bytevector_literal_with_elements(self) -> None:
        bv = read_one("#u8(0 1 127 255)")
        assert is_bytevector(bv)
        assert len(bv) == 4
        assert bv[0] == 0
        assert bv[1] == 1
        assert bv[2] == 127
        assert bv[3] == 255
        assert repr(bv) == "#u8(0 1 127 255)"

    def test_bytevector_predicate(self) -> None:
        code = """
        (list (bytevector? #u8(1 2 3))
              (bytevector? #(1 2 3))
              (bytevector? "hello")
              (bytevector? '()))
        """
        res = run_code(code)
        assert res.car is True
        assert res.cdr.car is False
        assert res.cdr.cdr.car is False
        assert res.cdr.cdr.cdr.car is False


class TestBytevectorPrimitives:
    """Test standard bytevector primitives adhering to R7RS Section 6.9."""

    def test_make_bytevector_and_length(self) -> None:
        code = """
        (let ((bv1 (make-bytevector 5))
              (bv2 (make-bytevector 3 255)))
          (list (bytevector-length bv1)
                (bytevector-u8-ref bv1 0)
                (bytevector-length bv2)
                (bytevector-u8-ref bv2 2)))
        """
        res = run_code(code)
        assert res.car == 5
        assert res.cdr.car == 0
        assert res.cdr.cdr.car == 3
        assert res.cdr.cdr.cdr.car == 255

    def test_bytevector_constructor(self) -> None:
        code = "(bytevector 10 20 30 40)"
        res = run_code(code)
        assert is_bytevector(res)
        assert len(res) == 4
        assert res[2] == 30

    def test_bytevector_u8_set(self) -> None:
        code = """
        (let ((bv (make-bytevector 3 0)))
          (bytevector-u8-set! bv 1 42)
          (bytevector-u8-ref bv 1))
        """
        res = run_code(code)
        assert res == 42

    def test_bytevector_copy_and_copy_bang(self) -> None:
        code = """
        (let ((src (bytevector 1 2 3 4 5))
              (dst (make-bytevector 5 0)))
          (let ((sub (bytevector-copy src 1 4)))
            (bytevector-copy! dst 2 src 0 3)
            (list sub dst)))
        """
        res = run_code(code)
        sub = res.car
        dst = res.cdr.car
        assert is_bytevector(sub)
        assert list(sub) == [2, 3, 4]
        assert is_bytevector(dst)
        assert list(dst) == [0, 0, 1, 2, 3]

    def test_bytevector_append(self) -> None:
        code = """
        (bytevector-append #u8(1 2) #u8(3 4 5) #u8(6))
        """
        res = run_code(code)
        assert is_bytevector(res)
        assert list(res) == [1, 2, 3, 4, 5, 6]

    def test_utf8_conversions(self) -> None:
        code = """
        (let ((str "こんにちは ILISP"))
          (let ((bv (string->utf8 str)))
            (let ((decoded (utf8->string bv)))
              (list (bytevector? bv)
                    (> (bytevector-length bv) 0)
                    decoded))))
        """
        res = run_code(code)
        assert res.car is True
        assert res.cdr.car is True
        assert res.cdr.cdr.car == "こんにちは ILISP"


class TestBytesPorts:
    """Test in-memory binary ports reading from and writing to bytevectors."""

    def test_bytes_output_port(self) -> None:
        code = """
        (let ((p (open-output-bytevector)))
          (write-u8 65 p)
          (write-u8 66 p)
          (write-bytevector #u8(67 68) p)
          (get-output-bytevector p))
        """
        res = run_code(code)
        assert is_bytevector(res)
        assert list(res) == [65, 66, 67, 68]
        assert bytes(res.data) == b"ABCD"

    def test_bytes_input_port(self) -> None:
        code = """
        (let ((p (open-input-bytevector #u8(10 20 30 40 50))))
          (let ((b1 (peek-u8 p))
                (b2 (read-u8 p))
                (sub (read-bytevector 2 p))
                (b3 (read-u8 p))
                (b4 (read-u8 p))
                (eof (read-u8 p)))
            (list b1 b2 sub b3 b4 (eof-object? eof))))
        """
        res = run_code(code)
        assert res.car == 10
        assert res.cdr.car == 10
        sub = res.cdr.cdr.car
        assert is_bytevector(sub)
        assert list(sub) == [20, 30]
        assert res.cdr.cdr.cdr.car == 40
        assert res.cdr.cdr.cdr.cdr.car == 50
        assert res.cdr.cdr.cdr.cdr.cdr.car is True

    def test_read_bytevector_bang(self) -> None:
        code = """
        (let ((p (open-input-bytevector #u8(100 101 102)))
              (buf (make-bytevector 5 0)))
          (let ((n (read-bytevector! buf p 1 4)))
            (list n buf)))
        """
        res = run_code(code)
        assert res.car == 3
        buf = res.cdr.car
        assert list(buf) == [0, 100, 101, 102, 0]


class TestBinaryFilePorts:
    """Test filesystem binary ports and raw byte payload processing."""

    def test_binary_file_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            filepath = str(Path(tmpdir) / "test.bin")
            # PDF header signature %PDF-1.4 = [37, 80, 68, 70, 45, 49, 46, 52]
            code = f"""
            (begin
              (let ((out (open-binary-output-file "{filepath}")))
                (write-bytevector #u8(37 80 68 70 45 49 46 52 10) out)
                (write-u8 0 out)
                (write-u8 255 out)
                (close-output-port out))
              (let ((in (open-binary-input-file "{filepath}")))
                (let ((sig (read-bytevector 9 in))
                      (b1 (read-u8 in))
                      (b2 (read-u8 in))
                      (eof (read-u8 in)))
                  (close-input-port in)
                  (list (utf8->string sig) b1 b2 (eof-object? eof)))))
            """
            res = run_code(code)
            assert res.car == "%PDF-1.4\n"
            assert res.cdr.car == 0
            assert res.cdr.cdr.car == 255
            assert res.cdr.cdr.cdr.car is True

    def test_binary_port_predicates(self) -> None:
        in_p = open_input_bytevector(Bytevector(b"test"))
        out_p = open_output_bytevector()

        assert binary_port_p(in_p) is True
        assert binary_port_p(out_p) is True


class TestModuleBytevectorIntegration:
    """Test bytevector and binary port availability through (scheme base) and (scheme file)."""

    def test_scheme_base_bytevectors(self) -> None:
        code = """
        (import (only (scheme base) make-bytevector bytevector-u8-set! bytevector-u8-ref let))
        (let ((bv (make-bytevector 2 0)))
          (bytevector-u8-set! bv 0 77)
          (bytevector-u8-ref bv 0))
        """
        res = run_code(code)
        assert res == 77

    def test_scheme_file_binary_ports(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            filepath = str(Path(tmpdir) / "mod_test.bin")
            code = f"""
            (import (scheme base) (scheme file))
            (let ((out (open-binary-output-file "{filepath}")))
              (write-u8 99 out)
              (close-output-port out))
            (let ((in (open-binary-input-file "{filepath}")))
              (let ((b (read-u8 in)))
                (close-input-port in)
                b))
            """
            res = run_code(code)
            assert res == 99


class TestBackendABytevectorIntegration:
    """Test Backend A (Python AST Transpiler) bytevector code generation."""

    def test_py_codegen_bytevector_literals(self) -> None:
        env = make_initial_env(preload_stdlib=True)
        code = """
        (let ((bv #u8(10 20 30)))
          (bytevector-u8-ref bv 1))
        """
        res = compile_ilisp(code, env=env)
        assert res == 20

    def test_py_codegen_bytevector_operations(self) -> None:
        env = make_initial_env(preload_stdlib=True)
        code = """
        (let ((bv (make-bytevector 4 65)))
          (bytevector-u8-set! bv 3 66)
          (utf8->string bv))
        """
        res = compile_ilisp(code, env=env)
        assert res == "AAAB"
