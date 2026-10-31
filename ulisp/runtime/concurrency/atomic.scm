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
  (if (not (atomic-box? box))
      (error "atomic-ref: expected <atomic-box>" box)
      (%atomic-box-val box)))

(define (atomic-box-ref box)
  (if (not (atomic-box? box))
      (error "atomic-box-ref: expected <atomic-box>" box)
      (%atomic-box-val box)))

(define (atomic-set! box new-val)
  (if (not (atomic-box? box))
      (error "atomic-set!: expected <atomic-box>" box)
      (begin
        (%atomic-box-val-set! box new-val)
        (%memory-fence)
        new-val)))

(define (atomic-box-set! box new-val)
  (if (not (atomic-box? box))
      (error "atomic-box-set!: expected <atomic-box>" box)
      (begin
        (%atomic-box-val-set! box new-val)
        (%memory-fence)
        new-val)))

(define (atomic-cas! box expected new-val)
  (if (not (atomic-box? box))
      (error "atomic-cas!: expected <atomic-box>" box)
      (%atomic-cas! box expected new-val)))

;; -----------------------------------------------------------------------
;; 3. High-Level Lock-Free Derived Operations
;; -----------------------------------------------------------------------

(define (atomic-swap! box new-val)
  (if (not (atomic-box? box))
      (error "atomic-swap!: expected <atomic-box>" box)
      (let retry ()
        (let ((old (%atomic-box-val box)))
          (if (%atomic-cas! box old new-val)
              old
              (retry))))))

(define (atomic-fetch-add! box delta)
  (if (not (atomic-box? box))
      (error "atomic-fetch-add!: expected <atomic-box>" box)
      (if (not (integer? delta))
          (error "atomic-fetch-add!: delta must be an integer" delta)
          (let retry ()
            (let ((old (%atomic-box-val box)))
              (if (not (integer? old))
                  (error "atomic-fetch-add!: current box value is not an integer" old)
                  (let ((next (+ old delta)))
                    (if (%atomic-cas! box old next)
                        old
                        (retry)))))))))

(define (atomic-update! box proc)
  (if (not (atomic-box? box))
      (error "atomic-update!: expected <atomic-box>" box)
      (if (not (procedure? proc))
          (error "atomic-update!: expected procedure" proc)
          (let retry ()
            (let* ((old (%atomic-box-val box))
                   (next (proc old)))
              (if (%atomic-cas! box old next)
                  next
                  (retry)))))))

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

