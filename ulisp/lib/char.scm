;;; =======================================================================
;;; ULisp Standard Library: char.scm
;;; R7RS Section 6.6 & 7.1.3 (scheme char) Characters
;;; Classification, case conversion, and case-insensitive comparison
;;; Conforms to Issue #612
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §6.6 Characters: Character classification predicates
;; ---------------------------------------------------------------------

(define (char-alphabetic? c)
  (let ((code (char->integer c)))
    (or (and (>= code 65) (<= code 90))
        (and (>= code 97) (<= code 122)))))

(define (char-numeric? c)
  (let ((code (char->integer c)))
    (and (>= code 48) (<= code 57))))

(define (char-whitespace? c)
  (let ((code (char->integer c)))
    (or (= code 32)
        (and (>= code 9) (<= code 13)))))

(define (char-upper-case? c)
  (let ((code (char->integer c)))
    (and (>= code 65) (<= code 90))))

(define (char-lower-case? c)
  (let ((code (char->integer c)))
    (and (>= code 97) (<= code 122))))

(define (digit-value c)
  (let ((code (char->integer c)))
    (if (and (>= code 48) (<= code 57))
        (- code 48)
        #f)))

;; ---------------------------------------------------------------------
;; §6.6 Characters: Case conversion & Case folding
;; ---------------------------------------------------------------------

(define (char-upcase c)
  (let ((code (char->integer c)))
    (if (and (>= code 97) (<= code 122))
        (integer->char (- code 32))
        c)))

(define (char-downcase c)
  (let ((code (char->integer c)))
    (if (and (>= code 65) (<= code 90))
        (integer->char (+ code 32))
        c)))

(define (char-foldcase c)
  (char-downcase c))

;; ---------------------------------------------------------------------
;; §6.6 Characters: Case-insensitive character comparisons
;; ---------------------------------------------------------------------

(define (%char-ci-compare c1 c2)
  (- (char->integer (char-foldcase c1))
     (char->integer (char-foldcase c2))))

(define (char-ci=? c1 c2)
  (= (%char-ci-compare c1 c2) 0))

(define (char-ci<? c1 c2)
  (< (%char-ci-compare c1 c2) 0))

(define (char-ci>? c1 c2)
  (> (%char-ci-compare c1 c2) 0))

(define (char-ci<=? c1 c2)
  (<= (%char-ci-compare c1 c2) 0))

(define (char-ci>=? c1 c2)
  (>= (%char-ci-compare c1 c2) 0))
