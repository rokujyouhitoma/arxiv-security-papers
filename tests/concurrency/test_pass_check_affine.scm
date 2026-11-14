;;; =======================================================================
;;; Synapse Affine Ownership Check & RAII Drop Test Suite
;;; Path: tests/concurrency/test_pass_check_affine.scm
;;; Conforms to DSN-37 Section 4.3, 12.2 & Phase 3 Task 3.2 (Issue #638)
;;; =======================================================================

(test-begin "Synapse Affine Linearity & RAII Drop")

;;; -----------------------------------------------------------------------
;;; Group 1: Linear Variable Predicates & Environment Operations
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Linear Type Predicates & Formal Invariants (Issue #797) ---\n")

;; 1.1-1.5: Linear Type Predicates (Type-Driven, free of variable name heuristics)
(assert-true "1.1 channel is a linear type"
             (linear-type? 'channel))

(assert-true "1.2 spsc-channel is a linear type"
             (linear-type? 'spsc-channel))

(assert-true "1.3 bounded-channel is a linear type"
             (linear-type? 'bounded-channel))

(assert-true "1.4 linear is a linear type"
             (linear-type? 'linear))

(assert-false "1.5 integer is NOT a linear type"
              (linear-type? 'integer))

;; 1.6-1.7: Formal Parameter Linearity: Strictly requires type annotation (: var type)
(assert-true "1.6 typed formal (: c channel) is linear"
             (kernel-formal-linear? '(: c channel)))

(assert-false "1.7 untyped symbol 'rx' is NOT linear without type annotation (CWE-843 #797)"
              (kernel-formal-linear? 'rx))

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

;; Unconsumed linear formal in kernel (with explicit type annotation #797)
(define kernel-with-unconsumed
  '(%asc-kernel (my-kernel (: rx channel) n)
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
  '(%asc-kernel (my-kernel (: tx channel) n)
     (channel-close! tx)))

(define transformed-k2 (check-affine-kernel kernel-consumed))
(define k2-body (caddr transformed-k2))

;; k2-body should be direct (channel-close! tx) or (begin (channel-close! tx)), NOT wrapped with %affine-drop!
(assert-true "6.4 consumed linear argument does not get extra %affine-drop!"
             (or (equal? k2-body '(channel-close! tx))
                 (equal? k2-body '(begin (channel-close! tx)))))

;; Kernel where channel is borrowed (sent/received): tx is still available at exit so RAII drop IS injected to close it
(define kernel-borrowed
  '(%asc-kernel (my-kernel (: tx channel) n)
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

;;; -----------------------------------------------------------------------
;;; Group 8: Type-Based Linearity & Provenance Analysis (Issue #749)
;;; -----------------------------------------------------------------------
(display "\n--- Group 8: Type-Based Linearity & Provenance Analysis (Issue #749) ---\n")

;; 8.1 Constructor operator recognition
(assert-true "8.1 make-channel is recognized as linear constructor"
             (linear-constructor-op? 'make-channel))
(assert-true "8.2 make-spsc-channel is recognized as linear constructor"
             (linear-constructor-op? 'make-spsc-channel))
(assert-false "8.3 cons is not linear constructor"
              (linear-constructor-op? 'cons))

;; 8.2-8.5 Binding type inference
(assert-true "8.4 arbitrary variable name 'c' bound to make-channel is linear"
             (infer-linear-binding? 'c '(make-channel 1) '()))

(assert-false "8.5 variable 'result' (res prefix) bound to integer is NOT linear (CWE-843)"
              (infer-linear-binding? 'result 42 '()))

(assert-false "8.6 variable 'buffer-size' (buf prefix) bound to arithmetic is NOT linear"
              (infer-linear-binding? 'buffer-size '(+ 1024 16) '()))

(assert-true "8.7 variable 'my-conn' bound to make-bounded-channel is linear"
             (infer-linear-binding? 'my-conn '(make-bounded-channel 16) '()))

;; 8.8 Arbitrary variable name: Use-After-Move detected on double send as linear payload
(define double-send-payload-arbitrary
  '(let ((c (make-channel 1)))
     (channel-send! tx c)
     (channel-send! tx c)))

(define r-double-arbitrary (validate-affine-ast double-send-payload-arbitrary env-tx-avail))
(assert-equal "8.8 double send of arbitrary name 'c' as payload detected as use-after-move"
              '(error use-after-move c)
              r-double-arbitrary)

;; 8.7 Close then send on arbitrary name 'pipe'
(define close-then-send-pipe
  '(let ((pipe (make-channel 1)))
     (channel-close! pipe)
     (channel-send! pipe 42)))

(define r-close-pipe (validate-affine-ast close-then-send-pipe '()))
(assert-equal "8.9 close then send on arbitrary name 'pipe' detected as use-after-move"
              '(error use-after-move pipe)
              r-close-pipe)

;; 8.8 Ownership transfer / Alias move: (let ((c2 c1)) ...)
(define move-alias-expr
  '(let ((c1 (make-channel 1)))
     (let ((c2 c1))
       (channel-send! c1 10))))

(define r-move-alias (validate-affine-ast move-alias-expr '()))
(assert-equal "8.10 use of transferred variable c1 detected as use-after-move"
              '(error use-after-move c1)
              r-move-alias)

;; 8.9 Non-linear variable 'result' can be referenced multiple times without error
(define multi-ref-result-expr
  '(let ((result 100))
     (+ result (+ result result))))

(define r-multi-result (validate-affine-ast multi-ref-result-expr '()))
(assert-true "8.11 multi-ref of non-linear 'result' validates ok"
             (and (pair? r-multi-result) (eq? (car r-multi-result) 'ok)))

;; 8.10 Non-linear variable 'result' does NOT get %affine-drop! injected
(define trans-result (transform-affine-expr multi-ref-result-expr '()))
(define trans-result-ast (car trans-result))
;; Body should simply be the let expression without let __raii_res or %affine-drop!
(assert-false "8.12 non-linear variable 'result' does NOT get %affine-drop! injected"
              (and (pair? (caddr trans-result-ast))
                   (eq? (car (caddr trans-result-ast)) 'let)
                   (pair? (cadr (caddr trans-result-ast)))
                   (pair? (caar (cadr (caddr trans-result-ast))))
                   (eq? (caar (cadr (caddr trans-result-ast))) '__raii_res)))

;; 8.11 Unconsumed arbitrary name 'c' gets %affine-drop! injected
(define unconsumed-c-expr
  '(let ((c (make-channel 1)))
     42))

(define trans-c (transform-affine-expr unconsumed-c-expr '()))
(define trans-c-ast (car trans-c))
;; The body of (let ((c ...)) ...) should have let __raii_res with (%affine-drop! c)
(assert-true "8.13 unconsumed arbitrary name 'c' gets (%affine-drop! c) injected"
             (and (pair? trans-c-ast)
                  (eq? (car trans-c-ast) 'let)
                  (let* ((body (caddr trans-c-ast)))
                    (and (pair? body)
                         (eq? (car body) 'let)
                         (let ((inner-begin (caddr body)))
                           (and (pair? inner-begin)
                                (eq? (car inner-begin) 'begin)
                                (member '(%affine-drop! c) (cdr inner-begin))
                                #t))))))

;; 8.12 Arbitrary name 'c' bound to make-channel is upgraded to make-spsc-channel
(define opt-binding-c (car (cadr trans-c-ast)))
(assert-equal "8.14 make-channel upgraded to make-spsc-channel on arbitrary name 'c'"
              'make-spsc-channel
              (caadr opt-binding-c))

;; 8.13 Typed formal parameter (: c channel) in kernel
(define typed-kernel-expr
  '(%asc-kernel (my-kernel (: c channel) n)
     (+ n 100)))

(define trans-typed-k (check-affine-kernel typed-kernel-expr))
(assert-true "8.15 typed formal (: c channel) produces %asc-kernel with normalized header"
             (and (pair? trans-typed-k)
                  (eq? (car trans-typed-k) '%asc-kernel)
                  (equal? (cadr trans-typed-k) '(my-kernel c n))))

(define typed-k-body (caddr trans-typed-k))
(assert-true "8.16 unconsumed typed formal 'c' gets (%affine-drop! c) injected"
             (and (pair? typed-k-body)
                  (eq? (car typed-k-body) 'let)
                  (let ((inner (caddr typed-k-body)))
                    (and (pair? inner)
                         (eq? (car inner) 'begin)
                         (member '(%affine-drop! c) (cdr inner))
                         #t))))

;;; -----------------------------------------------------------------------
;;; Group 9: Elimination of Name-Based Heuristics & Signature Propagation (Issue #792)
;;; -----------------------------------------------------------------------
(display "\n--- Group 9: Elimination of Name-Based Heuristics & Signature Propagation (Issue #792) ---\n")

;; 9.1-9.2 Variable name heuristics elimination for let bindings
(assert-false "9.1 variable 'result' bound to function call is NOT linear (CWE-843)"
              (infer-linear-binding? 'result '(compute-val) '()))

(assert-false "9.2 variable 'response' bound to function call is NOT linear"
              (infer-linear-binding? 'response '(fetch-packet) '()))

;; 9.3-9.5 Name hint predicate refinement
(assert-false "9.3 linear-variable-name-hint? rejects 'result"
              (linear-variable-name-hint? 'result))

(assert-false "9.4 linear-variable-name-hint? rejects 'response"
              (linear-variable-name-hint? 'response))

(assert-false "9.5 linear-variable-name-hint? unconditionally rejects 'resource (heuristics eliminated #797)"
              (linear-variable-name-hint? 'resource))

;; 9.6 Multi-reference of 'result' bound to function call validates ok (False-Positive Fixed)
(define multi-ref-result-call-expr
  '(let ((result (compute-val)))
     (+ result result)))

(define r-multi-result-call (validate-affine-ast multi-ref-result-call-expr '()))
(assert-true "9.6 multi-ref of 'result' bound to function call validates ok without use-after-move"
             (and (pair? r-multi-result-call) (eq? (car r-multi-result-call) 'ok)))

;; 9.7 Non-linear variable 'result' from function call does NOT get %affine-drop! injected
(define trans-result-call (transform-affine-expr multi-ref-result-call-expr '()))
(define trans-result-call-ast (car trans-result-call))
(assert-false "9.7 non-linear 'result' from function call does NOT get %affine-drop! injected"
              (and (pair? (caddr trans-result-call-ast))
                   (eq? (car (caddr trans-result-call-ast)) 'let)
                   (pair? (cadr (caddr trans-result-call-ast)))
                   (pair? (caar (cadr (caddr trans-result-call-ast))))
                   (eq? (caar (cadr (caddr trans-result-call-ast))) '__raii_res)))

;; 9.8 Multi-reference of 'response' validates ok
(define multi-ref-response-expr
  '(let ((response (fetch-data)))
     (list response response)))

(define r-multi-response (validate-affine-ast multi-ref-response-expr '()))
(assert-true "9.8 multi-ref of 'response' validates ok without error"
             (and (pair? r-multi-response) (eq? (car r-multi-response) 'ok)))

;; 9.9 Function signature propagation: arbitrary name 'c' bound to function returning channel
(define sig-env-pipe '((open-pipe . channel)))
(assert-true "9.9 arbitrary name 'c' bound to function returning channel is linear via sig-env"
             (infer-linear-binding? 'c '(open-pipe) '() sig-env-pipe))

;; 9.10 Double send of channel 'c' from function return detected as use-after-move (False-Negative Fixed)
(define double-send-c-from-pipe
  '(let ((c (open-pipe)))
     (channel-send! tx c)
     (channel-send! tx c)))

(define r-double-c-pipe (validate-affine-ast double-send-c-from-pipe env-tx-avail sig-env-pipe))
(assert-equal "9.10 double send of channel 'c' from function return detected as use-after-move"
              '(error use-after-move c)
              r-double-c-pipe)

;; 9.11 Close then send on 'c' from function return detected as use-after-move
(define close-then-send-c-pipe
  '(let ((c (open-pipe)))
     (channel-close! c)
     (channel-send! c 42)))

(define r-close-c-pipe (validate-affine-ast close-then-send-c-pipe '() sig-env-pipe))
(assert-equal "9.11 close then send on channel 'c' detected as use-after-move"
              '(error use-after-move c)
              r-close-c-pipe)

;; 9.12 Unconsumed channel 'c' from function return gets (%affine-drop! c) injected (CWE-775)
(define unconsumed-c-pipe
  '(let ((c (open-pipe)))
     42))

(define trans-c-pipe (transform-affine-expr unconsumed-c-pipe '() sig-env-pipe))
(define trans-c-pipe-ast (car trans-c-pipe))
(assert-true "9.12 unconsumed channel 'c' from function return gets (%affine-drop! c) injected"
             (and (pair? trans-c-pipe-ast)
                  (eq? (car trans-c-pipe-ast) 'let)
                  (let* ((body (caddr trans-c-pipe-ast)))
                    (and (pair? body)
                         (eq? (car body) 'let)
                         (let ((inner (caddr body)))
                           (and (pair? inner)
                                (eq? (car inner) 'begin)
                                (member '(%affine-drop! c) (cdr inner))
                                #t))))))

;; 9.13-9.15 Explicit annotations support
(assert-true "9.13 typed let-binding (: c channel) is recognized as linear"
             (infer-linear-binding? '(: c channel) '(external-call) '()))

(assert-true "9.14 explicit !linear annotation in let value is linear"
             (infer-linear-binding? 'c '(!linear (external-call)) '()))

(assert-true "9.15 explicit (: channel expr) in let value is linear"
             (infer-linear-binding? 'c '(: channel (external-call)) '()))

;; 9.16 Dynamic signature registration
(register-affine-signature! 'dyn-chan 'channel)
(assert-true "9.16 dynamic signature registration makes function call linear"
             (infer-linear-binding? 'c '(dyn-chan) '()))

;; 9.17-9.19 Top-level form signature scanning via scan-form-signatures
(define test-forms
  (list
    '(: typed-pipe (-> () channel))
    '(define (tail-chan-pipe) (make-channel 16))
    '(define (normal-fn) (+ 1 2))))

(define scanned-sigs (scan-form-signatures test-forms))
(assert-equal "9.17 scan-form-signatures detects typed-pipe return type"
              'channel
              (cdr (assq 'typed-pipe scanned-sigs)))

(assert-equal "9.18 scan-form-signatures infers tail-chan-pipe return type"
              'channel
              (cdr (assq 'tail-chan-pipe scanned-sigs)))

(assert-false "9.19 normal-fn is not in scanned signatures"
              (assq 'normal-fn scanned-sigs))

;; 9.20 End-to-end check-affine-pass integration with signature propagation & non-linear 'result'
(define full-program-forms
  (list
    '(: open-comm (-> () channel))
    '(%asc-kernel (run-worker rx)
       (let ((result (compute-data)))
         (let ((c (open-comm)))
           (channel-send! rx result)
           (channel-send! rx c))))))

(define pass-out (check-affine-pass full-program-forms))
(assert-true "9.20 check-affine-pass succeeds with 'result' and 'c' from signature"
             (and (pair? (cadr pass-out))
                  (eq? (car (cadr pass-out)) '%asc-kernel)))

(test-end "Synapse Affine Linearity & RAII Drop")
