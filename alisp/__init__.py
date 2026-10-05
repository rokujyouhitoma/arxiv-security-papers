"""ALisp (Agent Lisp) Execution Environment.

A security-first, contract-driven Lisp environment built on ILisp R7RS-small
for autonomous AI coding agents. Provides fuel metering, contract programming,
object-capability boundaries, and deterministic AST self-repair.
"""

from alisp.contracts import (
    ContractViolationException,
    DefineContractTransformer,
    contract_assert,
)
from alisp.contracts.predicates import and_c, any_c, equal_c, none_c, not_c, or_c
from alisp.core import ALispEngine, eval_alisp, make_alisp_env
from alisp.metering import (
    FuelCounter,
    FuelExhaustedException,
    StepInterceptor,
    WithFuelTransformer,
)

__version__ = "0.1.0"

__all__ = [
    "ALispEngine",
    "eval_alisp",
    "make_alisp_env",
    "FuelExhaustedException",
    "FuelCounter",
    "StepInterceptor",
    "WithFuelTransformer",
    "ContractViolationException",
    "DefineContractTransformer",
    "contract_assert",
    "and_c",
    "or_c",
    "not_c",
    "any_c",
    "none_c",
    "equal_c",
]
