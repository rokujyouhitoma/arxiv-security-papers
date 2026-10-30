;;; =======================================================================
;;; ULisp S-Expression Reader EOF Syntax Error Diagnostic Test Suite
;;; Conforms to Issue #628 and DSN-33 Architecture Specification
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

(write-string "=== Running ULisp Reader EOF Diagnostic Test Suite (Issue #628) ===\n")

;; 1. Normal balanced reading
(write-string "--- Group 1: Normal Balanced Datum Reading ---\n")
(let ((p (open-input-string "(+ 1 2)")))
  (test "normal list" '(+ 1 2) (read p)))

(let ((p (open-input-string "")))
  (test "clean EOF at top level" #t (eof-object? (read p))))

(let ((p (open-input-string "   \n\t  ; comment\n")))
  (test "clean EOF after whitespace and comment" #t (eof-object? (read p))))

;; 2. Unclosed lists and pairs
(write-string "--- Group 2: Unclosed Lists & Pairs ---\n")
(let ((p (open-input-string "(")))
  (test "unclosed empty list"
        'caught
        (guard (e (else 'caught))
          (read p))))

(let ((p (open-input-string "(define (broken a b) (+ a b)")))
  (test "unclosed function definition"
        'caught
        (guard (e (else 'caught))
          (read p))))

(let ((p (open-input-string "((((1 2 3)))")))
  (test "deeply nested unclosed list"
        'caught
        (guard (e (else 'caught))
          (read p))))

(let ((p (open-input-string "(a . ")))
  (test "unclosed dotted pair tail"
        'caught
        (guard (e (else 'caught))
          (read p))))

;; 3. Unclosed String Literals
(write-string "--- Group 3: Unclosed String Literals ---\n")
(let ((p (open-input-string "\"unterminated string")))
  (test "unclosed string"
        'caught
        (guard (e (else 'caught))
          (read p))))

(let ((p (open-input-string "\"escaped \\\" quote but unclosed")))
  (test "unclosed string with escaped quotes"
        'caught
        (guard (e (else 'caught))
          (read p))))

;; 4. Unclosed Vector & Bytevector Literals
(write-string "--- Group 4: Unclosed Vectors & Bytevectors ---\n")
(let ((p (open-input-string "#(1 2 3")))
  (test "unclosed vector literal"
        'caught
        (guard (e (else 'caught))
          (read p))))

(let ((p (open-input-string "#u8(10 20 30")))
  (test "unclosed bytevector literal"
        'caught
        (guard (e (else 'caught))
          (read p))))

;; 5. Unclosed Quoting Syntax
(write-string "--- Group 5: Unclosed Quoting Syntax ---\n")
(let ((p (open-input-string "'")))
  (test "unclosed quote"
        'caught
        (guard (e (else 'caught))
          (read p))))

(let ((p (open-input-string "`")))
  (test "unclosed quasiquote"
        'caught
        (guard (e (else 'caught))
          (read p))))

(let ((p (open-input-string ",")))
  (test "unclosed unquote"
        'caught
        (guard (e (else 'caught))
          (read p))))

(let ((p (open-input-string ",@")))
  (test "unclosed unquote-splicing"
        'caught
        (guard (e (else 'caught))
          (read p))))

(write-string "=== All Reader EOF Diagnostic Tests Completed Successfully! ===\n")

