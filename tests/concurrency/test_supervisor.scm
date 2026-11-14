;;; =======================================================================
;;; ULisp Concurrency Test: Erlang/OTP Supervision Tree (#667)
;;; Conforms to DSN-37 Section 8.4.3 & 14.8 Task 6.2
;;; =======================================================================

(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/arena.scm")
(load "ulisp/runtime/concurrency/queue.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/links.scm")
(load "ulisp/runtime/concurrency/panic.scm")
(load "ulisp/runtime/concurrency/supervisor.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")

;; -----------------------------------------------------------------------
;; Minimal Test Harness (Vector Boxes)
;; -----------------------------------------------------------------------

(test-begin "concurrency-supervisor")

(define-syntax assert-true
  (syntax-rules ()
    ((assert-true val msg)
     (test-assert msg val))
    ((assert-true val)
     (test-assert "assert-true" val))))

(define-syntax assert-false
  (syntax-rules ()
    ((assert-false val msg)
     (test-assert msg (not val)))
    ((assert-false val)
     (test-assert "assert-false" (not val)))))

(define-syntax assert-eq
  (syntax-rules ()
    ((assert-eq actual expected msg)
     (test-equal msg expected actual))))

(define-syntax assert-equal
  (syntax-rules ()
    ((assert-equal actual expected msg)
     (test-equal msg expected actual))))

(define-syntax assert-error
  (syntax-rules ()
    ((assert-error thunk msg)
     (let ((caught
            (guard (exn (#t #t))
              (thunk)
              #f)))
       (test-assert msg caught)))))
;; -----------------------------------------------------------------------
;; Test Suite Execution
;; -----------------------------------------------------------------------

;; -----------------------------------------------------------------------
;; Group 1: one_for_one Restart Strategy
;; -----------------------------------------------------------------------
(write-string "--- Group 1: one_for_one Restart Strategy ---\n")
(flush-output-port)

(let* ((w1-spec (make-child-spec 'w1 (lambda () (make-task-context))))
       (w2-spec (make-child-spec 'w2 (lambda () (make-task-context))))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list w1-spec w2-spec)))
       (sup (make-supervisor sup-spec)))
  (assert-true (supervisor-context? sup) "supervisor created")
  (assert-eq (supervisor-state sup) 'stopped "initial state is 'stopped")

  ;; Start supervisor
  (supervisor-start! sup)
  (assert-eq (supervisor-state sup) 'running "supervisor is running")
  (assert-equal (length (supervisor-children sup)) 2 "supervisor has 2 children")

  (let* ((t1-initial (supervisor-child-task sup 'w1))
         (t2-initial (supervisor-child-task sup 'w2))
         (tid1-init (task-tid t1-initial))
         (tid2-init (task-tid t2-initial)))
    (assert-true (task-context? t1-initial) "w1 task running")
    (assert-true (task-context? t2-initial) "w2 task running")

    ;; Simulate w1 abnormal death
    (supervisor-handle-child-down! sup tid1-init '(panic . worker_fault))

    (let* ((t1-after (supervisor-child-task sup 'w1))
           (t2-after (supervisor-child-task sup 'w2))
           (tid1-after (task-tid t1-after))
           (tid2-after (task-tid t2-after)))
      ;; w1 must be restarted with a new Task ID
      (assert-true (not (= tid1-init tid1-after)) "w1 restarted with new TID")
      ;; w2 must NOT be restarted; same TID
      (assert-eq tid2-init tid2-after "w2 untouched with identical TID")
      (assert-eq t2-initial t2-after "w2 task identity preserved"))

    (supervisor-stop! sup)
    (assert-eq (supervisor-state sup) 'stopped "supervisor stopped")))

;; -----------------------------------------------------------------------
;; Group 2: one_for_all Restart Strategy (CWE-662 State Consistency)
;; -----------------------------------------------------------------------
(write-string "--- Group 2: one_for_all Restart Strategy ---\n")
(flush-output-port)

(let* ((s1-spec (make-child-spec 'stage1 (lambda () (make-task-context))))
       (s2-spec (make-child-spec 'stage2 (lambda () (make-task-context))))
       (sup-spec (make-supervisor-spec 'one_for_all 5 1000 (list s1-spec s2-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)

  (let* ((s1-init (supervisor-child-task sup 'stage1))
         (s2-init (supervisor-child-task sup 'stage2))
         (tid1-init (task-tid s1-init))
         (tid2-init (task-tid s2-init)))

    ;; Simulate stage2 death
    (supervisor-handle-child-down! sup tid2-init '(panic . pipeline_error))

    (let* ((s1-after (supervisor-child-task sup 'stage1))
           (s2-after (supervisor-child-task sup 'stage2))
           (tid1-after (task-tid s1-after))
           (tid2-after (task-tid s2-after)))
      ;; In one_for_all, BOTH stage1 and stage2 must be restarted!
      (assert-true (not (= tid1-init tid1-after)) "stage1 restarted in one_for_all")
      (assert-true (not (= tid2-init tid2-after)) "stage2 restarted in one_for_all")
      (assert-true (not (eq? s1-init s1-after)) "stage1 has fresh task context")
      (assert-true (not (eq? s2-init s2-after)) "stage2 has fresh task context"))

    (supervisor-stop! sup)))

;; -----------------------------------------------------------------------
;; Group 3: rest_for_one Restart Strategy
;; -----------------------------------------------------------------------
(write-string "--- Group 3: rest_for_one Restart Strategy ---\n")
(flush-output-port)

(let* ((a-spec (make-child-spec 'stepA (lambda () (make-task-context))))
       (b-spec (make-child-spec 'stepB (lambda () (make-task-context))))
       (c-spec (make-child-spec 'stepC (lambda () (make-task-context))))
       (sup-spec (make-supervisor-spec 'rest_for_one 5 1000 (list a-spec b-spec c-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)

  (let* ((a-init (supervisor-child-task sup 'stepA))
         (b-init (supervisor-child-task sup 'stepB))
         (c-init (supervisor-child-task sup 'stepC))
         (tidA-init (task-tid a-init))
         (tidB-init (task-tid b-init))
         (tidC-init (task-tid c-init)))

    ;; Simulate stepB death
    (supervisor-handle-child-down! sup tidB-init '(panic . stepB_fail))

    (let* ((a-after (supervisor-child-task sup 'stepA))
           (b-after (supervisor-child-task sup 'stepB))
           (c-after (supervisor-child-task sup 'stepC))
           (tidA-after (task-tid a-after))
           (tidB-after (task-tid b-after))
           (tidC-after (task-tid c-after)))
      ;; Prior stepA must remain alive
      (assert-eq tidA-init tidA-after "prior stepA untouched with identical TID")
      (assert-eq a-init a-after "prior stepA identity preserved")
      ;; Dead stepB and posterior stepC must both be restarted!
      (assert-true (not (= tidB-init tidB-after)) "dead stepB restarted with new TID")
      (assert-true (not (= tidC-init tidC-after)) "posterior stepC restarted with new TID"))

    (supervisor-stop! sup)))

;; -----------------------------------------------------------------------
;; Group 4: Restart Types (permanent, transient, temporary)
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Restart Types Behavior ---\n")
(flush-output-port)

;; 4.1 Transient: no restart on normal exit
(let* ((tr-spec (make-child-spec 'worker_transient (lambda () (make-task-context)) 'transient))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list tr-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)
  (let ((t-init (supervisor-child-task sup 'worker_transient)))
    ;; Normal termination: must NOT restart
    (supervisor-handle-child-down! sup (task-tid t-init) 'normal)
    (assert-eq (supervisor-child-task sup 'worker_transient) #f "transient worker removed on normal exit")
    (assert-equal (length (supervisor-children sup)) 0 "children list empty"))
  (supervisor-stop! sup))

;; 4.2 Transient: restarted on abnormal panic
(let* ((tr-spec (make-child-spec 'worker_transient2 (lambda () (make-task-context)) 'transient))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list tr-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)
  (let* ((t-init (supervisor-child-task sup 'worker_transient2))
         (tid-init (task-tid t-init)))
    ;; Panic termination: must restart
    (supervisor-handle-child-down! sup tid-init '(panic . crashed))
    (let ((t-after (supervisor-child-task sup 'worker_transient2)))
      (assert-true (task-context? t-after) "transient worker restarted on panic")
      (assert-true (not (= tid-init (task-tid t-after))) "new TID assigned"))
    (supervisor-stop! sup)))

;; 4.3 Temporary: never restarted even on panic
(let* ((tmp-spec (make-child-spec 'worker_temp (lambda () (make-task-context)) 'temporary))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list tmp-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)
  (let ((t-init (supervisor-child-task sup 'worker_temp)))
    (supervisor-handle-child-down! sup (task-tid t-init) '(panic . exploded))
    (assert-eq (supervisor-child-task sup 'worker_temp) #f "temporary worker never restarted")
    (supervisor-stop! sup)))

;; 4.4 Permanent: restarted on normal exit (#741)
(let* ((perm-spec (make-child-spec 'worker_perm (lambda () (make-task-context)) 'permanent))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list perm-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)
  (let* ((t-init (supervisor-child-task sup 'worker_perm))
         (tid-init (task-tid t-init)))
    ;; Normal termination: permanent child MUST restart!
    (supervisor-handle-child-down! sup tid-init 'normal)
    (let ((t-after (supervisor-child-task sup 'worker_perm)))
      (assert-true (task-context? t-after) "permanent worker restarted on normal exit (#741)")
      (assert-true (not (= tid-init (task-tid t-after))) "new TID assigned for permanent child"))
    (supervisor-stop! sup)))

;; -----------------------------------------------------------------------
;; Group 5: Crash Loop / Flapping Escalation (CWE-400 DoS Mitigation)
;; -----------------------------------------------------------------------
(write-string "--- Group 5: Crash Loop / Flapping Escalation ---\n")
(flush-output-port)

(let* ((c-spec (make-child-spec 'flapping_worker (lambda () (make-task-context))))
       ;; Allow at most 2 restarts within time window of 500
       (sup-spec (make-supervisor-spec 'one_for_one 2 500 (list c-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)

  ;; 1st restart (allowed)
  (let ((t1 (supervisor-child-task sup 'flapping_worker)))
    (supervisor-handle-child-down! sup (task-tid t1) '(panic . crash1))
    (assert-eq (supervisor-state sup) 'running "supervisor running after 1st crash"))

  ;; 2nd restart (allowed, reaches limit 2)
  (let ((t2 (supervisor-child-task sup 'flapping_worker)))
    (supervisor-handle-child-down! sup (task-tid t2) '(panic . crash2))
    (assert-eq (supervisor-state sup) 'running "supervisor running after 2nd crash"))

  ;; 3rd restart: EXCEEDS limit 2! Must escalate and shutdown
  (let* ((t3 (supervisor-child-task sup 'flapping_worker))
         (res (with-synapse-task-boundary (supervisor-task sup)
                (lambda ()
                  (supervisor-handle-child-down! sup (task-tid t3) '(panic . crash3))))))
    (assert-true (pair? res) "escalation returns pair")
    (assert-eq (car res) 'panic "crash loop triggers escalation panic (CWE-400)")
    (assert-true (synapse-panic-record? (cdr res)) "payload is <synapse-panic-record>")
    (assert-eq (synapse-panic-reason (cdr res)) 'shutdown_max_restarts_reached "panic reason matches")
    (assert-eq (supervisor-state sup) 'stopped "supervisor stopped on crash loop")
    (assert-equal (length (supervisor-children sup)) 0 "children stopped on crash loop")))

;; -----------------------------------------------------------------------
;; Group 6: Security & Boundary Guards (CWE-843 Type Confusion)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Security Guards & Type Confusion (CWE-843) ---\n")
(flush-output-port)

(assert-true (guard (exn (else #t)) (make-child-spec "not-a-symbol" (lambda () 1)) #f)
             "make-child-spec rejects non-symbol id (CWE-843)")
(assert-true (guard (exn (else #t)) (make-child-spec 'w "not-a-procedure") #f)
             "make-child-spec rejects non-procedure thunk (CWE-843)")
(assert-true (guard (exn (else #t)) (make-child-spec 'w (lambda () 1) 'invalid_restart) #f)
             "make-child-spec rejects invalid restart-type (CWE-843)")
(assert-true (guard (exn (else #t)) (make-supervisor-spec 'invalid_strategy 5 1000 '()) #f)
             "make-supervisor-spec rejects invalid strategy (CWE-843)")
(assert-true (guard (exn (else #t)) (make-supervisor-spec 'one_for_one -1 1000 '()) #f)
             "make-supervisor-spec rejects negative max-restarts (CWE-843)")
(assert-true (guard (exn (else #t)) (supervisor-start! "not-a-supervisor") #f)
             "supervisor-start! rejects non-supervisor (CWE-843)")
(assert-true (guard (exn (else #t)) (supervisor-handle-child-down! "bad-sup" 1 'normal) #f)
             "supervisor-handle-child-down! rejects non-supervisor (CWE-843)")

;; -----------------------------------------------------------------------
;; Group 7: x86-64 Linux CI End-to-End Integration Test (#722)
;;   Child under supervisor runs (car '()) and crashes;
;;   unrelated concurrent tasks complete normally;
;;   supervisor automatically restarts crashed child.
;; -----------------------------------------------------------------------
(write-string "--- Group 7: Supervisor Fault Isolation & Auto-Restart CI Integration (#722) ---\n")
(flush-output-port)

(let* ((sched (make-work-stealing-scheduler 2 32))
       (child-boot-count (make-atomic-box 0))
       (child-recovered-box (make-atomic-box 0))
       (child-tids-box (make-atomic-box '()))
       (unrelated-sum-box (make-atomic-box 0))
       (crashy-spec
        (make-child-spec
         'crashy_worker
         (lambda ()
           (let* ((t (make-task-context))
                  (attempt (+ (atomic-fetch-add! child-boot-count 1) 1)))
             (let retry ()
               (let ((cur (atomic-ref child-tids-box)))
                 (if (not (atomic-cas! child-tids-box cur (cons (task-tid t) cur)))
                     (retry)
                     #t)))
             (task-next-run-set!
              t
              (lambda ()
                (if (= attempt 1)
                    ;; 1st boot: trigger fatal (car '()) pair-tag fault
                    (car '())
                    ;; 2nd boot (restarted): succeed normally
                    (atomic-set! child-recovered-box 777))))
             t))
         'transient))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list crashy-spec)))
       (sup (make-supervisor sup-spec #f sched)))
  (supervisor-start! sup)
  (let* ((t-child-1 (supervisor-child-task sup 'crashy_worker))
         (tid-1 (task-tid t-child-1))
         (unrelated-1 (make-task-context))
         (unrelated-2 (make-task-context)))
    (task-next-run-set! unrelated-1 (lambda () (atomic-fetch-add! unrelated-sum-box 100)))
    (task-next-run-set! unrelated-2 (lambda () (atomic-fetch-add! unrelated-sum-box 200)))

    ;; Spawn initial crashing child and two unrelated tasks on scheduler
    (scheduler-spawn! sched unrelated-1 0)
    (scheduler-spawn! sched t-child-1 0)
    (scheduler-spawn! sched unrelated-2 1)
    (scheduler-run! sched)

    ;; 1. Unrelated concurrent tasks must complete without being affected by (car '())
    (assert-equal (atomic-ref unrelated-sum-box) 300 "unrelated concurrent tasks completed normally (100+200=300)")
    ;; 2. Crashed child task transitioned to 'terminated
    (assert-eq (task-state t-child-1) 'terminated "1st child instance running (car '()) terminated cleanly")
    ;; 3. Supervisor automatically received DOWN, restarted child, and enqueued to scheduler (#727, #742)
    (assert-equal (atomic-ref child-boot-count) 2 "child booted exactly twice (initial crash + 1 restart)")
    (assert-equal (atomic-ref child-recovered-box) 777 "restarted child automatically enqueued and executed to completion (#742)")
    (let ((tids (atomic-ref child-tids-box)))
      (assert-equal (length tids) 2 "2 task instances generated in total")
      (assert-true (not (= (car tids) (cadr tids))) "restarted child assigned a fresh TID"))
    ;; 4. Clean exit: transient worker deregistered upon normal completion (#741)
    (assert-eq (supervisor-child-task sup 'crashy_worker) #f "transient worker cleanly removed after normal exit (#741)")
    (supervisor-stop! sup)
    (scheduler-stop! sched)))

;; -----------------------------------------------------------------------
;; Group 8: Automatic Child DOWN -> supervisor-handle-child-down! Dispatch (#727)
;; -----------------------------------------------------------------------
(write-string "--- Group 8: Automatic Child DOWN Dispatch (#727) ---\n")
(flush-output-port)

(let* ((w1-boots (make-atomic-box 0))
       (w2-boots (make-atomic-box 0))
       (w1-spec (make-child-spec 'auto_w1
                                 (lambda ()
                                   (atomic-fetch-add! w1-boots 1)
                                   (make-task-context))))
       (w2-spec (make-child-spec 'auto_w2
                                 (lambda ()
                                   (atomic-fetch-add! w2-boots 1)
                                   (make-task-context))))
       (sup-spec (make-supervisor-spec 'one_for_all 5 1000 (list w1-spec w2-spec)))
       (sup (make-supervisor sup-spec)))
  (assert-true (procedure? (task-next-run (supervisor-task sup)))
               "supervisor task has runnable task-next-run loop (#727)")
  (supervisor-start! sup)
  (assert-equal (atomic-ref w1-boots) 1 "auto_w1 booted once on start")
  (assert-equal (atomic-ref w2-boots) 1 "auto_w2 booted once on start")

  (let* ((c1-before (supervisor-child-task sup 'auto_w1))
         (c2-before (supervisor-child-task sup 'auto_w2))
         (tid1-before (task-tid c1-before))
         (tid2-before (task-tid c2-before)))
    ;; Crash c1 inside task boundary WITHOUT calling supervisor-handle-child-down! or supervisor-poll-down-signals!
    (with-synapse-task-boundary c1-before
      (lambda ()
        (synapse-panic! 'auto_child_crash "unhandled child failure")))

    ;; Supervisor must have automatically received DOWN via monitor and restarted both children (one_for_all)
    (let* ((c1-after (supervisor-child-task sup 'auto_w1))
           (c2-after (supervisor-child-task sup 'auto_w2)))
      (assert-equal (atomic-ref w1-boots) 2 "auto_w1 automatically restarted on DOWN")
      (assert-equal (atomic-ref w2-boots) 2 "auto_w2 automatically restarted on DOWN (one_for_all)")
      (assert-true (not (= tid1-before (task-tid c1-after))) "auto_w1 assigned new TID")
      (assert-true (not (= tid2-before (task-tid c2-after))) "auto_w2 assigned new TID")
      (assert-true (task-mailbox-empty? (supervisor-task sup)) "supervisor task mailbox drained after auto-dispatch")))
  (supervisor-stop! sup))

;; -----------------------------------------------------------------------
;; Group 9: Monotonic System Clock for Restart Frequency Window (#728)
;; -----------------------------------------------------------------------
(write-string "--- Group 9: Monotonic System Clock for Restart Frequency Window (#728) ---\n")
(flush-output-port)

(let* ((t0 (supervisor-clock-now))
       (t1 (allocate-supervisor-timestamp!))
       (t2 (allocate-supervisor-timestamp!)))
  (assert-true (> t0 0) "supervisor-clock-now returns positive OS monotonic milliseconds")
  (assert-true (<= (- t2 t1) 5) "allocate-supervisor-timestamp! uses real monotonic clock (not fake +10 counter)"))

;; Verify sliding window expiry using monotonic clock + time advance
(let* ((c-spec (make-child-spec 'window_worker (lambda () (make-task-context))))
       ;; Max 2 restarts within 500ms window
       (sup-spec (make-supervisor-spec 'one_for_one 2 500 (list c-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)
  ;; 2 restarts within the current 500ms monotonic window
  (supervisor-handle-child-down! sup (task-tid (supervisor-child-task sup 'window_worker)) '(panic . w_crash1))
  (supervisor-handle-child-down! sup (task-tid (supervisor-child-task sup 'window_worker)) '(panic . w_crash2))
  (assert-eq (supervisor-state sup) 'running "supervisor still running after 2 restarts in window")

  ;; Advance monotonic clock offset by 600ms (past the 500ms window)
  (supervisor-clock-advance! 600)

  ;; 3rd restart is now outside the prior 500ms window and MUST succeed without escalation!
  (supervisor-handle-child-down! sup (task-tid (supervisor-child-task sup 'window_worker)) '(panic . w_crash3))
  (assert-eq (supervisor-state sup) 'running "3rd restart after 600ms window expiry succeeds without crash-loop escalation")
  (assert-true (task-context? (supervisor-child-task sup 'window_worker)) "window_worker restarted and alive")
  (supervisor-stop! sup))

;; -----------------------------------------------------------------------
;; Group 10: Graceful Shutdown with channel-recv-timeout! (#729)
;; -----------------------------------------------------------------------
(write-string "--- Group 10: Graceful Shutdown with channel-recv-timeout! (#729) ---\n")
(flush-output-port)

;; 10.1 Cooperative child that exits gracefully on 'shutdown signal within timeout
(let* ((graceful-cleaned-up (make-atomic-box #f))
       (coop-spec
        (make-child-spec
         'coop_worker
         (lambda ()
           (let ((t (make-task-context)))
             (task-next-run-set!
              t
              (lambda ()
                (let ((sig (task-take-handoff! t)))
                  (if (and (pair? sig) (eq? (car sig) 'EXIT) (eq? (caddr sig) 'shutdown))
                      (begin
                        (atomic-set! graceful-cleaned-up #t)
                        (task-exit! t 'shutdown))))))
             t))
         'permanent
         50)) ; 50ms graceful shutdown timeout
       ( unresponsive-spec
         (make-child-spec
          'hung_worker
          (lambda () (make-task-context))
          'permanent
          15)) ; 15ms timeout before brutal kill
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list coop-spec unresponsive-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)
  (let ((coop-task (supervisor-child-task sup 'coop_worker))
        (hung-task (supervisor-child-task sup 'hung_worker)))
    (supervisor-stop! sup)
    (assert-true (atomic-ref graceful-cleaned-up) "cooperative child ran graceful shutdown handler before exit")
    (assert-eq (task-state coop-task) 'terminated "cooperative child state is 'terminated")
    (assert-eq (task-state hung-task) 'terminated "unresponsive child forcefully terminated after 15ms timeout")
    (assert-eq (supervisor-state sup) 'stopped "supervisor transitioned to 'stopped after graceful shutdown")))

;; -----------------------------------------------------------------------
;; Group 11: Child Init Arguments Preservation & Deep-Copy on Restart (#735)
;; -----------------------------------------------------------------------
(write-string "--- Group 11: Child Init Arguments Deep-Copy on Restart (#735) ---\n")
(flush-output-port)

(let* ((received-args-history (make-atomic-box (list)))
       (worker-fn
        (lambda (arg-vec)
          (let ((t (make-task-context))
                (val (vector-ref arg-vec 0)))
            ;; Record received initial value
            (let retry ()
              (let ((cur (atomic-ref received-args-history)))
                (if (not (atomic-cas! received-args-history cur (cons val cur)))
                    (retry)
                    #t)))
            ;; Deliberately corrupt the passed vector in-place
            (vector-set! arg-vec 0 9999)
            t)))
       (init-vec (vector 100 200))
       (cspec (make-child-spec 'arg_worker worker-fn 'permanent 'brutal_kill 'worker (list init-vec)))
       (sup-spec (make-supervisor-spec 'one_for_one 5 10 (list cspec)))
       (sup (make-supervisor sup-spec)))

  ;; Verify accessor
  (assert-true (list? (child-spec-init-args cspec)) "child-spec-init-args returns list")
  (assert-equal (vector-ref (car (child-spec-init-args cspec)) 0) 100 "stored init-args vector slot is 100")

  (supervisor-start! sup)
  (let* ((c1 (supervisor-child-task sup 'arg_worker))
         (c1-tid (task-tid c1)))
    ;; 1st run should have received 100
    (assert-equal (car (atomic-ref received-args-history)) 100 "first boot received initial argument 100")

    ;; Simulate child crash and trigger supervisor auto-restart
    (supervisor-handle-child-down! sup c1-tid 'worker_crash)

    ;; 2nd run after restart MUST receive fresh 100, NOT corrupted 9999
    (let ((hist (atomic-ref received-args-history)))
      (assert-equal (length hist) 2 "history contains 2 boots (initial + restart)")
      (assert-equal (car hist) 100 "restarted child received pristine deep-copied argument 100")
      (assert-equal (cadr hist) 100 "both boots received pristine 100"))

    ;; Clean shutdown
    (supervisor-stop! sup))

  ;; Verification of error guard
  (assert-true (guard (exn (else #t))
                 (make-child-spec 'bad_args worker-fn 'permanent 'brutal_kill 'worker "not-a-list")
                 #f)
               "make-child-spec rejects non-list init-args (CWE-843)"))

;; -----------------------------------------------------------------------
;; Group 12: Multi-Strategy Auto-Enqueue to Scheduler on Restart (#742)
;; -----------------------------------------------------------------------
(write-string "--- Group 12: Multi-Strategy Scheduler Auto-Enqueue (#742) ---\n")
(flush-output-port)

(let* ((sched (make-work-stealing-scheduler 2 32))
       (all-a-runs (make-atomic-box 0))
       (all-b-runs (make-atomic-box 0))
       (all-a-spec
        (make-child-spec
         'all_a
         (lambda ()
           (let ((t (make-task-context))
                 (run-cnt (+ (atomic-fetch-add! all-a-runs 1) 1)))
             (task-next-run-set!
              t
              (lambda ()
                (if (= run-cnt 1)
                    (car '()) ; 1st boot: crash
                    #t)))     ; 2nd boot: complete normally
             t))
         'transient))
       (all-b-spec
        (make-child-spec
         'all_b
         (lambda ()
           (let ((t (make-task-context)))
             (atomic-fetch-add! all-b-runs 1)
             (task-next-run-set! t (lambda () #t))
             t))
         'transient))
       (sup-spec (make-supervisor-spec 'one_for_all 5 1000 (list all-a-spec all-b-spec)))
       (sup (make-supervisor sup-spec #f sched)))

  ;; Accessor verification
  (assert-true (work-stealing-scheduler? (supervisor-scheduler sup)) "supervisor-scheduler returns active scheduler")

  ;; Start supervisor and spawn initial children to scheduler
  (supervisor-start! sup)
  (let ((t-a (supervisor-child-task sup 'all_a))
        (t-b (supervisor-child-task sup 'all_b)))
    (scheduler-spawn! sched t-a 0)
    (scheduler-spawn! sched t-b 1)
    ;; Run scheduler: t-a crashes, supervisor executes one_for_all restart and automatically enqueues both new tasks
    (scheduler-run! sched)

    (assert-equal (atomic-ref all-a-runs) 2 "all_a booted twice (initial crash + restarted)")
    (assert-equal (atomic-ref all-b-runs) 2 "all_b booted twice (one_for_all cascaded restart)")
    (assert-eq (supervisor-child-task sup 'all_a) #f "all_a transient worker removed after normal completion")
    (assert-eq (supervisor-child-task sup 'all_b) #f "all_b transient worker removed after normal completion")
    (supervisor-stop! sup)
    (scheduler-stop! sched)))

;; -----------------------------------------------------------------------
;; Group 13: Supervisor Actor Serialization & Concurrent Crash Isolation (#743)
;; -----------------------------------------------------------------------
(write-string "--- Group 13: Supervisor Actor Concurrent Crash Isolation (#743) ---\n")
(flush-output-port)

(let* ((race-a-boots (make-atomic-box 0))
       (race-b-boots (make-atomic-box 0))
       (spec-a
        (make-child-spec
         'race_a
         (lambda ()
           (atomic-fetch-add! race-a-boots 1)
           (make-task-context))
         'permanent))
       (spec-b
        (make-child-spec
         'race_b
         (lambda ()
           (atomic-fetch-add! race-b-boots 1)
           (make-task-context))
         'permanent))
       (sup-spec (make-supervisor-spec 'one_for_all 10 1000 (list spec-a spec-b)))
       (sup (make-supervisor sup-spec)))

  (supervisor-start! sup)
  (assert-equal (atomic-ref race-a-boots) 1 "race_a booted once on start")
  (assert-equal (atomic-ref race-b-boots) 1 "race_b booted once on start")

  (let* ((t-a (supervisor-child-task sup 'race_a))
         (t-b (supervisor-child-task sup 'race_b))
         (tid-a (task-tid t-a))
         (tid-b (task-tid t-b))
         (sup-task (supervisor-task sup)))

    ;; Simulate two workers concurrently delivering DOWN signals to the supervisor mailbox
    (task-set-handoff! sup-task (list 'DOWN 101 'process tid-a '(panic . concurrent_fault_a)))
    (task-set-handoff! sup-task (list 'DOWN 102 'process tid-b '(panic . concurrent_fault_b)))

    ;; Drain signals via serialized Work-Draining loop
    (supervisor-poll-down-signals! sup)

    ;; In one_for_all, the supervisor drains both DOWN signals in serialized order.
    ;; 1st DOWN triggers one_for_all restart of both A and B.
    ;; 2nd DOWN for old tid-b is cleanly ignored/drained since tid-b is already terminated!
    ;; Therefore, children are restarted cleanly without state corruption or duplicate leaking instances.
    (assert-equal (length (supervisor-children sup)) 2 "supervisor maintains exactly 2 active children (no duplicate leakage)")
    (let ((new-a (supervisor-child-task sup 'race_a))
          (new-b (supervisor-child-task sup 'race_b)))
      (assert-true (task-context? new-a) "new race_a instance exists")
      (assert-true (task-context? new-b) "new race_b instance exists")
      (assert-true (not (= (task-tid new-a) tid-a)) "race_a assigned fresh TID")
      (assert-true (not (= (task-tid new-b) tid-b)) "race_b assigned fresh TID"))

    (supervisor-stop! sup)))

;; -----------------------------------------------------------------------
;; Group 14: Non-DOWN Signal Preservation & EXIT Auto-Restart (#751)
;; -----------------------------------------------------------------------
(write-string "--- Group 14: Non-DOWN Signal Preservation & Routing (#751) ---\n")
(flush-output-port)

;; 14.1 Interleaved DOWN and io_complete messages
(let* ((w-boots (make-atomic-box 0))
       (w-spec (make-child-spec 'w_io
                                (lambda ()
                                  (atomic-fetch-add! w-boots 1)
                                  (make-task-context))
                                'permanent))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list w-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)
  (assert-equal (atomic-ref w-boots) 1 "w_io booted initially")

  (let* ((child-t (supervisor-child-task sup 'w_io))
         (child-tid (task-tid child-t))
         (sup-task (supervisor-task sup)))

    ;; Deliver both a DOWN notification and an io_complete message to supervisor
    (task-set-handoff! sup-task (list 'DOWN 201 'process child-tid '(panic . io_error)))
    (task-set-handoff! sup-task (cons 'io_complete 8192))
    (task-set-handoff! sup-task '("custom_audit_event" 12345))

    ;; Poll down signals
    (supervisor-poll-down-signals! sup)

    ;; 1) DOWN signal must have restarted child w_io
    (assert-equal (atomic-ref w-boots) 2 "w_io restarted upon DOWN")
    (let ((new-child (supervisor-child-task sup 'w_io)))
      (assert-true (task-context? new-child) "new w_io exists")
      (assert-true (not (= (task-tid new-child) child-tid)) "w_io assigned new TID"))

    ;; 2) io_complete and custom audit messages MUST NOT be discarded; preserved in preserved-inbox
    (let ((preserved (supervisor-preserved-messages sup)))
      (assert-equal (length preserved) 2 "both non-DOWN messages preserved in inbox")
      (assert-equal (car preserved) (cons 'io_complete 8192) "1st preserved message is io_complete")
      (assert-equal (cadr preserved) '("custom_audit_event" 12345) "2nd preserved message is audit event"))

    ;; 3) supervisor-take-preserved-message! drains FIFO
    (assert-equal (supervisor-take-preserved-message! sup) (cons 'io_complete 8192)
                  "drained 1st preserved message")
    (assert-equal (length (supervisor-preserved-messages sup)) 1 "1 message remaining")
    (assert-equal (supervisor-take-preserved-message! sup) '("custom_audit_event" 12345)
                  "drained 2nd preserved message")
    (assert-equal (supervisor-take-preserved-message! sup 'none) 'none
                  "empty take returns default")
    (assert-equal (length (supervisor-preserved-messages sup)) 0 "inbox is empty"))

  (supervisor-stop! sup))

;; 14.2 Managed child EXIT signal triggers supervisor restart
(let* ((exit-boots (make-atomic-box 0))
       (w-spec (make-child-spec 'w_exit
                                (lambda ()
                                  (atomic-fetch-add! exit-boots 1)
                                  (make-task-context))
                                'permanent))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list w-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)
  (assert-equal (atomic-ref exit-boots) 1 "w_exit booted initially")

  (let* ((child-t (supervisor-child-task sup 'w_exit))
         (child-tid (task-tid child-t))
         (sup-task (supervisor-task sup)))

    ;; Deliver Erlang/OTP style EXIT signal from managed child
    (task-set-handoff! sup-task (list 'EXIT child-tid '(panic . segv_fault)))

    ;; Poll signals
    (supervisor-poll-down-signals! sup)

    ;; EXIT signal from managed child MUST trigger automatic restart!
    (assert-equal (atomic-ref exit-boots) 2 "w_exit restarted via EXIT signal")
    (let ((new-child (supervisor-child-task sup 'w_exit)))
      (assert-true (task-context? new-child) "new w_exit exists")
      (assert-true (not (= (task-tid new-child) child-tid)) "w_exit assigned fresh TID"))
    ;; Managed child EXIT signal must not be preserved as leftover unhandled message
    (assert-equal (length (supervisor-preserved-messages sup)) 0 "EXIT signal consumed by restart"))

  (supervisor-stop! sup))

;; 14.3 Unmanaged external EXIT signal is preserved
(let* ((w-spec (make-child-spec 'w_idle
                                (lambda () (make-task-context))
                                'permanent))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list w-spec)))
       (sup (make-supervisor sup-spec)))
  (supervisor-start! sup)
  (let ((sup-task (supervisor-task sup))
        (unmanaged-exit (list 'EXIT 88888 'external_linked_peer_crashed)))

    (task-set-handoff! sup-task unmanaged-exit)
    (supervisor-poll-down-signals! sup)

    (assert-equal (length (supervisor-preserved-messages sup)) 1 "unmanaged EXIT preserved")
    (assert-equal (supervisor-take-preserved-message! sup) unmanaged-exit "retrieved unmanaged EXIT")
    (assert-equal (length (supervisor-preserved-messages sup)) 0 "preserved inbox drained"))
  (supervisor-stop! sup))

;; 14.4 Custom message handler hook & clear API
(let* ((w-spec (make-child-spec 'w_custom
                                (lambda () (make-task-context))
                                'permanent))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list w-spec)))
       (sup (make-supervisor sup-spec))
       (handled-rpc (make-atomic-box #f)))

  ;; Set custom message handler: handles 'rpc_ping, rejects other
  (supervisor-set-message-handler!
   sup
   (lambda (s msg)
     (if (and (pair? msg) (eq? (car msg) 'rpc_ping))
         (begin
           (atomic-set! handled-rpc (cdr msg))
           #t) ; handled!
         #f))) ; unhandled -> falls through to preserved inbox

  (assert-true (procedure? (supervisor-message-handler sup)) "message handler installed")
  (supervisor-start! sup)

  (let ((sup-task (supervisor-task sup)))
    ;; Deliver handled RPC and unhandled tuple
    (task-set-handoff! sup-task (cons 'rpc_ping 999))
    (task-set-handoff! sup-task (cons 'unhandled_command 42))

    (supervisor-poll-down-signals! sup)

    (assert-equal (atomic-ref handled-rpc) 999 "rpc_ping processed by custom handler")
    (assert-equal (length (supervisor-preserved-messages sup)) 1 "unhandled command preserved")
    (assert-equal (supervisor-take-preserved-message! sup) (cons 'unhandled_command 42) "unhandled retrieved")

    ;; Test clear preserved messages
    (task-set-handoff! sup-task 'msg1)
    (task-set-handoff! sup-task 'msg2)
    (supervisor-poll-down-signals! sup)
    (assert-equal (length (supervisor-preserved-messages sup)) 2 "2 messages preserved")
    (supervisor-clear-preserved-messages! sup)
    (assert-equal (length (supervisor-preserved-messages sup)) 0 "preserved inbox cleared"))

  (supervisor-stop! sup))

;; 14.5 CWE-843 Type guards on preserved API
(assert-true (guard (exn (else #t)) (supervisor-preserved-messages 'not-a-sup) #f)
             "supervisor-preserved-messages rejects non-supervisor (CWE-843)")
(assert-true (guard (exn (else #t)) (supervisor-take-preserved-message! 'not-a-sup) #f)
             "supervisor-take-preserved-message! rejects non-supervisor (CWE-843)")
(assert-true (guard (exn (else #t)) (supervisor-clear-preserved-messages! 'not-a-sup) #f)
             "supervisor-clear-preserved-messages! rejects non-supervisor (CWE-843)")
(assert-true (guard (exn (else #t)) (supervisor-set-message-handler! 'not-a-sup (lambda (s m) #t)) #f)
             "supervisor-set-message-handler! rejects non-supervisor (CWE-843)")
(assert-true (guard (exn (else #t)) (supervisor-set-message-handler! (make-supervisor (make-supervisor-spec 'one_for_one 1 100 '())) 'not-a-proc) #f)
             "supervisor-set-message-handler! rejects non-procedure handler (CWE-843)")

;; -----------------------------------------------------------------------
;; Group 15: Nested Supervision Tree & Persistent Supervisor Tasks (Issue #788)
;; -----------------------------------------------------------------------
(write-string "--- Group 15: Nested Supervision Tree & Persistent Supervisor Tasks (#788) ---\n")
(flush-output-port)

;; 15.1 task-resident-set!, task-resident?, and task-resident-hook API (CWE-843)
(let ((t (make-task-context)))
  (assert-true (not (task-resident? t)) "default task is not resident")
  (assert-true (not (task-resident-hook t)) "default task has no resident-hook")
  (assert-true (task-resident-set! t #t) "task-resident-set! #t returns #t")
  (assert-true (task-resident? t) "task-resident? is now #t")
  (assert-true (not (task-resident-hook t)) "task-resident-hook is #f when set to #t")
  (let ((custom-hook (lambda (task) 'hook-executed)))
    (assert-true (procedure? (task-resident-set! t custom-hook)) "task-resident-set! accepts procedure")
    (assert-true (task-resident? t) "task-resident? is #t when procedure is set")
    (assert-eq (task-resident-hook t) custom-hook "task-resident-hook returns custom procedure"))
  (assert-true (not (task-resident-set! t #f)) "task-resident-set! #f returns #f")
  (assert-true (not (task-resident? t)) "task-resident? is now #f")
  (assert-true (not (task-resident-hook t)) "task-resident-hook is now #f"))

(assert-true (not (task-resident? 'not-a-task)) "task-resident? on non-task returns #f")
(assert-true (not (task-resident-hook 'not-a-task)) "task-resident-hook on non-task returns #f")
(assert-true (guard (exn (else #t)) (task-resident-set! 'not-a-task #t) #f)
             "task-resident-set! rejects non-task (CWE-843)")
(assert-true (guard (exn (else #t)) (task-resident-set! (make-task-context) "invalid-string") #f)
             "task-resident-set! rejects invalid type string (CWE-843)")
(assert-true (guard (exn (else #t)) (task-resident-set! (make-task-context) 12345) #f)
             "task-resident-set! rejects invalid type integer (CWE-843)")

;; 15.2 Supervisor sup-task is marked resident by default
(let* ((spec (make-supervisor-spec 'one_for_one 5 1000 '()))
       (sup (make-supervisor spec)))
  (assert-true (task-resident? (supervisor-task sup)) "supervisor-task is marked resident on creation (#788)")
  (supervisor-start! sup)
  (assert-true (task-resident? (supervisor-task sup)) "supervisor-task remains resident after start")
  (supervisor-stop! sup)
  (assert-true (not (task-resident? (supervisor-task sup))) "supervisor-stop! clears resident flag (#788)")
  (assert-eq (task-state (supervisor-task sup)) 'terminated "supervisor-stop! terminates sup-task"))

;; 15.3 Single Supervisor Mailbox Drain preserves 'waiting state in Scheduler
(let* ((sched (make-work-stealing-scheduler 2 256))
       (w-boots (make-atomic-box 0))
       (w-spec (make-child-spec 'w_drain
                                (lambda ()
                                  (atomic-fetch-add! w-boots 1)
                                  (let ((t (make-task-context)))
                                    (task-next-run-set! t (lambda () (cons 'ok 'drain_done)))
                                    t))
                                'transient))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list w-spec)))
       (sup (make-supervisor sup-spec #f sched)))
  (supervisor-start! sup sched #t)
  (let* ((sup-task (supervisor-task sup))
         (child (supervisor-child-task sup 'w_drain)))
    (assert-eq (atomic-ref w-boots) 1 "w_drain booted initially")
    ;; Run scheduler step to execute child task to normal completion
    (scheduler-worker-step! sched 0)
    ;; Child completed normally -> sends DOWN (normal) to sup-task
    ;; Draining DOWN signal by sup-task via scheduler step:
    (scheduler-worker-step! sched 0)
    ;; Verify sup-task state is 'waiting (NOT 'terminated!)
    (assert-eq (task-state sup-task) 'waiting "supervisor task state is 'waiting after mailbox drain (#788)")
    (assert-true (not (eq? (task-state sup-task) 'terminated)) "supervisor task is not terminated (#788)")
    (supervisor-stop! sup)))

;; 15.4 Nested Supervision Tree: Worker crash under Child Supervisor does not trigger Parent restart
(let* ((sched (make-work-stealing-scheduler 2 256))
       (leaf-boots (make-atomic-box 0))
       (leaf-spec (make-child-spec 'leaf_worker
                                   (lambda ()
                                     (atomic-fetch-add! leaf-boots 1)
                                     (make-task-context))
                                   'permanent))
       (child-sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list leaf-spec)))
       (child-sup (make-supervisor child-sup-spec #f sched))
       (child-sup-task (supervisor-task child-sup))
       (initial-child-sup-tid (task-tid child-sup-task))
       (parent-restarts-of-child (make-atomic-box 0))
       (child-sup-child-spec (make-child-spec 'sub_supervisor
                                              (lambda ()
                                                (atomic-fetch-add! parent-restarts-of-child 1)
                                                child-sup-task)
                                              'permanent
                                              'supervisor))
       (parent-sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list child-sup-child-spec)))
       (parent-sup (make-supervisor parent-sup-spec #f sched)))

  ;; Start child supervisor then parent supervisor
  (supervisor-start! child-sup sched #t)
  (supervisor-start! parent-sup sched #t)

  (assert-eq (atomic-ref leaf-boots) 1 "leaf_worker booted initially (1st time)")
  (assert-eq (atomic-ref parent-restarts-of-child) 1 "child_supervisor registered in parent (1st time)")

  (let* ((leaf-task (supervisor-child-task child-sup 'leaf_worker))
         (leaf-tid (task-tid leaf-task)))
    ;; Simulate a failure of leaf_worker
    (task-exit! leaf-task '(panic . simulated_leaf_fault))

    ;; Process DOWN signals through scheduler
    (scheduler-worker-step! sched 0)
    (scheduler-worker-step! sched 0)

    ;; Verify leaf_worker was restarted under child-sup
    (assert-eq (atomic-ref leaf-boots) 2 "leaf_worker restarted after fault")
    (let ((new-leaf (supervisor-child-task child-sup 'leaf_worker)))
      (assert-true (task-context? new-leaf) "new leaf_worker task exists")
      (assert-true (not (= (task-tid new-leaf) leaf-tid)) "new leaf_worker has fresh TID"))

    ;; Crucial verification of Issue #788:
    ;; child-sup-task did NOT prematurely exit or send spurious DOWN (normal) to parent-sup!
    (assert-eq (task-state child-sup-task) 'waiting "child supervisor task is 'waiting (not terminated) (#788)")
    (assert-eq (atomic-ref parent-restarts-of-child) 1 "parent supervisor NEVER restarted child supervisor (#788)")
    (assert-eq (task-tid (supervisor-child-task parent-sup 'sub_supervisor))
               initial-child-sup-tid
               "child supervisor preserved original TID across child worker restarts (#788)")

    ;; Verify parent-sup inbox has no unhandled DOWN messages
    (assert-equal (length (supervisor-preserved-messages parent-sup)) 0
                  "parent supervisor received 0 spurious signals (#788)"))

  (supervisor-stop! parent-sup)
  (supervisor-stop! child-sup)
  (assert-eq (task-state child-sup-task) 'terminated "child supervisor terminated after explicit stop")
  (assert-eq (task-state (supervisor-task parent-sup)) 'terminated "parent supervisor terminated after explicit stop"))

;; -----------------------------------------------------------------------
;; Group 16: Coalesced Supervisor Spawning & Multi-Child Crash Isolation (Issue #789)
;; -----------------------------------------------------------------------
(write-string "--- Group 16: Coalesced Supervisor Spawning & Multi-Child Crash Isolation (#789) ---\n")
(flush-output-port)

;; 16.1 supervisor-enqueued-state API & Security Guards (CWE-843)
(let* ((spec (make-supervisor-spec 'one_for_one 5 1000 '()))
       (sup (make-supervisor spec)))
  (assert-eq (supervisor-enqueued-state sup) 'idle "initial supervisor enqueued state is 'idle (#789)")
  (supervisor-start! sup)
  (assert-eq (supervisor-enqueued-state sup) 'idle "running supervisor with empty mailbox is 'idle")
  (supervisor-stop! sup)
  (assert-eq (supervisor-enqueued-state sup) 'idle "stopped supervisor is 'idle"))

(assert-true (guard (exn (else #t)) (supervisor-enqueued-state 'not-a-sup) #f)
             "supervisor-enqueued-state rejects non-supervisor (CWE-843)")

;; 16.2 4-State Actor Machine Transitions (idle -> scheduled -> running -> running_notified -> idle)
(let* ((sched (make-work-stealing-scheduler 2 256))
       (spec (make-supervisor-spec 'one_for_one 5 1000 '()))
       (sup (make-supervisor spec #f sched))
       (sup-task (supervisor-task sup)))
  (supervisor-start! sup sched #f)
  (assert-eq (supervisor-enqueued-state sup) 'idle "initial state is 'idle")

  ;; Schedule actor: transition 'idle -> 'scheduled
  (assert-true (%supervisor-schedule-actor! sup sup-task) "%supervisor-schedule-actor! returns #t")
  (assert-eq (supervisor-enqueued-state sup) 'scheduled "state transitioned to 'scheduled")
  (assert-eq (task-state sup-task) 'ready "sup-task is 'ready")

  ;; Second schedule attempt while already 'scheduled must be coalesced (no duplicate spawn)
  (let ((sched-spawned-before (scheduler-tasks-spawned sched)))
    (assert-true (%supervisor-schedule-actor! sup sup-task) "second schedule returns #t (coalesced)")
    (assert-eq (supervisor-enqueued-state sup) 'scheduled "state remains 'scheduled (no duplicate)")
    (assert-eq (scheduler-tasks-spawned sched) sched-spawned-before "no additional task spawned into scheduler (#789)"))

  ;; Worker pops and starts executing: drain loop sets state to 'running
  (let ((res (%supervisor-drain-loop! sup)))
    ;; Drain loop completes and transitions back to 'idle
    (assert-eq (supervisor-enqueued-state sup) 'idle "state returned to 'idle after drain"))

  ;; Test 'running -> 'running_notified transition
  (let ((box (%supervisor-enqueued-box sup)))
    (atomic-set! box 'running)
    (assert-eq (supervisor-enqueued-state sup) 'running "manually set to 'running")
    (assert-true (%supervisor-schedule-actor! sup sup-task) "schedule while running returns #t")
    (assert-eq (supervisor-enqueued-state sup) 'running_notified "state transitioned to 'running_notified (#789)")
    ;; Additional notification while already 'running_notified remains 'running_notified
    (assert-true (%supervisor-schedule-actor! sup sup-task) "repeated notification while running_notified returns #t")
    (assert-eq (supervisor-enqueued-state sup) 'running_notified "state remains 'running_notified (#789)")
    ;; Reset to idle
    (atomic-set! box 'idle))

  (supervisor-stop! sup))

;; 16.3 Multi-Child Simultaneous Crash: Coalesced Scheduling & Full Recovery
(let* ((sched (make-work-stealing-scheduler 2 256))
       (b0 (make-atomic-box 0))
       (b1 (make-atomic-box 0))
       (b2 (make-atomic-box 0))
       (b3 (make-atomic-box 0))
       (b4 (make-atomic-box 0))
       (b5 (make-atomic-box 0))
       (make-worker (lambda (name b)
                      (make-child-spec name
                                       (lambda ()
                                         (atomic-fetch-add! b 1)
                                         (let ((t (make-task-context)))
                                           (task-resident-set! t #t)
                                           t))
                                       'permanent)))
       (w0-spec (make-worker 'w0 b0))
       (w1-spec (make-worker 'w1 b1))
       (w2-spec (make-worker 'w2 b2))
       (w3-spec (make-worker 'w3 b3))
       (w4-spec (make-worker 'w4 b4))
       (w5-spec (make-worker 'w5 b5))
       (sup-spec (make-supervisor-spec 'one_for_one 20 1000 (list w0-spec w1-spec w2-spec w3-spec w4-spec w5-spec)))
       (sup (make-supervisor sup-spec #f sched))
       (sup-task (supervisor-task sup)))

  (supervisor-start! sup sched #t)

  ;; Verify all 6 workers booted once
  (assert-eq (atomic-ref b0) 1 "w0 booted initially")
  (assert-eq (atomic-ref b1) 1 "w1 booted initially")
  (assert-eq (atomic-ref b2) 1 "w2 booted initially")
  (assert-eq (atomic-ref b3) 1 "w3 booted initially")
  (assert-eq (atomic-ref b4) 1 "w4 booted initially")
  (assert-eq (atomic-ref b5) 1 "w5 booted initially")

  (let ((t0 (supervisor-child-task sup 'w0))
        (t1 (supervisor-child-task sup 'w1))
        (t2 (supervisor-child-task sup 'w2))
        (t3 (supervisor-child-task sup 'w3))
        (t4 (supervisor-child-task sup 'w4))
        (t5 (supervisor-child-task sup 'w5)))

    (let ((tid0 (task-tid t0))
          (tid1 (task-tid t1))
          (tid2 (task-tid t2))
          (tid3 (task-tid t3))
          (tid4 (task-tid t4))
          (tid5 (task-tid t5)))

      ;; SIMULTANEOUS BURST CRASH: all 6 children terminate concurrently!
      (task-exit! t0 '(panic . simultaneous_crash_0))
      (task-exit! t1 '(panic . simultaneous_crash_1))
      (task-exit! t2 '(panic . simultaneous_crash_2))
      (task-exit! t3 '(panic . simultaneous_crash_3))
      (task-exit! t4 '(panic . simultaneous_crash_4))
      (task-exit! t5 '(panic . simultaneous_crash_5))

      ;; Because of Coalesced Scheduling (#789):
      ;; sup-task was enqueued into sched ONCE, not 6 times!
      (assert-true (or (eq? (supervisor-enqueued-state sup) 'scheduled)
                       (eq? (supervisor-enqueued-state sup) 'running)
                       (eq? (supervisor-enqueued-state sup) 'running_notified))
                   "supervisor task is scheduled or running")

      ;; Execute tasks through the scheduler to drain all notifications and perform restarts
      (scheduler-run! sched 30)

      ;; Verify all 6 workers restarted cleanly (boot count = 2)
      (assert-eq (atomic-ref b0) 2 "w0 restarted after burst crash")
      (assert-eq (atomic-ref b1) 2 "w1 restarted after burst crash")
      (assert-eq (atomic-ref b2) 2 "w2 restarted after burst crash")
      (assert-eq (atomic-ref b3) 2 "w3 restarted after burst crash")
      (assert-eq (atomic-ref b4) 2 "w4 restarted after burst crash")
      (assert-eq (atomic-ref b5) 2 "w5 restarted after burst crash")

      ;; Verify each child has a new, fresh TID
      (assert-true (not (= (task-tid (supervisor-child-task sup 'w0)) tid0)) "w0 assigned fresh TID")
      (assert-true (not (= (task-tid (supervisor-child-task sup 'w1)) tid1)) "w1 assigned fresh TID")
      (assert-true (not (= (task-tid (supervisor-child-task sup 'w2)) tid2)) "w2 assigned fresh TID")
      (assert-true (not (= (task-tid (supervisor-child-task sup 'w3)) tid3)) "w3 assigned fresh TID")
      (assert-true (not (= (task-tid (supervisor-child-task sup 'w4)) tid4)) "w4 assigned fresh TID")
      (assert-true (not (= (task-tid (supervisor-child-task sup 'w5)) tid5)) "w5 assigned fresh TID")

      ;; Verify supervisor task state is 'waiting and enqueued state is 'idle
      (assert-eq (task-state sup-task) 'waiting "supervisor task returned to 'waiting")
      (assert-eq (supervisor-enqueued-state sup) 'idle "supervisor enqueued state returned to 'idle (#789)")))

  (supervisor-stop! sup))

;; 16.4 Multi-Worker Work-Stealing Crash Isolation (4 Workers, CWE-362 / CWE-662)
(let* ((sched (make-work-stealing-scheduler 4 256))
       (restarts (make-atomic-box 0))
       (make-spec (lambda (name)
                    (make-child-spec name
                                     (lambda ()
                                       (atomic-fetch-add! restarts 1)
                                       (let ((t (make-task-context)))
                                         (task-resident-set! t #t)
                                         t))
                                     'permanent)))
       (cspecs (list (make-spec 'c0) (make-spec 'c1) (make-spec 'c2) (make-spec 'c3)
                     (make-spec 'c4) (make-spec 'c5) (make-spec 'c6) (make-spec 'c7)))
       (sup-spec (make-supervisor-spec 'one_for_one 30 1000 cspecs))
       (sup (make-supervisor sup-spec #f sched))
       (sup-task (supervisor-task sup)))

  (supervisor-start! sup sched #t)
  (assert-eq (atomic-ref restarts) 8 "all 8 workers booted initially")

  ;; Crash all 8 workers in rapid succession
  (let loop ((names '(c0 c1 c2 c3 c4 c5 c6 c7)))
    (if (not (null? names))
        (let ((ctask (supervisor-child-task sup (car names))))
          (task-exit! ctask '(panic . burst_crash))
          (loop (cdr names)))))

  ;; Drain scheduler with 4 workers
  (scheduler-run! sched 40)

  ;; Verify exactly 8 restarts occurred (total 16 boots)
  (assert-eq (atomic-ref restarts) 16 "all 8 workers restarted exactly once under 4-worker scheduler (#789)")
  (assert-eq (supervisor-enqueued-state sup) 'idle "supervisor enqueued state is 'idle after multi-worker drain")
  (assert-eq (task-state sup-task) 'waiting "supervisor task state is 'waiting")

  (supervisor-stop! sup)
  (assert-eq (supervisor-enqueued-state sup) 'idle "stopped supervisor remains 'idle"))

;; -----------------------------------------------------------------------
;; Group 17: Post-Boundary Hook & Race-Free Idle Re-Entry under 4-Worker Burst (#798)
;; -----------------------------------------------------------------------
(write-string "--- Group 17: Post-Boundary Hook & Race-Free Idle Re-Entry (#798) ---\n")
(flush-output-port)

;; 17.1 sup-task automatically receives post-drain resident hook on creation
(let* ((spec (make-supervisor-spec 'one_for_one 5 1000 '()))
       (sup (make-supervisor spec))
       (sup-task (supervisor-task sup)))
  (assert-true (task-resident? sup-task) "sup-task is resident")
  (assert-true (procedure? (task-resident-hook sup-task)) "sup-task has procedure resident hook (#798)")
  (supervisor-stop! sup))

;; 17.2 scheduler-execute-task! calls task-resident-hook after task-state becomes 'waiting
(let* ((sched (make-work-stealing-scheduler 1 64))
       (hook-called (make-atomic-box #f))
       (state-at-hook (make-atomic-box #f))
       (t (make-task-context)))
  (task-resident-set! t (lambda (task)
                          (atomic-set! hook-called #t)
                          (atomic-set! state-at-hook (task-state task))))
  (task-next-run-set! t (lambda () (cons 'ok 'done)))
  (scheduler-spawn! sched t 0)
  (scheduler-worker-step! sched 0)
  (assert-true (atomic-ref hook-called) "post-boundary hook called after execution (#798)")
  (assert-eq (atomic-ref state-at-hook) 'waiting "task-state is 'waiting when hook is executed (#798)")
  (assert-eq (task-state t) 'waiting "task remains 'waiting after hook"))

;; 17.3 4-Worker High-Frequency Burst Crash: Zero Concurrent Re-entry (CWE-362/662)
(let* ((sched (make-work-stealing-scheduler 4 512))
       (restarts (make-atomic-box 0))
       (active-workers (make-atomic-box 0))
       (max-active-workers (make-atomic-box 0))
       (make-spec (lambda (name)
                    (make-child-spec name
                                     (lambda ()
                                       (atomic-fetch-add! restarts 1)
                                       (let ((t (make-task-context)))
                                         (task-resident-set! t #t)
                                         (task-next-run-set! t (lambda () (cons 'ok 'worker_alive)))
                                         t))
                                     'permanent)))
       (cspecs (list (make-spec 'k0) (make-spec 'k1) (make-spec 'k2) (make-spec 'k3)
                     (make-spec 'k4) (make-spec 'k5) (make-spec 'k6) (make-spec 'k7)))
       (sup-spec (make-supervisor-spec 'one_for_one 100 2000 cspecs))
       (sup (make-supervisor sup-spec #f sched))
       (sup-task (supervisor-task sup))
       (orig-hook (task-resident-hook sup-task)))

  ;; Instrument supervisor task execution with concurrency detector
  (let ((orig-runner (task-next-run sup-task)))
    (task-next-run-set!
     sup-task
     (lambda ()
       (let ((cur (atomic-fetch-add! active-workers 1)))
         (let retry-max ()
           (let* ((old-max (atomic-ref max-active-workers))
                  (new-max (+ cur 1)))
             (if (> new-max old-max)
                 (if (not (atomic-cas! max-active-workers old-max new-max))
                     (retry-max)
                     #t)
                 #t)))
         (let ((res (orig-runner)))
           (atomic-fetch-add! active-workers -1)
           res)))))

  (supervisor-start! sup sched #t)
  (assert-eq (atomic-ref restarts) 8 "all 8 burst workers booted initially")

  ;; Perform 3 rounds of 8-worker burst crashes (total 24 crashes)
  (let round-loop ((round 0))
    (if (< round 3)
        (begin
          (let crash-loop ((names '(k0 k1 k2 k3 k4 k5 k6 k7)))
            (if (not (null? names))
                (let ((ctask (supervisor-child-task sup (car names))))
                  (task-exit! ctask (cons 'panic (cons 'burst_round round)))
                  (crash-loop (cdr names)))))
          (scheduler-run! sched 20)
          (round-loop (+ round 1)))))

  ;; Final drain of scheduler queues
  (scheduler-run! sched 40)

  ;; Assertions
  ;; Initial 8 boots + 24 restarts = 32 boots
  (assert-eq (atomic-ref restarts) 32 "all 8 workers restarted 3 times (total 32 boots) (#798)")
  ;; Concurrent supervisor execution count MUST never exceed 1 (Zero Re-Entry)
  (assert-true (<= (atomic-ref max-active-workers) 1) "supervisor concurrency never exceeded 1 worker (CWE-362/662) (#798)")
  (assert-eq (atomic-ref active-workers) 0 "no workers actively running supervisor at idle state")
  (assert-eq (supervisor-enqueued-state sup) 'idle "supervisor enqueued state is 'idle after burst drain (#798)")
  (assert-eq (task-state sup-task) 'waiting "supervisor task state is 'waiting after burst drain")

  (supervisor-stop! sup)
  (assert-eq (supervisor-enqueued-state sup) 'idle "stopped supervisor remains 'idle"))

(test-end "concurrency-supervisor")
