"""Interactive REPL and CLI Runner for Kernel ILISP.

This module provides the interactive Read-Eval-Print Loop with multi-line bracket
balancing, string evaluation, file execution, and standard command line interfaces.
"""

from __future__ import annotations

import argparse
import sys
from typing import Any, Optional

from ilisp.env import Environment, make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import LispSyntaxError, read_all
from ilisp.types import NIL, Symbol


def run_string(
    code: str,
    env: Optional[Environment] = None,
    filename: str = "<stdin>",
    backend: str = "interp",
) -> Any:
    """Evaluate a sequence of S-expressions from code string within an environment."""
    if env is None:
        env = make_initial_env()

    if backend == "py_ast":
        from ilisp.backend.py_codegen.compiler import compile_ilisp

        return compile_ilisp(code, env=env, filename=filename)

    if backend in {"native", "ulisp"}:
        import tempfile

        from ilisp.backend.ulisp_codegen.compiler import compile_to_elf, run_elf

        with tempfile.TemporaryDirectory(prefix="ilisp_native_") as tmpdir:
            bin_path = f"{tmpdir}/tmp_exec"
            compile_to_elf(code, bin_path)
            proc = run_elf(bin_path)
            if proc.returncode != 0:
                print(proc.stderr, file=sys.stderr)
            return proc.stdout.rstrip()

    expressions = read_all(code, filename=filename)
    result: Any = NIL
    for expr in expressions:
        result = eval_expr(expr, env)
    return result


def run_file(
    filepath: str, env: Optional[Environment] = None, backend: str = "interp"
) -> Any:
    """Execute an ILISP source code file (.ilisp or .scm)."""
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    return run_string(content, env=env, filename=filepath, backend=backend)


def repl(env: Optional[Environment] = None) -> None:
    """Run interactive REPL with multi-line bracket balancing."""
    if env is None:
        env = make_initial_env()

    print("ILISP (Intelligence LISP) 0.1.0 (Kernel ILISP R7RS-small)")
    print("Type (exit) or Ctrl+D to exit.\n")

    buffer: list[str] = []
    open_paren_count = 0

    while True:
        try:
            prompt = "ilisp> " if not buffer else "...    "
            line = input(prompt)
        except (EOFError, KeyboardInterrupt):
            print("\nExiting ILISP REPL.")
            break

        buffer.append(line)
        # Simple parenthesis balance tracking
        for ch in line:
            if ch == "(":
                open_paren_count += 1
            elif ch == ")":
                open_paren_count = max(0, open_paren_count - 1)

        # If parens are closed, attempt parse and evaluate
        if open_paren_count == 0 and buffer:
            full_code = "\n".join(buffer)
            buffer = []
            if not full_code.strip():
                continue

            try:
                expressions = read_all(full_code, filename="<repl>")
                for expr in expressions:
                    # Check for (exit)
                    if (
                        hasattr(expr, "car")
                        and isinstance(expr.car, Symbol)
                        and expr.car.name == "exit"
                    ):
                        print("Exiting ILISP REPL.")
                        return
                    res = eval_expr(expr, env)
                    if res is not None:
                        print(repr(res))
            except LispSyntaxError as e:
                print(f"SyntaxError: {e}")
            except Exception as e:
                print(f"Error: {type(e).__name__}: {e}")


def main() -> None:
    """CLI Entry point for python -m ilisp."""
    parser = argparse.ArgumentParser(
        description="ILISP (Intelligence LISP) Kernel Runner"
    )
    parser.add_argument("file", nargs="?", help="Path to .ilisp file to execute")
    parser.add_argument("-e", "--eval", help="Evaluate ILISP expression string")
    parser.add_argument(
        "--backend",
        choices=["interp", "py_ast", "native", "ulisp"],
        default="interp",
        help=(
            "Execution backend: 'interp' (tree-walk), "
            "'py_ast' (Python AST transpiler), or 'native'/'ulisp' (x86-64 Native AOT)"
        ),
    )
    parser.add_argument(
        "-c",
        "--compile",
        action="store_true",
        help="Compile source file or -e expression to standalone native ELF executable",
    )
    parser.add_argument(
        "-S",
        "--assembly-only",
        action="store_true",
        help="Emit x86-64 GAS assembly code",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="Output binary/assembly file path (default: <stem> or a.out)",
    )

    args = parser.parse_args()

    if args.compile or args.assembly_only:
        from pathlib import Path

        from ilisp.backend.ulisp_codegen.compiler import (
            compile_to_assembly,
            compile_to_elf,
        )

        if not args.file and not args.eval:
            parser.error("Compilation requires an input file or -e expression")

        if args.eval:
            code_content = args.eval
            default_out = "a.out"
        else:
            with open(args.file, "r", encoding="utf-8") as f:
                code_content = f.read()
            default_out = Path(args.file).stem

        if args.assembly_only:
            out_s = args.output
            asm = compile_to_assembly(code_content)
            if out_s:
                Path(out_s).write_text(asm, encoding="utf-8")
                print(f"Assembly written to: {out_s}")
            else:
                sys.stdout.write(asm)
            sys.exit(0)

        out_bin = args.output or default_out
        target_path = compile_to_elf(code_content, out_bin)
        print(f"Compiled native ELF binary: {target_path}")
        sys.exit(0)

    env = make_initial_env()

    if args.eval:
        res = run_string(
            args.eval, env=env, filename="<cli-eval>", backend=args.backend
        )
        if res is not None and res is not NIL:
            print(repr(res))
        sys.exit(0)

    if args.file:
        res = run_file(args.file, env=env, backend=args.backend)
        if args.backend in {"native", "ulisp"} and res:
            print(res)
        sys.exit(0)

    repl(env=env)


if __name__ == "__main__":
    main()
