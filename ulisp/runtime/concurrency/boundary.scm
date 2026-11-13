;;; =======================================================================
;;; Synapse Concurrency Runtime: Host-Kernel Boundary Sanitizer (boundary.scm)
;;; Conforms to DSN-37 Section 8.1, 9.1 & Phase 4 Task 4.1 (Issue #641)
;;;
;;; Enforces Shared-Nothing memory isolation between Layer 1 (R7RS host GC heap)
;;; and Layer 2 (ASC task bump arena).
;;; Implements zero-copy immediate passing, deep-copy allocation into target arena,
;;; circular reference detection (CWE-674), resource limits (CWE-400), and
;;; pointer non-sharing audit predicate (shared-pointer?).
;;; =======================================================================

(define *boundary-max-depth* 1024)
(define *boundary-max-bytes* 1048576) ; 1MB limit for single boundary transfer
(define *pair-alloc-bytes* 16)        ; 16 bytes per pair (car + cdr)

;; -----------------------------------------------------------------------
;; 1. Immediate Value Predicate
;; -----------------------------------------------------------------------

(define (immediate-value? x)
  (or (number? x)
      (boolean? x)
      (char? x)
      (null? x)
      (symbol? x)))

;; -----------------------------------------------------------------------
;; 2. Cycle Detection & Helper Procedures
;; -----------------------------------------------------------------------

(define (%check-depth-and-cycle! val ancestors depth)
  (if (> depth *boundary-max-depth*)
      (error "boundary-sanitize: recursion depth exceeded maximum limit (CWE-674)" depth)
      (if (and (or (pair? val) (vector? val)) (memq val ancestors))
          (error "boundary-sanitize: circular reference detected (CWE-674)" 'circular-reference)
          #t)))

;; -----------------------------------------------------------------------
;; 3. Deep Copy to Task Arena (Host -> Kernel Transfer)
;; -----------------------------------------------------------------------

(define (%sanitize-to-arena-step val arena ancestors depth)
  (%check-depth-and-cycle! val ancestors depth)
  (cond
    ;; Immediate: zero-copy return
    ((immediate-value? val)
     val)

    ;; Vector: deep copy elements into a fresh vector and account memory
    ;; Note: vector? tested before pair? for robust tag disambiguation
    ((vector? val)
     (let* ((len (vector-length val))
            (alloc-sz (arena-align-up (+ (* len 8) 16) 8))
            (next-ancestors (cons val ancestors))
            (next-depth (+ depth 1)))
       (if (and arena (task-arena? arena))
           (arena-allocate! arena alloc-sz 8)
           #f)
       (let ((new-vec (make-vector len)))
         (let loop ((i 0))
           (if (< i len)
               (begin
                 (vector-set! new-vec i
                              (%sanitize-to-arena-step (vector-ref val i) arena next-ancestors next-depth))
                 (loop (+ i 1)))
               new-vec)))))

    ;; String: duplicate string and account memory
    ((string? val)
     (let* ((len (string-length val))
            (alloc-sz (arena-align-up (+ len 16) 8)))
       (if (and arena (task-arena? arena))
           (arena-allocate! arena alloc-sz 8)
           #f)
       (string-copy val)))

    ;; Bytevector: duplicate bytevector and account memory
    ((bytevector? val)
     (let* ((len (bytevector-length val))
            (alloc-sz (arena-align-up (+ len 16) 8)))
       (if (and arena (task-arena? arena))
           (arena-allocate! arena alloc-sz 8)
           #f)
       (bytevector-copy-range val 0 len)))

    ;; Pair: recursively copy and account memory from task arena
    ((pair? val)
     (let ((next-ancestors (cons val ancestors))
           (next-depth (+ depth 1)))
       ;; Account 16 bytes for pair in task arena if arena provided
       (if (and arena (task-arena? arena))
           (arena-allocate! arena *pair-alloc-bytes* 8)
           #f)
       (let ((new-car (%sanitize-to-arena-step (car val) arena next-ancestors next-depth))
             (new-cdr (%sanitize-to-arena-step (cdr val) arena next-ancestors next-depth)))
         (cons new-car new-cdr))))

    (else
     (error "boundary-sanitize: unsupported type across boundary (CWE-843)" val))))

(define (sanitize-to-arena val arena)
  (declare (no-safepoints))
  (if (and arena (not (task-arena? arena)))
      (error "sanitize-to-arena: expected <task-arena> or #f" arena)
      (%sanitize-to-arena-step val arena '() 0)))

;; -----------------------------------------------------------------------
;; 4. Deep Copy from Task Arena to Host Heap (Kernel -> Host Transfer)
;; -----------------------------------------------------------------------

(define (%sanitize-from-arena-step val ancestors depth)
  (%check-depth-and-cycle! val ancestors depth)
  (cond
    ;; Immediate: zero-copy
    ((immediate-value? val)
     val)

    ;; Vector: replicate into host GC heap
    ((vector? val)
     (let* ((len (vector-length val))
            (new-vec (make-vector len))
            (next-ancestors (cons val ancestors))
            (next-depth (+ depth 1)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (vector-set! new-vec i
                            (%sanitize-from-arena-step (vector-ref val i) next-ancestors next-depth))
               (loop (+ i 1)))
             new-vec))))

    ;; String
    ((string? val)
     (string-copy val))

    ;; Bytevector
    ((bytevector? val)
     (bytevector-copy-range val 0 (bytevector-length val)))

    ;; Pair: replicate into host GC heap
    ((pair? val)
     (let ((next-ancestors (cons val ancestors))
           (next-depth (+ depth 1)))
       (let ((new-car (%sanitize-from-arena-step (car val) next-ancestors next-depth))
             (new-cdr (%sanitize-from-arena-step (cdr val) next-ancestors next-depth)))
         (cons new-car new-cdr))))

    (else
     (error "sanitize-from-arena: unsupported type across boundary (CWE-843)" val))))

(define (sanitize-from-arena val)
  (declare (no-safepoints))
  (%sanitize-from-arena-step val '() 0))

;; -----------------------------------------------------------------------
;; 5. Pointer Sharing Audit Predicate (Shared-Nothing Verification)
;; -----------------------------------------------------------------------

(define (collect-all-pointers obj)
  (let loop ((val obj) (ptrs '()) (depth 0))
    (if (> depth *boundary-max-depth*)
        ptrs
        (cond
          ((immediate-value? val)
           ptrs)
          ((memq val ptrs)
           ptrs)
          ((vector? val)
           (let* ((p-acc (cons val ptrs))
                  (len (vector-length val)))
             (let inner ((i 0) (cur-ptrs p-acc))
               (if (< i len)
                   (inner (+ i 1) (loop (vector-ref val i) cur-ptrs (+ depth 1)))
                   cur-ptrs))))
          ((or (string? val) (bytevector? val))
           (cons val ptrs))
          ((pair? val)
           (let ((p-acc (cons val ptrs)))
             (loop (cdr val) (loop (car val) p-acc (+ depth 1)) (+ depth 1))))
          (else
           ptrs)))))

(define (shared-pointer? obj1 obj2)
  (declare (no-safepoints))
  (let ((ptrs1 (collect-all-pointers obj1))
        (ptrs2 (collect-all-pointers obj2)))
    (let loop ((ps ptrs1))
      (cond
        ((null? ps) #f)
        ((memq (car ps) ptrs2) #t)
        (else (loop (cdr ps)))))))
