"""Unit tests for R7RS (scheme lazy) library and delayed evaluation constructs."""

from ilisp.env import Environment
from ilisp.evaluator import eval_expr
from ilisp.module import GLOBAL_LIBRARY_REGISTRY
from ilisp.reader import read_all
from ilisp.types import Symbol


class TestSchemeLazyModule:
    """Test (scheme lazy) library registration and import semantics."""

    def test_library_registered(self) -> None:
        assert GLOBAL_LIBRARY_REGISTRY.has(("scheme", "lazy"))
        lib = GLOBAL_LIBRARY_REGISTRY.get(("scheme", "lazy"))
        assert lib is not None
        for name in ("delay", "delay-force", "force", "make-promise", "promise?"):
            assert Symbol.intern(name) in lib.exports

    def test_clean_import_and_delay_force(self) -> None:
        env = Environment()
        code = """
        (import (scheme base) (scheme lazy))
        (define count 0)
        (define p (delay (begin (set! count (+ count 1)) (* 10 20))))
        """
        for expr in read_all(code):
            eval_expr(expr, env)

        assert env.lookup(Symbol.intern("count")) == 0

        # First force
        res1 = eval_expr(read_all("(force p)")[0], env)
        assert res1 == 200
        assert env.lookup(Symbol.intern("count")) == 1

        # Second force: must use memoized value and not increment count
        res2 = eval_expr(read_all("(force p)")[0], env)
        assert res2 == 200
        assert env.lookup(Symbol.intern("count")) == 1

    def test_promise_predicate(self) -> None:
        env = Environment()
        code = """
        (import (scheme base) (scheme lazy))
        (define p (delay 42))
        (define not-p 42)
        """
        for expr in read_all(code):
            eval_expr(expr, env)

        assert eval_expr(read_all("(promise? p)")[0], env) is True
        assert eval_expr(read_all("(promise? not-p)")[0], env) is False
        assert eval_expr(read_all("(promise? (make-promise 100))")[0], env) is True

    def test_make_promise(self) -> None:
        env = Environment()
        code = """
        (import (scheme base) (scheme lazy))
        (define p1 (make-promise 99))
        (define p2 (make-promise p1))
        """
        for expr in read_all(code):
            eval_expr(expr, env)

        assert eval_expr(read_all("(force p1)")[0], env) == 99
        # make-promise returns the promise itself if argument is already a promise
        assert eval_expr(read_all("(force p2)")[0], env) == 99

    def test_delay_force_stream(self) -> None:
        """Test iterative unrolling of delay-force in streams."""
        env = Environment()
        code = """
        (import (scheme base) (scheme lazy))

        (define (stream-filter pred s)
          (delay-force
            (if (null? (force s))
                (delay '())
                (let ((head (car (force s)))
                      (tail (cdr (force s))))
                  (if (pred head)
                      (delay (cons head (stream-filter pred tail)))
                      (stream-filter pred tail))))))

        (define (from n)
          (delay (cons n (from (+ n 1)))))

        (define evens (stream-filter (lambda (x) (= (modulo x 2) 0)) (from 0)))
        """
        for expr in read_all(code):
            eval_expr(expr, env)

        # Take first 3 even numbers
        res = eval_expr(
            read_all("""
                (let* ((p1 (force evens))
                       (e0 (car p1))
                       (p2 (force (cdr p1)))
                       (e1 (car p2))
                       (p3 (force (cdr p2)))
                       (e2 (car p3)))
                  (list e0 e1 e2))
                """)[0],
            env,
        )
        from ilisp.types import to_py_list

        assert to_py_list(res) == [0, 2, 4]
