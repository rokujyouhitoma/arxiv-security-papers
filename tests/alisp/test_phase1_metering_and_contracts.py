"""Tests for ALisp Phase 1: Core Safety Primitives (with-fuel, define/c) & Step Hook.

Verifies:
- Evaluator DIP StepHook interface and StepInterceptor.
- FuelCounter and with-fuel step metering (terminating infinite loops).
- Hierarchical sub-budgeting (child fuel capped by parent, fuel subtracted from parent).
- define/c contract macro, pre-condition / post-condition assertions, and Blame Tracking.
- Predicate combinators (and/c, or/c, not/c, any/c, none/c, equal/c).
- Diagnostic S-expression serialization.
- ALispEngine and eval_alisp top-level integration.
"""

import pytest

from alisp import (
    ALispEngine,
    ContractViolationException,
    FuelExhaustedException,
    StepInterceptor,
    and_c,
    any_c,
    eval_alisp,
    none_c,
)
from ilisp.env import make_initial_env
from ilisp.evaluator import Evaluator
from ilisp.reader import read_one
from ilisp.types import Cons, Symbol, to_py_list


class TestStepInterceptorAndEvaluatorHook:
    """Test the DIP StepHook interface in ilisp.evaluator and StepInterceptor."""

    def test_evaluator_step_hook_invocation(self) -> None:
        count = 0

        def hook() -> None:
            nonlocal count
            count += 1

        evaluator = Evaluator(step_hook=hook)
        env = make_initial_env()
        expr = read_one("(+ 1 2 3)")
        res = evaluator.eval(expr, env)
        assert res == 6
        assert count > 0

    def test_evaluator_without_hook_has_zero_overhead(self) -> None:
        evaluator = Evaluator(step_hook=None)
        env = make_initial_env()
        expr = read_one("(* 6 7)")
        res = evaluator.eval(expr, env)
        assert res == 42


class TestFuelMetering:
    """Test computational step budgeting and with-fuel bounds."""

    def test_infinite_tail_recursion_terminated_by_with_fuel(self) -> None:
        engine = ALispEngine()
        code = """
        (with-fuel 100
          (letrec ((f (lambda () (f))))
            (f)))
        """
        with pytest.raises(FuelExhaustedException) as exc_info:
            engine.eval(code)
        assert "limit of 100 steps exceeded" in str(exc_info.value)
        assert exc_info.value.limit == 100

    def test_infinite_non_tail_recursion_terminated_by_with_fuel(self) -> None:
        engine = ALispEngine()
        code = """
        (with-fuel 80
          (letrec ((f (lambda (n) (+ 1 (f (+ n 1))))))
            (f 0)))
        """
        with pytest.raises(FuelExhaustedException) as exc_info:
            engine.eval(code)
        assert exc_info.value.limit == 80

    def test_normal_computation_completes_within_budget(self) -> None:
        engine = ALispEngine()
        code = """
        (with-fuel 500
          (letrec ((fact (lambda (n)
                           (if (<= n 1)
                               1
                               (* n (fact (- n 1)))))))
            (fact 5)))
        """
        res = engine.eval(code)
        assert res == 120

    def test_engine_eval_with_fuel_kwarg(self) -> None:
        engine = ALispEngine()
        with pytest.raises(FuelExhaustedException):
            engine.eval(
                "(letrec ((f (lambda () (f)))) (f))",
                fuel=50,
            )

    def test_eval_alisp_helper(self) -> None:
        res = eval_alisp("(+ 10 20)")
        assert res == 30

        with pytest.raises(FuelExhaustedException):
            eval_alisp("(letrec ((f (lambda () (f)))) (f))", fuel=60)


class TestSubBudgeting:
    """Test hierarchical sub-budgeting and parent-child fuel delegation."""

    def test_nested_with_fuel_capped_by_parent(self) -> None:
        engine = ALispEngine()
        # Parent has 40 steps, child requests 200 steps.
        # Execution must terminate around 40 steps, not 200.
        code = """
        (with-fuel 40
          (with-fuel 200
            (letrec ((f (lambda () (f))))
              (f))))
        """
        with pytest.raises(FuelExhaustedException) as exc_info:
            engine.eval(code)
        # Child effective limit was min(200, parent_remaining) <= 40
        assert exc_info.value.limit <= 40

    def test_nested_with_fuel_sub_budget_deducted_from_parent(self) -> None:
        interceptor = StepInterceptor()
        with interceptor.with_fuel_scope(100) as parent_counter:
            assert parent_counter.remaining == 100

            # Consume 10 steps in parent
            for _ in range(10):
                interceptor()
            assert parent_counter.remaining == 90

            # Enter child scope of 30 steps
            with interceptor.with_fuel_scope(30) as child_counter:
                assert child_counter.remaining == 30
                # Consume 20 steps in child
                for _ in range(20):
                    interceptor()
                assert child_counter.remaining == 10
                assert parent_counter.remaining == 70

            # Back in parent: 70 steps remaining
            assert parent_counter.remaining == 70

    def test_nested_with_fuel_completes_and_returns_to_outer(self) -> None:
        engine = ALispEngine()
        code = """
        (with-fuel 1000
          (+ 10
             (with-fuel 200 (+ 20 30))))
        """
        res = engine.eval(code)
        assert res == 60


class TestDefineContract:
    """Test define/c macro and contract pre/post condition assertions."""

    def test_define_c_valid_arguments_pass(self) -> None:
        engine = ALispEngine()
        code = """
        (define/c (add (x number?) (y number?))
          (+ x y))
        (add 3 4)
        """
        res = engine.eval(code)
        assert res == 7

    def test_precondition_violation_blames_caller(self) -> None:
        engine = ALispEngine()
        code = """
        (define/c (add (x number?) (y number?))
          (+ x y))
        (add "not-a-number" 4)
        """
        with pytest.raises(ContractViolationException) as exc_info:
            engine.eval(code)

        exc = exc_info.value
        assert exc.blame == ":caller"
        assert exc.function_name == "add"
        assert exc.argument_index == 1
        assert exc.parameter_name == "x"
        assert "add" in exc.message
        assert ":caller" in exc.message

    def test_second_argument_precondition_violation(self) -> None:
        engine = ALispEngine()
        code = """
        (define/c (multiply (a number?) (b number?))
          (* a b))
        (multiply 10 'invalid-symbol)
        """
        with pytest.raises(ContractViolationException) as exc_info:
            engine.eval(code)

        exc = exc_info.value
        assert exc.blame == ":caller"
        assert exc.function_name == "multiply"
        assert exc.argument_index == 2
        assert exc.parameter_name == "b"

    def test_postcondition_violation_blames_callee_with_hash_post(self) -> None:
        engine = ALispEngine()
        code = """
        (define/c (broken-fn (x number?))
          #:post string?
          (+ x 1))
        (broken-fn 10)
        """
        with pytest.raises(ContractViolationException) as exc_info:
            engine.eval(code)

        exc = exc_info.value
        assert exc.blame == ":callee"
        assert exc.function_name == "broken-fn"
        assert exc.argument_index is None
        assert exc.parameter_name == "return"
        assert ":callee" in exc.message

    def test_postcondition_success_returns_result(self) -> None:
        engine = ALispEngine()
        code = """
        (define/c (make-pos (x number?))
          #:post positive?
          (if (< x 0) (- x) x))
        (make-pos -42)
        """
        res = engine.eval(code)
        assert res == 42

    def test_postcondition_with_colon_post_syntax(self) -> None:
        engine = ALispEngine()
        code = """
        (define/c (safe-str (s string?))
          :post string?
          (string-append s "!"))
        (safe-str "hello")
        """
        res = engine.eval(code)
        assert res == "hello!"

    def test_diagnostic_serialization(self) -> None:
        engine = ALispEngine()
        code = """
        (define/c (compute (x positive?))
          x)
        (compute -1)
        """
        with pytest.raises(ContractViolationException) as exc_info:
            engine.eval(code)

        diag = exc_info.value.to_diagnostic()
        assert isinstance(diag, Cons)
        assert diag.car == Symbol.intern("diagnostic")
        fields = to_py_list(diag.cdr)
        field_dict = {f.car.name: f.cdr.car for f in fields}
        assert field_dict["severity"].name == "error"
        assert field_dict["type"].name == ":contract-violation"
        assert field_dict["blame"].name == ":caller"
        assert field_dict["function"].name == "compute"
        assert field_dict["argument"] == 1
        assert field_dict["received"] == -1


class TestPredicateCombinators:
    """Test and/c, or/c, not/c, any/c, none/c, and equal/c."""

    def test_and_c_in_python_and_scheme(self) -> None:
        comb = and_c(lambda x: isinstance(x, int), lambda x: x > 0)
        assert comb(5) is True
        assert comb(-5) is False
        assert comb("string") is False

        engine = ALispEngine()
        code = """
        (define/c (int-pos (n (and/c integer? positive?)))
          #:post positive?
          n)
        (int-pos 10)
        """
        assert engine.eval(code) == 10

        with pytest.raises(ContractViolationException):
            engine.eval("(int-pos -5)")

    def test_or_c_in_scheme(self) -> None:
        engine = ALispEngine()
        code = """
        (define/c (str-or-num (v (or/c string? number?)))
          v)
        (list (str-or-num "test") (str-or-num 99))
        """
        res = engine.eval(code)
        py_res = to_py_list(res)
        assert py_res == ["test", 99]

        with pytest.raises(ContractViolationException):
            engine.eval("(str-or-num #t)")

    def test_not_c_in_scheme(self) -> None:
        engine = ALispEngine()
        code = """
        (define/c (non-empty (lst (not/c null?)))
          (car lst))
        (non-empty '(1 2 3))
        """
        assert engine.eval(code) == 1

        with pytest.raises(ContractViolationException):
            engine.eval("(non-empty '())")

    def test_any_c_and_none_c(self) -> None:
        assert any_c("anything") is True
        assert any_c(123) is True
        assert none_c("anything") is False

        engine = ALispEngine()
        assert engine.eval("((any/c) 123)") is True
        assert engine.eval("((none/c) 123)") is False


class TestFullIntegrationAndR7RSCompatibility:
    """Test combined fuel + contracts and pure R7RS compatibility."""

    def test_contracts_inside_with_fuel(self) -> None:
        engine = ALispEngine()
        code = """
        (define/c (fib (n (and/c integer? (or/c zero? positive?))))
          #:post (and/c integer? (or/c zero? positive?))
          (if (< n 2)
              n
              (+ (fib (- n 1)) (fib (- n 2)))))
        (with-fuel 2000
          (fib 6))
        """
        assert engine.eval(code) == 8

    def test_pure_r7rs_expressions_run_identically(self) -> None:
        engine = ALispEngine()
        code = """
        (define (map-double lst)
          (map (lambda (x) (* x 2)) lst))
        (map-double '(1 2 3 4))
        """
        res = engine.eval(code)
        assert to_py_list(res) == [2, 4, 6, 8]
