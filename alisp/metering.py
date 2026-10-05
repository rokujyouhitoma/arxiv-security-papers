"""ALisp Metering Subsystem.

Provides computational step budgeting, hierarchical sub-budgeting,
and FuelExhaustedException to guarantee bounded autonomy for AI coding agents.
"""

from __future__ import annotations

import time
from contextlib import contextmanager
from typing import Any, Iterator, Optional

from ilisp.evaluator import _apply_procedure
from ilisp.types import NIL, Cons, Primitive, Procedure, Symbol, car, cdr, is_pair


class FuelExhaustedException(BaseException):
    """Raised when execution fuel budget is completely exhausted.

    Inherits from BaseException so that it bypasses standard Scheme / Python
    (guard ...) or (except Exception:) blocks, guaranteeing deterministic physical
    interruption of infinite loops.
    """

    def __init__(
        self,
        message: str = "Execution fuel exhausted",
        steps: int = 0,
        remaining: int = 0,
        limit: int = 0,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.steps = steps
        self.remaining = remaining
        self.limit = limit

    def __str__(self) -> str:
        return self.message


class FuelCounter:
    """Hierarchical fuel counter tracking evaluation steps.

    Implements sub-budgeting:
    child_fuel = min(requested, parent_remaining)
    Steps consumed by the child are also subtracted from parent remaining fuel.
    """

    def __init__(
        self,
        limit: int,
        parent: Optional[FuelCounter] = None,
        timeout_seconds: Optional[float] = None,
    ) -> None:
        if limit < 0:
            raise ValueError(f"Fuel limit must be non-negative, got {limit}")
        self.initial_limit = limit
        self.remaining = limit
        self.consumed = 0
        self.parent = parent
        self.timeout_seconds = timeout_seconds
        self.deadline: Optional[float] = (
            (time.monotonic() + timeout_seconds)
            if timeout_seconds is not None
            else (parent.deadline if parent is not None else None)
        )

    def step(self) -> None:
        """Decrement 1 step of fuel. If remaining <= 0 or deadline exceeded, raise exception."""
        if self.deadline is not None and time.monotonic() > self.deadline:
            raise TimeoutError(
                f"Execution wall-clock timeout exceeded ({self.timeout_seconds}s)"
            )
        if self.remaining <= 0:
            raise FuelExhaustedException(
                f"Execution fuel exhausted: limit of {self.initial_limit} steps exceeded",
                steps=self.consumed,
                remaining=0,
                limit=self.initial_limit,
            )
        self.remaining -= 1
        self.consumed += 1
        if self.parent is not None:
            self.parent.step()


class StepInterceptor:
    """Manages active fuel counters and provides the step hook for ILisp."""

    def __init__(self) -> None:
        self.current_counter: Optional[FuelCounter] = None

    def __call__(self) -> None:
        """Callback invoked by ilisp.evaluator on each evaluation step."""
        if self.current_counter is not None:
            self.current_counter.step()

    @contextmanager
    def with_fuel_scope(
        self,
        steps: int,
        timeout_seconds: Optional[float] = None,
    ) -> Iterator[FuelCounter]:
        """Scoped fuel budget context manager supporting hierarchical sub-budgeting."""
        parent = self.current_counter
        effective_steps = min(steps, parent.remaining) if parent is not None else steps
        child = FuelCounter(
            limit=effective_steps,
            parent=parent,
            timeout_seconds=timeout_seconds,
        )
        self.current_counter = child
        try:
            yield child
        finally:
            self.current_counter = parent


class WithFuelTransformer:
    """Macro transformer for (with-fuel steps expr...).

    Desugars:
      (with-fuel 100 expr1 expr2 ...)
    into:
      (%with-fuel 100 (lambda () (begin expr1 expr2 ...)))
    """

    def transform(self, expr: Any, env: Any) -> Any:
        # expr is (with-fuel steps . body)
        args = cdr(expr)
        if not is_pair(args):
            raise SyntaxError(
                "with-fuel requires steps and at least one expression: (with-fuel steps expr...)"
            )
        steps_expr = car(args)
        body_rest = cdr(args)
        if not is_pair(body_rest):
            raise SyntaxError(
                "with-fuel requires at least one body expression: (with-fuel steps expr...)"
            )

        # Construct: (lambda () (begin expr1 expr2 ...))
        begin_form = Cons(Symbol.intern("begin"), body_rest)
        lambda_form = Cons(Symbol.intern("lambda"), Cons(NIL, Cons(begin_form, NIL)))
        # Construct: (%with-fuel steps_expr lambda_form)
        return Cons(
            Symbol.intern("%with-fuel"),
            Cons(steps_expr, Cons(lambda_form, NIL)),
        )


def make_with_fuel_primitive(interceptor: StepInterceptor) -> Primitive:
    """Create the runtime %with-fuel primitive bound to the given interceptor."""

    def _prim_with_fuel(steps: Any, thunk: Any) -> Any:
        if not isinstance(steps, int):
            raise TypeError(f"with-fuel steps must be an integer, got {steps!r}")
        with interceptor.with_fuel_scope(steps):
            if isinstance(thunk, Procedure):
                return _apply_procedure(thunk, [])
            elif callable(thunk):
                return thunk()
            else:
                raise TypeError(f"with-fuel expected procedure thunk, got {thunk!r}")

    return Primitive("%with-fuel", _prim_with_fuel)
