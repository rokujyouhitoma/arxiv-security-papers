;;; =======================================================================
;;; ULisp Runtime Concurrency: Linear Ownership Channel & Backpressure (channel.scm)
;;; Conforms to DSN-37 Section 4, 4.3.1, 6.1, 13.4 & Phase 1 Task 1.2 (Issue #633)
;;;
;;; Provides 1-to-1 zero-copy linear ownership transfer channels (<channel>)
;;; supporting both capacity=0 synchronous rendezvous and capacity>0 bounded
;;; buffering with deterministic producer backpressure suspension and wakeup,
;;; plus explicit deep-copy fan-out (broadcast-send!).
;;; =======================================================================

(include "ulisp/runtime/concurrency/queue.scm")
(include "ulisp/runtime/concurrency/futex.scm")

;; -----------------------------------------------------------------------
;; 1. Constants & Global Scheduler / Epoch Integration Hooks
;; -----------------------------------------------------------------------

(define *task-default-reductions* 4096)
(define *channel-max-capacity* 1048576)

(define (%asm-get-trampoline-addr which)
  (if (not (integer? which)) 0 0))

(define (%asm-set-handler-chain! chain-addr)
  (if (integer? chain-addr) #t #f))

(define (%asm-get-handler-chain)
  (%asm-get-trampoline-addr 6))

(define (%asm-current-worker-slot)
  (%asm-get-trampoline-addr 5))

;; Per-Worker Current Task TLS Table (64 worker slots, Issue #719)
(define *active-current-task-box* (make-atomic-box #f))
(define *worker-current-task-tls* (make-vector 64 #f))
(define *worker-slot-override-tls* (make-vector 64 #f))

(define (%current-worker-tls-index)
  (let ((hw-slot (%asm-current-worker-slot)))
    (if (and (integer? hw-slot) (>= hw-slot 0) (< hw-slot 64))
        (let ((logical (vector-ref *worker-slot-override-tls* hw-slot)))
          (if (and (integer? logical) (>= logical 0) (< logical 64))
              logical
              hw-slot))
        0)))

(define (%set-current-worker-tls-override! wid)
  (let ((hw-slot (%asm-current-worker-slot)))
    (if (and (integer? hw-slot) (>= hw-slot 0) (< hw-slot 64))
        (vector-set! *worker-slot-override-tls* hw-slot wid)
        #f)))

(define (current-synapse-task)
  (let ((idx (%current-worker-tls-index)))
    (vector-ref *worker-current-task-tls* idx)))

(define (%set-current-synapse-task! task)
  (let ((idx (%current-worker-tls-index)))
    (vector-set! *worker-current-task-tls* idx task)
    (atomic-set! *active-current-task-box* task)
    task))

;; Optional callback `(lambda (task) ...)` invoked when a suspended task
;; transitions from 'waiting-channel to 'ready.
(define *channel-wake-hook-box* (make-atomic-box #f))

(define (set-channel-wake-hook! proc)
  (if (and proc (not (procedure? proc)))
      (error "set-channel-wake-hook!: expected procedure or #f" proc)
      (atomic-set! *channel-wake-hook-box* proc)))

(define (channel-wake-hook)
  (atomic-ref *channel-wake-hook-box*))

;; Optional predicate `(lambda (task) ...)` for DSN-37 Section 8.3 Generation Gate.
;; Returns #t if the task's epoch is still valid; #f if speculative rollback aborted it.
(define *channel-epoch-validator-box* (make-atomic-box #f))

(define (set-channel-epoch-validator! proc)
  (if (and proc (not (procedure? proc)))
      (error "set-channel-epoch-validator!: expected procedure or #f" proc)
      (atomic-set! *channel-epoch-validator-box* proc)))

(define (channel-epoch-validator)
  (atomic-ref *channel-epoch-validator-box*))

;; -----------------------------------------------------------------------
;; 2. <task-context> (TCB) Record Type (DSN-37 Section 6.1)
;; -----------------------------------------------------------------------

(define-record-type <task-context>
  (%make-task-context tid state reductions continuation-pc stack-pointer
                      arena-base arena-offset arena-capacity
                      blocked-on epoch next-run
                      reduction-exhaustions steals-count handoff-box
                      links-box monitors-box monitored-by-box trap-exit-box owned-channels-box
                      arena-box escape-k-box handler-chain-box)
  task-context?
  (tid                   %task-tid)
  (state                 %task-state                 %task-state-set!)
  (reductions            %task-reductions            %task-reductions-set!)
  (continuation-pc       %task-continuation-pc       %task-continuation-pc-set!)
  (stack-pointer         %task-stack-pointer         %task-stack-pointer-set!)
  (arena-base            %task-arena-base)
  (arena-offset          %task-arena-offset          %task-arena-offset-set!)
  (arena-capacity        %task-arena-capacity)
  (blocked-on            %task-blocked-on            %task-blocked-on-set!)
  (epoch                 %task-epoch                 %task-epoch-set!)
  (next-run              %task-next-run              %task-next-run-set!)
  (reduction-exhaustions %task-reduction-exhaustions %task-reduction-exhaustions-set!)
  (steals-count          %task-steals-count          %task-steals-count-set!)
  (handoff-box           %task-handoff-box)
  (links-box             %task-links-box)
  (monitors-box          %task-monitors-box)
  (monitored-by-box      %task-monitored-by-box)
  (trap-exit-box         %task-trap-exit-box)
  (owned-channels-box    %task-owned-channels-box)
  (arena-box             %task-arena-box)
  (escape-k-box          %task-escape-k-box)
  (handler-chain-box     %task-handler-chain-box))

;; -----------------------------------------------------------------------
;; Global Monotonically Increasing Atomic Task ID Allocator (#673)
;; -----------------------------------------------------------------------

(define *task-next-id* (make-atomic-box 1))

(define (allocate-task-id!)
  (atomic-fetch-add! *task-next-id* 1))

(define (task-next-id-current)
  (atomic-ref *task-next-id*))

(define (task-reset-next-id! val)
  (if (not (integer? val))
      (error "task-reset-next-id!: val must be an integer" val)
      (atomic-set! *task-next-id* val)))

;; -----------------------------------------------------------------------
;; Global Lock-Free Task Table for O(1) TID Resolution (Issue #733, Item B2)
;; -----------------------------------------------------------------------

(define *task-table-bucket-count* 64)

(define *global-task-table-buckets*
  (let ((vec (make-vector *task-table-bucket-count* #f)))
    (let loop ((i 0))
      (if (< i *task-table-bucket-count*)
          (begin
            (vector-set! vec i (make-atomic-box '()))
            (loop (+ i 1)))
          vec))))

(define (%task-table-bucket-index tid)
  (let ((h (if (integer? tid) tid 0)))
    (modulo (if (< h 0) (- 0 h) h) *task-table-bucket-count*)))

(define (%task-table-assv tid xs)
  (let loop ((cur xs))
    (cond
      ((null? cur) #f)
      ((and (pair? (car cur)) (eqv? (caar cur) tid)) (car cur))
      (else (loop (cdr cur))))))

(define (task-table-register! task)
  (if (not (task-context? task))
      (error "task-table-register!: expected <task-context>" task)
      (let* ((tid (task-tid task))
             (idx (%task-table-bucket-index tid))
             (b-box (vector-ref *global-task-table-buckets* idx)))
        (let retry ()
          (let* ((cur (atomic-ref b-box))
                 (existing (%task-table-assv tid cur)))
            (if existing
                (let ((new-list (cons (cons tid task)
                                      (let remove-loop ((xs cur))
                                        (cond ((null? xs) '())
                                              ((eqv? (caar xs) tid) (cdr xs))
                                              (else (cons (car xs) (remove-loop (cdr xs)))))))))
                  (if (atomic-cas! b-box cur new-list)
                      #t
                      (retry)))
                (let ((new-list (cons (cons tid task) cur)))
                  (if (atomic-cas! b-box cur new-list)
                      #t
                      (retry)))))))))

(define (task-table-unregister! tid-or-task)
  (let ((tid (cond
               ((integer? tid-or-task) tid-or-task)
               ((task-context? tid-or-task) (task-tid tid-or-task))
               (else (error "task-table-unregister!: expected integer TID or <task-context>" tid-or-task)))))
    (let* ((idx (%task-table-bucket-index tid))
           (b-box (vector-ref *global-task-table-buckets* idx)))
      (let retry ()
        (let* ((cur (atomic-ref b-box))
               (existing (%task-table-assv tid cur)))
          (if (not existing)
              #f
              (let ((new-list (let remove-loop ((xs cur))
                                (cond ((null? xs) '())
                                      ((eqv? (caar xs) tid) (cdr xs))
                                      (else (cons (car xs) (remove-loop (cdr xs))))))))
                (if (atomic-cas! b-box cur new-list)
                    #t
                    (retry)))))))))

(define (lookup-task-by-tid tid)
  (if (not (integer? tid))
      #f
      (let* ((idx (%task-table-bucket-index tid))
             (b-box (vector-ref *global-task-table-buckets* idx))
             (cur (atomic-ref b-box))
             (pair (%task-table-assv tid cur)))
        (if pair
            (let ((task (cdr pair)))
              (if (and (task-context? task)
                       (not (eq? (%task-state task) 'terminated)))
                  task
                  #f))
            #f))))

(define task-by-id lookup-task-by-tid)

(define (task-table-clear!)
  (let loop ((i 0))
    (if (< i *task-table-bucket-count*)
        (begin
          (atomic-set! (vector-ref *global-task-table-buckets* i) '())
          (loop (+ i 1)))
        #t)))

(define (task-table-count)
  (let loop ((i 0) (count 0))
    (if (< i *task-table-bucket-count*)
        (let ((b-box (vector-ref *global-task-table-buckets* i)))
          (loop (+ i 1) (+ count (length (atomic-ref b-box)))))
        count)))

(define (%register-task-in-table! task)
  (guard (exn (else #f))
    (task-table-register! task))
  task)

(define make-task-context
  (case-lambda
    (()
     (let ((tid (allocate-task-id!)))
       (%register-task-in-table!
        (%make-task-context tid 'ready *task-default-reductions* 0 0
                            0 0 4096 #f 0 #f 0 0 (make-atomic-box #f)
                            (make-atomic-box '()) (make-atomic-box '())
                            (make-atomic-box '()) (make-atomic-box #f)
                            (make-atomic-box '())
                            (make-atomic-box #f) (make-atomic-box #f) (make-atomic-box 0)))))
    ((tid)
     (%register-task-in-table!
      (%make-task-context tid 'ready *task-default-reductions* 0 0
                          0 0 4096 #f 0 #f 0 0 (make-atomic-box #f)
                          (make-atomic-box '()) (make-atomic-box '())
                          (make-atomic-box '()) (make-atomic-box #f)
                          (make-atomic-box '())
                          (make-atomic-box #f) (make-atomic-box #f) (make-atomic-box 0))))
    ((tid epoch)
     (%register-task-in-table!
      (%make-task-context tid 'ready *task-default-reductions* 0 0
                          0 0 4096 #f epoch #f 0 0 (make-atomic-box #f)
                          (make-atomic-box '()) (make-atomic-box '())
                          (make-atomic-box '()) (make-atomic-box #f)
                          (make-atomic-box '())
                          (make-atomic-box #f) (make-atomic-box #f) (make-atomic-box 0))))
    ((tid state reductions continuation-pc stack-pointer
      arena-base arena-offset arena-capacity
      blocked-on epoch next-run
      reduction-exhaustions steals-count)
     (%register-task-in-table!
      (%make-task-context tid state reductions continuation-pc stack-pointer
                          arena-base arena-offset arena-capacity
                          blocked-on epoch next-run
                          reduction-exhaustions steals-count
                          (make-atomic-box #f)
                          (make-atomic-box '()) (make-atomic-box '())
                          (make-atomic-box '()) (make-atomic-box #f)
                          (make-atomic-box '())
                          (make-atomic-box #f) (make-atomic-box #f) (make-atomic-box 0))))))

(define (task-tid t)
  (if (not (task-context? t))
      (error "task-tid: expected <task-context>" t)
      (%task-tid t)))

(define (task-state t)
  (if (not (task-context? t))
      (error "task-state: expected <task-context>" t)
      (%task-state t)))

(define (task-state-set! t new-state)
  (if (not (task-context? t))
      (error "task-state-set!: expected <task-context>" t)
      (begin
        (%task-state-set! t new-state)
        (%memory-fence)
        new-state)))

(define (task-reductions t)
  (if (not (task-context? t))
      (error "task-reductions: expected <task-context>" t)
      (%task-reductions t)))

(define (task-reductions-set! t r)
  (if (not (task-context? t))
      (error "task-reductions-set!: expected <task-context>" t)
      (%task-reductions-set! t r)))

(define (task-continuation-pc t)
  (if (not (task-context? t))
      (error "task-continuation-pc: expected <task-context>" t)
      (%task-continuation-pc t)))

(define (task-continuation-pc-set! t pc)
  (if (not (task-context? t))
      (error "task-continuation-pc-set!: expected <task-context>" t)
      (%task-continuation-pc-set! t pc)))

(define (task-stack-pointer t)
  (if (not (task-context? t))
      (error "task-stack-pointer: expected <task-context>" t)
      (%task-stack-pointer t)))

(define (task-stack-pointer-set! t sp)
  (if (not (task-context? t))
      (error "task-stack-pointer-set!: expected <task-context>" t)
      (%task-stack-pointer-set! t sp)))

(define (task-arena-base t)
  (if (not (task-context? t))
      (error "task-arena-base: expected <task-context>" t)
      (%task-arena-base t)))

(define (task-arena-offset t)
  (if (not (task-context? t))
      (error "task-arena-offset: expected <task-context>" t)
      (%task-arena-offset t)))

(define (task-arena-offset-set! t off)
  (if (not (task-context? t))
      (error "task-arena-offset-set!: expected <task-context>" t)
      (%task-arena-offset-set! t off)))

(define (task-arena-capacity t)
  (if (not (task-context? t))
      (error "task-arena-capacity: expected <task-context>" t)
      (%task-arena-capacity t)))

(define (task-blocked-on t)
  (if (not (task-context? t))
      (error "task-blocked-on: expected <task-context>" t)
      (%task-blocked-on t)))

(define (task-blocked-on-set! t ch)
  (if (not (task-context? t))
      (error "task-blocked-on-set!: expected <task-context>" t)
      (begin
        (%task-blocked-on-set! t ch)
        (%memory-fence)
        ch)))

(define (task-epoch t)
  (if (not (task-context? t))
      (error "task-epoch: expected <task-context>" t)
      (%task-epoch t)))

(define (task-epoch-set! t ep)
  (if (not (task-context? t))
      (error "task-epoch-set!: expected <task-context>" t)
      (begin
        (%task-epoch-set! t ep)
        (%memory-fence)
        ep)))

(define (task-next-run t)
  (if (not (task-context? t))
      (error "task-next-run: expected <task-context>" t)
      (%task-next-run t)))

(define (task-next-run-set! t nxt)
  (if (not (task-context? t))
      (error "task-next-run-set!: expected <task-context>" t)
      (%task-next-run-set! t nxt)))

(define (task-reduction-exhaustions t)
  (if (not (task-context? t))
      (error "task-reduction-exhaustions: expected <task-context>" t)
      (%task-reduction-exhaustions t)))

(define (task-reduction-exhaustions-set! t n)
  (if (not (task-context? t))
      (error "task-reduction-exhaustions-set!: expected <task-context>" t)
      (%task-reduction-exhaustions-set! t n)))

(define (task-steals-count t)
  (if (not (task-context? t))
      (error "task-steals-count: expected <task-context>" t)
      (%task-steals-count t)))

(define (task-steals-count-set! t n)
  (if (not (task-context? t))
      (error "task-steals-count-set!: expected <task-context>" t)
      (%task-steals-count-set! t n)))

(define (task-has-handoff? t)
  (if (not (task-context? t))
      (error "task-has-handoff?: expected <task-context>" t)
      (pair? (atomic-ref (%task-handoff-box t)))))

(define (task-handoff-box t)
  (if (not (task-context? t))
      (error "task-handoff-box: expected <task-context>" t)
      (%task-handoff-box t)))

(define (task-handoff t)
  (if (not (task-context? t))
      (error "task-handoff: expected <task-context>" t)
      (let ((cur (atomic-ref (%task-handoff-box t))))
        (cond
          ((not (pair? cur)) #f)
          ((boolean? (car cur)) (cdr cur))
          ((pair? (car cur)) (cdar cur))
          (else (car cur))))))

(define (task-set-handoff! t val)
  (if (not (task-context? t))
      (error "task-set-handoff!: expected <task-context>" t)
      (let ((box (%task-handoff-box t))
            (entry (cons #t val)))
        (let retry ()
          (let* ((cur (atomic-ref box))
                 (cur-list (cond
                             ((not (pair? cur)) '())
                             ((boolean? (car cur)) (list cur))
                             (else cur)))
                 (next-list (append cur-list (list entry))))
            (if (atomic-cas! box cur next-list)
                (begin
                  (%memory-fence)
                  val)
                (retry)))))))

(define task-take-handoff!
  (case-lambda
    ((t) (task-take-handoff! t #f))
    ((t empty-default)
     (if (not (task-context? t))
         (error "task-take-handoff!: expected <task-context>" t)
         (let ((box (%task-handoff-box t)))
           (let retry ()
             (let ((cur (atomic-ref box)))
               (cond
                 ((not (pair? cur))
                  empty-default)
                 ((boolean? (car cur))
                  (if (atomic-cas! box cur #f)
                      (cdr cur)
                      (retry)))
                 (else
                  (let ((next (if (null? (cdr cur)) #f (cdr cur)))
                        (head (car cur)))
                    (if (atomic-cas! box cur next)
                        (if (pair? head) (cdr head) head)
                        (retry))))))))))))

;; Explicit Task Mailbox (FIFO Queue) API (Issue #726)
(define (task-mailbox-empty? t)
  (not (task-has-handoff? t)))

(define (task-mailbox-size t)
  (if (not (task-context? t))
      (error "task-mailbox-size: expected <task-context>" t)
      (let ((cur (atomic-ref (%task-handoff-box t))))
        (cond
          ((not (pair? cur)) 0)
          ((boolean? (car cur)) 1)
          (else (length cur))))))

(define (task-mailbox-enqueue! t val)
  (task-set-handoff! t val))

(define task-mailbox-dequeue! task-take-handoff!)

(define (task-mailbox-peek t)
  (task-handoff t))

;; 耐障害性・リンク・モニタ・チャネル所有メタデータアクセサ
(define (task-links-box t)
  (if (not (task-context? t))
      (error "task-links-box: expected <task-context>" t)
      (%task-links-box t)))

(define (task-links t)
  (let ((v (atomic-ref (task-links-box t))))
    (if (list? v) v '())))

(define (task-monitors-box t)
  (if (not (task-context? t))
      (error "task-monitors-box: expected <task-context>" t)
      (%task-monitors-box t)))

(define (task-monitors t)
  (let ((v (atomic-ref (task-monitors-box t))))
    (if (list? v) v '())))

(define (task-monitored-by-box t)
  (if (not (task-context? t))
      (error "task-monitored-by-box: expected <task-context>" t)
      (%task-monitored-by-box t)))

(define (task-monitored-by t)
  (let ((v (atomic-ref (task-monitored-by-box t))))
    (if (list? v) v '())))

(define (task-trap-exit? t)
  (if (not (task-context? t))
      (error "task-trap-exit?: expected <task-context>" t)
      (atomic-ref (%task-trap-exit-box t))))

(define (task-trap-exit! t val)
  (if (not (task-context? t))
      (error "task-trap-exit!: expected <task-context>" t)
      (let ((b (if val #t #f)))
        (atomic-set! (%task-trap-exit-box t) b)
        (%memory-fence)
        b)))

(define (task-owned-channels-box t)
  (if (not (task-context? t))
      (error "task-owned-channels-box: expected <task-context>" t)
      (%task-owned-channels-box t)))

(define (task-owned-channels t)
  (atomic-ref (task-owned-channels-box t)))

(define (task-arena-box t)
  (if (not (task-context? t))
      (error "task-arena-box: expected <task-context>" t)
      (%task-arena-box t)))

(define (task-arena t)
  (atomic-ref (task-arena-box t)))

(define (task-set-arena! t arena)
  (if (not (task-context? t))
      (error "task-set-arena!: expected <task-context>" t)
      (begin
        (atomic-set! (task-arena-box t) arena)
        arena)))

(define (task-escape-k-box t)
  (if (not (task-context? t))
      (error "task-escape-k-box: expected <task-context>" t)
      (%task-escape-k-box t)))

(define (task-escape-continuation t)
  (atomic-ref (task-escape-k-box t)))

(define (task-set-escape-continuation! t k)
  (if (not (task-context? t))
      (error "task-set-escape-continuation!: expected <task-context>" t)
      (begin
        (atomic-set! (task-escape-k-box t) k)
        k)))

(define (task-handler-chain-box t)
  (if (not (task-context? t))
      (error "task-handler-chain-box: expected <task-context>" t)
      (%task-handler-chain-box t)))

(define (task-handler-chain t)
  (atomic-ref (task-handler-chain-box t)))

(define (task-set-handler-chain! t hc)
  (if (not (task-context? t))
      (error "task-set-handler-chain!: expected <task-context>" t)
      (begin
        (atomic-set! (task-handler-chain-box t) hc)
        hc)))

;; -----------------------------------------------------------------------
;; Per-Worker Fallback Task Contexts & Default Task Boundary Hook (Issue #720)
;; -----------------------------------------------------------------------

(define *worker-fallback-task-tls*
  (let ((vec (make-vector 64 #f)))
    (let loop ((i 0))
      (if (< i 64)
          (begin
            (vector-set! vec i (%make-task-context (- -1000 i) 'ready *task-default-reductions* 0 0
                                                   0 0 4096 #f 0 #f 0 0 (make-atomic-box #f)
                                                   (make-atomic-box '()) (make-atomic-box '())
                                                   (make-atomic-box '()) (make-atomic-box #f)
                                                   (make-atomic-box '())
                                                   (make-atomic-box #f) (make-atomic-box #f) (make-atomic-box 0)))
            (loop (+ i 1)))
          vec))))

(define (%current-worker-fallback-task)
  (vector-ref *worker-fallback-task-tls* (%current-worker-tls-index)))

(define *synapse-boundary-escape-tag* (list 'synapse-boundary-escape))

(define (%default-with-synapse-task-boundary task thunk secure-scrub?)
  (if (not (task-context? task))
      (error "with-synapse-task-boundary: expected <task-context> (CWE-843)" task)
      (if (not (procedure? thunk))
          (error "with-synapse-task-boundary: expected procedure (CWE-843)" thunk)
          (let ((prev-task (current-synapse-task))
                (prev-k (task-escape-continuation task))
                (prev-hc (%asm-get-handler-chain))
                (task-hc (task-handler-chain task)))
            (let ((result
                   (guard (exn
                           ((and (pair? exn) (eq? (car exn) *synapse-boundary-escape-tag*))
                            (cdr exn))
                           (else
                            (task-state-set! task 'terminated)
                            (cons 'panic exn)))
                     (let* ((boundary-hc (%asm-get-handler-chain))
                            (escape-k (lambda (val)
                                        (%asm-set-handler-chain! boundary-hc)
                                        (raise (cons *synapse-boundary-escape-tag* val)))))
                       (task-set-escape-continuation! task escape-k)
                       (%set-current-synapse-task! task)
                       (if (and (integer? task-hc) (> task-hc 0))
                           (%asm-set-handler-chain! task-hc)
                           #f)
                       (with-exception-handler
                        (lambda (unhandled-exn)
                          (task-state-set! task 'terminated)
                          (escape-k (cons 'panic unhandled-exn)))
                        (lambda ()
                          (let ((res (thunk)))
                            (task-set-handler-chain! task (%asm-get-handler-chain))
                            (cons 'ok res))))))))
              (%asm-set-handler-chain! prev-hc)
              (task-set-escape-continuation! task prev-k)
              (%set-current-synapse-task! prev-task)
              result)))))

(define *synapse-task-boundary-hook-box*
  (make-atomic-box %default-with-synapse-task-boundary))

(define with-synapse-task-boundary
  (case-lambda
    ((task thunk)
     ((atomic-ref *synapse-task-boundary-hook-box*) task thunk #f))
    ((task thunk secure-scrub?)
     ((atomic-ref *synapse-task-boundary-hook-box*) task thunk secure-scrub?))))

;; Global hook for task normal termination cleanup (#741)
(define *task-exit-hook-box*
  (vector (lambda (t reason)
            (if (task-context? t)
                (task-state-set! t 'terminated)
                #f))))

(define (task-exit! task reason)
  (let ((hook (vector-ref *task-exit-hook-box* 0)))
    (if (procedure? hook)
        (hook task reason)
        #f)))

(define (task-register-channel! t ch)
  (if (not (task-context? t))
      (error "task-register-channel!: expected <task-context>" t)
      (if (not (channel? ch))
          (error "task-register-channel!: expected <channel>" ch)
          (let retry ()
            (let* ((box (%task-owned-channels-box t))
                   (cur (atomic-ref box)))
              (if (memq ch cur)
                  #t
                  (if (atomic-cas! box cur (cons ch cur))
                      #t
                      (retry))))))))

(define (task-unregister-channel! t ch)
  (if (not (task-context? t))
      (error "task-unregister-channel!: expected <task-context>" t)
      (if (not (channel? ch))
          (error "task-unregister-channel!: expected <channel>" ch)
          (let retry ()
            (let* ((box (%task-owned-channels-box t))
                   (cur (atomic-ref box)))
              (if (not (memq ch cur))
                  #t
                  (let ((new-list (let remove-ch ((xs cur))
                                    (cond ((null? xs) '())
                                          ((eq? (car xs) ch) (cdr xs))
                                          (else (cons (car xs) (remove-ch (cdr xs))))))))
                    (if (atomic-cas! box cur new-list)
                        #t
                        (retry)))))))))

(define task-poison-owned-channels!
  (case-lambda
    ((t) (task-poison-owned-channels! t 'killed #f))
    ((t reason) (task-poison-owned-channels! t reason #f))
    ((t reason wake-hook)
     (if (not (task-context? t))
         (error "task-poison-owned-channels!: expected <task-context>" t)
         (let ((chs (atomic-swap! (%task-owned-channels-box t) '())))
           (let loop ((xs chs))
             (if (null? xs)
                 #t
                 (begin
                   (channel-poison! (car xs) reason wake-hook)
                   (loop (cdr xs))))))))))

;; -----------------------------------------------------------------------
;; 3. <channel-waiter> Record Type (Wait Queue Entry)
;; -----------------------------------------------------------------------

(define-record-type <channel-waiter>
  (%make-channel-waiter task payload-box state-box)
  channel-waiter?
  (task %waiter-task)
  (payload-box %waiter-payload-box)
  (state-box %waiter-state-box))

(define (make-channel-waiter task payload)
  (if (and task (not (task-context? task)))
      (error "make-channel-waiter: expected <task-context> or #f" task)
      (%make-channel-waiter task
                            (make-atomic-box payload)
                            (make-atomic-box 'waiting))))

(define (channel-waiter-task w)
  (if (not (channel-waiter? w))
      (error "channel-waiter-task: expected <channel-waiter>" w)
      (%waiter-task w)))

(define (channel-waiter-state w)
  (if (not (channel-waiter? w))
      (error "channel-waiter-state: expected <channel-waiter>" w)
      (atomic-ref (%waiter-state-box w))))

;; -----------------------------------------------------------------------
;; 4. <channel> Record Type & Construction (DSN-37 Section 6.1, Issue #680)
;; -----------------------------------------------------------------------

(define *ring-empty* (list '%%ring-empty%%))

;; Fast pure utility to round up capacity to the nearest power of two (Issue #684)
(define (%round-to-power-of-two n)
  (if (<= n 1)
      1
      (let loop ((p 1))
        (if (>= p n)
            p
            (loop (* p 2))))))

(define-record-type <channel>
  (%make-channel message-queue recv-wait-queue send-wait-queue
                 capacity current-count closed-box
                 sent-count-box received-count-box
                 backpressure-count-box handoff-count-box
                 ring-buffer ring-head-box ring-tail-box ring-mask
                 spsc?)
  channel?
  (message-queue          %channel-message-queue)
  (recv-wait-queue        %channel-recv-wait-queue)
  (send-wait-queue        %channel-send-wait-queue)
  (capacity               %channel-capacity)
  (current-count          %channel-current-count)
  (closed-box             %channel-closed-box)
  (sent-count-box         %channel-sent-count-box)
  (received-count-box     %channel-received-count-box)
  (backpressure-count-box %channel-backpressure-count-box)
  (handoff-count-box      %channel-handoff-count-box)
  (ring-buffer            %channel-ring-buffer)
  (ring-head-box          %channel-ring-head-box)
  (ring-tail-box          %channel-ring-tail-box)
  (ring-mask              %channel-ring-mask)
  (spsc?                  %channel-spsc?))

(define (%make-channel-instance capacity spsc?)
  (if (or (not (integer? capacity))
          (< capacity 0)
          (> capacity *channel-max-capacity*))
      (error "make-channel: capacity must be an integer in [0, *channel-max-capacity*]" capacity)
      (let* ((ring-cap (if (> capacity 0) (%round-to-power-of-two capacity) 0))
             (ring-mask (if (> ring-cap 0) (- ring-cap 1) #f))
             (ring (if (> ring-cap 0)
                       (make-vector ring-cap *ring-empty*)
                       #f))
             (head-box (if (> ring-cap 0) (make-padded-atomic-box 0) #f))
             (tail-box (if (> ring-cap 0) (make-padded-atomic-box 0) #f))
             (ch (%make-channel (make-lock-free-queue)
                                (make-lock-free-queue)
                                (make-lock-free-queue)
                                capacity
                                (make-padded-atomic-box 0)
                                (make-atomic-box #f)
                                (make-padded-atomic-box 0)
                                (make-padded-atomic-box 0)
                                (make-padded-atomic-box 0)
                                (make-padded-atomic-box 0)
                                ring
                                head-box
                                tail-box
                                ring-mask
                                (if spsc? #t #f))))
        (%memory-fence)
        ;; Auto-register created channel to currently running task (Issue #731, Item A6)
        (guard (exn (else #f))
          (let ((cur-task (current-synapse-task)))
            (if (task-context? cur-task)
                (task-register-channel! cur-task ch)
                #f)))
        ch)))

(define make-channel
  (case-lambda
    (()
     (%make-channel-instance 0 #f))
    ((capacity)
     (%make-channel-instance capacity #f))
    ((capacity spsc?)
     (%make-channel-instance capacity spsc?))))

(define make-spsc-channel
  (case-lambda
    (()
     (%make-channel-instance 0 #t))
    ((capacity)
     (%make-channel-instance capacity #t))))

(define (channel-spsc? ch)
  (if (not (channel? ch))
      (error "channel-spsc?: expected <channel>" ch)
      (%channel-spsc? ch)))

;; DSN-37 Section 6.1 5-argument constructor compatibility
(define (make-channel-internal message-queue recv-wait-queue send-wait-queue capacity current-count)
  (if (or (not (lock-free-queue? message-queue))
          (not (lock-free-queue? recv-wait-queue))
          (not (lock-free-queue? send-wait-queue)))
      (error "make-channel-internal: queues must be <lock-free-queue>" message-queue)
      (if (or (not (integer? capacity)) (< capacity 0) (> capacity *channel-max-capacity*))
          (error "make-channel-internal: invalid capacity" capacity)
          (let* ((cnt-box (cond
                            ((or (atomic-box? current-count) (padded-atomic-box? current-count))
                             current-count)
                            ((integer? current-count)
                             (make-padded-atomic-box current-count))
                            (else (make-padded-atomic-box 0))))
                 (ring-cap (if (> capacity 0) (%round-to-power-of-two capacity) 0))
                 (ring-mask (if (> ring-cap 0) (- ring-cap 1) #f))
                 (ring (if (> ring-cap 0)
                           (make-vector ring-cap *ring-empty*)
                           #f))
                 (head-box (if (> ring-cap 0) (make-padded-atomic-box 0) #f))
                 (tail-box (if (> ring-cap 0) (make-padded-atomic-box 0) #f)))
            (%make-channel message-queue
                           recv-wait-queue
                           send-wait-queue
                           capacity
                           cnt-box
                           (make-atomic-box #f)
                           (make-padded-atomic-box 0)
                           (make-padded-atomic-box 0)
                           (make-padded-atomic-box 0)
                           (make-padded-atomic-box 0)
                           ring
                           head-box
                           tail-box
                           ring-mask
                           #f)))))

(define (channel-message-queue ch)
  (if (not (channel? ch))
      (error "channel-message-queue: expected <channel>" ch)
      (%channel-message-queue ch)))

(define (channel-recv-wait-queue ch)
  (if (not (channel? ch))
      (error "channel-recv-wait-queue: expected <channel>" ch)
      (%channel-recv-wait-queue ch)))

(define (channel-send-wait-queue ch)
  (if (not (channel? ch))
      (error "channel-send-wait-queue: expected <channel>" ch)
      (%channel-send-wait-queue ch)))

(define (channel-capacity ch)
  (if (not (channel? ch))
      (error "channel-capacity: expected <channel>" ch)
      (%channel-capacity ch)))

(define (channel-current-count ch)
  (if (not (channel? ch))
      (error "channel-current-count: expected <channel>" ch)
      (%channel-current-count ch)))

(define (channel-ring-buffer ch)
  (if (not (channel? ch))
      (error "channel-ring-buffer: expected <channel>" ch)
      (%channel-ring-buffer ch)))

(define (channel-ring-mask ch)
  (if (not (channel? ch))
      (error "channel-ring-mask: expected <channel>" ch)
      (%channel-ring-mask ch)))

(define (channel-unboxed? ch)
  (if (not (channel? ch))
      (error "channel-unboxed?: expected <channel>" ch)
      (and (> (%channel-capacity ch) 0)
           (vector? (%channel-ring-buffer ch)))))

(define (channel-count ch)
  (if (not (channel? ch))
      (error "channel-count: expected <channel>" ch)
      (if (and (%channel-spsc? ch) (> (%channel-capacity ch) 0))
          (- (padded-atomic-ref (%channel-ring-head-box ch))
             (padded-atomic-ref (%channel-ring-tail-box ch)))
          (atomic-ref (%channel-current-count ch)))))

(define (channel-closed? ch)
  (if (not (channel? ch))
      (error "channel-closed?: expected <channel>" ch)
      (let ((val (atomic-ref (%channel-closed-box ch))))
        (if val #t #f))))

(define (channel-poisoned? ch)
  (if (not (channel? ch))
      (error "channel-poisoned?: expected <channel>" ch)
      (eq? (atomic-ref (%channel-closed-box ch)) 'poisoned)))

(define (channel-empty? ch)
  (if (not (channel? ch))
      (error "channel-empty?: expected <channel>" ch)
      (if (and (%channel-spsc? ch) (> (%channel-capacity ch) 0))
          (= (padded-atomic-ref (%channel-ring-head-box ch))
             (padded-atomic-ref (%channel-ring-tail-box ch)))
          (and (= (atomic-ref (%channel-current-count ch)) 0)
               (if (%channel-ring-buffer ch)
                   #t
                   (queue-empty? (%channel-message-queue ch)))))))

(define (channel-full? ch)
  (if (not (channel? ch))
      (error "channel-full?: expected <channel>" ch)
      (if (and (%channel-spsc? ch) (> (%channel-capacity ch) 0))
          (>= (- (padded-atomic-ref (%channel-ring-head-box ch))
                 (padded-atomic-ref (%channel-ring-tail-box ch)))
              (%channel-capacity ch))
          (let ((cap (%channel-capacity ch)))
            (if (= cap 0)
                (queue-empty? (%channel-recv-wait-queue ch))
                (>= (atomic-ref (%channel-current-count ch)) cap))))))

;; -----------------------------------------------------------------------
;; 4b. Ring Buffer Operations (MPMC & SPSC Lamport Fast-Path)
;; -----------------------------------------------------------------------

;; SPSC Lamport Ring Buffer (Issue #687): Zero LOCK Instructions!
;; Producer uniquely updates head-box; Consumer uniquely updates tail-box.
(define (%channel-spsc-try-enqueue! ch val)
  (let ((ring (%channel-ring-buffer ch)))
    (if (not ring)
        #f
        (let* ((cap (%channel-capacity ch))
               (mask (%channel-ring-mask ch))
               (head-box (%channel-ring-head-box ch))
               (tail-box (%channel-ring-tail-box ch))
               (head (padded-atomic-ref head-box))
               (tail (padded-atomic-ref tail-box)))
          (if (>= (- head tail) cap)
              #f
              (let ((slot-idx (bitwise-and head mask)))
                (vector-set! ring slot-idx val)
                (%memory-fence)
                (padded-atomic-set! head-box (+ head 1))
                #t))))))

(define (channel-spsc-try-enqueue! ch val)
  (if (not (channel? ch))
      (error "channel-spsc-try-enqueue!: expected <channel>" ch)
      (%channel-spsc-try-enqueue! ch val)))

(define (%channel-spsc-try-dequeue-val! ch)
  (let ((ring (%channel-ring-buffer ch)))
    (if (not ring)
        *ring-empty*
        (let* ((mask (%channel-ring-mask ch))
               (head-box (%channel-ring-head-box ch))
               (tail-box (%channel-ring-tail-box ch))
               (tail (padded-atomic-ref tail-box))
               (head (padded-atomic-ref head-box)))
          (if (>= tail head)
              *ring-empty*
              (let* ((slot-idx (bitwise-and tail mask))
                     (val (vector-ref ring slot-idx)))
                (vector-set! ring slot-idx *ring-empty*)
                (%memory-fence)
                (padded-atomic-set! tail-box (+ tail 1))
                val))))))

(define (channel-spsc-try-dequeue-val! ch)
  (if (not (channel? ch))
      (error "channel-spsc-try-dequeue-val!: expected <channel>" ch)
      (%channel-spsc-try-dequeue-val! ch)))

;; MPMC Ring Buffer (Issue #680 Unboxed Fast-Path & Issue #684 Bitmask)
(define (%channel-ring-try-enqueue! ch val)
  (let ((ring (%channel-ring-buffer ch)))
    (if (not ring)
        #f
        (let ((cap (%channel-capacity ch))
              (mask (%channel-ring-mask ch))
              (head-box (%channel-ring-head-box ch))
              (tail-box (%channel-ring-tail-box ch)))
          (let retry ()
            (let ((cur-head (atomic-ref head-box))
                  (cur-tail (atomic-ref tail-box)))
              (if (>= (- cur-head cur-tail) cap)
                  #f
                  (if (atomic-cas! head-box cur-head (+ cur-head 1))
                      (let* ((slot-idx (bitwise-and cur-head mask)))
                        (let spin ()
                          (let ((old (vector-ref ring slot-idx)))
                            (if (not (eq? old *ring-empty*))
                                (begin
                                  (futex-spin-pause! 4)
                                  (spin))
                                (begin
                                  (vector-set! ring slot-idx val)
                                  (%memory-fence)
                                  #t)))))
                      (retry)))))))))

(define (%channel-ring-try-dequeue-val! ch)
  (let ((ring (%channel-ring-buffer ch)))
    (if (not ring)
        *ring-empty*
        (let ((cap (%channel-capacity ch))
              (mask (%channel-ring-mask ch))
              (head-box (%channel-ring-head-box ch))
              (tail-box (%channel-ring-tail-box ch)))
          (let retry ()
            (let ((cur-tail (atomic-ref tail-box))
                  (cur-head (atomic-ref head-box)))
              (if (>= cur-tail cur-head)
                  *ring-empty*
                  (if (atomic-cas! tail-box cur-tail (+ cur-tail 1))
                      (let* ((slot-idx (bitwise-and cur-tail mask)))
                        (let spin ()
                          (let ((val (vector-ref ring slot-idx)))
                            (if (eq? val *ring-empty*)
                                (begin
                                  (futex-spin-pause! 4)
                                  (spin))
                                (begin
                                  (vector-set! ring slot-idx *ring-empty*)
                                  (%memory-fence)
                                  val)))))
                      (retry)))))))))

(define (channel-try-dequeue-val! ch)
  (if (not (channel? ch))
      (error "channel-try-dequeue-val!: expected <channel>" ch)
      (if (and (%channel-spsc? ch) (> (%channel-capacity ch) 0))
          (let ((msg (%channel-spsc-try-dequeue-val! ch)))
            (if (not (eq? msg *ring-empty*))
                (begin
                  (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                    (if send-waiter
                        (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                              (sender-task (%waiter-task send-waiter)))
                          (%channel-spsc-try-enqueue! ch promoted-val)
                          (%wake-task! sender-task #f))))
                  msg)
                *ring-empty*))
          (let ((val (%channel-ring-try-dequeue-val! ch)))
            (if (eq? val *ring-empty*)
                *ring-empty*
                (begin
                  (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                    (if send-waiter
                        (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                              (sender-task (%waiter-task send-waiter)))
                          (%channel-ring-try-enqueue! ch promoted-val)
                          (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                          (%wake-task! sender-task #f))
                        (atomic-fetch-add! (%channel-current-count ch) -1)))
                  (atomic-fetch-add! (%channel-received-count-box ch) 1)
                  val))))))

(define (%channel-ring-try-dequeue! ch)
  (let ((val (if (and (%channel-spsc? ch) (> (%channel-capacity ch) 0))
                 (%channel-spsc-try-dequeue-val! ch)
                 (%channel-ring-try-dequeue-val! ch))))
    (if (eq? val *ring-empty*)
        #f
        (cons #t val))))

;; -----------------------------------------------------------------------
;; 5. Internal Waiter Claiming, Epoch Validation & Task Wakeup Helpers
;; -----------------------------------------------------------------------

(define (%task-epoch-valid? task)
  (if (not task)
      #t
      (if (eq? (%task-state task) 'terminated)
          #f
          (let ((validator (atomic-ref *channel-epoch-validator-box*)))
            (if validator
                (validator task)
                #t)))))

(define (%wake-task! task wake-hook)
  (if (and task (not (eq? (%task-state task) 'terminated)))
      (begin
        (%task-blocked-on-set! task #f)
        (%task-state-set! task 'ready)
        (%memory-fence)
        (let ((hook (or wake-hook (atomic-ref *channel-wake-hook-box*))))
          (if hook
              (hook task))))))

(define task-wake!
  (case-lambda
    ((task) (%wake-task! task #f))
    ((task wake-hook) (%wake-task! task wake-hook))))

;; Pop next valid, unclaimed <channel-waiter> from a wait queue.
;; Any waiter whose task fails the Generation Gate is transitioned to 'terminated.
(define (%pop-live-waiter! wait-q)
  (let loop ()
    (let ((st (dequeue-lockfree-with-status! wait-q)))
      (if (not (car st))
          #f
          (let ((w (cdr st)))
            (if (not (channel-waiter? w))
                (loop)
                (let ((task (%waiter-task w)))
                  (if (not (%task-epoch-valid? task))
                      (begin
                        ;; Generation Gate (DSN-37 Section 8.3): abort stale task
                        (atomic-set! (%waiter-payload-box w) #f)
                        (atomic-set! (%waiter-state-box w) 'aborted)
                        (if task
                            (begin
                              (%task-blocked-on-set! task #f)
                              (%task-state-set! task 'terminated)))
                        (loop))
                      (if (atomic-cas! (%waiter-state-box w) 'waiting 'claimed)
                          w
                          (loop))))))))))

;; -----------------------------------------------------------------------
;; 6. Linear Ownership Transfer Send & Backpressure (DSN-37 4.1 & 4.3.1)
;; -----------------------------------------------------------------------

;; Try to atomically reserve 1 slot in bounded buffer (when capacity > 0).
(define (%try-reserve-buffer-slot! ch)
  (let ((cap (%channel-capacity ch))
        (cnt-box (%channel-current-count ch)))
    (if (<= cap 0)
        #f
        (let retry ()
          (let ((cur (atomic-ref cnt-box)))
            (if (>= cur cap)
                #f
                (if (atomic-cas! cnt-box cur (+ cur 1))
                    #t
                    (retry))))))))

(define (%channel-send-core! ch val sender-task wake-hook allow-suspend?)
  (if (not (channel? ch))
      (error "channel-send!: expected <channel>" ch)
      (if (and sender-task (not (task-context? sender-task)))
          (error "channel-send!: expected <task-context> or #f" sender-task)
          (let ((closed-state (atomic-ref (%channel-closed-box ch))))
            (cond
              ((eq? closed-state 'poisoned)
               (if (not allow-suspend?)
                   (cons #f 'poisoned)
                   (error "channel-send!: cannot send on poisoned channel (CWE-833)" ch)))
              (closed-state
               (error "channel-send!: cannot send on closed channel" ch))
              (else
               (if (and (%channel-spsc? ch) (> (%channel-capacity ch) 0))
                   ;; SPSC Zero-LOCK Fast-Path: enqueue directly without wait-queue CAS
                   (if (%channel-spsc-try-enqueue! ch val)
                       (begin
                         (if (> (queue-size (%channel-recv-wait-queue ch)) 0)
                             (let ((recv-waiter (%pop-live-waiter! (%channel-recv-wait-queue ch))))
                               (if recv-waiter
                                   (let ((recv-task (%waiter-task recv-waiter)))
                                     (%wake-task! recv-task wake-hook)))))
                         #t)
                       ;; SPSC Buffer full -> Backpressure suspend
                       (if (not allow-suspend?)
                           #f
                           (let ((waiter (make-channel-waiter sender-task val)))
                             (if sender-task
                                 (begin
                                   (%task-blocked-on-set! sender-task ch)
                                   (%task-state-set! sender-task 'waiting-channel)
                                   (%memory-fence)))
                             (enqueue-lockfree! (%channel-send-wait-queue ch) waiter)
                             (atomic-fetch-add! (%channel-backpressure-count-box ch) 1)
                             'suspended)))
                   ;; Fast Path 1: Direct zero-copy handoff to a waiting receiver
                   (let ((recv-waiter (%pop-live-waiter! (%channel-recv-wait-queue ch))))
                     (if recv-waiter
                         (let ((recv-task (%waiter-task recv-waiter)))
                           (if recv-task
                               (task-set-handoff! recv-task val)
                               (atomic-set! (%waiter-payload-box recv-waiter) val))
                           (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                           (atomic-fetch-add! (%channel-received-count-box ch) 1)
                           (atomic-fetch-add! (%channel-handoff-count-box ch) 1)
                           (%wake-task! recv-task wake-hook)
                           #t)
                         ;; Fast Path 2: Enqueue into bounded ring buffer if space is available
                         (if (and (> (%channel-capacity ch) 0)
                                  (%channel-ring-try-enqueue! ch val))
                             (begin
                               (atomic-fetch-add! (%channel-current-count ch) 1)
                               (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                               #t)
                             ;; Slow Path: Buffer full (or capacity = 0) -> Backpressure suspend
                             (if (not allow-suspend?)
                                 #f
                                 (let ((waiter (make-channel-waiter sender-task val)))
                                   (if sender-task
                                       (begin
                                         (%task-blocked-on-set! sender-task ch)
                                         (%task-state-set! sender-task 'waiting-channel)
                                         (%memory-fence)))
                                   (enqueue-lockfree! (%channel-send-wait-queue ch) waiter)
                                   (atomic-fetch-add! (%channel-backpressure-count-box ch) 1)
                                   'suspended))))))))))))

;; Direct SPSC 2-argument fast-path (bypasses case-lambda / sender-task checks)
(define (%channel-send-fast-2! ch val)
  (if (not (channel? ch))
      (error "channel-send!: expected <channel>" ch)
      (if (and (%channel-spsc? ch) (> (%channel-capacity ch) 0))
          (if (%channel-spsc-try-enqueue! ch val)
              (begin
                (if (> (queue-size (%channel-recv-wait-queue ch)) 0)
                    (let ((recv-waiter (%pop-live-waiter! (%channel-recv-wait-queue ch))))
                      (if recv-waiter
                          (let ((recv-task (%waiter-task recv-waiter)))
                            (%wake-task! recv-task #f)))))
                #t)
              (%channel-send-core! ch val #f #f #t))
          (%channel-send-core! ch val #f #f #t))))

(define channel-send!
  (case-lambda
    ((ch val)
     (%channel-send-fast-2! ch val))
    ((ch val sender-task)
     (%channel-send-core! ch val sender-task #f #t))
    ((ch val sender-task wake-hook)
     (%channel-send-core! ch val sender-task wake-hook #t))))

(define (channel-try-send! ch val)
  (%channel-send-core! ch val #f #f #f))

(define channel-send-unboxed!
  (case-lambda
    ((ch val)
     (%channel-send-fast-2! ch val))
    ((ch val sender-task)
     (%channel-send-core! ch val sender-task #f #t))
    ((ch val sender-task wake-hook)
     (%channel-send-core! ch val sender-task wake-hook #t))))

(define (channel-try-send-unboxed! ch val)
  (%channel-send-core! ch val #f #f #f))

;; -----------------------------------------------------------------------
;; 7. Linear Ownership Transfer Receive & Backpressure Relief (DSN-37 4.3.1)
;; -----------------------------------------------------------------------

(define (%channel-recv-core! ch receiver-task wake-hook allow-suspend? empty-default)
  (if (not (channel? ch))
      (error "channel-recv!: expected <channel>" ch)
      (if (and receiver-task (not (task-context? receiver-task)))
          (error "channel-recv!: expected <task-context> or #f" receiver-task)
          ;; Fast Path 1: Buffered message in ring buffer (when capacity > 0)
          (let ((msg (if (> (%channel-capacity ch) 0)
                         (%channel-ring-try-dequeue-val! ch)
                         *ring-empty*)))
            (if (not (eq? msg *ring-empty*))
                (begin
                  (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                    (if send-waiter
                        ;; Backpressure relief: promote waiting sender's payload into ring buffer!
                        (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                              (sender-task (%waiter-task send-waiter)))
                          (%channel-ring-try-enqueue! ch promoted-val)
                          (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                          (%wake-task! sender-task wake-hook))
                        ;; No waiting sender; decrement buffered message count
                        (atomic-fetch-add! (%channel-current-count ch) -1)))
                  (atomic-fetch-add! (%channel-received-count-box ch) 1)
                  (cons #t msg))
                ;; Fallback to legacy queue (if capacity was 0 or populated via internal queue)
                (let ((deq (dequeue-lockfree-with-status! (%channel-message-queue ch))))
                  (if (car deq)
                      (let ((msg (cdr deq))
                            (send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                        (if send-waiter
                            (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                                  (sender-task (%waiter-task send-waiter)))
                              (enqueue-lockfree! (%channel-message-queue ch) promoted-val)
                              (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                              (%wake-task! sender-task wake-hook))
                            (atomic-fetch-add! (%channel-current-count ch) -1))
                        (atomic-fetch-add! (%channel-received-count-box ch) 1)
                        (cons #t msg))
                      ;; Fast Path 2: Direct rendezvous handoff from a waiting sender
                      (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                        (if send-waiter
                            (let ((val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                                  (sender-task (%waiter-task send-waiter)))
                              (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                              (atomic-fetch-add! (%channel-received-count-box ch) 1)
                              (atomic-fetch-add! (%channel-handoff-count-box ch) 1)
                              (%wake-task! sender-task wake-hook)
                              (cons #t val))
                            ;; Slow Path: No buffered message and no waiting sender
                            (let ((closed-state (atomic-ref (%channel-closed-box ch))))
                              (cond
                                ((eq? closed-state 'poisoned)
                                 (cons #f 'poisoned))
                                (closed-state
                                 (cons #f 'closed))
                                (else
                                 (if (not allow-suspend?)
                                     (cons #f empty-default)
                                     (let ((waiter (make-channel-waiter receiver-task #f)))
                                       (if receiver-task
                                           (begin
                                             (%task-blocked-on-set! receiver-task ch)
                                             (%task-state-set! receiver-task 'waiting-channel)
                                             (%memory-fence)))
                                       (enqueue-lockfree! (%channel-recv-wait-queue ch) waiter)
                                       (cons #f 'suspended)))))))))))))))

(define (%channel-recv-val! ch receiver-task wake-hook allow-suspend? empty-default)
  (if (not (channel? ch))
      (error "channel-recv!: expected <channel>" ch)
      (if (and receiver-task (not (task-context? receiver-task)))
          (error "channel-recv!: expected <task-context> or #f" receiver-task)
          (if (and (%channel-spsc? ch) (> (%channel-capacity ch) 0))
              ;; SPSC Zero-LOCK Fast-Path
              (let ((msg (%channel-spsc-try-dequeue-val! ch)))
                (if (not (eq? msg *ring-empty*))
                    (begin
                      (if (> (queue-size (%channel-send-wait-queue ch)) 0)
                          (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                            (if send-waiter
                                (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                                      (sender-task (%waiter-task send-waiter)))
                                  (%channel-spsc-try-enqueue! ch promoted-val)
                                  (%wake-task! sender-task wake-hook)))))
                      msg)
                    (cdr (%channel-recv-core! ch receiver-task wake-hook allow-suspend? empty-default))))
              ;; MPMC Fast-Path
              (let ((msg (if (> (%channel-capacity ch) 0)
                             (%channel-ring-try-dequeue-val! ch)
                             *ring-empty*)))
                (if (not (eq? msg *ring-empty*))
                    (begin
                      (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                        (if send-waiter
                            ;; Backpressure relief: promote waiting sender's payload into ring buffer!
                            (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                                  (sender-task (%waiter-task send-waiter)))
                              (%channel-ring-try-enqueue! ch promoted-val)
                              (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                              (%wake-task! sender-task wake-hook))
                            ;; No waiting sender; decrement buffered message count
                            (atomic-fetch-add! (%channel-current-count ch) -1)))
                      (atomic-fetch-add! (%channel-received-count-box ch) 1)
                      msg)
                    (cdr (%channel-recv-core! ch receiver-task wake-hook allow-suspend? empty-default))))))))

;; Direct SPSC 1-argument fast-path (bypasses case-lambda / receiver-task checks)
(define (%channel-recv-fast-1! ch)
  (if (not (channel? ch))
      (error "channel-recv!: expected <channel>" ch)
      (if (and (%channel-spsc? ch) (> (%channel-capacity ch) 0))
          (let ((msg (%channel-spsc-try-dequeue-val! ch)))
            (if (not (eq? msg *ring-empty*))
                (begin
                  (if (> (queue-size (%channel-send-wait-queue ch)) 0)
                      (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                        (if send-waiter
                            (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                                  (sender-task (%waiter-task send-waiter)))
                              (%channel-spsc-try-enqueue! ch promoted-val)
                              (%wake-task! sender-task #f)))))
                  msg)
                (cdr (%channel-recv-core! ch #f #f #t 'suspended))))
          (%channel-recv-val! ch #f #f #t 'suspended))))

(define channel-recv!
  (case-lambda
    ((ch)
     (%channel-recv-fast-1! ch))
    ((ch receiver-task)
     (%channel-recv-val! ch receiver-task #f #t 'suspended))
    ((ch receiver-task wake-hook)
     (%channel-recv-val! ch receiver-task wake-hook #t 'suspended))))

(define channel-try-recv!
  (case-lambda
    ((ch)
     (%channel-recv-val! ch #f #f #f #f))
    ((ch empty-default)
     (%channel-recv-val! ch #f #f #f empty-default))))

(define (channel-try-recv-with-status! ch)
  (%channel-recv-core! ch #f #f #f #f))

;; -----------------------------------------------------------------------
;; 7a. Monotonic Deadline Channel Receive with Timeout (Issue #729, Item C6)
;; -----------------------------------------------------------------------

(define (%channel-monotonic-ms)
  (let ((ts (sys-clock-gettime-monotonic)))
    (if (pair? ts)
        (+ (* (car ts) 1000) (quotient (cdr ts) 1000000))
        0)))

(define (%prune-inactive-waiters! wait-q)
  (let ((n (queue-size wait-q)))
    (let loop ((i 0))
      (if (< i n)
          (let ((st (dequeue-lockfree-with-status! wait-q)))
            (if (car st)
                (let ((w (cdr st)))
                  (if (and (channel-waiter? w)
                           (eq? (atomic-ref (%waiter-state-box w)) 'waiting))
                      (enqueue-lockfree! wait-q w))
                  (loop (+ i 1)))))))))

(define channel-recv-timeout!
  (case-lambda
    ((ch timeout-ms)
     (channel-recv-timeout! ch timeout-ms #f))
    ((ch timeout-ms receiver-task)
     (if (not (channel? ch))
         (error "channel-recv-timeout!: expected <channel> (CWE-843)" ch)
         (if (or (not (integer? timeout-ms)) (< timeout-ms 0))
             (error "channel-recv-timeout!: timeout-ms must be a non-negative integer (CWE-843)" timeout-ms)
             (if (and receiver-task (not (task-context? receiver-task)))
                 (error "channel-recv-timeout!: expected <task-context> or #f (CWE-843)" receiver-task)
                 ;; Fast Path: try immediate non-blocking receive first
                 (let ((fast (%channel-recv-core! ch #f #f #f 'empty)))
                   (cond
                     ((car fast)
                      fast)
                     ((or (eq? (cdr fast) 'closed) (eq? (cdr fast) 'poisoned))
                      fast)
                     ((= timeout-ms 0)
                      (cons #f 'timeout))
                     (else
                      ;; Register a <channel-waiter> in recv-wait-queue and wait until monotonic deadline
                      (let* ((start-ms (%channel-monotonic-ms))
                             (deadline-ms (+ start-ms timeout-ms))
                             (waiter (make-channel-waiter receiver-task #f)))
                        (if receiver-task
                            (begin
                              (%task-blocked-on-set! receiver-task ch)
                              (%task-state-set! receiver-task 'waiting-channel)
                              (%memory-fence)))
                        (enqueue-lockfree! (%channel-recv-wait-queue ch) waiter)
                        (let wait-loop ()
                          (let ((st (atomic-ref (%waiter-state-box waiter))))
                            (if (eq? st 'claimed)
                                ;; Direct handoff from sender into waiter or receiver-task
                                (let ((val (if receiver-task
                                               (task-take-handoff! receiver-task)
                                               (atomic-swap! (%waiter-payload-box waiter) #f))))
                                  (cons #t val))
                                ;; Check if a buffered message arrived or channel closed/poisoned
                                (let ((polled (%channel-recv-core! ch #f #f #f 'empty)))
                                  (cond
                                    ((car polled)
                                     (if (not (atomic-cas! (%waiter-state-box waiter) 'waiting 'cancelled))
                                         (let ((extra-val (if receiver-task
                                                              (task-take-handoff! receiver-task)
                                                              (atomic-swap! (%waiter-payload-box waiter) #f))))
                                           (enqueue-lockfree! (%channel-message-queue ch) extra-val)
                                           (atomic-fetch-add! (%channel-current-count ch) 1)))
                                     (%prune-inactive-waiters! (%channel-recv-wait-queue ch))
                                     (if receiver-task
                                         (begin
                                           (%task-blocked-on-set! receiver-task #f)
                                           (%task-state-set! receiver-task 'ready)))
                                     polled)
                                    ((or (eq? (cdr polled) 'closed) (eq? (cdr polled) 'poisoned))
                                     (atomic-cas! (%waiter-state-box waiter) 'waiting 'cancelled)
                                     (%prune-inactive-waiters! (%channel-recv-wait-queue ch))
                                     (if receiver-task
                                         (begin
                                           (%task-blocked-on-set! receiver-task #f)
                                           (%task-state-set! receiver-task 'ready)))
                                     polled)
                                    ((>= (%channel-monotonic-ms) deadline-ms)
                                     ;; Deadline reached: atomically transition waiter from 'waiting -> 'timed-out
                                     (if (atomic-cas! (%waiter-state-box waiter) 'waiting 'timed-out)
                                         (begin
                                           (%prune-inactive-waiters! (%channel-recv-wait-queue ch))
                                           (if receiver-task
                                               (begin
                                                 (%task-blocked-on-set! receiver-task #f)
                                                 (%task-state-set! receiver-task 'ready)))
                                           (cons #f 'timeout))
                                         ;; Sender claimed waiter at the last instant before timeout
                                         (let ((val (if receiver-task
                                                        (task-take-handoff! receiver-task)
                                                        (atomic-swap! (%waiter-payload-box waiter) #f))))
                                           (cons #t val))))
                                    (else
                                     (%memory-fence)
                                     (wait-loop)))))))))))))))))

(define channel-recv-unboxed!
  (case-lambda
    ((ch)
     (%channel-recv-val! ch #f #f #t 'suspended))
    ((ch receiver-task)
     (%channel-recv-val! ch receiver-task #f #t 'suspended))
    ((ch receiver-task wake-hook)
     (%channel-recv-val! ch receiver-task wake-hook #t 'suspended))))

(define channel-try-recv-unboxed!
  (case-lambda
    ((ch)
     (%channel-recv-val! ch #f #f #f #f))
    ((ch empty-default)
     (%channel-recv-val! ch #f #f #f empty-default))))

;; -----------------------------------------------------------------------
;; 7b. Multiple Values Zero-Allocation API (R7RS §6.10, Issue #686)
;; -----------------------------------------------------------------------

(define (channel-try-recv-values! ch)
  (if (not (channel? ch))
      (error "channel-try-recv-values!: expected <channel>" ch)
      (if (and (%channel-spsc? ch) (> (%channel-capacity ch) 0))
          (let ((msg (%channel-spsc-try-dequeue-val! ch)))
            (if (not (eq? msg *ring-empty*))
                (begin
                  (if (> (queue-size (%channel-send-wait-queue ch)) 0)
                      (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                        (if send-waiter
                            (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                                  (sender-task (%waiter-task send-waiter)))
                              (%channel-spsc-try-enqueue! ch promoted-val)
                              (%wake-task! sender-task #f)))))
                  (values #t msg))
                (values #f #f)))
          (let ((msg (if (> (%channel-capacity ch) 0)
                         (%channel-ring-try-dequeue-val! ch)
                         *ring-empty*)))
            (if (not (eq? msg *ring-empty*))
                (begin
                  (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                    (if send-waiter
                        (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                              (sender-task (%waiter-task send-waiter)))
                          (%channel-ring-try-enqueue! ch promoted-val)
                          (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                          (%wake-task! sender-task #f))
                        (atomic-fetch-add! (%channel-current-count ch) -1)))
                  (atomic-fetch-add! (%channel-received-count-box ch) 1)
                  (values #t msg))
                (let ((res (%channel-recv-core! ch #f #f #f #f)))
                  (values (car res) (cdr res))))))))

(define channel-recv-values!
  (case-lambda
    ((ch) (channel-recv-values! ch #f #f))
    ((ch receiver-task) (channel-recv-values! ch receiver-task #f))
    ((ch receiver-task wake-hook)
     (if (and (%channel-spsc? ch) (> (%channel-capacity ch) 0))
         (let ((msg (%channel-spsc-try-dequeue-val! ch)))
           (if (not (eq? msg *ring-empty*))
               (begin
                 (if (> (queue-size (%channel-send-wait-queue ch)) 0)
                     (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                       (if send-waiter
                           (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                                 (sender-task (%waiter-task send-waiter)))
                             (%channel-spsc-try-enqueue! ch promoted-val)
                             (%wake-task! sender-task wake-hook)))))
                 (values #t msg))
               (let ((res (%channel-recv-core! ch receiver-task wake-hook #t 'suspended)))
                 (values (car res) (cdr res)))))
         (let ((msg (if (> (%channel-capacity ch) 0)
                        (%channel-ring-try-dequeue-val! ch)
                        *ring-empty*)))
           (if (not (eq? msg *ring-empty*))
               (begin
                 (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                   (if send-waiter
                       (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                             (sender-task (%waiter-task send-waiter)))
                         (%channel-ring-try-enqueue! ch promoted-val)
                         (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                         (%wake-task! sender-task wake-hook))
                       (atomic-fetch-add! (%channel-current-count ch) -1)))
                 (atomic-fetch-add! (%channel-received-count-box ch) 1)
                 (values #t msg))
               (let ((res (%channel-recv-core! ch receiver-task wake-hook #t 'suspended)))
                 (values (car res) (cdr res)))))))))

;; -----------------------------------------------------------------------
;; 8. Channel Close & Fan-Out Deep-Copy Broadcast (DSN-37 Section 4.2)
;; -----------------------------------------------------------------------

(define channel-close!
  (case-lambda
    ((ch) (channel-close! ch #f))
    ((ch wake-hook)
     (if (not (channel? ch))
         (error "channel-close!: expected <channel>" ch)
         (begin
           (atomic-set! (%channel-closed-box ch) #t)
           (%memory-fence)
           ;; Wake any waiting receivers so they observe closed state
           (let wake-recvs ()
             (let ((w (%pop-live-waiter! (%channel-recv-wait-queue ch))))
               (if w
                   (begin
                     (%wake-task! (%waiter-task w) wake-hook)
                     (wake-recvs)))))
           ;; Wake any waiting senders so they do not hang forever on closed channel
           (let wake-sends ()
             (let ((w (%pop-live-waiter! (%channel-send-wait-queue ch))))
               (if w
                   (begin
                     (%wake-task! (%waiter-task w) wake-hook)
                     (wake-sends)))))
           ;; Unregister closed channel from currently running task (Issue #731)
           (guard (exn (else #f))
             (let ((cur-task (current-synapse-task)))
               (if (task-context? cur-task)
                   (task-unregister-channel! cur-task ch)
                   #f)))
           #t)))))

(define channel-poison!
  (case-lambda
    ((ch) (channel-poison! ch 'poisoned #f))
    ((ch reason) (channel-poison! ch reason #f))
    ((ch reason wake-hook)
     (if (not (channel? ch))
         (error "channel-poison!: expected <channel>" ch)
         (begin
           (atomic-set! (%channel-closed-box ch) 'poisoned)
           (%memory-fence)
           ;; 1. Wake all waiting receivers and notify them of poisoning
           (let wake-recvs ()
             (let ((w (%pop-live-waiter! (%channel-recv-wait-queue ch))))
               (if w
                   (let ((t (%waiter-task w)))
                     (if t
                         (begin
                           (task-set-handoff! t (cons 'poisoned reason))
                           (%task-blocked-on-set! t #f)
                           (%task-state-set! t 'ready)
                           (%wake-task! t wake-hook)))
                     (wake-recvs)))))
           ;; 2. Wake all waiting senders and notify them of poisoning
           (let wake-sends ()
             (let ((w (%pop-live-waiter! (%channel-send-wait-queue ch))))
               (if w
                   (let ((t (%waiter-task w)))
                     (if t
                         (begin
                           (task-set-handoff! t (cons 'poisoned reason))
                           (%task-blocked-on-set! t #f)
                           (%task-state-set! t 'ready)
                           (%wake-task! t wake-hook)))
                     (wake-sends)))))
           #t)))))

;; Structural deep copy for fan-out broadcast so mutable pairs, vectors,
;; strings, and bytevectors are never aliased across receiving tasks (CWE-662).
(define (channel-deep-copy val)
  (cond
    ((or (fixnum? val) (null? val) (boolean? val) (symbol? val) (char? val) (eof-object? val))
     val)
    ((vector? val)
     (let* ((len (vector-length val))
            (out (vector-copy val)))
       (let vec-loop ((i 0) (v out))
         (if (>= i len)
             v
             (begin
               (vector-set! v i (channel-deep-copy (vector-ref val i)))
               (vec-loop (+ i 1) v))))))
    ((pair? val)
     (let ((d-car (channel-deep-copy (car val)))
           (d-cdr (channel-deep-copy (cdr val))))
       (cons d-car d-cdr)))
    ((string? val)
     (string-copy val))
    ((bytevector? val)
     (bytevector-copy val))
    (else val)))

(define broadcast-send!
  (case-lambda
    ((channels val)
     (broadcast-send! channels val channel-deep-copy))
    ((channels val copy-proc)
     (if (not (procedure? copy-proc))
         (error "broadcast-send!: copy-proc must be a procedure" copy-proc)
         (if (channel? channels)
             (channel-send! channels (copy-proc val))
             (if (not (or (null? channels)
                          (and (pair? channels) (not (vector? channels)))))
                 (error "broadcast-send!: expected list of <channel> or single <channel>" channels)
                 (let loop ((rest channels) (count 0))
                   (if (null? rest)
                       count
                       (let ((ch (car rest)))
                         (if (not (channel? ch))
                             (error "broadcast-send!: element is not a <channel>" ch)
                             (begin
                               (channel-send! ch (copy-proc val))
                               (loop (cdr rest) (+ count 1)))))))))))))

;; -----------------------------------------------------------------------
;; 9. Channel Telemetry & Inspection
;; -----------------------------------------------------------------------

(define (channel-stats ch)
  (if (not (channel? ch))
      (error "channel-stats: expected <channel>" ch)
      (let* ((spsc? (%channel-spsc? ch))
             (has-ring? (and (> (%channel-capacity ch) 0) (%channel-ring-buffer ch)))
             (buffered (if (and spsc? has-ring?)
                           (- (padded-atomic-ref (%channel-ring-head-box ch))
                              (padded-atomic-ref (%channel-ring-tail-box ch)))
                           (atomic-ref (%channel-current-count ch))))
             (sent (if (and spsc? has-ring?)
                       (+ (padded-atomic-ref (%channel-ring-head-box ch))
                          (atomic-ref (%channel-sent-count-box ch)))
                       (atomic-ref (%channel-sent-count-box ch))))
             (received (if (and spsc? has-ring?)
                           (+ (padded-atomic-ref (%channel-ring-tail-box ch))
                              (atomic-ref (%channel-received-count-box ch)))
                           (atomic-ref (%channel-received-count-box ch)))))
        (list (cons 'capacity (%channel-capacity ch))
              (cons 'buffered buffered)
              (cons 'recv-waiting (queue-size (%channel-recv-wait-queue ch)))
              (cons 'send-waiting (queue-size (%channel-send-wait-queue ch)))
              (cons 'sent sent)
              (cons 'received received)
              (cons 'backpressure-suspends (atomic-ref (%channel-backpressure-count-box ch)))
              (cons 'rendezvous-handoffs (atomic-ref (%channel-handoff-count-box ch)))
              (cons 'closed? (atomic-ref (%channel-closed-box ch)))
              (cons 'unboxed? (if (%channel-ring-buffer ch) #t #f))
              (cons 'spsc? (if spsc? #t #f))))))

