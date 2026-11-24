"""Tree-walk Evaluator and Trampoline TCO Engine for Kernel ILISP.

This module implements the core evaluation semantics of Kernel ILISP,
supporting standard special forms (quote, if, lambda, define, set!, begin, define-macro)
and tail-call optimization via trampolining.
"""

from __future__ import annotations

import importlib
from fractions import Fraction
from typing import Any, Callable, List, Optional, Tuple

from ilisp.compiler_ir import call_compiled_procedure
from ilisp.env import (
    _SENTINEL,
    _SHADOW_TRACKED_SYMBOLS,
    _SPECIAL_FORM_SYMBOLS,
    Environment,
)
from ilisp.reader import LispSyntaxError
from ilisp.syntax import SyntaxRulesTransformer
from ilisp.types import (
    NIL,
    Bytevector,
    Cell,
    Char,
    Cons,
    Continuation,
    ErrorObject,
    EscapeContinuation,
    MutableString,
    NilType,
    Parameter,
    Primitive,
    Procedure,
    Record,
    RecordType,
    SchemeException,
    Symbol,
    Values,
    Vector,
    car,
    cdr,
    is_null,
    is_pair,
    to_lisp_list,
    to_py_list,
)

StepHook = Callable[[], None]

_current_step_hook: Optional[StepHook] = None


def get_step_hook() -> Optional[StepHook]:
    """Return the currently active evaluation step hook, if any."""
    return _current_step_hook


def set_step_hook(hook: Optional[StepHook]) -> None:
    """Set or clear the active evaluation step hook."""
    global _current_step_hook
    _current_step_hook = hook


class StepHookContext:
    """Context manager for scoped installation of an evaluation step hook."""

    def __init__(self, hook: Optional[StepHook]) -> None:
        self.hook = hook
        self.old_hook: Optional[StepHook] = None

    def __enter__(self) -> StepHookContext:
        self.old_hook = get_step_hook()
        set_step_hook(self.hook)
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        set_step_hook(self.old_hook)


class Evaluator:
    """R7RS Scheme Evaluator engine with DIP Step Hook support."""

    def __init__(self, step_hook: Optional[StepHook] = None) -> None:
        self.step_hook = step_hook

    def eval(self, expr: Any, env: Environment) -> Any:
        """Evaluate an expression within the given environment under this evaluator's hook."""
        with StepHookContext(self.step_hook):
            return eval_expr(expr, env)


class TailCall:
    """Trampoline token holding an expression and environment to be evaluated in tail position."""

    __slots__ = ("expr", "env")

    def __init__(self, expr: Any, env: Environment) -> None:
        self.expr = expr
        self.env = env


_SELF_EVALUATING_TYPES = (
    int,
    float,
    complex,
    str,
    bool,
    NilType,
    Primitive,
    Procedure,
    Vector,
    Bytevector,
    Char,
    MutableString,
    Parameter,
    RecordType,
    Record,
    Continuation,
    Fraction,
)

_SCALAR_TYPES = (int, bool, str, float)
_ELSE_SYM = Symbol.intern("else")
_ARROW_SYM = Symbol.intern("=>")
_QUOTE_SYM = Symbol.intern("quote")

_interaction_environment_ready = False


def _is_locally_bound(sym: Symbol, env: Environment) -> bool:
    """Return True if `sym` is shadowed in any non-root lexical frame."""
    if not env._has_shadowed_sf:
        return False
    cur: Optional[Environment] = env
    while cur is not None and cur.parent is not None:
        if sym in cur.bindings:
            return True
        cur = cur.parent
    return False


def _check_shadows_sf(params: Any, rest_param: Optional[Symbol]) -> bool:
    """Return True if parameter list contains any special-form/arrow/else symbol."""
    if rest_param is not None and rest_param in _SHADOW_TRACKED_SYMBOLS:
        return True
    if type(params) is Symbol:
        return params in _SHADOW_TRACKED_SYMBOLS
    for p in params:
        if p in _SHADOW_TRACKED_SYMBOLS:
            return True
    return False


def _eqv_p(a: Any, b: Any) -> bool:
    """Fast R7RS eqv? helper for case matching."""
    if a is b:
        return True
    ta = type(a)
    if ta is type(b) and isinstance(
        a, (int, float, str, bool, Char, complex, Fraction)
    ):
        return bool(a == b)
    return False


def _build_syntax_transformer(name: str, trans_spec: Any, env: Environment) -> Any:
    """Build a SyntaxRulesTransformer or evaluate macro transformer."""
    from ilisp.syntax import SyntaxRulesTransformer

    if (
        is_pair(trans_spec)
        and isinstance(car(trans_spec), Symbol)
        and car(trans_spec).name == "syntax-rules"
    ):
        spec_args = cdr(trans_spec)
        if not is_pair(spec_args):
            raise SyntaxError("syntax-rules requires literals list and rules")
        first_arg = car(spec_args)
        if isinstance(first_arg, Symbol) and is_pair(cdr(spec_args)):
            ellipsis_sym = first_arg.name
            spec_args = cdr(spec_args)
            literals_expr = car(spec_args)
        else:
            ellipsis_sym = "..."
            literals_expr = first_arg

        raw_literals = to_py_list(literals_expr)
        literals = [lit.name for lit in raw_literals if isinstance(lit, Symbol)]
        rules_raw = to_py_list(cdr(spec_args))
        rules: List[Tuple[Any, Any]] = []
        for r in rules_raw:
            if not is_pair(r) or not is_pair(cdr(r)):
                raise SyntaxError(
                    f"syntax-rules rule must be (pattern template), got {r!r}"
                )
            rules.append((car(r), car(cdr(r))))
        return SyntaxRulesTransformer(
            name, literals, rules, ellipsis=ellipsis_sym, def_env=env
        )
    return eval_expr(trans_spec, env)


def _resolve_dotted_symbol(name: str, env: Environment) -> Any:
    """Resolve a symbol with dot notation (e.g. math.pi, os.getcwd, resp.status_code).

    1. If the root prefix is bound in `env`, traverse properties from the bound object.
    2. Otherwise, attempt to import the module prefix via `importlib.import_module` and
       traverse properties from the imported module.
    """
    if not name or name.startswith(".") or name.endswith(".") or ".." in name:
        return None

    parts = name.split(".")
    if not all(p.isidentifier() for p in parts):
        return None

    # Step 1: Check if parts[0] is bound in lexical/global environment
    first_sym = Symbol.intern(parts[0])
    curr_obj: Any = None
    resolved_root = False
    try:
        curr_obj = env.lookup(first_sym)
        resolved_root = True
    except NameError:
        pass

    if resolved_root:
        for p in parts[1:]:
            if isinstance(curr_obj, dict):
                if p in curr_obj:
                    curr_obj = curr_obj[p]
                else:
                    raise NameError(
                        f"Dotted symbol '{name}': key {p!r} not found in dict"
                    )
            elif hasattr(curr_obj, p):
                curr_obj = getattr(curr_obj, p)
            else:
                raise NameError(
                    f"Dotted symbol '{name}': object {curr_obj!r} has no attribute {p!r}"
                )
        return curr_obj

    # Step 2: Try importing module prefix
    for k in range(len(parts) - 1, 0, -1):
        mod_name = ".".join(parts[:k])
        try:
            mod = importlib.import_module(mod_name)
        except Exception:
            continue

        curr_obj = mod
        for p in parts[k:]:
            if hasattr(curr_obj, p):
                curr_obj = getattr(curr_obj, p)
            elif isinstance(curr_obj, dict) and p in curr_obj:
                curr_obj = curr_obj[p]
            else:
                raise NameError(
                    f"Dotted symbol '{name}': attribute {p!r} not found in module {curr_obj!r}"
                )
        return curr_obj

    return None


def eval_expr(expr: Any, env: Environment, step_hook: Optional[StepHook] = None) -> Any:
    """Evaluate an S-expression within an environment using a trampoline loop for TCO."""
    if step_hook is not None:
        with StepHookContext(step_hook):
            return eval_expr(expr, env)

    global _interaction_environment_ready
    if not _interaction_environment_ready:
        from ilisp.env import get_interaction_environment, set_interaction_environment

        if get_interaction_environment() is None:
            set_interaction_environment(env.root)
        _interaction_environment_ready = True

    curr_expr: Any = expr
    curr_env: Environment = env

    while True:
        if _current_step_hook is not None:
            _current_step_hook()

        expr_type = type(curr_expr)

        # 1. Pair / Form evaluation
        if expr_type is Cons:
            op = curr_expr.car

            # --- Special Forms ---
            if type(op) is Symbol:
                if op in _SPECIAL_FORM_SYMBOLS:
                    op_name = op.name

                    # (quote datum)
                    if op_name == "quote" and (
                        not curr_env._has_shadowed_sf
                        or not _is_locally_bound(op, curr_env)
                    ):
                        args = curr_expr.cdr
                        if type(args) is Cons:
                            return args.car
                        if is_pair(args):
                            return car(args)
                        raise SyntaxError("quote requires 1 argument")

                    # (if test then [else]) - R7RS / macro fallback checks arity before lexical shadow
                    if op_name == "if":
                        cdr1 = curr_expr.cdr
                        if type(cdr1) is Cons:
                            cdr2 = cdr1.cdr
                            if type(cdr2) is Cons:
                                cdr3 = cdr2.cdr
                                if cdr3 is NIL:
                                    if eval_expr(cdr1.car, curr_env) is not False:
                                        curr_expr = cdr2.car
                                        continue
                                    return NIL
                                if type(cdr3) is Cons and cdr3.cdr is NIL:
                                    if eval_expr(cdr1.car, curr_env) is not False:
                                        curr_expr = cdr2.car
                                    else:
                                        curr_expr = cdr3.car
                                    continue

                        if not _is_locally_bound(op, curr_env):
                            args = to_py_list(curr_expr.cdr)
                            raise SyntaxError(
                                f"if requires 2 or 3 expressions, got {len(args)}"
                            )

                    # (let bindings body ...) or (let name bindings body ...)
                    elif op_name == "let":
                        args = curr_expr.cdr
                        if not is_pair(args):
                            if not _is_locally_bound(op, curr_env):
                                raise SyntaxError("let requires bindings and body")
                        else:
                            first_arg = car(args)
                            if isinstance(first_arg, Symbol) and not is_pair(cdr(args)):
                                if not _is_locally_bound(op, curr_env):
                                    raise SyntaxError(
                                        "Named let requires bindings and body"
                                    )
                            elif isinstance(first_arg, Symbol):
                                # Named let: (let name ((var val) ...) body ...)
                                let_name = first_arg
                                bindings = car(cdr(args))
                                body = cdr(cdr(args))
                                vars_list: List[Symbol] = []
                                vals_list: List[Any] = []
                                cur_b = bindings
                                while type(cur_b) is Cons:
                                    b = cur_b.car
                                    vars_list.append(b.car)
                                    vals_list.append(eval_expr(b.cdr.car, curr_env))
                                    cur_b = cur_b.cdr
                                if cur_b is not NIL:
                                    b_list = to_py_list(cur_b)
                                    for b in b_list:
                                        vars_list.append(car(b))
                                        vals_list.append(
                                            eval_expr(car(cdr(b)), curr_env)
                                        )
                                body_list = to_py_list(body)
                                new_env = Environment(
                                    parent=curr_env,
                                    has_shadowed_sf=curr_env._has_shadowed_sf
                                    or (let_name in _SHADOW_TRACKED_SYMBOLS),
                                )
                                proc = Procedure(
                                    vars_list,
                                    body_list,
                                    new_env,
                                    name=let_name.name,
                                    shadows_sf=_check_shadows_sf(vars_list, None),
                                )
                                new_env.define(let_name, proc)
                                call_env = _bind_procedure_call(proc, vals_list)
                                if not body_list:
                                    return NIL
                                for step in body_list[:-1]:
                                    eval_expr(step, call_env)
                                curr_expr = body_list[-1]
                                curr_env = call_env
                                continue
                            elif (
                                first_arg is NIL
                                or (
                                    type(first_arg) is Cons
                                    and type(first_arg.car) is Cons
                                )
                                or not _is_locally_bound(op, curr_env)
                            ):
                                bindings = first_arg
                                body = cdr(args)
                                eval_bindings: dict[Symbol, Any] = {}
                                cur_b = bindings
                                has_sf = curr_env._has_shadowed_sf
                                while type(cur_b) is Cons:
                                    b = cur_b.car
                                    if type(b) is not Cons or type(b.cdr) is not Cons:
                                        raise SyntaxError(
                                            f"let: malformed binding: {b!r}"
                                        )
                                    vsym = b.car
                                    if not has_sf and vsym in _SHADOW_TRACKED_SYMBOLS:
                                        has_sf = True
                                    eval_bindings[vsym] = eval_expr(b.cdr.car, curr_env)
                                    cur_b = cur_b.cdr
                                if cur_b is not NIL:
                                    for b in to_py_list(cur_b):
                                        if not is_pair(b) or not is_pair(cdr(b)):
                                            raise SyntaxError(
                                                f"let: malformed binding: {b!r}"
                                            )
                                        vsym = car(b)
                                        if (
                                            not has_sf
                                            and vsym in _SHADOW_TRACKED_SYMBOLS
                                        ):
                                            has_sf = True
                                        eval_bindings[vsym] = eval_expr(
                                            car(cdr(b)), curr_env
                                        )
                                new_env = Environment(
                                    parent=curr_env,
                                    bindings=eval_bindings,
                                    has_shadowed_sf=has_sf,
                                )
                                if body is NIL:
                                    return NIL
                                cur_step = body
                                while type(cur_step) is Cons:
                                    nxt_step = cur_step.cdr
                                    if nxt_step is NIL:
                                        curr_expr = cur_step.car
                                        curr_env = new_env
                                        break
                                    eval_expr(cur_step.car, new_env)
                                    cur_step = nxt_step
                                else:
                                    if is_null(cur_step):
                                        return NIL
                                    body_exprs = to_py_list(cur_step)
                                    if not body_exprs:
                                        return NIL
                                    for step in body_exprs[:-1]:
                                        eval_expr(step, new_env)
                                    curr_expr = body_exprs[-1]
                                    curr_env = new_env
                                continue

                    elif not curr_env._has_shadowed_sf or not _is_locally_bound(
                        op, curr_env
                    ):
                        # (and expr ...)
                        if op_name == "and":
                            cur_a = curr_expr.cdr
                            if cur_a is NIL:
                                return True
                            while type(cur_a) is Cons:
                                nxt_a = cur_a.cdr
                                if nxt_a is NIL:
                                    curr_expr = cur_a.car
                                    break
                                if eval_expr(cur_a.car, curr_env) is False:
                                    return False
                                cur_a = nxt_a
                            else:
                                if is_null(cur_a):
                                    return True
                                raise SyntaxError("and: malformed expression list")
                            continue

                        # (or expr ...)
                        if op_name == "or":
                            cur_o = curr_expr.cdr
                            if cur_o is NIL:
                                return False
                            while type(cur_o) is Cons:
                                nxt_o = cur_o.cdr
                                if nxt_o is NIL:
                                    curr_expr = cur_o.car
                                    break
                                val_o = eval_expr(cur_o.car, curr_env)
                                if val_o is not False:
                                    return val_o
                                cur_o = nxt_o
                            else:
                                if is_null(cur_o):
                                    return False
                                raise SyntaxError("or: malformed expression list")
                            continue

                        # (when test expr ...) / (unless test expr ...)
                        if op_name == "when":
                            args = curr_expr.cdr
                            if not is_pair(args):
                                raise SyntaxError("when requires a test expression")
                            if eval_expr(car(args), curr_env) is False:
                                return NIL
                            cur_b = cdr(args)
                            if cur_b is NIL:
                                return NIL
                            while type(cur_b) is Cons:
                                nxt_b = cur_b.cdr
                                if nxt_b is NIL:
                                    curr_expr = cur_b.car
                                    break
                                eval_expr(cur_b.car, curr_env)
                                cur_b = nxt_b
                            else:
                                if is_null(cur_b):
                                    return NIL
                                raise SyntaxError("when: malformed body list")
                            continue

                        if op_name == "unless":
                            args = curr_expr.cdr
                            if not is_pair(args):
                                raise SyntaxError("unless requires a test expression")
                            if eval_expr(car(args), curr_env) is not False:
                                return NIL
                            cur_b = cdr(args)
                            if cur_b is NIL:
                                return NIL
                            while type(cur_b) is Cons:
                                nxt_b = cur_b.cdr
                                if nxt_b is NIL:
                                    curr_expr = cur_b.car
                                    break
                                eval_expr(cur_b.car, curr_env)
                                cur_b = nxt_b
                            else:
                                if is_null(cur_b):
                                    return NIL
                                raise SyntaxError("unless: malformed body list")
                            continue

                        # (cond clause ...)
                        if op_name == "cond":
                            cur_cl = curr_expr.cdr
                            has_match = False
                            while type(cur_cl) is Cons:
                                clause = cur_cl.car
                                if not is_pair(clause):
                                    raise SyntaxError(
                                        f"cond: malformed clause: {clause!r}"
                                    )
                                test_or_else = car(clause)
                                body_rest = cdr(clause)

                                if test_or_else is _ELSE_SYM and (
                                    not curr_env._has_shadowed_sf
                                    or not _is_locally_bound(_ELSE_SYM, curr_env)
                                ):
                                    if is_null(body_rest):
                                        return NIL
                                    if (
                                        is_pair(body_rest)
                                        and car(body_rest) is _ARROW_SYM
                                        and (
                                            not curr_env._has_shadowed_sf
                                            or not _is_locally_bound(
                                                _ARROW_SYM, curr_env
                                            )
                                        )
                                    ):
                                        recip = eval_expr(car(cdr(body_rest)), curr_env)
                                        if type(recip) is Primitive:
                                            return recip.fn()
                                        curr_expr = Cons(recip, NIL)
                                        has_match = True
                                        break
                                    cur_b = body_rest
                                    while type(cur_b) is Cons:
                                        nxt_b = cur_b.cdr
                                        if nxt_b is NIL:
                                            curr_expr = cur_b.car
                                            has_match = True
                                            break
                                        eval_expr(cur_b.car, curr_env)
                                        cur_b = nxt_b
                                    if has_match:
                                        break
                                    body_exprs = to_py_list(body_rest)
                                    if not body_exprs:
                                        return NIL
                                    for step in body_exprs[:-1]:
                                        eval_expr(step, curr_env)
                                    curr_expr = body_exprs[-1]
                                    has_match = True
                                    break

                                t_val = eval_expr(test_or_else, curr_env)
                                if t_val is not False:
                                    if is_null(body_rest):
                                        return t_val
                                    if (
                                        is_pair(body_rest)
                                        and car(body_rest) is _ARROW_SYM
                                        and (
                                            not curr_env._has_shadowed_sf
                                            or not _is_locally_bound(
                                                _ARROW_SYM, curr_env
                                            )
                                        )
                                    ):
                                        recip_expr = car(cdr(body_rest))
                                        recip = eval_expr(recip_expr, curr_env)
                                        if type(recip) is Primitive:
                                            return recip.fn(t_val)
                                        if type(recip) is Procedure:
                                            call_env = _bind_procedure_call(
                                                recip, [t_val]
                                            )
                                            rbody = recip.body
                                            if not rbody:
                                                return NIL
                                            for step in rbody[:-1]:
                                                eval_expr(step, call_env)
                                            curr_expr = rbody[-1]
                                            curr_env = call_env
                                            has_match = True
                                            break
                                        if callable(recip):
                                            return recip(t_val)
                                        raise TypeError(
                                            f"cond => expected procedure, got {recip!r}"
                                        )

                                    cur_b = body_rest
                                    while type(cur_b) is Cons:
                                        nxt_b = cur_b.cdr
                                        if nxt_b is NIL:
                                            curr_expr = cur_b.car
                                            has_match = True
                                            break
                                        eval_expr(cur_b.car, curr_env)
                                        cur_b = nxt_b
                                    if has_match:
                                        break
                                    body_exprs = to_py_list(body_rest)
                                    if not body_exprs:
                                        return t_val
                                    for step in body_exprs[:-1]:
                                        eval_expr(step, curr_env)
                                    curr_expr = body_exprs[-1]
                                    has_match = True
                                    break

                                cur_cl = cur_cl.cdr

                            if has_match:
                                continue
                            if cur_cl is NIL:
                                return NIL
                            raise SyntaxError(
                                f"cond: malformed clause list: {cur_cl!r}"
                            )

                        # (case key clause ...)
                        if op_name == "case":
                            args = curr_expr.cdr
                            if not is_pair(args):
                                raise SyntaxError("case requires key and clauses")
                            key_val = eval_expr(car(args), curr_env)
                            cur_cl = cdr(args)
                            has_match = False
                            while type(cur_cl) is Cons:
                                clause = cur_cl.car
                                if not is_pair(clause):
                                    raise SyntaxError(
                                        f"case: malformed clause: {clause!r}"
                                    )
                                datums = car(clause)
                                body_rest = cdr(clause)
                                matched = False
                                if datums is _ELSE_SYM and (
                                    not curr_env._has_shadowed_sf
                                    or not _is_locally_bound(_ELSE_SYM, curr_env)
                                ):
                                    matched = True
                                else:
                                    cur_d = datums
                                    while type(cur_d) is Cons:
                                        if _eqv_p(key_val, cur_d.car):
                                            matched = True
                                            break
                                        cur_d = cur_d.cdr
                                    if not matched and is_pair(cur_d):
                                        while is_pair(cur_d):
                                            if _eqv_p(key_val, car(cur_d)):
                                                matched = True
                                                break
                                            cur_d = cdr(cur_d)
                                if matched:
                                    if is_null(body_rest):
                                        return NIL
                                    if (
                                        is_pair(body_rest)
                                        and car(body_rest) is _ARROW_SYM
                                        and (
                                            not curr_env._has_shadowed_sf
                                            or not _is_locally_bound(
                                                _ARROW_SYM, curr_env
                                            )
                                        )
                                    ):
                                        recip = eval_expr(car(cdr(body_rest)), curr_env)
                                        if type(recip) is Primitive:
                                            return recip.fn(key_val)
                                        if type(recip) is Procedure:
                                            call_env = _bind_procedure_call(
                                                recip, [key_val]
                                            )
                                            rbody = recip.body
                                            if not rbody:
                                                return NIL
                                            for step in rbody[:-1]:
                                                eval_expr(step, call_env)
                                            curr_expr = rbody[-1]
                                            curr_env = call_env
                                            has_match = True
                                            break
                                        if callable(recip):
                                            return recip(key_val)
                                        raise TypeError(
                                            f"case => expected procedure, got {recip!r}"
                                        )
                                    cur_b = body_rest
                                    while type(cur_b) is Cons:
                                        nxt_b = cur_b.cdr
                                        if nxt_b is NIL:
                                            curr_expr = cur_b.car
                                            has_match = True
                                            break
                                        eval_expr(cur_b.car, curr_env)
                                        cur_b = nxt_b
                                    if has_match:
                                        break
                                    return NIL
                                cur_cl = cur_cl.cdr
                            if has_match:
                                continue
                            return NIL

                        # (do ((var init [step]) ...) (test expr ...) command ...)
                        if op_name == "do":
                            args = curr_expr.cdr
                            if not is_pair(args) or not is_pair(cdr(args)):
                                raise SyntaxError(
                                    "do requires bindings list and test clause"
                                )
                            var_specs = to_py_list(car(args))
                            test_clause = car(cdr(args))
                            if not is_pair(test_clause):
                                raise SyntaxError(
                                    f"do: malformed test clause: {test_clause!r}"
                                )
                            test_expr = car(test_clause)
                            exit_exprs = to_py_list(cdr(test_clause))
                            commands = to_py_list(cdr(cdr(args)))

                            do_vars: List[Symbol] = []
                            do_steps: List[Any] = []
                            init_bindings: dict[Symbol, Any] = {}
                            has_sf_var = curr_env._has_shadowed_sf
                            for vs in var_specs:
                                vs_list = to_py_list(vs)
                                if len(vs_list) < 2 or len(vs_list) > 3:
                                    raise SyntaxError(
                                        f"do: malformed variable spec: {vs!r}"
                                    )
                                v_sym = vs_list[0]
                                if not isinstance(v_sym, Symbol):
                                    raise SyntaxError(
                                        f"do: variable must be symbol: {v_sym!r}"
                                    )
                                if not has_sf_var and v_sym in _SHADOW_TRACKED_SYMBOLS:
                                    has_sf_var = True
                                init_val = eval_expr(vs_list[1], curr_env)
                                do_vars.append(v_sym)
                                do_steps.append(
                                    vs_list[2] if len(vs_list) == 3 else v_sym
                                )
                                init_bindings[v_sym] = init_val

                            loop_env = Environment(
                                parent=curr_env,
                                bindings=init_bindings,
                                has_shadowed_sf=has_sf_var,
                            )
                            while eval_expr(test_expr, loop_env) is False:
                                for cmd in commands:
                                    eval_expr(cmd, loop_env)
                                next_bindings = {
                                    vsym: eval_expr(step_e, loop_env)
                                    for vsym, step_e in zip(do_vars, do_steps)
                                }
                                loop_env = Environment(
                                    parent=curr_env,
                                    bindings=next_bindings,
                                    has_shadowed_sf=has_sf_var,
                                )

                            if not exit_exprs:
                                return NIL
                            for ex_step in exit_exprs[:-1]:
                                eval_expr(ex_step, loop_env)
                            curr_expr = exit_exprs[-1]
                            curr_env = loop_env
                            continue

                        # (begin expr ...)
                        if op_name == "begin":
                            cur_b = curr_expr.cdr
                            if cur_b is NIL:
                                return NIL
                            while type(cur_b) is Cons:
                                nxt_b = cur_b.cdr
                                if nxt_b is NIL:
                                    curr_expr = cur_b.car
                                    break
                                eval_expr(cur_b.car, curr_env)
                                cur_b = nxt_b
                            else:
                                if is_null(cur_b):
                                    return NIL
                                body_exprs = to_py_list(cur_b)
                                if not body_exprs:
                                    return NIL
                                for step in body_exprs[:-1]:
                                    eval_expr(step, curr_env)
                                curr_expr = body_exprs[-1]
                            continue

                        # (let* bindings body ...)
                        if op_name == "let*":
                            args = curr_expr.cdr
                            if not is_pair(args):
                                raise SyntaxError("let* requires bindings and body")
                            bindings = car(args)
                            body = cdr(args)
                            new_env = Environment(
                                parent=curr_env,
                                has_shadowed_sf=curr_env._has_shadowed_sf,
                            )
                            cur_b = bindings
                            while type(cur_b) is Cons:
                                b = cur_b.car
                                if type(b) is not Cons or type(b.cdr) is not Cons:
                                    raise SyntaxError(f"let*: malformed binding: {b!r}")
                                vsym = b.car
                                val_e = eval_expr(b.cdr.car, new_env)
                                if vsym in new_env.bindings:
                                    new_env = Environment(
                                        parent=new_env,
                                        has_shadowed_sf=new_env._has_shadowed_sf,
                                    )
                                new_env.define(vsym, val_e)
                                cur_b = cur_b.cdr
                            if cur_b is not NIL:
                                for b in to_py_list(cur_b):
                                    if not is_pair(b) or not is_pair(cdr(b)):
                                        raise SyntaxError(
                                            f"let*: malformed binding: {b!r}"
                                        )
                                    vsym = car(b)
                                    val_e = eval_expr(car(cdr(b)), new_env)
                                    if vsym in new_env.bindings:
                                        new_env = Environment(
                                            parent=new_env,
                                            has_shadowed_sf=new_env._has_shadowed_sf,
                                        )
                                    new_env.define(vsym, val_e)
                            if body is NIL:
                                return NIL
                            cur_step = body
                            while type(cur_step) is Cons:
                                nxt_step = cur_step.cdr
                                if nxt_step is NIL:
                                    curr_expr = cur_step.car
                                    curr_env = new_env
                                    break
                                eval_expr(cur_step.car, new_env)
                                cur_step = nxt_step
                            else:
                                if is_null(cur_step):
                                    return NIL
                                body_exprs = to_py_list(cur_step)
                                if not body_exprs:
                                    return NIL
                                for step in body_exprs[:-1]:
                                    eval_expr(step, new_env)
                                curr_expr = body_exprs[-1]
                                curr_env = new_env
                            continue

                        # (letrec bindings body ...) or (letrec* bindings body ...)
                        if op_name in ("letrec", "letrec*"):
                            args = curr_expr.cdr
                            if not is_pair(args):
                                raise SyntaxError(
                                    f"{op_name} requires bindings and body"
                                )
                            bindings = car(args)
                            body = cdr(args)
                            b_list = to_py_list(bindings)
                            new_env = curr_env.extend()
                            for b in b_list:
                                if not is_pair(b) or not is_pair(cdr(b)):
                                    raise SyntaxError(
                                        f"{op_name}: malformed binding: {b!r}"
                                    )
                                new_env.define(car(b), NIL)
                            eval_rec_vals = []
                            for b in b_list:
                                val = eval_expr(car(cdr(b)), new_env)
                                if op_name == "letrec*":
                                    new_env.define(car(b), val)
                                else:
                                    eval_rec_vals.append((car(b), val))
                            if op_name == "letrec":
                                for var_s, val_v in eval_rec_vals:
                                    new_env.define(var_s, val_v)
                            body_exprs = to_py_list(body)
                            if not body_exprs:
                                return NIL
                            for step in body_exprs[:-1]:
                                eval_expr(step, new_env)
                            curr_expr = body_exprs[-1]
                            curr_env = new_env
                            continue

                        # (syntax-error message irritants...)
                        if op_name == "syntax-error":
                            args = to_py_list(curr_expr.cdr)
                            if not args:
                                err_obj = ErrorObject(
                                    "syntax-error requires at least a message",
                                    NIL,
                                    kind="read",
                                )
                                raise SchemeException(err_obj)
                            msg_raw = args[0]
                            if isinstance(msg_raw, str):
                                msg_str = msg_raw
                            else:
                                eval_msg = eval_expr(msg_raw, curr_env)
                                msg_str = (
                                    str(eval_msg)
                                    if not isinstance(eval_msg, str)
                                    else eval_msg
                                )
                            irritants_list = (
                                to_lisp_list(args[1:]) if len(args) > 1 else NIL
                            )
                            err_obj = ErrorObject(msg_str, irritants_list, kind="read")
                            raise SchemeException(err_obj)

                        # (quasiquote template)
                        if op_name == "quasiquote":
                            args = curr_expr.cdr
                            if not is_pair(args):
                                raise SyntaxError("quasiquote requires 1 argument")
                            return eval_quasiquote(car(args), curr_env)

                        # (cond-expand clause ...)
                        if op_name == "cond-expand":
                            clauses = to_py_list(curr_expr.cdr)
                            features = {"r7rs", "ilisp", "antigravity"}
                            matched_exprs = None
                            for clause in clauses:
                                if not is_pair(clause):
                                    continue
                                req = car(clause)
                                body_list = to_py_list(cdr(clause))
                                matched = False
                                if req == _ELSE_SYM:
                                    matched = True
                                elif isinstance(req, Symbol) and req.name in features:
                                    matched = True
                                if matched:
                                    matched_exprs = body_list
                                    break
                            if matched_exprs is None or not matched_exprs:
                                return NIL
                            for step in matched_exprs[:-1]:
                                eval_expr(step, curr_env)
                            curr_expr = matched_exprs[-1]
                            continue

                        # (guard (var clause ...) body ...)
                        if op_name == "guard":
                            guard_args = curr_expr.cdr
                            if not is_pair(guard_args) or not is_pair(guard_args.cdr):
                                raise SyntaxError(
                                    "guard requires (guard (var clause ...) body ...)"
                                )
                            spec = car(guard_args)
                            body_rest = cdr(guard_args)
                            if not is_pair(spec):
                                raise SyntaxError("guard: malformed spec")
                            var_sym = car(spec)
                            if not isinstance(var_sym, Symbol):
                                raise SyntaxError("guard: variable must be a symbol")
                            clauses = to_py_list(cdr(spec))
                            body_exprs = to_py_list(body_rest)

                            err_val: Any = None
                            original_exc: Optional[Exception] = None
                            try:
                                res = NIL
                                for step in body_exprs:
                                    res = eval_expr(step, curr_env)
                                return res
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

                            h_env = curr_env.extend()
                            h_env.define(var_sym, err_val)
                            for clause in clauses:
                                if not is_pair(clause):
                                    raise SyntaxError(
                                        f"guard: malformed clause: {clause!r}"
                                    )
                                c_test = car(clause)
                                c_body = cdr(clause)

                                if c_test is _ELSE_SYM:
                                    c_exprs = to_py_list(c_body)
                                    if not c_exprs:
                                        return NIL
                                    c_res = NIL
                                    for c_step in c_exprs:
                                        c_res = eval_expr(c_step, h_env)
                                    return c_res

                                t_val = eval_expr(c_test, h_env)
                                if t_val is not False:
                                    if is_null(c_body):
                                        return t_val
                                    if is_pair(c_body) and car(c_body) is _ARROW_SYM:
                                        recip_expr = car(cdr(c_body))
                                        recip = eval_expr(recip_expr, h_env)
                                        if isinstance(recip, Procedure):
                                            return _apply_procedure(recip, [t_val])
                                        elif isinstance(recip, Primitive):
                                            return recip.fn(t_val)
                                        elif callable(recip):
                                            return recip(t_val)
                                        raise TypeError(
                                            f"guard => expected procedure, got {recip!r}"
                                        )
                                    c_exprs = to_py_list(c_body)
                                    c_res = NIL
                                    for c_step in c_exprs:
                                        c_res = eval_expr(c_step, h_env)
                                    return c_res

                            if original_exc is not None:
                                raise original_exc
                            raise SchemeException(err_val)

                        # (include string1 string2 ...) / (include-ci string1 string2 ...)
                        if op_name in ("include", "include-ci"):
                            args = to_py_list(curr_expr.cdr)
                            if not args:
                                raise SchemeException(
                                    ErrorObject(
                                        f"{op_name}: requires at least one filename string",
                                        NIL,
                                        kind="file",
                                    )
                                )
                            from ilisp.reader import (
                                active_include_context,
                                extract_base_dir,
                                extract_caller_file,
                                read_all_from_file,
                                resolve_include_path,
                            )

                            caller_file = extract_caller_file(curr_expr)
                            base_dir = extract_base_dir(curr_expr)
                            fold_case = op_name == "include-ci"

                            last_res: Any = NIL
                            for arg in args:
                                if not isinstance(arg, str):
                                    raise SchemeException(
                                        ErrorObject(
                                            f"{op_name}: argument must be a string, got {arg!r}",
                                            NIL,
                                            kind="file",
                                        )
                                    )
                                canon_path = resolve_include_path(
                                    arg, base_dir=base_dir
                                )
                                with active_include_context(
                                    canon_path, caller_loc_file=caller_file
                                ):
                                    exprs = read_all_from_file(
                                        canon_path, fold_case=fold_case
                                    )
                                    for step in exprs:
                                        last_res = eval_expr(step, curr_env)
                            return last_res

                        # (define var val) or (define (name params...) body...)
                        if op_name == "define":
                            args = curr_expr.cdr
                            if not is_pair(args):
                                raise SyntaxError("define requires target and body")
                            target = car(args)
                            body_rest = cdr(args)

                            if isinstance(target, Symbol):
                                val_expr = car(body_rest) if is_pair(body_rest) else NIL
                                val = eval_expr(val_expr, curr_env)
                                curr_env.define(target, val)
                                return target

                            elif isinstance(target, Cons):
                                fn_name = car(target)
                                if not isinstance(fn_name, Symbol):
                                    raise SyntaxError(
                                        f"define function name must be a symbol, got {fn_name!r}"
                                    )
                                params_expr = cdr(target)
                                parsed_params, rest_p = _parse_params(params_expr)
                                proc = Procedure(
                                    params=parsed_params,
                                    body=to_py_list(body_rest),
                                    env=curr_env,
                                    is_macro=False,
                                    rest_param=rest_p,
                                    name=fn_name.name,
                                    shadows_sf=_check_shadows_sf(parsed_params, rest_p),
                                )
                                curr_env.define(fn_name, proc)
                                return fn_name
                            else:
                                raise SyntaxError(f"Invalid define target: {target!r}")

                        # (define-values formals expr)
                        if op_name == "define-values":
                            args = curr_expr.cdr
                            if not is_pair(args):
                                raise SyntaxError(
                                    "define-values requires formals and expression"
                                )
                            formals = car(args)
                            body_rest = cdr(args)
                            if not is_pair(body_rest):
                                raise SyntaxError(
                                    "define-values requires an expression"
                                )
                            val_expr = car(body_rest)
                            res = eval_expr(val_expr, curr_env)
                            if isinstance(res, Values):
                                res_vals: Tuple[Any, ...] = res.values
                            else:
                                res_vals = (res,)

                            if isinstance(formals, Symbol):
                                curr_env.define(formals, to_lisp_list(list(res_vals)))
                                return NIL

                            proper_vars: List[Symbol] = []
                            rest_var: Optional[Symbol] = None
                            curr_f: Any = formals
                            while is_pair(curr_f):
                                sym = car(curr_f)
                                if not isinstance(sym, Symbol):
                                    raise SyntaxError(
                                        f"define-values formal must be a symbol, got {sym!r}"
                                    )
                                proper_vars.append(sym)
                                curr_f = cdr(curr_f)
                            if isinstance(curr_f, Symbol):
                                rest_var = curr_f
                            elif not is_null(curr_f):
                                raise SyntaxError(
                                    f"define-values invalid formals: {formals!r}"
                                )

                            if rest_var is None:
                                if len(res_vals) != len(proper_vars):
                                    raise SchemeException(
                                        ErrorObject(
                                            f"define-values expected {len(proper_vars)} values, got {len(res_vals)}",
                                            NIL,
                                            kind="generic",
                                        )
                                    )
                                for sym, v in zip(proper_vars, res_vals):
                                    curr_env.define(sym, v)
                            else:
                                if len(res_vals) < len(proper_vars):
                                    raise SchemeException(
                                        ErrorObject(
                                            f"define-values expected at least {len(proper_vars)} "
                                            f"values, got {len(res_vals)}",
                                            NIL,
                                            kind="generic",
                                        )
                                    )
                                for sym, v in zip(
                                    proper_vars, res_vals[: len(proper_vars)]
                                ):
                                    curr_env.define(sym, v)
                                curr_env.define(
                                    rest_var,
                                    to_lisp_list(list(res_vals[len(proper_vars) :])),
                                )
                            return NIL

                        # (set! var val)
                        if op_name == "set!":
                            c_args = curr_expr.cdr
                            if (
                                type(c_args) is not Cons
                                or type(c_args.cdr) is not Cons
                                or c_args.cdr.cdr is not NIL
                            ):
                                raise SyntaxError(
                                    "set! requires exactly variable and value"
                                )
                            var_sym = c_args.car
                            if type(var_sym) is not Symbol:
                                raise SyntaxError(
                                    f"set! target must be a symbol, got {var_sym!r}"
                                )
                            val = eval_expr(c_args.cdr.car, curr_env)
                            curr_env.set(var_sym, val)
                            return val

                        # (lambda (params...) body...)
                        if op_name == "lambda":
                            args = curr_expr.cdr
                            if not is_pair(args):
                                raise SyntaxError("lambda requires parameters and body")
                            params_expr = car(args)
                            body_exprs = to_py_list(cdr(args))
                            parsed_params, rest_p = _parse_params(params_expr)
                            return Procedure(
                                params=parsed_params,
                                body=body_exprs,
                                env=curr_env,
                                is_macro=False,
                                rest_param=rest_p,
                                shadows_sf=_check_shadows_sf(parsed_params, rest_p),
                            )

                        # (define-macro (name params...) body...)
                        if op_name == "define-macro":
                            args = curr_expr.cdr
                            if not is_pair(args):
                                raise SyntaxError(
                                    "define-macro requires signature and body"
                                )
                            target = car(args)
                            body_rest = cdr(args)
                            if not isinstance(target, Cons):
                                raise SyntaxError(
                                    "define-macro syntax: (define-macro (name args...) body...)"
                                )
                            macro_name = car(target)
                            if not isinstance(macro_name, Symbol):
                                raise SyntaxError("macro name must be a symbol")
                            params_expr = cdr(target)
                            parsed_params, rest_p = _parse_params(params_expr)
                            macro_proc = Procedure(
                                params=parsed_params,
                                body=to_py_list(body_rest),
                                env=curr_env,
                                is_macro=True,
                                rest_param=rest_p,
                                name=macro_name.name,
                                shadows_sf=_check_shadows_sf(parsed_params, rest_p),
                            )
                            curr_env.define(macro_name, macro_proc)
                            return macro_name

                        # (define-syntax name transformer-spec)
                        if op_name == "define-syntax":
                            args = curr_expr.cdr
                            if not is_pair(args) or not is_pair(cdr(args)):
                                raise SyntaxError(
                                    "define-syntax requires name and transformer spec"
                                )
                            syn_name = car(args)
                            if not isinstance(syn_name, Symbol):
                                raise SyntaxError(
                                    "define-syntax target must be a symbol"
                                )
                            trans_spec = car(cdr(args))
                            transformer = _build_syntax_transformer(
                                syn_name.name, trans_spec, curr_env
                            )
                            curr_env.define(syn_name, transformer)
                            return syn_name

                        # (let-syntax ((name spec) ...) body ...)
                        # (letrec-syntax ((name spec) ...) body ...)
                        if op_name in ("let-syntax", "letrec-syntax"):
                            args = curr_expr.cdr
                            if not is_pair(args):
                                raise SyntaxError(
                                    f"{op_name} requires bindings and body"
                                )
                            bindings_raw = to_py_list(car(args))
                            body_exprs = to_py_list(cdr(args))
                            sub_env = Environment(curr_env)
                            spec_env = (
                                sub_env if op_name == "letrec-syntax" else curr_env
                            )
                            for b in bindings_raw:
                                b_list = to_py_list(b)
                                if len(b_list) != 2:
                                    raise SyntaxError(
                                        f"Invalid binding in {op_name}: {b!r}"
                                    )
                                b_name, b_spec = b_list[0], b_list[1]
                                if not isinstance(b_name, Symbol):
                                    raise SyntaxError(
                                        f"Binding target in {op_name} must be a symbol"
                                    )
                                trans = _build_syntax_transformer(
                                    b_name.name, b_spec, spec_env
                                )
                                sub_env.define(b_name, trans)
                            if not body_exprs:
                                return NIL
                            for step in body_exprs[:-1]:
                                eval_expr(step, sub_env)
                            curr_expr = body_exprs[-1]
                            curr_env = sub_env
                            continue

                        # (define-library (name ...) decl ...)
                        if op_name == "define-library":
                            from ilisp.module import execute_define_library

                            lib = execute_define_library(curr_expr)
                            return Symbol.intern(".".join(lib.name))

                        # (import import-set ...)
                        if op_name == "import":
                            from ilisp.module import execute_import

                            execute_import(curr_expr, curr_env)
                            return NIL

                        # 3. Primitive Dot Form: (. obj member-spec arg ...)
                        if op_name == ".":
                            args = curr_expr.cdr
                            if not is_pair(args) or not is_pair(cdr(args)):
                                raise SyntaxError(
                                    "'.' requires at least a target object and member specification"
                                )
                            target_obj = car(args)
                            spec = car(cdr(args))
                            rest_args = cdr(cdr(args))

                            if isinstance(spec, Symbol):
                                if spec.name.startswith("-") and len(spec.name) > 1:
                                    attr_name = spec.name[1:]
                                    if is_null(rest_args):
                                        curr_expr = Cons(
                                            Symbol.intern("py-get"),
                                            Cons(
                                                target_obj,
                                                Cons(
                                                    Cons(
                                                        Symbol.intern("quote"),
                                                        Cons(
                                                            Symbol.intern(attr_name),
                                                            NIL,
                                                        ),
                                                    ),
                                                    NIL,
                                                ),
                                            ),
                                        )
                                        continue
                                    elif is_pair(rest_args) and is_null(cdr(rest_args)):
                                        curr_expr = Cons(
                                            Symbol.intern("py-set!"),
                                            Cons(
                                                target_obj,
                                                Cons(
                                                    Cons(
                                                        Symbol.intern("quote"),
                                                        Cons(
                                                            Symbol.intern(attr_name),
                                                            NIL,
                                                        ),
                                                    ),
                                                    Cons(car(rest_args), NIL),
                                                ),
                                            ),
                                        )
                                        continue
                                    else:
                                        count = len(to_py_list(rest_args)) + 1
                                        raise SyntaxError(
                                            f"'.' attribute access expects 1 or 2 arguments, got {count}"
                                        )
                                else:
                                    curr_expr = Cons(
                                        Symbol.intern("py-call"),
                                        Cons(
                                            target_obj,
                                            Cons(
                                                Cons(
                                                    Symbol.intern("quote"),
                                                    Cons(Symbol.intern(spec.name), NIL),
                                                ),
                                                rest_args,
                                            ),
                                        ),
                                    )
                                    continue
                            elif is_pair(spec):
                                method_sym = car(spec)
                                if not isinstance(method_sym, Symbol):
                                    raise SyntaxError(
                                        f"Method in '.' member spec must be a symbol, got {method_sym!r}"
                                    )
                                inner_args = cdr(spec)
                                combined_args_list = to_py_list(
                                    inner_args
                                ) + to_py_list(rest_args)
                                curr_expr = Cons(
                                    Symbol.intern("py-call"),
                                    Cons(
                                        target_obj,
                                        Cons(
                                            Cons(
                                                Symbol.intern("quote"),
                                                Cons(
                                                    Symbol.intern(method_sym.name), NIL
                                                ),
                                            ),
                                            to_lisp_list(combined_args_list),
                                        ),
                                    ),
                                )
                                continue
                            else:
                                raise SyntaxError(
                                    f"Invalid member specification in '.' form: {spec!r}"
                                )

                # --- Clojure-style Python Interop Dot Shorthands ---
                op_name = op.name
                if op_name and op_name[0] == "." and op_name != "...":
                    if op_name.startswith(".-") and len(op_name) > 2:
                        attr_name = op_name[2:]
                        args = curr_expr.cdr
                        if not is_pair(args):
                            raise SyntaxError(f"{op_name} requires a target object")
                        target_obj = car(args)
                        rest = cdr(args)
                        if is_null(rest):
                            curr_expr = Cons(
                                Symbol.intern("py-get"),
                                Cons(
                                    target_obj,
                                    Cons(
                                        Cons(
                                            Symbol.intern("quote"),
                                            Cons(Symbol.intern(attr_name), NIL),
                                        ),
                                        NIL,
                                    ),
                                ),
                            )
                            continue
                        elif is_pair(rest) and is_null(cdr(rest)):
                            val_expr = car(rest)
                            curr_expr = Cons(
                                Symbol.intern("py-set!"),
                                Cons(
                                    target_obj,
                                    Cons(
                                        Cons(
                                            Symbol.intern("quote"),
                                            Cons(Symbol.intern(attr_name), NIL),
                                        ),
                                        Cons(val_expr, NIL),
                                    ),
                                ),
                            )
                            continue
                        else:
                            raise SyntaxError(
                                f"{op_name} expects 1 or 2 arguments, got {len(to_py_list(args))}"
                            )
                    elif len(op_name) > 1:
                        method_name = op_name[1:]
                        args = curr_expr.cdr
                        if not is_pair(args):
                            raise SyntaxError(f"{op_name} requires a target object")
                        target_obj = car(args)
                        call_args = cdr(args)
                        curr_expr = Cons(
                            Symbol.intern("py-call"),
                            Cons(
                                target_obj,
                                Cons(
                                    Cons(
                                        Symbol.intern("quote"),
                                        Cons(Symbol.intern(method_name), NIL),
                                    ),
                                    call_args,
                                ),
                            ),
                        )
                        continue

            # --- Function or Macro Application ---
            if type(op) is Symbol:
                if _current_step_hook is not None:
                    fn = eval_expr(op, curr_env)
                else:
                    cur_l: Optional[Environment] = curr_env
                    fn = _SENTINEL
                    while cur_l is not None:
                        val_l = cur_l.bindings.get(op, _SENTINEL)
                        if val_l is not _SENTINEL:
                            fn = val_l.get() if type(val_l) is Cell else val_l
                            break
                        cur_l = cur_l.parent
                    if fn is _SENTINEL:
                        if "." in op.name and not op.name.startswith("."):
                            val_d = _resolve_dotted_symbol(op.name, curr_env)
                            if val_d is not None:
                                fn = val_d
                            else:
                                raise NameError(f"Unbound variable: '{op.name}'")
                        else:
                            raise NameError(f"Unbound variable: '{op.name}'")
            else:
                fn = eval_expr(op, curr_env)

            fn_type = type(fn)

            if fn_type is Primitive:
                c1 = curr_expr.cdr
                if c1 is NIL:
                    return fn.fn()
                has_hook = _current_step_hook is not None
                can_fast_quote = not curr_env._has_shadowed_sf and not has_hook
                if type(c1) is Cons:
                    a1_expr = c1.car
                    ta1 = type(a1_expr)
                    if not has_hook and (ta1 in _SCALAR_TYPES or a1_expr is NIL):
                        a1 = a1_expr
                    elif not has_hook and ta1 is Symbol:
                        cur_a1: Optional[Environment] = curr_env
                        a1 = _SENTINEL
                        while cur_a1 is not None:
                            v1 = cur_a1.bindings.get(a1_expr, _SENTINEL)
                            if v1 is not _SENTINEL:
                                a1 = v1.get() if type(v1) is Cell else v1
                                break
                            cur_a1 = cur_a1.parent
                        if a1 is _SENTINEL:
                            a1 = eval_expr(a1_expr, curr_env)
                    elif (
                        can_fast_quote
                        and ta1 is Cons
                        and a1_expr.car is _QUOTE_SYM
                        and type(a1_expr.cdr) is Cons
                    ):
                        a1 = a1_expr.cdr.car
                    else:
                        a1 = eval_expr(a1_expr, curr_env)

                    c2 = c1.cdr
                    if c2 is NIL:
                        return fn.fn(a1)
                    if type(c2) is Cons:
                        a2_expr = c2.car
                        ta2 = type(a2_expr)
                        if not has_hook and (ta2 in _SCALAR_TYPES or a2_expr is NIL):
                            a2 = a2_expr
                        elif not has_hook and ta2 is Symbol:
                            cur_a2: Optional[Environment] = curr_env
                            a2 = _SENTINEL
                            while cur_a2 is not None:
                                v2 = cur_a2.bindings.get(a2_expr, _SENTINEL)
                                if v2 is not _SENTINEL:
                                    a2 = v2.get() if type(v2) is Cell else v2
                                    break
                                cur_a2 = cur_a2.parent
                            if a2 is _SENTINEL:
                                a2 = eval_expr(a2_expr, curr_env)
                        elif (
                            can_fast_quote
                            and ta2 is Cons
                            and a2_expr.car is _QUOTE_SYM
                            and type(a2_expr.cdr) is Cons
                        ):
                            a2 = a2_expr.cdr.car
                        else:
                            a2 = eval_expr(a2_expr, curr_env)
                        if c2.cdr is NIL:
                            return fn.fn(a1, a2)
                        eval_args = [a1, a2]
                        curr_arg = c2.cdr
                    else:
                        eval_args = [a1]
                        curr_arg = c2
                    while type(curr_arg) is Cons:
                        ae = curr_arg.car
                        tae = type(ae)
                        if not has_hook and (tae in _SCALAR_TYPES or ae is NIL):
                            eval_args.append(ae)
                        elif not has_hook and tae is Symbol:
                            cur_ae: Optional[Environment] = curr_env
                            ve = _SENTINEL
                            while cur_ae is not None:
                                v_got = cur_ae.bindings.get(ae, _SENTINEL)
                                if v_got is not _SENTINEL:
                                    ve = v_got.get() if type(v_got) is Cell else v_got
                                    break
                                cur_ae = cur_ae.parent
                            eval_args.append(
                                eval_expr(ae, curr_env) if ve is _SENTINEL else ve
                            )
                        else:
                            eval_args.append(eval_expr(ae, curr_env))
                        curr_arg = curr_arg.cdr
                    if curr_arg is not NIL:
                        while is_pair(curr_arg):
                            eval_args.append(eval_expr(car(curr_arg), curr_env))
                            curr_arg = cdr(curr_arg)
                        if not is_null(curr_arg):
                            raise TypeError(
                                f"Improper argument list: {curr_expr.cdr!r}"
                            )
                    return fn.fn(*eval_args)
                eval_args = to_py_list(c1) if is_pair(c1) else []
                return fn.fn(*eval_args)

            if fn_type is Procedure:
                if fn.is_macro:
                    unevaluated_args = to_py_list(curr_expr.cdr)
                    curr_expr = _apply_procedure(fn, unevaluated_args)
                    continue

                has_hook = _current_step_hook is not None
                eval_args = []
                curr_arg = curr_expr.cdr
                while type(curr_arg) is Cons:
                    ae = curr_arg.car
                    tae = type(ae)
                    if not has_hook and (tae in _SCALAR_TYPES or ae is NIL):
                        eval_args.append(ae)
                    elif not has_hook and tae is Symbol:
                        cur_ae2: Optional[Environment] = curr_env
                        ve2 = _SENTINEL
                        while cur_ae2 is not None:
                            v_got2 = cur_ae2.bindings.get(ae, _SENTINEL)
                            if v_got2 is not _SENTINEL:
                                ve2 = v_got2.get() if type(v_got2) is Cell else v_got2
                                break
                            cur_ae2 = cur_ae2.parent
                        eval_args.append(
                            eval_expr(ae, curr_env) if ve2 is _SENTINEL else ve2
                        )
                    else:
                        eval_args.append(eval_expr(ae, curr_env))
                    curr_arg = curr_arg.cdr
                if curr_arg is not NIL:
                    while is_pair(curr_arg):
                        eval_args.append(eval_expr(car(curr_arg), curr_env))
                        curr_arg = cdr(curr_arg)
                    if not is_null(curr_arg):
                        raise TypeError(f"Improper argument list: {curr_expr.cdr!r}")

                if Environment._mutation_hook is None:
                    return call_compiled_procedure(fn, eval_args)

                call_env = _bind_procedure_call(fn, eval_args)
                body = fn.body
                if not body:
                    return NIL
                for step in body[:-1]:
                    eval_expr(step, call_env)
                curr_expr = body[-1]
                curr_env = call_env
                continue

            if fn_type is SyntaxRulesTransformer:
                curr_expr = fn.transform(curr_expr, curr_env)
                continue

            if hasattr(fn, "transform"):
                curr_expr = fn.transform(curr_expr, curr_env)
                continue

            eval_args = []
            curr_arg = curr_expr.cdr
            while type(curr_arg) is Cons:
                eval_args.append(eval_expr(curr_arg.car, curr_env))
                curr_arg = curr_arg.cdr
            if curr_arg is not NIL:
                while is_pair(curr_arg):
                    eval_args.append(eval_expr(car(curr_arg), curr_env))
                    curr_arg = cdr(curr_arg)
                if not is_null(curr_arg):
                    raise TypeError(f"Improper argument list: {curr_expr.cdr!r}")

            if callable(fn):
                return fn(*eval_args)

            raise TypeError(f"Attempted to apply non-procedure: {fn!r}")

        # 2. Variable lookup
        elif expr_type is Symbol:
            cur_s: Optional[Environment] = curr_env
            while cur_s is not None:
                val_s = cur_s.bindings.get(curr_expr, _SENTINEL)
                if val_s is not _SENTINEL:
                    return val_s.get() if type(val_s) is Cell else val_s
                cur_s = cur_s.parent
            if "." in curr_expr.name and not curr_expr.name.startswith("."):
                val = _resolve_dotted_symbol(curr_expr.name, curr_env)
                if val is not None:
                    return val
            raise NameError(f"Unbound variable: '{curr_expr.name}'")

        # 3. NIL singleton
        elif curr_expr is NIL:
            return NIL

        # 4. Builtin scalar types
        elif expr_type in _SCALAR_TYPES:
            return curr_expr

        # 5. Other self-evaluating literals
        elif isinstance(curr_expr, _SELF_EVALUATING_TYPES):
            return curr_expr

        else:
            raise TypeError(f"Unknown AST node during evaluation: {curr_expr!r}")


def _parse_params(params_expr: Any) -> Tuple[List[Symbol], Optional[Symbol]]:
    """Parse Scheme parameter list including dotted rest arguments."""
    params: List[Symbol] = []
    rest_param: Optional[Symbol] = None

    if isinstance(params_expr, Symbol):
        # (lambda args body...)
        return ([], params_expr)

    curr = params_expr
    while isinstance(curr, Cons):
        elem = curr.car
        if not isinstance(elem, Symbol):
            raise SyntaxError(f"Parameter must be a symbol, got {elem!r}")
        params.append(elem)
        curr = curr.cdr

    if isinstance(curr, Symbol):
        # Dotted rest parameter: (lambda (a b . rest) body...)
        rest_param = curr
    elif curr is not NIL:
        raise SyntaxError(f"Invalid parameter list ending with {curr!r}")

    return (params, rest_param)


def _bind_procedure_call(proc: Procedure, args: List[Any]) -> Environment:
    """Create local call environment binding procedure parameters to arguments."""
    params = proc.params
    p_env: Environment = proc.env
    if proc.lex_frame is not None and proc._code is not None:
        psnap = proc._code.parent_visible
        if psnap:
            from ilisp.compiler_ir import _materialize_bridge_env

            p_env, _ = _materialize_bridge_env(proc._code, proc.lex_frame, psnap)
    shadows = p_env._has_shadowed_sf or proc.shadows_sf
    if isinstance(params, Symbol):
        new_bindings = {params: to_lisp_list(args)}
        return Environment(parent=p_env, bindings=new_bindings, has_shadowed_sf=shadows)

    n_params = len(params)
    n_args = len(args)
    if proc.rest_param is None:
        if n_params != n_args:
            raise TypeError(
                f"Procedure {proc.name or 'lambda'} expected {n_params} arguments, got {n_args}"
            )
        if n_params == 1:
            new_bindings = {params[0]: args[0]}
        elif n_params == 2:
            new_bindings = {params[0]: args[0], params[1]: args[1]}
        elif n_params == 3:
            new_bindings = {params[0]: args[0], params[1]: args[1], params[2]: args[2]}
        elif n_params == 0:
            new_bindings = {}
        else:
            new_bindings = dict(zip(params, args))
    else:
        if n_args < n_params:
            raise TypeError(
                f"Procedure {proc.name or 'lambda'} expected at least {n_params} arguments, got {n_args}"
            )
        new_bindings = dict(zip(params, args[:n_params]))
        new_bindings[proc.rest_param] = to_lisp_list(args[n_params:])

    return Environment(parent=p_env, bindings=new_bindings, has_shadowed_sf=shadows)


def _apply_procedure_treewalk(proc: Procedure, args: List[Any]) -> Any:
    """Directly evaluate a procedure or macro body via tree-walk evaluator."""
    call_env = _bind_procedure_call(proc, args)
    result: Any = NIL
    for expr in proc.body:
        result = eval_expr(expr, call_env)
    return result


def _apply_procedure(proc: Procedure, args: List[Any]) -> Any:
    """Invoke a procedure or macro using VM if compiled or tree-walk fallback."""
    if not proc.is_macro and Environment._mutation_hook is None:
        return call_compiled_procedure(proc, args)
    return _apply_procedure_treewalk(proc, args)


def eval_quasiquote(template: Any, env: Environment, depth: int = 1) -> Any:
    """Evaluate a quasiquote template supporting nested quasiquotes and splicing."""
    if not is_pair(template):
        if isinstance(template, Vector):
            expanded_elements: List[Any] = []
            for item in template.elements:
                if is_pair(item) and isinstance(car(item), Symbol):
                    if car(item).name == "unquote-splicing" and depth == 1:
                        spliced = eval_expr(car(cdr(item)), env)
                        if isinstance(spliced, (list, tuple, Vector)):
                            expanded_elements.extend(spliced)
                        else:
                            expanded_elements.extend(to_py_list(spliced))
                        continue
                expanded_elements.append(eval_quasiquote(item, env, depth))
            return Vector(expanded_elements)
        return template

    first = car(template)
    if isinstance(first, Symbol):
        if first.name == "quasiquote":
            inner = eval_quasiquote(car(cdr(template)), env, depth + 1)
            return Cons(Symbol.intern("quasiquote"), Cons(inner, NIL))
        if first.name == "unquote":
            if depth == 1:
                return eval_expr(car(cdr(template)), env)
            else:
                inner = eval_quasiquote(car(cdr(template)), env, depth - 1)
                return Cons(Symbol.intern("unquote"), Cons(inner, NIL))
        if first.name == "unquote-splicing":
            if depth == 1:
                raise SyntaxError("unquote-splicing not in list context")
            else:
                inner = eval_quasiquote(car(cdr(template)), env, depth - 1)
                return Cons(Symbol.intern("unquote-splicing"), Cons(inner, NIL))

    # General list: expand elements with splicing support
    result_elements: List[Any] = []
    curr = template
    while is_pair(curr):
        item = car(curr)
        if is_pair(item) and isinstance(car(item), Symbol):
            sym_name = car(item).name
            if sym_name == "unquote-splicing" and depth == 1:
                spliced_val = eval_expr(car(cdr(item)), env)
                if isinstance(spliced_val, (list, tuple, Vector)):
                    for s in spliced_val:
                        result_elements.append(s)
                else:
                    for s in to_py_list(spliced_val):
                        result_elements.append(s)
                curr = cdr(curr)
                continue
        result_elements.append(eval_quasiquote(item, env, depth))
        curr = cdr(curr)

    if not is_null(curr):
        tail_val = eval_quasiquote(curr, env, depth)
        res: Any = tail_val
        for elem in reversed(result_elements):
            res = Cons(elem, res)
        return res

    res = NIL
    for elem in reversed(result_elements):
        res = Cons(elem, res)
    return res
