;;; =======================================================================
;;; ULisp Runtime Concurrency: Erlang/OTP Supervision Tree (supervisor.scm)
;;; Conforms to DSN-37 Section 8.4.3 & 14.8 Task 6.2 (Issue #667)
;;;
;;; Implements:
;;;   1. <child-spec>, <supervisor-spec>, <supervisor-context> records
;;;   2. 3 core restart strategies: 'one_for_one, 'one_for_all, 'rest_for_one
;;;   3. Restart types: 'permanent, 'transient, 'temporary
;;;   4. Sliding time-window Flapping / Crash Loop detection (MaxRestarts / MaxTime)
;;;   5. Parent escalation and graceful shutdown cascading
;;;   6. Integration with Ephemeral Arena O(1) reset, channel poisoning, and links/monitors
;;;   7. CWE-400 (Loop DoS), CWE-662 (Sync/State), CWE-833 (Deadlock), CWE-843 (Type) mitigations
;;; =======================================================================

;; Optional registry rebind hook (injected via registry.scm, Issue #669)
(define *supervisor-registry-rebind-box* (vector (lambda (id target) #f)))

;; Optional crash logger hook (injected via crash_logger.scm, Issue #670)
(define *supervisor-crash-logger-hook-box* (vector (lambda (target-tid reason id) #f)))

(define (synapse-set-supervisor-crash-hook! hook)
  (vector-set! *supervisor-crash-logger-hook-box* 0 hook))

;; Optional scheduler spawn hook (injected via scheduler.scm, Issue #742)
(define *supervisor-scheduler-spawn-hook-box*
  (vector (lambda (sched task)
            (guard (exn (else #f))
              (if (procedure? scheduler-spawn!)
                  (scheduler-spawn! sched task)
                  #f)))))

(define (synapse-set-supervisor-scheduler-spawn-hook! hook)
  (vector-set! *supervisor-scheduler-spawn-hook-box* 0 hook))

;; -----------------------------------------------------------------------
;; 1. Monotonic System Clock for Supervisor Time Window (Issue #728, Item C4)
;; -----------------------------------------------------------------------

(define *supervisor-clock-offset-ms* (make-atomic-box 0))
(define *supervisor-clock* *supervisor-clock-offset-ms*)

(define (%monotonic-clock-ms)
  (let ((ts (sys-clock-gettime-monotonic)))
    (if (pair? ts)
        (+ (* (car ts) 1000) (quotient (cdr ts) 1000000))
        0)))

(define (supervisor-clock-now)
  (+ (%monotonic-clock-ms) (atomic-ref *supervisor-clock-offset-ms*)))

(define (allocate-supervisor-timestamp!)
  (supervisor-clock-now))

(define (supervisor-clock-advance! delta)
  (if (not (integer? delta))
      (error "supervisor-clock-advance!: delta must be an integer (CWE-843)" delta)
      (begin
        (atomic-fetch-add! *supervisor-clock-offset-ms* delta)
        (supervisor-clock-now))))

;; -----------------------------------------------------------------------
;; 2. Record Types: <child-spec>, <supervisor-spec>, <supervisor-context>
;; -----------------------------------------------------------------------

(define-record-type <child-spec>
  (%make-child-spec id start-thunk restart-type shutdown-strategy child-type init-args)
  child-spec?
  (id                child-spec-id)
  (start-thunk       child-spec-start-thunk)
  (restart-type      child-spec-restart-type)
  (shutdown-strategy child-spec-shutdown-strategy)
  (child-type        child-spec-child-type)
  (init-args         child-spec-init-args))

(define make-child-spec
  (case-lambda
    ((id start-thunk)
     (make-child-spec id start-thunk 'permanent 'brutal_kill 'worker '()))
    ((id start-thunk restart-or-args)
     (if (list? restart-or-args)
         (make-child-spec id start-thunk 'permanent 'brutal_kill 'worker restart-or-args)
         (make-child-spec id start-thunk restart-or-args 'brutal_kill 'worker '())))
    ((id start-thunk restart-type shutdown-strategy)
     (make-child-spec id start-thunk restart-type shutdown-strategy 'worker '()))
    ((id start-thunk restart-type shutdown-strategy child-type-or-args)
     (if (list? child-type-or-args)
         (make-child-spec id start-thunk restart-type shutdown-strategy 'worker child-type-or-args)
         (make-child-spec id start-thunk restart-type shutdown-strategy child-type-or-args '())))
    ((id start-thunk restart-type shutdown-strategy child-type init-args)
     (if (not (symbol? id))
         (error "make-child-spec: id must be a symbol (CWE-843)" id)
         (if (not (procedure? start-thunk))
             (error "make-child-spec: start-thunk must be a procedure (CWE-843)" start-thunk)
             (if (not (memq restart-type '(permanent transient temporary)))
                 (error "make-child-spec: invalid restart-type (CWE-843)" restart-type)
                 (if (not (list? init-args))
                     (error "make-child-spec: init-args must be a list (CWE-843)" init-args)
                     (%make-child-spec id start-thunk restart-type shutdown-strategy child-type (channel-deep-copy init-args)))))))))

(define-record-type <supervisor-spec>
  (%make-supervisor-spec strategy max-restarts max-time child-specs)
  supervisor-spec?
  (strategy     supervisor-spec-strategy)
  (max-restarts supervisor-spec-max-restarts)
  (max-time     supervisor-spec-max-time)
  (child-specs  supervisor-spec-child-specs))

(define make-supervisor-spec
  (case-lambda
    ((strategy max-restarts max-time child-specs)
     (if (not (memq strategy '(one_for_one one_for_all rest_for_one)))
         (error "make-supervisor-spec: invalid strategy (CWE-843)" strategy)
         (if (or (not (integer? max-restarts)) (< max-restarts 0))
             (error "make-supervisor-spec: max-restarts must be a non-negative integer" max-restarts)
             (if (or (not (integer? max-time)) (<= max-time 0))
                 (error "make-supervisor-spec: max-time must be a positive integer" max-time)
                 (if (not (list? child-specs))
                     (error "make-supervisor-spec: child-specs must be a list" child-specs)
                     (%make-supervisor-spec strategy max-restarts max-time child-specs))))))))

(define-record-type <supervisor-context>
  (%make-supervisor-context spec sup-task children-box restart-history-box parent-sup
                            state-box scheduler-box processing-box
                            preserved-inbox-box message-handler-box)
  supervisor-context?
  (spec                 supervisor-spec)
  (sup-task             supervisor-task)
  (children-box         %supervisor-children-box)
  (restart-history-box  %supervisor-restart-history-box)
  (parent-sup           supervisor-parent)
  (state-box            %supervisor-state-box)
  (scheduler-box        %supervisor-scheduler-box)
  (processing-box       %supervisor-processing-box)
  (preserved-inbox-box  %supervisor-preserved-inbox-box)
  (message-handler-box  %supervisor-message-handler-box))

(define (supervisor-preserved-messages sup)
  (if (not (supervisor-context? sup))
      (error "supervisor-preserved-messages: expected <supervisor-context> (CWE-843)" sup)
      (atomic-ref (%supervisor-preserved-inbox-box sup))))

(define supervisor-take-preserved-message!
  (case-lambda
    ((sup) (supervisor-take-preserved-message! sup #f))
    ((sup empty-default)
     (if (not (supervisor-context? sup))
         (error "supervisor-take-preserved-message!: expected <supervisor-context> (CWE-843)" sup)
         (let ((pbox (%supervisor-preserved-inbox-box sup)))
           (let retry ()
             (let ((cur (atomic-ref pbox)))
               (if (null? cur)
                   empty-default
                   (let ((head (car cur))
                         (tail (cdr cur)))
                     (if (atomic-cas! pbox cur tail)
                         head
                         (retry)))))))))))

(define (supervisor-clear-preserved-messages! sup)
  (if (not (supervisor-context? sup))
      (error "supervisor-clear-preserved-messages!: expected <supervisor-context> (CWE-843)" sup)
      (let ((pbox (%supervisor-preserved-inbox-box sup)))
        (let retry ()
          (let ((cur (atomic-ref pbox)))
            (if (atomic-cas! pbox cur '())
                #t
                (retry)))))))

(define (supervisor-message-handler sup)
  (if (not (supervisor-context? sup))
      (error "supervisor-message-handler: expected <supervisor-context> (CWE-843)" sup)
      (atomic-ref (%supervisor-message-handler-box sup))))

(define (supervisor-set-message-handler! sup handler)
  (if (not (supervisor-context? sup))
      (error "supervisor-set-message-handler!: expected <supervisor-context> (CWE-843)" sup)
      (if (and handler (not (procedure? handler)))
          (error "supervisor-set-message-handler!: handler must be a procedure or #f (CWE-843)" handler)
          (begin
            (atomic-set! (%supervisor-message-handler-box sup) handler)
            handler))))

(define supervisor-children
  (case-lambda
    ((sup)
     (if (not (supervisor-context? sup))
         (error "supervisor-children: expected <supervisor-context> (CWE-843)" sup)
         (atomic-ref (%supervisor-children-box sup))))))

(define supervisor-restart-history
  (case-lambda
    ((sup)
     (if (not (supervisor-context? sup))
         (error "supervisor-restart-history: expected <supervisor-context> (CWE-843)" sup)
         (atomic-ref (%supervisor-restart-history-box sup))))))

(define supervisor-state
  (case-lambda
    ((sup)
     (if (not (supervisor-context? sup))
         (error "supervisor-state: expected <supervisor-context> (CWE-843)" sup)
         (atomic-ref (%supervisor-state-box sup))))))

(define supervisor-scheduler
  (case-lambda
    ((sup)
     (if (not (supervisor-context? sup))
         (error "supervisor-scheduler: expected <supervisor-context> (CWE-843)" sup)
         (atomic-ref (%supervisor-scheduler-box sup))))))

(define supervisor-set-scheduler!
  (case-lambda
    ((sup sched)
     (if (not (supervisor-context? sup))
         (error "supervisor-set-scheduler!: expected <supervisor-context> (CWE-843)" sup)
         (begin
           (atomic-set! (%supervisor-scheduler-box sup) sched)
           sched)))))

(define (%supervisor-enqueue-child! sup child-entry)
  (let ((sched (supervisor-scheduler sup)))
    (if sched
        (let ((ctask (if (pair? child-entry) (cadr child-entry) child-entry)))
          (if (and ctask (task-context? ctask))
              (let ((hook (vector-ref *supervisor-scheduler-spawn-hook-box* 0)))
                (if (procedure? hook)
                    (hook sched ctask)
                    #f))
              #f))
        #f)))

;; -----------------------------------------------------------------------
;; 3. Child Task Spawning & Monitoring Helpers
;; -----------------------------------------------------------------------

(define (%spawn-and-monitor-child! sup-task cspec)
  (let* ((proc (child-spec-start-thunk cspec))
         (args (child-spec-init-args cspec))
         (child-task (if (or (not (list? args)) (null? args))
                         (proc)
                         (apply proc (channel-deep-copy args)))))
    (if (not (task-context? child-task))
        (error "spawn-child: start-thunk must return <task-context> (CWE-843)" child-task)
        (begin
          ;; Assign fresh Ephemeral Bump Arena if not present
          (if (not (task-arena child-task))
              (task-set-arena! child-task (make-task-arena 4096)))
          ;; Establish unidirectional monitor from supervisor to child
          (let ((mref (task-monitor sup-task child-task)))
            ;; Rebind child-spec id in registry if registry hook is available (Issue #669)
            (guard (exn (else #f))
              (let ((id (child-spec-id cspec)))
                (if (symbol? id)
                    ((vector-ref *supervisor-registry-rebind-box* 0) id child-task)
                    #f)))
            (list cspec child-task mref))))))

(define (%stop-child-instance! sup-task child-entry)
  (let* ((cspec (car child-entry))
         (ctask (cadr child-entry))
         (mref (caddr child-entry))
         (shutdown-strat (child-spec-shutdown-strategy cspec)))
    (if (and ctask (task-context? ctask))
        (begin
          ;; Demonitor first to prevent duplicate down handling
          (if (and sup-task (task-context? sup-task))
              (task-demonitor sup-task mref))
          (cond
            ((or (eq? shutdown-strat 'brutal_kill)
                 (eq? (task-state ctask) 'terminated))
             ;; Immediate O(1) Ephemeral Arena Reset, channel drop & cascade cleanup
             (synapse-cleanup-task-resources! ctask 'supervisor_shutdown #f #f)
             #t)
            ((and (integer? shutdown-strat) (> shutdown-strat 0))
             ;; Graceful shutdown with timeout (Issue #729, Item C6):
             ;; Deliver 'shutdown EXIT signal and wait up to shutdown-strat ms via channel-recv-timeout!
             (let* ((ack-ch (make-channel 1))
                    (obs-dummy (make-task-context))
                    (sref (task-monitor obs-dummy ctask ack-ch)))
               (task-set-handoff! ctask (list 'EXIT (if (task-context? sup-task) (task-tid sup-task) 0) 'shutdown))
               (task-wake! ctask #f)
               (if (and (eq? (task-state ctask) 'ready)
                        (procedure? (task-next-run ctask)))
                   (with-synapse-task-boundary ctask (task-next-run ctask))
                   #f)
               (let ((wait-res (channel-recv-timeout! ack-ch shutdown-strat)))
                 (task-demonitor obs-dummy sref)
                 (if (not (eq? (task-state ctask) 'terminated))
                     (synapse-cleanup-task-resources! ctask 'killed_after_shutdown_timeout #f #f)
                     (synapse-cleanup-task-resources! ctask 'shutdown #f #f))
                 #t)))
            (else
             (synapse-cleanup-task-resources! ctask 'supervisor_shutdown #f #f)
             #t)))
        #f)))

;; -----------------------------------------------------------------------
;; 4. Sliding Time-Window Crash Loop / Flapping Detector (CWE-400)
;; -----------------------------------------------------------------------

(define (%record-restart-and-check-limit! sup)
  (let* ((spec (supervisor-spec sup))
         (max-restarts (supervisor-spec-max-restarts spec))
         (max-time (supervisor-spec-max-time spec))
         (now (allocate-supervisor-timestamp!))
         (cutoff (- now max-time))
         (hist-box (%supervisor-restart-history-box sup)))
    (let retry ()
      (let* ((current-hist (atomic-ref hist-box))
             ;; Filter out timestamps older than cutoff window
             (filtered-hist (let filter-loop ((xs current-hist) (acc (list)))
                              (if (null? xs)
                                  acc
                                  (if (>= (car xs) cutoff)
                                      (filter-loop (cdr xs) (cons (car xs) acc))
                                      (filter-loop (cdr xs) acc)))))
             (new-hist (cons now filtered-hist)))
        (if (not (atomic-cas! hist-box current-hist new-hist))
            (retry)
            ;; Check if restarts exceed maximum allowed within window
            (if (> (length new-hist) max-restarts)
                #f ; Limit exceeded! Crash loop detected
                #t)))))) ; Within safe limits

;; -----------------------------------------------------------------------
;; 5. Supervisor Factory & Initialization
;; -----------------------------------------------------------------------

;; Active supervisor registry keyed by supervisor <task-context> for automatic
;; DOWN signal -> supervisor-handle-child-down! dispatch (Issue #727, Item C7)
(define *active-supervisors-by-task-box* (make-atomic-box '()))

(define (%register-active-supervisor! sup-task sup)
  (let retry ()
    (let* ((cur (atomic-ref *active-supervisors-by-task-box*))
           (filtered (let rem ((xs cur))
                       (cond ((null? xs) '())
                             ((eq? (caar xs) sup-task) (rem (cdr xs)))
                             (else (cons (car xs) (rem (cdr xs))))))))
      (if (atomic-cas! *active-supervisors-by-task-box* cur (cons (cons sup-task sup) filtered))
          #t
          (retry)))))

(define (%unregister-active-supervisor! sup-task)
  (let retry ()
    (let* ((cur (atomic-ref *active-supervisors-by-task-box*))
           (filtered (let rem ((xs cur))
                       (cond ((null? xs) '())
                             ((eq? (caar xs) sup-task) (rem (cdr xs)))
                             (else (cons (car xs) (rem (cdr xs))))))))
      (if (atomic-cas! *active-supervisors-by-task-box* cur filtered)
          #t
          (retry)))))

(define (%lookup-active-supervisor-by-task obs-task)
  (let loop ((xs (atomic-ref *active-supervisors-by-task-box*)))
    (cond
      ((null? xs) #f)
      ((eq? (caar xs) obs-task) (cdar xs))
      (else (loop (cdr xs))))))

(define make-supervisor
  (case-lambda
    ((spec)
     (make-supervisor spec #f #f))
    ((spec parent-or-sched)
     (if (and parent-or-sched (not (supervisor-context? parent-or-sched)))
         (make-supervisor spec #f parent-or-sched)
         (make-supervisor spec parent-or-sched #f)))
    ((spec parent-sup sched)
     (if (not (supervisor-spec? spec))
         (error "make-supervisor: expected <supervisor-spec> (CWE-843)" spec)
         (let* ((sup-task (make-task-context))
                (sup (%make-supervisor-context spec
                                               sup-task
                                               (make-atomic-box (list))
                                               (make-atomic-box (list))
                                               parent-sup
                                               (make-atomic-box 'stopped)
                                               (make-atomic-box sched)
                                               (make-atomic-box #f)
                                               (make-atomic-box (list))
                                               (make-atomic-box #f))))
           ;; Mark sup-task as a resident actor task (Issue #788)
           (task-resident-set! sup-task #t)
           ;; Configure sup-task as an executable task whose loop drains DOWN signals (Issue #727, Item C7, #743)
           (task-next-run-set!
            sup-task
            (lambda ()
              (let ((res (supervisor-poll-down-signals! sup)))
                (if (and (eq? (supervisor-state sup) 'running)
                         (task-has-handoff? sup-task))
                    (task-state-set! sup-task 'ready))
                res)))
           sup)))))

(define supervisor-start!
  (case-lambda
    ((sup)
     (supervisor-start! sup #f #f))
    ((sup sched-or-spawn)
     (if (boolean? sched-or-spawn)
         (supervisor-start! sup #f sched-or-spawn)
         (supervisor-start! sup sched-or-spawn #f)))
    ((sup sched spawn-initial?)
     (if (not (supervisor-context? sup))
         (error "supervisor-start!: expected <supervisor-context> (CWE-843)" sup)
         (begin
           (if sched (supervisor-set-scheduler! sup sched))
           (let* ((spec (supervisor-spec sup))
                  (sup-task (supervisor-task sup))
                  (cspecs (supervisor-spec-child-specs spec)))
             (atomic-set! (%supervisor-state-box sup) 'running)
             (%register-active-supervisor! sup-task sup)
             (let ((children (let loop ((specs cspecs) (acc (list)))
                               (if (null? specs)
                                   acc
                                   (let ((child-inst (%spawn-and-monitor-child! sup-task (car specs))))
                                     (loop (cdr specs) (cons child-inst acc)))))))
               (let ((rev-children (reverse children)))
                 (atomic-set! (%supervisor-children-box sup) rev-children)
                 (if (and spawn-initial? (supervisor-scheduler sup))
                     (let spawn-loop ((xs rev-children))
                       (if (not (null? xs))
                           (begin
                             (%supervisor-enqueue-child! sup (car xs))
                             (spawn-loop (cdr xs))))))
                 #t))))))))

(define supervisor-stop!
  (case-lambda
    ((sup)
     (if (not (supervisor-context? sup))
         (error "supervisor-stop!: expected <supervisor-context> (CWE-843)" sup)
         (let ((sup-task (supervisor-task sup)))
           (task-resident-set! sup-task #f)
           (atomic-set! (%supervisor-state-box sup) 'stopping)
           (%unregister-active-supervisor! sup-task)
           (let ((children (atomic-swap! (%supervisor-children-box sup) (list))))
             ;; Stop children in reverse order
             (let loop ((cs (reverse children)))
               (if (null? cs)
                   #t
                   (begin
                     (%stop-child-instance! sup-task (car cs))
                     (loop (cdr cs))))))
           (task-exit! sup-task 'normal)
           (atomic-set! (%supervisor-state-box sup) 'stopped)
           #t)))))

;; -----------------------------------------------------------------------
;; 6. 3 Core Restart Strategies: one_for_one, one_for_all, rest_for_one
;; -----------------------------------------------------------------------

(define (%restart-one-for-one! sup dead-entry)
  (let* ((sup-task (supervisor-task sup))
         (cspec (car dead-entry))
         (old-task (cadr dead-entry))
         (new-entry (%spawn-and-monitor-child! sup-task cspec))
         (ch-box (%supervisor-children-box sup)))
    (let retry ()
      (let* ((cur (atomic-ref ch-box))
             (new-list (let map-loop ((xs cur))
                         (if (null? xs)
                             (list)
                             (if (eq? (car xs) dead-entry)
                                 (cons new-entry (cdr xs))
                                 (cons (car xs) (map-loop (cdr xs))))))))
        (if (atomic-cas! ch-box cur new-list)
            (begin
              (%supervisor-enqueue-child! sup new-entry)
              new-entry)
            (retry))))))

(define (%restart-one-for-all! sup)
  (let* ((spec (supervisor-spec sup))
         (sup-task (supervisor-task sup))
         (cspecs (supervisor-spec-child-specs spec))
         (ch-box (%supervisor-children-box sup)))
    ;; 1. Stop all current children in reverse order
    (let ((current (atomic-swap! ch-box (list))))
      (let stop-loop ((cs (reverse current)))
        (if (not (null? cs))
            (begin
              (%stop-child-instance! sup-task (car cs))
              (stop-loop (cdr cs))))))
    ;; 2. Re-spawn all specs from beginning
    (let ((restarted (let spawn-loop ((specs cspecs) (acc (list)))
                       (if (null? specs)
                           acc
                           (let ((entry (%spawn-and-monitor-child! sup-task (car specs))))
                             (spawn-loop (cdr specs) (cons entry acc)))))))
      (let ((final-list (reverse restarted)))
        (atomic-set! ch-box final-list)
        (let enqueue-loop ((xs final-list))
          (if (not (null? xs))
              (begin
                (%supervisor-enqueue-child! sup (car xs))
                (enqueue-loop (cdr xs)))))
        final-list))))

(define (%restart-rest-for-one! sup dead-entry)
  (let* ((sup-task (supervisor-task sup))
         (ch-box (%supervisor-children-box sup)))
    (let retry ()
      (let* ((current (atomic-ref ch-box))
             ;; Split into (prefix-untouched, suffix-to-restart)
             (pair (let split-loop ((xs current) (prefix (list)))
                     (if (null? xs)
                         (cons (reverse prefix) (list))
                         (if (eq? (car xs) dead-entry)
                             (cons (reverse prefix) xs)
                             (split-loop (cdr xs) (cons (car xs) prefix))))))
             (prefix (car pair))
             (suffix (cdr pair)))
        ;; Stop suffix instances in reverse order
        (let stop-loop ((ss (reverse suffix)))
          (if (not (null? ss))
              (begin
                (%stop-child-instance! sup-task (car ss))
                (stop-loop (cdr ss)))))
        ;; Re-spawn suffix specs
        (let* ((restarted-suffix
                (let respawn-loop ((ss suffix) (acc (list)))
                  (if (null? ss)
                      acc
                      (let* ((cspec (caar ss))
                             (new-entry (%spawn-and-monitor-child! sup-task cspec)))
                        (respawn-loop (cdr ss) (cons new-entry acc))))))
               (rev-suffix (reverse restarted-suffix))
               (full-new-list (append prefix rev-suffix)))
          (if (atomic-cas! ch-box current full-new-list)
              (begin
                (let enqueue-loop ((xs rev-suffix))
                  (if (not (null? xs))
                      (begin
                        (%supervisor-enqueue-child! sup (car xs))
                        (enqueue-loop (cdr xs)))))
                restarted-suffix)
              (retry)))))))

;; -----------------------------------------------------------------------
;; 7. Down Signal Dispatcher & Escalation
;; -----------------------------------------------------------------------

(define supervisor-handle-child-down!
  (case-lambda
    ((sup target-tid reason)
     (if (not (supervisor-context? sup))
         (error "supervisor-handle-child-down!: expected <supervisor-context> (CWE-843)" sup)
         (let* ((children (atomic-ref (%supervisor-children-box sup)))
                (entry (let find-loop ((xs children))
                         (if (null? xs)
                             #f
                             (if (= (task-tid (cadar xs)) target-tid)
                                 (car xs)
                                 (find-loop (cdr xs)))))))
           (if (not entry)
               #f ; Unknown child or already terminated
               (let* ((cspec (car entry))
                      (rtype (child-spec-restart-type cspec))
                      (is-abnormal (not (eq? reason 'normal)))
                      (should-restart
                       (cond
                         ((eq? rtype 'permanent) #t)
                         ((eq? rtype 'transient) is-abnormal)
                         ((eq? rtype 'temporary) #f)
                         (else #f))))
                 (if is-abnormal
                     (let ((hook (vector-ref *supervisor-crash-logger-hook-box* 0)))
                       (if (procedure? hook)
                           (hook target-tid reason (child-spec-id cspec))
                           #f))
                     #f)
                 (if (not should-restart)
                     ;; For non-restarted child, remove from active children list
                     (let ((sup-task (supervisor-task sup)))
                       (%stop-child-instance! sup-task entry)
                       (let ((ch-box (%supervisor-children-box sup)))
                         (let retry ()
                           (let* ((cur (atomic-ref ch-box))
                                  (new-cur (let rem ((xs cur))
                                             (if (null? xs)
                                                 (list)
                                                 (if (eq? (car xs) entry)
                                                     (cdr xs)
                                                     (cons (car xs) (rem (cdr xs))))))))
                             (if (not (atomic-cas! ch-box cur new-cur))
                                 (retry)
                                 'child_removed)))))
                     ;; Check restart frequency threshold
                     (if (not (%record-restart-and-check-limit! sup))
                         ;; CWE-400 Mitigation: Crash Loop detected! Stop all and escalate
                         (begin
                           (supervisor-stop! sup)
                           (let ((parent (supervisor-parent sup)))
                             (if (and parent (supervisor-context? parent))
                                 (supervisor-handle-child-down! parent
                                                               (task-tid (supervisor-task sup))
                                                               '(shutdown_max_restarts_reached))
                                 (synapse-panic! 'shutdown_max_restarts_reached (child-spec-id cspec)))))
                         ;; Execute restart according to strategy
                         (let ((strat (supervisor-spec-strategy (supervisor-spec sup))))
                           (cond
                             ((eq? strat 'one_for_one)
                              (%restart-one-for-one! sup entry))
                             ((eq? strat 'one_for_all)
                              (%restart-one-for-all! sup))
                             ((eq? strat 'rest_for_one)
                              (%restart-rest-for-one! sup entry))
                             (else
                              (error "supervisor-handle-child-down!: unknown strategy" strat)))))))))))))

(define supervisor-child-task
  (case-lambda
    ((sup child-id)
     (if (not (supervisor-context? sup))
         (error "supervisor-child-task: expected <supervisor-context> (CWE-843)" sup)
         (let ((children (atomic-ref (%supervisor-children-box sup))))
           (let find-loop ((xs children))
             (if (null? xs)
                 #f
                 (if (eq? (child-spec-id (caar xs)) child-id)
                     (cadar xs)
                     (find-loop (cdr xs))))))))))

(define (%supervisor-preserve-message! sup msg)
  (let ((pbox (%supervisor-preserved-inbox-box sup)))
    (let retry ()
      (let* ((cur (atomic-ref pbox))
             (next (append cur (list msg))))
        (if (atomic-cas! pbox cur next)
            #t
            (retry))))))

(define supervisor-poll-down-signals!
  (case-lambda
    ((sup)
     (if (not (supervisor-context? sup))
         (error "supervisor-poll-down-signals!: expected <supervisor-context> (CWE-843)" sup)
         (let ((proc-box (%supervisor-processing-box sup))
               (sup-task (supervisor-task sup)))
           ;; Lock-Free Actor MPSC Work-Draining Loop (Issue #743, Item C7)
           ;; Guarantees strict serialization of supervisor state updates across concurrent workers
           (if (not (atomic-cas! proc-box #f #t))
               #f ; Another worker is actively draining the supervisor mailbox
               (let outer-loop ((last-res #f))
                 (let drain-loop ((res last-res))
                   (if (not (task-has-handoff? sup-task))
                       (begin
                         (atomic-set! proc-box #f)
                         ;; Check once more before releasing lock to prevent lost-wake race
                         (if (task-has-handoff? sup-task)
                             (if (atomic-cas! proc-box #f #t)
                                 (outer-loop res)
                                 res)
                             res))
                       (let ((msg (task-take-handoff! sup-task)))
                         (cond
                           ;; 1. DOWN notification: (DOWN ref subject target-tid reason)
                           ((and (pair? msg) (eq? (car msg) 'DOWN) (>= (length msg) 5))
                            (let* ((target-tid (list-ref msg 3))
                                   (reason (list-ref msg 4))
                                   (h-res (supervisor-handle-child-down! sup target-tid reason)))
                              (drain-loop h-res)))

                           ;; 2. EXIT signal: (EXIT from-tid reason) - Erlang/OTP link crash signal (Issue #751)
                           ((and (pair? msg) (eq? (car msg) 'EXIT) (>= (length msg) 3))
                            (let* ((from-tid (cadr msg))
                                   (reason (caddr msg))
                                   ;; Check if from-tid is an active child of this supervisor
                                   (is-child (let check-child ((xs (atomic-ref (%supervisor-children-box sup))))
                                               (cond
                                                 ((null? xs) #f)
                                                 ((and (pair? (car xs))
                                                       (pair? (cdar xs))
                                                       (task-context? (cadar xs))
                                                       (= (task-tid (cadar xs)) from-tid))
                                                  #t)
                                                 (else (check-child (cdr xs)))))))
                              (if is-child
                                  ;; Child died via EXIT signal: trigger supervisor restart!
                                  (let ((h-res (supervisor-handle-child-down! sup from-tid reason)))
                                    (drain-loop h-res))
                                  ;; Not a managed child: dispatch to custom handler or preserve
                                  (let* ((handler (atomic-ref (%supervisor-message-handler-box sup)))
                                         (handled? (if (procedure? handler) (handler sup msg) #f)))
                                    (if (not handled?)
                                        (%supervisor-preserve-message! sup msg))
                                    (drain-loop res)))))

                           ;; 3. Non-DOWN/EXIT messages (io_complete, control RPCs, custom tuples) (Issue #751)
                           (else
                            (let* ((handler (atomic-ref (%supervisor-message-handler-box sup)))
                                   (handled? (if (procedure? handler) (handler sup msg) #f)))
                              (if (not handled?)
                                  (%supervisor-preserve-message! sup msg))
                              (drain-loop res))))))))))))))

;; Connect monitor DOWN notifications to active supervisor tasks automatically (Issue #727, Item C7, #743)
(guard (exn (else #f))
  (if (procedure? set-monitor-down-dispatch-hook!)
      (set-monitor-down-dispatch-hook!
       (lambda (obs-task)
         (let ((sup (%lookup-active-supervisor-by-task obs-task)))
           (if (and sup (eq? (supervisor-state sup) 'running))
               (let ((sched (supervisor-scheduler sup)))
                 (if (and sched (procedure? scheduler-spawn!) (scheduler-running? sched))
                     ;; Actor mode: wake up supervisor task and enqueue to scheduler
                     (begin
                       (task-state-set! obs-task 'ready)
                       (%supervisor-enqueue-child! sup obs-task))
                     ;; Direct fallback mode (e.g. single-threaded tests): drain via serialized Work-Draining loop
                     (let ((runner (task-next-run obs-task)))
                       (if (procedure? runner)
                           (runner)
                           (supervisor-poll-down-signals! sup)))))
               #f))))))
