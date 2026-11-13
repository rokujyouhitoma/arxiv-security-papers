;;; =======================================================================
;;; ULisp Concurrency Runtime: Chase-Lev Dynamic Work-Stealing Deque
;;; Conforms to DSN-37 Architecture Specification & Issue #635
;;; Paper: Dynamic Circular Work-Stealing Deque (Chase & Lev, SPAA 2005)
;;; =======================================================================

;; -----------------------------------------------------------------------
;; 1. Deque Constants & Sizing Parameters
;; -----------------------------------------------------------------------

(define *deque-min-capacity* 16)
(define *deque-default-capacity* 256)
(define *deque-max-capacity* 1048576) ; 1M entries max

(define (%deque-round-pow2 n)
  (let ((target (if (> n *deque-min-capacity*) n *deque-min-capacity*)))
    (let loop ((p *deque-min-capacity*))
      (if (>= p target)
          p
          (if (>= p *deque-max-capacity*)
              *deque-max-capacity*
              (loop (* p 2)))))))

;; -----------------------------------------------------------------------
;; 2. <chase-lev-deque> Record Type
;; -----------------------------------------------------------------------
;; Fields (5 fields, fits in System V AMD64 argument registers):
;;   top      : <atomic-box> holding 64-bit integer top index (CAS updated by thieves & pop)
;;   bottom   : fixnum bottom index (written only by owner worker)
;;   buffer   : vector payload
;;   capacity : fixnum power-of-two capacity
;;   mask     : fixnum capacity - 1

(define-record-type <chase-lev-deque>
  (%make-chase-lev-deque top bottom buffer capacity mask)
  chase-lev-deque?
  (top      %deque-top-box)
  (bottom   %deque-bottom   %deque-bottom-set!)
  (buffer   %deque-buffer   %deque-buffer-set!)
  (capacity deque-capacity  %deque-capacity-set!)
  (mask     %deque-mask     %deque-mask-set!))

(define make-chase-lev-deque
  (begin (declare (no-safepoints))
   (case-lambda
    (()
     (make-chase-lev-deque *deque-default-capacity*))
    ((initial-capacity)
     (if (not (integer? initial-capacity))
         (error "make-chase-lev-deque: initial-capacity must be an integer (CWE-843)" initial-capacity)
         (if (< initial-capacity 0)
             (error "make-chase-lev-deque: negative capacity not allowed (CWE-20)" initial-capacity)
             (if (> initial-capacity *deque-max-capacity*)
                 (error "make-chase-lev-deque: initial-capacity exceeds *deque-max-capacity* (CWE-400)" initial-capacity)
                 (let* ((cap (%deque-round-pow2 initial-capacity))
                        (buf (make-vector cap #f)))
                   (%make-chase-lev-deque (make-atomic-box 0) 0 buf cap (- cap 1))))))))))

;; -----------------------------------------------------------------------
;; 3. Deque Observers & State Predicates
;; -----------------------------------------------------------------------

(define (deque-count deque)
  (declare (no-safepoints))
  (if (not (chase-lev-deque? deque))
      (error "deque-count: expected <chase-lev-deque>" deque)
      (let* ((b (%deque-bottom deque))
             (t (atomic-ref (%deque-top-box deque)))
             (diff (- b t)))
        (if (> diff 0) diff 0))))

(define (deque-empty? deque)
  (declare (no-safepoints))
  (if (not (chase-lev-deque? deque))
      (error "deque-empty?: expected <chase-lev-deque>" deque)
      (let ((b (%deque-bottom deque))
            (t (atomic-ref (%deque-top-box deque))))
        (>= t b))))

(define (deque-stats deque)
  (declare (no-safepoints))
  (if (not (chase-lev-deque? deque))
      (error "deque-stats: expected <chase-lev-deque>" deque)
      (let* ((b (%deque-bottom deque))
             (t (atomic-ref (%deque-top-box deque)))
             (c (deque-capacity deque))
             (diff (- b t)))
        (list (cons 'capacity c)
              (cons 'count (if (> diff 0) diff 0))
              (cons 'top t)
              (cons 'bottom b)))))

;; -----------------------------------------------------------------------
;; 4. Internal Buffer Expansion (Chase & Lev 2005)
;; -----------------------------------------------------------------------

(define (%deque-grow! deque b t)
  (let* ((old-cap (deque-capacity deque))
         (new-cap (* old-cap 2)))
    (if (> new-cap *deque-max-capacity*)
        (error "deque-push!: maximum deque capacity exceeded (CWE-400)" new-cap)
        (let* ((old-buf (%deque-buffer deque))
               (new-buf (make-vector new-cap #f))
               (old-mask (%deque-mask deque))
               (new-mask (- new-cap 1)))
          ;; Copy all live items from [t .. b) into new buffer
          (let loop ((i t))
            (if (< i b)
                (let ((item (vector-ref old-buf (bitwise-and i old-mask))))
                  (vector-set! new-buf (bitwise-and i new-mask) item)
                  (loop (+ i 1)))))
          (%deque-buffer-set! deque new-buf)
          (%deque-capacity-set! deque new-cap)
          (%deque-mask-set! deque new-mask)
          (%memory-fence)
          new-cap))))

;; -----------------------------------------------------------------------
;; 5. Core Deque Operations: push!, pop!, steal!
;; -----------------------------------------------------------------------

(define (deque-push! deque val)
  (declare (no-safepoints))
  (if (not (chase-lev-deque? deque))
      (error "deque-push!: expected <chase-lev-deque>" deque)
      (if (not val)
          (error "deque-push!: task payload cannot be #f (CWE-20)" val)
          (let* ((b (%deque-bottom deque))
                 (t (atomic-ref (%deque-top-box deque)))
                 (cap (deque-capacity deque))
                 (size (- b t)))
            ;; Grow if capacity exhausted (size >= cap - 1)
            (if (>= size (- cap 1))
                (%deque-grow! deque b t))
            (let* ((buf (%deque-buffer deque))
                   (mask (%deque-mask deque)))
              (vector-set! buf (bitwise-and b mask) val)
              (%memory-fence)
              (%deque-bottom-set! deque (+ b 1))
              #t)))))

(define (deque-pop! deque)
  (declare (no-safepoints))
  (if (not (chase-lev-deque? deque))
      (error "deque-pop!: expected <chase-lev-deque>" deque)
      (let* ((b-prev (%deque-bottom deque))
             (b (- b-prev 1)))
        (%deque-bottom-set! deque b)
        (%memory-fence)
        (let* ((top-box (%deque-top-box deque))
               (t (atomic-ref top-box))
               (diff (- b t)))
          (cond
            ((> diff 0)
             ;; Non-empty and >= 2 items: owner safely takes item at b without CAS
             (let* ((buf (%deque-buffer deque))
                    (mask (%deque-mask deque))
                    (val (vector-ref buf (bitwise-and b mask))))
               (vector-set! buf (bitwise-and b mask) #f) ; Clear slot for GC
               val))
            ((= diff 0)
             ;; Exactly 1 item left: owner races against concurrent thief CAS on top-box
             (if (atomic-cas! top-box t (+ t 1))
                 (let* ((buf (%deque-buffer deque))
                        (mask (%deque-mask deque))
                        (val (vector-ref buf (bitwise-and b mask))))
                   (vector-set! buf (bitwise-and b mask) #f)
                   (%deque-bottom-set! deque (+ t 1))
                   val)
                 (begin
                   ;; Lost race to thief: thief stole the last item
                   (%deque-bottom-set! deque (+ t 1))
                   #f)))
            (else
             ;; Deque was empty (t > b, diff < 0)
             (%deque-bottom-set! deque t)
             #f))))))

(define (deque-steal! deque)
  (declare (no-safepoints))
  (if (not (chase-lev-deque? deque))
      (error "deque-steal!: expected <chase-lev-deque>" deque)
      (let* ((top-box (%deque-top-box deque))
             (t (atomic-ref top-box)))
        (%memory-fence)
        (let* ((b (%deque-bottom deque))
               (diff (- b t)))
          (if (<= diff 0)
              'empty
              (let* ((buf (%deque-buffer deque))
                     (mask (%deque-mask deque))
                     (val (vector-ref buf (bitwise-and t mask))))
                (if (atomic-cas! top-box t (+ t 1))
                    val
                    'abort)))))))

;; -----------------------------------------------------------------------
;; 6. L1 Bounded Ring Buffer (Go-Style 256-Entry Circular Queue, Issue #804)
;; -----------------------------------------------------------------------
;; Fields:
;;   buffer  : fixed-length 256-element vector
;;   head    : fixnum read index
;;   tail    : fixnum write index
;;   runnext : single priority task slot for instant zero-overhead execution
(define *l1-ring-capacity* 256)
(define *l1-ring-mask* 255)
(define *l1-batch-size* 128)

(define-record-type <l1-ring-buffer>
  (%make-l1-ring-buffer buffer head-box tail runnext)
  l1-ring-buffer?
  (buffer   %l1-ring-buffer)
  (head-box %l1-ring-head-box)
  (tail     %l1-ring-tail     %l1-ring-tail-set!)
  (runnext  %l1-ring-runnext  %l1-ring-runnext-set!))

(define (make-l1-ring-buffer)
  (declare (no-safepoints))
  (%make-l1-ring-buffer (make-vector *l1-ring-capacity* #f) (make-atomic-box 0) 0 #f))

(define (%l1-ring-head l1)
  (atomic-ref (%l1-ring-head-box l1)))

(define (%l1-ring-head-set! l1 val)
  (atomic-set! (%l1-ring-head-box l1) val))

(define (l1-ring-count l1)
  (declare (no-safepoints))
  (if (not (l1-ring-buffer? l1))
      (error "l1-ring-count: expected <l1-ring-buffer>" l1)
      (let* ((h (%l1-ring-head l1))
             (t (%l1-ring-tail l1))
             (diff (- t h))
             (nxt (if (%l1-ring-runnext l1) 1 0)))
        (+ (if (> diff 0) diff 0) nxt))))

(define (l1-ring-empty? l1)
  (declare (no-safepoints))
  (if (not (l1-ring-buffer? l1))
      (error "l1-ring-empty?: expected <l1-ring-buffer>" l1)
      (and (not (%l1-ring-runnext l1))
           (>= (%l1-ring-head l1) (%l1-ring-tail l1)))))

(define (l1-ring-full? l1)
  (declare (no-safepoints))
  (if (not (l1-ring-buffer? l1))
      (error "l1-ring-full?: expected <l1-ring-buffer>" l1)
      (>= (- (%l1-ring-tail l1) (%l1-ring-head l1)) *l1-ring-capacity*)))

(define (l1-ring-runnext l1)
  (declare (no-safepoints))
  (if (not (l1-ring-buffer? l1))
      (error "l1-ring-runnext: expected <l1-ring-buffer>" l1)
      (%l1-ring-runnext l1)))

;; Batch offload: transfer oldest 128 tasks from L1 ring to L2 Chase-Lev deque
(define (%l1-ring-batch-offload! l1 l2-deque)
  (let* ((h (%l1-ring-head l1))
         (buf (%l1-ring-buffer l1))
         (cnt (min *l1-batch-size* (- (%l1-ring-tail l1) h))))
    (if (and l2-deque (chase-lev-deque? l2-deque))
        (let loop ((i 0))
          (if (< i cnt)
              (let* ((idx (+ h i))
                     (slot (bitwise-and idx *l1-ring-mask*))
                     (task (vector-ref buf slot)))
                (vector-set! buf slot #f) ; Clear slot for GC (CWE-416)
                (if task
                    (deque-push! l2-deque task)
                    #f)
                (loop (+ i 1)))
              (begin
                (%l1-ring-head-set! l1 (+ h cnt))
                cnt)))
        0)))

;; Batch refill: transfer up to 128 tasks from L2 Chase-Lev deque into L1 ring
(define (%l1-ring-batch-refill! l1 l2-deque)
  (if (and l2-deque (chase-lev-deque? l2-deque))
      (let* ((buf (%l1-ring-buffer l1))
             (t (%l1-ring-tail l1)))
        (let loop ((count 0) (cur-tail t))
          (if (< count *l1-batch-size*)
              (let ((task (deque-pop! l2-deque)))
                (if task
                    (begin
                      (vector-set! buf (bitwise-and cur-tail *l1-ring-mask*) task)
                      (loop (+ count 1) (+ cur-tail 1)))
                    (begin
                      (%l1-ring-tail-set! l1 cur-tail)
                      count)))
              (begin
                (%l1-ring-tail-set! l1 cur-tail)
                count))))
      0))

(define l1-ring-push!
  (begin (declare (no-safepoints))
   (case-lambda
    ((l1 val)
     (l1-ring-push! l1 val #f))
    ((l1 val l2-deque)
     (if (not (l1-ring-buffer? l1))
         (error "l1-ring-push!: expected <l1-ring-buffer>" l1)
         (if (not val)
             (error "l1-ring-push!: task payload cannot be #f (CWE-20)" val)
             (let ((rn (%l1-ring-runnext l1)))
               (if (not rn)
                   ;; Fast-path: runnext slot is empty -> 1-instruction direct handoff
                   (begin
                     (%l1-ring-runnext-set! l1 val)
                     #t)
                   ;; Slow-path: runnext occupied -> put old runnext into ring, update runnext to val
                   (let* ((to-insert rn)
                          (h (%l1-ring-head l1))
                          (t (%l1-ring-tail l1))
                          (size (- t h)))
                     ;; If ring buffer is full (256 items), offload oldest 128 to L2 deque
                     (if (>= (+ size 1) *l1-ring-capacity*)
                         (%l1-ring-batch-offload! l1 l2-deque)
                         #f)
                     (let* ((new-h (%l1-ring-head l1))
                            (new-t (%l1-ring-tail l1))
                            (buf (%l1-ring-buffer l1))
                            (slot (bitwise-and new-t *l1-ring-mask*)))
                       (vector-set! buf slot to-insert)
                       (%l1-ring-tail-set! l1 (+ new-t 1))
                       (%l1-ring-runnext-set! l1 val)
                       #t))))))))))

(define l1-ring-pop!
  (begin (declare (no-safepoints))
   (case-lambda
    ((l1)
     (l1-ring-pop! l1 #f))
    ((l1 l2-deque)
     (if (not (l1-ring-buffer? l1))
         (error "l1-ring-pop!: expected <l1-ring-buffer>" l1)
         (let ((rn (%l1-ring-runnext l1)))
           (if rn
               ;; Fast-path: take from runnext (1 instruction, CAS-free)
               (begin
                 (%l1-ring-runnext-set! l1 #f)
                 rn)
               ;; Second-path: take LIFO from ring buffer tail
               (let* ((h-box (%l1-ring-head-box l1))
                      (h (atomic-ref h-box))
                      (t (%l1-ring-tail l1))
                      (diff (- t h)))
                 (cond
                   ((> diff 1)
                    ;; Non-empty and >= 2 items: owner safely takes item at t-1 without CAS
                    (let* ((new-t (- t 1))
                           (buf (%l1-ring-buffer l1))
                           (slot (bitwise-and new-t *l1-ring-mask*))
                           (val (vector-ref buf slot)))
                      (vector-set! buf slot #f) ; Clear slot for GC (CWE-416)
                      (%l1-ring-tail-set! l1 new-t)
                      val))
                   ((= diff 1)
                    ;; Exactly 1 item left: owner races against concurrent thief CAS on head-box
                    (let* ((buf (%l1-ring-buffer l1))
                           (slot (bitwise-and h *l1-ring-mask*))
                           (val (vector-ref buf slot)))
                      (if (atomic-cas! h-box h (+ h 1))
                          (begin
                            (vector-set! buf slot #f)
                            (%l1-ring-tail-set! l1 (+ h 1))
                            val)
                          (begin
                            ;; Lost race to thief
                            (%l1-ring-tail-set! l1 (+ h 1))
                            #f))))
                   (else
                    ;; Third-path: L1 is empty -> try refill from L2 deque
                    (if (and l2-deque (chase-lev-deque? l2-deque))
                        (let ((refilled (%l1-ring-batch-refill! l1 l2-deque)))
                          (if (> refilled 0)
                              (let* ((t-refilled (%l1-ring-tail l1))
                                     (new-t (- t-refilled 1))
                                     (buf (%l1-ring-buffer l1))
                                     (slot (bitwise-and new-t *l1-ring-mask*))
                                     (val (vector-ref buf slot)))
                                (vector-set! buf slot #f)
                                (%l1-ring-tail-set! l1 new-t)
                                val)
                              #f))
                        #f)))))))))))

(define (l1-ring-steal! l1)
  (declare (no-safepoints))
  (if (not (l1-ring-buffer? l1))
      (error "l1-ring-steal!: expected <l1-ring-buffer>" l1)
      (let* ((h-box (%l1-ring-head-box l1))
             (h (atomic-ref h-box))
             (t (%l1-ring-tail l1))
             (diff (- t h)))
        (if (<= diff 0)
            'empty
            (let* ((buf (%l1-ring-buffer l1))
                   (slot (bitwise-and h *l1-ring-mask*))
                   (task (vector-ref buf slot)))
              (if (not task)
                  'empty
                  (if (atomic-cas! h-box h (+ h 1))
                      (begin
                        (vector-set! buf slot #f) ; Clear slot for GC (CWE-416)
                        task)
                      'abort)))))))

(define (l1-ring-drain-all! l1)
  (declare (no-safepoints))
  (if (not (l1-ring-buffer? l1))
      (error "l1-ring-drain-all!: expected <l1-ring-buffer>" l1)
      (let* ((rn (%l1-ring-runnext l1))
             (init-res (if rn
                           (begin
                             (%l1-ring-runnext-set! l1 #f)
                             (list rn))
                           '())))
        (let loop ((acc init-res))
          (let ((item (l1-ring-pop! l1 #f)))
            (if item
                (loop (cons item acc))
                (reverse acc)))))))
