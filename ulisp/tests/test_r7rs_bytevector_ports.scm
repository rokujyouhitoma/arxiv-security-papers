;;; =======================================================================
;;; ULisp R7RS §6.13 Bytevector Ports and Ready Predicates Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #660
;;; =======================================================================

(define (equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (pair? a) (pair? b))
     (and (equal? (car a) (car b))
          (equal? (cdr a) (cdr b))))
    ((and (string? a) (string? b))
     (string=? a b))
    ((and (bytevector? a) (bytevector? b))
     (and (= (bytevector-length a) (bytevector-length b))
          (let loop ((i 0))
            (if (= i (bytevector-length a))
                #t
                (if (= (bytevector-u8-ref a i) (bytevector-u8-ref b i))
                    (loop (+ i 1))
                    #f)))))
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


;;; --- Test 1: open-input-bytevector ---
(write-string "--- Test 1: open-input-bytevector ---\n")
(define bv1 (make-bytevector 4 0))
(bytevector-u8-set! bv1 0 65)  ; 'A'
(bytevector-u8-set! bv1 1 66)  ; 'B'
(bytevector-u8-set! bv1 2 67)  ; 'C'
(bytevector-u8-set! bv1 3 10)  ; '\n'

(define in-p (open-input-bytevector bv1))
(test "port? on bytevector port" #t (port? in-p))
(test "input-port? on bytevector in-port" #t (input-port? in-p))
(test "output-port? on bytevector in-port" #f (output-port? in-p))
(test "binary-port? on bytevector in-port" #t (binary-port? in-p))
(test "port-open? on fresh in-port" #t (port-open? in-p))
(test "char-ready? on fresh in-port" #t (char-ready? in-p))
(test "u8-ready? on fresh in-port" #t (u8-ready? in-p))

(test "peek-u8 byte 0" 65 (peek-u8 in-p))
(test "read-u8 byte 0" 65 (read-u8 in-p))
(test "read-u8 byte 1" 66 (read-u8 in-p))
(test "peek-char char 2" #\C (peek-char in-p))
(test "read-char char 2" #\C (read-char in-p))
(test "read-char newline" #\newline (read-char in-p))
(test "read-u8 at EOF returns eof-object" #t (eof-object? (read-u8 in-p)))
(test "peek-char at EOF returns eof-object" #t (eof-object? (peek-char in-p)))
(test "char-ready? at EOF returns #t (R7RS §6.13.2)" #t (char-ready? in-p))

(close-port in-p)
(test "port-open? after close" #f (port-open? in-p))

;;; --- Test 2: open-output-bytevector & get-output-bytevector ---
(write-string "--- Test 2: open-output-bytevector ---\n")
(let ((out-p (open-output-bytevector)))
  (test "output-port? on bytevector out-port" #t (output-port? out-p))
  (test "input-port? on bytevector out-port" #f (input-port? out-p))
  (test "binary-port? on bytevector out-port" #t (binary-port? out-p))

  (write-u8 72 out-p)   ; 'H'
  (write-u8 101 out-p)  ; 'e'
  (write-u8 121 out-p)  ; 'y'
  (write-char #\! out-p) ; 33

  (let ((out-bv (get-output-bytevector out-p)))
    (test "get-output-bytevector length" 4 (bytevector-length out-bv))
    (test "byte 0" 72 (bytevector-u8-ref out-bv 0))
    (test "byte 1" 101 (bytevector-u8-ref out-bv 1))
    (test "byte 2" 121 (bytevector-u8-ref out-bv 2))
    (test "byte 3" 33 (bytevector-u8-ref out-bv 3))

    ;; Test dynamic buffer growth (> 64 bytes)
    (let loop ((i 0))
      (if (< i 100)
          (begin
            (write-u8 (modulo i 256) out-p)
            (loop (+ i 1)))
          #t))

    (let ((large-bv (get-output-bytevector out-p)))
      (test "large buffer growth length" 104 (bytevector-length large-bv))
      (test "large buffer byte at 103" 99 (bytevector-u8-ref large-bv 103))

      (close-output-port out-p)
      (test "output port closed" #f (port-open? out-p))))))

;;; --- Test 3: String Port Ready Predicates ---
(write-string "--- Test 3: String Port Ready Predicates ---\n")
(define str-p (open-input-string "hello"))
(test "char-ready? on string port" #t (char-ready? str-p))
(test "u8-ready? on string port" #t (u8-ready? str-p))
(read-char str-p)
(test "char-ready? on partially read string port" #t (char-ready? str-p))

