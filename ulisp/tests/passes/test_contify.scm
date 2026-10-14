;;; =======================================================================
;;; ULisp Test Suite: Contification & Local Closure Elimination (test_contify.scm)
;;; Conforms to DSN-33 Section 8.4 & Issue #522
;;;
;;; Verifies:
;;; 1. Static escape analysis (escapes? predicate)
;;; 2. Tail-call dominance analysis (tail-calls-only? predicate)
;;; 3. Contifiability detection (contifiable-binding?)
;;; 4. AST transformation to %cont-fun and %cont-call (contify-all)
;;; 5. Complete elimination of closure allocation (%make-closure count = 0)
;;; 6. LIR code generation into direct jumps (%jump) without %call-closure
;;; =======================================================================

(define *contify-tests-passed* 0)
(define *contify-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *contify-tests-passed* (+ *contify-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *contify-tests-failed* (+ *contify-tests-failed* 1))
        (display "  [FAIL] ")
        (display test-name)
        (display " -> Expected: ")
        (display expected)
        (display " but got: ")
        (display actual)
        (newline)
        (exit 1))))

(define (assert-true test-name expr)
  (assert-equal test-name #t (if expr #t #f)))

(define (assert-false test-name expr)
  (assert-equal test-name #f (if expr #t #f)))

(display "=======================================================")
(newline)
(display " Starting ULisp Contification & Closure Elimination Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; Test Group 1: Escape Analysis (escapes?)
(display "--- Group 1: Escape Analysis (escapes?) ---")
(newline)

;; 1. Operator call site does not escape
(let ((expr '(loop 10 0)))
  (assert-false "loop in operator position does not escape"
                (escapes? 'loop expr)))

;; 2. Argument position escapes
(let ((expr '(cons loop '())))
  (assert-true "loop passed as argument escapes"
               (escapes? 'loop expr)))

;; 3. Return position escapes
(let ((expr '(if #t loop #f)))
  (assert-true "loop returned escapes"
               (escapes? 'loop expr)))

;; 4. Nested recursive loop does not escape
(let ((expr '(if (= n 0) acc (loop (- n 1) (+ acc n)))))
  (assert-false "recursive loop call does not escape"
                (escapes? 'loop expr)))


;;; Test Group 2: Tail-Call Dominance Analysis (tail-calls-only?)
(display "--- Group 2: Tail-Call Dominance Analysis (tail-calls-only?) ---")
(newline)

;; 1. Direct tail call
(let ((expr '(loop 10 0)))
  (assert-true "direct call is in tail position"
               (tail-calls-only? 'loop expr)))

;; 2. Tail call in if branches
(let ((expr '(if (= n 0) acc (loop (- n 1) acc))))
  (assert-true "calls in if branches are in tail position"
               (tail-calls-only? 'loop expr)))

;; 3. Non-tail call inside addition
(let ((expr '(+ 1 (loop (- n 1)))))
  (assert-false "call inside + is not in tail position"
               (tail-calls-only? 'loop expr)))


;;; Test Group 3: Contifiability Detection (contifiable-binding?)
(display "--- Group 3: Contifiability Detection (contifiable-binding?) ---")
(newline)

;; 1. Standard tail-recursive loop is contifiable
(let* ((binding-val '(lambda (n acc) (if (= n 0) acc (loop (- n 1) (+ acc n)))))
       (body '(loop 10 0)))
  (assert-true "tail-recursive loop is contifiable"
               (contifiable-binding? 'loop binding-val body)))

;; 2. Escaping function is NOT contifiable
(let* ((binding-val '(lambda (x) (+ x 1)))
       (body '(cons f '())))
  (assert-false "escaping function is not contifiable"
               (contifiable-binding? 'f binding-val body)))


;;; Test Group 4: AST Transformation (contify-all)
(display "--- Group 4: AST Transformation (contify-all) ---")
(newline)

;; 1. letrec loop transforms to %cont-fun and %cont-call
(let* ((input '(letrec ((loop (lambda (n acc)
                                (if (= n 0)
                                    acc
                                    (loop (- n 1) (+ acc n))))))
                 (loop 10 0)))
       (transformed (contify-all input)))
  (assert-true "transforms to %cont-fun"
               (and (pair? transformed) (eq? (car transformed) '%cont-fun)))
  (assert-equal "retains loop function name"
                'loop
                (cadr transformed))
  (assert-equal "retains loop parameter list"
                '(n acc)
                (caddr transformed))
  (assert-true "in-body converted to %cont-call"
               (equal? (car (cddddr transformed))
                       '(%cont-call loop 10 0))))

;; 2. Escaping letrec binding remains letrec
(let* ((input '(letrec ((f (lambda (x) (+ x 1))))
                 (cons f '())))
       (transformed (contify-all input)))
  (assert-true "escaping letrec preserved as letrec"
               (and (pair? transformed) (eq? (car transformed) 'letrec))))


;;; Test Group 5: Zero-Closure Conversion Verification (Pass 05)
(display "--- Group 5: Closure Elimination in Pass 05 ---")
(newline)

(let* ((input '(letrec ((loop (lambda (n acc)
                                (if (= n 0)
                                    acc
                                    (loop (- n 1) (+ acc n))))))
                 (loop 10 0)))
       (contified (contify-all input))
       (closed (closure-convert contified))
       (lifted-fns (cadr closed))
       (main-expr (caddr closed)))
  (assert-equal "lifted functions count is 0 for contified loop"
                0
                (length lifted-fns))
  (assert-true "main expr is %cont-fun"
               (and (pair? main-expr) (eq? (car main-expr) '%cont-fun))))


;;; Test Group 6: Direct Jump LIR Generation (Pass 06)
(display "--- Group 6: Direct Jump LIR Generation (Pass 06) ---")
(newline)

(let* ((input '(letrec ((loop (lambda (n acc)
                                (if (= n 0)
                                    acc
                                    (loop (- n 1) (+ acc n))))))
                 (loop 10 0)))
       (contified (contify-all input))
       (closed (closure-convert contified))
       (lir (generate-lir closed))
       (main-insts (caddr (assq '%lir-main lir))))
  ;; Verify that there are NO %call-closure instructions
  (let ((has-call-closure?
         (let loop ((insts main-insts))
           (and (pair? insts)
                (or (and (pair? (car insts)) (eq? (caar insts) '%call-closure))
                    (loop (cdr insts)))))))
    (assert-false "no %call-closure in contified loop LIR"
                  has-call-closure?))
  ;; Verify that %jump is generated for the loop
  (let ((jump-count
         (let loop ((insts main-insts) (cnt 0))
           (if (null? insts) cnt
               (let ((inst (car insts)))
                 (if (and (pair? inst) (eq? (car inst) '%jump))
                     (loop (cdr insts) (+ cnt 1))
                     (loop (cdr insts) cnt)))))))
    (assert-true "contains multiple %jump instructions (local jumps)"
                 (>= jump-count 2))))

(display "=======================================================")
(newline)
(display " All Contification & Local Closure Elimination tests PASSED successfully!")
(newline)
(display "=======================================================")
(newline)
