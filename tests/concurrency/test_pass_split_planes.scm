;;; =======================================================================
;;; Synapse Dual-Plane Boundary Splitting Test Suite
;;; Path: tests/concurrency/test_pass_split_planes.scm
;;; Conforms to DSN-37 Section 1.2, 8.1, 12.1 & Phase 3 Task 3.1 (Issue #637)
;;; =======================================================================

(test-begin "Synapse Dual-Plane Boundary Splitting")

;;; -----------------------------------------------------------------------
;;; Group 1: Free Variable Capture Analysis
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Free Variable Capture Analysis ---\n")

;; 1.1 Literal constants: no free variables
(assert-equal "1.1 numbers have no free variables"
              '()
              (extract-free-variables 42 '()))

(assert-equal "1.2 quoted forms have no free variables"
              '()
              (extract-free-variables '(quote (a b c)) '()))

;; 1.3 Unbound symbol is free
(assert-equal "1.3 single unbound symbol is free"
              '(x)
              (extract-free-variables 'x '()))

;; 1.4 Bound symbol is not free
(assert-equal "1.4 bound symbol is not free"
              '()
              (extract-free-variables 'x '(x y z)))

;; 1.5 Lambda abstraction binding
(assert-equal "1.5 lambda binds formal parameter"
              '()
              (extract-free-variables '(lambda (x) (+ x 1)) '(+)))

(assert-equal "1.6 lambda captures outer free variable"
              '(y)
              (extract-free-variables '(lambda (x) (+ x y)) '(+)))

;; 1.7 Let bindings
(assert-equal "1.7 let binds local variable"
              '()
              (extract-free-variables '(let ((x 10)) (+ x 1)) '(+)))

(assert-equal "1.8 let captures outer variable in body"
              '(y)
              (extract-free-variables '(let ((x 10)) (+ x y)) '(+)))

(assert-equal "1.9 let captures variable in binding expression"
              '(z)
              (extract-free-variables '(let ((x z)) (+ x 1)) '(+)))

;;; -----------------------------------------------------------------------
;;; Group 2: Capture Mode Classification (DSN-37 Section 8.1 & Issue #797)
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Capture Mode Classification (Type-Driven / No Name Heuristics) ---\n")

(define sample-type-env
  '((count . integer)
    (idx . fixnum)
    (n . integer)
    (is-ready? . boolean)
    (c . channel)
    (my-pipe . spsc-channel)
    (chan-val . integer)
    (chan-flag . boolean)
    (payload-buffer . vector)
    (shared-vec . vector)))

;; Immediate types via type environment (Issue #797)
(assert-equal "2.1 count (integer) is classified as immediate"
              'immediate
              (classify-capture-mode 'count sample-type-env))

(assert-equal "2.2 idx (fixnum) is classified as immediate"
              'immediate
              (classify-capture-mode 'idx sample-type-env))

(assert-equal "2.3 n (integer) is classified as immediate"
              'immediate
              (classify-capture-mode 'n sample-type-env))

(assert-equal "2.4 is-ready? (boolean) is classified as immediate"
              'immediate
              (classify-capture-mode 'is-ready? sample-type-env))

;; Variable with 'chan' prefix but integer type is NOT linear (CWE-843 Type Confusion Prevention)
(assert-equal "2.5 chan-val (integer) is classified as immediate, NOT linear"
              'immediate
              (classify-capture-mode 'chan-val sample-type-env))

(assert-equal "2.6 chan-flag (boolean) is classified as immediate, NOT linear"
              'immediate
              (classify-capture-mode 'chan-flag sample-type-env))

;; Linear Move via Type Environment: arbitrary names (Issue #797)
(assert-equal "2.7 arbitrary name 'c' (channel) is classified as linear-move"
              'linear-move
              (classify-capture-mode 'c sample-type-env))

(assert-equal "2.8 arbitrary name 'my-pipe' (spsc-channel) is classified as linear-move"
              'linear-move
              (classify-capture-mode 'my-pipe sample-type-env))

;; Direct inline type annotation (: var type)
(assert-equal "2.9 inline (: pipe channel) is classified as linear-move"
              'linear-move
              (classify-capture-mode '(: pipe channel)))

(assert-equal "2.10 inline (: max-size integer) is classified as immediate"
              'immediate
              (classify-capture-mode '(: max-size integer)))

;; Deep Copy (Shared-Nothing CWE-362/662 safe default for untyped or composite)
(assert-equal "2.11 payload-buffer (vector) is classified as deep-copy"
              'deep-copy
              (classify-capture-mode 'payload-buffer sample-type-env))

(assert-equal "2.12 untyped variable defaults to deep-copy (safe default)"
              'deep-copy
              (classify-capture-mode 'untyped-var '()))

;; Static Boundary Warning for Untyped Variable Crossing (Issue #811)
(reset-untyped-boundary-warnings!)
(assert-equal "2.13 untyped variable emits warning and defaults to deep-copy"
              'deep-copy
              (classify-capture-mode 'raw-buf '() 'spawn-task))

(assert-equal "2.14 warning list records raw-buf for spawn-task boundary"
              '((raw-buf . spawn-task))
              (untyped-boundary-warnings))

(reset-untyped-boundary-warnings!)
(assert-equal "2.15 inline (: my-buf deep-copy) suppresses warning"
              'deep-copy
              (classify-capture-mode '(: my-buf deep-copy)))
(assert-equal "2.16 warning list remains empty on explicit deep-copy annotation"
              '()
              (untyped-boundary-warnings))

(assert-equal "2.17 inline (: my-buf any) suppresses warning"
              'deep-copy
              (classify-capture-mode '(: my-buf any)))
(assert-equal "2.18 warning list remains empty on explicit any annotation"
              '()
              (untyped-boundary-warnings))

(let ((env-with-explicit-deep-copy '((explicit-buf . deep-copy))))
  (assert-equal "2.19 type-env explicit deep-copy suppresses warning"
                'deep-copy
                (classify-capture-mode 'explicit-buf env-with-explicit-deep-copy))
  (assert-equal "2.20 warning list remains empty on type-env explicit deep-copy"
                '()
                (untyped-boundary-warnings)))

;; Zero false positives for typed variables
(reset-untyped-boundary-warnings!)
(classify-capture-mode 'c sample-type-env 'with-channel)
(classify-capture-mode 'count sample-type-env 'spawn-task)
(assert-equal "2.21 zero false positive warnings for typed variables"
              '()
              (untyped-boundary-warnings))

;; Global flag suppression (*warn-untyped-boundary* = #f)
(reset-untyped-boundary-warnings!)
(set-car! *warn-untyped-boundary* #f)
(assert-equal "2.22 untyped variable with warnings disabled returns deep-copy"
              'deep-copy
              (classify-capture-mode 'silent-untyped '() 'spawn-task))
(assert-equal "2.23 no warning emitted when *warn-untyped-boundary* is disabled"
              '()
              (untyped-boundary-warnings))
(set-car! *warn-untyped-boundary* #t)

;;; -----------------------------------------------------------------------
;;; Group 3: spawn-task and with-channel Plane Boundary Splitting
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Plane Boundary Splitting (AST Separation) ---\n")

(reset-asc-kernel-counter!)

(define input-spawn-1
  '(spawn-task
     (+ n count)))

(define split-res-1 (split-planes-ast input-spawn-1 sample-type-env))
(define bridge-1 (car split-res-1))
(define kernels-1 (cdr split-res-1))

(assert-true "3.1 bridge expression is %boundary-bridge"
             (boundary-bridge? bridge-1))

(assert-equal "3.2 bridge targets %asc-kernel-1"
              '%asc-kernel-1
              (caddr bridge-1))

(assert-equal "3.3 kernels list has 1 kernel"
              1
              (length kernels-1))

(define kernel-1 (car kernels-1))
(assert-true "3.4 kernel is %asc-kernel"
             (asc-kernel? kernel-1))

(assert-equal "3.5 kernel header has name and captured vars"
              '(%asc-kernel-1 n count)
              (cadr kernel-1))

;; with-channel test
(define input-chan-1
  '(with-channel (rx tx 64)
     (send! tx payload-buffer)
     (recv! rx)))

(define split-res-2 (split-planes-ast input-chan-1 sample-type-env))
(define bridge-2 (car split-res-2))
(define kernels-2 (cdr split-res-2))

(assert-true "3.6 with-channel produces %boundary-bridge"
             (boundary-bridge? bridge-2))

(assert-equal "3.7 with-channel bridge contains captures"
              '((payload-buffer deep-copy))
              (cadr bridge-2))

(define kernel-2 (car kernels-2))
(assert-true "3.8 with-channel kernel is %asc-kernel"
             (asc-kernel? kernel-2))

(assert-equal "3.9 with-channel kernel formals include typed rx tx and fvars"
              '(%asc-kernel-2 (: rx channel) (: tx channel) payload-buffer)
              (cadr kernel-2))

;;; -----------------------------------------------------------------------
;;; Group 4: Full Form Transformation (split-planes-pass)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Full Form Transformation ---\n")

(reset-asc-kernel-counter!)

(define program-forms
  '((define (worker n payload)
      (spawn-task
        (process n payload)))
    (worker 10 "secret")))

(define transformed (split-planes-pass program-forms))

(assert-equal "4.1 transformed forms count is 3 (worker, invocation, extracted-kernel)"
              3
              (length transformed))

;; First form is define worker with %boundary-bridge
(define def-worker (car transformed))
(assert-equal "4.2 first form is define worker"
              'worker
              (if (pair? (cadr def-worker))
                  (caadr def-worker)
                  (cadr def-worker)))

;; Third form is extracted %asc-kernel-1
(define extracted-k (caddr transformed))
(assert-true "4.3 third form is %asc-kernel"
             (asc-kernel? extracted-k))

;;; -----------------------------------------------------------------------
;;; Group 5: Pass Manager Injection & Pipeline Integration
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Pass Manager Injection & Pipeline Integration ---\n")

(init-default-pass-registry!)
(assert-false "5.1 pass-synapse-split-planes not initially in pipeline"
              (memq 'pass-synapse-split-planes (map pass-id (build-pipeline 0 '()))))

;; Inject the pass
(inject-synapse-split-planes-pass!)
(define pipeline-synapse (build-pipeline 0 '()))
(define ids-synapse (map pass-id pipeline-synapse))

(assert-true "5.2 pass-synapse-split-planes successfully injected into pipeline"
             (memq 'pass-synapse-split-planes ids-synapse))

;; Check prerequisite validation
(assert-true "5.3 injected pipeline satisfies all prerequisite DAG constraints"
             (validate-pipeline-prerequisites pipeline-synapse))

;; Remove injected pass
(remove-synapse-split-planes-pass!)
(define pipeline-cleaned (build-pipeline 0 '()))
(assert-false "5.4 pass-synapse-split-planes cleanly removed"
              (memq 'pass-synapse-split-planes (map pass-id pipeline-cleaned)))

(test-end "Synapse Dual-Plane Boundary Splitting")
