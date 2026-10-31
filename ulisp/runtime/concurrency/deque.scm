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
                   (%make-chase-lev-deque (make-atomic-box 0) 0 buf cap (- cap 1)))))))))

;; -----------------------------------------------------------------------
;; 3. Deque Observers & State Predicates
;; -----------------------------------------------------------------------

(define (deque-count deque)
  (if (not (chase-lev-deque? deque))
      (error "deque-count: expected <chase-lev-deque>" deque)
      (let* ((b (%deque-bottom deque))
             (t (atomic-ref (%deque-top-box deque)))
             (diff (- b t)))
        (if (> diff 0) diff 0))))

(define (deque-empty? deque)
  (if (not (chase-lev-deque? deque))
      (error "deque-empty?: expected <chase-lev-deque>" deque)
      (let ((b (%deque-bottom deque))
            (t (atomic-ref (%deque-top-box deque))))
        (>= t b))))

(define (deque-stats deque)
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
