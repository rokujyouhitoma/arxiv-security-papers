;;; =======================================================================
;;; (ulisp concurrency io-uring) - Linux io_uring Event Loop (R7RS)
;;; Conforms to DSN-37 Section 7.4.3 & Section 14.9 Task 7.3 (Issue #677)
;;; =======================================================================

(define-library (ulisp concurrency io-uring)
  (export
    <io-uring>
    make-io-uring
    io-uring?
    io-uring-fd
    io-uring-capacity
    io-uring-native?
    io-uring-active?
    io-uring-close!

    io-uring-submit-nop!
    io-uring-submit-read!
    io-uring-submit-write!

    io-uring-poll-completions!
    io-uring-dequeue-completion!

    io-uring-submitted-count
    io-uring-completed-count
    io-uring-pending-count
    io-uring-stats

    current-io-uring
    synapse-set-current-io-uring!)

  (import
    (scheme base)
    (ulisp atomic))

  (include "../../../runtime/concurrency/io_uring.scm"))

