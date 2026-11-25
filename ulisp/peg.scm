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

;;; -----------------------------------------------------------------------
;;; Direct-Style Static Scheme Code Emission API (Issue #948)
;;; -----------------------------------------------------------------------

(define (%peg-string-contains-dotdot? path)
  (let ((len (string-length path)))
    (let loop ((i 0))
      (cond
        ((> (+ i 2) len) #f)
        ((and (char=? (string-ref path i) #\.)
              (char=? (string-ref path (+ i 1)) #\.)
              (or (= (+ i 2) len)
                  (char=? (string-ref path (+ i 2)) #\/)
                  (char=? (string-ref path (+ i 2)) #\\))
              (or (= i 0)
                  (char=? (string-ref path (- i 1)) #\/)
                  (char=? (string-ref path (- i 1)) #\\)))
         #t)
        (else (loop (+ i 1)))))))

(define (%peg-validate-output-path! out-path)
  (if (or (not (string? out-path))
          (= (string-length out-path) 0)
          (%peg-string-contains-dotdot? out-path)
          (let check-nul ((i 0))
            (and (< i (string-length out-path))
                 (or (= (char->integer (string-ref out-path i)) 0)
                     (check-nul (+ i 1))))))
      (error "Invalid output path (CWE-22 guard)" out-path)
      #t))

;;; Emit Direct-Style static Scheme source code string from a <peg-grammar-def> AST
(define emit-peg-grammar->scheme
  (case-lambda
    ((grammar-ast)
     (emit-peg-grammar->scheme grammar-ast '()))
    ((grammar-ast opts)
     (let ((opt-ast (optimize-grammar grammar-ast)))
       (%emit-peg-grammar->scheme opt-ast opts)))))

;;; Emit Direct-Style static Scheme source code string from PEG specification text
(define emit-peg-string->scheme
  (case-lambda
    ((text)
     (emit-peg-string->scheme text '()))
    ((text opts)
     (let ((ast (parse-peg-grammar text)))
       (emit-peg-grammar->scheme ast opts)))))

;;; Emit Direct-Style static Scheme source code string from a .peg file
(define emit-peg-file->scheme
  (case-lambda
    ((path)
     (emit-peg-file->scheme path '()))
    ((path opts)
     (let ((text (read-all-file-text path)))
       (emit-peg-string->scheme text opts)))))

;;; Compile a .peg file to Direct-Style static Scheme source and write it to out-path
(define write-peg-file->scheme!
  (case-lambda
    ((in-path out-path)
     (write-peg-file->scheme! in-path out-path '()))
    ((in-path out-path opts)
     (%peg-validate-output-path! out-path)
     (let ((code (emit-peg-file->scheme in-path opts)))
       (call-with-output-file out-path
         (lambda (port)
           (display code port)))
       out-path))))
