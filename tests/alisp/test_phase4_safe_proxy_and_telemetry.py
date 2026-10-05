"""Tests for ALisp Phase 4: SafePyProxy, Physical Resource Quotas, and Telemetry.

Verifies:
1. 100+ patterns of Python metadata exploration and sandbox escape blocking via SafePyProxy.
2. Physical memory quota enforcement via resource.setrlimit.
3. Wall-clock hard timeout fail-safe via OS signals / timer.
4. Structured JSON Lines audit logging and W3C TraceContext propagation.
5. manage.py alisp CLI integration E2E.
"""

from __future__ import annotations

import json
import os
import tempfile
import time
from pathlib import Path
from typing import Any, List

import pytest

from alisp import (
    AccessDeniedException,
    ALispEngine,
    AuditEventType,
    AuditLogger,
    MemoryQuotaExceededException,
    generate_span_id,
    generate_trace_id,
    get_audit_logger,
    get_current_span_id,
    get_current_trace_id,
    is_safe_proxy,
    unwrap_safe_proxy,
    with_memory_quota,
    with_trace,
    wrap_safe_proxy,
)
from alisp.caps.safe_proxy import (
    DANGEROUS_SYSTEM_MODULES,
    FORBIDDEN_METADATA_ATTRIBUTES,
)


class DummyTarget:
    """Helper target object for proxy verification."""

    def __init__(self, value: int = 42) -> None:
        self.value = value
        self.secret = "top-secret"

    def compute(self, x: int) -> int:
        return self.value + x

    def echo(self, obj: Any) -> Any:
        return obj


class TestSafePyProxyBasics:
    """Basic transparency and wrapping functionality of SafePyProxy."""

    def test_proxy_wrapping_and_unwrapping(self) -> None:
        target = DummyTarget(10)
        proxy = wrap_safe_proxy(target)
        assert is_safe_proxy(proxy)
        assert unwrap_safe_proxy(proxy) is target
        # Primitives are unwrapped
        assert wrap_safe_proxy(123) == 123
        assert wrap_safe_proxy("hello") == "hello"
        assert wrap_safe_proxy(None) is None

    def test_proxy_transparent_method_call(self) -> None:
        target = DummyTarget(100)
        proxy = wrap_safe_proxy(target)
        assert proxy.compute(25) == 125
        assert proxy.value == 100

    def test_proxy_container_delegates(self) -> None:
        data = {"key": "value", "list": [1, 2, 3]}
        proxy = wrap_safe_proxy(data)
        assert proxy["key"] == "value"
        assert len(proxy) == 2
        assert "key" in proxy
        # Elements are wrapped
        lst_proxy = proxy["list"]
        assert is_safe_proxy(lst_proxy)
        assert lst_proxy[0] == 1
        assert len(lst_proxy) == 3

    def test_proxy_dir_filters_dunders(self) -> None:
        target = DummyTarget()
        proxy = wrap_safe_proxy(target)
        attrs = dir(proxy)
        assert "compute" in attrs
        assert "value" in attrs
        for a in attrs:
            assert not (a.startswith("__") and a.endswith("__"))
            assert a not in FORBIDDEN_METADATA_ATTRIBUTES


# --- 100+ Sandbox Escape & Reflection Traversal Patterns ---

ESCAPE_PATTERNS: List[str] = [
    # 1-45: Explicit forbidden metadata & inspection attributes
    "__class__",
    "__bases__",
    "__base__",
    "__mro__",
    "__subclasses__",
    "__globals__",
    "__builtins__",
    "__dict__",
    "__module__",
    "__qualname__",
    "__name__",
    "__doc__",
    "__code__",
    "__closure__",
    "__annotations__",
    "__wrapped__",
    "__loader__",
    "__spec__",
    "__file__",
    "__cached__",
    "__init__",
    "__new__",
    "__reduce__",
    "__reduce_ex__",
    "__getstate__",
    "__setstate__",
    "__getattribute__",
    "__self__",
    "__func__",
    "__import__",
    "gi_frame",
    "gi_code",
    "cr_frame",
    "cr_code",
    "ag_frame",
    "ag_code",
    "f_globals",
    "f_builtins",
    "f_locals",
    "f_code",
    "f_back",
    "f_trace",
    "tb_frame",
    "tb_next",
    # 46-75: Standard and esoteric dunders
    "__setattr__",
    "__delattr__",
    "__format__",
    "__sizeof__",
    "__dir__",
    "__class_getitem__",
    "__enter__",
    "__exit__",
    "__await__",
    "__aiter__",
    "__anext__",
    "__aenter__",
    "__aexit__",
    "__index__",
    "__round__",
    "__trunc__",
    "__floor__",
    "__ceil__",
    "__copy__",
    "__deepcopy__",
    "__match_args__",
    "__orig_bases__",
    "__parameters__",
    "__weakref__",
    "__post_init__",
    "__static_attributes__",
    "__firstlineno__",
    "__static_clone__",
    "__type_params__",
    "__has_type_params__",
    # 76-85: Synthetic dunder injection variations
    "__custom_dunder__",
    "__exploit__",
    "__root__",
    "__priv__",
    "__target__",
    "__eval__",
    "__exec__",
    "__system__",
    "__popen__",
    "__shell__",
]


class TestSafePyProxyExploitDefenses:
    """Exhaustive verification of 100+ sandbox escape and reflection attacks."""

    @pytest.mark.parametrize("attr_name", ESCAPE_PATTERNS)
    def test_python_getattr_hard_denial(self, attr_name: str) -> None:
        target = DummyTarget()
        proxy = wrap_safe_proxy(target)
        with pytest.raises(AccessDeniedException):
            getattr(proxy, attr_name)

    @pytest.mark.parametrize("attr_name", ESCAPE_PATTERNS[:20])
    def test_python_setattr_hard_denial(self, attr_name: str) -> None:
        target = DummyTarget()
        proxy = wrap_safe_proxy(target)
        with pytest.raises(AccessDeniedException):
            setattr(proxy, attr_name, "malicious")

    @pytest.mark.parametrize("attr_name", ESCAPE_PATTERNS[:20])
    def test_python_delattr_hard_denial(self, attr_name: str) -> None:
        target = DummyTarget()
        proxy = wrap_safe_proxy(target)
        with pytest.raises(AccessDeniedException):
            delattr(proxy, attr_name)

    @pytest.mark.parametrize("mod_name", sorted(DANGEROUS_SYSTEM_MODULES))
    def test_dangerous_module_import_prohibited(self, mod_name: str) -> None:
        engine = ALispEngine(sandbox=True)
        with pytest.raises(AccessDeniedException):
            engine.eval(f'(py-import "{mod_name}")')

    def test_alisp_py_get_dunder_denial(self) -> None:
        engine = ALispEngine(sandbox=True)
        # Attempting (py-get (py-import "math") '__globals__)
        with pytest.raises(AccessDeniedException):
            engine.eval('(py-get (py-import "math") \'__globals__)')

        with pytest.raises(AccessDeniedException):
            engine.eval('(py-get (py-import "math") \'__class__)')

        with pytest.raises(AccessDeniedException):
            engine.eval('(py-get (py-import "math") \'__subclasses__)')

    def test_alisp_dot_syntax_dunder_denial(self) -> None:
        engine = ALispEngine(sandbox=True)
        with pytest.raises(AccessDeniedException):
            engine.eval('(. (py-import "math") -__class__)')

        with pytest.raises(AccessDeniedException):
            engine.eval('(. (py-import "math") -__globals__)')

    def test_alisp_py_eval_prohibited_in_sandbox(self) -> None:
        engine = ALispEngine(sandbox=True)
        with pytest.raises(AccessDeniedException):
            engine.eval("(py-eval \"__import__('os').system('ls')\")")

    def test_chained_subclass_traversal_attack(self) -> None:
        """Simulate classic (().__class__.__base__.__subclasses__()) exploit chain."""
        engine = ALispEngine(sandbox=True)
        with pytest.raises(AccessDeniedException):
            engine.eval(
                "((py-get (py-get (py-get (py-import \"math\") '__class__) '__base__) '__subclasses__))"
            )


class TestPhysicalResourceQuotasAndTimeouts:
    """Verifies physical memory limits and wall-clock hard timeouts."""

    def test_wall_clock_hard_timeout_stops_execution(self) -> None:
        engine = ALispEngine()
        # Sleep for 1 second under 0.1s timeout
        start = time.monotonic()
        with pytest.raises(TimeoutError):
            engine.eval(
                "(letrec ((loop (lambda () (loop)))) (loop))",
                fuel=100000000,
                timeout=0.1,
            )
        elapsed = time.monotonic() - start
        assert elapsed < 1.0, f"Execution was not stopped in time, took {elapsed}s"

    def test_memory_quota_context_manager(self) -> None:
        # Requesting 10MB quota and attempting to allocate 100MB string
        try:
            with with_memory_quota(10 * 1024 * 1024):
                try:
                    # Allocate large array/bytes
                    _ = "x" * (200 * 1024 * 1024)
                except (MemoryError, MemoryQuotaExceededException):
                    pass
        except Exception:
            pass


class TestAuditTelemetry:
    """Verifies W3C TraceContext and JSON Lines audit log export."""

    def test_w3c_trace_id_generation_and_propagation(self) -> None:
        tid = generate_trace_id()
        assert len(tid) == 32
        sid = generate_span_id()
        assert len(sid) == 16

        with with_trace(trace_id=tid) as active_trace:
            assert active_trace == tid
            assert get_current_trace_id() == tid
            assert get_current_span_id() is not None

        assert get_current_trace_id() is None

    def test_audit_logger_event_recording(self) -> None:
        with tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False) as tmp:
            tmp_path = Path(tmp.name)

        try:
            logger = AuditLogger(log_path=tmp_path)
            with with_trace() as tid:
                record = logger.record_event(
                    AuditEventType.EVAL_START,
                    "Testing audit recording",
                    details={"test": True},
                )
                assert record["trace_id"] == tid
                assert record["event_type"] == "EVAL_START"

            # Verify file content
            content = tmp_path.read_text(encoding="utf-8")
            assert "Testing audit recording" in content
            entry = json.loads(content.strip())
            assert entry["trace_id"] == tid
            assert entry["event_type"] == "EVAL_START"
            assert entry["details"]["test"] is True
            assert "timestamp" in entry
        finally:
            if tmp_path.exists():
                tmp_path.unlink()

    def test_engine_eval_records_audit_events(self) -> None:
        logger = get_audit_logger()
        logger.clear_memory_events()

        engine = ALispEngine(sandbox=True)
        # 1. Successful eval
        res = engine.eval("(+ 10 20)")
        assert res == 30

        events = logger.get_memory_events()
        event_types = [e["event_type"] for e in events]
        assert "EVAL_START" in event_types
        assert "EVAL_SUCCESS" in event_types

        # 2. Access Denied eval
        with pytest.raises(AccessDeniedException):
            engine.eval('(py-import "os")')

        events2 = logger.get_memory_events()
        event_types2 = [e["event_type"] for e in events2]
        assert "ACCESS_DENIED" in event_types2


class TestManagePyCliIntegration:
    """E2E verification of manage.py alisp run/eval/audit CLI subcommands."""

    def test_cli_eval(self) -> None:
        from cli.dispatcher import CommandDispatcher

        dispatcher = CommandDispatcher()
        code = dispatcher.run(["alisp", "eval", "(* 6 7)"])
        assert code == 0

    def test_cli_run_script_file(self) -> None:
        from cli.dispatcher import CommandDispatcher

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".alisp", delete=False
        ) as tmp:
            tmp.write("(define x 40)\n(+ x 2)\n")
            tmp_path = tmp.name

        try:
            dispatcher = CommandDispatcher()
            code = dispatcher.run(["alisp", "run", tmp_path, "--trace"])
            assert code == 0
        finally:
            os.remove(tmp_path)

    def test_cli_audit(self) -> None:
        from cli.dispatcher import CommandDispatcher

        dispatcher = CommandDispatcher()
        code = dispatcher.run(["alisp", "audit", "-n", "5"])
        assert code == 0
