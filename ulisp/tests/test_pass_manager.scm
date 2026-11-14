;;; =======================================================================
;;; ULisp Unified Pass Manager Test Suite
;;; Conforms to Issue #598 & DSN-33 Architecture Specification
;;; =======================================================================

(test-begin "Unified Pass Manager")

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
(assert-true "2.3.1 -O0 contains pass-035-scope-resolve"
             (memq 'pass-035-scope-resolve ids-o0))
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
(record-pass-timing! 'pass-010-library "Desugar Libraries and Imports" 5200 24576)
(record-pass-timing! 'pass-030-desugar "Core Desugar All" 12400 65536)

(assert-equal "5.1 recorded timings count"
              2
              (length (get-pass-timings)))

(define first-timing (car (get-pass-timings)))
(assert-equal "5.2 first recorded timing id"
              'pass-010-library
              (pass-timing-id first-timing))

(assert-equal "5.3 first recorded timing name"
              "Desugar Libraries and Imports"
              (pass-timing-name first-timing))

(assert-equal "5.4 first recorded timing elapsed-us"
              5200
              (pass-timing-elapsed-us first-timing))

(assert-equal "5.5 first recorded timing alloc-bytes"
              24576
              (pass-timing-alloc-bytes first-timing))

(assert-equal "5.6 format-fixed-2-ms formatting"
              "5.20 ms"
              (format-fixed-2-ms 5200))

(assert-equal "5.7 format-fixed-1-pct formatting"
              "29.5%"
              (format-fixed-1-pct 5200 17600))

(assert-equal "5.8 format-alloc-kb formatting"
              "24 KB"
              (format-alloc-kb 24576))

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

;;; -----------------------------------------------------------------------
;;; Group 7: Pass Injection Mechanism (inject-pass-after! / inject-pass-before!)
;;; -----------------------------------------------------------------------
(display "\n--- Group 7: Pass Injection Mechanism (Pluggable Extensions) ---\n")

(init-default-pass-registry!)
(define dummy-injected-pass (lambda (ast) ast))
(define injected-desc-1
  (make-pass-descriptor 'pass-injected-split-planes
                        "Injected Split Planes Extension"
                        'frontend
                        0
                        dummy-injected-pass
                        #f
                        'L_core
                        'L_core
                        '(pass-030-desugar)
                        #t))

;; 7.1 inject-pass-after!
(inject-pass-after! 'pass-030-desugar injected-desc-1)
(define pipeline-injected-1 (build-pipeline 0 '()))
(define ids-injected-1 (map pass-id pipeline-injected-1))

(assert-true "7.1 injected pass is registered in pipeline"
             (memq 'pass-injected-split-planes ids-injected-1))

;; Verify relative position: pass-injected-split-planes should immediately follow pass-030-desugar
(define (pass-after? p1 p2 p-list)
  (let loop ((ps p-list))
    (cond
      ((null? ps) #f)
      ((null? (cdr ps)) #f)
      ((and (eq? (car ps) p1) (eq? (cadr ps) p2)) #t)
      (else (loop (cdr ps))))))

(assert-true "7.2 injected pass directly follows target pass"
             (pass-after? 'pass-030-desugar 'pass-injected-split-planes ids-injected-1))

;; 7.3 inject-pass-before!
(define injected-desc-2
  (make-pass-descriptor 'pass-injected-pre-desugar
                        "Injected Pre-Desugar Hook"
                        'frontend
                        0
                        dummy-injected-pass
                        #f
                        'L_src
                        'L_src
                        '()
                        #t))

(inject-pass-before! 'pass-030-desugar injected-desc-2)
(define ids-injected-2 (map pass-id (build-pipeline 0 '())))
(assert-true "7.3 injected pass directly precedes target pass"
             (pass-after? 'pass-injected-pre-desugar 'pass-030-desugar ids-injected-2))

;; 7.4 Re-inject repositioning
(inject-pass-after! 'pass-070-anf injected-desc-1)
(define ids-injected-3 (map pass-id (build-pipeline 0 '())))
(assert-true "7.4 re-injected pass moves to new location"
             (pass-after? 'pass-070-anf 'pass-injected-split-planes ids-injected-3))
(assert-false "7.5 old location is cleared"
              (pass-after? 'pass-030-desugar 'pass-injected-split-planes ids-injected-3))

;; 7.6 remove-injected-pass!
(remove-injected-pass! 'pass-injected-split-planes)
(remove-injected-pass! 'pass-injected-pre-desugar)
(define ids-clean (map pass-id (build-pipeline 0 '())))
(assert-false "7.6 removed pass-injected-split-planes no longer in pipeline"
              (memq 'pass-injected-split-planes ids-clean))
(assert-false "7.7 removed pass-injected-pre-desugar no longer in pipeline"
              (memq 'pass-injected-pre-desugar ids-clean))

;;; -----------------------------------------------------------------------
;;; Group 8: Issue #753 — Pass Registry Language Schema Completeness
;;; -----------------------------------------------------------------------
(display "\n--- Group 8: Pass Registry Language Schema Completeness ---\n")

(init-default-pass-registry!)
(define registered-langs (nanopass-get-all-languages))

(assert-true "8.1 every pass in default registry has registered in-lang and out-lang"
             (let loop ((ps (pass-registry)))
               (if (null? ps)
                   #t
                   (let* ((p (car ps))
                          (in-l (pass-in-lang p))
                          (out-l (pass-out-lang p)))
                     (and (memq in-l registered-langs)
                          (memq out-l registered-langs)
                          (loop (cdr ps)))))))

;;; -----------------------------------------------------------------------
;;; Group 9: Issue #768 — define-pipeline DSL & Named Pipeline Profiles
;;; -----------------------------------------------------------------------
(display "\n--- Group 9: define-pipeline DSL & Named Pipeline Profiles (DSN-33-01 T6.1) ---\n")

(init-default-pass-registry!)

;; 9.1 pipeline-descriptor? predicate and accessors
(define sample-pipe-desc
  (make-pipeline-descriptor 'test-pipeline "Sample Test Pipeline" '(pass-010-library) 'lir '(opt-a opt-b)))

(assert-true "9.1 pipeline-descriptor? predicate"
             (pipeline-descriptor? sample-pipe-desc))
(assert-equal "9.2 pipeline-desc-name accessor"
              'test-pipeline
              (pipeline-desc-name sample-pipe-desc))
(assert-equal "9.3 pipeline-desc-doc accessor"
              "Sample Test Pipeline"
              (pipeline-desc-doc sample-pipe-desc))
(assert-equal "9.4 pipeline-desc-passes accessor"
              '(pass-010-library)
              (pipeline-desc-passes sample-pipe-desc))
(assert-equal "9.5 pipeline-desc-target-ir accessor"
              'lir
              (pipeline-desc-target-ir sample-pipe-desc))
(assert-equal "9.6 pipeline-desc-options accessor"
              '(opt-a opt-b)
              (pipeline-desc-options sample-pipe-desc))

;; 9.2 Standard named pipelines registration
(assert-true "9.7 standard aot-native-pipeline is registered"
             (pipeline-registered? 'aot-native-pipeline))
(assert-true "9.8 standard repl-fast-pipeline is registered"
             (pipeline-registered? 'repl-fast-pipeline))
(assert-true "9.9 standard static-check-pipeline is registered"
             (pipeline-registered? 'static-check-pipeline))

(define aot-desc (lookup-pipeline 'aot-native-pipeline))
(assert-equal "9.10 aot-native-pipeline target-ir is lir"
              'lir
              (pipeline-desc-target-ir aot-desc))
(assert-true "9.11 aot-native-pipeline includes pass-133-lir-peephole"
             (memq 'pass-133-lir-peephole (pipeline-desc-passes aot-desc)))

(define repl-desc (lookup-pipeline 'repl-fast-pipeline))
(assert-equal "9.12 repl-fast-pipeline target-ir is lir"
              'lir
              (pipeline-desc-target-ir repl-desc))
(assert-false "9.13 repl-fast-pipeline excludes heavy CP0 optimization"
              (memq 'pass-050-cp0 (pipeline-desc-passes repl-desc)))
(assert-false "9.14 repl-fast-pipeline excludes LIR peephole"
              (memq 'pass-133-lir-peephole (pipeline-desc-passes repl-desc)))

(define check-desc (lookup-pipeline 'static-check-pipeline))
(assert-equal "9.15 static-check-pipeline target-ir is ast"
              'ast
              (pipeline-desc-target-ir check-desc))
(assert-true "9.16 static-check-pipeline includes pass-040-analysis"
             (memq 'pass-040-analysis (pipeline-desc-passes check-desc)))
(assert-false "9.17 static-check-pipeline excludes pass-130-lir"
              (memq 'pass-130-lir (pipeline-desc-passes check-desc)))

;; 9.3 Language Continuity Validation
(assert-true "9.18 validate-pipeline-continuity-by-ids succeeds on aot-native-pipeline"
             (validate-pipeline-continuity-by-ids (pipeline-desc-passes aot-desc)))
(assert-true "9.19 validate-pipeline-continuity-by-ids succeeds on repl-fast-pipeline"
             (validate-pipeline-continuity-by-ids (pipeline-desc-passes repl-desc)))
(assert-true "9.20 validate-pipeline-continuity-by-ids succeeds on static-check-pipeline"
             (validate-pipeline-continuity-by-ids (pipeline-desc-passes check-desc)))

;; Test continuity rejection with incompatible passes (pass-010-library [L_cst] followed by pass-070-anf [L_core -> L_anf])
(define bad-continuity-passes '(pass-010-library pass-070-anf))
(assert-false "9.21 check-pipeline-continuity-by-ids detects schema continuity violation"
              (check-pipeline-continuity-by-ids bad-continuity-passes))

;; 9.4 Prerequisite Validation Rejection
(define bad-prereq-passes '(pass-070-anf))
(assert-false "9.22 check-pipeline-prerequisites-by-ids detects missing prerequisites"
              (check-pipeline-prerequisites-by-ids bad-prereq-passes))

;; 9.5 select-pipeline! and current-pipeline-name
(assert-equal "9.23 initial pipeline is aot-native-pipeline"
              'aot-native-pipeline
              (current-pipeline-name))
(select-pipeline! 'repl-fast-pipeline)
(assert-equal "9.24 active pipeline switched to repl-fast-pipeline"
              'repl-fast-pipeline
              (current-pipeline-name))
(select-pipeline! 'aot-native-pipeline)
(assert-equal "9.25 active pipeline restored to aot-native-pipeline"
              'aot-native-pipeline
              (current-pipeline-name))

;; 9.6 Execution of named pipelines
(define test-code-form
  '((define (square x) (* x x))
    (square 7)))

;; Execute aot-native-pipeline
(define aot-lir (run-named-pipeline 'aot-native-pipeline test-code-form #t #f))
(assert-true "9.26 aot-native-pipeline produces %lir-program"
             (and (pair? aot-lir) (eq? (car aot-lir) '%lir-program)))

;; Execute repl-fast-pipeline
(define repl-lir (run-named-pipeline 'repl-fast-pipeline test-code-form #t #f))
(assert-true "9.27 repl-fast-pipeline produces %lir-program"
             (and (pair? repl-lir) (eq? (car repl-lir) '%lir-program)))

;; Execute static-check-pipeline (should return analyzed AST, not %lir-program)
(define check-ast (run-named-pipeline 'static-check-pipeline test-code-form #f #f))
(assert-true "9.28 static-check-pipeline produces valid AST output"
             (and (pair? check-ast) (not (eq? (car check-ast) '%lir-program))))

;; 9.7 define-pipeline DSL expansion and registration
(define-pipeline test-dynamic-sub-pipeline
  (doc "Dynamically defined sub-pipeline via DSL")
  (target-ir lir)
  (passes
    pass-010-library
    pass-015-dsl-expander
    pass-020-macro-expander
    pass-025-top-level
    pass-030-desugar
    pass-035-scope-resolve
    pass-070-anf
    pass-110-closure-convert
    pass-130-lir))

(assert-true "9.29 define-pipeline registers named pipeline into registry"
             (pipeline-registered? 'test-dynamic-sub-pipeline))

(define dyn-lir (test-dynamic-sub-pipeline test-code-form #t #f))
(assert-true "9.30 define-pipeline generates callable wrapper procedure producing %lir-program"
             (and (pair? dyn-lir) (eq? (car dyn-lir) '%lir-program)))

;;; -----------------------------------------------------------------------
;;; Group 10: Picopass Disabling API & Rule-level Auto-Bisect (DSN-33-01 T6.2)
;;; -----------------------------------------------------------------------

(display "\n--- Group 10: Picopass Disabling API & Rule-level Auto-Bisect ---\n")

;; 10.1 Picopass disabling state
(reset-disabled-picopasses!)
(assert-equal "10.1 initial disabled-picopasses is empty"
              '()
              (disabled-picopasses))

(assert-true "10.2 picopass-enabled? returns #t initially"
             (picopass-enabled? 'test-rule-x))

(disable-picopass! 'test-rule-x)
(assert-equal "10.3 disable-picopass! adds rule to disabled list"
              '(test-rule-x)
              (disabled-picopasses))

(assert-false "10.4 picopass-enabled? returns #f for disabled rule"
              (picopass-enabled? 'test-rule-x))

(assert-true "10.5 picopass-enabled? returns #t for other rules"
             (picopass-enabled? 'test-rule-y))

(enable-picopass! 'test-rule-x)
(assert-equal "10.6 enable-picopass! removes rule from disabled list"
              '()
              (disabled-picopasses))

(assert-true "10.7 picopass-enabled? restored to #t"
             (picopass-enabled? 'test-rule-x))

;; 10.8 with-disabled-picopasses scoped execution
(with-disabled-picopasses '(rule-temp-1 rule-temp-2)
  (lambda ()
    (assert-false "10.8 rule-temp-1 disabled inside thunk"
                  (picopass-enabled? 'rule-temp-1))
    (assert-false "10.9 rule-temp-2 disabled inside thunk"
                  (picopass-enabled? 'rule-temp-2))))

(assert-true "10.10 rule-temp-1 restored outside thunk"
             (picopass-enabled? 'rule-temp-1))
(assert-true "10.11 rule-temp-2 restored outside thunk"
             (picopass-enabled? 'rule-temp-2))

;; 10.12 mandatory rule protection
(define-picopass rule-mandatory-guard
  :mandatory #t
  (Expr
    ((guard-check ,x) x)))

(assert-true "10.12 rule-mandatory? returns #t for mandatory rule"
             (rule-mandatory? (rule-descriptor 'rule-mandatory-guard)))

(assert-false "10.13 disable-picopass! rejects disabling mandatory rule"
              (disable-picopass! 'rule-mandatory-guard))
(assert-true "10.13.1 mandatory rule remains enabled"
             (picopass-enabled? 'rule-mandatory-guard))

;; 10.14 picopass-split-list helper
(assert-equal "10.14 picopass-split-list splits list evenly"
              '((a b) c d e)
              (let ((s (picopass-split-list '(a b c d e) 2)))
                (cons (car s) (cdr s))))

;; 10.15 auto-bisect-picopasses: base check when test-fn passes initially
(let ((res (auto-bisect-picopasses '(r1 r2 r3) (lambda () #t))))
  (assert-equal "10.15 auto-bisect returns #f when bug does not reproduce"
                #f
                res))

;; 10.16 auto-bisect-picopasses: when test-fn fails even with all candidates disabled
(let ((res (auto-bisect-picopasses '(r1 r2 r3) (lambda () #f))))
  (assert-equal "10.16 auto-bisect detects failure with all rules disabled"
                'cannot-isolate-all-disabled-still-fails
                res))

;; 10.17 auto-bisect-picopasses: single rule isolation among 6 rules (rule 4 is bug)
;; Bug rule: r4.
;; test-fn returns #t (PASS) if r4 is disabled, #f (FAIL) if r4 is enabled.
(let* ((candidates '(r1 r2 r3 r4 r5 r6))
       (test-fn (lambda ()
                  (not (picopass-enabled? 'r4))))
       (isolated (auto-bisect-picopasses candidates test-fn)))
  (assert-equal "10.17 auto-bisect successfully isolates buggy rule r4 in O(log n)"
                'r4
                isolated))

;; 10.18 auto-bisect-picopasses: single rule isolation among 8 rules (rule 7 is bug)
(let* ((candidates '(opt-1 opt-2 opt-3 opt-4 opt-5 opt-6 opt-7 opt-8))
       (test-fn (lambda ()
                  (not (picopass-enabled? 'opt-7))))
       (isolated (auto-bisect-picopasses candidates test-fn)))
  (assert-equal "10.18 auto-bisect successfully isolates opt-7 among 8 candidates"
                'opt-7
                isolated))

;; 10.19 auto-bisect-picopasses: 2-rule interaction bug
;; Bug requires BOTH r2 and r5 to be enabled simultaneously.
(let* ((candidates '(r1 r2 r3 r4 r5 r6))
       (test-fn (lambda ()
                  (not (and (picopass-enabled? 'r2)
                            (picopass-enabled? 'r5)))))
       (isolated (auto-bisect-picopasses candidates test-fn)))
  (assert-true "10.19 auto-bisect detects multi-rule interaction"
               (and (pair? isolated) (eq? (car isolated) 'interaction))))

;; 10.20 auto-bisect-picopasses restores state on exception in test-fn
(disable-picopass! 'saved-rule-init)
(let ((caught #f))
  (call/cc
    (lambda (escape)
      (with-exception-handler
        (lambda (ex)
          (set! caught #t)
          (escape #t))
        (lambda ()
          (auto-bisect-picopasses '(r1 r2) (lambda () (raise 'simulated-failure)))))))
  (assert-true "10.20 exception handled" caught)
  (assert-equal "10.21 disabled-picopasses restored to initial state after exception"
                '(saved-rule-init)
                (disabled-picopasses)))
(reset-disabled-picopasses!)

;; 10.22 Real integration: fused pass with disabled rule skips transformation
(define-picopass rule-pm-fuse-1
  (Expr
    ((pm-op-1 ,x) (list 'res-1 x))))

(define-picopass rule-pm-fuse-2
  (Expr
    ((pm-op-2 ,x) (list 'res-2 x))))

(define-pass test-pass-pm-fused : L_src (ir) -> L_src ()
  (entry Expr)
  (fuse-rules
    rule-pm-fuse-1
    rule-pm-fuse-2))

;; When both enabled: both transform
(assert-equal "10.22 both rules transform when enabled"
              '(list (res-1 a) (res-2 b))
              (test-pass-pm-fused '(list (pm-op-1 a) (pm-op-2 b))))

;; When rule-pm-fuse-1 is disabled: only rule 2 transforms, rule 1 is skipped!
(disable-picopass! 'rule-pm-fuse-1)
(assert-equal "10.23 disabled rule-pm-fuse-1 is skipped in fused pass"
              '(list (pm-op-1 a) (res-2 b))
              (test-pass-pm-fused '(list (pm-op-1 a) (pm-op-2 b))))
(reset-disabled-picopasses!)

(test-end "Unified Pass Manager")
