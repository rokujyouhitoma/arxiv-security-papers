"""Runtime helpers for ILISP Python AST Code Generation Backend (`--backend=py_ast`).

Provides lightweight trampolining for mutual tail-call optimization, GlobalCell
lookup/mutation bridges, R7RS guard/quasiquote/values helpers, and procedure tagging
so py_ast-compiled closures interoperate seamlessly with eval_expr, apply, and call/cc.
"""

from __future__ import annotations

from contextvars import ContextVar
from typing import Any, Callable, List, Optional, Sequence, Tuple

from ilisp.env import Environment
from ilisp.types import (
    NIL,
    UNBOUND,
    Cons,
    ErrorObject,
    EscapeContinuation,
    GlobalCell,
    Primitive,
    SchemeException,
    Symbol,
    Values,
    Vector,
    to_lisp_list,
    to_py_list,
)

_NUM_FAST_TYPES = (int, float)


class _TailCall:
    """Deferred tail-call thunk returned by raw functions for mutual TCO trampoline."""

    __slots__ = ("fn", "args")
    fn: Any
    args: Tuple[Any, ...]

    def __init__(self, fn: Any, args: Tuple[Any, ...]) -> None:
        self.fn = fn
        self.args = args


def _trampoline(res: Any) -> Any:
    """Bounce `_TailCall` thunks iteratively until a final non-tail-call value emerges."""
    while type(res) is _TailCall:
        fn = res.fn
        raw = getattr(fn, "__ilisp_raw__", None)
        if raw is not None:
            res = raw(*res.args)
        else:
            res = fn(*res.args)
    return res


_cc_replay_stack: ContextVar[Tuple[Any, ...]] = ContextVar(
    "_cc_replay_stack", default=()
)


def _mark_proc(
    fn: Callable[..., Any],
    raw: Optional[Callable[..., Any]] = None,
    uses_call_cc: bool = False,
    path_getter: Optional[Callable[[], Any]] = None,
) -> Callable[..., Any]:
    """Tag a native Python function as an R7RS procedure (optionally linking raw TCO target)."""
    setattr(fn, "__ilisp_proc__", True)
    if raw is not None:
        setattr(fn, "__ilisp_raw__", raw)
    if uses_call_cc:

        def _replay(val: Any) -> Any:
            cur = _cc_replay_stack.get()
            tok = _cc_replay_stack.set(cur + (val,))
            try:
                return fn()
            finally:
                _cc_replay_stack.reset(tok)

        setattr(fn, "__ilisp_replay__", _replay)
    if path_getter is not None:
        setattr(fn, "__ilisp_path_getter__", path_getter)
    return fn


def _call_cc_or_replay(fn: Any, arg: Any) -> Any:
    """Return active continuation replay value if replaying `dynamic-wind`, else call `call/cc`."""
    cur = _cc_replay_stack.get()
    if cur:
        val = cur[-1]
        _cc_replay_stack.set(cur[:-1])
        return val
    return fn(arg)


def _call_tail(fn: Any, args: Tuple[Any, ...]) -> Any:
    """Return a `_TailCall` for py_ast procedures or tail-invoke interpreter/primitive callables."""
    if getattr(fn, "__ilisp_raw__", None) is not None:
        return _TailCall(fn, args)
    if type(fn) is Primitive:
        return fn.fn(*args)
    return fn(*args)


def _gref(cell: GlobalCell, env: Optional[Environment] = None) -> Any:
    """Dereference a GlobalCell, falling back to dotted Python interop or raising NameError."""
    val = cell.value
    if val is not UNBOUND:
        return val
    name = cell.sym.name
    if "." in name and not name.startswith(".") and env is not None:
        from ilisp.evaluator import _resolve_dotted_symbol

        resolved = _resolve_dotted_symbol(name, env)
        if resolved is not None:
            return resolved
    raise NameError(f"Unbound variable: '{name}'")


def _gdef(cell: GlobalCell, target_env: Environment, val: Any) -> Symbol:
    """Define a variable in `target_env` (updating its GlobalCell) and return the symbol."""
    target_env.define(cell.sym, val)
    return cell.sym


def _gset(cell: GlobalCell, target_env: Environment, val: Any) -> Symbol:
    """Mutate an existing variable via `target_env.set` (or raise if unbound)."""
    if cell.value is UNBOUND and target_env.parent is None:
        raise NameError(f"Unbound variable: '{cell.sym.name}'")
    target_env.set(cell.sym, val)
    return cell.sym


def _env_ref(env: Environment, sym: Symbol) -> Any:
    """Lookup `sym` dynamically in a non-root `Environment` with dotted-interop fallback."""
    try:
        return env.lookup(sym)
    except NameError:
        name = sym.name
        if "." in name and not name.startswith("."):
            from ilisp.evaluator import _resolve_dotted_symbol

            resolved = _resolve_dotted_symbol(name, env)
            if resolved is not None:
                return resolved
        raise


def _env_def(env: Environment, sym: Symbol, val: Any) -> Symbol:
    """Bind `sym` in `env` and return `sym`."""
    env.define(sym, val)
    return sym


def _env_set(env: Environment, sym: Symbol, val: Any) -> Symbol:
    """Mutate `sym` in `env` and return `sym`."""
    env.set(sym, val)
    return sym


def _check_vararg(
    args: Tuple[Any, ...], fixed_count: int, fn_name: str
) -> Tuple[Any, ...]:
    """Validate minimum arity for variadic functions with optional rest parameter."""
    if len(args) < fixed_count:
        raise TypeError(
            f"Procedure {fn_name} expected at least {fixed_count} arguments, got {len(args)}"
        )
    return args[:fixed_count] + (to_lisp_list(list(args[fixed_count:])),)


def _bind_values_target(val: Any, proper_count: int, has_rest: bool) -> Tuple[Any, ...]:
    """Unpack single value or `Values(...)` into tuple for `define-values`/`let-values`."""
    res_vals: Tuple[Any, ...] = val.values if isinstance(val, Values) else (val,)
    if not has_rest:
        if len(res_vals) != proper_count:
            raise SchemeException(
                ErrorObject(
                    f"define-values expected {proper_count} values, got {len(res_vals)}",
                    NIL,
                    kind="generic",
                )
            )
        return res_vals
    if len(res_vals) < proper_count:
        raise SchemeException(
            ErrorObject(
                f"define-values expected at least {proper_count} values, got {len(res_vals)}",
                NIL,
                kind="generic",
            )
        )
    return res_vals[:proper_count] + (to_lisp_list(list(res_vals[proper_count:])),)


def _qq_list_append(items: Sequence[Any], tail: Any = NIL) -> Any:
    """Build a proper or improper Scheme list from pre-built elements and splice segments."""
    res: Any = tail
    for kind, obj in reversed(items):
        if kind == 0:
            res = Cons(obj, res)
        else:
            if isinstance(obj, (list, tuple, Vector)):
                seq = list(obj)
            else:
                seq = to_py_list(obj)
            for elem in reversed(seq):
                res = Cons(elem, res)
    return res


def _qq_vec_append(items: Sequence[Tuple[int, Any]]) -> Vector:
    """Build a Scheme `Vector` from quasiquote elements and spliced sequences."""
    elems: List[Any] = []
    for kind, obj in items:
        if kind == 0:
            elems.append(obj)
        else:
            if isinstance(obj, (list, tuple, Vector)):
                elems.extend(obj)
            else:
                elems.extend(to_py_list(obj))
    return Vector(elems)


def _eqv_p(a: Any, b: Any) -> bool:
    """Exact R7RS eqv? semantics for `case` datum comparisons."""
    from fractions import Fraction

    if isinstance(a, Symbol) and isinstance(b, Symbol):
        return a is b
    if isinstance(a, (int, float, str, bool, complex, Fraction)) and isinstance(
        b, (int, float, str, bool, complex, Fraction)
    ):
        return type(a) is type(b) and a == b
    if type(a).__name__ == "Char" and type(b).__name__ == "Char":
        return bool(a == b)
    return a is b


def _in_datums(key: Any, datums: Tuple[Any, ...]) -> bool:
    """Return True if `key` matches any datum in `datums` under R7RS `eqv?`."""
    for d in datums:
        if _eqv_p(key, d):
            return True
    return False


def _eval_guard(
    body_fn: Callable[[], Any],
    handler_fn: Callable[[Any], Tuple[bool, Any]],
) -> Any:
    """Execute `(guard (var clause ...) body ...)` matching evaluator.py semantics."""
    from ilisp.reader import LispSyntaxError

    err_val: Any = None
    original_exc: Optional[Exception] = None
    try:
        return body_fn()
    except EscapeContinuation:
        raise
    except SchemeException as se:
        err_val = se.datum
        original_exc = se
    except (LispSyntaxError, SyntaxError) as syn_err:
        err_val = ErrorObject(str(syn_err), NIL, kind="read")
        original_exc = syn_err
    except (
        FileNotFoundError,
        PermissionError,
        IsADirectoryError,
        OSError,
    ) as os_err:
        err_val = ErrorObject(str(os_err), NIL, kind="file")
        original_exc = os_err
    except Exception as py_err:
        err_val = ErrorObject(str(py_err), NIL, kind="generic")
        original_exc = py_err

    handled, result = handler_fn(err_val)
    if handled:
        return result
    if original_exc is not None:
        raise original_exc
    raise SchemeException(err_val)


def _prim_add_rest(*args: Any) -> Any:
    res: Any = 0
    for a in args:
        res = res + a
    return res
