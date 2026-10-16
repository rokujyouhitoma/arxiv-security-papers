;;; =======================================================================
;;; ULisp Standard Library: Equivalence Predicates (R7RS Section 6.1)
;;; Conforms to DSN-33 Architecture Specification & Issue #532
;;; =======================================================================

;;; eqv?: R7RS Section 6.1
;;; In ULisp, all numbers (fixnums), characters, booleans, empty list,
;;; and eof objects are immediate tagged values. Heap objects (pairs,
;;; vectors, strings, symbols, closures, continuations) are uniquely
;;; addressed. Therefore, pointer identity (eq?) satisfies R7RS eqv?.
(define (eqv? a b)
  (eq? a b))

;;; boolean=?: R7RS Section 6.3
(define (boolean=? a b)
  (if (boolean? a)
      (if (boolean? b)
          (eq? a b)
          #f)
      #f))

;;; symbol=?: R7RS Section 6.5
(define (symbol=? a b)
  (if (symbol? a)
      (if (symbol? b)
          (eq? a b)
          #f)
      #f))
