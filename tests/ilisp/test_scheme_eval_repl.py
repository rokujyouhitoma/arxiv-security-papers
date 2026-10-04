"""Unit tests for R7RS (scheme eval) and (scheme repl) libraries."""

import pytest

from ilisp.env import Environment, set_interaction_environment
from ilisp.evaluator import eval_expr
from ilisp.module import GLOBAL_LIBRARY_REGISTRY
from ilisp.reader import read_all
from ilisp.types import SchemeException, Symbol


class TestSchemeEvalAndRepl:
    """Test (scheme eval) and (scheme repl) libraries and dynamic evaluation."""

    def test_libraries_registered(self) -> None:
        assert GLOBAL_LIBRARY_REGISTRY.has(("scheme", "eval"))
        eval_lib = GLOBAL_LIBRARY_REGISTRY.get(("scheme", "eval"))
        assert eval_lib is not None
        assert Symbol.intern("eval") in eval_lib.exports
        assert Symbol.intern("environment") in eval_lib.exports

        assert GLOBAL_LIBRARY_REGISTRY.has(("scheme", "repl"))
        repl_lib = GLOBAL_LIBRARY_REGISTRY.get(("scheme", "repl"))
        assert repl_lib is not None
        assert Symbol.intern("interaction-environment") in repl_lib.exports

    def test_eval_in_new_environment(self) -> None:
        env = Environment()
        code = """
        (import (scheme base) (scheme eval))
        (define env1 (environment '(scheme base)))
        (eval '(+ 10 20) env1)
        """
        exprs = read_all(code)
        res = None
        for e in exprs:
            res = eval_expr(e, env)
        assert res == 30

    def test_environment_multi_import_and_isolation(self) -> None:
        env = Environment()
        code = """
        (import (scheme base) (scheme eval))
        (define env1 (environment '(scheme base)))
        (define env2 (environment '(scheme base) '(scheme inexact)))
        (eval '(define x 42) env1)
        (eval 'x env1)
        """
        exprs = read_all(code)
        res = None
        for e in exprs:
            res = eval_expr(e, env)
        assert res == 42

        # env2 should NOT have 'x' defined
        with pytest.raises((SchemeException, NameError, Exception)):
            eval_expr(read_all("(eval 'x env2)")[0], env)

        # env2 has inexact functions, env1 does not
        sin_res = eval_expr(read_all("(eval '(sin 0.0) env2)")[0], env)
        assert sin_res == 0.0

    def test_interaction_environment(self) -> None:
        env = Environment()
        set_interaction_environment(env)
        code = """
        (import (scheme base) (scheme eval) (scheme repl))
        (define greeting "hello")
        (eval 'greeting (interaction-environment))
        """
        exprs = read_all(code)
        res = None
        for e in exprs:
            res = eval_expr(e, env)
        assert res == "hello"

        # Mutation in interaction environment
        eval_expr(
            read_all('(eval \'(set! greeting "world") (interaction-environment))')[0],
            env,
        )
        assert env.lookup(Symbol.intern("greeting")) == "world"

    def test_eval_invalid_env_type(self) -> None:
        env = Environment()
        code = """
        (import (scheme base) (scheme eval))
        (eval '(+ 1 2) 12345)
        """
        with pytest.raises((TypeError, SchemeException)):
            for e in read_all(code):
                eval_expr(e, env)
