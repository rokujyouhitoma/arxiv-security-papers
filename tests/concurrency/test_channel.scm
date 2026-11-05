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
;; Group 1b: Atomic Task ID (TID) Allocation & Monotonic Invariants (#673)
;; -----------------------------------------------------------------------
(write-string "--- Group 1b: Atomic Task ID Allocation & Monotonic Invariants (#673) ---\n")
(flush-output-port)

(let* ((base-tid (task-next-id-current))
       (tid1 (allocate-task-id!))
       (tid2 (allocate-task-id!))
       (tid3 (allocate-task-id!)))
  (assert-equal tid2 (+ tid1 1) "allocate-task-id! tid2 is tid1 + 1")
  (assert-equal tid3 (+ tid2 1) "allocate-task-id! tid3 is tid2 + 1")
  (assert-equal (task-next-id-current) (+ tid3 1) "task-next-id-current reflects advances"))

;; 0-arg (make-task-context) automatic TID allocation
(let* ((cur (task-next-id-current))
       (auto-t1 (make-task-context))
       (auto-t2 (make-task-context))
       (auto-t3 (make-task-context)))
  (assert-equal (task-tid auto-t1) cur "0-arg make-task-context assigns current TID")
  (assert-equal (task-tid auto-t2) (+ cur 1) "0-arg make-task-context advances TID by 1")
  (assert-equal (task-tid auto-t3) (+ cur 2) "0-arg make-task-context advances TID by 2")
  (assert-true (eq? (task-state auto-t1) 'ready) "auto-t1 has initial state 'ready")
  (assert-equal (task-reductions auto-t1) 4096 "auto-t1 has default reductions 4096"))

;; task-reset-next-id! verification
(task-reset-next-id! 50000)
(assert-equal (task-next-id-current) 50000 "task-reset-next-id! sets next TID to 50000")
(let ((t50k (make-task-context)))
  (assert-equal (task-tid t50k) 50000 "make-task-context after reset receives 50000")
  (assert-equal (task-next-id-current) 50001 "task-next-id-current increments to 50001"))

;; Guard against non-integer reset (CWE-843)
(let ((rejected (guard (exn (else #t))
                  (task-reset-next-id! "invalid-tid")
                  #f)))
  (assert-true rejected "task-reset-next-id! rejects non-integer (CWE-843)"))

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
;; Group 7: Cache-Line Padded Ring Buffer & Unboxed Fast-Path (Issue #680)
;; -----------------------------------------------------------------------
(write-string "--- Group 7: Cache-Line Padded Ring Buffer & Unboxed Fast-Path (#680) ---\n")
(flush-output-port)

;; 7a: <padded-atomic-box> Primitives & Polymorphism
(let ((pbox (make-padded-atomic-box 42)))
  (assert-true (padded-atomic-box? pbox) "make-padded-atomic-box creates valid <padded-atomic-box>")
  (assert-true (not (atomic-box? pbox)) "<padded-atomic-box> is distinct from <atomic-box>")
  (assert-equal (padded-atomic-ref pbox) 42 "padded-atomic-ref returns initial value 42")
  (assert-equal (atomic-ref pbox) 42 "polymorphic atomic-ref works on <padded-atomic-box>")
  (assert-equal (padded-atomic-set! pbox 100) 100 "padded-atomic-set! updates value to 100")
  (assert-equal (atomic-ref pbox) 100 "atomic-ref reflects updated value 100")
  (assert-true (padded-atomic-cas! pbox 100 200) "padded-atomic-cas! succeeds on expected match")
  (assert-equal (atomic-ref pbox) 200 "value is 200 after CAS")
  (assert-true (not (padded-atomic-cas! pbox 999 300)) "padded-atomic-cas! fails on mismatch")
  (assert-equal (atomic-ref pbox) 200 "value remains 200 after failed CAS")
  (assert-equal (padded-atomic-swap! pbox 500) 200 "padded-atomic-swap! returns old value 200")
  (assert-equal (atomic-ref pbox) 500 "value is 500 after swap")
  (assert-equal (padded-atomic-fetch-add! pbox 15) 500 "padded-atomic-fetch-add! returns old value 500")
  (assert-equal (atomic-ref pbox) 515 "value is 515 after fetch-add"))

;; 7b: Channel Unboxed Predicates & Ring Buffer Access
(let ((ch0 (make-channel 0))
      (ch8 (make-channel 8)))
  (assert-true (not (channel-unboxed? ch0)) "capacity=0 channel is not unboxed")
  (assert-true (not (channel-ring-buffer ch0)) "capacity=0 channel ring buffer is #f")
  (assert-true (channel-unboxed? ch8) "capacity=8 channel is unboxed")
  (assert-true (vector? (channel-ring-buffer ch8)) "channel-ring-buffer returns vector for capacity=8")
  (assert-equal (vector-length (channel-ring-buffer ch8)) 8 "ring buffer vector length matches capacity 8")
  (let ((stats (channel-stats ch8)))
    (assert-true (cdr (assq 'unboxed? stats)) "channel-stats includes unboxed? = #t")))

;; 7c: Unboxed Send/Recv Fast-Path Operations
(let ((ch (make-channel 4)))
  (assert-true (channel-empty? ch) "channel is initially empty")
  (assert-true (channel-send-unboxed! ch 111) "channel-send-unboxed! #1 succeeds")
  (assert-true (channel-send-unboxed! ch 222) "channel-send-unboxed! #2 succeeds")
  (assert-true (channel-try-send-unboxed! ch 333) "channel-try-send-unboxed! #3 succeeds")
  (assert-true (channel-try-send-unboxed! ch 444) "channel-try-send-unboxed! #4 succeeds")
  (assert-equal (channel-count ch) 4 "channel count is 4 (full)")
  (assert-true (channel-full? ch) "channel-full? is #t")
  (assert-true (not (channel-try-send-unboxed! ch 555)) "channel-try-send-unboxed! returns #f when ring buffer is full")
  (assert-equal (channel-recv-unboxed! ch) 111 "channel-recv-unboxed! #1 returns 111")
  (assert-equal (channel-try-recv-unboxed! ch) 222 "channel-try-recv-unboxed! #2 returns 222")
  (assert-equal (channel-recv-unboxed! ch) 333 "channel-recv-unboxed! #3 returns 333")
  (assert-equal (channel-recv-unboxed! ch) 444 "channel-recv-unboxed! #4 returns 444")
  (assert-true (channel-empty? ch) "channel is empty after draining")
  (assert-equal (channel-try-recv-unboxed! ch 'empty-sentinel) 'empty-sentinel "channel-try-recv-unboxed! on empty channel returns default sentinel"))

;; 7d: Ring Buffer Multi-Cycle Wraparound & Strict FIFO Ordering
(let ((ch (make-channel 3)))
  (let cycle-loop ((cycle 0) (val 1))
    (if (< cycle 20)
        (begin
          (channel-send-unboxed! ch val)
          (channel-send-unboxed! ch (+ val 1))
          (assert-equal (channel-recv-unboxed! ch) val "wraparound FIFO preserve #1")
          (channel-send-unboxed! ch (+ val 2))
          (assert-equal (channel-recv-unboxed! ch) (+ val 1) "wraparound FIFO preserve #2")
          (assert-equal (channel-recv-unboxed! ch) (+ val 2) "wraparound FIFO preserve #3")
          (cycle-loop (+ cycle 1) (+ val 3)))
        #t))
  (assert-true (channel-empty? ch) "channel is empty after 20 wraparound cycles")
  (assert-equal (channel-count ch) 0 "channel count is 0 after wraparound cycles"))

;; 7e: Unboxed Channel 10,000 Messages Endurance & Backpressure Relief
(let ((ch (make-channel 32))
      (prod-task (make-task-context 701)))
  (let ((res
         (let batch-loop ((b 0) (next-val 1) (total-sum 0) (order-ok #t))
           (if (>= b 100)
               (cons total-sum order-ok)
               (begin
                 ;; Push 100 items into capacity-32 channel (32 buffered, 68 suspended)
                 (let send-loop ((k 0) (v next-val))
                   (if (< k 100)
                       (begin
                         (channel-send-unboxed! ch v prod-task)
                         (send-loop (+ k 1) (+ v 1)))))
                 ;; Receive 100 items
                 (let recv-loop ((k 0) (expected next-val) (s total-sum) (ok order-ok))
                   (if (>= k 100)
                       (batch-loop (+ b 1) (+ next-val 100) s ok)
                       (let ((got (channel-recv-unboxed! ch)))
                         (recv-loop (+ k 1)
                                    (+ expected 1)
                                    (+ s got)
                                    (and ok (= got expected)))))))))))
    (assert-equal (car res) 50005000 "sum of 10,000 unboxed messages 1..10000 is 50005000")
    (assert-true (cdr res) "all 10,000 unboxed messages preserved strict FIFO ordering across backpressure")
    (let ((stats (channel-stats ch)))
      (assert-equal (cdr (assq 'sent stats)) 10000 "unboxed channel-stats sent = 10,000")
      (assert-equal (cdr (assq 'received stats)) 10000 "unboxed channel-stats received = 10,000")
      (assert-equal (cdr (assq 'backpressure-suspends stats)) 6800 "unboxed channel-stats recorded 6,800 suspensions")
      (assert-equal (cdr (assq 'buffered stats)) 0 "unboxed channel-stats buffered = 0 after completion"))))

;; -----------------------------------------------------------------------
;; Group 8: Power-of-Two Bitmask Indexing & Non-Power-of-Two Logical Capacity (#684)
;; -----------------------------------------------------------------------
(write-string "--- Group 8: Power-of-Two Bitmask Indexing & Logical Capacity (#684) ---\n")
(flush-output-port)

;; 8a: Pure utility %round-to-power-of-two verification
(assert-equal (%round-to-power-of-two 0) 1 "%round-to-power-of-two 0 is 1")
(assert-equal (%round-to-power-of-two 1) 1 "%round-to-power-of-two 1 is 1")
(assert-equal (%round-to-power-of-two 2) 2 "%round-to-power-of-two 2 is 2")
(assert-equal (%round-to-power-of-two 3) 4 "%round-to-power-of-two 3 is 4")
(assert-equal (%round-to-power-of-two 4) 4 "%round-to-power-of-two 4 is 4")
(assert-equal (%round-to-power-of-two 5) 8 "%round-to-power-of-two 5 is 8")
(assert-equal (%round-to-power-of-two 7) 8 "%round-to-power-of-two 7 is 8")
(assert-equal (%round-to-power-of-two 8) 8 "%round-to-power-of-two 8 is 8")
(assert-equal (%round-to-power-of-two 9) 16 "%round-to-power-of-two 9 is 16")
(assert-equal (%round-to-power-of-two 1000) 1024 "%round-to-power-of-two 1000 is 1024")
(assert-equal (%round-to-power-of-two 1024) 1024 "%round-to-power-of-two 1024 is 1024")

;; 8b: Channel Ring Mask and Vector Length Verification
(let ((ch0 (make-channel 0))
      (ch8 (make-channel 8))
      (ch3 (make-channel 3)))
  (assert-true (not (channel-ring-mask ch0)) "channel-ring-mask is #f for capacity=0")
  (assert-equal (channel-ring-mask ch8) 7 "channel-ring-mask is 7 for capacity=8")
  (assert-equal (vector-length (channel-ring-buffer ch8)) 8 "ring buffer vector length is 8 for capacity=8")
  (assert-equal (channel-capacity ch3) 3 "logical capacity is 3 for ch3")
  (assert-equal (channel-ring-mask ch3) 3 "channel-ring-mask is 3 (2^2 - 1) for capacity=3")
  (assert-equal (vector-length (channel-ring-buffer ch3)) 4 "physical ring length is rounded up to 4 for capacity=3")

  ;; 8c: Logical Capacity Guarding & Wraparound on Non-Power-of-Two Channel
  (assert-true (channel-try-send! ch3 10) "ch3 send 1 succeeds")
  (assert-true (channel-try-send! ch3 20) "ch3 send 2 succeeds")
  (assert-true (channel-try-send! ch3 30) "ch3 send 3 succeeds")
  (assert-equal (channel-count ch3) 3 "ch3 count is 3 at logical capacity")
  (assert-true (channel-full? ch3) "ch3 is full at logical capacity 3")
  (assert-true (not (channel-try-send! ch3 40)) "ch3 send 4 rejected when count reaches logical capacity 3")
  (assert-equal (channel-recv! ch3) 10 "ch3 recv 1 is 10")
  (assert-true (not (channel-full? ch3)) "ch3 is not full after 1 recv")
  (assert-true (channel-try-send! ch3 40) "ch3 send 4 now succeeds into wrapped slot")
  (assert-equal (channel-recv! ch3) 20 "ch3 recv 2 is 20")
  (assert-equal (channel-recv! ch3) 30 "ch3 recv 3 is 30")
  (assert-equal (channel-recv! ch3) 40 "ch3 recv 4 is 40")
  (assert-true (channel-empty? ch3) "ch3 is empty after draining")
  (assert-equal (channel-count ch3) 0 "ch3 count is 0"))

;; -----------------------------------------------------------------------
;; Group 9: Flat Unboxed Ring Buffer Architecture (Issue #685)
;; -----------------------------------------------------------------------
(write-string "--- Group 9: Flat Unboxed Memory Buffer (Issue #685) ---\n")
(flush-output-port)

(let* ((cap 4)
       (ch (make-channel cap))
       (ring (channel-ring-buffer ch)))
  (assert-true (vector? ring) "flat ring buffer is a vector")
  (assert-equal (vector-length ring) 4 "flat ring buffer length matches rounded capacity")
  ;; Slot elements are direct unboxed sentinel *ring-empty*, NOT atomic-box!
  (assert-true (not (atomic-box? (vector-ref ring 0))) "slot 0 is unboxed, not <atomic-box>")
  (assert-true (not (atomic-box? (vector-ref ring 1))) "slot 1 is unboxed, not <atomic-box>")
  (assert-true (not (atomic-box? (vector-ref ring 2))) "slot 2 is unboxed, not <atomic-box>")
  (assert-true (not (atomic-box? (vector-ref ring 3))) "slot 3 is unboxed, not <atomic-box>")
  (assert-true (eq? (vector-ref ring 0) *ring-empty*) "slot 0 initialized to *ring-empty*")
  (assert-true (eq? (vector-ref ring 1) *ring-empty*) "slot 1 initialized to *ring-empty*")

  ;; Send and verify direct unboxed slot write (no atomic-box wrapper)
  (assert-true (channel-try-send! ch 42) "enqueue into flat ring buffer succeeds")
  (assert-equal (vector-ref ring 0) 42 "slot 0 directly contains payload 42 (unboxed, no wrapper)")
  (assert-true (eq? (vector-ref ring 1) *ring-empty*) "slot 1 remains *ring-empty*")

  ;; Dequeue and verify slot is cleared directly to *ring-empty*
  (assert-equal (channel-recv! ch) 42 "dequeue returns payload 42")
  (assert-true (eq? (vector-ref ring 0) *ring-empty*) "slot 0 reset to *ring-empty* after dequeue"))

;; -----------------------------------------------------------------------
;; Group 10: Zero-Allocation Dequeue & Multiple Values API (Issue #686)
;; -----------------------------------------------------------------------
(write-string "--- Group 10: Zero-Allocation Dequeue & Multiple Values (Issue #686) ---\n")
(flush-output-port)

(let* ((ch (make-channel 4)))
  ;; 10a: channel-try-dequeue-val! returns *ring-empty* when empty
  (assert-true (eq? (channel-try-dequeue-val! ch) *ring-empty*)
               "channel-try-dequeue-val! returns *ring-empty* on empty channel")

  ;; 10b: #f payload preservation (CWE-843 Type Confusion defense)
  (assert-true (channel-try-send! ch #f) "send #f payload succeeds")
  (let ((val (channel-try-dequeue-val! ch)))
    (assert-true (eq? val #f) "channel-try-dequeue-val! returns exact #f payload")
    (assert-true (not (eq? val *ring-empty*)) "#f payload is strictly distinct from *ring-empty*"))

  ;; 10c: Direct channel-recv! zero-allocation hotpath
  (assert-true (channel-send! ch 999) "send 999 succeeds")
  (assert-equal (channel-recv! ch) 999 "channel-recv! returns 999 directly without cons allocation")
  (assert-true (channel-empty? ch) "channel is empty after recv")

  ;; 10d: R7RS Multiple Values API: channel-try-recv-values! on empty channel
  (call-with-values
    (lambda () (channel-try-recv-values! ch))
    (lambda (ok val)
      (assert-true (not ok) "channel-try-recv-values! returns ok=#f when empty")
      (assert-true (not val) "channel-try-recv-values! returns val=#f when empty")))

  ;; 10e: R7RS Multiple Values API: channel-try-recv-values! with data
  (channel-send! ch 'multi-val-payload)
  (call-with-values
    (lambda () (channel-try-recv-values! ch))
    (lambda (ok val)
      (assert-true ok "channel-try-recv-values! returns ok=#t with payload")
      (assert-true (eq? val 'multi-val-payload) "channel-try-recv-values! returns exact payload")))

  ;; 10f: channel-recv-values! blocking form with data
  (channel-send! ch 12345)
  (call-with-values
    (lambda () (channel-recv-values! ch))
    (lambda (ok val)
      (assert-true ok "channel-recv-values! returns ok=#t")
      (assert-equal val 12345 "channel-recv-values! returns exact payload 12345")))
  (assert-true (channel-empty? ch) "channel is empty after all multi-value tests"))

;; -----------------------------------------------------------------------
;; Group 11: SPSC Lamport Lock-Free Ring Buffer (Issue #687)
;; -----------------------------------------------------------------------
(write-string "--- Group 11: SPSC Lamport Lock-Free Ring (Issue #687) ---\n")
(flush-output-port)

(let* ((ch-spsc (make-spsc-channel 4))
       (ch-mpmc (make-channel 4)))
  ;; 11a: Type and Predicate Verification
  (assert-true (channel? ch-spsc) "make-spsc-channel creates valid <channel>")
  (assert-true (channel-spsc? ch-spsc) "channel-spsc? is #t for make-spsc-channel")
  (assert-true (not (channel-spsc? ch-mpmc)) "channel-spsc? is #f for default make-channel")
  (assert-equal (channel-capacity ch-spsc) 4 "ch-spsc has capacity 4")
  (assert-equal (channel-count ch-spsc) 0 "ch-spsc initial count is 0")
  (assert-true (channel-empty? ch-spsc) "ch-spsc is initially empty")
  (assert-true (not (channel-full? ch-spsc)) "ch-spsc is not full initially")

  ;; 11b: Raw SPSC Low-Level Operations (%channel-spsc-try-enqueue!, %channel-spsc-try-dequeue-val!)
  (assert-true (channel-spsc-try-enqueue! ch-spsc 111) "channel-spsc-try-enqueue! 111 succeeds")
  (assert-equal (channel-count ch-spsc) 1 "channel-count is 1 after 1 enqueue")
  (assert-true (not (channel-empty? ch-spsc)) "channel is not empty after 1 enqueue")
  (assert-equal (channel-spsc-try-dequeue-val! ch-spsc) 111 "channel-spsc-try-dequeue-val! returns 111")
  (assert-equal (channel-count ch-spsc) 0 "channel-count is 0 after dequeue")
  (assert-true (channel-empty? ch-spsc) "channel is empty again")
  (assert-true (eq? (channel-spsc-try-dequeue-val! ch-spsc) *ring-empty*)
               "channel-spsc-try-dequeue-val! returns *ring-empty* when empty")

  ;; 11c: Normal channel-send! and channel-recv! zero-LOCK dispatch on SPSC channel
  (assert-true (channel-send! ch-spsc 222) "channel-send! on SPSC channel succeeds")
  (assert-equal (channel-recv! ch-spsc) 222 "channel-recv! on SPSC channel returns 222")
  (assert-true (channel-empty? ch-spsc) "ch-spsc empty after recv")

  ;; 11d: #f payload preservation on SPSC channel (CWE-843 defense)
  (assert-true (channel-try-send! ch-spsc #f) "send #f payload on SPSC channel succeeds")
  (let ((val (channel-recv! ch-spsc)))
    (assert-true (eq? val #f) "recv returns exact #f payload on SPSC channel")
    (assert-true (not (eq? val *ring-empty*)) "#f payload is strictly distinct from *ring-empty*"))

  ;; 11e: Capacity boundary & backpressure on SPSC channel
  (assert-true (channel-send! ch-spsc 10) "spsc fill 1")
  (assert-true (channel-send! ch-spsc 20) "spsc fill 2")
  (assert-true (channel-send! ch-spsc 30) "spsc fill 3")
  (assert-true (channel-send! ch-spsc 40) "spsc fill 4")
  (assert-true (channel-full? ch-spsc) "ch-spsc is full at capacity 4")
  (assert-true (not (channel-try-send! ch-spsc 50)) "try-send rejected when spsc is full")

  (let ((prod (make-task-context 701)))
    (assert-true (eq? (channel-send! ch-spsc 50 prod) 'suspended)
                 "send! suspends prod when spsc is full (backpressure)")
    (assert-true (eq? (task-state prod) 'waiting-channel) "prod transitions to waiting-channel")
    (assert-equal (channel-recv! ch-spsc) 10 "recv frees 1 slot (10)")
    (assert-true (eq? (task-state prod) 'ready) "prod woken to ready on slot freed")
    (assert-equal (channel-recv! ch-spsc) 20 "recv 20")
    (assert-equal (channel-recv! ch-spsc) 30 "recv 30")
    (assert-equal (channel-recv! ch-spsc) 40 "recv 40")
    (assert-equal (channel-recv! ch-spsc) 50 "recv promoted 50 from prod")
    (assert-true (channel-empty? ch-spsc) "ch-spsc empty after draining backpressure queue"))

  ;; 11f: Multiple values API on SPSC channel
  (channel-send! ch-spsc 'spsc-multi)
  (call-with-values
    (lambda () (channel-try-recv-values! ch-spsc))
    (lambda (ok val)
      (assert-true ok "channel-try-recv-values! ok=#t on SPSC")
      (assert-true (eq? val 'spsc-multi) "channel-try-recv-values! payload match on SPSC")))

  ;; 11g: SPSC High-Throughput Burst: 10,000 unboxed messages FIFO verification
  (let ((burst-ch (make-spsc-channel 128))
        (n 10000))
    (let loop ((i 1) (sum-sent 0) (sum-recvd 0))
      (if (<= i n)
          (begin
            (channel-send! burst-ch i)
            (let ((v (channel-recv! burst-ch)))
              (if (not (= v i))
                  (error "SPSC FIFO mismatch" v i))
              (loop (+ i 1) (+ sum-sent i) (+ sum-recvd v))))
          (begin
            (assert-equal sum-sent sum-recvd "10,000 SPSC messages sum matches exactly (Zero Loss)")
            (assert-true (channel-empty? burst-ch) "burst-ch empty after 10,000 messages")
            (let ((st (channel-stats burst-ch)))
              (assert-true (assq 'spsc? st) "channel-stats has spsc? key")
              (assert-true (cdr (assq 'spsc? st)) "channel-stats spsc? is #t")
              (assert-equal (cdr (assq 'sent st)) n "channel-stats sent = 10,000")
              (assert-equal (cdr (assq 'received st)) n "channel-stats received = 10,000")))))))

;; -----------------------------------------------------------------------
;; Group 12: Monotonic Deadline channel-recv-timeout! (Issue #729, Item C6)
;; -----------------------------------------------------------------------
(write-string "--- Group 12: channel-recv-timeout! & Waiter Cleanup (#729) ---\n")
(flush-output-port)

(let ((ch (make-channel 4))
      (rx-task (make-task-context)))
  ;; 12a: Immediate hit when message is already buffered
  (channel-send! ch 'ready-now)
  (let ((res (channel-recv-timeout! ch 50 rx-task)))
    (assert-equal (car res) #t "channel-recv-timeout! immediate hit status is #t")
    (assert-equal (cdr res) 'ready-now "channel-recv-timeout! returns 'ready-now immediately"))

  ;; 12b: Zero-timeout returns (cons #f 'timeout) immediately
  (let ((res0 (channel-recv-timeout! ch 0 rx-task)))
    (assert-equal (car res0) #f "channel-recv-timeout! 0ms status is #f")
    (assert-equal (cdr res0) 'timeout "channel-recv-timeout! with 0ms on empty channel returns 'timeout"))

  ;; 12c: Positive timeout (15ms) expires cleanly and leaves 0 garbage waiters in recv-wait-queue
  (let ((res-exp (channel-recv-timeout! ch 15 rx-task)))
    (assert-equal (car res-exp) #f "channel-recv-timeout! 15ms status is #f")
    (assert-equal (cdr res-exp) 'timeout "channel-recv-timeout! expires after 15ms with 'timeout")
    (assert-equal (task-state rx-task) 'ready "rx-task restored to 'ready after timeout")
    (assert-equal (task-blocked-on rx-task) #f "rx-task blocked-on cleared to #f after timeout")
    (assert-equal (queue-size (channel-recv-wait-queue ch)) 0 "waiter queue pruned to 0 garbage entries after timeout"))

  ;; 12d: Subsequent send after timeout goes to ring buffer (not swallowed by timed-out waiter)
  (channel-send! ch 'post-timeout-msg)
  (let ((res-after (channel-recv-timeout! ch 20 rx-task)))
    (assert-equal (car res-after) #t "subsequent message after timeout status is #t")
    (assert-equal (cdr res-after) 'post-timeout-msg "subsequent message after timeout received cleanly")))

;; -----------------------------------------------------------------------
;; Group 13: Auto-Registration of Created Channels to Current Task (#731)
;; -----------------------------------------------------------------------
(write-string "--- Group 13: Auto-Registration of Channels to Current Task (#731) ---\n")
(flush-output-port)

(let* ((task (make-task-context))
       (prev (%set-current-synapse-task! task)))
  (let ((ch1 (make-channel 2))
        (ch2 (make-spsc-channel 4)))
    ;; Check both channels automatically registered to task
    (let ((owned (task-owned-channels task)))
      (assert-true (memq ch1 owned) "ch1 auto-registered to current task")
      (assert-true (memq ch2 owned) "ch2 auto-registered to current task"))

    ;; Closing ch1 unregisters it from task
    (channel-close! ch1)
    (let ((owned-after-close (task-owned-channels task)))
      (assert-true (not (memq ch1 owned-after-close)) "ch1 unregistered upon close")
      (assert-true (memq ch2 owned-after-close) "ch2 still registered"))

    ;; Poisoning owned channels marks ch2 poisoned
    (task-poison-owned-channels! task 'task-failed #f)
    (assert-true (channel-poisoned? ch2) "ch2 poisoned via task-poison-owned-channels!")
    (assert-equal (length (task-owned-channels task)) 0 "task owned channels cleared after poisoning"))

  (%set-current-synapse-task! prev))

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
