;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 142 (x86-64 Freestanding Runtime Generator)
;;; Conforms to Issue #572, Issue #601 & Nanopass Architecture Quality Standard
;;; =======================================================================




(test-begin "Pass 142 (x86-64 Freestanding)")

;; 1. Test existence and callable nature of freestanding emission procedures
(assert-true "emit-freestanding-runtime is procedure" (procedure? emit-freestanding-runtime))

;; 2. Test emission of symbol printing routines and structured exception formatter
(let* ((captured '())
       (orig-emit emit))
  (set! emit (lambda (line) (set! captured (cons line captured))))
  (emit-freestanding-runtime)
  (set! emit orig-emit)
  (assert-true "emit-freestanding-runtime emits ulisp_find_symbol_str"
               (pair? (member "ulisp_find_symbol_str:" captured)))
  (assert-true "emit-freestanding-runtime emits ulisp_print_symbol"
               (pair? (member "ulisp_print_symbol:" captured)))
  (assert-true "emit-freestanding-runtime emits ulisp_is_error_symbol"
               (pair? (member "ulisp_is_error_symbol:" captured)))
  (assert-true "emit-freestanding-runtime emits ulisp_unhandled_exception"
               (pair? (member "ulisp_unhandled_exception:" captured)))
  (assert-true "emit-freestanding-runtime emits error prefix string"
               (pair? (member ".L_str_err_prefix: .asciz \"*** ERROR: \"" captured)))
  (assert-true "emit-freestanding-runtime emits irritants prefix string"
               (pair? (member ".L_str_irritants_prefix: .asciz \"    Irritants: \"" captured)))
  (assert-true "emit-freestanding-runtime emits error-object symbol name"
               (pair? (member ".L_str_sym_error_object: .asciz \"error-object\"" captured))))

(test-end "Pass 142 (x86-64 Freestanding)")
