;;; =======================================================================
;;; ULisp R7RS §4.3.1 let-syntax & letrec-syntax Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #657
;;; =======================================================================

(define (equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (pair? a) (pair? b))
     (and (equal? (car a) (car b))
          (equal? (cdr a) (cdr b))))
    ((and (string? a) (string? b))
     (string=? a b))
    (else #f)))

(define (test name expected actual)
  (if (equal? expected actual)
      (begin
        (write-string "  [PASS] ")
        (write-string name)
        (write-char #\newline)
        (flush-output-port)
        #t)
      (begin
        (write-string "  [FAIL] ")
        (write-string name)
        (write-string " - Expected: ")
        (display expected)
        (write-string ", Actual: ")
        (display actual)
        (write-char #\newline)
        (flush-output-port)
        (exit 1))))

(write-string "=== Running ULisp R7RS let-syntax & letrec-syntax Tests ===\n")

;;; --- Test 1: Basic let-syntax with single & multiple macros ---
(write-string "--- Test 1: Basic let-syntax ---\n")
(let-syntax ((add-ten (syntax-rules ()
                        ((_ x) (+ x 10))))
             (mul-two (syntax-rules ()
                        ((_ x) (* x 2)))))
  (test "let-syntax basic addition macro" 25 (add-ten 15))
  (test "let-syntax basic multiplication macro" 30 (mul-two 15))
  (test "let-syntax composed macros" 50 (add-ten (mul-two 20))))

;;; --- Test 2: Multiple expressions in body (begin sequence) ---
(write-string "--- Test 2: Multiple body expressions ---\n")
(define *test-side-effect* (vector 0))
(let-syntax ((inc-side-effect! (syntax-rules ()
                                 ((_ v) (vector-set! v 0 (+ (vector-ref v 0) 1))))))
  (inc-side-effect! *test-side-effect*)
  (inc-side-effect! *test-side-effect*)
  (test "let-syntax multiple body side-effects" 2 (vector-ref *test-side-effect* 0)))

;;; --- Test 3: Lexical scoping & shadowing ---
(write-string "--- Test 3: Lexical Scoping and Shadowing ---\n")
(define-syntax helper (syntax-rules () ((_ x) (+ x 1000))))

(test "top-level helper macro before let-syntax" 1005 (helper 5))

(let-syntax ((helper (syntax-rules () ((_ x) (+ x 10)))))
  (test "let-syntax shadows top-level macro" 15 (helper 5)))

(test "top-level helper macro restored after let-syntax" 1005 (helper 5))

;;; --- Test 4: Nested let-syntax ---
(write-string "--- Test 4: Nested let-syntax ---\n")
(let-syntax ((outer (syntax-rules () ((_ x) (+ x 100)))))
  (let-syntax ((inner (syntax-rules () ((_ y) (outer (* y 2))))))
    (test "nested let-syntax references enclosing macro" 120 (inner 10))))

;;; --- Test 5: let-syntax non-recursiveness (outer macro reference) ---
(write-string "--- Test 5: let-syntax non-recursiveness ---\n")
;; In let-syntax, the transformer is evaluated in the outer environment.
;; If an outer macro exists, the template's reference to the keyword resolves to the outer macro.
(define-syntax wrap-val (syntax-rules () ((_ v) (list 'outer v))))

(let-syntax ((wrap-val (syntax-rules ()
                         ((_ v) (list 'inner (wrap-val v))))))
  (test "let-syntax template references outer macro" '(inner (outer 42)) (wrap-val 42)))

;;; --- Test 6: Basic letrec-syntax self-recursion ---
(write-string "--- Test 6: letrec-syntax self-recursion ---\n")
(letrec-syntax ((my-list-sum (syntax-rules ()
                               ((_) 0)
                               ((_ x rest ...) (+ x (my-list-sum rest ...))))))
  (test "letrec-syntax self-recursive list sum 3 items" 60 (my-list-sum 10 20 30))
  (test "letrec-syntax self-recursive list sum 5 items" 150 (my-list-sum 10 20 30 40 50)))

;;; --- Test 7: letrec-syntax mutual recursion ---
(write-string "--- Test 7: letrec-syntax mutual recursion ---\n")
(letrec-syntax ((my-even? (syntax-rules ()
                            ((_) #t)
                            ((_ x rest ...) (my-odd? rest ...))))
                (my-odd? (syntax-rules ()
                           ((_) #f)
                           ((_ x rest ...) (my-even? rest ...)))))
  (test "letrec-syntax mutual recursion even 0" #t (my-even?))
  (test "letrec-syntax mutual recursion even 2" #t (my-even? 1 2))
  (test "letrec-syntax mutual recursion even 3" #f (my-even? 1 2 3))
  (test "letrec-syntax mutual recursion odd 0" #f (my-odd?))
  (test "letrec-syntax mutual recursion odd 3" #t (my-odd? 1 2 3)))

;;; --- Test 8: let-syntax with internal definitions ---
(write-string "--- Test 8: Internal definitions in let-syntax ---\n")
(let-syntax ((sq (syntax-rules () ((_ x) (* x x)))))
  (define a 3)
  (define b 4)
  (test "let-syntax with internal definitions and computation" 25 (+ (sq a) (sq b))))

;;; --- Test 9: Hygienic renaming in local macros ---
(write-string "--- Test 9: Hygienic renaming in local macros ---\n")
(let-syntax ((with-temp (syntax-rules ()
                          ((_ val expr)
                           (let ((temp val))
                             (+ temp expr))))))
  (let ((temp 100))
    (test "hygiene prevents local variable capture in let-syntax" 150 (with-temp 50 temp))))

(write-string "=== All let-syntax and letrec-syntax Tests Passed! ===\n")
