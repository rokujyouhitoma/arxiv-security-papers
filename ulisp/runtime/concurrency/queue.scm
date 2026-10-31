;;; =======================================================================
;;; ULisp Runtime Concurrency: Michael-Scott Lock-Free Queue (queue.scm)
;;; Conforms to DSN-37 Section 6.1, 6.2, 6.3, 13.4 & Phase 1 Task 1.1 (Issue #632)
;;;
;;; Provides a wait-free/lock-free MPMC (Multi-Producer Multi-Consumer) FIFO
;;; queue using the Michael & Scott (PODC 1996) two-phase CAS algorithm with
;;; cooperative tail helping, sentinel value clearing (CWE-401 mitigation),
;;; and an ABA-safe 64-bit generation-stamped node pool (CWE-416 mitigation).
;;; =======================================================================

(include "ulisp/runtime/concurrency/atomic.scm")

;; -----------------------------------------------------------------------
;; 1. <queue-node> Record Type (DSN-37 Section 6.1)
;; -----------------------------------------------------------------------
;; Memory Layout (Pass 025 expand-define-record-type):
;;   Slot 0 [node + 3]  : '%%record-type-<queue-node>
;;   Slot 1 [node + 11] : value (payload or #f when acting as sentinel dummy)
;;   Slot 2 [node + 19] : next  (<atomic-box> holding next <queue-node> or #f)

(define-record-type <queue-node>
  (%make-queue-node value next)
  queue-node?
  (value %queue-node-value %queue-node-value-set!)
  (next %queue-node-next %queue-node-next-set!))

(define make-queue-node
  (case-lambda
    ((value)
     (let ((node (%make-queue-node value (make-atomic-box #f))))
       (%memory-fence)
       node))
    ((value next-box)
     (if (not (atomic-box? next-box))
         (error "make-queue-node: next must be an <atomic-box>" next-box)
         (let ((node (%make-queue-node value next-box)))
           (%memory-fence)
           node)))))

(define (queue-node-value node)
  (if (not (queue-node? node))
      (error "queue-node-value: expected <queue-node>" node)
      (%queue-node-value node)))

(define (queue-node-value-set! node val)
  (if (not (queue-node? node))
      (error "queue-node-value-set!: expected <queue-node>" node)
      (begin
        (%queue-node-value-set! node val)
        (%memory-fence)
        val)))

(define (queue-node-next node)
  (if (not (queue-node? node))
      (error "queue-node-next: expected <queue-node>" node)
      (%queue-node-next node)))

(define (queue-node-next-set! node next-box)
  (if (not (queue-node? node))
      (error "queue-node-next-set!: expected <queue-node>" node)
      (if (not (atomic-box? next-box))
          (error "queue-node-next-set!: expected <atomic-box>" next-box)
          (begin
            (%queue-node-next-set! node next-box)
            (%memory-fence)
            next-box))))

;; -----------------------------------------------------------------------
;; 2. ABA-Safe Generation-Stamped Node Pool (<queue-node-pool>, DSN-37 6.3)
;; -----------------------------------------------------------------------
;; Uses <atomic-stamped-box> with a monotonically increasing 64-bit integer
;; generation stamp to recycle retired sentinel <queue-node> instances
;; without risking the ABA problem (CWE-416).

(define-record-type <queue-node-pool>
  (%make-queue-node-pool top-stamped capacity available-box)
  queue-node-pool?
  (top-stamped %queue-node-pool-top)
  (capacity %queue-node-pool-capacity)
  (available-box %queue-node-pool-available-box))

(define make-queue-node-pool
  (case-lambda
    (()
     (%make-queue-node-pool (make-atomic-stamped-box #f 0) 0 (make-atomic-box 0)))
    ((capacity)
     (if (or (not (integer? capacity)) (< capacity 0))
         (error "make-queue-node-pool: capacity must be a non-negative integer" capacity)
         (let build-free-list ((i 0) (head #f))
           (if (>= i capacity)
               (%make-queue-node-pool (make-atomic-stamped-box head 0)
                                      capacity
                                      (make-atomic-box capacity))
               (let ((node (%make-queue-node #f (make-atomic-box head))))
                 (build-free-list (+ i 1) node))))))))

(define (queue-node-pool-stamp pool)
  (if (not (queue-node-pool? pool))
      (error "queue-node-pool-stamp: expected <queue-node-pool>" pool)
      (atomic-stamped-stamp (%queue-node-pool-top pool))))

(define (queue-node-pool-capacity pool)
  (if (not (queue-node-pool? pool))
      (error "queue-node-pool-capacity: expected <queue-node-pool>" pool)
      (%queue-node-pool-capacity pool)))

(define (queue-node-pool-available pool)
  (if (not (queue-node-pool? pool))
      (error "queue-node-pool-available: expected <queue-node-pool>" pool)
      (atomic-ref (%queue-node-pool-available-box pool))))

(define (pool-alloc-node! pool val)
  (if (not (queue-node-pool? pool))
      (error "pool-alloc-node!: expected <queue-node-pool>" pool)
      (let ((sbox (%queue-node-pool-top pool)))
        (let retry ()
          (let* ((snap (atomic-stamped-ref sbox))
                 (top (car snap))
                 (stamp (cdr snap)))
            (if (not top)
                (make-queue-node val (make-atomic-box #f))
                (let ((next-free (atomic-ref (%queue-node-next top))))
                  (if (atomic-stamped-cas! sbox top next-free stamp (+ stamp 1))
                      (begin
                        (atomic-fetch-add! (%queue-node-pool-available-box pool) -1)
                        (atomic-set! (%queue-node-next top) #f)
                        (%queue-node-value-set! top val)
                        (%memory-fence)
                        top)
                      (retry)))))))))

(define (queue-pool-acquire! pool val)
  (pool-alloc-node! pool val))

(define (pool-free-node! pool node)
  (if (not (queue-node-pool? pool))
      (error "pool-free-node!: expected <queue-node-pool>" pool)
      (if (not (queue-node? node))
          (error "pool-free-node!: expected <queue-node>" node)
          (let ((sbox (%queue-node-pool-top pool)))
            (%queue-node-value-set! node #f)
            (let retry ()
              (let* ((snap (atomic-stamped-ref sbox))
                     (old-top (car snap))
                     (old-stamp (cdr snap)))
                (atomic-set! (%queue-node-next node) old-top)
                (if (atomic-stamped-cas! sbox old-top node old-stamp (+ old-stamp 1))
                    (begin
                      (atomic-fetch-add! (%queue-node-pool-available-box pool) 1)
                      #t)
                    (retry))))))))

(define (queue-pool-release! pool node)
  (pool-free-node! pool node))

;; -----------------------------------------------------------------------
;; 3. <lock-free-queue> Record Type & Construction (DSN-37 Section 6.1)
;; -----------------------------------------------------------------------
;; Initialized with a single sentinel dummy node whose value is #f and
;; whose next pointer is an <atomic-box> containing #f.

(define-record-type <lock-free-queue>
  (%make-lock-free-queue head tail count-box pool enqueue-count-box dequeue-count-box)
  lock-free-queue?
  (head %queue-head %queue-head-set!)
  (tail %queue-tail %queue-tail-set!)
  (count-box %queue-count-box)
  (pool %queue-pool)
  (enqueue-count-box %queue-enqueue-count-box)
  (dequeue-count-box %queue-dequeue-count-box))

(define make-lock-free-queue
  (case-lambda
    (()
     (let* ((dummy (make-queue-node #f (make-atomic-box #f)))
            (q (%make-lock-free-queue (make-atomic-box dummy)
                                      (make-atomic-box dummy)
                                      (make-atomic-box 0)
                                      #f
                                      (make-atomic-box 0)
                                      (make-atomic-box 0))))
       (%memory-fence)
       q))
    ((pool-or-cap)
     (let* ((pool (cond
                    ((queue-node-pool? pool-or-cap) pool-or-cap)
                    ((and (integer? pool-or-cap) (>= pool-or-cap 0))
                     (make-queue-node-pool pool-or-cap))
                    (else
                     (error "make-lock-free-queue: expected <queue-node-pool> or non-negative integer capacity" pool-or-cap))))
            (dummy (pool-alloc-node! pool #f))
            (q (%make-lock-free-queue (make-atomic-box dummy)
                                      (make-atomic-box dummy)
                                      (make-atomic-box 0)
                                      pool
                                      (make-atomic-box 0)
                                      (make-atomic-box 0))))
       (%memory-fence)
       q))
    ((head-box tail-box)
     (if (or (not (atomic-box? head-box)) (not (atomic-box? tail-box)))
         (error "make-lock-free-queue: head and tail must be <atomic-box>" (cons head-box tail-box))
         (let ((q (%make-lock-free-queue head-box
                                         tail-box
                                         (make-atomic-box 0)
                                         #f
                                         (make-atomic-box 0)
                                         (make-atomic-box 0))))
           (%memory-fence)
           q)))))

(define (lock-free-queue-head q)
  (if (not (lock-free-queue? q))
      (error "lock-free-queue-head: expected <lock-free-queue>" q)
      (%queue-head q)))

(define (lock-free-queue-head-set! q head-box)
  (if (not (lock-free-queue? q))
      (error "lock-free-queue-head-set!: expected <lock-free-queue>" q)
      (if (not (atomic-box? head-box))
          (error "lock-free-queue-head-set!: expected <atomic-box>" head-box)
          (begin
            (%queue-head-set! q head-box)
            (%memory-fence)
            head-box))))

(define (lock-free-queue-tail q)
  (if (not (lock-free-queue? q))
      (error "lock-free-queue-tail: expected <lock-free-queue>" q)
      (%queue-tail q)))

(define (lock-free-queue-tail-set! q tail-box)
  (if (not (lock-free-queue? q))
      (error "lock-free-queue-tail-set!: expected <lock-free-queue>" q)
      (if (not (atomic-box? tail-box))
          (error "lock-free-queue-tail-set!: expected <atomic-box>" tail-box)
          (begin
            (%queue-tail-set! q tail-box)
            (%memory-fence)
            tail-box))))

(define (queue-head q)
  (lock-free-queue-head q))

(define (queue-tail q)
  (lock-free-queue-tail q))

;; -----------------------------------------------------------------------
;; 4. Core Michael-Scott Non-Blocking Queue Operations (DSN-37 Section 6.2)
;; -----------------------------------------------------------------------

;; Internal helper: link a prepared <queue-node> into <lock-free-queue>
(define (%enqueue-node-lockfree! q node)
  (let loop ()
    (let* ((tail-box (%queue-tail q))
           (tail (atomic-ref tail-box))
           (next-box (%queue-node-next tail))
           (next (atomic-ref next-box)))
      (if (eq? tail (atomic-ref tail-box))
          (if (not next)
              ;; Phase 1: tail points to the last node; link node at tail.next
              (if (atomic-cas! next-box #f node)
                  (begin
                    ;; Phase 2: best-effort swing of q.tail to the new node
                    (atomic-cas! tail-box tail node)
                    (atomic-fetch-add! (%queue-count-box q) 1)
                    (atomic-fetch-add! (%queue-enqueue-count-box q) 1)
                    #t)
                  (loop))
              ;; Cooperative helping: tail is lagging behind; advance q.tail
              (begin
                (atomic-cas! tail-box tail next)
                (loop)))
          (loop)))))

(define (enqueue-lockfree! q val)
  (if (not (lock-free-queue? q))
      (error "enqueue-lockfree!: expected <lock-free-queue>" q)
      (let* ((pool (%queue-pool q))
             (node (if pool
                       (pool-alloc-node! pool val)
                       (make-queue-node val (make-atomic-box #f)))))
        (%enqueue-node-lockfree! q node))))

(define (queue-enqueue! q val)
  (enqueue-lockfree! q val))

(define (%dequeue-core! q empty-default release-pool)
  (let loop ()
    (let* ((head-box (%queue-head q))
           (tail-box (%queue-tail q))
           (head (atomic-ref head-box))
           (tail (atomic-ref tail-box))
           (next (atomic-ref (%queue-node-next head))))
      (if (eq? head (atomic-ref head-box))
          (if (eq? head tail)
              (if (not next)
                  (cons #f empty-default)
                  ;; Cooperative helping: tail is lagging on a non-empty queue
                  (begin
                    (atomic-cas! tail-box tail next)
                    (loop)))
              ;; Read payload before swinging head so concurrent dequeues cannot
              ;; overwrite or clear next.value before we capture it
              (let ((val (%queue-node-value next)))
                (if (atomic-cas! head-box head next)
                    (begin
                      ;; CWE-401 mitigation: next is now the new sentinel dummy
                      ;; node; clear its payload reference immediately so GC can
                      ;; reclaim the dequeued object.
                      (%queue-node-value-set! next #f)
                      (atomic-fetch-add! (%queue-count-box q) -1)
                      (atomic-fetch-add! (%queue-dequeue-count-box q) 1)
                      (%memory-fence)
                      (if release-pool
                          (pool-free-node! release-pool head))
                      (cons #t val))
                    (loop))))
          (loop)))))

(define dequeue-lockfree!
  (case-lambda
    ((q)
     (if (not (lock-free-queue? q))
         (error "dequeue-lockfree!: expected <lock-free-queue>" q)
         (cdr (%dequeue-core! q #f (%queue-pool q)))))
    ((q empty-default)
     (if (not (lock-free-queue? q))
         (error "dequeue-lockfree!: expected <lock-free-queue>" q)
         (cdr (%dequeue-core! q empty-default (%queue-pool q)))))))

(define queue-dequeue!
  (case-lambda
    ((q) (dequeue-lockfree! q))
    ((q empty-default) (dequeue-lockfree! q empty-default))))

(define (dequeue-lockfree-with-status! q)
  (if (not (lock-free-queue? q))
      (error "dequeue-lockfree-with-status!: expected <lock-free-queue>" q)
      (%dequeue-core! q #f (%queue-pool q))))

(define (enqueue-lockfree/pooled! q pool val)
  (if (not (lock-free-queue? q))
      (error "enqueue-lockfree/pooled!: expected <lock-free-queue>" q)
      (if (not (queue-node-pool? pool))
          (error "enqueue-lockfree/pooled!: expected <queue-node-pool>" pool)
          (let ((node (pool-alloc-node! pool val)))
            (%enqueue-node-lockfree! q node)))))

(define dequeue-lockfree/pooled!
  (case-lambda
    ((q pool)
     (if (not (lock-free-queue? q))
         (error "dequeue-lockfree/pooled!: expected <lock-free-queue>" q)
         (if (not (queue-node-pool? pool))
             (error "dequeue-lockfree/pooled!: expected <queue-node-pool>" pool)
             (cdr (%dequeue-core! q #f pool)))))
    ((q pool empty-default)
     (if (not (lock-free-queue? q))
         (error "dequeue-lockfree/pooled!: expected <lock-free-queue>" q)
         (if (not (queue-node-pool? pool))
             (error "dequeue-lockfree/pooled!: expected <queue-node-pool>" pool)
             (cdr (%dequeue-core! q empty-default pool)))))))

;; -----------------------------------------------------------------------
;; 5. Queue Inspection & Telemetry Procedures
;; -----------------------------------------------------------------------

(define (queue-empty? q)
  (if (not (lock-free-queue? q))
      (error "queue-empty?: expected <lock-free-queue>" q)
      (let loop ()
        (let* ((head-box (%queue-head q))
               (tail-box (%queue-tail q))
               (head (atomic-ref head-box))
               (tail (atomic-ref tail-box))
               (next (atomic-ref (%queue-node-next head))))
          (if (eq? head (atomic-ref head-box))
              (if (eq? head tail)
                  (if (not next)
                      #t
                      (begin
                        (atomic-cas! tail-box tail next)
                        (loop)))
                  #f)
              (loop))))))

(define (lock-free-queue-empty? q)
  (queue-empty? q))

(define queue-peek
  (case-lambda
    ((q) (queue-peek q #f))
    ((q empty-default)
     (if (not (lock-free-queue? q))
         (error "queue-peek: expected <lock-free-queue>" q)
         (let loop ()
           (let* ((head-box (%queue-head q))
                  (tail-box (%queue-tail q))
                  (head (atomic-ref head-box))
                  (tail (atomic-ref tail-box))
                  (next (atomic-ref (%queue-node-next head))))
             (if (eq? head (atomic-ref head-box))
                 (if (eq? head tail)
                     (if (not next)
                         empty-default
                         (begin
                           (atomic-cas! tail-box tail next)
                           (loop)))
                     (%queue-node-value next))
                 (loop))))))))

(define lock-free-queue-peek
  (case-lambda
    ((q) (queue-peek q #f))
    ((q empty-default) (queue-peek q empty-default))))

(define (queue-size q)
  (if (not (lock-free-queue? q))
      (error "queue-size: expected <lock-free-queue>" q)
      (let* ((head (atomic-ref (%queue-head q)))
             (first (atomic-ref (%queue-node-next head))))
        (let count-loop ((cur first) (n 0))
          (if (not cur)
              n
              (count-loop (atomic-ref (%queue-node-next cur)) (+ n 1)))))))

(define (lock-free-queue-size q)
  (queue-size q))

(define (queue->list q)
  (if (not (lock-free-queue? q))
      (error "queue->list: expected <lock-free-queue>" q)
      (let* ((head (atomic-ref (%queue-head q)))
             (first (atomic-ref (%queue-node-next head))))
        (let collect-loop ((cur first) (acc '()))
          (if (not cur)
              (reverse acc)
              (collect-loop (atomic-ref (%queue-node-next cur))
                            (cons (%queue-node-value cur) acc)))))))

(define (queue-stats q)
  (if (not (lock-free-queue? q))
      (error "queue-stats: expected <lock-free-queue>" q)
      (list (cons 'size (queue-size q))
            (cons 'enqueued (atomic-ref (%queue-enqueue-count-box q)))
            (cons 'dequeued (atomic-ref (%queue-dequeue-count-box q)))
            (cons 'has-pool? (if (%queue-pool q) #t #f)))))
