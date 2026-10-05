"""ALisp Contracts Subsystem.

Provides define/c contract definition macro, Blame Tracking (:caller / :callee),
ContractViolationException, and S-expression diagnostic serialization.
"""

from __future__ import annotations

from typing import Any, List, Optional, Tuple

from alisp.contracts.blame import (
    BlameParty,
    Contract,
    ContractWrappedProcedure,
    FlatContract,
    FunctionContract,
    make_arrow_contract_primitive,
    swap_blame,
)
from alisp.contracts.predicates import _call_predicate
from ilisp.types import (
    NIL,
    Cons,
    Primitive,
    Symbol,
    car,
    cdr,
    is_pair,
    to_lisp_list,
    to_py_list,
)


class ContractViolationException(Exception):
    """Raised when a function contract pre-condition or post-condition fails."""

    def __init__(
        self,
        message: str,
        blame: str = ":caller",
        function_name: str = "",
        argument_index: Optional[int] = None,
        parameter_name: str = "",
        expected: str = "",
        received: Any = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.blame = blame
        self.function_name = function_name
        self.argument_index = argument_index
        self.parameter_name = parameter_name
        self.expected = expected
        self.received = received

    def to_diagnostic(self) -> Cons:
        """Convert into an S-expression diagnostic structure as specified in DSN-32 Section 6.1."""
        fields: List[Any] = [
            Cons(Symbol.intern("severity"), Cons(Symbol.intern("error"), NIL)),
            Cons(
                Symbol.intern("type"),
                Cons(Symbol.intern(":contract-violation"), NIL),
            ),
            Cons(Symbol.intern("blame"), Cons(Symbol.intern(self.blame), NIL)),
            Cons(
                Symbol.intern("function"),
                Cons(Symbol.intern(self.function_name), NIL),
            ),
        ]
        if self.argument_index is not None:
            fields.append(
                Cons(Symbol.intern("argument"), Cons(self.argument_index, NIL))
            )
        if self.parameter_name:
            fields.append(
                Cons(
                    Symbol.intern("parameter"),
                    Cons(Symbol.intern(self.parameter_name), NIL),
                )
            )
        fields.append(
            Cons(
                Symbol.intern("expected"),
                Cons(Symbol.intern(str(self.expected)), NIL),
            )
        )
        fields.append(Cons(Symbol.intern("received"), Cons(self.received, NIL)))
        return Cons(Symbol.intern("diagnostic"), to_lisp_list(fields))


def contract_assert(
    fn_name: str,
    arg_idx: Any,
    param_name: str,
    pred: Any,
    value: Any,
    blame: str,
) -> Any:
    """Evaluate contract predicate on value, raising ContractViolationException on failure."""
    idx_val: Optional[int] = (
        arg_idx
        if (isinstance(arg_idx, int) and not isinstance(arg_idx, bool))
        else None
    )

    if isinstance(pred, Contract):
        pos = BlameParty.from_value(blame)
        neg = BlameParty(
            BlameParty.CALLEE if pos.name == BlameParty.CALLER else BlameParty.CALLER
        )
        return pred.check(
            value,
            positive=pos,
            negative=neg,
            fn_name=fn_name,
            arg_idx=idx_val,
        )

    try:
        ok = _call_predicate(pred, value)
    except ContractViolationException:
        raise
    except Exception:
        ok = False

    if not ok:
        pred_repr = (
            getattr(pred, "name", None) or getattr(pred, "__name__", None) or str(pred)
        )
        if blame == ":caller":
            msg = (
                f"Contract violation: function '{fn_name}' argument '{param_name}' "
                f"(index {arg_idx}) failed contract '{pred_repr}'. Received: {value!r}. Blame: {blame}"
            )
        else:
            msg = (
                f"Contract violation: function '{fn_name}' return value failed "
                f"post-condition '{pred_repr}'. Received: {value!r}. Blame: {blame}"
            )
        raise ContractViolationException(
            message=msg,
            blame=blame,
            function_name=fn_name,
            argument_index=idx_val,
            parameter_name=param_name,
            expected=pred_repr,
            received=value,
        )
    return value


def make_contract_assert_primitive() -> Primitive:
    """Create the runtime %contract-assert primitive."""

    def _prim_contract_assert(
        fn_name: Any,
        arg_idx: Any,
        param_name: Any,
        pred: Any,
        val: Any,
        blame: Any,
    ) -> Any:
        f_name_str = fn_name.name if isinstance(fn_name, Symbol) else str(fn_name)
        p_name_str = (
            param_name.name if isinstance(param_name, Symbol) else str(param_name)
        )
        blame_str = blame.name if isinstance(blame, Symbol) else str(blame)
        return contract_assert(f_name_str, arg_idx, p_name_str, pred, val, blame_str)

    return Primitive("%contract-assert", _prim_contract_assert)


class DefineContractTransformer:
    """Macro transformer for define/c.

    Desugars:
      (define/c (func-name (arg1 pred1) (arg2 pred2) ...)
        #:post post-pred
        body...)
    into:
      (define (func-name arg1 arg2 ...)
        (%contract-assert "func-name" 1 "arg1" pred1 arg1 ":caller")
        (%contract-assert "func-name" 2 "arg2" pred2 arg2 ":caller")
        (let ((__res__ (begin body...)))
          (%contract-assert "func-name" #f "return" post-pred __res__ ":callee")
          __res__))
    """

    @staticmethod
    def _parse_param_elem(
        elem: Any, arg_idx: int
    ) -> Tuple[Symbol, Optional[Tuple[int, Symbol, Any]]]:
        if is_pair(elem):
            p_sym = car(elem)
            if not isinstance(p_sym, Symbol):
                raise SyntaxError(f"define/c parameter must be a symbol, got {p_sym!r}")
            p_pred_args = cdr(elem)
            if not is_pair(p_pred_args):
                raise SyntaxError(
                    f"define/c parameter {p_sym.name} missing contract predicate"
                )
            return p_sym, (arg_idx, p_sym, car(p_pred_args))
        if isinstance(elem, Symbol):
            return elem, None
        raise SyntaxError(f"define/c invalid parameter specification: {elem!r}")

    @classmethod
    def _parse_params(
        cls, head_cdr: Any
    ) -> Tuple[List[Symbol], List[Tuple[int, Symbol, Any]], Optional[Symbol]]:
        param_syms: List[Symbol] = []
        param_contracts: List[Tuple[int, Symbol, Any]] = []
        curr_p = head_cdr
        arg_idx = 1
        rest_param: Optional[Symbol] = None

        while is_pair(curr_p):
            p_sym, contract = cls._parse_param_elem(car(curr_p), arg_idx)
            param_syms.append(p_sym)
            if contract is not None:
                param_contracts.append(contract)
            arg_idx += 1
            curr_p = cdr(curr_p)

        if isinstance(curr_p, Symbol):
            rest_param = curr_p
        elif curr_p is not NIL:
            raise SyntaxError(f"define/c invalid dotted parameter list: {curr_p!r}")

        return param_syms, param_contracts, rest_param

    @staticmethod
    def _parse_body_and_post(
        body_forms: List[Any],
    ) -> Tuple[Optional[Any], List[Any]]:
        if not body_forms:
            raise SyntaxError("define/c requires at least one body expression")
        first_form = body_forms[0]
        if isinstance(first_form, Symbol) and first_form.name in (
            ":post",
            "#:post",
        ):
            if len(body_forms) < 3:
                raise SyntaxError(
                    "define/c with #:post requires post predicate and body expression"
                )
            return body_forms[1], body_forms[2:]
        return None, body_forms

    @staticmethod
    def _build_assert_forms(
        fn_name: str, contracts: List[Tuple[int, Symbol, Any]]
    ) -> List[Any]:
        assert_forms: List[Any] = []
        for idx, p_sym, p_pred in contracts:
            call_form = Cons(
                Symbol.intern("%contract-assert"),
                Cons(
                    fn_name,
                    Cons(
                        idx,
                        Cons(
                            p_sym.name,
                            Cons(p_pred, Cons(p_sym, Cons(":caller", NIL))),
                        ),
                    ),
                ),
            )
            # Rebind parameter with wrapped or asserted value
            set_form = Cons(Symbol.intern("set!"), Cons(p_sym, Cons(call_form, NIL)))
            assert_forms.append(set_form)
        return assert_forms

    @staticmethod
    def _build_post_assert(fn_name: str, post_pred: Any, begin_body: Any) -> Any:
        res_sym = Symbol.intern("__alisp_res__")
        let_binding = Cons(Cons(res_sym, Cons(begin_body, NIL)), NIL)
        post_assert = Cons(
            Symbol.intern("%contract-assert"),
            Cons(
                fn_name,
                Cons(
                    False,
                    Cons(
                        "return",
                        Cons(
                            post_pred,
                            Cons(res_sym, Cons(":callee", NIL)),
                        ),
                    ),
                ),
            ),
        )
        return Cons(
            Symbol.intern("let"),
            Cons(let_binding, Cons(post_assert, Cons(res_sym, NIL))),
        )

    def transform(self, expr: Any, env: Any) -> Any:
        args = cdr(expr)
        if not is_pair(args) or not is_pair(car(args)):
            raise SyntaxError(
                "define/c requires header and body: (define/c (func-name (arg pred)...) body...)"
            )
        head = car(args)
        fn_name_sym = car(head)
        if not isinstance(fn_name_sym, Symbol):
            raise SyntaxError(
                f"define/c function name must be a symbol, got {fn_name_sym!r}"
            )

        param_syms, param_contracts, rest_param = self._parse_params(cdr(head))
        post_pred, actual_body = self._parse_body_and_post(to_py_list(cdr(args)))

        assert_forms = self._build_assert_forms(fn_name_sym.name, param_contracts)
        begin_body = Cons(Symbol.intern("begin"), to_lisp_list(actual_body))

        if post_pred is not None:
            final_body = assert_forms + [
                self._build_post_assert(fn_name_sym.name, post_pred, begin_body)
            ]
        else:
            final_body = assert_forms + [begin_body]

        def_params: Any = to_lisp_list(param_syms) if rest_param is None else rest_param
        if rest_param is not None:
            for p in reversed(param_syms):
                def_params = Cons(p, def_params)

        return Cons(
            Symbol.intern("define"),
            Cons(Cons(fn_name_sym, def_params), to_lisp_list(final_body)),
        )


__all__ = [
    "ContractViolationException",
    "contract_assert",
    "make_contract_assert_primitive",
    "DefineContractTransformer",
    "BlameParty",
    "Contract",
    "FlatContract",
    "FunctionContract",
    "ContractWrappedProcedure",
    "make_arrow_contract_primitive",
    "swap_blame",
]
