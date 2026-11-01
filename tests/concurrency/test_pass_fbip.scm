;;; =======================================================================
;;; Synapse FBIP (Perceus) In-Place Reuse Test Suite
;;; Path: tests/concurrency/test_pass_fbip.scm
;;; Conforms to DSN-37 Section 1.1, 12.3 & Phase 3 Task 3.3 (Issue #639)
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Synapse FBIP In-Place Reuse Tests\n")
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
;;; Group 1: FBIP Predicates & Drop Collection
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: FBIP Predicates & Drop Collection ---\n")

(assert-true "1.1 affine-drop-form? detects %affine-drop!"
             (affine-drop-form? '(%affine-drop! old-pair)))

(assert-false "1.2 affine-drop-form? rejects other symbols"
              (affine-drop-form? '(drop! old-pair)))

(assert-true "1.3 cons-form? detects binary cons"
             (cons-form? '(cons a b)))

(assert-false "1.4 cons-form? rejects unary cons"
              (cons-form? '(cons a)))

(assert-false "1.5 cons-form? rejects ternary cons"
              (cons-form? '(cons a b c)))

(define sample-block
  '(let ((__raii_res (cons 1 2)))
     (begin
       (%affine-drop! p1)
       (%affine-drop! p2)
       __raii_res)))

(define collected (collect-drops sample-block))
(assert-true "1.6 collect-drops collects p1"
             (memq 'p1 collected))
(assert-true "1.7 collect-drops collects p2"
             (memq 'p2 collected))

;;; -----------------------------------------------------------------------
;;; Group 2: Cons In-Place Reuse Transformation
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Cons In-Place Reuse Transformation ---\n")

(define test-input-1
  '(let ((__raii_res (cons (+ h 1) t)))
     (begin
       (%affine-drop! old-pair)
       __raii_res)))

(define trans-res-1 (fbip-transform-block test-input-1 '(old-pair)))
(define trans-ast-1 (car trans-res-1))

;; The cons should be converted to (%fbip-reuse-pair! old-pair (+ h 1) t)
(define binding-1 (caadr trans-ast-1))
(define init-expr-1 (cadr binding-1))

(assert-true "2.1 fresh cons converted to %fbip-reuse-pair!"
             (and (pair? init-expr-1) (eq? (car init-expr-1) '%fbip-reuse-pair!)))

(assert-equal "2.2 target of reuse is old-pair"
              'old-pair
              (cadr init-expr-1))

(assert-equal "2.3 car argument preserved"
              '(+ h 1)
              (caddr init-expr-1))

(assert-equal "2.4 cdr argument preserved"
              't
              (cadddr init-expr-1))

;; Verify redundant drop is removed from body
(define body-1 (cddr trans-ast-1))
(assert-false "2.5 redundant %affine-drop! is eliminated"
              (let loop ((e body-1))
                (cond
                  ((not (pair? e)) #f)
                  ((affine-drop-form? e) #t)
                  (else (or (loop (car e)) (loop (cdr e)))))))

;;; -----------------------------------------------------------------------
;;; Group 3: Non-Reused Allocations (Preserve Fresh Cons)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Non-Reused Allocations ---\n")

(define test-no-drop
  '(let ((p (cons 10 20)))
     p))

(define trans-res-2 (fbip-transform-block test-no-drop '()))
(define trans-ast-2 (car trans-res-2))

(define init-expr-2 (cadr (caadr trans-ast-2)))
(assert-equal "3.1 cons without available drop remains normal cons"
              '(cons 10 20)
              init-expr-2)

;;; -----------------------------------------------------------------------
;;; Group 4: ASC Kernel Level FBIP Transformation
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: ASC Kernel FBIP Transformation ---\n")

(define kernel-with-drop
  '(%asc-kernel (list-map-worker old-pair)
     (let ((h (car old-pair))
           (t (cdr old-pair)))
       (let ((__raii_res (cons (+ h 1) t)))
         (begin
           (%affine-drop! old-pair)
           __raii_res)))))

(define trans-k (fbip-transform-kernel kernel-with-drop))

(assert-true "4.1 kernel output is %asc-kernel"
             (and (pair? trans-k) (eq? (car trans-k) '%asc-kernel)))

(define trans-k-body (caddr trans-k))
(assert-false "4.2 kernel body has no leftover %affine-drop!"
              (let loop ((e trans-k-body))
                (cond
                  ((not (pair? e)) #f)
                  ((affine-drop-form? e) #t)
                  (else (or (loop (car e)) (loop (cdr e)))))))

;;; -----------------------------------------------------------------------
;;; Group 5: Pass Manager Injection & Pipeline Integration
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Pass Manager Injection & Pipeline Integration ---\n")

(init-default-pass-registry!)
(inject-synapse-split-planes-pass!)
(inject-synapse-check-affine-pass!)
(inject-synapse-fbip-pass!)

(define pipeline-all (build-pipeline 0 '()))
(define ids-all (map pass-id pipeline-all))

(assert-true "5.1 pass-synapse-split-planes in pipeline"
             (memq 'pass-synapse-split-planes ids-all))

(assert-true "5.2 pass-synapse-check-affine in pipeline"
             (memq 'pass-synapse-check-affine ids-all))

(assert-true "5.3 pass-synapse-fbip in pipeline"
             (memq 'pass-synapse-fbip ids-all))

(define (pass-after? p1 p2 p-list)
  (let loop ((ps p-list))
    (cond
      ((null? ps) #f)
      ((null? (cdr ps)) #f)
      ((and (eq? (car ps) p1) (eq? (cadr ps) p2)) #t)
      (else (loop (cdr ps))))))

(assert-true "5.4 fbip pass directly follows check-affine pass"
             (pass-after? 'pass-synapse-check-affine 'pass-synapse-fbip ids-all))

(assert-true "5.5 pipeline satisfies all DAG prerequisites"
             (validate-pipeline-prerequisites pipeline-all))

;; Forms list execution
(define forms-input
  (list
    '(define (caller) 42)
    kernel-with-drop))

(define forms-output (fbip-pass forms-input))

(assert-equal "5.6 non-kernel form preserved"
              '(define (caller) 42)
              (car forms-output))

(assert-true "5.7 kernel form transformed"
             (and (pair? (cadr forms-output)) (eq? (car (cadr forms-output)) '%asc-kernel)))

;; Clean removal
(remove-synapse-fbip-pass!)
(remove-synapse-check-affine-pass!)
(remove-synapse-split-planes-pass!)
(define clean-pipe (build-pipeline 0 '()))

(assert-false "5.8 fbip pass cleanly removed"
              (memq 'pass-synapse-fbip (map pass-id clean-pipe)))

(display "\n=======================================================\n")
(display " Test Suite Completed: ")
(display (car *pass-count*))
(display " / ")
(display (car *test-count*))
(display " assertions passed.\n")
(display "=======================================================\n\n")

