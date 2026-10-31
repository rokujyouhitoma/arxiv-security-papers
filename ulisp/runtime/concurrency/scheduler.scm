;;; =======================================================================
;;; ULisp Concurrency Runtime: Distributed M:N Work-Stealing Scheduler
;;; Conforms to DSN-37 Architecture Specification & Issue #635
;;; Paper: Scheduling Multithreaded Computations by Work Stealing
;;;        (Blumofe & Leiserson, FOCS 1994 / JACM 1999)
;;; =======================================================================

(define *scheduler-default-workers* 4)
(define *scheduler-max-workers* 64)
(define *scheduler-max-tasks* 10000000) ; 10M tasks upper bound

;; Preemption execution hook (overridden when preempt.scm is loaded)
(define budgeted-task-execute! (lambda (task) #f))

;; -----------------------------------------------------------------------
;; 1. <worker-context> Record Type (5 fields, fits in AMD64 registers)
;; -----------------------------------------------------------------------
;; Fields:
;;   id               : fixnum worker index (0 .. worker-count - 1)
;;   deque            : <chase-lev-deque> for this worker
;;   current-task-box : 1-element vector holding current task or #f
;;   rng-state-box    : 1-element vector holding 64-bit PRNG seed
;;   stats            : 4-element vector:
;;                      [0] tasks executed
;;                      [1] steals attempted
;;                      [2] steals succeeded
;;                      [3] yields count

(define-record-type <worker-context>
  (%make-worker-context id deque current-task-box rng-state-box stats)
  worker-context?
  (id               worker-id)
  (deque            worker-deque)
  (current-task-box %worker-current-task-box)
  (rng-state-box    %worker-rng-state-box)
  (stats            %worker-stats))

(define (%make-worker-stats)
  (let ((s (make-vector 4)))
    (vector-set! s 0 0)
    (vector-set! s 1 0)
    (vector-set! s 2 0)
    (vector-set! s 3 0)
    s))

(define (%make-worker-box val)
  (let ((b (make-vector 1)))
    (vector-set! b 0 val)
    b))

(define (make-worker-context id initial-cap)
  (let* ((dq (make-chase-lev-deque initial-cap))
         (seed (+ 123456789 (* (+ id 1) 1103515245)))
         (seed-clamped (if (= seed 0) 987654321 seed))
         (cur-box (%make-worker-box #f))
         (rng-box (%make-worker-box seed-clamped))
         (stats (%make-worker-stats)))
    (%make-worker-context id dq cur-box rng-box stats)))

(define (worker-current-task worker)
  (vector-ref (%worker-current-task-box worker) 0))

(define (worker-tasks-executed worker)
  (vector-ref (%worker-stats worker) 0))

(define (worker-steals-attempted worker)
  (vector-ref (%worker-stats worker) 1))

(define (worker-steals-succeeded worker)
  (vector-ref (%worker-stats worker) 2))

(define (worker-yields worker)
  (vector-ref (%worker-stats worker) 3))

(define (worker-rng-seed worker)
  (vector-ref (%worker-rng-state-box worker) 0))

(define (%bitwise-xor a b)
  (- (bitwise-ior a b) (bitwise-and a b)))

(define (worker-next-random! worker)
  (let* ((box (%worker-rng-state-box worker))
         (seed (vector-ref box 0))
         ;; Xorshift32 PRNG (Marsaglia 2003): x ^= x << 13, x ^= x >> 17, x ^= x << 5
         (x1 (%bitwise-xor seed (bitwise-and (* seed 8192) 2147483647)))
         (x2 (%bitwise-xor x1 (quotient x1 131072)))
         (x3 (%bitwise-xor x2 (bitwise-and (* x2 32) 2147483647)))
         (next (if (= x3 0) 123456789 x3)))
    (vector-set! box 0 next)
    next))

(define (%worker-tasks-exec-inc! worker)
  (let ((s (%worker-stats worker)))
    (vector-set! s 0 (+ (vector-ref s 0) 1))))

(define (%worker-steals-att-inc! worker)
  (let ((s (%worker-stats worker)))
    (vector-set! s 1 (+ (vector-ref s 1) 1))))

(define (%worker-steals-succ-inc! worker)
  (let ((s (%worker-stats worker)))
    (vector-set! s 2 (+ (vector-ref s 2) 1))))

(define (%worker-yields-inc! worker)
  (let ((s (%worker-stats worker)))
    (vector-set! s 3 (+ (vector-ref s 3) 1))))

;; -----------------------------------------------------------------------
;; 2. <work-stealing-scheduler> Record Type (5 fields, fits in AMD64 registers)
;; -----------------------------------------------------------------------
;; Fields:
;;   worker-count  : fixnum count of workers
;;   workers       : vector of <worker-context>
;;   global-queue  : <lock-free-queue> (Michael-Scott queue) for global tasks
;;   state-box     : <atomic-box> holding 'init | 'running | 'stopped
;;   stats         : 2-element vector:
;;                   [0] spawned tasks count
;;                   [1] completed tasks count

(define-record-type <work-stealing-scheduler>
  (%make-work-stealing-scheduler worker-count workers global-queue state-box stats)
  work-stealing-scheduler?
  (worker-count  scheduler-worker-count)
  (workers       scheduler-workers)
  (global-queue  scheduler-global-queue)
  (state-box     %scheduler-state-box)
  (stats         %scheduler-stats))

(define (%make-scheduler-stats)
  (let ((s (make-vector 2)))
    (vector-set! s 0 0)
    (vector-set! s 1 0)
    s))

(define (%make-scheduler-internal worker-count workers)
  (let ((gq (make-lock-free-queue))
        (box (make-atomic-box 'running))
        (stats (%make-scheduler-stats)))
    (%make-work-stealing-scheduler worker-count workers gq box stats)))

(define (%init-workers! vec i n cap)
  (if (< i n)
      (let ((w (make-worker-context i cap)))
        (vector-set! vec i w)
        (%init-workers! vec (+ i 1) n cap))
      vec))

(define make-work-stealing-scheduler
  (case-lambda
    (()
     (make-work-stealing-scheduler *scheduler-default-workers*))
    ((worker-count)
     (make-work-stealing-scheduler worker-count *deque-default-capacity*))
    ((worker-count initial-deque-cap)
     (if (not (integer? worker-count))
         (error "make-work-stealing-scheduler: worker-count must be an integer (CWE-843)" worker-count)
         (if (or (< worker-count 1) (> worker-count *scheduler-max-workers*))
             (error "make-work-stealing-scheduler: worker-count out of range [1..64] (CWE-400)" worker-count)
             (let ((workers (make-vector worker-count)))
               (%init-workers! workers 0 worker-count initial-deque-cap)
               (%make-scheduler-internal worker-count workers)))))))

(define (scheduler-get-worker sched worker-id)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-get-worker: expected <work-stealing-scheduler>" sched)
      (if (or (< worker-id 0) (>= worker-id (scheduler-worker-count sched)))
          (error "scheduler-get-worker: worker-id out of range" worker-id)
          (vector-ref (scheduler-workers sched) worker-id))))

(define (scheduler-state sched)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-state: expected <work-stealing-scheduler>" sched)
      (atomic-ref (%scheduler-state-box sched))))

(define (scheduler-running? sched)
  (eq? (scheduler-state sched) 'running))

(define (scheduler-stopped? sched)
  (eq? (scheduler-state sched) 'stopped))

(define (scheduler-tasks-spawned sched)
  (vector-ref (%scheduler-stats sched) 0))

(define (scheduler-tasks-completed sched)
  (vector-ref (%scheduler-stats sched) 1))

(define (scheduler-total-spawned sched)
  (scheduler-tasks-spawned sched))

(define (scheduler-total-completed sched)
  (scheduler-tasks-completed sched))

(define (%scheduler-tasks-spawned-inc! sched)
  (let ((s (%scheduler-stats sched)))
    (vector-set! s 0 (+ (vector-ref s 0) 1))))

(define (%scheduler-tasks-completed-inc! sched)
  (let ((s (%scheduler-stats sched)))
    (vector-set! s 1 (+ (vector-ref s 1) 1))))

;; -----------------------------------------------------------------------
;; 3. Task Execution Engine & Spawning
;; -----------------------------------------------------------------------

(define (%is-budgeted-task? task)
  (and (vector? task)
       (> (vector-length task) 1)
       (eq? (vector-ref task 0) '%%record-type-<budgeted-task>)))

(define (scheduler-execute-task! task)
  (cond
    ;; DSN-37 task-context (Issue #633)
    ((task-context? task)
     (if (eq? (task-state task) 'ready)
         (begin
           (task-state-set! task 'running)
           #t)
         #t))
    ;; DSN-37 budgeted-task with reductions (Issue #636)
    ((%is-budgeted-task? task)
     (budgeted-task-execute! task))
    ;; Scheme native coroutine context (Issue #634)
    ((coroutine-context? task)
     (if (not (coroutine-terminated? task))
         (context-resume! task)
         #f))
    ;; Thunk: zero-argument procedure (verify not a vector record due to low-tag overlap)
    ((and (not (vector? task)) (procedure? task))
     (task))
    (else
     (error "scheduler-execute-task!: invalid task object (CWE-843)" task))))

(define scheduler-spawn!
  (case-lambda
    ((sched task)
     (scheduler-spawn! sched task #f))
    ((sched task target-worker-id)
     (if (not (work-stealing-scheduler? sched))
         (error "scheduler-spawn!: expected <work-stealing-scheduler>" sched)
         (if (not (or (procedure? task) (coroutine-context? task) (task-context? task) (%is-budgeted-task? task)))
             (error "scheduler-spawn!: task must be procedure, coroutine, or task-context (CWE-843)" task)
             (if (not (scheduler-running? sched))
                 (error "scheduler-spawn!: cannot spawn into stopped scheduler" sched)
                 (let ((sp-cnt (scheduler-tasks-spawned sched)))
                   (if (>= sp-cnt *scheduler-max-tasks*)
                       (error "scheduler-spawn!: maximum spawned tasks limit exceeded (CWE-400)" sp-cnt)
                       (begin
                         (%scheduler-tasks-spawned-inc! sched)
                         (if (and target-worker-id
                                  (integer? target-worker-id)
                                  (>= target-worker-id 0)
                                  (< target-worker-id (scheduler-worker-count sched)))
                             (let ((w (scheduler-get-worker sched target-worker-id)))
                               (deque-push! (worker-deque w) task))
                             (queue-enqueue! (scheduler-global-queue sched) task))
                         #t)))))))))

;; -----------------------------------------------------------------------
;; 4. Work-Stealing Step & Multi-Worker Coordination
;; -----------------------------------------------------------------------

(define (scheduler-worker-step! sched worker-id)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-worker-step!: expected <work-stealing-scheduler>" sched)
      (let* ((num-workers (scheduler-worker-count sched))
             (w (scheduler-get-worker sched worker-id))
             (dq (worker-deque w)))
        ;; Phase 1: Local Deque (LIFO)
        (let ((local-task (deque-pop! dq)))
          (if local-task
              (%scheduler-run-and-record! sched w local-task)
              ;; Phase 2: Global Michael-Scott Queue (FIFO)
              (let ((global-task (queue-dequeue! (scheduler-global-queue sched))))
                (if global-task
                    (%scheduler-run-and-record! sched w global-task)
                    ;; Phase 3: Work Stealing from Victim
                    (let ((stolen-task (%scheduler-try-steal! sched w num-workers)))
                      (if stolen-task
                          (%scheduler-run-and-record! sched w stolen-task)
                          (begin
                            (%worker-yields-inc! w)
                            #f))))))))))

(define (%steal-loop sched worker num-workers start-victim-offset attempts)
  (if (>= attempts (* 2 num-workers))
      #f
      (let* ((victim-id (modulo (+ (+ (worker-id worker) start-victim-offset) attempts) num-workers))
             (victim (scheduler-get-worker sched victim-id))
             (victim-dq (worker-deque victim)))
        (%worker-steals-att-inc! worker)
        (let ((stolen (deque-steal! victim-dq)))
          (cond
            ((eq? stolen 'empty)
             (%steal-loop sched worker num-workers start-victim-offset (+ attempts 1)))
            ((eq? stolen 'abort)
             (%steal-loop sched worker num-workers start-victim-offset (+ attempts 1)))
            (else
             (%worker-steals-succ-inc! worker)
             stolen))))))

(define (%scheduler-try-steal! sched worker num-workers)
  (if (<= num-workers 1)
      #f
      (let* ((rand-val (worker-next-random! worker))
             (offset (+ (modulo rand-val (- num-workers 1)) 1)))
        (%steal-loop sched worker num-workers offset 0))))

(define (%scheduler-run-and-record! sched worker task)
  (let ((cur-box (%worker-current-task-box worker)))
    (vector-set! cur-box 0 task)
    (let ((result (scheduler-execute-task! task)))
      (vector-set! cur-box 0 #f)
      (%worker-tasks-exec-inc! worker)
      (%scheduler-tasks-completed-inc! sched)
      #t)))

;; -----------------------------------------------------------------------
;; 5. Scheduler Loop & Lifecycle Management
;; -----------------------------------------------------------------------

(define (%scheduler-idle-backoff!)
  ;; Bounded spin pause to relieve bus/CPU contention during quiescent periods
  (let spin ((i 0))
    (if (< i 64)
        (spin (+ i 1))
        #f)))

(define (%scheduler-step-all! sched num-workers i progress-made)
  (if (< i num-workers)
      (let ((executed? (scheduler-worker-step! sched i)))
        (%scheduler-step-all! sched num-workers (+ i 1) (if executed? #t progress-made)))
      progress-made))

(define (%scheduler-run-loop sched max-tasks num-workers)
  (if (not (scheduler-running? sched))
      (scheduler-tasks-completed sched)
      (let* ((spawned (scheduler-tasks-spawned sched))
             (completed (scheduler-tasks-completed sched)))
        (if (or (>= completed max-tasks)
                (and (>= completed spawned) (> spawned 0)))
            completed
            (let ((progress-made (%scheduler-step-all! sched num-workers 0 #f)))
              (if (not progress-made)
                  (if (and (>= (scheduler-tasks-completed sched) (scheduler-tasks-spawned sched))
                           (> (scheduler-tasks-spawned sched) 0))
                      (scheduler-tasks-completed sched)
                      (begin
                        (%scheduler-idle-backoff!)
                        (%scheduler-run-loop sched max-tasks num-workers)))
                  (%scheduler-run-loop sched max-tasks num-workers)))))))

(define scheduler-run!
  (case-lambda
    ((sched)
     (scheduler-run! sched *scheduler-max-tasks*))
    ((sched max-tasks)
     (if (not (work-stealing-scheduler? sched))
         (error "scheduler-run!: expected <work-stealing-scheduler>" sched)
         (%scheduler-run-loop sched max-tasks (scheduler-worker-count sched))))))

(define (scheduler-stop! sched)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-stop!: expected <work-stealing-scheduler>" sched)
      (begin
        (atomic-set! (%scheduler-state-box sched) 'stopped)
        (%memory-fence)
        #t)))

;; -----------------------------------------------------------------------
;; 6. Channel & Context Integration Hooks (DSN-37 Section 8.4)
;; -----------------------------------------------------------------------

(define (scheduler-enable-channel-wake! sched)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-enable-channel-wake!: expected <work-stealing-scheduler>" sched)
      (let ((wake-hook
             (lambda (task)
               (if (or (procedure? task) (coroutine-context? task) (task-context? task))
                   (scheduler-spawn! sched task #f)
                   #f))))
        (set-channel-wake-hook! wake-hook)
        #t)))

;; -----------------------------------------------------------------------
;; 7. Diagnostics & Metrics Collection
;; -----------------------------------------------------------------------

(define (%collect-worker-stats sched num-workers i acc)
  (if (>= i num-workers)
      (reverse acc)
      (let ((w (scheduler-get-worker sched i)))
        (%collect-worker-stats
         sched num-workers (+ i 1)
         (cons (list (cons 'id (worker-id w))
                     (cons 'tasks-executed (worker-tasks-executed w))
                     (cons 'steals-attempted (worker-steals-attempted w))
                     (cons 'steals-succeeded (worker-steals-succeeded w))
                     (cons 'yields (worker-yields w))
                     (cons 'deque-count (deque-count (worker-deque w))))
               acc)))))

(define (scheduler-stats sched)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-stats: expected <work-stealing-scheduler>" sched)
      (let* ((num-workers (scheduler-worker-count sched))
             (worker-stats-list (%collect-worker-stats sched num-workers 0 '())))
        (list (cons 'worker-count num-workers)
              (cons 'state (scheduler-state sched))
              (cons 'tasks-spawned (scheduler-tasks-spawned sched))
              (cons 'tasks-completed (scheduler-tasks-completed sched))
              (cons 'global-queue-size (queue-size (scheduler-global-queue sched)))
              (cons 'workers worker-stats-list)))))
