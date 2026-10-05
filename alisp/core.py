"""ALisp Core Engine.

Main entry point for ALisp (Agent Lisp) execution environment, integrating
ILisp R7RS-small core with DIP StepInterceptor, Fuel metering, Contracts,
and Object-Capability (OCaps) sandbox security boundaries.
"""

from __future__ import annotations

from typing import Any, Optional, Sequence, Union

from alisp.caps import (
    Capability,
    WithCapsTransformer,
    install_sandboxed_file_primitives,
    is_tainted,
    make_attenuate_cap_primitive,
    make_fs_cap_primitive,
    make_net_cap_primitive,
    make_with_caps_primitive,
    taint,
    untaint,
    with_capabilities,
)
from alisp.contracts import DefineContractTransformer, make_contract_assert_primitive
from alisp.contracts.predicates import (
    any_c,
    make_and_c_primitive,
    make_equal_c_primitive,
    make_not_c_primitive,
    make_or_c_primitive,
    none_c,
)
from alisp.metering import (
    StepInterceptor,
    WithFuelTransformer,
    make_with_fuel_primitive,
)
from ilisp.env import Environment, make_initial_env
from ilisp.evaluator import Evaluator
from ilisp.reader import read_all
from ilisp.types import NIL, Primitive, Symbol


def make_alisp_env(
    interceptor: Optional[StepInterceptor] = None,
    sandbox: bool = True,
    initial_caps: Optional[Sequence[Capability]] = None,
) -> Environment:
    """Create a new ILISP Environment equipped with ALisp primitives, contracts, and capability sandbox."""
    env = make_initial_env(preload_stdlib=True)
    active_interceptor = interceptor if interceptor is not None else StepInterceptor()

    # Register Fuel primitives and macros
    env.define(
        Symbol.intern("%with-fuel"),
        make_with_fuel_primitive(active_interceptor),
    )
    env.define(Symbol.intern("with-fuel"), WithFuelTransformer())

    # Register Contract primitives and macros
    env.define(Symbol.intern("%contract-assert"), make_contract_assert_primitive())
    env.define(Symbol.intern("define/c"), DefineContractTransformer())

    # Register Predicate combinators
    env.define(Symbol.intern("and/c"), make_and_c_primitive())
    env.define(Symbol.intern("or/c"), make_or_c_primitive())
    env.define(Symbol.intern("not/c"), make_not_c_primitive())
    env.define(Symbol.intern("any/c"), Primitive("any/c", any_c))
    env.define(Symbol.intern("none/c"), Primitive("none/c", none_c))
    env.define(Symbol.intern("equal/c"), make_equal_c_primitive())

    # Register Object-Capability primitives and macros (Phase 2)
    env.define(Symbol.intern("%with-caps"), make_with_caps_primitive())
    env.define(Symbol.intern("with-caps"), WithCapsTransformer())
    env.define(Symbol.intern("make-fs-cap"), make_fs_cap_primitive())
    env.define(Symbol.intern("make-net-cap"), make_net_cap_primitive())
    env.define(Symbol.intern("attenuate-cap"), make_attenuate_cap_primitive())

    # Register Taint Tracking primitives
    env.define(Symbol.intern("taint"), Primitive("taint", taint))
    env.define(Symbol.intern("tainted?"), Primitive("tainted?", is_tainted))
    env.define(Symbol.intern("untaint"), Primitive("untaint", untaint))

    # Apply sandbox: guard destructive I/O unless permitted by Capability
    if sandbox:
        install_sandboxed_file_primitives(env)

    return env


class ALispEngine:
    """ALisp Execution Engine with bounded autonomy guards, contracts, and OCaps sandbox."""

    def __init__(
        self,
        default_fuel: Optional[int] = None,
        env: Optional[Environment] = None,
        sandbox: bool = True,
        initial_caps: Optional[Sequence[Capability]] = None,
    ) -> None:
        self.default_fuel = default_fuel
        self.sandbox = sandbox
        self.initial_caps = list(initial_caps) if initial_caps is not None else []
        self.interceptor = StepInterceptor()
        self.evaluator = Evaluator(step_hook=self.interceptor)
        self.env = (
            env
            if env is not None
            else make_alisp_env(
                self.interceptor,
                sandbox=sandbox,
                initial_caps=self.initial_caps,
            )
        )

    def eval(
        self,
        source: Union[str, Any],
        fuel: Optional[int] = None,
        timeout: Optional[float] = None,
        caps: Optional[Sequence[Capability]] = None,
    ) -> Any:
        """Evaluate an ALisp source string or AST under fuel, contract, and capability boundaries."""
        effective_fuel = fuel if fuel is not None else self.default_fuel
        effective_caps = list(self.initial_caps)
        if caps is not None:
            effective_caps.extend(caps)

        if effective_caps:
            with with_capabilities(effective_caps):
                return self._eval_with_fuel(source, effective_fuel, timeout)
        else:
            return self._eval_with_fuel(source, effective_fuel, timeout)

    def _eval_with_fuel(
        self,
        source: Union[str, Any],
        effective_fuel: Optional[int],
        timeout: Optional[float],
    ) -> Any:
        if effective_fuel is not None:
            with self.interceptor.with_fuel_scope(
                effective_fuel, timeout_seconds=timeout
            ):
                return self._eval_internal(source)
        else:
            return self._eval_internal(source)

    def run(
        self,
        source: Union[str, Any],
        fuel: Optional[int] = None,
        timeout: Optional[float] = None,
        caps: Optional[Sequence[Capability]] = None,
    ) -> Any:
        """Alias for eval."""
        return self.eval(source, fuel=fuel, timeout=timeout, caps=caps)

    def _eval_internal(self, source: Union[str, Any]) -> Any:
        if isinstance(source, str):
            ast_list = read_all(source)
            if not ast_list:
                return NIL
            result: Any = NIL
            for ast in ast_list:
                result = self.evaluator.eval(ast, self.env)
            return result
        else:
            return self.evaluator.eval(source, self.env)


def eval_alisp(
    source: Union[str, Any],
    env: Optional[Environment] = None,
    fuel: Optional[int] = None,
    timeout: Optional[float] = None,
    caps: Optional[Sequence[Capability]] = None,
    sandbox: bool = True,
) -> Any:
    """Convenience function to evaluate an ALisp string or expression."""
    engine = ALispEngine(default_fuel=fuel, env=env, sandbox=sandbox, initial_caps=caps)
    return engine.eval(source, timeout=timeout)
