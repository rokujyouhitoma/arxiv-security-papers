;;; =======================================================================
;;; Public Facade for Pure Scheme PEG Parser Generator
;;; Conforms to DSN-25 & DSN-33-04 §3, Issue #894
;;; =======================================================================

;;; Helper to read an entire file into a string
(define (read-all-file-text path)
  (call-with-input-file path
    (lambda (port)
      (let loop ((chars '()))
        (let ((c (read-char port)))
          (if (eof-object? c)
              (list->string (reverse chars))
              (loop (cons c chars))))))))

;;; Compiles a <peg-grammar-def> AST into an executable entry parser
(define (compile-peg-grammar grammar-ast . maybe-entry)
  (let* ((opt-ast (optimize-grammar grammar-ast))
         (entry-name (if (pair? maybe-entry) (car maybe-entry) #f)))
    (if entry-name
        (compile-grammar-entry-parser opt-ast entry-name)
        (compile-grammar-entry-parser opt-ast))))

;;; Compiles a PEG grammar specification text into an executable entry parser
(define (compile-peg-string text . maybe-entry)
  (let ((ast (parse-peg-grammar text)))
    (apply compile-peg-grammar ast maybe-entry)))

;;; Compiles a PEG grammar file (.peg / .gram) into an executable entry parser
(define (compile-peg-file path . maybe-entry)
  (let ((text (read-all-file-text path)))
    (apply compile-peg-string text maybe-entry)))

;;; S-expression declarative grammar macro: (define-grammar Name (rule1 ...) ...)
(define-syntax define-grammar
  (syntax-rules ()
    ((define-grammar name (rule-name rule-body) ...)
     (define name
       (let ((ast (sexpr->ast
                   '(grammar name
                      (directives)
                      (rules
                       (rule rule-name rule-body) ...)))))
         (compile-peg-grammar ast))))))
