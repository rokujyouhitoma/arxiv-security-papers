;;; =======================================================================
;;; ULisp Standard Library: First-Class Continuations & dynamic-wind (R7RS Section 6.10)
;;; Conforms to DSN-33 Architecture Specification, Issue #540 & Issue #561
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;; =======================================================================

;; Mutable cell holding the active dynamic-wind chain
(define *ulisp-wind-cell* (cons '() '()))

(define (get-wind-chain)
  (car *ulisp-wind-cell*))

(define (set-wind-chain! c)
  (set-car! *ulisp-wind-cell* c))

;; ---------------------------------------------------------------------
;; §6.10 Control features: dynamic-wind
;; ---------------------------------------------------------------------
(define (dynamic-wind before thunk after)
  (before)
  (set-wind-chain! (cons (cons before after) (get-wind-chain)))
  (let ((res (thunk)))
    (set-wind-chain! (cdr (get-wind-chain)))
    (after)
    res))

;;; Lowest Common Ancestor (LCA) helper for wind-chain transition
(define (wind-chain-length chain)
  (let loop ((c chain) (n 0))
    (if (null? c) n (loop (cdr c) (+ n 1)))))

(define (wind-to target-chain)
  (let ((cur (get-wind-chain)))
    (if (eq? cur target-chain)
        #t
        (let* ((len-cur (wind-chain-length cur))
               (len-target (wind-chain-length target-chain)))
          ;; 1. If cur is deeper than target, unwind cur until equal length
          (let unwind-cur ((c cur) (l-cur len-cur))
            (if (> l-cur len-target)
                (let ((after-fn (cdr (car c))))
                  (set-wind-chain! (cdr c))
                  (after-fn)
                  (unwind-cur (cdr c) (- l-cur 1)))
                ;; 2. If target is deeper or equal, find lowest common ancestor
                (let find-lca ((c1 c) (c2 target-chain) (l len-target) (to-rewind '()))
                  (if (> l l-cur)
                      (find-lca c1 (cdr c2) (- l 1) (cons (car c2) to-rewind))
                      (if (eq? c1 c2)
                          ;; Found common ancestor! Now rewind target path
                          (let rewind-target ((path to-rewind))
                            (if (null? path)
                                #t
                                (let ((frame (car path)))
                                  (set-wind-chain! (cons frame (get-wind-chain)))
                                  ((car frame))
                                  (rewind-target (cdr path)))))
                          ;; Step up both
                          (begin
                            (let ((after-fn (cdr (car c1))))
                              (set-wind-chain! (cdr c1))
                              (after-fn))
                            (find-lca (cdr c1) (cdr c2) (- l 1) (cons (car c2) to-rewind))))))))))))

;; ---------------------------------------------------------------------
;; §6.10 Control features: call-with-current-continuation / call/cc
;; ---------------------------------------------------------------------
(define (call-with-current-continuation proc)
  (let ((captured-wind (get-wind-chain)))
    (%raw-call/cc
      (lambda (raw-k)
        (proc (lambda (val)
                (wind-to captured-wind)
                (raw-k val)))))))

(define (call/cc proc)
  (call-with-current-continuation proc))
