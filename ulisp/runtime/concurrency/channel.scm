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

;; -----------------------------------------------------------------------
;; 1. Constants & Global Scheduler / Epoch Integration Hooks
;; -----------------------------------------------------------------------

(define *task-default-reductions* 4096)
(define *channel-max-capacity* 1048576)

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
                      reduction-exhaustions steals-count handoff-box)
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
  (handoff-box           %task-handoff-box))

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

(define make-task-context
  (case-lambda
    (()
     (let ((tid (allocate-task-id!)))
       (%make-task-context tid 'ready *task-default-reductions* 0 0
                           0 0 4096 #f 0 #f 0 0 (make-atomic-box #f))))
    ((tid)
     (%make-task-context tid 'ready *task-default-reductions* 0 0
                         0 0 4096 #f 0 #f 0 0 (make-atomic-box #f)))
    ((tid epoch)
     (%make-task-context tid 'ready *task-default-reductions* 0 0
                         0 0 4096 #f epoch #f 0 0 (make-atomic-box #f)))
    ((tid state reductions continuation-pc stack-pointer
      arena-base arena-offset arena-capacity
      blocked-on epoch next-run
      reduction-exhaustions steals-count)
     (%make-task-context tid state reductions continuation-pc stack-pointer
                         arena-base arena-offset arena-capacity
                         blocked-on epoch next-run
                         reduction-exhaustions steals-count
                         (make-atomic-box #f)))))

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

(define task-take-handoff!
  (case-lambda
    ((t) (task-take-handoff! t #f))
    ((t empty-default)
     (if (not (task-context? t))
         (error "task-take-handoff!: expected <task-context>" t)
         (let ((cell (atomic-swap! (%task-handoff-box t) #f)))
           (if (pair? cell)
               (cdr cell)
               empty-default))))))

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
;; 4. <channel> Record Type & Construction (DSN-37 Section 6.1)
;; -----------------------------------------------------------------------

(define-record-type <channel>
  (%make-channel message-queue recv-wait-queue send-wait-queue
                 capacity current-count closed-box
                 sent-count-box received-count-box
                 backpressure-count-box handoff-count-box)
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
  (handoff-count-box      %channel-handoff-count-box))

(define make-channel
  (case-lambda
    (()
     (make-channel 0))
    ((capacity)
     (if (or (not (integer? capacity))
             (< capacity 0)
             (> capacity *channel-max-capacity*))
         (error "make-channel: capacity must be an integer in [0, *channel-max-capacity*]" capacity)
         (let ((ch (%make-channel (make-lock-free-queue)
                                  (make-lock-free-queue)
                                  (make-lock-free-queue)
                                  capacity
                                  (make-atomic-box 0)
                                  (make-atomic-box #f)
                                  (make-atomic-box 0)
                                  (make-atomic-box 0)
                                  (make-atomic-box 0)
                                  (make-atomic-box 0))))
           (%memory-fence)
           ch)))))

;; DSN-37 Section 6.1 5-argument constructor compatibility
(define (make-channel-internal message-queue recv-wait-queue send-wait-queue capacity current-count)
  (if (or (not (lock-free-queue? message-queue))
          (not (lock-free-queue? recv-wait-queue))
          (not (lock-free-queue? send-wait-queue)))
      (error "make-channel-internal: queues must be <lock-free-queue>" message-queue)
      (if (or (not (integer? capacity)) (< capacity 0) (> capacity *channel-max-capacity*))
          (error "make-channel-internal: invalid capacity" capacity)
          (let ((cnt-box (if (atomic-box? current-count)
                             current-count
                             (make-atomic-box current-count))))
            (%make-channel message-queue
                           recv-wait-queue
                           send-wait-queue
                           capacity
                           cnt-box
                           (make-atomic-box #f)
                           (make-atomic-box 0)
                           (make-atomic-box 0)
                           (make-atomic-box 0)
                           (make-atomic-box 0))))))

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

(define (channel-count ch)
  (if (not (channel? ch))
      (error "channel-count: expected <channel>" ch)
      (atomic-ref (%channel-current-count ch))))

(define (channel-closed? ch)
  (if (not (channel? ch))
      (error "channel-closed?: expected <channel>" ch)
      (atomic-ref (%channel-closed-box ch))))

(define (channel-empty? ch)
  (if (not (channel? ch))
      (error "channel-empty?: expected <channel>" ch)
      (and (= (atomic-ref (%channel-current-count ch)) 0)
           (queue-empty? (%channel-message-queue ch)))))

(define (channel-full? ch)
  (if (not (channel? ch))
      (error "channel-full?: expected <channel>" ch)
      (let ((cap (%channel-capacity ch)))
        (if (= cap 0)
            (queue-empty? (%channel-recv-wait-queue ch))
            (>= (atomic-ref (%channel-current-count ch)) cap)))))

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
  (if task
      (begin
        (%task-blocked-on-set! task #f)
        (%task-state-set! task 'ready)
        (%memory-fence)
        (let ((hook (or wake-hook (atomic-ref *channel-wake-hook-box*))))
          (if hook
              (hook task))))))

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
          (if (atomic-ref (%channel-closed-box ch))
              (error "channel-send!: cannot send on closed channel" ch)
              ;; Fast Path 1: Direct zero-copy handoff to a waiting receiver
              (let ((recv-waiter (%pop-live-waiter! (%channel-recv-wait-queue ch))))
                (if recv-waiter
                    (let ((recv-task (%waiter-task recv-waiter)))
                      (if recv-task
                          (atomic-set! (%task-handoff-box recv-task) (cons #t val))
                          (atomic-set! (%waiter-payload-box recv-waiter) val))
                      (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                      (atomic-fetch-add! (%channel-received-count-box ch) 1)
                      (atomic-fetch-add! (%channel-handoff-count-box ch) 1)
                      (%wake-task! recv-task wake-hook)
                      #t)
                    ;; Fast Path 2: Enqueue into bounded buffer if space is available
                    (if (%try-reserve-buffer-slot! ch)
                        (begin
                          (enqueue-lockfree! (%channel-message-queue ch) val)
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
                              'suspended)))))))))

(define channel-send!
  (case-lambda
    ((ch val)
     (%channel-send-core! ch val #f #f #t))
    ((ch val sender-task)
     (%channel-send-core! ch val sender-task #f #t))
    ((ch val sender-task wake-hook)
     (%channel-send-core! ch val sender-task wake-hook #t))))

(define (channel-try-send! ch val)
  (%channel-send-core! ch val #f #f #f))

;; -----------------------------------------------------------------------
;; 7. Linear Ownership Transfer Receive & Backpressure Relief (DSN-37 4.3.1)
;; -----------------------------------------------------------------------

(define (%channel-recv-core! ch receiver-task wake-hook allow-suspend? empty-default)
  (if (not (channel? ch))
      (error "channel-recv!: expected <channel>" ch)
      (if (and receiver-task (not (task-context? receiver-task)))
          (error "channel-recv!: expected <task-context> or #f" receiver-task)
          ;; Fast Path 1: Buffered message available in message-queue
          (let ((deq (dequeue-lockfree-with-status! (%channel-message-queue ch))))
            (if (car deq)
                (let ((msg (cdr deq))
                      (send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                  (if send-waiter
                      ;; Backpressure relief: promote waiting sender's payload into
                      ;; message-queue (keeping current-count constant) and wake sender!
                      (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                            (sender-task (%waiter-task send-waiter)))
                        (enqueue-lockfree! (%channel-message-queue ch) promoted-val)
                        (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                        (%wake-task! sender-task wake-hook))
                      ;; No waiting sender; decrement buffered message count
                      (atomic-fetch-add! (%channel-current-count ch) -1))
                  (atomic-fetch-add! (%channel-received-count-box ch) 1)
                  (cons #t msg))
                ;; Fast Path 2: Direct rendezvous handoff from a waiting sender
                (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
                  (if send-waiter
                      ;; CWE-401 mitigation: clear waiter payload reference via atomic-swap!
                      (let ((val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                            (sender-task (%waiter-task send-waiter)))
                        (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                        (atomic-fetch-add! (%channel-received-count-box ch) 1)
                        (atomic-fetch-add! (%channel-handoff-count-box ch) 1)
                        (%wake-task! sender-task wake-hook)
                        (cons #t val))
                      ;; Slow Path: No buffered message and no waiting sender
                      (if (atomic-ref (%channel-closed-box ch))
                          (cons #f 'closed)
                          (if (not allow-suspend?)
                              (cons #f empty-default)
                              (let ((waiter (make-channel-waiter receiver-task #f)))
                                (if receiver-task
                                    (begin
                                      (atomic-set! (%task-handoff-box receiver-task) #f)
                                      (%task-blocked-on-set! receiver-task ch)
                                      (%task-state-set! receiver-task 'waiting-channel)
                                      (%memory-fence)))
                                (enqueue-lockfree! (%channel-recv-wait-queue ch) waiter)
                                (cons #f 'suspended)))))))))))

(define channel-recv!
  (case-lambda
    ((ch)
     (cdr (%channel-recv-core! ch #f #f #t 'suspended)))
    ((ch receiver-task)
     (cdr (%channel-recv-core! ch receiver-task #f #t 'suspended)))
    ((ch receiver-task wake-hook)
     (cdr (%channel-recv-core! ch receiver-task wake-hook #t 'suspended)))))

(define channel-try-recv!
  (case-lambda
    ((ch)
     (cdr (%channel-recv-core! ch #f #f #f #f)))
    ((ch empty-default)
     (cdr (%channel-recv-core! ch #f #f #f empty-default)))))

(define (channel-try-recv-with-status! ch)
  (%channel-recv-core! ch #f #f #f #f))

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
           ;; Wake any waiting receivers so they observe closed state
           (let wake-recvs ()
             (let ((w (%pop-live-waiter! (%channel-recv-wait-queue ch))))
               (if w
                   (begin
                     (%wake-task! (%waiter-task w) wake-hook)
                     (wake-recvs)))))
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
      (list (cons 'capacity (%channel-capacity ch))
            (cons 'buffered (atomic-ref (%channel-current-count ch)))
            (cons 'recv-waiting (queue-size (%channel-recv-wait-queue ch)))
            (cons 'send-waiting (queue-size (%channel-send-wait-queue ch)))
            (cons 'sent (atomic-ref (%channel-sent-count-box ch)))
            (cons 'received (atomic-ref (%channel-received-count-box ch)))
            (cons 'backpressure-suspends (atomic-ref (%channel-backpressure-count-box ch)))
            (cons 'rendezvous-handoffs (atomic-ref (%channel-handoff-count-box ch)))
            (cons 'closed? (atomic-ref (%channel-closed-box ch))))))

