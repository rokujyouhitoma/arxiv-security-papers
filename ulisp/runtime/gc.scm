;;; =======================================================================
;;; ULisp Pure Scheme Runtime: gc.scm (Pre-Scheme Architecture)
;;; Conforms to DSN-33 Architecture Specification & Issue #580
;;;
;;; Pre-Scheme inspired low-level garbage collection state management,
;;; heap allocation, dynamic mature space growth, and write barriers.
;;; =======================================================================

;; Static Generational GC State Buffer indices:
;;   0: nursery_base, 1: nursery_size, 2: mature_from, 3: mature_to
;;   4: mature_size, 5: mature_free, 6: stack_bottom, 7: minor_count
;;   8: major_count, 9: remset_ptr, 10: remset_count, 11: gen_mode
;;   12: mature_max_size, 13: mature_growth_count, 14: profile_id, 15: debug_gc
;;   16: stress_mode, 17: total_alloc_bytes, 18: total_survived_bytes
;;   19: total_gc_time_ns, 20: stats_mode, 21: start_time_sec, 22: start_time_nsec

(define *runtime-heap-default-size* (* 16 1024 1024)) ; 16MB default

(define (runtime-gc-state-ref idx)
  (%raw-load (%get-gc-state-ptr) (* idx 8)))

(define (runtime-gc-state-set! idx val)
  (%raw-store! (%get-gc-state-ptr) (* idx 8) (%to-raw val)))

;; Query individual GC state slots
(define (runtime-gc-nursery-base) (runtime-gc-state-ref 0))
(define (runtime-gc-nursery-size) (%to-fixnum (runtime-gc-state-ref 1)))
(define (runtime-gc-mature-from)  (runtime-gc-state-ref 2))
(define (runtime-gc-mature-to)    (runtime-gc-state-ref 3))
(define (runtime-gc-mature-size)  (%to-fixnum (runtime-gc-state-ref 4)))
(define (runtime-gc-mature-free)  (runtime-gc-state-ref 5))
(define (runtime-gc-stack-bottom) (runtime-gc-state-ref 6))
(define (runtime-gc-minor-count)  (%to-fixnum (runtime-gc-state-ref 7)))
(define (runtime-gc-major-count)  (%to-fixnum (runtime-gc-state-ref 8)))
(define (runtime-gc-remset-ptr)   (runtime-gc-state-ref 9))
(define (runtime-gc-remset-count) (%to-fixnum (runtime-gc-state-ref 10)))
(define (runtime-gc-gen-mode)     (%to-fixnum (runtime-gc-state-ref 11)))
(define (runtime-gc-max-size)     (%to-fixnum (runtime-gc-state-ref 12)))
(define (runtime-gc-growth-count) (%to-fixnum (runtime-gc-state-ref 13)))
(define (runtime-gc-profile-id)   (%to-fixnum (runtime-gc-state-ref 14)))
(define (runtime-gc-debug-gc)     (%to-fixnum (runtime-gc-state-ref 15)))
(define (runtime-gc-stress-mode)  (%to-fixnum (runtime-gc-state-ref 16)))
(define (runtime-set-gc-stress-mode! v)
  (runtime-gc-state-set! 16 (if v 1 0)))

;; GC Statistics accessors (Issue #622)
(define (runtime-gc-alloc-bytes)    (%to-fixnum (runtime-gc-state-ref 17)))
(define (runtime-gc-survived-bytes) (%to-fixnum (runtime-gc-state-ref 18)))
(define (runtime-gc-total-time-ns)  (%to-fixnum (runtime-gc-state-ref 19)))
(define (runtime-gc-stats-mode)     (%to-fixnum (runtime-gc-state-ref 20)))
(define (runtime-set-gc-stats-mode! v)
  (runtime-gc-state-set! 20 (if v 1 0)))

;; Initialize generational GC heap with profile
(define (runtime-init-heap size-bytes profile-id debug-gc)
  (let* ((n-size
          (cond
            ((= profile-id 1) 268435456)   ; compiler: 256MB
            ((= profile-id 2) 16777216)    ; server: 16MB
            (else 4194304)))               ; standard: 4MB
         (m-size
          (cond
            ((= profile-id 1) 268435456)   ; compiler: 256MB
            ((= profile-id 2) 268435456)   ; server: 256MB
            (else 67108864)))              ; standard: 64MB
         (max-size
          (cond
            ((= profile-id 1) 4294967296)  ; compiler: 4GB
            ((= profile-id 2) 4294967296)  ; server: 4GB
            (else 1073741824)))            ; standard: 1GB
         (total-alloc (+ n-size (* m-size 2) 65536))
         (heap (sys-mmap total-alloc)))
    (if (<= heap 0)
        (runtime-oom-exit)
        (let* ((m-from (%ptr-add heap n-size))
               (m-to   (%ptr-add m-from m-size))
               (remset (%ptr-add m-to m-size)))
          (runtime-gc-state-set! 0 heap)
          (runtime-gc-state-set! 1 n-size)
          (runtime-gc-state-set! 2 m-from)
          (runtime-gc-state-set! 3 m-to)
          (runtime-gc-state-set! 4 m-size)
          (runtime-gc-state-set! 5 m-from)
          (runtime-gc-state-set! 6 0)
          (runtime-gc-state-set! 7 0)
          (runtime-gc-state-set! 8 0)
          (runtime-gc-state-set! 9 remset)
          (runtime-gc-state-set! 10 0)
          (runtime-gc-state-set! 11 1)
          (runtime-gc-state-set! 12 max-size)
          (runtime-gc-state-set! 13 0)
          (runtime-gc-state-set! 14 profile-id)
          (runtime-gc-state-set! 15 debug-gc)
          (%set-heap-ptr! heap)
          heap))))

;; Dynamic Mature Space Expansion (Issue #566 policy)
(define (runtime-gc-grow-mature)
  (if (not (= (runtime-gc-gen-mode) 1))
      0
      (let* ((m-from (runtime-gc-mature-from))
             (m-size (runtime-gc-mature-size))
             (m-free (runtime-gc-mature-free))
             (max-size (runtime-gc-max-size))
             (used (- m-free m-from)))
        (if (<= (* used 10) (* m-size 7))
            0 ; Occupancy <= 70%, no growth needed
            (let ((new-size (let ((d (* m-size 2)))
                              (if (> d max-size) max-size d))))
              (if (<= new-size m-size)
                  0
                  (let ((new-addr (sys-mremap m-from m-size new-size 1))) ; MREMAP_MAYMOVE = 1
                    (if (<= new-addr 0)
                        0
                        (begin
                          (if (not (= new-addr m-from))
                              (let ((diff (- new-addr m-from)))
                                (runtime-gc-state-set! 2 new-addr)
                                (runtime-gc-state-set! 5 (+ m-free diff))))
                          (runtime-gc-state-set! 4 new-size)
                          (runtime-gc-state-set! 13 (+ (runtime-gc-growth-count) 1))
                          1)))))))))

;; Generational Write Barrier
(define (runtime-gc-write-barrier mature-obj-addr val)
  (if (= (runtime-gc-gen-mode) 1)
      (let* ((n-base (runtime-gc-nursery-base))
             (n-size (runtime-gc-nursery-size))
             (val-addr (bitwise-and val -8)))
        (if (and (>= val-addr n-base) (< val-addr (+ n-base n-size)))
            (let ((remset (runtime-gc-remset-ptr))
                  (count  (runtime-gc-remset-count)))
              (if (and (> remset 0) (< count 4096))
                  (begin
                    (%raw-store! remset (* count 8) mature-obj-addr)
                    (runtime-gc-state-set! 10 (+ count 1)))))))))

;; Out-Of-Memory Handler
(define (runtime-oom-exit)
  (sys-write-string "Fatal Error: ULisp Heap Limit Exhausted (OOM)\n")
  (sys-flush)
  (sys-exit 1))
