;;; =======================================================================
;;; ULisp Test Suite: SRFI 189 Maybe and Either
;;; Conforms to R7RS-large Hypnos Docket & SRFI 189
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(test-begin "srfi-189")

(define-syntax assert-equal
  (syntax-rules ()
    ((assert-equal name actual expected)
     (test-equal name expected actual))))

(define-syntax assert-true
  (syntax-rules ()
    ((assert-true name expr)
     (test-assert name expr))))

(define-syntax assert-false
  (syntax-rules ()
    ((assert-false name expr)
     (test-assert name (not expr)))))

(define (num= a b) (= a b))
(define (sym-eq? a b) (eq? a b))
(define (is-even? x) (even? x))
(define (add-op a b) (+ a b))
(define (is-string? x) (string? x))


(define (assert-error name thunk)
  (let ((raised-cell (cons #f '())))
    (with-exception-handler
     (lambda (exn)
       (set-car! raised-cell #t)
       #f)
     thunk)
    (test-assert name (car raised-cell))))

;; =======================================================================
;; Group 1: Constructors & Disjoint Predicates
;; =======================================================================
(write-string "--- Group 1: Constructors & Disjoint Predicates ---\n")

(let ((j (just 42)))
  (assert-true "just is maybe?" (maybe? j))
  (assert-true "just is just?" (just? j))
  (assert-false "just is not nothing?" (nothing? j))
  (assert-false "just is not either?" (either? j))
  (assert-false "just is not right?" (right? j))
  (assert-false "just is not left?" (left? j)))

(let ((n (nothing)))
  (assert-true "nothing is maybe?" (maybe? n))
  (assert-true "nothing is nothing?" (nothing? n))
  (assert-false "nothing is not just?" (just? n))
  (assert-false "nothing is not either?" (either? n))
  (assert-false "nothing is not right?" (right? n))
  (assert-false "nothing is not left?" (left? n)))

(let ((r (right 100)))
  (assert-true "right is either?" (either? r))
  (assert-true "right is right?" (right? r))
  (assert-false "right is not left?" (left? r))
  (assert-false "right is not maybe?" (maybe? r))
  (assert-false "right is not just?" (just? r))
  (assert-false "right is not nothing?" (nothing? r)))

(let ((l (left 'error-code)))
  (assert-true "left is either?" (either? l))
  (assert-true "left is left?" (left? l))
  (assert-false "left is not right?" (right? l))
  (assert-false "left is not maybe?" (maybe? l))
  (assert-false "left is not just?" (just? l))
  (assert-false "left is not nothing?" (nothing? l)))

;; Multi-value payload constructors
(let ((j0 (just))
      (j2 (just 1 2))
      (r2 (right 'a 'b))
      (l2 (left 'e 500)))
  (assert-true "just with 0 elements is just?" (just? j0))
  (assert-true "just with 2 elements is just?" (just? j2))
  (assert-true "right with 2 elements is right?" (right? r2))
  (assert-true "left with 2 elements is left?" (left? l2)))

;; =======================================================================
;; Group 2: Equality & Swap
;; =======================================================================
(write-string "--- Group 2: Equality & Swap ---\n")

(assert-true "maybe= singletons" (maybe= num= (just 1) (just 1)))
(assert-false "maybe= different values" (maybe= num= (just 1) (just 2)))
(assert-true "maybe= nothing nothing" (maybe= num= (nothing) (nothing)))
(assert-false "maybe= just nothing" (maybe= num= (just 1) (nothing)))
(assert-true "maybe= multi-value" (maybe= num= (just 1 2) (just 1 2)))
(assert-false "maybe= multi-value diff" (maybe= num= (just 1 2) (just 1 3)))
(assert-true "maybe= chain" (maybe= num= (just 1) (just 1) (just 1)))
(assert-false "maybe= chain diff" (maybe= num= (just 1) (just 1) (just 2)))

(assert-true "either= right right" (either= sym-eq? (right 'a) (right 'a)))
(assert-false "either= right right diff" (either= sym-eq? (right 'a) (right 'b)))
(assert-true "either= left left" (either= sym-eq? (left 'e) (left 'e)))
(assert-false "either= right left" (either= sym-eq? (right 'a) (left 'a)))
(assert-true "either= multi" (either= num= (right 1 2) (right 1 2)))

(let ((swapped-r (either-swap (right 10)))
      (swapped-l (either-swap (left 'err))))
  (assert-true "swap right becomes left?" (left? swapped-r))
  (assert-equal "swap right payload" (either-ref swapped-r (lambda (x) x)) 10)
  (assert-true "swap left becomes right?" (right? swapped-l))
  (assert-equal "swap left payload" (either-ref/default swapped-l #f) 'err))

;; =======================================================================
;; Group 3: Accessors & Extractors
;; =======================================================================
(write-string "--- Group 3: Accessors & Extractors ---\n")

(assert-equal "maybe-ref just" (maybe-ref (just 10) (lambda () 0)) 10)
(assert-equal "maybe-ref nothing" (maybe-ref (nothing) (lambda () 0)) 0)
(assert-equal "maybe-ref with success"
              (maybe-ref (just 10) (lambda () 0) (lambda (x) (* x 2)))
              20)
(assert-equal "maybe-ref/default just" (maybe-ref/default (just 10) 99) 10)
(assert-equal "maybe-ref/default nothing" (maybe-ref/default (nothing) 99) 99)

(assert-equal "either-ref right"
              (either-ref (right 10) (lambda (e) -1))
              10)
(assert-equal "either-ref left"
              (either-ref (left "bad") (lambda (e) (string-append "err:" e)))
              "err:bad")
(assert-equal "either-ref with success"
              (either-ref (right 10) (lambda (e) 0) (lambda (x) (* x 3)))
              30)
(assert-equal "either-ref/default right" (either-ref/default (right 10) 99) 10)
(assert-equal "either-ref/default left" (either-ref/default (left 'err) 99) 99)

;; =======================================================================
;; Group 4: Join, Bind & Compose (Monadic Operations)
;; =======================================================================
(write-string "--- Group 4: Join, Bind & Compose ---\n")

(assert-true "maybe-join just just"
             (maybe= num= (maybe-join (just (just 5))) (just 5)))
(assert-true "maybe-join just nothing"
             (maybe= num= (maybe-join (just (nothing))) (nothing)))
(assert-true "maybe-join nothing"
             (maybe= num= (maybe-join (nothing)) (nothing)))

(assert-true "either-join right right"
             (either= num= (either-join (right (right 7))) (right 7)))
(assert-true "either-join right left"
             (either= sym-eq? (either-join (right (left 'bad))) (left 'bad)))
(assert-true "either-join left"
             (either= sym-eq? (either-join (left 'outer)) (left 'outer)))

(let ((res-m (maybe-bind (just 4)
                         (lambda (x) (just (* x 2)))
                         (lambda (x) (just (+ x 1))))))
  (assert-true "maybe-bind pipeline" (maybe= num= res-m (just 9))))

(let ((res-mn (maybe-bind (just 4)
                          (lambda (x) (nothing))
                          (lambda (x) (just (+ x 1))))))
  (assert-true "maybe-bind short-circuit" (maybe= num= res-mn (nothing))))

(let ((res-init-n (maybe-bind (nothing) (lambda (x) (just (* x 2))))))
  (assert-true "maybe-bind init nothing" (maybe= num= res-init-n (nothing))))

(let ((comp-m (maybe-compose (lambda (x) (just (* x 2)))
                             (lambda (x) (just (+ x 1))))))
  (assert-true "maybe-compose" (maybe= num= (comp-m 4) (just 9))))

(let ((res-e (either-bind (right 4)
                          (lambda (x) (right (* x 2)))
                          (lambda (x) (right (+ x 1))))))
  (assert-true "either-bind pipeline" (either= num= res-e (right 9))))

(let ((res-el (either-bind (right 4)
                           (lambda (x) (left 'halted))
                           (lambda (x) (right (+ x 1))))))
  (assert-true "either-bind short-circuit" (either= sym-eq? res-el (left 'halted))))

;; =======================================================================
;; Group 5: Sequence Operations
;; =======================================================================
(write-string "--- Group 5: Sequence Operations ---\n")

(assert-equal "maybe-length just" (maybe-length (just 1)) 1)
(assert-equal "maybe-length nothing" (maybe-length (nothing)) 0)
(assert-equal "either-length right" (either-length (right 1)) 1)
(assert-equal "either-length left" (either-length (left 'e)) 0)

(assert-true "maybe-filter pass" (maybe= num= (maybe-filter is-even? (just 2)) (just 2)))
(assert-true "maybe-filter drop" (maybe= num= (maybe-filter is-even? (just 3)) (nothing)))
(assert-true "maybe-filter nothing" (maybe= num= (maybe-filter is-even? (nothing)) (nothing)))

(assert-true "maybe-remove drop" (maybe= num= (maybe-remove is-even? (just 2)) (nothing)))
(assert-true "maybe-remove keep" (maybe= num= (maybe-remove is-even? (just 3)) (just 3)))

(assert-true "either-filter pass" (either= num= (either-filter is-even? (right 2) 'not-even) (right 2)))
(assert-true "either-filter drop" (either= sym-eq? (either-filter is-even? (right 3) 'not-even) (left 'not-even)))

(assert-true "either-remove drop" (either= sym-eq? (either-remove is-even? (right 2) 'is-even) (left 'is-even)))
(assert-true "either-remove keep" (either= num= (either-remove is-even? (right 3) 'is-even) (right 3)))

(let ((seq-m (maybe-sequence (list (just 1) (just 2) (just 3)) map (lambda (x) x))))
  (assert-true "maybe-sequence success"
               (equal? (maybe-ref/default seq-m '()) '(1 2 3))))

(let ((seq-mn (maybe-sequence (list (just 1) (nothing) (just 3)) map)))
  (assert-true "maybe-sequence failure" (nothing? seq-mn)))

(let ((seq-e (either-sequence (list (right 1) (right 2)) map (lambda (x) x))))
  (assert-true "either-sequence success"
               (equal? (either-ref/default seq-e '()) '(1 2))))

(let ((seq-el (either-sequence (list (right 1) (left 'err)) map)))
  (assert-true "either-sequence failure" (either= sym-eq? seq-el (left 'err))))

;; =======================================================================
;; Group 6: Protocol Conversion
;; =======================================================================
(write-string "--- Group 6: Protocol Conversion ---\n")

(assert-equal "maybe->list just" (maybe->list (just 1 2)) '(1 2))
(assert-equal "maybe->list nothing" (maybe->list (nothing)) '())
(assert-equal "either->list right" (either->list (right 1 2)) '(1 2))
(assert-equal "either->list left" (either->list (left 'err)) '(err))

(assert-true "list->maybe nonempty" (maybe= num= (list->maybe '(1 2)) (just 1 2)))
(assert-true "list->maybe empty" (maybe= num= (list->maybe '()) (nothing)))

(assert-true "list->either nonempty" (either= num= (list->either '(1 2) 'def) (right 1 2)))
(assert-true "list->either empty" (either= sym-eq? (list->either '() 'def) (left 'def)))

(assert-true "maybe->either just" (either= num= (maybe->either (just 5) 'def) (right 5)))
(assert-true "maybe->either nothing" (either= sym-eq? (maybe->either (nothing) 'def) (left 'def)))

(assert-true "either->maybe right" (maybe= num= (either->maybe (right 5)) (just 5)))
(assert-true "either->maybe left" (maybe= num= (either->maybe (left 'err)) (nothing)))

(assert-equal "maybe->truth just" (maybe->truth (just 5)) 5)
(assert-false "maybe->truth nothing" (maybe->truth (nothing)))
(assert-true "truth->maybe truthy" (maybe= num= (truth->maybe 5) (just 5)))
(assert-true "truth->maybe #f" (maybe= num= (truth->maybe #f) (nothing)))

(assert-equal "either->truth right" (either->truth (right 5)) 5)
(assert-false "either->truth left" (either->truth (left 'err)))
(assert-true "truth->either truthy" (either= num= (truth->either 5 'err) (right 5)))
(assert-true "truth->either #f" (either= sym-eq? (truth->either #f 'err) (left 'err)))

(assert-equal "maybe->generation just" (maybe->generation (just 5)) 5)
(assert-true "maybe->generation nothing" (eof-object? (maybe->generation (nothing))))
(assert-true "generation->maybe val" (maybe= num= (generation->maybe 5) (just 5)))
(assert-true "generation->maybe eof" (maybe= num= (generation->maybe (eof-object)) (nothing)))

(assert-true "values->maybe multiple"
             (maybe= num= (values->maybe (lambda () (values 1 2))) (just 1 2)))
(assert-true "values->maybe zero"
             (maybe= num= (values->maybe (lambda () (values))) (nothing)))

(assert-true "values->either multiple"
             (either= num= (values->either (lambda () (values 1 2)) 'err) (right 1 2)))
(assert-true "values->either zero"
             (either= sym-eq? (values->either (lambda () (values)) 'err) (left 'err)))

(assert-equal "maybe->two-values just"
              (call-with-values (lambda () (maybe->two-values (just 42))) list)
              '(42 #t))
(assert-equal "maybe->two-values nothing"
              (call-with-values (lambda () (maybe->two-values (nothing))) list)
              '(#f #f))

(assert-true "two-values->maybe success"
             (maybe= num= (two-values->maybe (lambda () (values 42 #t))) (just 42)))
(assert-true "two-values->maybe failure"
             (maybe= num= (two-values->maybe (lambda () (values 42 #f))) (nothing)))

;; =======================================================================
;; Group 7: Exception Containment & Guard
;; =======================================================================
(write-string "--- Group 7: Exception Containment & Guard ---\n")

(let ((res-ok (exception->either is-string? (lambda () 42))))
  (assert-true "exception->either success is right?" (right? res-ok))
  (assert-equal "exception->either success payload" (either-ref/default res-ok 0) 42))

(let ((res-err (exception->either is-string? (lambda () (raise "fail")))))
  (assert-true "exception->either caught is left?" (left? res-err))
  (assert-equal "exception->either caught payload" (either-ref res-err (lambda (e) e)) "fail"))

(let ((g-ok (either-guard is-string? 100)))
  (assert-true "either-guard ok is right?" (right? g-ok))
  (assert-equal "either-guard ok payload" (either-ref/default g-ok 0) 100))

(let ((g-err (either-guard is-string? (raise "boom"))))
  (assert-true "either-guard caught is left?" (left? g-err))
  (assert-equal "either-guard caught payload" (either-ref g-err (lambda (e) e)) "boom"))

;; =======================================================================
;; Group 8: Map, Fold & Unfold
;; =======================================================================
(write-string "--- Group 8: Map, Fold & Unfold ---\n")

(assert-true "maybe-map just"
             (maybe= num= (maybe-map (lambda (x) (* x 2)) (just 21)) (just 42)))
(assert-true "maybe-map nothing"
             (maybe= num= (maybe-map (lambda (x) (* x 2)) (nothing)) (nothing)))

(assert-true "either-map right"
             (either= num= (either-map (lambda (x) (* x 2)) (right 21)) (right 42)))
(assert-true "either-map left"
             (either= sym-eq? (either-map (lambda (x) (* x 2)) (left 'err)) (left 'err)))

(assert-equal "maybe-fold just" (maybe-fold add-op 10 (just 5)) 15)
(assert-equal "maybe-fold nothing" (maybe-fold add-op 10 (nothing)) 10)
(assert-equal "either-fold right" (either-fold add-op 10 (right 5)) 15)
(assert-equal "either-fold left" (either-fold add-op 10 (left 'err)) 10)

(let ((u-m1 (maybe-unfold (lambda (x) (= x 3))
                          (lambda (x) (* x 10))
                          (lambda (x) (+ x 1))
                          2)))
  (assert-true "maybe-unfold success" (maybe= num= u-m1 (just 20))))

(let ((u-m2 (maybe-unfold (lambda (x) (= x 2))
                          (lambda (x) (* x 10))
                          (lambda (x) (+ x 1))
                          2)))
  (assert-true "maybe-unfold stop immediately" (nothing? u-m2)))

(let ((u-e1 (either-unfold (lambda (x) (= x 3))
                           (lambda (x) (* x 10))
                           (lambda (x) (+ x 1))
                           2)))
  (assert-true "either-unfold success" (either= num= u-e1 (right 20))))

;; =======================================================================
;; Group 9: Trivalent Logic
;; =======================================================================
(write-string "--- Group 9: Trivalent Logic ---\n")

(assert-true "tri-not true" (maybe= sym-eq? (tri-not (just #t)) (just #f)))
(assert-true "tri-not false" (maybe= sym-eq? (tri-not (just #f)) (just #t)))
(assert-true "tri-not nothing" (nothing? (tri-not (nothing))))

(assert-true "tri=? both true" (maybe= sym-eq? (tri=? (just #t) (just #t)) (just #t)))
(assert-true "tri=? true false" (maybe= sym-eq? (tri=? (just #t) (just #f)) (just #f)))
(assert-true "tri=? with nothing" (maybe= sym-eq? (tri=? (nothing) (nothing)) (just #f)))

(assert-true "tri-and all true" (maybe= sym-eq? (tri-and (just #t) (just #t)) (just #t)))
(assert-true "tri-and has false" (maybe= sym-eq? (tri-and (just #t) (just #f)) (just #f)))
(assert-true "tri-and has nothing" (nothing? (tri-and (just #t) (nothing))))

(assert-true "tri-or has true" (maybe= sym-eq? (tri-or (just #t) (nothing)) (just #t)))
(assert-true "tri-or false and nothing" (nothing? (tri-or (just #f) (nothing))))
(assert-true "tri-or all false" (maybe= sym-eq? (tri-or (just #f) (just #f)) (just #f)))

(assert-true "tri-merge first just" (maybe= num= (tri-merge (nothing) (just 1) (just 2)) (just 1)))
(assert-true "tri-merge all nothing" (nothing? (tri-merge (nothing) (nothing))))

;; =======================================================================
;; Group 10: Syntax Forms & Short-Circuiting
;; =======================================================================
(write-string "--- Group 10: Syntax Forms & Short-Circuiting ---\n")

(assert-equal "maybe-if just" (maybe-if (just 10) 'yes 'no) 'yes)
(assert-equal "maybe-if nothing" (maybe-if (nothing) 'yes 'no) 'no)

(assert-true "maybe-and success" (maybe= num= (maybe-and (just 1) (just 2)) (just 2)))
(assert-true "maybe-and short-circuit" (nothing? (maybe-and (just 1) (nothing) (just 3))))

(assert-true "maybe-or first just" (maybe= num= (maybe-or (nothing) (just 2) (nothing)) (just 2)))
(assert-true "maybe-or all nothing" (nothing? (maybe-or (nothing) (nothing))))

(assert-true "either-and success" (either= num= (either-and (right 1) (right 2)) (right 2)))
(assert-true "either-and short-circuit" (either= sym-eq? (either-and (right 1) (left 'err) (right 3)) (left 'err)))

(assert-true "either-or first right" (either= num= (either-or (left 'e1) (right 2) (left 'e2)) (right 2)))
(assert-true "either-or all left" (either= sym-eq? (either-or (left 'e1) (left 'e2)) (left 'e2)))

(let ((res-let (maybe-let* ((x (just 10))
                            (y (just 20)))
                 (+ x y))))
  (assert-true "maybe-let* success" (maybe= num= res-let (just 30))))

(let ((res-let-n (maybe-let* ((x (just 10))
                              (y (nothing)))
                   (+ x y))))
  (assert-true "maybe-let* short-circuit" (nothing? res-let-n)))

(let ((res-e-let (either-let* ((x (right 10))
                               (y (right 20)))
                   (+ x y))))
  (assert-true "either-let* success" (either= num= res-e-let (right 30))))

(let ((res-e-let-l (either-let* ((x (right 10))
                                 (y (left 'err)))
                     (+ x y))))
  (assert-true "either-let* short-circuit" (either= sym-eq? res-e-let-l (left 'err))))

(let ((res-letv (maybe-let*-values (((x y) (just 10 20)))
                                    (+ x y))))
  (assert-true "maybe-let*-values success" (maybe= num= res-letv (just 30))))

(let ((res-e-letv (either-let*-values (((x y) (right 10 20)))
                                      (+ x y))))
  (assert-true "either-let*-values success" (either= num= res-e-letv (right 30))))

(test-end "srfi-189")
