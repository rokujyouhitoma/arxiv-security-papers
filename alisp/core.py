"""ALisp Core Engine.

Main entry point for ALisp (Agent Lisp) execution environment, integrating
ILisp R7RS-small core with DIP StepInterceptor, Fuel metering, and Contracts.
"""

from __future__ import annotations

from typing import Any, Optional, Union

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


def make_alisp_env(interceptor: Optional[StepInterceptor] = None) -> Environment:
    """Create a new ILISP Environment equipped with ALisp primitives and macros."""
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

    return env


class ALispEngine:
    """ALisp Execution Engine with bounded autonomy guards and contract validation."""

    def __init__(
        self,
        default_fuel: Optional[int] = None,
        env: Optional[Environment] = None,
    ) -> None:
        self.default_fuel = default_fuel
        self.interceptor = StepInterceptor()
        self.evaluator = Evaluator(step_hook=self.interceptor)
        self.env = env if env is not None else make_alisp_env(self.interceptor)

    def eval(
        self,
        source: Union[str, Any],
        fuel: Optional[int] = None,
        timeout: Optional[float] = None,
    ) -> Any:
        """Evaluate an ALisp source string or AST under fuel and contract boundaries."""
        effective_fuel = fuel if fuel is not None else self.default_fuel

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
    ) -> Any:
        """Alias for eval."""
        return self.eval(source, fuel=fuel, timeout=timeout)

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
) -> Any:
    """Convenience function to evaluate an ALisp string or expression."""
    engine = ALispEngine(default_fuel=fuel, env=env)
    return engine.eval(source, timeout=timeout)
