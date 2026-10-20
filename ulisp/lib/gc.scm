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
(define (gc-nursery-size) (%to-fixnum (%raw-load (%get-gc-state-ptr) 8)))
(define (gc-mature-from)  (%raw-load (%get-gc-state-ptr) 16))
(define (gc-mature-to)    (%raw-load (%get-gc-state-ptr) 24))
(define (gc-mature-size)  (%to-fixnum (%raw-load (%get-gc-state-ptr) 32)))
(define (gc-mature-free)  (%raw-load (%get-gc-state-ptr) 40))
(define (gc-gen-bottom)   (%raw-load (%get-gc-state-ptr) 48))
(define (gc-minor-count)  (%to-fixnum (%raw-load (%get-gc-state-ptr) 56)))
(define (gc-major-count)  (%to-fixnum (%raw-load (%get-gc-state-ptr) 64)))
(define (gc-remset-ptr)   (%raw-load (%get-gc-state-ptr) 72))
(define (gc-remset-count) (%to-fixnum (%raw-load (%get-gc-state-ptr) 80)))
(define (gc-gen-mode)     (%to-fixnum (%raw-load (%get-gc-state-ptr) 88)))
(define (gc-max-size)     (%to-fixnum (%raw-load (%get-gc-state-ptr) 96)))
(define (gc-growth-count) (%to-fixnum (%raw-load (%get-gc-state-ptr) 104)))
(define (gc-profile-id)   (%to-fixnum (%raw-load (%get-gc-state-ptr) 112)))

;; Hybrid Exact-Conservative Scanning State (Issue #568)
;; [120]: bit 0 = debug_gc mode, bits 1..63 = rescued unmapped pointers count
(define (gc-debug-mode?)
  (= (bitwise-and (%to-fixnum (%raw-load (%get-gc-state-ptr) 120)) 1) 1))

(define (set-gc-debug-mode! v)
  (let ((cur (%to-fixnum (%raw-load (%get-gc-state-ptr) 120))))
    (%raw-store! (%get-gc-state-ptr) 120
                 (%to-raw (if v (bitwise-ior cur 1) (bitwise-and cur -2))))))

(define (gc-hybrid-rescued-count)
  (quotient (%to-fixnum (%raw-load (%get-gc-state-ptr) 120)) 2))

(define (set-gc-hybrid-rescued-count! cnt)
  (let ((dbg (if (gc-debug-mode?) 1 0)))
    (%raw-store! (%get-gc-state-ptr) 120
                 (%to-raw (+ (* cnt 2) dbg)))))

(define (gc-inc-hybrid-rescued!)
  (let ((cur (%to-fixnum (%raw-load (%get-gc-state-ptr) 120))))
    (%raw-store! (%get-gc-state-ptr) 120 (%to-raw (+ cur 2)))))

(define (gc-log-unmapped-pointer! sp val)
  (gc-inc-hybrid-rescued!)
  (if (gc-debug-mode?)
      (begin
        (sys-write-string "[DEBUG_GC] Hybrid scanner rescued unmapped pointer at SP=")
        (sys-write-fixnum (%to-fixnum sp))
        (sys-write-string " val=")
        (sys-write-fixnum (%to-fixnum val))
        (sys-write-char #\newline)
        (sys-flush))))

(define (set-gc-mature-from! v) (%raw-store! (%get-gc-state-ptr) 16 v))
(define (set-gc-mature-size! v) (%raw-store! (%get-gc-state-ptr) 32 (%to-raw v)))
(define (set-gc-mature-free! v) (%raw-store! (%get-gc-state-ptr) 40 v))
(define (set-gc-max-size! v)    (%raw-store! (%get-gc-state-ptr) 96 (%to-raw v)))
(define (set-gc-growth-count! v)(%raw-store! (%get-gc-state-ptr) 104 (%to-raw v)))
(define (set-gc-profile-id! v)  (%raw-store! (%get-gc-state-ptr) 112 (%to-raw v)))

;;; Query current GC execution profile (Issue #567)
;;; Returns symbol: 'standard, 'compiler, 'server, 'none, or 'dual-space
(define (gc-current-profile)
  (let ((id (gc-profile-id)))
    (cond
      ((= id 1) 'compiler)
      ((= id 2) 'server)
      ((= id 3) 'none)
      ((= id 4) 'dual-space)
      (else 'standard))))

;;; Initialize classic dual-space copying garbage collector
(define (gc-init! from-space to-space heap-size stack-bottom)
  (%raw-store! (%get-gc-state-ptr) 88 0) ; mode 0
  (set-gc-from! from-space)
  (set-gc-to! to-space)
  (set-gc-size! heap-size)
  (set-gc-bottom! stack-bottom)
  (set-gc-count! 0)
  (set-gc-free! to-space)
  (set-gc-profile-id! 4)                ; profile 4: dual-space
  (%set-heap-ptr! from-space))

;;; Initialize Nursery & Generational Copying Garbage Collector
(define (gc-init-generational! nursery-base nursery-size mature-from mature-to mature-size stack-bottom remset-ptr)
  (%raw-store! (%get-gc-state-ptr) 0 nursery-base)
  (%raw-store! (%get-gc-state-ptr) 8 (%to-raw nursery-size))
  (%raw-store! (%get-gc-state-ptr) 16 mature-from)
  (%raw-store! (%get-gc-state-ptr) 24 mature-to)
  (%raw-store! (%get-gc-state-ptr) 32 (%to-raw mature-size))
  (%raw-store! (%get-gc-state-ptr) 40 mature-from)   ; mature-free starts at mature-from
  (%raw-store! (%get-gc-state-ptr) 48 stack-bottom)
  (%raw-store! (%get-gc-state-ptr) 56 0)             ; minor count = 0
  (%raw-store! (%get-gc-state-ptr) 64 0)             ; major count = 0
  (%raw-store! (%get-gc-state-ptr) 72 remset-ptr)
  (%raw-store! (%get-gc-state-ptr) 80 0)             ; remset count = 0
  (%raw-store! (%get-gc-state-ptr) 88 1)             ; generational mode = 1
  (%raw-store! (%get-gc-state-ptr) 96 (%to-raw (* mature-size 32))) ; default max mature size: 32x
  (%raw-store! (%get-gc-state-ptr) 104 0)            ; mature growth count = 0
  (set-gc-profile-id! 0)                             ; profile 0: standard default
  (%set-heap-ptr! nursery-base))

;;; Initialize Generational GC with named execution profile (Issue #567)
;;; Supported profiles: 'standard, 'compiler, 'server
(define (gc-init-profile! profile)
  (let ((stack-bottom (gc-bottom)))
    (cond
      ((eq? profile 'compiler)
       ;; Compiler profile: 256MB Nursery, 256MB Mature, 4GB Max (Sub-second AST compilation)
       (let* ((n-size 268435456)
              (m-size 268435456)
              (max-size 4294967296)
              (total (+ n-size (+ (* m-size 2) 65536)))
              (base (sys-mmap total))
              (m-from (%ptr-add base n-size))
              (m-to (%ptr-add m-from m-size))
              (remset (%ptr-add m-to m-size)))
         (gc-init-generational! base n-size m-from m-to m-size stack-bottom remset)
         (set-gc-max-size! max-size)
         (set-gc-profile-id! 1)))
      ((eq? profile 'server)
       ;; Server profile: 16MB Nursery, 256MB Mature, 4GB Max (Long-lived server/daemon)
       (let* ((n-size 16777216)
              (m-size 268435456)
              (max-size 4294967296)
              (total (+ n-size (+ (* m-size 2) 65536)))
              (base (sys-mmap total))
              (m-from (%ptr-add base n-size))
              (m-to (%ptr-add m-from m-size))
              (remset (%ptr-add m-to m-size)))
         (gc-init-generational! base n-size m-from m-to m-size stack-bottom remset)
         (set-gc-max-size! max-size)
         (set-gc-profile-id! 2)))
      (else
       ;; Standard profile: 4MB Nursery, 64MB Mature, 1GB Max (Low memory footprint script)
       (let* ((n-size 4194304)
              (m-size 67108864)
              (max-size 1073741824)
              (total (+ n-size (+ (* m-size 2) 32768)))
              (base (sys-mmap total))
              (m-from (%ptr-add base n-size))
              (m-to (%ptr-add m-from m-size))
              (remset (%ptr-add m-to m-size)))
         (gc-init-generational! base n-size m-from m-to m-size stack-bottom remset)
         (set-gc-max-size! max-size)
         (set-gc-profile-id! 0))))))

;;; Predicate: is value a pointer pointing into nursery?
(define (gc-nursery-pointer? val)
  (let ((tag (%ptr-tag val)))
    (if (or (= tag 1) (= tag 3) (= tag 5) (= tag 7))
        (let ((addr (%ptr-untag val)))
          (and (>= addr (gc-nursery-base))
               (< addr (%ptr-add (gc-nursery-base) (gc-nursery-size)))))
        #f)))

;;; Predicate: is the value a heap pointer pointing into current from-space?
(define (gc-heap-pointer? val)
  (let ((tag (%ptr-tag val)))
    (if (or (= tag 1) (= tag 3) (= tag 5) (= tag 7))
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
    ;; Check if already forwarded in current GC cycle (must be allocated within current [gc-to, gc-free))
    (if (and (not (= (%ptr-tag hdr) 0))
             (let ((addr (%ptr-untag hdr)))
               (and (>= addr (gc-to))
                    (< addr (gc-free)))))
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

;;; -----------------------------------------------------------------------
;;; Dynamic Mature Heap Expansion & Relocation (Issue #566)
;;; -----------------------------------------------------------------------

;; Predicate: check if pointer was pointing to old mature space [old-from, old-from + old-size)
(define (gc-in-old-mature? ptr old-from old-size)
  (let ((tag (%ptr-tag ptr)))
    (if (or (= tag 1) (= tag 3) (= tag 5) (= tag 7))
        (let ((addr (%ptr-untag ptr)))
          (and (>= addr old-from)
               (< addr (%ptr-add old-from old-size))))
        #f)))

;; Adjust pointer by diff if within old mature space
(define (gc-relocate-ptr ptr old-from old-size diff)
  (if (gc-in-old-mature? ptr old-from old-size)
      (%ptr-add ptr (%to-fixnum diff))
      ptr))

;; Relocate internal object pointers after mremap move
(define (gc-relocate-mature-objects! new-from new-free old-from old-size diff)
  (let scan-loop ((scan new-from))
    (if (< scan new-free)
        (let* ((hdr (%raw-load scan 0))
               (type (bitwise-and hdr 255))
               (payload-bytes (quotient hdr 65536))
               (payload-addr (%ptr-add scan 8)))
          (cond
            ;; Type 1: Pair
            ((= type 1)
             (let ((c1 (%raw-load payload-addr 0))
                   (c2 (%raw-load payload-addr 8)))
               (%raw-store! payload-addr 0 (gc-relocate-ptr c1 old-from old-size diff))
               (%raw-store! payload-addr 8 (gc-relocate-ptr c2 old-from old-size diff))))
            ;; Type 2: Closure
            ((= type 2)
             (let ((num-fields (bitwise-and (quotient hdr 256) 255)))
               (let f-loop ((i 1))
                 (if (< i num-fields)
                     (let* ((slot-addr (%ptr-add payload-addr (* i 8)))
                            (v (%raw-load slot-addr 0)))
                       (%raw-store! slot-addr 0 (gc-relocate-ptr v old-from old-size diff))
                       (f-loop (+ i 1)))))))
            ;; Type 5: Vector
            ((= type 5)
             (let ((vec-len (quotient (%raw-load payload-addr 0) 4)))
               (let vec-loop ((i 0))
                 (if (< i vec-len)
                     (let* ((slot-addr (%ptr-add payload-addr (* (+ i 1) 8)))
                            (v (%raw-load slot-addr 0)))
                       (%raw-store! slot-addr 0 (gc-relocate-ptr v old-from old-size diff))
                       (vec-loop (+ i 1)))))))
            (else #t))
          (scan-loop (%ptr-add scan (+ payload-bytes 8)))))))

;; Relocate stack roots after mremap move
(define (gc-relocate-stack! deepest-sp bottom old-from old-size diff)
  (let loop ((sp deepest-sp))
    (if (< sp bottom)
        (let ((val (%raw-load sp 0)))
          (if (gc-in-old-mature? val old-from old-size)
              (%raw-store! sp 0 (gc-relocate-ptr val old-from old-size diff)))
          (loop (%ptr-add sp 8))))))

;; Relocate remembered set pointers after mremap move
(define (gc-relocate-remset! old-from old-size diff)
  (let ((remset (gc-remset-ptr))
        (count (gc-remset-count)))
    (if (and (> remset 0) (> count 0))
        (let loop ((i 0))
          (if (< i count)
              (let ((slot-addr (%raw-load remset (* i 8))))
                (if (and (>= slot-addr old-from) (< slot-addr (%ptr-add old-from old-size)))
                    (%raw-store! remset (* i 8) (+ slot-addr diff)))
                (loop (+ i 1))))))))

;; Mature space usage & available capacity (all in Scheme fixnum bytes)
(define (gc-mature-used)
  (%to-fixnum (- (gc-mature-free) (gc-mature-from))))

(define (gc-mature-available)
  (- (gc-mature-size) (gc-mature-used)))

;; Expand mature space using Linux sys_mremap (Syscall 25)
(define (gc-grow-mature! deepest-sp)
  (let* ((old-from (gc-mature-from))
         (old-size (gc-mature-size))
         (old-free (gc-mature-free))
         (max-size (gc-max-size))
         (target-size (* old-size 2))
         (new-size (if (and (> max-size 0) (> target-size max-size))
                       max-size
                       target-size)))
    (if (> new-size old-size)
        ;; First try in-place expansion without moving (flags = 0)
        (let ((in-place-ret (%raw-syscall (%to-raw 25) old-from (%to-raw old-size) (%to-raw new-size) 0 0 0)))
          (if (and (> in-place-ret 0) (= in-place-ret old-from))
              ;; In-place expansion succeeded!
              (begin
                (set-gc-mature-size! new-size)
                (set-gc-growth-count! (+ (gc-growth-count) 1))
                #t)
              ;; If mremap flags=0 is rejected (e.g. within pre-reserved contiguous VMA block),
              ;; check if we are within pre-reserved max-size boundary:
              (if (and (> max-size 0) (<= new-size max-size))
                  (begin
                    (set-gc-mature-size! new-size)
                    (set-gc-growth-count! (+ (gc-growth-count) 1))
                    #t)
                  ;; Otherwise, try MREMAP_MAYMOVE = 1 (flags = 1)
                  (let ((move-ret (%raw-syscall (%to-raw 25) old-from (%to-raw old-size) (%to-raw new-size) (%to-raw 1) 0 0)))
                    (if (or (<= move-ret 0) (< move-ret -4096))
                        ;; OS limit reached (mremap error)
                        #f
                        (begin
                          (set-gc-mature-size! new-size)
                          (set-gc-growth-count! (+ (gc-growth-count) 1))
                          (if (not (= move-ret old-from))
                              (let* ((diff (- move-ret old-from))
                                     (new-from move-ret)
                                     (new-free (+ old-free diff)))
                                (set-gc-mature-from! new-from)
                                (set-gc-mature-free! new-free)
                                (gc-relocate-mature-objects! new-from new-free old-from old-size diff)
                                (gc-relocate-stack! deepest-sp (gc-gen-bottom) old-from old-size diff)
                                (gc-relocate-remset! old-from old-size diff)))
                          #t))))))
        #f)))

;; Check mature space usage and grow if occupancy > 70%
(define (gc-check-mature-growth! deepest-sp)
  (if (> (* (gc-mature-used) 10) (* (gc-mature-size) 7))
      (gc-grow-mature! deepest-sp)
      #f))

;; Ensure mature space has capacity for at least needed-bytes
(define (gc-ensure-mature-capacity! needed-bytes deepest-sp)
  (if (< (gc-mature-available) needed-bytes)
      (gc-grow-mature! deepest-sp)
      #t))

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
        (let* ((type (bitwise-and hdr 255))
               (payload-bytes (quotient hdr 65536))
               (total-bytes (+ payload-bytes 8)))
          (gc-ensure-mature-capacity! total-bytes (%get-rsp))
          (let* ((m-free (gc-mature-free))
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
            new-val)))))

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
            ;; Type 5: Vector (slot 0 is length, slots 1..len are Scheme values)
            ((= type 5)
             (let ((vec-len (quotient (%raw-load payload-addr 0) 4)))
               (let vec-loop ((i 0))
                 (if (< i vec-len)
                     (let ((slot-addr (%ptr-add payload-addr (* (+ i 1) 8))))
                       (%raw-store! slot-addr 0 (gc-copy-if-heap (%raw-load slot-addr 0)))
                       (vec-loop (+ i 1)))))))
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
            ;; Type 5: Vector
            ((= type 5)
             (let ((vec-len (quotient (%raw-load payload-addr 0) 4)))
               (let vec-loop ((i 0))
                 (if (< i vec-len)
                     (let* ((slot-addr (%ptr-add payload-addr (* (+ i 1) 8)))
                            (v (%raw-load slot-addr 0)))
                       (if (gc-nursery-pointer? v)
                           (%raw-store! slot-addr 0 (gc-promote-object v)))
                       (vec-loop (+ i 1)))))))
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

;;; Hybrid Exact-Conservative GC Root Scanner (Dual-Space) (Issue #568)
(define (gc-scan-roots! deepest-sp bottom)
  (let* ((tbl (%get-stackmap-table))
         (tbl-count (%to-fixnum (%raw-load tbl 0))))
    ;; --- Pass 1: Exact Stackmap Primary Scan ---
    (if (> tbl-count 0)
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
                    (walk-loop (%ptr-add sp 8)))))))
    ;; --- Pass 2: Conservative Fallback Secondary Scan ---
    (let conserv-loop ((sp deepest-sp))
      (if (< sp bottom)
          (let ((val (%raw-load sp 0)))
            (if (gc-heap-pointer? val)
                (begin
                  (if (> tbl-count 0)
                      (gc-log-unmapped-pointer! sp val))
                  (%raw-store! sp 0 (gc-copy-object val))))
            (conserv-loop (%ptr-add sp 8)))))))

;;; Hybrid Exact-Conservative GC Root Scanner for Generational Nursery (Minor GC) (Issue #568)
(define (gc-scan-roots-generational! deepest-sp bottom)
  (let* ((tbl (%get-stackmap-table))
         (tbl-count (%to-fixnum (%raw-load tbl 0))))
    ;; --- Pass 1: Exact Stackmap Primary Scan ---
    (if (> tbl-count 0)
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
                    (walk-loop (%ptr-add sp 8)))))))
    ;; --- Pass 2: Conservative Fallback Secondary Scan ---
    (let conserv-loop ((sp deepest-sp))
      (if (< sp bottom)
          (let ((val (%raw-load sp 0)))
            (if (gc-nursery-pointer? val)
                (begin
                  (if (> tbl-count 0)
                      (gc-log-unmapped-pointer! sp val))
                  (%raw-store! sp 0 (gc-promote-object val))))
            (conserv-loop (%ptr-add sp 8)))))))

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
    ;; 4. Check mature space occupancy & trigger dynamic growth if > 70% (Issue #566)
    (gc-check-mature-growth! deepest-sp)
    ;; 5. Reset nursery allocation bump pointer back to nursery-base (cost = 0!)
    (%set-heap-ptr! (gc-nursery-base))
    ;; 6. Reset remembered set
    (%raw-store! (%get-gc-state-ptr) 80 0)
    ;; 7. Increment minor collection count
    (%raw-store! (%get-gc-state-ptr) 56 (%to-raw (+ (gc-minor-count) 1)))
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
