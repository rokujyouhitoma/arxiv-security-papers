;;; =======================================================================
;;; (ulisp concurrency io-uring) - Linux io_uring Event Loop (R7RS)
;;; Conforms to DSN-37 Section 7.4.3 & Section 14.9 Task 7.3 (Issue #677, #683)
;;; =======================================================================

(define-library (ulisp concurrency io-uring)
  (export
    <io-uring>
    make-io-uring
    io-uring?
    io-uring-fd
    io-uring-capacity
    io-uring-native?
    io-uring-sqpoll?
    io-uring-sq-idle-ms
    io-uring-active?
    io-uring-close!

    io-uring-registered-buffers
    io-uring-registered-buffer-count
    io-uring-enter-syscall-count
    io-uring-sqpoll-kick-count

    io-uring-register-buffers!
    io-uring-unregister-buffers!

    io-uring-submit-nop!
    io-uring-submit-read!
    io-uring-submit-write!
    io-uring-submit-read-fixed!
    io-uring-submit-write-fixed!
    io-uring-sqpoll-wakeup!

    io-uring-poll-completions!
    io-uring-dequeue-completion!

    io-uring-submitted-count
    io-uring-completed-count
    io-uring-pending-count
    io-uring-stats

    current-io-uring
    synapse-set-current-io-uring!

    IORING_OP_NOP
    IORING_OP_READ
    IORING_OP_WRITE
    IORING_OP_READ_FIXED
    IORING_OP_WRITE_FIXED
    IORING_SETUP_SQPOLL
    IORING_ENTER_SQ_WAKEUP
    IORING_REGISTER_BUFFERS
    IORING_UNREGISTER_BUFFERS)

  (import
    (scheme base)
    (ulisp atomic))

  (include "../../../runtime/concurrency/io_uring.scm"))
