"""Python AST Code Generation Backend for ILISP.

Compiles Kernel ILISP S-expression ASTs directly into Python's standard ast.AST,
providing Self Tail-Call Optimization (Self-TCO), Cell boxing for mutable variables,
and native CPython execution speed.
"""

from __future__ import annotations

import ast
from typing import Any, Dict, List, Optional, Sequence, Set

from ilisp.env import Environment, make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.syntax import SyntaxRulesTransformer
from ilisp.types import (
    NIL,
    Bytevector,
    Char,
    Cons,
    NilType,
    Procedure,
    Symbol,
    Vector,
    car,
    cdr,
    is_null,
    is_pair,
    to_py_list,
)

# Reserved words in Python requiring safe mangling
PYTHON_KEYWORDS = {
    "False",
    "None",
    "True",
    "and",
    "as",
    "assert",
    "async",
    "await",
    "break",
    "class",
    "continue",
    "def",
    "del",
    "elif",
    "else",
    "except",
    "finally",
    "for",
    "from",
    "global",
    "if",
    "import",
    "in",
    "is",
    "lambda",
    "nonlocal",
    "not",
    "or",
    "pass",
    "raise",
    "return",
    "try",
    "while",
    "with",
    "yield",
}


def mangle_symbol(name: str) -> str:
    """Mangle Scheme identifier into a valid Python identifier."""
    if not name:
        return "_empty_"

    char_map = {
        "-": "_dash_",
        "?": "_p",
        "!": "_bang",
        "+": "_plus_",
        "*": "_star_",
        "/": "_slash_",
        "=": "_eq_",
        "<": "_lt_",
        ">": "_gt_",
        ":": "_colon_",
        ".": "_dot_",
        "@": "_at_",
    }

    res: List[str] = []
    for ch in name:
        if ch in char_map:
            res.append(char_map[ch])
        elif ch.isalnum() or ch == "_":
            res.append(ch)
        else:
            res.append(f"_u{ord(ch):04x}_")

    mangled = "".join(res)
    if mangled[0].isdigit():
        mangled = f"_num_{mangled}"
    if mangled in PYTHON_KEYWORDS:
        mangled = f"{mangled}_"
    return mangled


def analyze_mutated_vars(expr: Any) -> Set[str]:
    """Statically collect names of all variables targeted by (set! var val)."""
    mutated: Set[str] = set()

    def walk(node: Any) -> None:
        if isinstance(node, Cons):
            op = node.car
            if isinstance(op, Symbol) and op.name == "set!":
                args = to_py_list(node.cdr)
                if args and isinstance(args[0], Symbol):
                    mutated.add(args[0].name)
                for a in args[1:]:
                    walk(a)
            else:
                curr = node
                while isinstance(curr, Cons):
                    walk(curr.car)
                    curr = curr.cdr
                if curr is not NIL:
                    walk(curr)

    walk(expr)
    return mutated


class PythonASTCompiler:
    """Compiles S-expressions into Python standard ast.AST with emit-stack."""

    def __init__(
        self, env: Optional[Environment] = None, filename: str = "<ilisp>"
    ) -> None:
        self.env: Environment = env if env is not None else make_initial_env()
        self.filename: str = filename
        self._counter: int = 0
        self._stmt_stack: List[List[ast.stmt]] = []

    def _gensym(self, prefix: str = "_tmp") -> str:
        self._counter += 1
        return f"{prefix}_{self._counter}"

    def emit(self, stmt: ast.stmt) -> None:
        """Emit a statement into the current block statement list."""
        if not self._stmt_stack:
            raise RuntimeError("Cannot emit statement without an active block context")
        self._stmt_stack[-1].append(stmt)

    def compile(self, exprs: Sequence[Any]) -> ast.Module:
        """Compile a sequence of S-expressions into an ast.Module."""
        # 1. Macro-expand all expressions
        expanded_exprs = [self._expand_macros(e) for e in exprs]

        # 2. Analyze all mutated variables across expressions
        mutated_vars: Set[str] = set()
        for e in expanded_exprs:
            mutated_vars.update(analyze_mutated_vars(e))

        # 3. Setup module-level emit block
        top_stmts: List[ast.stmt] = []
        self._stmt_stack.append(top_stmts)

        # Standard runtime imports
        import_stmt = ast.ImportFrom(
            module="ilisp.types",
            names=[
                ast.alias(name="NIL", asname=None),
                ast.alias(name="Cons", asname=None),
                ast.alias(name="Symbol", asname=None),
                ast.alias(name="Cell", asname=None),
                ast.alias(name="SequenceView", asname=None),
                ast.alias(name="Vector", asname=None),
                ast.alias(name="Values", asname=None),
                ast.alias(name="Bytevector", asname=None),
                ast.alias(name="Char", asname=None),
                ast.alias(name="MutableString", asname=None),
                ast.alias(name="SchemeException", asname=None),
                ast.alias(name="Continuation", asname=None),
            ],
            level=0,
        )
        self.emit(import_stmt)

        last_expr_var = "__ilisp_result__"

        for expr in expanded_exprs:
            val_ast = self._compile_expr(expr, mutated_vars)
            if val_ast is not None:
                # Assign to result variable
                assign = ast.Assign(
                    targets=[ast.Name(id=last_expr_var, ctx=ast.Store())],
                    value=val_ast,
                )
                self.emit(assign)

        self._stmt_stack.pop()

        module = ast.Module(body=top_stmts, type_ignores=[])
        ast.fix_missing_locations(module)
        return module

    def _expand_macros(self, expr: Any) -> Any:
        """Recursively expand macros defined in the environment."""
        if not isinstance(expr, Cons):
            return expr

        op = expr.car
        if isinstance(op, Symbol) and op.name in (
            "define-macro",
            "define-syntax",
            "define-library",
            "import",
        ):
            eval_expr(expr, self.env)
            return expr

        if isinstance(op, Symbol):
            try:
                binding = self.env.lookup(op)
                if isinstance(binding, Procedure) and binding.is_macro:
                    from ilisp.evaluator import _apply_procedure

                    unevaluated_args = to_py_list(expr.cdr)
                    expanded = _apply_procedure(binding, unevaluated_args)
                    return self._expand_macros(expanded)
                if isinstance(binding, SyntaxRulesTransformer):
                    expanded = binding.transform(expr)
                    return self._expand_macros(expanded)
            except Exception:
                pass

        expanded_elements: List[Any] = []
        curr = expr
        while isinstance(curr, Cons):
            expanded_elements.append(self._expand_macros(curr.car))
            curr = curr.cdr

        result: Any = curr
        for elem in reversed(expanded_elements):
            result = Cons(elem, result, loc=expr.loc)
        return result

    def _compile_expr(self, expr: Any, mutated_vars: Set[str]) -> ast.expr:
        """Compile a Scheme expression into a Python ast.expr, emitting statements as needed."""
        # 1. Literals
        if isinstance(expr, bool):
            return ast.Constant(value=expr)
        if isinstance(expr, (int, float, str)):
            return ast.Constant(value=expr)
        if expr is NIL or isinstance(expr, NilType):
            return ast.Name(id="NIL", ctx=ast.Load())
        if isinstance(expr, Vector):
            elts = [self._compile_expr(elem, mutated_vars) for elem in expr.elements]
            return ast.Call(
                func=ast.Name(id="Vector", ctx=ast.Load()),
                args=[ast.List(elts=elts, ctx=ast.Load())],
                keywords=[],
            )
        if isinstance(expr, Bytevector):
            return ast.Call(
                func=ast.Name(id="Bytevector", ctx=ast.Load()),
                args=[ast.Constant(value=bytes(expr.data))],
                keywords=[],
            )
        if isinstance(expr, Char):
            return ast.Call(
                func=ast.Name(id="Char", ctx=ast.Load()),
                args=[ast.Constant(value=expr.val)],
                keywords=[],
            )

        # 2. Variable reference
        if isinstance(expr, Symbol):
            m_name = mangle_symbol(expr.name)
            if expr.name in mutated_vars:
                # Retrieve from Cell box
                return ast.Call(
                    func=ast.Attribute(
                        value=ast.Name(id=m_name, ctx=ast.Load()),
                        attr="get",
                        ctx=ast.Load(),
                    ),
                    args=[],
                    keywords=[],
                )
            return ast.Name(id=m_name, ctx=ast.Load())

        # 3. S-expression forms
        if isinstance(expr, Cons):
            op = expr.car

            if isinstance(op, Symbol):
                # (define var val) or (define (fn ...) ...)
                if op.name == "define":
                    args = expr.cdr
                    target = car(args)
                    body_rest = cdr(args)
                    if isinstance(target, Symbol):
                        var_name = mangle_symbol(target.name)
                        val_ast = self._compile_expr(car(body_rest), mutated_vars)
                        if target.name in mutated_vars:
                            cell_val = ast.Call(
                                func=ast.Name(id="Cell", ctx=ast.Load()),
                                args=[val_ast],
                                keywords=[],
                            )
                            assign = ast.Assign(
                                targets=[ast.Name(id=var_name, ctx=ast.Store())],
                                value=cell_val,
                            )
                        else:
                            assign = ast.Assign(
                                targets=[ast.Name(id=var_name, ctx=ast.Store())],
                                value=val_ast,
                            )
                        self.emit(assign)
                        return ast.Name(id=var_name, ctx=ast.Load())

                    elif isinstance(target, Cons):
                        fn_name_sym = car(target)
                        assert isinstance(fn_name_sym, Symbol)
                        fn_name = mangle_symbol(fn_name_sym.name)
                        params_expr = cdr(target)
                        fn_def = self._compile_function(
                            fn_name, params_expr, to_py_list(body_rest), mutated_vars
                        )
                        self.emit(fn_def)
                        return ast.Name(id=fn_name, ctx=ast.Load())

                # (define-macro ...) or (define-syntax ...) or (define-library ...) or (import ...)
                if op.name in (
                    "define-macro",
                    "define-syntax",
                    "define-library",
                    "import",
                ):
                    return ast.Name(id="NIL", ctx=ast.Load())

                # (set! var val)
                if op.name == "set!":
                    args = to_py_list(expr.cdr)
                    target_sym = args[0]
                    assert isinstance(target_sym, Symbol)
                    m_name = mangle_symbol(target_sym.name)
                    val_ast = self._compile_expr(args[1], mutated_vars)
                    return ast.Call(
                        func=ast.Attribute(
                            value=ast.Name(id=m_name, ctx=ast.Load()),
                            attr="set",
                            ctx=ast.Load(),
                        ),
                        args=[val_ast],
                        keywords=[],
                    )

                # (quote datum)
                if op.name == "quote":
                    datum = car(expr.cdr)
                    return self._compile_quote(datum)

                # (quasiquote template)
                if op.name == "quasiquote":
                    template = car(expr.cdr)
                    return self._compile_quasiquote(template, mutated_vars)

                # (if test then [else])
                if op.name == "if":
                    args = to_py_list(expr.cdr)
                    test_ast = self._compile_truthy_test(args[0], mutated_vars)
                    then_ast = self._compile_expr(args[1], mutated_vars)
                    else_ast = (
                        self._compile_expr(args[2], mutated_vars)
                        if len(args) == 3
                        else ast.Name(id="NIL", ctx=ast.Load())
                    )
                    return ast.IfExp(test=test_ast, body=then_ast, orelse=else_ast)

                # (begin expr ...)
                if op.name == "begin":
                    sub_exprs = to_py_list(expr.cdr)
                    last_ast: ast.expr = ast.Name(id="NIL", ctx=ast.Load())
                    for i, sub in enumerate(sub_exprs):
                        val = self._compile_expr(sub, mutated_vars)
                        if i == len(sub_exprs) - 1:
                            last_ast = val
                        else:
                            self.emit(ast.Expr(value=val))
                    return last_ast

                # (lambda (params...) body...)
                if op.name == "lambda":
                    args = expr.cdr
                    params_expr = car(args)
                    body_exprs = to_py_list(cdr(args))
                    fn_name = self._gensym("_closure")
                    fn_def = self._compile_function(
                        fn_name, params_expr, body_exprs, mutated_vars
                    )
                    self.emit(fn_def)
                    return ast.Name(id=fn_name, ctx=ast.Load())

            # Function Application: (fn arg1 arg2...)
            fn_ast = self._compile_expr(op, mutated_vars)
            raw_args = to_py_list(expr.cdr)
            eval_args = [self._compile_expr(a, mutated_vars) for a in raw_args]
            return ast.Call(func=fn_ast, args=eval_args, keywords=[])

        raise TypeError(f"Cannot compile AST node: {expr!r}")

    def _compile_function(
        self,
        name: str,
        params_expr: Any,
        body_exprs: List[Any],
        mutated_vars: Set[str],
    ) -> ast.FunctionDef:
        """Compile a Scheme procedure with Self-Tail Call Optimization (Self-TCO)."""
        param_names: List[str] = []
        curr = params_expr
        while isinstance(curr, Cons):
            elem = curr.car
            assert isinstance(elem, Symbol)
            param_names.append(elem.name)
            curr = curr.cdr

        mangled_params = [mangle_symbol(p) for p in param_names]
        args_ast = ast.arguments(
            posonlyargs=[],
            args=[ast.arg(arg=p) for p in mangled_params],
            kwonlyargs=[],
            kw_defaults=[],
            defaults=[],
        )

        fn_body: List[ast.stmt] = []
        self._stmt_stack.append(fn_body)

        # Box any parameter that is mutated by set!
        for p_name, m_name in zip(param_names, mangled_params):
            if p_name in mutated_vars:
                box_stmt = ast.Assign(
                    targets=[ast.Name(id=m_name, ctx=ast.Store())],
                    value=ast.Call(
                        func=ast.Name(id="Cell", ctx=ast.Load()),
                        args=[ast.Name(id=m_name, ctx=ast.Load())],
                        keywords=[],
                    ),
                )
                self.emit(box_stmt)

        # Check if the function contains self-tail calls
        has_self_tail = self._has_self_tail_call(
            name, body_exprs[-1] if body_exprs else None
        )

        if has_self_tail:
            loop_body = self._compile_tail_body(
                name, mangled_params, body_exprs, mutated_vars
            )
            while_loop = ast.While(
                test=ast.Constant(value=True), body=loop_body, orelse=[]
            )
            self.emit(while_loop)
        else:
            for step in body_exprs[:-1]:
                val = self._compile_expr(step, mutated_vars)
                self.emit(ast.Expr(value=val))
            if body_exprs:
                ret_val = self._compile_expr(body_exprs[-1], mutated_vars)
                self.emit(ast.Return(value=ret_val))
            else:
                self.emit(ast.Return(value=ast.Name(id="NIL", ctx=ast.Load())))

        self._stmt_stack.pop()

        return ast.FunctionDef(
            name=name,
            args=args_ast,
            body=fn_body,
            decorator_list=[],
        )

    def _has_self_tail_call(self, fn_name: str, tail_expr: Any) -> bool:
        """Check if tail expression contains a direct recursive call to fn_name."""
        if not isinstance(tail_expr, Cons):
            return False
        op = tail_expr.car
        if isinstance(op, Symbol) and mangle_symbol(op.name) == fn_name:
            return True
        if isinstance(op, Symbol) and op.name == "if":
            args = to_py_list(tail_expr.cdr)
            if len(args) == 3:
                return self._has_self_tail_call(
                    fn_name, args[1]
                ) or self._has_self_tail_call(fn_name, args[2])
            elif len(args) == 2:
                return self._has_self_tail_call(fn_name, args[1])
        if isinstance(op, Symbol) and op.name == "begin":
            sub_exprs = to_py_list(tail_expr.cdr)
            if sub_exprs:
                return self._has_self_tail_call(fn_name, sub_exprs[-1])
        return False

    def _compile_tail_body(
        self,
        fn_name: str,
        param_names: List[str],
        body_exprs: List[Any],
        mutated_vars: Set[str],
    ) -> List[ast.stmt]:
        """Compile function body in tail position for while True loop."""
        loop_stmts: List[ast.stmt] = []
        self._stmt_stack.append(loop_stmts)

        for step in body_exprs[:-1]:
            val = self._compile_expr(step, mutated_vars)
            self.emit(ast.Expr(value=val))
        if body_exprs:
            tail_stmts = self._compile_tail_expr(
                fn_name, param_names, body_exprs[-1], mutated_vars
            )
            for ts in tail_stmts:
                self.emit(ts)

        self._stmt_stack.pop()
        return loop_stmts

    def _compile_tail_expr(
        self,
        fn_name: str,
        param_names: List[str],
        expr: Any,
        mutated_vars: Set[str],
    ) -> List[ast.stmt]:
        """Compile a single expression in tail position."""
        if isinstance(expr, Cons):
            op = expr.car
            if isinstance(op, Symbol) and mangle_symbol(op.name) == fn_name:
                raw_args = to_py_list(expr.cdr)
                eval_args = [self._compile_expr(a, mutated_vars) for a in raw_args]
                target_names: List[ast.expr] = [
                    ast.Name(id=p, ctx=ast.Store()) for p in param_names
                ]
                if len(target_names) == 1:
                    assign = ast.Assign(targets=[target_names[0]], value=eval_args[0])
                else:
                    assign = ast.Assign(
                        targets=[ast.Tuple(elts=target_names, ctx=ast.Store())],
                        value=ast.Tuple(elts=eval_args, ctx=ast.Load()),
                    )
                return [assign, ast.Continue()]

            if isinstance(op, Symbol) and op.name == "if":
                args = to_py_list(expr.cdr)
                test_ast = self._compile_truthy_test(args[0], mutated_vars)
                then_stmts = self._compile_tail_expr(
                    fn_name, param_names, args[1], mutated_vars
                )
                else_stmts: List[ast.stmt] = []
                if len(args) == 3:
                    else_stmts = self._compile_tail_expr(
                        fn_name, param_names, args[2], mutated_vars
                    )
                else:
                    else_stmts = [ast.Return(value=ast.Name(id="NIL", ctx=ast.Load()))]
                return [ast.If(test=test_ast, body=then_stmts, orelse=else_stmts)]

            if isinstance(op, Symbol) and op.name == "begin":
                sub_exprs = to_py_list(expr.cdr)
                begin_stmts: List[ast.stmt] = []
                for s in sub_exprs[:-1]:
                    val = self._compile_expr(s, mutated_vars)
                    begin_stmts.append(ast.Expr(value=val))
                if sub_exprs:
                    begin_stmts.extend(
                        self._compile_tail_expr(
                            fn_name, param_names, sub_exprs[-1], mutated_vars
                        )
                    )
                return begin_stmts

        return [ast.Return(value=self._compile_expr(expr, mutated_vars))]

    def _compile_truthy_test(self, expr: Any, mutated_vars: Set[str]) -> ast.expr:
        """In Scheme, only #f is falsy."""
        if expr is False:
            return ast.Constant(value=False)
        if isinstance(expr, (int, float, str)) or expr is NIL or expr is True:
            return ast.Constant(value=True)

        val = self._compile_expr(expr, mutated_vars)
        if isinstance(val, ast.Constant):
            return ast.Constant(value=val.value is not False)

        return ast.Compare(
            left=val,
            ops=[ast.IsNot()],
            comparators=[ast.Constant(value=False)],
        )

    def _compile_quote(self, datum: Any) -> ast.expr:
        """Compile quoted datum into an ast.expr."""
        if isinstance(datum, (int, float, str, bool)):
            return ast.Constant(value=datum)
        if datum is NIL or isinstance(datum, NilType):
            return ast.Name(id="NIL", ctx=ast.Load())
        if isinstance(datum, Symbol):
            return ast.Call(
                func=ast.Attribute(
                    value=ast.Name(id="Symbol", ctx=ast.Load()),
                    attr="intern",
                    ctx=ast.Load(),
                ),
                args=[ast.Constant(value=datum.name)],
                keywords=[],
            )
        if isinstance(datum, Cons):
            car_ast = self._compile_quote(datum.car)
            cdr_ast = self._compile_quote(datum.cdr)
            return ast.Call(
                func=ast.Name(id="Cons", ctx=ast.Load()),
                args=[car_ast, cdr_ast],
                keywords=[],
            )
        if isinstance(datum, Vector):
            elts = [self._compile_quote(x) for x in datum.elements]
            return ast.Call(
                func=ast.Name(id="Vector", ctx=ast.Load()),
                args=[ast.List(elts=elts, ctx=ast.Load())],
                keywords=[],
            )
        return ast.Constant(value=datum)

    def _compile_quasiquote(
        self, template: Any, mutated_vars: Set[str], depth: int = 1
    ) -> ast.expr:
        """Compile a quasiquote template into an ast.expr."""
        if not is_pair(template):
            if isinstance(template, Vector):
                elts = [
                    self._compile_quasiquote(elem, mutated_vars, depth)
                    for elem in template.elements
                ]
                return ast.Call(
                    func=ast.Name(id="Vector", ctx=ast.Load()),
                    args=[ast.List(elts=elts, ctx=ast.Load())],
                    keywords=[],
                )
            if isinstance(template, Symbol):
                return self._compile_quote(template)
            return self._compile_expr(template, mutated_vars)

        first = car(template)
        if isinstance(first, Symbol):
            if first.name == "quasiquote":
                inner_ast = self._compile_quasiquote(
                    car(cdr(template)), mutated_vars, depth + 1
                )
                return ast.Call(
                    func=ast.Name(id="Cons", ctx=ast.Load()),
                    args=[
                        self._compile_quote(Symbol.intern("quasiquote")),
                        ast.Call(
                            func=ast.Name(id="Cons", ctx=ast.Load()),
                            args=[inner_ast, ast.Name(id="NIL", ctx=ast.Load())],
                            keywords=[],
                        ),
                    ],
                    keywords=[],
                )
            if first.name == "unquote":
                if depth == 1:
                    return self._compile_expr(car(cdr(template)), mutated_vars)
                else:
                    inner_ast = self._compile_quasiquote(
                        car(cdr(template)), mutated_vars, depth - 1
                    )
                    return ast.Call(
                        func=ast.Name(id="Cons", ctx=ast.Load()),
                        args=[
                            self._compile_quote(Symbol.intern("unquote")),
                            ast.Call(
                                func=ast.Name(id="Cons", ctx=ast.Load()),
                                args=[inner_ast, ast.Name(id="NIL", ctx=ast.Load())],
                                keywords=[],
                            ),
                        ],
                        keywords=[],
                    )

        # General list: desugar into append / cons calls
        chunks: List[ast.expr] = []
        normal_acc: List[ast.expr] = []

        curr = template
        while is_pair(curr):
            item = car(curr)
            if (
                is_pair(item)
                and isinstance(car(item), Symbol)
                and car(item).name == "unquote-splicing"
                and depth == 1
            ):
                if normal_acc:
                    chunk_call = self._build_cons_list_ast(normal_acc)
                    chunks.append(chunk_call)
                    normal_acc = []
                spliced_expr = self._compile_expr(car(cdr(item)), mutated_vars)
                chunks.append(spliced_expr)
                curr = cdr(curr)
                continue

            normal_acc.append(self._compile_quasiquote(item, mutated_vars, depth))
            curr = cdr(curr)

        if not is_null(curr):
            tail_ast = self._compile_quasiquote(curr, mutated_vars, depth)
            if normal_acc:
                chunks.append(self._build_cons_list_ast(normal_acc, tail=tail_ast))
            else:
                chunks.append(tail_ast)
        elif normal_acc:
            chunks.append(self._build_cons_list_ast(normal_acc))

        if not chunks:
            return ast.Name(id="NIL", ctx=ast.Load())

        if len(chunks) == 1:
            return chunks[0]

        m_append = mangle_symbol("append")
        return ast.Call(
            func=ast.Name(id=m_append, ctx=ast.Load()),
            args=chunks,
            keywords=[],
        )

    def _build_cons_list_ast(
        self, elements: List[ast.expr], tail: Optional[ast.expr] = None
    ) -> ast.expr:
        """Helper to build Cons(...) chain AST from list of element ASTs."""
        res: ast.expr = tail if tail is not None else ast.Name(id="NIL", ctx=ast.Load())
        for elem in reversed(elements):
            res = ast.Call(
                func=ast.Name(id="Cons", ctx=ast.Load()),
                args=[elem, res],
                keywords=[],
            )
        return res


def compile_ilisp(
    code_or_exprs: Any, env: Optional[Environment] = None, filename: str = "<ilisp>"
) -> Any:
    """Compile and execute ILISP code using Python AST Transpiler (Backend A)."""
    if env is None:
        env = make_initial_env()

    if isinstance(code_or_exprs, str):
        exprs = read_all(code_or_exprs, filename=filename)
    elif isinstance(code_or_exprs, list):
        exprs = code_or_exprs
    else:
        exprs = [code_or_exprs]

    compiler = PythonASTCompiler(env=env, filename=filename)
    mod_ast = compiler.compile(exprs)

    # Compile Python ast to bytecode
    code_obj = compile(mod_ast, filename=filename, mode="exec")

    # Prepare execution namespace preloaded with primitive bindings
    namespace: Dict[str, Any] = {}
    curr: Optional[Environment] = env
    while curr is not None:
        for sym, val in curr.bindings.items():
            m_name = mangle_symbol(sym.name)
            if m_name not in namespace:
                namespace[m_name] = val
        curr = curr.parent

    # Execute bytecode in the namespace
    exec(code_obj, namespace)  # nosec

    # Extract final result
    result = namespace.get("__ilisp_result__", NIL)

    # Sync any new top-level variables back to the Scheme environment
    for sym_name, val in namespace.items():
        if not sym_name.startswith("__") and not sym_name.startswith("_"):
            env.define(Symbol.intern(sym_name), val)

    return result
