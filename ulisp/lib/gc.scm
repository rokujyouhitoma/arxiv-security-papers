;;; =======================================================================
;;; ULisp Standard Library: Generational Copying Garbage Collector
;;; Conforms to DSN-33 Section 8.5, DSN-36 & Issue #525
;;; Based on Cornell CS 6120 & Bacon et al. Unified Theory of GC
;;; Implemented purely in Scheme with ZERO heap allocations during GC.
;;; =======================================================================

;;; Static GC State Buffer Layout via %get-gc-state-ptr:
;;; Dual-Space Mode (mode 0):
;;;   [0]: from, [8]: to, [16]: size, [24]: bottom, [32]: count, [40]: free_ptr
;;; Generational Mode (mode 1):
;;;   [0]: nursery_base, [8]: nursery_size, [16]: mature_from, [24]: mature_to
;;;   [32]: mature_size, [40]: mature_free, [48]: stack_bottom, [56]: minor_count
;;;   [64]: major_count, [72]: remset_ptr, [80]: remset_count, [88]: gen_mode

;; Dual-space accessors (backward compatibility)
(define (gc-from) (%raw-load (%get-gc-state-ptr) 0))
(define (gc-to) (%raw-load (%get-gc-state-ptr) 8))
(define (gc-size) (%raw-load (%get-gc-state-ptr) 16))
(define (gc-bottom)
  (if (= (gc-gen-mode) 1)
      (%raw-load (%get-gc-state-ptr) 48)
      (%raw-load (%get-gc-state-ptr) 24)))
(define (gc-count) (%raw-load (%get-gc-state-ptr) 32))
(define (gc-free) (%raw-load (%get-gc-state-ptr) 40))

(define (set-gc-from! v) (%raw-store! (%get-gc-state-ptr) 0 v))
(define (set-gc-to! v) (%raw-store! (%get-gc-state-ptr) 8 v))
(define (set-gc-size! v) (%raw-store! (%get-gc-state-ptr) 16 v))
(define (set-gc-bottom! v) (%raw-store! (%get-gc-state-ptr) 24 v))
(define (set-gc-count! v) (%raw-store! (%get-gc-state-ptr) 32 v))
(define (set-gc-free! v) (%raw-store! (%get-gc-state-ptr) 40 v))

;; Generational mode accessors
(define (gc-nursery-base) (%raw-load (%get-gc-state-ptr) 0))
(define (gc-nursery-size) (%raw-load (%get-gc-state-ptr) 8))
(define (gc-mature-from)  (%raw-load (%get-gc-state-ptr) 16))
(define (gc-mature-to)    (%raw-load (%get-gc-state-ptr) 24))
(define (gc-mature-size)  (%raw-load (%get-gc-state-ptr) 32))
(define (gc-mature-free)  (%raw-load (%get-gc-state-ptr) 40))
(define (gc-gen-bottom)   (%raw-load (%get-gc-state-ptr) 48))
(define (gc-minor-count)  (%raw-load (%get-gc-state-ptr) 56))
(define (gc-major-count)  (%raw-load (%get-gc-state-ptr) 64))
(define (gc-remset-ptr)   (%raw-load (%get-gc-state-ptr) 72))
(define (gc-remset-count) (%raw-load (%get-gc-state-ptr) 80))
(define (gc-gen-mode)     (%raw-load (%get-gc-state-ptr) 88))

(define (set-gc-mature-free! v) (%raw-store! (%get-gc-state-ptr) 40 v))

;;; Initialize classic dual-space copying garbage collector
(define (gc-init! from-space to-space heap-size stack-bottom)
  (%raw-store! (%get-gc-state-ptr) 88 0) ; mode 0
  (set-gc-from! from-space)
  (set-gc-to! to-space)
  (set-gc-size! heap-size)
  (set-gc-bottom! stack-bottom)
  (set-gc-count! 0)
  (set-gc-free! to-space)
  (%set-heap-ptr! from-space))

;;; Initialize Nursery & Generational Copying Garbage Collector
(define (gc-init-generational! nursery-base nursery-size mature-from mature-to mature-size stack-bottom remset-ptr)
  (%raw-store! (%get-gc-state-ptr) 0 nursery-base)
  (%raw-store! (%get-gc-state-ptr) 8 nursery-size)
  (%raw-store! (%get-gc-state-ptr) 16 mature-from)
  (%raw-store! (%get-gc-state-ptr) 24 mature-to)
  (%raw-store! (%get-gc-state-ptr) 32 mature-size)
  (%raw-store! (%get-gc-state-ptr) 40 mature-from)   ; mature-free starts at mature-from
  (%raw-store! (%get-gc-state-ptr) 48 stack-bottom)
  (%raw-store! (%get-gc-state-ptr) 56 0)             ; minor count = 0
  (%raw-store! (%get-gc-state-ptr) 64 0)             ; major count = 0
  (%raw-store! (%get-gc-state-ptr) 72 remset-ptr)
  (%raw-store! (%get-gc-state-ptr) 80 0)             ; remset count = 0
  (%raw-store! (%get-gc-state-ptr) 88 1)             ; generational mode = 1
  (%set-heap-ptr! nursery-base))

;;; Predicate: is value a pointer pointing into nursery?
(define (gc-nursery-pointer? val)
  (let ((tag (%ptr-tag val)))
    (if (or (= tag 1) (= tag 3))
        (let ((addr (%ptr-untag val)))
          (and (>= addr (gc-nursery-base))
               (< addr (%ptr-add (gc-nursery-base) (gc-nursery-size)))))
        #f)))

;;; Predicate: is the value a heap pointer pointing into current from-space?
(define (gc-heap-pointer? val)
  (let ((tag (%ptr-tag val)))
    (if (or (= tag 1) (= tag 3))
        (let ((addr (%ptr-untag val)))
          (and (>= addr (gc-from))
               (< addr (%ptr-add (gc-from) (gc-size)))))
        #f)))

;;; Copy an object from from-space to to-space and return the forwarded pointer
(define (gc-copy-object val)
  (let* ((tag (%ptr-tag val))
         (orig (%ptr-untag val))
         ;; Read 8-byte prefix header located at [orig - 8]
         (hdr (%raw-load (%ptr-add orig -8) 0)))
    ;; Check if already forwarded in current GC cycle
    (if (and (not (= (%ptr-tag hdr) 0))
             (let ((addr (%ptr-untag hdr)))
               (and (>= addr (gc-to))
                    (< addr (%ptr-add (gc-to) (gc-size))))))
        hdr
        ;; Not yet copied: allocate in to-space
        (let* ((to-free (gc-free))
               (type (bitwise-and hdr 255))
               (payload-bytes (quotient hdr 65536))
               (total-bytes (+ payload-bytes 8))
               (new-orig (%ptr-add to-free 8))
               (new-val (%ptr-tag-add new-orig tag)))
          ;; Copy 8-byte header and payload words
          (let copy-loop ((offset 0))
            (if (< offset total-bytes)
                (begin
                  (%raw-store! to-free offset (%raw-load (%ptr-add orig -8) offset))
                  (copy-loop (+ offset 8)))))
          ;; Write forwarding pointer at original header location
          (%raw-store! (%ptr-add orig -8) 0 new-val)
          ;; Advance to-space free pointer
          (set-gc-free! (%ptr-add to-free total-bytes))
          ;; Return forwarded tagged pointer
          new-val))))

;;; Promote a surviving object from Nursery to Mature Space during Minor GC
(define (gc-promote-object val)
  (let* ((tag (%ptr-tag val))
         (orig (%ptr-untag val))
         (hdr (%raw-load (%ptr-add orig -8) 0)))
    ;; Check if already forwarded during this minor GC cycle
    (if (and (not (= (%ptr-tag hdr) 0))
             (let ((addr (%ptr-untag hdr)))
               (and (>= addr (gc-mature-from))
                    (< addr (%ptr-add (gc-mature-from) (gc-mature-size))))))
        hdr
        ;; Not yet promoted: allocate in mature space
        (let* ((m-free (gc-mature-free))
               (type (bitwise-and hdr 255))
               (payload-bytes (quotient hdr 65536))
               (total-bytes (+ payload-bytes 8))
               (new-orig (%ptr-add m-free 8))
               (new-val (%ptr-tag-add new-orig tag)))
          ;; Copy 8-byte header and payload words
          (let copy-loop ((offset 0))
            (if (< offset total-bytes)
                (begin
                  (%raw-store! m-free offset (%raw-load (%ptr-add orig -8) offset))
                  (copy-loop (+ offset 8)))))
          ;; Write forwarding pointer at original nursery header location
          (%raw-store! (%ptr-add orig -8) 0 new-val)
          ;; Advance mature free pointer
          (set-gc-mature-free! (%ptr-add m-free total-bytes))
          ;; Return forwarded tagged pointer
          new-val))))

;;; Helper to copy only if value is a valid from-space heap pointer
(define (gc-copy-if-heap val)
  (if (gc-heap-pointer? val)
      (gc-copy-object val)
      val))

;;; Cheney breadth-first scan through copied objects in to-space
(define (gc-cheney-scan! scan-start)
  (let scan-loop ((scan scan-start))
    (if (< scan (gc-free))
        (let* ((hdr (%raw-load scan 0))
               (type (bitwise-and hdr 255))
               (payload-bytes (quotient hdr 65536))
               (payload-addr (%ptr-add scan 8)))
          (cond
            ;; Type 1: Pair (2 pointer fields: car, cdr)
            ((= type 1)
             (%raw-store! payload-addr 0 (gc-copy-if-heap (%raw-load payload-addr 0)))
             (%raw-store! payload-addr 8 (gc-copy-if-heap (%raw-load payload-addr 8))))
            ;; Type 2: Closure (slot 0 is code_ptr, slots 1..N-1 are captured vars)
            ((= type 2)
             (let ((num-fields (bitwise-and (quotient hdr 256) 255)))
               (let field-loop ((i 1))
                 (if (< i num-fields)
                     (let ((slot-addr (%ptr-add payload-addr (* i 8))))
                       (%raw-store! slot-addr 0 (gc-copy-if-heap (%raw-load slot-addr 0)))
                       (field-loop (+ i 1)))))))
            ;; Type 3: String (pure byte buffer, no pointers)
            (else #t))
          (scan-loop (%ptr-add scan (+ payload-bytes 8)))))))

;;; Minor Cheney Scan through newly promoted objects in mature space
(define (gc-minor-cheney-scan! scan-start)
  (let scan-loop ((scan scan-start))
    (if (< scan (gc-mature-free))
        (let* ((hdr (%raw-load scan 0))
               (type (bitwise-and hdr 255))
               (payload-bytes (quotient hdr 65536))
               (payload-addr (%ptr-add scan 8)))
          (cond
            ;; Type 1: Pair
            ((= type 1)
             (let ((c1 (%raw-load payload-addr 0))
                   (c2 (%raw-load payload-addr 8)))
               (if (gc-nursery-pointer? c1)
                   (%raw-store! payload-addr 0 (gc-promote-object c1)))
               (if (gc-nursery-pointer? c2)
                   (%raw-store! payload-addr 8 (gc-promote-object c2)))))
            ;; Type 2: Closure
            ((= type 2)
             (let ((num-fields (bitwise-and (quotient hdr 256) 255)))
               (let f-loop ((i 1))
                 (if (< i num-fields)
                     (let* ((slot-addr (%ptr-add payload-addr (* i 8)))
                            (v (%raw-load slot-addr 0)))
                       (if (gc-nursery-pointer? v)
                           (%raw-store! slot-addr 0 (gc-promote-object v)))
                       (f-loop (+ i 1)))))))
            (else #t))
          (scan-loop (%ptr-add scan (+ payload-bytes 8)))))))

;;; Stackmap table lookup: returns entry index or -1 if not found
(define (gc-find-stackmap pc tbl)
  (let ((count (%to-fixnum (%raw-load tbl 0))))
    (let loop ((i 0))
      (if (< i count)
          (let* ((entry-offset (+ 8 (* i 24)))
                 (entry-pc (%raw-load tbl entry-offset)))
            (if (= entry-pc pc)
                i
                (loop (+ i 1))))
          -1))))

;;; Exact Stackmap-Guided GC Root Scanner (Dual-Space)
(define (gc-scan-roots! deepest-sp bottom)
  (let* ((tbl (%get-stackmap-table))
         (tbl-count (%to-fixnum (%raw-load tbl 0))))
    (if (> tbl-count 0)
        ;; --- Exact Stackmap Walk ---
        (let walk-loop ((sp deepest-sp))
          (if (< sp bottom)
              (let* ((word (%raw-load sp 0))
                     (sm-idx (gc-find-stackmap word tbl)))
                (if (>= sm-idx 0)
                    ;; Found safepoint return address!
                    (let* ((entry-offset (+ 8 (* sm-idx 24)))
                           (frame-size (%to-fixnum (%raw-load tbl (+ entry-offset 8))))
                           (bitmap (%to-fixnum (%raw-load tbl (+ entry-offset 16))))
                           (slot-count (quotient frame-size 8))
                           (frame-base (%ptr-add sp 8)))
                      (let slot-loop ((k 0) (mask bitmap))
                        (if (< k slot-count)
                            (begin
                              (if (or (and (< k 60) (= (modulo mask 2) 1))
                                      (>= k 60))
                                  (let* ((slot-addr (%ptr-add frame-base (* k 8)))
                                         (val (%raw-load slot-addr 0)))
                                    (if (gc-heap-pointer? val)
                                        (%raw-store! slot-addr 0 (gc-copy-object val)))))
                              (slot-loop (+ k 1) (if (< k 60) (quotient mask 2) 0)))))
                      (walk-loop (%ptr-add frame-base frame-size)))
                    (walk-loop (%ptr-add sp 8))))))
        ;; --- Fallback Conservative Walk ---
        (let conserv-loop ((sp deepest-sp))
          (if (< sp bottom)
              (let ((val (%raw-load sp 0)))
                (if (gc-heap-pointer? val)
                    (%raw-store! sp 0 (gc-copy-object val)))
                (conserv-loop (%ptr-add sp 8))))))))

;;; Exact Stackmap-Guided GC Root Scanner for Generational Nursery (Minor GC)
(define (gc-scan-roots-generational! deepest-sp bottom)
  (let* ((tbl (%get-stackmap-table))
         (tbl-count (%to-fixnum (%raw-load tbl 0))))
    (if (> tbl-count 0)
        ;; --- Exact Stackmap Walk ---
        (let walk-loop ((sp deepest-sp))
          (if (< sp bottom)
              (let* ((word (%raw-load sp 0))
                     (sm-idx (gc-find-stackmap word tbl)))
                (if (>= sm-idx 0)
                    (let* ((entry-offset (+ 8 (* sm-idx 24)))
                           (frame-size (%to-fixnum (%raw-load tbl (+ entry-offset 8))))
                           (bitmap (%to-fixnum (%raw-load tbl (+ entry-offset 16))))
                           (slot-count (quotient frame-size 8))
                           (frame-base (%ptr-add sp 8)))
                      (let slot-loop ((k 0) (mask bitmap))
                        (if (< k slot-count)
                            (begin
                              (if (or (and (< k 60) (= (modulo mask 2) 1))
                                      (>= k 60))
                                  (let* ((slot-addr (%ptr-add frame-base (* k 8)))
                                         (val (%raw-load slot-addr 0)))
                                    (if (gc-nursery-pointer? val)
                                        (%raw-store! slot-addr 0 (gc-promote-object val)))))
                              (slot-loop (+ k 1) (if (< k 60) (quotient mask 2) 0)))))
                      (walk-loop (%ptr-add frame-base frame-size)))
                    (walk-loop (%ptr-add sp 8))))))
        ;; --- Fallback Conservative Walk ---
        (let conserv-loop ((sp deepest-sp))
          (if (< sp bottom)
              (let ((val (%raw-load sp 0)))
                (if (gc-nursery-pointer? val)
                    (%raw-store! sp 0 (gc-promote-object val)))
                (conserv-loop (%ptr-add sp 8))))))))

;;; Scan Remembered Set (slots in mature objects pointing to nursery)
(define (gc-scan-remset!)
  (let ((remset (gc-remset-ptr))
        (count (gc-remset-count)))
    (if (and (> remset 0) (> count 0))
        (let loop ((i 0))
          (if (< i count)
              (let* ((slot-addr (%raw-load remset (* i 8)))
                     (val (%raw-load slot-addr 0)))
                (if (gc-nursery-pointer? val)
                    (%raw-store! slot-addr 0 (gc-promote-object val)))
                (loop (+ i 1))))))))

;;; Write Barrier: record a mature space slot that stores a nursery pointer
(define (gc-record-remset! slot-addr)
  (let ((remset (gc-remset-ptr))
        (count (gc-remset-count)))
    (if (and (> remset 0) (< count 4096))
        (begin
          (%raw-store! remset (* count 8) slot-addr)
          (%raw-store! (%get-gc-state-ptr) 80 (+ count 1))))))

;;; Perform Minor GC: promote live nursery objects to mature space, reset nursery pointer
(define (gc-minor-collect! current-rsp)
  (let ((scan-start (gc-mature-free))
        (deepest-sp (%get-rsp)))
    ;; 1. Scan execution stack using Exact GC Stackmaps
    (gc-scan-roots-generational! deepest-sp (gc-gen-bottom))
    ;; 2. Scan remembered set
    (gc-scan-remset!)
    ;; 3. Cheney scan mature space to transitively promote nursery objects
    (gc-minor-cheney-scan! scan-start)
    ;; 4. Reset nursery allocation bump pointer back to nursery-base (cost = 0!)
    (%set-heap-ptr! (gc-nursery-base))
    ;; 5. Reset remembered set
    (%raw-store! (%get-gc-state-ptr) 80 0)
    ;; 6. Increment minor collection count
    (%raw-store! (%get-gc-state-ptr) 56 (+ (gc-minor-count) 1))
    (gc-nursery-base)))

;;; Perform classic full dual-space garbage collection
(define (gc-collect! current-rsp)
  (if (= (gc-gen-mode) 1)
      (gc-minor-collect! current-rsp)
      (begin
        (set-gc-free! (gc-to))
        (let ((scan-start (gc-to))
              (deepest-sp (%get-rsp)))
          ;; 1. Scan execution stack using Exact GC Stackmaps
          (gc-scan-roots! deepest-sp (gc-bottom))
          ;; 2. Cheney breadth-first scan to transitively copy reachable subgraph
          (gc-cheney-scan! scan-start)
          ;; 3. Swap from-space and to-space
          (let ((new-heap-ptr (gc-free))
                (old-from (gc-from)))
            (set-gc-from! (gc-to))
            (set-gc-to! old-from)
            (set-gc-count! (+ (gc-count) 1))
            ;; Update runtime heap pointer register (%r12)
            (%set-heap-ptr! new-heap-ptr)
            new-heap-ptr)))))

;;; Automatic trigger check: collect if requested bytes exceed available space
(define (gc-maybe-collect! needed-bytes)
  (if (= (gc-gen-mode) 1)
      (let ((curr (%get-heap-ptr)))
        (if (> (%ptr-add curr needed-bytes) (%ptr-add (gc-nursery-base) (gc-nursery-size)))
            (gc-minor-collect! (%get-rsp))
            curr))
      (let ((curr (%get-heap-ptr)))
        (if (> (%ptr-add curr needed-bytes) (%ptr-add (gc-from) (gc-size)))
            (gc-collect! (%get-rsp))
            curr))))
