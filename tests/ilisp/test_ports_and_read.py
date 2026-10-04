"""Unit and integration tests for R7RS I/O Ports and Datum Reader in ILISP."""

import tempfile
from pathlib import Path
from typing import Any

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.port import (
    close_port,
    input_port_p,
    open_input_string,
    open_output_string,
    output_port_p,
    port_open_p,
    port_p,
    textual_port_p,
)
from ilisp.reader import read_all
from ilisp.types import Cons, Symbol, Vector


def run_code(code: str) -> Any:
    """Helper to evaluate ILISP code with standard environment."""
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    res = None
    for e in exprs:
        res = eval_expr(e, env)
    return res


class TestPortPredicates:
    """Test R7RS port predicates and lifecycle."""

    def test_predicates_on_string_ports(self) -> None:
        in_p = open_input_string("hello")
        out_p = open_output_string()

        assert port_p(in_p) is True
        assert port_p(out_p) is True
        assert port_p("not a port") is False

        assert input_port_p(in_p) is True
        assert input_port_p(out_p) is False

        assert output_port_p(out_p) is True
        assert output_port_p(in_p) is False

        assert textual_port_p(in_p) is True
        assert textual_port_p(out_p) is True

        assert port_open_p(in_p) is True
        close_port(in_p)
        assert port_open_p(in_p) is False

    def test_scheme_port_predicates(self) -> None:
        code = """
        (let ((p (open-output-string)))
          (list (port? p)
                (output-port? p)
                (input-port? p)
                (port-open? p)))
        """
        res = run_code(code)
        assert res.car is True
        assert res.cdr.car is True
        assert res.cdr.cdr.car is False
        assert res.cdr.cdr.cdr.car is True


class TestStringPortsAndCharIO:
    """Test string input/output ports and character/line operations."""

    def test_string_output_port(self) -> None:
        code = """
        (let ((p (open-output-string)))
          (write-string "hello " p)
          (write-char #\\w p)
          (display "orld" p)
          (newline p)
          (get-output-string p))
        """
        res = run_code(code)
        assert res == "hello world\n"

    def test_string_input_port(self) -> None:
        code = """
        (let ((p (open-input-string "line1\\nline2")))
          (let ((l1 (read-line p))
                (l2 (read-line p))
                (l3 (read-line p)))
            (list l1 l2 (eof-object? l3))))
        """
        res = run_code(code)
        assert res.car == "line1"
        assert res.cdr.car == "line2"
        assert res.cdr.cdr.car is True

    def test_peek_and_read_char(self) -> None:
        code = """
        (let ((p (open-input-string "ab")))
          (let ((c1 (peek-char p))
                (c2 (read-char p))
                (c3 (read-char p))
                (c4 (read-char p)))
            (list c1 c2 c3 (eof-object? c4))))
        """
        res = run_code(code)
        assert res.car == "a"
        assert res.cdr.car == "a"
        assert res.cdr.cdr.car == "b"
        assert res.cdr.cdr.cdr.car is True


class TestDatumReader:
    """Test S-expression datum reader from input ports."""

    def test_read_successive_datums(self) -> None:
        code = """
        (let ((p (open-input-string "100 (a b c) \\"hello\\" #(1 2 3) 'foo")))
          (let ((d1 (read p))
                (d2 (read p))
                (d3 (read p))
                (d4 (read p))
                (d5 (read p))
                (d6 (read p)))
            (list d1 d2 d3 d4 d5 (eof-object? d6))))
        """
        res = run_code(code)
        # d1 = 100
        assert res.car == 100
        # d2 = (a b c)
        assert isinstance(res.cdr.car, Cons)
        assert res.cdr.car.car == Symbol.intern("a")
        # d3 = "hello"
        assert res.cdr.cdr.car == "hello"
        # d4 = #(1 2 3)
        assert isinstance(res.cdr.cdr.cdr.car, Vector)
        assert res.cdr.cdr.cdr.car.elements == [1, 2, 3]
        # d5 = (quote foo)
        d5 = res.cdr.cdr.cdr.cdr.car
        assert isinstance(d5, Cons)
        assert d5.car == Symbol.intern("quote")
        # d6 is EOF
        assert res.cdr.cdr.cdr.cdr.cdr.car is True

    def test_read_with_comments(self) -> None:
        code = """
        (let ((p (open-input-string "; line comment\\n#; (discarded datum) 42")))
          (read p))
        """
        res = run_code(code)
        assert res == 42


class TestFilePorts:
    """Test file input/output ports and file lifecycle."""

    def test_file_io_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            filepath = str(Path(tmpdir) / "test_io.txt")
            code = f"""
            (begin
              (let ((out (open-output-file "{filepath}")))
                (write-string "(define answer 42)\\n" out)
                (close-output-port out))
              (let ((in (open-input-file "{filepath}")))
                (let ((datum (read in)))
                  (close-input-port in)
                  datum)))
            """
            res = run_code(code)
            assert isinstance(res, Cons)
            assert res.car == Symbol.intern("define")
            assert res.cdr.car == Symbol.intern("answer")
            assert res.cdr.cdr.car == 42

    def test_call_with_port_auto_close(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            filepath = str(Path(tmpdir) / "test_call.txt")
            code = f"""
            (begin
              (call-with-output-file "{filepath}"
                (lambda (p)
                  (display "sample data" p)))
              (call-with-input-file "{filepath}"
                (lambda (p)
                  (read-line p))))
            """
            res = run_code(code)
            assert res == "sample data"

    def test_with_input_and_output_to_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            filepath = str(Path(tmpdir) / "test_with.txt")
            code = f"""
            (begin
              (with-output-to-file "{filepath}"
                (lambda ()
                  (display "redirected output\\n")
                  (write '(1 2 3))))
              (with-input-from-file "{filepath}"
                (lambda ()
                  (let ((l (read-line))
                        (d (read)))
                    (list l d)))))
            """
            res = run_code(code)
            assert res.car == "redirected output"
            assert isinstance(res.cdr.car, Cons)
            assert res.cdr.car.car == 1


class TestModulePortsIntegration:
    """Test (scheme read) and (scheme file) module integration."""

    def test_import_scheme_read(self) -> None:
        code = """
        (import (only (scheme read) read)
                (only (scheme base) open-input-string let))
        (let ((p (open-input-string "42")))
          (read p))
        """
        res = run_code(code)
        assert res == 42

    def test_import_scheme_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            filepath = str(Path(tmpdir) / "test_mod_file.txt")
            code = f"""
            (import (scheme file) (scheme base) (scheme read))
            (call-with-output-file "{filepath}"
              (lambda (p)
                (write '(foo bar) p)))
            (call-with-input-file "{filepath}"
              (lambda (p)
                (read p)))
            """
            res = run_code(code)
            assert isinstance(res, Cons)
            assert res.car == Symbol.intern("foo")
            assert res.cdr.car == Symbol.intern("bar")


class TestBackendAPortIntegration:
    """Test Python AST Compiler (Backend A) port and read integration."""

    def test_py_codegen_ports(self) -> None:
        env = make_initial_env(preload_stdlib=True)
        code = """
        (let ((p (open-output-string)))
          (write-string "Hello, " p)
          (display "ILISP" p)
          (write-char #\\! p)
          (get-output-string p))
        """
        res = compile_ilisp(code, env=env)
        assert res == "Hello, ILISP!"
