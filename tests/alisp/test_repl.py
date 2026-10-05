"""Tests for ALisp Interactive REPL and CLI Runner (alisp.repl)."""

import sys
import tempfile
from typing import List
from unittest.mock import patch

import pytest

from alisp.core import ALispEngine
from alisp.repl import (
    _handle_repl_eval,
    _is_exit_expression,
    _update_paren_balance,
    main,
    repl,
)
from ilisp.reader import read_one


class TestReplHelpers:
    """Test helper functions in alisp.repl."""

    def test_is_exit_expression(self) -> None:
        expr_exit = read_one("(exit)")
        assert _is_exit_expression(expr_exit) is True

        expr_other = read_one("(+ 1 2)")
        assert _is_exit_expression(expr_other) is False

        assert _is_exit_expression(123) is False

    def test_update_paren_balance(self) -> None:
        assert _update_paren_balance("(+ 1 2)", 0) == 0
        assert _update_paren_balance("(+ 1", 0) == 1
        assert _update_paren_balance("2)", 1) == 0
        assert _update_paren_balance(")))", 0) == 0

    def test_handle_repl_eval_normal(self, capsys: pytest.CaptureFixture[str]) -> None:
        engine = ALispEngine()
        res = _handle_repl_eval(engine, "(+ 10 20)")
        assert res is True
        captured = capsys.readouterr()
        assert "30" in captured.out

    def test_handle_repl_eval_exit(self) -> None:
        engine = ALispEngine()
        res = _handle_repl_eval(engine, "(exit)")
        assert res is False

    def test_handle_repl_eval_fuel_exhausted(
        self, capsys: pytest.CaptureFixture[str]
    ) -> None:
        engine = ALispEngine()
        code = "(with-fuel 20 (letrec ((f (lambda () (f)))) (f)))"
        res = _handle_repl_eval(engine, code)
        assert res is True
        captured = capsys.readouterr()
        assert "[FuelExhausted]" in captured.out

    def test_handle_repl_eval_contract_violation(
        self, capsys: pytest.CaptureFixture[str]
    ) -> None:
        engine = ALispEngine()
        code = "(begin (define/c (f (x number?)) x) (f 'invalid))"
        res = _handle_repl_eval(engine, code)
        assert res is True
        captured = capsys.readouterr()
        assert "[ContractViolation]" in captured.out
        assert "diagnostic:" in captured.out

    def test_handle_repl_eval_syntax_error(
        self, capsys: pytest.CaptureFixture[str]
    ) -> None:
        engine = ALispEngine()
        res = _handle_repl_eval(engine, "(+ 1 2")
        assert res is True
        captured = capsys.readouterr()
        assert "SyntaxError:" in captured.out


class TestReplInteractiveLoop:
    """Test full repl() loop with simulated user inputs."""

    def test_repl_session_eval_and_exit(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        inputs: List[str] = [
            "(+ 5 7)",
            "(define double (lambda (x) (* x 2)))",
            "(double 21)",
            "(exit)",
        ]
        input_iter = iter(inputs)
        monkeypatch.setattr("builtins.input", lambda prompt="": next(input_iter))

        repl()

        captured = capsys.readouterr()
        assert "ALisp (Agent Lisp)" in captured.out
        assert "12" in captured.out
        assert "42" in captured.out
        assert "Exiting ALisp REPL." in captured.out

    def test_repl_session_multiline_input(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        inputs: List[str] = [
            "(define add3",
            "  (lambda (x)",
            "    (+ x 3)))",
            "(add3 10)",
            "(exit)",
        ]
        input_iter = iter(inputs)
        monkeypatch.setattr("builtins.input", lambda prompt="": next(input_iter))

        repl()

        captured = capsys.readouterr()
        assert "13" in captured.out

    def test_repl_handles_keyboard_interrupt_gracefully(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        raised = False

        def mock_input(prompt: str = "") -> str:
            nonlocal raised
            if not raised:
                raised = True
                raise KeyboardInterrupt
            return "(exit)"

        monkeypatch.setattr("builtins.input", mock_input)

        repl()

        captured = capsys.readouterr()
        assert "KeyboardInterrupt" in captured.out
        assert "Exiting ALisp REPL." in captured.out

    def test_repl_eof_terminates(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        monkeypatch.setattr(
            "builtins.input", lambda prompt="": (_ for _ in ()).throw(EOFError)
        )

        repl()

        captured = capsys.readouterr()
        assert "Exiting ALisp REPL." in captured.out


class TestAlispCLI:
    """Test python -m alisp command line interface."""

    def test_cli_eval_success(self, capsys: pytest.CaptureFixture[str]) -> None:
        with patch.object(sys, "argv", ["alisp", "-e", "(+ 100 200)"]):
            with pytest.raises(SystemExit) as exc_info:
                main()
            assert exc_info.value.code == 0

        captured = capsys.readouterr()
        assert "300" in captured.out

    def test_cli_eval_fuel_exhausted(self, capsys: pytest.CaptureFixture[str]) -> None:
        code = "(with-fuel 30 (letrec ((f (lambda () (f)))) (f)))"
        with patch.object(sys, "argv", ["alisp", "-e", code]):
            with pytest.raises(SystemExit) as exc_info:
                main()
            assert exc_info.value.code == 1

        captured = capsys.readouterr()
        assert "[FuelExhausted]" in captured.err

    def test_cli_eval_contract_violation(
        self, capsys: pytest.CaptureFixture[str]
    ) -> None:
        code = "(begin (define/c (f (x number?)) x) (f 'bad))"
        with patch.object(sys, "argv", ["alisp", "-e", code]):
            with pytest.raises(SystemExit) as exc_info:
                main()
            assert exc_info.value.code == 1

        captured = capsys.readouterr()
        assert "[ContractViolation]" in captured.err

    def test_cli_run_file(self, capsys: pytest.CaptureFixture[str]) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f:
            f.write("(define val 42)\n")
            f_path = f.name

        with patch.object(sys, "argv", ["alisp", f_path]):
            with pytest.raises(SystemExit) as exc_info:
                main()
            assert exc_info.value.code == 0

    def test_cli_default_fuel_flag(self, capsys: pytest.CaptureFixture[str]) -> None:
        code = "(letrec ((f (lambda () (f)))) (f))"
        with patch.object(sys, "argv", ["alisp", "--fuel", "40", "-e", code]):
            with pytest.raises(SystemExit) as exc_info:
                main()
            assert exc_info.value.code == 1

        captured = capsys.readouterr()
        assert "[FuelExhausted]" in captured.err
