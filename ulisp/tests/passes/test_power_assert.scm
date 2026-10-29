;;; =======================================================================
;;; Unit Test Suite: Power Assert & LIR Diagnostics (Issue #603)
;;; Conforms to DSN-33 Architecture Specification & Issue #603
;;; =======================================================================

(define *pa-tests-run* 0)
(define *pa-tests-passed* 0)

(define (assert-true label cond)
  (set! *pa-tests-run* (+ *pa-tests-run* 1))
  (if cond
      (begin
        (set! *pa-tests-passed* (+ *pa-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label) (newline)
        (error "Assertion failed:" label))))

(define (assert-equal label expected actual)
  (set! *pa-tests-run* (+ *pa-tests-run* 1))
  (if (equal? expected actual)
      (begin
        (set! *pa-tests-passed* (+ *pa-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(display "=======================================================")
(newline)
(display " Starting Power Assert & LIR Diagnostics (Pass 603) Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; --- Group 1: Levenshtein Distance Algorithm ---
(display "--- Group 1: Levenshtein Distance Algorithm ---") (newline)

(assert-equal "identical strings dist 0" 0 (string-levenshtein-distance "cat" "cat"))
(assert-equal "single char substitution dist 1" 1 (string-levenshtein-distance "cat" "bat"))
(assert-equal "single char insertion dist 1" 1 (string-levenshtein-distance "cat" "cats"))
(assert-equal "single char deletion dist 1" 1 (string-levenshtein-distance "cats" "cat"))
(assert-equal "empty string vs non-empty" 5 (string-levenshtein-distance "" "hello"))
(assert-equal "non-empty vs empty string" 5 (string-levenshtein-distance "hello" ""))
(assert-equal "both empty strings dist 0" 0 (string-levenshtein-distance "" ""))
(assert-equal "classic kitten vs sitting dist 3" 3 (string-levenshtein-distance "kitten" "sitting"))

;; Symbol Levenshtein distance
(assert-equal "identical symbols dist 0" 0 (symbol-levenshtein-distance 'car 'car))
(assert-equal "symbol car vs cdr dist 1" 1 (symbol-levenshtein-distance 'car 'cdr))
(assert-equal "symbol car vs caar dist 1" 1 (symbol-levenshtein-distance 'car 'caar))
(assert-equal "symbol len vs length dist 3" 3 (symbol-levenshtein-distance 'len 'length))

;;; --- Group 2: Similar Symbols Recommendation (Did you mean?) ---
(display "--- Group 2: Similar Symbols Recommendation ---") (newline)

(let ((candidates '(cdr caar cadar ls env pred count)))
  (let ((suggestions (find-similar-symbols 'car candidates)))
    (assert-true "suggestions contains cdr" (memq 'cdr suggestions))
    (assert-true "suggestions contains caar" (memq 'caar suggestions))
    (assert-true "suggestions does not contain ls" (not (memq 'ls suggestions)))
    ;; Verify ordering: distance 1 candidates (cdr/caar) come first
    (assert-true "first suggestion is distance 1" (memq (car suggestions) '(cdr caar)))))

;; Custom threshold using find-similar-symbols-dist
(let ((suggestions (find-similar-symbols-dist 'car '(cadar caadar) 3)))
  (assert-true "distance 3 finds cadar" (memq 'cadar suggestions)))

;; When no candidate is close within threshold
(let ((suggestions (find-similar-symbols 'xyz '(alpha beta gamma delta))))
  (assert-equal "no match returns empty list" '() suggestions))

;; Target itself is not included in suggestions
(let ((suggestions (find-similar-symbols 'target '(target target2 other))))
  (assert-true "self is excluded from suggestions" (not (memq 'target suggestions)))
  (assert-true "target2 is included" (memq 'target2 suggestions)))

;;; --- Group 3: LIR Environment (env) Formatting & Diagnostics ---
(display "--- Group 3: LIR Environment Formatting & Diagnostics ---") (newline)

(assert-equal "format stack offset" "stack -8" (format-binding-info -8))
(assert-equal "format reg pair" "reg %rax" (format-binding-info '(reg . %rax)))
(assert-equal "format reg symbol" "reg %rbx" (format-binding-info '%rbx))
(assert-equal "format param" "param -16" (format-binding-info '(param . -16)))
(assert-equal "format self" "self -24" (format-binding-info '(self . -24)))

;; Verify dump-lir-unbound-variable-diagnostic runs cleanly with bindings
(set-current-pass! 'pass-130-lir)
(set-current-toplevel-name! 'filter-evens)
(set-current-form! '(car ls))

(let ((env '((ls . (param . -8))
             (cdr . (param . -16))
             (pred . (param . -24)))))
  (set-car! *compiler-suppress-diagnostics* #t)
  (dump-lir-unbound-variable-diagnostic 'car env)
  (set-car! *compiler-suppress-diagnostics* #f)
  (assert-true "dump diagnostic with env executed cleanly" #t))

;; Verify dump-lir-unbound-variable-diagnostic runs cleanly with empty env
(set-car! *compiler-suppress-diagnostics* #t)
(dump-lir-unbound-variable-diagnostic 'unbound '())
(set-car! *compiler-suppress-diagnostics* #f)
(assert-true "dump diagnostic with empty env executed cleanly" #t)

;;; --- Group 4: Power Assert Diagnostics & AST Expansion ---
(display "--- Group 4: Power Assert Diagnostics & AST Expansion ---") (newline)

;; Representation lengths
(assert-equal "repr len of symbol 'assq" 4 (datum-repr-length 'assq))
(assert-equal "repr len of number 42" 2 (datum-repr-length 42))
(assert-equal "repr len of boolean #f" 2 (datum-repr-length #f))
(assert-equal "repr len of list (a b)" 5 (datum-repr-length '(a b)))
(assert-equal "repr len of list (assq var env)" 14 (datum-repr-length '(assq var env)))

;; Column computation for diagram
(let ((cols (compute-expr-columns '(assq var env) 4)))
  (assert-equal "base columns for (assq var env)" '(5 10 14) cols))

;; Expansion of power-assert form
(let* ((expanded (power-assert-expand '(assq var env))))
  (assert-true "expanded is a pair" (pair? expanded))
  (assert-equal "expanded starts with let*" 'let* (car expanded)))

;; Define host macro for testing power-assert
(define-macro (power-assert form)
  (power-assert-expand form))

;; Evaluation of power-assert macro with a truthy condition
(let ((val (power-assert (= (+ 1 2) 3))))
  (assert-equal "power-assert on truthy condition returns result" #t val))

;; Power-assert failure report output verification (suppressed during unit test run)
(set-car! *compiler-abort-on-error* #f)
(set-car! *compiler-suppress-diagnostics* #t)
(let ((ret (power-assert-report '(assq var env)
                                '((var car) (env ((ls . (param . -8)))))
                                #f)))
  (assert-equal "power-assert-report returns irritant form" '(assq var env) ret))
(set-car! *compiler-abort-on-error* #t)
(set-car! *compiler-suppress-diagnostics* #f)

(display "=======================================================")
(newline)
(display " All Power Assert & LIR Diagnostics Tests Passed Successfully! (")
(display *pa-tests-passed*)
(display " / ")
(display *pa-tests-run*)
(display ")")
(newline)
(display "=======================================================")
(newline)
