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
