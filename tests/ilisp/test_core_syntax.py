"""Unit tests for R7RS Core Syntax Extensions: letrec, letrec*, do, and named let."""

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all


class TestLetrecAndLetrecStar:
    """Test mutual recursion and sequential scoping in letrec and letrec*."""

    def test_letrec_mutual_recursion(self) -> None:
        code = """
        (letrec ((is-even? (lambda (n)
                             (if (= n 0)
                                 #t
                                 (is-odd? (- n 1)))))
                 (is-odd? (lambda (n)
                            (if (= n 0)
                                #f
                                (is-even? (- n 1))))))
          (list (is-even? 10) (is-odd? 10) (is-even? 7) (is-odd? 7)))
        """
        env = make_initial_env()
        exprs = read_all(code)
        res = eval_expr(exprs[0], env)
        # (list #t #f #f #t) -> Cons(#t, Cons(#f, Cons(#f, Cons(#t, NIL))))
        assert res.car is True
        assert res.cdr.car is False
        assert res.cdr.cdr.car is False
        assert res.cdr.cdr.cdr.car is True

    def test_letrec_star_sequential_initialization(self) -> None:
        code = """
        (letrec* ((a 10)
                  (b (+ a 5))
                  (c (* b 2)))
          c)
        """
        env = make_initial_env()
        exprs = read_all(code)
        res = eval_expr(exprs[0], env)
        # a=10, b=15, c=30
        assert res == 30


class TestNamedLet:
    """Test Named let (loop accumulation)."""

    def test_named_let_factorial(self) -> None:
        code = """
        (let fact ((n 5) (acc 1))
          (if (= n 0)
              acc
              (fact (- n 1) (* acc n))))
        """
        env = make_initial_env()
        exprs = read_all(code)
        res = eval_expr(exprs[0], env)
        assert res == 120

    def test_named_let_sum(self) -> None:
        code = """
        (let loop ((i 1) (total 0))
          (if (> i 10)
              total
              (loop (+ i 1) (+ total i))))
        """
        env = make_initial_env()
        exprs = read_all(code)
        res = eval_expr(exprs[0], env)
        assert res == 55


class TestDoIteration:
    """Test R7RS do iteration loop macro."""

    def test_do_basic_sum(self) -> None:
        code = """
        (do ((i 0 (+ i 1))
             (sum 0 (+ sum i)))
            ((> i 10) sum))
        """
        env = make_initial_env()
        exprs = read_all(code)
        res = eval_expr(exprs[0], env)
        # 0 + 1 + 2 + ... + 10 = 55
        assert res == 55

    def test_do_omitted_step(self) -> None:
        # Step omitted for 'base', so 'base' remains constant
        code = """
        (do ((i 1 (+ i 1))
             (base 3)
             (acc 1 (* acc base)))
            ((> i 4) acc))
        """
        env = make_initial_env()
        exprs = read_all(code)
        res = eval_expr(exprs[0], env)
        # 3^4 = 81
        assert res == 81

    def test_do_with_commands(self) -> None:
        code = """
        (let ((collected '()))
          (do ((i 1 (+ i 1)))
              ((> i 3) collected)
            (set! collected (cons i collected))))
        """
        env = make_initial_env()
        exprs = read_all(code)
        res = eval_expr(exprs[0], env)
        # collected: (3 2 1)
        assert res.car == 3
        assert res.cdr.car == 2
        assert res.cdr.cdr.car == 1


class TestBackendACoreSyntaxIntegration:
    """Verify that letrec, named let, and do compile cleanly under Backend A."""

    def test_py_codegen_letrec_and_named_let(self) -> None:
        code = """
        (define (run-named-let)
          (let loop ((count 10) (acc 0))
            (if (= count 0)
                acc
                (loop (- count 1) (+ acc 2)))))
        """
        env = make_initial_env()
        compile_ilisp(code, env=env)
        res = compile_ilisp("(run-named-let)", env=env)
        assert res == 20

    def test_py_codegen_do_loop(self) -> None:
        code = """
        (define (calc-do)
          (do ((i 0 (+ i 1))
               (sum 0 (+ sum i)))
              ((> i 5) sum)))
        """
        env = make_initial_env()
        compile_ilisp(code, env=env)
        res = compile_ilisp("(calc-do)", env=env)
        assert res == 15
