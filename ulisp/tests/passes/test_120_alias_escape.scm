;;; =======================================================================
;;; ULisp Test Suite: TBAA & Escape Analysis Nanopass (Pass 6b)
;;; Conforms to DSN-33 Section 8.5 & Issue #525
;;;
;;; Verifies:
;;; 1. TBAA type-class categorization & provable disjointness
;;; 2. TBAA load preservation across disjoint stores (vector-set!, etc.)
;;; 3. Invalidation of cached loads on non-disjoint stores
;;; 4. Local non-escaping `cons` promotion to `%stack-cons`
;;; 5. Escaping `cons` (tail-return or heap escape) preservation as `cons`
;;; 6. Local non-escaping `%make-closure` promotion to `%make-stack-closure`
;;; 7. End-to-end LIR generation with `%alloc-stack`
;;; =======================================================================

(define *ae-tests-passed* 0)
(define *ae-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *ae-tests-passed* (+ *ae-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *ae-tests-failed* (+ *ae-tests-failed* 1))
        (display "  [FAIL] ")
        (display test-name)
        (display " -> Expected: ")
        (display expected)
        (display " but got: ")
        (display actual)
        (newline)
        (exit 1))))

(define (assert-true test-name expr)
  (assert-equal test-name #t (if expr #t #f)))

(define (assert-false test-name expr)
  (assert-equal test-name #f (if expr #t #f)))

(display "=======================================================")
(newline)
(display " Starting ULisp TBAA & Escape Analysis Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; -----------------------------------------------------------------------
;;; Test Group 1: TBAA Type Classes & Disjointness Theorems
;;; -----------------------------------------------------------------------
(display "--- Group 1: TBAA Type Classes & Disjointness ---")
(newline)

(assert-equal "pair type class for (car p)" 'pair (tbaa-type-class '(car p)))
(assert-equal "pair type class for (set-car! p v)" 'pair (tbaa-type-class '(set-car! p v)))
(assert-equal "closure type class for (%closure-ref c 1)" 'closure (tbaa-type-class '(%closure-ref c 1)))
(assert-equal "vector type class for (vector-set! v 0 x)" 'vector (tbaa-type-class '(vector-set! v 0 x)))
(assert-equal "raw type class for (%raw-store! ptr 0 v)" 'raw (tbaa-type-class '(%raw-store! ptr 0 v)))

;; Non-interference across disjoint memory classes
(assert-true "pair and vector are disjoint" (tbaa-disjoint? 'pair 'vector))
(assert-true "closure and pair are disjoint" (tbaa-disjoint? 'closure 'pair))
(assert-true "closure and vector are disjoint" (tbaa-disjoint? 'closure 'vector))
(assert-true "raw and pair are disjoint" (tbaa-disjoint? 'raw 'pair))
(assert-false "pair and pair are not disjoint" (tbaa-disjoint? 'pair 'pair))
(assert-false "unknown and pair are not disjoint" (tbaa-disjoint? 'unknown 'pair))

;;; -----------------------------------------------------------------------
;;; Test Group 2: TBAA Cache Invalidation Across Disjoint vs Non-Disjoint Stores
;;; -----------------------------------------------------------------------
(display "--- Group 2: TBAA Cache Preservation & Invalidation ---")
(newline)

(let* ((initial-loads '(((car p) pair r_car)
                        ((cdr p) pair r_cdr)
                        ((%closure-ref c 1) closure r_env1)))
       ;; A store to vector MUST NOT invalidate pair or closure loads
       (after-vec-store (tbaa-invalidate-loads '(vector-set! v 0 42) initial-loads)))
  (assert-equal "disjoint store preserves pair and closure loads"
                initial-loads
                after-vec-store))

(let* ((initial-loads '(((car p) pair r_car)
                        ((cdr p) pair r_cdr)
                        ((%closure-ref c 1) closure r_env1)))
       ;; A store to pair MUST invalidate pair loads but PRESERVE closure loads
       (after-pair-store (tbaa-invalidate-loads '(set-car! p 99) initial-loads)))
  (assert-equal "pair store preserves closure load but invalidates pair"
                '(((%closure-ref c 1) closure r_env1))
                after-pair-store))

;;; -----------------------------------------------------------------------
;;; Test Group 3: Flow-Sensitive Escape Analysis & Stack Promotion
;;; -----------------------------------------------------------------------
(display "--- Group 3: Flow-Sensitive Escape Analysis ---")
(newline)

;; Case 3.1: Non-escaping pair in local arithmetic
;; (let ((p (cons 10 20))) (+ (car p) (cdr p)))
;; Expected: p does not escape -> (cons 10 20) promoted to (%stack-cons 10 20)
(let* ((expr '(let ((p (cons 10 20)))
                (+ (car p) (cdr p))))
       (res (alias-escape-all expr)))
  (assert-equal "local non-escaping pair is promoted to %stack-cons"
                '(let ((p (%stack-cons 10 20)))
                   (+ (car p) (cdr p)))
                res))

;; Case 3.2: Escaping pair returned from function
;; (let ((p (cons 10 20))) p)
;; Expected: p escapes via tail position -> remains (cons 10 20)
(let* ((expr '(let ((p (cons 10 20)))
                p))
       (res (alias-escape-all expr)))
  (assert-equal "escaping pair returned in tail position remains (cons)"
                '(let ((p (cons 10 20)))
                   p)
                res))

;; Case 3.3: Escaping pair stored into another data structure
;; (let ((p (cons 1 2))) (vector-set! vec 0 p) 0)
;; Expected: p escapes into vec -> remains (cons 1 2)
(let* ((expr '(let ((p (cons 1 2)))
                (begin
                  (vector-set! vec 0 p)
                  0)))
       (res (alias-escape-all expr)))
  (assert-equal "pair stored into vector escapes and remains (cons)"
                '(let ((p (cons 1 2)))
                   (begin
                     (vector-set! vec 0 p)
                     0))
                res))

;; Case 3.4: Local temporary closure promotion
;; (let ((c (%make-closure 'L_add1 x))) (%closure-ref c 1))
;; Expected: c does not escape -> promoted to %make-stack-closure
(let* ((expr '(let ((c (%make-closure 'L_add1 x)))
                (%closure-ref c 1)))
       (res (alias-escape-all expr)))
  (assert-equal "local temporary closure is promoted to %make-stack-closure"
                '(let ((c (%make-stack-closure 'L_add1 x)))
                   (%closure-ref c 1))
                res))

;; Case 3.5: Local %make-closure-env promotion to (annotate #:stack-alloc ...)
;; (let ((c (%make-closure-env 'L_add1 x))) (%closure-ref c 1))
;; Expected: c does not escape -> annotated with #:stack-alloc
(let* ((expr '(let ((c (%make-closure-env 'L_add1 x)))
                (%closure-ref c 1)))
       (res (alias-escape-all expr)))
  (assert-equal "local %make-closure-env is annotated with #:stack-alloc"
                '(let ((c (annotate #:stack-alloc (%make-closure-env 'L_add1 x))))
                   (%closure-ref c 1))
                res))

;; Case 3.6: Locally invoked closure does not escape -> annotated with #:stack-alloc
;; (let ((f (%make-closure-env 'L_square x))) (f 10))
;; Expected: calling f does not cause f to escape!
(let* ((expr '(let ((f (%make-closure-env 'L_square x)))
                (f 10)))
       (res (alias-escape-all expr)))
  (assert-equal "locally invoked closure is annotated with #:stack-alloc"
                '(let ((f (annotate #:stack-alloc (%make-closure-env 'L_square x))))
                   (f 10))
                res))

;; Case 3.7: Escaping closure returned in tail position is NOT annotated
;; (let ((f (%make-closure-env 'L_square x))) f)
;; Expected: f escapes via tail position -> remains unannotated
(let* ((expr '(let ((f (%make-closure-env 'L_square x)))
                f))
       (res (alias-escape-all expr)))
  (assert-equal "escaping closure returned in tail position remains unannotated"
                '(let ((f (%make-closure-env 'L_square x)))
                   f)
                res))

;; Case 3.8: Escaping closure stored into heap data structure is NOT annotated
;; (let ((f (%make-closure-env 'L_square x))) (vector-set! vec 0 f) 0)
;; Expected: f escapes into vec -> remains unannotated
(let* ((expr '(let ((f (%make-closure-env 'L_square x)))
                (begin
                  (vector-set! vec 0 f)
                  0)))
       (res (alias-escape-all expr)))
  (assert-equal "closure stored into vector escapes and remains unannotated"
                '(let ((f (%make-closure-env 'L_square x)))
                   (begin
                     (vector-set! vec 0 f)
                     0))
                res))

;;; -----------------------------------------------------------------------
;;; Test Group 4: TBAA Redundant Load Elimination in AST
;;; -----------------------------------------------------------------------
(display "--- Group 4: TBAA Redundant Load Elimination ---")
(newline)

;; (let ((a (car p)))
;;   (let ((dummy (vector-set! v 0 100)))
;;     (let ((b (car p)))
;;       (+ a b))))
;; Since vector-set! does not alias pair, second (car p) is replaced with `a`!
(let* ((expr '(let ((a (car p)))
                (let ((dummy (vector-set! v 0 100)))
                  (let ((b (car p)))
                    (+ a b)))))
       (res (alias-escape-all expr)))
  (assert-equal "second (car p) is eliminated and replaced with a"
                '(let ((a (car p)))
                   (let ((dummy (vector-set! v 0 100)))
                    (let ((b a))
                      (+ a b))))
                res))

;;; -----------------------------------------------------------------------
;;; Test Group 5: LIR Generation with %alloc-stack
;;; -----------------------------------------------------------------------
(display "--- Group 5: LIR Generation with %alloc-stack ---")
(newline)

;; Check that (%stack-cons 42 99) emits %alloc-stack instruction in LIR
(let* ((prog '(%program () (%stack-cons 42 99)))
       (lir (generate-lir prog)))
  (let* ((lir-main (cadddr (cdr lir)))
         (body-entry (caddr lir-main))
         (insts (cdr body-entry))
         (has-alloc-stack?
          (let loop ((is insts))
            (cond
              ((null? is) #f)
              ((and (pair? (car is)) (eq? (caar is) '%alloc-stack)) #t)
              (else (loop (cdr is)))))))
    (assert-true "LIR contains %alloc-stack for %stack-cons" has-alloc-stack?)))

(display "=======================================================")
(newline)
(display " All ULisp TBAA & Escape Analysis Tests Passed (")
(display *ae-tests-passed*)
(display " passed)")
(newline)
(display "=======================================================")
(newline)
