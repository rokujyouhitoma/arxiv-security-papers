"""Test suite verifying ILISP compliance against chibi-scheme official R7RS test suite.

Origin:
  Project: chibi-scheme (Minimal Scheme Implementation by Alex Shinn)
  Repository: https://github.com/ashinn/chibi-scheme
  Commit: c4e7367e867428889d8fe898a0b39f42e418b3f1
  Test file: ilisp/tests/r7rs_tests.scm
  License: 3-Clause BSD License (Alex Shinn)

Test Harness:
  Test file: ilisp/tests/test_harness.scm
  License: MIT License (Project ILISP Authors - Original Code)
"""

from pathlib import Path
from typing import Any, List

from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.port import format_datum
from ilisp.reader import read_all
from ilisp.types import Cons, NilType, Symbol

R7RS_TESTS_FILE = (
    Path(__file__).parent.parent.parent / "ilisp" / "tests" / "r7rs_tests.scm"
)
TEST_HARNESS_FILE = (
    Path(__file__).parent.parent.parent / "ilisp" / "tests" / "test_harness.scm"
)


def _cons_to_list(val: Any) -> List[Any]:
    items: List[Any] = []
    curr = val
    while isinstance(curr, Cons):
        items.append(curr.car)
        curr = curr.cdr
    return items


class TestChibiR7rsConformance:
    """Verify integration and autonomous execution of the chibi-scheme R7RS conformance test suite."""

    def test_file_provenance_and_license_header(self) -> None:
        """Verify proper attribution, license separation, and provenance metadata."""
        assert R7RS_TESTS_FILE.exists(), f"Missing test file at {R7RS_TESTS_FILE}"
        assert (
            TEST_HARNESS_FILE.exists()
        ), f"Missing test harness at {TEST_HARNESS_FILE}"

        # 1. chibi-scheme upstream file verification (3-Clause BSD)
        r7rs_content = R7RS_TESTS_FILE.read_text(encoding="utf-8")
        assert "Alex Shinn" in r7rs_content
        assert "https://github.com/ashinn/chibi-scheme" in r7rs_content
        assert "3-Clause BSD License" in r7rs_content
        assert "Copyright (c) 2009-2021 Alex Shinn" in r7rs_content
        # Ensure our proprietary harness is completely decoupled from BSD upstream code
        assert (
            "Embedded Portable Test Harness" not in r7rs_content
        ), "Custom test harness must not be embedded in upstream BSD3 code"

        # 2. ILISP original test harness verification (MIT License)
        harness_content = TEST_HARNESS_FILE.read_text(encoding="utf-8")
        assert "ILISP Portable Test Harness" in harness_content
        assert "MIT License" in harness_content
        assert "Copyright (C) 2026 Project ILISP Authors" in harness_content

    def test_r7rs_conformance_execution(self) -> None:
        """Execute the full r7rs_tests.scm test suite and enforce 100% PASS (0 FAIL, 0 ERROR)."""
        assert TEST_HARNESS_FILE.exists()
        assert R7RS_TESTS_FILE.exists()

        env = make_initial_env(preload_stdlib=True)

        # 1. Load and initialize independent ILISP test harness
        harness_exprs = read_all(
            TEST_HARNESS_FILE.read_text(encoding="utf-8"),
            filename=str(TEST_HARNESS_FILE),
        )
        for h_expr in harness_exprs:
            eval_expr(h_expr, env)

        # 2. Load and evaluate official chibi-scheme R7RS test suite
        r7rs_content = R7RS_TESTS_FILE.read_text(encoding="utf-8")
        exprs = read_all(r7rs_content, filename=str(R7RS_TESTS_FILE))
        assert (
            len(exprs) >= 1150
        ), f"Expected at least 1150 S-expressions, got {len(exprs)}"

        for expr in exprs:
            eval_expr(expr, env)

        # 3. Retrieve test results and failure logs
        passes = env.lookup(Symbol("*test-passes*"))
        failures = env.lookup(Symbol("*test-failures*"))
        errors = env.lookup(Symbol("*test-errors*"))
        failure_log_val = env.lookup(Symbol("*test-failure-log*"))

        assert isinstance(passes, int)
        assert isinstance(failures, int)
        assert isinstance(errors, int)

        total_tests = passes + failures + errors
        assert total_tests >= 1200, f"Expected >1200 tests executed, got {total_tests}"

        # 4. Extract detailed failure logs if any failure or error occurred
        log_items = (
            _cons_to_list(failure_log_val)
            if not isinstance(failure_log_val, NilType)
            else []
        )
        log_details = []
        for entry in reversed(log_items):
            log_details.append(format_datum(entry))
        details_str = "\n".join(log_details)

        # 5. Enforce 100% PASS requirement
        error_msg = (
            f"\n=======================================================\n"
            f"R7RS CONFORMANCE TEST FAILED (100% required)\n"
            f"Passes: {passes}, Failures: {failures}, Errors: {errors} (Total: {total_tests})\n"
            f"-------------------------------------------------------\n"
            f"Failure Details:\n{details_str}\n"
            f"======================================================="
        )

        assert failures == 0, f"Found {failures} test failures! {error_msg}"
        assert errors == 0, f"Found {errors} test errors! {error_msg}"
        assert (
            passes == total_tests
        ), f"Expected 100% pass rate ({total_tests}/{total_tests}), got {passes}/{total_tests}"
