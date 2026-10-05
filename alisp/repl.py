"""Interactive REPL and CLI Runner for ALisp (Agent Lisp).

Provides an interactive Read-Eval-Print Loop with multi-line bracket balancing,
step fuel metering, contract programming, and blame diagnostic reporting.
"""

from __future__ import annotations

import argparse
import sys
from typing import Any, List, Optional

from alisp.contracts import ContractViolationException
from alisp.core import ALispEngine
from alisp.metering import FuelExhaustedException
from ilisp.evaluator import StepHookContext
from ilisp.reader import LispSyntaxError, read_all
from ilisp.types import NIL, Symbol


def _is_exit_expression(expr: Any) -> bool:
    """Check if the expression is (exit)."""
    return (
        hasattr(expr, "car")
        and isinstance(expr.car, Symbol)
        and expr.car.name == "exit"
    )


def _eval_repl_expression(engine: ALispEngine, expr: Any) -> None:
    """Evaluate a single AST expression in the REPL and print its result."""
    with StepHookContext(engine.interceptor):
        res = engine.evaluator.eval(expr, engine.env)
        if res is not None and res is not NIL:
            print(repr(res))


def _handle_repl_eval(engine: ALispEngine, full_code: str) -> bool:
    """Parse and evaluate expressions in full_code. Returns False if (exit) was called."""
    try:
        expressions = read_all(full_code, filename="<repl>")
        for expr in expressions:
            if _is_exit_expression(expr):
                return False
            _eval_repl_expression(engine, expr)
    except FuelExhaustedException as e:
        print(f"[FuelExhausted] {e}")
    except ContractViolationException as e:
        print(f"[ContractViolation] {e}")
        try:
            print(f"  diagnostic: {e.to_diagnostic()}")
        except Exception:
            pass
    except LispSyntaxError as e:
        print(f"SyntaxError: {e}")
    except Exception as e:
        print(f"Error: {type(e).__name__}: {e}")
    return True


def _update_paren_balance(line: str, current_count: int) -> int:
    """Compute paren balance count for a line."""
    count = current_count
    for ch in line:
        if ch == "(":
            count += 1
        elif ch == ")":
            count = max(0, count - 1)
    return count


def repl(
    engine: Optional[ALispEngine] = None,
    default_fuel: Optional[int] = None,
) -> None:
    """Run the interactive ALisp REPL."""
    active_engine = (
        engine if engine is not None else ALispEngine(default_fuel=default_fuel)
    )

    print("ALisp (Agent Lisp) 0.1.0 (Guarded R7RS-small Lisp)")
    if default_fuel is not None:
        print(f"Default Fuel Limit: {default_fuel} steps")
    print("Type (exit) or Ctrl+D to exit.\n")

    buffer: List[str] = []
    open_paren_count = 0

    while True:
        try:
            prompt = "alisp> " if not buffer else "...     "
            line = input(prompt)
        except EOFError:
            print("\nExiting ALisp REPL.")
            break
        except KeyboardInterrupt:
            print("\nKeyboardInterrupt")
            buffer = []
            open_paren_count = 0
            continue

        buffer.append(line)
        open_paren_count = _update_paren_balance(line, open_paren_count)

        if open_paren_count == 0 and buffer:
            full_code = "\n".join(buffer)
            buffer = []
            if not full_code.strip():
                continue

            should_continue = _handle_repl_eval(active_engine, full_code)
            if not should_continue:
                print("Exiting ALisp REPL.")
                break


def main() -> None:
    """CLI Entry point for python -m alisp."""
    parser = argparse.ArgumentParser(
        description="ALisp (Agent Lisp) Execution Environment"
    )
    parser.add_argument("file", nargs="?", help="Path to ALisp / ILisp file to execute")
    parser.add_argument("-e", "--eval", help="Evaluate expression string")
    parser.add_argument(
        "--fuel",
        type=int,
        default=None,
        help="Global default step fuel limit",
    )

    args = parser.parse_args()
    engine = ALispEngine(default_fuel=args.fuel)

    if args.eval:
        try:
            res = engine.eval(args.eval)
            if res is not None and res is not NIL:
                print(repr(res))
        except FuelExhaustedException as e:
            print(f"[FuelExhausted] {e}", file=sys.stderr)
            sys.exit(1)
        except ContractViolationException as e:
            print(f"[ContractViolation] {e}", file=sys.stderr)
            sys.exit(1)
        sys.exit(0)

    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            content = f.read()
        try:
            engine.eval(content)
        except (FuelExhaustedException, ContractViolationException) as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        sys.exit(0)

    repl(engine=engine, default_fuel=args.fuel)


if __name__ == "__main__":
    main()
