;;; =======================================================================
;;; ULisp Concurrency Runtime: Reduction Safepoint & Preemption (preempt.scm)
;;; Conforms to DSN-37 Section 7.2 & Section 14.4 (Phase 2 Task 2.3), Issue #636
;;; Model: Erlang BEAM Reduction-based Deterministic Safepoint Polling
;;; =======================================================================

(define *default-reduction-budget* 4096)
(define *min-reduction-budget* 1)
(define *max-reduction-budget* 1048576) ; 1M reductions maximum

;; -----------------------------------------------------------------------
;; 1. <budgeted-task> Record Type (aligned with DSN-37 <task-context>)
;; -----------------------------------------------------------------------
;; Fields:
;;   id              : fixnum task identifier
;;   state-box       : 1-element vector holding task state ('ready | 'running | 'yielded | 'completed)
;;   reductions-box  : 1-element vector holding remaining reductions
;;   initial-budget  : fixnum baseline computation budget (default 4096)
;;   task-obj        : procedure, coroutine-context, or task-context
;;   exhaustions-box : 1-element vector holding exhaustions count

(define-record-type <budgeted-task>
  (%make-budgeted-task id state-box reductions-box initial-budget task-obj exhaustions-box)
  budgeted-task?
  (id              task-id)
  (state-box       %task-state-box)
  (reductions-box  %task-reductions-box)
  (initial-budget  task-initial-budget)
  (task-obj        task-target-obj)
  (exhaustions-box %task-exhaustions-box))

(define (%make-task-box val)
  (let ((v (make-vector 1)))
    (vector-set! v 0 val)
    v))

(define (%make-budgeted-task-impl id task-obj budget)
  (if (not (integer? id))
      (error "make-budgeted-task: id must be an integer (CWE-843)" id)
      (if (not (integer? budget))
          (error "make-budgeted-task: budget must be an integer (CWE-843)" budget)
          (if (or (< budget *min-reduction-budget*) (> budget *max-reduction-budget*))
              (error "make-budgeted-task: budget out of range [1, 1048576] (CWE-190)" budget)
              (let ((st-box (%make-task-box 'ready))
                    (red-box (%make-task-box budget))
                    (exh-box (%make-task-box 0)))
                (%make-budgeted-task id st-box red-box budget task-obj exh-box))))))

(define make-budgeted-task
  (case-lambda
    ((task-obj)
     (%make-budgeted-task-impl (allocate-task-id!) task-obj *default-reduction-budget*))
    ((arg1 arg2)
     (if (integer? arg1)
         (%make-budgeted-task-impl arg1 arg2 *default-reduction-budget*)
         (%make-budgeted-task-impl (allocate-task-id!) arg1 arg2)))
    ((id task-obj budget)
     (%make-budgeted-task-impl id task-obj budget))))

;; -----------------------------------------------------------------------
;; 2. State & Field Accessors (Unified with DSN-37 <task-context>)
;; -----------------------------------------------------------------------

(define (task-reductions obj)
  (cond
    ((budgeted-task? obj)
     (vector-ref (%task-reductions-box obj) 0))
    ((task-context? obj)
     (%task-reductions obj))
    (else
     (error "task-reductions: expected <budgeted-task> or <task-context> (CWE-843)" obj))))

(define (task-reductions-set! obj n)
  (cond
    ((budgeted-task? obj)
     (if (not (integer? n))
         (error "task-reductions-set!: n must be an integer (CWE-843)" n)
         (let ((clamped (if (< n 0) 0 (if (> n *max-reduction-budget*) *max-reduction-budget* n))))
           (vector-set! (%task-reductions-box obj) 0 clamped)
           clamped)))
    ((task-context? obj)
     (%task-reductions-set! obj n))
    (else
     (error "task-reductions-set!: expected <budgeted-task> or <task-context> (CWE-843)" obj))))

(define (task-exhaustion-count btask)
  (if (not (budgeted-task? btask))
      (error "task-exhaustion-count: expected <budgeted-task> (CWE-843)" btask)
      (vector-ref (%task-exhaustions-box btask) 0)))

(define (task-state obj)
  (cond
    ((budgeted-task? obj)
     (vector-ref (%task-state-box obj) 0))
    ((task-context? obj)
     (%task-state obj))
    (else
     (error "task-state: expected <budgeted-task> or <task-context> (CWE-843)" obj))))

(define (task-state-set! obj st)
  (cond
    ((budgeted-task? obj)
     (vector-set! (%task-state-box obj) 0 st)
     st)
    ((task-context? obj)
     (%task-state-set! obj st)
     st)
    (else
     (error "task-state-set!: expected <budgeted-task> or <task-context> (CWE-843)" obj))))

(define (task-exhausted? btask)
  (<= (task-reductions btask) 0))

;; -----------------------------------------------------------------------
;; 3. Budget Consumption & Replenishment
;; -----------------------------------------------------------------------

(define (%exhaustion-inc! btask)
  (let ((b (%task-exhaustions-box btask)))
    (vector-set! b 0 (+ (vector-ref b 0) 1))))

(define (%task-consume-impl! btask delta)
  (if (not (budgeted-task? btask))
      (error "task-consume-reductions!: expected <budgeted-task> (CWE-843)" btask)
      (if (or (not (integer? delta)) (< delta 0))
          (error "task-consume-reductions!: delta must be a non-negative integer (CWE-190)" delta)
          (let* ((box (%task-reductions-box btask))
                 (cur (vector-ref box 0))
                 (rem (- cur delta))
                 (clamped (if (< rem 0) 0 rem)))
            (vector-set! box 0 clamped)
            clamped))))

(define task-consume-reductions!
  (case-lambda
    ((btask)
     (%task-consume-impl! btask 1))
    ((btask delta)
     (%task-consume-impl! btask delta))))

(define (task-replenish! btask)
  (if (not (budgeted-task? btask))
      (error "task-replenish!: expected <budgeted-task> (CWE-843)" btask)
      (let ((init-b (task-initial-budget btask)))
        (%exhaustion-inc! btask)
        (vector-set! (%task-reductions-box btask) 0 init-b)
        init-b)))

;; -----------------------------------------------------------------------
;; 4. Safepoint Polling & Preemptive Yield
;; -----------------------------------------------------------------------

(define (%check-safepoint-impl! btask on-exhaust-thunk)
  (if (not (budgeted-task? btask))
      (error "check-safepoint!: expected <budgeted-task> (CWE-843)" btask)
      (let* ((box (%task-reductions-box btask))
             (cur (vector-ref box 0))
             (rem (- cur 1)))
        (if (<= rem 0)
            (begin
              (task-replenish! btask)
              (if on-exhaust-thunk
                  (on-exhaust-thunk)
                  #f))
            (begin
              (vector-set! box 0 rem)
              #t)))))

(define check-safepoint!
  (case-lambda
    ((btask)
     (%check-safepoint-impl! btask #f))
    ((btask on-exhaust-thunk)
     (%check-safepoint-impl! btask on-exhaust-thunk))))

(define (safepoint-poll! btask)
  (%check-safepoint-impl! btask #f))

(define (%scheduler-yield-impl! btask sched)
  (if (not (budgeted-task? btask))
      (error "scheduler-yield!: expected <budgeted-task> (CWE-843)" btask)
      (begin
        (task-state-set! btask 'yielded)
        ;; Avoid double-replenishment if check-safepoint! already replenished
        (if (not (= (task-reductions btask) (task-initial-budget btask)))
            (task-replenish! btask)
            #t)
        (if (and sched (work-stealing-scheduler? sched))
            (scheduler-spawn! sched btask)
            #f)
        (let ((target (task-target-obj btask)))
          (if (coroutine-context? target)
              (context-yield! 'yielded)
              #t)))))

(define scheduler-yield!
  (case-lambda
    ((btask)
     (%scheduler-yield-impl! btask #f))
    ((btask sched)
     (%scheduler-yield-impl! btask sched))))

;; -----------------------------------------------------------------------
;; 5. Budgeted Task Execution Engine
;; -----------------------------------------------------------------------

(define (budgeted-task-execute! btask)
  (if (not (budgeted-task? btask))
      (error "budgeted-task-execute!: expected <budgeted-task> (CWE-843)" btask)
      (let ((target (task-target-obj btask)))
        (task-state-set! btask 'running)
        (cond
          ;; Scheme coroutine context
          ((coroutine-context? target)
           (if (not (coroutine-terminated? target))
               (let ((res (context-resume! target)))
                 (if (coroutine-terminated? target)
                     (task-state-set! btask 'completed)
                     (task-state-set! btask 'yielded))
                 res)
               (begin
                 (task-state-set! btask 'completed)
                 #f)))
          ;; DSN-37 task-context
          ((task-context? target)
           (if (eq? (task-state target) 'ready)
               (begin
                 (task-state-set! target 'running)
                 (task-state-set! btask 'completed)
                 #t)
               (begin
                 (task-state-set! btask 'completed)
                 #t)))
          ;; Standard zero-argument procedure (thunk)
          ((and (not (vector? target)) (procedure? target))
           (let ((res (target)))
             (task-state-set! btask 'completed)
             res))
          (else
           (error "budgeted-task-execute!: invalid target task object (CWE-843)" target))))))

;; -----------------------------------------------------------------------
;; 6. Diagnostics & Introspection
;; -----------------------------------------------------------------------

(define (budgeted-task-stats btask)
  (if (not (budgeted-task? btask))
      (error "budgeted-task-stats: expected <budgeted-task> (CWE-843)" btask)
      (let ((tid (task-id btask))
            (init-b (task-initial-budget btask))
            (rem-r (task-reductions btask))
            (exh (task-exhaustion-count btask))
            (st (task-state btask)))
        (list (cons 'id tid)
              (cons 'initial-budget init-b)
              (cons 'remaining rem-r)
              (cons 'exhaustions exh)
              (cons 'state st)))))
