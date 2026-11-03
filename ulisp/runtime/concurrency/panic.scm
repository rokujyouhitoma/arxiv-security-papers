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
  (atomic-fetch-add! *panic-timestamp-counter* 1))

(define-record-type <synapse-panic-record>
  (%make-synapse-panic-record reason details source-loc timestamp)
  synapse-panic-record?
  (reason     synapse-panic-reason)
  (details    synapse-panic-details)
  (source-loc synapse-panic-source-loc)
  (timestamp  synapse-panic-timestamp))

(define make-synapse-panic-record
  (case-lambda
    ((reason)
     (%make-synapse-panic-record reason (list) #f (allocate-panic-timestamp!)))
    ((reason details)
     (%make-synapse-panic-record reason details #f (allocate-panic-timestamp!)))
    ((reason details source-loc)
     (%make-synapse-panic-record reason details source-loc (allocate-panic-timestamp!)))))

;; -----------------------------------------------------------------------
;; 2. Active Current Task Tracking & Crash Logger Hook
;; -----------------------------------------------------------------------

(define *active-current-task-box* (make-atomic-box #f))
(define *synapse-crash-logger-hook-box* (make-atomic-box #f))

(define (current-synapse-task)
  (atomic-ref *active-current-task-box*))

(define (%set-current-synapse-task! task)
  (atomic-set! *active-current-task-box* task))

(define (synapse-set-crash-logger-hook! hook)
  (atomic-set! *synapse-crash-logger-hook-box* hook))

;; -----------------------------------------------------------------------
;; 3. Task Resource Zero-Leak Cleanup (Arena O(1) Reset & Channel Drop)
;; -----------------------------------------------------------------------

(define synapse-cleanup-task-resources!
  (case-lambda
    ((task panic-reason)
     (synapse-cleanup-task-resources! task panic-reason #f #f))
    ((task panic-reason secure-scrub?)
     (synapse-cleanup-task-resources! task panic-reason secure-scrub? #f))
    ((task panic-reason secure-scrub? wake-hook)
     (if (not (task-context? task))
         (error "synapse-cleanup-task-resources!: expected <task-context> (CWE-843)" task)
         (begin
           ;; 1. O(1) Instant Arena Reset (CWE-212 & CWE-400 Zero-Leak)
           (let ((arena (task-arena task)))
             (if (and arena (task-arena? arena))
                 (if secure-scrub?
                     (arena-secure-reset! arena)
                     (arena-reset! arena))
                 #f))
           ;; 2. Poison channels & dispatch link cascade / monitor notifications (CWE-833 Deadlock Prevention)
           (task-handle-termination! task (cons 'panic panic-reason) wake-hook)
           #t)))))

;; -----------------------------------------------------------------------
;; 4. Fail-Fast Panic Primitives
;; -----------------------------------------------------------------------

(define (%execute-task-panic! reason details secure?)
  (let* ((task (current-synapse-task))
         (panic-rec (%make-synapse-panic-record reason details #f (allocate-panic-timestamp!))))
    (if (and task (task-context? task))
        (let ((k (task-escape-continuation task))
              (hook (atomic-ref *synapse-crash-logger-hook-box*)))
          ;; Step A: Invoke crash logger hook if registered
          (if (procedure? hook)
              (hook task reason details)
              #f)
          ;; Step B: Instant O(1) clean-up of arena, owned channels & link cascades
          (synapse-cleanup-task-resources! task reason secure? #f)
          ;; Step C: Escape via continuation if boundary established
          (if (procedure? k)
              (k (cons 'panic panic-rec))
              (error "synapse-panic!: unhandled panic within task boundary" reason details)))
        (error "synapse-panic!: called outside active task boundary" reason details))))

(define synapse-panic!
  (case-lambda
    ((reason)
     (%execute-task-panic! reason (list) #f))
    ((reason d1)
     (%execute-task-panic! reason (list d1) #f))
    ((reason d1 d2)
     (%execute-task-panic! reason (list d1 d2) #f))
    ((reason d1 d2 d3)
     (%execute-task-panic! reason (list d1 d2 d3) #f))))

(define synapse-secure-panic!
  (case-lambda
    ((reason)
     (%execute-task-panic! reason (list) #t))
    ((reason d1)
     (%execute-task-panic! reason (list d1) #t))
    ((reason d1 d2)
     (%execute-task-panic! reason (list d1 d2) #t))
    ((reason d1 d2 d3)
     (%execute-task-panic! reason (list d1 d2 d3) #t))))

;; -----------------------------------------------------------------------
;; 5. Task Boundary Protection Wrapper (Zero-State Contamination)
;; -----------------------------------------------------------------------

(define with-synapse-task-boundary
  (case-lambda
    ((task thunk)
     (with-synapse-task-boundary task thunk #f))
    ((task thunk secure-scrub?)
     (if (not (task-context? task))
         (error "with-synapse-task-boundary: expected <task-context> (CWE-843)" task)
         (if (not (procedure? thunk))
             (error "with-synapse-task-boundary: expected procedure (CWE-843)" thunk)
             (call/cc
               (lambda (escape-k)
                 (let ((prev-task (current-synapse-task))
                       (prev-k (task-escape-continuation task)))
                   (dynamic-wind
                     (lambda ()
                       (task-set-escape-continuation! task escape-k)
                       (%set-current-synapse-task! task))
                     (lambda ()
                       (let ((res (thunk)))
                         (cons 'ok res)))
                     (lambda ()
                       (task-set-escape-continuation! task prev-k)
                       (%set-current-synapse-task! prev-task)))))))))))

;; -----------------------------------------------------------------------
;; 6. Fast Assertion Guard
;; -----------------------------------------------------------------------

(define synapse-assert-true!
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
         #t))))

(define synapse-assert
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
         #t))))
