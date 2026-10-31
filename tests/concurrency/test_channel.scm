;;; =======================================================================
;;; Unit & Endurance Test Suite: Linear Ownership Channel & Backpressure (#633)
;;; Conforms to DSN-37 Section 4, 4.3.1, 6.1, 13.4 & Phase 1 Task 1.2
;;; =======================================================================

(load "ulisp/runtime/concurrency/channel.scm")

(define *test-channel-failures* (vector 0))
(define *test-channel-passes* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-channel-failures* 0 (+ (vector-ref *test-channel-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-channel-passes* 0 (+ (vector-ref *test-channel-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-equal actual expected msg)
  (if (not (eqv? actual expected))
      (begin
        (vector-set! *test-channel-failures* 0 (+ (vector-ref *test-channel-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-string " (expected ")
        (if (integer? expected) (write-string (number->string expected)) (write-string "<val>"))
        (write-string ", got ")
        (if (integer? actual) (write-string (number->string actual)) (write-string "<val>"))
        (write-string ")\n")
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-channel-passes* 0 (+ (vector-ref *test-channel-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(write-string "=======================================================\n")
(write-string " Starting Linear Ownership Channel Test Suite (#633)\n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: <channel> & <task-context> Initialization and Predicates
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Initialization, Predicates & DSN-37 Structs ---\n")
(flush-output-port)

(let ((ch0 (make-channel))
      (ch4 (make-channel 4))
      (t1  (make-task-context 101))
      (t2  (make-task-context 102 7))
      (t13 (make-task-context 103 'running 2048 4096 8192 16384 0 4096 #f 9 #f 2 3)))
  (assert-true (channel? ch0) "ch0 satisfies channel?")
  (assert-true (channel? ch4) "ch4 satisfies channel?")
  (assert-true (not (channel? 42)) "fixnum is not channel?")
  (assert-true (not (channel? (vector 1 2 3))) "raw vector is not channel?")
  (assert-equal (channel-capacity ch0) 0 "default make-channel capacity is 0 (rendezvous)")
  (assert-equal (channel-capacity ch4) 4 "make-channel 4 has capacity 4")
  (assert-equal (channel-count ch0) 0 "ch0 initial count is 0")
  (assert-equal (channel-count ch4) 0 "ch4 initial count is 0")
  (assert-true (channel-empty? ch0) "ch0 is initially empty")
  (assert-true (channel-empty? ch4) "ch4 is initially empty")
  (assert-true (channel-full? ch0) "unbuffered ch0 with no waiting receiver is considered full")
  (assert-true (not (channel-full? ch4)) "bounded ch4 (0/4) is not full")
  (assert-true (not (channel-closed? ch0)) "ch0 is initially open")
  (assert-true (lock-free-queue? (channel-message-queue ch4)) "channel-message-queue is a <lock-free-queue>")
  (assert-true (lock-free-queue? (channel-recv-wait-queue ch4)) "channel-recv-wait-queue is a <lock-free-queue>")
  (assert-true (lock-free-queue? (channel-send-wait-queue ch4)) "channel-send-wait-queue is a <lock-free-queue>")

  ;; <task-context> checks
  (assert-true (task-context? t1) "t1 satisfies task-context?")
  (assert-equal (task-tid t1) 101 "t1 tid is 101")
  (assert-true (eq? (task-state t1) 'ready) "t1 initial state is 'ready")
  (assert-equal (task-reductions t1) 4096 "t1 initial reductions is 4096")
  (assert-equal (task-epoch t2) 7 "2-arg make-task-context sets epoch 7")
  (assert-equal (task-tid t13) 103 "13-arg DSN-37 make-task-context sets tid 103")
  (assert-true (eq? (task-state t13) 'running) "13-arg make-task-context sets state 'running")
  (assert-equal (task-reduction-exhaustions t13) 2 "13-arg make-task-context sets reduction-exhaustions 2")
  (assert-equal (task-steals-count t13) 3 "13-arg make-task-context sets steals-count 3"))

;; DSN-37 5-arg make-channel-internal compatibility
(let ((ch-int (make-channel-internal (make-lock-free-queue)
                                     (make-lock-free-queue)
                                     (make-lock-free-queue)
                                     2
                                     (make-atomic-box 0))))
  (assert-true (channel? ch-int) "5-arg make-channel-internal creates valid <channel>")
  (assert-equal (channel-capacity ch-int) 2 "make-channel-internal sets capacity 2"))

;; -----------------------------------------------------------------------
;; Group 2: Rendezvous Synchronous Channels (capacity = 0)
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Rendezvous Synchronous Channels (capacity = 0) ---\n")
(flush-output-port)

;; Case 2a: Receiver arrives first -> suspends -> Sender arrives -> direct handoff & wakeup
(let ((ch (make-channel 0))
      (recv-task (make-task-context 201))
      (send-task (make-task-context 202))
      (woken-log (make-atomic-box '()))
      (payload (cons 'rendezvous-key 'rendezvous-val)))
  (set-channel-wake-hook!
   (lambda (t)
     (atomic-set! woken-log (cons (task-tid t) (atomic-ref woken-log)))))

  ;; Non-blocking try-send / try-recv on empty rendezvous channel must return #f
  (assert-true (not (channel-try-send! ch 'nope)) "channel-try-send! on capacity=0 with no receiver returns #f")
  (assert-true (eq? (channel-try-recv! ch 'empty) 'empty) "channel-try-recv! on capacity=0 with no sender returns 'empty")

  ;; Receiver calls channel-recv! first -> suspends
  (let ((r1 (channel-recv! ch recv-task)))
    (assert-true (eq? r1 'suspended) "channel-recv! on capacity=0 with no sender returns 'suspended")
    (assert-true (eq? (task-state recv-task) 'waiting-channel) "recv-task transitions to 'waiting-channel")
    (assert-true (eq? (task-blocked-on recv-task) ch) "recv-task blocked-on points to ch")
    (assert-true (not (channel-full? ch)) "capacity=0 channel with waiting receiver is ready to accept send"))

  ;; Sender calls channel-send! -> directly hands off payload and wakes recv-task
  (let ((s1 (channel-send! ch payload send-task)))
    (assert-true (eq? s1 #t) "channel-send! succeeds immediately when receiver is waiting")
    (assert-true (eq? (task-state recv-task) 'ready) "recv-task is woken back to 'ready")
    (assert-true (eq? (task-blocked-on recv-task) #f) "recv-task blocked-on is cleared to #f")
    (assert-equal (car (atomic-ref woken-log)) 201 "wake-hook was invoked with recv-task (tid 201)")
    (assert-true (task-has-handoff? recv-task) "recv-task has direct handoff payload ready")
    (let ((transferred (task-take-handoff! recv-task)))
      (assert-true (eq? transferred payload) "zero-copy Move: transferred object is eq? to original payload")
      (assert-true (not (task-has-handoff? recv-task)) "CWE-401 mitigation: handoff slot is cleared after task-take-handoff!")))

  (set-channel-wake-hook! #f))

;; Case 2b: Sender arrives first -> suspends -> Receiver arrives -> direct handoff & wakeup
(let ((ch (make-channel 0))
      (send-task (make-task-context 203))
      (recv-task (make-task-context 204))
      (woken-tid (make-atomic-box 0))
      (payload (vector 'zero-copy 10 20 30)))
  ;; Sender calls channel-send! first -> suspends
  (let ((s1 (channel-send! ch payload send-task)))
    (assert-true (eq? s1 'suspended) "channel-send! on capacity=0 with no receiver returns 'suspended")
    (assert-true (eq? (task-state send-task) 'waiting-channel) "send-task transitions to 'waiting-channel")
    (assert-true (eq? (task-blocked-on send-task) ch) "send-task blocked-on points to ch"))

  ;; Receiver calls channel-recv! with explicit wake-hook -> receives payload and wakes send-task
  (let ((received (channel-recv! ch recv-task (lambda (t) (atomic-set! woken-tid (task-tid t))))))
    (assert-true (eq? received payload) "zero-copy Move: receiver obtains exact payload pointer (eq?) from suspended sender")
    (assert-true (eq? (task-state send-task) 'ready) "send-task is woken back to 'ready")
    (assert-true (eq? (task-blocked-on send-task) #f) "send-task blocked-on is cleared to #f")
    (assert-equal (atomic-ref woken-tid) 203 "explicit wake-hook was invoked for send-task (tid 203)")))

;; -----------------------------------------------------------------------
;; Group 3: Bounded Buffered Channels & Deterministic Backpressure (4.3.1)
;; -----------------------------------------------------------------------
(write-string "--- Group 3: Bounded Channels & Backpressure Relief ---\n")
(flush-output-port)

(let ((ch (make-channel 3))
      (prod-1 (make-task-context 301))
      (prod-2 (make-task-context 302))
      (woken-order (make-atomic-box '())))
  (set-channel-wake-hook!
   (lambda (t)
     (atomic-set! woken-order (cons (task-tid t) (atomic-ref woken-order)))))

  ;; Fill bounded buffer of capacity 3
  (assert-true (eq? (channel-send! ch 100 prod-1) #t) "send #1 (100) buffered without suspending")
  (assert-true (eq? (channel-send! ch 200 prod-1) #t) "send #2 (200) buffered without suspending")
  (assert-true (eq? (channel-send! ch 300 prod-1) #t) "send #3 (300) buffered without suspending")
  (assert-equal (channel-count ch) 3 "channel count is 3 (at capacity)")
  (assert-true (channel-full? ch) "channel-full? is #t at capacity 3/3")
  (assert-true (not (channel-try-send! ch 999)) "channel-try-send! returns #f when bounded buffer is full")

  ;; 4th and 5th sends trigger deterministic backpressure suspension!
  (assert-true (eq? (channel-send! ch 400 prod-1) 'suspended)
               "Backpressure #1: send #4 (400) suspends prod-1 when buffer is full (3/3)")
  (assert-true (eq? (task-state prod-1) 'waiting-channel) "prod-1 state is 'waiting-channel")
  (assert-true (eq? (task-blocked-on prod-1) ch) "prod-1 blocked-on is ch")

  (assert-true (eq? (channel-send! ch 500 prod-2) 'suspended)
               "Backpressure #2: send #5 (500) suspends prod-2 when buffer is full (3/3)")
  (assert-true (eq? (task-state prod-2) 'waiting-channel) "prod-2 state is 'waiting-channel")

  ;; First receive (100) frees 1 slot -> promotes prod-1's 400 into buffer & wakes prod-1!
  (let ((v1 (channel-recv! ch)))
    (assert-equal v1 100 "recv #1 returns 100")
    (assert-true (eq? (task-state prod-1) 'ready) "Backpressure relief #1: prod-1 woken to 'ready")
    (assert-true (eq? (task-blocked-on prod-1) #f) "prod-1 blocked-on cleared to #f")
    (assert-true (eq? (task-state prod-2) 'waiting-channel) "prod-2 still waiting in send-wait-queue")
    (assert-equal (channel-count ch) 3 "buffer remains at capacity 3 after promoting prod-1's message"))

  ;; Second receive (200) promotes prod-2's 500 into buffer & wakes prod-2!
  (let ((v2 (channel-recv! ch)))
    (assert-equal v2 200 "recv #2 returns 200")
    (assert-true (eq? (task-state prod-2) 'ready) "Backpressure relief #2: prod-2 woken to 'ready")
    (assert-equal (channel-count ch) 3 "buffer remains at capacity 3 after promoting prod-2's message"))

  ;; Drain remaining 3 messages (300, 400, 500)
  (assert-equal (channel-recv! ch) 300 "recv #3 returns 300")
  (assert-equal (channel-recv! ch) 400 "recv #4 returns promoted 400 from prod-1")
  (assert-equal (channel-recv! ch) 500 "recv #5 returns promoted 500 from prod-2")
  (assert-true (channel-empty? ch) "channel is empty after draining all 5 messages")
  (let ((ordered (reverse (atomic-ref woken-order))))
    (assert-equal (length ordered) 2 "both suspended producers were woken in FIFO order")
    (assert-equal (car ordered) 301 "prod-1 (tid 301) woken first")
    (assert-equal (cadr ordered) 302 "prod-2 (tid 302) woken second"))

  (set-channel-wake-hook! #f))

;; -----------------------------------------------------------------------
;; Group 4: Zero-Copy Move, #f Payloads, Broadcast Deep-Copy & Epoch Gate
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Zero-Copy Move, Broadcast Deep-Copy & Epoch Gate ---\n")
(flush-output-port)

;; 4a: Zero-copy pointer identity on bounded channel & #f payload distinction
(let ((ch (make-channel 2))
      (obj (vector 'linear-owned (cons 1 2))))
  (channel-send! ch obj)
  (channel-send! ch #f)
  (let ((r1 (channel-recv! ch))
        (st2 (channel-try-recv-with-status! ch))
        (st3 (channel-try-recv-with-status! ch)))
    (assert-true (eq? r1 obj) "bounded channel preserves exact pointer identity (eq?) for zero-copy Move")
    (assert-true (and (car st2) (eq? (cdr st2) #f))
                 "channel-try-recv-with-status! distinguishes #f payload (#t . #f)")
    (assert-true (and (not (car st3)) (eq? (cdr st3) #f))
                 "channel-try-recv-with-status! reports empty channel as (#f . #f)")))

;; 4b: broadcast-send! performs deep copy across multiple channels (DSN-37 Section 4.2)
(let* ((ch-a (make-channel 2))
       (ch-b (make-channel 2))
       (inner-vec (vector 10 20))
       (inner-lst (list 'x 'y))
       (orig (cons inner-vec inner-lst)))
  (assert-equal (broadcast-send! (list ch-a ch-b) orig) 2 "broadcast-send! delivers to 2 channels")
  (let* ((copy-a (channel-recv! ch-a))
         (copy-b (channel-recv! ch-b))
         (vec-a (car copy-a))
         (vec-b (car copy-b)))
    (assert-equal (vector-ref vec-a 0) 10 "copy-a nested vector[0] is 10")
    (assert-equal (vector-ref vec-a 1) 20 "copy-a nested vector[1] is 20")
    (assert-true (eq? (car (cdr copy-a)) 'x) "copy-a nested list car is 'x")
    (assert-equal (vector-ref vec-b 0) 10 "copy-b nested vector[0] is 10")
    (assert-true (not (eq? copy-a orig)) "copy-a is a distinct deep-copied pair (not eq? to orig)")
    (assert-true (not (eq? copy-b orig)) "copy-b is a distinct deep-copied pair (not eq? to orig)")
    (assert-true (not (eq? copy-a copy-b)) "copy-a and copy-b do not share outer pair pointer")
    (assert-true (not (eq? vec-a vec-b)) "copy-a and copy-b do not share nested vector pointer")
    ;; Mutating copy-a's nested vector must NOT affect orig or copy-b!
    (vector-set! vec-a 0 999)
    (assert-equal (vector-ref inner-vec 0) 10 "mutating copy-a does not taint orig (Shared-Nothing)")
    (assert-equal (vector-ref vec-b 0) 10 "mutating copy-a does not taint copy-b (Shared-Nothing)")))

;; 4c: Generation Gate (DSN-37 Section 8.3) skips stale epoch tasks in wait queue
(let ((ch (make-channel 0))
      (stale-recv (make-task-context 401 1))
      (valid-recv (make-task-context 402 2)))
  ;; Only epoch == 2 is valid
  (set-channel-epoch-validator! (lambda (t) (= (task-epoch t) 2)))
  (channel-recv! ch stale-recv)
  (channel-recv! ch valid-recv)
  (channel-send! ch 'epoch-checked-msg)
  (assert-true (eq? (task-state stale-recv) 'terminated)
               "Generation Gate transitions stale epoch task (epoch 1) to 'terminated")
  (assert-true (not (task-has-handoff? stale-recv))
               "stale epoch task did not consume the message")
  (assert-true (eq? (task-state valid-recv) 'ready)
               "valid epoch task (epoch 2) was woken to 'ready")
  (assert-true (eq? (task-take-handoff! valid-recv) 'epoch-checked-msg)
               "valid epoch task received 'epoch-checked-msg")
  (set-channel-epoch-validator! #f))

;; -----------------------------------------------------------------------
;; Group 5: 10,000 Messages Endurance Stress Test & Channel Telemetry
;; -----------------------------------------------------------------------
(write-string "--- Group 5: 10,000 Messages Endurance Stress & Telemetry ---\n")
(flush-output-port)

(let ((ch (make-channel 64))
      (prod-task (make-task-context 501)))
  ;; Send & receive 10,000 messages in 100 batches of 100 (exceeding capacity 64 every batch
  ;; so 36 sends per batch trigger backpressure suspension and promotion!)
  (let ((res
         (let batch-loop ((b 0) (next-val 1) (total-sum 0) (order-ok #t))
           (if (>= b 100)
               (cons total-sum order-ok)
               (begin
                 ;; Push 100 items into capacity-64 channel (first 64 buffered, next 36 suspended)
                 (let send-loop ((k 0) (v next-val) (target ch))
                   (if (< k 100)
                       (begin
                         (channel-send! target v prod-task)
                         (send-loop (+ k 1) (+ v 1) target))))
                 ;; Receive all 100 items, automatically promoting the 36 suspended sends
                 (let recv-loop ((k 0) (expected next-val) (s total-sum) (ok order-ok))
                   (if (>= k 100)
                       (batch-loop (+ b 1) (+ next-val 100) s ok)
                       (let ((got (channel-recv! ch)))
                         (recv-loop (+ k 1)
                                    (+ expected 1)
                                    (+ s got)
                                    (and ok (= got expected)))))))))))
    (assert-equal (car res) 50005000 "sum of 10,000 transferred messages 1..10000 is 50005000")
    (assert-true (cdr res) "all 10,000 messages preserved strict FIFO ordering across backpressure promotions")
    (let ((stats (channel-stats ch)))
      (assert-equal (cdr (assq 'sent stats)) 10000 "channel-stats sent = 10,000")
      (assert-equal (cdr (assq 'received stats)) 10000 "channel-stats received = 10,000")
      (assert-equal (cdr (assq 'backpressure-suspends stats)) 3600 "channel-stats recorded 3,600 backpressure suspensions")
      (assert-equal (cdr (assq 'buffered stats)) 0 "channel-stats buffered = 0 after completion"))))

;; -----------------------------------------------------------------------
;; Group 6: Channel Close & Security Guard Verification (CWE-843 / CWE-20)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Channel Close & Security Guards (CWE-843 / CWE-20) ---\n")
(flush-output-port)

(let ((ch (make-channel 2))
      (waiting-r (make-task-context 601)))
  (channel-recv! ch waiting-r)
  (assert-true (eq? (task-state waiting-r) 'waiting-channel) "waiting-r is suspended on ch")
  (assert-true (channel-close! ch) "channel-close! succeeds")
  (assert-true (channel-closed? ch) "channel-closed? is #t after close")
  (assert-true (eq? (task-state waiting-r) 'ready) "channel-close! wakes waiting receiver task")
  (assert-true (eq? (channel-recv! ch) 'closed) "channel-recv! on closed empty channel returns 'closed"))

(let ((caught-neg-cap
       (guard (exn (#t #t))
         (make-channel -1)
         #f))
      (caught-huge-cap
       (guard (exn (#t #t))
         (make-channel 99999999)
         #f))
      (caught-bad-send
       (guard (exn (#t #t))
         (channel-send! 'not-a-channel 1)
         #f))
      (caught-bad-task
       (guard (exn (#t #t))
         (channel-send! (make-channel 0) 1 'not-a-task)
         #f))
      (caught-closed-send
       (guard (exn (#t #t))
         (let ((c (make-channel 1)))
           (channel-close! c)
           (channel-send! c 42))
         #f)))
  (assert-true caught-neg-cap "make-channel rejects negative capacity (CWE-20 mitigation)")
  (assert-true caught-huge-cap "make-channel rejects oversized capacity > *channel-max-capacity* (CWE-400 mitigation)")
  (assert-true caught-bad-send "channel-send! rejects non-channel object (CWE-843 mitigation)")
  (assert-true caught-bad-task "channel-send! rejects non-task-context argument (CWE-843 mitigation)")
  (assert-true caught-closed-send "channel-send! rejects sending on a closed channel"))

;; -----------------------------------------------------------------------
;; Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Linear Ownership Channel Test Summary: ")
(write-string (number->string (vector-ref *test-channel-passes* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *test-channel-failures* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *test-channel-failures* 0) 0)
    (error "test_channel: one or more assertions failed" (vector-ref *test-channel-failures* 0)))
