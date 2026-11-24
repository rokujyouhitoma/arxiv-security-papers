;;; =======================================================================
;;; Public Facade for Pure Scheme PEG Parser Generator
;;; Conforms to DSN-25 & DSN-33-04 §3, Issue #894
;;; =======================================================================

;;; Helper to read an entire file into a string using bulk read-string chunks
(define (read-all-file-text path)
  (call-with-input-file path
    (lambda (port)
      (let loop ((chunks '()))
        (let ((chunk (read-string 65536 port)))
          (if (or (eof-object? chunk) (= (string-length chunk) 0))
              (cond
                ((null? chunks) "")
                ((null? (cdr chunks)) (car chunks))
                (else
                 (let* ((ordered (reverse chunks))
                        (total (let sum ((cs ordered) (n 0))
                                 (if (null? cs)
                                     n
                                     (sum (cdr cs) (+ n (string-length (car cs)))))))
                        (out (make-string total)))
                   (let copy-chunks ((cs ordered) (off 0))
                     (if (null? cs)
                         out
                         (let* ((s (car cs))
                                (slen (string-length s)))
                           (let copy-chars ((i 0))
                             (if (< i slen)
                                 (begin
                                   (string-set! out (+ off i) (string-ref s i))
                                   (copy-chars (+ i 1)))))
                           (copy-chunks (cdr cs) (+ off slen))))))))
              (loop (cons chunk chunks))))))))

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
