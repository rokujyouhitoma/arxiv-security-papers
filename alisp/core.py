"""ALisp Core Engine.

Main entry point for ALisp (Agent Lisp) execution environment, integrating
ILisp R7RS-small core with DIP StepInterceptor, Fuel metering, Contracts,
and Object-Capability (OCaps) sandbox security boundaries.
"""

from __future__ import annotations

from typing import Any, Optional, Sequence, Union

from alisp.caps import (
    AccessDeniedException,
    Capability,
    WithCapsTransformer,
    install_sandboxed_file_primitives,
    install_sandboxed_py_primitives,
    is_tainted,
    make_attenuate_cap_primitive,
    make_fs_cap_primitive,
    make_net_cap_primitive,
    make_with_caps_primitive,
    taint,
    untaint,
    with_capabilities,
)
from alisp.contracts import (
    ContractViolationException,
    DefineContractTransformer,
    make_arrow_contract_primitive,
    make_contract_assert_primitive,
)
from alisp.contracts.predicates import (
    any_c,
    make_and_c_primitive,
    make_equal_c_primitive,
    make_not_c_primitive,
    make_or_c_primitive,
    none_c,
)
from alisp.metering import (
    FuelExhaustedException,
    MemoryQuotaExceededException,
    StepInterceptor,
    WithFuelTransformer,
    make_with_fuel_primitive,
    with_memory_quota,
    with_wall_clock_timeout,
)
from alisp.repair import (
    Diagnostic,
    apply_patch,
    format_diagnostic,
    make_patch_primitive,
)
from alisp.telemetry import AuditEventType, record_audit_event, with_trace
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
    env.define(Symbol.intern("->"), make_arrow_contract_primitive())

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

    # Register Self-Repair primitives (Phase 3)
    env.define(Symbol.intern("patch"), make_patch_primitive())

    # Apply sandbox: guard destructive I/O and unsafe Python FFI
    if sandbox:
        install_sandboxed_file_primitives(env)
        install_sandboxed_py_primitives(env)

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
        memory_limit: Optional[int] = None,
        caps: Optional[Sequence[Capability]] = None,
        trace_id: Optional[str] = None,
    ) -> Any:
        """Evaluate an ALisp source string or AST under fuel, contract, capability, and physical resource boundaries."""
        effective_fuel = fuel if fuel is not None else self.default_fuel
        effective_caps = list(self.initial_caps)
        if caps is not None:
            effective_caps.extend(caps)

        with with_trace(trace_id=trace_id) as active_trace:
            record_audit_event(
                AuditEventType.EVAL_START,
                "ALisp evaluation started",
                details={
                    "fuel_limit": effective_fuel,
                    "timeout": timeout,
                    "memory_limit": memory_limit,
                    "sandbox": self.sandbox,
                },
                trace_id=active_trace,
            )
            try:
                with with_wall_clock_timeout(timeout):
                    with with_memory_quota(
                        memory_limit if memory_limit is not None else 0
                    ):
                        if effective_caps:
                            with with_capabilities(effective_caps):
                                res = self._eval_with_fuel(
                                    source, effective_fuel, timeout
                                )
                        else:
                            res = self._eval_with_fuel(source, effective_fuel, timeout)

                record_audit_event(
                    AuditEventType.EVAL_SUCCESS,
                    "ALisp evaluation completed successfully",
                    details={"result_type": type(res).__name__},
                    trace_id=active_trace,
                )
                return res
            except FuelExhaustedException as e:
                record_audit_event(
                    AuditEventType.FUEL_EXHAUSTED,
                    str(e),
                    details={"consumed": e.steps, "limit": e.limit},
                    trace_id=active_trace,
                )
                raise
            except ContractViolationException as e:
                blame_val = (
                    getattr(e.blame, "value", str(e.blame))
                    if hasattr(e, "blame") and e.blame is not None
                    else None
                )
                record_audit_event(
                    AuditEventType.CONTRACT_VIOLATION,
                    str(e),
                    details={"blame": blame_val},
                    trace_id=active_trace,
                )
                raise
            except AccessDeniedException as e:
                record_audit_event(
                    AuditEventType.ACCESS_DENIED,
                    str(e),
                    trace_id=active_trace,
                )
                raise
            except TimeoutError as e:
                record_audit_event(
                    AuditEventType.TIMEOUT,
                    str(e),
                    details={"timeout": timeout},
                    trace_id=active_trace,
                )
                raise
            except MemoryQuotaExceededException as e:
                record_audit_event(
                    AuditEventType.MEMORY_LIMIT_EXCEEDED,
                    str(e),
                    details={"memory_limit": memory_limit},
                    trace_id=active_trace,
                )
                raise
            except Exception as e:
                record_audit_event(
                    AuditEventType.EXCEPTION,
                    str(e),
                    details={"exception_type": type(e).__name__},
                    trace_id=active_trace,
                )
                raise

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
        memory_limit: Optional[int] = None,
        caps: Optional[Sequence[Capability]] = None,
        trace_id: Optional[str] = None,
    ) -> Any:
        """Alias for eval."""
        return self.eval(
            source,
            fuel=fuel,
            timeout=timeout,
            memory_limit=memory_limit,
            caps=caps,
            trace_id=trace_id,
        )

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

    def apply_patch(
        self,
        ast: Any,
        patch_spec: Any,
    ) -> Any:
        """Apply an atomic CAS patch to an AST using S-Path deterministic selection."""
        return apply_patch(ast, patch_spec)

    def diagnose(
        self,
        exc: Exception,
        ast: Optional[Any] = None,
    ) -> Diagnostic:
        """Generate a structured S-expression diagnostic for an exception."""
        return format_diagnostic(exc, ast=ast)


def eval_alisp(
    source: Union[str, Any],
    env: Optional[Environment] = None,
    fuel: Optional[int] = None,
    timeout: Optional[float] = None,
    memory_limit: Optional[int] = None,
    caps: Optional[Sequence[Capability]] = None,
    sandbox: bool = True,
    trace_id: Optional[str] = None,
) -> Any:
    """Convenience function to evaluate an ALisp string or expression."""
    engine = ALispEngine(default_fuel=fuel, env=env, sandbox=sandbox, initial_caps=caps)
    return engine.eval(
        source,
        timeout=timeout,
        memory_limit=memory_limit,
        trace_id=trace_id,
    )
