;;; =======================================================================
;;; ULisp SRFI 252 Property Testing Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #821
;;; =======================================================================

(write-string "=== Running ULisp SRFI 252 Property Testing Test Suite ===\n")

;; Initialize deterministic PRNG seed for reproducible test run
(property-random-seed-set! 42)

;; -----------------------------------------------------------------------
;; Test 1: Built-in Type Generators Basic Validation
;; -----------------------------------------------------------------------
(write-string "--- Test 1: Built-in Type Generators ---\n")

(let ((b-gen (boolean-generator))
      (c-gen (char-generator))
      (s-gen (string-generator))
      (sym-gen (symbol-generator))
      (bv-gen (bytevector-generator))
      (int-gen (exact-integer-generator -50 50))
      (cplx-gen (exact-complex-generator))
      (lst-gen (list-generator (exact-integer-generator 0 10) 5))
      (vec-gen (vector-generator (boolean-generator) 5))
      (sx-gen (sexpr-generator 3)))
  (let loop ((i 0))
    (if (< i 20)
        (let ((b (b-gen))
              (c (c-gen))
              (s (s-gen))
              (sym (sym-gen))
              (bv (bv-gen))
              (n (int-gen))
              (z (cplx-gen))
              (lst (lst-gen))
              (v (vec-gen))
              (sx (sx-gen)))
          (if (not (boolean? b)) (error "Expected boolean" b))
          (if (not (char? c)) (error "Expected char" c))
          (if (not (string? s)) (error "Expected string" s))
          (if (not (symbol? sym)) (error "Expected symbol" sym))
          (if (not (bytevector? bv)) (error "Expected bytevector" bv))
          (if (not (integer? n)) (error "Expected integer" n))
          (if (not (complex? z)) (error "Expected complex" z))
          (if (not (list? lst)) (error "Expected list" lst))
          (if (not (vector? v)) (error "Expected vector" v))
          (loop (+ i 1))))))

(write-string "  [PASS] All basic generator outputs match expected types.\n")

;; -----------------------------------------------------------------------
;; Test 2: Mathematical Properties (Algebraic Invariants)
;; -----------------------------------------------------------------------
(write-string "--- Test 2: Mathematical Invariants ---\n")

;; Commutativity of Addition: a + b = b + a
(define prop-add-comm
  (lambda (a b)
    (= (+ a b) (+ b a))))

;; Commutativity of Multiplication: a * b = b * a
(define prop-mul-comm
  (lambda (a b)
    (= (* a b) (* b a))))

;; Associativity of Addition: (a + b) + c = a + (b + c)
(define prop-add-assoc
  (lambda (a b c)
    (= (+ (+ a b) c) (+ a (+ b c)))))

;; Distributivity: a * (b + c) = (a * b) + (a * c)
(define prop-distrib
  (lambda (a b c)
    (= (* a (+ b c)) (+ (* a b) (* a c)))))

;; Identity: a + 0 = a, a * 1 = a
(define prop-identities
  (lambda (a)
    (and (= (+ a 0) a)
         (= (* a 1) a))))

(let ((int-gen (exact-integer-generator -500 500)))
  (if (not (test-property "addition commutativity" prop-add-comm (list int-gen int-gen) 50))
      (error "prop-add-comm failed"))
  (if (not (test-property "multiplication commutativity" prop-mul-comm (list int-gen int-gen) 50))
      (error "prop-mul-comm failed"))
  (if (not (test-property "addition associativity" prop-add-assoc (list int-gen int-gen int-gen) 50))
      (error "prop-add-assoc failed"))
  (if (not (test-property "distributivity" prop-distrib (list int-gen int-gen int-gen) 50))
      (error "prop-distrib failed"))
  (if (not (test-property "additive & multiplicative identity" prop-identities (list int-gen) 50))
      (error "prop-identities failed")))

(write-string "  [PASS] Mathematical properties hold for all generated inputs.\n")

;; -----------------------------------------------------------------------
;; Test 3: Collection Structure Invariants
;; -----------------------------------------------------------------------
(write-string "--- Test 3: Collection Structure Invariants ---\n")

;; List double-reversal: reverse(reverse(lst)) == lst
(define prop-list-reverse
  (lambda (lst)
    (equal? (reverse (reverse lst)) lst)))

;; Append length preservation: length(append(a, b)) == length(a) + length(b)
(define prop-append-length
  (lambda (a b)
    (= (length (append a b)) (+ (length a) (length b)))))

;; Vector <-> List roundtrip: list->vector(vector->list(v)) == v
(define prop-vector-list-roundtrip
  (lambda (v)
    (equal? (list->vector (vector->list v)) v)))

;; String append length: string-length(s1 ++ s2) == len(s1) + len(s2)
(define prop-string-append-len
  (lambda (s1 s2)
    (= (string-length (string-append s1 s2))
       (+ (string-length s1) (string-length s2)))))

(let ((lst-gen (list-generator (exact-integer-generator -100 100) 10))
      (vec-gen (vector-generator (symbol-generator 6) 8))
      (str-gen (string-generator (char-generator #\a #\z) 12)))
  (if (not (test-property "list double reversal" prop-list-reverse (list lst-gen) 50))
      (error "prop-list-reverse failed"))
  (if (not (test-property "append length preservation" prop-append-length (list lst-gen lst-gen) 50))
      (error "prop-append-length failed"))
  (if (not (test-property "vector-list roundtrip" prop-vector-list-roundtrip (list vec-gen) 50))
      (error "prop-vector-list-roundtrip failed"))
  (if (not (test-property "string append length" prop-string-append-len (list str-gen str-gen) 50))
      (error "prop-string-append-len failed")))

(write-string "  [PASS] Collection structural invariants verified.\n")

;; -----------------------------------------------------------------------
;; Test 4: Skip, Expect-Fail, and Error Properties
;; -----------------------------------------------------------------------
(write-string "--- Test 4: Skip, Expect-Fail, and Error ---\n")

;; test-property-skip should always return #t and skip execution
(if (not (test-property-skip "skipped test" (lambda (x) (= x x)) (list (exact-integer-generator)) 20))
    (error "test-property-skip failed"))

;; test-property-expect-fail should succeed when the property fails
(define prop-unreasonable
  (lambda (x)
    (> x 100000))) ;; will fail for range 0..100

(if (not (test-property-expect-fail "expected failure" prop-unreasonable (list (exact-integer-generator 0 100)) 30))
    (error "test-property-expect-fail should have reported expected failure"))

;; test-property-error should succeed when property raises an exception
(define prop-err-test
  (lambda (x)
    (error "deliberate error" x)))

(if (not (test-property-error "deliberate error test" prop-err-test (list (exact-integer-generator 1 100)) 20))
    (error "test-property-error should have caught expected exception"))

(write-string "  [PASS] Skip, expect-fail, and error properties behave correctly.\n")

;; -----------------------------------------------------------------------
;; Test 5: Deterministic Counterexample Reproduction
;; -----------------------------------------------------------------------
(write-string "--- Test 5: Deterministic Counterexample Reproduction ---\n")

;; Save baseline seed
(define fixed-seed 987654321)

;; A property that fails for any number >= 25
(define prop-small
  (lambda (x)
    (< x 25)))

(let* ((_1 (property-random-seed-set! fixed-seed))
       (gen-1 (exact-integer-generator 0 100))
       (val-1 (let loop ((i 0))
                (if (< i 50)
                    (let ((v (gen-1)))
                      (if (not (prop-small v))
                          v
                          (loop (+ i 1))))
                    #f)))
       (_2 (property-random-seed-set! fixed-seed))
       (gen-2 (exact-integer-generator 0 100))
       (val-2 (let loop ((i 0))
                (if (< i 50)
                    (let ((v (gen-2)))
                      (if (not (prop-small v))
                          v
                          (loop (+ i 1))))
                    #f))))
  (if (not (equal? val-1 val-2))
      (error "PRNG determinism failed: counterexamples differ" val-1 val-2))
  (write-string "  [PASS] Counterexample deterministically reproduced with seed: ")
  (write fixed-seed)
  (write-string " => value: ")
  (write val-1)
  (newline))

;; -----------------------------------------------------------------------
;; Test 6: S-expression AST Generator & Reader/Printer Roundtrip
;; -----------------------------------------------------------------------
(write-string "--- Test 6: S-Expression AST Generator & Roundtrip ---\n")

(define (sexpr->string obj)
  (let ((p (open-output-string)))
    (write obj p)
    (get-output-string p)))

(define (string->sexpr str)
  (let ((p (open-input-string str)))
    (read p)))

(define prop-ast-roundtrip
  (lambda (ast)
    (let* ((str (sexpr->string ast))
           (parsed (string->sexpr str)))
      (equal? ast parsed))))

(if (not (test-property "ast-roundtrip" prop-ast-roundtrip (list (sexpr-generator 3)) 30))
    (error "prop-ast-roundtrip failed on generated S-expressions"))

(write-string "  [PASS] S-expression AST generator passes Reader/Printer roundtrip.\n")

;; -----------------------------------------------------------------------
;; Test 7: SRFI 64 Test Suite Integration
;; -----------------------------------------------------------------------
(write-string "--- Test 7: SRFI 64 Test Runner Integration ---\n")

(test-begin "srfi-252-integrated-suite")

(test-property "srfi64-int-identity"
               (lambda (x) (= (+ x 0) x))
               (list (exact-integer-generator -100 100))
               25)

(test-property "srfi64-list-rev-length"
               (lambda (lst) (= (length (reverse lst)) (length lst)))
               (list (list-generator (exact-integer-generator 0 50) 6))
               25)

(test-end "srfi-252-integrated-suite")

(write-string "=== All SRFI 252 Property Tests Passed Successfully! ===\n")
