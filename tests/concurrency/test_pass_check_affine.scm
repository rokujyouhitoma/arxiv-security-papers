;;; =======================================================================
;;; Synapse Affine Ownership Check & RAII Drop Test Suite
;;; Path: tests/concurrency/test_pass_check_affine.scm
;;; Conforms to DSN-37 Section 4.3, 12.2 & Phase 3 Task 3.2 (Issue #638)
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Synapse Affine Linearity & RAII Drop Tests\n")
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
;;; Group 1: Linear Variable Predicates & Environment Operations
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Linear Variable Predicates & Environment ---\n")

(assert-true "1.1 rx is linear"
             (linear-variable? 'rx))

(assert-true "1.2 tx is linear"
             (linear-variable? 'tx))

(assert-true "1.3 chan is linear"
             (linear-variable? 'chan))

(assert-true "1.4 data-channel is linear"
             (linear-variable? 'data-channel))

(assert-true "1.5 payload-buf is linear"
             (linear-variable? 'payload-buf))

(assert-false "1.6 count is not linear"
              (linear-variable? 'count))

(assert-false "1.7 x is not linear"
              (linear-variable? 'x))

(define env1 (lin-env-add-available '() 'rx))
(assert-equal "1.8 lin-env-add-available records available status"
              'available
              (lin-env-lookup env1 'rx))

(define env2 (lin-env-set env1 'rx 'moved))
(assert-equal "1.9 lin-env-set records moved status"
              'moved
              (lin-env-lookup env2 'rx))

(define env3 (lin-env-add-available env2 'tx))
(assert-equal "1.10 lin-env-unconsumed returns only available variables"
              '(tx)
              (lin-env-unconsumed env3))

;;; -----------------------------------------------------------------------
;;; Group 2: Forbidden Syntax & Side-Effects (CWE-362)
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Forbidden Syntax & Side-Effects ---\n")

(assert-true "2.1 set! is forbidden"
             (affine-forbidden-syntax? 'set!))

(assert-true "2.2 set-car! is forbidden"
             (affine-forbidden-syntax? 'set-car!))

(assert-true "2.3 vector-set! is forbidden"
             (affine-forbidden-syntax? 'vector-set!))

(assert-true "2.4 call/cc is forbidden"
             (affine-forbidden-syntax? 'call/cc))

(assert-true "2.5 dynamic-wind is forbidden"
             (affine-forbidden-syntax? 'dynamic-wind))

(define val-set-expr
  '(begin
     (set! x 42)
     x))

(define r-set (validate-affine-ast val-set-expr '()))
(assert-equal "2.6 validate-affine-ast catches set!"
              '(error forbidden-syntax set!)
              r-set)

(define val-callcc-expr
  '(call/cc (lambda (k) (k 10))))

(define r-callcc (validate-affine-ast val-callcc-expr '()))
(assert-equal "2.7 validate-affine-ast catches call/cc"
              '(error forbidden-syntax call/cc)
              r-callcc)

;;; -----------------------------------------------------------------------
;;; Group 3: Valid Linear Code Progression (Borrow & Linear Payload Move)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Valid Linear Code Progression ---\n")

(define valid-send-expr
  '(channel-send! tx payload))

(define env-tx-avail (lin-env-add-available '() 'tx))
(define r-valid-send (validate-affine-ast valid-send-expr env-tx-avail))

(assert-true "3.1 single channel-send! validates ok"
             (and (pair? r-valid-send) (eq? (car r-valid-send) 'ok)))

(define env-after-send (cadr r-valid-send))
(assert-equal "3.2 tx is borrowed ('available) after channel-send!"
              'available
              (lin-env-lookup env-after-send 'tx))

;; Multiple references to non-linear variable x
(define valid-multi-ref
  '(+ x (+ x x)))

(define r-multi (validate-affine-ast valid-multi-ref '()))
(assert-true "3.3 non-linear variable can be referenced multiple times"
             (and (pair? r-multi) (eq? (car r-multi) 'ok)))

;; Multi-recv on same rx endpoint
(define multi-recv-expr
  '(begin
     (channel-recv! rx)
     (channel-recv! rx)))
(define env-rx-avail (lin-env-add-available '() 'rx))
(define r-multi-recv (validate-affine-ast multi-recv-expr env-rx-avail))
(assert-true "3.4 multiple channel-recv! on same endpoint validates ok"
             (and (pair? r-multi-recv) (eq? (car r-multi-recv) 'ok)))

;; Multi-send on same tx endpoint
(define multi-send-expr
  '(begin
     (channel-send! tx 1)
     (channel-send! tx 2)))
(define r-multi-send (validate-affine-ast multi-send-expr env-tx-avail))
(assert-true "3.5 multiple channel-send! on same endpoint validates ok"
             (and (pair? r-multi-send) (eq? (car r-multi-send) 'ok)))

;;; -----------------------------------------------------------------------
;;; Group 4: Use-After-Move Detection (CWE-416)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Use-After-Move Detection ---\n")

;; Send a linear payload twice
(define double-send-payload-expr
  '(let ((data-channel (make-channel 1)))
     (channel-send! tx data-channel)
     (channel-send! tx data-channel)))

(define r-double-payload (validate-affine-ast double-send-payload-expr env-tx-avail))
(assert-equal "4.1 double send of same linear payload detected as use-after-move"
              '(error use-after-move data-channel)
              r-double-payload)

;; Passing channel to custom function (transferring ownership) then sending
(define pass-then-send
  '(begin
     (forward-packet tx)
     (channel-send! tx 42)))

(define r-pass-send (validate-affine-ast pass-then-send env-tx-avail))

(assert-equal "4.2 forward then send detected as use-after-move"
              '(error use-after-move tx)
              r-pass-send)

;; Using channel after channel-close!
(define close-then-send
  '(begin
     (channel-close! tx)
     (channel-send! tx 42)))

(define r-close-send (validate-affine-ast close-then-send env-tx-avail))
(assert-equal "4.3 use after channel-close! detected as use-after-move"
              '(error use-after-move tx)
              r-close-send)

;;; -----------------------------------------------------------------------
;;; Group 5: Conditional Branching Tracking
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Conditional Branching Tracking ---\n")

(define if-both-consume
  '(if is-ready?
       (channel-close! tx)
       (channel-close! tx)))

(define r-if-both (validate-affine-ast if-both-consume env-tx-avail))
(assert-true "5.1 consumption in both branches validates ok"
             (and (pair? r-if-both) (eq? (car r-if-both) 'ok)))

(define env-if-both (cadr r-if-both))
(assert-equal "5.2 variable consumed in both branches is marked moved"
              'moved
              (lin-env-lookup env-if-both 'tx))

;;; -----------------------------------------------------------------------
;;; Group 6: Automatic RAII Drop Injection
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Automatic RAII Drop Injection ---\n")

;; Unconsumed linear formal in kernel
(define kernel-with-unconsumed
  '(%asc-kernel (my-kernel rx n)
     (+ n 100)))

(define transformed-k1 (check-affine-kernel kernel-with-unconsumed))

(assert-true "6.1 kernel transformed produces %asc-kernel"
             (and (pair? transformed-k1) (eq? (car transformed-k1) '%asc-kernel)))

(define k1-body (caddr transformed-k1))
;; The body should wrap the original (+ n 100) with let __kernel_res and (%affine-drop! rx)
(assert-equal "6.2 body wrapped with let __kernel_res"
              'let
              (car k1-body))

(define let-body (caddr k1-body))
(assert-equal "6.3 let body has (%affine-drop! rx)"
              '(%affine-drop! rx)
              (cadr let-body))

;; Kernel where linear variable is consumed: no RAII drop should be injected
(define kernel-consumed
  '(%asc-kernel (my-kernel tx n)
     (channel-close! tx)))

(define transformed-k2 (check-affine-kernel kernel-consumed))
(define k2-body (caddr transformed-k2))

;; k2-body should be direct (channel-close! tx) or (begin (channel-close! tx)), NOT wrapped with %affine-drop!
(assert-true "6.4 consumed linear argument does not get extra %affine-drop!"
             (or (equal? k2-body '(channel-close! tx))
                 (equal? k2-body '(begin (channel-close! tx)))))

;; Kernel where channel is borrowed (sent/received): tx is still available at exit so RAII drop IS injected to close it
(define kernel-borrowed
  '(%asc-kernel (my-kernel tx n)
     (channel-send! tx n)))

(define transformed-k3 (check-affine-kernel kernel-borrowed))
(define k3-body (caddr transformed-k3))
(assert-true "6.5 borrowed channel at kernel exit gets RAII drop"
             (and (pair? k3-body)
                  (eq? (car k3-body) 'let)
                  (let ((inner (caddr k3-body)))
                    (and (pair? inner)
                         (eq? (car inner) 'begin)
                         (member '(%affine-drop! tx) (cdr inner))
                         #t))))

;;; -----------------------------------------------------------------------
;;; Group 7: Pass Manager Injection & Pipeline Integration
;;; -----------------------------------------------------------------------
(display "\n--- Group 7: Pass Manager Injection & Pipeline Integration ---\n")

(init-default-pass-registry!)
(inject-synapse-split-planes-pass!)
(inject-synapse-check-affine-pass!)

(define pipeline-both (build-pipeline 0 '()))
(define ids-both (map pass-id pipeline-both))

(assert-true "7.1 pass-synapse-split-planes in pipeline"
             (memq 'pass-synapse-split-planes ids-both))

(assert-true "7.2 pass-synapse-check-affine in pipeline"
             (memq 'pass-synapse-check-affine ids-both))

(define (pass-after? p1 p2 p-list)
  (let loop ((ps p-list))
    (cond
      ((null? ps) #f)
      ((null? (cdr ps)) #f)
      ((and (eq? (car ps) p1) (eq? (cadr ps) p2)) #t)
      (else (loop (cdr ps))))))

(assert-true "7.3 check-affine pass directly follows split-planes pass"
             (pass-after? 'pass-synapse-split-planes 'pass-synapse-check-affine ids-both))

(assert-true "7.4 injected pipeline satisfies DAG prerequisites"
             (validate-pipeline-prerequisites pipeline-both))

;; Full check-affine-pass execution on forms list
(define sample-forms
  (list
    '(define (caller) 42)
    kernel-with-unconsumed))

(define pass-result (check-affine-pass sample-forms))
(assert-equal "7.5 check-affine-pass preserves non-kernel forms"
              '(define (caller) 42)
              (car pass-result))

(assert-true "7.6 check-affine-pass transforms kernel form"
             (and (pair? (cadr pass-result)) (eq? (car (cadr pass-result)) '%asc-kernel)))

;; Clean removal
(remove-synapse-check-affine-pass!)
(remove-synapse-split-planes-pass!)
(define pipeline-clean (build-pipeline 0 '()))
(assert-false "7.7 check-affine pass cleanly removed"
              (memq 'pass-synapse-check-affine (map pass-id pipeline-clean)))

(display "\n=======================================================\n")
(display " Test Suite Completed: ")
(display (car *pass-count*))
(display " / ")
(display (car *test-count*))
(display " assertions passed.\n")
(display "=======================================================\n\n")
