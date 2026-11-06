;;; =======================================================================
;;; ULisp Concurrency Test: Task Links, Monitors & Poisoning (#666)
;;; Conforms to DSN-37 Section 8.4.1 & 8.4.2 (Fault-Tolerant Supervision)
;;; =======================================================================

(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/queue.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/links.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")

;; -----------------------------------------------------------------------
;; Minimal Test Harness (Vector Boxes instead of top-level set!)
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

(define (assert-false expr msg)
  (assert-true (not expr) msg))

(define (assert-equal actual expected msg)
  (if (equal? actual expected)
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
        (write-string " (expected ")
        (write expected)
        (write-string ", got ")
        (write actual)
        (write-string ")\n")
        (flush-output-port))))

(write-string "=======================================================\n")
(write-string " Starting Synapse Task Links & Monitors Test Suite (#666)\n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: Bi-directional Links & Normal Exit Non-Cascade
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Bi-directional Links & Normal Exit ---\n")
(flush-output-port)

(let ((ta (make-task-context))
      (tb (make-task-context)))
  (assert-false (task-linked? ta tb) "ta and tb not linked initially")
  (assert-true (task-link! ta tb) "task-link! ta tb succeeds")
  (assert-true (task-linked? ta tb) "ta is linked to tb")
  (assert-true (task-linked? tb ta) "tb is linked to ta (symmetric)")

  ;; Normal exit of ta must NOT terminate tb
  (task-handle-termination! ta 'normal)
  (assert-equal (task-state ta) 'terminated "ta is terminated")
  (assert-equal (task-state tb) 'ready "tb remains ready on normal exit of ta")

  ;; Unlink
  (let ((tc (make-task-context))
        (td (make-task-context)))
    (task-link! tc td)
    (assert-true (task-linked? tc td) "tc and td linked")
    (task-unlink! tc td)
    (assert-false (task-linked? tc td) "tc and td unlinked")
    (assert-false (task-linked? td tc) "td and tc unlinked symmetric")))

;; -----------------------------------------------------------------------
;; Group 2: Abnormal Exit Cascade Termination (Zombie Elimination)
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Abnormal Exit Cascade Termination ---\n")
(flush-output-port)

(let ((t1 (make-task-context))
      (t2 (make-task-context))
      (t3 (make-task-context)))
  ;; Form link chain: t1 <-> t2 <-> t3
  (task-link! t1 t2)
  (task-link! t2 t3)
  (assert-true (task-linked? t1 t2) "t1 linked to t2")
  (assert-true (task-linked? t2 t3) "t2 linked to t3")

  ;; t1 crashes with abnormal reason
  (task-handle-termination! t1 'kernel_panic)
  (assert-equal (task-state t1) 'terminated "t1 terminated by panic")
  (assert-equal (task-reductions t1) 0 "t1 reductions zeroed on termination (#723)")
  (assert-equal (task-state t2) 'terminated "t2 cascade killed by t1 (no zombie)")
  (assert-equal (task-reductions t2) 0 "t2 reductions zeroed on link cascade kill (#723)")
  (assert-equal (task-state t3) 'terminated "t3 cascade killed by t2 (no zombie)")
  (assert-equal (task-reductions t3) 0 "t3 reductions zeroed on link cascade kill (#723)"))

;; -----------------------------------------------------------------------
;; Group 3: trap-exit Catch & Signal Message Delivery
;; -----------------------------------------------------------------------
(write-string "--- Group 3: trap-exit Catch & Signal Message Delivery ---\n")
(flush-output-port)

(let ((parent (make-task-context))
      (child (make-task-context)))
  (task-link! parent child)
  (assert-false (task-trap-exit? parent) "parent default trap-exit is #f")
  (assert-true (task-trap-exit! parent #t) "task-trap-exit! parent #t succeeds")
  (assert-true (task-trap-exit? parent) "parent trap-exit is #t")

  ;; Child crashes with error
  (task-handle-termination! child 'division_by_zero)
  (assert-equal (task-state child) 'terminated "child is terminated")
  (assert-equal (task-state parent) 'ready "parent survived child crash due to trap-exit")

  ;; Parent receives EXIT signal message
  (assert-true (task-has-handoff? parent) "parent has EXIT handoff message")
  (let ((msg (task-take-handoff! parent)))
    (assert-equal (car msg) 'EXIT "signal message is 'EXIT")
    (assert-equal (cadr msg) (task-tid child) "signal message contains child tid")
    (assert-equal (caddr msg) 'division_by_zero "signal message contains reason")))

;; -----------------------------------------------------------------------
;; Group 4: Unidirectional Monitor & DOWN Message Delivery
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Unidirectional Monitor & DOWN Notification ---\n")
(flush-output-port)

(let* ((observer (make-task-context))
       (target (make-task-context))
       (notify-ch (make-channel 10))
       (ref (task-monitor observer target notify-ch)))
  (assert-true (integer? ref) "task-monitor returns integer reference ID")
  (assert-true (> ref 0) "ref is positive")

  ;; Target terminates
  (task-handle-termination! target 'worker_timeout)
  (assert-equal (task-state target) 'terminated "target terminated")
  (assert-equal (task-state observer) 'ready "observer unharmed by target death")

  ;; DOWN notification received on notify-ch
  (let ((down-msg (channel-try-recv! notify-ch)))
    (assert-equal (car down-msg) 'DOWN "message type is 'DOWN")
    (assert-equal (cadr down-msg) ref "message ref matches")
    (assert-equal (caddr down-msg) 'process "message format is 'process")
    (assert-equal (cadddr down-msg) (task-tid target) "message tid matches target")
    (assert-equal (car (cddddr down-msg)) 'worker_timeout "message reason matches")))

;; Demonitor test
(let* ((observer (make-task-context))
       (target (make-task-context))
       (notify-ch (make-channel 10))
       (ref (task-monitor observer target notify-ch)))
  (assert-true (task-demonitor observer ref) "task-demonitor succeeds")
  (task-handle-termination! target 'normal)
  (assert-false (channel-try-recv! notify-ch) "no DOWN message delivered after demonitor"))

;; Monitor on already-dead process returns immediate 'noproc
(let* ((observer (make-task-context))
       (dead-target (make-task-context))
       (notify-ch (make-channel 10)))
  (task-state-set! dead-target 'terminated)
  (let ((ref (task-monitor observer dead-target notify-ch)))
    (let ((down-msg (channel-try-recv! notify-ch)))
      (assert-equal (car down-msg) 'DOWN "immediate DOWN delivered for dead process")
      (assert-equal (car (cddddr down-msg)) 'noproc "reason is 'noproc"))))

;; -----------------------------------------------------------------------
;; Group 5: Channel Poisoning & Deadlock Elimination (CWE-833)
;; -----------------------------------------------------------------------
(write-string "--- Group 5: Channel Poisoning & Deadlock Elimination ---\n")
(flush-output-port)

(let ((ch (make-channel 0))
      (owner (make-task-context))
      (client (make-task-context)))
  ;; Register ch to owner task
  (task-register-channel! owner ch)
  (assert-equal (task-owned-channels owner) (list ch) "ch registered to owner")

  ;; Client attempts to recv and gets suspended
  (let ((recv-st (channel-try-recv-with-status! ch)))
    (assert-false (car recv-st) "channel-try-recv-with-status! is not ready"))

  ;; Owner crashes! Must poison all owned channels and unblock client
  (task-handle-termination! owner 'connection_reset)
  (assert-true (channel-poisoned? ch) "channel is poisoned on owner crash")
  (assert-true (channel-closed? ch) "poisoned channel also reports closed")

  ;; Subsequent operations on poisoned channel fail safely with zero hang
  (let ((try-res (channel-try-send! ch 42)))
    (assert-equal try-res (cons #f 'poisoned) "channel-try-send! returns (cons #f 'poisoned)"))
  (let ((recv-res (channel-try-recv-with-status! ch)))
    (assert-equal recv-res (cons #f 'poisoned) "channel-try-recv! returns (cons #f 'poisoned)"))

  ;; Unregister channel
  (task-unregister-channel! owner ch)
  (assert-equal (task-owned-channels owner) '() "ch unregistered successfully"))

;; -----------------------------------------------------------------------
;; Group 6: Security & Boundary Guards (CWE-843 & CWE-400)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Security & Boundary Guards ---\n")
(flush-output-port)

(let ((good-task (make-task-context)))
  ;; Type confusion guards (CWE-843)
  (assert-true (guard (exn (else #t)) (task-link! good-task "not-a-task") #f)
               "task-link! rejects non-task object (CWE-843)")
  (assert-true (guard (exn (else #t)) (task-unlink! "bad" good-task) #f)
               "task-unlink! rejects non-task object (CWE-843)")
  (assert-true (guard (exn (else #t)) (task-monitor good-task 123) #f)
               "task-monitor rejects non-task target (CWE-843)")
  (assert-true (guard (exn (else #t)) (task-demonitor good-task "bad-ref") #f)
               "task-demonitor rejects non-integer ref (CWE-843)")
  (assert-true (guard (exn (else #t)) (channel-poison! "not-a-channel") #f)
               "channel-poison! rejects non-channel (CWE-843)")
  (assert-true (guard (exn (else #t)) (task-register-channel! good-task "not-ch") #f)
               "task-register-channel! rejects non-channel (CWE-843)"))

;; -----------------------------------------------------------------------
;; Group 7: Atomic Monitor/Link Registration vs Termination Seal (#725)
;; -----------------------------------------------------------------------
(write-string "--- Group 7: Atomic Monitor/Link Registration & Closed Seal (#725) ---\n")
(flush-output-port)

;; 7.1 Termination seals monitored-by-box and links-box to 'closed
(let* ((dying (make-task-context))
       (obs-before (make-task-context))
       (obs-after (make-task-context))
       (link-after (make-task-context))
       (ref-before (task-monitor obs-before dying)))
  (task-handle-termination! dying 'crash_reason)
  (assert-equal (atomic-ref (task-monitored-by-box dying)) 'closed "monitored-by-box sealed to 'closed on termination")
  (assert-equal (atomic-ref (task-links-box dying)) 'closed "links-box sealed to 'closed on termination")
  (assert-equal (task-monitored-by dying) '() "task-monitored-by accessor returns '() when sealed")
  (assert-equal (task-links dying) '() "task-links accessor returns '() when sealed")

  ;; Observer registered BEFORE seal receives actual crash_reason
  (let ((msg-before (task-take-handoff! obs-before)))
    (assert-equal (car msg-before) 'DOWN "pre-termination observer got DOWN")
    (assert-equal (list-ref msg-before 4) 'crash_reason "pre-termination observer got 'crash_reason"))

  ;; Observer registering AFTER seal (without notify-channel, via task handoff) immediately gets 'noproc
  (let* ((ref-after (task-monitor obs-after dying))
         (msg-after (task-take-handoff! obs-after)))
    (assert-true (pair? msg-after) "post-seal monitor without channel receives immediate DOWN handoff")
    (assert-equal (car msg-after) 'DOWN "post-seal handoff is 'DOWN")
    (assert-equal (cadr msg-after) ref-after "post-seal DOWN ref matches")
    (assert-equal (list-ref msg-after 4) 'noproc "post-seal DOWN reason is 'noproc"))

  ;; Link registering AFTER seal on trapping task delivers immediate EXIT 'noproc
  (task-trap-exit! link-after #t)
  (task-link! link-after dying)
  (let ((exit-after (task-take-handoff! link-after)))
    (assert-true (pair? exit-after) "post-seal link on trap-exit task receives immediate EXIT")
    (assert-equal (car exit-after) 'EXIT "post-seal link signal is 'EXIT")
    (assert-equal (caddr exit-after) 'noproc "post-seal link reason is 'noproc")))

;; 7.2 Concurrent race between task-monitor and task-handle-termination! across 2 native threads
(let ((missed-downs (make-atomic-box 0)))
  (let race-loop ((iter 0))
    (if (< iter 25)
        (let* ((target (make-task-context))
               (obs (make-task-context))
               (ch (make-channel 4))
               (done-flag (make-atomic-box #f)))
          (spawn-native-thread
           (lambda (arg)
             (task-handle-termination! target 'concurrent_death)
             (atomic-set! done-flag #t))
           0)
          (task-monitor obs target ch)
          (let wait-t ((s 0))
            (if (and (not (atomic-ref done-flag)) (< s 2000000))
                (wait-t (+ s 1))
                #t))
          (let ((msg (channel-try-recv! ch)))
            (if (not (and (pair? msg)
                          (eq? (car msg) 'DOWN)
                          (or (eq? (list-ref msg 4) 'concurrent_death)
                              (eq? (list-ref msg 4) 'noproc))))
                (atomic-fetch-add! missed-downs 1)
                #t))
          (race-loop (+ iter 1)))
        #t))
  (assert-equal (atomic-ref missed-downs) 0 "0 missed DOWN notifications across 25 concurrent monitor/termination races"))

;; -----------------------------------------------------------------------
;; Group 8: Task Mailbox FIFO Queue Prevents Overwriting Notifications (#726)
;; -----------------------------------------------------------------------
(write-string "--- Group 8: Task Mailbox FIFO Queue (#726) ---\n")
(flush-output-port)

(let* ((watcher (make-task-context))
       (child-1 (make-task-context))
       (child-2 (make-task-context))
       (linked-peer (make-task-context))
       (ref-1 (task-monitor watcher child-1))
       (ref-2 (task-monitor watcher child-2)))
  (task-trap-exit! watcher #t)
  (task-link! watcher linked-peer)

  (assert-true (task-mailbox-empty? watcher) "watcher mailbox initially empty")
  (assert-equal (task-mailbox-size watcher) 0 "watcher mailbox initial size is 0")

  ;; Deliver 4 distinct notifications to watcher without draining in between:
  ;; 1) child-1 DOWN
  ;; 2) io_uring completion result
  ;; 3) child-2 DOWN
  ;; 4) linked-peer EXIT
  (task-handle-termination! child-1 'err_child_1)
  (task-set-handoff! watcher (cons 'io_complete 4096))
  (task-handle-termination! child-2 'err_child_2)
  (task-handle-termination! linked-peer 'peer_crashed)

  (assert-false (task-mailbox-empty? watcher) "watcher mailbox is non-empty")
  (assert-equal (task-mailbox-size watcher) 4 "all 4 notifications preserved in FIFO mailbox without overwrite")

  ;; Peek returns oldest notification (child-1 DOWN) without removing it
  (let ((peeked (task-mailbox-peek watcher)))
    (assert-equal (car peeked) 'DOWN "peeked oldest message is child-1 DOWN")
    (assert-equal (cadr peeked) ref-1 "peeked DOWN ref is ref-1")
    (assert-equal (task-mailbox-size watcher) 4 "mailbox size still 4 after peek"))

  ;; Dequeue in strict FIFO order
  (let ((m1 (task-take-handoff! watcher))
        (m2 (task-take-handoff! watcher))
        (m3 (task-take-handoff! watcher))
        (m4 (task-take-handoff! watcher)))
    (assert-equal (car m1) 'DOWN "1st message is DOWN")
    (assert-equal (cadr m1) ref-1 "1st message is ref-1")
    (assert-equal (list-ref m1 4) 'err_child_1 "1st message reason is 'err_child_1")

    (assert-equal m2 (cons 'io_complete 4096) "2nd message is io_complete 4096")

    (assert-equal (car m3) 'DOWN "3rd message is DOWN")
    (assert-equal (cadr m3) ref-2 "3rd message is ref-2")
    (assert-equal (list-ref m3 4) 'err_child_2 "3rd message reason is 'err_child_2")

    (assert-equal (car m4) 'EXIT "4th message is EXIT")
    (assert-equal (cadr m4) (task-tid linked-peer) "4th message tid is linked-peer")
    (assert-equal (caddr m4) 'peer_crashed "4th message reason is 'peer_crashed")

    (assert-true (task-mailbox-empty? watcher) "watcher mailbox is empty after draining all 4")
    (assert-equal (task-mailbox-size watcher) 0 "watcher mailbox size is 0 after draining")))

;; -----------------------------------------------------------------------
;; Group 6: Clean Task Termination & Automatic Cleanup (#741)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Clean Task Termination & Automatic Cleanup (#741) ---\n")
(flush-output-port)

;; 6.1 Normal exit sends DOWN (normal) to monitor
(let* ((sched (make-work-stealing-scheduler 2 64))
       (observer (make-task-context))
       (target (make-task-context))
       (notify-ch (make-channel 10))
       (m-ref (task-monitor observer target notify-ch)))
  (task-next-run-set! target (lambda () 42))
  (scheduler-spawn! sched target 0)
  (scheduler-run! sched 2)
  (assert-equal (task-state target) 'terminated "target state transitioned to 'terminated on normal exit")
  (let ((down-msg (channel-try-recv! notify-ch)))
    (assert-true (pair? down-msg) "DOWN message delivered to notify-ch on normal exit")
    (assert-equal (car down-msg) 'DOWN "message type is 'DOWN")
    (assert-equal (cadr down-msg) m-ref "monitor ref matches")
    (assert-equal (caddr down-msg) 'process "subject is 'process")
    (assert-equal (cadddr down-msg) (task-tid target) "target TID matches")
    (assert-equal (list-ref down-msg 4) 'normal "DOWN reason is 'normal"))
  (scheduler-stop! sched))

;; 6.2 Normal exit does not kill linked tasks
(let* ((sched (make-work-stealing-scheduler 2 64))
       (peer (make-task-context))
       (target (make-task-context))
       (peer-alive-box (make-atomic-box #f)))
  (task-link! peer target)
  (task-next-run-set! target (lambda () 'finished-cleanly))
  (task-next-run-set! peer (lambda () (atomic-set! peer-alive-box #t)))
  (scheduler-spawn! sched target 0)
  (scheduler-spawn! sched peer 1)
  (scheduler-run! sched 3)
  (assert-equal (task-state target) 'terminated "target terminated cleanly")
  (assert-equal (task-state peer) 'terminated "peer also ran to completion")
  (assert-true (atomic-ref peer-alive-box) "peer was not cascade-killed by normal exit")
  (scheduler-stop! sched))

;; 6.3 Normal coroutine completion sends DOWN (normal)
(let* ((sched (make-work-stealing-scheduler 2 64))
       (observer (make-task-context))
       (target (make-task-context))
       (coro (make-coroutine-context (lambda () (* 6 7))))
       (notify-ch (make-channel 10))
       (m-ref (task-monitor observer target notify-ch)))
  (task-next-run-set! target coro)
  (scheduler-spawn! sched target 0)
  (scheduler-run! sched 2)
  (assert-equal (task-state target) 'terminated "coroutine target state is 'terminated")
  (assert-true (coroutine-terminated? coro) "coro object is terminated")
  (let ((down-msg (channel-try-recv! notify-ch)))
    (assert-true (pair? down-msg) "coroutine DOWN message delivered")
    (assert-equal (car down-msg) 'DOWN "message type is 'DOWN")
    (assert-equal (list-ref down-msg 4) 'normal "coroutine DOWN reason is 'normal"))
  (scheduler-stop! sched)
  (free-coroutine-context! coro))

;; -----------------------------------------------------------------------
;; Test Suite Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Synapse Links & Monitors Summary: ")
(write-string (number->string (vector-ref *tests-passed* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *tests-failed* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *tests-failed* 0) 0)
    (sys-exit 1)
    (sys-exit 0))
