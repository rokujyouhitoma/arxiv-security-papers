;;; =======================================================================
;;; MLisp Core: Delimited Continuations (shift / reset)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; Provides first-class delimited control primitives (shift / reset)
;;; for endogenous meta-tracing JIT in MLisp.
;;; Implements Danvy & Filinski style delimited control via meta-continuation stack.
;;; =======================================================================

;;; Internal meta-continuation stack for tracking delimited prompt boundaries
(define *meta-continuation-stack* '())

;;; Push a prompt exit continuation
(define (push-prompt-k! k)
  (set! *meta-continuation-stack* (cons k *meta-continuation-stack*)))

;;; Pop a prompt exit continuation
(define (pop-prompt-k!)
  (if (null? *meta-continuation-stack*)
      (error "Delimited control error: meta-continuation stack underflow")
      (let ((k (car *meta-continuation-stack*)))
        (set! *meta-continuation-stack* (cdr *meta-continuation-stack*))
        k)))

;;; Peek the innermost prompt exit continuation
(define (top-prompt-k)
  (if (null? *meta-continuation-stack*)
      (error "Delimited control error: shift called outside of any enclosing reset")
      (car *meta-continuation-stack*)))

;;; =======================================================================
;;; Core Primitives: reset-thunk & shift-thunk
;;; =======================================================================

;;; Evaluates thunk within a new delimited continuation boundary (prompt).
;;; When the thunk returns normally, the prompt is popped and the value returned.
(define (reset-thunk thunk)
  (call/cc
    (lambda (k-exit)
      (push-prompt-k! k-exit)
      (let ((res (thunk)))
        (pop-prompt-k!)
        res))))

;;; Captures the delimited continuation from the current point up to the enclosing reset.
;;; Aborts the evaluation up to that reset and invokes (receiver delimited-k).
(define (shift-thunk receiver)
  (call/cc
    (lambda (k-current)
      (let ((k-exit (pop-prompt-k!)))
        (k-exit
          (receiver
            (lambda (val)
              (push-prompt-k! k-exit)
              (k-current val))))))))

;;; =======================================================================
;;; Syntactic Macros: reset & shift
;;; =======================================================================

;;; Macro helper for reset
;;; Syntax: (reset body ...)
(define-macro (reset . body)
  `(reset-thunk (lambda () ,@body)))

;;; Macro helper for shift
;;; Syntax: (shift k body ...)
(define-macro (shift k . body)
  `(shift-thunk (lambda (,k) ,@body)))

;;; Abort helper: discards the delimited continuation and returns val directly
(define (abort-delimited val)
  (let ((k-exit (pop-prompt-k!)))
    (k-exit val)))
