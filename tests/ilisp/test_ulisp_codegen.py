"""Unit and E2E integration tests for ILISP ULisp Native AOT Backend (Backend B).

Verifies:
- Transpiler desugaring (multi-arity arithmetics, forms, Scheme AST serialization)
- x86-64 GAS assembly emission via ULisp compiler engine
- End-to-end standalone ELF native binary compilation and execution
- CLI options (--compile, -c, --backend native, -S)
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

from ilisp.backend.ulisp_codegen.compiler import (
    UlispCodegenError,
    compile_to_assembly,
    compile_to_elf,
    run_elf,
)
from ilisp.backend.ulisp_codegen.transpiler import UlispTranspiler, transpile_for_ulisp
from ilisp.repl import run_string


class TestUlispTranspiler:
    """Tests for S-expression AST desugaring and normalization."""

    def test_transpiler_instance(self) -> None:
        tr = UlispTranspiler()
        assert tr.transpile("(+ 1 2)") == "(+ 1 2)"

    def test_invalid_syntax_error(self) -> None:
        with pytest.raises(UlispCodegenError):
            compile_to_assembly("(define)")

    def test_transpile_literals(self) -> None:
        assert transpile_for_ulisp("42") == "42"
        assert transpile_for_ulisp("#t") == "#t"
        assert transpile_for_ulisp("#f") == "#f"
        assert transpile_for_ulisp("'()") == "'()"
        assert transpile_for_ulisp('"hello"') == '"hello"'
        assert transpile_for_ulisp("#\\a") == "#\\a"

    def test_multi_arity_arithmetic(self) -> None:
        # (+ 1 2 3 4) => (+ (+ (+ 1 2) 3) 4)
        res_add = transpile_for_ulisp("(+ 1 2 3 4)")
        assert res_add == "(+ (+ (+ 1 2) 3) 4)"

        # (* 2 3 4) => (* (* 2 3) 4)
        res_mul = transpile_for_ulisp("(* 2 3 4)")
        assert res_mul == "(* (* 2 3) 4)"

        # (- 10 3 2) => (- (- 10 3) 2)
        res_sub = transpile_for_ulisp("(- 10 3 2)")
        assert res_sub == "(- (- 10 3) 2)"

        # (- 5) => (- 0 5)
        res_neg = transpile_for_ulisp("(- 5)")
        assert res_neg == "(- 0 5)"

    def test_define_normalization(self) -> None:
        code = "(define (add a b) (+ a b))"
        res = transpile_for_ulisp(code)
        assert res == "(define add (lambda (a b) (+ a b)))"

    def test_quote_preservation(self) -> None:
        res = transpile_for_ulisp("'(a b c)")
        assert res == "'(a b c)"


class TestUlispAssemblyEmission:
    """Tests for x86-64 assembly generation."""

    def test_assembly_basic_number(self) -> None:
        asm = compile_to_assembly("42")
        assert ".globl scheme_entry" in asm
        assert "scheme_entry:" in asm
        assert "ret" in asm
        # In ULisp, 42 as fixnum has tag 0 (42 << 2 = 168)
        assert "168" in asm

    def test_assembly_addition(self) -> None:
        asm = compile_to_assembly("(+ 10 20)")
        assert "add" in asm


class TestUlispELFExecution:
    """End-to-End tests compiling Scheme programs to native ELF binaries and executing them."""

    def test_compile_and_run_immediate_and_arithmetic(self) -> None:
        with tempfile.TemporaryDirectory(prefix="test_elf_") as tmpdir:
            bin_path = Path(tmpdir) / "bin_arith"
            compile_to_elf("(+ 12 30)", bin_path)
            proc = run_elf(bin_path)
            assert proc.returncode == 0
            assert proc.stdout.strip() == "42"

    def test_compile_and_run_multi_arity(self) -> None:
        with tempfile.TemporaryDirectory(prefix="test_elf_") as tmpdir:
            bin_path = Path(tmpdir) / "bin_multi"
            compile_to_elf("(+ 1 2 3 4 5 6 7 8 9 10)", bin_path)
            proc = run_elf(bin_path)
            assert proc.returncode == 0
            assert proc.stdout.strip() == "55"

    def test_compile_and_run_conditional(self) -> None:
        with tempfile.TemporaryDirectory(prefix="test_elf_") as tmpdir:
            bin_path = Path(tmpdir) / "bin_if"
            code = """
            (if (< 10 20)
                "smaller"
                "greater")
            """
            compile_to_elf(code, bin_path)
            proc = run_elf(bin_path)
            assert proc.returncode == 0
            assert proc.stdout.strip() == '"smaller"'

    def test_compile_and_run_closures_and_higher_order(self) -> None:
        with tempfile.TemporaryDirectory(prefix="test_elf_") as tmpdir:
            bin_path = Path(tmpdir) / "bin_closure"
            code = """
            (let ((make-adder (lambda (x) (lambda (y) (+ x y)))))
              (let ((add10 (make-adder 10)))
                (add10 32)))
            """
            compile_to_elf(code, bin_path)
            proc = run_elf(bin_path)
            assert proc.returncode == 0
            assert proc.stdout.strip() == "42"

    def test_compile_and_run_tail_call_recursion(self) -> None:
        with tempfile.TemporaryDirectory(prefix="test_elf_") as tmpdir:
            bin_path = Path(tmpdir) / "bin_tco"
            code = """
            (letrec ((loop (lambda (n acc)
                             (if (= n 0)
                                 acc
                                 (loop (- n 1) (+ acc n))))))
              (loop 100 0))
            """
            compile_to_elf(code, bin_path)
            proc = run_elf(bin_path)
            assert proc.returncode == 0
            assert proc.stdout.strip() == "5050"

    def test_compile_and_run_pairs_and_lists(self) -> None:
        with tempfile.TemporaryDirectory(prefix="test_elf_") as tmpdir:
            bin_path = Path(tmpdir) / "bin_list"
            code = """
            (let ((p (cons 10 (cons 20 '()))))
              (+ (car p) (car (cdr p))))
            """
            compile_to_elf(code, bin_path)
            proc = run_elf(bin_path)
            assert proc.returncode == 0
            assert proc.stdout.strip() == "30"

    def test_compile_and_run_display_output(self) -> None:
        with tempfile.TemporaryDirectory(prefix="test_elf_") as tmpdir:
            bin_path = Path(tmpdir) / "bin_display"
            code = """
            (begin
              (display "Hello from ILisp AOT ELF!")
              (newline))
            """
            compile_to_elf(code, bin_path)
            proc = run_elf(bin_path)
            assert proc.returncode == 0
            assert "Hello from ILisp AOT ELF!" in proc.stdout


class TestCLIAndReplIntegration:
    """Tests for CLI options and repl backend integration."""

    def test_run_string_with_native_backend(self) -> None:
        res = run_string("(+ 100 200)", backend="native")
        assert res == "300"

    def test_cli_compile_flag_execution(self) -> None:
        with tempfile.TemporaryDirectory(prefix="test_cli_") as tmpdir:
            bin_path = Path(tmpdir) / "cli_bin"
            cmd = [
                sys.executable,
                "-m",
                "ilisp",
                "-c",
                "-e",
                "(+ 21 21)",
                "-o",
                str(bin_path),
            ]
            env = os.environ.copy()
            env["PYTHONPATH"] = str(Path.cwd())
            proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
            assert proc.returncode == 0, f"CLI compile failed: {proc.stderr}"
            assert bin_path.is_file()

            # Execute compiled binary
            res = subprocess.run([str(bin_path)], capture_output=True, text=True)
            assert res.returncode == 0
            assert res.stdout.strip() == "42"

    def test_cli_assembly_only_flag(self) -> None:
        cmd = [
            sys.executable,
            "-m",
            "ilisp",
            "-S",
            "-e",
            "(+ 5 5)",
        ]
        env = os.environ.copy()
        env["PYTHONPATH"] = str(Path.cwd())
        proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
        assert proc.returncode == 0
        assert ".globl scheme_entry" in proc.stdout
