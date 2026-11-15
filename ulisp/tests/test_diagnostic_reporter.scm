;;; =======================================================================
;;; Unit Test Suite: ULisp Unified Pretty Diagnostic Reporter
;;; Conforms to DSN-33-02 §3.4, DSN-38 §1/§2 & Issue #833
;;; =======================================================================

(test-begin "Unified Pretty Diagnostic Reporter (Issue #833)")

;;; -----------------------------------------------------------------------
;;; Group 1: <diagnostic> Record Type, Constructors, Accessors & Modifiers
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: <diagnostic> Record Type & Basic Operations ---\n")

(reset-diagnostic-state!)
(set-diagnostic-color-mode! 'never)

(define test-span-1 (make-source-span "src/main.scm" 10 5 10 12 #f 1))
(define diag1 (make-diagnostic 'error 'S0001 test-span-1 "unbound variable 'calculate-pi'"))

(assert-true "1.1 diagnostic? identifies <diagnostic>" (diagnostic? diag1))
(assert-equal "1.2 diagnostic-level extracts 'error" 'error (diagnostic-level diag1))
(assert-equal "1.3 diagnostic-code extracts 'S0001" 'S0001 (diagnostic-code diag1))
(assert-equal "1.4 diagnostic-span extracts span" test-span-1 (diagnostic-span diag1))
(assert-equal "1.5 diagnostic-message extracts message" "unbound variable 'calculate-pi'" (diagnostic-message diag1))
(assert-equal "1.6 initial labels is empty" '() (diagnostic-labels diag1))
(assert-equal "1.7 initial notes is empty" '() (diagnostic-notes diag1))
(assert-equal "1.8 initial help is empty" '() (diagnostic-help diag1))

;; Normalization: invalid level defaults to 'error
(define diag-norm (make-diagnostic 'invalid-level "C0042" #f "type mismatch"))
(assert-equal "1.9 invalid level normalized to 'error" 'error (diagnostic-level diag-norm))
(assert-equal "1.10 string code normalized to symbol" 'C0042 (diagnostic-code diag-norm))

;; Modifiers: add-label!, add-note!, add-help!
(diagnostic-add-label! diag1 test-span-1 "unbound variable")
(diagnostic-add-note! diag1 "check import list")
(diagnostic-add-help! diag1 "did you mean 'calculate-pi-approx'?")

(assert-equal "1.11 labels contains entry" 1 (length (diagnostic-labels diag1)))
(assert-equal "1.12 label text matches" "unbound variable" (cdr (car (diagnostic-labels diag1))))
(assert-equal "1.13 notes contains entry" 1 (length (diagnostic-notes diag1)))
(assert-equal "1.14 note text matches" "check import list" (car (diagnostic-notes diag1)))
(assert-equal "1.15 help contains entry" 1 (length (diagnostic-help diag1)))
(assert-equal "1.16 help text matches" "did you mean 'calculate-pi-approx'?" (car (diagnostic-help diag1)))

;;; -----------------------------------------------------------------------
;;; Group 2: Color Configuration & ANSI Control
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Color Configuration & ANSI Control ---\n")

(set-diagnostic-color-mode! 'never)
(assert-false "2.1 color disabled in 'never mode" (diagnostic-color-enabled?))

(set-diagnostic-color-mode! 'always)
(assert-true "2.2 color enabled in 'always mode" (diagnostic-color-enabled?))

(set-diagnostic-color-mode! 'auto)
(assert-equal "2.3 mode is 'auto" 'auto (diagnostic-color-mode))

;; Test string contains NO ANSI escape sequences in 'never mode
(set-diagnostic-color-mode! 'never)
(define plain-out (format-diagnostic diag1))

(define (contains-ansi-escape? str)
  (let ((len (string-length str)))
    (let loop ((i 0))
      (cond
        ((>= i len) #f)
        ((= (char->integer (string-ref str i)) 27) #t) ; ESC character 0x1b
        (else (loop (+ i 1)))))))

(assert-false "2.4 plain format output contains ZERO ANSI escapes" (contains-ansi-escape? plain-out))

;; Test string contains ANSI escape sequences in 'always mode
(set-diagnostic-color-mode! 'always)
(define color-out (format-diagnostic diag1))
(assert-true "2.5 color format output contains ANSI escapes" (contains-ansi-escape? color-out))

(set-diagnostic-color-mode! 'never) ; Restore 'never mode for deterministic string tests

;;; -----------------------------------------------------------------------
;;; Group 3: Source File Caching, Line Sanitization & DoS Guards
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Source File Caching & Line Sanitization ---\n")

(diagnostic-register-source-string!
 "test_sample.scm"
 "(define (foo x)\n  (+ x y)\n  (* x 2))")

(assert-equal "3.1 line 1 extracted correctly" "(define (foo x)" (diagnostic-get-source-line "test_sample.scm" 1))
(assert-equal "3.2 line 2 extracted correctly" "  (+ x y)" (diagnostic-get-source-line "test_sample.scm" 2))
(assert-equal "3.3 line 3 extracted correctly" "  (* x 2))" (diagnostic-get-source-line "test_sample.scm" 3))

;; Boundary conditions (THREAT-833-2)
(assert-false "3.4 line 0 returns #f" (diagnostic-get-source-line "test_sample.scm" 0))
(assert-false "3.5 negative line returns #f" (diagnostic-get-source-line "test_sample.scm" -1))
(assert-false "3.6 line exceeding file returns #f" (diagnostic-get-source-line "test_sample.scm" 999))
(assert-false "3.7 unknown file returns #f" (diagnostic-get-source-line "<unknown>" 1))

;; Control character sanitization (THREAT-833-3)
(define dirty-line (string-append "foo" (string (integer->char 7)) (string (integer->char 27)) "bar")) ; BEL + ESC
(define clean-line (sanitize-diagnostic-line-chars dirty-line))
(assert-false "3.8 sanitized line has no ESC" (contains-ansi-escape? clean-line))
(assert-equal "3.9 non-printable chars replaced by space" "foo  bar" clean-line)

;; Truncation of huge lines (THREAT-833-1)
(define huge-line (%diagnostic-make-string-fill 500 #\a))
(define truncated-line (truncate-diagnostic-line huge-line))
(assert-true "3.10 huge line truncated" (< (string-length truncated-line) 300))
(assert-true "3.11 truncated line ends with ellipsis" (string-ends-with? truncated-line " ..."))

;;; -----------------------------------------------------------------------
;;; Group 4: Visual Formatting, Caret Positioning & Underlines
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Visual Formatting & Caret Positioning ---\n")

(set-diagnostic-color-mode! 'never)

(define test-span-snippet (make-source-span "test_sample.scm" 2 6 2 6 #f 2)) ; pointing to 'y' in '(+ x y)'
(define diag-snippet (make-diagnostic 'error 'S0002 test-span-snippet "unbound variable 'y'"))
(diagnostic-add-label! diag-snippet test-span-snippet "unbound variable")

(define snippet-out (format-diagnostic diag-snippet))

;; Verify header format: error[S0002]: unbound variable 'y'
(assert-true "4.1 header line present" (string-starts-with? snippet-out "error[S0002]: unbound variable 'y'"))

;; Verify location pointer: --> test_sample.scm:2:6
(assert-true "4.2 location pointer present" (string-contains? snippet-out "--> test_sample.scm:2:6"))

;; Verify gutter and source line: 2 |   (+ x y)
(assert-true "4.3 gutter line present" (string-contains? snippet-out "2 |   (+ x y)"))

;; Verify caret pointing to 'y' at col 6: (col 1 is ' ', col 2 is ' ', col 3 is '(', col 4 is '+', col 5 is ' ', col 6 is 'x'...)
(assert-true "4.4 caret line contains ^" (string-contains? snippet-out "^"))
(assert-true "4.5 label text attached to caret" (string-contains? snippet-out "^ unbound variable"))

;;; -----------------------------------------------------------------------
;;; Group 5: Macro Expansion Trace & Provenance
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Macro Expansion Trace ---\n")

(define macro-def-span (make-source-span "macros.scm" 5 3 5 20 #f 10))
(define macro-call-span (make-source-span "test_sample.scm" 2 3 2 10 macro-def-span 11))
(define diag-macro (make-diagnostic 'error 'E0003 macro-call-span "expansion error in macro"))

(define macro-out (format-diagnostic diag-macro))
(assert-true "5.1 macro note header present" (string-contains? macro-out "= note: expanded from macro at macros.scm:5:3"))

;;; -----------------------------------------------------------------------
;;; Group 6: Similar Symbols & Fix-It Recommendations
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Similar Symbols & Fix-It Recommendations ---\n")

(define diag-help (make-diagnostic 'error 'S0004 test-span-snippet "unbound variable 'string-apend'"))
(diagnostic-add-help! diag-help "did you mean 'string-append'?")

(define help-out (format-diagnostic diag-help))
(assert-true "6.1 help suggestion present" (string-contains? help-out "= help: did you mean 'string-append'?"))

;;; -----------------------------------------------------------------------
;;; Group 7: Error & Warning Count Tracking
;;; -----------------------------------------------------------------------
(display "\n--- Group 7: Error & Warning Count Tracking ---\n")

(reset-diagnostic-state!)
(assert-equal "7.1 initial error count is 0" 0 (diagnostic-error-count))
(assert-equal "7.2 initial warning count is 0" 0 (diagnostic-warning-count))

(report-diagnostic (make-diagnostic 'error 'E1 #f "first error"))
(report-diagnostic (make-diagnostic 'error 'E2 #f "second error"))
(report-diagnostic (make-diagnostic 'warning 'W1 #f "first warning"))
(report-diagnostic (make-diagnostic 'note 'N1 #f "note does not increment"))

(assert-equal "7.3 error count is 2" 2 (diagnostic-error-count))
(assert-equal "7.4 warning count is 1" 1 (diagnostic-warning-count))

(reset-diagnostic-state!)
(assert-equal "7.5 reset clears error count" 0 (diagnostic-error-count))
(assert-equal "7.6 reset clears warning count" 0 (diagnostic-warning-count))

(test-end "Unified Pretty Diagnostic Reporter (Issue #833)")
