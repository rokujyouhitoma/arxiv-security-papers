;;; =======================================================================
;;; ULisp Runtime Concurrency: Low-Level Atomic Primitives (atomic.scm)
;;; Conforms to DSN-37 Section 6 & Section 14.2 (Phase 0 Task 0.2), Issue #631
;;;
;;; Provides hardware-backed lock-free Compare-And-Swap (LOCK CMPXCHG)
;;; and memory barrier (MFENCE) primitives for <atomic-box> and ABA-safe
;;; <atomic-stamped-box> without OS mutex locks.
;;; =======================================================================

;; -----------------------------------------------------------------------
;; 1. Hardware Memory Barrier
;; -----------------------------------------------------------------------

(define (memory-fence)
  (%memory-fence))

;; -----------------------------------------------------------------------
;; 2. <atomic-box> Record Type & Core Primitives (DSN-37 Section 6.1)
;; -----------------------------------------------------------------------
;; Memory Layout (Pass 025 expand-define-record-type):
;;   Slot 0 [box + 3]  : '%%record-type-<atomic-box>
;;   Slot 1 [box + 11] : val (mutated atomically via LOCK CMPXCHG)

(define-record-type <atomic-box>
  (%make-atomic-box val)
  atomic-box?
  (val %atomic-box-val %atomic-box-val-set!))

(define (make-atomic-box initial-val)
  (let ((box (%make-atomic-box initial-val)))
    (%memory-fence)
    box))

(define (atomic-ref box)
  (cond
    ((atomic-box? box) (%atomic-box-val box))
    ((padded-atomic-box? box) (%padded-atomic-box-val box))
    (else (error "atomic-ref: expected <atomic-box> or <padded-atomic-box>" box))))

(define (atomic-box-ref box)
  (atomic-ref box))

(define (atomic-set! box new-val)
  (cond
    ((atomic-box? box)
     (%atomic-box-val-set! box new-val)
     (%memory-fence)
     new-val)
    ((padded-atomic-box? box)
     (%padded-atomic-box-val-set! box new-val)
     (%memory-fence)
     new-val)
    (else (error "atomic-set!: expected <atomic-box> or <padded-atomic-box>" box))))

(define (atomic-box-set! box new-val)
  (atomic-set! box new-val))

(define (atomic-cas! box expected new-val)
  (cond
    ((or (atomic-box? box) (padded-atomic-box? box))
     (%atomic-cas! box expected new-val))
    (else (error "atomic-cas!: expected <atomic-box> or <padded-atomic-box>" box))))

;; -----------------------------------------------------------------------
;; 2b. Cache-Line Padded Atomic Box (<padded-atomic-box>) (Issue #680)
;; -----------------------------------------------------------------------
;; Guarantees at least 64-byte physical memory footprint (72 bytes on AMD64)
;; to eliminate cache-line bouncing (False Sharing) between concurrent cores.
;; Slot 1 holds `val`, matching the exact offset of <atomic-box> so native
;; %atomic-cas! can operate directly without translation.

(define-record-type <padded-atomic-box>
  (%make-padded-atomic-box val _p1 _p2 _p3 _p4 _p5 _p6 _p7)
  padded-atomic-box?
  (val %padded-atomic-box-val %padded-atomic-box-val-set!))

(define (make-padded-atomic-box initial-val)
  (let ((box (%make-padded-atomic-box initial-val 0 0 0 0 0 0 0)))
    (%memory-fence)
    box))

(define (padded-atomic-ref box)
  (if (not (padded-atomic-box? box))
      (error "padded-atomic-ref: expected <padded-atomic-box>" box)
      (%padded-atomic-box-val box)))

(define (padded-atomic-set! box new-val)
  (if (not (padded-atomic-box? box))
      (error "padded-atomic-set!: expected <padded-atomic-box>" box)
      (begin
        (%padded-atomic-box-val-set! box new-val)
        (%memory-fence)
        new-val)))

(define (padded-atomic-cas! box expected new-val)
  (if (not (padded-atomic-box? box))
      (error "padded-atomic-cas!: expected <padded-atomic-box>" box)
      (%atomic-cas! box expected new-val)))

(define (padded-atomic-swap! box new-val)
  (if (not (padded-atomic-box? box))
      (error "padded-atomic-swap!: expected <padded-atomic-box>" box)
      (let retry ()
        (let ((old (%padded-atomic-box-val box)))
          (if (%atomic-cas! box old new-val)
              old
              (retry))))))

(define (padded-atomic-fetch-add! box delta)
  (if (not (padded-atomic-box? box))
      (error "padded-atomic-fetch-add!: expected <padded-atomic-box>" box)
      (if (not (integer? delta))
          (error "padded-atomic-fetch-add!: delta must be an integer" delta)
          (let retry ()
            (let ((old (%padded-atomic-box-val box)))
              (if (not (integer? old))
                  (error "padded-atomic-fetch-add!: current box value is not an integer" old)
                  (let ((next (+ old delta)))
                    (if (%atomic-cas! box old next)
                        old
                        (retry)))))))))

;; -----------------------------------------------------------------------
;; 3. High-Level Lock-Free Derived Operations
;; -----------------------------------------------------------------------

(define (atomic-swap! box new-val)
  (cond
    ((atomic-box? box)
     (let retry ()
       (let ((old (%atomic-box-val box)))
         (if (%atomic-cas! box old new-val)
             old
             (retry)))))
    ((padded-atomic-box? box)
     (padded-atomic-swap! box new-val))
    (else (error "atomic-swap!: expected <atomic-box> or <padded-atomic-box>" box))))

(define (atomic-fetch-add! box delta)
  (cond
    ((atomic-box? box)
     (if (not (integer? delta))
         (error "atomic-fetch-add!: delta must be an integer" delta)
         (let retry ()
           (let ((old (%atomic-box-val box)))
             (if (not (integer? old))
                 (error "atomic-fetch-add!: current box value is not an integer" old)
                 (let ((next (+ old delta)))
                   (if (%atomic-cas! box old next)
                       old
                       (retry))))))))
    ((padded-atomic-box? box)
     (padded-atomic-fetch-add! box delta))
    (else (error "atomic-fetch-add!: expected <atomic-box> or <padded-atomic-box>" box))))

(define (atomic-update! box proc)
  (cond
    ((atomic-box? box)
     (if (not (procedure? proc))
         (error "atomic-update!: expected procedure" proc)
         (let retry ()
           (let* ((old (%atomic-box-val box))
                  (next (proc old)))
             (if (%atomic-cas! box old next)
                 next
                 (retry))))))
    ((padded-atomic-box? box)
     (if (not (procedure? proc))
         (error "atomic-update!: expected procedure" proc)
         (let retry ()
           (let* ((old (%padded-atomic-box-val box))
                  (next (proc old)))
             (if (%atomic-cas! box old next)
                 next
                 (retry))))))
    (else (error "atomic-update!: expected <atomic-box> or <padded-atomic-box>" box))))

;; -----------------------------------------------------------------------
;; 4. ABA-Safe Version-Stamped Atomic Box (<atomic-stamped-box>)
;; -----------------------------------------------------------------------
;; Mitigates CWE-416 / ABA Problem in lock-free stacks and queues by pairing
;; each reference with a monotonically increasing integer generation stamp.

(define-record-type <atomic-stamped-box>
  (%make-atomic-stamped-box cell)
  atomic-stamped-box?
  (cell %atomic-stamped-cell))

(define make-atomic-stamped-box
  (case-lambda
    ((initial-val)
     (%make-atomic-stamped-box (make-atomic-box (cons initial-val 0))))
    ((initial-val initial-stamp)
     (if (not (integer? initial-stamp))
         (error "make-atomic-stamped-box: initial-stamp must be an integer" initial-stamp)
         (%make-atomic-stamped-box (make-atomic-box (cons initial-val initial-stamp)))))))

(define (atomic-stamped-ref sbox)
  (if (not (atomic-stamped-box? sbox))
      (error "atomic-stamped-ref: expected <atomic-stamped-box>" sbox)
      (%atomic-box-val (%atomic-stamped-cell sbox))))

(define (atomic-stamped-val sbox)
  (if (not (atomic-stamped-box? sbox))
      (error "atomic-stamped-val: expected <atomic-stamped-box>" sbox)
      (car (%atomic-box-val (%atomic-stamped-cell sbox)))))

(define (atomic-stamped-stamp sbox)
  (if (not (atomic-stamped-box? sbox))
      (error "atomic-stamped-stamp: expected <atomic-stamped-box>" sbox)
      (cdr (%atomic-box-val (%atomic-stamped-cell sbox)))))

(define (atomic-stamped-set! sbox new-val new-stamp)
  (if (not (atomic-stamped-box? sbox))
      (error "atomic-stamped-set!: expected <atomic-stamped-box>" sbox)
      (if (not (integer? new-stamp))
          (error "atomic-stamped-set!: new-stamp must be an integer" new-stamp)
          (let ((pair (cons new-val new-stamp)))
            (atomic-set! (%atomic-stamped-cell sbox) pair)
            pair))))

(define (atomic-stamped-cas! sbox expected-val new-val expected-stamp new-stamp)
  (if (not (atomic-stamped-box? sbox))
      (error "atomic-stamped-cas!: expected <atomic-stamped-box>" sbox)
      (if (or (not (integer? expected-stamp)) (not (integer? new-stamp)))
          (error "atomic-stamped-cas!: stamps must be integers" (cons expected-stamp new-stamp))
          (let* ((cell (%atomic-stamped-cell sbox))
                 (cur (%atomic-box-val cell)))
            (if (and (eq? (car cur) expected-val)
                     (= (cdr cur) expected-stamp))
                (%atomic-cas! cell cur (cons new-val new-stamp))
                #f)))))

