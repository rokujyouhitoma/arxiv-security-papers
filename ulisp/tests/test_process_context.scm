;;; =======================================================================
;;; Test Suite: test_process_context.scm
;;; Specification: R7RS-small Section 6.14 (System interface) & (scheme process-context)
;;; Conforms to Issue #611
;;; =======================================================================

(define *test-failures* (vector 0))

(define (test-pass name)
  (write-string "  [PASS] ")
  (write-string name)
  (write-char #\newline)
  (flush-output-port))

(define (test-fail name expected actual)
  (vector-set! *test-failures* 0 (+ (vector-ref *test-failures* 0) 1))
  (write-string "  [FAIL] ")
  (write-string name)
  (write-string " (expected: ")
  (write-string expected)
  (write-string ", got: ")
  (write-string actual)
  (write-string ")")
  (write-char #\newline)
  (flush-output-port))

(define (assert-true name expr)
  (if expr
      (test-pass name)
      (test-fail name "#t" "#f")))

(define (assert-false name expr)
  (if (not expr)
      (test-pass name)
      (test-fail name "#f" "#t")))

(define (lookup-env key alist)
  (let loop ((ls alist))
    (cond
      ((null? ls) #f)
      ((and (pair? (car ls)) (string=? (car (car ls)) key)) (car ls))
      (else (loop (cdr ls))))))

(write-string "=== Testing (scheme process-context) & R7RS 6.14 ===")
(write-char #\newline)

;;; 1. Single environment variable query (get-environment-variable)
(let ((path (get-environment-variable "PATH")))
  (assert-true "get-environment-variable PATH returns a string" (string? path))
  (assert-true "PATH is non-empty" (> (string-length path) 0)))

;; Non-existent variable
(assert-true "get-environment-variable returns #f for unknown var"
             (eq? (get-environment-variable "ULISP_NON_EXISTENT_VAR_123456789") #f))

;; Prefix match prevention: "PAT" should not match "PATH=..."
(assert-true "get-environment-variable PAT does not match PATH"
             (eq? (get-environment-variable "PAT") #f))

;; Non-string argument handling
(assert-true "get-environment-variable returns #f for symbol"
             (eq? (get-environment-variable 'PATH) #f))
(assert-true "get-environment-variable returns #f for number"
             (eq? (get-environment-variable 123) #f))

;;; 2. All environment variables query (get-environment-variables)
(let ((envs (get-environment-variables)))
  (assert-true "get-environment-variables returns a list" (pair? envs))
  (assert-true "first element of envs is a pair" (pair? (car envs)))
  (assert-true "first element key is a string" (string? (car (car envs))))
  (assert-true "first element value is a string" (string? (cdr (car envs))))

  ;; Lookup PATH in alist
  (let ((path-entry (lookup-env "PATH" envs)))
    (assert-true "PATH entry found in (get-environment-variables) alist" (pair? path-entry))
    (if (pair? path-entry)
        (let ((path-val (cdr path-entry))
              (direct-val (get-environment-variable "PATH")))
          (assert-true "PATH entry matches get-environment-variable result"
                       (string=? path-val direct-val)))))

  ;; Lookup unknown in alist
  (assert-false "unknown var not found in (get-environment-variables) alist"
                (lookup-env "ULISP_NON_EXISTENT_VAR_123456789" envs)))

;;; 3. Command line procedure (command-line)
(let ((cmd (command-line)))
  (assert-true "command-line returns a pair" (pair? cmd))
  (assert-true "car of command-line is a string" (string? (car cmd))))

;;; 4. Final report
(let ((fails (vector-ref *test-failures* 0)))
  (if (= fails 0)
      (begin
        (write-string "All (scheme process-context) tests passed successfully!")
        (write-char #\newline)
        (exit 0))
      (begin
        (write-string "Test failures detected: ")
        (sys-write-fixnum fails)
        (write-char #\newline)
        (exit 1))))
