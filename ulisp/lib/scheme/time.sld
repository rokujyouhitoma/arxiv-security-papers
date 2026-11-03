;;; =======================================================================
;;; Library: (scheme time)
;;; Specification: R7RS-small Section 7.1.14 (Time Library: §6.14)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme time)
  (export
    ;; §6.14 System interface (Time)
    current-second
    current-jiffy
    jiffies-per-second)

  (begin
    ;; §6.14 System interface: current-second
    (define (current-second)
      (car (sys-clock-gettime-realtime)))

    ;; §6.14 System interface: jiffies-per-second
    (define (jiffies-per-second)
      1000000)

    ;; §6.14 System interface: current-jiffy
    (define (current-jiffy)
      (let* ((ts (sys-clock-gettime-monotonic))
             (sec (car ts))
             (nsec (cdr ts)))
        (+ (* sec 1000000) (quotient nsec 1000))))))
