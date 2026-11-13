;;; =======================================================================
;;; Synapse Concurrency Runtime: Epoch Fencing & Distributed Rollback (epoch.scm)
;;; Conforms to DSN-37 Section 8.2, 8.3 & Phase 4 Task 4.2 (Issue #642)
;;;
;;; Implements generation-based speculative cancellation and Generation Gate:
;;; - Global monotonically increasing epoch counter
;;; - Task epoch binding and registration registry
;;; - Atomic reduction budget zeroing and O(1) arena reset on rollback
;;; - Generation Gate validation for channel-waiting tasks (CWE-362 & CWE-400 guard)
;;; - First-class call/cc backtracking integration (epoch-checkpoint)
;;; =======================================================================

;; -----------------------------------------------------------------------
;; 1. Global Epoch Counters & State
;; -----------------------------------------------------------------------

(define *epoch-global-counter* (make-atomic-box 1))
(define *epoch-active-floor*   (make-atomic-box 1))
(define *epoch-aborted-list*   (make-atomic-box '()))
(define *epoch-task-registry*  (make-atomic-box '()))

;; Telemetry Counters
(define *epoch-stats-aborted-tasks*  (make-atomic-box 0))
(define *epoch-stats-aborted-epochs* (make-atomic-box 0))

;; -----------------------------------------------------------------------
;; 2. Epoch Queries & Transitions
;; -----------------------------------------------------------------------

(define (epoch-current)
  (declare (no-safepoints))
  (atomic-ref *epoch-global-counter*))

(define (epoch-floor)
  (declare (no-safepoints))
  (atomic-ref *epoch-active-floor*))

(define (epoch-advance!)
  (declare (no-safepoints))
  (+ (atomic-fetch-add! *epoch-global-counter* 1) 1))

(define (epoch-set-floor! floor-val)
  (declare (no-safepoints))
  (if (or (not (integer? floor-val)) (< floor-val 1))
      (error "epoch-set-floor!: floor must be a positive integer" floor-val)
      (atomic-set! *epoch-active-floor* floor-val)))

(define (epoch-aborted? ep)
  (declare (no-safepoints))
  (let ((aborted (atomic-ref *epoch-aborted-list*))
        (floor-val (atomic-ref *epoch-active-floor*)))
    (or (< ep floor-val)
        (if (memq ep aborted) #t #f))))

;; -----------------------------------------------------------------------
;; 3. Task Registration & Epoch Binding
;; -----------------------------------------------------------------------

(define epoch-bind-task!
  (begin (declare (no-safepoints))
   (case-lambda
    ((task)
     (epoch-bind-task! task (epoch-current) #f))
    ((task ep)
     (epoch-bind-task! task ep #f))
    ((task ep arena)
     (if (not (integer? ep))
         (error "epoch-bind-task!: epoch must be an integer" ep))
     (if (task-context? task)
         (task-epoch-set! task ep))
     ;; Register task in *epoch-task-registry* as (cons task (cons ep arena))
     (let loop ()
       (let* ((reg (atomic-ref *epoch-task-registry*))
              (new-reg (cons (cons task (cons ep arena)) reg)))
         (if (not (atomic-cas! *epoch-task-registry* reg new-reg))
             (loop)
             ep)))))))

(define (epoch-unbind-task! task)
  (declare (no-safepoints))
  (let loop ()
    (let* ((reg (atomic-ref *epoch-task-registry*))
           (new-reg (let rem ((cur reg))
                      (cond
                        ((null? cur) '())
                        ((eq? (caar cur) task) (cdr cur))
                        (else (cons (car cur) (rem (cdr cur))))))))
      (if (not (atomic-cas! *epoch-task-registry* reg new-reg))
          (loop)
          #t))))

(define (epoch-registered-tasks)
  (declare (no-safepoints))
  (atomic-ref *epoch-task-registry*))

;; -----------------------------------------------------------------------
;; 4. Task Cancellation & O(1) Arena Release
;; -----------------------------------------------------------------------

(define abort-task!
  (case-lambda
    ((task)
     (abort-task! task #f))
    ((task arena)
     (if task
         (begin
           ;; 1. Atomically zero the reduction budget to trigger instant safepoint abort
           (if (task-context? task)
               (begin
                 (%task-reductions-set! task 0)
                 (%task-state-set! task 'terminated)
                 (%task-blocked-on-set! task #f)))
           ;; 2. Reset process-local ephemeral arena in O(1) only if task is not actively executing (Issue #745, CWE-416)
           ;; If executing, arena will be safely reclaimed at boundary exit epilogue.
           (if (and arena (task-arena? arena)
                    (or (not (task-context? task))
                        (not (task-executing? task))))
               (begin
                 (if (task-context? task)
                     (%task-arena-offset-set! task 0))
                 (arena-reset! arena)))
           ;; Telemetry
           (atomic-fetch-add! *epoch-stats-aborted-tasks* 1)
           #t)
         #f))))

;; -----------------------------------------------------------------------
;; 5. Speculative Rollback (Generation Cancellation)
;; -----------------------------------------------------------------------

(define (epoch-rollback-to! target-epoch)
  (declare (no-safepoints))
  (if (or (not (integer? target-epoch)) (< target-epoch 1))
      (error "epoch-rollback-to!: target-epoch must be a positive integer" target-epoch)
      (begin
        ;; 1. Identify tasks belonging to epochs > target-epoch and abort them
        (let* ((reg (atomic-ref *epoch-task-registry*)))
          (let scan ((entries reg)
                     (survivors '())
                     (aborted-count 0))
            (if (not (null? entries))
                (let* ((entry (car entries))
                       (task (car entry))
                       (ep-arena (cdr entry))
                       (ep (if (pair? ep-arena) (car ep-arena) ep-arena))
                       (arena (if (pair? ep-arena) (cdr ep-arena) #f)))
                  (if (> ep target-epoch)
                      (begin
                        (abort-task! task arena)
                        (scan (cdr entries) survivors (+ aborted-count 1)))
                      (scan (cdr entries) (cons entry survivors) aborted-count)))
                ;; 2. Update registry with surviving tasks
                (let loop ()
                  (let ((cur-reg (atomic-ref *epoch-task-registry*)))
                    (if (not (atomic-cas! *epoch-task-registry* cur-reg survivors))
                        (loop)))))))

        ;; 3. Record aborted epochs list
        (let loop ()
          (let* ((cur-aborted (atomic-ref *epoch-aborted-list*))
                 (curr (epoch-current)))
            (let fill ((e (+ target-epoch 1))
                       (acc cur-aborted)
                       (new-cnt 0))
              (if (> e curr)
                  (begin
                    (if (> new-cnt 0)
                        (atomic-fetch-add! *epoch-stats-aborted-epochs* new-cnt))
                    (if (not (atomic-cas! *epoch-aborted-list* cur-aborted acc))
                        (loop)))
                  (if (memq e acc)
                      (fill (+ e 1) acc new-cnt)
                      (fill (+ e 1) (cons e acc) (+ new-cnt 1)))))))

        ;; 4. Advance to a fresh active epoch for subsequent operations
        (epoch-advance!))))

;; -----------------------------------------------------------------------
;; 6. Generation Gate Validation (DSN-37 Section 8.3)
;; -----------------------------------------------------------------------

(define (epoch-task-valid? task)
  (declare (no-safepoints))
  (if (not task)
      #f
      (let ((st (if (task-context? task) (%task-state task) 'unknown)))
        (if (or (eq? st 'terminated) (eq? st 'aborted))
            #f
            (let ((ep (if (task-context? task) (%task-epoch task) #f)))
              (if (not ep)
                  #t ; Unversioned task remains valid
                  (not (epoch-aborted? ep))))))))

(define (install-epoch-channel-gate!)
  (set-channel-epoch-validator! epoch-task-valid?))

;; -----------------------------------------------------------------------
;; 7. call/cc Backtracking Checkpoint Integration
;; -----------------------------------------------------------------------

(define (epoch-checkpoint proc)
  (declare (no-safepoints))
  (let ((saved-epoch (epoch-current)))
    (call/cc
     (lambda (k)
       (let ((rollback-fn (lambda (reason)
                            (let ((next-ep (epoch-rollback-to! saved-epoch)))
                              (k (cons 'rollback (cons reason next-ep)))))))
         (proc rollback-fn))))))

;; -----------------------------------------------------------------------
;; 8. Observability & Telemetry API
;; -----------------------------------------------------------------------

(define (epoch-stats)
  (declare (no-safepoints))
  (list (cons 'current-epoch (epoch-current))
        (cons 'active-floor (epoch-floor))
        (cons 'aborted-epochs (atomic-ref *epoch-stats-aborted-epochs*))
        (cons 'aborted-tasks (atomic-ref *epoch-stats-aborted-tasks*))
        (cons 'registered-tasks (length (atomic-ref *epoch-task-registry*)))))

(define (epoch-reset-stats!)
  (declare (no-safepoints))
  (begin
    (atomic-set! *epoch-stats-aborted-tasks* 0)
    (atomic-set! *epoch-stats-aborted-epochs* 0)
    #t))

(define (epoch-reset-global!)
  (declare (no-safepoints))
  (begin
    (atomic-set! *epoch-global-counter* 1)
    (atomic-set! *epoch-active-floor* 1)
    (atomic-set! *epoch-aborted-list* '())
    (atomic-set! *epoch-task-registry* '())
    (epoch-reset-stats!)
    #t))
