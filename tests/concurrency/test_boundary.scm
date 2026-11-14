;;; =======================================================================
;;; Synapse Host-Kernel Boundary Sanitizer Test Suite
;;; Path: tests/concurrency/test_boundary.scm
;;; Conforms to DSN-37 Section 8.1, 9.1 & Phase 4 Task 4.1 (Issue #641)
;;; =======================================================================

(load "ulisp/runtime/concurrency/arena.scm")
(load "ulisp/runtime/concurrency/boundary.scm")

(test-begin "concurrency-boundary")

(define-syntax assert-true
  (syntax-rules ()
    ((assert-true val msg)
     (test-assert msg val))
    ((assert-true val)
     (test-assert "assert-true" val))))

(define-syntax assert-false
  (syntax-rules ()
    ((assert-false val msg)
     (test-assert msg (not val)))
    ((assert-false val)
     (test-assert "assert-false" (not val)))))

(define-syntax assert-eq
  (syntax-rules ()
    ((assert-eq actual expected msg)
     (test-equal msg expected actual))))

(define-syntax assert-equal
  (syntax-rules ()
    ((assert-equal actual expected msg)
     (test-equal msg expected actual))))

(define-syntax assert-error
  (syntax-rules ()
    ((assert-error thunk msg)
     (let ((caught
            (guard (exn (#t #t))
              (thunk)
              #f)))
       (test-assert msg caught)))))


(define (deep-equal? a b)
  (cond
    ((eqv? a b) #t)
    ((and (pair? a) (pair? b))
     (and (deep-equal? (car a) (car b))
          (deep-equal? (cdr a) (cdr b))))
    ((and (vector? a) (vector? b))
     (let ((len-a (vector-length a))
           (len-b (vector-length b)))
       (if (= len-a len-b)
           (let loop ((i 0))
             (if (< i len-a)
                 (if (deep-equal? (vector-ref a i) (vector-ref b i))
                     (loop (+ i 1))
                     #f)
                 #t))
           #f)))
    ((and (string? a) (string? b))
     (string=? a b))
    ((and (bytevector? a) (bytevector? b))
     (let ((len-a (bytevector-length a))
           (len-b (bytevector-length b)))
       (if (= len-a len-b)
           (let loop ((i 0))
             (if (< i len-a)
                 (if (= (bytevector-u8-ref a i) (bytevector-u8-ref b i))
                     (loop (+ i 1))
                     #f)
                 #t))
           #f)))
    (else #f)))

(define (assert-equal actual expected msg)
  (test-equal msg expected actual))

;;; -----------------------------------------------------------------------
;;; Group 1: Immediate Value Pass-Through (Zero-Copy)
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 1: Immediate Value Pass-Through (Zero-Copy) ---\n")
(flush-output-port)

(define arena (make-task-arena 4096))

(assert-true (immediate-value? 42) "1.1 fixnum is immediate-value?")
(assert-true (and (immediate-value? #t) (immediate-value? #f)) "1.2 boolean is immediate-value?")
(assert-true (immediate-value? #\A) "1.3 char is immediate-value?")
(assert-true (immediate-value? '()) "1.4 null is immediate-value?")
(assert-true (immediate-value? 'synapse-atom) "1.5 symbol is immediate-value?")
(assert-false (immediate-value? (cons 1 2)) "1.6 pair is not immediate-value?")
(assert-false (immediate-value? #(1 2 3)) "1.7 vector is not immediate-value?")

;; Zero-copy transfer of immediates
(let ((off-before (arena-offset arena)))
  (assert-equal (sanitize-to-arena 100 arena) 100 "1.8 fixnum passed without arena bump")
  (assert-equal (arena-offset arena) off-before "1.9 arena offset unchanged for immediate"))

;;; -----------------------------------------------------------------------
;;; Group 2: List / Pair Deep Copy & Pointer Non-Sharing
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 2: List / Pair Deep Copy & Pointer Non-Sharing ---\n")
(flush-output-port)

(let* ((orig (list 1 2 3 4 5))
       (off-before (arena-offset arena))
       (copied (sanitize-to-arena orig arena)))
  (assert-equal copied orig "2.1 list structure preserved")
  (assert-false (eq? orig copied) "2.2 top-level pair pointer is distinct")
  (assert-false (shared-pointer? orig copied) "2.3 shared-pointer? detects zero shared pair pointers")
  (assert-true (> (arena-offset arena) off-before) "2.4 arena offset advanced by pair allocations"))

;; Nested tree structure
(let* ((orig-tree '((a (b c)) (d (e (f)))))
       (copied-tree (sanitize-to-arena orig-tree arena)))
  (assert-equal copied-tree orig-tree "2.5 nested tree preserved")
  (assert-false (shared-pointer? orig-tree copied-tree) "2.6 tree pointers completely distinct"))

;; Mutation isolation verification
(let* ((host-list (list 10 20 30))
       (kernel-list (sanitize-to-arena host-list arena)))
  (set-car! kernel-list 999)
  (assert-equal host-list '(10 20 30) "2.7 modifying kernel list leaves host list unaffected")
  (assert-equal kernel-list '(999 20 30) "2.8 kernel list modified in isolation"))

;;; -----------------------------------------------------------------------
;;; Group 3: Vector Deep Copy & Isolation
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 3: Vector Deep Copy & Isolation ---\n")
(flush-output-port)

(let* ((orig-vec (vector 1 2 (vector 3 4) 5))
       (copied-vec (sanitize-to-arena orig-vec arena)))
  (assert-equal copied-vec orig-vec "3.1 vector structure preserved")
  (assert-false (eq? orig-vec copied-vec) "3.2 vector identity distinct")
  (assert-false (eq? (vector-ref orig-vec 2) (vector-ref copied-vec 2)) "3.3 inner vector identity distinct")
  (assert-false (shared-pointer? orig-vec copied-vec) "3.4 shared-pointer? is false for vector graph")

  ;; Mutation isolation
  (vector-set! copied-vec 0 888)
  (assert-equal (vector-ref orig-vec 0) 1 "3.5 host vector intact after copied vector modification"))

;;; -----------------------------------------------------------------------
;;; Group 4: String & Bytevector Deep Copy
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 4: String & Bytevector Deep Copy ---\n")
(flush-output-port)

(let* ((orig-str "synapse-isolated-domain")
       (copied-str (sanitize-to-arena orig-str arena)))
  (assert-equal copied-str orig-str "4.1 string content preserved")
  (assert-false (eq? orig-str copied-str) "4.2 string pointer is distinct")
  (assert-false (shared-pointer? orig-str copied-str) "4.3 shared-pointer? is false for distinct string"))

(let* ((orig-bv (let ((b (make-bytevector 4)))
                  (bytevector-u8-set! b 0 10)
                  (bytevector-u8-set! b 1 20)
                  (bytevector-u8-set! b 2 30)
                  (bytevector-u8-set! b 3 40)
                  b))
       (copied-bv (sanitize-to-arena orig-bv arena)))
  (assert-equal copied-bv orig-bv "4.4 bytevector content preserved")
  (assert-false (eq? orig-bv copied-bv) "4.5 bytevector pointer is distinct")
  (assert-false (shared-pointer? orig-bv copied-bv) "4.6 shared-pointer? is false for distinct bytevector"))

;;; -----------------------------------------------------------------------
;;; Group 5: Circular Reference Detection (CWE-674 Guard)
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 5: Circular Reference Detection (CWE-674 Guard) ---\n")
(flush-output-port)

;; Top-level definition ensures stable global reference across guard closure boundaries
(define test-circ-list (cons 1 (cons 2 '())))
(set-cdr! (cdr test-circ-list) test-circ-list)

(define test-circ-vec (vector 1 2))
(vector-set! test-circ-vec 0 test-circ-vec)

;; 5.1 Circular list detection
(let ((caught-list (guard (exn (else #t))
                     (sanitize-to-arena test-circ-list arena)
                     #f)))
  (assert-true caught-list "5.1 circular list is safely rejected (CWE-674)"))

;; 5.2 Circular vector detection
(let ((caught-vec (guard (exn (else #t))
                    (sanitize-to-arena test-circ-vec arena)
                    #f)))
  (assert-true caught-vec "5.2 circular vector is safely rejected (CWE-674)"))

;;; -----------------------------------------------------------------------
;;; Group 6: Kernel to Host Transfer (sanitize-from-arena)
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 6: Kernel to Host Transfer (sanitize-from-arena) ---\n")
(flush-output-port)

(let* ((kernel-data (list "result" (vector 100 200) '(nested-val)))
       (host-data (sanitize-from-arena kernel-data)))
  (assert-equal host-data kernel-data "6.1 result replicated into host format")
  (assert-false (shared-pointer? kernel-data host-data) "6.2 host data shares no pointers with kernel data")

  ;; Simulate task arena instant full reset
  (arena-reset! arena)
  (assert-equal host-data (list "result" (vector 100 200) '(nested-val)) "6.3 host data remains fully accessible after task arena reset"))

(test-end "concurrency-boundary")
