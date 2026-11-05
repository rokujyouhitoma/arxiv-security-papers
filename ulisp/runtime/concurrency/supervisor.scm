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
  (%make-supervisor-context spec sup-task children-box restart-history-box parent-sup state-box)
  supervisor-context?
  (spec                 supervisor-spec)
  (sup-task             supervisor-task)
  (children-box         %supervisor-children-box)
  (restart-history-box  %supervisor-restart-history-box)
  (parent-sup           supervisor-parent)
  (state-box            %supervisor-state-box))

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
     (make-supervisor spec #f))
    ((spec parent-sup)
     (if (not (supervisor-spec? spec))
         (error "make-supervisor: expected <supervisor-spec> (CWE-843)" spec)
         (let* ((sup-task (make-task-context))
                (sup (%make-supervisor-context spec
                                               sup-task
                                               (make-atomic-box (list))
                                               (make-atomic-box (list))
                                               parent-sup
                                               (make-atomic-box 'stopped))))
           ;; Configure sup-task as an executable task whose loop drains DOWN signals (Issue #727, Item C7)
           (task-next-run-set!
            sup-task
            (lambda ()
              (let ((res (supervisor-poll-down-signals! sup)))
                (if (eq? (supervisor-state sup) 'running)
                    (task-state-set! sup-task 'ready))
                res)))
           sup)))))

(define supervisor-start!
  (case-lambda
    ((sup)
     (if (not (supervisor-context? sup))
         (error "supervisor-start!: expected <supervisor-context> (CWE-843)" sup)
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
             (atomic-set! (%supervisor-children-box sup) (reverse children))
             #t))))))

(define supervisor-stop!
  (case-lambda
    ((sup)
     (if (not (supervisor-context? sup))
         (error "supervisor-stop!: expected <supervisor-context> (CWE-843)" sup)
         (let ((sup-task (supervisor-task sup)))
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
            new-entry
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
      (atomic-set! ch-box (reverse restarted))
      (reverse restarted))))

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
               (full-new-list (append prefix (reverse restarted-suffix))))
          (if (atomic-cas! ch-box current full-new-list)
              restarted-suffix
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

(define supervisor-poll-down-signals!
  (case-lambda
    ((sup)
     (if (not (supervisor-context? sup))
         (error "supervisor-poll-down-signals!: expected <supervisor-context> (CWE-843)" sup)
         (let ((sup-task (supervisor-task sup)))
           (let drain ((last-res #f))
             (if (not (task-has-handoff? sup-task))
                 last-res
                 (let ((msg (task-take-handoff! sup-task)))
                   (if (and (pair? msg) (eq? (car msg) 'DOWN) (>= (length msg) 5))
                       (let* ((target-tid (list-ref msg 3))
                              (reason (list-ref msg 4))
                              (res (supervisor-handle-child-down! sup target-tid reason)))
                         (drain res))
                       (drain last-res))))))))))

;; Connect monitor DOWN notifications to active supervisor tasks automatically (Issue #727, Item C7)
(guard (exn (else #f))
  (if (procedure? set-monitor-down-dispatch-hook!)
      (set-monitor-down-dispatch-hook!
       (lambda (obs-task)
         (let ((sup (%lookup-active-supervisor-by-task obs-task)))
           (if (and sup (eq? (supervisor-state sup) 'running))
               (let ((runner (task-next-run obs-task)))
                 (if (procedure? runner)
                     (runner)
                     (supervisor-poll-down-signals! sup)))
               #f))))))
