;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 020 (Macro Expander)
;;; Conforms to Issue #572 & Nanopass Architecture Quality Standard
;;; =======================================================================

(define *pass-tests-passed* 0)
(define *pass-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *pass-tests-passed* (+ *pass-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *pass-tests-failed* (+ *pass-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting Pass 020 (Macro Expander) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. parse-syntax-rules-def
(let ((m (parse-syntax-rules-def '(define-syntax when
                                    (syntax-rules ()
                                      ((_ c body ...)
                                       (if c (begin body ...) #f)))))))
  (assert-equal "macro name" 'when (macro-name m))
  (assert-true "is syntax-rules macro" (syntax-rules-macro? m)))

;; 2. expand-macros-in-forms with basic when macro
(let* ((forms '((define-syntax when
                  (syntax-rules ()
                    ((_ c body ...)
                     (if c (begin body ...) #f))))
                (when (= x 1) (+ x 10))))
       (expanded (expand-macros-in-forms forms)))
  (assert-equal "expand when macro in forms"
                '((if (= x 1) (begin (+ x 10)) #f))
                expanded))

;; 3. Nested syntax-rules macro expansion
(let* ((forms '((define-syntax my-const
                  (syntax-rules ()
                    ((_) 42)))
                (define-syntax twice
                  (syntax-rules ()
                    ((_ x) (+ x x))))
                (+ (twice 5) (my-const))))
       (expanded (expand-macros-in-forms forms)))
  (assert-equal "expand multi-macros in forms"
                '((+ (+ 5 5) 42))
                expanded))

;; 4. unless macro expansion
(let* ((forms '((define-syntax unless
                  (syntax-rules ()
                    ((_ c body ...)
                     (if c #f (begin body ...)))))
                (unless #f 100)))
       (expanded (expand-macros-in-forms forms)))
  (assert-equal "expand unless macro"
                '((if #f #f (begin 100)))
                expanded))

(display "=======================================================") (newline)
(display " Pass 020: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
