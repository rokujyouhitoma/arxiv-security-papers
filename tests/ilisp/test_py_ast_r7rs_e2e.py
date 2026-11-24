"""E2E tests for the ILISP Python AST backend (`--backend=py_ast`, Issue #941).

Covers full Chibi R7RS conformance, regression tests for audited compiler gaps,
and CLI bit-identity of the ULisp C driver against the tree-walk interpreter.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest

from ilisp.backend.py_codegen.compiler import compile_ilisp, mangle_symbol
from ilisp.env import make_initial_env
from ilisp.repl import run_string
from ilisp.types import Symbol, to_py_list

ROOT = Path(__file__).resolve().parent.parent.parent
R7RS_FILE = ROOT / "ilisp" / "tests" / "r7rs_tests.scm"
HARNESS_FILE = ROOT / "ilisp" / "tests" / "test_harness.scm"
C_DRIVER = ROOT / "ulisp" / "build" / "c_driver_runner.scm"


def run(code: str) -> Any:
    return compile_ilisp(code, env=make_initial_env(preload_stdlib=True))


def test_chibi_r7rs_conformance_py_ast() -> None:
    env = make_initial_env(preload_stdlib=True)
    run_string(
        HARNESS_FILE.read_text(encoding="utf-8"),
        env=env,
        filename=str(HARNESS_FILE),
        backend="py_ast",
    )
    run_string(
        R7RS_FILE.read_text(encoding="utf-8"),
        env=env,
        filename=str(R7RS_FILE),
        backend="py_ast",
    )
    passes = env.lookup(Symbol.intern("*test-passes*"))
    failures = env.lookup(Symbol.intern("*test-failures*"))
    errors = env.lookup(Symbol.intern("*test-errors*"))
    assert failures == 0
    assert errors == 0
    assert passes >= 1200


def test_lazy_branch_side_effects() -> None:
    code = """
    (define hits 0)
    (if #t 1 (begin (set! hits (+ hits 1)) 2))
    (cond (#t 1) (else (set! hits (+ hits 1))))
    (case 1 ((1) 1) (else (set! hits (+ hits 1))))
    (and #f (set! hits (+ hits 1)))
    (or #t (set! hits (+ hits 1)))
    (when #f (set! hits (+ hits 1)))
    (unless #t (set! hits (+ hits 1)))
    hits
    """
    assert run(code) == 0


def test_literals_and_quote_identity() -> None:
    assert run("(exact? 1/3)") is True
    assert run("(real? -2.5+0.0i)") is False
    assert run("(real? -2.5+0i)") is True
    assert run("(let ((f (lambda () '(1 2)))) (eq? (f) (f)))") is True


def test_lexical_shadowing_of_syntax() -> None:
    assert run("(let ((when list)) (when 1 2))") is not None
    assert [x for x in to_py_list(run("(let ((when list)) (when 1 2))"))] == [1, 2]
    assert run("(let ((=> #f)) (cond (#t => 'ok)))") == Symbol.intern("ok")


def test_hygienic_let_syntax() -> None:
    code = """
    (let ((x 'outer))
      (let-syntax ((m (syntax-rules () ((m) x))))
        (let ((x 'inner)) (m))))
    """
    assert run(code) == Symbol.intern("outer")


def test_internal_define_values() -> None:
    assert run("(let () (define-values (x y) (values 1 2)) (+ x y))") == 3


def test_mangle_symbol_injective() -> None:
    names = ["foo-bar", "foo_dash_bar", "_start", "_append2", "class", "def", "a?"]
    mangled = [mangle_symbol(n) for n in names]
    assert len(set(mangled)) == len(names)
    for m in mangled:
        assert m.isidentifier()


def test_underscore_symbols_sync_to_env() -> None:
    env = make_initial_env(preload_stdlib=False)
    compile_ilisp("(define _start 7) (define foo-bar 8)", env=env)
    assert env.lookup(Symbol.intern("_start")) == 7
    assert env.lookup(Symbol.intern("foo-bar")) == 8


def test_builtin_redefinition_fallback() -> None:
    assert run("(define + *) (+ 3 4)") == 12


def test_deep_tail_recursion() -> None:
    assert run(
        "(define (loop n) (if (= n 0) 'done (loop (- n 1)))) (loop 200000)"
    ) == Symbol.intern("done")
    assert run("(let loop ((i 0)) (if (< i 200000) (loop (+ i 1)) i))") == 200000
    assert run("(do ((i 0 (+ i 1))) ((= i 100000) i))") == 100000
    code = """
    (define (ev? n) (if (= n 0) #t (od? (- n 1))))
    (define (od? n) (if (= n 0) #f (ev? (- n 1))))
    (ev? 50000)
    """
    assert run(code) is True


def test_control_flow_interop() -> None:
    assert run("(call/cc (lambda (k) (+ 1 (k 42))))") == 42
    assert run("(guard (e (#t 'caught)) (raise 'boom))") == Symbol.intern("caught")
    assert run("(call-with-values (lambda () (values 1 2)) +)") == 3
    assert run("(force (delay (+ 1 2)))") == 3
    assert run("(procedure? (lambda (x) x))") is True


def test_staged_macro_barrier() -> None:
    code = """
    (define (helper x) (list 'quote x))
    (define-macro (const-of x) (helper x))
    (const-of 5)
    """
    assert run(code) == 5


@pytest.mark.skipif(not C_DRIVER.exists(), reason="c_driver_runner.scm not built")
def test_cli_tiny_c_bit_identity(tmp_path: Path) -> None:
    src = tmp_path / "tiny.c"
    src.write_text("int main(void) { return 42; }\n", encoding="utf-8")
    env = {**os.environ, "PYTHONPATH": str(ROOT)}
    digests = []
    for backend in ("interp", "py_ast"):
        out = tmp_path / f"tiny_{backend}.o"
        proc = subprocess.run(
            [
                sys.executable,
                "-m",
                "ilisp",
                f"--backend={backend}",
                str(C_DRIVER),
                "--",
                "-O2",
                "-c",
                str(src),
                "-o",
                str(out),
            ],
            env=env,
            capture_output=True,
            text=True,
            timeout=600,
        )
        assert proc.returncode == 0, proc.stderr[-1000:]
        digests.append(hashlib.sha256(out.read_bytes()).hexdigest())
    assert digests[0] == digests[1]
