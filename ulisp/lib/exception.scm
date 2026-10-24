;;; =======================================================================
;;; ULisp Standard Library: Exception Handling Substrate (R7RS Section 6.11)
;;; Conforms to DSN-33 Architecture Specification, Issue #531 & Issue #561
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §6.11 Exceptions: error-object?
;; ---------------------------------------------------------------------
(define (error-object? obj)
  (and (pair? obj) (eq? (car obj) 'error-object)))

;; ---------------------------------------------------------------------
;; §6.11 Exceptions: error-object-message
;; ---------------------------------------------------------------------
(define (error-object-message obj)
  (if (error-object? obj)
      (cadr obj)
      (raise (list 'error-object "error-object-message: expected error-object" obj))))

;; ---------------------------------------------------------------------
;; §6.11 Exceptions: error-object-irritants
;; ---------------------------------------------------------------------
(define (error-object-irritants obj)
  (if (error-object? obj)
      (cddr obj)
      (raise (list 'error-object "error-object-irritants: expected error-object" obj))))

;; ---------------------------------------------------------------------
;; §6.11 Exceptions: error-object-traceback (Issue #604)
;; ---------------------------------------------------------------------
(define (error-object-traceback obj)
  '())

;; ---------------------------------------------------------------------
;; §6.11 Exceptions: file-error?
;; ---------------------------------------------------------------------
(define (file-error? obj)
  (and (pair? obj) (eq? (car obj) 'file-error)))

;; ---------------------------------------------------------------------
;; §6.11 Exceptions: read-error?
;; ---------------------------------------------------------------------
(define (read-error? obj)
  (and (pair? obj) (eq? (car obj) 'read-error)))

;; ---------------------------------------------------------------------
;; §6.11 Exceptions: with-exception-handler
;; ---------------------------------------------------------------------
(define (with-exception-handler handler thunk)
  (%with-handler handler thunk))

;; ---------------------------------------------------------------------
;; §6.11 Exceptions: raise-continuable
;; ---------------------------------------------------------------------
(define (raise-continuable obj)
  (raise obj))
