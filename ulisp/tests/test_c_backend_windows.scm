;;; =======================================================================
;;; Unit Test Suite: ULisp Portable C99 Backend for Windows (MinGW/Wine)
;;; Conforms to Issue #695, DSN-33, and DSN-33-02
;;; Tests C code generation, MinGW compilation, and Wine64 execution.
;;; =======================================================================

(use file.util)
(use srfi-1)
(use srfi-13)

(test-begin "ULisp C99 Backend Windows (MinGW/Wine)")

(define *mingw-gcc* "x86_64-w64-mingw32-gcc")
(define *wine-cmd* "wine64")

(define (command-available? cmd)
  (let* ((res (sys-system (string-append "which " cmd " > /dev/null 2>&1"))))
    (= res 0)))

(define *has-mingw-and-wine*
  (and (command-available? *mingw-gcc*)
       (command-available? *wine-cmd*)))

(assert-true "MinGW cross-compiler and Wine64 available" *has-mingw-and-wine*)

(define *test-counter* 0)
(define (next-test-id!)
  (set! *test-counter* (+ *test-counter* 1))
  *test-counter*)

(when *has-mingw-and-wine*
  ;; Helper to compile Scheme expr to C, build with MinGW, and run with Wine
  (define (run-windows-c-test name expr env-vars)
    (let* ((tid (next-test-id!))
           (c-file (string-append "/tmp/ulisp_win_" (number->string (sys-getpid)) "_" (number->string tid) ".c"))
           (exe-file (string-append "/tmp/ulisp_win_" (number->string (sys-getpid)) "_" (number->string tid) ".exe"))
           (out-file (string-append exe-file ".out"))
           (log-file (string-append exe-file ".compile.log"))
           (core (desugar-all expr))
           (opt (cp0-optimize core))
           (anf (anf-all opt))
           (clos (closure-convert anf))
           (lir (generate-lir clos)))
      ;; 1. Emit C file
      (with-output-to-file c-file
        (lambda ()
          (emit-c lir 'none)))

      ;; 2. Compile with MinGW-w64 (-Wall -Wextra -Werror)
      (let* ((compile-cmd (string-append *mingw-gcc* " -O2 -Wall -Wextra -Werror "
                                         c-file " -o " exe-file " > " log-file " 2>&1"))
             (compile-res (sys-system compile-cmd)))
        (when (not (= compile-res 0))
          (display (string-append "=== COMPILATION FAILED: " name " ===\n"))
          (when (file-exists? log-file)
            (display (file->string log-file))))
        (assert-true (string-append name " (MinGW compilation successful)")
                     (and (= compile-res 0) (file-exists? exe-file)))

        ;; 3. Execute with Wine64
        (if (and (= compile-res 0) (file-exists? exe-file))
            (let* ((env-str (if (null? env-vars) "" (string-append (string-join env-vars " ") " ")))
                   (run-cmd (string-append env-str "WINEDEBUG=-all " *wine-cmd* " " exe-file " > " out-file " 2>&1"))
                   (run-res (sys-system run-cmd))
                   (lines (if (file-exists? out-file) (file->string-list out-file) '()))
                   ;; Filter out Wine initialization or fixme lines
                   (filtered-lines (remove (lambda (line)
                                             (or (string-prefix? "wine:" line)
                                                 (string-contains line "fixme:")
                                                 (string-contains line "err:")))
                                           lines))
                   (result-str (if (null? filtered-lines) "" (string-join filtered-lines "\n"))))
              ;; Clean up temporary test files
              (when (file-exists? c-file) (sys-unlink c-file))
              (when (file-exists? exe-file) (sys-unlink exe-file))
              (when (file-exists? out-file) (sys-unlink out-file))
              (when (file-exists? log-file) (sys-unlink log-file))
              result-str)
            (begin
              (when (file-exists? c-file) (sys-unlink c-file))
              (when (file-exists? log-file) (sys-unlink log-file))
              "COMPILATION_FAILED")))))

  ;; Test 1: Basic integer arithmetic
  (let ((out (run-windows-c-test "integer arithmetic" '(let ((a 100) (b 23)) (- (+ a b) 3)) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Fixnum arithmetic returns 120" "120" (string-trim out)))

  ;; Test 2: Conditionals and Booleans
  (let ((out (run-windows-c-test "boolean true" '(if (< 10 20) #t #f) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Boolean comparison returns #t" "#t" (string-trim out)))
  (let ((out (run-windows-c-test "boolean false" '(if (> 10 20) #t #f) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Boolean comparison returns #f" "#f" (string-trim out)))

  ;; Test 3: Pair and List operations
  (let ((out (run-windows-c-test "pairs and lists" '(car (cdr (cons 1 (cons 2 (cons 3 '()))))) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "List cadr returns 2" "2" (string-trim out)))

  ;; Test 4: Closure generation and higher-order calls
  (let ((out (run-windows-c-test "closures" '((lambda (f x) (f (f x))) (lambda (n) (* n 2)) 5) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Closure call returns 20" "20" (string-trim out)))

  ;; Test 5: Recursion (Factorial)
  (let ((out (run-windows-c-test "recursion factorial" '(letrec ((fact (lambda (n) (if (<= n 1) 1 (* n (fact (- n 1))))))) (fact 6)) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Factorial of 6 returns 720" "720" (string-trim out)))

  ;; Test 6: String indexing and predicates
  (let ((out (run-windows-c-test "string indexing" '(let ((s "Windows")) (string-ref s 0)) '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "String-ref returns #\\W" "#\\W" (string-trim out)))

  ;; Test 7: Standard Output binary mode integrity via write-string
  (let ((out (run-windows-c-test "standard output write-string" '(begin (write-string "Hello_Windows_ULisp\n") 999) '("ULISP_PRINT_RESULT=0"))))
    (assert-true "Output contains expected string" (string-contains out "Hello_Windows_ULisp")))

  ;; Test 8: Heap allocation and Cheney GC execution on Windows (VirtualAlloc)
  ;; Allocate 10,000 pairs in a loop to trigger memory management and allocation
  (let ((out (run-windows-c-test "heap allocation and GC"
                                '(letrec ((build-list (lambda (n acc)
                                                        (if (<= n 0)
                                                            (car acc)
                                                            (build-list (- n 1) (cons n acc))))))
                                   (build-list 10000 '()))
                                '("ULISP_PRINT_RESULT=1"))))
    (assert-equal "Heap allocation loop completes returning 1" "1" (string-trim out)))
)

(test-end "ULisp C99 Backend Windows (MinGW/Wine)")
