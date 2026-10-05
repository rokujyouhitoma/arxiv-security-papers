"""Tests for ALisp Phase 3: S-Path Deterministic AST Patch, CAS, and Self-Repair.

Verifies:
- S-Path parsing and deterministic AST tree navigation without lexical ambiguity.
- Precise pinpoint replacement when multiple identical function signatures exist.
- CAS (Compare-And-Swap) verification: rejection of replacement on mismatch.
- S-expression structured diagnostic generation (DSN-32 Section 6.1).
- Macro expansion source location inversion (Source Location Inversion).
- Higher-Order Contract Blame Tracking: Blame Swap between caller and callee.
- ALispEngine and Scheme runtime integration.
"""

from __future__ import annotations

import pytest

from alisp import (
    ALispEngine,
    CasMismatchError,
    ContractViolationException,
    Diagnostic,
    PatchSpec,
    SPath,
    apply_patch,
    format_diagnostic,
    invert_source_location,
    is_ast_equal,
    parse_spath,
    resolve_spath,
)
from ilisp.reader import read_one
from ilisp.types import SourceLocation, Symbol, car


class TestSPathNavigation:
    """Test S-Path parsing and deterministic AST navigation."""

    def test_parse_spath_formats(self) -> None:
        # String format
        p1 = parse_spath("(root 2 3 1)")
        assert p1.elements == ("root", 2, 3, 1)

        # target-path wrapper
        p2 = parse_spath("(target-path (root 1 2))")
        assert p2.elements == ("root", 1, 2)

        # Python list
        p3 = parse_spath(["root", 0, 1])
        assert p3.elements == ("root", 0, 1)

        # S-expression directly
        sexpr = read_one("(root 2 1)")
        p4 = parse_spath(sexpr)
        assert p4.elements == ("root", 2, 1)

    def test_resolve_spath_nested_list(self) -> None:
        # (define (fetch-paper-chunk id limit) (+ id limit))
        ast = read_one("(define (fetch-paper-chunk id limit) (+ id limit))")
        # Path (root 2 1):
        # 0: define
        # 1: (fetch-paper-chunk id limit)
        # 2: (+ id limit) -> 2 1: id
        cursor = resolve_spath(ast, "(root 2 1)")
        assert isinstance(cursor.node, Symbol)
        assert cursor.node.name == "id"

    def test_disambiguate_identical_call_signatures(self) -> None:
        """Verify that when multiple identical function calls exist, S-Path targets only the exact one."""
        # Code with two identical calls to (fetch id limit)
        code = """
        (define (process-papers id limit)
          (let ((chunk1 (fetch id limit))
                (chunk2 (fetch id limit)))
            (combine chunk1 chunk2)))
        """
        ast = read_one(code)
        # Let bindings is index 2 of define form:
        # form[2] = (let ((chunk1 (fetch id limit)) (chunk2 (fetch id limit))) (combine chunk1 chunk2))
        # let bindings: form[2][1] = ((chunk1 (fetch id limit)) (chunk2 (fetch id limit)))
        # binding 0: (chunk1 (fetch id limit)) -> chunk1 expr: form[2][1][0][1] = (fetch id limit)
        # binding 1: (chunk2 (fetch id limit)) -> chunk2 expr: form[2][1][1][1] = (fetch id limit)

        cursor1 = resolve_spath(ast, "(root 2 1 0 1)")
        cursor2 = resolve_spath(ast, "(root 2 1 1 1)")

        assert is_ast_equal(cursor1.node, cursor2.node)
        # They point to different parents/accessors
        assert cursor1.node is not cursor2.node

        # Patch ONLY the second one: chunk2
        patch_spec = PatchSpec(
            target_path=parse_spath("(root 2 1 1 1)"),
            expected_original=read_one("(fetch id limit)"),
            replace_with=read_one("(fetch id (abs limit))"),
        )
        patched_ast = apply_patch(ast, patch_spec)

        # Verify chunk1 is UNTOUCHED
        cur1_after = resolve_spath(patched_ast, "(root 2 1 0 1)")
        assert repr(cur1_after.node) == "(fetch id limit)"

        # Verify chunk2 is PATCHED
        cur2_after = resolve_spath(patched_ast, "(root 2 1 1 1)")
        assert repr(cur2_after.node) == "(fetch id (abs limit))"


class TestCasPatching:
    """Test Compare-And-Swap (CAS) atomic replacement and error handling."""

    def test_cas_success(self) -> None:
        ast = read_one("(define (safe-fetch x) (fetch x -5))")
        patch_sexpr = read_one("""
        (patch
          (target-path (root 2 2))
          (expected-original -5)
          (replace-with 10))
        """)
        patched = apply_patch(ast, patch_sexpr)
        assert repr(patched) == "(define (safe-fetch x) (fetch x 10))"

    def test_cas_mismatch_rejection(self) -> None:
        """When expected-original does not match the actual node, reject with CasMismatchError."""
        ast = read_one("(define (safe-fetch x) (fetch x 20))")
        # Agent hallucinates that current node is -5
        patch_sexpr = read_one("""
        (patch
          (target-path (root 2 2))
          (expected-original -5)
          (replace-with 10))
        """)
        with pytest.raises(CasMismatchError) as exc_info:
            apply_patch(ast, patch_sexpr)

        err = exc_info.value
        assert err.expected == -5
        assert err.actual == 20
        # Check diagnostic conversion
        diag_sexpr = err.to_diagnostic()
        assert car(diag_sexpr) == Symbol.intern("diagnostic")
        assert ":cas-mismatch" in repr(diag_sexpr)


class TestStructuredDiagnostics:
    """Test S-expression diagnostic formatting (DSN-32 Section 6.1)."""

    def test_diagnostic_serialization(self) -> None:
        diag = Diagnostic(
            severity="error",
            type_name=":contract-violation",
            blame=":caller",
            function="fetch-paper-chunk",
            argument=2,
            parameter="limit",
            expected="positive?",
            received=-5,
            hint="Argument 2 must be positive. Use (abs limit).",
            location=SourceLocation("fetch.scm", 42, 10),
            target_path=SPath(["root", 2, 3, 1]),
            original_form=read_one("(fetch-paper-chunk id limit)"),
        )
        assert diag.to_sexpr() is not None
        sexpr_str = diag.to_string()
        assert "(severity error)" in sexpr_str
        assert "(type :contract-violation)" in sexpr_str
        assert "(blame :caller)" in sexpr_str
        assert "(function fetch-paper-chunk)" in sexpr_str
        assert "(argument 2)" in sexpr_str
        assert "(parameter limit)" in sexpr_str
        assert '(hint "Argument 2 must be positive. Use (abs limit).")' in sexpr_str
        assert '(location "fetch.scm:42:10")' in sexpr_str
        assert "(target-path (root 2 3 1))" in sexpr_str

    def test_format_diagnostic_from_contract_violation(self) -> None:
        exc = ContractViolationException(
            message="Contract violation",
            blame=":callee",
            function_name="calculate-hash",
            argument_index=1,
            parameter_name="input",
            expected="string?",
            received=12345,
        )
        diag = format_diagnostic(exc)
        assert diag.severity == "error"
        assert diag.type_name == ":contract-violation"
        assert diag.blame == ":callee"
        assert diag.function == "calculate-hash"
        assert diag.received == 12345


class TestMacroSourceLocationInversion:
    """Test Macro Expansion Source Location Inversion (DSN-32 Section 6.4)."""

    def test_macro_location_and_original_form_tracking(self) -> None:
        engine = ALispEngine()
        # Define a macro with syntax-rules
        macro_code = """
        (define-syntax check-positive
          (syntax-rules ()
            ((check-positive val)
             (if (<= val 0)
                 (%contract-assert "check-positive" 1 "val" positive? val ":caller")
                 val))))
        """
        engine.eval(macro_code)

        # Run invocation that triggers contract violation
        test_call = "(check-positive -10)"
        ast = read_one(test_call)
        ast.loc = SourceLocation("test_script.scm", 15, 4)

        with pytest.raises(ContractViolationException) as exc_info:
            engine.eval(ast)

        # Invert source location from violation
        orig_form, orig_loc = invert_source_location(
            exc_info.value.received, loc=ast.loc
        )
        assert orig_loc is not None
        assert orig_loc.file == "test_script.scm"
        assert orig_loc.line == 15


class TestHigherOrderBlameTracking:
    """Test Findler & Felleisen Blame Assignment and Blame Swap for higher-order contracts."""

    def test_first_order_domain_blames_caller(self) -> None:
        engine = ALispEngine()
        engine.eval("""
        (define/c (square (n integer?))
          #:post positive?
          (* n n))
        """)
        # Passing non-integer string should blame caller
        with pytest.raises(ContractViolationException) as exc_info:
            engine.eval('(square "invalid")')
        assert exc_info.value.blame == ":caller"
        assert exc_info.value.function_name == "square"

    def test_first_order_range_blames_callee(self) -> None:
        engine = ALispEngine()
        # Returns 0 which is not positive? -> callee blame
        engine.eval("""
        (define/c (bad-positive (n integer?))
          #:post positive?
          0)
        """)
        with pytest.raises(ContractViolationException) as exc_info:
            engine.eval("(bad-positive 5)")
        assert exc_info.value.blame == ":callee"

    def test_higher_order_callback_argument_blames_callee(self) -> None:
        """When an implementation passes an invalid argument to a caller-provided callback, blame callee!"""
        engine = ALispEngine()
        # apply-twice expects callback: (-> positive? positive?)
        # But apply-twice internally passes -1 to f!
        engine.eval("""
        (define/c (apply-twice (f (-> positive? positive?)) (x positive?))
          #:post positive?
          (f -1))
        """)
        # Caller provides perfectly valid callback
        engine.eval("(define (my-cb val) (+ val 10))")

        with pytest.raises(ContractViolationException) as exc_info:
            engine.eval("(apply-twice my-cb 5)")

        # The CALLEE (apply-twice) violated the callback's contract by passing negative number!
        assert exc_info.value.blame == ":callee"

    def test_higher_order_callback_return_blames_caller(self) -> None:
        """When the caller's callback returns a value violating its contract, blame caller!"""
        engine = ALispEngine()
        engine.eval("""
        (define/c (run-callback (f (-> positive? positive?)) (x positive?))
          #:post positive?
          (f x))
        """)
        # Caller provides buggy callback that returns a non-positive value
        engine.eval("(define (buggy-cb val) -100)")

        with pytest.raises(ContractViolationException) as exc_info:
            engine.eval("(run-callback buggy-cb 5)")

        # The CALLER provided a callback that returns -100, so blame CALLER!
        assert exc_info.value.blame == ":caller"


class TestALispEngineIntegration:
    """Test ALispEngine methods for self-repair and patch evaluation."""

    def test_engine_apply_patch(self) -> None:
        engine = ALispEngine()
        ast = read_one("(define (double x) (+ x x))")
        patch_spec = read_one("""
        (patch
          (target-path (root 2 0))
          (expected-original +)
          (replace-with *))
        """)
        patched = engine.apply_patch(ast, patch_spec)
        assert repr(patched) == "(define (double x) (* x x))"
        # Run patched code in engine
        engine.eval(patched)
        assert engine.eval("(double 5)") == 25
