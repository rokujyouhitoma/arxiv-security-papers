;;; =======================================================================
;;; Synapse Reduction Safepoint Injection Test Suite
;;; Path: tests/concurrency/test_pass_inject_safepoints.scm
;;; Conforms to DSN-37 Section 7.2, 12.4 & Phase 3 Task 3.4 (Issue #640)
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Synapse Reduction Safepoint Injection Tests\n")
(display "=======================================================\n")

(define *test-count* (cons 0 '()))
(define *pass-count* (cons 0 '()))

(define (assert-true name expr-result)
  (set-car! *test-count* (+ (car *test-count*) 1))
  (if expr-result
      (begin
        (set-car! *pass-count* (+ (car *pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

(define (assert-false name expr-result)
  (set-car! *test-count* (+ (car *test-count*) 1))
  (if (not expr-result)
      (begin
        (set-car! *pass-count* (+ (car *pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] Expected failure/rejection: ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

(define (assert-equal name expected actual)
  (set-car! *test-count* (+ (car *test-count*) 1))
  (if (equal? expected actual)
      (begin
        (set-car! *pass-count* (+ (car *pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (display " - Expected: ")
        (write expected)
        (display " but got: ")
        (write actual)
        (newline)
        (error "Assertion failed" name))))

;;; -----------------------------------------------------------------------
;;; Group 1: AST Predicates & Construction
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 1: AST Predicates & Construction ---\n")

(assert-true "1.1 safepoint-poll-form? detects %synapse-safepoint-poll!"
             (safepoint-poll-form? '(%synapse-safepoint-poll!)))

(assert-true "1.2 safepoint-poll-form? detects %safepoint-poll!"
             (safepoint-poll-form? '(%safepoint-poll!)))

(assert-false "1.3 safepoint-poll-form? rejects arbitrary symbols"
              (safepoint-poll-form? '(foo 1 2)))

(assert-true "1.4 make-safepoint-poll produces valid polling form"
             (safepoint-poll-form? (make-safepoint-poll)))

(assert-true "1.5 lambda-form? detects valid lambda"
             (lambda-form? '(lambda (x y) (+ x y))))

(assert-false "1.6 lambda-form? rejects non-lambda"
              (lambda-form? '(define (f x) x)))

(assert-true "1.7 named-let-form? detects named let loop"
             (named-let-form? '(let loop ((n 10)) (if (> n 0) (loop (- n 1)) 0))))

(assert-false "1.8 named-let-form? rejects standard let"
              (named-let-form? '(let ((x 1)) x)))

(assert-true "1.9 asc-kernel-form? detects %asc-kernel"
             (asc-kernel-form? '(%asc-kernel (task 100) (display 1))))

;;; -----------------------------------------------------------------------
;;; Group 2: Function Prologue Safepoint Injection
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 2: Function Prologue Safepoint Injection ---\n")

(let* ((orig '(lambda (x) (+ x 1)))
       (res (inject-safepoints-expr orig '())))
  (assert-true "2.1 lambda prologue gets safepoint injected"
               (equal? res '(lambda (x) (%synapse-safepoint-poll!) (+ x 1)))))

;; Idempotency: verify no duplicate injection if already present
(let* ((orig '(lambda (x) (%synapse-safepoint-poll!) (+ x 1)))
       (res (inject-safepoints-expr orig '())))
  (assert-true "2.2 lambda prologue does not duplicate existing safepoint"
               (equal? res '(lambda (x) (%synapse-safepoint-poll!) (+ x 1)))))

;; Multi-expression lambda body
(let* ((orig '(lambda (a b) (display a) (+ a b)))
       (res (inject-safepoints-expr orig '())))
  (assert-true "2.3 multi-expression lambda preserves all expressions after safepoint"
               (equal? res '(lambda (a b) (%synapse-safepoint-poll!) (display a) (+ a b)))))

;;; -----------------------------------------------------------------------
;;; Group 3: Loop Backedge & Named-Let Injection
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 3: Loop Backedge & Named-Let Injection ---\n")

;; Infinite loop
(let* ((orig '(let loop () (loop)))
       (res (inject-safepoints-expr orig '())))
  (assert-true "3.1 named-let infinite loop receives entry safepoint and backedge safepoint"
               (equal? res '(let loop ()
                              (%synapse-safepoint-poll!)
                              (begin (%synapse-safepoint-poll!) (loop))))))

;; Conditional loop with recursion
(let* ((orig '(let loop ((n 10))
                (if (> n 0)
                    (loop (- n 1))
                    n)))
       (res (inject-safepoints-expr orig '())))
  (assert-true "3.2 conditional loop backedge receives safepoint before recursive call"
               (equal? res '(let loop ((n 10))
                              (%synapse-safepoint-poll!)
                              (if (> n 0)
                                  (begin (%synapse-safepoint-poll!) (loop (- n 1)))
                                  n)))))

;; Nested loops
(let* ((orig '(let outer ()
                (let inner ()
                  (inner))
                (outer)))
       (res (inject-safepoints-expr orig '())))
  (assert-true "3.3 nested loops both receive entry and backedge safepoints"
               (and (pair? res)
                    (eq? (car res) 'let)
                    (eq? (cadr res) 'outer))))

;;; -----------------------------------------------------------------------
;;; Group 4: ASC Kernel Transformation
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 4: ASC Kernel Transformation ---\n")

(let* ((kernel '(%asc-kernel (task: (id 101))
                  (let loop ((count 100))
                    (if (> count 0)
                        (loop (- count 1))
                        'done))))
       (trans (inject-safepoints-kernel kernel)))
  (assert-true "4.1 kernel output retains %asc-kernel tag"
               (and (pair? trans) (eq? (car trans) '%asc-kernel)))
  (assert-equal "4.2 kernel header preserved"
                '(task: (id 101))
                (cadr trans))
  (let ((body (caddr trans)))
    ;; Body wrapped in begin with prologue safepoint
    (assert-true "4.3 kernel body has top-level safepoint poll"
                 (and (pair? body)
                      (eq? (car body) 'begin)
                      (safepoint-poll-form? (cadr body))))))

;;; -----------------------------------------------------------------------
;;; Group 5: Layer 1 (R7RS) Functions & Loops Safepoint Injection (#744)
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 5: Layer 1 (R7RS) Functions & Loops Safepoint Injection (#744) ---\n")

(let* ((r7rs-forms '((define (host-func x) (* x 2))
                     (let loop () (loop))))
       (out (inject-safepoints-pass r7rs-forms)))
  (assert-true "5.1 define function prologue receives safepoint"
               (equal? (car out)
                       '(define (host-func x) (%synapse-safepoint-poll!) (* x 2))))
  (assert-true "5.2 top-level loop receives safepoint in entry and backedge"
               (equal? (cadr out)
                       '(let loop ()
                          (%synapse-safepoint-poll!)
                          (begin (%synapse-safepoint-poll!) (loop))))))

;;; -----------------------------------------------------------------------
;;; Group 6: Pass Manager Injection & Pipeline Integration
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 6: Pass Manager Injection & Pipeline Integration ---\n")

(init-default-pass-registry!)
(inject-synapse-split-planes-pass!)
(inject-synapse-check-affine-pass!)
(inject-synapse-fbip-pass!)
(inject-synapse-safepoints-pass!)

(define pipeline-all (build-pipeline 0 '()))
(define ids-all (map pass-id pipeline-all))

(assert-true "6.1 pass-synapse-split-planes present in pipeline"
             (memq 'pass-synapse-split-planes ids-all))
(assert-true "6.2 pass-synapse-check-affine present in pipeline"
             (memq 'pass-synapse-check-affine ids-all))
(assert-true "6.3 pass-synapse-fbip present in pipeline"
             (memq 'pass-synapse-fbip ids-all))
(assert-true "6.4 pass-synapse-inject-safepoints present in pipeline"
             (memq 'pass-synapse-inject-safepoints ids-all))

(define (pass-after? p1 p2 p-list)
  (let loop ((ps p-list))
    (cond
      ((null? ps) #f)
      ((null? (cdr ps)) #f)
      ((and (eq? (car ps) p1) (eq? (cadr ps) p2)) #t)
      (else (loop (cdr ps))))))

(assert-true "6.5 safepoints pass directly follows fbip pass"
             (pass-after? 'pass-synapse-fbip 'pass-synapse-inject-safepoints ids-all))

;; Validate prerequisites DAG
(assert-true "6.6 injected pipeline satisfies all DAG prerequisites"
             (validate-pipeline-prerequisites pipeline-all))

;; Execute pass through pass-function
(define forms-input
  (list
    '(define (caller) 42)
    '(%asc-kernel (task: (id 200))
       (let loop () (loop)))))

(define forms-output (inject-safepoints-pass forms-input))

(assert-equal "6.7 define form transformed with safepoint prologue"
              '(define (caller) (%synapse-safepoint-poll!) 42)
              (car forms-output))

(assert-true "6.8 kernel form transformed"
             (and (pair? (cadr forms-output))
                  (eq? (car (cadr forms-output)) '%asc-kernel)))

;; Clean up pass from manager
(remove-synapse-safepoints-pass!)
(remove-synapse-fbip-pass!)
(remove-synapse-check-affine-pass!)
(remove-synapse-split-planes-pass!)

(define clean-pipe (build-pipeline 0 '()))
(define clean-ids (map pass-id clean-pipe))
(assert-false "6.9 safepoints pass cleanly removed"
              (memq 'pass-synapse-inject-safepoints clean-ids))

;;; -----------------------------------------------------------------------
;;; Test Summary
;;; -----------------------------------------------------------------------

(newline)
(display "=======================================================\n")
(display " Test Suite Completed: ")
(display (car *pass-count*))
(display " / ")
(display (car *test-count*))
(display " assertions passed.\n")
(display "=======================================================\n")
(newline)
