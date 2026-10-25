;;; =======================================================================
;;; Unit Test Suite: R7RS include and Source Location Tracking
;;; Conforms to Issue #606 & Nanopass Architecture Quality Standard
;;; =======================================================================

(define *inc-tests-passed* 0)
(define *inc-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *inc-tests-passed* (+ *inc-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *inc-tests-failed* (+ *inc-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(define (assert-true label actual)
  (assert-equal label #t (if actual #t #f)))

(define (assert-false label actual)
  (assert-equal label #f (if actual #t #f)))

(display "\n=======================================================\n")
(display " Starting R7RS include & Source Location Unit Tests\n")
(display "=======================================================\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Source Location Structure & Helpers
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Source Location Structure & Helpers ---\n")

(define loc-sample '(%source-loc "lib/list.scm" 45 2 (define (foo x) x)))

(assert-true "1.1 source-loc? recognizes valid %source-loc" (source-loc? loc-sample))
(assert-false "1.2 source-loc? rejects normal pair" (source-loc? '(define (foo x) x)))
(assert-false "1.3 source-loc? rejects symbol" (source-loc? 'foo))

(assert-equal "1.4 source-loc-file extracts filename" "lib/list.scm" (source-loc-file loc-sample))
(assert-equal "1.5 source-loc-line extracts line number" 45 (source-loc-line loc-sample))
(assert-equal "1.6 source-loc-col extracts column number" 2 (source-loc-col loc-sample))
(assert-equal "1.7 source-loc-form extracts inner AST" '(define (foo x) x) (source-loc-form loc-sample))
(assert-equal "1.8 strip-source-loc unwraps annotated form" '(define (foo x) x) (strip-source-loc loc-sample))
(assert-equal "1.9 strip-source-loc preserves unannotated form" '(+ 1 2) (strip-source-loc '(+ 1 2)))

;;; -----------------------------------------------------------------------
;;; Group 2: Context State Management
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Context State Management ---\n")

(reset-compiler-context!)
(assert-equal "2.1 initial source file is none" 'none (current-source-file))
(assert-equal "2.2 initial source line is 0" 0 (current-source-line))
(assert-equal "2.3 initial source col is 0" 0 (current-source-col))

(set-current-source-file! "runtime/gc.scm")
(set-current-source-line! 120)
(set-current-source-col! 5)

(assert-equal "2.4 updated source file matches" "runtime/gc.scm" (current-source-file))
(assert-equal "2.5 updated source line matches" 120 (current-source-line))
(assert-equal "2.6 updated source col matches" 5 (current-source-col))

(reset-compiler-context!)
(assert-equal "2.7 reset clears source file" 'none (current-source-file))
(assert-equal "2.8 reset clears source line" 0 (current-source-line))
(assert-equal "2.9 reset clears source col" 0 (current-source-col))

;;; -----------------------------------------------------------------------
;;; Group 3: Top-level rewrite-top-level unwrapping & context promotion
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: rewrite-top-level Integration ---\n")

(reset-compiler-context!)
(define test-forms
  (list (list '%source-loc "lib/test.scm" 10 1 '(define (square x) (* x x)))
        (list '%source-loc "lib/test.scm" 15 1 '(define (cube x) (* x (square x))))))

(define p-res (rewrite-top-level test-forms))
(assert-true "3.1 returns %program structure" (and (pair? p-res) (eq? (car p-res) '%program)))
(assert-equal "3.2 last processed source file is recorded" "lib/test.scm" (current-source-file))
(assert-equal "3.3 last processed source line is recorded" 15 (current-source-line))

;;; -----------------------------------------------------------------------
;;; Group 4: Path Traversal & Security Guard
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Path Traversal & Security Guard ---\n")

(assert-true "4.1 path-traversal? detects leading slash" (path-traversal? "/etc/passwd"))
(assert-true "4.2 path-traversal? detects ../ in path" (path-traversal? "../../secret.key"))
(assert-true "4.3 path-traversal? detects nested ../" (path-traversal? "foo/../../../bar.scm"))
(assert-false "4.4 path-traversal? allows safe relative path" (path-traversal? "lib/list.scm"))
(assert-false "4.5 path-traversal? allows dotted filename" (path-traversal? "lib/file.test.scm"))

;;; -----------------------------------------------------------------------
;;; Group 5: R7RS include syntax detection & expansion
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: R7RS include Syntax Detection ---\n")

(assert-true "5.1 include-form? detects (include ...)" (include-form? '(include "foo.scm")))
(assert-true "5.2 include-form? detects (include-ci ...)" (include-form? '(include-ci "foo.scm")))
(assert-false "5.3 include-form? rejects non-include pair" (include-form? '(define x 1)))
(assert-false "5.4 include-form? rejects symbol" (include-form? 'include))

;;; -----------------------------------------------------------------------
;;; Summary
;;; -----------------------------------------------------------------------
(display "\n=======================================================\n")
(display " R7RS include & Source Location Tests Summary:\n")
(display "   Passed: ") (display *inc-tests-passed*) (newline)
(display "   Failed: ") (display *inc-tests-failed*) (newline)
(display "=======================================================\n\n")

(if (> *inc-tests-failed* 0)
    (error "Unit tests failed!" *inc-tests-failed*)
    #t)
