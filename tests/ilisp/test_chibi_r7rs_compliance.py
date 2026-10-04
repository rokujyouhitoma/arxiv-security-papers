"""Test suite verifying ILISP compliance against chibi-scheme official R7RS test suite.

Origin:
  Project: chibi-scheme (Minimal Scheme Implementation by Alex Shinn)
  Repository: https://github.com/ashinn/chibi-scheme
  Commit: c4e7367e867428889d8fe898a0b39f42e418b3f1
  Test file: ilisp/tests/r7rs_tests.scm
  License: 3-Clause BSD License (Alex Shinn)
"""

from pathlib import Path

from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import Symbol

R7RS_TESTS_FILE = (
    Path(__file__).parent.parent.parent / "ilisp" / "tests" / "r7rs_tests.scm"
)


class TestChibiR7rsConformance:
    """Verify integration and execution of the chibi-scheme R7RS conformance test suite."""

    def test_file_provenance_and_license_header(self) -> None:
        """Verify the test file embeds proper attribution, license, and origin metadata."""
        assert R7RS_TESTS_FILE.exists(), f"Missing test file at {R7RS_TESTS_FILE}"
        content = R7RS_TESTS_FILE.read_text(encoding="utf-8")
        assert "Alex Shinn" in content
        assert "https://github.com/ashinn/chibi-scheme" in content
        assert "3-Clause BSD License" in content
        assert "Copyright (c) 2009-2021 Alex Shinn" in content
        assert "Embedded Portable Test Harness" in content

    def test_r7rs_conformance_execution(self) -> None:
        """Execute the full r7rs_tests.scm test suite and verify high compliance rate (> 90%)."""
        assert R7RS_TESTS_FILE.exists()
        content = R7RS_TESTS_FILE.read_text(encoding="utf-8")

        env = make_initial_env(preload_stdlib=True)
        exprs = read_all(content, filename=str(R7RS_TESTS_FILE))
        assert (
            len(exprs) >= 1200
        ), f"Expected at least 1200 S-expressions, got {len(exprs)}"

        for expr in exprs:
            eval_expr(expr, env)

        passes = env.lookup(Symbol("*test-passes*"))
        failures = env.lookup(Symbol("*test-failures*"))
        errors = env.lookup(Symbol("*test-errors*"))

        assert isinstance(passes, int)
        assert isinstance(failures, int)
        assert isinstance(errors, int)

        total_tests = passes + failures + errors
        assert total_tests > 1200, f"Total tests run: {total_tests}"
        # We achieve > 90% PASS rate on Alex Shinn's complete chibi-scheme conformance test suite
        pass_rate = passes / total_tests
        assert (
            pass_rate >= 0.90
        ), f"Expected pass rate >= 90%, got {pass_rate:.1%} ({passes}/{total_tests})"
        assert passes >= 1100, f"Expected at least 1100 passing tests, got {passes}"
