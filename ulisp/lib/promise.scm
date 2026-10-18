;;; =======================================================================
;;; R7RS Section 4.2.5: Delayed Evaluation (Promise Runtime)
;;; Conforms to SRFI-45 (Primitives for Expressing Iterative Lazy Algorithms)
;;; =======================================================================

(define (%%make-promise tag val)
  (vector '%%promise (cons tag val)))

(define (promise? obj)
  (and (vector? obj)
       (= (vector-length obj) 2)
       (eq? (vector-ref obj 0) '%%promise)))

(define (make-promise obj)
  (if (promise? obj)
      obj
      (vector '%%promise (cons 'eager obj))))

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
