;;; =======================================================================
;;; ULisp Test Suite: Yellow Docket Macros (SRFI 8, 26, 31, 2, 61)
;;; Conforms to R7RS-large Yellow Docket
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(test-begin "yellow-docket-macros")

(define-syntax assert-equal
  (syntax-rules ()
    ((assert-equal name actual expected)
     (test-equal name expected actual))))

(define-syntax assert-true
  (syntax-rules ()
    ((assert-true name expr)
     (test-assert name expr))))

(define-syntax assert-false
  (syntax-rules ()
    ((assert-false name expr)
     (test-assert name (not expr)))))

;; =======================================================================
;; Group 1: SRFI 8 (receive) Multiple Values Binding
;; =======================================================================
(write-string "--- Group 1: SRFI 8 (receive) ---\n")

;; Single value
(assert-equal "receive single value"
              (receive (x) 42 x)
              42)

;; Two values
(assert-equal "receive two values"
              (receive (a b) (values 1 2) (+ a b))
              3)

;; Four values
(assert-equal "receive four values"
              (receive (a b c d) (values 10 20 30 40) (+ (+ a b) (+ c d)))
              100)

;; Zero values
(assert-equal "receive zero values"
              (receive () (values) 'ok)
              'ok)

;; Rest parameter
(assert-equal "receive with rest parameter"
              (receive (first . rest) (values 1 2 3 4)
                (cons first (length rest)))
              '(1 . 3))

;; Single symbol formals (all values as list)
(assert-equal "receive single symbol formals"
              (receive all (values 'a 'b 'c)
                all)
              '(a b c))

;; Nested receive
(assert-equal "receive nested"
              (receive (x)
                (receive (y) 10 (+ y 5))
                (* x 2))
              30)

;; =======================================================================
;; Group 2: SRFI 31 (rec) Recursive Evaluation Special Form
;; =======================================================================
(write-string "--- Group 2: SRFI 31 (rec) ---\n")

;; Anonymous recursion: Factorial
(assert-equal "rec factorial"
              ((rec (fact n)
                 (if (<= n 1)
                     1
                     (* n (fact (- n 1)))))
               5)
              120)

;; Anonymous recursion: Fibonacci
(assert-equal "rec fibonacci"
              ((rec (fib n)
                 (if (<= n 1)
                     n
                     (+ (fib (- n 1)) (fib (- n 2)))))
               10)
              55)

;; Value-binding form: simple expression
(assert-equal "rec value form simple"
              (rec x (+ 10 20))
              30)

;; Value-binding form: self-referencing loop
(let ((loop (rec f (lambda (n acc) (if (<= n 0) acc (f (- n 1) (* acc n)))))))
  (assert-equal "rec value loop" (loop 5 1) 120))

;; =======================================================================
;; Group 3: SRFI 2 (and-let*) Conditional Binding Syntax
;; =======================================================================
(write-string "--- Group 3: SRFI 2 (and-let*) ---\n")

;; Empty claw list
(assert-equal "and-let* empty with body"
              (and-let* () 42)
              42)

(assert-true "and-let* empty no body"
             (and-let* ()))

;; Single claw: (<var> <expr>) success
(assert-equal "and-let* single var success"
              (and-let* ((x 10))
                (+ x 5))
              15)

;; Single claw: (<var> <expr>) failure
(assert-false "and-let* single var fail"
              (and-let* ((x #f))
                (+ x 5)))

;; Condition only: (<expr>) success
(assert-equal "and-let* condition success"
              (and-let* (((> 5 3)))
                'yes)
              'yes)

;; Condition only: (<expr>) failure
(assert-false "and-let* condition fail"
              (and-let* (((< 5 3)))
                'yes))

;; Symbol only
(let ((my-var #t))
  (assert-equal "and-let* symbol true"
                (and-let* (my-var) 99)
                99))

(let ((my-var #f))
  (assert-false "and-let* symbol false"
                (and-let* (my-var) 99)))

;; Sequential dependencies
(assert-equal "and-let* sequential dependency"
              (and-let* ((a 10)
                         (b (+ a 20))
                         ((= b 30)))
                (+ a b))
              40)

;; Short-circuit evaluation ensures subsequent clauses are skipped
(let ((mutated 0))
  (assert-false "and-let* short-circuit return"
                (and-let* ((a 1)
                           (b #f)
                           (c (begin (set! mutated 1) 2)))
                  #t))
  (assert-equal "and-let* short-circuit no side-effect" mutated 0))

;; =======================================================================
;; Group 4: SRFI 26 (cut / cute) Parameter Specialization
;; =======================================================================
(write-string "--- Group 4: SRFI 26 (cut / cute) ---\n")

;; cut with no slots (thunk)
(assert-equal "cut thunk"
              ((cut + 1 2))
              3)

;; cut with single slot
(assert-equal "cut single slot"
              ((cut + 1 <>) 10)
              11)

;; cut with multiple slots
(assert-equal "cut multiple slots"
              ((cut list <> 'mid <>) 1 2)
              '(1 mid 2))

;; cut with procedure as slot
(let ()
  (define (op-add a b) (+ a b))
  (define (op-sub a b) (- a b))
  (assert-equal "cut proc as slot op-add"
                ((cut <> 10 2) op-add)
                12)
  (assert-equal "cut proc as slot op-sub"
                ((cut <> 10 2) op-sub)
                8))

;; cut with rest-slot <...>
(assert-equal "cut with rest slot"
              ((cut list 0 <> <...>) 1 2 3 4)
              '(0 1 2 3 4))

;; cut with only rest-slot
(assert-equal "cut only rest slot"
              ((cut list <...>) 1 2 3)
              '(1 2 3))

;; cute: verify non-slot arguments are evaluated once at definition time
(let ()
  (define (add2 a b) (+ a b))
  (let ((eval-count (cons 0 '())))
    (let ((add-cached (cute add2 (begin (set-car! eval-count (+ (car eval-count) 1)) 100) <>)))
      ;; Already evaluated once at cute construction
      (assert-equal "cute evaluated at creation" (car eval-count) 1)
      ;; Multiple invocations should not re-evaluate the fixed argument
      (assert-equal "cute call 1" (add-cached 5) 105)
      (assert-equal "cute call 2" (add-cached 20) 120)
      (assert-equal "cute eval-count unchanged" (car eval-count) 1))))

;; cute with rest slot
(assert-equal "cute with rest slot"
              ((cute list 'start <> <...>) 'mid 'end1 'end2)
              '(start mid end1 end2))

;; =======================================================================
;; Group 5: SRFI 61 (General cond clause)
;; =======================================================================
(write-string "--- Group 5: SRFI 61 (cond clause) ---\n")

(let ()
  (define (is-odd? n) (not (= (modulo n 2) 0)))

  ;; Single value generator, guard returns true
  (assert-equal "srfi-61 single value match"
                (cond
                  ((+ 1 2) is-odd? => (lambda (x) (* x 10)))
                  (else 'fail))
                30)

  ;; Single value generator, guard returns false (falls through)
  (assert-equal "srfi-61 single value fallthrough"
                (cond
                  ((+ 1 3) is-odd? => (lambda (x) 'fail))
                  (else 'passed))
                'passed)

  ;; Multiple values generator, guard returns true
  (assert-equal "srfi-61 multiple values match"
                (cond
                  ((values 10 20) (lambda (a b) (= (+ a b) 30)) => (lambda (a b) (* a b)))
                  (else 'fail))
                200)

  ;; Multiple values generator, guard returns false (falls through)
  (assert-equal "srfi-61 multiple values fallthrough"
                (cond
                  ((values 10 25) (lambda (a b) (= (+ a b) 30)) => (lambda (a b) 'fail))
                  (else 'passed))
                'passed)

  ;; Mixed with standard cond clauses (normal test, standard =>, else)
  (assert-equal "srfi-61 mixed with standard cond"
                (cond
                  ((< 5 2) 'impossible)
                  ((values 7 3) (lambda (a b) (> a b)) => (lambda (a b) (- a b)))
                  (else 'fail))
                4))

(test-end "yellow-docket-macros")
