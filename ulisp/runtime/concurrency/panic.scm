;;; =======================================================================
;;; ULisp Runtime Concurrency: Fail-Fast "Let It Crash" Semantics (panic.scm)
;;; Conforms to DSN-37 Section 8.4.4 & 14.8 Task 6.3 (Issue #668)
;;;
;;; Implements:
;;;   1. Task-local Fail-Fast escape primitive: (synapse-panic! reason [details...])
;;;   2. Secure scrubbing panic variant: (synapse-secure-panic! reason [details...])
;;;   3. O(1) instant Ephemeral Arena bump reset and zero-leak cleanup
;;;   4. Automatic linear channel poisoning and RAII drop integration
;;;   5. Link cascade and monitor DOWN notification dispatch
;;;   6. Task boundary protection wrapper: (with-synapse-task-boundary task thunk)
;;;   7. Fast assertion guard: (synapse-assert condition msg [details...])
;;;   8. CWE-212 (Scrubbing), CWE-400 (Leak), CWE-833 (Deadlock), CWE-843 (Type) mitigations
;;; =======================================================================

;; -----------------------------------------------------------------------
;; 1. Panic Timestamp Allocator & Record Definition
;; -----------------------------------------------------------------------

(define *panic-timestamp-counter* (make-atomic-box 1))

(define (allocate-panic-timestamp!)
  (declare (no-safepoints))
  (atomic-fetch-add! *panic-timestamp-counter* 1))

(define-record-type <synapse-panic-record>
  (%make-synapse-panic-record reason details source-loc timestamp)
  synapse-panic-record?
  (reason     synapse-panic-reason)
  (details    synapse-panic-details)
  (source-loc synapse-panic-source-loc)
  (timestamp  synapse-panic-timestamp))

(define make-synapse-panic-record
  (begin (declare (no-safepoints))
   (case-lambda
    ((reason)
     (%make-synapse-panic-record reason (list) #f (allocate-panic-timestamp!)))
    ((reason details)
     (%make-synapse-panic-record reason details #f (allocate-panic-timestamp!)))
    ((reason details source-loc)
     (%make-synapse-panic-record reason details source-loc (allocate-panic-timestamp!))))))

;; -----------------------------------------------------------------------
;; 2. Active Current Task Tracking & Crash Logger Hook (Per-Worker TLS, #719)
;; -----------------------------------------------------------------------

(define *synapse-crash-logger-hook-box* (make-atomic-box #f))

(define (synapse-set-crash-logger-hook! hook)
  (declare (no-safepoints))
  (atomic-set! *synapse-crash-logger-hook-box* hook))

;; -----------------------------------------------------------------------
;; 3. Task Resource Zero-Leak Cleanup (Arena O(1) Reset & Channel Drop)
;; -----------------------------------------------------------------------

(define (synapse-deep-copy-reason val)
  (declare (no-safepoints))
  (channel-deep-copy val))

(define (%reclaim-terminated-task-arena! task secure-scrub?)
  (if (and (task-context? task)
           (not (task-executing? task))
           (eq? (task-state task) 'terminated))
      (let ((arena (task-arena task)))
        (if (and arena (task-arena? arena) (> (arena-used-bytes arena) 0))
            (if secure-scrub?
                (arena-secure-reset! arena)
                (arena-reset! arena))
            #f))
      #f))

(define synapse-cleanup-task-resources!
  (begin (declare (no-safepoints))
   (case-lambda
    ((task panic-reason)
     (synapse-cleanup-task-resources! task panic-reason #f #f))
    ((task panic-reason secure-scrub?)
     (synapse-cleanup-task-resources! task panic-reason secure-scrub? #f))
    ((task panic-reason secure-scrub? wake-hook)
     (if (not (task-context? task))
         (error "synapse-cleanup-task-resources!: expected <task-context> (CWE-843)" task)
         ;; 1. Deep-copy exit reason BEFORE arena reset (Issue #724, Item B5)
         (let ((copied-reason (synapse-deep-copy-reason panic-reason)))
           ;; 2. Mark terminated, zero reductions, poison channels & dispatch link/monitor notifications (Issue #723, Item B6 & A4)
           (task-handle-termination! task (cons 'panic copied-reason) wake-hook)
           ;; 3. Safe Arena Reclamation (Issue #745, CWE-416):
           ;; If the task is currently executing inside with-synapse-task-boundary,
           ;; DO NOT reset the arena prematurely. The arena will be safely reclaimed
           ;; at the boundary exit epilogue (%reclaim-terminated-task-arena!).
           ;; Only if the task is completely stopped (not executing) and terminated, reclaim immediately.
           (if (and (not (task-executing? task)) (eq? (task-state task) 'terminated))
               (let ((arena (task-arena task)))
                 (if (and arena (task-arena? arena))
                     (if secure-scrub?
                         (arena-secure-reset! arena)
                         (arena-reset! arena))
                     #f))
               #f)
           #t))))))

;; -----------------------------------------------------------------------
;; 4. Fail-Fast Panic Primitives
;; -----------------------------------------------------------------------

(define (%execute-task-panic! reason details secure?)
  (let* ((task (current-synapse-task))
         (safe-reason (synapse-deep-copy-reason reason))
         (safe-details (synapse-deep-copy-reason details))
         (panic-rec (%make-synapse-panic-record safe-reason safe-details #f (allocate-panic-timestamp!))))
    (if (and task (task-context? task))
        (let ((k (task-escape-continuation task))
              (hook (atomic-ref *synapse-crash-logger-hook-box*)))
          ;; Step A: Invoke crash logger hook if registered (with deep-copied reason & details)
          (if (procedure? hook)
              (hook task safe-reason safe-details)
              #f)
          ;; Step B: Notify monitors/links with deep-copied reason, then O(1) reset arena LAST
          (synapse-cleanup-task-resources! task safe-reason secure? #f)
          ;; Step C: Escape via continuation if boundary established
          (if (procedure? k)
              (k (cons 'panic panic-rec))
              (error "synapse-panic!: unhandled panic within task boundary" safe-reason safe-details)))
        (error "synapse-panic!: called outside active task boundary" safe-reason safe-details))))

(define synapse-panic!
  (begin (declare (no-safepoints))
   (case-lambda
    ((reason)
     (%execute-task-panic! reason (list) #f))
    ((reason d1)
     (%execute-task-panic! reason (list d1) #f))
    ((reason d1 d2)
     (%execute-task-panic! reason (list d1 d2) #f))
    ((reason d1 d2 d3)
     (%execute-task-panic! reason (list d1 d2 d3) #f)))))

(define synapse-secure-panic!
  (begin (declare (no-safepoints))
   (case-lambda
    ((reason)
     (%execute-task-panic! reason (list) #t))
    ((reason d1)
     (%execute-task-panic! reason (list d1) #t))
    ((reason d1 d2)
     (%execute-task-panic! reason (list d1 d2) #t))
    ((reason d1 d2 d3)
     (%execute-task-panic! reason (list d1 d2 d3) #t)))))

;; Connect Ephemeral Arena overflow to task-local synapse-panic! (Issue #721, Item A3)
(guard (exn (else #f))
  (set-arena-overflow-panic-hook!
   (lambda (reason msg irritant)
     (let ((task (current-synapse-task)))
       (if (and task (task-context? task) (procedure? (task-escape-continuation task)))
           (synapse-panic! reason msg irritant)
           (error msg irritant))))))

;; -----------------------------------------------------------------------
;; 5. Task Boundary Protection Wrapper (Zero-State Contamination)
;; -----------------------------------------------------------------------

(define *synapse-boundary-escape-tag* (list 'synapse-boundary-escape))

(define (%panic-with-synapse-task-boundary task thunk secure-scrub?)
  (if (not (task-context? task))
      (error "with-synapse-task-boundary: expected <task-context> (CWE-843)" task)
      (if (not (procedure? thunk))
          (error "with-synapse-task-boundary: expected procedure (CWE-843)" thunk)
          (let ((prev-task (current-synapse-task))
                (prev-k (task-escape-continuation task))
                (prev-hc (%asm-get-handler-chain))
                (task-hc (task-handler-chain task)))
            (task-executing-set! task #t)
            (let ((result
                   (guard (exn
                           ((and (pair? exn) (eq? (car exn) *synapse-boundary-escape-tag*))
                            (cdr exn))
                           (else
                            (let ((panic-rec (%make-synapse-panic-record
                                              (if (error-object? exn) 'error 'unhandled-exception)
                                              (if (error-object? exn)
                                                  (cons (error-object-message exn) (error-object-irritants exn))
                                                  (list exn))
                                              #f
                                              (allocate-panic-timestamp!)))
                                  (hook (atomic-ref *synapse-crash-logger-hook-box*)))
                              (if (procedure? hook)
                                  (hook task (synapse-panic-reason panic-rec) (synapse-panic-details panic-rec))
                                  #f)
                              (synapse-cleanup-task-resources! task (synapse-panic-reason panic-rec) secure-scrub? #f)
                              (cons 'panic panic-rec))))
                     (let* ((boundary-hc (%asm-get-handler-chain))
                            (escape-k (lambda (val)
                                        (%asm-set-handler-chain! boundary-hc)
                                        (raise (cons *synapse-boundary-escape-tag* val)))))
                       (task-set-escape-continuation! task escape-k)
                       (%set-current-synapse-task! task)
                       (if (and (integer? task-hc) (> task-hc 0))
                           (%asm-set-handler-chain! task-hc)
                           #f)
                       (with-exception-handler
                        (lambda (unhandled-exn)
                          (if (and (pair? unhandled-exn) (eq? (car unhandled-exn) *synapse-boundary-escape-tag*))
                              (begin
                                (%asm-set-handler-chain! boundary-hc)
                                (raise unhandled-exn))
                              (%execute-task-panic!
                               (if (error-object? unhandled-exn) 'error 'unhandled-exception)
                               (if (error-object? unhandled-exn)
                                   (cons (error-object-message unhandled-exn)
                                         (error-object-irritants unhandled-exn))
                                   (list unhandled-exn))
                               secure-scrub?)))
                        (lambda ()
                          (let ((res (thunk)))
                            (task-set-handler-chain! task (%asm-get-handler-chain))
                            (cons 'ok res))))))))
              (%asm-set-handler-chain! prev-hc)
              (task-set-escape-continuation! task prev-k)
              (%set-current-synapse-task! prev-task)
              (task-executing-set! task #f)
              ;; Ensure arena is reclaimed after execution stops if task was terminated via link cascade or panic (Issue #723, #745)
              (%reclaim-terminated-task-arena! task secure-scrub?)
              result)))))

(atomic-set! *synapse-task-boundary-hook-box* %panic-with-synapse-task-boundary)

(define with-synapse-task-boundary
  (begin (declare (no-safepoints))
   (case-lambda
    ((task thunk)
     (%panic-with-synapse-task-boundary task thunk #f))
    ((task thunk secure-scrub?)
     (%panic-with-synapse-task-boundary task thunk secure-scrub?)))))

;; -----------------------------------------------------------------------
;; 6. Fast Assertion Guard
;; -----------------------------------------------------------------------

(define synapse-assert-true!
  (begin (declare (no-safepoints))
   (case-lambda
    ((cond-val msg)
     (if (not cond-val)
         (synapse-panic! 'assertion-violation msg)
         #t))
    ((cond-val msg d1)
     (if (not cond-val)
         (synapse-panic! 'assertion-violation msg d1)
         #t))
    ((cond-val msg d1 d2)
     (if (not cond-val)
         (synapse-panic! 'assertion-violation msg d1 d2)
         #t)))))

(define synapse-assert
  (begin (declare (no-safepoints))
   (case-lambda
    ((test msg)
     (if (not test)
         (synapse-panic! 'assertion-violation msg)
         #t))
    ((test msg d1)
     (if (not test)
         (synapse-panic! 'assertion-violation msg d1)
         #t))
    ((test msg d1 d2)
     (if (not test)
         (synapse-panic! 'assertion-violation msg d1 d2)
         #t)))))
