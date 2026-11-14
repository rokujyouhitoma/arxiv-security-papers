;;; =======================================================================
;;; ULisp Test Suite: R7RS §6.12 Environment Specifiers (Issue #716)
;;; =======================================================================

(define *pass-count* (cons 0 '()))
(define *fail-count* (cons 0 '()))

(define (assert-true name cond)
  (if cond
      (begin
        (set-car! *pass-count* (+ (car *pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline)
        (flush-output-port))
      (begin
        (set-car! *fail-count* (+ (car *fail-count*) 1))
        (display "  [FAIL] ")
        (display name)
        (newline)
        (flush-output-port))))

(define (assert-equal name expected actual)
  (if (equal? expected actual)
      (begin
        (set-car! *pass-count* (+ (car *pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline)
        (flush-output-port))
      (begin
        (set-car! *fail-count* (+ (car *fail-count*) 1))
        (display "  [FAIL] ")
        (display name)
        (display " (expected ")
        (write expected)
        (display ", got ")
        (write actual)
        (display ")")
        (newline)
        (flush-output-port))))

(newline)

;; 1. environment? Predicate and Constructors
(let ((env-base (environment '(scheme base)))
      (env-inex (environment '(scheme inexact)))
      (env-comp (environment '(scheme complex)))
      (null-env (null-environment 5))
      (rep-env  (scheme-report-environment 5))
      (inter-env (interaction-environment)))
  (assert-true "environment? on (environment '(scheme base))" (environment? env-base))
  (assert-true "environment? on (environment '(scheme inexact))" (environment? env-inex))
  (assert-true "environment? on (environment '(scheme complex))" (environment? env-comp))
  (assert-true "environment? on (null-environment 5)" (environment? null-env))
  (assert-true "environment? on (scheme-report-environment 5)" (environment? rep-env))
  (assert-true "environment? on (interaction-environment)" (environment? inter-env))
  (assert-true "not environment? on #t" (not (environment? #t)))
  (assert-true "not environment? on vector #(1 2 3)" (not (environment? #(1 2 3))))

  ;; 2. Bound variable inspection
  (assert-true "+ is bound in (scheme base)" (%r7rs-env-bound? env-base '+))
  (assert-true "car is bound in (scheme base)" (%r7rs-env-bound? env-base 'car))
  (assert-true "not sin bound in (scheme base)" (not (%r7rs-env-bound? env-base 'sin)))
  (assert-true "sin is bound in (scheme inexact)" (%r7rs-env-bound? env-inex 'sin))
  (assert-true "make-rectangular is bound in (scheme complex)" (%r7rs-env-bound? env-comp 'make-rectangular))

  ;; 3. null-environment & scheme-report-environment
  (assert-true "lambda is in null-env" (%r7rs-env-bound? null-env 'lambda))
  (assert-true "+ is not in null-env" (not (%r7rs-env-bound? null-env '+)))
  (assert-true "+ is in scheme-report-environment" (%r7rs-env-bound? rep-env '+))
  (assert-true "sin is in scheme-report-environment" (%r7rs-env-bound? rep-env 'sin))

  ;; 4. interaction-environment mutability
  (assert-true "interaction-environment is mutable" (%r7rs-env-mutable? inter-env))
  (assert-true "environment '(scheme base) is immutable" (not (%r7rs-env-mutable? env-base)))
  (assert-true "null-environment is immutable" (not (%r7rs-env-mutable? null-env)))

  (%r7rs-env-define! inter-env 'my-test-var 42)
  (assert-true "my-test-var bound in interaction-env" (%r7rs-env-bound? inter-env 'my-test-var))
  (assert-equal "my-test-var value lookup" 42 (%r7rs-env-lookup inter-env 'my-test-var))
  (%r7rs-env-set! inter-env 'my-test-var 100)
  (assert-equal "my-test-var value set!" 100 (%r7rs-env-lookup inter-env 'my-test-var)))

;; 5. Import Set Modifiers: only, except, prefix, rename
(let ((env-only (environment '(only (scheme base) + - *)))
      (env-except (environment '(except (scheme base) + -)))
      (env-pref (environment '(prefix (scheme base) base:)))
      (env-ren  (environment '(rename (scheme base) (+ plus) (* times)))))
  (assert-true "+ is in env-only" (%r7rs-env-bound? env-only '+))
  (assert-true "- is in env-only" (%r7rs-env-bound? env-only '-))
  (assert-true "* is in env-only" (%r7rs-env-bound? env-only '*))
  (assert-true "car is NOT in env-only" (not (%r7rs-env-bound? env-only 'car)))

  (assert-true "+ is NOT in env-except" (not (%r7rs-env-bound? env-except '+)))
  (assert-true "- is NOT in env-except" (not (%r7rs-env-bound? env-except '-)))
  (assert-true "* is in env-except" (%r7rs-env-bound? env-except '*))
  (assert-true "car is in env-except" (%r7rs-env-bound? env-except 'car))

  (assert-true "base:+ is in env-pref" (%r7rs-env-bound? env-pref 'base:+))
  (assert-true "base:car is in env-pref" (%r7rs-env-bound? env-pref 'base:car))
  (assert-true "+ is NOT in env-pref" (not (%r7rs-env-bound? env-pref '+)))

  (assert-true "plus is in env-ren" (%r7rs-env-bound? env-ren 'plus))
  (assert-true "times is in env-ren" (%r7rs-env-bound? env-ren 'times))
  (assert-true "+ is NOT in env-ren" (not (%r7rs-env-bound? env-ren '+)))
  (assert-true "- is in env-ren" (%r7rs-env-bound? env-ren '-)))

;; 6. Invocation of looked-up procedures
(let* ((env (environment '(scheme base)))
       (plus-fn (%r7rs-env-lookup env '+))
       (cons-fn (%r7rs-env-lookup env 'cons)))
  (assert-equal "(+ 10 20 30) via lookup" 60 (plus-fn 10 20 30))
  (assert-equal "(cons 1 2) via lookup" '(1 . 2) (cons-fn 1 2)))

;; -----------------------------------------------------------------------
;; 7. R7RS §6.12 (scheme eval) Metacircular Dynamic Evaluation (Issue #717)
;; -----------------------------------------------------------------------
(flush-output-port)

(let ((base-env (environment '(scheme base)))
      (inter-env (interaction-environment)))

  ;; 7.1 Self-evaluating literals & quote
  (assert-equal "eval literal fixnum" 42 (eval 42 base-env))
  (assert-equal "eval literal string" "hello" (eval "hello" base-env))
  (assert-equal "eval literal boolean" #t (eval #t base-env))
  (assert-equal "eval literal char" #\a (eval #\a base-env))
  (assert-equal "eval quote" '(1 2 (3 4)) (eval '(quote (1 2 (3 4))) base-env))

  ;; 7.2 Variable lookup and core arithmetic
  (assert-equal "eval (+ 1 2 3 4)" 10 (eval '(+ 1 2 3 4) base-env))
  (assert-equal "eval (* (- 10 2) (/ 12 3))" 32 (eval '(* (- 10 2) (/ 12 3)) base-env))

  ;; 7.3 lambda abstractions and closures
  (assert-equal "eval simple lambda" 42 (eval '((lambda (x) (* x 2)) 21) base-env))
  (assert-equal "eval multi-arg lambda" 15 (eval '((lambda (a b c) (+ a b c)) 4 5 6) base-env))
  (assert-equal "eval dotted rest lambda" '(1 2 3 4) (eval '((lambda (x . rest) (cons x rest)) 1 2 3 4) base-env))
  (assert-equal "eval single rest symbol lambda" 3 (eval '((lambda args (length args)) 'a 'b 'c) base-env))

  ;; 7.4 case-lambda in eval
  (let ((cl-expr '((case-lambda
                     ((x) (* x 10))
                     ((x y) (+ x y))
                     ((x y . rest) (cons (+ x y) rest)))
                   3 4 5 6)))
    (assert-equal "eval case-lambda rest match" '(7 5 6) (eval cl-expr base-env)))

  ;; 7.5 Conditionals: if, cond, case, and, or, when, unless
  (assert-equal "eval if true" 'yes (eval '(if (= 1 1) 'yes 'no) base-env))
  (assert-equal "eval if false" 'no (eval '(if (= 1 2) 'yes 'no) base-env))
  (assert-equal "eval cond" 200 (eval '(cond ((= 1 2) 100) ((= 2 2) 200) (else 300)) base-env))
  (assert-equal "eval cond =>" 84 (eval '(cond ((+ 20 22) => (lambda (v) (* v 2)))) base-env))
  (assert-equal "eval case matching" 'composite (eval '(case (* 2 3) ((2 3 5) 'prime) ((4 6 8 9) 'composite) (else 'other)) base-env))
  (assert-equal "eval and" 42 (eval '(and 1 2 42) base-env))
  (assert-equal "eval and short-circuit" #f (eval '(and 1 #f 42) base-env))
  (assert-equal "eval or" 10 (eval '(or #f 10 #f) base-env))
  (assert-equal "eval when" 99 (eval '(when #t 99) base-env))
  (assert-equal "eval unless" 77 (eval '(unless #f 77) base-env))

  ;; 7.6 Local bindings: let, let*, letrec, letrec*, named let
  (assert-equal "eval let" 30 (eval '(let ((x 10) (y 20)) (+ x y)) base-env))
  (assert-equal "eval let*" 60 (eval '(let* ((x 10) (y (+ x 5)) (z (* y 4))) z) base-env))
  (assert-equal "eval named let tail recursion" 55
                (eval '(let loop ((n 10) (acc 0))
                         (if (= n 0)
                             acc
                             (loop (- n 1) (+ acc n))))
                      base-env))
  (assert-equal "eval letrec mutual recursion" #t
                (eval '(letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1)))))
                                (odd?  (lambda (n) (if (= n 0) #f (even? (- n 1))))))
                         (even? 10))
                      base-env))

  ;; 7.7 Quasiquotation with unquote and unquote-splicing
  (assert-equal "eval quasiquote" '(+ 1 5 4 5)
                (eval '(quasiquote (+ 1 (unquote (+ 2 3)) (unquote-splicing (list 4 5))))
                      base-env))

  ;; 7.8 Do loop
  (assert-equal "eval do loop" 55
                (eval '(do ((i 0 (+ i 1))
                            (sum 0 (+ sum i)))
                           ((> i 10) sum))
                      base-env))

  ;; 7.9 Multiple values: define-values, let-values, call-with-values
  (assert-equal "eval call-with-values" 60
                (eval '(call-with-values (lambda () (values 10 20 30))
                                         (lambda (a b c) (+ a b c)))
                      base-env))
  (assert-equal "eval let-values" 33
                (eval '(let-values (((q r) (values 30 3)))
                         (+ q r))
                      base-env))

  ;; 7.10 Dynamic mutations in interaction-environment
  (eval '(define dynamic-x 10) inter-env)
  (assert-equal "eval dynamic define" 10 (eval 'dynamic-x inter-env))
  (eval '(set! dynamic-x 25) inter-env)
  (assert-equal "eval dynamic set!" 25 (eval 'dynamic-x inter-env))
  (eval '(define (dynamic-square x) (* x x)) inter-env)
  (assert-equal "eval dynamic function define & call" 144 (eval '(dynamic-square 12) inter-env))

  ;; 7.11 Higher-order host interop: passing eval closure to host map
  (let ((host-map-fn (%r7rs-env-lookup base-env 'map))
        (evaled-fn (eval '(lambda (x) (+ x 100)) base-env)))
    (assert-equal "host map with eval closure" '(101 102 103) (host-map-fn evaled-fn '(1 2 3))))

  ;; 7.12 Continuation & Exception
  (assert-equal "eval call/cc escape" 42
                (eval '(call/cc (lambda (k) (+ 100 (k 42)))) base-env))
  (assert-equal "eval guard exception handling" 142
                (eval '(guard (ex ((number? ex) (+ ex 100))) (raise 42)) base-env))

  ;; 7.13 Immutable environment protection
  (assert-true "eval define in immutable env fails"
               (guard (ex ((error-object? ex) #t))
                 (eval '(define forbidden 1) base-env)
                 #f)))

;; -----------------------------------------------------------------------
;; 8. R7RS §6.14 (scheme load) and (scheme repl) Dynamic File Loading (Issue #718)
;; -----------------------------------------------------------------------
(flush-output-port)

(let ((test-filename "build/test_tmp_load_script.scm"))
  (if (file-exists? test-filename)
      (delete-file test-filename))
  ;; Create temporary script
  (let ((out (open-output-file test-filename)))
    (write-string ";; Dynamic load test script\n" out)
    (write-string "(define loaded-const 888)\n" out)
    (write-string "(define (loaded-adder a b) (+ a b (* loaded-const 2)))\n" out)
    (close-port out))

  (assert-true "test script file exists" (file-exists? test-filename))

  ;; 8.1 Load into default interaction-environment
  (load test-filename)
  (assert-equal "eval loaded variable from interaction-environment" 888 (eval 'loaded-const (interaction-environment)))
  (assert-equal "eval loaded function from interaction-environment" 1806 (eval '(loaded-adder 10 20) (interaction-environment)))

  ;; 8.2 Load with explicit environment specifier
  (load test-filename (interaction-environment))
  (assert-equal "eval loaded variable after explicit env load" 888 (eval 'loaded-const (interaction-environment)))

  ;; 8.3 Error handling on non-existent file
  (assert-true "load non-existent file raises error"
               (guard (ex ((error-object? ex) #t))
                 (load "build/non_existent_file_path_12345.scm")
                 #f))

  ;; 8.4 Error handling on invalid filename type
  (assert-true "load with non-string filename raises error"
               (guard (ex ((error-object? ex) #t))
                 (load 99999)
                 #f))

  ;; 8.5 Error handling on invalid environment specifier
  (assert-true "load with invalid environment specifier raises error"
               (guard (ex ((error-object? ex) #t))
                 (load test-filename 'invalid-env)
                 #f))

  ;; Cleanup
  (if (file-exists? test-filename)
      (delete-file test-filename)))

;; -----------------------------------------------------------------------
;; 9. R7RS §7.1.16 (scheme r5rs) Full Compatibility Library (Issue #718)
;; -----------------------------------------------------------------------
(flush-output-port)

(let ((r5rs-env (environment '(scheme r5rs))))
  (assert-true "r5rs-env is valid environment" (environment? r5rs-env))
  (assert-true "+ is bound in (scheme r5rs)" (%r7rs-env-bound? r5rs-env '+))
  (assert-true "eval is bound in (scheme r5rs)" (%r7rs-env-bound? r5rs-env 'eval))
  (assert-true "load is bound in (scheme r5rs)" (%r7rs-env-bound? r5rs-env 'load))
  (assert-true "interaction-environment is bound in (scheme r5rs)" (%r7rs-env-bound? r5rs-env 'interaction-environment))
  (assert-true "null-environment is bound in (scheme r5rs)" (%r7rs-env-bound? r5rs-env 'null-environment))
  (assert-true "scheme-report-environment is bound in (scheme r5rs)" (%r7rs-env-bound? r5rs-env 'scheme-report-environment))
  (assert-true "exact->inexact is bound in (scheme r5rs)" (%r7rs-env-bound? r5rs-env 'exact->inexact))
  (assert-true "inexact->exact is bound in (scheme r5rs)" (%r7rs-env-bound? r5rs-env 'inexact->exact))

  ;; R5RS exactness conversions via eval
  (let ((flo-42 (exact->inexact 42)))
    (assert-equal "eval exact->inexact in r5rs-env" flo-42 (eval '(exact->inexact 42) r5rs-env))
    (assert-equal "eval inexact->exact in r5rs-env" 42 (eval (list 'inexact->exact flo-42) r5rs-env)))

  ;; R5RS math and list operations via eval
  (assert-equal "eval (* (+ 2 3) (- 10 4)) in r5rs-env" 30 (eval '(* (+ 2 3) (- 10 4)) r5rs-env))
  (assert-equal "eval (list 'a 'b 'c) in r5rs-env" '(a b c) (eval '(list 'a 'b 'c) r5rs-env)))

(display "Passed: ")
(display (car *pass-count*))
(display ", Failed: ")
(display (car *fail-count*))
(newline)
(if (> (car *fail-count*) 0)
    (exit 1)
    (exit 0))

