;;; =======================================================================
;;; ULisp Test Suite: SRFI 116 (scheme ilist) & SRFI 134 (scheme ideque)
;;; Conforms to DSN-33 Architecture Specification & Issue #710
;;; =======================================================================

(define *test-count* (cons 0 '()))

(define (assert-equal label expected actual)
  (set-car! *test-count* (+ (car *test-count*) 1))
  (if (equal? expected actual)
      (begin
        (display "  [PASS] ")
        (display label)
        (newline)
        (flush-output-port))
      (begin
        (display "  [FAIL] ")
        (display label)
        (display " | expected: ")
        (write expected)
        (display " | actual: ")
        (write actual)
        (newline)
        (flush-output-port)
        (exit 1))))

(display "=============================================================\n")
(display " Starting SRFI 116 (ilist) & SRFI 134 (ideque) Test Suite\n")
(display "=============================================================\n")

;; ---------------------------------------------------------------------
;; 1. SRFI 116: Immutable Pairs & Lists (Constructors, Predicates, Selectors)
;; ---------------------------------------------------------------------
(display "--- 1. SRFI 116 Constructors, Predicates & Selectors ---\n")

(define ip1 (ipair 1 2))
(assert-equal "ipair? on ipair" #t (ipair? ip1))
(assert-equal "ipair? disjoint from pair?" #f (pair? ip1))
(assert-equal "pair? disjoint from ipair?" #f (ipair? (cons 1 2)))
(assert-equal "icar" 1 (icar ip1))
(assert-equal "icdr" 2 (icdr ip1))
(assert-equal "replace-icar" 99 (icar (replace-icar ip1 99)))
(assert-equal "replace-icdr" 88 (icdr (replace-icdr ip1 88)))

(define il1 (ilist 10 20 30 40))
(assert-equal "proper-ilist? on ilist" #t (proper-ilist? il1))
(assert-equal "dotted-ilist? on ipair" #t (dotted-ilist? ip1))
(assert-equal "ilength" 4 (ilength il1))
(assert-equal "ilist->list" '(10 20 30 40) (ilist->list il1))
(assert-equal "ifirst" 10 (ifirst il1))
(assert-equal "isecond" 20 (isecond il1))
(assert-equal "ithird" 30 (ithird il1))
(assert-equal "ilast" 40 (ilast il1))
(assert-equal "itake 2" '(10 20) (ilist->list (itake il1 2)))
(assert-equal "idrop 2" '(30 40) (ilist->list (idrop il1 2)))
(assert-equal "itake-right 2" '(30 40) (ilist->list (itake-right il1 2)))
(assert-equal "idrop-right 2" '(10 20) (ilist->list (idrop-right il1 2)))
(assert-equal "iiota 5" '(0 1 2 3 4) (ilist->list (iiota 5)))

;; ---------------------------------------------------------------------
;; 2. SRFI 116: Fold, Map, Filter, Search, Assoc & Tree Conversion
;; ---------------------------------------------------------------------
(display "--- 2. SRFI 116 Fold, Map, Filter, Search & Conversion ---\n")

(assert-equal "ireverse" '(40 30 20 10) (ilist->list (ireverse il1)))
(assert-equal "iappend" '(1 2 3 4) (ilist->list (iappend (ilist 1 2) (ilist 3 4))))
(assert-equal "imap" '(20 40 60 80) (ilist->list (imap (lambda (x) (* x 2)) il1)))
(assert-equal "ifold sum" 100 (ifold (lambda (a b) (+ a b)) 0 il1))
(assert-equal "ifold-right list" '(10 20 30 40) (ilist->list (ifold-right ipair '() il1)))
(assert-equal "ifilter >= 25" '(30 40) (ilist->list (ifilter (lambda (x) (>= x 25)) il1)))
(assert-equal "iremove >= 25" '(10 20) (ilist->list (iremove (lambda (x) (>= x 25)) il1)))
(assert-equal "ifind > 15" 20 (ifind (lambda (x) (> x 15)) il1))
(assert-equal "iany > 35" #t (iany (lambda (x) (> x 35)) il1))
(assert-equal "ievery > 5" #t (ievery (lambda (x) (> x 5)) il1))
(assert-equal "idelete 20" '(10 30 40) (ilist->list (idelete 20 il1)))
(assert-equal "idelete-duplicates" '(1 2 3) (ilist->list (idelete-duplicates (ilist 1 2 1 3 2))))

(define ial (ialist-cons 'a 1 (ialist-cons 'b 2 '())))
(assert-equal "iassq found" 2 (icdr (iassq 'b ial)))
(assert-equal "itree->tree & tree->itree" '((1 . 2) (3 4))
              (itree->tree (tree->itree '((1 . 2) (3 4)))))
(assert-equal "ilist-comparator =?" #t
              (=? ilist-comparator (ilist 1 2 3) (list->ilist '(1 2 3))))

;; ---------------------------------------------------------------------
;; 3. SRFI 134: Immutable Deques (Constructors, Queue Ops, Slices)
;; ---------------------------------------------------------------------
(display "--- 3. SRFI 134 Immutable Deques Queue Ops & Slices ---\n")

(define dq0 (ideque))
(assert-equal "ideque? on empty" #t (ideque? dq0))
(assert-equal "ideque-empty? on empty" #t (ideque-empty? dq0))

(define dq1 (ideque 10 20 30))
(assert-equal "ideque-length" 3 (ideque-length dq1))
(assert-equal "ideque-front" 10 (ideque-front dq1))
(assert-equal "ideque-back" 30 (ideque-back dq1))
(assert-equal "ideque-ref 1" 20 (ideque-ref dq1 1))

(define dq2 (ideque-add-back (ideque-add-front dq1 5) 40))
(assert-equal "ideque-add-front & add-back" '(5 10 20 30 40) (ideque->list dq2))
(assert-equal "ideque-remove-front" '(10 20 30 40) (ideque->list (ideque-remove-front dq2)))
(assert-equal "ideque-remove-back" '(5 10 20 30) (ideque->list (ideque-remove-back dq2)))
(assert-equal "ideque-take 3" '(5 10 20) (ideque->list (ideque-take dq2 3)))
(assert-equal "ideque-drop 3" '(30 40) (ideque->list (ideque-drop dq2 3)))
(assert-equal "ideque-take-right 2" '(30 40) (ideque->list (ideque-take-right dq2 2)))
(assert-equal "ideque-drop-right 2" '(5 10 20) (ideque->list (ideque-drop-right dq2 2)))

;; ---------------------------------------------------------------------
;; 4. SRFI 134: Higher-Order Operations & Generators
;; ---------------------------------------------------------------------
(display "--- 4. SRFI 134 Higher-Order Operations & Generators ---\n")

(assert-equal "ideque-reverse" '(40 30 20 10 5) (ideque->list (ideque-reverse dq2)))
(assert-equal "ideque-append" '(1 2 3 4)
              (ideque->list (ideque-append (ideque 1 2) (ideque 3 4))))
(assert-equal "ideque-map" '(10 20 30)
              (ideque->list (ideque-map (lambda (x) (* x 10)) (ideque 1 2 3))))
(assert-equal "ideque-fold" '(30 20 10)
              (ideque-fold (lambda (a b) (cons a b)) '() dq1))
(assert-equal "ideque-fold-right" '(10 20 30)
              (ideque-fold-right (lambda (a b) (cons a b)) '() dq1))
(assert-equal "ideque-filter >= 20" '(20 30 40)
              (ideque->list (ideque-filter (lambda (x) (>= x 20)) dq2)))
(assert-equal "ideque-find > 15" 20 (ideque-find (lambda (x) (> x 15)) dq2))
(assert-equal "ideque-find-right < 35" 30 (ideque-find-right (lambda (x) (< x 35)) dq2))
(assert-equal "ideque-take-while < 25" '(5 10 20)
              (ideque->list (ideque-take-while (lambda (x) (< x 25)) dq2)))
(assert-equal "ideque-take-while-right >= 20" '(20 30 40)
              (ideque->list (ideque-take-while-right (lambda (x) (>= x 20)) dq2)))

(define g-dq (ideque->generator dq1))
(define dq-from-g (generator->ideque g-dq))
(assert-equal "ideque->generator & generator->ideque" #t (ideque= (lambda (a b) (= a b)) dq1 dq-from-g))

(display "=============================================================\n")
(display " All ")
(display (car *test-count*))
(display " SRFI 116 & SRFI 134 Tests Passed Successfully!\n")
(display "=============================================================\n")
