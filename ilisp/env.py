"""Lexical Environment and Core Primitives for Kernel ILISP.

This module implements nested lexical scopes, variable binding, Cell boxing,
and standard R7RS-small core primitives plus Python zero-copy interop.
"""

from __future__ import annotations

import importlib
import sys
from typing import Any, Callable, Dict, Optional, Sequence, Union

from ilisp.types import (
    NIL,
    Cell,
    Cons,
    Primitive,
    SequenceView,
    Symbol,
    car,
    cdr,
    is_null,
    is_pair,
    to_lisp_list,
    to_py_list,
)


class Environment:
    """Lexical Environment frame with parent scoping chain."""

    def __init__(
        self,
        parent: Optional[Environment] = None,
        bindings: Optional[Dict[Symbol, Any]] = None,
    ) -> None:
        self.parent: Optional[Environment] = parent
        self.bindings: Dict[Symbol, Any] = bindings if bindings is not None else {}

    def define(self, sym: Symbol, val: Any) -> None:
        """Bind variable in the current local environment frame."""
        self.bindings[sym] = val

    def lookup(self, sym: Symbol) -> Any:
        """Lookup variable recursively through lexical chain; unwrap Cell if boxed."""
        curr: Optional[Environment] = self
        while curr is not None:
            if sym in curr.bindings:
                bound = curr.bindings[sym]
                if isinstance(bound, Cell):
                    return bound.get()
                return bound
            curr = curr.parent
        raise NameError(f"Unbound variable: '{sym.name}'")

    def lookup_cell(self, sym: Symbol) -> Optional[Cell]:
        """Lookup Cell container for variable if it is boxed."""
        curr: Optional[Environment] = self
        while curr is not None:
            if sym in curr.bindings:
                bound = curr.bindings[sym]
                if isinstance(bound, Cell):
                    return bound
                return None
            curr = curr.parent
        return None

    def set(self, sym: Symbol, val: Any) -> None:
        """Mutate existing variable via set!; updates Cell value if boxed."""
        curr: Optional[Environment] = self
        while curr is not None:
            if sym in curr.bindings:
                bound = curr.bindings[sym]
                if isinstance(bound, Cell):
                    bound.set(val)
                else:
                    curr.bindings[sym] = val
                return
            curr = curr.parent
        raise NameError(f"Cannot set! unbound variable: '{sym.name}'")

    def extend(self, params: Sequence[Symbol], args: Sequence[Any]) -> Environment:
        """Create a child environment binding parameters to arguments."""
        if len(params) != len(args):
            raise TypeError(
                f"Argument count mismatch: expected {len(params)}, got {len(args)}"
            )
        new_bindings = {p: a for p, a in zip(params, args)}
        return Environment(parent=self, bindings=new_bindings)


def make_initial_env() -> Environment:
    """Construct top-level global environment preloaded with 23 core primitives and Python interop."""
    env = Environment()

    # --- 1. Pair & List Primitives ---
    def prim_cons(a: Any, b: Any) -> Cons:
        return Cons(a, b)

    def prim_car(p: Any) -> Any:
        return car(p)

    def prim_cdr(p: Any) -> Any:
        return cdr(p)

    def prim_pair_p(x: Any) -> bool:
        return is_pair(x)

    def prim_null_p(x: Any) -> bool:
        return is_null(x)

    def prim_list(*args: Any) -> Any:
        return to_lisp_list(args)

    # --- 2. Symbol & String Primitives ---
    def prim_symbol_p(x: Any) -> bool:
        return isinstance(x, Symbol)

    def prim_symbol_to_string(s: Symbol) -> str:
        if not isinstance(s, Symbol):
            raise TypeError(f"symbol->string expected symbol, got {s!r}")
        return s.name

    def prim_string_p(x: Any) -> bool:
        return isinstance(x, str)

    def prim_string_append(*strs: str) -> str:
        return "".join(strs)

    def prim_string_eq_p(s1: str, s2: str) -> bool:
        return s1 == s2

    # --- 3. Equality & Boolean Primitives ---
    def prim_eq_p(a: Any, b: Any) -> bool:
        if isinstance(a, Symbol) and isinstance(b, Symbol):
            return a is b
        if a is NIL and b is NIL:
            return True
        return a is b

    def prim_eqv_p(a: Any, b: Any) -> bool:
        if isinstance(a, Symbol) and isinstance(b, Symbol):
            return a is b
        if isinstance(a, (int, float, str, bool)) and isinstance(
            b, (int, float, str, bool)
        ):
            return type(a) is type(b) and a == b
        return a is b

    def prim_boolean_p(x: Any) -> bool:
        return isinstance(x, bool)

    def prim_not(x: Any) -> bool:
        # In Scheme, only #f is false. Everything else (including 0 and '()) is truthy!
        return x is False

    # --- 4. Arithmetic & Comparison Primitives ---
    def prim_add(*nums: Union[int, float]) -> Union[int, float]:
        total: Union[int, float] = 0
        for n in nums:
            total += n
        return total

    def prim_sub(
        first: Union[int, float], *rest: Union[int, float]
    ) -> Union[int, float]:
        if not rest:
            return -first
        total = first
        for n in rest:
            total -= n
        return total

    def prim_mul(*nums: Union[int, float]) -> Union[int, float]:
        prod: Union[int, float] = 1
        for n in nums:
            prod *= n
        return prod

    def prim_quotient(a: int, b: int) -> int:
        return int(a // b)

    def prim_remainder(a: int, b: int) -> int:
        return int(a % b)

    def prim_num_eq(a: Union[int, float], b: Union[int, float]) -> bool:
        return a == b

    def prim_num_lt(a: Union[int, float], b: Union[int, float]) -> bool:
        return a < b

    def prim_num_gt(a: Union[int, float], b: Union[int, float]) -> bool:
        return a > b

    # --- 5. I/O Primitives ---
    def prim_display(x: Any) -> None:
        if isinstance(x, str):
            sys.stdout.write(x)
        else:
            sys.stdout.write(str(x))
        sys.stdout.flush()

    def prim_newline() -> None:
        sys.stdout.write("\n")
        sys.stdout.flush()

    def prim_write(x: Any) -> None:
        sys.stdout.write(repr(x))
        sys.stdout.flush()

    def prim_read_char() -> Optional[str]:
        ch = sys.stdin.read(1)
        return ch if ch else None

    def prim_eof_object_p(x: Any) -> bool:
        return x is None

    # --- 6. Python Zero-Copy & Interop Primitives ---
    def prim_sequence_view(seq: Sequence[Any], offset: int = 0) -> SequenceView:
        return SequenceView(seq, offset=offset)

    def prim_py_import(mod_name: Union[Symbol, str]) -> Any:
        name = mod_name.name if isinstance(mod_name, Symbol) else str(mod_name)
        return importlib.import_module(name)

    def prim_py_call(obj: Any, method: Union[Symbol, str], *args: Any) -> Any:
        method_name = method.name if isinstance(method, Symbol) else str(method)
        fn = getattr(obj, method_name)
        # Convert Scheme lists to python collections if needed
        unwrapped_args = [to_py_list(arg) if is_pair(arg) else arg for arg in args]
        return fn(*unwrapped_args)

    def prim_py_get(obj: Any, attr: Union[Symbol, str]) -> Any:
        attr_name = attr.name if isinstance(attr, Symbol) else str(attr)
        if isinstance(obj, dict):
            return obj.get(attr_name)
        return getattr(obj, attr_name)

    def prim_py_set_bang(obj: Any, attr: Union[Symbol, str], val: Any) -> None:
        attr_name = attr.name if isinstance(attr, Symbol) else str(attr)
        if isinstance(obj, dict):
            obj[attr_name] = val
        else:
            setattr(obj, attr_name, val)

    def prim_py_eval(expr_str: str) -> Any:
        return eval(expr_str)  # nosec

    # Register all primitives
    primitives: Dict[str, Callable[..., Any]] = {
        # Pairs and Lists
        "cons": prim_cons,
        "car": prim_car,
        "cdr": prim_cdr,
        "pair?": prim_pair_p,
        "null?": prim_null_p,
        "list": prim_list,
        # Symbols and Strings
        "symbol?": prim_symbol_p,
        "symbol->string": prim_symbol_to_string,
        "string?": prim_string_p,
        "string-append": prim_string_append,
        "string=?": prim_string_eq_p,
        # Equality and Booleans
        "eq?": prim_eq_p,
        "eqv?": prim_eqv_p,
        "boolean?": prim_boolean_p,
        "not": prim_not,
        # Arithmetic & Numeric comparison
        "+": prim_add,
        "-": prim_sub,
        "*": prim_mul,
        "quotient": prim_quotient,
        "remainder": prim_remainder,
        "=": prim_num_eq,
        "<": prim_num_lt,
        ">": prim_num_gt,
        # I/O
        "display": prim_display,
        "newline": prim_newline,
        "write": prim_write,
        "read-char": prim_read_char,
        "eof-object?": prim_eof_object_p,
        # Python Zero-Copy & Interop
        "sequence-view": prim_sequence_view,
        "py-import": prim_py_import,
        "py-call": prim_py_call,
        "py-get": prim_py_get,
        "py-set!": prim_py_set_bang,
        "py-eval": prim_py_eval,
    }

    for name, fn in primitives.items():
        sym = Symbol.intern(name)
        env.define(sym, Primitive(name, fn))

    return env
