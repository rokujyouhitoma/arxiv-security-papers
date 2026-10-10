;;; =======================================================================
;;; ULisp Standard Library: Self-Hosting Cheney's Copying Garbage Collector
;;; Conforms to DSN-33 Architecture Specification & Issue #501
;;; Implemented purely in Scheme with ZERO heap allocations during GC.
;;; =======================================================================

;; Static GC state accessors via zero-allocation %get-gc-state-ptr
;; Layout: [0:from, 8:to, 16:size, 24:bottom, 32:count, 40:free_ptr]
(define (gc-from) (%raw-load (%get-gc-state-ptr) 0))
(define (gc-to) (%raw-load (%get-gc-state-ptr) 8))
(define (gc-size) (%raw-load (%get-gc-state-ptr) 16))
(define (gc-bottom) (%raw-load (%get-gc-state-ptr) 24))
(define (gc-count) (%raw-load (%get-gc-state-ptr) 32))
(define (gc-free) (%raw-load (%get-gc-state-ptr) 40))

(define (set-gc-from! v) (%raw-store! (%get-gc-state-ptr) 0 v))
(define (set-gc-to! v) (%raw-store! (%get-gc-state-ptr) 8 v))
(define (set-gc-size! v) (%raw-store! (%get-gc-state-ptr) 16 v))
(define (set-gc-bottom! v) (%raw-store! (%get-gc-state-ptr) 24 v))
(define (set-gc-count! v) (%raw-store! (%get-gc-state-ptr) 32 v))
(define (set-gc-free! v) (%raw-store! (%get-gc-state-ptr) 40 v))

;;; Initialize the dual-space copying garbage collector
(define (gc-init! from-space to-space heap-size stack-bottom)
  (set-gc-from! from-space)
  (set-gc-to! to-space)
  (set-gc-size! heap-size)
  (set-gc-bottom! stack-bottom)
  (set-gc-count! 0)
  (set-gc-free! to-space)
  (%set-heap-ptr! from-space))

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
    ;; If forwarded, hdr has tag != 0 (it is a tagged pointer pointing into to-space)
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

;;; Perform full garbage collection: root scan -> Cheney scan -> space swap
(define (gc-collect! current-rsp)
  (set-gc-free! (gc-to))
  (let ((scan-start (gc-to))
        (deepest-sp (%get-rsp)))
    ;; 1. Scan execution stack from deepest-sp up to stack-bottom
    (let stack-loop ((sp deepest-sp))
      (if (< sp (gc-bottom))
          (let ((val (%raw-load sp 0)))
            (if (gc-heap-pointer? val)
                (%raw-store! sp 0 (gc-copy-object val)))
            (stack-loop (%ptr-add sp 8)))))
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
      new-heap-ptr)))

;;; Automatic trigger check: collect if requested bytes exceed available space
(define (gc-maybe-collect! needed-bytes)
  (let ((curr (%get-heap-ptr)))
    (if (> (%ptr-add curr needed-bytes) (%ptr-add (gc-from) (gc-size)))
        (gc-collect! (%get-rsp))
        curr)))
