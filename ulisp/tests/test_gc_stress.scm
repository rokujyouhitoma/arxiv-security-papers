;;; =======================================================================
;;; ULisp Test Suite: GC Stress Testing Mode (--gc-stress) (Issue #577)
;;; =======================================================================

(define *test-stress-failures* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-stress-failures* 0 (+ (vector-ref *test-stress-failures* 0) 1))
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
        (vector-set! *test-stress-failures* 0 (+ (vector-ref *test-stress-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-string " (expected ")
        (write-string (if (number? expected) (number->string expected) "val"))
        (write-string ", got ")
        (write-string (if (number? actual) (number->string actual) "val"))
        (write-string ")")
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(write-string "=== Running ULisp Issue #577 GC Stress Testing Mode Suite ===\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Scenario 1: Deep Recursion with Pair Allocation at Every Frame
;; -----------------------------------------------------------------------
(write-string "--- Scenario 1: Deep Recursion with Pair Allocation ---\n")
(flush-output-port)

(letrec ((make-range (lambda (n acc)
                       (if (<= n 0)
                           acc
                           (make-range (- n 1) (cons n acc)))))
         (sum-list (lambda (lst acc)
                     (if (null? lst)
                         acc
                         (sum-list (cdr lst) (+ acc (car lst)))))))
  (let ((r (make-range 300 '())))
    (assert-equal (car r) 1 "Range head is 1")
    (assert-equal (sum-list r 0) 45150 "Range sum matches 300*301/2 (45150)")))

;; -----------------------------------------------------------------------
;; Scenario 2: Mutual Recursion with Intermediate Closures
;; -----------------------------------------------------------------------
(write-string "--- Scenario 2: Mutual Recursion & Intermediate Closures ---\n")
(flush-output-port)

(letrec ((even-step (lambda (k acc)
                      (if (<= k 0)
                          acc
                          (odd-step (- k 1) (cons ((lambda (x) (+ x 1)) k) acc)))))
         (odd-step (lambda (k acc)
                     (if (<= k 0)
                         acc
                         (even-step (- k 1) (cons ((lambda (x) (* x 2)) k) acc))))))
  (let ((res (even-step 200 '())))
    (assert-equal (car res) 2 "Head of alternating transformed list is 2")
    (assert-true (pair? (cdr res)) "Tail of alternating list is a pair")))

;; -----------------------------------------------------------------------
;; Scenario 3: Escaping Closures with Captured Environments
;; -----------------------------------------------------------------------
(write-string "--- Scenario 3: Escaping Closures & Captured Environments ---\n")
(flush-output-port)

(letrec ((make-adders (lambda (n acc)
                        (if (<= n 0)
                            acc
                            (make-adders (- n 1) (cons (lambda (x) (+ x n)) acc)))))
         (apply-all (lambda (adders val acc)
                      (if (null? adders)
                          acc
                          (apply-all (cdr adders) val (+ acc ((car adders) val)))))))
  (let* ((adders (make-adders 50 '()))
         ;; (10+1) + (10+2) + ... + (10+50) = 500 + 1275 = 1775
         (total (apply-all adders 10 0)))
    (assert-equal total 1775 "Sum of 50 escaping captured closures applied to 10 is 1775")))

;; -----------------------------------------------------------------------
;; Scenario 4: Circular Structures & Graph Mutation
;; -----------------------------------------------------------------------
(write-string "--- Scenario 4: Circular Structures & Graph Mutation ---\n")
(flush-output-port)

(let ((node (cons 999 '())))
  (set-cdr! node node)
  ;; Allocate multiple objects to ensure GC cycles run with circular node active on stack
  (letrec ((churn (lambda (count)
                    (if (<= count 0)
                        #t
                        (begin
                          (cons count (cons (+ count 1) '()))
                          (churn (- count 1)))))))
    (churn 50)
    (assert-equal (car node) 999 "Circular node car is 999")
    (assert-equal (car (cdr node)) 999 "Circular node 1st self-reference car is 999")
    (assert-equal (car (cdr (cdr node))) 999 "Circular node 2nd self-reference car is 999")
    (assert-equal (car (cdr (cdr (cdr node)))) 999 "Circular node 3rd self-reference car is 999")))

;; -----------------------------------------------------------------------
;; Scenario 5: Vectors Containing Heap Pointers
;; -----------------------------------------------------------------------
(write-string "--- Scenario 5: Vectors Containing Heap Pointers ---\n")
(flush-output-port)

(let ((v (vector (cons 10 20) (cons 30 40) (cons 50 60))))
  ;; Churn allocations to force GC moving objects in vector
  (letrec ((churn2 (lambda (count)
                     (if (<= count 0)
                         #t
                         (begin
                           (cons count count)
                           (churn2 (- count 1)))))))
    (churn2 40)
    (assert-equal (car (vector-ref v 0)) 10 "Vector[0] car intact (10)")
    (assert-equal (cdr (vector-ref v 0)) 20 "Vector[0] cdr intact (20)")
    (assert-equal (car (vector-ref v 1)) 30 "Vector[1] car intact (30)")
    (assert-equal (cdr (vector-ref v 1)) 40 "Vector[1] cdr intact (40)")
    (assert-equal (car (vector-ref v 2)) 50 "Vector[2] car intact (50)")
    (assert-equal (cdr (vector-ref v 2)) 60 "Vector[2] cdr intact (60)")))

;; -----------------------------------------------------------------------
;; Scenario 6: Binary Tree Allocation & Reduction
;; -----------------------------------------------------------------------
(write-string "--- Scenario 6: Binary Tree Allocation & Reduction ---\n")
(flush-output-port)

(letrec ((make-tree (lambda (depth val)
                      (if (<= depth 0)
                          (cons val '())
                          (cons val (cons (make-tree (- depth 1) (+ (* val 2) 1))
                                          (make-tree (- depth 1) (+ (* val 2) 2)))))))
         (sum-tree (lambda (tree)
                     (if (null? (cdr tree))
                         (car tree)
                         (+ (car tree)
                            (+ (sum-tree (car (cdr tree)))
                               (sum-tree (cdr (cdr tree)))))))))
  (let ((tree (make-tree 6 1)))
    (assert-true (> (sum-tree tree) 0) "Binary tree generated and summed successfully")))

;; -----------------------------------------------------------------------
;; Final Summary & Exit
;; -----------------------------------------------------------------------
(let ((failures (vector-ref *test-stress-failures* 0)))
  (if (> failures 0)
      (begin
        (write-string "=== SOME GC STRESS TESTS FAILED! ===\n")
        (flush-output-port)
        (exit 1))
      (begin
        (write-string "=== ALL ULisp Issue #577 GC Stress Tests PASSED! ===\n")
        #t)))
