;;; =======================================================================
;;; Library: (scheme lazy)
;;; Specification: R7RS-small Section 7.1.9 (Lazy Evaluation Library)
;;; Description: SRFI-45 compliant promises and iterative lazy algorithms
;;; =======================================================================

(define-library (scheme lazy)
  (export
    ;; §4.2.5 Delayed evaluation syntax & procedures
    delay
    force
    delay-force
    make-promise
    promise?)

  (include "../promise.scm"))
