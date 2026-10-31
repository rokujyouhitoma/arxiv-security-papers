;;; =======================================================================
;;; ULisp Runtime Concurrency: Process-Local Ephemeral Arena (arena.scm)
;;; Conforms to DSN-37 Section 5 & Section 14.2 (Phase 0 Task 0.1), Issue #630
;;;
;;; Implements isolated per-task bump allocation arenas (2KB - 8KB initial)
;;; with 8-byte alignment, O(1) instant full reset, chained 8KB overflow
;;; chunks, and CWE-190 / CWE-212 / CWE-400 security mitigations.
;;; =======================================================================

;; -----------------------------------------------------------------------
;; 1. Arena Configuration Constants
;; -----------------------------------------------------------------------

(define *arena-min-capacity* 2048)           ; 2KB minimum initial capacity
(define *arena-default-capacity* 4096)       ; 4KB default initial capacity
(define *arena-max-initial-capacity* 8192)   ; 8KB standard initial upper bound
(define *arena-overflow-chunk-size* 8192)    ; 8KB chained overflow chunk capacity
(define *arena-default-align* 8)             ; 8-byte boundary alignment (System V AMD64 / tagged ptr)
(define *arena-default-base* 65536)          ; 0x10000 (64KB aligned logical base address)
(define *arena-chunk-stride* 65536)          ; 64KB address stride per overflow chunk
(define *arena-max-chunks* 64)               ; Fail-safe limit: max 64 overflow chunks (512KB) per task
(define *arena-max-alloc-size* 1048576)      ; Fail-safe limit: max 1MB single allocation

;; -----------------------------------------------------------------------
;; 2. Bitwise & Alignment Helpers (Portable across ILisp & ULisp AOT)
;; -----------------------------------------------------------------------

(define (bitwise-not x)
  (- -1 x))

(define (arena-power-of-two? n)
  (and (integer? n)
       (> n 0)
       (= (bitwise-and n (- n 1)) 0)))

(define (arena-align-up size align)
  (let ((mask (- align 1)))
    (bitwise-and (+ size mask) (bitwise-not mask))))

;; -----------------------------------------------------------------------
;; 3. Record Type Definitions (<arena-chunk> & <task-arena>)
;; -----------------------------------------------------------------------

(define-record-type <arena-chunk>
  (make-arena-chunk base offset capacity buffer next)
  arena-chunk?
  (base     arena-chunk-base)
  (offset   arena-chunk-offset   arena-chunk-offset-set!)
  (capacity arena-chunk-capacity)
  (buffer   arena-chunk-buffer)
  (next     arena-chunk-next     arena-chunk-next-set!))

(define-record-type <task-arena>
  (%make-task-arena base offset capacity buffer chunks chunk-count max-chunks total-allocated reset-count)
  task-arena?
  (base            arena-base            arena-base-set!)
  (offset          arena-offset          arena-offset-set!)
  (capacity        arena-capacity        arena-capacity-set!)
  (buffer          arena-buffer          arena-buffer-set!)
  (chunks          arena-chunks          arena-chunks-set!)
  (chunk-count     arena-chunk-count     arena-chunk-count-set!)
  (max-chunks      arena-max-chunks      arena-max-chunks-set!)
  (total-allocated arena-total-allocated arena-total-allocated-set!)
  (reset-count     arena-reset-count     arena-reset-count-set!))

(define (%init-task-arena base offset capacity)
  (if (or (not (integer? capacity)) (<= capacity 0) (> capacity *arena-max-alloc-size*))
      (error "make-task-arena: capacity must be a positive integer within limits" capacity)
      (if (or (not (integer? offset)) (< offset 0) (> offset capacity))
          (error "make-task-arena: offset out of range" offset)
          (let* ((aligned-cap (arena-align-up capacity *arena-default-align*))
                 (raw-base (if (and (integer? base) (> base 0)) base *arena-default-base*))
                 (aligned-base (arena-align-up raw-base *arena-default-align*))
                 (buf (make-bytevector aligned-cap)))
            (%make-task-arena aligned-base
                              offset
                              aligned-cap
                              buf
                              '()
                              0
                              *arena-max-chunks*
                              0
                              0)))))

(define make-task-arena
  (case-lambda
    (()
     (%init-task-arena *arena-default-base* 0 *arena-default-capacity*))
    ((initial-capacity)
     (%init-task-arena *arena-default-base* 0 initial-capacity))
    ((initial-capacity base-addr)
     (%init-task-arena base-addr 0 initial-capacity))
    ((base offset capacity)
     (%init-task-arena base offset capacity))))

;; -----------------------------------------------------------------------
;; 4. Overflow Chunk Chaining Fallback (DSN-37 Section 5.3)
;; -----------------------------------------------------------------------

(define (%arena-allocate-new-chunk! arena aligned-size align)
  (let ((chunks (arena-chunks arena))
        (count  (arena-chunk-count arena))
        (max-c  (arena-max-chunks arena)))
    (if (>= count max-c)
        (error "arena-overflow-fallback!: maximum overflow chunks exceeded (CWE-400 guard)" max-c)
        (let* ((chunk-cap (if (> aligned-size *arena-overflow-chunk-size*)
                              (arena-align-up aligned-size align)
                              *arena-overflow-chunk-size*))
               (prev-end (if (pair? chunks)
                             (+ (arena-chunk-base (car chunks))
                                (arena-align-up (arena-chunk-capacity (car chunks)) *arena-chunk-stride*))
                             (+ (arena-base arena)
                                (arena-align-up (arena-capacity arena) *arena-chunk-stride*))))
               (chunk-base (arena-align-up prev-end align))
               (chunk-buf (make-bytevector chunk-cap))
               (new-chunk (make-arena-chunk chunk-base aligned-size chunk-cap chunk-buf chunks)))
          (arena-chunks-set! arena (cons new-chunk chunks))
          (arena-chunk-count-set! arena (+ count 1))
          (arena-total-allocated-set! arena (+ (arena-total-allocated arena) aligned-size))
          chunk-base))))

(define (%arena-overflow-fallback-impl! arena aligned-size align)
  (let ((chunks (arena-chunks arena)))
    (if (pair? chunks)
        (let* ((head (car chunks))
               (cur-off (arena-align-up (arena-chunk-offset head) align))
               (next-off (+ cur-off aligned-size)))
          (if (<= next-off (arena-chunk-capacity head))
              (begin
                (arena-chunk-offset-set! head next-off)
                (arena-total-allocated-set! arena (+ (arena-total-allocated arena) aligned-size))
                (+ (arena-chunk-base head) cur-off))
              (%arena-allocate-new-chunk! arena aligned-size align)))
        (%arena-allocate-new-chunk! arena aligned-size align))))

(define arena-overflow-fallback!
  (case-lambda
    ((arena aligned-size)
     (%arena-overflow-fallback-impl! arena aligned-size *arena-default-align*))
    ((arena aligned-size align)
     (%arena-overflow-fallback-impl! arena aligned-size align))))

;; -----------------------------------------------------------------------
;; 5. Fast Bump Allocation (DSN-37 Section 5.2)
;; -----------------------------------------------------------------------

(define (%arena-allocate-impl! arena size align)
  (if (not (task-arena? arena))
      (error "arena-allocate!: expected <task-arena>" arena)
      (if (or (not (integer? size)) (<= size 0) (> size *arena-max-alloc-size*))
          (error "arena-allocate!: size must be a positive integer within limits (CWE-190 guard)" size)
          (if (or (not (arena-power-of-two? align)) (< align *arena-default-align*))
              (error "arena-allocate!: alignment must be a power of two >= 8" align)
              (let* ((aligned-size (bitwise-and (+ size (- align 1)) (bitwise-not (- align 1))))
                     (current-off (if (= align *arena-default-align*)
                                      (arena-offset arena)
                                      (arena-align-up (arena-offset arena) align)))
                     (next-off (+ current-off aligned-size)))
                (if (or (not (null? (arena-chunks arena)))
                        (> next-off (arena-capacity arena)))
                    (arena-overflow-fallback! arena aligned-size align)
                    (begin
                      (arena-offset-set! arena next-off)
                      (arena-total-allocated-set! arena (+ (arena-total-allocated arena) aligned-size))
                      (+ (arena-base arena) current-off))))))))

(define arena-allocate!
  (case-lambda
    ((arena size)
     (%arena-allocate-impl! arena size *arena-default-align*))
    ((arena size align)
     (%arena-allocate-impl! arena size align))))

;; -----------------------------------------------------------------------
;; 6. O(1) Instant Reset & Secure Zero-Scrubbing Reset
;; -----------------------------------------------------------------------

(define (arena-reset! arena)
  (if (not (task-arena? arena))
      (error "arena-reset!: expected <task-arena>" arena)
      (begin
        (arena-offset-set! arena 0)
        (if (not (null? (arena-chunks arena)))
            (begin
              (arena-chunks-set! arena '())
              (arena-chunk-count-set! arena 0)))
        (arena-reset-count-set! arena (+ (arena-reset-count arena) 1))
        #t)))

(define (%zero-scrub-bytevector! bv limit)
  (let ((end (if (> limit (bytevector-length bv)) (bytevector-length bv) limit)))
    (let loop ((i 0))
      (if (< i end)
          (begin
            (bytevector-u8-set! bv i 0)
            (loop (+ i 1)))
          #t))))

(define (arena-secure-reset! arena)
  (if (not (task-arena? arena))
      (error "arena-secure-reset!: expected <task-arena>" arena)
      (begin
        (%zero-scrub-bytevector! (arena-buffer arena) (arena-offset arena))
        (let loop ((cs (arena-chunks arena)))
          (if (pair? cs)
              (let ((c (car cs)))
                (%zero-scrub-bytevector! (arena-chunk-buffer c) (arena-chunk-offset c))
                (loop (cdr cs)))))
        (arena-reset! arena))))

;; -----------------------------------------------------------------------
;; 7. Arena Memory Read / Write & Telemetry Accessors
;; -----------------------------------------------------------------------

(define (%resolve-arena-buffer-and-offset arena addr size)
  (if (not (task-arena? arena))
      (error "arena memory access: expected <task-arena>" arena)
      (let ((p-base (arena-base arena))
            (p-off  (arena-offset arena)))
        (if (and (>= addr p-base) (<= (+ addr size) (+ p-base p-off)))
            (cons (arena-buffer arena) (- addr p-base))
            (let loop ((cs (arena-chunks arena)))
              (if (null? cs)
                  (error "arena memory access: address out of allocated bounds (CWE-787 guard)" addr)
                  (let* ((c (car cs))
                         (c-base (arena-chunk-base c))
                         (c-off  (arena-chunk-offset c)))
                    (if (and (>= addr c-base) (<= (+ addr size) (+ c-base c-off)))
                        (cons (arena-chunk-buffer c) (- addr c-base))
                        (loop (cdr cs))))))))))

(define (arena-u8-ref arena addr)
  (let ((resolved (%resolve-arena-buffer-and-offset arena addr 1)))
    (bytevector-u8-ref (car resolved) (cdr resolved))))

(define (arena-u8-set! arena addr val)
  (let ((resolved (%resolve-arena-buffer-and-offset arena addr 1)))
    (bytevector-u8-set! (car resolved) (cdr resolved) (bitwise-and val 255))))

(define (arena-u64-ref arena addr)
  (if (not (= (modulo addr 8) 0))
      (error "arena-u64-ref: unaligned 64-bit access" addr)
      (let* ((resolved (%resolve-arena-buffer-and-offset arena addr 8))
             (bv (car resolved))
             (off (cdr resolved)))
        (let loop ((i 7) (acc 0))
          (if (< i 0)
              acc
              (loop (- i 1)
                    (+ (* acc 256) (bytevector-u8-ref bv (+ off i)))))))))

(define (arena-u64-set! arena addr val)
  (if (not (= (modulo addr 8) 0))
      (error "arena-u64-set!: unaligned 64-bit access" addr)
      (let* ((resolved (%resolve-arena-buffer-and-offset arena addr 8))
             (bv (car resolved))
             (off (cdr resolved)))
        (let loop ((i 0) (v val))
          (if (< i 8)
              (let* ((b (modulo v 256))
                     (u-b (if (< b 0) (+ b 256) b))
                     (next-v (if (< v 0) (quotient (- v u-b) 256) (quotient v 256))))
                (bytevector-u8-set! bv (+ off i) u-b)
                (loop (+ i 1) next-v))
              #t)))))

(define (arena-used-bytes arena)
  (let loop ((cs (arena-chunks arena)) (acc (arena-offset arena)))
    (if (null? cs)
        acc
        (loop (cdr cs) (+ acc (arena-chunk-offset (car cs)))))))

(define (arena-available-bytes arena)
  (- (arena-capacity arena) (arena-offset arena)))

(define (arena-empty? arena)
  (and (= (arena-offset arena) 0)
       (null? (arena-chunks arena))))

(define (arena-stats arena)
  (list (cons 'base (arena-base arena))
        (cons 'offset (arena-offset arena))
        (cons 'capacity (arena-capacity arena))
        (cons 'used-bytes (arena-used-bytes arena))
        (cons 'available-bytes (arena-available-bytes arena))
        (cons 'chunk-count (arena-chunk-count arena))
        (cons 'total-allocated (arena-total-allocated arena))
        (cons 'reset-count (arena-reset-count arena))))
