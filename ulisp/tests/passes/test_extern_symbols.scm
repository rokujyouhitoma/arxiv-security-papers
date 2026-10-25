;;; =======================================================================
;;; Unit Test Suite: ULisp External Symbols & 2-Split Modular Linking
;;; Conforms to DSN-33 Architecture Specification & Issue #607
;;; =======================================================================

(define *extern-tests-passed* 0)
(define *extern-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *extern-tests-passed* (+ *extern-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *extern-tests-failed* (+ *extern-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting External Symbols (Issue #607) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. Symbol Mangling
(assert-equal "mangle-fn-label map" 'ulisp_fn_map (mangle-fn-label 'map))
(assert-equal "mangle-fn-label string-append" 'ulisp_fn_string_append (mangle-fn-label 'string-append))
(assert-equal "mangle-fn-label null?" 'ulisp_fn_null_p (mangle-fn-label 'null?))
(assert-equal "mangle-fn-label string=?" 'ulisp_fn_string_eq_p (mangle-fn-label 'string=?))
(assert-equal "mangle-fn-label string<?" 'ulisp_fn_string_lt_p (mangle-fn-label 'string<?))
(assert-equal "mangle-fn-label string<=?" 'ulisp_fn_string_lt_eq_p (mangle-fn-label 'string<=?))
(assert-equal "mangle-gvar-label *stdin-port*" "ulisp_gvar__starstdin_port_star" (mangle-gvar-label '*stdin-port*))

;; 2. Pass 110: Top-level define function has deterministic ulisp_fn_ label
(let* ((prog '(%program ((define my-add (lambda (a b) (+ a b)))) (my-add 1 2)))
       (lifted (closure-convert prog))
       (funcs (cadr lifted))
       (my-fn (car funcs)))
  (assert-equal "top-level function has ulisp_fn_my_add label" 'ulisp_fn_my_add (cadr my-fn)))

;; 3. Pass 110: Unbound symbol in call position becomes %direct-call when allow-extern-symbols? is #t
(set-allow-extern-symbols! #t)
(let* ((expr '(external-callee 10 20))
       (conv (convert-expr expr '())))
  (assert-equal "extern call becomes %direct-call to ulisp_fn_external_callee"
                '(%direct-call ulisp_fn_external_callee 10 20)
                conv))

;; 4. Pass 110: Unbound symbol as value becomes %global-ref when allow-extern-symbols? is #t
(let* ((expr 'external-var)
       (conv (convert-expr expr '())))
  (assert-equal "extern var becomes %global-ref"
                '(%global-ref external-var)
                conv))

;; 5. Pass 130: lir-compile-variable emits %global-ref when allow-extern-symbols? is #t
(reset-lir!)
(lir-compile-variable 'my-extern-global '())
(let ((insts (reverse (car *lir-instructions*))))
  (assert-equal "lir-compile-variable emits %global-ref"
                '((%global-ref %rax my-extern-global))
                insts))

;; 6. Pass 140: select-instructions-function exports ulisp_fn_ as globl
(let* ((fn-ast '(%lir-function ulisp_fn_test_add
                               (params (a b))
                               (frame-size 16)
                               (body (%load %rax %rsp -8)
                                     (%return))))
       (asm-fn (select-instructions-function fn-ast))
       (body (cdr (assq 'body (cddr asm-fn)))))
  ;; Verify that the first three instructions in the reversed body are .globl, .weak, and .type
  (assert-equal "asm-fn starts with .globl"
                '(%raw-asm "    .globl ulisp_fn_test_add")
                (car body))
  (assert-equal "asm-fn has .weak"
                '(%raw-asm "    .weak ulisp_fn_test_add")
                (cadr body))
  (assert-equal "asm-fn has .type @function"
                '(%raw-asm "    .type ulisp_fn_test_add, @function")
                (caddr body)))

;; Reset flags
(set-allow-extern-symbols! #f)
(set-module-mode! #f)

(display "=======================================================") (newline)
(display " External Symbols Unit Tests: ALL ")
(display *extern-tests-passed*)
(display " TESTS PASSED!") (newline)
(display "=======================================================") (newline)
