;;; =======================================================================
;;; Unit & Integration Test Suite: Synapse Dual-Mode Evaluation Adapter (#644)
;;; Conforms to DSN-37 Section 13, Section 14.7 (Phase 5 Task 5.3) & Issue #644
;;;
;;; Tests:
;;;   Group 1: Affine Syntax Linter (CWE-416 / Double-Move & set! Guard)
;;;   Group 2: Scope Environment Operations & Identifier Resolution
;;;   Group 3: S-expression Tree-walk Evaluation & Primitive Operations
;;;   Group 4: Reduction-Accounting & Deterministic Preemptive Safepoint Yielding (CWE-400)
;;;   Group 5: Dynamic Task Arena Scoping & O(1) Instant Reclaim
;;;   Group 6: Inter-Task Linear Channel Messaging Integration
;;;   Group 7: Security Guards, Type Distinctions & Error Handling (CWE-843 / CWE-190)
;;; =======================================================================

(load "ulisp/runtime/concurrency/arena.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")
(load "ulisp/runtime/concurrency/preempt.scm")
(load "ulisp/runtime/concurrency/eval_adapter.scm")

(define *test-eval-failures* (vector 0))
(define *test-eval-passes* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-eval-failures* 0 (+ (vector-ref *test-eval-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-eval-passes* 0 (+ (vector-ref *test-eval-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (deep-equal? a b)
  (cond
    ((eqv? a b) #t)
    ((and (string? a) (string? b))
     (string=? a b))
    ((and (pair? a) (pair? b))
     (and (deep-equal? (car a) (car b))
          (deep-equal? (cdr a) (cdr b))))
    ((and (vector? a) (vector? b))
     (let ((len (vector-length a)))
       (if (= len (vector-length b))
           (let loop ((i 0))
             (if (< i len)
                 (if (deep-equal? (vector-ref a i) (vector-ref b i))
                     (loop (+ i 1))
                     #f)
                 #t))
           #f)))
    (else #f)))

(define (assert-equal actual expected msg)
  (if (not (deep-equal? actual expected))
      (begin
        (vector-set! *test-eval-failures* 0 (+ (vector-ref *test-eval-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-string " (expected ")
        (if (integer? expected) (write-string (number->string expected)) (write-string "<val>"))
        (write-string ", got ")
        (if (integer? actual) (write-string (number->string actual)) (write-string "<val>"))
        (write-string ")\n")
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-eval-passes* 0 (+ (vector-ref *test-eval-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(write-string "=======================================================\n")
(write-string " Starting Dual-Mode Evaluation Adapter Test Suite (#644)\n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: Affine Syntax Linter (CWE-416 Guard)
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Affine Syntax Linter ---\n")
(flush-output-port)

(let* ()
  ;; Valid pure affine expressions
  (assert-true (affine-syntax-valid? '(+ 1 2)) "pure arithmetic is affine valid")
  (assert-true (affine-syntax-valid? '(if (> x 0) (* x 2) 0)) "branching expression is affine valid")
  (assert-true (affine-syntax-valid? '(let ((x 10)) (+ x 5))) "let expression is affine valid")
  (assert-true (affine-syntax-valid? '(lambda (x) (* x x))) "unrestricted lambda is affine valid")

  ;; set! prohibition (CWE-416 guard)
  (let ((res (lint-affine-syntax '(set! x 100))))
    (assert-true (and (pair? res) (eq? (car res) 'error)) "set! is detected as error")
    (assert-true (eq? (cadr res) 'forbidden-set!) "error reason is forbidden-set!"))

  (let ((res (lint-affine-syntax '(begin (+ 1 2) (set! y 42)))))
    (assert-true (and (pair? res) (eq? (car res) 'error)) "nested set! inside begin is detected")
    (assert-true (eq? (cadr res) 'forbidden-set!) "nested set! returns forbidden-set!"))

  (assert-true (not (affine-syntax-valid? '(let ((x 1)) (begin (set! x 2) x)))) "affine-syntax-valid? rejects set!")

  ;; Linear variable double-move detection
  (let ((expr '(begin (channel-send! ch 10) (channel-send! ch 20))))
    (let ((res (lint-affine-syntax expr '(ch))))
      (assert-true (and (pair? res) (eq? (car res) 'error)) "double consumption of linear var is rejected")
      (assert-true (eq? (cadr res) 'double-move) "error reason is double-move")
      (assert-true (eq? (cddr res) 'ch) "error identifies offending linear symbol ch")))

  ;; Branching linear variable: consuming once in either branch is allowed
  (let ((branching-expr '(if (> flag 0) (channel-send! ch 1) (channel-send! ch 2))))
    (assert-true (affine-syntax-valid? branching-expr '(ch))
                 "consuming linear var in mutually exclusive if branches is permitted"))

  ;; Branching linear variable: double-use in test + branch is rejected
  (let ((bad-branching '(if (channel-recv! ch) (channel-send! ch 1) #f)))
    (assert-true (not (affine-syntax-valid? bad-branching '(ch)))
                 "consuming linear var in test and then branch is rejected as double-move"))

  ;; Triple Move rejection
  (let ((triple-expr '(begin (channel-send! ch 1) (channel-send! ch 2) (channel-send! ch 3))))
    (assert-true (not (affine-syntax-valid? triple-expr '(ch)))
                 "triple consumption of linear var is rejected"))

  ;; Affine validity on self-evaluating literals
  (assert-true (affine-syntax-valid? 42) "fixnum is affine valid")
  (assert-true (affine-syntax-valid? "string") "string is affine valid"))

;; -----------------------------------------------------------------------
;; Group 2: Scope Environment Operations & Identifier Resolution
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Scope Environment Operations ---\n")
(flush-output-port)

(let* ((env1 (make-eval-env)))
  (assert-true (eval-env? env1) "make-eval-env creates <eval-env>")
  (assert-true (not (eval-env? 'not-an-env)) "symbol is not eval-env")
  (assert-true (not (eval-env? (vector 1 2))) "vector is not eval-env")
  (assert-equal (eval-env-parent env1) #f "root env has parent #f")

  ;; Binding and lookup
  (eval-env-bind! env1 'x 42)
  (eval-env-bind! env1 'msg "hello")
  (assert-equal (eval-env-lookup env1 'x) 42 "lookup returns bound fixnum")
  (assert-equal (eval-env-lookup env1 'msg) "hello" "lookup returns bound string")
  (assert-true (eval-env-bound? env1 'x) "eval-env-bound? returns #t for existing symbol")
  (assert-true (not (eval-env-bound? env1 'unbound-sym)) "eval-env-bound? returns #f for missing symbol")

  ;; Nested environment shadowing
  (let ((env2 (make-eval-env env1)))
    (assert-true (eq? (eval-env-parent env2) env1) "child env points to parent env")
    (assert-equal (eval-env-lookup env2 'x) 42 "child env delegates to parent")
    (eval-env-bind! env2 'x 999)
    (assert-equal (eval-env-lookup env2 'x) 999 "child env shadows parent binding")
    (assert-equal (eval-env-lookup env1 'x) 42 "parent binding remains untouched"))

  ;; Rebinding in same environment
  (eval-env-bind! env1 'x 100)
  (assert-equal (eval-env-lookup env1 'x) 100 "re-binding updates value in same scope"))

;; -----------------------------------------------------------------------
;; Group 3: S-expression Tree-walk Evaluation & Primitive Operations
;; -----------------------------------------------------------------------
(write-string "--- Group 3: S-expression Tree-walk Evaluation ---\n")
(flush-output-port)

(let* ((env (make-default-eval-env)))
  ;; Literals
  (assert-equal (eval-in-task 123 env #f) 123 "eval integer literal")
  (assert-equal (eval-in-task #t env #f) #t "eval boolean literal")
  (assert-equal (eval-in-task "synapse" env #f) "synapse" "eval string literal")
  (assert-equal (eval-in-task '(quote (a b c)) env #f) '(a b c) "eval quote datum")

  ;; Arithmetic & Logic
  (assert-equal (eval-in-task '(+ 10 20 30) env #f) 60 "eval (+ 10 20 30)")
  (assert-equal (eval-in-task '(- 100 (* 5 8)) env #f) 60 "eval nested arithmetic")
  (assert-equal (eval-in-task '(if (> 10 5) 'yes 'no) env #f) 'yes "eval (if (> 10 5) 'yes 'no)")
  (assert-equal (eval-in-task '(if (< 10 5) 'yes 'no) env #f) 'no "eval false branch of if")
  (assert-equal (eval-in-task '(begin (+ 1 2) (* 3 4)) env #f) 12 "eval (begin ...)")

  ;; Let & Let*
  (assert-equal (eval-in-task '(let ((a 10) (b 20)) (+ a b)) env #f) 30 "eval let expression")
  (assert-equal (eval-in-task '(let* ((a 5) (b (* a 2)) (c (+ b 3))) (+ a b c)) env #f) 28 "eval let* expression")

  ;; Lambda & Closure Application
  (assert-equal (eval-in-task '((lambda (x) (* x x)) 9) env #f) 81 "eval immediate lambda application")
  (assert-equal (eval-in-task '(let ((sq (lambda (x) (* x x)))) (sq 12)) env #f) 144 "eval bound lambda closure")

  ;; Recursive Function Definition
  (eval-in-task '(define (fact n) (if (<= n 1) 1 (* n (fact (- n 1))))) env #f)
  (assert-equal (eval-in-task '(fact 5) env #f) 120 "eval recursive factorial (fact 5)")
  (assert-equal (eval-in-task '(fact 6) env #f) 720 "eval recursive factorial (fact 6)")

  ;; Additional Builtins
  (assert-equal (eval-in-task '(quotient 40 3) env #f) 13 "eval (quotient 40 3)")
  (assert-equal (eval-in-task '(modulo 40 3) env #f) 1 "eval (modulo 40 3)")
  (assert-equal (eval-in-task '(- 50) env #f) -50 "eval (- 50) unary negation")
  (assert-equal (eval-in-task '(* 2 3 4) env #f) 24 "eval (* 2 3 4) multi-arg product"))

;; -----------------------------------------------------------------------
;; Group 4: Reduction Accounting & Preemptive Safepoint Yielding (CWE-400)
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Reduction Accounting & Preemption ---\n")
(flush-output-port)

(let* ((btask (make-budgeted-task 101 #f 50))
       (env (make-default-eval-env))
       (yield-count-box (vector 0)))
  ;; Configure yield hook to monitor preemption
  (set-eval-yield-hook!
   (lambda (t)
     (vector-set! yield-count-box 0 (+ (vector-ref yield-count-box 0) 1))))

  (assert-equal (task-reductions btask) 50 "initial reductions budget is 50")

  ;; Single simple evaluation consumes 1 reduction
  (eval-in-task '(+ 1 2) env btask)
  ;; (+ 1 2) involves application step + sub-steps (+, 1, 2)
  (assert-true (< (task-reductions btask) 50) "reductions budget was decremented")
  (assert-equal (vector-ref yield-count-box 0) 0 "yield hook not triggered before exhaustion")

  ;; Run a deterministic iterative loop that exceeds the 50 reductions budget
  (eval-in-task '(define (countdown n)
                   (if (<= n 0)
                       'done
                       (countdown (- n 1))))
                env btask)
  (let ((res (eval-in-task '(countdown 100) env btask)))
    (assert-equal res 'done "countdown loop completed successfully")
    (assert-true (> (vector-ref yield-count-box 0) 0)
                 "safepoint preemption yield was automatically triggered when budget exhausted (CWE-400)")
    (assert-true (> (task-exhaustion-count btask) 0)
                 "task exhaustion count was incremented on preemption"))

  (set-eval-yield-hook! #f))

;; -----------------------------------------------------------------------
;; Group 5: Dynamic Task Arena Scoping & O(1) Instant Reclaim
;; -----------------------------------------------------------------------
(write-string "--- Group 5: Dynamic Task Arena Scoping ---\n")
(flush-output-port)

(let* ((arena (make-task-arena 4096))
       (btask (make-budgeted-task 102 arena 1000))
       (env (make-default-eval-env)))
  (assert-equal (current-task-arena) #f "outside with-task-arena, current-task-arena is #f")

  ;; with-task-arena dynamically binds current-task-arena
  (let ((captured (with-task-arena arena
                    (lambda ()
                      (current-task-arena)))))
    (assert-true (eq? captured arena) "current-task-arena points to bound arena inside thunk"))
  (assert-equal (current-task-arena) #f "current-task-arena restored to #f after thunk")

  ;; Evaluate allocation inside task
  (assert-equal (arena-offset arena) 0 "arena offset is initially 0")
  (eval-in-task '(arena-allocate! (current-task-arena) 128) env btask)
  (assert-true (>= (arena-offset arena) 128) "eval-in-task allocated 128 bytes from task arena")

  ;; O(1) instant reset
  (eval-in-task '(arena-reset! (current-task-arena)) env btask)
  (assert-equal (arena-offset arena) 0 "arena-reset! inside task instantly resets offset to 0 (O(1) Reclaim)"))

;; -----------------------------------------------------------------------
;; Group 6: Inter-Task Linear Channel Messaging Integration
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Linear Channel Messaging in Evaluator ---\n")
(flush-output-port)

(let* ((env (make-default-eval-env))
       (btask (make-budgeted-task 103 #f 1000)))
  ;; Create channel in interpreter
  (eval-in-task '(define ch (make-channel 10)) env btask)
  (assert-true (eval-in-task '(channel? ch) env btask) "ch satisfies channel?")

  ;; Send messages through channel in interpreter
  (assert-true (eval-in-task '(channel-send! ch 42) env btask) "channel-send! 42 succeeds")
  (assert-true (eval-in-task '(channel-send! ch 100) env btask) "channel-send! 100 succeeds")

  ;; Receive messages
  (assert-equal (eval-in-task '(channel-recv! ch) env btask) 42 "channel-recv! receives 42")
  (assert-equal (eval-in-task '(channel-recv! ch) env btask) 100 "channel-recv! receives 100")

  ;; Close channel
  (eval-in-task '(channel-close! ch) env btask)
  (let ((closed-send (guard (exn (#t #t)) (eval-in-task '(channel-send! ch 999) env btask) #f)))
    (assert-true closed-send "sending to closed channel in evaluator is cleanly rejected"))
  (write-string "  [STATUS]: Linear Channel in Evaluator works seamlessly\n"))

;; -----------------------------------------------------------------------
;; Group 7: Security Guards, Type Distinctions & Error Handling
;; -----------------------------------------------------------------------
(write-string "--- Group 7: Security Guards & Error Handling ---\n")
(flush-output-port)

(let* ((env (make-default-eval-env)))
  ;; CWE-843: Type confusion guard on make-eval-env
  (let ((bad-parent (guard (exn (#t #t)) (make-eval-env 'invalid-parent) #f)))
    (assert-true bad-parent "make-eval-env rejects invalid parent (CWE-843 guard)"))

  ;; CWE-843: Type confusion guard on eval-env-bind!
  (let ((bad-env (guard (exn (#t #t)) (eval-env-bind! 'not-an-env 'x 1) #f)))
    (assert-true bad-env "eval-env-bind! rejects non-env object (CWE-843 guard)"))

  (let ((bad-key (guard (exn (#t #t)) (eval-env-bind! env 12345 1) #f)))
    (assert-true bad-key "eval-env-bind! rejects non-symbol key (CWE-843 guard)"))

  ;; CWE-843: Unbound variable lookup produces clean error
  (let ((unbound-res (guard (exn (#t #t)) (eval-in-task 'undefined-variable-xyz env #f) #f)))
    (assert-true unbound-res "unbound variable produces clean exception"))

  ;; CWE-843: Non-procedure application produces clean error
  (let ((bad-app (guard (exn (#t #t)) (eval-in-task '(123 456) env #f) #f)))
    (assert-true bad-app "applying non-procedure produces clean exception"))

  ;; CWE-843: Invalid task object in with-task-arena
  (let ((bad-task (guard (exn (#t #t)) (with-task-arena 'not-a-task (lambda () #t)) #f)))
    (assert-true bad-task "with-task-arena rejects invalid task object (CWE-843 guard)")))

;; -----------------------------------------------------------------------
;; Group 8: Fault-Tolerance, Boundary & Subsystem Fallback Guards (#738)
;; -----------------------------------------------------------------------
(write-string "--- Group 8: Fault-Tolerance, Boundary & Subsystem Fallback Guards (#738) ---\n")
(flush-output-port)

(let* ((env (make-default-eval-env))
       (t (make-task-context 999 50)))
  ;; 1. with-synapse-task-boundary executes closure and returns (ok . val)
  (let ((res (eval-in-task '(with-synapse-task-boundary task (lambda () (+ 100 200)))
                           (let ((e (make-eval-env env)))
                             (begin (eval-env-bind! e 'task t) e))
                           t)))
    (assert-true (pair? res) "boundary returns pair")
    (assert-equal (car res) 'ok "boundary status is ok")
    (assert-equal (cdr res) 300 "boundary result is 300"))

  ;; 2. with-synapse-task-boundary establishes current-synapse-task
  (let* ((t2 (make-task-context 1000 50))
         (e2 (make-eval-env env)))
    (eval-env-bind! e2 'task t2)
    (let ((res (eval-in-task '(with-synapse-task-boundary task (lambda () (task-id (current-synapse-task))))
                             e2
                             t2)))
      (assert-equal (car res) 'ok "current task query inside boundary is ok")
      (assert-equal (cdr res) 1000 "current task inside boundary matches task-id")))

  ;; 3. synapse-panic! inside boundary escapes and returns panic
  (let* ((t3 (make-task-context 1001 50))
         (e3 (make-eval-env env)))
    (eval-env-bind! e3 'task t3)
    (let ((res (eval-in-task '(with-synapse-task-boundary task (lambda () (synapse-panic! 'test-crash)))
                             e3
                             t3)))
      (assert-true (pair? res) "panic inside boundary returns pair")
      (assert-equal (car res) 'panic "panic status is panic")
      (assert-equal (task-state t3) 'terminated "task is marked terminated after panic")))

  ;; 4. synapse-panic! outside task boundary raises error (not silent #f)
  (let ((outside-err (guard (exn (#t #t)) (synapse-panic! 'outside-crash) #f)))
    (assert-true outside-err "synapse-panic! outside boundary raises explicit error (not #f)"))

  ;; 5. synapse-assert-true! returns #t on true, panics on false
  (assert-true (synapse-assert-true! #t "should pass") "synapse-assert-true! returns #t on true")
  (let* ((t4 (make-task-context 1002 50))
         (e4 (make-eval-env env)))
    (eval-env-bind! e4 'task t4)
    (let ((res (eval-in-task '(with-synapse-task-boundary task (lambda () (synapse-assert-true! #f "must fail")))
                             e4
                             t4)))
      (assert-equal (car res) 'panic "synapse-assert-true! failure inside boundary triggers panic")))

  ;; 6. Subsystem stubs throw explicit error instead of silent #f
  (let ((sup-err (guard (exn (#t #t)) (supervisor-handle-child-down! 'sup 1 'crash) #f)))
    (assert-true sup-err "supervisor-handle-child-down! throws error without supervisor subsystem"))

  (let ((link-err (guard (exn (#t #t)) (task-link! t t) #f)))
    (assert-true link-err "task-link! throws error without links subsystem"))

  (let ((reg-err (guard (exn (#t #t)) (synapse-register! 'svc t) #f)))
    (assert-true reg-err "synapse-register! throws error without registry subsystem"))

  (let ((io-err (guard (exn (#t #t)) (make-io-uring) #f)))
    (assert-true io-err "make-io-uring throws error without native io_uring subsystem")))

;; -----------------------------------------------------------------------
;; Test Suite Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Dual-Mode Evaluation Adapter Summary: ")
(write-string (number->string (vector-ref *test-eval-passes* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *test-eval-failures* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *test-eval-failures* 0) 0)
    (error "Test Suite Failed" (vector-ref *test-eval-failures* 0)))

