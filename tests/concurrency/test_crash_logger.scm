;;; =======================================================================
;;; Synapse Concurrency: Structured Crash Reporting & Observability Test Suite
;;; Conforms to Issue #670, DSN-37 Section 8.4.6 & Section 14.8 Task 6.5
;;; =======================================================================

(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/arena.scm")
(load "ulisp/runtime/concurrency/boundary.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/links.scm")
(load "ulisp/runtime/concurrency/panic.scm")
(load "ulisp/runtime/concurrency/supervisor.scm")
(load "ulisp/runtime/concurrency/registry.scm")
(load "ulisp/runtime/concurrency/crash_logger.scm")

;; -----------------------------------------------------------------------
;; Minimal Test Harness
;; -----------------------------------------------------------------------

(define *pass-count* (vector 0))
(define *fail-count* (vector 0))

(define (assert-true cond msg)
  (if cond
      (begin
        (vector-set! *pass-count* 0 (+ (vector-ref *pass-count* 0) 1))
        (write-string "PASS: ") (write-string msg) (write-char #\newline))
      (begin
        (vector-set! *fail-count* 0 (+ (vector-ref *fail-count* 0) 1))
        (write-string "FAIL: ") (write-string msg) (write-char #\newline))))

(define (assert-equal actual expected msg)
  (if (equal? actual expected)
      (begin
        (vector-set! *pass-count* 0 (+ (vector-ref *pass-count* 0) 1))
        (write-string "PASS: ") (write-string msg) (write-char #\newline))
      (begin
        (vector-set! *fail-count* 0 (+ (vector-ref *fail-count* 0) 1))
        (write-string "FAIL: ") (write-string msg)
        (write-string " [expected ") (write-string (number->string expected))
        (write-string ", got ") (write-string (number->string actual)) (write-string "]\n"))))

(define (assert-error thunk msg)
  (let ((caught? (vector #f)))
    (guard (ex (else (vector-set! caught? 0 #t)))
      (thunk))
    (if (vector-ref caught? 0)
        (begin
          (vector-set! *pass-count* 0 (+ (vector-ref *pass-count* 0) 1))
          (write-string "PASS: ") (write-string msg) (write-char #\newline))
        (begin
          (vector-set! *fail-count* 0 (+ (vector-ref *fail-count* 0) 1))
          (write-string "FAIL: ") (write-string msg) (write-string " (expected error not raised)\n")))))

(write-string "=======================================================\n")
(write-string " Starting Synapse Crash Reporting Test Suite (#670)\n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: Basic <crash-report> Creation & Field Inspection
;; -----------------------------------------------------------------------
(define (run-group-1!)
  (write-string "--- Group 1: Basic <crash-report> Creation ---\n")
  (flush-output-port)
  (let* ((task (make-task-context))
         (arena (make-task-arena 4096)))
    (task-set-arena! task arena)
    (task-reductions-set! task 150)
    (let ((rep (make-crash-report task 'out_of_fuel '("fuel limit reached") "worker.scm:42" "msg#42" 'worker_1)))
      (assert-true (crash-report? rep) "make-crash-report returns <crash-report>")
      (assert-true (> (crash-report-id rep) 0) "report ID is positive")
      (assert-equal (crash-report-tid rep) (task-tid task) "report TID matches task TID")
      (assert-true (eq? (crash-report-registered-name rep) 'worker_1) "registered-name matches")
      (assert-equal (crash-report-fuel-consumed rep) 150 "fuel-consumed matches task reductions")
      (assert-true (eq? (crash-report-reason rep) 'out_of_fuel) "reason matches")
      (assert-true (string? (crash-report-source-loc rep)) "source-loc is string")
      (assert-true (string? (crash-report-last-msg-summary rep)) "last-msg-summary is string"))

    ;; Integer TID creation
    (let ((rep-tid (make-crash-report 999 'unhandled_exception '() #f #f 'db_actor)))
      (assert-true (crash-report? rep-tid) "direct integer TID creates valid report")
      (assert-equal (crash-report-tid rep-tid) 999 "TID matches 999")
      (assert-true (eq? (crash-report-registered-name rep-tid) 'db_actor) "registered name matches db_actor"))))

(run-group-1!)

;; -----------------------------------------------------------------------
;; Group 2: Lock-Free Non-Blocking Ring Buffer
;; -----------------------------------------------------------------------
(define (run-group-2!)
  (write-string "--- Group 2: Lock-Free Non-Blocking Ring Buffer ---\n")
  (flush-output-port)
  (let ((buf (make-crash-ring-buffer 4)))
    (assert-true (crash-ring-buffer? buf) "make-crash-ring-buffer returns <crash-ring-buffer>")
    (assert-equal (crash-buffer-capacity buf) 4 "capacity is 4")
    (assert-equal (crash-buffer-count buf) 0 "initial count is 0")
    (assert-equal (crash-buffer-dropped buf) 0 "initial dropped count is 0")

    ;; Enqueue 3 items
    (let ((r1 (make-crash-report 1 'reason_a))
          (r2 (make-crash-report 2 'reason_b))
          (r3 (make-crash-report 3 'reason_c)))
      (assert-true (crash-buffer-enqueue! buf r1) "enqueue r1 succeeds")
      (assert-true (crash-buffer-enqueue! buf r2) "enqueue r2 succeeds")
      (assert-true (crash-buffer-enqueue! buf r3) "enqueue r3 succeeds")
      (assert-equal (crash-buffer-count buf) 3 "count is 3"))

    ;; Dequeue 1 item
    (let ((deq-item (crash-buffer-dequeue! buf)))
      (assert-true (crash-report? deq-item) "dequeue returns <crash-report>")
      (assert-equal (crash-report-tid deq-item) 1 "first dequeued item is r1 (FIFO)")
      (assert-equal (crash-buffer-count buf) 2 "count decremented to 2"))

    ;; Fill buffer to capacity (2 items present, add 2 more -> total 4)
    (let ((r4 (make-crash-report 4 'reason_d))
          (r5 (make-crash-report 5 'reason_e)))
      (crash-buffer-enqueue! buf r4)
      (crash-buffer-enqueue! buf r5)
      (assert-equal (crash-buffer-count buf) 4 "buffer reached capacity 4"))

    ;; Overflow enqueue: capacity is 4, adding 6th item causes overwrite/drop
    (let ((r6 (make-crash-report 6 'reason_f)))
      (assert-true (crash-buffer-enqueue! buf r6) "overflow enqueue succeeds without blocking")
      (assert-equal (crash-buffer-dropped buf) 1 "dropped counter incremented to 1"))

    ;; Drain buffer
    (let ((drained (crash-buffer-drain! buf)))
      (assert-equal (length drained) 4 "drain returned remaining 4 reports")
      (assert-equal (crash-buffer-count buf) 0 "buffer count is 0 after drain"))))

(run-group-2!)

;; -----------------------------------------------------------------------
;; Group 3: SASL Formatting & S-Expression Export
;; -----------------------------------------------------------------------
(define (run-group-3!)
  (write-string "--- Group 3: SASL Formatting & S-Expression Export ---\n")
  (flush-output-port)
  (let* ((task (make-task-context))
         (arena (make-task-arena 8192)))
    (task-set-arena! task arena)
    (task-reductions-set! task 500)
    (let ((rep (make-crash-report task 'assertion_violation '("check-bounds failed") "parser.scm:105" "token#88" 'parser_worker)))
      ;; SASL Formatter
      (let ((formatted (format-crash-report rep)))
        (assert-true (string? formatted) "format-crash-report returns string")
        (assert-true (> (string-length formatted) 50) "formatted string is descriptive")
        (assert-true (let loop ((i 0))
                       (if (> (+ i 14) (string-length formatted))
                           #f
                           (if (string=? (substring formatted i (+ i 14)) "=CRASH REPORT=")
                               #t
                               (loop (+ i 1)))))
                     "formatted string starts with SASL header =CRASH REPORT="))

      ;; S-Expression Export
      (let ((sexpr (crash-report->sexpr rep)))
        (assert-true (pair? sexpr) "crash-report->sexpr returns pair")
        (assert-true (eq? (car sexpr) 'crash-report) "car is 'crash-report"))

      ;; A-list Export
      (let ((alist (crash-report->alist rep)))
        (assert-true (pair? alist) "crash-report->alist returns pair")
        (assert-equal (cdr (assq 'reason alist)) 'assertion_violation "alist reason matches")))))

(run-group-3!)

;; -----------------------------------------------------------------------
;; Group 4: Automatic Crash Logging Integration with Panic & Supervisor
;; -----------------------------------------------------------------------
(define (run-group-4!)
  (write-string "--- Group 4: Automatic Integration with Panic & Supervisor ---\n")
  (flush-output-port)
  (let* ((buf (make-crash-ring-buffer 16))
         (task (make-task-context))
         (arena (make-task-arena 2048)))
    (task-set-arena! task arena)
    (synapse-set-current-crash-buffer! buf)
    (synapse-enable-crash-logging!)

    ;; Trigger panic inside task boundary
    (with-synapse-task-boundary task
      (lambda ()
        (synapse-panic! 'custom_panic '("test-details"))))

    ;; Verify crash report was automatically captured
    (assert-equal (crash-buffer-count buf) 1 "crash report automatically captured in buffer")
    (let ((rep (crash-buffer-dequeue! buf)))
      (assert-true (crash-report? rep) "dequeued report is <crash-report>")
      (assert-equal (crash-report-tid rep) (task-tid task) "report TID matches panicked task")
      (assert-true (eq? (crash-report-reason rep) 'custom_panic) "report reason is custom_panic"))

    ;; Test Supervisor integration: simulated child down
    (let* ((cspec (make-child-spec 'monitored_worker (lambda () (make-task-context)) 'permanent))
           (sspec (make-supervisor-spec 'one_for_one 5 1000 (list cspec)))
           (sup (make-supervisor sspec)))
      (supervisor-start! sup)
      (let ((child-task (supervisor-child-task sup 'monitored_worker)))
        (assert-true (task-context? child-task) "supervisor child task exists")
        (let ((child-tid (task-tid child-task)))
          ;; Trigger supervisor-handle-child-down! with panic reason
          (supervisor-handle-child-down! sup child-tid 'child_panicked)
          ;; Verify crash report was enqueued
          (assert-equal (crash-buffer-count buf) 1 "supervisor child crash captured in buffer")
          (let ((sup-rep (crash-buffer-dequeue! buf)))
            (assert-equal (crash-report-tid sup-rep) child-tid "supervisor report TID matches child TID")
            (assert-true (eq? (crash-report-reason sup-rep) 'child_panicked) "supervisor report reason is child_panicked"))))
      (supervisor-stop! sup))

    (synapse-disable-crash-logging!)))

(run-group-4!)

;; -----------------------------------------------------------------------
;; Group 5: High-Throughput Burst & Bounded Memory (CWE-400)
;; -----------------------------------------------------------------------
(define (run-group-5!)
  (write-string "--- Group 5: High-Throughput Burst & Bounded Memory ---\n")
  (flush-output-port)
  (let* ((buf (make-crash-ring-buffer 100))
         (n 1000))
    (synapse-set-current-crash-buffer! buf)
    (synapse-reset-crash-metrics!)

    ;; Burst 1,000 crashes through synapse-log-task-crash!
    (let loop ((i 0))
      (if (< i n)
          (let ((rsn (if (= (modulo i 2) 0) 'even_crash 'odd_crash)))
            (synapse-log-task-crash! (+ i 1) rsn)
            (loop (+ i 1)))
          #t))

    ;; Verify buffer count is bounded at capacity (100)
    (assert-equal (crash-buffer-count buf) 100 "buffer count bounded at capacity 100 (CWE-400)")
    ;; Dropped count must be exactly 1000 - 100 = 900
    (assert-equal (crash-buffer-dropped buf) 900 "dropped count exactly 900")

    ;; Verify metrics
    (let* ((m (synapse-crash-metrics))
           (total (cdr (assq 'total m))))
      (assert-equal total 1000 "metrics total crashes recorded 1,000")
      (let* ((by-r (cdr (assq 'by-reason m)))
             (even-cnt (cdr (assq 'even_crash by-r)))
             (odd-cnt (cdr (assq 'odd_crash by-r))))
        (assert-equal even-cnt 500 "even_crash count is 500")
        (assert-equal odd-cnt 500 "odd_crash count is 500")))

    (synapse-reset-crash-metrics!)
    (assert-equal (cdr (assq 'total (synapse-crash-metrics))) 0 "metrics reset successfully")))

(run-group-5!)

;; -----------------------------------------------------------------------
;; Group 6: Security & Boundary Guards (CWE-843, CWE-400, CWE-209/212)
;; -----------------------------------------------------------------------
(define (run-group-6!)
  (write-string "--- Group 6: Security & Boundary Guards ---\n")
  (flush-output-port)

  ;; CWE-843: Type confusion rejection
  (assert-error (lambda () (make-crash-report "invalid-task" 'bad))
                "make-crash-report rejects string task (CWE-843)")
  (assert-error (lambda () (make-crash-ring-buffer "not-an-int"))
                "make-crash-ring-buffer rejects non-integer capacity (CWE-843)")
  (assert-error (lambda () (crash-buffer-enqueue! (make-crash-ring-buffer 10) "not-a-report"))
                "crash-buffer-enqueue! rejects non-report (CWE-843)")
  (assert-error (lambda () (format-crash-report "not-a-report"))
                "format-crash-report rejects non-report (CWE-843)")

  ;; CWE-400: Resource limit boundary
  (assert-error (lambda () (make-crash-ring-buffer 0))
                "make-crash-ring-buffer rejects zero capacity (CWE-400)")
  (assert-error (lambda () (make-crash-ring-buffer -10))
                "make-crash-ring-buffer rejects negative capacity (CWE-400)")
  (assert-error (lambda () (make-crash-ring-buffer 1000000))
                "make-crash-ring-buffer rejects capacity > 65536 (CWE-400)")

  ;; CWE-209 / CWE-212: Long sensitive message redaction & truncation
  (let* ((huge-msg (let ((s (make-string 500)))
                     (let loop ((i 0))
                       (if (< i 500)
                           (begin (string-set! s i #\A) (loop (+ i 1)))
                           s))))
         (rep (make-crash-report 777 'mem_leak '() #f huge-msg #f))
         (summary (crash-report-last-msg-summary rep)))
    (assert-true (<= (string-length summary) 256) "message summary is truncated to <= 256 chars (CWE-209/212)")
    (assert-true (let ((l (string-length summary)))
                   (string=? (substring summary (- l 3) l) "..."))
                 "truncated message ends with ellipsis (...)")))

(run-group-6!)

;; -----------------------------------------------------------------------
;; Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Synapse Crash Reporting Summary: ")
(write-string (number->string (vector-ref *pass-count* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *fail-count* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *fail-count* 0) 0)
    (exit 1)
    (exit 0))
