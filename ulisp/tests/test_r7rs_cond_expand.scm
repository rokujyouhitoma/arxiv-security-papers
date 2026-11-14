;;; =======================================================================
;;; ULisp R7RS §4.2.1 / §5.5.1 cond-expand Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #658
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


;;; --- Test 1: Basic Standard Feature Identifiers ---
(write-string "--- Test 1: Standard Feature Identifiers ---\n")
(define val-r7rs
  (cond-expand
    (r7rs 'r7rs-supported)
    (else 'r7rs-unsupported)))
(test "cond-expand r7rs feature" 'r7rs-supported val-r7rs)

(define val-ulisp
  (cond-expand
    (ulisp 'ulisp-supported)
    (else 'ulisp-unsupported)))
(test "cond-expand ulisp feature" 'ulisp-supported val-ulisp)

(define val-endian
  (cond-expand
    (little-endian 'le)
    (big-endian 'be)
    (else 'unknown)))
(test "cond-expand little-endian feature" 'le val-endian)

(define val-neg-feat
  (cond-expand
    (windows 'windows-not-expected)
    (else 'non-windows)))
(test "cond-expand windows fallback else" 'non-windows val-neg-feat)

;;; --- Test 2: Logical Combinations (and, or, not) ---
(write-string "--- Test 2: Logical Combinations ---\n")
(define val-and
  (cond-expand
    ((and r7rs ulisp exact-closed) 'and-ok)
    (else 'and-fail)))
(test "cond-expand and expression" 'and-ok val-and)

(define val-or
  (cond-expand
    ((or windows non-existent-os linux) 'or-ok)
    (else 'or-fail)))
(test "cond-expand or expression" 'or-ok val-or)

(define val-not
  (cond-expand
    ((not windows) 'not-windows-ok)
    (else 'not-windows-fail)))
(test "cond-expand not expression" 'not-windows-ok val-not)

(define val-nested-logic
  (cond-expand
    ((and (or windows posix) (not big-endian) (and ulisp r7rs)) 'nested-ok)
    (else 'nested-fail)))
(test "cond-expand nested logical expression" 'nested-ok val-nested-logic)

;;; --- Test 3: Library Availability (library <name>) ---
(write-string "--- Test 3: Library Availability ---\n")
(define val-lib-base
  (cond-expand
    ((library (scheme base)) 'lib-base-ok)
    (else 'lib-base-fail)))
(test "cond-expand (library (scheme base))" 'lib-base-ok val-lib-base)

(define val-lib-nonexistent
  (cond-expand
    ((library (scheme non-existent-library-xyz)) 'should-not-match)
    (else 'lib-fallback-ok)))
(test "cond-expand nonexistent library fallback" 'lib-fallback-ok val-lib-nonexistent)

;;; --- Test 4: Top-level Multiple Expressions in Clause ---
(write-string "--- Test 4: Multiple Expressions in Clause ---\n")
(define *seq-box* (vector 0))
(cond-expand
  (ulisp
   (vector-set! *seq-box* 0 (+ (vector-ref *seq-box* 0) 10))
   (vector-set! *seq-box* 0 (+ (vector-ref *seq-box* 0) 20)))
  (else
   (vector-set! *seq-box* 0 999)))
(test "cond-expand multiple body expressions" 30 (vector-ref *seq-box* 0))

;;; --- Test 5: Inner Expression Context ---
(write-string "--- Test 5: Inner Expression Context ---\n")
(define (get-platform-tag)
  (cond-expand
    (posix "posix-platform")
    (else "unknown-platform")))
(test "cond-expand inside function body" "posix-platform" (get-platform-tag))

;;; --- Test 6: R7RS §6.14 (features) Procedure (Issue #705) ---
(write-string "--- Test 6: (features) Procedure ---\n")
(let ((feats (features)))
  (test "features returns a non-empty pair" #t (pair? feats))
  (test "features contains r7rs" #t (if (memq 'r7rs feats) #t #f))
  (test "features contains ulisp" #t (if (memq 'ulisp feats) #t #f))
  (test "features contains exact-closed" #t (if (memq 'exact-closed feats) #t #f))
  (test "features contains little-endian" #t (if (memq 'little-endian feats) #t #f))
  (test "features contains srfi-193" #t (if (memq 'srfi-193 feats) #t #f)))

;;; --- Test 7: R7RS §6.14 command-line & SRFI 193 (Issue #706) ---
(write-string "--- Test 7: command-line & SRFI 193 ---\n")
(let ((orig-cmd (command-line)))
  (test "command-line returns non-empty list" #t (pair? orig-cmd))
  (test "command-line first element is string" #t (string? (car orig-cmd)))
  (test "script-file default is #f" #f (script-file))
  (test "script-directory default is #f" #f (script-directory))
  (command-line '("/usr/local/bin/my-app.scm" "--flag" "arg1"))
  (test "command-name strips dir and .scm" "my-app" (command-name))
  (test "command-args returns tail args" '("--flag" "arg1") (command-args))
  (command-line '("" "a"))
  (test "command-name on empty arg0 returns #f" #f (command-name))
  (script-file "/workspace/scripts/run.scm")
  (test "script-file override returns path" "/workspace/scripts/run.scm" (script-file))
  (test "script-directory returns directory with trailing slash" "/workspace/scripts/" (script-directory))
  (script-file #f)
  (command-line orig-cmd))

