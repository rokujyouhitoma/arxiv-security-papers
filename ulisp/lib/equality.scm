;;; =======================================================================
;;; ULisp Standard Library: Equivalence and Comparison Predicates (R7RS Section 6.1, 6.3, 6.5, 6.6)
;;; Conforms to DSN-33 Architecture Specification, Issue #532, #556 & Issue #561
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §6.1 Equivalence predicates: eqv?
;; ---------------------------------------------------------------------
;; In ULisp, all numbers (fixnums), characters, booleans, empty list,
;; and eof objects are immediate tagged values. Heap objects (pairs,
;; vectors, strings, symbols, closures, continuations) are uniquely
;; addressed. Therefore, pointer identity (eq?) satisfies R7RS eqv?.
(define (eqv? a b)
  (eq? a b))

;; ---------------------------------------------------------------------
;; §6.3 Booleans: boolean=?
;; ---------------------------------------------------------------------
(define (boolean=? a b)
  (if (boolean? a)
      (if (boolean? b)
          (eq? a b)
          #f)
      #f))

;; ---------------------------------------------------------------------
;; §6.5 Symbols: symbol=?
;; ---------------------------------------------------------------------
(define (symbol=? a b)
  (if (symbol? a)
      (if (symbol? b)
          (eq? a b)
          #f)
      #f))

;; ---------------------------------------------------------------------
;; §6.6 Characters: char<?, char>?, char<=?, char>=?
;; ---------------------------------------------------------------------
(define (char<? a b)
  (< (char->integer a) (char->integer b)))

(define (char>? a b)
  (> (char->integer a) (char->integer b)))

(define (char<=? a b)
  (<= (char->integer a) (char->integer b)))

(define (char>=? a b)
  (>= (char->integer a) (char->integer b)))


