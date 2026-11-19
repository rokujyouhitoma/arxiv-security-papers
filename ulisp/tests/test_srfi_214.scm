;;; =======================================================================
;;; ULisp Test Suite: SRFI 214 Flexvectors
;;; Conforms to R7RS-large Hypnos Docket & SRFI 214
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(test-begin "srfi-214")

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

(define (assert-error name thunk)
  (let ((raised-cell (cons #f '())))
    (with-exception-handler
     (lambda (exn)
       (set-car! raised-cell #t)
       #f)
     thunk)
    (test-assert name (car raised-cell))))

(define (num= a b) (= a b))
(define (add a b) (+ a b))
(define (sym-eq? a b) (eq? a b))
(define (is-even? x) (even? x))
(define (is-odd? x) (odd? x))

;; =======================================================================
;; Group 1: Constructors, Predicates & Selectors
;; =======================================================================
(write-string "--- Group 1: Constructors, Predicates & Selectors ---\n")

(let ((fv (make-flexvector 0)))
  (assert-true "make-flexvector 0 is flexvector?" (flexvector? fv))
  (assert-true "make-flexvector 0 is empty" (flexvector-empty? fv))
  (assert-equal "length 0" (flexvector-length fv) 0))

(let ((fv (make-flexvector 5 'init)))
  (assert-true "make-flexvector 5 is flexvector?" (flexvector? fv))
  (assert-false "make-flexvector 5 not empty" (flexvector-empty? fv))
  (assert-equal "length 5" (flexvector-length fv) 5)
  (assert-equal "ref 0" (flexvector-ref fv 0) 'init)
  (assert-equal "ref 4" (flexvector-ref fv 4) 'init)
  (assert-equal "front" (flexvector-front fv) 'init)
  (assert-equal "back" (flexvector-back fv) 'init))

(let ((fv (flexvector 10 20 30 40 50)))
  (assert-equal "flexvector length" (flexvector-length fv) 5)
  (assert-equal "flexvector-front" (flexvector-front fv) 10)
  (assert-equal "flexvector-back" (flexvector-back fv) 50)
  (assert-equal "flexvector-ref mid" (flexvector-ref fv 2) 30))

(assert-true "flexvector=? on identical"
             (flexvector=? num= (flexvector 1 2 3) (flexvector 1 2 3)))
(assert-false "flexvector=? on different elements"
              (flexvector=? num= (flexvector 1 2 3) (flexvector 1 2 4)))
(assert-false "flexvector=? on different length"
              (flexvector=? num= (flexvector 1 2) (flexvector 1 2 3)))
(assert-true "flexvector=? multiple args"
             (flexvector=? sym-eq? (flexvector 'a 'b) (flexvector 'a 'b) (flexvector 'a 'b)))

;; =======================================================================
;; Group 2: Fixed-size Mutators
;; =======================================================================
(write-string "--- Group 2: Fixed-size Mutators ---\n")

(let ((fv (flexvector 1 2 3 4 5)))
  (flexvector-set! fv 1 99)
  (assert-equal "flexvector-set!" (flexvector-ref fv 1) 99)
  (flexvector-swap! fv 0 4)
  (assert-equal "flexvector-swap! pos 0" (flexvector-ref fv 0) 5)
  (assert-equal "flexvector-swap! pos 4" (flexvector-ref fv 4) 1)
  (flexvector-fill! fv 0 1 3)
  (assert-equal "flexvector-fill! pos 1" (flexvector-ref fv 1) 0)
  (assert-equal "flexvector-fill! pos 2" (flexvector-ref fv 2) 0)
  (assert-equal "flexvector-fill! pos 3 unmutated" (flexvector-ref fv 3) 4))

(let ((fv (flexvector 1 2 3 4 5)))
  (flexvector-reverse! fv)
  (assert-equal "reverse! whole" (flexvector->list fv) '(5 4 3 2 1)))

(let ((fv (flexvector 1 2 3 4 5)))
  (flexvector-reverse! fv 1 4)
  (assert-equal "reverse! range" (flexvector->list fv) '(1 4 3 2 5)))

(let ((to (flexvector 0 0 0 0 0))
      (from (flexvector 10 20 30)))
  (flexvector-copy! to 1 from)
  (assert-equal "copy! from start" (flexvector->list to) '(0 10 20 30 0)))

(let ((to (flexvector 0 0 0 0 0))
      (from (flexvector 10 20 30)))
  (flexvector-reverse-copy! to 1 from)
  (assert-equal "reverse-copy!" (flexvector->list to) '(0 30 20 10 0)))

;; =======================================================================
;; Group 3: Dynamic Operations & Resizing
;; =======================================================================
(write-string "--- Group 3: Dynamic Operations & Resizing ---\n")

(let ((fv (flexvector 1 2 3)))
  (flexvector-add-back! fv 4 5)
  (assert-equal "add-back! multiple" (flexvector->list fv) '(1 2 3 4 5))
  (flexvector-add-front! fv -1 0)
  (assert-equal "add-front! multiple" (flexvector->list fv) '(-1 0 1 2 3 4 5))
  (flexvector-add! fv 3 'x 'y)
  (assert-equal "add! at index 3" (flexvector->list fv) '(-1 0 1 x y 2 3 4 5)))

(let ((fv (flexvector 10 20 30 40 50)))
  (assert-equal "remove-back! returns val" (flexvector-remove-back! fv) 50)
  (assert-equal "remove-back! state" (flexvector->list fv) '(10 20 30 40))
  (assert-equal "remove-front! returns val" (flexvector-remove-front! fv) 10)
  (assert-equal "remove-front! state" (flexvector->list fv) '(20 30 40))
  (assert-equal "remove! at index 1" (flexvector-remove! fv 1) 30)
  (assert-equal "remove! state" (flexvector->list fv) '(20 40)))

(let ((fv (flexvector 0 1 2 3 4 5 6 7)))
  (flexvector-remove-range! fv 2 5)
  (assert-equal "remove-range!" (flexvector->list fv) '(0 1 5 6 7)))

(let ((fv (flexvector 1 2 3)))
  (flexvector-clear! fv)
  (assert-true "clear! makes empty" (flexvector-empty? fv))
  (assert-equal "clear! length 0" (flexvector-length fv) 0))

(let ((fv (flexvector 1 2 3)))
  (flexvector-set-length! fv 5 'z)
  (assert-equal "set-length! expand" (flexvector->list fv) '(1 2 3 z z))
  (flexvector-set-length! fv 2)
  (assert-equal "set-length! truncate" (flexvector->list fv) '(1 2)))

(let ((fv (make-flexvector 0)))
  ;; Test geometric doubling under 500 pushes
  (let loop ((i 0))
    (if (< i 500)
        (begin
          (flexvector-add-back! fv i)
          (loop (+ i 1)))))
  (assert-equal "500 elements push length" (flexvector-length fv) 500)
  (assert-equal "500 elements push ref 0" (flexvector-ref fv 0) 0)
  (assert-equal "500 elements push ref 499" (flexvector-ref fv 499) 499)
  (flexvector-trim! fv)
  (assert-equal "trim! maintains elements" (flexvector-length fv) 500)
  (assert-equal "trim! back element" (flexvector-back fv) 499))

;; =======================================================================
;; Group 4: Copying & Appending
;; =======================================================================
(write-string "--- Group 4: Copying & Appending ---\n")

(let* ((orig (flexvector 1 2 3 4 5))
       (cp (flexvector-copy orig 1 4))
       (rcp (flexvector-reverse-copy orig 1 4)))
  (assert-equal "flexvector-copy subrange" (flexvector->list cp) '(2 3 4))
  (assert-equal "flexvector-reverse-copy subrange" (flexvector->list rcp) '(4 3 2)))

(let ((fv1 (flexvector 1 2))
      (fv2 (flexvector 3 4))
      (fv3 (flexvector 5)))
  (assert-equal "flexvector-append"
                (flexvector->list (flexvector-append fv1 fv2 fv3))
                '(1 2 3 4 5))
  (assert-equal "flexvector-concatenate"
                (flexvector->list (flexvector-concatenate (list fv1 fv2 fv3)))
                '(1 2 3 4 5)))

(let ((fv1 (flexvector 1 2 3 4))
      (fv2 (flexvector 10 20 30 40)))
  (assert-equal "flexvector-append-subvectors"
                (flexvector->list (flexvector-append-subvectors fv1 1 3 fv2 2 4))
                '(2 3 30 40)))

;; =======================================================================
;; Group 5: Unfold Procedures
;; =======================================================================
(write-string "--- Group 5: Unfold Procedures ---\n")

(let ((fv (flexvector-unfold (lambda (x) (> x 5))
                             (lambda (x) (* x 10))
                             (lambda (x) (+ x 1))
                             1)))
  (assert-equal "flexvector-unfold" (flexvector->list fv) '(10 20 30 40 50)))

(let ((fv (flexvector-unfold-right (lambda (x) (> x 5))
                                   (lambda (x) (* x 10))
                                   (lambda (x) (+ x 1))
                                   1)))
  (assert-equal "flexvector-unfold-right" (flexvector->list fv) '(50 40 30 20 10)))

;; =======================================================================
;; Group 6: Iteration & Higher-Order Procedures
;; =======================================================================
(write-string "--- Group 6: Iteration & Higher-Order Procedures ---\n")

(let ((fv (flexvector 1 2 3 4 5)))
  (assert-equal "flexvector-fold" (flexvector-fold add 0 fv) 15)
  (assert-equal "flexvector-fold cons" (flexvector-fold (lambda (acc x) (cons x acc)) '() fv) '(5 4 3 2 1))
  (assert-equal "flexvector-fold-right cons" (flexvector-fold-right (lambda (acc x) (cons x acc)) '() fv) '(1 2 3 4 5)))

(let ((fv1 (flexvector 1 2 3))
      (fv2 (flexvector 10 20 30)))
  (assert-equal "flexvector-map 2 args"
                (flexvector->list (flexvector-map add fv1 fv2))
                '(11 22 33))
  (assert-equal "flexvector-map/index"
                (flexvector->list (flexvector-map/index (lambda (i x) (+ (* i 100) x)) fv1))
                '(1 102 203)))

(let ((fv (flexvector 1 2 3)))
  (flexvector-map! (lambda (x) (* x 2)) fv)
  (assert-equal "flexvector-map!" (flexvector->list fv) '(2 4 6)))

(let ((acc-cell (cons 0 '()))
      (fv (flexvector 10 20 30)))
  (flexvector-for-each (lambda (x) (set-car! acc-cell (+ (car acc-cell) x))) fv)
  (assert-equal "flexvector-for-each" (car acc-cell) 60))

(let ((fv (flexvector 1 2 3)))
  (assert-equal "flexvector-append-map"
                (flexvector->list (flexvector-append-map (lambda (x) (flexvector x (* x 10))) fv))
                '(1 10 2 20 3 30)))

(let ((fv (flexvector 1 2 3 4 5 6)))
  (assert-equal "flexvector-filter"
                (flexvector->list (flexvector-filter is-even? fv))
                '(2 4 6))
  (assert-equal "flexvector-remove"
                (flexvector->list (flexvector-remove is-even? fv))
                '(1 3 5))
  (assert-equal "flexvector-count" (flexvector-count is-even? fv) 3))

(let ((fv (flexvector 1 2 3 4 5 6)))
  (flexvector-filter! is-even? fv)
  (assert-equal "flexvector-filter!" (flexvector->list fv) '(2 4 6)))

(let ((fv (flexvector 1 2 3 4 5)))
  (call-with-values
   (lambda () (flexvector-partition is-even? fv))
   (lambda (pass fail)
     (assert-equal "partition pass" (flexvector->list pass) '(2 4))
     (assert-equal "partition fail" (flexvector->list fail) '(1 3 5)))))

(let ((fv (vector->flexvector #(3 1 4 1 5 9 2 5 6))))
  (assert-equal "flexvector-cumulate sum"
                (flexvector->list (flexvector-cumulate add 0 fv))
                '(3 4 8 9 14 23 25 30 36)))

;; =======================================================================
;; Group 7: Searching Procedures
;; =======================================================================
(write-string "--- Group 7: Searching Procedures ---\n")

(let ((fv (flexvector 10 20 30 40 20 50)))
  (assert-equal "index match" (flexvector-index (lambda (x) (= x 20)) fv) 1)
  (assert-equal "index-right match" (flexvector-index-right (lambda (x) (= x 20)) fv) 4)
  (assert-false "index no match" (flexvector-index (lambda (x) (= x 99)) fv))
  (assert-equal "skip match" (flexvector-skip (lambda (x) (< x 30)) fv) 2)
  (assert-equal "skip-right match" (flexvector-skip-right (lambda (x) (> x 25)) fv) 4))

(let ((fv (flexvector 10 20 30 40 50 60 70 80)))
  (define (cmp a b) (cond ((= a b) 0) ((< a b) -1) (else 1)))
  (assert-equal "binary-search found middle" (flexvector-binary-search fv 40 cmp) 3)
  (assert-equal "binary-search found first" (flexvector-binary-search fv 10 cmp) 0)
  (assert-equal "binary-search found last" (flexvector-binary-search fv 80 cmp) 7)
  (assert-false "binary-search not found" (flexvector-binary-search fv 35 cmp)))

(let ((fv (flexvector 1 3 5 7 8 9)))
  (assert-true "any found" (flexvector-any is-even? fv))
  (assert-false "every not all true" (flexvector-every is-odd? fv)))

(let ((fv (flexvector 1 3 5 7 9)))
  (assert-true "every all true" (flexvector-every is-odd? fv)))

;; =======================================================================
;; Group 8: Conversions & Generator Interop
;; =======================================================================
(write-string "--- Group 8: Conversions & Generator Interop ---\n")

(let* ((v #(1 2 3 4 5))
       (fv (vector->flexvector v 1 4)))
  (assert-equal "vector->flexvector range" (flexvector->list fv) '(2 3 4))
  (assert-equal "flexvector->vector" (flexvector->vector fv) #(2 3 4)))

(let ((lst '(a b c d)))
  (assert-equal "list->flexvector" (flexvector->list (list->flexvector lst)) '(a b c d))
  (assert-equal "reverse-list->flexvector" (flexvector->list (reverse-list->flexvector lst)) '(d c b a))
  (assert-equal "reverse-flexvector->list" (reverse-flexvector->list (list->flexvector lst)) '(d c b a)))

(let* ((fv (flexvector 100 200 300))
       (gen (flexvector->generator fv)))
  (assert-equal "generator step 1" (gen) 100)
  (assert-equal "generator step 2" (gen) 200)
  (assert-equal "generator step 3" (gen) 300)
  (assert-true "generator eof" (eof-object? (gen))))

(let* ((cnt-cell (cons 0 '()))
       (test-gen (lambda ()
                   (let ((c (car cnt-cell)))
                     (if (< c 4)
                         (begin (set-car! cnt-cell (+ c 1)) (+ c 1))
                         (eof-object)))))
       (fv (generator->flexvector test-gen)))
  (assert-equal "generator->flexvector" (flexvector->list fv) '(1 2 3 4)))

;; =======================================================================
;; Group 9: Error Handling & Security Boundary Tests
;; =======================================================================
(write-string "--- Group 9: Error Handling & Security Boundary Tests ---\n")

;; Negative size allocation error (THREAT-863-1)
(assert-error "make-flexvector negative size" (lambda () (make-flexvector -5)))

;; Out of bounds access (THREAT-863-2)
(let ((fv (flexvector 1 2 3)))
  (assert-error "ref negative index" (lambda () (flexvector-ref fv -1)))
  (assert-error "ref past length" (lambda () (flexvector-ref fv 3)))
  (assert-error "set! negative index" (lambda () (flexvector-set! fv -1 99)))
  (assert-error "set! past length" (lambda () (flexvector-set! fv 3 99)))
  (assert-error "remove! past length" (lambda () (flexvector-remove! fv 3)))
  (assert-error "add! past length" (lambda () (flexvector-add! fv 4 99))))

;; Empty access error
(let ((empty-fv (make-flexvector 0)))
  (assert-error "front on empty" (lambda () (flexvector-front empty-fv)))
  (assert-error "back on empty" (lambda () (flexvector-back empty-fv)))
  (assert-error "remove-front! on empty" (lambda () (flexvector-remove-front! empty-fv)))
  (assert-error "remove-back! on empty" (lambda () (flexvector-remove-back! empty-fv))))

;; Type confusion defense (THREAT-863-3)
(assert-error "flexvector-length on raw vector" (lambda () (flexvector-length #(1 2 3))))
(assert-error "flexvector-ref on list" (lambda () (flexvector-ref '(1 2 3) 0)))
(assert-error "flexvector-add-back! on integer" (lambda () (flexvector-add-back! 42 1)))

(test-end "srfi-214")
