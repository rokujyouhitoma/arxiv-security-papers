;;; =======================================================================
;;; Test Suite: Freeze Graph Serialization & .rodata Bloat Guard (Issue #883)
;;; Conforms to DSN-33-03 §7.3
;;; =======================================================================

(display "\n=== [Test Suite: Freeze Graph Serialization & .rodata Bloat Guard (Issue #883)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Non-cyclic Data Structure Freezing
;;; -----------------------------------------------------------------------
(display "--- Group 1: Non-cyclic Data Structure Freezing ---\n")

(let* ((data '(1 2 (3 4 "hello" #(5 6))))
       (frozen (freeze! data)))
  (assert-equal "1.1 Acyclic list structure preserved"
                data
                frozen))

(let* ((rodata (freeze-serialize-to-rodata '(a b c) #f)))
  (assert-equal "1.2 Rodata segment header tag"
                'rodata-segment
                (car rodata))
  (assert-true "1.3 Rodata size recorded"
               (> (cdr (cadr rodata)) 0)))

;;; -----------------------------------------------------------------------
;;; Group 2: Cyclic List Graph Serialization
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Cyclic List Graph Serialization ---\n")

;; Construct a cyclic list: x = (1 2 . x)
(let* ((cell (cons 2 '()))
       (cycle-list (cons 1 cell)))
  (set-cdr! cell cycle-list) ; create cycle!
  ;; Without freeze! with visited set, traversing cycle-list would loop infinitely
  (let ((frozen-cycle (freeze! cycle-list)))
    (assert-equal "2.1 Head element preserved"
                  1
                  (car frozen-cycle))
    (assert-equal "2.2 Second element preserved"
                  2
                  (car (cdr frozen-cycle)))
    ;; Cycle reference placeholder should be placed at the tail
    (assert-equal "2.3 Cycle back-edge resolved as cycle-ref placeholder"
                  '(cycle-ref 1)
                  (cdr (cdr frozen-cycle)))))

;;; -----------------------------------------------------------------------
;;; Group 3: Self-referential Vector Freezing
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Self-referential Vector Freezing ---\n")

(let ((vec (make-vector 2)))
  (vector-set! vec 0 42)
  (vector-set! vec 1 vec) ; self-reference!
  (let ((frozen-vec (freeze! vec)))
    (assert-equal "3.1 Vector element 0 preserved"
                  42
                  (vector-ref frozen-vec 0))
    (assert-equal "3.2 Vector self-reference resolved to cycle-ref"
                  '(cycle-ref 1)
                  (vector-ref frozen-vec 1))))

;;; -----------------------------------------------------------------------
;;; Group 4: .rodata Size Limit Bloat Guard (E-RODATA-OVERFLOW)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: .rodata Size Limit Bloat Guard ---\n")

;; Normal small size limit pass
(let ((small-rodata (freeze-serialize-to-rodata '(x y z) 1000)))
  (assert-equal "4.1 Rodata serialization under limit succeeds"
                'rodata-segment
                (car small-rodata)))

;; Exceeding size limit triggers E-RODATA-OVERFLOW
(let ((orig-abort (car *compiler-abort-on-error*))
      (orig-suppress (car *compiler-suppress-diagnostics*)))
  (set-car! *compiler-abort-on-error* #f)
  (set-car! *compiler-suppress-diagnostics* #t)
  ;; Pass an artificially small max-size (10 bytes) for a large list
  (let ((res (freeze-serialize-to-rodata '(1 2 3 4 5 6 7 8 9 10 "large payload string") 16)))
    (set-car! *compiler-abort-on-error* orig-abort)
    (set-car! *compiler-suppress-diagnostics* orig-suppress)
    (assert-true "4.2 Rodata size limit overflow triggers safe error interception"
                 (number? res))))

(display "\n[RESULT] All Freeze Graph Serialization & .rodata Bloat Guard tests PASSED!\n")
