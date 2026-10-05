"""Comprehensive unit tests for ILISP Python interop layer (Issue 480)."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

import ilisp
from ilisp.interop import (
    Evaluator,
    IlispModuleProxy,
    load_ilisp_module,
    load_module,
    register_import_hook,
    unregister_import_hook,
)


class TestIlispEval:
    """Tests for top-level ilisp.eval."""

    def test_immediate_arithmetic(self) -> None:
        assert ilisp.eval("(+ 1 2 3)") == 6
        assert ilisp.eval("(* 6 7)") == 42
        assert ilisp.eval("(- 10 3 2)") == 5

    def test_list_and_lambda_eval(self) -> None:
        res = ilisp.eval("((lambda (x y) (+ x y)) 10 20)")
        assert res == 30

    def test_eval_with_custom_env(self) -> None:
        env = ilisp.make_initial_env()
        ilisp.eval("(define custom-val 100)", env=env)
        assert ilisp.eval("(* custom-val 2)", env=env) == 200

    def test_eval_py_ast_backend(self) -> None:
        res = ilisp.eval("(+ 10 20)", backend="py_ast")
        assert res == 30


class TestEvaluator:
    """Tests for stateful Evaluator session."""

    def test_session_state_persistence(self) -> None:
        ev = Evaluator()
        ev.eval("(define counter 10)")
        assert ev.eval("(+ counter 5)") == 15
        ev.eval("(set! counter (+ counter 1))")
        assert ev.eval("counter") == 11

    def test_get_and_set(self) -> None:
        ev = Evaluator()
        ev.set("x", 42)
        assert ev.get("x") == 42
        assert ev.eval("x") == 42

        # Update via set
        ev.set("x", 99)
        assert ev.get("x") == 99

    def test_kebab_snake_case_fallback(self) -> None:
        ev = Evaluator()
        ev.eval("(define threat-level 'critical)")
        # Access via snake_case
        assert str(ev.get("threat_level")) == "critical"
        # Access via kebab-case
        assert str(ev.get("threat-level")) == "critical"

        # Reverse: defined with snake_case, access with kebab
        ev.eval('(define cve_id "CVE-2026-9999")')
        assert ev.get("cve-id") == "CVE-2026-9999"

    def test_call_scheme_procedure(self) -> None:
        ev = Evaluator()
        ev.eval("(define (add3 a b c) (+ a b c))")
        assert ev.call("add3", 1, 2, 3) == 6

        # Call with snake_case name for kebab-case procedure
        ev.eval("(define (calc-score x) (* x 2))")
        assert ev.call("calc_score", 21) == 42

    def test_get_unbound_raises_name_error(self) -> None:
        ev = Evaluator()
        with pytest.raises(NameError, match="not bound in ILISP environment"):
            ev.get("non_existent_symbol")

    def test_call_non_callable_raises_type_error(self) -> None:
        ev = Evaluator()
        ev.set("not_a_fn", 123)
        with pytest.raises(TypeError, match="not callable"):
            ev.call("not_a_fn", 1)


class TestIlispModuleLoading:
    """Tests for load_ilisp_module and IlispModuleProxy."""

    def test_load_module_and_proxy_attributes(self, tmp_path: Path) -> None:
        code = """
(define module-name "crypto-tools")
(define base-score 100)
(define (encrypt-token val key)
  (+ val key))
(define (get-status)
  'ok)
"""
        mod_file = tmp_path / "crypto_tools.ilisp"
        mod_file.write_text(code, encoding="utf-8")

        proxy = load_ilisp_module(mod_file)
        assert isinstance(proxy, IlispModuleProxy)

        # Attribute access with kebab/snake conversion
        assert proxy.module_name == "crypto-tools"
        assert proxy.base_score == 100

        # Procedure invocation via proxy attribute
        assert proxy.encrypt_token(10, 5) == 15
        assert str(proxy.get_status()) == "ok"

        # Dictionary-style item access
        assert proxy["module-name"] == "crypto-tools"
        assert proxy["module_name"] == "crypto-tools"

        # Internal eval within proxy's environment
        assert proxy.eval("(+ base-score 50)") == 150

        # Inspection / dir() support
        dir_keys = dir(proxy)
        assert "module_name" in dir_keys or "module-name" in dir_keys
        assert "encrypt_token" in dir_keys or "encrypt-token" in dir_keys

    def test_load_module_alias(self, tmp_path: Path) -> None:
        mod_file = tmp_path / "simple.scm"
        mod_file.write_text("(define answer 42)", encoding="utf-8")
        proxy = load_module(mod_file)
        assert proxy.answer == 42

    def test_file_not_found(self) -> None:
        with pytest.raises(FileNotFoundError):
            load_ilisp_module("/non/existent/path/file.ilisp")

    def test_is_directory_error(self, tmp_path: Path) -> None:
        with pytest.raises(IsADirectoryError):
            load_ilisp_module(tmp_path)


class TestPythonInteropBidirectional:
    """Tests for passing Python functions/objects into Scheme and calling back."""

    def test_pass_python_function_to_evaluator(self) -> None:
        ev = Evaluator()

        def py_hasher(s: str) -> str:
            return f"hash:{s}"

        ev.set("py-hash", py_hasher)
        result = ev.eval('(py-hash "secret")')
        assert result == "hash:secret"

    def test_higher_order_callback(self) -> None:
        ev = Evaluator()
        logs: list[int] = []

        def record(val: int) -> int:
            logs.append(val)
            return val * 10

        ev.set("record", record)
        ev.eval("""
(define (process-items lst)
  (map record lst))
""")
        res = ev.call("process_items", [1, 2, 3])
        # res can be a Cons list or list; let's verify logs and items
        assert logs == [1, 2, 3]
        assert list(res) == [10, 20, 30]


class TestTransparentImportHook:
    """Tests for sys.meta_path transparent import hooks."""

    def test_register_and_unregister_hook(self) -> None:
        # Initial cleanup just in case
        unregister_import_hook()

        # Register
        assert register_import_hook() is True
        # Double registration returns False (idempotent)
        assert register_import_hook() is False

        # Unregister
        assert unregister_import_hook() is True
        # Double unregister returns False
        assert unregister_import_hook() is False

    def test_import_ilisp_file(self, tmp_path: Path) -> None:
        unregister_import_hook()
        register_import_hook()

        mod_code = """
(define app-version "2.4.0")
(define (calculate-hash text)
  (string-append "sha256:" text))
(define (verify-token token)
  (equal? token "valid-token"))
"""
        mod_file = tmp_path / "threat_scanner.ilisp"
        mod_file.write_text(mod_code, encoding="utf-8")

        sys.path.insert(0, str(tmp_path))
        try:
            # Import dynamically
            import threat_scanner  # type: ignore[import-not-found]

            assert threat_scanner.app_version == "2.4.0"
            assert threat_scanner.calculate_hash("data") == "sha256:data"
            assert threat_scanner.verify_token("valid-token") is True
            assert threat_scanner.verify_token("bad-token") is False

            # Eval method attached to module
            assert threat_scanner.eval("(+ 1 2)") == 3

        finally:
            if str(tmp_path) in sys.path:
                sys.path.remove(str(tmp_path))
            if "threat_scanner" in sys.modules:
                del sys.modules["threat_scanner"]
            unregister_import_hook()
