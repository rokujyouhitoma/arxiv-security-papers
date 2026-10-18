;;; =======================================================================
;;; ULisp Standard Library: Delayed Evaluation (R7RS Section 4.2.5, SRFI-45)
;;; Conforms to DSN-33 Architecture Specification, Issue #550 & Issue #561
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §4.2.5 Delayed evaluation: %%make-promise (Internal)
;; ---------------------------------------------------------------------
(define (%%make-promise tag val)
  (vector '%%promise (cons tag val)))

;; ---------------------------------------------------------------------
;; §4.2.5 Delayed evaluation: promise?
;; ---------------------------------------------------------------------
(define (promise? obj)
  (and (vector? obj)
       (= (vector-length obj) 2)
       (eq? (vector-ref obj 0) '%%promise)))

;; ---------------------------------------------------------------------
;; §4.2.5 Delayed evaluation: make-promise
;; ---------------------------------------------------------------------
(define (make-promise obj)
  (if (promise? obj)
      obj
      (vector '%%promise (cons 'eager obj))))

;; ---------------------------------------------------------------------
;; §4.2.5 Delayed evaluation: force
;; ---------------------------------------------------------------------
(define (force promise)
  (let loop ((p promise))
    (if (not (promise? p))
        p
        (let ((content (vector-ref p 1)))
          (if (eq? (car content) 'eager)
              (cdr content)
              (let* ((promise* ((cdr content)))
                     (content (vector-ref p 1)))
                (if (not (eq? (car content) 'eager))
                    (if (promise? promise*)
                        (let ((p*-content (vector-ref promise* 1)))
                          (set-car! content (car p*-content))
                          (set-cdr! content (cdr p*-content))
                          (vector-set! promise* 1 content))
                        (begin
                          (set-car! content 'eager)
                          (set-cdr! content promise*))))
                (loop p)))))))
