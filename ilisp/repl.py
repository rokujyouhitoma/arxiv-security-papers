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
    code: str, env: Optional[Environment] = None, filename: str = "<stdin>"
) -> Any:
    """Evaluate a sequence of S-expressions from code string within an environment."""
    if env is None:
        env = make_initial_env()

    expressions = read_all(code, filename=filename)
    result: Any = NIL
    for expr in expressions:
        result = eval_expr(expr, env)
    return result


def run_file(filepath: str, env: Optional[Environment] = None) -> Any:
    """Execute an ILISP source code file (.ilisp or .scm)."""
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    return run_string(content, env=env, filename=filepath)


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

    args = parser.parse_args()

    env = make_initial_env()

    if args.eval:
        res = run_string(args.eval, env=env, filename="<cli-eval>")
        if res is not None and res is not NIL:
            print(repr(res))
        sys.exit(0)

    if args.file:
        run_file(args.file, env=env)
        sys.exit(0)

    repl(env=env)


if __name__ == "__main__":
    main()
