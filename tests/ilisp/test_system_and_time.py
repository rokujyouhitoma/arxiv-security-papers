"""Tests for R7RS 6.14 System interface, (scheme process-context), and (scheme time)."""

from typing import Any

import pytest

from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import Cons, is_pair, to_py_list


def eval_str(code: str) -> Any:
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    result = None
    for expr in exprs:
        result = eval_expr(expr, env)
    return result


class TestSchemeTime:
    """Tests for (scheme time): current-second, current-jiffy, jiffies-per-second."""

    def test_current_second(self) -> None:
        sec = eval_str("(current-second)")
        assert isinstance(sec, float)
        assert sec > 1_700_000_000.0  # Recent epoch

    def test_current_jiffy(self) -> None:
        code = """
        (let ((j1 (current-jiffy))
              (j2 (current-jiffy)))
          (list (exact-integer? j1) (>= j2 j1)))
        """
        res = eval_str(code)
        py_res = to_py_list(res)
        assert py_res == [True, True]

    def test_jiffies_per_second(self) -> None:
        jps = eval_str("(jiffies-per-second)")
        assert isinstance(jps, int)
        assert jps > 0
        assert jps == 1_000_000_000


class TestSchemeProcessContext:
    """Tests for (scheme process-context): get-environment-variable(s), command-line."""

    def test_get_environment_variable_existing(self) -> None:
        res = eval_str('(get-environment-variable "PATH")')
        assert isinstance(res, str)
        assert len(res) > 0

    def test_get_environment_variable_mutable_string(self) -> None:
        code = """
        (let ((key (string #\\P #\\A #\\T #\\H)))
          (get-environment-variable key))
        """
        res = eval_str(code)
        assert isinstance(res, str)
        assert len(res) > 0

    def test_get_environment_variable_non_existent(self) -> None:
        res = eval_str(
            '(get-environment-variable "__DEFINITELY_NON_EXISTENT_ILISP_ENV__")'
        )
        assert res is False

    def test_get_environment_variable_type_error(self) -> None:
        with pytest.raises(Exception):
            eval_str("(get-environment-variable 12345)")
        with pytest.raises(Exception):
            eval_str("(get-environment-variable 'PATH)")

    def test_get_environment_variables(self) -> None:
        res = eval_str("(get-environment-variables)")
        assert is_pair(res)
        first_pair = res.car
        assert isinstance(first_pair, Cons)
        assert isinstance(first_pair.car, str)
        assert isinstance(first_pair.cdr, str)

    def test_command_line(self) -> None:
        res = eval_str("(command-line)")
        py_res = to_py_list(res)
        assert isinstance(py_res, list)
        assert len(py_res) >= 1
        assert all(isinstance(x, str) for x in py_res)


class TestExit:
    """Tests for exit and emergency-exit."""

    def test_exit_default(self) -> None:
        with pytest.raises(SystemExit) as excinfo:
            eval_str("(exit)")
        assert excinfo.value.code == 0

    def test_exit_true(self) -> None:
        with pytest.raises(SystemExit) as excinfo:
            eval_str("(exit #t)")
        assert excinfo.value.code == 0

    def test_exit_false(self) -> None:
        with pytest.raises(SystemExit) as excinfo:
            eval_str("(exit #f)")
        assert excinfo.value.code == 1

    def test_exit_integer(self) -> None:
        with pytest.raises(SystemExit) as excinfo:
            eval_str("(exit 42)")
        assert excinfo.value.code == 42
