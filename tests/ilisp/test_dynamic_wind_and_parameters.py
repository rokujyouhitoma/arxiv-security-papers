"""Unit and integration tests for R7RS dynamic-wind and parameters in ILISP."""

from typing import Any

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import is_parameter


def run_code(code: str) -> Any:
    """Helper to evaluate ILISP code with standard environment."""
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    res = None
    for e in exprs:
        res = eval_expr(e, env)
    return res


class TestDynamicWind:
    """Test dynamic-wind execution order and protection guarantees."""

    def test_normal_order(self) -> None:
        code = r"""
        (let ((log '()))
          (dynamic-wind
            (lambda () (set! log (cons "before" log)))
            (lambda ()
              (set! log (cons "body" log))
              "result")
            (lambda () (set! log (cons "after" log))))
          log)
        """
        res = run_code(code)
        from ilisp.types import to_py_list

        assert to_py_list(res) == ["after", "body", "before"]

    def test_dynamic_wind_return_value(self) -> None:
        code = r"""
        (dynamic-wind
          (lambda () 1)
          (lambda () 42)
          (lambda () 3))
        """
        assert run_code(code) == 42

    def test_exception_unwinding(self) -> None:
        code = r"""
        (let ((log '()))
          (guard (e ((equal? e "boom") log))
            (dynamic-wind
              (lambda () (set! log (cons "before" log)))
              (lambda ()
                (set! log (cons "body" log))
                (raise "boom"))
              (lambda () (set! log (cons "after" log))))))
        """
        res = run_code(code)
        from ilisp.types import to_py_list

        assert to_py_list(res) == ["after", "body", "before"]

    def test_escape_continuation_unwinding(self) -> None:
        code = r"""
        (let ((log '()))
          (call/cc
            (lambda (escape)
              (dynamic-wind
                (lambda () (set! log (cons "before" log)))
                (lambda ()
                  (set! log (cons "body" log))
                  (escape "escaped")
                  (set! log (cons "unreachable" log)))
                (lambda () (set! log (cons "after" log))))))
          log)
        """
        res = run_code(code)
        from ilisp.types import to_py_list

        assert to_py_list(res) == ["after", "body", "before"]

    def test_nested_dynamic_wind(self) -> None:
        code = r"""
        (let ((log '()))
          (dynamic-wind
            (lambda () (set! log (cons "outer-before" log)))
            (lambda ()
              (dynamic-wind
                (lambda () (set! log (cons "inner-before" log)))
                (lambda () (set! log (cons "inner-body" log)))
                (lambda () (set! log (cons "inner-after" log))))
              (set! log (cons "outer-body" log)))
            (lambda () (set! log (cons "outer-after" log))))
          log)
        """
        res = run_code(code)
        from ilisp.types import to_py_list

        expected = [
            "outer-after",
            "outer-body",
            "inner-after",
            "inner-body",
            "inner-before",
            "outer-before",
        ]
        assert to_py_list(res) == expected


class TestParameters:
    """Test make-parameter, getters, setters, and converter procedures."""

    def test_parameter_creation_and_predicates(self) -> None:
        p = run_code("(make-parameter 10)")
        assert is_parameter(p)
        assert run_code("(parameter? (make-parameter 10))") is True
        assert run_code("(parameter? 10)") is False

    def test_parameter_get_and_set(self) -> None:
        code = r"""
        (let ((p (make-parameter "initial")))
          (let ((v1 (p)))
            (p "updated")
            (let ((v2 (p)))
              (list v1 v2))))
        """
        res = run_code(code)
        from ilisp.types import to_py_list

        assert to_py_list(res) == ["initial", "updated"]

    def test_parameter_converter(self) -> None:
        code = r"""
        (let ((rad (make-parameter 5 (lambda (x) (* x 2)))))
          (let ((v1 (rad)))
            (rad 10)
            (let ((v2 (rad)))
              (list v1 v2))))
        """
        res = run_code(code)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [10, 20]


class TestParameterize:
    """Test parameterize macro scoping and unwinding behavior."""

    def test_basic_parameterize(self) -> None:
        code = r"""
        (let ((rad (make-parameter 10)))
          (let ((v1 (rad))
                (v2 (parameterize ((rad 99))
                      (rad)))
                (v3 (rad)))
            (list v1 v2 v3)))
        """
        res = run_code(code)
        from ilisp.types import to_py_list

        assert to_py_list(res) == [10, 99, 10]

    def test_nested_parameterize(self) -> None:
        code = r"""
        (let ((p1 (make-parameter "a"))
              (p2 (make-parameter "b")))
          (let ((v1 (list (p1) (p2)))
                (v2 (parameterize ((p1 "A") (p2 "B"))
                      (let ((inner1 (list (p1) (p2)))
                            (inner2 (parameterize ((p1 "AA"))
                                      (list (p1) (p2)))))
                        (list inner1 inner2))))
                (v3 (list (p1) (p2))))
            (list v1 v2 v3)))
        """
        res = run_code(code)
        from ilisp.types import to_py_list

        py_res = to_py_list(res)
        assert to_py_list(py_res[0]) == ["a", "b"]
        inner = to_py_list(py_res[1])
        assert to_py_list(inner[0]) == ["A", "B"]
        assert to_py_list(inner[1]) == ["AA", "B"]
        assert to_py_list(py_res[2]) == ["a", "b"]

    def test_parameterize_exception_restoration(self) -> None:
        code = r"""
        (let ((p (make-parameter 10)))
          (guard (e ((equal? e "err") (p)))
            (parameterize ((p 999))
              (raise "err"))))
        """
        assert run_code(code) == 10

    def test_parameterize_continuation_restoration(self) -> None:
        code = r"""
        (let ((p (make-parameter "start")))
          (call/cc
            (lambda (k)
              (parameterize ((p "temp"))
                (k "escaped"))))
          (p))
        """
        assert run_code(code) == "start"


class TestBackendADynamicWindIntegration:
    """Test Python AST compiler integration with dynamic-wind and parameters."""

    def test_py_codegen_dynamic_wind(self) -> None:
        env = make_initial_env(preload_stdlib=True)
        code = r"""
        (let ((val 0))
          (dynamic-wind
            (lambda () (set! val (+ val 1)))
            (lambda () (+ val 10))
            (lambda () (set! val (+ val 5)))))
        """
        res = compile_ilisp(code, env=env)
        assert res == 11

    def test_py_codegen_parameterize(self) -> None:
        env = make_initial_env(preload_stdlib=True)
        code = r"""
        (let ((p (make-parameter "base")))
          (let ((inner (parameterize ((p "nested"))
                         (p)))
                (outer (p)))
            (string-append inner outer)))
        """
        res = compile_ilisp(code, env=env)
        assert str(res) == "nestedbase"
