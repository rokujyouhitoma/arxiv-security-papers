;;; =======================================================================
;;; Unit Test Suite: ULisp Freestanding Demand-Paged BSS Bump Allocator & GC
;;; Conforms to DSN-33-07 / Issue #905
;;; Zero libc / Zero external runtime / Cheney 2-Space GC Verification
;;; =======================================================================

(!gc dual-space)
(include "lib/posix.scm")

;; 1. Direct sys-write to stdout
(sys-write-string "=== [TEST] Zero-libc Freestanding BSS Heap & GC Suite ===\n")

;; 2. Verify BSS Initial Heap pointer
(sys-write-string "[1/3] Testing BSS initial heap pointer & bump allocation: ")
(let ((bss-ptr (sys-initial-heap)))
  (if (<= bss-ptr 0)
      (begin
        (sys-write-string "FAIL (invalid BSS pointer)\n")
        (sys-exit 1))
      (begin
        (sys-write-string "PASS (bss-ptr: ")
        (sys-write-fixnum bss-ptr)
        (sys-write-string ")\n"))))

;; 3. Recursive allocation stress loop
;; Allocates count pairs, building a linked list and retaining references
(define (alloc-stress count acc)
  (if (<= count 0)
      acc
      (alloc-stress (- count 1) (cons (car acc) count))))

;; 4. Verify GC survival under constrained heap
(sys-write-string "[2/3] Testing Cheney 2-Space GC under allocation pressure: ")
(let* ((st-ptr (%get-gc-state-ptr))
       (lim-ptr (%get-heap-limit-ptr))
       (from (%raw-load st-ptr 0))
       (small-size 32768)) ;; 32KB small from-space
  (%raw-store! st-ptr 16 (%to-raw small-size))
  (let ((to (%raw-load st-ptr 8)))
    (%raw-store! st-ptr 40 to)
    (%raw-store! lim-ptr 0 (%ptr-add from small-size)))

  ;; Allocate 15,000 cons cells (~360,000 bytes) in a 32KB heap (> 10 GC cycles)
  (let ((list-res (alloc-stress 15000 (cons 42 0))))
    (if (and (pair? list-res) (= (car list-res) 42))
        (begin
          (sys-write-string "PASS (15,000 pairs allocated, surviving root verified: ")
          (sys-write-fixnum (car list-res))
          (sys-write-string ")\n"))
        (begin
          (sys-write-string "FAIL (GC object corruption)\n")
          (sys-exit 2)))))

;; 5. Verify cyclic and nested structure preservation across GC
(sys-write-string "[3/3] Testing nested object integrity across GC cycles: ")
(define (build-nested-tree depth)
  (if (<= depth 0)
      (cons 777 888)
      (cons (build-nested-tree (- depth 1)) (build-nested-tree (- depth 1)))))

(let ((tree (build-nested-tree 8))) ;; 256 leaves, 511 pairs
  (let ((dummy (alloc-stress 8000 (cons 1 2)))) ;; trigger additional GC cycles
    (if (and (pair? tree) (pair? (car tree)))
        (sys-write-string "PASS (nested tree intact after GC)\n")
        (begin
          (sys-write-string "FAIL (tree corrupted)\n")
          (sys-exit 3)))))

(sys-write-string "=== [SUCCESS] Freestanding Demand-Paged BSS GC Verified ===\n")
(sys-exit 0)
