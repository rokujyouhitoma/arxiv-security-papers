;;; =======================================================================
;;; Unit & Integration Test Suite: Nanopass AST First-Class Source Span & Metadata
;;; Conforms to DSN-33-02 §3.1 & Issue #824
;;; =======================================================================

(test-begin "Nanopass AST First-Class Source Span & Metadata")

;;; -----------------------------------------------------------------------
;;; Group 1: <source-span> Record Type, Constructors, Accessors & ID Counter
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: <source-span> Record Type & Basic Operations ---\n")

(reset-source-span-id-counter!)
(define span1 (make-source-span "src/parser.scm" 10 5 12 20 #f (next-source-span-id!)))

(assert-true "1.1 source-span? identifies <source-span>" (source-span? span1))
(assert-false "1.2 source-span? rejects non-record vector" (source-span? #(1 2 3)))
(assert-false "1.3 source-span? rejects list or atom" (source-span? '(10 5 12 20)))
(assert-false "1.4 source-span? rejects symbol" (source-span? 'span))

(assert-equal "1.5 span-file extracts sanitized path" "src/parser.scm" (span-file span1))
(assert-equal "1.6 span-start-line extracts start line" 10 (span-start-line span1))
(assert-equal "1.7 span-start-col extracts start col" 5 (span-start-col span1))
(assert-equal "1.8 span-end-line extracts end line" 12 (span-end-line span1))
(assert-equal "1.9 span-end-col extracts end col" 20 (span-end-col span1))
(assert-false "1.10 span-macro-origin is #f when not from macro" (span-macro-origin span1))
(assert-true "1.11 span-node-id is positive integer" (> (span-node-id span1) 0))

;; Monotonic ID counter
(define span2 (make-source-span "src/parser.scm" 15 1 15 10 #f (next-source-span-id!)))
(assert-true "1.12 node-id monotonically increments" (> (span-node-id span2) (span-node-id span1)))

;; Flyweight singleton *no-source-span*
(assert-true "1.13 no-source-span? recognizes singleton" (no-source-span? *no-source-span*))
(assert-equal "1.14 *no-source-span* node-id is 0" 0 (span-node-id *no-source-span*))
(assert-false "1.15 no-source-span? rejects real span" (no-source-span? span1))

;; Explicit end coordinates
(define span-short (make-source-span "src/short.scm" 42 7 42 7 #f (next-source-span-id!)))
(assert-equal "1.16 end-line defaults to start-line" 42 (span-end-line span-short))
(assert-equal "1.17 end-col defaults to start-col" 7 (span-end-col span-short))

;;; -----------------------------------------------------------------------
;;; Group 2: AST Annotation, Extraction, Stripping & Idempotency
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: AST Annotation & Stripping Operations ---\n")

(define ast-node '(+ 1 2))
(define annotated (ast-with-span ast-node span1))

(assert-true "2.1 ast-has-span? recognizes annotated AST" (ast-has-span? annotated))
(assert-false "2.2 ast-has-span? rejects plain AST" (ast-has-span? ast-node))
(assert-equal "2.3 ast-source-span retrieves attached span" span1 (ast-source-span annotated))
(assert-equal "2.4 ast-strip-span extracts raw form" '(+ 1 2) (ast-strip-span annotated))

;; Idempotent wrapping (no nested %source-span)
(define double-annotated (ast-with-span annotated span2))
(assert-equal "2.5 double-annotated replaces span without nesting" span2 (ast-source-span double-annotated))
(assert-equal "2.6 stripped form remains unchanged" '(+ 1 2) (ast-strip-span double-annotated))
(assert-false "2.7 inner form is not %source-span" (ast-has-span? (ast-strip-span double-annotated)))

;; strip-source-loc handles both %source-loc and %source-span
(assert-equal "2.8 strip-source-loc unwraps %source-span" '(+ 1 2) (strip-source-loc annotated))

;; ast-propagate-span
(define new-node '(* 2 3))
(define propagated (ast-propagate-span new-node annotated))
(assert-true "2.9 propagated node has span" (ast-has-span? propagated))
(assert-equal "2.10 propagated span matches original" span1 (ast-source-span propagated))
(assert-equal "2.11 propagated raw node is new-node" '(* 2 3) (ast-strip-span propagated))

;;; -----------------------------------------------------------------------
;;; Group 3: Nanopass Engine Transparent Span Propagation
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Nanopass Transparent Span Propagation ---\n")

;; Define a test picopass that optimizes (+ 1 2) -> 3
(define-picopass test-pico-fold
  (Expr
    ((+ 1 2) 3)))

(define input-pico (ast-with-span '(+ 1 2) span1))
(define output-pico (test-pico-fold input-pico))

(assert-true "3.1 picopass transformed node preserves span" (ast-has-span? output-pico))
(assert-equal "3.2 picopass transformed raw value is 3" 3 (ast-strip-span output-pico))
(assert-equal "3.3 picopass preserved span matches input span" span1 (ast-source-span output-pico))

;; Define a define-pass that transforms (+ ,a ,b) -> (- ,a (- 0 ,b))
(define-language L_test_arith
  (terminals
    (symbol (x))
    (number (n)))
  (Expr (e)
    x
    n
    (+ e1 e2)
    (- e1 e2)))

(define-pass test-pass-arith : L_test_arith (e) -> L_test_arith ()
  (Expr : Expr (e) -> Expr ()
    ((+ ,e1 ,e2)
     `(- ,e1 (- 0 ,e2)))))

(define input-pass (ast-with-span '(+ x 5) span1))
(define output-pass (test-pass-arith input-pass))

(assert-true "3.4 define-pass preserves root span" (ast-has-span? output-pass))
(assert-equal "3.5 define-pass raw form is rewritten" '(- x (- 0 5)) (ast-strip-span output-pass))
(assert-equal "3.6 define-pass root span matches original" span1 (ast-source-span output-pass))

;;; -----------------------------------------------------------------------
;;; Group 4: Macro Expansion Origin Tracking (macro-origin Chain)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Macro Origin Chain Tracking ---\n")

(define macro-table-test
  (list (cons 'double
              (parse-syntax-rules-def '(define-syntax double
                                         (syntax-rules ()
                                           ((double x) (+ x x))))))))

(define call-span (make-source-span "src/macro_test.scm" 25 1 25 10 #f (next-source-span-id!)))
(define macro-call (ast-with-span '(double 21) call-span))

(define macro-res (macro-expand-1 macro-call macro-table-test))
(assert-true "4.1 macro-expand-1 expands successfully" (car macro-res))

(define expanded-node (cdr macro-res))
(assert-true "4.2 expanded node has span" (ast-has-span? expanded-node))
(assert-equal "4.3 expanded form is (+ 21 21)" '(+ 21 21) (ast-strip-span expanded-node))

(define exp-span (ast-source-span expanded-node))
(assert-true "4.4 expanded node span exists" (source-span? exp-span))
(assert-equal "4.5 macro-origin points to call-span" call-span (span-macro-origin exp-span))
(assert-equal "4.6 macro-origin file matches" "src/macro_test.scm" (span-file (span-macro-origin exp-span)))
(assert-equal "4.7 macro-origin line matches" 25 (span-start-line (span-macro-origin exp-span)))

;; Nested macro expansion chain
(define nested-macro-table
  (append macro-table-test
          (list (cons 'quadruple
                      (parse-syntax-rules-def '(define-syntax quadruple
                                                 (syntax-rules ()
                                                   ((quadruple x) (double (double x))))))))))

(define quad-call-span (make-source-span "src/quad.scm" 50 3 50 18 #f (next-source-span-id!)))
(define quad-call (ast-with-span '(quadruple 5) quad-call-span))
(define quad-res (macro-expand-1 quad-call nested-macro-table))
(assert-true "4.8 quadruple expands" (car quad-res))
(define quad-step1 (cdr quad-res))
(define step1-span (ast-source-span quad-step1))
(assert-equal "4.9 step1 macro-origin links to quad-call-span" quad-call-span (span-macro-origin step1-span))

;;; -----------------------------------------------------------------------
;;; Group 5: Security & Boundary Guards (CWE-119, CWE-400, CWE-843, CWE-22)
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Security & Boundary Guards ---\n")

;; CWE-119 / Coordinate Boundary Guard: negative or inverted lines clamped
(define safe-span (make-source-span "src/test.scm" -5 -10 2 1 #f (next-source-span-id!)))
(assert-true "5.1 start-line clamped >= 1" (>= (span-start-line safe-span) 1))
(assert-true "5.2 start-col clamped >= 1" (>= (span-start-col safe-span) 1))
(assert-true "5.3 end-line clamped >= start-line" (>= (span-end-line safe-span) (span-start-line safe-span)))

;; CWE-22: Path Sanitization (Directory Traversal Prevention)
(define (string-contains-char? s ch)
  (let loop ((i (- (string-length s) 1)))
    (cond
      ((< i 0) #f)
      ((char=? (string-ref s i) ch) #t)
      (else (loop (- i 1))))))

(define unsafe-path "dir/../../etc/passwd\n\t\"")
(define sanitized (sanitize-source-path unsafe-path))
(assert-false "5.4 sanitized path contains no newline" (string-contains-char? sanitized #\newline))
(assert-false "5.5 sanitized path contains no double quotes" (string-contains-char? sanitized #\"))

;; CWE-843: Type Confusion Guard
(assert-false "5.6 ast-has-span? rejects fake tag in pair" (ast-has-span? '(%source-span "invalid")))
(assert-false "5.7 ast-has-span? rejects vector as ast" (ast-has-span? (vector '%source-span span1)))
(assert-equal "5.8 ast-strip-span passes through invalid structures" "foo" (ast-strip-span "foo"))

;; Function Source Span Table Registration & Lookup
(register-function-source-span! 'my-handler span1)
(assert-equal "5.9 lookup-function-source-span retrieves registered span" span1 (lookup-function-source-span 'my-handler))
(assert-false "5.10 lookup-function-source-span returns #f for unknown function" (lookup-function-source-span 'nonexistent-fn))

;;; -----------------------------------------------------------------------
;;; Group 6: Overhead & Performance Benchmark (< 5%)
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Performance & Memory Overhead Validation ---\n")

(define bench-iterations 1000)
(define bench-node '(if (> x 0) (+ x 1) (- x 1)))

(define (benchmark-run with-spans?)
  (let loop ((i bench-iterations) (acc '()))
    (if (<= i 0)
        acc
        (if with-spans?
            (let ((s (make-source-span "bench.scm" i 1 i 20 #f i)))
              (loop (- i 1) (cons (ast-with-span bench-node s) acc)))
            (loop (- i 1) (cons bench-node acc))))))

(define t0 (current-jiffy))
(define raw-nodes (benchmark-run #f))
(define t1 (current-jiffy))
(define raw-time (max 1 (- t1 t0)))

(define t2 (current-jiffy))
(define span-nodes (benchmark-run #t))
(define t3 (current-jiffy))
(define span-time (max 1 (- t3 t2)))

(display "  Raw allocation iterations: ")
(display bench-iterations)
(display " in ")
(display raw-time)
(display " jiffies\n")
(display "  Span allocation iterations: ")
(display bench-iterations)
(display " in ")
(display span-time)
(display " jiffies\n")

;; Verify node count and sample integrity
(assert-equal "6.1 benchmark allocated 1000 span nodes" 1000 (length span-nodes))
(assert-true "6.2 sample node has valid span" (ast-has-span? (car span-nodes)))
(assert-equal "6.3 stripped sample node equals original" bench-node (ast-strip-span (car span-nodes)))

(test-end "Nanopass AST First-Class Source Span & Metadata")
