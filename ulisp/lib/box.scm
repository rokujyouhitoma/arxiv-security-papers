;;; =======================================================================
;;; Library: (scheme box) / (srfi 111)
;;; Specification: SRFI 111: Boxes / R7RS-large Red Edition
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; §1 Boxes: box
(define (box val)
  (cons '%box (cons val '())))

;; §1 Boxes: box?
(define (box? obj)
  (and (pair? obj) (eq? (car obj) '%box) (pair? (cdr obj))))

;; §1 Boxes: unbox
(define (unbox b)
  (if (box? b)
      (cadr b)
      (error "unbox: contract violation; expected box" b)))

;; §1 Boxes: set-box!
(define (set-box! b val)
  (if (box? b)
      (begin
        (set-car! (cdr b) val)
        63)
      (error "set-box!: contract violation; expected box" b)))

