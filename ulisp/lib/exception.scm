;;; =======================================================================
;;; ULisp Standard Library: Exception Handling Substrate (R7RS Section 6.11)
;;; Conforms to DSN-33 Architecture Specification & Issue #531
;;; =======================================================================

(define (error-object? obj)
  (and (pair? obj) (eq? (car obj) 'error-object)))

(define (error-object-message obj)
  (if (error-object? obj)
      (cadr obj)
      (raise (list 'error-object "error-object-message: expected error-object" obj))))

(define (error-object-irritants obj)
  (if (error-object? obj)
      (cddr obj)
      (raise (list 'error-object "error-object-irritants: expected error-object" obj))))

(define (file-error? obj)
  (and (pair? obj) (eq? (car obj) 'file-error)))

(define (read-error? obj)
  (and (pair? obj) (eq? (car obj) 'read-error)))

(define (with-exception-handler handler thunk)
  (%with-handler handler thunk))

(define (raise-continuable obj)
  (raise obj))
