"""ALisp Metering Subsystem.

Provides computational step budgeting, hierarchical sub-budgeting,
FuelExhaustedException, and automatic atomic transaction rollback for state mutations.
"""

from __future__ import annotations

import time
from contextlib import contextmanager
from contextvars import ContextVar
from typing import Any, Dict, Iterator, Optional, Set, Tuple

from ilisp.env import Environment
from ilisp.evaluator import _apply_procedure
from ilisp.types import NIL, Cell, Cons, Primitive, Procedure, Symbol, car, cdr, is_pair


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


class Transaction:
    """Manages transactional state mutations and atomic rollback upon fuel exhaustion."""

    def __init__(self, parent: Optional[Transaction] = None) -> None:
        self.parent = parent
        self.cell_snapshots: Dict[int, Tuple[Cell, Any]] = {}
        self.env_snapshots: Dict[
            Tuple[int, Symbol], Tuple[Environment, Symbol, Any]
        ] = {}
        self.managed_ports: Set[Any] = set()

    def record_cell(self, cell: Cell, old_val: Any) -> None:
        """Record the initial value of a Cell before its first mutation in this scope."""
        c_id = id(cell)
        if c_id not in self.cell_snapshots:
            self.cell_snapshots[c_id] = (cell, old_val)

    def record_env(self, env: Environment, sym: Symbol, old_val: Any) -> None:
        """Record the initial binding value in an Environment frame before mutation."""
        key = (id(env), sym)
        if key not in self.env_snapshots:
            self.env_snapshots[key] = (env, sym, old_val)

    def record_port(self, port: Any) -> None:
        """Track a ManagedPort used during this transaction."""
        self.managed_ports.add(port)

    def rollback(self) -> None:
        """Atomic rollback of all recorded mutations to their pre-transaction values."""
        for cell, initial_val in self.cell_snapshots.values():
            cell.value = initial_val
        for env, sym, initial_val in self.env_snapshots.values():
            env.bindings[sym] = initial_val
        for port in self.managed_ports:
            if hasattr(port, "rollback"):
                port.rollback()

    def merge_into_parent(self) -> None:
        """Merge committed mutations into parent transaction scope."""
        if self.parent is not None:
            for c_id, entry in self.cell_snapshots.items():
                if c_id not in self.parent.cell_snapshots:
                    self.parent.cell_snapshots[c_id] = entry
            for key, entry in self.env_snapshots.items():
                if key not in self.parent.env_snapshots:
                    self.parent.env_snapshots[key] = entry
            self.parent.managed_ports.update(self.managed_ports)


_current_transaction: ContextVar[Optional[Transaction]] = ContextVar(
    "_current_transaction", default=None
)


def _global_cell_mutation_hook(cell: Cell, old_val: Any) -> None:
    tx = _current_transaction.get()
    if tx is not None:
        tx.record_cell(cell, old_val)


def _global_env_mutation_hook(env: Environment, sym: Symbol, old_val: Any) -> None:
    tx = _current_transaction.get()
    if tx is not None:
        tx.record_env(env, sym, old_val)


# Install global hooks on Cell and Environment
Cell._mutation_hook = _global_cell_mutation_hook
Environment._mutation_hook = _global_env_mutation_hook


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
    """Manages active fuel counters and transaction scopes, providing DIP step hook for ILisp."""

    def __init__(self) -> None:
        self.current_counter: Optional[FuelCounter] = None
        self.current_transaction: Optional[Transaction] = None

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
        """Scoped fuel budget context manager supporting hierarchical sub-budgeting and rollback."""
        parent_counter = self.current_counter
        parent_tx = self.current_transaction

        effective_steps = (
            min(steps, parent_counter.remaining)
            if parent_counter is not None
            else steps
        )
        child_counter = FuelCounter(
            limit=effective_steps,
            parent=parent_counter,
            timeout_seconds=timeout_seconds,
        )
        child_tx = Transaction(parent=parent_tx)

        self.current_counter = child_counter
        self.current_transaction = child_tx
        token = _current_transaction.set(child_tx)

        try:
            yield child_counter
        except (FuelExhaustedException, TimeoutError):
            child_tx.rollback()
            raise
        except BaseException:
            child_tx.rollback()
            raise
        else:
            child_tx.merge_into_parent()
        finally:
            self.current_counter = parent_counter
            self.current_transaction = parent_tx
            _current_transaction.reset(token)


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
