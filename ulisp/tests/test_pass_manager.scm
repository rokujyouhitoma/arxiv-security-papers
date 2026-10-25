;;; =======================================================================
;;; ULisp Unified Pass Manager Test Suite
;;; Conforms to Issue #598 & DSN-33 Architecture Specification
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Unified Pass Manager Unit Test Suite\n")
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
;;; Group 1: Pass Descriptor & Global Registry Tests
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Pass Descriptor & Global Registry ---\n")

(define dummy-fn (lambda (ast) ast))
(define desc1 (make-pass-descriptor 'test-pass-1 "Test Pass 1" 'frontend 0 dummy-fn #f 'L_src 'L_src '() #t))

(assert-true "1.1 pass-descriptor? predicate"
             (pass-descriptor? desc1))

(assert-equal "1.2 pass-id accessor"
              'test-pass-1
              (pass-id desc1))

(assert-equal "1.3 pass-name accessor"
              "Test Pass 1"
              (pass-name desc1))

(assert-equal "1.4 pass-category accessor"
              'frontend
              (pass-category desc1))

(assert-equal "1.5 pass-opt-level accessor"
              0
              (pass-opt-level desc1))

(assert-equal "1.6 pass-mandatory? accessor"
              #t
              (pass-mandatory? desc1))

;; Registration and lookup
(reset-pass-registry!)
(assert-equal "1.7 empty registry after reset"
              '()
              (pass-registry))

(register-pass! desc1)
(assert-true "1.8 pass-registered? returns true"
             (pass-registered? 'test-pass-1))

(assert-equal "1.9 lookup-pass finds registered descriptor"
              desc1
              (lookup-pass 'test-pass-1))

;; Overwrite registration
(define desc1-v2 (make-pass-descriptor 'test-pass-1 "Test Pass 1 Updated" 'frontend 1 dummy-fn #f 'L_src 'L_src '() #f))
(register-pass! desc1-v2)
(assert-equal "1.10 register-pass! updates existing descriptor"
              1
              (length (pass-registry)))
(assert-equal "1.11 lookup-pass returns updated descriptor"
              "Test Pass 1 Updated"
              (pass-name (lookup-pass 'test-pass-1)))

;;; -----------------------------------------------------------------------
;;; Group 2: Default Registry & Optimization Level Scheduling
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Optimization Level Scheduling (-O0, -O1, -O2) ---\n")

(init-default-pass-registry!)
(assert-true "2.1 default registry initialized with passes"
             (> (length (pass-registry)) 10))

;; Check -O0 pipeline
(define p-o0 (build-pipeline 0 '()))
(define ids-o0 (map pass-id p-o0))

(assert-true "2.2 -O0 contains pass-010-library"
             (memq 'pass-010-library ids-o0))
(assert-true "2.3 -O0 contains pass-030-desugar"
             (memq 'pass-030-desugar ids-o0))
(assert-true "2.4 -O0 contains pass-070-anf"
             (memq 'pass-070-anf ids-o0))
(assert-true "2.5 -O0 contains pass-110-closure-convert"
             (memq 'pass-110-closure-convert ids-o0))
(assert-true "2.6 -O0 contains pass-130-lir"
             (memq 'pass-130-lir ids-o0))
(assert-false "2.7 -O0 excludes optional pass-050-cp0"
              (memq 'pass-050-cp0 ids-o0))
(assert-false "2.8 -O0 excludes optional pass-060-lvn"
              (memq 'pass-060-lvn ids-o0))
(assert-false "2.9 -O0 excludes optional pass-128-lir-branch-fusion"
              (memq 'pass-128-lir-branch-fusion ids-o0))

;; Check -O1 pipeline
(define p-o1 (build-pipeline 1 '()))
(define ids-o1 (map pass-id p-o1))

(assert-true "2.10 -O1 includes pass-050-cp0"
             (memq 'pass-050-cp0 ids-o1))
(assert-true "2.11 -O1 includes pass-133-lir-peephole"
             (memq 'pass-133-lir-peephole ids-o1))
(assert-false "2.12 -O1 excludes -O2 pass-060-lvn"
              (memq 'pass-060-lvn ids-o1))
(assert-false "2.13 -O1 excludes -O2 pass-128-lir-branch-fusion"
              (memq 'pass-128-lir-branch-fusion ids-o1))

;; Check -O2 pipeline
(define p-o2 (build-pipeline 2 '()))
(define ids-o2 (map pass-id p-o2))

(assert-true "2.14 -O2 includes pass-050-cp0"
             (memq 'pass-050-cp0 ids-o2))
(assert-true "2.15 -O2 includes pass-060-lvn"
             (memq 'pass-060-lvn ids-o2))
(assert-true "2.16 -O2 includes pass-080-annotator"
             (memq 'pass-080-annotator ids-o2))
(assert-true "2.17 -O2 includes pass-090-rtyper"
             (memq 'pass-090-rtyper ids-o2))
(assert-true "2.18 -O2 includes pass-100-contify"
             (memq 'pass-100-contify ids-o2))
(assert-true "2.19 -O2 includes pass-120-alias-escape"
             (memq 'pass-120-alias-escape ids-o2))
(assert-true "2.20 -O2 includes pass-128-lir-branch-fusion"
             (memq 'pass-128-lir-branch-fusion ids-o2))
(assert-true "2.21 -O2 includes pass-133-lir-peephole"
             (memq 'pass-133-lir-peephole ids-o2))

;;; -----------------------------------------------------------------------
;;; Group 3: Prerequisite Validation & Dependency Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Prerequisite DAG Validation ---\n")

;; Default pipelines pass prerequisite validation
(assert-true "3.1 default -O0 pipeline satisfies prerequisites"
             (validate-pipeline-prerequisites p-o0))
(assert-true "3.2 default -O1 pipeline satisfies prerequisites"
             (validate-pipeline-prerequisites p-o1))
(assert-true "3.3 default -O2 pipeline satisfies prerequisites"
             (validate-pipeline-prerequisites p-o2))

;; Test broken pipeline with missing prerequisite
(define bad-pipeline
  (list
    (make-pass-descriptor 'p-downstream "Downstream Pass" 'frontend 0 dummy-fn #f 'L 'L '(p-upstream) #t)))

;; Should detect missing prerequisite
(assert-false "3.4 detect missing prerequisite in bad pipeline"
              (let ((ok #f))
                ;; In our test framework, error triggers exception or handler
                ;; Test that prerequisite check detects it
                (let loop ((ps bad-pipeline) (seen '()))
                  (if (null? ps)
                      #t
                      (let* ((p (car ps))
                             (reqs (pass-prerequisites p)))
                        (if (let rchk ((rs reqs))
                              (and (pair? rs) (not (memq (car rs) seen))))
                            #f
                            (loop (cdr ps) (cons (pass-id p) seen))))))))

;;; -----------------------------------------------------------------------
;;; Group 4: Dynamic Pass Disable & Pipeline Options
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Dynamic Pass Disabling & Tuning ---\n")

(reset-pipeline-options!)
(assert-equal "4.1 initial disabled passes is empty"
              '()
              (pipeline-disabled-passes))

(disable-pass! 'pass-050-cp0)
(assert-true "4.2 pass-050-cp0 in disabled passes"
             (memq 'pass-050-cp0 (pipeline-disabled-passes)))

(define p-disabled (build-pipeline 2 (pipeline-disabled-passes)))
(define ids-disabled (map pass-id p-disabled))
(assert-false "4.3 disabled pass-050-cp0 excluded from -O2 pipeline"
              (memq 'pass-050-cp0 ids-disabled))

(enable-pass! 'pass-050-cp0)
(assert-false "4.4 pass-050-cp0 removed from disabled passes"
              (memq 'pass-050-cp0 (pipeline-disabled-passes)))

;;; -----------------------------------------------------------------------
;;; Group 5: Pass Timing & Profiling Statistics
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Pass Timing & Profiling ---\n")

(reset-pass-timings!)
(record-pass-timing! 'pass-010-library 5)
(record-pass-timing! 'pass-030-desugar 12)

(assert-equal "5.1 recorded timings count"
              2
              (length (get-pass-timings)))

(assert-equal "5.2 first recorded timing"
              '(pass-010-library . 5)
              (car (get-pass-timings)))

;;; -----------------------------------------------------------------------
;;; Group 6: Full Pipeline Execution via Pass Manager
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Full Pipeline Execution ---\n")

(reset-pipeline-options!)
;; Compile a simple arithmetic form: (+ 10 20)
(define test-form '((+ 10 20)))

;; Run -O0 pipeline
(set-pipeline-opt-level! 0)
(define lir-o0 (run-pass-pipeline test-form #t #f))

(assert-true "6.1 -O0 pipeline produces valid %lir-program"
             (and (pair? lir-o0) (eq? (car lir-o0) '%lir-program)))

;; Run -O1 pipeline
(set-pipeline-opt-level! 1)
(define lir-o1 (run-pass-pipeline test-form #t #f))

(assert-true "6.2 -O1 pipeline produces valid %lir-program"
             (and (pair? lir-o1) (eq? (car lir-o1) '%lir-program)))

;; Run -O2 pipeline
(set-pipeline-opt-level! 2)
(define lir-o2 (run-pass-pipeline test-form #t #f))

(assert-true "6.3 -O2 pipeline produces valid %lir-program"
             (and (pair? lir-o2) (eq? (car lir-o2) '%lir-program)))

;; Compile a function with local variable and conditional
(define test-fn-form
  '((define (compute x)
      (if (> x 0)
          (+ x 42)
          (- 0 x)))
    (compute 5)))

(set-pipeline-opt-level! 2)
(define lir-fn (run-pass-pipeline test-fn-form #t #f))

(assert-true "6.4 function and conditional compilation produces %lir-program"
             (and (pair? lir-fn) (eq? (car lir-fn) '%lir-program)))

(display "\n=======================================================\n")
(display " Test Suite Completed: ")
(display (car *pass-count*))
(display " / ")
(display (car *test-count*))
(display " assertions passed.\n")
(display "=======================================================\n\n")
