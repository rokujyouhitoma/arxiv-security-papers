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

(define *tests-passed* (vector 0))
(define *tests-failed* (vector 0))

(define (assert-true expr msg)
  (if expr
      (begin
        (vector-set! *tests-passed* 0 (+ (vector-ref *tests-passed* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-string "\n")
        (flush-output-port))
      (begin
        (vector-set! *tests-failed* 0 (+ (vector-ref *tests-failed* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-string "\n")
        (flush-output-port))))

(define (assert-eq a b msg)
  (assert-true (eq? a b) msg))

(define (assert-equal a b msg)
  (assert-true (equal? a b) msg))

;; -----------------------------------------------------------------------
;; Test Suite Execution
;; -----------------------------------------------------------------------

(write-string "=======================================================\n")
(write-string " Starting Synapse Supervision Tree Test Suite (#667)\n")
(write-string "=======================================================\n")
(flush-output-port)

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
       (unrelated-sum-box (make-atomic-box 0))
       (crashy-spec
        (make-child-spec
         'crashy_worker
         (lambda ()
           (let ((t (make-task-context))
                 (attempt (+ (atomic-fetch-add! child-boot-count 1) 1)))
             (task-next-run-set!
              t
              (lambda ()
                (if (= attempt 1)
                    ;; 1st boot: trigger fatal (car '()) pair-tag fault
                    (car '())
                    ;; 2nd boot (restarted): succeed normally
                    (atomic-set! child-recovered-box 777))))
             t))))
       (sup-spec (make-supervisor-spec 'one_for_one 5 1000 (list crashy-spec)))
       (sup (make-supervisor sup-spec)))
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
    ;; 3. Supervisor received DOWN signal and automatically restarts child
    (supervisor-poll-down-signals! sup)
    (let* ((t-child-2 (supervisor-child-task sup 'crashy_worker))
           (tid-2 (task-tid t-child-2)))
      (assert-true (task-context? t-child-2) "restarted child task context exists")
      (assert-true (not (= tid-1 tid-2)) "restarted child assigned a fresh TID")
      ;; Schedule the restarted child and verify it completes
      (scheduler-spawn! sched t-child-2 0)
      (scheduler-run! sched)
      (assert-equal (atomic-ref child-boot-count) 2 "child booted exactly twice (initial crash + 1 restart)")
      (assert-equal (atomic-ref child-recovered-box) 777 "restarted child executed and completed normally"))
    (supervisor-stop! sup)
    (scheduler-stop! sched)))

;; -----------------------------------------------------------------------
;; Final Summary
;; -----------------------------------------------------------------------

(write-string "=======================================================\n")
(write-string " Synapse Supervision Tree Summary: ")
(write-string (number->string (vector-ref *tests-passed* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *tests-failed* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *tests-failed* 0) 0)
    (sys-exit 1)
    (sys-exit 0))
