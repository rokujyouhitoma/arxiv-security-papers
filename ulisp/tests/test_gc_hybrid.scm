;;; =======================================================================
;;; ULisp Test Suite: Hybrid Exact & Conservative Stack Scanning (Issue #568)
;;; =======================================================================

(define *test-hybrid-failures* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-hybrid-failures* 0 (+ (vector-ref *test-hybrid-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-equal actual expected msg)
  (if (not (or (eqv? actual expected)
               (and (string? actual) (string? expected) (string=? actual expected))))
      (begin
        (vector-set! *test-hybrid-failures* 0 (+ (vector-ref *test-hybrid-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(write-string "=== Running ULisp Issue #568 Hybrid Exact-Conservative Scanning Tests ===\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Test 1: Standard Exact Stackmap Root Scan & Nursery Object Promotion
;; -----------------------------------------------------------------------
(write-string "--- Test 1: Standard Exact Stackmap Scan & Promotion ---\n")
(flush-output-port)

(let ((p (cons 10 20))
      (v (vector 1 2 3 4 5))
      (s "hybrid-gc-string"))
  (gc-minor-collect! (%get-rsp))
  (assert-equal (car p) 10 "Promoted pair car preserved")
  (assert-equal (cdr p) 20 "Promoted pair cdr preserved")
  (assert-equal (vector-ref v 2) 3 "Promoted vector element preserved")
  (assert-equal s "hybrid-gc-string" "String literal preserved"))

;; -----------------------------------------------------------------------
;; Test 2: Unmapped Pointer Protection via Conservative Fallback (Nursery)
;; -----------------------------------------------------------------------
(write-string "--- Test 2: Unmapped Pointer Protection via Conservative Fallback ---\n")
(flush-output-port)

;; Simulate a slot in the current frame that is not tracked by the exact stackmap bitmap
;; (e.g. temporary register spill or raw slot).
(let* ((orig-rescued (gc-hybrid-rescued-count))
       (dummy-box (cons 0 0)))
  ;; Allocate a nursery pair
  (let ((untracked-pair (cons 777 888)))
    ;; Store the untracked pointer directly into a stack frame slot between RSP and bottom
    (let ((frame-slot (%ptr-add (%get-rsp) 16)))
      (%raw-store! frame-slot 0 untracked-pair)
      ;; Trigger minor collection - Pass 1 will not track this raw slot, Pass 2 will rescue it!
      (gc-minor-collect! (%get-rsp))
      (let ((rescued (%raw-load frame-slot 0)))
        (assert-true (> (gc-hybrid-rescued-count) orig-rescued)
                     "Conservative pass detected and rescued unmapped pointer")
        (assert-equal (car rescued) 777 "Rescued pair car intact (777)")
        (assert-equal (cdr rescued) 888 "Rescued pair cdr intact (888)")))))

;; -----------------------------------------------------------------------
;; Test 3: Multiple Unmapped Pointers and Tagged Pointer Validation
;; -----------------------------------------------------------------------
(write-string "--- Test 3: Multiple Unmapped Pointer Rescue ---\n")
(flush-output-port)

(let* ((p1 (cons 111 222))
       (p2 (cons 333 444))
       (v1 (vector 10 20 30))
       (slot1 (%ptr-add (%get-rsp) 24))
       (slot2 (%ptr-add (%get-rsp) 32))
       (slot3 (%ptr-add (%get-rsp) 40)))
  (%raw-store! slot1 0 p1)
  (%raw-store! slot2 0 p2)
  (%raw-store! slot3 0 v1)
  (gc-minor-collect! (%get-rsp))
  (let ((rp1 (%raw-load slot1 0))
        (rp2 (%raw-load slot2 0))
        (rv1 (%raw-load slot3 0)))
    (assert-equal (car rp1) 111 "Multiple unmapped: rp1 car matches")
    (assert-equal (cdr rp1) 222 "Multiple unmapped: rp1 cdr matches")
    (assert-equal (car rp2) 333 "Multiple unmapped: rp2 car matches")
    (assert-equal (cdr rp2) 444 "Multiple unmapped: rp2 cdr matches")
    (assert-equal (vector-ref rv1 1) 20 "Multiple unmapped: rv1 elem matches")))

;; -----------------------------------------------------------------------
;; Test 4: Deep Recursion with Active GC and Nested Stack Frames
;; -----------------------------------------------------------------------
(write-string "--- Test 4: Deep Recursion with Intermittent Minor GC ---\n")
(flush-output-port)

(define (recursive-alloc-sum depth acc)
  (if (<= depth 0)
      acc
      (let ((item (cons depth acc)))
        ;; Trigger GC periodically deep in stack
        (if (= (modulo depth 50) 0)
            (gc-minor-collect! (%get-rsp)))
        (recursive-alloc-sum (- depth 1) (+ (car item) acc)))))

(let ((res (recursive-alloc-sum 200 0)))
  (assert-true (> res 0) "Deep recursion completes without stack corruption"))

;; -----------------------------------------------------------------------
;; Test 5: Dual-Space Mode Hybrid Scanning
;; -----------------------------------------------------------------------
(write-string "--- Test 5: Dual-Space Mode Hybrid Scanning ---\n")
(flush-output-port)

(let* ((orig (%get-heap-ptr))
       (half 65536)
       (from orig)
       (to (+ orig half)))
  (gc-init! from to half (%get-rsp))
  (let ((lst (cons 1234 5678)))
    (let ((ds-slot (%ptr-add (%get-rsp) 16)))
      (%raw-store! ds-slot 0 lst)
      (gc-collect! (%get-rsp))
      (let ((res-lst (%raw-load ds-slot 0)))
        (assert-equal (car res-lst) 1234 "Dual-space unmapped car matches")
        (assert-equal (cdr res-lst) 5678 "Dual-space unmapped cdr matches")))))

;; -----------------------------------------------------------------------
;; Test 6: Debug Mode (DEBUG_GC=1) & Diagnostic Log Accessor Verification
;; -----------------------------------------------------------------------
(write-string "--- Test 6: Debug Mode and Accessor Verification ---\n")
(flush-output-port)

(let ((orig-dbg (gc-debug-mode?)))
  (set-gc-debug-mode! #t)
  (assert-true (gc-debug-mode?) "gc-debug-mode? is #t after setting")
  (set-gc-debug-mode! #f)
  (assert-true (not (gc-debug-mode?)) "gc-debug-mode? is #f after unsetting")
  (set-gc-debug-mode! orig-dbg))

;; -----------------------------------------------------------------------
;; Final Result
;; -----------------------------------------------------------------------
(let ((failures (vector-ref *test-hybrid-failures* 0)))
  (if (> failures 0)
      (begin
        (write-string "=== SOME HYBRID SCANNING TESTS FAILED! ===\n")
        (sys-exit 1))
      (begin
        (write-string "=== ALL Issue #568 Hybrid Scanning Tests PASSED! ===\n")
        (sys-exit 0))))
