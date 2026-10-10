"""Tree-walk Evaluator and Trampoline TCO Engine for Kernel ILISP.

This module implements the core evaluation semantics of Kernel ILISP,
supporting standard special forms (quote, if, lambda, define, set!, begin, define-macro)
and tail-call optimization via trampolining.
"""

from __future__ import annotations

import importlib
from fractions import Fraction
from typing import Any, Callable, List, Optional, Tuple

from ilisp.env import Environment
from ilisp.reader import LispSyntaxError
from ilisp.syntax import SyntaxRulesTransformer
from ilisp.types import (
    NIL,
    Bytevector,
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

_SPECIAL_FORM_NAMES = {
    "syntax-error",
    "quote",
    "quasiquote",
    "if",
    "cond",
    "guard",
    "let",
    "let*",
    "letrec",
    "letrec*",
    "begin",
    "define",
    "define-values",
    "set!",
    "lambda",
    "define-macro",
    "define-syntax",
    "let-syntax",
    "letrec-syntax",
    "define-library",
    "import",
    "case-lambda",
    "delay",
    "delay-force",
    "parameterize",
    "do",
    "define-record-type",
    "let-values",
    "let*-values",
    "raise",
    "raise-continuable",
    "with-exception-handler",
    "macroexpand-1",
    "macroexpand",
    ".",
}
_SPECIAL_FORM_SYMBOLS = {Symbol.intern(s) for s in _SPECIAL_FORM_NAMES}

_interaction_environment_ready = False


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
            if type(op) is Symbol and (
                op in _SPECIAL_FORM_SYMBOLS or op.name.startswith(".")
            ):
                op_name = op.name

                # (syntax-error message irritants...)
                if op_name == "syntax-error":
                    args = to_py_list(curr_expr.cdr)
                    if not args:
                        err_obj = ErrorObject(
                            "syntax-error requires at least a message", NIL, kind="read"
                        )
                        raise SchemeException(err_obj)
                    msg_raw = args[0]
                    if isinstance(msg_raw, str):
                        msg_str = msg_raw
                    else:
                        eval_msg = eval_expr(msg_raw, curr_env)
                        msg_str = (
                            str(eval_msg) if not isinstance(eval_msg, str) else eval_msg
                        )
                    irritants_list = to_lisp_list(args[1:]) if len(args) > 1 else NIL
                    err_obj = ErrorObject(msg_str, irritants_list, kind="read")
                    raise SchemeException(err_obj)

                # (quote datum)
                if op_name == "quote":
                    args = curr_expr.cdr
                    if not is_pair(args):
                        raise SyntaxError("quote requires 1 argument")
                    return car(args)

                # (quasiquote template)
                if op_name == "quasiquote":
                    args = curr_expr.cdr
                    if not is_pair(args):
                        raise SyntaxError("quasiquote requires 1 argument")
                    return eval_quasiquote(car(args), curr_env)

                # (if test then [else])
                if op_name == "if":
                    cdr1 = curr_expr.cdr
                    if type(cdr1) is Cons:
                        cdr2 = cdr1.cdr
                        if type(cdr2) is Cons:
                            cdr3 = cdr2.cdr
                            if cdr3 is NIL:
                                test_val = eval_expr(cdr1.car, curr_env)
                                if test_val is not False:
                                    curr_expr = cdr2.car
                                    continue
                                return NIL
                            elif type(cdr3) is Cons and cdr3.cdr is NIL:
                                test_val = eval_expr(cdr1.car, curr_env)
                                if test_val is not False:
                                    curr_expr = cdr2.car
                                else:
                                    curr_expr = cdr3.car
                                continue

                    args = to_py_list(curr_expr.cdr)
                    if len(args) < 2 or len(args) > 3:
                        is_lex_bound = False
                        cur_e = curr_env
                        while cur_e.parent is not None:
                            if op in cur_e.bindings:
                                is_lex_bound = True
                                break
                            cur_e = cur_e.parent
                        if not is_lex_bound:
                            raise SyntaxError(
                                f"if requires 2 or 3 expressions, got {len(args)}"
                            )
                    else:
                        test_val = eval_expr(args[0], curr_env)
                        # In Scheme, only False is falsy
                        if test_val is not False:
                            curr_expr = args[1]
                            continue
                        else:
                            if len(args) == 3:
                                curr_expr = args[2]
                                continue
                            return NIL

                # (cond clause ...)
                if op_name == "cond":
                    clauses = to_py_list(curr_expr.cdr)
                    has_match = False
                    for clause in clauses:
                        if not is_pair(clause):
                            raise SyntaxError(f"cond: malformed clause: {clause!r}")
                        test_or_else = car(clause)
                        body_rest = cdr(clause)

                        if test_or_else == Symbol.intern("else"):
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
                            if is_pair(body_rest) and car(body_rest) == Symbol.intern(
                                "=>"
                            ):
                                is_shadowed = False
                                cur_e = curr_env
                                while cur_e.parent is not None:
                                    if Symbol.intern("=>") in cur_e.bindings:
                                        is_shadowed = True
                                        break
                                    cur_e = cur_e.parent

                                if not is_shadowed:
                                    recip_expr = car(cdr(body_rest))
                                    recip = eval_expr(recip_expr, curr_env)
                                    curr_expr = Cons(
                                        recip,
                                        Cons(
                                            Cons(
                                                Symbol.intern("quote"),
                                                Cons(t_val, NIL),
                                            ),
                                            NIL,
                                        ),
                                    )
                                    has_match = True
                                    break

                            body_exprs = to_py_list(body_rest)
                            if not body_exprs:
                                return t_val
                            for step in body_exprs[:-1]:
                                eval_expr(step, curr_env)
                            curr_expr = body_exprs[-1]
                            has_match = True
                            break

                    if has_match:
                        continue
                    return NIL

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
                            raise SyntaxError(f"guard: malformed clause: {clause!r}")
                        c_test = car(clause)
                        c_body = cdr(clause)

                        if c_test == Symbol.intern("else"):
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
                            if is_pair(c_body) and car(c_body) == Symbol.intern("=>"):
                                recip_expr = car(cdr(c_body))
                                recip = eval_expr(recip_expr, h_env)
                                if isinstance(recip, Procedure):
                                    return _apply_procedure(recip, [t_val])
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

                # (let bindings body ...) or (let name bindings body ...)
                if op_name == "let":
                    args = curr_expr.cdr
                    is_lex_bound = False
                    cur_e = curr_env
                    while cur_e.parent is not None:
                        if op in cur_e.bindings:
                            is_lex_bound = True
                            break
                        cur_e = cur_e.parent

                    if not is_pair(args):
                        if not is_lex_bound:
                            raise SyntaxError("let requires bindings and body")
                    else:
                        first_arg = car(args)
                        if isinstance(first_arg, Symbol) and not is_pair(cdr(args)):
                            if not is_lex_bound:
                                raise SyntaxError(
                                    "Named let requires bindings and body"
                                )
                        elif isinstance(first_arg, Symbol):
                            # Named let: (let name ((var val) ...) body ...)
                            let_name = first_arg
                            bindings = car(cdr(args))
                            body = cdr(cdr(args))
                            b_list = to_py_list(bindings)
                            vars_list = [car(b) for b in b_list]
                            vals_list = [
                                eval_expr(car(cdr(b)), curr_env) for b in b_list
                            ]
                            new_env = curr_env.extend()
                            proc = Procedure(
                                vars_list, to_py_list(body), new_env, name=let_name.name
                            )
                            new_env.define(let_name, proc)
                            return _apply_procedure(proc, vals_list)
                        else:
                            bindings = first_arg
                            body = cdr(args)
                            b_list = to_py_list(bindings)
                            eval_bindings = []
                            for b in b_list:
                                if not is_pair(b) or not is_pair(cdr(b)):
                                    raise SyntaxError(f"let: malformed binding: {b!r}")
                                eval_bindings.append(
                                    (car(b), eval_expr(car(cdr(b)), curr_env))
                                )
                            new_env = curr_env.extend()
                            for var_s, val_v in eval_bindings:
                                new_env.define(var_s, val_v)
                            body_exprs = to_py_list(body)
                            if not body_exprs:
                                return NIL
                            for step in body_exprs[:-1]:
                                eval_expr(step, new_env)
                            curr_expr = body_exprs[-1]
                            curr_env = new_env
                            continue

                # (let* bindings body ...)
                if op_name == "let*":
                    args = curr_expr.cdr
                    if not is_pair(args):
                        raise SyntaxError("let* requires bindings and body")
                    bindings = car(args)
                    body = cdr(args)
                    b_list = to_py_list(bindings)
                    new_env = curr_env.extend()
                    for b in b_list:
                        if not is_pair(b) or not is_pair(cdr(b)):
                            raise SyntaxError(f"let*: malformed binding: {b!r}")
                        val_e = eval_expr(car(cdr(b)), new_env)
                        new_env = new_env.extend()
                        new_env.define(car(b), val_e)
                    body_exprs = to_py_list(body)
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
                        raise SyntaxError(f"{op_name} requires bindings and body")
                    bindings = car(args)
                    body = cdr(args)
                    b_list = to_py_list(bindings)
                    new_env = curr_env.extend()
                    for b in b_list:
                        if not is_pair(b) or not is_pair(cdr(b)):
                            raise SyntaxError(f"{op_name}: malformed binding: {b!r}")
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

                # (begin expr ...)
                if op_name == "begin":
                    body_exprs = to_py_list(curr_expr.cdr)
                    if not body_exprs:
                        return NIL
                    for step in body_exprs[:-1]:
                        eval_expr(step, curr_env)
                    curr_expr = body_exprs[-1]
                    continue

                # (define var val) or (define (name params...) body...)
                if op_name == "define":
                    args = curr_expr.cdr
                    if not is_pair(args):
                        raise SyntaxError("define requires target and body")
                    target = car(args)
                    body_rest = cdr(args)

                    if isinstance(target, Symbol):
                        # (define var val)
                        val_expr = car(body_rest) if is_pair(body_rest) else NIL
                        val = eval_expr(val_expr, curr_env)
                        curr_env.define(target, val)
                        return target

                    elif isinstance(target, Cons):
                        # (define (name params...) body...)
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
                        raise SyntaxError("define-values requires an expression")
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
                        raise SyntaxError(f"define-values invalid formals: {formals!r}")

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
                                    f"define-values expected at least {len(proper_vars)} values, got {len(res_vals)}",
                                    NIL,
                                    kind="generic",
                                )
                            )
                        for sym, v in zip(proper_vars, res_vals[: len(proper_vars)]):
                            curr_env.define(sym, v)
                        curr_env.define(
                            rest_var,
                            to_lisp_list(list(res_vals[len(proper_vars) :])),
                        )
                    return NIL

                # (set! var val)
                if op_name == "set!":
                    args = to_py_list(curr_expr.cdr)
                    if len(args) != 2:
                        raise SyntaxError("set! requires exactly variable and value")
                    var_sym = args[0]
                    if not isinstance(var_sym, Symbol):
                        raise SyntaxError(
                            f"set! target must be a symbol, got {var_sym!r}"
                        )
                    val = eval_expr(args[1], curr_env)
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
                    )

                # (define-macro (name params...) body...)
                if op_name == "define-macro":
                    args = curr_expr.cdr
                    if not is_pair(args):
                        raise SyntaxError("define-macro requires signature and body")
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
                        raise SyntaxError("define-syntax target must be a symbol")
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
                        raise SyntaxError(f"{op_name} requires bindings and body")
                    bindings_raw = to_py_list(car(args))
                    body_exprs = to_py_list(cdr(args))
                    sub_env = Environment(curr_env)
                    spec_env = sub_env if op_name == "letrec-syntax" else curr_env
                    for b in bindings_raw:
                        b_list = to_py_list(b)
                        if len(b_list) != 2:
                            raise SyntaxError(f"Invalid binding in {op_name}: {b!r}")
                        b_name, b_spec = b_list[0], b_list[1]
                        if not isinstance(b_name, Symbol):
                            raise SyntaxError(
                                f"Binding target in {op_name} must be a symbol"
                            )
                        trans = _build_syntax_transformer(b_name.name, b_spec, spec_env)
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

                # --- Clojure-style Python Interop Special Forms ---
                # 1. Field / Property Accessor: (.-attr obj [val])
                if op_name.startswith(".-") and len(op_name) > 2:
                    attr_name = op_name[2:]
                    args = curr_expr.cdr
                    if not is_pair(args):
                        raise SyntaxError(f"{op_name} requires a target object")
                    target_obj = car(args)
                    rest = cdr(args)
                    if is_null(rest):
                        # Getter: (py-get target_obj 'attr)
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
                        # Setter: (py-set! target_obj 'attr val)
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

                # 2. Method Invocation Shorthand: (.method obj arg ...)
                if (
                    op_name.startswith(".")
                    and len(op_name) > 1
                    and op_name != "..."
                    and not op_name.startswith(".-")
                ):
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
                            # Property getter: (. obj -attr)
                            attr_name = spec.name[1:]
                            if is_null(rest_args):
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
                            elif is_pair(rest_args) and is_null(cdr(rest_args)):
                                # Property setter: (. obj -attr val)
                                curr_expr = Cons(
                                    Symbol.intern("py-set!"),
                                    Cons(
                                        target_obj,
                                        Cons(
                                            Cons(
                                                Symbol.intern("quote"),
                                                Cons(Symbol.intern(attr_name), NIL),
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
                            # Method call: (. obj method arg ...)
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
                        # List call spec: (. obj (method spec_arg ...) rest_args ...)
                        method_sym = car(spec)
                        if not isinstance(method_sym, Symbol):
                            raise SyntaxError(
                                f"Method in '.' member spec must be a symbol, got {method_sym!r}"
                            )
                        inner_args = cdr(spec)
                        combined_args_list = to_py_list(inner_args) + to_py_list(
                            rest_args
                        )
                        curr_expr = Cons(
                            Symbol.intern("py-call"),
                            Cons(
                                target_obj,
                                Cons(
                                    Cons(
                                        Symbol.intern("quote"),
                                        Cons(Symbol.intern(method_sym.name), NIL),
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

            # --- Function or Macro Application ---
            fn = eval_expr(op, curr_env)

            # 1. Macro call: pass unevaluated AST, expand, and re-evaluate
            if isinstance(fn, Procedure) and fn.is_macro:
                unevaluated_args = to_py_list(curr_expr.cdr)
                expanded_ast = _apply_procedure(fn, unevaluated_args)
                curr_expr = expanded_ast
                continue

            if isinstance(fn, SyntaxRulesTransformer) or hasattr(fn, "transform"):
                expanded_ast = fn.transform(curr_expr, curr_env)
                curr_expr = expanded_ast
                continue

            # 2. Procedure / Primitive call: evaluate arguments directly from Cons chain
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

            if isinstance(fn, Primitive):
                return fn(*eval_args)

            if isinstance(fn, Procedure):
                # Bind parameters
                call_env = _bind_procedure_call(fn, eval_args)
                body = fn.body
                if not body:
                    return NIL
                for step in body[:-1]:
                    eval_expr(step, call_env)
                # Tail call optimization: jump to last expression in new environment
                curr_expr = body[-1]
                curr_env = call_env
                continue

            if callable(fn):
                return fn(*eval_args)

            raise TypeError(f"Attempted to apply non-procedure: {fn!r}")

        # 2. Variable lookup
        elif expr_type is Symbol:
            try:
                return curr_env.lookup(curr_expr)
            except NameError:
                if "." in curr_expr.name and not curr_expr.name.startswith("."):
                    val = _resolve_dotted_symbol(curr_expr.name, curr_env)
                    if val is not None:
                        return val
                raise

        # 3. NIL singleton
        elif curr_expr is NIL:
            return NIL

        # 4. Builtin scalar types
        elif expr_type in (int, bool, str, float):
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
    if not isinstance(params, list):
        # Varargs single symbol: (lambda args ...)
        new_bindings = {params: to_lisp_list(args)}
        return Environment(parent=proc.env, bindings=new_bindings)

    if proc.rest_param is None:
        if len(params) != len(args):
            raise TypeError(
                f"Procedure {proc.name or 'lambda'} expected {len(params)} arguments, got {len(args)}"
            )
        new_bindings = dict(zip(params, args))
    else:
        # Fixed params + rest param
        if len(args) < len(params):
            raise TypeError(
                f"Procedure {proc.name or 'lambda'} expected at least {len(params)} arguments, got {len(args)}"
            )
        new_bindings = dict(zip(params, args[: len(params)]))
        rest_args = args[len(params) :]
        new_bindings[proc.rest_param] = to_lisp_list(rest_args)

    return Environment(parent=proc.env, bindings=new_bindings)


def _apply_procedure(proc: Procedure, args: List[Any]) -> Any:
    """Directly evaluate a procedure or macro body, returning the result."""
    call_env = _bind_procedure_call(proc, args)
    result: Any = NIL
    for expr in proc.body:
        result = eval_expr(expr, call_env)
    return result


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
