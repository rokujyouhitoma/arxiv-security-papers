"""Higher-Order Function Blame Tracking Engine.

Implements Findler & Felleisen (2002) higher-order contract monitoring with
rigorous Blame Assignment and Blame Inversion (Blame Swap) across higher-order boundaries.
"""

from __future__ import annotations

from typing import Any, List, Optional, Sequence, Tuple, Union

from alisp.contracts.predicates import _call_predicate
from ilisp.types import NIL, Primitive, Procedure, Symbol


class BlameParty:
    """Represents a principal or boundary participant responsible for contract satisfaction."""

    CALLER = ":caller"
    CALLEE = ":callee"

    def __init__(self, name: str) -> None:
        self.name = name

    def __str__(self) -> str:
        return self.name

    def __repr__(self) -> str:
        return f"BlameParty({self.name})"

    def __eq__(self, other: object) -> bool:
        if isinstance(other, BlameParty):
            return self.name == other.name
        if isinstance(other, str):
            return self.name == other
        if isinstance(other, Symbol):
            return self.name == other.name
        return False

    def __hash__(self) -> int:
        return hash(self.name)

    @classmethod
    def from_value(cls, val: Any) -> BlameParty:
        if isinstance(val, BlameParty):
            return val
        if isinstance(val, Symbol):
            return cls(val.name)
        return cls(str(val))


def swap_blame(
    positive: Union[str, BlameParty], negative: Union[str, BlameParty]
) -> Tuple[BlameParty, BlameParty]:
    """Swap positive (caller) and negative (callee) blame parties for higher-order domain checking."""
    pos = BlameParty.from_value(positive)
    neg = BlameParty.from_value(negative)
    return neg, pos


class Contract:
    """Base class for all contract specifications (Flat or Higher-Order)."""

    def check(
        self,
        val: Any,
        positive: BlameParty,
        negative: BlameParty,
        fn_name: str,
        arg_idx: Optional[int] = None,
    ) -> Any:
        raise NotImplementedError


class FlatContract(Contract):
    """Wraps a unary predicate as a flat first-order contract."""

    def __init__(self, predicate: Any, name: Optional[str] = None) -> None:
        self.predicate = predicate
        self.name = name or (
            getattr(predicate, "name", None)
            or getattr(predicate, "__name__", None)
            or str(predicate)
        )

    def check(
        self,
        val: Any,
        positive: BlameParty,
        negative: BlameParty,
        fn_name: str,
        arg_idx: Optional[int] = None,
    ) -> Any:
        try:
            ok = _call_predicate(self.predicate, val)
        except Exception:
            ok = False

        if not ok:
            # Domain violations blame positive (caller); Range violations blame positive (which is callee for range)
            from alisp.contracts import ContractViolationException

            blame_str = positive.name
            arg_str = f" argument index {arg_idx}" if arg_idx is not None else ""
            msg = (
                f"Contract violation: function '{fn_name}'{arg_str} "
                f"failed contract '{self.name}'. Received: {val!r}. Blame: {blame_str}"
            )
            raise ContractViolationException(
                message=msg,
                blame=blame_str,
                function_name=fn_name,
                argument_index=arg_idx,
                parameter_name="",
                expected=self.name,
                received=val,
            )
        return val

    def __repr__(self) -> str:
        return f"FlatContract({self.name})"


class FunctionContract(Contract):
    """Higher-order function contract: (-> dom1 dom2 ... rng).

    Enforces Findler-Felleisen blame semantics:
    - Domain contracts check inputs provided by the caller (positive blame).
    - Range contract checks output returned by the callee (negative blame becomes positive).
    - When a domain contract is itself a FunctionContract (a callback), the blame roles
      are swapped: if the callee misuses the callback's arguments, blame falls on the callee!
    """

    def __init__(
        self,
        domain_contracts: Sequence[Union[Contract, Any]],
        range_contract: Union[Contract, Any],
        name: Optional[str] = None,
    ) -> None:
        self.domain_contracts: List[Contract] = [
            c if isinstance(c, Contract) else FlatContract(c) for c in domain_contracts
        ]
        self.range_contract: Contract = (
            range_contract
            if isinstance(range_contract, Contract)
            else FlatContract(range_contract)
        )
        self.name = name or self._build_repr()

    def _build_repr(self) -> str:
        dom_strs = [getattr(c, "name", str(c)) for c in self.domain_contracts]
        rng_str = getattr(self.range_contract, "name", str(self.range_contract))
        return f"(-> {' '.join(dom_strs)} {rng_str})"

    def check(
        self,
        val: Any,
        positive: BlameParty,
        negative: BlameParty,
        fn_name: str,
        arg_idx: Optional[int] = None,
    ) -> Any:
        if not (callable(val) or isinstance(val, (Primitive, Procedure))):
            from alisp.contracts import ContractViolationException

            msg = (
                f"Contract violation: function '{fn_name}' expected procedure for "
                f"contract '{self.name}', got {val!r}. Blame: {positive.name}"
            )
            raise ContractViolationException(
                message=msg,
                blame=positive.name,
                function_name=fn_name,
                argument_index=arg_idx,
                expected=self.name,
                received=val,
            )

        return ContractWrappedProcedure(
            underlying=val,
            contract=self,
            positive=positive,
            negative=negative,
            fn_name=fn_name,
        )

    def __repr__(self) -> str:
        return self.name


class ContractWrappedProcedure:
    """A higher-order procedure proxy wrapped with a FunctionContract.

    Interceps invocations to verify domain arguments and return values with appropriate Blame attribution.
    """

    def __init__(
        self,
        underlying: Any,
        contract: FunctionContract,
        positive: BlameParty,
        negative: BlameParty,
        fn_name: str,
    ) -> None:
        self.underlying = underlying
        self.contract = contract
        self.positive = positive
        self.negative = negative
        self.fn_name = fn_name

    def __call__(self, *args: Any) -> Any:
        # Findler-Felleisen Blame Inversion for higher-order callback procedures:
        # - self.positive is the provider of this procedure (outer caller).
        # - self.negative is the consumer of this procedure who invokes it (outer callee).
        # Therefore:
        # - The arguments passed to this procedure are supplied by the consumer (self.negative).
        #   If an argument violates its domain contract, BLAME FALLS ON self.negative (:callee)!
        # - The result returned by this procedure is produced by the provider (self.positive).
        #   If the return value violates its range contract, BLAME FALLS ON self.positive (:caller)!
        dom_contracts = self.contract.domain_contracts
        if len(args) != len(dom_contracts):
            from alisp.contracts import ContractViolationException

            msg = (
                f"Arity mismatch in contract-wrapped procedure '{self.fn_name}': "
                f"expected {len(dom_contracts)} arguments, got {len(args)}. Blame: {self.negative.name}"
            )
            raise ContractViolationException(
                message=msg,
                blame=self.negative.name,
                function_name=self.fn_name,
                expected=f"{len(dom_contracts)} arguments",
                received=len(args),
            )

        checked_args: List[Any] = []
        for i, (arg, dom_c) in enumerate(zip(args, dom_contracts)):
            if isinstance(dom_c, FunctionContract):
                # When callback receives another callback as argument, swap roles again
                swapped_pos, swapped_neg = swap_blame(self.negative, self.positive)
                checked_arg = dom_c.check(
                    arg,
                    positive=swapped_pos,
                    negative=swapped_neg,
                    fn_name=f"{self.fn_name}_cb_arg{i+1}",
                    arg_idx=i + 1,
                )
            else:
                # Consumer supplied this argument -> positive blame party for argument check is self.negative!
                checked_arg = dom_c.check(
                    arg,
                    positive=self.negative,
                    negative=self.positive,
                    fn_name=self.fn_name,
                    arg_idx=i + 1,
                )
            checked_args.append(checked_arg)

        # Execute underlying procedure
        if isinstance(self.underlying, Primitive):
            result = self.underlying.fn(*checked_args)
        elif isinstance(self.underlying, Procedure):
            from ilisp.evaluator import _bind_procedure_call, eval_expr

            call_env = _bind_procedure_call(self.underlying, checked_args)
            result = NIL
            for step in self.underlying.body:
                result = eval_expr(step, call_env)
        elif callable(self.underlying):
            result = self.underlying(*checked_args)
        else:
            raise TypeError(f"Uncallable procedure: {self.underlying!r}")

        # Check range contract:
        # Result is produced by the provider (self.positive) -> positive blame party is self.positive!
        range_c = self.contract.range_contract
        if isinstance(range_c, FunctionContract):
            checked_result = range_c.check(
                result,
                positive=self.positive,
                negative=self.negative,
                fn_name=f"{self.fn_name}_result",
                arg_idx=None,
            )
        else:
            checked_result = range_c.check(
                result,
                positive=self.positive,
                negative=self.negative,
                fn_name=self.fn_name,
                arg_idx=None,
            )

        return checked_result


def make_arrow_contract_primitive() -> Primitive:
    """Scheme primitive `->` for constructing FunctionContract objects: (-> dom1 dom2 ... rng)."""

    def _arrow_prim(*parts: Any) -> FunctionContract:
        if len(parts) < 1:
            raise SyntaxError(
                "Function contract '->' requires at least a range predicate: (-> rng)"
            )
        if len(parts) == 1:
            return FunctionContract(domain_contracts=[], range_contract=parts[0])
        return FunctionContract(domain_contracts=parts[:-1], range_contract=parts[-1])

    return Primitive("->", _arrow_prim)
