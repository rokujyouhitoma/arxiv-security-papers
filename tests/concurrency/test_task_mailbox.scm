;;; =======================================================================
;;; ULisp Concurrency Test: Bounded 2-List FIFO Task Mailbox (Issue #750)
;;; Conforms to DSN-37 Section 8.4 & CWE-400 Mitigation Specifications
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
;; Minimal Test Harness
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
(write-string " Starting Task Mailbox Bounded FIFO Test Suite (#750)\n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: Basic FIFO Operations & O(1) Scalability
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Basic FIFO Operations & O(1) Scalability ---\n")
(flush-output-port)

(let ((t (make-task-context)))
  (assert-true (task-mailbox-empty? t) "mailbox is initially empty")
  (assert-equal (task-mailbox-size t) 0 "initial size is 0")
  (assert-false (task-has-handoff? t) "task-has-handoff? is #f initially")
  (assert-equal (task-mailbox-peek t) #f "peek returns #f on empty mailbox")

  ;; Single item enqueue and dequeue
  (assert-equal (task-mailbox-enqueue! t 'msg-1) 'msg-1 "enqueue returns val")
  (assert-false (task-mailbox-empty? t) "mailbox not empty after enqueue")
  (assert-equal (task-mailbox-size t) 1 "size is 1")
  (assert-true (task-has-handoff? t) "task-has-handoff? is #t")
  (assert-equal (task-mailbox-peek t) 'msg-1 "peek returns msg-1")
  (assert-equal (task-mailbox-size t) 1 "peek does not consume")

  (assert-equal (task-mailbox-dequeue! t) 'msg-1 "dequeue returns msg-1")
  (assert-true (task-mailbox-empty? t) "mailbox is empty after dequeue")
  (assert-equal (task-mailbox-size t) 0 "size is 0 after dequeue")
  (assert-equal (task-mailbox-dequeue! t 'none) 'none "dequeue empty returns empty-default")

  ;; Bulk enqueue of 500 items to verify O(1) batched queue behavior
  (let loop ((i 1))
    (if (<= i 500)
        (begin
          (task-mailbox-enqueue! t i)
          (loop (+ i 1)))))

  (assert-equal (task-mailbox-size t) 500 "size is 500 after 500 enqueues")
  (assert-equal (task-mailbox-peek t) 1 "peek returns first item (1)")

  ;; Verify strict FIFO draining
  (let drain-loop ((expected 1) (all-matched #t))
    (if (> expected 500)
        (assert-true all-matched "all 500 items drained in strict FIFO order")
        (let ((val (task-mailbox-dequeue! t)))
          (drain-loop (+ expected 1) (and all-matched (equal? val expected))))))

  (assert-true (task-mailbox-empty? t) "mailbox is empty after draining 500 items")
  (assert-equal (task-mailbox-size t) 0 "size is 0 after draining 500 items"))

;; -----------------------------------------------------------------------
;; Group 2: Mailbox Capacity & CWE-400 Mitigation (Reject Policy)
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Mailbox Capacity & CWE-400 Mitigation (Reject) ---\n")
(flush-output-port)

(let ((t (make-task-context)))
  (assert-equal (task-mailbox-capacity t) 1024 "default capacity is 1024")
  (assert-equal (task-mailbox-policy t) 'reject "default policy is 'reject")
  (assert-equal (task-mailbox-dropped-count t) 0 "initial dropped count is 0")

  ;; Set small custom capacity for testing
  (task-mailbox-capacity-set! t 3)
  (assert-equal (task-mailbox-capacity t) 3 "capacity updated to 3")

  ;; Fill to capacity
  (assert-true (task-mailbox-try-enqueue! t 'a) "try-enqueue item 1 succeeds")
  (assert-true (task-mailbox-try-enqueue! t 'b) "try-enqueue item 2 succeeds")
  (assert-true (task-mailbox-try-enqueue! t 'c) "try-enqueue item 3 succeeds")
  (assert-equal (task-mailbox-size t) 3 "mailbox is full at capacity 3")

  ;; 4th item should be rejected under 'reject policy
  (assert-false (task-mailbox-try-enqueue! t 'd) "try-enqueue rejected when full")
  (assert-equal (task-mailbox-size t) 3 "size remains 3 after rejection")

  ;; task-mailbox-enqueue! should raise an error under 'reject policy
  (let ((raised-error (guard (exn (else #t))
                        (task-mailbox-enqueue! t 'e)
                        #f)))
    (assert-true raised-error "task-mailbox-enqueue! raises error on overflow (CWE-400)"))

  ;; Dequeue 1 item; capacity frees up
  (assert-equal (task-mailbox-dequeue! t) 'a "dequeued 'a")
  (assert-equal (task-mailbox-size t) 2 "size reduced to 2")
  (assert-true (task-mailbox-try-enqueue! t 'd) "try-enqueue succeeds after space freed")
  (assert-equal (task-mailbox-size t) 3 "size back to 3")

  ;; Drain remaining
  (assert-equal (task-mailbox-dequeue! t) 'b "dequeued 'b")
  (assert-equal (task-mailbox-dequeue! t) 'c "dequeued 'c")
  (assert-equal (task-mailbox-dequeue! t) 'd "dequeued 'd")
  (assert-true (task-mailbox-empty? t) "mailbox empty after draining"))

;; -----------------------------------------------------------------------
;; Group 3: Drop-Oldest Policy
;; -----------------------------------------------------------------------
(write-string "--- Group 3: Drop-Oldest Policy ---\n")
(flush-output-port)

(let ((t (make-task-context)))
  (task-mailbox-capacity-set! t 3)
  (task-mailbox-policy-set! t 'drop-oldest)
  (assert-equal (task-mailbox-policy t) 'drop-oldest "policy is drop-oldest")

  (task-mailbox-enqueue! t 10)
  (task-mailbox-enqueue! t 20)
  (task-mailbox-enqueue! t 30)
  (assert-equal (task-mailbox-size t) 3 "size is 3")

  ;; Enqueue 4th item: 10 should be dropped, 40 added
  (task-mailbox-enqueue! t 40)
  (assert-equal (task-mailbox-size t) 3 "size remains at capacity 3")
  (assert-equal (task-mailbox-dropped-count t) 1 "dropped count is 1")

  ;; Enqueue 5th item: 20 should be dropped, 50 added
  (task-mailbox-enqueue! t 50)
  (assert-equal (task-mailbox-size t) 3 "size remains at capacity 3")
  (assert-equal (task-mailbox-dropped-count t) 2 "dropped count is 2")

  ;; Draining should yield 30, 40, 50
  (assert-equal (task-mailbox-dequeue! t) 30 "first remaining item is 30")
  (assert-equal (task-mailbox-dequeue! t) 40 "second remaining item is 40")
  (assert-equal (task-mailbox-dequeue! t) 50 "third remaining item is 50")
  (assert-true (task-mailbox-empty? t) "mailbox is empty"))

;; -----------------------------------------------------------------------
;; Group 4: Drop-Newest Policy
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Drop-Newest Policy ---\n")
(flush-output-port)

(let ((t (make-task-context)))
  (task-mailbox-capacity-set! t 3)
  (task-mailbox-policy-set! t 'drop-newest)
  (assert-equal (task-mailbox-policy t) 'drop-newest "policy is drop-newest")

  (task-mailbox-enqueue! t 100)
  (task-mailbox-enqueue! t 200)
  (task-mailbox-enqueue! t 300)
  (assert-equal (task-mailbox-size t) 3 "size is 3")

  ;; Enqueue 4th item: should be dropped, existing 100, 200, 300 kept
  (task-mailbox-enqueue! t 400)
  (assert-equal (task-mailbox-size t) 3 "size remains 3")
  (assert-equal (task-mailbox-dropped-count t) 1 "dropped count is 1")

  ;; Draining should yield 100, 200, 300
  (assert-equal (task-mailbox-dequeue! t) 100 "1st item is 100")
  (assert-equal (task-mailbox-dequeue! t) 200 "2nd item is 200")
  (assert-equal (task-mailbox-dequeue! t) 300 "3rd item is 300")
  (assert-true (task-mailbox-empty? t) "mailbox empty"))

;; -----------------------------------------------------------------------
;; Group 5: High-Priority Critical System Signal Protection
;; -----------------------------------------------------------------------
(write-string "--- Group 5: High-Priority Critical System Signal Protection ---\n")
(flush-output-port)

(let ((t (make-task-context)))
  (task-mailbox-capacity-set! t 2)
  (task-mailbox-policy-set! t 'reject)

  ;; Fill to capacity with normal user messages
  (task-mailbox-enqueue! t 'user-msg-1)
  (task-mailbox-enqueue! t 'user-msg-2)
  (assert-equal (task-mailbox-size t) 2 "mailbox full of user messages")

  ;; Normal user message is rejected
  (assert-false (task-mailbox-try-enqueue! t 'user-msg-3) "normal message rejected")

  ;; Critical signals MUST bypass normal capacity and be delivered safely
  (let ((down-sig (list 'DOWN 999 'process 42 'crash))
        (exit-sig (list 'EXIT 42 'killed))
        (poison-sig (cons 'poisoned 'shutdown))
        (io-sig (cons 'io_complete 8192)))
    (assert-equal (task-set-handoff! t down-sig) down-sig "DOWN signal delivered past capacity")
    (assert-equal (task-set-handoff! t exit-sig) exit-sig "EXIT signal delivered past capacity")
    (assert-equal (task-set-handoff! t poison-sig) poison-sig "poisoned signal delivered past capacity")
    (assert-equal (task-set-handoff! t io-sig) io-sig "io_complete signal delivered past capacity")

    (assert-equal (task-mailbox-size t) 6 "all 4 critical signals accommodated without drop")

    ;; Verify draining preserves user messages and critical signals in FIFO order
    (assert-equal (task-mailbox-dequeue! t) 'user-msg-1 "item 1 is user-msg-1")
    (assert-equal (task-mailbox-dequeue! t) 'user-msg-2 "item 2 is user-msg-2")
    (assert-equal (task-mailbox-dequeue! t) down-sig "item 3 is DOWN signal")
    (assert-equal (task-mailbox-dequeue! t) exit-sig "item 4 is EXIT signal")
    (assert-equal (task-mailbox-dequeue! t) poison-sig "item 5 is poisoned signal")
    (assert-equal (task-mailbox-dequeue! t) io-sig "item 6 is io_complete signal")
    (assert-true (task-mailbox-empty? t) "mailbox drained completely")))

;; -----------------------------------------------------------------------
;; Group 6: Backward Compatibility & Legacy Fallback
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Backward Compatibility & Legacy Fallback ---\n")
(flush-output-port)

(let ((t (make-task-context)))
  ;; Manually simulate a legacy single handoff slot: (make-atomic-box (cons #t 'legacy-val))
  (atomic-set! (task-handoff-box t) (cons #t 'legacy-val))

  (assert-true (task-has-handoff? t) "task-has-handoff? detects legacy slot")
  (assert-equal (task-mailbox-size t) 1 "task-mailbox-size is 1 for legacy slot")
  (assert-equal (task-mailbox-peek t) 'legacy-val "peek extracts legacy-val")
  (assert-equal (task-mailbox-dequeue! t) 'legacy-val "dequeue extracts legacy-val")
  (assert-true (task-mailbox-empty? t) "mailbox empty after legacy dequeue")

  ;; Simulate legacy list format: (list (cons #t 1) (cons #t 2))
  (atomic-set! (task-handoff-box t) (list (cons #t 'leg-1) (cons #t 'leg-2)))
  (assert-equal (task-mailbox-size t) 2 "legacy list size is 2")
  (assert-equal (task-mailbox-dequeue! t) 'leg-1 "dequeue item 1 from legacy list")
  (assert-equal (task-mailbox-dequeue! t) 'leg-2 "dequeue item 2 from legacy list")
  (assert-true (task-mailbox-empty? t) "mailbox empty after legacy list"))

;; -----------------------------------------------------------------------
;; Group 7: Error Guards & Parameter Validation (CWE-843)
;; -----------------------------------------------------------------------
(write-string "--- Group 7: Error Guards & Parameter Validation (CWE-843) ---\n")
(flush-output-port)

(assert-true (guard (exn (else #t)) (task-mailbox-size 'not-a-task) #f)
             "task-mailbox-size rejects non-task")
(assert-true (guard (exn (else #t)) (task-mailbox-capacity 'not-a-task) #f)
             "task-mailbox-capacity rejects non-task")
(assert-true (guard (exn (else #t)) (task-mailbox-capacity-set! (make-task-context) 'invalid-cap) #f)
             "task-mailbox-capacity-set! rejects non-integer capacity")
(assert-true (guard (exn (else #t)) (task-mailbox-policy-set! (make-task-context) 'invalid-policy) #f)
             "task-mailbox-policy-set! rejects invalid policy name")

;; -----------------------------------------------------------------------
;; Test Suite Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Task Mailbox Summary: ")
(write-string (number->string (vector-ref *tests-passed* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *tests-failed* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *tests-failed* 0) 0)
    (sys-exit 1)
    (sys-exit 0))

