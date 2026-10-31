;;; =======================================================================
;;; Unit & Endurance Test Suite: Michael-Scott Lock-Free Queue (Issue #632)
;;; Conforms to DSN-37 Section 6.1-6.3, Section 13.4 & Phase 1 Task 1.1
;;; =======================================================================

(load "ulisp/runtime/concurrency/queue.scm")

(define *test-queue-failures* (vector 0))
(define *test-queue-passes* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-queue-failures* 0 (+ (vector-ref *test-queue-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-queue-passes* 0 (+ (vector-ref *test-queue-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-equal actual expected msg)
  (if (not (eqv? actual expected))
      (begin
        (vector-set! *test-queue-failures* 0 (+ (vector-ref *test-queue-failures* 0) 1))
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
        (vector-set! *test-queue-passes* 0 (+ (vector-ref *test-queue-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(write-string "=======================================================\n")
(write-string " Starting Michael-Scott Lock-Free Queue Test Suite (#632)\n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: Queue Initialization, Sentinel Invariance & Empty/#f Semantics
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Initialization, Sentinel Invariance & Empty/#f ---\n")
(flush-output-port)

(let ((q (make-lock-free-queue))
      (n1 (make-queue-node 'single-arg)))
  (assert-true (queue-node? n1) "1-arg make-queue-node creates a <queue-node>")
  (assert-true (eq? (queue-node-value n1) 'single-arg) "1-arg queue-node holds value")
  (assert-true (atomic-box? (queue-node-next n1)) "1-arg queue-node auto-initializes next <atomic-box>")
  (assert-true (eq? (atomic-ref (queue-node-next n1)) #f) "1-arg queue-node next defaults to #f")

  (assert-true (lock-free-queue? q) "q satisfies lock-free-queue?")
  (assert-true (not (lock-free-queue? 42)) "fixnum is not lock-free-queue?")
  (assert-true (not (lock-free-queue? (vector 1 2 3))) "raw vector is not lock-free-queue?")
  (assert-true (atomic-box? (lock-free-queue-head q)) "lock-free-queue-head is an <atomic-box>")
  (assert-true (atomic-box? (lock-free-queue-tail q)) "lock-free-queue-tail is an <atomic-box>")
  (assert-true (eq? (queue-head q) (lock-free-queue-head q)) "queue-head alias matches lock-free-queue-head")
  (assert-true (eq? (queue-tail q) (lock-free-queue-tail q)) "queue-tail alias matches lock-free-queue-tail")

  (let ((h (atomic-ref (lock-free-queue-head q)))
        (t (atomic-ref (lock-free-queue-tail q))))
    (assert-true (queue-node? h) "initial head points to a <queue-node> sentinel")
    (assert-true (eq? h t) "initial head and tail point to the exact same sentinel dummy node")
    (assert-true (eq? (queue-node-value h) #f) "sentinel dummy node has value #f")
    (assert-true (eq? (atomic-ref (queue-node-next h)) #f) "sentinel dummy node next is #f"))

  (assert-true (queue-empty? q) "newly created queue is empty (queue-empty?)")
  (assert-true (lock-free-queue-empty? q) "newly created queue is empty (lock-free-queue-empty?)")
  (assert-equal (queue-size q) 0 "newly created queue has size 0")
  (assert-true (null? (queue->list q)) "queue->list on empty queue returns '()")
  (assert-true (eq? (queue-peek q) #f) "1-arg queue-peek on empty queue returns #f")
  (assert-true (eq? (queue-peek q 'empty) 'empty) "2-arg queue-peek on empty queue returns custom default 'empty")
  (assert-true (eq? (dequeue-lockfree! q) #f) "1-arg dequeue-lockfree! on empty queue returns #f (DSN-37 6.2)")
  (assert-true (eq? (dequeue-lockfree! q 'empty) 'empty) "2-arg dequeue-lockfree! on empty queue returns 'empty")
  (let ((st-empty (dequeue-lockfree-with-status! q)))
    (assert-true (and (pair? st-empty) (eq? (car st-empty) #f) (eq? (cdr st-empty) #f))
                 "dequeue-lockfree-with-status! on empty queue returns (#f . #f)"))

  ;; Distinguish #f payload from empty queue
  (assert-true (enqueue-lockfree! q #f) "enqueue-lockfree! accepts #f as a valid payload")
  (assert-true (not (queue-empty? q)) "queue containing #f payload is not empty")
  (assert-equal (queue-size q) 1 "queue containing #f payload has size 1")
  (assert-true (eq? (queue-peek q 'empty) #f) "2-arg queue-peek returns #f payload (distinct from 'empty)")
  (let ((st-false (dequeue-lockfree-with-status! q)))
    (assert-true (and (pair? st-false) (eq? (car st-false) #t) (eq? (cdr st-false) #f))
                 "dequeue-lockfree-with-status! returns (#t . #f) for #f payload"))
  (assert-true (eq? (dequeue-lockfree! q 'empty) 'empty) "subsequent 2-arg dequeue returns 'empty")
  (assert-true (queue-empty? q) "queue is empty again after dequeuing #f payload"))

;; DSN-37 6.1 2-arg constructor compatibility: (make-lock-free-queue head-box tail-box)
(let* ((dummy (make-queue-node #f (make-atomic-box #f)))
       (q2 (make-lock-free-queue (make-atomic-box dummy) (make-atomic-box dummy))))
  (assert-true (lock-free-queue? q2) "2-arg DSN-37 constructor creates valid <lock-free-queue>")
  (assert-true (queue-enqueue! q2 55) "queue-enqueue! works on 2-arg constructed queue")
  (assert-equal (queue-dequeue! q2) 55 "queue-dequeue! returns 55"))

;; -----------------------------------------------------------------------
;; Group 2: Strict FIFO Ordering, queue->list & queue-stats
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Strict FIFO Ordering, queue->list & queue-stats ---\n")
(flush-output-port)

(let ((q (make-lock-free-queue))
      (p1 (cons 'alpha 'beta))
      (v1 (vector 10 20 30)))
  (assert-true (enqueue-lockfree! q 101) "enqueue 101")
  (assert-true (enqueue-lockfree! q 'sym-payload) "enqueue symbol")
  (assert-true (enqueue-lockfree! q p1) "enqueue pair")
  (assert-true (enqueue-lockfree! q v1) "enqueue vector")
  (assert-true (enqueue-lockfree! q 202) "enqueue 202")
  (assert-equal (queue-size q) 5 "queue size is 5 after 5 enqueues")
  (assert-equal (queue-peek q) 101 "queue-peek returns front element 101 without removing it")

  (let ((lst (queue->list q)))
    (assert-equal (length lst) 5 "queue->list returns 5 elements")
    (assert-equal (car lst) 101 "queue->list element 0 is 101")
    (assert-true (eq? (cadr lst) 'sym-payload) "queue->list element 1 is 'sym-payload"))

  (assert-equal (dequeue-lockfree! q) 101 "FIFO dequeue #1 -> 101")
  (assert-true (eq? (dequeue-lockfree! q) 'sym-payload) "FIFO dequeue #2 -> 'sym-payload")
  (assert-true (eq? (dequeue-lockfree! q) p1) "FIFO dequeue #3 -> exact pair p1")
  (assert-true (eq? (dequeue-lockfree! q) v1) "FIFO dequeue #4 -> exact vector v1")
  (assert-equal (dequeue-lockfree! q) 202 "FIFO dequeue #5 -> 202")
  (assert-true (eq? (dequeue-lockfree! q) #f) "FIFO dequeue #6 -> #f (empty)")
  (assert-equal (queue-size q) 0 "queue size is 0 after draining")

  (let ((stats (queue-stats q)))
    (assert-equal (cdr (assq 'size stats)) 0 "queue-stats size is 0")
    (assert-equal (cdr (assq 'enqueued stats)) 5 "queue-stats enqueued count is 5")
    (assert-equal (cdr (assq 'dequeued stats)) 5 "queue-stats dequeued count is 5")
    (assert-true (eq? (cdr (assq 'has-pool? stats)) #f) "queue-stats has-pool? is #f")))

;; -----------------------------------------------------------------------
;; Group 3: Cooperative Tail Helping (Lagging Tail Recovery)
;; -----------------------------------------------------------------------
(write-string "--- Group 3: Cooperative Tail Helping (Lagging Tail Recovery) ---\n")
(flush-output-port)

;; Case 3a: Enqueue helps advance a lagging tail left behind by a stalled producer
(let* ((q (make-lock-free-queue))
       (dummy (atomic-ref (lock-free-queue-tail q)))
       (half-enqueued-node (make-queue-node 777 (make-atomic-box #f))))
  ;; Simulate Phase 1 of enqueue without Phase 2: link dummy.next -> half-enqueued-node
  ;; while leaving q.tail pointing at dummy.
  (assert-true (atomic-cas! (queue-node-next dummy) #f half-enqueued-node)
               "simulate stalled producer Phase 1: dummy.next linked, q.tail still lagging at dummy")
  (assert-true (eq? (atomic-ref (lock-free-queue-tail q)) dummy)
               "q.tail is confirmed lagging behind dummy.next")

  ;; Now invoke normal enqueue-lockfree! for 888: it must help swing q.tail to
  ;; half-enqueued-node and then append 888 after 777.
  (assert-true (enqueue-lockfree! q 888)
               "enqueue-lockfree! cooperatively advances lagging tail and appends 888")
  (assert-equal (queue-size q) 2 "queue has both 777 and 888")
  (assert-equal (dequeue-lockfree! q) 777 "first dequeue yields 777 from stalled producer")
  (assert-equal (dequeue-lockfree! q) 888 "second dequeue yields 888 from helping producer")
  (assert-true (eq? (dequeue-lockfree! q) #f) "queue is empty after both dequeues"))

;; Case 3b: Dequeue helps advance a lagging tail when head == tail and next != #f
(let* ((q (make-lock-free-queue))
       (dummy (atomic-ref (lock-free-queue-tail q)))
       (stalled-node (make-queue-node 999 (make-atomic-box #f))))
  (assert-true (atomic-cas! (queue-node-next dummy) #f stalled-node)
               "simulate stalled producer Phase 1 on empty queue")
  (assert-true (eq? (atomic-ref (lock-free-queue-head q)) (atomic-ref (lock-free-queue-tail q)))
               "head == tail while head.next is non-#f")
  (assert-true (not (queue-empty? q))
               "queue-empty? helps advance lagging tail and reports non-empty (#f)")
  (assert-equal (dequeue-lockfree! q) 999
                "dequeue-lockfree! helps advance lagging tail and returns 999")
  (assert-true (eq? (dequeue-lockfree! q) #f)
               "queue is empty after dequeuing 999"))

;; -----------------------------------------------------------------------
;; Group 4: Sentinel Node Payload Clearing (CWE-401 Memory Leak Prevention)
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Sentinel Node Payload Clearing (CWE-401) ---\n")
(flush-output-port)

(let ((q (make-lock-free-queue))
      (big-payload (vector 'secret-data 1 2 3 4)))
  (enqueue-lockfree! q big-payload)
  (let* ((old-head (atomic-ref (lock-free-queue-head q)))
         (enqueued-node (atomic-ref (queue-node-next old-head))))
    (assert-true (eq? (queue-node-value enqueued-node) big-payload)
                 "before dequeue, enqueued node holds reference to big-payload")
    (let ((out (dequeue-lockfree! q))
          (new-head (atomic-ref (lock-free-queue-head q))))
      (assert-true (eq? out big-payload) "dequeue returns big-payload")
      (assert-true (eq? new-head enqueued-node)
                   "enqueued-node became the new sentinel dummy node at queue-head")
      (assert-true (eq? (queue-node-value new-head) #f)
                   "CWE-401 mitigation: new sentinel dummy node value is cleared to #f"))))

;; -----------------------------------------------------------------------
;; Group 5: ABA-Safe Stamped Node Pool & 10,000+ Operations Endurance
;; -----------------------------------------------------------------------
(write-string "--- Group 5: ABA-Safe Stamped Node Pool & 10,000 Ops Endurance ---\n")
(flush-output-port)

;; Test fixed-capacity pre-allocated pool & pool-backed queue
(let ((fixed-pool (make-queue-node-pool 8)))
  (assert-true (queue-node-pool? fixed-pool) "fixed-pool satisfies queue-node-pool?")
  (assert-equal (queue-node-pool-capacity fixed-pool) 8 "fixed-pool capacity is 8")
  (assert-equal (queue-node-pool-available fixed-pool) 8 "fixed-pool initially has 8 pre-allocated nodes")
  (let ((q-pooled (make-lock-free-queue fixed-pool)))
    (assert-equal (queue-node-pool-available fixed-pool) 7 "sentinel node acquired 1 node from fixed-pool (7 left)")
    (enqueue-lockfree! q-pooled 'a)
    (assert-equal (queue-node-pool-available fixed-pool) 6 "enqueue acquired 1 node from fixed-pool (6 left)")
    (assert-true (eq? (dequeue-lockfree! q-pooled) 'a) "dequeue returns 'a")
    (assert-equal (queue-node-pool-available fixed-pool) 7 "dequeue released retired sentinel back to fixed-pool (7 left)")
    (assert-true (cdr (assq 'has-pool? (queue-stats q-pooled))) "queue-stats reports has-pool? = #t")))

(let ((q (make-lock-free-queue))
      (pool (make-queue-node-pool)))
  (assert-true (queue-node-pool? pool) "pool satisfies queue-node-pool?")
  (assert-equal (queue-node-pool-stamp pool) 0 "initial pool stamp is 0")

  ;; First pooled enqueue + dequeue retires the initial sentinel node into pool
  (let ((initial-sentinel (atomic-ref (lock-free-queue-head q))))
    (assert-true (enqueue-lockfree/pooled! q pool 'first-item)
                 "enqueue-lockfree/pooled! #1 succeeds")
    (assert-true (eq? (dequeue-lockfree/pooled! q pool) 'first-item)
                 "dequeue-lockfree/pooled! #1 returns 'first-item and frees old sentinel to pool")
    (assert-equal (queue-node-pool-stamp pool) 1
                  "pool generation stamp increments to 1 on pool-free-node!")

    ;; Next pooled allocation must reuse initial-sentinel from the pool and increment stamp to 2
    (let ((reused-node (queue-pool-acquire! pool 'reused-payload)))
      (assert-true (eq? reused-node initial-sentinel)
                   "queue-pool-acquire! recycles the exact retired sentinel <queue-node>")
      (assert-equal (queue-node-pool-stamp pool) 2
                    "pool generation stamp increments to 2 on queue-pool-acquire!")
      (assert-true (eq? (queue-node-value reused-node) 'reused-payload)
                   "recycled node value initialized to 'reused-payload")
      (assert-true (eq? (atomic-ref (queue-node-next reused-node)) #f)
                   "recycled node next box reset to #f")
      ;; Return it to the pool
      (assert-true (queue-pool-release! pool reused-node)
                   "queue-pool-release! returns node to pool")
      (assert-equal (queue-node-pool-stamp pool) 3
                    "pool generation stamp increments to 3")))

  ;; 5,000 standard enqueues followed by 5,000 standard dequeues (10,000 ops)
  (let enq-loop ((i 1) (tag 'std))
    (if (<= i 5000)
        (begin
          (enqueue-lockfree! q i)
          (enq-loop (+ i 1) tag))))
  (assert-equal (queue-size q) 5000 "5,000 elements enqueued via enqueue-lockfree!")

  (let ((res-std
         (let deq-loop ((i 1) (sum 0) (order-ok #t))
           (if (> i 5000)
               (cons sum order-ok)
               (let ((v (dequeue-lockfree! q)))
                 (deq-loop (+ i 1)
                           (+ sum v)
                           (and order-ok (= v i))))))))
    (assert-equal (car res-std) 12502500 "sum of 5,000 dequeued elements is 12502500")
    (assert-true (cdr res-std) "all 5,000 elements dequeued in strict FIFO order 1..5000")
    (assert-true (eq? (dequeue-lockfree! q) #f) "queue is empty after 5,000 dequeues"))

  ;; 5,000 pooled interleaved enqueue/dequeue cycles (10,000 pooled ops)
  (let ((stamp-before (queue-node-pool-stamp pool))
        (res-pooled
         (let pooled-loop ((i 1) (sum 0) (order-ok #t))
           (if (> i 5000)
               (cons sum order-ok)
               (begin
                 (enqueue-lockfree/pooled! q pool i)
                 (let ((v (dequeue-lockfree/pooled! q pool)))
                   (pooled-loop (+ i 1)
                                (+ sum v)
                                (and order-ok (= v i)))))))))
    (assert-equal (car res-pooled) 12502500 "sum of 5,000 pooled enqueue/dequeue cycles is 12502500")
    (assert-true (cdr res-pooled) "all 5,000 pooled cycles preserved exact FIFO values")
    (assert-true (> (queue-node-pool-stamp pool) (+ stamp-before 9999))
                 "64-bit ABA pool stamp advanced by >= 10,000 across 5,000 recycle cycles")))

;; -----------------------------------------------------------------------
;; Group 6: Security Guard Verification (TM-632-01 / CWE-843 Type Confusion)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Security Guard Verification (CWE-843) ---\n")
(flush-output-port)

(let ((caught-enq
       (guard (exn (#t #t))
         (enqueue-lockfree! (vector 1 2) 'x)
         #f))
      (caught-deq
       (guard (exn (#t #t))
         (dequeue-lockfree! 'not-a-queue)
         #f))
      (caught-empty
       (guard (exn (#t #t))
         (queue-empty? 123)
         #f))
      (caught-node
       (guard (exn (#t #t))
         (make-queue-node 'val 'not-an-atomic-box)
         #f))
      (caught-pool
       (guard (exn (#t #t))
         (pool-alloc-node! 'not-a-pool 'val)
         #f)))
  (assert-true caught-enq "enqueue-lockfree! rejects raw vector (CWE-843 mitigation)")
  (assert-true caught-deq "dequeue-lockfree! rejects symbol (CWE-843 mitigation)")
  (assert-true caught-empty "queue-empty? rejects fixnum (CWE-843 mitigation)")
  (assert-true caught-node "make-queue-node rejects non-atomic-box next field (CWE-843 mitigation)")
  (assert-true caught-pool "pool-alloc-node! rejects non-pool argument (CWE-843 mitigation)"))

;; -----------------------------------------------------------------------
;; Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Michael-Scott Queue Test Summary: ")
(write-string (number->string (vector-ref *test-queue-passes* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *test-queue-failures* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *test-queue-failures* 0) 0)
    (error "test_queue: one or more assertions failed" (vector-ref *test-queue-failures* 0)))
