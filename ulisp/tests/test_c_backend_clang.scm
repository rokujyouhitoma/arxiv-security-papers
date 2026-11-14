;;; =======================================================================
;;; Unit Test Suite: ULisp Portable C99 Backend with Clang (macOS / Linux)
;;; Conforms to Issue #696, DSN-33, and DSN-33-02
;;; Tests C code generation, Clang compilation (-Wall -Wextra -Werror -pedantic),
;;; and native binary execution.
;;; =======================================================================

(use file.util)
(use srfi-1)
(use srfi-13)

(test-begin "ULisp C99 Backend Clang (macOS / Linux)")

(define *clang-cmd* "clang")

(define (command-available? cmd)
  (let* ((res (sys-system (string-append "which " cmd " > /dev/null 2>&1"))))
    (= res 0)))

(define *has-clang* (command-available? *clang-cmd*))

(assert-true "Clang compiler available" *has-clang*)

(define *test-counter* 0)
(define (next-test-id!)
  (set! *test-counter* (+ *test-counter* 1))
  *test-counter*)

(when *has-clang*
  ;; Helper to compile Scheme expr to C, build with Clang, and run
  (define (run-clang-c-test name expr env-vars)
    (let* ((tid (next-test-id!))
           (c-file (string-append "/tmp/ulisp_clang_" (number->string (sys-getpid)) "_" (number->string tid) ".c"))
           (bin-file (string-append "/tmp/ulisp_clang_" (number->string (sys-getpid)) "_" (number->string tid)))
           (out-file (string-append bin-file ".out"))
           (log-file (string-append bin-file ".compile.log"))
           (core (desugar-all expr))
           (opt (cp0-optimize core))
           (anf (anf-all opt))
           (clos (closure-convert anf))
           (lir (generate-lir clos)))
      ;; 1. Emit C file
      (with-output-to-file c-file
        (lambda ()
          (emit-c lir 'none)))

      ;; 2. Compile with Clang (-std=c99 -O2 -Wall -Wextra -Werror -pedantic)
      (let* ((compile-cmd (string-append *clang-cmd* " -std=c99 -O2 -Wall -Wextra -Werror -pedantic "
                                         c-file " -o " bin-file " > " log-file " 2>&1"))
             (compile-res (sys-system compile-cmd)))
        (when (not (= compile-res 0))
          (display (string-append "=== COMPILATION FAILED: " name " ===\n"))
          (when (file-exists? log-file)
            (display (file->string log-file))))
        (assert-true (string-append name " (Clang compilation successful)")
                     (and (= compile-res 0) (file-exists? bin-file)))

        ;; 3. Execute native binary
        (if (and (= compile-res 0) (file-exists? bin-file))
            (let* ((env-str (if (null? env-vars) "" (string-append (string-join env-vars " ") " ")))
                   (run-cmd (string-append env-str bin-file " > " out-file " 2>&1"))
                   (run-res (sys-system run-cmd))
                   (lines (if (file-exists? out-file) (file->string-list out-file) '()))
                   (result-str (if (null? lines) "" (string-join lines "\n"))))
              ;; Clean up temporary test files
              (when (file-exists? c-file) (sys-unlink c-file))
              (when (file-exists? bin-file) (sys-unlink bin-file))
              (when (file-exists? out-file) (sys-unlink out-file))
              (when (file-exists? log-file) (sys-unlink log-file))
              result-str)
            (begin
              (when (file-exists? c-file) (sys-unlink c-file))
              (when (file-exists? log-file) (sys-unlink log-file))
              "COMPILATION_FAILED")))))

  ;; Test 1: Basic integer arithmetic
  (let ((out (run-clang-c-test "integer arithmetic" '(let ((a 100) (b 23)) (- (+ a b) 3)) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Fixnum arithmetic returns 120" "120" (string-trim out)))

  ;; Test 2: Conditionals and Booleans
  (let ((out (run-clang-c-test "boolean true" '(if (< 10 20) #t #f) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Boolean comparison returns #t" "#t" (string-trim out)))
  (let ((out (run-clang-c-test "boolean false" '(if (> 10 20) #t #f) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Boolean comparison returns #f" "#f" (string-trim out)))

  ;; Test 3: Pair and List operations
  (let ((out (run-clang-c-test "pairs and lists" '(car (cdr (cons 1 (cons 2 (cons 3 '()))))) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "List cadr returns 2" "2" (string-trim out)))

  ;; Test 4: Closure generation and higher-order calls
  (let ((out (run-clang-c-test "closures" '((lambda (f x) (f (f x))) (lambda (n) (* n 2)) 5) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Closure call returns 20" "20" (string-trim out)))

  ;; Test 5: Recursion (Factorial)
  (let ((out (run-clang-c-test "recursion factorial" '(letrec ((fact (lambda (n) (if (<= n 1) 1 (* n (fact (- n 1))))))) (fact 6)) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Factorial of 6 returns 720" "720" (string-trim out)))

  ;; Test 6: String indexing and predicates
  (let ((out (run-clang-c-test "string indexing" '(let ((s "DarwinClang")) (string-ref s 0)) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "String-ref returns #\\D" "#\\D" (string-trim out)))

  ;; Test 7: Standard Output via write-string
  (let ((out (run-clang-c-test "standard output write-string" '(begin (write-string "Hello_Clang_macOS_ULisp\n") 999) '("ULISP_PRINT_RESULT=0"))))
    (assert-true "Output contains expected string" (string-contains out "Hello_Clang_macOS_ULisp")))

  ;; Test 8: Heap allocation and Cheney GC execution (mmap PROT_READ|PROT_WRITE)
  ;; Allocate 10,000 pairs in a loop to trigger memory management and allocation
  (let ((out (run-clang-c-test "heap allocation and GC"
                               '(letrec ((build-list (lambda (n acc)
                                                       (if (<= n 0)
                                                           (car acc)
                                                           (build-list (- n 1) (cons n acc))))))
                                  (build-list 10000 '()))
                               '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Heap allocation loop completes returning 1" "1" (string-trim out)))
)

(test-end "ULisp C99 Backend Clang (macOS / Linux)")
