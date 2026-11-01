;;; =======================================================================
;;; ULisp Test Suite: R7RS §6.13 / §6.14 (scheme file) File Ports & Ops
;;; Conforms to Issue #651
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
  (write-string " (expected ")
  (write expected)
  (write-string ", got ")
  (write actual)
  (write-string ")")
  (write-char #\newline)
  (flush-output-port))

(define (test-equal? a b)
  (cond
    ((eqv? a b) #t)
    ((and (string? a) (string? b)) (string=? a b))
    ((and (pair? a) (pair? b))
     (and (test-equal? (car a) (car b))
          (test-equal? (cdr a) (cdr b))))
    (else #f)))

(define (assert-equal name actual expected)
  (if (test-equal? actual expected)
      (test-pass name)
      (test-fail name expected actual)))

(define (assert-true name cond)
  (if cond
      (test-pass name)
      (test-fail name #t #f)))

(define (assert-false name cond)
  (if (not cond)
      (test-pass name)
      (test-fail name #f #t)))

(define test-file-1 "/tmp/ulisp_test_file_1.txt")
(define test-file-2 "/tmp/ulisp_test_file_2.bin")
(define test-file-3 "/tmp/ulisp_test_file_3.txt")
(define test-file-4 "/tmp/ulisp_test_file_4.txt")

;; クリーンアップヘルパー
(define (cleanup-test-files!)
  (if (file-exists? test-file-1) (delete-file test-file-1))
  (if (file-exists? test-file-2) (delete-file test-file-2))
  (if (file-exists? test-file-3) (delete-file test-file-3))
  (if (file-exists? test-file-4) (delete-file test-file-4)))

(cleanup-test-files!)

;;; -----------------------------------------------------------------------
;;; Group 1: File Existence and Deletion (R7RS §6.14)
;;; -----------------------------------------------------------------------
(write-string "--- Group 1: File Existence and Deletion ---")
(write-char #\newline)

(assert-false "file-exists? on non-existent file"
              (file-exists? "/tmp/ulisp_non_existent_file_xyz_123.tmp"))

;; 一時ファイルを作成して存在チェック
(let ((out (open-output-file test-file-1)))
  (write-string "Hello, ULisp File!" out)
  (close-output-port out))

(assert-true "file-exists? on newly created file"
             (file-exists? test-file-1))

;; 削除して非存在チェック
(assert-true "delete-file returns #t"
             (delete-file test-file-1))

(assert-false "file-exists? after delete-file"
              (file-exists? test-file-1))

;;; -----------------------------------------------------------------------
;;; Group 2: Basic File I/O (open-output-file / open-input-file)
;;; -----------------------------------------------------------------------
(write-string "--- Group 2: Basic File I/O ---")
(write-char #\newline)

(let ((out (open-output-file test-file-1)))
  (assert-true "file-output-port? on open-output-file"
               (file-output-port? out))
  (assert-true "output-port? on file-output-port"
               (output-port? out))
  (assert-false "input-port? on file-output-port"
                (input-port? out))
  (assert-true "textual-port? on open-output-file"
               (textual-port? out))
  (assert-false "binary-port? on open-output-file"
                (binary-port? out))
  (assert-true "port-open? before close"
               (port-open? out))
  (write-string "Line 1: Hello World" out)
  (write-char #\newline out)
  (write-string "Line 2: Scheme R7RS" out)
  (write-char #\newline out)
  (flush-output-port out)
  (close-output-port out)
  (assert-false "port-open? after close"
                (port-open? out)))

(let ((in (open-input-file test-file-1)))
  (assert-true "file-input-port? on open-input-file"
               (file-input-port? in))
  (assert-true "input-port? on file-input-port"
               (input-port? in))
  (assert-false "output-port? on file-input-port"
                (output-port? in))
  (assert-true "textual-port? on open-input-file"
               (textual-port? in))
  (assert-false "binary-port? on open-input-file"
                (binary-port? in))
  (assert-true "port-open? before close (input)"
               (port-open? in))
  (assert-equal "read-line 1"
                (read-line in)
                "Line 1: Hello World")
  (assert-equal "read-line 2"
                (read-line in)
                "Line 2: Scheme R7RS")
  (assert-true "eof-object? at end of file"
               (eof-object? (read-char in)))
  (close-input-port in)
  (assert-false "port-open? after close (input)"
                (port-open? in)))

(delete-file test-file-1)

;;; -----------------------------------------------------------------------
;;; Group 3: Binary File Ports (open-binary-*-file)
;;; -----------------------------------------------------------------------
(write-string "--- Group 3: Binary File Ports ---")
(write-char #\newline)

(let ((out (open-binary-output-file test-file-2)))
  (assert-true "file-output-port? on binary output"
               (file-output-port? out))
  (assert-true "binary-port? on binary output"
               (binary-port? out))
  (assert-false "textual-port? on binary output"
                (textual-port? out))
  (write-u8 65 out) ; 'A'
  (write-u8 66 out) ; 'B'
  (write-u8 67 out) ; 'C'
  (close-port out))

(let ((in (open-binary-input-file test-file-2)))
  (assert-true "file-input-port? on binary input"
               (file-input-port? in))
  (assert-true "binary-port? on binary input"
               (binary-port? in))
  (assert-false "textual-port? on binary input"
                (textual-port? in))
  (assert-equal "read-u8 1" (read-u8 in) 65)
  (assert-equal "read-u8 2" (read-u8 in) 66)
  (assert-equal "read-u8 3" (read-u8 in) 67)
  (assert-true "read-u8 EOF" (eof-object? (read-u8 in)))
  (close-port in))

(delete-file test-file-2)

;;; -----------------------------------------------------------------------
;;; Group 4: High-Level Port Control (call-with-*-file)
;;; -----------------------------------------------------------------------
(write-string "--- Group 4: High-Level Port Control ---")
(write-char #\newline)

(call-with-output-file test-file-3
  (lambda (p)
    (write-string "Auto closed content" p)
    (write-char #\newline p)))

(assert-true "file-exists? after call-with-output-file"
             (file-exists? test-file-3))

(let ((res (call-with-input-file test-file-3
             (lambda (p)
               (read-line p)))))
  (assert-equal "call-with-input-file read content"
                res
                "Auto closed content"))

(delete-file test-file-3)

;;; -----------------------------------------------------------------------
;;; Group 5: Dynamic Current Port Redirection (with-*-file)
;;; -----------------------------------------------------------------------
(write-string "--- Group 5: Dynamic Current Port Redirection ---")
(write-char #\newline)

(with-output-to-file test-file-4
  (lambda ()
    (display "Redirected display line")
    (newline)
    (write 12345)
    (newline)))

(assert-true "file-exists? after with-output-to-file"
             (file-exists? test-file-4))

(with-input-from-file test-file-4
  (lambda ()
    (assert-equal "with-input-from-file read-line"
                  (read-line)
                  "Redirected display line")
    (assert-equal "with-input-from-file read S-exp"
                  (read)
                  12345)))

(delete-file test-file-4)

;;; -----------------------------------------------------------------------
;;; Group 6: Exception Safety and Auto-Close (RAII)
;;; -----------------------------------------------------------------------
(write-string "--- Group 6: Exception Safety and Auto-Close ---")
(write-char #\newline)

(define saved-port-cell (cons #f '()))

(guard (exc (else #t))
  (call-with-output-file test-file-1
    (lambda (p)
      (set-car! saved-port-cell p)
      (write-string "Partial write" p)
      (error "Simulated error during write"))))

(assert-false "port-open? is #f after exception in call-with-output-file"
              (port-open? (car saved-port-cell)))

(if (file-exists? test-file-1)
    (delete-file test-file-1))

;;; -----------------------------------------------------------------------
;;; Summary & Exit
;;; -----------------------------------------------------------------------
(write-string "=== ULisp R7RS (scheme file) Tests Completed: ")
(if (= (vector-ref *test-failures* 0) 0)
    (begin
      (write-string "ALL TESTS PASSED ===")
      (write-char #\newline)
      (flush-output-port)
      #t)
    (begin
      (write-string "FAILURES ENCOUNTERED ===")
      (write-char #\newline)
      (flush-output-port)
      (exit 1)))

