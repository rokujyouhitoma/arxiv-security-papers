;;; =======================================================================
;;; Library: (scheme time)
;;; Specification: R7RS-small Section 7.1.14 (Time Library)
;;; Description: High-resolution timers and epoch timestamp procedures
;;; =======================================================================

(define-library (scheme time)
  (export
    ;; §6.14 System interface (Timers)
    current-second
    current-jiffy
    jiffies-per-second)

  (begin
    ;; Default fallback POSIX seconds / jiffies
    (define (jiffies-per-second) 1000000000)
    (define (current-second) 0)
    (define (current-jiffy) 0)))
