"""ALisp (Agent Lisp) Execution Environment.

A security-first, contract-driven Lisp environment built on ILisp R7RS-small
for autonomous AI coding agents. Provides fuel metering, contract programming,
object-capability boundaries, and deterministic AST self-repair.
"""

from alisp.caps import (
    AccessDeniedException,
    Capability,
    CapabilityError,
    FileSystemCapability,
    ManagedBinaryInputPort,
    ManagedBinaryOutputPort,
    ManagedPortMixin,
    ManagedTextualInputPort,
    ManagedTextualOutputPort,
    NetworkCapability,
    PortQuotaExceededException,
    TaintedValue,
    TaintLeakViolationException,
    WithCapsTransformer,
    check_sink,
    get_active_capabilities,
    get_active_capability,
    is_tainted,
    make_loopback_binary_port,
    make_loopback_textual_port,
    taint,
    untaint,
    with_capabilities,
    wrap_managed_port,
)
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
    Transaction,
    WithFuelTransformer,
)
from alisp.repl import repl

__version__ = "0.1.0"

__all__ = [
    "ALispEngine",
    "eval_alisp",
    "make_alisp_env",
    "repl",
    "FuelExhaustedException",
    "FuelCounter",
    "StepInterceptor",
    "Transaction",
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
    # Phase 2: Object-Capability & Managed Port & Taint Tracking
    "Capability",
    "CapabilityError",
    "AccessDeniedException",
    "PortQuotaExceededException",
    "FileSystemCapability",
    "NetworkCapability",
    "ManagedPortMixin",
    "ManagedTextualOutputPort",
    "ManagedTextualInputPort",
    "ManagedBinaryOutputPort",
    "ManagedBinaryInputPort",
    "wrap_managed_port",
    "make_loopback_textual_port",
    "make_loopback_binary_port",
    "TaintedValue",
    "TaintLeakViolationException",
    "taint",
    "is_tainted",
    "untaint",
    "check_sink",
    "with_capabilities",
    "get_active_capability",
    "get_active_capabilities",
    "WithCapsTransformer",
]
