;;; =======================================================================
;;; ULisp R7RS String Ports Test Suite (R7RS Section 6.13)
;;; Conforms to DSN-33 Architecture Specification & Issue #534
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

(write-string "=== Running ULisp R7RS String Ports Test Suite ===\n")

;;; --- Test 1: Port Predicates ---
(write-string "--- Test 1: Port Predicates ---\n")
(let ((in-p (open-input-string "sample"))
      (out-p (open-output-string)))
  (test "port? on input port" #t (port? in-p))
  (test "port? on output port" #t (port? out-p))
  (test "port? on stdin" #t (port? (current-input-port)))
  (test "port? on stdout" #t (port? (current-output-port)))
  (test "port? on non-port" #f (port? "not-a-port"))
  (test "port? on number" #f (port? 42))

  (test "input-port? on in-p" #t (input-port? in-p))
  (test "input-port? on out-p" #f (input-port? out-p))
  (test "input-port? on stdin" #t (input-port? (current-input-port)))
  (test "input-port? on stdout" #f (input-port? (current-output-port)))

  (test "output-port? on in-p" #f (output-port? in-p))
  (test "output-port? on out-p" #t (output-port? out-p))
  (test "output-port? on stdin" #f (output-port? (current-input-port)))
  (test "output-port? on stdout" #t (output-port? (current-output-port)))

  (test "textual-port? on in-p" #t (textual-port? in-p))
  (test "textual-port? on out-p" #t (textual-port? out-p))
  (test "binary-port? on in-p" #f (binary-port? in-p))
  (test "port-open? on in-p" #t (port-open? in-p))
  (test "close-port on in-p" #t (close-port in-p))
  (test "close-output-port on out-p" #t (close-output-port out-p)))

;;; --- Test 2: Basic String Input Port Characters ---
(write-string "--- Test 2: Character-level Input Port ---\n")
(let ((p (open-input-string "Hi!")))
  (test "peek first char" #\H (peek-char p))
  (test "read first char" #\H (read-char p))
  (test "peek second char" #\i (peek-char p))
  (test "read second char" #\i (read-char p))
  (test "read third char" #\! (read-char p))
  (test "read at EOF" #t (eof-object? (read-char p)))
  (test "peek at EOF" #t (eof-object? (peek-char p))))

;;; --- Test 3: String Output Port Writing & Extraction ---
(write-string "--- Test 3: Basic String Output Port ---\n")
(let ((p (open-output-string)))
  (write-char #\A p)
  (write-char #\B p)
  (write-char #\C p)
  (test "accumulated ABC" "ABC" (get-output-string p))
  (write-string " 123" p)
  (test "accumulated ABC 123" "ABC 123" (get-output-string p)))

;;; --- Test 4: Formatted Output (display, write, newline) ---
(write-string "--- Test 4: Formatted Output to Port ---\n")
(let ((p (open-output-string)))
  (display "hello" p)
  (test "display hello" "hello" (get-output-string p)))

(let ((p (open-output-string)))
  (write "hello" p)
  (test "write quoted hello" "\"hello\"" (get-output-string p)))

(let ((p (open-output-string)))
  (display '(1 2 3) p)
  (newline p)
  (display 42 p)
  (test "formatted list and number" "(1 2 3)\n42" (get-output-string p)))

;;; --- Test 5: S-expression Parsing from Input String ---
(write-string "--- Test 5: S-expression Parsing (read) ---\n")
(test "read fixnum" 42 (read (open-input-string "42")))
(test "read negative" -99 (read (open-input-string "-99")))
(test "read symbol" 'foo (read (open-input-string "foo")))
(test "read simple list" '(+ 1 2) (read (open-input-string "(+ 1 2)")))
(test "read nested list" '(define (sq x) (* x x))
      (read (open-input-string "(define (sq x) (* x x))")))
(test "read quoted expr" '(quote (a b))
      (read (open-input-string "'(a b)")))
(test "read string literal" "embedded string"
      (read (open-input-string "\"embedded string\"")))

;;; Multi-datum reading from a single port
(let ((p (open-input-string "10 20 30")))
  (test "multi-read item 1" 10 (read p))
  (test "multi-read item 2" 20 (read p))
  (test "multi-read item 3" 30 (read p))
  (test "multi-read at EOF" #t (eof-object? (read p))))

;;; --- Test 6: Dynamic Output Buffer Growth ---
(write-string "--- Test 6: Output Buffer Dynamic Growth (> 64 chars) ---\n")
(let ((p (open-output-string)))
  (let loop ((i 0))
    (if (< i 200)
        (begin
          (write-char #\x p)
          (loop (+ i 1)))
        #t))
  (let ((res (get-output-string p)))
    (test "length of grown buffer is 200" 200 (string-length res))
    (test "first char is x" #\x (string-ref res 0))
    (test "last char is x" #\x (string-ref res 199))))

;;; --- Test 7: 10,000 Consecutive In-memory Read Iterations ---
(write-string "--- Test 7: 10,000 In-memory Read Iterations ---\n")
(let ((res
       (let loop ((i 0) (sum 0))
         (if (< i 10000)
             (let* ((p (open-input-string "(+ 1 2)"))
                    (form (read p)))
               (if (equal? form '(+ 1 2))
                   (loop (+ i 1) (+ sum 1))
                   (loop (+ i 1) sum)))
             sum))))
  (test "10,000 read iterations sum" 10000 res))

;;; --- Test 8: Issue #628 S-expression Reader EOF Diagnostics ---
(write-string "--- Test 8: Reader EOF Syntax Error Diagnostics (Issue #628) ---\n")
(let ((p (open-input-string "(1 2 3")))
  (test "unclosed list raises error"
        'caught-eof-error
        (guard (e (else 'caught-eof-error))
          (read p))))

(let ((p (open-input-string "\"unclosed string")))
  (test "unclosed string raises error"
        'caught-eof-str
        (guard (e (else 'caught-eof-str))
          (read p))))

(let ((p (open-input-string "#(1 2 3")))
  (test "unclosed vector literal raises error"
        'caught-eof-vec
        (guard (e (else 'caught-eof-vec))
          (read p))))

(let ((p (open-input-string "'")))
  (test "unclosed quote raises error"
        'caught-eof-quote
        (guard (e (else 'caught-eof-quote))
          (read p))))

(write-string "=== All R7RS String Ports Tests Completed Successfully! ===\n")
