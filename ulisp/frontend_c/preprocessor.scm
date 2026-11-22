;;; =======================================================================
;;; ULisp C99 Frontend: Pure Scheme C99 Preprocessor (CPP)
;;; Conforms to DSN-33-11 §3.3/§4.1, DSN-33-32 §3.1/§5.1 & Issue #914
;;; Implements:
;;;   - #include "..." / <...> resolution, #pragma once & #ifndef guard cache
;;;   - Object/Function/Variadic (#define ... __VA_ARGS__), #undef, -D/-I/-U
;;;   - Dave Prosser Blue-painted (hide-set) recursive macro suppression
;;;   - # stringification & ## token pasting (+ , ## __VA_ARGS__)
;;;   - CTFE (#825) & 64-bit (#832) #if / #elif constant integer evaluation
;;;   - Source span propagation (span-macro-origin) & diagnostic reporting (#833)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Data Structures: <cpp-macro>, <cpp-context> & Metrics
;;; -----------------------------------------------------------------------

(define-record-type <cpp-macro>
  (make-cpp-macro name function-like? params variadic? body def-span builtin-proc)
  cpp-macro?
  (name           cpp-macro-name)
  (function-like? cpp-macro-function-like?)
  (params         cpp-macro-params)
  (variadic?      cpp-macro-variadic?)
  (body           cpp-macro-body)
  (def-span       cpp-macro-def-span)
  (builtin-proc   cpp-macro-builtin-proc))

(define-record-type <cpp-context>
  (make-cpp-context include-paths system-include-paths macros
                    pragma-once-files include-guard-cache
                    include-depth max-include-depth
                    expansion-steps max-expansion-steps
                    virtual-files)
  cpp-context?
  (include-paths        cpp-ctx-include-paths        cpp-ctx-include-paths-set!)
  (system-include-paths cpp-ctx-system-include-paths cpp-ctx-system-include-paths-set!)
  (macros               cpp-ctx-macros               cpp-ctx-macros-set!)
  (pragma-once-files    cpp-ctx-pragma-once-files    cpp-ctx-pragma-once-files-set!)
  (include-guard-cache  cpp-ctx-include-guard-cache  cpp-ctx-include-guard-cache-set!)
  (include-depth        cpp-ctx-include-depth        cpp-ctx-include-depth-set!)
  (max-include-depth    cpp-ctx-max-include-depth)
  (expansion-steps      cpp-ctx-expansion-steps      cpp-ctx-expansion-steps-set!)
  (max-expansion-steps  cpp-ctx-max-expansion-steps)
  (virtual-files        cpp-ctx-virtual-files        cpp-ctx-virtual-files-set!))

(define *cpp-max-include-depth* 64)
(define *cpp-max-expansion-steps* 200000)
(define *cpp-include-skip-counter* (cons 0 '()))

(define (cpp-reset-metrics!)
  (set-car! *cpp-include-skip-counter* 0))

(define (cpp-include-skip-count)
  (car *cpp-include-skip-counter*))

(define (%cpp-inc-skip-count!)
  (set-car! *cpp-include-skip-counter* (+ (car *cpp-include-skip-counter*) 1)))

(define (%cpp-raise-error code sp msg)
  (let* ((safe-sp (if (source-span? sp)
                      sp
                      (make-source-span "<c99-cpp>" 1 1 1 1 #f (next-source-span-id!))))
         (diag (make-diagnostic 'error code safe-sp msg)))
    (report-diagnostic diag)
    (raise (list 'c99-cpp-error code msg safe-sp))))

(define (%cpp-attach-origin sp origin-sp)
  (if (not (source-span? sp))
      origin-sp
      (if (source-span? origin-sp)
          (make-source-span (span-file sp)
                            (span-start-line sp)
                            (span-start-col sp)
                            (span-end-line sp)
                            (span-end-col sp)
                            origin-sp
                            (next-source-span-id!))
          sp)))

(define (%cpp-tokens-attach-origin toks call-span)
  (map (lambda (t)
         (c-token-clone-with-span t (%cpp-attach-origin (c-token-span t) call-span)))
       toks))

;;; -----------------------------------------------------------------------
;;; 2. Path Normalization & Include Path Management
;;; -----------------------------------------------------------------------

(define (%cpp-string-split-slash str)
  (let ((n (string-length str)))
    (let loop ((i 0) (start 0) (parts '()))
      (cond
        ((>= i n)
         (reverse (if (> i start) (cons (substring str start i) parts) parts)))
        ((char=? (string-ref str i) #\/)
         (loop (+ i 1) (+ i 1)
               (if (> i start) (cons (substring str start i) parts) parts)))
        (else
         (loop (+ i 1) start parts))))))

(define (%cpp-string-join-with parts sep)
  (if (null? parts)
      ""
      (let loop ((rest (cdr parts)) (acc (list (car parts))))
        (if (null? rest)
            (apply string-append (reverse acc))
            (loop (cdr rest) (cons (car rest) (cons sep acc)))))))

(define (%cpp-normalize-path path)
  (let* ((n (string-length path))
         (abs? (and (> n 0) (char=? (string-ref path 0) #\/)))
         (segs (%cpp-string-split-slash path)))
    (let loop ((rest segs) (stack '()))
      (if (null? rest)
          (let ((joined (%cpp-string-join-with (reverse stack) "/")))
            (cond
              ((and abs? (string=? joined "")) "/")
              (abs? (string-append "/" joined))
              ((string=? joined "") ".")
              (else joined)))
          (let ((seg (car rest)))
            (cond
              ((string=? seg ".") (loop (cdr rest) stack))
              ((string=? seg "..")
               (if (and (pair? stack) (not (string=? (car stack) "..")))
                   (loop (cdr rest) (cdr stack))
                   (if abs?
                       (loop (cdr rest) stack)
                       (loop (cdr rest) (cons ".." stack)))))
              (else
               (loop (cdr rest) (cons seg stack)))))))))

(define (%cpp-path-dirname path)
  (let ((n (string-length path)))
    (let loop ((i (- n 1)))
      (cond
        ((< i 0) ".")
        ((char=? (string-ref path i) #\/)
         (if (= i 0) "/" (substring path 0 i)))
        (else (loop (- i 1)))))))

(define (%cpp-path-join dir rel)
  (let ((rn (string-length rel)))
    (if (and (> rn 0) (char=? (string-ref rel 0) #\/))
        (%cpp-normalize-path rel)
        (if (or (string=? dir "") (string=? dir "."))
            (%cpp-normalize-path rel)
            (%cpp-normalize-path (string-append dir "/" rel))))))

(define *cpp-builtin-system-include-paths*
  '("frontend_c/include" "ulisp/frontend_c/include" "/__ulisp_builtin__"))

(define (%cpp-insert-before-builtins paths new-path)
  (let loop ((xs paths) (acc '()))
    (cond
      ((null? xs) (reverse (cons new-path acc)))
      ((member (car xs) *cpp-builtin-system-include-paths*)
       (append (reverse acc) (cons new-path xs)))
      (else
       (loop (cdr xs) (cons (car xs) acc))))))

(define (cpp-add-include-path! ctx dir-path . maybe-system?)
  (let ((sys? (and (pair? maybe-system?) (car maybe-system?)))
        (norm (%cpp-normalize-path dir-path)))
    (if sys?
        (cpp-ctx-system-include-paths-set!
         ctx (%cpp-insert-before-builtins (cpp-ctx-system-include-paths ctx) norm))
        (cpp-ctx-include-paths-set!
         ctx (append (cpp-ctx-include-paths ctx) (list norm))))))

(define (cpp-register-virtual-file! ctx filepath content-str)
  (let* ((norm (%cpp-normalize-path filepath))
         (filtered
          (let loop ((xs (cpp-ctx-virtual-files ctx)) (acc '()))
            (cond
              ((null? xs) (reverse acc))
              ((string=? (caar xs) norm) (loop (cdr xs) acc))
              (else (loop (cdr xs) (cons (car xs) acc)))))))
    (cpp-ctx-virtual-files-set! ctx (cons (cons norm content-str) filtered))))

(define (%cpp-lookup-virtual-file ctx path)
  (let ((slot (assoc (%cpp-normalize-path path) (cpp-ctx-virtual-files ctx))))
    (if slot (cdr slot) #f)))

;;; -----------------------------------------------------------------------
;;; 3. Macro Table Operations & Built-in Predefined Macros
;;; -----------------------------------------------------------------------

(define (cpp-lookup-macro ctx name-sym)
  (let ((slot (assq name-sym (cpp-ctx-macros ctx))))
    (if slot (cdr slot) #f)))

(define (%cpp-set-macro! ctx name-sym mac)
  (let ((filtered
         (let loop ((xs (cpp-ctx-macros ctx)) (acc '()))
           (cond
             ((null? xs) (reverse acc))
             ((eq? (caar xs) name-sym) (loop (cdr xs) acc))
             (else (loop (cdr xs) (cons (car xs) acc)))))))
    (cpp-ctx-macros-set! ctx (cons (cons name-sym mac) filtered))))

(define (cpp-undef! ctx name-sym)
  (let ((filtered
         (let loop ((xs (cpp-ctx-macros ctx)) (acc '()))
           (cond
             ((null? xs) (reverse acc))
             ((eq? (caar xs) name-sym) (loop (cdr xs) acc))
             (else (loop (cdr xs) (cons (car xs) acc)))))))
    (cpp-ctx-macros-set! ctx filtered)))

(define (cpp-define-object! ctx name-sym body-tokens . maybe-span)
  (let ((sp (if (pair? maybe-span) (car maybe-span) #f)))
    (%cpp-set-macro! ctx name-sym
                     (make-cpp-macro name-sym #f '() #f body-tokens sp #f))))

(define (cpp-define-function! ctx name-sym params variadic? body-tokens . maybe-span)
  (let ((sp (if (pair? maybe-span) (car maybe-span) #f)))
    (%cpp-set-macro! ctx name-sym
                     (make-cpp-macro name-sym #t params variadic? body-tokens sp #f))))

(define (%cpp-strip-eof toks)
  (let loop ((xs toks) (acc '()))
    (cond
      ((null? xs) (reverse acc))
      ((eq? (c-token-kind (car xs)) 'eof) (loop (cdr xs) acc))
      (else (loop (cdr xs) (cons (car xs) acc))))))

(define (%cpp-find-eq-idx str)
  (let ((n (string-length str)))
    (let loop ((i 0))
      (cond
        ((>= i n) #f)
        ((char=? (string-ref str i) #\=) i)
        (else (loop (+ i 1)))))))

(define (cpp-define-string! ctx name-str . maybe-val-str)
  (let* ((eq-idx (if (pair? maybe-val-str) #f (%cpp-find-eq-idx name-str)))
         (clean-name (if eq-idx (substring name-str 0 eq-idx) name-str))
         (val-str (cond
                    ((pair? maybe-val-str) (car maybe-val-str))
                    (eq-idx (substring name-str (+ eq-idx 1) (string-length name-str)))
                    (else "1")))
         (body-toks (%cpp-strip-eof (c-tokenize-string val-str "<cmdline>")))
         (sym (string->symbol clean-name)))
    (cpp-define-object! ctx sym body-toks #f)))

(define (%cpp-register-builtin! ctx name-sym proc)
  (%cpp-set-macro! ctx name-sym
                   (make-cpp-macro name-sym #f '() #f '() #f proc)))

(define (%cpp-escape-c-string str)
  (let ((n (string-length str)))
    (let loop ((i 0) (parts '()))
      (if (>= i n)
          (apply string-append (reverse parts))
          (let* ((ch (string-ref str i))
                 (seg (cond
                        ((char=? ch #\\) "\\\\")
                        ((char=? ch #\") "\\\"")
                        ((char=? ch #\newline) "\\n")
                        ((char=? ch #\tab) "\\t")
                        (else (string ch)))))
            (loop (+ i 1) (cons seg parts)))))))

(define *c99-builtin-stdarg-h*
  (string-append
   "/* ULisp C99 Built-in <stdarg.h> (ISO C99 §7.15 & System V AMD64 psABI §3.5.7) */\n"
   "#ifndef _ULISP_STDARG_H\n"
   "#define _ULISP_STDARG_H\n\n"
   "typedef __builtin_va_list va_list;\n"
   "typedef __builtin_va_list __gnuc_va_list;\n\n"
   "#define va_start(ap, last) __builtin_va_start(ap, last)\n"
   "#define va_arg(ap, type)   __builtin_va_arg(ap, type)\n"
   "#define va_end(ap)         __builtin_va_end(ap)\n"
   "#define va_copy(dst, src)  __builtin_va_copy(dst, src)\n\n"
   "#endif /* _ULISP_STDARG_H */\n"))

(define (make-default-cpp-context . maybe-include-paths)
  (let* ((inc-paths (if (pair? maybe-include-paths)
                        (map %cpp-normalize-path (car maybe-include-paths))
                        '()))
         (ctx (make-cpp-context inc-paths
                                (append *cpp-builtin-system-include-paths* '())
                                '() '() '()
                                0 *cpp-max-include-depth*
                                0 *cpp-max-expansion-steps*
                                '())))
    (cpp-register-virtual-file! ctx "/__ulisp_builtin__/stdarg.h" *c99-builtin-stdarg-h*)
    (%cpp-register-builtin!
     ctx '__FILE__
     (lambda (call-tok)
       (let* ((sp (c-token-span call-tok))
              (f  (span-file sp))
              (lex (string-append "\"" (%cpp-escape-c-string f) "\"")))
         (make-c-token 'string-lit lex f sp
                       (c-token-at-bol? call-tok)
                       (c-token-has-leading-space? call-tok)
                       (cons '__FILE__ (c-token-hide-set call-tok))))))
    (%cpp-register-builtin!
     ctx '__LINE__
     (lambda (call-tok)
       (let* ((sp (c-token-span call-tok))
              (ln (span-start-line sp))
              (lex (number->string ln)))
         (make-c-token 'int-lit lex ln sp
                       (c-token-at-bol? call-tok)
                       (c-token-has-leading-space? call-tok)
                       (cons '__LINE__ (c-token-hide-set call-tok))))))
    (cpp-define-string! ctx "__STDC__" "1")
    (cpp-define-string! ctx "__STDC_HOSTED__" "1")
    (cpp-define-string! ctx "__STDC_VERSION__" "199901")
    (cpp-define-string! ctx "__x86_64__" "1")
    (cpp-define-string! ctx "__LP64__" "1")
    ctx))

;;; -----------------------------------------------------------------------
;;; 4. Dave Prosser Blue-Painted (hide-set) Expander (#, ##, __VA_ARGS__)
;;; -----------------------------------------------------------------------

(define (%cpp-ident-token? tok)
  (let ((k (c-token-kind tok)))
    (or (eq? k 'ident) (eq? k 'keyword))))

(define (%hide-set-contains? hs sym)
  (if (memq sym hs) #t #f))

(define (%hide-set-add hs sym)
  (if (memq sym hs) hs (cons sym hs)))

(define (%hide-set-union hs1 hs2)
  (let loop ((xs hs1) (acc hs2))
    (if (null? xs)
        acc
        (if (memq (car xs) acc)
            (loop (cdr xs) acc)
            (loop (cdr xs) (cons (car xs) acc))))))

(define (%hide-set-intersection hs1 hs2)
  (let loop ((xs hs1) (acc '()))
    (if (null? xs)
        (reverse acc)
        (if (memq (car xs) hs2)
            (loop (cdr xs) (cons (car xs) acc))
            (loop (cdr xs) acc)))))

(define (%tokens-add-hide-set toks hs)
  (if (null? hs)
      toks
      (map (lambda (t)
             (c-token-clone-with-hide-set t (%hide-set-union (c-token-hide-set t) hs)))
           toks)))

(define (%cpp-inherit-leading-flags toks call-tok)
  (if (null? toks)
      toks
      (let ((first (car toks)))
        (cons (make-c-token (c-token-kind first)
                            (c-token-lexeme first)
                            (c-token-value first)
                            (c-token-span first)
                            (c-token-at-bol? call-tok)
                            (c-token-has-leading-space? call-tok)
                            (c-token-hide-set first))
              (cdr toks)))))

(define (%cpp-escape-string-for-stringify str)
  (let ((n (string-length str)))
    (let loop ((i 0) (parts '()))
      (if (>= i n)
          (apply string-append (reverse parts))
          (let ((ch (string-ref str i)))
            (cond
              ((char=? ch #\\) (loop (+ i 1) (cons "\\\\" parts)))
              ((char=? ch #\") (loop (+ i 1) (cons "\\\"" parts)))
              (else (loop (+ i 1) (cons (string ch) parts)))))))))

(define (%cpp-stringify-tokens arg-toks call-span call-tok)
  (let* ((raw-str
          (let loop ((xs arg-toks) (first? #t) (parts '()))
            (if (null? xs)
                (apply string-append (reverse parts))
                (let* ((t (car xs))
                       (need-sp? (and (not first?)
                                      (or (c-token-has-leading-space? t)
                                          (c-token-at-bol? t))))
                       (lex (c-token-lexeme t))
                       (parts2 (if need-sp? (cons " " parts) parts)))
                  (loop (cdr xs) #f (cons lex parts2))))))
         (lit-lex (string-append "\"" (%cpp-escape-string-for-stringify raw-str) "\"")))
    (make-c-token 'string-lit lit-lex raw-str call-span
                  (c-token-at-bol? call-tok)
                  (c-token-has-leading-space? call-tok)
                  '())))

(define (%cpp-paste-two-tokens tok1 tok2 call-span)
  (let* ((pasted-str (string-append (c-token-lexeme tok1) (c-token-lexeme tok2)))
         (fname (if (source-span? call-span) (span-file call-span) "<cpp-paste>"))
         (relexed
          (guard (ex (else
                      (%cpp-raise-error "C99-CPP-005" call-span
                                        (string-append "Invalid token pasting result: '" pasted-str "'"))))
            (%cpp-strip-eof (c-tokenize-string pasted-str fname)))))
    (if (not (= (length relexed) 1))
        (%cpp-raise-error "C99-CPP-005" call-span
                          (string-append "Token pasting '##' did not form a single valid token: '" pasted-str "'"))
        (let* ((res (car relexed))
               (hs (%hide-set-union (c-token-hide-set tok1) (c-token-hide-set tok2))))
          (make-c-token (c-token-kind res)
                        (c-token-lexeme res)
                        (c-token-value res)
                        call-span
                        (c-token-at-bol? tok1)
                        (c-token-has-leading-space? tok1)
                        hs)))))

;;; Paste items list where items are either <c-token>, '(%cpp-paste span), or '(%cpp-empty)
(define (%cpp-reduce-pastes items)
  (let loop ((rest items) (out '()))
    (if (null? rest)
        (reverse out)
        (let ((cur (car rest)))
          (if (and (pair? cur) (eq? (car cur) '%cpp-paste))
              (let ((sp (cadr cur)))
                (cond
                  ((null? out)
                   (%cpp-raise-error "C99-CPP-005" sp "'##' cannot appear at beginning of macro expansion"))
                  ((null? (cdr rest))
                   (%cpp-raise-error "C99-CPP-005" sp "'##' cannot appear at end of macro expansion"))
                  (else
                   (let ((lhs (car out))
                         (rhs (cadr rest)))
                     (cond
                       ;; Empty marker handling
                       ((and (pair? lhs) (eq? (car lhs) '%cpp-empty)
                             (pair? rhs) (eq? (car rhs) '%cpp-empty))
                        (loop (cddr rest) out))
                       ((and (pair? lhs) (eq? (car lhs) '%cpp-empty))
                        (loop (cddr rest) (cons rhs (cdr out))))
                       ((and (pair? rhs) (eq? (car rhs) '%cpp-empty))
                        (loop (cddr rest) out))
                       (else
                        (let ((merged (%cpp-paste-two-tokens lhs rhs sp)))
                          (loop (cddr rest) (cons merged (cdr out))))))))))
              (if (and (pair? cur) (eq? (car cur) '%cpp-empty))
                  (let ((next-is-paste? (and (pair? (cdr rest))
                                             (pair? (cadr rest))
                                             (eq? (caadr rest) '%cpp-paste))))
                    (if next-is-paste?
                        (loop (cdr rest) (cons cur out))
                        (loop (cdr rest) out)))
                  (loop (cdr rest) (cons cur out))))))))

(define (%cpp-is-paste-op? tok)
  (c-token-is-punct? tok "##"))

(define (%cpp-subst-body ctx body call-tok raw-env)
  (let ((call-span (c-token-span call-tok))
        (expanded-cache '()))
    (define (get-expanded sym raw-toks)
      (let ((slot (assq sym expanded-cache)))
        (if slot
            (cdr slot)
            (let ((exp (%cpp-expand-stream ctx raw-toks)))
              (set! expanded-cache (cons (cons sym exp) expanded-cache))
              exp))))
    (let loop ((rest body) (prev-paste? #f) (items '()))
      (if (null? rest)
          (%cpp-reduce-pastes (reverse items))
          (let ((tok (car rest))
                (tail (cdr rest)))
            (cond
              ;; Special extension: , ## __VA_ARGS__
              ((and (c-token-is-punct? tok ",")
                    (>= (length rest) 3)
                    (%cpp-is-paste-op? (cadr rest))
                    (%cpp-ident-token? (caddr rest))
                    (eq? (c-token-value (caddr rest)) '__VA_ARGS__)
                    (assq '__VA_ARGS__ raw-env))
               => (lambda (va-slot)
                    (let ((va-raw (cdr va-slot)))
                      (if (null? va-raw)
                          ;; Drop comma and ## __VA_ARGS__
                          (loop (cdddr rest) #f items)
                          ;; Preserve comma and emit expanded __VA_ARGS__
                          (let* ((va-exp (get-expanded '__VA_ARGS__ va-raw))
                                 (orig-tok (c-token-clone-with-span
                                            tok (%cpp-attach-origin (c-token-span tok) call-span)))
                                 (items1 (cons orig-tok items))
                                 (items2 (let append-rev ((xs va-exp) (acc items1))
                                           (if (null? xs)
                                               acc
                                               (append-rev (cdr xs)
                                                           (cons (c-token-clone-with-span
                                                                  (car xs)
                                                                  (%cpp-attach-origin (c-token-span (car xs)) call-span))
                                                                 acc))))))
                            (loop (cdddr rest) #f items2))))))

              ;; Stringification: #param
              ((and (c-token-is-punct? tok "#")
                    (pair? tail)
                    (%cpp-ident-token? (car tail))
                    (assq (c-token-value (car tail)) raw-env))
               => (lambda (p-slot)
                    (let ((s-tok (%cpp-stringify-tokens (cdr p-slot) call-span call-tok)))
                      (loop (cdr tail) #f (cons s-tok items)))))

              ;; Token paste operator ##
              ((%cpp-is-paste-op? tok)
               (if (or (null? items) (null? tail))
                   (%cpp-raise-error "C99-CPP-005" call-span
                                     "Misplaced '##' operator in macro body")
                   (loop tail #t (cons (list '%cpp-paste call-span) items))))

              ;; Parameter reference
              ((and (%cpp-ident-token? tok)
                    (assq (c-token-value tok) raw-env))
               => (lambda (p-slot)
                    (let* ((psym (car p-slot))
                           (raw-arg (cdr p-slot))
                           (next-paste? (and (pair? tail) (%cpp-is-paste-op? (car tail))))
                           (arg-raw (if (or prev-paste? next-paste?)
                                        (%cpp-tokens-attach-origin raw-arg call-span)
                                        (%cpp-tokens-attach-origin (get-expanded psym raw-arg) call-span)))
                           (arg-toks (if prev-paste?
                                         arg-raw
                                         (%cpp-inherit-leading-flags arg-raw tok))))
                      (if (null? arg-toks)
                          (if (or prev-paste? next-paste?)
                              (loop tail #f (cons (list '%cpp-empty) items))
                              (loop tail #f items))
                          (let ((items2
                                 (let append-rev ((xs arg-toks) (acc items))
                                   (if (null? xs)
                                       acc
                                       (append-rev (cdr xs) (cons (car xs) acc))))))
                            (loop tail #f items2))))))

              ;; Normal body token
              (else
               (let ((t-with-origin
                      (c-token-clone-with-span
                       tok (%cpp-attach-origin (c-token-span tok) call-span))))
                 (loop tail #f (cons t-with-origin items))))))))))

(define (%cpp-collect-macro-args ctx tokens-after-lparen macro-name call-span)
  (let loop ((rest tokens-after-lparen) (depth 0) (curr '()) (args '()))
    (cond
      ((null? rest)
       (%cpp-raise-error "C99-CPP-005" call-span
                         (string-append "Unterminated argument list in macro invocation: "
                                        (symbol->string macro-name))))
      (else
       (let ((t (car rest)))
         (cond
           ((eq? (c-token-kind t) 'eof)
            (%cpp-raise-error "C99-CPP-005" call-span
                              (string-append "Reached EOF inside argument list of macro: "
                                             (symbol->string macro-name))))
           ((and (= depth 0) (c-token-is-punct? t ")"))
            (let ((raw-args (if (and (null? args) (null? curr))
                                '()
                                (reverse (cons (reverse curr) args)))))
              (list raw-args t (cdr rest))))
           ((c-token-is-punct? t "(")
            (loop (cdr rest) (+ depth 1) (cons t curr) args))
           ((c-token-is-punct? t ")")
            (loop (cdr rest) (- depth 1) (cons t curr) args))
           ((and (= depth 0) (c-token-is-punct? t ","))
            (loop (cdr rest) depth '() (cons (reverse curr) args)))
           (else
            (loop (cdr rest) depth (cons t curr) args))))))))

(define (%cpp-bind-macro-params params variadic? raw-args macro-name call-span)
  (let* ((param-cnt (length params))
         (norm-args (if (and (null? raw-args)
                             (or (= param-cnt 1) (and (= param-cnt 0) variadic?)))
                        '(())
                        raw-args))
         (arg-cnt (length norm-args)))
    (if variadic?
        (if (< arg-cnt param-cnt)
            (%cpp-raise-error "C99-CPP-005" call-span
                              (string-append "Too few arguments in call to variadic macro "
                                             (symbol->string macro-name)))
            (let loop ((ps params) (as norm-args) (env '()))
              (if (null? ps)
                  ;; Join remaining variadic args with synthetic comma tokens
                  (let ((va-toks
                         (let join-va ((va-list as) (first? #t) (acc '()))
                           (if (null? va-list)
                               (reverse acc)
                               (let* ((acc1 (if first?
                                                acc
                                                (cons (make-c-token 'punct "," "," call-span #f #f '())
                                                      acc)))
                                      (acc2 (let rev-push ((ts (car va-list)) (a acc1))
                                              (if (null? ts) a (rev-push (cdr ts) (cons (car ts) a))))))
                                 (join-va (cdr va-list) #f acc2))))))
                    (cons (cons '__VA_ARGS__ va-toks) env))
                  (loop (cdr ps) (cdr as) (cons (cons (car ps) (car as)) env)))))
        (if (not (= arg-cnt param-cnt))
            (%cpp-raise-error "C99-CPP-005" call-span
                              (string-append "Macro " (symbol->string macro-name)
                                             " expected " (number->string param-cnt)
                                             " arguments, got " (number->string arg-cnt)))
            (let loop ((ps params) (as norm-args) (env '()))
              (if (null? ps)
                  env
                  (loop (cdr ps) (cdr as) (cons (cons (car ps) (car as)) env))))))))

(define (%cpp-inc-expansion-step! ctx call-span)
  (let ((next-step (+ (cpp-ctx-expansion-steps ctx) 1)))
    (if (> next-step (cpp-ctx-max-expansion-steps ctx))
        (%cpp-raise-error "C99-CPP-005" call-span
                          "Maximum preprocessor macro expansion steps exceeded")
        (cpp-ctx-expansion-steps-set! ctx next-step))))

(define (%cpp-expand-stream ctx tokens)
  (let loop ((rest tokens) (out '()))
    (if (null? rest)
        (reverse out)
        (let ((tok (car rest))
              (tail (cdr rest)))
          (if (not (%cpp-ident-token? tok))
              (loop tail (cons tok out))
              (let* ((sym (c-token-value tok))
                     (mac (cpp-lookup-macro ctx sym)))
                (cond
                  ((or (not mac) (%hide-set-contains? (c-token-hide-set tok) sym))
                   (loop tail (cons tok out)))
                  ((cpp-macro-builtin-proc mac)
                   => (lambda (bproc)
                        (%cpp-inc-expansion-step! ctx (c-token-span tok))
                        (loop tail (cons (bproc tok) out))))
                  ((not (cpp-macro-function-like? mac))
                   (%cpp-inc-expansion-step! ctx (c-token-span tok))
                   (let* ((new-hs (%hide-set-add (c-token-hide-set tok) sym))
                          (subst (%cpp-subst-body ctx (cpp-macro-body mac) tok '()))
                          (painted (%cpp-inherit-leading-flags (%tokens-add-hide-set subst new-hs) tok)))
                     (loop (append painted tail) out)))
                  (else
                   ;; Function-like macro: only expand if followed by '(' (skipping non-eof)
                   (if (and (pair? tail) (c-token-is-punct? (car tail) "("))
                       (begin
                         (%cpp-inc-expansion-step! ctx (c-token-span tok))
                         (let* ((call-info (%cpp-collect-macro-args
                                            ctx (cdr tail) sym (c-token-span tok)))
                                (raw-args   (car call-info))
                                (rparen-tok (cadr call-info))
                                (after-call (caddr call-info))
                                (raw-env (%cpp-bind-macro-params
                                          (cpp-macro-params mac)
                                          (cpp-macro-variadic? mac)
                                          raw-args sym (c-token-span tok)))
                                (call-hs (%hide-set-add
                                          (%hide-set-intersection
                                           (c-token-hide-set tok)
                                           (c-token-hide-set rparen-tok))
                                          sym))
                                (subst (%cpp-subst-body ctx (cpp-macro-body mac) tok raw-env))
                                (painted (%cpp-inherit-leading-flags
                                          (%tokens-add-hide-set subst call-hs) tok)))
                           (loop (append painted after-call) out)))
                       (loop tail (cons tok out)))))))))))

;;; -----------------------------------------------------------------------
;;; 5. #if / #elif Constant Integer Expression Evaluator (CTFE #825 / 64-bit #832)
;;; -----------------------------------------------------------------------

(define (%cpp-resolve-defined ctx toks)
  (let loop ((rest toks) (acc '()))
    (if (null? rest)
        (reverse acc)
        (let ((t (car rest)))
          (if (and (%cpp-ident-token? t) (eq? (c-token-value t) 'defined))
              (let ((tail (cdr rest)))
                (cond
                  ((and (pair? tail) (c-token-is-punct? (car tail) "(")
                        (pair? (cdr tail)) (%cpp-ident-token? (cadr tail))
                        (pair? (cddr tail)) (c-token-is-punct? (caddr tail) ")"))
                   (let* ((sym (c-token-value (cadr tail)))
                          (val (if (cpp-lookup-macro ctx sym) 1 0))
                          (itok (make-c-token 'int-lit (number->string val) val
                                              (c-token-span t) #f #t '())))
                     (loop (cdddr tail) (cons itok acc))))
                  ((and (pair? tail) (%cpp-ident-token? (car tail)))
                   (let* ((sym (c-token-value (car tail)))
                          (val (if (cpp-lookup-macro ctx sym) 1 0))
                          (itok (make-c-token 'int-lit (number->string val) val
                                              (c-token-span t) #f #t '())))
                     (loop (cdr tail) (cons itok acc))))
                  (else
                   (%cpp-raise-error "C99-CPP-004" (c-token-span t)
                                     "Invalid syntax for 'defined' operator in #if"))))
              (loop (cdr rest) (cons t acc)))))))

(define (%cpp-replace-unknown-idents-with-zero toks)
  (map (lambda (t)
         (if (%cpp-ident-token? t)
             (make-c-token 'int-lit "0" 0 (c-token-span t)
                           (c-token-at-bol? t) (c-token-has-leading-space? t) '())
             t))
       toks))

(define (%cpp-expr-primary toks eval? dir-span)
  (if (null? toks)
      (%cpp-raise-error "C99-CPP-004" dir-span "Unexpected end of #if constant expression")
      (let ((t (car toks))
            (k (c-token-kind (car toks))))
        (cond
          ((or (eq? k 'int-lit) (eq? k 'char-lit))
           (cons (c-token-value t) (cdr toks)))
          ((c-token-is-punct? t "(")
           (let* ((inner (%cpp-expr-ternary (cdr toks) eval? dir-span))
                  (val (car inner))
                  (rest (cdr inner)))
             (if (and (pair? rest) (c-token-is-punct? (car rest) ")"))
                 (cons val (cdr rest))
                 (%cpp-raise-error "C99-CPP-004" (c-token-span t)
                                   "Missing closing ')' in #if constant expression"))))
          (else
           (%cpp-raise-error "C99-CPP-004" (c-token-span t)
                             (string-append "Unexpected token in #if constant expression: "
                                            (c-token-lexeme t))))))))

(define (%cpp-expr-unary toks eval? dir-span)
  (if (null? toks)
      (%cpp-raise-error "C99-CPP-004" dir-span "Unexpected end of unary expression in #if")
      (let ((t (car toks)))
        (cond
          ((c-token-is-punct? t "+") (%cpp-expr-unary (cdr toks) eval? dir-span))
          ((c-token-is-punct? t "-")
           (let ((r (%cpp-expr-unary (cdr toks) eval? dir-span)))
             (cons (- 0 (car r)) (cdr r))))
          ((c-token-is-punct? t "~")
           (let ((r (%cpp-expr-unary (cdr toks) eval? dir-span)))
             (cons (ctfe-bitwise-not (car r)) (cdr r))))
          ((c-token-is-punct? t "!")
           (let ((r (%cpp-expr-unary (cdr toks) eval? dir-span)))
             (cons (if (= (car r) 0) 1 0) (cdr r))))
          (else
           (%cpp-expr-primary toks eval? dir-span))))))

(define (%cpp-expr-mul toks eval? dir-span)
  (let loop ((res (%cpp-expr-unary toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (cond
        ((and (pair? rest) (c-token-is-punct? (car rest) "*"))
         (let ((rhs (%cpp-expr-unary (cdr rest) eval? dir-span)))
           (loop (cons (if eval? (* lhs (car rhs)) 0) (cdr rhs)))))
        ((and (pair? rest)
              (or (c-token-is-punct? (car rest) "/")
                  (c-token-is-punct? (car rest) "%")))
         (let* ((op-tok (car rest))
                (is-div? (c-token-is-punct? op-tok "/"))
                (rhs (%cpp-expr-unary (cdr rest) eval? dir-span))
                (rval (car rhs)))
           (if eval?
               (if (= rval 0)
                   (%cpp-raise-error "C99-CPP-004" (c-token-span op-tok)
                                     "Division or modulo by zero in #if constant expression")
                   (loop (cons (if is-div? (quotient lhs rval) (remainder lhs rval))
                               (cdr rhs))))
               (loop (cons 0 (cdr rhs))))))
        (else res)))))

(define (%cpp-expr-add toks eval? dir-span)
  (let loop ((res (%cpp-expr-mul toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (cond
        ((and (pair? rest) (c-token-is-punct? (car rest) "+"))
         (let ((rhs (%cpp-expr-mul (cdr rest) eval? dir-span)))
           (loop (cons (if eval? (+ lhs (car rhs)) 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) "-"))
         (let ((rhs (%cpp-expr-mul (cdr rest) eval? dir-span)))
           (loop (cons (if eval? (- lhs (car rhs)) 0) (cdr rhs)))))
        (else res)))))

(define (%cpp-expr-shift toks eval? dir-span)
  (let loop ((res (%cpp-expr-add toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (cond
        ((and (pair? rest) (c-token-is-punct? (car rest) "<<"))
         (let ((rhs (%cpp-expr-add (cdr rest) eval? dir-span)))
           (loop (cons (if eval? (ctfe-arithmetic-shift lhs (car rhs)) 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) ">>"))
         (let ((rhs (%cpp-expr-add (cdr rest) eval? dir-span)))
           (loop (cons (if eval? (ctfe-arithmetic-shift lhs (- 0 (car rhs))) 0) (cdr rhs)))))
        (else res)))))

(define (%cpp-expr-rel toks eval? dir-span)
  (let loop ((res (%cpp-expr-shift toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (cond
        ((and (pair? rest) (c-token-is-punct? (car rest) "<"))
         (let ((rhs (%cpp-expr-shift (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (< lhs (car rhs))) 1 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) "<="))
         (let ((rhs (%cpp-expr-shift (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (<= lhs (car rhs))) 1 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) ">"))
         (let ((rhs (%cpp-expr-shift (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (> lhs (car rhs))) 1 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) ">="))
         (let ((rhs (%cpp-expr-shift (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (>= lhs (car rhs))) 1 0) (cdr rhs)))))
        (else res)))))

(define (%cpp-expr-eq toks eval? dir-span)
  (let loop ((res (%cpp-expr-rel toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (cond
        ((and (pair? rest) (c-token-is-punct? (car rest) "=="))
         (let ((rhs (%cpp-expr-rel (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (= lhs (car rhs))) 1 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) "!="))
         (let ((rhs (%cpp-expr-rel (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (not (= lhs (car rhs)))) 1 0) (cdr rhs)))))
        (else res)))))

(define (%cpp-expr-bitand toks eval? dir-span)
  (let loop ((res (%cpp-expr-eq toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (if (and (pair? rest) (c-token-is-punct? (car rest) "&"))
          (let ((rhs (%cpp-expr-eq (cdr rest) eval? dir-span)))
            (loop (cons (if eval? (ctfe-bitwise-and lhs (car rhs)) 0) (cdr rhs))))
          res))))

(define (%cpp-expr-bitxor toks eval? dir-span)
  (let loop ((res (%cpp-expr-bitand toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (if (and (pair? rest) (c-token-is-punct? (car rest) "^"))
          (let ((rhs (%cpp-expr-bitand (cdr rest) eval? dir-span)))
            (loop (cons (if eval? (ctfe-bitwise-xor lhs (car rhs)) 0) (cdr rhs))))
          res))))

(define (%cpp-expr-bitior toks eval? dir-span)
  (let loop ((res (%cpp-expr-bitxor toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (if (and (pair? rest) (c-token-is-punct? (car rest) "|"))
          (let ((rhs (%cpp-expr-bitxor (cdr rest) eval? dir-span)))
            (loop (cons (if eval? (ctfe-bitwise-ior lhs (car rhs)) 0) (cdr rhs))))
          res))))

(define (%cpp-expr-land toks eval? dir-span)
  (let loop ((res (%cpp-expr-bitior toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (if (and (pair? rest) (c-token-is-punct? (car rest) "&&"))
          (let* ((rhs-eval? (and eval? (not (= lhs 0))))
                 (rhs (%cpp-expr-bitior (cdr rest) rhs-eval? dir-span))
                 (val (if (and rhs-eval? (not (= (car rhs) 0))) 1 0)))
            (loop (cons val (cdr rhs))))
          res))))

(define (%cpp-expr-lor toks eval? dir-span)
  (let loop ((res (%cpp-expr-land toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (if (and (pair? rest) (c-token-is-punct? (car rest) "||"))
          (let* ((lhs-true? (and eval? (not (= lhs 0))))
                 (rhs-eval? (and eval? (not lhs-true?)))
                 (rhs (%cpp-expr-land (cdr rest) rhs-eval? dir-span))
                 (val (if (or lhs-true? (and rhs-eval? (not (= (car rhs) 0)))) 1 0)))
            (loop (cons val (cdr rhs))))
          res))))

(define (%cpp-expr-ternary toks eval? dir-span)
  (let* ((cond-res (%cpp-expr-lor toks eval? dir-span))
         (cond-val (car cond-res))
         (rest (cdr cond-res)))
    (if (and (pair? rest) (c-token-is-punct? (car rest) "?"))
        (let* ((then-eval? (and eval? (not (= cond-val 0))))
               (else-eval? (and eval? (= cond-val 0)))
               (then-res (%cpp-expr-ternary (cdr rest) then-eval? dir-span))
               (after-then (cdr then-res)))
          (if (not (and (pair? after-then) (c-token-is-punct? (car after-then) ":")))
              (%cpp-raise-error "C99-CPP-004" dir-span
                                "Expected ':' in ternary '?:' expression inside #if")
              (let* ((else-res (%cpp-expr-ternary (cdr after-then) else-eval? dir-span))
                     (final-val (if (= cond-val 0) (car else-res) (car then-res))))
                (cons final-val (cdr else-res)))))
        cond-res)))

(define (%cpp-eval-const-expr ctx raw-toks dir-span)
  (let* ((with-def1 (%cpp-resolve-defined ctx raw-toks))
         (expanded (%cpp-expand-stream ctx with-def1))
         (with-def2 (%cpp-resolve-defined ctx expanded))
         (ready (%cpp-replace-unknown-idents-with-zero with-def2)))
    (if (null? ready)
        (%cpp-raise-error "C99-CPP-004" dir-span "Empty constant expression in #if / #elif")
        (let* ((res (%cpp-expr-ternary ready #t dir-span))
               (val (car res))
               (leftover (cdr res)))
          (if (pair? leftover)
              (%cpp-raise-error "C99-CPP-004" (c-token-span (car leftover))
                                (string-append "Unexpected trailing token '"
                                               (c-token-lexeme (car leftover))
                                               "' in #if expression"))
              val)))))

;;; -----------------------------------------------------------------------
;;; 6. Logical Line Splitting, Include Guard Detection & Directive Processor
;;; -----------------------------------------------------------------------

(define (%cpp-split-logical-lines tokens)
  (let ((body (%cpp-strip-eof tokens)))
    (let loop ((rest body) (curr '()) (lines '()))
      (if (null? rest)
          (reverse (if (null? curr) lines (cons (reverse curr) lines)))
          (let ((t (car rest)))
            (if (and (c-token-at-bol? t) (pair? curr))
                (loop (cdr rest) (list t) (cons (reverse curr) lines))
                (loop (cdr rest) (cons t curr) lines)))))))

(define (%cpp-detect-include-guard lines)
  (if (< (length lines) 3)
      #f
      (let* ((l0 (car lines))
             (l1 (cadr lines))
             (last-line (list-ref lines (- (length lines) 1))))
        (if (and (= (length l0) 3)
                 (c-token-is-punct? (car l0) "#")
                 (%cpp-ident-token? (cadr l0))
                 (eq? (c-token-value (cadr l0)) 'ifndef)
                 (%cpp-ident-token? (caddr l0))
                 (>= (length l1) 3)
                 (c-token-is-punct? (car l1) "#")
                 (%cpp-ident-token? (cadr l1))
                 (eq? (c-token-value (cadr l1)) 'define)
                 (%cpp-ident-token? (caddr l1))
                 (eq? (c-token-value (caddr l0)) (c-token-value (caddr l1)))
                 (= (length last-line) 2)
                 (c-token-is-punct? (car last-line) "#")
                 (%cpp-ident-token? (cadr last-line))
                 (eq? (c-token-value (cadr last-line)) 'endif))
            ;; Verify conditional depth stays >= 1 across middle lines
            (let ((middle-ok?
                   (let check ((rest (cdr lines)) (depth 1))
                     (if (null? (cdr rest))
                         (= depth 1)
                         (let ((ln (car rest)))
                           (if (and (>= (length ln) 2) (c-token-is-punct? (car ln) "#")
                                    (%cpp-ident-token? (cadr ln)))
                               (let ((d (c-token-value (cadr ln))))
                                 (cond
                                   ((memq d '(if ifdef ifndef))
                                    (check (cdr rest) (+ depth 1)))
                                   ((eq? d 'endif)
                                    (if (<= (- depth 1) 0)
                                        #f
                                        (check (cdr rest) (- depth 1))))
                                   (else (check (cdr rest) depth))))
                               (check (cdr rest) depth)))))))
              (if middle-ok? (c-token-value (caddr l0)) #f))
            #f))))

(define (%cpp-resolve-include-file ctx target-name is-system? current-file call-span)
  (let* ((candidates
          (if is-system?
              (append (cpp-ctx-system-include-paths ctx)
                      (cpp-ctx-include-paths ctx))
              (cons (%cpp-path-dirname current-file)
                    (append (cpp-ctx-include-paths ctx)
                            (cpp-ctx-system-include-paths ctx)))))
         (found
          (let loop ((dirs candidates))
            (if (null? dirs)
                #f
                (let ((cand (%cpp-path-join (car dirs) target-name)))
                  (cond
                    ((%cpp-lookup-virtual-file ctx cand)
                     => (lambda (vtxt) (cons cand vtxt)))
                    ((file-exists? cand)
                     (cons cand (read-all-file-text cand)))
                    (else (loop (cdr dirs)))))))))
    (or found
        (let ((direct-v (%cpp-lookup-virtual-file ctx target-name)))
          (cond
            (direct-v (cons (%cpp-normalize-path target-name) direct-v))
            ((file-exists? target-name)
             (cons (%cpp-normalize-path target-name) (read-all-file-text target-name)))
            (else
             (%cpp-raise-error "C99-CPP-001" call-span
                               (string-append "Include file not found: '" target-name "'"))))))))

(define (%cpp-parse-include-target ctx rest-toks call-span)
  (define (extract-target toks)
    (cond
      ((null? toks) #f)
      ((eq? (c-token-kind (car toks)) 'string-lit)
       (cons (c-token-value (car toks)) #f))
      ((c-token-is-punct? (car toks) "<")
       (let loop ((xs (cdr toks)) (parts '()))
         (cond
           ((null? xs) #f)
           ((c-token-is-punct? (car xs) ">")
            (cons (apply string-append (reverse parts)) #t))
           (else
            (loop (cdr xs) (cons (c-token-lexeme (car xs)) parts))))))
      (else #f)))
  (or (extract-target rest-toks)
      (extract-target (%cpp-expand-stream ctx rest-toks))
      (%cpp-raise-error "C99-CPP-001" call-span
                        "Invalid #include filename specification")))

(define (%cpp-parse-define! ctx args dir-span)
  (if (or (null? args) (not (%cpp-ident-token? (car args))))
      (%cpp-raise-error "C99-CPP-003" dir-span "#define requires a macro identifier name")
      (let* ((name-tok (car args))
             (name-sym (c-token-value name-tok))
             (after-name (cdr args)))
        (if (and (pair? after-name)
                 (c-token-is-punct? (car after-name) "(")
                 (not (c-token-has-leading-space? (car after-name))))
            ;; Function-like macro definition
            (let loop ((ps (cdr after-name)) (params '()) (expect-param? #t))
              (cond
                ((null? ps)
                 (%cpp-raise-error "C99-CPP-003" dir-span
                                   "Unterminated parameter list in #define"))
                ((c-token-is-punct? (car ps) ")")
                 (if (and (pair? params) expect-param?)
                     (%cpp-raise-error "C99-CPP-003" (c-token-span (car ps))
                                       "Trailing comma in macro parameter list")
                     (cpp-define-function! ctx name-sym (reverse params) #f (cdr ps) dir-span)))
                ((and expect-param? (c-token-is-punct? (car ps) "..."))
                 (if (and (pair? (cdr ps)) (c-token-is-punct? (cadr ps) ")"))
                     (cpp-define-function! ctx name-sym (reverse params) #t (cddr ps) dir-span)
                     (%cpp-raise-error "C99-CPP-003" (c-token-span (car ps))
                                       "'...' must be the last parameter in #define")))
                ((and expect-param? (%cpp-ident-token? (car ps)))
                 (let ((pname (c-token-value (car ps)))
                       (after-p (cdr ps)))
                   (cond
                     ((null? after-p)
                      (%cpp-raise-error "C99-CPP-003" dir-span
                                        "Unterminated parameter list in #define"))
                     ((c-token-is-punct? (car after-p) ")")
                      (cpp-define-function! ctx name-sym (reverse (cons pname params)) #f (cdr after-p) dir-span))
                     ((c-token-is-punct? (car after-p) ",")
                      (loop (cdr after-p) (cons pname params) #t))
                     (else
                      (%cpp-raise-error "C99-CPP-003" (c-token-span (car after-p))
                                        "Expected ',' or ')' in macro parameter list")))))
                (else
                 (%cpp-raise-error "C99-CPP-003" (c-token-span (car ps))
                                   "Invalid token in #define parameter list"))))
            ;; Object-like macro definition
            (cpp-define-object! ctx name-sym after-name dir-span)))))

(define (%cpp-active? cond-stack)
  (or (null? cond-stack)
      (caddr (car cond-stack))))

(define (%cpp-process-lines ctx lines current-file)
  (let* ((norm-cur (%cpp-normalize-path current-file))
         (flush-normal
          (lambda (pending out)
            (if (null? pending)
                out
                (let ((exp (%cpp-expand-stream ctx (reverse pending))))
                  (let push-rev ((xs exp) (acc out))
                    (if (null? xs) acc (push-rev (cdr xs) (cons (car xs) acc)))))))))
    (let loop ((rest-lines lines) (cond-stack '()) (pending '()) (out '()))
      (if (null? rest-lines)
          (if (pair? cond-stack)
              (%cpp-raise-error "C99-CPP-003" (list-ref (car cond-stack) 4)
                                "Unterminated #if / #ifdef / #ifndef directive before EOF")
              (reverse (flush-normal pending out)))
          (let* ((ln (car rest-lines))
                 (next-lines (cdr rest-lines))
                 (active? (%cpp-active? cond-stack)))
            (if (and (pair? ln)
                     (c-token-at-bol? (car ln))
                     (c-token-is-punct? (car ln) "#"))
                ;; Preprocessing directive line
                (let* ((out1 (flush-normal pending out))
                       (hash-tok (car ln))
                       (after-hash (cdr ln)))
                  (if (null? after-hash)
                      ;; Null directive '#'
                      (loop next-lines cond-stack '() out1)
                      (let* ((dir-tok (car after-hash))
                             (dir-args (cdr after-hash))
                             (dir-sp (c-token-span hash-tok))
                             (dir-sym (if (%cpp-ident-token? dir-tok)
                                          (c-token-value dir-tok)
                                          #f)))
                        (cond
                          ;; Conditional directives run in both active & inactive modes
                          ((memq dir-sym '(if ifdef ifndef))
                           (if (not active?)
                               (loop next-lines (cons (list #f #t #f #f dir-sp) cond-stack) '() out1)
                               (let ((taken?
                                      (case dir-sym
                                        ((ifdef)
                                         (if (and (= (length dir-args) 1) (%cpp-ident-token? (car dir-args)))
                                             (if (cpp-lookup-macro ctx (c-token-value (car dir-args))) #t #f)
                                             (%cpp-raise-error "C99-CPP-003" dir-sp "#ifdef expects a single identifier")))
                                        ((ifndef)
                                         (if (and (= (length dir-args) 1) (%cpp-ident-token? (car dir-args)))
                                             (if (cpp-lookup-macro ctx (c-token-value (car dir-args))) #f #t)
                                             (%cpp-raise-error "C99-CPP-003" dir-sp "#ifndef expects a single identifier")))
                                        ((if)
                                         (not (= (%cpp-eval-const-expr ctx dir-args dir-sp) 0))))))
                                 (loop next-lines (cons (list #t taken? taken? #f dir-sp) cond-stack) '() out1))))

                          ((eq? dir-sym 'elif)
                           (if (null? cond-stack)
                               (%cpp-raise-error "C99-CPP-003" dir-sp "Unexpected #elif without matching #if")
                               (let* ((frame (car cond-stack))
                                      (parent-act? (list-ref frame 0))
                                      (any-taken?  (list-ref frame 1))
                                      (saw-else?   (list-ref frame 3)))
                                 (if saw-else?
                                     (%cpp-raise-error "C99-CPP-003" dir-sp "#elif directive after #else")
                                     (if (or (not parent-act?) any-taken?)
                                         (loop next-lines (cons (list parent-act? any-taken? #f #f dir-sp)
                                                                (cdr cond-stack)) '() out1)
                                         (let ((taken? (not (= (%cpp-eval-const-expr ctx dir-args dir-sp) 0))))
                                           (loop next-lines (cons (list #t taken? taken? #f dir-sp)
                                                                  (cdr cond-stack)) '() out1)))))))

                          ((eq? dir-sym 'else)
                           (if (null? cond-stack)
                               (%cpp-raise-error "C99-CPP-003" dir-sp "Unexpected #else without matching #if")
                               (let* ((frame (car cond-stack))
                                      (parent-act? (list-ref frame 0))
                                      (any-taken?  (list-ref frame 1))
                                      (saw-else?   (list-ref frame 3)))
                                 (if saw-else?
                                     (%cpp-raise-error "C99-CPP-003" dir-sp "Duplicate #else directive")
                                     (let ((cur-act? (and parent-act? (not any-taken?))))
                                       (loop next-lines (cons (list parent-act? #t cur-act? #t dir-sp)
                                                              (cdr cond-stack)) '() out1))))))

                          ((eq? dir-sym 'endif)
                           (if (null? cond-stack)
                               (%cpp-raise-error "C99-CPP-003" dir-sp "Unexpected #endif without matching #if")
                               (loop next-lines (cdr cond-stack) '() out1)))

                          ;; All other directives are skipped if inactive
                          ((not active?)
                           (loop next-lines cond-stack '() out1))

                          ((eq? dir-sym 'define)
                           (%cpp-parse-define! ctx dir-args dir-sp)
                           (loop next-lines cond-stack '() out1))

                          ((eq? dir-sym 'undef)
                           (if (and (= (length dir-args) 1) (%cpp-ident-token? (car dir-args)))
                               (begin
                                 (cpp-undef! ctx (c-token-value (car dir-args)))
                                 (loop next-lines cond-stack '() out1))
                               (%cpp-raise-error "C99-CPP-003" dir-sp "#undef requires an identifier")))

                          ((eq? dir-sym 'error)
                           (let ((msg (apply string-append
                                             (map (lambda (t) (string-append (c-token-lexeme t) " ")) dir-args))))
                             (%cpp-raise-error "C99-CPP-002" dir-sp
                                               (string-append "#error " msg))))

                          ((eq? dir-sym 'pragma)
                           (if (and (pair? dir-args) (%cpp-ident-token? (car dir-args))
                                    (eq? (c-token-value (car dir-args)) 'once))
                               (if (not (member norm-cur (cpp-ctx-pragma-once-files ctx)))
                                   (cpp-ctx-pragma-once-files-set!
                                    ctx (cons norm-cur (cpp-ctx-pragma-once-files ctx)))))
                           (loop next-lines cond-stack '() out1))

                          ((eq? dir-sym 'line)
                           (loop next-lines cond-stack '() out1))

                          ((eq? dir-sym 'include)
                           (if (>= (cpp-ctx-include-depth ctx) (cpp-ctx-max-include-depth ctx))
                               (%cpp-raise-error "C99-CPP-001" dir-sp
                                                 "Maximum #include nesting depth exceeded")
                               (let* ((tgt (%cpp-parse-include-target ctx dir-args dir-sp))
                                      (tgt-name (car tgt))
                                      (is-sys?  (cdr tgt))
                                      (resolved (%cpp-resolve-include-file
                                                 ctx tgt-name is-sys? norm-cur dir-sp))
                                      (inc-path (car resolved))
                                      (inc-text (cdr resolved))
                                      (guard-entry (assoc inc-path (cpp-ctx-include-guard-cache ctx))))
                                 (cond
                                   ((member inc-path (cpp-ctx-pragma-once-files ctx))
                                    (%cpp-inc-skip-count!)
                                    (loop next-lines cond-stack '() out1))
                                   ((and guard-entry (cpp-lookup-macro ctx (cdr guard-entry)))
                                    (%cpp-inc-skip-count!)
                                    (loop next-lines cond-stack '() out1))
                                   (else
                                    (let* ((inc-toks (c-tokenize-string inc-text inc-path))
                                           (inc-lines (%cpp-split-logical-lines inc-toks))
                                           (detected-guard (%cpp-detect-include-guard inc-lines)))
                                      (if detected-guard
                                          (cpp-ctx-include-guard-cache-set!
                                           ctx (cons (cons inc-path detected-guard)
                                                     (cpp-ctx-include-guard-cache ctx))))
                                      (cpp-ctx-include-depth-set! ctx (+ (cpp-ctx-include-depth ctx) 1))
                                      (let ((inc-out
                                             (guard (ex (else
                                                         (cpp-ctx-include-depth-set!
                                                          ctx (- (cpp-ctx-include-depth ctx) 1))
                                                         (raise ex)))
                                               (let ((r (%cpp-process-lines ctx inc-lines inc-path)))
                                                 (cpp-ctx-include-depth-set!
                                                  ctx (- (cpp-ctx-include-depth ctx) 1))
                                                 r))))
                                        (let ((out2 (let push-rev ((xs inc-out) (acc out1))
                                                      (if (null? xs) acc (push-rev (cdr xs) (cons (car xs) acc))))))
                                          (loop next-lines cond-stack '() out2)))))))))

                          (else
                           (%cpp-raise-error "C99-CPP-003" dir-sp
                                             (string-append "Unknown preprocessor directive #"
                                                            (c-token-lexeme dir-tok))))))))
                ;; Non-directive line: buffer onto pending when active
                (if active?
                    (let ((pending2 (let push-rev ((xs ln) (acc pending))
                                      (if (null? xs) acc (push-rev (cdr xs) (cons (car xs) acc))))))
                      (loop next-lines cond-stack pending2 out))
                    (loop next-lines cond-stack pending out))))))))

;;; -----------------------------------------------------------------------
;;; 7. Public Top-Level Preprocessor Entry Points
;;; -----------------------------------------------------------------------

(define (%cpp-last-or-synth-eof tokens fname)
  (let loop ((xs tokens) (last-eof #f))
    (if (null? xs)
        (or last-eof
            (let ((sp (make-source-span fname 1 1 1 1 #f (next-source-span-id!))))
              (make-c-token 'eof "" 'eof sp #t #f '())))
        (loop (cdr xs)
              (if (eq? (c-token-kind (car xs)) 'eof) (car xs) last-eof)))))

(define (cpp-preprocess-tokens ctx tokens . maybe-filename)
  (let* ((fname (if (pair? maybe-filename)
                    (car maybe-filename)
                    (if (pair? tokens)
                        (span-file (c-token-span (car tokens)))
                        "<c99-input>")))
         (lines (%cpp-split-logical-lines tokens))
         (expanded (%cpp-process-lines ctx lines fname))
         (eof-tok (%cpp-last-or-synth-eof tokens fname)))
    (append expanded (list eof-tok))))

(define (cpp-preprocess-string src-text . rest)
  (let* ((fname (if (pair? rest) (car rest) "<c99-input>"))
         (ctx   (if (and (pair? rest) (pair? (cdr rest)))
                    (cadr rest)
                    (make-default-cpp-context)))
         (raw-toks (c-tokenize-string src-text fname))
         (pp-toks  (cpp-preprocess-tokens ctx raw-toks fname)))
    (c-concat-adjacent-string-tokens pp-toks)))

(define (cpp-preprocess-to-string src-text . rest)
  (let ((toks (apply cpp-preprocess-string (cons src-text rest))))
    (c-tokens->source-string toks)))

(define (cpp-preprocess-file filepath . maybe-ctx)
  (let* ((ctx (if (pair? maybe-ctx) (car maybe-ctx) (make-default-cpp-context)))
         (norm (%cpp-normalize-path filepath))
         (src (read-all-file-text norm)))
    (cpp-preprocess-string src norm ctx)))
