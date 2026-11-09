;;; =======================================================================
;;; ULisp Concurrency Runtime: Distributed M:N Work-Stealing Scheduler
;;; Conforms to DSN-37 Architecture Specification & Issue #635
;;; Paper: Scheduling Multithreaded Computations by Work Stealing
;;;        (Blumofe & Leiserson, FOCS 1994 / JACM 1999)
;;; =======================================================================

(define *scheduler-default-workers* 4)
(define *scheduler-max-workers* 64)
(define *scheduler-run-default-max-steps* 10000000) ; 10M steps default per run
(define *scheduler-max-tasks* 10000000) ; 10M tasks upper bound
(define *scheduler-max-tasks-box* (vector 10000000))

(define (scheduler-max-tasks)
  (vector-ref *scheduler-max-tasks-box* 0))

(define (scheduler-set-max-tasks! limit)
  (if (not (integer? limit))
      (error "scheduler-set-max-tasks!: expected integer (CWE-843)" limit)
      (if (<= limit 0)
          (error "scheduler-set-max-tasks!: limit must be positive (CWE-400)" limit)
          (begin
            (vector-set! *scheduler-max-tasks-box* 0 limit)
            #t))))

;; Preemption execution hook (overridden when preempt.scm is loaded)
(define budgeted-task-execute! (lambda (task) #f))

;; Futex execution hooks (injected via futex.scm, Issue #676, #679)
(define (%sys-cpu-pause cycles) #t)
(define *scheduler-futex-enabled-box* (vector #f))
(define *scheduler-make-futex-cell-box* (vector (lambda () #f)))
(define *scheduler-futex-park-box* (vector (lambda (cell timeout-ms) #t)))
(define *scheduler-futex-park-adaptive-box* (vector (lambda (cell spins timeout-ms) #t)))
(define *scheduler-futex-unpark-box* (vector (lambda (cell) #t)))
(define *scheduler-futex-unpark-all-box* (vector (lambda (cell) #t)))

;; -----------------------------------------------------------------------
;; 1. <worker-context> Record Type (6 fields, fits in AMD64 registers)
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
;;   futex-cell       : <futex-cell> or #f for parking idle workers (Issue #676)

(define-record-type <worker-context>
  (%make-worker-context id node-id deque current-task-box rng-state-box stats futex-cell)
  worker-context?
  (id               worker-id)
  (node-id          worker-node-id)
  (deque            worker-deque)
  (current-task-box %worker-current-task-box)
  (rng-state-box    %worker-rng-state-box)
  (stats            %worker-stats)
  (futex-cell       worker-futex-cell           %worker-futex-cell-set!))

(define (%make-worker-stats)
  (let ((s (make-vector 8)))
    (vector-set! s 0 0)
    (vector-set! s 1 0)
    (vector-set! s 2 0)
    (vector-set! s 3 0)
    (vector-set! s 4 0)
    (vector-set! s 5 0)
    (vector-set! s 6 0)
    (vector-set! s 7 0)
    s))

(define (%make-worker-box val)
  (let ((b (make-vector 1)))
    (vector-set! b 0 val)
    b))

(define make-worker-context
  (case-lambda
    ((id initial-cap)
     (make-worker-context id 0 initial-cap))
    ((id node-id initial-cap)
     (let* ((dq (make-chase-lev-deque initial-cap))
            (seed (+ 123456789 (* (+ id 1) 1103515245)))
            (seed-clamped (if (= seed 0) 987654321 seed))
            (cur-box (%make-worker-box #f))
            (rng-box (%make-worker-box seed-clamped))
            (stats (%make-worker-stats))
            (futex-cell ((vector-ref *scheduler-make-futex-cell-box* 0))))
       (%make-worker-context id node-id dq cur-box rng-box stats futex-cell)))))

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

(define (worker-local-steals-attempted worker)
  (vector-ref (%worker-stats worker) 4))

(define (worker-local-steals-succeeded worker)
  (vector-ref (%worker-stats worker) 5))

(define (worker-remote-steals-attempted worker)
  (vector-ref (%worker-stats worker) 6))

(define (worker-remote-steals-succeeded worker)
  (vector-ref (%worker-stats worker) 7))

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

(define (%worker-local-steals-att-inc! worker)
  (let ((s (%worker-stats worker)))
    (vector-set! s 1 (+ (vector-ref s 1) 1))
    (vector-set! s 4 (+ (vector-ref s 4) 1))))

(define (%worker-local-steals-succ-inc! worker)
  (let ((s (%worker-stats worker)))
    (vector-set! s 2 (+ (vector-ref s 2) 1))
    (vector-set! s 5 (+ (vector-ref s 5) 1))))

(define (%worker-remote-steals-att-inc! worker)
  (let ((s (%worker-stats worker)))
    (vector-set! s 1 (+ (vector-ref s 1) 1))
    (vector-set! s 6 (+ (vector-ref s 6) 1))))

(define (%worker-remote-steals-succ-inc! worker)
  (let ((s (%worker-stats worker)))
    (vector-set! s 2 (+ (vector-ref s 2) 1))
    (vector-set! s 7 (+ (vector-ref s 7) 1))))

(define (%worker-yields-inc! worker)
  (let ((s (%worker-stats worker)))
    (vector-set! s 3 (+ (vector-ref s 3) 1))))

;; -----------------------------------------------------------------------
;; 2. <work-stealing-scheduler> Record Type (NUMA-Aware Hierarchical Topology)
;; -----------------------------------------------------------------------
;; Fields:
;;   worker-count  : fixnum count of workers
;;   node-count    : fixnum count of NUMA nodes
;;   workers       : vector of <worker-context>
;;   node-workers  : vector of vectors of worker IDs per node
;;   global-queue  : <lock-free-queue> (Michael-Scott queue) for global tasks
;;   state-box     : <atomic-box> holding 'init | 'running | 'stopped
;;   stats         : 2-element vector:
;;                   [0] spawned tasks count
;;                   [1] completed tasks count

(define-record-type <work-stealing-scheduler>
  (%make-work-stealing-scheduler worker-count node-count workers node-workers global-queue state-box stats)
  work-stealing-scheduler?
  (worker-count  scheduler-worker-count)
  (node-count    scheduler-node-count)
  (workers       scheduler-workers)
  (node-workers  %scheduler-node-workers)
  (global-queue  scheduler-global-queue)
  (state-box     %scheduler-state-box)
  (stats         %scheduler-stats))

(define (scheduler-node-workers sched node-id)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-node-workers: expected <work-stealing-scheduler>" sched)
      (if (not (integer? node-id))
          (error "scheduler-node-workers: node-id must be an integer (CWE-843)" node-id)
          (if (or (< node-id 0) (>= node-id (scheduler-node-count sched)))
              (error "scheduler-node-workers: node-id out of range (CWE-400)" node-id)
              (vector-ref (%scheduler-node-workers sched) node-id)))))

(define (%make-scheduler-stats)
  (let ((s (make-vector 4)))
    (vector-set! s 0 (make-atomic-box 0))
    (vector-set! s 1 (make-atomic-box 0))
    (vector-set! s 2 (make-atomic-box 0))
    (vector-set! s 3 (make-atomic-box 0))
    s))

(define (%make-scheduler-internal worker-count node-count workers node-workers)
  (let ((gq (make-lock-free-queue))
        (box (make-atomic-box 'running))
        (stats (%make-scheduler-stats)))
    (%make-work-stealing-scheduler worker-count node-count workers node-workers gq box stats)))

(define (%build-node-workers-table worker-count node-count)
  (let ((table (make-vector node-count)))
    (let ((counts (make-vector node-count 0)))
      (let count-loop ((i 0))
        (if (< i worker-count)
            (let ((node (quotient (* i node-count) worker-count)))
              (vector-set! counts node (+ (vector-ref counts node) 1))
              (count-loop (+ i 1)))
            #t))
      (let alloc-loop ((n 0))
        (if (< n node-count)
            (begin
              (vector-set! table n (make-vector (vector-ref counts n)))
              (alloc-loop (+ n 1)))
            #t))
      (let ((indices (make-vector node-count 0)))
        (let fill-loop ((i 0))
          (if (< i worker-count)
              (let* ((node (quotient (* i node-count) worker-count))
                     (idx (vector-ref indices node))
                     (vec (vector-ref table node)))
                (vector-set! vec idx i)
                (vector-set! indices node (+ idx 1))
                (fill-loop (+ i 1)))
              #t)))
      table)))

(define (%init-workers! vec i n cap node-count)
  (if (< i n)
      (let* ((node-id (quotient (* i node-count) n))
             (w (make-worker-context i node-id cap)))
        (vector-set! vec i w)
        (%init-workers! vec (+ i 1) n cap node-count))
      vec))

(define make-work-stealing-scheduler
  (case-lambda
    (()
     (make-work-stealing-scheduler *scheduler-default-workers* *deque-default-capacity* 1))
    ((worker-count)
     (make-work-stealing-scheduler worker-count *deque-default-capacity* 1))
    ((worker-count initial-deque-cap)
     (make-work-stealing-scheduler worker-count initial-deque-cap 1))
    ((worker-count initial-deque-cap node-count)
     (if (not (integer? worker-count))
         (error "make-work-stealing-scheduler: worker-count must be an integer (CWE-843)" worker-count)
         (if (or (< worker-count 1) (> worker-count *scheduler-max-workers*))
             (error "make-work-stealing-scheduler: worker-count out of range [1..64] (CWE-400)" worker-count)
             (if (not (integer? initial-deque-cap))
                 (error "make-work-stealing-scheduler: initial-deque-cap must be an integer (CWE-843)" initial-deque-cap)
                 (if (or (< initial-deque-cap 2) (> initial-deque-cap 1048576))
                     (error "make-work-stealing-scheduler: initial-deque-cap out of range (CWE-400)" initial-deque-cap)
                     (if (not (integer? node-count))
                         (error "make-work-stealing-scheduler: node-count must be an integer (CWE-843)" node-count)
                         (if (or (< node-count 1) (> node-count worker-count))
                             (error "make-work-stealing-scheduler: node-count out of range [1..worker-count] (CWE-400)" node-count)
                             (let ((workers (make-vector worker-count))
                                   (node-workers (%build-node-workers-table worker-count node-count)))
                               (%init-workers! workers 0 worker-count initial-deque-cap node-count)
                               (%make-scheduler-internal worker-count node-count workers node-workers)))))))))))

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
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-tasks-spawned: expected <work-stealing-scheduler>" sched)
      (atomic-ref (vector-ref (%scheduler-stats sched) 0))))

(define (scheduler-tasks-completed sched)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-tasks-completed: expected <work-stealing-scheduler>" sched)
      (atomic-ref (vector-ref (%scheduler-stats sched) 1))))

(define (scheduler-tasks-failed sched)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-tasks-failed: expected <work-stealing-scheduler>" sched)
      (atomic-ref (vector-ref (%scheduler-stats sched) 2))))

(define (scheduler-live-tasks sched)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-live-tasks: expected <work-stealing-scheduler>" sched)
      (atomic-ref (vector-ref (%scheduler-stats sched) 3))))

(define (scheduler-total-spawned sched)
  (scheduler-tasks-spawned sched))

(define (scheduler-total-completed sched)
  (scheduler-tasks-completed sched))

(define (scheduler-total-failed sched)
  (scheduler-tasks-failed sched))

(define (scheduler-total-live sched)
  (scheduler-live-tasks sched))

(define (%scheduler-tasks-spawned-inc! sched)
  (atomic-fetch-add! (vector-ref (%scheduler-stats sched) 0) 1))

(define (%scheduler-tasks-completed-inc! sched)
  (atomic-fetch-add! (vector-ref (%scheduler-stats sched) 1) 1))

(define (%scheduler-tasks-failed-inc! sched)
  (atomic-fetch-add! (vector-ref (%scheduler-stats sched) 2) 1))

(define (%scheduler-live-tasks-inc! sched)
  (atomic-fetch-add! (vector-ref (%scheduler-stats sched) 3) 1))

(define (%scheduler-live-tasks-dec! sched)
  (atomic-fetch-add! (vector-ref (%scheduler-stats sched) 3) -1))

(define (%scheduler-stats-reset! sched)
  (if (not (work-stealing-scheduler? sched))
      (error "%scheduler-stats-reset!: expected <work-stealing-scheduler>" sched)
      (let ((s (%scheduler-stats sched)))
        (atomic-set! (vector-ref s 0) 0)
        (atomic-set! (vector-ref s 1) 0)
        (atomic-set! (vector-ref s 2) 0)
        (atomic-set! (vector-ref s 3) 0)
        #t)))

;; -----------------------------------------------------------------------
;; 3. Task Execution Engine & Spawning
;; -----------------------------------------------------------------------

(define (%is-budgeted-task? task)
  (and (vector? task)
       (> (vector-length task) 1)
       (eq? (vector-ref task 0) '%%record-type-<budgeted-task>)))

(define (%budgeted-task-id-safe task)
  (if (and (vector? task) (> (vector-length task) 1) (integer? (vector-ref task 1)))
      (vector-ref task 1)
      0))

(define (%budgeted-task-reductions-safe task)
  (if (and (vector? task) (> (vector-length task) 3) (vector? (vector-ref task 3)))
      (vector-ref (vector-ref task 3) 0)
      *task-default-reductions*))

(define (%normalize-task-context task)
  (cond
    ((task-context? task)
     task)
    ((coroutine-context? task)
     (let ((ctx (make-task-context)))
       (task-next-run-set! ctx task)
       ctx))
    ((%is-budgeted-task? task)
     (let ((tid (%budgeted-task-id-safe task))
           (reds (%budgeted-task-reductions-safe task)))
       (let ((ctx (if (> tid 0) (make-task-context tid) (make-task-context))))
         (task-reductions-set! ctx reds)
         (task-next-run-set! ctx task)
         ctx)))
    ((and (not (vector? task)) (procedure? task))
     (let ((ctx (make-task-context)))
       (task-next-run-set! ctx task)
       ctx))
    (else
     (error "scheduler-spawn!: task must be procedure, coroutine, or task-context (CWE-843)" task))))

(define (scheduler-execute-task! task)
  (let ((ctx (cond
               ((task-context? task) task)
               ((or (coroutine-context? task) (%is-budgeted-task? task) (and (not (vector? task)) (procedure? task)))
                (%normalize-task-context task))
               (else
                (error "scheduler-execute-task!: invalid task object (CWE-843)" task)))))
    (if (eq? (task-state ctx) 'terminated)
        #f
        (begin
          (if (eq? (task-state ctx) 'ready)
              (task-state-set! ctx 'running)
              #t)
          (let ((nxt (task-next-run ctx)))
            (cond
              ;; Scheme native coroutine context (Issue #634, #720, #740, #741)
              ((coroutine-context? nxt)
               (if (not (coroutine-terminated? nxt))
                   (let ((res (with-synapse-task-boundary ctx
                                (lambda () (context-resume! nxt)))))
                     (cond
                       ((and (pair? res) (eq? (car res) 'panic))
                        (let ((stk (coroutine-stack nxt)))
                          (if (and (task-stack? stk) (not (task-stack-freed? stk)))
                              (%context-raw-u64-set! (task-stack-top stk) -24 3)
                              #f))
                        res)
                       ((coroutine-terminated? nxt)
                        (task-exit! ctx 'normal)
                        res)
                       (else
                        res)))
                   (begin
                     (if (not (eq? (task-state ctx) 'terminated))
                         (task-exit! ctx 'normal)
                         #f)
                     #f)))
              ;; DSN-37 budgeted-task with reductions (Issue #636, #720, #741)
              ((%is-budgeted-task? nxt)
               (let ((res (with-synapse-task-boundary ctx
                            (lambda () (budgeted-task-execute! nxt)))))
                 (if (and (pair? res) (eq? (car res) 'ok))
                     (if (or (eq? (task-state nxt) 'completed) (eq? (task-state nxt) 'terminated))
                         (begin
                           (task-exit! ctx 'normal)
                           res)
                         res)
                     res)))
              ;; Thunk: zero-argument procedure (Issue #741, #788)
              ((and (not (vector? nxt)) (procedure? nxt))
               (let ((res (with-synapse-task-boundary ctx nxt)))
                 (if (and (pair? res) (eq? (car res) 'ok))
                     (if (task-resident? ctx)
                         ;; Resident actor task: do NOT exit! Transition to idle/waiting
                         (begin
                           (if (not (eq? (task-state ctx) 'terminated))
                               (task-state-set! ctx 'waiting))
                           res)
                         (begin
                           (task-exit! ctx 'normal)
                           res))
                     res)))
              (else
               (if (task-resident? ctx)
                   (begin
                     (if (not (eq? (task-state ctx) 'terminated))
                         (task-state-set! ctx 'waiting))
                     (cons 'ok #t))
                   (begin
                     (task-exit! ctx 'normal)
                     (cons 'ok #t))))))))))

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
                 (let ((live-cnt (scheduler-live-tasks sched)))
                   (if (>= live-cnt (vector-ref *scheduler-max-tasks-box* 0))
                       (error "scheduler-spawn!: maximum spawned tasks limit exceeded (CWE-400)" live-cnt)
                       (let ((normalized (%normalize-task-context task)))
                         (%scheduler-tasks-spawned-inc! sched)
                         (%scheduler-live-tasks-inc! sched)
                         (if (and target-worker-id
                                  (integer? target-worker-id)
                                  (>= target-worker-id 0)
                                  (< target-worker-id (scheduler-worker-count sched)))
                             (let ((w (scheduler-get-worker sched target-worker-id)))
                               (deque-push! (worker-deque w) normalized)
                               (let ((cell (worker-futex-cell w)))
                                 (if cell ((vector-ref *scheduler-futex-unpark-box* 0) cell))))
                             (begin
                               (queue-enqueue! (scheduler-global-queue sched) normalized)
                               ;; Wake a worker to consume from global queue
                               (if (> (scheduler-worker-count sched) 1)
                                   (let* ((w (scheduler-get-worker sched 1))
                                          (cell (worker-futex-cell w)))
                                     (if cell ((vector-ref *scheduler-futex-unpark-box* 0) cell))))))
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

(define (%find-worker-index vec wid i len)
  (if (>= i len)
      0
      (if (= (vector-ref vec i) wid)
          i
          (%find-worker-index vec wid (+ i 1) len))))

;; Tier 1: Intra-Node Steal
;; Attempts to steal from peer workers located on the same NUMA node.
(define (%tier1-steal-loop sched worker local-workers local-len my-idx start-offset attempts max-attempts)
  (if (>= attempts max-attempts)
      #f
      (let* ((step (+ 1 (modulo (+ start-offset attempts) (- local-len 1))))
             (victim-idx (modulo (+ my-idx step) local-len))
             (victim-id (vector-ref local-workers victim-idx))
             (victim (scheduler-get-worker sched victim-id))
             (victim-dq (worker-deque victim)))
        (%worker-local-steals-att-inc! worker)
        (let ((stolen (deque-steal! victim-dq)))
          (cond
            ((eq? stolen 'empty)
             (%tier1-steal-loop sched worker local-workers local-len my-idx start-offset (+ attempts 1) max-attempts))
            ((eq? stolen 'abort)
             (%tier1-steal-loop sched worker local-workers local-len my-idx start-offset (+ attempts 1) max-attempts))
            (else
             (%worker-local-steals-succ-inc! worker)
             stolen))))))

;; Tier 2: Inter-Node Fallback Steal
;; Attempts to steal from workers on remote NUMA nodes when local node is exhausted.
(define (%tier2-steal-loop sched worker node-count my-node node-workers rand-node-seed rand-w-seed attempts max-attempts)
  (if (>= attempts max-attempts)
      #f
      (let* ((node-offset (+ 1 (modulo (+ rand-node-seed attempts) (- node-count 1))))
             (target-node (modulo (+ my-node node-offset) node-count))
             (remote-workers (vector-ref node-workers target-node))
             (rem-len (vector-length remote-workers)))
        (if (<= rem-len 0)
            (%tier2-steal-loop sched worker node-count my-node node-workers rand-node-seed rand-w-seed (+ attempts 1) max-attempts)
            (let* ((w-offset (modulo (+ rand-w-seed attempts) rem-len))
                   (victim-id (vector-ref remote-workers w-offset))
                   (victim (scheduler-get-worker sched victim-id))
                   (victim-dq (worker-deque victim)))
              (%worker-remote-steals-att-inc! worker)
              (let ((stolen (deque-steal! victim-dq)))
                (cond
                  ((eq? stolen 'empty)
                   (%tier2-steal-loop sched worker node-count my-node node-workers rand-node-seed rand-w-seed (+ attempts 1) max-attempts))
                  ((eq? stolen 'abort)
                   (%tier2-steal-loop sched worker node-count my-node node-workers rand-node-seed rand-w-seed (+ attempts 1) max-attempts))
                  (else
                   (%worker-remote-steals-succ-inc! worker)
                   stolen))))))))

(define (%scheduler-try-steal! sched worker num-workers)
  (if (<= num-workers 1)
      #f
      (let* ((node-count (scheduler-node-count sched))
             (node-workers (%scheduler-node-workers sched))
             (my-node (worker-node-id worker))
             (local-workers (vector-ref node-workers my-node))
             (local-len (vector-length local-workers))
             (wid (worker-id worker)))
        ;; Tier 1: Try local NUMA node peers first
        (let ((tier1-task
               (if (> local-len 1)
                   (let* ((my-idx (%find-worker-index local-workers wid 0 local-len))
                          (rand-val (worker-next-random! worker))
                          (start-offset (modulo rand-val (- local-len 1)))
                          (max-attempts (* 2 (- local-len 1))))
                     (%tier1-steal-loop sched worker local-workers local-len my-idx start-offset 0 max-attempts))
                   #f)))
          (if tier1-task
              tier1-task
              ;; Tier 2: Fallback to remote NUMA nodes if node-count > 1
              (if (> node-count 1)
                  (let* ((remote-count (- num-workers local-len)))
                    (if (> remote-count 0)
                        (let* ((rand-node-seed (worker-next-random! worker))
                               (rand-w-seed (worker-next-random! worker))
                               (max-remote-attempts (* 2 remote-count)))
                          (%tier2-steal-loop sched worker node-count my-node node-workers rand-node-seed rand-w-seed 0 max-remote-attempts))
                        #f))
                  #f))))))

(define (%scheduler-run-and-record! sched worker task)
  (let* ((cur-box (%worker-current-task-box worker))
         (wid (worker-id worker))
         (prev-override (vector-ref *worker-slot-override-tls* (%asm-current-worker-slot)))
         (prev-task (current-synapse-task))
         (prev-hc (%asm-get-handler-chain)))
    (%set-current-worker-tls-override! wid)
    (vector-set! cur-box 0 task)
    (%set-current-synapse-task! task)
    (if (and (task-context? task) (> (task-handler-chain task) 0))
        (%asm-set-handler-chain! (task-handler-chain task))
        #f)
    (let ((result (scheduler-execute-task! task)))
      (if (task-context? task)
          (task-set-handler-chain! task (%asm-get-handler-chain))
          #f)
      (%asm-set-handler-chain! prev-hc)
      (vector-set! cur-box 0 #f)
      (%set-current-synapse-task! prev-task)
      (%set-current-worker-tls-override! prev-override)
      (%worker-tasks-exec-inc! worker)
      ;; Separate completed (normal) vs failed (panic / exception) counters (Issue #732, Item A8)
      ;; and decrement live tasks counter upon completion (Issue #793)
      (if (or (and (pair? result) (eq? (car result) 'panic))
              (and (task-context? task)
                   (let ((st (%task-state task)))
                     (or (eq? st 'panicked) (eq? st 'failed)))))
          (begin
            (%scheduler-tasks-failed-inc! sched)
            (%scheduler-live-tasks-dec! sched))
          (begin
            (%scheduler-tasks-completed-inc! sched)
            (%scheduler-live-tasks-dec! sched)))
      #t)))

;; -----------------------------------------------------------------------
;; 5. Scheduler Loop & Lifecycle Management
;; -----------------------------------------------------------------------

(define (%scheduler-idle-backoff!)
  ;; Bounded spin pause to relieve bus/CPU contention during quiescent periods (Issue #679)
  (if (vector-ref *scheduler-futex-enabled-box* 0)
      (%sys-cpu-pause 16)
      (let spin ((i 0))
        (if (< i 64)
            (spin (+ i 1))
            #f))))

(define (%scheduler-step-all! sched num-workers i progress-made)
  (if (< i num-workers)
      (let ((executed? (guard (exn (else #f))
                         (scheduler-worker-step! sched i))))
        (%scheduler-step-all! sched num-workers (+ i 1) (if executed? #t progress-made)))
      progress-made))

(define (%scheduler-run-loop sched target-done num-workers)
  (if (not (scheduler-running? sched))
      (scheduler-tasks-completed sched)
      (let* ((spawned (scheduler-tasks-spawned sched))
             (completed (scheduler-tasks-completed sched))
             (failed (scheduler-tasks-failed sched))
             (total-done (+ completed failed)))
        (if (or (>= total-done target-done)
                (and (>= total-done spawned) (> spawned 0)))
            total-done
            (let ((progress-made (%scheduler-step-all! sched num-workers 0 #f)))
              (if (not progress-made)
                  (let* ((c2 (scheduler-tasks-completed sched))
                         (f2 (scheduler-tasks-failed sched))
                         (tot2 (+ c2 f2))
                         (sp2 (scheduler-tasks-spawned sched)))
                    (if (and (>= tot2 sp2) (> sp2 0))
                        tot2
                        (begin
                          (%scheduler-idle-backoff!)
                          (%scheduler-run-loop sched target-done num-workers))))
                  (%scheduler-run-loop sched target-done num-workers)))))))

(define scheduler-run!
  (case-lambda
    ((sched)
     (scheduler-run! sched *scheduler-run-default-max-steps*))
    ((sched max-tasks)
     (if (not (work-stealing-scheduler? sched))
         (error "scheduler-run!: expected <work-stealing-scheduler>" sched)
         (let* ((c (scheduler-tasks-completed sched))
                (f (scheduler-tasks-failed sched))
                (target (+ (+ c f) max-tasks)))
           (%scheduler-run-loop sched target (scheduler-worker-count sched)))))))

(define (scheduler-stop! sched)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-stop!: expected <work-stealing-scheduler>" sched)
      (begin
        (atomic-set! (%scheduler-state-box sched) 'stopped)
        (%memory-fence)
        ;; Wake all workers so they immediately exit their park loop (Issue #676)
        (let ((n (scheduler-worker-count sched)))
          (let wake-loop ((i 0))
            (if (< i n)
                (let* ((w (scheduler-get-worker sched i))
                       (cell (worker-futex-cell w)))
                  (if cell ((vector-ref *scheduler-futex-unpark-box* 0) cell))
                  (wake-loop (+ i 1)))
                #t)))
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
                     (cons 'node-id (worker-node-id w))
                     (cons 'tasks-executed (worker-tasks-executed w))
                     (cons 'steals-attempted (worker-steals-attempted w))
                     (cons 'steals-succeeded (worker-steals-succeeded w))
                     (cons 'local-steals-attempted (worker-local-steals-attempted w))
                     (cons 'local-steals-succeeded (worker-local-steals-succeeded w))
                     (cons 'remote-steals-attempted (worker-remote-steals-attempted w))
                     (cons 'remote-steals-succeeded (worker-remote-steals-succeeded w))
                     (cons 'yields (worker-yields w))
                     (cons 'deque-count (deque-count (worker-deque w))))
               acc)))))

(define (scheduler-stats sched)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-stats: expected <work-stealing-scheduler>" sched)
      (let* ((num-workers (scheduler-worker-count sched))
             (num-nodes (scheduler-node-count sched))
             (worker-stats-list (%collect-worker-stats sched num-workers 0 '())))
        (list (cons 'worker-count num-workers)
              (cons 'node-count num-nodes)
              (cons 'state (scheduler-state sched))
              (cons 'tasks-spawned (scheduler-tasks-spawned sched))
              (cons 'tasks-completed (scheduler-tasks-completed sched))
              (cons 'tasks-failed (scheduler-tasks-failed sched))
              (cons 'live-tasks (scheduler-live-tasks sched))
              (cons 'global-queue-size (queue-size (scheduler-global-queue sched)))
              (cons 'workers worker-stats-list)))))

;; -----------------------------------------------------------------------
;; 8. Native Multithreading Engine (DSN-37 Section 7.4 & Issue #675)
;; -----------------------------------------------------------------------

(define (%scheduler-worker-native-loop sched worker-id)
  (begin
    ;; 1:1 CPU core pinning
    (guard (exn (else #f))
      (set-thread-affinity! worker-id))
    (let ((worker (scheduler-get-worker sched worker-id)))
      (let loop ()
        (if (scheduler-running? sched)
            (let ((executed? (guard (exn (else #f))
                               (scheduler-worker-step! sched worker-id))))
              (if (not executed?)
                  (begin
                    (%scheduler-idle-backoff!)
                    ;; If still no work, park via Linux futex with adaptive spin (Issue #676, #679)
                    (let ((cell (worker-futex-cell worker)))
                      (if (and cell (scheduler-running? sched))
                          ((vector-ref *scheduler-futex-park-adaptive-box* 0) cell 256 50)
                          #f)))
                  #f)
              (loop))
            #t)))))

(define (scheduler-start-native-workers! sched)
  (if (not (work-stealing-scheduler? sched))
      (error "scheduler-start-native-workers!: expected <work-stealing-scheduler>" sched)
      (let* ((num-workers (scheduler-worker-count sched))
             (tids-box (vector '())))
        ;; Spawn workers 1 to num-workers - 1 as OS native threads
        (let spawn-loop ((w 1))
          (if (< w num-workers)
              (let* ((worker-id w)
                     (tid (spawn-native-thread
                           (lambda (wid) (%scheduler-worker-native-loop sched wid))
                           worker-id)))
                (vector-set! tids-box 0 (cons tid (vector-ref tids-box 0)))
                (spawn-loop (+ w 1)))
              (reverse (vector-ref tids-box 0)))))))

(define scheduler-run-parallel!
  (case-lambda
    ((sched)
     (scheduler-run-parallel! sched *scheduler-run-default-max-steps*))
    ((sched max-tasks)
     (if (not (work-stealing-scheduler? sched))
         (error "scheduler-run-parallel!: expected <work-stealing-scheduler>" sched)
         (let* ((num-workers (scheduler-worker-count sched)))
           (if (<= num-workers 1)
               ;; Fallback to single-thread run if worker count <= 1
               (scheduler-run! sched max-tasks)
               (let* ((c (scheduler-tasks-completed sched))
                      (f (scheduler-tasks-failed sched))
                      (target (+ (+ c f) max-tasks))
                      (tids (scheduler-start-native-workers! sched)))
                 ;; Worker 0 runs on the calling (main) thread
                 (let main-loop ()
                   (if (not (scheduler-running? sched))
                       (scheduler-tasks-completed sched)
                       (let* ((spawned (scheduler-tasks-spawned sched))
                              (completed (scheduler-tasks-completed sched))
                              (failed (scheduler-tasks-failed sched))
                              (total-done (+ completed failed)))
                         (if (or (>= total-done target)
                                 (and (>= total-done spawned) (> spawned 0)))
                             (begin
                               (scheduler-stop! sched)
                               total-done)
                             (begin
                               (guard (exn (else #f))
                                 (scheduler-worker-step! sched 0))
                               (main-loop)))))))))))))


;; Connect scheduler-spawn! to supervisor automatic restart queueing (Issue #742)
(guard (exn (else #f))
  (if (procedure? synapse-set-supervisor-scheduler-spawn-hook!)
      (synapse-set-supervisor-scheduler-spawn-hook! scheduler-spawn!)))
