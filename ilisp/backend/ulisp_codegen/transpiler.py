"""Transpiler and AST Desugaring Pass for ULisp Native AOT Backend.

Translates high-level ILISP / Scheme S-expression ASTs into normalized, pure Scheme
core constructs accepted by the ULisp compiler engine (DSN-33).
Handles hygienic macro expansion, multi-arity arithmetic desugaring, and serialization.
"""

from __future__ import annotations

from typing import Any, List, Sequence, Union

from ilisp.reader import read_all
from ilisp.types import (
    NIL,
    Char,
    Cons,
    NilType,
    Symbol,
    Vector,
    car,
    cdr,
    is_null,
    is_pair,
    to_py_list,
)


class UlispCodegenError(Exception):
    """Base exception for ULisp compilation, transpilation, or ELF generation."""


class UlispTranspileError(UlispCodegenError):
    """Raised when transpilation to ULisp core syntax fails."""


class UlispTranspiler:
    """Normalizes and translates ILISP expressions into ULisp-compliant Scheme code."""

    def __init__(self, include_stdlib: bool = False) -> None:
        self.include_stdlib = include_stdlib
        self._var_counter = 0

    def _gensym(self, prefix: str = "_u") -> Symbol:
        self._var_counter += 1
        return Symbol(f"{prefix}_{self._var_counter}")

    def transpile(self, source_or_exprs: Union[str, Sequence[Any]]) -> str:
        """Transpile Scheme source text or datum sequence into ULisp Scheme code string."""
        if isinstance(source_or_exprs, str):
            exprs = read_all(source_or_exprs, filename="<ulisp-codegen>")
        else:
            exprs = list(source_or_exprs)

        desugared_forms: List[str] = []
        for expr in exprs:
            norm_expr = self.desugar_expr(expr)
            desugared_forms.append(self.to_scheme_string(norm_expr))

        return "\n\n".join(desugared_forms)

    def desugar_expr(self, expr: Any) -> Any:
        """Recursively desugar macros, multi-arity arithmetics, and specialized forms."""
        if not is_pair(expr):
            return expr

        op = car(expr)
        args = to_py_list(cdr(expr))

        # Check for symbol operator
        if isinstance(op, Symbol):
            op_name = op.name

            # Multi-arity arithmetic normalization: (+ a b c ...) -> (+ (+ a b) c)
            if op_name in {"+", "*"}:
                return self._desugar_associative_binop(op_name, args)

            if op_name == "-":
                return self._desugar_subtraction(args)

            # (define ...) forms
            if op_name == "define":
                if not args:
                    raise UlispTranspileError(
                        "Malformed define syntax: missing arguments"
                    )
                target = args[0]
                body = [self.desugar_expr(e) for e in args[1:]]
                if is_pair(target):
                    # (define (f x y) body...) -> (define f (lambda (x y) body...))
                    fn_name = car(target)
                    params = cdr(target)
                    lambda_expr = self._make_pair(
                        Symbol("lambda"),
                        self._make_pair(params, self._list_to_pairs(body)),
                    )
                    return self._make_pair(
                        Symbol("define"),
                        self._make_pair(fn_name, self._make_pair(lambda_expr, NIL)),
                    )
                else:
                    val = body[0] if body else NIL
                    return self._make_pair(
                        Symbol("define"),
                        self._make_pair(target, self._make_pair(val, NIL)),
                    )

            # (lambda (params...) body...)
            if op_name == "lambda":
                if not args:
                    raise UlispTranspileError(
                        "Malformed lambda syntax: missing parameter list"
                    )
                params = args[0]
                body = [self.desugar_expr(e) for e in args[1:]]
                return self._make_pair(
                    Symbol("lambda"), self._make_pair(params, self._list_to_pairs(body))
                )

            # (let ((k v)...) body...)
            if op_name in {"let", "let*", "letrec"}:
                if not args:
                    raise UlispTranspileError(f"Malformed {op_name} syntax")
                # Handle named let: (let name ((k v)...) body...)
                if isinstance(args[0], Symbol):
                    loop_name = args[0]
                    bindings = (
                        to_py_list(args[1])
                        if is_pair(args[1]) or is_null(args[1])
                        else []
                    )
                    body = [self.desugar_expr(e) for e in args[2:]]
                    # Named let can be passed directly to ULisp as it supports named let,
                    # but we desugar bindings and body expressions
                    norm_bindings = self._desugar_bindings(bindings)
                    return self._make_pair(
                        Symbol("let"),
                        self._make_pair(
                            loop_name,
                            self._make_pair(
                                self._list_to_pairs(norm_bindings),
                                self._list_to_pairs(body),
                            ),
                        ),
                    )
                else:
                    bindings = (
                        to_py_list(args[0])
                        if is_pair(args[0]) or is_null(args[0])
                        else []
                    )
                    body = [self.desugar_expr(e) for e in args[1:]]
                    norm_bindings = self._desugar_bindings(bindings)
                    return self._make_pair(
                        Symbol(op_name),
                        self._make_pair(
                            self._list_to_pairs(norm_bindings),
                            self._list_to_pairs(body),
                        ),
                    )

            # (if test then [else])
            if op_name == "if":
                norm_args = [self.desugar_expr(a) for a in args]
                return self._make_pair(Symbol("if"), self._list_to_pairs(norm_args))

            # (begin expr...)
            if op_name == "begin":
                norm_args = [self.desugar_expr(a) for a in args]
                return self._make_pair(Symbol("begin"), self._list_to_pairs(norm_args))

            # (cond (c1 e1...) ...)
            if op_name == "cond":
                clauses = []
                for clause in args:
                    if is_pair(clause):
                        c_list = to_py_list(clause)
                        clauses.append(
                            self._list_to_pairs([self.desugar_expr(x) for x in c_list])
                        )
                    else:
                        clauses.append(clause)
                return self._make_pair(Symbol("cond"), self._list_to_pairs(clauses))

            # (and e1 e2 ...) / (or e1 e2 ...)
            if op_name in {"and", "or"}:
                norm_args = [self.desugar_expr(a) for a in args]
                return self._make_pair(Symbol(op_name), self._list_to_pairs(norm_args))

            # (quote datum)
            if op_name == "quote":
                return expr

            # (set! var val)
            if op_name == "set!":
                if len(args) != 2:
                    raise UlispTranspileError(
                        f"Malformed set! syntax: expected 2 args, got {len(args)}"
                    )
                return self._make_pair(
                    Symbol("set!"),
                    self._make_pair(
                        args[0], self._make_pair(self.desugar_expr(args[1]), NIL)
                    ),
                )

        # Default general procedure application (f arg1 arg2 ...)
        norm_op = self.desugar_expr(op)
        norm_args = [self.desugar_expr(a) for a in args]
        return self._make_pair(norm_op, self._list_to_pairs(norm_args))

    def _desugar_bindings(self, bindings: List[Any]) -> List[Any]:
        res = []
        for b in bindings:
            if is_pair(b):
                var = car(b)
                val_list = to_py_list(cdr(b))
                val = self.desugar_expr(val_list[0]) if val_list else NIL
                res.append(self._make_pair(var, self._make_pair(val, NIL)))
            else:
                res.append(b)
        return res

    def _desugar_associative_binop(self, op: str, args: List[Any]) -> Any:
        identity = 0 if op == "+" else 1
        if not args:
            return identity
        if len(args) == 1:
            return self.desugar_expr(args[0])

        current = self.desugar_expr(args[0])
        for next_arg in args[1:]:
            current = self._make_pair(
                Symbol(op),
                self._make_pair(
                    current, self._make_pair(self.desugar_expr(next_arg), NIL)
                ),
            )
        return current

    def _desugar_subtraction(self, args: List[Any]) -> Any:
        if not args:
            raise UlispTranspileError("Malformed '-' operator with 0 arguments")
        if len(args) == 1:
            # (- x) -> (- 0 x)
            return self._make_pair(
                Symbol("-"),
                self._make_pair(0, self._make_pair(self.desugar_expr(args[0]), NIL)),
            )

        current = self.desugar_expr(args[0])
        for next_arg in args[1:]:
            current = self._make_pair(
                Symbol("-"),
                self._make_pair(
                    current, self._make_pair(self.desugar_expr(next_arg), NIL)
                ),
            )
        return current

    def _make_pair(self, car_val: Any, cdr_val: Any) -> Cons:
        return Cons(car_val, cdr_val)

    def _list_to_pairs(self, items: List[Any]) -> Any:
        res: Any = NIL
        for item in reversed(items):
            res = Cons(item, res)
        return res

    def to_scheme_string(self, expr: Any) -> str:
        """Convert any Scheme / ILISP datum to valid Scheme source text representation."""
        if expr is NIL or isinstance(expr, NilType):
            return "'()"
        if expr is True:
            return "#t"
        if expr is False:
            return "#f"
        if isinstance(expr, int):
            return str(expr)
        if isinstance(expr, Symbol):
            return expr.name
        if isinstance(expr, Char):
            if expr.val == " ":
                return "#\\space"
            if expr.val == "\n":
                return "#\\newline"
            if expr.val == "\t":
                return "#\\tab"
            return f"#\\{expr.val}"
        if isinstance(expr, str):
            escaped = (
                expr.replace("\\", "\\\\")
                .replace('"', '\\"')
                .replace("\n", "\\n")
                .replace("\t", "\\t")
            )
            return f'"{escaped}"'
        if isinstance(expr, Vector):
            elems = " ".join(self.to_scheme_string(e) for e in expr.elements)
            return f"#({elems})"
        if is_pair(expr):
            # Check for quote form: (quote x) -> 'x
            if (
                isinstance(car(expr), Symbol)
                and car(expr).name == "quote"
                and is_pair(cdr(expr))
                and is_null(cdr(cdr(expr)))
            ):
                inner = car(cdr(expr))
                return f"'{self._to_quoted_string(inner)}"

            parts: List[str] = []
            curr = expr
            while is_pair(curr):
                parts.append(self.to_scheme_string(car(curr)))
                curr = cdr(curr)
            if not is_null(curr) and curr is not NIL:
                parts.append(".")
                parts.append(self.to_scheme_string(curr))
            return "(" + " ".join(parts) + ")"

        return str(expr)

    def _to_quoted_string(self, expr: Any) -> str:
        if expr is NIL or isinstance(expr, NilType):
            return "()"
        if is_pair(expr):
            parts: List[str] = []
            curr = expr
            while is_pair(curr):
                parts.append(self._to_quoted_string(car(curr)))
                curr = cdr(curr)
            if not is_null(curr) and curr is not NIL:
                parts.append(".")
                parts.append(self._to_quoted_string(curr))
            return "(" + " ".join(parts) + ")"
        return self.to_scheme_string(expr)


def transpile_for_ulisp(source_or_exprs: Union[str, Sequence[Any]]) -> str:
    """Convenience functional API to transpile source or ASTs into ULisp Scheme code."""
    transpiler = UlispTranspiler()
    return transpiler.transpile(source_or_exprs)
