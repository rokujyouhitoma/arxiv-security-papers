"""Unit, compatibility, and performance tests for ILISP Phase 2 Lexical Slot VM (#940)."""

from __future__ import annotations

import time
from typing import List

from ilisp import run_string, to_py_list
from ilisp.compiler_ir import ensure_compiled
from ilisp.env import make_initial_env
from ilisp.evaluator import StepHookContext, eval_expr
from ilisp.reader import read_all, read_one
from ilisp.types import Symbol


class TestLexicalSlotsAndClosures:
    """Verify multi-level lexical slots, shared set!, internal defines, and TCO."""

    def test_multi_level_closure_shared_mutation(self) -> None:
        code = """
        (define (make-counter start)
          (let ((count start))
            (list
              (lambda () (set! count (+ count 1)) count)
              (lambda (delta) (set! count (+ count delta)) count)
              (lambda () count))))
        (let ((ops (make-counter 10)))
          (list ((car ops))
                ((cadr ops) 5)
                ((caddr ops))
                ((car ops))))
        """
        assert to_py_list(run_string(code)) == [11, 16, 16, 17]

    def test_mutual_letrec_and_internal_defines(self) -> None:
        code = """
        (define (classify-range n)
          (define (even? k) (if (= k 0) #t (odd? (- k 1))))
          (define (odd? k) (if (= k 0) #f (even? (- k 1))))
          (letrec ((step (lambda (i acc)
                           (if (< i 0)
                               (reverse acc)
                               (step (- i 1) (cons (if (even? i) 'E 'O) acc))))))
            (step n '())))
        (classify-range 4)
        """
        syms = [s.name for s in to_py_list(run_string(code))]
        assert syms == ["E", "O", "E", "O", "E"]

    def test_variadic_and_dotted_params(self) -> None:
        code = """
        (define (f-all . args) (length args))
        (define (f-dotted a b . rest) (list a b (length rest) rest))
        (list (f-all) (f-all 1 2 3) (f-dotted 10 20) (f-dotted 10 20 30 40))
        """
        res = to_py_list(run_string(code))
        assert res[0] == 0
        assert res[1] == 3
        assert res[2].car == 10 and res[2].cdr.car == 20 and res[2].cdr.cdr.car == 0
        assert res[3].car == 10 and res[3].cdr.car == 20 and res[3].cdr.cdr.car == 2
        assert to_py_list(res[3].cdr.cdr.cdr.car) == [30, 40]

    def test_let_star_do_and_non_tail_named_let(self) -> None:
        # 1. let* duplicate variable closure capture
        code_let_star = """
        (define (f-let-star)
          (let* ((x 1)
                 (g (lambda () x))
                 (x 2))
            (list (g) x)))
        (f-let-star)
        """
        assert to_py_list(run_string(code_let_star)) == [1, 2]

        # 2. do per-iteration closure capture
        code_do = """
        (define (f-do)
          (let ((thunks (do ((i 0 (+ i 1))
                             (acc '() (cons (lambda () i) acc)))
                            ((= i 4) (reverse acc)))))
            (map (lambda (th) (th)) thunks)))
        (f-do)
        """
        assert to_py_list(run_string(code_do)) == [0, 1, 2, 3]

        # 3. Non-tail Named let inside expression (regression for Issue #940 Form #1804)
        code_nontail = """
        (define (partition-wrapper items)
          (let ((pairs (let loop ((rem items) (acc '()))
                         (if (null? rem)
                             (reverse acc)
                             (loop (cdr rem) (cons (list (car rem) (+ (car rem) 10)) acc))))))
            (map (lambda (p) (+ (car p) (cadr p))) pairs)))
        (partition-wrapper '(1 2 3))
        """
        assert to_py_list(run_string(code_nontail)) == [12, 14, 16]

    def test_deep_tail_recursion_in_vm(self) -> None:
        code = """
        (define (ping n acc)
          (if (<= n 0) acc (pong (- n 1) (+ acc 1))))
        (define (pong n acc)
          (if (<= n 0) acc (ping (- n 1) (+ acc 2))))
        (define (loop-tail limit)
          (let loop ((i limit) (s 0))
            (if (<= i 0) s (loop (- i 1) (+ s i)))))
        (list (ping 50000 0) (loop-tail 50000))
        """
        assert to_py_list(run_string(code)) == [75000, 1250025000]


class TestVMSafetyInvariants:
    """Verify macro epoch invalidation, builtin redefinition guards, fallbacks, and hooks."""

    def test_macro_epoch_recompilation(self) -> None:
        env = make_initial_env(preload_stdlib=True)
        src_1 = """
        (define-macro (tag-val x) `(list 'v1 ,x))
        (define (use-macro n) (tag-val (+ n 1)))
        """
        for form in read_all(src_1):
            eval_expr(form, env)

        r1 = to_py_list(eval_expr(read_one("(use-macro 9)"), env))
        assert [r1[0].name, r1[1]] == ["v1", 10]
        fn = env.lookup(Symbol.intern("use-macro"))
        code1 = ensure_compiled(fn)
        assert code1 is not None and code1.uses_macros is True

        # Redefine macro via define-macro -> must invalidate cached CodeObject
        eval_expr(read_one("(define-macro (tag-val x) `(list 'v2 (* ,x 10)))"), env)
        r2 = to_py_list(eval_expr(read_one("(use-macro 9)"), env))
        assert [r2[0].name, r2[1]] == ["v2", 100]

        # Also test define-syntax invalidation
        src_2 = """
        (define-syntax scale-x (syntax-rules () ((scale-x y) (+ y 1))))
        (define (use-syn n) (scale-x n))
        """
        for form in read_all(src_2):
            eval_expr(form, env)
        assert eval_expr(read_one("(use-syn 5)"), env) == 6
        eval_expr(
            read_one("(define-syntax scale-x (syntax-rules () ((scale-x y) (* y 3))))"),
            env,
        )
        assert eval_expr(read_one("(use-syn 5)"), env) == 15

    def test_superinstruction_shadow_and_redefinition_guard(self) -> None:
        code = """
        (define (calc-local x y)
          (let ((+ *) (car (lambda (p) (cdr p))))
            (list (+ x y) (car (cons 'a 'b)))))
        (calc-local 6 7)
        """
        res_local = to_py_list(run_string(code))
        assert res_local[0] == 42 and res_local[1] == Symbol.intern("b")

        # Top-level builtin redefinition must bypass superinstruction fast path cleanly
        env = make_initial_env(preload_stdlib=True)
        eval_expr(read_one("(define (top-add a b) (+ a b))"), env)
        assert eval_expr(read_one("(top-add 3 4)"), env) == 7
        eval_expr(read_one("(define orig-plus +)"), env)
        eval_expr(read_one("(set! + *)"), env)
        assert eval_expr(read_one("(top-add 3 4)"), env) == 12
        eval_expr(read_one("(set! + orig-plus)"), env)
        assert eval_expr(read_one("(top-add 3 4)"), env) == 7

    def test_hybrid_fallback_guard_callcc_quasiquote_and_writeback(self) -> None:
        code = """
        (define (hybrid-fn x)
          (let ((acc x))
            (guard (ex (else (list 'caught ex acc)))
              (set! acc (+ acc 5))
              (if (> acc 10)
                  (raise 'boom)
                  `(ok ,acc ,(+ acc 1))))))
        (define (cc-test x)
          (+ 1 (call/cc (lambda (k) (k (* x 10))))))
        (list (hybrid-fn 2) (hybrid-fn 8) (cc-test 4))
        """
        res = to_py_list(run_string(code))
        ok_res = to_py_list(res[0])
        err_res = to_py_list(res[1])
        assert [ok_res[0].name, ok_res[1], ok_res[2]] == ["ok", 7, 8]
        assert [err_res[0].name, err_res[1].name, err_res[2]] == ["caught", "boom", 13]
        assert res[2] == 41

    def test_step_hook_inside_vm(self) -> None:
        env = make_initial_env(preload_stdlib=True)
        eval_expr(
            read_one("(define (count-down n) (if (<= n 0) 0 (count-down (- n 1))))"),
            env,
        )
        # Warm compilation first
        assert eval_expr(read_one("(count-down 5)"), env) == 0
        steps: List[int] = [0]

        def hook() -> None:
            steps[0] += 1

        with StepHookContext(hook):
            res = eval_expr(read_one("(count-down 10)"), env)
        assert res == 0
        assert steps[0] >= 10

    def test_dotted_symbol_local_variable_in_vm(self) -> None:
        from types import SimpleNamespace

        env = make_initial_env(preload_stdlib=True)
        env.define(Symbol.intern("mock-res"), SimpleNamespace(status_code=204))
        for form in read_all("(define (get-status response) response.status_code)"):
            eval_expr(form, env)
        assert eval_expr(read_one("(get-status mock-res)"), env) == 204


class TestVMPerformanceGate:
    """Verify 4-workload microbenchmark speedup stays well below regression threshold."""

    def test_four_workload_microbench_speed(self) -> None:
        code = """
        (define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
        (define (sum-loop n acc) (if (<= n 0) acc (sum-loop (- n 1) (+ acc n))))
        (define (list-ops n)
          (let loop ((i n) (xs '()))
            (if (<= i 0)
                (length (reverse (map (lambda (x) (+ x 1)) xs)))
                (loop (- i 1) (cons i xs)))))
        (define (cond-dispatch n)
          (let loop ((i n) (acc 0))
            (if (<= i 0) acc
                (loop (- i 1)
                      (+ acc (cond ((= (modulo i 4) 0) 1)
                                   ((= (modulo i 4) 1) 2)
                                   ((= (modulo i 4) 2) 3)
                                   (else 4)))))))
        (list (fib 20) (sum-loop 50000 0) (list-ops 20000) (cond-dispatch 20000))
        """
        env = make_initial_env(preload_stdlib=True)
        forms = read_all(code)
        t0 = time.perf_counter()
        res = None
        for f in forms:
            res = eval_expr(f, env)
        elapsed = time.perf_counter() - t0
        assert to_py_list(res) == [6765, 1250025000, 20000, 50000]
        assert elapsed < 1.5, f"4-workload microbench too slow: {elapsed:.3f}s"
