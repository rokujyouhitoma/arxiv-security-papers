;;; =======================================================================
;;; uLisp Concurrency Runtime: Linux Futex Primitives (futex.scm)
;;; Conforms to DSN-37 Section 7.4.2 & Section 14.9 Task 7.2 (Issue #676)
;;;
;;; Provides low-latency, zero-overhead thread park/unpark primitives
;;; using Linux sys_futex (FUTEX_WAIT_PRIVATE / FUTEX_WAKE_PRIVATE) and
;;; a 3-state CAS state machine (EMPTY=0, PARKED=1, NOTIFIED=2) to
;;; completely eliminate Lost Wakeup (CWE-833) and CPU spin waste (CWE-400).
;;; =======================================================================

;; -----------------------------------------------------------------------
;; Low-level ASM stubs overridden at link-time by futex.o
;; -----------------------------------------------------------------------
(define (%sys-futex-alloc-cell)
  #f)

(define (%sys-futex-free-cell! addr)
  #f)

(define (%sys-futex-get addr)
  0)

(define (%sys-futex-set! addr val)
  #f)

(define (%sys-futex-cas! addr expected desired)
  #f)

(define (%sys-futex-wait addr expected timeout-ms)
  0)

(define (%sys-futex-wake addr count)
  0)

;; -----------------------------------------------------------------------
;; Scheduler Integration Hook Forward Declarations (Issue #676)
;; -----------------------------------------------------------------------
(define *scheduler-futex-enabled-box* (vector #f))
(define *scheduler-make-futex-cell-box* (vector (lambda () #f)))
(define *scheduler-futex-park-box* (vector (lambda (cell timeout-ms) #t)))
(define *scheduler-futex-unpark-box* (vector (lambda (cell) #t)))
(define *scheduler-futex-unpark-all-box* (vector (lambda (cell) #t)))
(define work-stealing-scheduler? (lambda (x) #f))
(define scheduler-worker-count (lambda (x) 0))
(define scheduler-get-worker (lambda (sched id) #f))
(define worker-futex-cell (lambda (w) #f))
(define %worker-futex-cell-set! (lambda (w c) #f))

;; -----------------------------------------------------------------------
;; Futex Cell Constants & Record Definition
;; -----------------------------------------------------------------------

(define FUTEX_STATE_EMPTY 0)
(define FUTEX_STATE_PARKED 1)
(define FUTEX_STATE_NOTIFIED 2)

(define-record-type <futex-cell>
  (%make-futex-cell-record addr)
  futex-cell?
  (addr futex-cell-addr %futex-cell-addr-set!))

;; (make-futex-cell [initial-val]) -> <futex-cell>
(define make-futex-cell
  (case-lambda
    (()
     (make-futex-cell 0))
    ((initial-val)
     (if (not (integer? initial-val))
         (error "make-futex-cell: initial-val must be an integer (CWE-843)" initial-val)
         (let ((addr (%sys-futex-alloc-cell)))
           (if (not (integer? addr))
               (error "make-futex-cell: memory allocation failed via sys_mmap (CWE-400)")
               (let ((cell (%make-futex-cell-record addr)))
                 (if (not (= initial-val 0))
                     (%sys-futex-set! addr initial-val))
                 cell)))))))

;; (free-futex-cell! cell) -> #t
(define (free-futex-cell! cell)
  (if (not (futex-cell? cell))
      (error "free-futex-cell!: expected <futex-cell> (CWE-843)" cell)
      (let ((addr (futex-cell-addr cell)))
        (if (= addr 0)
            #t
            (begin
              (%futex-cell-addr-set! cell 0)
              (%sys-futex-free-cell! addr))))))

;; (futex-cell-ref cell) -> integer
(define (futex-cell-ref cell)
  (if (not (futex-cell? cell))
      (error "futex-cell-ref: expected <futex-cell> (CWE-843)" cell)
      (let ((addr (futex-cell-addr cell)))
        (if (= addr 0)
            (error "futex-cell-ref: use-after-free on futex cell (CWE-416)" cell)
            (%sys-futex-get addr)))))

(define (futex-cell-value cell)
  (futex-cell-ref cell))

;; (futex-cell-set! cell val) -> #t
(define (futex-cell-set! cell val)
  (if (not (futex-cell? cell))
      (error "futex-cell-set!: expected <futex-cell> (CWE-843)" cell)
      (if (not (integer? val))
          (error "futex-cell-set!: val must be an integer (CWE-843)" val)
          (let ((addr (futex-cell-addr cell)))
            (if (= addr 0)
                (error "futex-cell-set!: use-after-free on futex cell (CWE-416)" cell)
                (%sys-futex-set! addr val))))))

;; (futex-cell-cas! cell expected desired) -> #t / #f
(define (futex-cell-cas! cell expected desired)
  (if (not (futex-cell? cell))
      (error "futex-cell-cas!: expected <futex-cell> (CWE-843)" cell)
      (if (not (and (integer? expected) (integer? desired)))
          (error "futex-cell-cas!: expected and desired must be integers (CWE-843)")
          (let ((addr (futex-cell-addr cell)))
            (if (= addr 0)
                (error "futex-cell-cas!: use-after-free on futex cell (CWE-416)" cell)
                (%sys-futex-cas! addr expected desired))))))

;; (futex-wait! cell expected [timeout-ms]) -> status (0: woken, 1: eagain, 2: etimedout, 3: eintr, -1: err)
(define futex-wait!
  (case-lambda
    ((cell expected)
     (futex-wait! cell expected -1))
    ((cell expected timeout-ms)
     (if (not (futex-cell? cell))
         (error "futex-wait!: expected <futex-cell> (CWE-843)" cell)
         (if (not (integer? expected))
             (error "futex-wait!: expected must be an integer (CWE-843)" expected)
             (let ((t (cond ((not timeout-ms) -1)
                            ((integer? timeout-ms) timeout-ms)
                            (else (error "futex-wait!: timeout-ms must be integer or #f" timeout-ms))))
                   (addr (futex-cell-addr cell)))
               (if (= addr 0)
                   (error "futex-wait!: use-after-free on futex cell (CWE-416)" cell)
                   (%sys-futex-wait addr expected t))))))))

;; (futex-wake! cell [count]) -> integer (number of woken threads)
(define futex-wake!
  (case-lambda
    ((cell)
     (futex-wake! cell 1))
    ((cell count)
     (if (not (futex-cell? cell))
         (error "futex-wake!: expected <futex-cell> (CWE-843)" cell)
         (if (not (and (integer? count) (> count 0)))
             (error "futex-wake!: count must be positive integer (CWE-843)" count)
             (let ((addr (futex-cell-addr cell)))
               (if (= addr 0)
                   (error "futex-wake!: use-after-free on futex cell (CWE-416)" cell)
                   (%sys-futex-wake addr count))))))))

;; -----------------------------------------------------------------------
;; 3-State Park / Unpark Primitives (CWE-833 Deadlock & Lost Wakeup Free)
;; -----------------------------------------------------------------------

;; (futex-park! cell [timeout-ms]) -> #t (woken or bypass) / #f (timed out)
(define futex-park!
  (case-lambda
    ((cell)
     (futex-park! cell -1))
    ((cell timeout-ms)
     (if (not (futex-cell? cell))
         (error "futex-park!: expected <futex-cell> (CWE-843)" cell)
         (let ((t (cond ((not timeout-ms) -1)
                        ((integer? timeout-ms) timeout-ms)
                        (else (error "futex-park!: timeout-ms must be integer or #f" timeout-ms))))
               (addr (futex-cell-addr cell)))
           (if (= addr 0)
               (error "futex-park!: use-after-free on futex cell (CWE-416)" cell)
               ;; 1. Check if unpark already provided a wakeup token (NOTIFIED = 2)
               (if (%sys-futex-cas! addr 2 0)
                   #t ;; Token consumed, bypass sleep!
                   ;; 2. Transition from EMPTY (0) -> PARKED (1)
                   (if (%sys-futex-cas! addr 0 1)
                       ;; Transition succeeded: wait on futex
                       (let ((status (%sys-futex-wait addr 1 t)))
                         ;; Reset to EMPTY (0)
                         (%sys-futex-cas! addr 1 0)
                         (%sys-futex-cas! addr 2 0)
                         (cond
                           ((= status 2) #f) ;; Timed out
                           (else #t)))       ;; Woken or value changed
                       ;; 3. CAS failed: could have become NOTIFIED (2) during CAS
                       (if (%sys-futex-cas! addr 2 0)
                           #t
                           ;; Fallback wait
                           (let* ((cur (%sys-futex-get addr))
                                  (status (%sys-futex-wait addr cur t)))
                             (%sys-futex-cas! addr 1 0)
                             (%sys-futex-cas! addr 2 0)
                             (cond
                               ((= status 2) #f)
                               (else #t))))))))))))

;; (futex-unpark! cell) -> #t
(define (futex-unpark! cell)
  (if (not (futex-cell? cell))
      (error "futex-unpark!: expected <futex-cell> (CWE-843)" cell)
      (let ((addr (futex-cell-addr cell)))
        (if (= addr 0)
            (error "futex-unpark!: use-after-free on futex cell (CWE-416)" cell)
            (let loop ()
              (let ((cur (%sys-futex-get addr)))
                (cond
                  ((= cur 1) ;; PARKED
                   (if (%sys-futex-cas! addr 1 2)
                       (begin
                         (%sys-futex-wake addr 1)
                         #t)
                       (loop))) ;; CAS collision, retry
                  ((= cur 0) ;; EMPTY
                   (if (%sys-futex-cas! addr 0 2)
                       #t ;; Token stored for next park
                       (loop))) ;; CAS collision, retry
                  (else
                   ;; Already NOTIFIED (2) or other
                   #t))))))))

;; (futex-unpark-all! cell) -> #t
(define (futex-unpark-all! cell)
  (if (not (futex-cell? cell))
      (error "futex-unpark-all!: expected <futex-cell> (CWE-843)" cell)
      (let ((addr (futex-cell-addr cell)))
        (if (= addr 0)
            (error "futex-unpark-all!: use-after-free on futex cell (CWE-416)" cell)
            (begin
              (%sys-futex-set! addr 2)
              (%sys-futex-wake addr 1024)
              #t)))))

;; -----------------------------------------------------------------------
;; Scheduler Integration Hook (DSN-37 Section 7.4.2 & Issue #676)
;; -----------------------------------------------------------------------
(define scheduler-enable-futex!
  (case-lambda
    (()
     (vector-set! *scheduler-futex-enabled-box* 0 #t)
     (vector-set! *scheduler-make-futex-cell-box* 0 (lambda () (make-futex-cell 0)))
     (vector-set! *scheduler-futex-park-box* 0 (lambda (cell timeout-ms) (futex-park! cell timeout-ms)))
     (vector-set! *scheduler-futex-unpark-box* 0 (lambda (cell) (futex-unpark! cell)))
     (vector-set! *scheduler-futex-unpark-all-box* 0 (lambda (cell) (futex-unpark-all! cell)))
     #t)
    ((sched)
     (scheduler-enable-futex!)
     (if (work-stealing-scheduler? sched)
         (let ((n (scheduler-worker-count sched)))
           (let loop ((i 0))
             (if (< i n)
                 (let ((w (scheduler-get-worker sched i)))
                   (if (not (worker-futex-cell w))
                       (%worker-futex-cell-set! w (make-futex-cell 0)))
                   (loop (+ i 1)))
                 #t)))
         #t))))

