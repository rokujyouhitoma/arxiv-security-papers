;;; =======================================================================
;;; ULisp Test Suite: Generational GC Dynamic Heap Growth Policy & mremap (Issue #566)
;;; =======================================================================

(define *test-gc-failures* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-gc-failures* 0 (+ (vector-ref *test-gc-failures* 0) 1))
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
        (vector-set! *test-gc-failures* 0 (+ (vector-ref *test-gc-failures* 0) 1))
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

(write-string "=== Running ULisp Issue #566 Dynamic Heap Growth & mremap Tests ===\n")
(flush-output-port)

;; 1. Initialize Generational GC with 256KB Nursery and 64KB Initial Mature Space (1MB VMA reserved)
(let* ((nursery-size 262144)
       (initial-mature-size 65536)
       (max-mature-size 1048576)
       (total-reserved (+ nursery-size (+ (* max-mature-size 2) 32768)))
       (heap-ptr (sys-mmap total-reserved))
       (nursery-base heap-ptr)
       (mature-from (%ptr-add nursery-base nursery-size))
       (mature-to (%ptr-add mature-from max-mature-size))
       (remset-ptr (%ptr-add mature-to max-mature-size)))
  (gc-init-generational! nursery-base nursery-size mature-from mature-to initial-mature-size (%get-rsp) remset-ptr)
  (set-gc-max-size! max-mature-size)

  ;; Verify initial state
  (assert-equal (gc-growth-count) 0 "Initial growth count is 0")
  (assert-equal (gc-mature-size) initial-mature-size "Initial mature size matches configuration")

  ;; 2. Allocate and promote small objects
  (let ((obj1 (cons 100 200))
        (obj2 (vector 1 2 3 4 5)))
    (gc-minor-collect! (%get-rsp))
    (assert-equal (car obj1) 100 "Promoted pair car preserved")
    (assert-equal (cdr obj1) 200 "Promoted pair cdr preserved")
    (assert-equal (vector-ref obj2 2) 3 "Promoted vector element preserved")

    ;; 3. Allocate a list of 2200 pairs (2200 * 24 = 52800 bytes > 65536 * 0.7 = 45875 bytes)
    (let ((acc (let loop ((i 0) (lst '()))
                 (if (< i 2200)
                     (loop (+ i 1) (cons i lst))
                     lst))))
      ;; Force minor GC to promote all 2200 pairs into mature space
      (gc-minor-collect! (%get-rsp))
      (assert-true (> (gc-growth-count) 0) "Dynamic growth occurred when occupancy exceeded 70%")
      (assert-true (> (gc-mature-size) initial-mature-size) "Mature size expanded beyond initial size")
      (assert-equal (car acc) 2199 "Data head preserved after dynamic expansion")
      (assert-equal (car (cdr acc)) 2198 "Data tail preserved after dynamic expansion")

      ;; 4. Continue allocating to trigger a second growth cycle (3500 more pairs)
      (let ((acc2 (let loop2 ((j 0) (lst2 acc))
                    (if (< j 3500)
                        (loop2 (+ j 1) (cons j lst2))
                        lst2))))
        (gc-minor-collect! (%get-rsp))
        (assert-true (>= (gc-growth-count) 2) "Multi-cycle dynamic expansion succeeds (>= 2)")
        (assert-equal (car acc2) 3499 "Data integrity preserved across multiple expansions")
        #t))))

(let ((failures (vector-ref *test-gc-failures* 0)))
  (if (> failures 0)
      (begin
        (write-string "=== SOME GC GROWTH TESTS FAILED! ===\n")
        (sys-exit 1))
      (begin
        (write-string "=== ALL Issue #566 Dynamic Heap Growth & mremap Tests PASSED! ===\n")
        (sys-exit 0))))
