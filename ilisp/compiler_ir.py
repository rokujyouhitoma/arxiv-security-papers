"""Lazy AST-to-Bytecode Precompiler and Lexical-Slot Stack VM for Kernel ILISP.

This module compiles Scheme Procedures lazily on first invocation into flat
bytecode CodeObjects operating over array-backed LexFrames and direct
GlobalCell references, eliminating runtime S-expression re-parsing and
dictionary environment allocation while preserving full R7RS semantics.
"""

from __future__ import annotations

from fractions import Fraction
from typing import TYPE_CHECKING, Any, Dict, List, Optional, Tuple, Union

from ilisp.syntax import SyntaxRulesTransformer
from ilisp.types import (
    NIL,
    UNBOUND,
    Bytevector,
    Char,
    Cons,
    GlobalCell,
    LexFrame,
    MutableString,
    Parameter,
    Primitive,
    Procedure,
    Record,
    RecordType,
    SequenceView,
    Symbol,
    Vector,
    to_lisp_list,
)

if TYPE_CHECKING:
    from ilisp.env import Environment

# ---------------------------------------------------------------------------
# Bytecode Opcodes (Integer Constants for Fast Tuple Dispatch)
# ---------------------------------------------------------------------------
OP_CONST = 0
OP_LOAD_LOCAL0 = 1
OP_LOAD_LOCAL = 2
OP_STORE_LOCAL0 = 3
OP_STORE_LOCAL = 4
OP_POP_STORE_LOCAL0 = 5
OP_POP_STORE_LOCAL = 6
OP_LOAD_GLOBAL = 7
OP_STORE_GLOBAL = 8
OP_LOAD_OUTER_ENV = 9
OP_STORE_OUTER_ENV = 10
OP_POP = 11
OP_JUMP = 12
OP_JUMP_IF_FALSE = 13
OP_JUMP_IF_TRUE = 14
OP_JUMP_IF_FALSE_KEEP = 15
OP_JUMP_IF_TRUE_KEEP = 16
OP_PUSH_FRAME = 17
OP_POP_FRAME = 18
OP_MAKE_CLOSURE = 19
OP_CALL = 20
OP_TAIL_CALL = 21
OP_RETURN = 22
OP_CASE_MATCH = 23
OP_QUASIQUOTE = 24
OP_EVAL_FALLBACK = 25

# Guarded Inline Superinstructions
OP_CAR = 30
OP_CDR = 31
OP_CADR = 32
OP_CADDR = 33
OP_NULL_P = 34
OP_PAIR_P = 35
OP_NOT = 36
OP_CONS = 37
OP_EQ_P = 38
OP_ADD2 = 39
OP_SUB2 = 40
OP_MUL2 = 41
OP_NUM_EQ2 = 42
OP_LT2 = 43
OP_LE2 = 44
OP_GT2 = 45
OP_GE2 = 46
OP_LIST = 47
OP_VECTOR_REF = 48
OP_LENGTH = 49
OP_ASSQ = 50
OP_MEMQ = 51
OP_CADDDR = 52
OP_SYMBOL_P = 53
OP_STRING_P = 54
OP_REVERSE = 55
OP_MODULO = 56
OP_STRING_EQ = 57
OP_CHAR_EQ = 58
OP_STRING_REF = 59
OP_SET_CAR = 60
OP_SET_CDR = 61

_SUPER_1ARG = {
    "car": OP_CAR,
    "cdr": OP_CDR,
    "cadr": OP_CADR,
    "caddr": OP_CADDR,
    "cadddr": OP_CADDDR,
    "null?": OP_NULL_P,
    "pair?": OP_PAIR_P,
    "not": OP_NOT,
    "length": OP_LENGTH,
    "symbol?": OP_SYMBOL_P,
    "string?": OP_STRING_P,
    "reverse": OP_REVERSE,
}

_SUPER_2ARG = {
    "cons": OP_CONS,
    "eq?": OP_EQ_P,
    "+": OP_ADD2,
    "-": OP_SUB2,
    "*": OP_MUL2,
    "=": OP_NUM_EQ2,
    "<": OP_LT2,
    "<=": OP_LE2,
    ">": OP_GT2,
    ">=": OP_GE2,
    "vector-ref": OP_VECTOR_REF,
    "assq": OP_ASSQ,
    "memq": OP_MEMQ,
    "modulo": OP_MODULO,
    "string=?": OP_STRING_EQ,
    "char=?": OP_CHAR_EQ,
    "string-ref": OP_STRING_REF,
    "set-car!": OP_SET_CAR,
    "set-cdr!": OP_SET_CDR,
}

_FALLBACK_FORMS: frozenset[str] = frozenset(
    {
        "guard",
        "parameterize",
        "let-syntax",
        "letrec-syntax",
        "define-syntax",
        "define-macro",
        "define-values",
        "let-values",
        "let*-values",
        "case-lambda",
        "delay",
        "delay-force",
        "cond-expand",
        "define-record-type",
        "define-library",
        "import",
        "include",
        "include-ci",
        "raise",
        "raise-continuable",
        "with-exception-handler",
        "syntax-error",
        "macroexpand",
        "macroexpand-1",
        ".",
    }
)

_SYM_IF = Symbol.intern("if")
_SYM_QUOTE = Symbol.intern("quote")
_SYM_BEGIN = Symbol.intern("begin")
_SYM_LET = Symbol.intern("let")
_SYM_LET_STAR = Symbol.intern("let*")
_SYM_LETREC = Symbol.intern("letrec")
_SYM_LETREC_STAR = Symbol.intern("letrec*")
_SYM_LAMBDA = Symbol.intern("lambda")
_SYM_COND = Symbol.intern("cond")
_SYM_CASE = Symbol.intern("case")
_SYM_AND = Symbol.intern("and")
_SYM_OR = Symbol.intern("or")
_SYM_WHEN = Symbol.intern("when")
_SYM_UNLESS = Symbol.intern("unless")
_SYM_DO = Symbol.intern("do")
_SYM_DEFINE = Symbol.intern("define")
_SYM_SET = Symbol.intern("set!")
_SYM_QUASIQUOTE = Symbol.intern("quasiquote")
_SYM_ELSE = Symbol.intern("else")
_SYM_ARROW = Symbol.intern("=>")
_SYM_LIST = Symbol.intern("list")

_SELF_EVAL_TUPLE = (
    int,
    float,
    complex,
    str,
    bool,
    Bytevector,
    Char,
    MutableString,
    Parameter,
    RecordType,
    Record,
    Vector,
)


class _SelfTailCallBailout(Exception):
    """Internal control flow used when a Named let proves non-tail-loopable."""


class CodeObject:
    """Immutable compiled bytecode chunk for a Scheme lambda/procedure."""

    __slots__ = (
        "ops",
        "arg1",
        "arg2",
        "n_params",
        "rest_index",
        "n_locals",
        "param_syms",
        "rest_sym",
        "body_ast",
        "name",
        "shadows_sf",
        "root_env",
        "outer_env",
        "uses_macros",
        "macro_epoch",
        "base_slot_names",
        "parent_scope",
        "parent_visible",
    )

    def __init__(
        self,
        ops: Tuple[int, ...],
        arg1: Tuple[Any, ...],
        arg2: Tuple[Any, ...],
        n_params: int,
        rest_index: int,
        n_locals: int,
        param_syms: Union[Symbol, List[Symbol]],
        rest_sym: Optional[Symbol],
        body_ast: List[Any],
        name: Optional[str],
        shadows_sf: bool,
        root_env: Environment,
        outer_env: Optional[Environment],
        uses_macros: bool,
        macro_epoch: int,
        base_slot_names: Tuple[Optional[Symbol], ...],
        parent_scope: Optional[_CompileScope] = None,
        parent_visible: Tuple[Tuple[int, int, Symbol], ...] = (),
    ) -> None:
        self.ops = ops
        self.arg1 = arg1
        self.arg2 = arg2
        self.n_params = n_params
        self.rest_index = rest_index
        self.n_locals = n_locals
        self.param_syms = param_syms
        self.rest_sym = rest_sym
        self.body_ast = body_ast
        self.name = name
        self.shadows_sf = shadows_sf
        self.root_env = root_env
        self.outer_env = outer_env
        self.uses_macros = uses_macros
        self.macro_epoch = macro_epoch
        self.base_slot_names = base_slot_names
        self.parent_scope = parent_scope
        self.parent_visible = parent_visible

    def lookup_in_lex_frame(self, frame: LexFrame, sym: Symbol) -> Tuple[bool, Any]:
        """Resolve a symbol in this CodeObject's active LexFrame chain."""
        names = self.base_slot_names
        # Reverse search prefers inner shadow bindings
        for idx in range(len(names) - 1, -1, -1):
            if names[idx] is sym and idx < len(frame.slots):
                return (True, frame.slots[idx])
        return (False, None)


class _CompileScope:
    """Compile-time lexical variable slot map nested by runtime LexFrame."""

    __slots__ = (
        "parent",
        "is_frame_root",
        "bindings",
        "named_let_loops",
        "frame_slot_count",
        "frame_slot_names",
    )

    def __init__(
        self,
        parent: Optional[_CompileScope] = None,
        is_frame_root: bool = False,
    ) -> None:
        self.parent = parent
        self.is_frame_root = is_frame_root
        self.bindings: Dict[Symbol, int] = {}
        self.named_let_loops: Dict[Symbol, Tuple[int, List[int]]] = {}
        if is_frame_root or parent is None:
            self.frame_slot_count: List[int] = [0]
            self.frame_slot_names: List[Optional[Symbol]] = []
        else:
            self.frame_slot_count = parent.frame_slot_count
            self.frame_slot_names = parent.frame_slot_names

    def alloc_slot(self, sym: Symbol) -> int:
        idx = self.frame_slot_count[0]
        self.frame_slot_count[0] = idx + 1
        self.frame_slot_names.append(sym)
        self.bindings[sym] = idx
        return idx

    def resolve(self, sym: Symbol) -> Optional[Tuple[int, int]]:
        """Return (frame_depth, slot_index) if `sym` is bound lexically."""
        cur: Optional[_CompileScope] = self
        depth = 0
        while cur is not None:
            slot = cur.bindings.get(sym)
            if slot is not None:
                return (depth, slot)
            if cur.is_frame_root:
                depth += 1
            cur = cur.parent
        return None

    def resolve_named_loop(self, sym: Symbol) -> Optional[Tuple[int, List[int]]]:
        """Return (loop_ip, var_slots) if `sym` is a tail-only local loop."""
        cur: Optional[_CompileScope] = self
        while cur is not None:
            if sym in cur.bindings:
                return None
            loop_info = cur.named_let_loops.get(sym)
            if loop_info is not None:
                return loop_info
            if cur.is_frame_root:
                # Escaped into nested lambda -> cannot jump across LexFrames
                return None
            cur = cur.parent
        return None

    def snapshot_visible(self) -> Tuple[Tuple[int, int, Symbol], ...]:
        """Return outer-to-inner (depth, slot, sym) entries for bridge envs."""
        chain: List[_CompileScope] = []
        cur: Optional[_CompileScope] = self
        while cur is not None:
            chain.append(cur)
            cur = cur.parent

        # Compute runtime depth of each _CompileScope relative to `self`
        frame_depths: Dict[int, int] = {}
        d = 0
        c2: Optional[_CompileScope] = self
        while c2 is not None:
            frame_depths[id(c2)] = d
            if c2.is_frame_root:
                d += 1
            c2 = c2.parent

        out: List[Tuple[int, int, Symbol]] = []
        for sc in reversed(chain):
            sc_d = frame_depths[id(sc)]
            for sym, slot in sc.bindings.items():
                out.append((sc_d, slot, sym))
        return tuple(out)


def _is_in_outer_env(sym: Symbol, outer_env: Optional[Environment]) -> bool:
    """Return True if `sym` is bound in an interpreted non-root outer_env."""
    if outer_env is None:
        return False
    cur: Optional[Environment] = outer_env
    while cur is not None and cur.parent is not None:
        if sym in cur.bindings:
            return True
        cur = cur.parent
    return False


def _expr_has_lambda_or_fallback(expr: Any) -> bool:
    """Conservative check whether `expr` contains `lambda` or dynamic forms."""
    stack: List[Any] = [expr]
    while stack:
        node = stack.pop()
        if type(node) is not Cons:
            continue
        head = node.car
        if type(head) is Symbol:
            hname = head.name
            if hname == "quote":
                continue
            if hname in (
                "lambda",
                "guard",
                "parameterize",
                "let-syntax",
                "letrec-syntax",
                "case-lambda",
                "delay",
                "delay-force",
                "quasiquote",
            ):
                return True
        cur: Any = node
        while type(cur) is Cons:
            stack.append(cur.car)
            cur = cur.cdr
    return False


def _proper_list_elems(lst: Any) -> Optional[List[Any]]:
    """Convert proper Cons list to Python list, returning None if improper."""
    res: List[Any] = []
    cur = lst
    while type(cur) is Cons:
        res.append(cur.car)
        cur = cur.cdr
    if cur is NIL:
        return res
    return None


def _flatten_leading_defines(body_exprs: List[Any]) -> List[Any]:
    """Flatten leading `(begin (define ...) ...)` blocks per R7RS 5.3.2."""
    out: List[Any] = []
    idx = 0
    n = len(body_exprs)
    while idx < n:
        e = body_exprs[idx]
        if (
            type(e) is Cons
            and e.car is _SYM_BEGIN
            and _proper_list_elems(e.cdr) is not None
        ):
            inner = _proper_list_elems(e.cdr)
            assert inner is not None
            if inner and _is_internal_define(inner[0]):
                out.extend(_flatten_leading_defines(inner))
                idx += 1
                continue
        break
    if idx > 0:
        out.extend(body_exprs[idx:])
        return out
    return body_exprs


def _is_internal_define(expr: Any) -> bool:
    """Return True if `expr` is `(define var val)` or `(define (fn ...) ...)`."""
    if type(expr) is not Cons or expr.car is not _SYM_DEFINE:
        return False
    args = _proper_list_elems(expr.cdr)
    if args is None or not args:
        return False
    target = args[0]
    if type(target) is Symbol:
        return len(args) == 2
    if type(target) is Cons and type(target.car) is Symbol:
        return len(args) >= 2
    return False


class _FunctionCompiler:
    """Compiles one Scheme Procedure body into a flat bytecode CodeObject."""

    def __init__(
        self,
        params: Union[Symbol, List[Symbol]],
        rest_param: Optional[Symbol],
        body_ast: List[Any],
        name: Optional[str],
        shadows_sf: bool,
        root_env: Environment,
        outer_env: Optional[Environment],
        parent_scope: Optional[_CompileScope],
    ) -> None:
        self.params = params
        self.rest_param = rest_param
        self.body_ast = body_ast
        self.name = name
        self.shadows_sf = shadows_sf
        self.root_env = root_env
        self.outer_env = outer_env
        self.ops: List[int] = []
        self.arg1: List[Any] = []
        self.arg2: List[Any] = []
        self.uses_macros = False
        self.macro_epoch = root_env._macro_epoch
        self.scope = _CompileScope(parent=parent_scope, is_frame_root=True)
        # Track active named-let loop vars to reject non-tail loop usage
        self.active_loop_syms: set[Symbol] = set()

    def _emit(self, op: int, a1: Any = None, a2: Any = None) -> int:
        ip = len(self.ops)
        self.ops.append(op)
        self.arg1.append(a1)
        self.arg2.append(a2)
        return ip

    def _patch(self, ip: int, target_ip: int) -> None:
        self.arg1[ip] = target_ip

    def _emit_var_get(self, sym: Symbol, scope: _CompileScope) -> None:
        if sym in self.active_loop_syms and scope.resolve_named_loop(sym) is not None:
            raise _SelfTailCallBailout()
        loc = scope.resolve(sym)
        if loc is not None:
            depth, slot = loc
            if depth == 0:
                self._emit(OP_LOAD_LOCAL0, slot)
            else:
                self._emit(OP_LOAD_LOCAL, depth, slot)
            return
        if _is_in_outer_env(sym, self.outer_env):
            self._emit(OP_LOAD_OUTER_ENV, sym)
            return
        cell = self.root_env.get_global_cell(sym)
        self._emit(OP_LOAD_GLOBAL, cell)

    def _emit_var_set(self, sym: Symbol, scope: _CompileScope) -> None:
        """Emit value-preserving set (top of stack remains `val`)."""
        if sym in self.active_loop_syms and scope.resolve_named_loop(sym) is not None:
            raise _SelfTailCallBailout()
        loc = scope.resolve(sym)
        if loc is not None:
            depth, slot = loc
            if depth == 0:
                self._emit(OP_STORE_LOCAL0, slot)
            else:
                self._emit(OP_STORE_LOCAL, depth, slot)
            return
        if _is_in_outer_env(sym, self.outer_env):
            self._emit(OP_STORE_OUTER_ENV, sym)
            return
        cell = self.root_env.get_global_cell(sym)
        self._emit(OP_STORE_GLOBAL, cell)

    def _is_bound_lexically(self, sym: Symbol, scope: _CompileScope) -> bool:
        if scope.resolve(sym) is not None:
            return True
        return self.outer_env is not None and _is_in_outer_env(sym, self.outer_env)

    def compile(self) -> CodeObject:
        # Allocate slots for parameters first
        if isinstance(self.params, Symbol):
            self.scope.alloc_slot(self.params)
            n_params = 0
            rest_index = 0
        else:
            for p in self.params:
                self.scope.alloc_slot(p)
            n_params = len(self.params)
            if self.rest_param is not None:
                rest_index = self.scope.alloc_slot(self.rest_param)
            else:
                rest_index = -1

        if not self.body_ast:
            self._emit(OP_CONST, NIL)
        else:
            self._compile_body(self.body_ast, self.scope, is_tail=True)
        self._emit(OP_RETURN)

        pscope = self.scope.parent
        return CodeObject(
            ops=tuple(self.ops),
            arg1=tuple(self.arg1),
            arg2=tuple(self.arg2),
            n_params=n_params,
            rest_index=rest_index,
            n_locals=self.scope.frame_slot_count[0],
            param_syms=self.params,
            rest_sym=self.rest_param,
            body_ast=self.body_ast,
            name=self.name,
            shadows_sf=self.shadows_sf,
            root_env=self.root_env,
            outer_env=self.outer_env,
            uses_macros=self.uses_macros,
            macro_epoch=self.macro_epoch,
            base_slot_names=tuple(self.scope.frame_slot_names),
            parent_scope=pscope,
            parent_visible=pscope.snapshot_visible() if pscope is not None else (),
        )

    def _compile_body(
        self, exprs: List[Any], scope: _CompileScope, is_tail: bool
    ) -> None:
        if not exprs:
            self._emit(OP_CONST, NIL)
            return

        flat = _flatten_leading_defines(exprs)
        def_count = 0
        while def_count < len(flat) and _is_internal_define(flat[def_count]):
            def_count += 1

        if def_count > 0:
            body_scope = _CompileScope(parent=scope, is_frame_root=False)
            def_targets: List[Tuple[int, Any]] = []
            for idx in range(def_count):
                d_expr = flat[idx]
                args = _proper_list_elems(d_expr.cdr)
                assert args is not None
                target = args[0]
                if type(target) is Symbol:
                    slot = body_scope.alloc_slot(target)
                    def_targets.append((slot, args[1]))
                else:
                    assert type(target) is Cons and type(target.car) is Symbol
                    fn_sym = target.car
                    slot = body_scope.alloc_slot(fn_sym)
                    lambda_node = Cons(_SYM_LAMBDA, Cons(target.cdr, d_expr.cdr.cdr))
                    def_targets.append((slot, lambda_node))

            for slot, val_expr in def_targets:
                self._compile_expr(val_expr, body_scope, is_tail=False)
                self._emit(OP_POP_STORE_LOCAL0, slot)

            rem = flat[def_count:]
            if not rem:
                self._emit(OP_CONST, NIL)
                return
            for e in rem[:-1]:
                self._compile_expr(e, body_scope, is_tail=False)
                self._emit(OP_POP)
            self._compile_expr(rem[-1], body_scope, is_tail=is_tail)
            return

        for e in exprs[:-1]:
            self._compile_expr(e, scope, is_tail=False)
            self._emit(OP_POP)
        self._compile_expr(exprs[-1], scope, is_tail=is_tail)

    def _compile_expr(self, expr: Any, scope: _CompileScope, is_tail: bool) -> None:
        et = type(expr)
        if et is Cons:
            op = expr.car
            if type(op) is Symbol:
                oname = op.name
                is_bound = self._is_bound_lexically(op, scope)

                if oname == "quote" and not is_bound:
                    if type(expr.cdr) is Cons and expr.cdr.cdr is NIL:
                        self._emit(OP_CONST, expr.cdr.car)
                        return
                    self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                    return

                if oname == "if":
                    args = _proper_list_elems(expr.cdr)
                    if args is not None and len(args) in (2, 3):
                        self._compile_expr(args[0], scope, is_tail=False)
                        jfalse = self._emit(OP_JUMP_IF_FALSE, 0)
                        self._compile_expr(args[1], scope, is_tail=is_tail)
                        jend = self._emit(OP_JUMP, 0)
                        self._patch(jfalse, len(self.ops))
                        if len(args) == 3:
                            self._compile_expr(args[2], scope, is_tail=is_tail)
                        else:
                            self._emit(OP_CONST, NIL)
                        self._patch(jend, len(self.ops))
                        return
                    if not is_bound:
                        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                        return

                if oname == "let":
                    if self._try_compile_let(expr, scope, is_tail):
                        return
                    if not is_bound:
                        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                        return

                if not is_bound:
                    if oname == "begin":
                        args = _proper_list_elems(expr.cdr)
                        if args is None:
                            self._emit(
                                OP_EVAL_FALLBACK,
                                expr,
                                scope.snapshot_visible(),
                            )
                            return
                        if not args:
                            self._emit(OP_CONST, NIL)
                            return
                        self._compile_body(args, scope, is_tail=is_tail)
                        return

                    if oname == "let*":
                        if self._compile_let_star(expr, scope, is_tail):
                            return
                        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                        return

                    if oname in ("letrec", "letrec*"):
                        if self._compile_letrec(expr, scope, is_tail):
                            return
                        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                        return

                    if oname == "cond":
                        if self._compile_cond(expr, scope, is_tail):
                            return
                        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                        return

                    if oname == "case":
                        if self._compile_case(expr, scope, is_tail):
                            return
                        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                        return

                    if oname == "and":
                        args = _proper_list_elems(expr.cdr)
                        if args is None:
                            self._emit(
                                OP_EVAL_FALLBACK,
                                expr,
                                scope.snapshot_visible(),
                            )
                            return
                        if not args:
                            self._emit(OP_CONST, True)
                            return
                        if len(args) == 1:
                            self._compile_expr(args[0], scope, is_tail=is_tail)
                            return
                        j_falses: List[int] = []
                        for sub in args[:-1]:
                            self._compile_expr(sub, scope, is_tail=False)
                            j_falses.append(self._emit(OP_JUMP_IF_FALSE_KEEP, 0))
                        self._compile_expr(args[-1], scope, is_tail=is_tail)
                        end_ip = len(self.ops)
                        for jf in j_falses:
                            self._patch(jf, end_ip)
                        return

                    if oname == "or":
                        args = _proper_list_elems(expr.cdr)
                        if args is None:
                            self._emit(
                                OP_EVAL_FALLBACK,
                                expr,
                                scope.snapshot_visible(),
                            )
                            return
                        if not args:
                            self._emit(OP_CONST, False)
                            return
                        if len(args) == 1:
                            self._compile_expr(args[0], scope, is_tail=is_tail)
                            return
                        j_trues: List[int] = []
                        for sub in args[:-1]:
                            self._compile_expr(sub, scope, is_tail=False)
                            j_trues.append(self._emit(OP_JUMP_IF_TRUE_KEEP, 0))
                        self._compile_expr(args[-1], scope, is_tail=is_tail)
                        end_ip = len(self.ops)
                        for jt in j_trues:
                            self._patch(jt, end_ip)
                        return

                    if oname == "when":
                        args = _proper_list_elems(expr.cdr)
                        if args is None or len(args) < 1:
                            self._emit(
                                OP_EVAL_FALLBACK,
                                expr,
                                scope.snapshot_visible(),
                            )
                            return
                        self._compile_expr(args[0], scope, is_tail=False)
                        jf = self._emit(OP_JUMP_IF_FALSE, 0)
                        self._compile_body(args[1:], scope, is_tail=is_tail)
                        jend = self._emit(OP_JUMP, 0)
                        self._patch(jf, len(self.ops))
                        self._emit(OP_CONST, NIL)
                        self._patch(jend, len(self.ops))
                        return

                    if oname == "unless":
                        args = _proper_list_elems(expr.cdr)
                        if args is None or len(args) < 1:
                            self._emit(
                                OP_EVAL_FALLBACK,
                                expr,
                                scope.snapshot_visible(),
                            )
                            return
                        self._compile_expr(args[0], scope, is_tail=False)
                        jt = self._emit(OP_JUMP_IF_TRUE, 0)
                        self._compile_body(args[1:], scope, is_tail=is_tail)
                        jend = self._emit(OP_JUMP, 0)
                        self._patch(jt, len(self.ops))
                        self._emit(OP_CONST, NIL)
                        self._patch(jend, len(self.ops))
                        return

                    if oname == "do":
                        if self._compile_do(expr, scope, is_tail):
                            return
                        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                        return

                    if oname == "set!":
                        args = _proper_list_elems(expr.cdr)
                        if (
                            args is not None
                            and len(args) == 2
                            and type(args[0]) is Symbol
                        ):
                            self._compile_expr(args[1], scope, is_tail=False)
                            self._emit_var_set(args[0], scope)
                            return
                        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                        return

                    if oname == "lambda":
                        if self._compile_lambda(expr, scope):
                            return
                        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                        return

                    if oname == "quasiquote":
                        args = _proper_list_elems(expr.cdr)
                        if args is not None and len(args) == 1:
                            self._emit(OP_QUASIQUOTE, args[0], scope.snapshot_visible())
                            return
                        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                        return

                    if oname in _FALLBACK_FORMS or oname == "define":
                        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                        return

                    # Check compile-time macro expansion from root_env
                    root_val = self.root_env.bindings.get(op)
                    if type(root_val) is Procedure and root_val.is_macro:
                        m_args = _proper_list_elems(expr.cdr)
                        if m_args is not None:
                            try:
                                from ilisp.evaluator import _apply_procedure

                                expanded = _apply_procedure(root_val, m_args)
                                self.uses_macros = True
                                self._compile_expr(expanded, scope, is_tail=is_tail)
                                return
                            except Exception:
                                self._emit(
                                    OP_EVAL_FALLBACK,
                                    expr,
                                    scope.snapshot_visible(),
                                )
                                return
                    elif type(root_val) is SyntaxRulesTransformer:
                        lits_shadowed = any(
                            self._is_bound_lexically(Symbol.intern(lit), scope)
                            for lit in root_val.literals
                        )
                        if not lits_shadowed:
                            try:
                                expanded = root_val.transform(expr, self.root_env)
                                self.uses_macros = True
                                self._compile_expr(expanded, scope, is_tail=is_tail)
                                return
                            except Exception:
                                self._emit(
                                    OP_EVAL_FALLBACK,
                                    expr,
                                    scope.snapshot_visible(),
                                )
                                return

                # Tail self-loop Named let call check!
                loop_info = scope.resolve_named_loop(op)
                if loop_info is not None:
                    arg_exprs = _proper_list_elems(expr.cdr)
                    loop_ip, loop_slots = loop_info
                    if (
                        is_tail
                        and arg_exprs is not None
                        and len(arg_exprs) == len(loop_slots)
                    ):
                        for ae in arg_exprs:
                            self._compile_expr(ae, scope, is_tail=False)
                        for slot in reversed(loop_slots):
                            self._emit(OP_POP_STORE_LOCAL0, slot)
                        self._emit(OP_JUMP, loop_ip)
                        return
                    raise _SelfTailCallBailout()

                # Try guarded inline superinstruction when op is global builtin
                if not is_bound:
                    arg_exprs = _proper_list_elems(expr.cdr)
                    if (
                        arg_exprs is not None
                        and self._try_emit_superinstruction_in_scope(
                            op, arg_exprs, scope
                        )
                    ):
                        return

            # General procedure / primitive call
            arg_exprs = _proper_list_elems(expr.cdr)
            if arg_exprs is None:
                self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                return

            self._compile_expr(op, scope, is_tail=False)
            for ae in arg_exprs:
                self._compile_expr(ae, scope, is_tail=False)
            self._emit(OP_TAIL_CALL if is_tail else OP_CALL, len(arg_exprs))
            return

        if et is Symbol:
            if "." in expr.name and not expr.name.startswith("."):
                # Could be lexical/global or dotted Python attribute access
                loc = scope.resolve(expr)
                if loc is not None:
                    depth, slot = loc
                    self._emit(
                        OP_LOAD_LOCAL0 if depth == 0 else OP_LOAD_LOCAL,
                        slot if depth == 0 else depth,
                        None if depth == 0 else slot,
                    )
                    return
                if self.outer_env is not None and _is_in_outer_env(
                    expr, self.outer_env
                ):
                    self._emit(OP_LOAD_OUTER_ENV, expr)
                    return
                root_prefix = Symbol.intern(expr.name.split(".", 1)[0])
                if self._is_bound_lexically(root_prefix, scope):
                    self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())
                    return
                cell = self.root_env.get_global_cell(expr)
                self._emit(OP_LOAD_GLOBAL, cell)
                return
            self._emit_var_get(expr, scope)
            return

        if expr is NIL:
            self._emit(OP_CONST, NIL)
            return

        if (
            et is int
            or et is bool
            or et is str
            or et is float
            or isinstance(expr, _SELF_EVAL_TUPLE)
        ):
            self._emit(OP_CONST, expr)
            return

        self._emit(OP_EVAL_FALLBACK, expr, scope.snapshot_visible())

    def _try_emit_superinstruction_in_scope(
        self, op_sym: Symbol, arg_exprs: List[Any], scope: _CompileScope
    ) -> bool:
        oname = op_sym.name
        n_args = len(arg_exprs)
        if n_args == 1:
            op_code = _SUPER_1ARG.get(oname)
            if op_code is None:
                if oname != "list":
                    return False
                cell = self.root_env.get_global_cell(op_sym)
                expected = cell.value
                if type(expected) is not Primitive:
                    return False
                self._compile_expr(arg_exprs[0], scope, is_tail=False)
                self._emit(OP_LIST, (cell, expected), 1)
                return True
            cell = self.root_env.get_global_cell(op_sym)
            expected = cell.value
            if type(expected) is not Primitive:
                return False
            self._compile_expr(arg_exprs[0], scope, is_tail=False)
            self._emit(op_code, cell, expected)
            return True

        if n_args == 2:
            op_code = _SUPER_2ARG.get(oname)
            if op_code is None:
                if oname != "list":
                    return False
                cell = self.root_env.get_global_cell(op_sym)
                expected = cell.value
                if type(expected) is not Primitive:
                    return False
                self._compile_expr(arg_exprs[0], scope, is_tail=False)
                self._compile_expr(arg_exprs[1], scope, is_tail=False)
                self._emit(OP_LIST, (cell, expected), 2)
                return True
            cell = self.root_env.get_global_cell(op_sym)
            expected = cell.value
            if type(expected) is not Primitive:
                return False
            self._compile_expr(arg_exprs[0], scope, is_tail=False)
            self._compile_expr(arg_exprs[1], scope, is_tail=False)
            self._emit(op_code, cell, expected)
            return True

        if oname == "list" and n_args <= 8:
            cell = self.root_env.get_global_cell(op_sym)
            expected = cell.value
            if type(expected) is not Primitive:
                return False
            for ae in arg_exprs:
                self._compile_expr(ae, scope, is_tail=False)
            self._emit(OP_LIST, (cell, expected), n_args)
            return True

        return False

    def _try_compile_let(self, expr: Cons, scope: _CompileScope, is_tail: bool) -> bool:
        args = _proper_list_elems(expr.cdr)
        if args is None or not args:
            return False
        first = args[0]

        if type(first) is Symbol:
            # Named let: (let name ((v init) ...) body ...)
            if len(args) < 3:
                return False
            loop_sym = first
            binds_raw = _proper_list_elems(args[1])
            if binds_raw is None:
                return False
            var_syms: List[Symbol] = []
            init_exprs: List[Any] = []
            for b in binds_raw:
                bl = _proper_list_elems(b)
                if bl is None or len(bl) != 2 or type(bl[0]) is not Symbol:
                    return False
                var_syms.append(bl[0])
                init_exprs.append(bl[1])
            body_exprs = args[2:]

            # Attempt flat in-place self-tail loop optimization when in tail position
            no_closures = not any(_expr_has_lambda_or_fallback(be) for be in body_exprs)
            if is_tail and no_closures:
                saved_ops_len = len(self.ops)
                saved_count = self.scope.frame_slot_count[0]
                saved_names_len = len(self.scope.frame_slot_names)
                try:
                    loop_scope = _CompileScope(parent=scope, is_frame_root=False)
                    loop_slots: List[int] = []
                    for ie in init_exprs:
                        self._compile_expr(ie, scope, is_tail=False)
                    for vs in var_syms:
                        loop_slots.append(loop_scope.alloc_slot(vs))
                    for slot in reversed(loop_slots):
                        self._emit(OP_POP_STORE_LOCAL0, slot)
                    loop_ip = len(self.ops)
                    loop_scope.named_let_loops[loop_sym] = (loop_ip, loop_slots)
                    self.active_loop_syms.add(loop_sym)
                    try:
                        self._compile_body(body_exprs, loop_scope, is_tail=True)
                    finally:
                        self.active_loop_syms.discard(loop_sym)
                    return True
                except _SelfTailCallBailout:
                    # Rollback partial emissions & slots; compile as letrec closure
                    del self.ops[saved_ops_len:]
                    del self.arg1[saved_ops_len:]
                    del self.arg2[saved_ops_len:]
                    self.scope.frame_slot_count[0] = saved_count
                    del self.scope.frame_slot_names[saved_names_len:]

            # General Named let via local letrec closure
            rec_scope = _CompileScope(parent=scope, is_frame_root=False)
            loop_slot = rec_scope.alloc_slot(loop_sym)
            from ilisp.evaluator import _check_shadows_sf

            child_comp = _FunctionCompiler(
                params=var_syms,
                rest_param=None,
                body_ast=body_exprs,
                name=loop_sym.name,
                shadows_sf=_check_shadows_sf(var_syms, None),
                root_env=self.root_env,
                outer_env=self.outer_env,
                parent_scope=rec_scope,
            )
            child_code = child_comp.compile()
            if child_comp.uses_macros:
                self.uses_macros = True
            self._emit(OP_MAKE_CLOSURE, child_code)
            self._emit(OP_POP_STORE_LOCAL0, loop_slot)
            # Now evaluate inits in outer scope and invoke loop closure
            self._emit(OP_LOAD_LOCAL0, loop_slot)
            for ie in init_exprs:
                self._compile_expr(ie, scope, is_tail=False)
            self._emit(OP_TAIL_CALL if is_tail else OP_CALL, len(init_exprs))
            return True

        # Ordinary let: (let ((v init) ...) body ...)
        if len(args) < 2:
            return False
        binds_raw = _proper_list_elems(first)
        if binds_raw is None:
            return False
        var_syms = []
        init_exprs = []
        for b in binds_raw:
            bl = _proper_list_elems(b)
            if bl is None or len(bl) != 2 or type(bl[0]) is not Symbol:
                return False
            var_syms.append(bl[0])
            init_exprs.append(bl[1])
        for ie in init_exprs:
            self._compile_expr(ie, scope, is_tail=False)
        let_scope = _CompileScope(parent=scope, is_frame_root=False)
        slots = [let_scope.alloc_slot(vs) for vs in var_syms]
        for slot in reversed(slots):
            self._emit(OP_POP_STORE_LOCAL0, slot)
        self._compile_body(args[1:], let_scope, is_tail=is_tail)
        return True

    def _compile_let_star(
        self, expr: Cons, scope: _CompileScope, is_tail: bool
    ) -> bool:
        args = _proper_list_elems(expr.cdr)
        if args is None or len(args) < 2:
            return False
        binds_raw = _proper_list_elems(args[0])
        if binds_raw is None:
            return False
        cur_scope = _CompileScope(parent=scope, is_frame_root=False)
        for b in binds_raw:
            bl = _proper_list_elems(b)
            if bl is None or len(bl) != 2 or type(bl[0]) is not Symbol:
                return False
            vs, ie = bl[0], bl[1]
            self._compile_expr(ie, cur_scope, is_tail=False)
            if vs in cur_scope.bindings:
                cur_scope = _CompileScope(parent=cur_scope, is_frame_root=False)
            slot = cur_scope.alloc_slot(vs)
            self._emit(OP_POP_STORE_LOCAL0, slot)
        self._compile_body(args[1:], cur_scope, is_tail=is_tail)
        return True

    def _compile_letrec(self, expr: Cons, scope: _CompileScope, is_tail: bool) -> bool:
        args = _proper_list_elems(expr.cdr)
        if args is None or len(args) < 2:
            return False
        binds_raw = _proper_list_elems(args[0])
        if binds_raw is None:
            return False
        rec_scope = _CompileScope(parent=scope, is_frame_root=False)
        pairs: List[Tuple[int, Any]] = []
        for b in binds_raw:
            bl = _proper_list_elems(b)
            if bl is None or len(bl) != 2 or type(bl[0]) is not Symbol:
                return False
            slot = rec_scope.alloc_slot(bl[0])
            pairs.append((slot, bl[1]))
        for slot, ie in pairs:
            self._compile_expr(ie, rec_scope, is_tail=False)
            self._emit(OP_POP_STORE_LOCAL0, slot)
        self._compile_body(args[1:], rec_scope, is_tail=is_tail)
        return True

    def _compile_cond(self, expr: Cons, scope: _CompileScope, is_tail: bool) -> bool:
        clauses = _proper_list_elems(expr.cdr)
        if clauses is None:
            return False
        if not clauses:
            self._emit(OP_CONST, NIL)
            return True

        else_shadowed = self._is_bound_lexically(_SYM_ELSE, scope)
        arrow_shadowed = self._is_bound_lexically(_SYM_ARROW, scope)
        end_jumps: List[int] = []

        for idx, cl in enumerate(clauses):
            parts = _proper_list_elems(cl)
            if parts is None or not parts:
                return False
            test_expr = parts[0]
            if test_expr is _SYM_ELSE and not else_shadowed:
                if idx != len(clauses) - 1 or len(parts) < 2:
                    return False
                self._compile_body(parts[1:], scope, is_tail=is_tail)
                target_end = len(self.ops)
                for ej in end_jumps:
                    self._patch(ej, target_end)
                return True

            self._compile_expr(test_expr, scope, is_tail=False)
            if len(parts) == 1:
                end_jumps.append(self._emit(OP_JUMP_IF_TRUE_KEEP, 0))
                continue

            if len(parts) == 3 and parts[1] is _SYM_ARROW and not arrow_shadowed:
                scratch_slot = self.scope.frame_slot_count[0]
                self.scope.frame_slot_count[0] += 1
                self.scope.frame_slot_names.append(None)
                self._emit(OP_STORE_LOCAL0, scratch_slot)
                jf = self._emit(OP_JUMP_IF_FALSE, 0)
                self._compile_expr(parts[2], scope, is_tail=False)
                self._emit(OP_LOAD_LOCAL0, scratch_slot)
                self._emit(OP_TAIL_CALL if is_tail else OP_CALL, 1)
            else:
                jf = self._emit(OP_JUMP_IF_FALSE, 0)
                self._compile_body(parts[1:], scope, is_tail=is_tail)
            end_jumps.append(self._emit(OP_JUMP, 0))
            self._patch(jf, len(self.ops))

        self._emit(OP_CONST, NIL)
        target_end = len(self.ops)
        for ej in end_jumps:
            self._patch(ej, target_end)
        return True

    def _compile_case(self, expr: Cons, scope: _CompileScope, is_tail: bool) -> bool:
        args = _proper_list_elems(expr.cdr)
        if args is None or len(args) < 2:
            return False
        else_shadowed = self._is_bound_lexically(_SYM_ELSE, scope)
        arrow_shadowed = self._is_bound_lexically(_SYM_ARROW, scope)

        key_slot = self.scope.frame_slot_count[0]
        self.scope.frame_slot_count[0] += 1
        self.scope.frame_slot_names.append(None)
        self._compile_expr(args[0], scope, is_tail=False)
        self._emit(OP_POP_STORE_LOCAL0, key_slot)

        end_jumps: List[int] = []
        clauses = args[1:]
        for idx, cl in enumerate(clauses):
            parts = _proper_list_elems(cl)
            if parts is None or len(parts) < 2:
                return False
            datums_spec = parts[0]
            is_else = datums_spec is _SYM_ELSE and not else_shadowed
            if is_else:
                if idx != len(clauses) - 1:
                    return False
                if len(parts) == 3 and parts[1] is _SYM_ARROW and not arrow_shadowed:
                    self._compile_expr(parts[2], scope, is_tail=False)
                    self._emit(OP_LOAD_LOCAL0, key_slot)
                    self._emit(OP_TAIL_CALL if is_tail else OP_CALL, 1)
                else:
                    self._compile_body(parts[1:], scope, is_tail=is_tail)
                end_ip = len(self.ops)
                for ej in end_jumps:
                    self._patch(ej, end_ip)
                return True

            datums = _proper_list_elems(datums_spec)
            if datums is None:
                return False
            self._emit(OP_LOAD_LOCAL0, key_slot)
            self._emit(OP_CASE_MATCH, tuple(datums))
            jf = self._emit(OP_JUMP_IF_FALSE, 0)
            if len(parts) == 3 and parts[1] is _SYM_ARROW and not arrow_shadowed:
                self._compile_expr(parts[2], scope, is_tail=False)
                self._emit(OP_LOAD_LOCAL0, key_slot)
                self._emit(OP_TAIL_CALL if is_tail else OP_CALL, 1)
            else:
                self._compile_body(parts[1:], scope, is_tail=is_tail)
            end_jumps.append(self._emit(OP_JUMP, 0))
            self._patch(jf, len(self.ops))

        self._emit(OP_CONST, NIL)
        end_ip = len(self.ops)
        for ej in end_jumps:
            self._patch(ej, end_ip)
        return True

    def _compile_do(self, expr: Cons, scope: _CompileScope, is_tail: bool) -> bool:
        args = _proper_list_elems(expr.cdr)
        if args is None or len(args) < 2:
            return False
        vars_raw = _proper_list_elems(args[0])
        test_raw = _proper_list_elems(args[1])
        if vars_raw is None or test_raw is None or not test_raw:
            return False
        cmds = args[2:]

        var_syms: List[Symbol] = []
        init_exprs: List[Any] = []
        step_exprs: List[Any] = []
        has_step: List[bool] = []
        for vspec in vars_raw:
            vp = _proper_list_elems(vspec)
            if vp is None or len(vp) not in (2, 3) or type(vp[0]) is not Symbol:
                return False
            var_syms.append(vp[0])
            init_exprs.append(vp[1])
            if len(vp) == 3:
                step_exprs.append(vp[2])
                has_step.append(True)
            else:
                step_exprs.append(vp[0])
                has_step.append(False)

        needs_iter_frame = any(_expr_has_lambda_or_fallback(x) for x in cmds) or any(
            _expr_has_lambda_or_fallback(x) for x in step_exprs
        )

        if not needs_iter_frame:
            # Fast flat-slot loop with zero LexFrame churn
            do_scope = _CompileScope(parent=scope, is_frame_root=False)
            for ie in init_exprs:
                self._compile_expr(ie, scope, is_tail=False)
            slots = [do_scope.alloc_slot(vs) for vs in var_syms]
            for slot in reversed(slots):
                self._emit(OP_POP_STORE_LOCAL0, slot)

            loop_ip = len(self.ops)
            self._compile_expr(test_raw[0], do_scope, is_tail=False)
            jf_cmds = self._emit(OP_JUMP_IF_FALSE, 0)
            if len(test_raw) > 1:
                self._compile_body(test_raw[1:], do_scope, is_tail=is_tail)
            else:
                self._emit(OP_CONST, NIL)
            j_exit = self._emit(OP_JUMP, 0)

            self._patch(jf_cmds, len(self.ops))
            for cmd in cmds:
                self._compile_expr(cmd, do_scope, is_tail=False)
                self._emit(OP_POP)
            for se in step_exprs:
                self._compile_expr(se, do_scope, is_tail=False)
            for slot in reversed(slots):
                self._emit(OP_POP_STORE_LOCAL0, slot)
            self._emit(OP_JUMP, loop_ip)
            self._patch(j_exit, len(self.ops))
            return True

        # Per-iteration frame for closure capture inside `do`
        # Compile step expressions inside a frame containing ONLY `var_syms`
        # so captured closures isolate iteration values cleanly.
        do_frame_scope = _CompileScope(parent=scope, is_frame_root=True)
        # Emit an inner helper thunk for the loop iteration:
        from ilisp.evaluator import _check_shadows_sf

        iter_body_exprs = [
            Cons(
                _SYM_IF,
                Cons(
                    test_raw[0],
                    Cons(
                        Cons(
                            _SYM_BEGIN,
                            to_lisp_list(test_raw[1:] if len(test_raw) > 1 else [NIL]),
                        ),
                        Cons(
                            Cons(
                                _SYM_BEGIN,
                                to_lisp_list(
                                    cmds
                                    + [
                                        Cons(
                                            Symbol.intern("__do_loop__"),
                                            to_lisp_list(step_exprs),
                                        )
                                    ]
                                ),
                            ),
                            NIL,
                        ),
                    ),
                ),
            )
        ]
        # Simple Named let lowering delegates per-iteration LexFrame allocation cleanly
        loop_sym = Symbol.intern("__do_loop__")
        rec_scope = _CompileScope(parent=scope, is_frame_root=False)
        loop_slot = rec_scope.alloc_slot(loop_sym)
        child_comp = _FunctionCompiler(
            params=var_syms,
            rest_param=None,
            body_ast=iter_body_exprs,
            name="__do_loop__",
            shadows_sf=_check_shadows_sf(var_syms, None),
            root_env=self.root_env,
            outer_env=self.outer_env,
            parent_scope=rec_scope,
        )
        del do_frame_scope
        child_code = child_comp.compile()
        if child_comp.uses_macros:
            self.uses_macros = True
        self._emit(OP_MAKE_CLOSURE, child_code)
        self._emit(OP_POP_STORE_LOCAL0, loop_slot)
        self._emit(OP_LOAD_LOCAL0, loop_slot)
        for ie in init_exprs:
            self._compile_expr(ie, scope, is_tail=False)
        self._emit(OP_TAIL_CALL if is_tail else OP_CALL, len(init_exprs))
        return True

    def _compile_lambda(self, expr: Cons, scope: _CompileScope) -> bool:
        args = _proper_list_elems(expr.cdr)
        if args is None or len(args) < 2:
            return False
        from ilisp.evaluator import _check_shadows_sf, _parse_params

        try:
            parsed_params, rest_p = _parse_params(args[0])
        except SyntaxError:
            return False

        child_comp = _FunctionCompiler(
            params=parsed_params,
            rest_param=rest_p,
            body_ast=args[1:],
            name=None,
            shadows_sf=_check_shadows_sf(parsed_params, rest_p),
            root_env=self.root_env,
            outer_env=self.outer_env,
            parent_scope=scope,
        )
        child_code = child_comp.compile()
        if child_comp.uses_macros:
            self.uses_macros = True
        self._emit(OP_MAKE_CLOSURE, child_code)
        return True


def ensure_compiled(proc: Procedure) -> Optional[CodeObject]:
    """Lazily compile `proc` into a cached CodeObject, or return existing one."""
    prev_parent_scope: Optional[_CompileScope] = None
    code: Optional[CodeObject] = proc._code
    if code is not None:
        if not code.uses_macros or code.macro_epoch == code.root_env._macro_epoch:
            return code
        prev_parent_scope = code.parent_scope
        proc._code = None

    if proc._uncompilable or proc.is_macro or proc.env is None:
        return None

    env = proc.env
    root_env = env.root
    outer_env = env if env.parent is not None else None
    compiler = _FunctionCompiler(
        params=proc.params,
        rest_param=proc.rest_param,
        body_ast=proc.body,
        name=proc.name,
        shadows_sf=proc.shadows_sf,
        root_env=root_env,
        outer_env=outer_env,
        parent_scope=prev_parent_scope,
    )
    try:
        code = compiler.compile()
    except Exception:
        proc._uncompilable = True
        return None

    proc._code = code
    return code


def _materialize_bridge_env(
    code: CodeObject,
    cur_frame: Optional[LexFrame],
    snap: Tuple[Tuple[int, int, Symbol], ...],
) -> Tuple[Any, List[Tuple[int, int, Symbol, Any]]]:
    """Build a temporary Environment mirroring active LexFrame slots."""
    from ilisp.env import Environment

    base = code.outer_env if code.outer_env is not None else code.root_env
    if not snap:
        return (base, [])
    bindings: Dict[Symbol, Any] = {}
    recorded: List[Tuple[int, int, Symbol, Any]] = []
    for depth, slot, sym in snap:
        f = cur_frame
        d = depth
        while d > 0 and f is not None:
            f = f.parent
            d -= 1
        val = f.slots[slot] if (f is not None and slot < len(f.slots)) else None
        bindings[sym] = val
        recorded.append((depth, slot, sym, val))
    bridge = Environment(parent=base, bindings=bindings)
    return (bridge, recorded)


def _sync_bridge_env(
    cur_frame: Optional[LexFrame],
    bridge_bindings: Dict[Symbol, Any],
    recorded: List[Tuple[int, int, Symbol, Any]],
) -> None:
    """Propagate any set! mutations made inside fallback back to LexFrame."""
    for depth, slot, sym, old_val in recorded:
        new_val = bridge_bindings.get(sym, old_val)
        if new_val is not old_val:
            f = cur_frame
            d = depth
            while d > 0 and f is not None:
                f = f.parent
                d -= 1
            if f is not None and slot < len(f.slots):
                f.slots[slot] = new_val


def _bind_lex_slots(code: CodeObject, args: List[Any]) -> List[Any]:
    """Allocate flat slot list for entering `code` with `args`."""
    n_p = code.n_params
    n_args = len(args)
    if code.rest_index < 0:
        if n_args != n_p:
            raise TypeError(
                f"Procedure {code.name or 'lambda'} expected {n_p} arguments, got {n_args}"
            )
        extra = code.n_locals - n_p
        if extra <= 0:
            return args
        return args + [None] * extra

    if n_args < n_p:
        raise TypeError(
            f"Procedure {code.name or 'lambda'} expected at least {n_p} arguments, got {n_args}"
        )
    rest_list = to_lisp_list(args[n_p:])
    extra = code.n_locals - n_p - 1
    if extra <= 0:
        return args[:n_p] + [rest_list]
    return args[:n_p] + [rest_list] + [None] * extra


_DEPS_READY = False
_DEP_ENV_CLS: Any = None
_DEP_IS_MACRO_VAL: Any = None
_DEP_APPLY_TREEWALK: Any = None
_DEP_RESOLVE_DOTTED: Any = None
_DEP_EVAL_EXPR: Any = None
_DEP_EVAL_QQ: Any = None
_DEP_EVAL_MOD: Any = None


def _init_vm_deps() -> None:
    global _DEPS_READY, _DEP_ENV_CLS, _DEP_IS_MACRO_VAL, _DEP_APPLY_TREEWALK
    global _DEP_RESOLVE_DOTTED, _DEP_EVAL_EXPR, _DEP_EVAL_QQ, _DEP_EVAL_MOD
    import ilisp.evaluator as eval_mod
    from ilisp.env import Environment, _is_macro_val

    _DEP_ENV_CLS = Environment
    _DEP_IS_MACRO_VAL = _is_macro_val
    _DEP_APPLY_TREEWALK = eval_mod._apply_procedure_treewalk
    _DEP_RESOLVE_DOTTED = eval_mod._resolve_dotted_symbol
    _DEP_EVAL_EXPR = eval_mod.eval_expr
    _DEP_EVAL_QQ = eval_mod.eval_quasiquote
    _DEP_EVAL_MOD = eval_mod
    _DEPS_READY = True


def call_compiled_procedure(proc: Procedure, args: List[Any]) -> Any:
    """Execute `proc` via lazy bytecode compilation + stack VM."""
    if not _DEPS_READY:
        _init_vm_deps()
    code = ensure_compiled(proc)
    if code is None:
        return _DEP_APPLY_TREEWALK(proc, args)
    slots = _bind_lex_slots(code, list(args))
    frame = LexFrame(proc.lex_frame, slots)
    return _run_vm(code, frame, slots)


def run_compiled_1arg(proc: Procedure, code: CodeObject, arg0: Any) -> Any:
    """Fast 1-argument entry point into compiled VM for HOF loops."""
    if not _DEPS_READY:
        _init_vm_deps()
    if code.n_params == 1 and code.rest_index < 0:
        extra = code.n_locals - 1
        slots = [arg0] if extra <= 0 else [arg0] + [None] * extra
    else:
        slots = _bind_lex_slots(code, [arg0])
    return _run_vm(code, LexFrame(proc.lex_frame, slots), slots)


def run_compiled_2arg(proc: Procedure, code: CodeObject, arg0: Any, arg1: Any) -> Any:
    """Fast 2-argument entry point into compiled VM for HOF loops."""
    if not _DEPS_READY:
        _init_vm_deps()
    if code.n_params == 2 and code.rest_index < 0:
        extra = code.n_locals - 2
        slots = [arg0, arg1] if extra <= 0 else [arg0, arg1] + [None] * extra
    else:
        slots = _bind_lex_slots(code, [arg0, arg1])
    return _run_vm(code, LexFrame(proc.lex_frame, slots), slots)


def _eqv_fast(a: Any, b: Any) -> bool:
    if a is b:
        return True
    ta = type(a)
    if ta is type(b) and isinstance(a, (int, float, str, bool, Char, complex)):
        return bool(a == b)
    from fractions import Fraction

    if isinstance(a, Fraction) and isinstance(b, Fraction):
        return a == b
    return False


def _run_vm(
    entry_code: CodeObject,
    entry_frame: LexFrame,
    entry_slots: List[Any],
) -> Any:
    """Iterative stack bytecode VM supporting zero-stack Scheme tail calls."""
    if not _DEPS_READY:
        _init_vm_deps()
    Environment = _DEP_ENV_CLS
    _is_macro_val = _DEP_IS_MACRO_VAL
    _apply_procedure_treewalk = _DEP_APPLY_TREEWALK
    _resolve_dotted_symbol = _DEP_RESOLVE_DOTTED
    eval_expr = _DEP_EVAL_EXPR
    eval_quasiquote = _DEP_EVAL_QQ
    eval_mod = _DEP_EVAL_MOD

    Cons_ = Cons
    NIL_ = NIL
    Procedure_ = Procedure
    Primitive_ = Primitive
    LexFrame_ = LexFrame
    Symbol_ = Symbol
    Char_ = Char
    MutableString_ = MutableString
    Fraction_ = Fraction
    UNBOUND_ = UNBOUND
    _type = type
    _int = int
    _str = str

    code = entry_code
    ops = code.ops
    arg1 = code.arg1
    arg2 = code.arg2
    ip = 0
    frame = entry_frame
    slots = entry_slots

    stack: List[Any] = []
    # Call stack entries: (caller_code, caller_ip, caller_frame, caller_slots)
    call_stack: List[Tuple[CodeObject, int, LexFrame, List[Any]]] = []

    while True:
        op = ops[ip]

        if op < 30:
            if op == OP_LOAD_LOCAL0:
                stack.append(slots[arg1[ip]])
                ip += 1

            elif op == OP_CONST:
                stack.append(arg1[ip])
                ip += 1

            elif op == OP_LOAD_GLOBAL:
                cell: GlobalCell = arg1[ip]
                val = cell.value
                if val is UNBOUND_:
                    sname = cell.sym.name
                    if "." in sname and not sname.startswith("."):
                        dval = _resolve_dotted_symbol(sname, code.root_env)
                        if dval is not None:
                            stack.append(dval)
                            ip += 1
                            continue
                    raise NameError(f"Unbound variable: '{sname}'")
                stack.append(val)
                ip += 1

            elif op == OP_JUMP_IF_FALSE:
                ip = arg1[ip] if stack.pop() is False else ip + 1

            elif op == OP_POP_STORE_LOCAL0:
                slots[arg1[ip]] = stack.pop()
                ip += 1

            elif op == OP_STORE_LOCAL0:
                slots[arg1[ip]] = stack[-1]
                ip += 1

            elif op == OP_JUMP:
                ip = arg1[ip]

            elif op == OP_POP:
                stack.pop()
                ip += 1

            elif op == OP_JUMP_IF_FALSE_KEEP:
                if stack[-1] is False:
                    ip = arg1[ip]
                else:
                    stack.pop()
                    ip += 1

            elif op == OP_JUMP_IF_TRUE_KEEP:
                if stack[-1] is not False:
                    ip = arg1[ip]
                else:
                    stack.pop()
                    ip += 1

            elif op == OP_JUMP_IF_TRUE:
                ip = arg1[ip] if stack.pop() is not False else ip + 1

            elif op == OP_CALL:
                argc = arg1[ip]
                if argc == 1:
                    a0 = stack.pop()
                    fn = stack.pop()
                    t_fn = _type(fn)
                    if t_fn is Primitive_:
                        stack.append(fn.fn(a0))
                        ip += 1
                        continue
                    if (
                        t_fn is Procedure_
                        and not fn.is_macro
                        and Environment._mutation_hook is None
                    ):
                        callee_code: Optional[CodeObject] = fn._code
                        if callee_code is None or (
                            callee_code.uses_macros
                            and callee_code.macro_epoch
                            != callee_code.root_env._macro_epoch
                        ):
                            callee_code = ensure_compiled(fn)
                        if callee_code is not None:
                            hook = eval_mod._current_step_hook
                            if hook is not None:
                                hook()
                            if callee_code.n_params == 1 and callee_code.rest_index < 0:
                                extra = callee_code.n_locals - 1
                                new_slots = (
                                    [a0] if extra <= 0 else [a0] + [None] * extra
                                )
                            else:
                                new_slots = _bind_lex_slots(callee_code, [a0])
                            call_stack.append((code, ip + 1, frame, slots))
                            code = callee_code
                            ops = code.ops
                            arg1 = code.arg1
                            arg2 = code.arg2
                            ip = 0
                            slots = new_slots
                            frame = LexFrame_(fn.lex_frame, new_slots)
                            continue
                    call_args = [a0]
                elif argc == 2:
                    a1 = stack.pop()
                    a0 = stack.pop()
                    fn = stack.pop()
                    t_fn = _type(fn)
                    if t_fn is Primitive_:
                        stack.append(fn.fn(a0, a1))
                        ip += 1
                        continue
                    if (
                        t_fn is Procedure_
                        and not fn.is_macro
                        and Environment._mutation_hook is None
                    ):
                        callee_code = fn._code
                        if callee_code is None or (
                            callee_code.uses_macros
                            and callee_code.macro_epoch
                            != callee_code.root_env._macro_epoch
                        ):
                            callee_code = ensure_compiled(fn)
                        if callee_code is not None:
                            hook = eval_mod._current_step_hook
                            if hook is not None:
                                hook()
                            if callee_code.n_params == 2 and callee_code.rest_index < 0:
                                extra = callee_code.n_locals - 2
                                new_slots = (
                                    [a0, a1]
                                    if extra <= 0
                                    else [a0, a1] + [None] * extra
                                )
                            else:
                                new_slots = _bind_lex_slots(callee_code, [a0, a1])
                            call_stack.append((code, ip + 1, frame, slots))
                            code = callee_code
                            ops = code.ops
                            arg1 = code.arg1
                            arg2 = code.arg2
                            ip = 0
                            slots = new_slots
                            frame = LexFrame_(fn.lex_frame, new_slots)
                            continue
                    call_args = [a0, a1]
                else:
                    if argc > 0:
                        base = len(stack) - argc
                        call_args = stack[base:]
                        del stack[base:]
                    else:
                        call_args = []
                    fn = stack.pop()
                    t_fn = _type(fn)

                if t_fn is Primitive_:
                    stack.append(fn.fn(*call_args))
                    ip += 1
                    continue

                if t_fn is Procedure_:
                    if fn.is_macro or Environment._mutation_hook is not None:
                        stack.append(_apply_procedure_treewalk(fn, call_args))
                        ip += 1
                        continue
                    callee_code = fn._code
                    if callee_code is None or (
                        callee_code.uses_macros
                        and callee_code.macro_epoch != callee_code.root_env._macro_epoch
                    ):
                        callee_code = ensure_compiled(fn)
                    if callee_code is None:
                        stack.append(_apply_procedure_treewalk(fn, call_args))
                        ip += 1
                        continue
                    hook = eval_mod._current_step_hook
                    if hook is not None:
                        hook()
                    new_slots = _bind_lex_slots(callee_code, call_args)
                    call_stack.append((code, ip + 1, frame, slots))
                    code = callee_code
                    ops = code.ops
                    arg1 = code.arg1
                    arg2 = code.arg2
                    ip = 0
                    slots = new_slots
                    frame = LexFrame_(fn.lex_frame, new_slots)
                    continue

                if hasattr(fn, "transform"):
                    raise TypeError(f"Attempted to apply macro directly: {fn!r}")
                if callable(fn):
                    stack.append(fn(*call_args))
                    ip += 1
                    continue
                raise TypeError(f"Attempted to apply non-procedure: {fn!r}")

            elif op == OP_TAIL_CALL:
                argc = arg1[ip]
                if argc == 1:
                    a0 = stack.pop()
                    fn = stack.pop()
                    t_fn = _type(fn)
                    if t_fn is Primitive_:
                        res = fn.fn(a0)
                        if not call_stack:
                            return res
                        stack.append(res)
                        code, ip, frame, slots = call_stack.pop()
                        ops = code.ops
                        arg1 = code.arg1
                        arg2 = code.arg2
                        continue
                    if (
                        t_fn is Procedure_
                        and not fn.is_macro
                        and Environment._mutation_hook is None
                    ):
                        callee_code = fn._code
                        if callee_code is None or (
                            callee_code.uses_macros
                            and callee_code.macro_epoch
                            != callee_code.root_env._macro_epoch
                        ):
                            callee_code = ensure_compiled(fn)
                        if callee_code is not None:
                            hook = eval_mod._current_step_hook
                            if hook is not None:
                                hook()
                            if callee_code.n_params == 1 and callee_code.rest_index < 0:
                                extra = callee_code.n_locals - 1
                                new_slots = (
                                    [a0] if extra <= 0 else [a0] + [None] * extra
                                )
                            else:
                                new_slots = _bind_lex_slots(callee_code, [a0])
                            code = callee_code
                            ops = code.ops
                            arg1 = code.arg1
                            arg2 = code.arg2
                            ip = 0
                            slots = new_slots
                            frame = LexFrame_(fn.lex_frame, new_slots)
                            continue
                    call_args = [a0]
                elif argc == 2:
                    a1 = stack.pop()
                    a0 = stack.pop()
                    fn = stack.pop()
                    t_fn = _type(fn)
                    if t_fn is Primitive_:
                        res = fn.fn(a0, a1)
                        if not call_stack:
                            return res
                        stack.append(res)
                        code, ip, frame, slots = call_stack.pop()
                        ops = code.ops
                        arg1 = code.arg1
                        arg2 = code.arg2
                        continue
                    if (
                        t_fn is Procedure_
                        and not fn.is_macro
                        and Environment._mutation_hook is None
                    ):
                        callee_code = fn._code
                        if callee_code is None or (
                            callee_code.uses_macros
                            and callee_code.macro_epoch
                            != callee_code.root_env._macro_epoch
                        ):
                            callee_code = ensure_compiled(fn)
                        if callee_code is not None:
                            hook = eval_mod._current_step_hook
                            if hook is not None:
                                hook()
                            if callee_code.n_params == 2 and callee_code.rest_index < 0:
                                extra = callee_code.n_locals - 2
                                new_slots = (
                                    [a0, a1]
                                    if extra <= 0
                                    else [a0, a1] + [None] * extra
                                )
                            else:
                                new_slots = _bind_lex_slots(callee_code, [a0, a1])
                            code = callee_code
                            ops = code.ops
                            arg1 = code.arg1
                            arg2 = code.arg2
                            ip = 0
                            slots = new_slots
                            frame = LexFrame_(fn.lex_frame, new_slots)
                            continue
                    call_args = [a0, a1]
                else:
                    if argc > 0:
                        base = len(stack) - argc
                        call_args = stack[base:]
                        del stack[base:]
                    else:
                        call_args = []
                    fn = stack.pop()
                    t_fn = _type(fn)

                if t_fn is Primitive_:
                    res = fn.fn(*call_args)
                    if not call_stack:
                        return res
                    stack.append(res)
                    code, ip, frame, slots = call_stack.pop()
                    ops = code.ops
                    arg1 = code.arg1
                    arg2 = code.arg2
                    continue

                if t_fn is Procedure_:
                    if fn.is_macro or Environment._mutation_hook is not None:
                        res = _apply_procedure_treewalk(fn, call_args)
                        if not call_stack:
                            return res
                        stack.append(res)
                        code, ip, frame, slots = call_stack.pop()
                        ops = code.ops
                        arg1 = code.arg1
                        arg2 = code.arg2
                        continue
                    callee_code = fn._code
                    if callee_code is None or (
                        callee_code.uses_macros
                        and callee_code.macro_epoch != callee_code.root_env._macro_epoch
                    ):
                        callee_code = ensure_compiled(fn)
                    if callee_code is None:
                        res = _apply_procedure_treewalk(fn, call_args)
                        if not call_stack:
                            return res
                        stack.append(res)
                        code, ip, frame, slots = call_stack.pop()
                        ops = code.ops
                        arg1 = code.arg1
                        arg2 = code.arg2
                        continue
                    hook = eval_mod._current_step_hook
                    if hook is not None:
                        hook()
                    if (
                        callee_code.rest_index < 0
                        and len(call_args) == callee_code.n_params
                    ):
                        extra = callee_code.n_locals - callee_code.n_params
                        new_slots = (
                            call_args if extra <= 0 else call_args + [None] * extra
                        )
                    else:
                        new_slots = _bind_lex_slots(callee_code, call_args)
                    code = callee_code
                    ops = code.ops
                    arg1 = code.arg1
                    arg2 = code.arg2
                    ip = 0
                    slots = new_slots
                    frame = LexFrame_(fn.lex_frame, new_slots)
                    continue

                if callable(fn):
                    res = fn(*call_args)
                    if not call_stack:
                        return res
                    stack.append(res)
                    code, ip, frame, slots = call_stack.pop()
                    ops = code.ops
                    arg1 = code.arg1
                    arg2 = code.arg2
                    continue
                raise TypeError(f"Attempted to apply non-procedure: {fn!r}")

            elif op == OP_RETURN:
                res = stack.pop()
                if not call_stack:
                    return res
                stack.append(res)
                code, ip, frame, slots = call_stack.pop()
                ops = code.ops
                arg1 = code.arg1
                arg2 = code.arg2

            elif op == OP_LOAD_LOCAL:
                depth = arg1[ip]
                slot = arg2[ip]
                f = frame.parent
                d = depth - 1
                while d > 0 and f is not None:
                    f = f.parent
                    d -= 1
                assert f is not None
                stack.append(f.slots[slot])
                ip += 1

            elif op == OP_MAKE_CLOSURE:
                cc: CodeObject = arg1[ip]
                stack.append(
                    Procedure_(
                        params=cc.param_syms,
                        body=cc.body_ast,
                        env=(
                            code.outer_env
                            if code.outer_env is not None
                            else code.root_env
                        ),
                        is_macro=False,
                        rest_param=cc.rest_sym,
                        name=cc.name,
                        shadows_sf=cc.shadows_sf,
                        lex_frame=frame,
                        code=cc,
                    )
                )
                ip += 1

            elif op == OP_CASE_MATCH:
                kval = stack.pop()
                tk = _type(kval)
                matched = False
                for d_item in arg1[ip]:
                    if kval is d_item:
                        matched = True
                        break
                    if (
                        tk is _type(d_item)
                        and (
                            tk is _int
                            or tk is float
                            or tk is _str
                            or tk is bool
                            or tk is Char_
                            or tk is complex
                            or tk is Fraction_
                        )
                        and kval == d_item
                    ):
                        matched = True
                        break
                stack.append(matched)
                ip += 1

            elif op == OP_STORE_LOCAL:
                depth = arg1[ip]
                slot = arg2[ip]
                f = frame.parent
                d = depth - 1
                while d > 0 and f is not None:
                    f = f.parent
                    d -= 1
                assert f is not None
                f.slots[slot] = stack[-1]
                ip += 1

            elif op == OP_POP_STORE_LOCAL:
                depth = arg1[ip]
                slot = arg2[ip]
                f = frame.parent
                d = depth - 1
                while d > 0 and f is not None:
                    f = f.parent
                    d -= 1
                assert f is not None
                f.slots[slot] = stack.pop()
                ip += 1

            elif op == OP_STORE_GLOBAL:
                cell = arg1[ip]
                if cell.value is UNBOUND_:
                    raise NameError(f"Cannot set! unbound variable: '{cell.sym.name}'")
                val = stack[-1]
                old_v = cell.value
                code.root_env.bindings[cell.sym] = val
                cell.value = val
                if _is_macro_val(val) or _is_macro_val(old_v):
                    code.root_env._macro_epoch += 1
                ip += 1

            elif op == OP_QUASIQUOTE:
                b_env, _ = _materialize_bridge_env(code, frame, arg2[ip])
                stack.append(eval_quasiquote(arg1[ip], b_env))
                ip += 1

            elif op == OP_EVAL_FALLBACK:
                b_env, rec = _materialize_bridge_env(code, frame, arg2[ip])
                try:
                    res_fb = eval_expr(arg1[ip], b_env)
                finally:
                    if rec:
                        _sync_bridge_env(frame, b_env.bindings, rec)
                stack.append(res_fb)
                ip += 1

            elif op == OP_LOAD_OUTER_ENV:
                assert code.outer_env is not None
                stack.append(code.outer_env.lookup(arg1[ip]))
                ip += 1

            elif op == OP_STORE_OUTER_ENV:
                assert code.outer_env is not None
                val = stack[-1]
                code.outer_env.set(arg1[ip], val)
                ip += 1

            # --- Guarded Superinstructions ---
            else:
                raise RuntimeError(f"Unknown VM opcode: {op}")
        elif op < 47:
            if op == OP_CAR:
                x = stack.pop()
                c_cell: GlobalCell = arg1[ip]
                exp: Primitive = arg2[ip]
                if c_cell.value is exp:
                    stack.append(x.car if _type(x) is Cons_ else exp.fn(x))
                else:
                    stack.append(c_cell.value(x))
                ip += 1

            elif op == OP_CDR:
                x = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    stack.append(x.cdr if _type(x) is Cons_ else exp.fn(x))
                else:
                    stack.append(c_cell.value(x))
                ip += 1

            elif op == OP_CADR:
                x = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(x) is Cons_ and _type(x.cdr) is Cons_:
                        stack.append(x.cdr.car)
                    else:
                        stack.append(exp.fn(x))
                else:
                    stack.append(c_cell.value(x))
                ip += 1

            elif op == OP_CADDR:
                x = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if (
                        _type(x) is Cons_
                        and _type(x.cdr) is Cons_
                        and _type(x.cdr.cdr) is Cons_
                    ):
                        stack.append(x.cdr.cdr.car)
                    else:
                        stack.append(exp.fn(x))
                else:
                    stack.append(c_cell.value(x))
                ip += 1

            elif op == OP_CONS:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    stack.append(Cons_(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_NULL_P:
                x = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    stack.append(
                        x is NIL_ or (_type(x) is SequenceView and len(x) == 0)
                    )
                else:
                    stack.append(c_cell.value(x))
                ip += 1

            elif op == OP_PAIR_P:
                x = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    stack.append(
                        _type(x) is Cons_ or (_type(x) is SequenceView and len(x) > 0)
                    )
                else:
                    stack.append(c_cell.value(x))
                ip += 1

            elif op == OP_NOT:
                x = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    stack.append(x is False)
                else:
                    stack.append(c_cell.value(x))
                ip += 1

            elif op == OP_EQ_P:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    stack.append(a is b)
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_ADD2:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(a) is _int and _type(b) is _int:
                        stack.append(a + b)
                    else:
                        stack.append(exp.fn(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_SUB2:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(a) is _int and _type(b) is _int:
                        stack.append(a - b)
                    else:
                        stack.append(exp.fn(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_MUL2:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(a) is _int and _type(b) is _int:
                        stack.append(a * b)
                    else:
                        stack.append(exp.fn(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_NUM_EQ2:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(a) is _int and _type(b) is _int:
                        stack.append(a == b)
                    else:
                        stack.append(exp.fn(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_LT2:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(a) is _int and _type(b) is _int:
                        stack.append(a < b)
                    else:
                        stack.append(exp.fn(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_LE2:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(a) is _int and _type(b) is _int:
                        stack.append(a <= b)
                    else:
                        stack.append(exp.fn(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_GT2:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(a) is _int and _type(b) is _int:
                        stack.append(a > b)
                    else:
                        stack.append(exp.fn(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_GE2:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(a) is _int and _type(b) is _int:
                        stack.append(a >= b)
                    else:
                        stack.append(exp.fn(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            else:
                raise RuntimeError(f"Unknown VM opcode: {op}")
        else:
            if op == OP_LIST:
                c_cell, exp = arg1[ip]
                argc = arg2[ip]
                if c_cell.value is exp:
                    if argc == 0:
                        stack.append(NIL_)
                    elif argc == 1:
                        stack[-1] = Cons_(stack[-1], NIL_)
                    elif argc == 2:
                        b = stack.pop()
                        stack[-1] = Cons_(stack[-1], Cons_(b, NIL_))
                    else:
                        lst_res: Any = NIL_
                        for _ in range(argc):
                            lst_res = Cons_(stack.pop(), lst_res)
                        stack.append(lst_res)
                else:
                    if argc > 0:
                        base = len(stack) - argc
                        largs = stack[base:]
                        del stack[base:]
                    else:
                        largs = []
                    stack.append(c_cell.value(*largs))
                ip += 1

            elif op == OP_VECTOR_REF:
                idx_v = stack.pop()
                vec = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(vec) is Vector and _type(idx_v) is _int:
                        stack.append(vec.elements[idx_v])
                    else:
                        stack.append(exp.fn(vec, idx_v))
                else:
                    stack.append(c_cell.value(vec, idx_v))
                ip += 1

            elif op == OP_LENGTH:
                lst = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    cnt = 0
                    cur_l = lst
                    while _type(cur_l) is Cons_:
                        cnt += 1
                        cur_l = cur_l.cdr
                    if cur_l is NIL_:
                        stack.append(cnt)
                    else:
                        stack.append(exp.fn(lst))
                else:
                    stack.append(c_cell.value(lst))
                ip += 1

            elif op == OP_ASSQ:
                alist = stack.pop()
                key = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    cur_a = alist
                    found_a: Any = False
                    fast_ok = True
                    while _type(cur_a) is Cons_:
                        ent = cur_a.car
                        if _type(ent) is Cons_:
                            if ent.car is key:
                                found_a = ent
                                break
                        else:
                            fast_ok = False
                            break
                        cur_a = cur_a.cdr
                    if fast_ok and cur_a is NIL_ or (fast_ok and found_a is not False):
                        stack.append(found_a)
                    else:
                        stack.append(exp.fn(key, alist))
                else:
                    stack.append(c_cell.value(key, alist))
                ip += 1

            elif op == OP_MEMQ:
                lst = stack.pop()
                item = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    cur_m = lst
                    found_m: Any = False
                    while _type(cur_m) is Cons_:
                        if cur_m.car is item:
                            found_m = cur_m
                            break
                        cur_m = cur_m.cdr
                    if cur_m is NIL_ or found_m is not False:
                        stack.append(found_m)
                    else:
                        stack.append(exp.fn(item, lst))
                else:
                    stack.append(c_cell.value(item, lst))
                ip += 1

            elif op == OP_CADDDR:
                x = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if (
                        _type(x) is Cons_
                        and _type(x.cdr) is Cons_
                        and _type(x.cdr.cdr) is Cons_
                        and _type(x.cdr.cdr.cdr) is Cons_
                    ):
                        stack.append(x.cdr.cdr.cdr.car)
                    else:
                        stack.append(exp.fn(x))
                else:
                    stack.append(c_cell.value(x))
                ip += 1

            elif op == OP_SYMBOL_P:
                x = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    stack.append(_type(x) is Symbol_)
                else:
                    stack.append(c_cell.value(x))
                ip += 1

            elif op == OP_STRING_P:
                x = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    tx = _type(x)
                    stack.append(tx is _str or tx is MutableString_)
                else:
                    stack.append(c_cell.value(x))
                ip += 1

            elif op == OP_REVERSE:
                lst = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    res_rv: Any = NIL_
                    cur_rv = lst
                    while _type(cur_rv) is Cons_:
                        res_rv = Cons_(cur_rv.car, res_rv)
                        cur_rv = cur_rv.cdr
                    if cur_rv is NIL_:
                        stack.append(res_rv)
                    else:
                        stack.append(exp.fn(lst))
                else:
                    stack.append(c_cell.value(lst))
                ip += 1

            elif op == OP_MODULO:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(a) is _int and _type(b) is _int and b != 0:
                        stack.append(a % b)
                    else:
                        stack.append(exp.fn(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_STRING_EQ:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(a) is _str and _type(b) is _str:
                        stack.append(a == b)
                    else:
                        stack.append(exp.fn(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_CHAR_EQ:
                b = stack.pop()
                a = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(a) is Char_ and _type(b) is Char_:
                        stack.append(a.val == b.val)
                    else:
                        stack.append(exp.fn(a, b))
                else:
                    stack.append(c_cell.value(a, b))
                ip += 1

            elif op == OP_STRING_REF:
                k = stack.pop()
                s = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(s) is _str and _type(k) is _int and 0 <= k < len(s):
                        stack.append(Char_(s[k]))
                    else:
                        stack.append(exp.fn(s, k))
                else:
                    stack.append(c_cell.value(s, k))
                ip += 1

            elif op == OP_SET_CAR:
                v = stack.pop()
                p = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(p) is Cons_:
                        p.car = v
                        stack.append(NIL_)
                    else:
                        stack.append(exp.fn(p, v))
                else:
                    stack.append(c_cell.value(p, v))
                ip += 1

            elif op == OP_SET_CDR:
                v = stack.pop()
                p = stack.pop()
                c_cell = arg1[ip]
                exp = arg2[ip]
                if c_cell.value is exp:
                    if _type(p) is Cons_:
                        p.cdr = v
                        stack.append(NIL_)
                    else:
                        stack.append(exp.fn(p, v))
                else:
                    stack.append(c_cell.value(p, v))
                ip += 1

            else:
                raise RuntimeError(f"Unknown VM opcode: {op}")
