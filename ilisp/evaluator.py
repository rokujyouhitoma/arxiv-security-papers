"""Tree-walk Evaluator and Trampoline TCO Engine for Kernel ILISP.

This module implements the core evaluation semantics of Kernel ILISP,
supporting standard special forms (quote, if, lambda, define, set!, begin, define-macro)
and tail-call optimization via trampolining.
"""

from __future__ import annotations

from typing import Any, List, Optional, Tuple

from ilisp.env import Environment
from ilisp.syntax import SyntaxRulesTransformer
from ilisp.types import (
    NIL,
    Bytevector,
    Char,
    Cons,
    Continuation,
    ErrorObject,
    MutableString,
    NilType,
    Parameter,
    Primitive,
    Procedure,
    Record,
    RecordType,
    SchemeException,
    Symbol,
    Vector,
    car,
    cdr,
    is_null,
    is_pair,
    to_lisp_list,
    to_py_list,
)


class TailCall:
    """Trampoline token holding an expression and environment to be evaluated in tail position."""

    __slots__ = ("expr", "env")

    def __init__(self, expr: Any, env: Environment) -> None:
        self.expr = expr
        self.env = env


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
        return SyntaxRulesTransformer(name, literals, rules, ellipsis=ellipsis_sym)
    return eval_expr(trans_spec, env)


def eval_expr(expr: Any, env: Environment) -> Any:
    """Evaluate an S-expression within an environment using a trampoline loop for TCO."""
    from ilisp.env import get_interaction_environment, set_interaction_environment

    if get_interaction_environment() is None:
        set_interaction_environment(env.root)

    curr_expr: Any = expr
    curr_env: Environment = env

    while True:
        # 1. Self-evaluating literals
        if (
            isinstance(
                curr_expr,
                (
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
                ),
            )
            or curr_expr is NIL
        ):
            return curr_expr

        # 2. Variable lookup
        if isinstance(curr_expr, Symbol):
            return curr_env.lookup(curr_expr)

        # 3. Pair / Form evaluation
        if isinstance(curr_expr, Cons):
            op = curr_expr.car

            # --- Special Forms ---
            if isinstance(op, Symbol):
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
                    args = to_py_list(curr_expr.cdr)
                    if len(args) < 2 or len(args) > 3:
                        raise SyntaxError(
                            f"if requires 2 or 3 expressions, got {len(args)}"
                        )
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

            # --- Function or Macro Application ---
            fn = eval_expr(op, curr_env)

            # 1. Macro call: pass unevaluated AST, expand, and re-evaluate
            if isinstance(fn, Procedure) and fn.is_macro:
                unevaluated_args = to_py_list(curr_expr.cdr)
                expanded_ast = _apply_procedure(fn, unevaluated_args)
                curr_expr = expanded_ast
                continue

            if isinstance(fn, SyntaxRulesTransformer):
                expanded_ast = fn.transform(curr_expr, curr_env)
                curr_expr = expanded_ast
                continue

            # 2. Procedure / Primitive call: evaluate arguments first
            raw_args = to_py_list(curr_expr.cdr)
            eval_args = [eval_expr(a, curr_env) for a in raw_args]

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
    new_bindings: dict[Symbol, Any] = {}
    params = proc.params
    if not isinstance(params, list):
        # Varargs single symbol: (lambda args ...)
        new_bindings[params] = to_lisp_list(args)
        return Environment(parent=proc.env, bindings=new_bindings)

    if proc.rest_param is None:
        if len(params) != len(args):
            raise TypeError(
                f"Procedure {proc.name or 'lambda'} expected {len(params)} arguments, got {len(args)}"
            )
        for p, a in zip(params, args):
            new_bindings[p] = a
    else:
        # Fixed params + rest param
        if len(args) < len(params):
            raise TypeError(
                f"Procedure {proc.name or 'lambda'} expected at least {len(params)} arguments, got {len(args)}"
            )
        for i, p in enumerate(params):
            new_bindings[p] = args[i]
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
