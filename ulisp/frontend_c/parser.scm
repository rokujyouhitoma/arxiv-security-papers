;;; =======================================================================
;;; ULisp C99 Frontend: PEG-Based C99 Parser & L_c_ast Builder
;;; Conforms to DSN-33-11 §4.2, DSN-33-22 §3, DSN-33-32 & Issue #931 / #915
;;; Uses tools/grammars/c99.peg with Warth left-recursion, <source-span> (#824),
;;; and <binding-id> / Scope Manager (#837) for typedef disambiguation.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. CST / String Utilities
;;; -----------------------------------------------------------------------

(define (%c99-cst->string node)
  (cond
    ((string? node) node)
    ((char? node) (string node))
    ((symbol? node) (symbol->string node))
    ((boolean? node) "")
    ((null? node) "")
    ((pair? node)
     (if (and (symbol? (car node)) (not (pair? (cdr node))) (not (null? (cdr node))))
         (%c99-cst->string (cdr node))
         (string-append (%c99-cst->string (car node))
                        (%c99-cst->string (cdr node)))))
    (else "")))

(define (%c99-string-trim-right-ws str)
  (let loop ((i (- (string-length str) 1)))
    (if (< i 0)
        ""
        (let ((ch (string-ref str i)))
          (if (or (char=? ch #\space)
                  (char=? ch #\tab)
                  (char=? ch #\newline)
                  (char=? ch #\return))
              (loop (- i 1))
              (substring str 0 (+ i 1)))))))

(define *c99-embedded-grammar-text* (cons #f '()))

(define (c99-register-embedded-grammar! txt)
  (set-car! *c99-embedded-grammar-text* txt))

(define (%c99-safe-grammar-path? p)
  (and (string? p)
       (> (string-length p) 0)
       (let ((len (string-length p)))
         (let loop ((i 0))
           (if (< i len)
               (let* ((ch (string-ref p i))
                      (code (char->integer ch)))
                 (cond
                   ((or (= code 0) (< code 32)
                        (char=? ch #\;) (char=? ch #\|) (char=? ch #\&)
                        (char=? ch #\$) (char=? ch #\`) (char=? ch #\<) (char=? ch #\>))
                    #f)
                   ((and (char=? ch #\.)
                         (< (+ i 1) len)
                         (char=? (string-ref p (+ i 1)) #\.)
                         (or (= i 0) (char=? (string-ref p (- i 1)) #\/))
                         (or (= (+ i 2) len) (char=? (string-ref p (+ i 2)) #\/)))
                    #f)
                   (else (loop (+ i 1)))))
               #t)))))

(define (%c99-read-grammar-text)
  (let ((env-path (guard (ex (else #f)) (get-environment-variable "ULISP_C99_GRAMMAR"))))
    (cond
      ((and (string? env-path) (> (string-length env-path) 0))
       (if (not (%c99-safe-grammar-path? env-path))
           (error "Unsafe ULISP_C99_GRAMMAR path rejected" env-path))
       (if (file-exists? env-path)
           (read-all-file-text env-path)
           (error "ULISP_C99_GRAMMAR file not found" env-path)))
      ((string? (car *c99-embedded-grammar-text*))
       (car *c99-embedded-grammar-text*))
      (else
       (let loop ((paths '("tools/grammars/c99.peg"
                           "../tools/grammars/c99.peg"
                           "../../tools/grammars/c99.peg"
                           "../../../tools/grammars/c99.peg")))
         (if (null? paths)
             (error "Unable to locate tools/grammars/c99.peg")
             (if (file-exists? (car paths))
                 (read-all-file-text (car paths))
                 (loop (cdr paths)))))))))

;;; -----------------------------------------------------------------------
;;; 2. C99 Parse Environment (Scope Manager + Typedef Table + Source Span)
;;; -----------------------------------------------------------------------

(define-record-type <c99-parse-env>
  (%make-c99-parse-env scope-mgr file text line-starts)
  c99-parse-env?
  (scope-mgr   c99-parse-env-scope-mgr   c99-parse-env-scope-mgr-set!)
  (file        c99-parse-env-file        c99-parse-env-file-set!)
  (text        c99-parse-env-text        c99-parse-env-text-set!)
  (line-starts c99-parse-env-line-starts c99-parse-env-line-starts-set!))

(define (c99-make-init-scope-manager)
  (let ((mgr (make-scope-manager)))
    (scope-manager-define! mgr '__builtin_va_list 'typedef)
    mgr))

(define (make-c99-parse-env . maybe-file)
  (let ((fname (if (pair? maybe-file) (car maybe-file) "<c99-input>")))
    (%make-c99-parse-env (c99-make-init-scope-manager) fname "" #f)))

(define (c99-push-scope! env kind)
  (scope-manager-push! (c99-parse-env-scope-mgr env) kind))

(define (c99-pop-scope! env)
  (let ((mgr (c99-parse-env-scope-mgr env)))
    (if (scope-node? (scope-node-parent (scope-manager-current mgr)))
        (scope-manager-pop! mgr)
        #f)))

(define (c99-register-typedef! env sym . maybe-span)
  (let* ((mgr (c99-parse-env-scope-mgr env))
         (sp (if (pair? maybe-span) (car maybe-span) #f)))
    (if sp
        (scope-manager-define! mgr sym 'typedef ':source-span sp)
        (scope-manager-define! mgr sym 'typedef))))

(define (c99-register-var! env sym kind . maybe-span)
  (let* ((mgr (c99-parse-env-scope-mgr env))
         (sp (if (pair? maybe-span) (car maybe-span) #f)))
    (if sp
        (scope-manager-define! mgr sym kind ':source-span sp)
        (scope-manager-define! mgr sym kind))))

(define (c99-typedef-bound? env sym)
  (scope-manager-typedef-name? (c99-parse-env-scope-mgr env) sym))

(define (c99-lookup-binding env sym . maybe-ns)
  (let ((mgr (c99-parse-env-scope-mgr env)))
    (if (pair? maybe-ns)
        (scope-manager-lookup mgr sym (car maybe-ns))
        (scope-manager-lookup mgr sym))))

(define (c99-lookup-binding-id env sym . maybe-ns)
  (let ((b (if (pair? maybe-ns)
               (c99-lookup-binding env sym (car maybe-ns))
               (c99-lookup-binding env sym))))
    (if b (binding-id b) #f)))

;;; -----------------------------------------------------------------------
;;; 3. Cached Grammar AST & Standalone PEG Parser
;;; -----------------------------------------------------------------------

(define *c99-peg-grammar-ast* (cons #f '()))
(define *c99-standalone-parser* (cons #f '()))
(define *c99-cached-env-parser* (cons #f '()))

(define (%c99-try-load-grammar-cache txt)
  (let loop ((paths '("build/c99_grammar_ast.sexp" "ulisp/build/c99_grammar_ast.sexp")))
    (if (null? paths)
        #f
        (let* ((p (car paths))
               (loaded
                (guard (ex (else #f))
                  (if (file-exists? p)
                      (call-with-input-file p
                        (lambda (port) (read port)))
                      #f))))
          (if (and (pair? loaded)
                   (eq? (car loaded) 'c99-grammar-cache)
                   (pair? (cdr loaded))
                   (string? (cadr loaded))
                   (string=? (cadr loaded) txt)
                   (pair? (cddr loaded)))
              (guard (ex (else #f))
                (sexpr->ast (caddr loaded)))
              (loop (cdr paths)))))))

(define (%c99-try-save-grammar-cache txt ast)
  (let ((target (cond
                  ((file-exists? "frontend_c/parser.scm") "build/c99_grammar_ast.sexp")
                  ((file-exists? "ulisp/frontend_c/parser.scm") "ulisp/build/c99_grammar_ast.sexp")
                  (else #f))))
    (if target
        (guard (ex (else #f))
          (let ((port (open-output-file target)))
            (write (list 'c99-grammar-cache txt (ast->sexpr ast)) port)
            (newline port)
            (close-output-port port))))))

(define (c99-peg-grammar-ast)
  (or (car *c99-peg-grammar-ast*)
      (let* ((txt (%c99-read-grammar-text))
             (cached (%c99-try-load-grammar-cache txt))
             (ast (if cached
                      cached
                      (let ((parsed (optimize-grammar (parse-peg-grammar txt))))
                        (%c99-try-save-grammar-cache txt parsed)
                        parsed))))
        (set-car! *c99-peg-grammar-ast* ast)
        ast)))

(define (c99-peg-parser . maybe-entry)
  (if (pair? maybe-entry)
      (compile-grammar-entry-parser (c99-peg-grammar-ast) (car maybe-entry))
      (or (car *c99-standalone-parser*)
          (let ((p (compile-grammar-entry-parser (c99-peg-grammar-ast) 'translation_unit)))
            (set-car! *c99-standalone-parser* p)
            p))))

;;; -----------------------------------------------------------------------
;;; 4. Source Span Attachment & AST Helpers
;;; -----------------------------------------------------------------------

(define (%c99-build-line-starts text)
  (let ((len (string-length text)))
    (let loop ((i 0) (acc '(0)))
      (if (>= i len)
          (list->vector (reverse acc))
          (if (char=? (string-ref text i) #\newline)
              (loop (+ i 1) (cons (+ i 1) acc))
              (loop (+ i 1) acc))))))

(define (%c99-lookup-line-col line-starts text-len pos)
  (let* ((p (cond ((< pos 0) 0) ((> pos text-len) text-len) (else pos)))
         (n (vector-length line-starts)))
    (if (= n 0)
        '(1 . 1)
        (let loop ((lo 0) (hi (- n 1)))
          (if (>= lo hi)
              (cons (+ lo 1) (+ (- p (vector-ref line-starts lo)) 1))
              (let ((mid (quotient (+ lo hi 1) 2)))
                (if (<= (vector-ref line-starts mid) p)
                    (loop mid hi)
                    (loop lo (- mid 1)))))))))

(define (%c99-make-span-from-pos env ctx start-pos end-pos)
  (let* ((txt (parse-ctx-text ctx))
         (ls (if (and (c99-parse-env-line-starts env)
                      (eq? txt (c99-parse-env-text env)))
                 (c99-parse-env-line-starts env)
                 (let ((built (%c99-build-line-starts txt)))
                   (c99-parse-env-text-set! env txt)
                   (c99-parse-env-line-starts-set! env built)
                   built)))
         (tlen (parse-ctx-length ctx))
         (slc (%c99-lookup-line-col ls tlen start-pos))
         (elc (%c99-lookup-line-col ls tlen (max start-pos end-pos))))
    (make-source-span (c99-parse-env-file env)
                      (car slc) (cdr slc)
                      (car elc) (cdr elc)
                      #f
                      (next-source-span-id!))))

(define (%c99-wrap-span env parser)
  (lambda (ctx pos sk fk)
    (parser ctx pos
            (lambda (val next-pos inner-fk)
              (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                (sk (ast-with-span val sp) next-pos inner-fk)))
            fk)))

;;; Extracts declared identifier symbols from declarator / init-declarator trees
(define (%c99-extract-declarator-names node)
  (let ((raw (ast-strip-span node)))
    (cond
      ((null? raw) '())
      ((boolean? raw) '())
      ((string? raw) '())
      ((symbol? raw) '())
      ((pair? raw)
       (cond
         ((eq? (car raw) 'c-decl-id)
          (list (cadr raw)))
         ((eq? (car raw) 'c-init-decl)
          (%c99-extract-declarator-names (cadr raw)))
         ((eq? (car raw) 'c-attr-decl)
          (%c99-extract-declarator-names (cadr raw)))
         ((eq? (car raw) 'c-fn-declarator)
          (%c99-extract-declarator-names (cadr raw)))
         ((eq? (car raw) 'c-arr-declarator)
          (%c99-extract-declarator-names (cadr raw)))
         ((eq? (car raw) 'c-ptr-declarator)
          (%c99-extract-declarator-names (caddr raw)))
         ((eq? (car raw) 'c-param-list)
          '())
         (else
          (append (%c99-extract-declarator-names (car raw))
                  (%c99-extract-declarator-names (cdr raw))))))
      (else '()))))

;;; Extracts parameter symbols from the outermost function declarator
(define (%c99-extract-fn-param-names decl-node)
  (let ((raw (ast-strip-span decl-node)))
    (cond
      ((not (pair? raw)) '())
      ((eq? (car raw) 'c-fn-declarator)
       (let ((inner (ast-strip-span (cadr raw)))
             (params (caddr raw)))
         (if (and (pair? inner) (eq? (car inner) 'c-decl-id))
             (%c99-collect-param-ids params)
             (let ((sub (%c99-extract-fn-param-names inner)))
               (if (null? sub) (%c99-collect-param-ids params) sub)))))
      ((eq? (car raw) 'c-ptr-declarator)
       (%c99-extract-fn-param-names (caddr raw)))
      (else '()))))

(define (%c99-collect-param-ids node)
  (let ((raw (ast-strip-span node)))
    (cond
      ((not (pair? raw)) '())
      ((eq? (car raw) 'c-param)
       (let ((d (caddr raw)))
         (if d (%c99-extract-declarator-names d) '())))
      (else
       (append (%c99-collect-param-ids (car raw))
               (%c99-collect-param-ids (cdr raw)))))))

(define (%c99-has-typedef-spec? specs-node)
  (let ((raw (ast-strip-span specs-node)))
    (cond
      ((eq? raw 'typedef) #t)
      ((pair? raw)
       (or (%c99-has-typedef-spec? (car raw))
           (%c99-has-typedef-spec? (cdr raw))))
      (else #f))))

(define (%c99-flatten-tag-syms node)
  (let ((raw (ast-strip-span node)))
    (cond
      ((null? raw) '())
      ((boolean? raw) '())
      ((string? raw) '())
      ((symbol? raw) (list raw))
      ((pair? raw)
       (append (%c99-flatten-tag-syms (car raw))
               (%c99-flatten-tag-syms (cdr raw))))
      (else '()))))

(define (%c99-flatten-decl-specs node)
  (let ((raw (ast-strip-span node)))
    (cond
      ((null? raw) '())
      ((boolean? raw) '())
      ((string? raw) '())
      ((symbol? raw) (list raw))
      ((and (pair? raw)
            (memq (car raw) '(c-struct c-union c-enum c-typedef-name c-typeof c-attr c-reg-decl)))
       (list raw))
      ((pair? raw)
       (append (%c99-flatten-decl-specs (car raw))
               (%c99-flatten-decl-specs (cdr raw))))
      (else '()))))

(define (%c99-list-last xs)
  (if (null? (cdr xs)) (car xs) (%c99-list-last (cdr xs))))

(define (%c99-binop-str->sym s)
  (cond
    ((string=? s ",")  'comma)
    ((string=? s "||") 'lor)
    ((string=? s "&&") 'land)
    ((string=? s "|")  'bit-or)
    ((string=? s "^")  'bit-xor)
    ((string=? s "&")  'bit-and)
    ((string=? s "%")  'rem)
    (else (string->symbol s))))

(define (%c99-assign-str->sym s)
  (cond
    ((string=? s "%=") 'rem=)
    ((string=? s "&=") 'bit-and=)
    ((string=? s "^=") 'bit-xor=)
    ((string=? s "|=") 'bit-or=)
    (else (string->symbol s))))

(define (%c99-unop-str->sym s)
  (cond
    ((string=? s "&") 'addr)
    ((string=? s "*") 'deref)
    ((string=? s "+") 'uplus)
    ((string=? s "-") 'neg)
    ((string=? s "~") 'bit-not)
    ((string=? s "!") 'lnot)
    (else (string->symbol s))))

(define (%c99-merge-c-str-literals items env ctx pos end-pos)
  (if (and (pair? items) (null? (cdr items)))
      (caar items)
      (let* ((parts
              (map (lambda (it)
                     (let* ((snode (ast-strip-span (car it)))
                            (raw (cadr snode))
                            (n (string-length raw)))
                       (cond
                         ((and (>= n 3) (char=? (string-ref raw 0) #\L) (char=? (string-ref raw 1) #\"))
                          (substring raw 2 (- n 1)))
                         ((and (>= n 2) (char=? (string-ref raw 0) #\"))
                          (substring raw 1 (- n 1)))
                         (else raw))))
                   items))
             (joined (string-append "\"" (apply string-append parts) "\""))
             (sp (%c99-make-span-from-pos env ctx pos end-pos)))
        (ast-with-span (list 'c-str joined) sp))))

(define (%c99-concat-c-str-cst node)
  (let ((acc (cons '() '())))
    (let walk ((n node))
      (let ((raw (ast-strip-span n)))
        (cond
          ((and (pair? raw) (eq? (car raw) 'c-str) (pair? (cdr raw)) (string? (cadr raw)))
           (let* ((s (cadr raw))
                  (len (string-length s))
                  (inner (cond
                           ((and (>= len 3) (char=? (string-ref s 0) #\L) (char=? (string-ref s 1) #\"))
                            (substring s 2 (- len 1)))
                           ((and (>= len 2) (char=? (string-ref s 0) #\"))
                            (substring s 1 (- len 1)))
                           (else s))))
             (set-car! acc (cons inner (car acc)))))
          ((pair? raw)
           (walk (car raw))
           (walk (cdr raw))))))
    (string-append "\"" (apply string-append (reverse (car acc))) "\"")))

(define (%c99-unquote-simple-c-str s)
  (let* ((n (string-length s))
         (body (if (and (>= n 2) (char=? (string-ref s 0) #\") (char=? (string-ref s (- n 1)) #\"))
                   (substring s 1 (- n 1))
                   s))
         (bn (string-length body)))
    (let loop ((i 0) (chars '()))
      (if (>= i bn)
          (list->string (reverse chars))
          (let ((ch (string-ref body i)))
            (if (and (char=? ch #\\) (< (+ i 1) bn))
                (let ((nx (string-ref body (+ i 1))))
                  (case nx
                    ((#\n) (loop (+ i 2) (cons #\newline chars)))
                    ((#\t) (loop (+ i 2) (cons #\tab chars)))
                    ((#\r) (loop (+ i 2) (cons (integer->char 13) chars)))
                    ((#\\) (loop (+ i 2) (cons #\\ chars)))
                    ((#\") (loop (+ i 2) (cons #\" chars)))
                    (else (loop (+ i 2) (cons nx chars)))))
                (loop (+ i 1) (cons ch chars))))))))

(define (%c99-strip-attr-underscores sym)
  (let* ((s (symbol->string sym))
         (n (string-length s)))
    (if (and (>= n 5)
             (char=? (string-ref s 0) #\_) (char=? (string-ref s 1) #\_)
             (char=? (string-ref s (- n 2)) #\_) (char=? (string-ref s (- n 1)) #\_))
        (string->symbol (substring s 2 (- n 2)))
        sym)))

(define (%c99-collect-attr-tokens node)
  (let ((acc (cons '() '())))
    (let walk ((n node))
      (let ((raw (ast-strip-span n)))
        (cond
          ((null? raw) #f)
          ((boolean? raw) #f)
          ((symbol? raw)
           (set-car! acc (cons (%c99-strip-attr-underscores raw) (car acc))))
          ((and (pair? raw) (eq? (car raw) 'c-str) (pair? (cdr raw)) (string? (cadr raw)))
           (set-car! acc (cons (%c99-unquote-simple-c-str (cadr raw)) (car acc))))
          ((and (pair? raw) (eq? (car raw) 'c-const) (pair? (cdr raw)) (string? (cadr raw)))
           (set-car! acc (cons (cadr raw) (car acc))))
          ((pair? raw)
           (walk (car raw))
           (walk (cdr raw))))))
    (reverse (car acc))))

(define (%c99-fold-binop-cst res env ctx pos end-pos)
  (let ((lhs (cdr (car res)))
        (rest (cdr (cadr res))))
    (if (null? rest)
        lhs
        (let loop ((items rest) (acc lhs))
          (if (null? items)
              acc
              (let* ((item (car items))
                     (op-str (%c99-string-trim-right-ws (%c99-cst->string (car item))))
                     (op-sym (%c99-binop-str->sym op-str))
                     (rhs (%c99-list-last item))
                     (sp (%c99-make-span-from-pos env ctx pos end-pos)))
                (loop (cdr items)
                      (ast-with-span (list 'c-binop op-sym acc rhs) sp))))))))

;;; -----------------------------------------------------------------------
;;; 4b. Fast Direct C99 Lexical Scanners (Shared by Parser & Lexer)
;;; -----------------------------------------------------------------------

(define *c99-keyword-symbols*
  '(auto break case char const continue default do double else enum extern
    float for goto if inline int long register restrict return short signed
    sizeof static struct switch typedef union unsigned void volatile while
    _Bool _Complex _Imaginary _Alignof __alignof__ __alignof
    __builtin_offsetof __builtin_va_arg))

(define (%c-ident-start-char? ch)
  (let ((c (char->integer ch)))
    (or (and (>= c 97) (<= c 122))
        (and (>= c 65) (<= c 90))
        (= c 95))))

(define (%c-ident-cont-char? ch)
  (let ((c (char->integer ch)))
    (or (and (>= c 97) (<= c 122))
        (and (>= c 65) (<= c 90))
        (and (>= c 48) (<= c 57))
        (= c 95))))

(define (%c-dec-digit-char? ch)
  (let ((c (char->integer ch)))
    (and (>= c 48) (<= c 57))))

(define (%c-oct-digit-char? ch)
  (let ((c (char->integer ch)))
    (and (>= c 48) (<= c 55))))

(define (%c-hex-digit-char? ch)
  (let ((c (char->integer ch)))
    (or (and (>= c 48) (<= c 57))
        (and (>= c 97) (<= c 102))
        (and (>= c 65) (<= c 70)))))

(define (%c-ws-char? ch)
  (let ((c (char->integer ch)))
    (or (= c 32) (= c 9) (= c 13) (= c 10))))

(define (%c-scan-ws-end text len pos)
  (let loop ((p pos))
    (if (>= p len)
        p
        (let ((ch (string-ref text p)))
          (cond
            ((%c-ws-char? ch)
             (loop (+ p 1)))
            ((or (char=? ch #\#)
                 (and (char=? ch #\/)
                      (< (+ p 1) len)
                      (char=? (string-ref text (+ p 1)) #\/)))
             (let skip-eol ((q (+ p (if (char=? ch #\#) 1 2))))
               (if (>= q len)
                   q
                   (let ((c2 (string-ref text q)))
                     (if (or (char=? c2 #\newline) (char=? c2 #\return))
                         (loop q)
                         (skip-eol (+ q 1)))))))
            ((and (char=? ch #\/)
                  (< (+ p 1) len)
                  (char=? (string-ref text (+ p 1)) #\*))
             (let skip-bc ((q (+ p 2)))
               (cond
                 ((>= (+ q 1) len) p)
                 ((and (char=? (string-ref text q) #\*)
                       (char=? (string-ref text (+ q 1)) #\/))
                  (loop (+ q 2)))
                 (else (skip-bc (+ q 1))))))
            (else p))))))

(define (%c-scan-char-lit-end text len pos)
  (let ((q0 (if (and (< (+ pos 1) len)
                     (char=? (string-ref text pos) #\L)
                     (char=? (string-ref text (+ pos 1)) #\'))
                (+ pos 1)
                pos)))
    (if (not (and (< q0 len) (char=? (string-ref text q0) #\')))
        #f
        (let loop ((p (+ q0 1)) (count 0))
          (if (>= p len)
              #f
              (let ((ch (string-ref text p)))
                (cond
                  ((char=? ch #\')
                   (if (> count 0) (+ p 1) #f))
                  ((char=? ch #\\)
                   (if (< (+ p 1) len)
                       (loop (+ p 2) (+ count 1))
                       #f))
                  ((or (char=? ch #\newline) (char=? ch #\return))
                   #f)
                  (else
                   (loop (+ p 1) (+ count 1))))))))))

(define (%c-scan-string-lit-end text len pos)
  (let ((q0 (if (and (< (+ pos 1) len)
                     (char=? (string-ref text pos) #\L)
                     (char=? (string-ref text (+ pos 1)) #\"))
                (+ pos 1)
                pos)))
    (if (not (and (< q0 len) (char=? (string-ref text q0) #\")))
        #f
        (let loop ((p (+ q0 1)))
          (if (>= p len)
              #f
              (let ((ch (string-ref text p)))
                (cond
                  ((char=? ch #\")
                   (+ p 1))
                  ((char=? ch #\\)
                   (if (< (+ p 1) len)
                       (loop (+ p 2))
                       #f))
                  ((or (char=? ch #\newline) (char=? ch #\return))
                   #f)
                  (else
                   (loop (+ p 1))))))))))

(define (%c-scan-ident-end text len pos)
  (if (and (< pos len) (%c-ident-start-char? (string-ref text pos)))
      (let loop ((p (+ pos 1)))
        (if (and (< p len) (%c-ident-cont-char? (string-ref text p)))
            (loop (+ p 1))
            p))
      #f))

(define (%c-scan-dec-digits-end text len pos)
  (let loop ((p pos))
    (if (and (< p len) (%c-dec-digit-char? (string-ref text p)))
        (loop (+ p 1))
        p)))

(define (%c-scan-oct-digits-end text len pos)
  (let loop ((p pos))
    (if (and (< p len) (%c-oct-digit-char? (string-ref text p)))
        (loop (+ p 1))
        p)))

(define (%c-scan-hex-digits-end text len pos)
  (let loop ((p pos))
    (if (and (< p len) (%c-hex-digit-char? (string-ref text p)))
        (loop (+ p 1))
        p)))

(define (%c-scan-exponent-end text len pos ch-lo ch-hi)
  (if (and (< pos len)
           (let ((ch (string-ref text pos)))
             (or (char=? ch ch-lo) (char=? ch ch-hi))))
      (let* ((p1 (+ pos 1))
             (p2 (if (and (< p1 len)
                          (let ((s (string-ref text p1)))
                            (or (char=? s #\+) (char=? s #\-))))
                     (+ p1 1)
                     p1))
             (p3 (%c-scan-dec-digits-end text len p2)))
        (if (> p3 p2) p3 #f))
      #f))

(define (%c-scan-float-suffix-guard text len pos)
  (let ((p1 (if (and (< pos len)
                     (let ((ch (string-ref text pos)))
                       (or (char=? ch #\f) (char=? ch #\F)
                           (char=? ch #\l) (char=? ch #\L))))
                (+ pos 1)
                pos)))
    (if (and (< p1 len) (%c-ident-cont-char? (string-ref text p1)))
        #f
        p1)))

(define (%c-scan-float-end text len pos)
  (if (>= pos len)
      #f
      (let ((c0 (string-ref text pos)))
        (cond
          ;; Hex float: 0x / 0X ...
          ((and (char=? c0 #\0)
                (< (+ pos 2) len)
                (let ((c1 (string-ref text (+ pos 1))))
                  (or (char=? c1 #\x) (char=? c1 #\X))))
           (let* ((q1 (%c-scan-hex-digits-end text len (+ pos 2)))
                  (n-pre (- q1 (+ pos 2))))
             (if (and (< q1 len) (char=? (string-ref text q1) #\.))
                 (let* ((q2 (%c-scan-hex-digits-end text len (+ q1 1)))
                        (n-post (- q2 (+ q1 1))))
                   (if (or (> n-pre 0) (> n-post 0))
                       (let ((exp-end (%c-scan-exponent-end text len q2 #\p #\P)))
                         (and exp-end (%c-scan-float-suffix-guard text len exp-end)))
                       #f))
                 (if (> n-pre 0)
                     (let ((exp-end (%c-scan-exponent-end text len q1 #\p #\P)))
                       (and exp-end (%c-scan-float-suffix-guard text len exp-end)))
                     #f))))
          ;; Decimal float: [0-9]* '.' [0-9]+ ... | [0-9]+ '.' ... | [0-9]+ dec_exp ...
          ((or (%c-dec-digit-char? c0) (char=? c0 #\.))
           (let* ((d1 (%c-scan-dec-digits-end text len pos))
                  (n-int (- d1 pos)))
             (if (and (< d1 len) (char=? (string-ref text d1) #\.))
                 (let* ((d2 (%c-scan-dec-digits-end text len (+ d1 1)))
                        (n-frac (- d2 (+ d1 1))))
                   (if (or (> n-int 0) (> n-frac 0))
                       (let* ((exp-end (%c-scan-exponent-end text len d2 #\e #\E))
                              (tail-start (or exp-end d2)))
                         (%c-scan-float-suffix-guard text len tail-start))
                       #f))
                 (if (> n-int 0)
                     (let ((exp-end (%c-scan-exponent-end text len d1 #\e #\E)))
                       (and exp-end (%c-scan-float-suffix-guard text len exp-end)))
                     #f))))
          (else #f)))))

(define (%c-scan-l-suffix text len pos)
  (if (< pos len)
      (let ((c0 (string-ref text pos)))
        (cond
          ((or (char=? c0 #\l) (char=? c0 #\L))
           (if (and (< (+ pos 1) len) (char=? (string-ref text (+ pos 1)) c0))
               (+ pos 2)
               (+ pos 1)))
          (else pos)))
      pos))

(define (%c-scan-int-suffix-guard text len pos)
  (let ((after
         (if (< pos len)
             (let ((c0 (string-ref text pos)))
               (cond
                 ((or (char=? c0 #\u) (char=? c0 #\U))
                  (%c-scan-l-suffix text len (+ pos 1)))
                 ((or (char=? c0 #\l) (char=? c0 #\L))
                  (let ((p1 (%c-scan-l-suffix text len pos)))
                    (if (and (< p1 len)
                             (let ((cu (string-ref text p1)))
                               (or (char=? cu #\u) (char=? cu #\U))))
                        (+ p1 1)
                        p1)))
                 (else pos)))
             pos)))
    (if (and (< after len) (%c-ident-cont-char? (string-ref text after)))
        #f
        after)))

(define (%c-scan-int-end text len pos)
  (if (not (and (< pos len) (%c-dec-digit-char? (string-ref text pos))))
      #f
      (let ((c0 (string-ref text pos)))
        (cond
          ((char=? c0 #\0)
           (if (and (< (+ pos 1) len)
                    (let ((c1 (string-ref text (+ pos 1))))
                      (or (char=? c1 #\x) (char=? c1 #\X))))
               (let ((qh (%c-scan-hex-digits-end text len (+ pos 2))))
                 (if (> qh (+ pos 2))
                     (%c-scan-int-suffix-guard text len qh)
                     (%c-scan-int-suffix-guard text len (+ pos 1))))
               (%c-scan-int-suffix-guard text len (%c-scan-oct-digits-end text len (+ pos 1)))))
          (else
           (%c-scan-int-suffix-guard text len (%c-scan-dec-digits-end text len (+ pos 1))))))))

(define (%c-scan-punct-end text len pos)
  (if (>= pos len)
      #f
      (let ((c0 (string-ref text pos))
            (c1 (if (< (+ pos 1) len) (string-ref text (+ pos 1)) #f))
            (c2 (if (< (+ pos 2) len) (string-ref text (+ pos 2)) #f)))
        (cond
          ;; 3-char punctuators: <<= >>= ...
          ((and c2
                (or (and (char=? c0 #\<) (char=? c1 #\<) (char=? c2 #\=))
                    (and (char=? c0 #\>) (char=? c1 #\>) (char=? c2 #\=))
                    (and (char=? c0 #\.) (char=? c1 #\.) (char=? c2 #\.))))
           (+ pos 3))
          ;; 2-char punctuators
          ((and c1
                (or (and (char=? c0 #\-) (or (char=? c1 #\>) (char=? c1 #\-) (char=? c1 #\=)))
                    (and (char=? c0 #\+) (or (char=? c1 #\+) (char=? c1 #\=)))
                    (and (char=? c0 #\<) (or (char=? c1 #\<) (char=? c1 #\=) (char=? c1 #\:) (char=? c1 #\%)))
                    (and (char=? c0 #\>) (or (char=? c1 #\>) (char=? c1 #\=)))
                    (and (char=? c0 #\=) (char=? c1 #\=))
                    (and (char=? c0 #\!) (char=? c1 #\=))
                    (and (char=? c0 #\&) (or (char=? c1 #\&) (char=? c1 #\=)))
                    (and (char=? c0 #\|) (or (char=? c1 #\|) (char=? c1 #\=)))
                    (and (char=? c0 #\*) (char=? c1 #\=))
                    (and (char=? c0 #\/) (char=? c1 #\=))
                    (and (char=? c0 #\%) (or (char=? c1 #\=) (char=? c1 #\>) (char=? c1 #\:)))
                    (and (char=? c0 #\^) (char=? c1 #\=))
                    (and (char=? c0 #\#) (char=? c1 #\#))
                    (and (char=? c0 #\:) (char=? c1 #\>))))
           (+ pos 2))
          ;; 1-char punctuators: [ ] ( ) { } . & * + - ~ ! / % < > ^ | ? : ; = , #
          ((case c0
             ((#\[ #\] #\( #\) #\{ #\} #\. #\& #\* #\+ #\- #\~ #\! #\/ #\% #\< #\> #\^ #\| #\? #\: #\; #\= #\, #\#)
              #t)
             (else #f))
           (+ pos 1))
          (else #f)))))

(define (%c-scan-raw-token text len pos)
  (let ((ch-end (%c-scan-char-lit-end text len pos)))
    (if ch-end
        (cons 'ch ch-end)
        (let ((str-end (%c-scan-string-lit-end text len pos)))
          (if str-end
              (cons 'str str-end)
              (let ((id-end (%c-scan-ident-end text len pos)))
                (if id-end
                    (let ((sym (string->symbol (substring text pos id-end))))
                      (cons (if (memq sym *c99-keyword-symbols*) 'kw 'id) id-end))
                    (let ((flt-end (%c-scan-float-end text len pos)))
                      (if flt-end
                          (cons 'flt flt-end)
                          (let ((int-end (%c-scan-int-end text len pos)))
                            (if int-end
                                (cons 'int int-end)
                                (let ((pun-end (%c-scan-punct-end text len pos)))
                                  (if pun-end
                                      (cons 'punct pun-end)
                                      #f)))))))))))))

(define (%c99-scan-binop text len pos)
  (if (>= pos len)
      #f
      (let ((c0 (string-ref text pos))
            (c1 (if (< (+ pos 1) len) (string-ref text (+ pos 1)) #f))
            (c2 (if (< (+ pos 2) len) (string-ref text (+ pos 2)) #f)))
        (cond
          ;; prec 1: ||
          ((and (char=? c0 #\|) c1 (char=? c1 #\|))
           (list 'lor 1 (+ pos 2)))
          ;; prec 2: &&
          ((and (char=? c0 #\&) c1 (char=? c1 #\&))
           (list 'land 2 (+ pos 2)))
          ;; prec 3: | !('|' | '=')
          ((and (char=? c0 #\|) (not (and c1 (or (char=? c1 #\|) (char=? c1 #\=)))))
           (list 'bit-or 3 (+ pos 1)))
          ;; prec 4: ^ !'='
          ((and (char=? c0 #\^) (not (and c1 (char=? c1 #\=))))
           (list 'bit-xor 4 (+ pos 1)))
          ;; prec 5: & !('&' | '=')
          ((and (char=? c0 #\&) (not (and c1 (or (char=? c1 #\&) (char=? c1 #\=)))))
           (list 'bit-and 5 (+ pos 1)))
          ;; prec 6: == | !=
          ((and (char=? c0 #\=) c1 (char=? c1 #\=))
           (list '== 6 (+ pos 2)))
          ((and (char=? c0 #\!) c1 (char=? c1 #\=))
           (list '!= 6 (+ pos 2)))
          ;; prec 7: <= | >= | < !('<' | '=') | > !('>' | '=')
          ((and (char=? c0 #\<) c1 (char=? c1 #\=))
           (list '<= 7 (+ pos 2)))
          ((and (char=? c0 #\>) c1 (char=? c1 #\=))
           (list '>= 7 (+ pos 2)))
          ((and (char=? c0 #\<) (not (and c1 (or (char=? c1 #\<) (char=? c1 #\=)))))
           (list '< 7 (+ pos 1)))
          ((and (char=? c0 #\>) (not (and c1 (or (char=? c1 #\>) (char=? c1 #\=)))))
           (list '> 7 (+ pos 1)))
          ;; prec 8: << !'=' | >> !'='
          ((and (char=? c0 #\<) c1 (char=? c1 #\<) (not (and c2 (char=? c2 #\=))))
           (list '<< 8 (+ pos 2)))
          ((and (char=? c0 #\>) c1 (char=? c1 #\>) (not (and c2 (char=? c2 #\=))))
           (list '>> 8 (+ pos 2)))
          ;; prec 9: + !('+' | '=') | - !('-' | '=' | '>')
          ((and (char=? c0 #\+) (not (and c1 (or (char=? c1 #\+) (char=? c1 #\=)))))
           (list '+ 9 (+ pos 1)))
          ((and (char=? c0 #\-) (not (and c1 (or (char=? c1 #\-) (char=? c1 #\=) (char=? c1 #\>)))))
           (list '- 9 (+ pos 1)))
          ;; prec 10: * !'=' | / !('=' | '/' | '*') | % !'='
          ((and (char=? c0 #\*) (not (and c1 (char=? c1 #\=))))
           (list '* 10 (+ pos 1)))
          ((and (char=? c0 #\/) (not (and c1 (or (char=? c1 #\=) (char=? c1 #\/) (char=? c1 #\*)))))
           (list '/ 10 (+ pos 1)))
          ((and (char=? c0 #\%) (not (and c1 (char=? c1 #\=))))
           (list 'rem 10 (+ pos 1)))
          (else #f)))))

(define (%c99-make-pratt-binop-parser env lookup-cell base-min-prec)
  (let ((cast-cell (lookup-cell 'cast_expr)))
    (letrec ((parse-prec
              (lambda (ctx start-pos min-prec sk fk)
                ((car cast-cell) ctx start-pos
                 (lambda (lhs next-pos lhs-fk)
                   (let ((txt (parse-ctx-text ctx))
                         (len (parse-ctx-length ctx)))
                     (let climb ((acc lhs) (cur-pos next-pos) (cur-fk lhs-fk))
                       (let ((hit (%c99-scan-binop txt len cur-pos)))
                         (if (and hit (>= (cadr hit) min-prec))
                             (let* ((op-sym (car hit))
                                    (prec   (cadr hit))
                                    (op-end (caddr hit))
                                    (rhs-pos (%c-scan-ws-end txt len op-end)))
                               (parse-prec ctx rhs-pos (+ prec 1)
                                           (lambda (rhs rhs-end rhs-fk)
                                             (let ((sp (%c99-make-span-from-pos env ctx start-pos rhs-end)))
                                               (climb (ast-with-span (list 'c-binop op-sym acc rhs) sp)
                                                      rhs-end
                                                      rhs-fk)))
                                           (lambda ()
                                             (sk acc cur-pos cur-fk))))
                             (sk acc cur-pos cur-fk))))))
                 fk))))
      (lambda (ctx pos sk fk)
        (parse-prec ctx pos base-min-prec sk fk)))))

;;; -----------------------------------------------------------------------
;;; 5. Direct-Style C99 Hooks & AST Decorators (Issue #949 — Zero CPS)
;;; -----------------------------------------------------------------------

(define (%c99ds-ret ctx end-pos val)
  (parse-ctx-res-val-set! ctx val)
  end-pos)

(define (%c99ds-ret-span env ctx start-pos end-pos val)
  (let ((sp (%c99-make-span-from-pos env ctx start-pos end-pos)))
    (parse-ctx-res-val-set! ctx (ast-with-span val sp))
    end-pos))

;;; Direct-Style fast lexical leaf scanners: (ctx env pos) -> next-pos | #f

(define (c99ds-leaf-ws ctx env pos)
  (let ((np (%c-scan-ws-end (parse-ctx-text ctx) (parse-ctx-length ctx) pos)))
    (%c99ds-ret ctx np "")))

(define (c99ds-leaf-ident-cont ctx env pos)
  (let ((txt (parse-ctx-text ctx))
        (len (parse-ctx-length ctx)))
    (if (and (< pos len) (%c-ident-cont-char? (string-ref txt pos)))
        (%c99ds-ret ctx (+ pos 1) (string (string-ref txt pos)))
        #f)))

(define (c99ds-leaf-keyword ctx env pos)
  (let* ((txt (parse-ctx-text ctx))
         (len (parse-ctx-length ctx))
         (end (%c-scan-ident-end txt len pos)))
    (if (and end (memq (string->symbol (substring txt pos end)) *c99-keyword-symbols*))
        (%c99ds-ret ctx end (substring txt pos end))
        #f)))

(define (c99ds-leaf-identifier ctx env pos)
  (let* ((txt (parse-ctx-text ctx))
         (len (parse-ctx-length ctx))
         (end (%c-scan-ident-end txt len pos)))
    (if end
        (let ((sym (string->symbol (substring txt pos end))))
          (if (memq sym *c99-keyword-symbols*)
              (begin
                (parse-ctx-update-max-pos! ctx pos "identifier")
                #f)
              (%c99ds-ret ctx end sym)))
        (begin
          (parse-ctx-update-max-pos! ctx pos "identifier")
          #f))))

(define (c99ds-leaf-constant ctx env pos)
  (let* ((txt (parse-ctx-text ctx))
         (len (parse-ctx-length ctx))
         (end (or (%c-scan-float-end txt len pos)
                  (%c-scan-int-end txt len pos)
                  (%c-scan-char-lit-end txt len pos))))
    (if end
        (%c99ds-ret-span env ctx pos end (list 'c-const (substring txt pos end)))
        (begin
          (parse-ctx-update-max-pos! ctx pos "constant")
          #f))))

(define (c99ds-leaf-string-literal ctx env pos)
  (let* ((txt (parse-ctx-text ctx))
         (len (parse-ctx-length ctx))
         (end (%c-scan-string-lit-end txt len pos)))
    (if end
        (%c99ds-ret-span env ctx pos end (list 'c-str (substring txt pos end)))
        (begin
          (parse-ctx-update-max-pos! ctx pos "string_literal")
          #f))))

;;; Direct-Style 10-level Pratt Precedence Climber (zero closures, zero local set!)

(define (c99ds-pratt-binop ctx env start-pos min-prec)
  (let ((first-pos (c99ds-cast_expr ctx env start-pos)))
    (if (not first-pos)
        #f
        (let ((txt (parse-ctx-text ctx))
              (len (parse-ctx-length ctx)))
          (let climb ((acc (parse-ctx-res-val ctx)) (cur-pos first-pos))
            (let ((hit (%c99-scan-binop txt len cur-pos)))
              (if (and hit (>= (cadr hit) min-prec))
                  (let* ((op-sym (car hit))
                         (prec   (cadr hit))
                         (op-end (caddr hit))
                         (rhs-pos (%c-scan-ws-end txt len op-end))
                         (rhs-end (c99ds-pratt-binop ctx env rhs-pos (+ prec 1))))
                    (if rhs-end
                        (let ((sp (%c99-make-span-from-pos env ctx start-pos rhs-end)))
                          (climb (ast-with-span (list 'c-binop op-sym acc (parse-ctx-res-val ctx)) sp)
                                 rhs-end))
                        (%c99ds-ret ctx cur-pos acc)))
                  (%c99ds-ret ctx cur-pos acc))))))))

;;; Direct-Style Scoped & Delegated Rule Overrides

(define (c99ds-override-typedef-init-declarator ctx env pos)
  (c99ds-init_declarator ctx env pos))

(define (c99ds-override-compound-stmt ctx env pos)
  (let ((p0 (peg-ds:lit1 ctx pos #\{ "{" "'{'")))
    (if (not p0)
        #f
        (let ((p1 (c99ds-ws ctx env p0)))
          (c99-push-scope! env 'block)
          (let loop ((cur-pos p1) (items '()))
            (let ((next-pos (c99ds-block_item ctx env cur-pos)))
              (if (and next-pos (> next-pos cur-pos))
                  (loop next-pos (cons (parse-ctx-res-val ctx) items))
                  (let ((p-rb (peg-ds:lit1 ctx cur-pos #\} "}" "'}'")))
                    (if (not p-rb)
                        (begin
                          (c99-pop-scope! env)
                          #f)
                        (let ((end-pos (c99ds-ws ctx env p-rb)))
                          (c99-pop-scope! env)
                          (%c99ds-ret-span env ctx pos end-pos
                                           (cons 'c-block (reverse items)))))))))))))

(define (c99ds-override-function-definition ctx env pos)
  (let ((pos1 (c99ds-declaration_specifiers ctx env pos)))
    (if (not pos1)
        #f
        (let ((specs (parse-ctx-res-val ctx))
              (pos2 (c99ds-declarator ctx env pos1)))
          (if (not pos2)
              #f
              (let ((decl (parse-ctx-res-val ctx)))
                (let attr-loop ((cur-p pos2) (attrs '()))
                  (let ((ap (c99ds-gnu_attribute ctx env cur-p)))
                    (if (and ap (> ap cur-p))
                        (attr-loop ap (cons (parse-ctx-res-val ctx) attrs))
                        (let* ((fn-attrs (reverse attrs))
                               (fn-names (%c99-extract-declarator-names decl))
                               (fn-sym (if (pair? fn-names) (car fn-names) 'anon_fn))
                               (param-syms (%c99-extract-fn-param-names decl))
                               (full-specs (if (pair? fn-attrs) (append specs fn-attrs) specs))
                               (fn-sp (%c99-make-span-from-pos env ctx pos cur-p)))
                          (c99-register-var! env fn-sym 'function fn-sp)
                          (c99-push-scope! env 'function)
                          (let ((param-bindings
                                 (map (lambda (psym)
                                        (let ((b (c99-register-var! env psym 'parameter fn-sp)))
                                          (list psym (binding-id b))))
                                      param-syms))
                                (dlist-pos (c99ds-declaration_list ctx env cur-p)))
                            (let ((body-start (or dlist-pos cur-p)))
                              (let ((end-pos (c99ds-compound_stmt ctx env body-start)))
                                (c99-pop-scope! env)
                                (if (not end-pos)
                                    #f
                                    (let ((body (parse-ctx-res-val ctx)))
                                      (%c99ds-ret-span
                                       env ctx pos end-pos
                                       (list 'c-fn-def fn-sym full-specs decl param-bindings body)))))))))))))))))

;;; Direct-Style AST Builder & Scope Decorator

(define (c99ds-decorate-rule name ctx env pos next-pos res)
  (case name
    ((typedef_name)
     (if (c99-typedef-bound? env res)
         (%c99ds-ret ctx next-pos (list 'c-typedef-name res (c99-lookup-binding-id env res)))
         #f))

    ((storage_class_specifier builtin_type_specifier type_qualifier function_specifier struct_or_union)
     (%c99ds-ret ctx next-pos (string->symbol (%c99-string-trim-right-ws (%c99-cst->string res)))))

    ((explicit_declaration_specifiers typedef_declaration_specifiers specifier_qualifier_list)
     (%c99ds-ret ctx next-pos (%c99-flatten-decl-specs res)))

    ((pointer)
     (%c99ds-ret
      ctx next-pos
      (map (lambda (level)
             (let ((q (if (>= (length level) 3) (list-ref level 2) #f)))
               (if q (%c99-flatten-decl-specs q) '())))
           res)))

    ((direct_declarator)
     (%c99ds-ret
      ctx next-pos
      (cond
        ((and (pair? res) (symbol? (car res)))
         (list 'c-decl-id (car res)))
        ((and (pair? res) (string? (car res)) (string=? (car res) "("))
         (list-ref res 2))
        ((and (pair? res) (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "["))
         (let ((nlen (length res)))
           (cond
             ((= nlen 7) (list 'c-arr-declarator (car res) (list-ref res 4)))
             ((= nlen 10) (list 'c-arr-declarator (car res) (list-ref res 7)))
             (else (list 'c-arr-declarator (car res) #f)))))
        ((and (pair? res) (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "("))
         (list 'c-fn-declarator (car res)
               (let ((p (list-ref res 3)))
                 (if p p '(c-param-list () #f)))))
        (else res))))

    ((declarator)
     (let ((ptr (car res))
           (dd (cadr res)))
       (%c99ds-ret ctx next-pos
                   (if (pair? ptr) (list 'c-ptr-declarator ptr dd) dd))))

    ((direct_abstract_declarator)
     (%c99ds-ret
      ctx next-pos
      (cond
        ((not (pair? res)) res)
        ((string? (car res))
         (cond
           ((string=? (car res) "(")
            (let ((inner (list-ref res 2)))
              (if (or (not inner) (and (pair? inner) (eq? (car inner) 'c-param-list)))
                  (list 'c-fn-declarator #f (or inner '(c-param-list () #f)))
                  inner)))
           ((string=? (car res) "[")
            (let ((nlen (length res)))
              (cond
                ((= nlen 6) (list 'c-arr-declarator #f (list-ref res 3)))
                ((= nlen 9) (list 'c-arr-declarator #f (list-ref res 6)))
                (else (list 'c-arr-declarator #f #f)))))
           (else res)))
        ((and (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "["))
         (let ((nlen (length res)))
           (cond
             ((= nlen 7) (list 'c-arr-declarator (car res) (list-ref res 4)))
             ((= nlen 10) (list 'c-arr-declarator (car res) (list-ref res 7)))
             (else (list 'c-arr-declarator (car res) #f)))))
        ((and (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "("))
         (list 'c-fn-declarator (car res) (or (list-ref res 3) '(c-param-list () #f))))
        (else res))))

    ((abstract_declarator)
     (%c99ds-ret
      ctx next-pos
      (if (and (pair? res) (pair? (car res))
               (or (null? (caar res)) (list? (caar res)))
               (not (memq (caar res) '(c-arr-declarator c-fn-declarator c-ptr-declarator))))
          (list 'c-ptr-declarator (car res) (cadr res))
          res)))

    ((type_name)
     (%c99ds-ret ctx next-pos (list 'c-type-name (car res) (cadr res))))

    ((parameter_list)
     (%c99ds-ret ctx next-pos
                 (cons (cdr (car res))
                       (map cadddr (cdr (cadr res))))))

    ((parameter_type_list)
     (%c99ds-ret ctx next-pos (list 'c-param-list (car res) (if (cadr res) #t #f))))

    ((parameter_declaration)
     (let ((opt-d (cadr res)))
       (%c99ds-ret ctx next-pos (list 'c-param (car res) (if (pair? opt-d) (car opt-d) opt-d)))))

    ((typeof_specifier)
     (%c99ds-ret ctx next-pos (list 'c-typeof (list-ref res 5))))

    ((attr_arg)
     (%c99ds-ret ctx next-pos (%c99-collect-attr-tokens res)))

    ((gnu_attribute)
     (let ((args (list-ref res 7)))
       (%c99ds-ret ctx next-pos (list 'c-attr (if (pair? args) args '())))))

    ((decl_asm_label)
     (%c99ds-ret ctx next-pos (list 'c-reg-decl (%c99-unquote-simple-c-str (list-ref res 5)))))

    ((init_declarator)
     (let* ((decl (car res))
            (opt-asm (list-ref res 1))
            (attrs (list-ref res 2))
            (opt-init (list-ref res 3))
            (wrapped (if (or opt-asm (pair? attrs))
                         (list 'c-attr-decl decl attrs (if opt-asm (cadr opt-asm) #f))
                         decl)))
       (%c99ds-ret ctx next-pos
                   (list 'c-init-decl wrapped (if (pair? opt-init) (list-ref opt-init 2) #f)))))

    ((init_declarator_list typedef_init_declarator_list struct_declarator_list argument_expr_list
      attr_arg_list asm_operand_list asm_clobber_list)
     (%c99ds-ret ctx next-pos
                 (cons (cdr (car res))
                       (map caddr (cdr (cadr res))))))

    ((struct_declarator)
     (%c99ds-ret ctx next-pos
                 (if (and (pair? res) (>= (length res) 4)
                          (string? (cadr res)) (string=? (cadr res) ":"))
                     (list 'c-struct-decl (car res) (list-ref res 3))
                     (list 'c-struct-decl (car res) #f))))

    ((struct_declaration)
     (%c99ds-ret ctx next-pos (list 'c-field-decl (car res) (or (cadr res) '()))))

    ((designator)
     (%c99ds-ret ctx next-pos
                 (if (string=? (car res) "[")
                     (list 'c-desig-index (list-ref res 2))
                     (list 'c-desig-field (list-ref res 2)))))

    ((designation)
     (%c99ds-ret ctx next-pos (car res)))

    ((initializer_item)
     (%c99ds-ret ctx next-pos (list 'c-init-item (car res) (cadr res))))

    ((initializer_list enumerator_list)
     (%c99ds-ret ctx next-pos
                 (cons (cdr (car res))
                       (map cadddr (cdr (cadr res))))))

    ((initializer)
     (%c99ds-ret ctx next-pos
                 (if (and (pair? res) (string? (car res)) (string=? (car res) "{"))
                     (let ((inner (list-ref res 2)))
                       (list 'c-init-list (if (pair? inner) (car inner) '())))
                     res)))

    ((offsetof_designator_suffix)
     (%c99ds-ret ctx next-pos
                 (if (and (pair? res) (string? (car res)) (string=? (car res) "."))
                     (list 'c-desig-field (list-ref res 2))
                     (list 'c-desig-index (list-ref res 2)))))

    ((offsetof_member_designator)
     (%c99ds-ret ctx next-pos (cons (list 'c-desig-field (car res)) (or (list-ref res 2) '()))))

    ((struct_or_union_specifier)
     (let* ((is-union? (eq? (car res) 'union))
            (tag-sym (list-ref res 2))
            (fields (if (>= (length res) 7) (or (list-ref res 6) '()) #f))
            (sp (%c99-make-span-from-pos env ctx pos next-pos)))
       (if (symbol? tag-sym)
           (c99-register-var! env tag-sym (if is-union? 'tag-union 'tag-struct) sp))
       (%c99ds-ret ctx next-pos
                   (ast-with-span (list (if is-union? 'c-union 'c-struct) tag-sym fields) sp))))

    ((enum_specifier)
     (let* ((tag-sym (list-ref res 3))
            (enums (if (>= (length res) 8) (or (list-ref res 7) '()) #f))
            (sp (%c99-make-span-from-pos env ctx pos next-pos)))
       (if (symbol? tag-sym)
           (c99-register-var! env tag-sym 'tag-enum sp))
       (%c99ds-ret ctx next-pos
                   (ast-with-span (list 'c-enum tag-sym enums) sp))))

    ((enumerator)
     (let* ((ec-sym (let ((syms (%c99-flatten-tag-syms (car res))))
                      (if (pair? syms) (car syms) #f)))
            (opt-eq (cadr res))
            (val-expr (if (pair? opt-eq) (list-ref opt-eq 2) #f))
            (sp (%c99-make-span-from-pos env ctx pos next-pos)))
       (if ec-sym
           (c99-register-var! env ec-sym 'enum-const sp))
       (%c99ds-ret ctx next-pos (list 'c-enumerator ec-sym val-expr))))

    ((explicit_declaration typedef_declaration)
     (let* ((specs (car res))
            (inits (or (cadr res) '()))
            (sp (%c99-make-span-from-pos env ctx pos next-pos))
            (is-td? (%c99-has-typedef-spec? specs))
            (decl-names (if (pair? inits) (%c99-extract-declarator-names inits) '())))
       (for-each
        (lambda (sym)
          (if is-td?
              (c99-register-typedef! env sym sp)
              (c99-register-var! env sym 'variable sp)))
        decl-names)
       (%c99ds-ret ctx next-pos
                   (ast-with-span (list (if is-td? 'c-typedef 'c-decl) specs inits) sp))))

    ((asm_template)
     (%c99ds-ret ctx next-pos (%c99-concat-c-str-cst res)))

    ((asm_operand)
     (let* ((opt-name (car res))
            (name-sym (if (pair? opt-name) (list-ref opt-name 2) #f))
            (cstr (list-ref res 1))
            (expr-node (list-ref res 4)))
       (%c99ds-ret ctx next-pos (list name-sym cstr expr-node))))

    ((asm_outputs asm_inputs)
     (%c99ds-ret ctx next-pos (cons 'c-asm-ops (or (list-ref res 2) '()))))

    ((asm_clobbers)
     (%c99ds-ret ctx next-pos (cons 'c-asm-clobs (or (list-ref res 2) '()))))

    ((asm_stmt)
     (let* ((quals (%c99-collect-attr-tokens (list-ref res 3)))
            (tpl (list-ref res 6))
            (opt-outs (list-ref res 7))
            (opt-ins (list-ref res 8))
            (opt-clobs (list-ref res 9))
            (outs (if (and (pair? opt-outs) (eq? (car opt-outs) 'c-asm-ops)) (cdr opt-outs) '()))
            (ins (if (and (pair? opt-ins) (eq? (car opt-ins) 'c-asm-ops)) (cdr opt-ins) '()))
            (clobs (if (and (pair? opt-clobs) (eq? (car opt-clobs) 'c-asm-clobs)) (cdr opt-clobs) '()))
            (vol? (if (or (null? outs)
                          (memq 'volatile quals)
                          (memq '__volatile quals)
                          (memq '__volatile__ quals))
                      #t #f)))
       (%c99ds-ret-span env ctx pos next-pos (list 'c-asm vol? tpl outs ins clobs))))

    ((top_asm_decl)
     (%c99ds-ret-span env ctx pos next-pos (list 'c-top-asm (list-ref res 5))))

    ((expr)
     (%c99ds-ret ctx next-pos (%c99-fold-binop-cst res env ctx pos next-pos)))

    ((assignment_operator)
     (%c99ds-ret ctx next-pos
                 (list 'c-assign-op (%c99-assign-str->sym (%c99-string-trim-right-ws (%c99-cst->string res))))))

    ((assignment_expr)
     (if (and (pair? res) (pair? (cdr res))
              (pair? (cadr res)) (eq? (caadr res) 'c-assign-op))
         (%c99ds-ret-span env ctx pos next-pos
                          (list 'c-assign (cadadr res) (car res) (list-ref res 3)))
         (%c99ds-ret ctx next-pos res)))

    ((conditional_expr)
     (if (and (pair? res) (= (length res) 2))
         (let ((opt-tail (cadr res)))
           (if (pair? opt-tail)
               (%c99ds-ret-span env ctx pos next-pos
                                (list 'c-ternary (car res) (list-ref opt-tail 2) (list-ref opt-tail 5)))
               (%c99ds-ret ctx next-pos (car res))))
         (%c99ds-ret ctx next-pos res)))

    ((cast_expr)
     (if (and (pair? res) (string? (car res)) (string=? (car res) "("))
         (%c99ds-ret-span env ctx pos next-pos (list 'c-cast (list-ref res 2) (list-ref res 6)))
         (%c99ds-ret ctx next-pos res)))

    ((unary_operator)
     (%c99ds-ret ctx next-pos
                 (list 'c-unop-tag (%c99-unop-str->sym (%c99-string-trim-right-ws (%c99-cst->string res))))))

    ((unary_expr)
     (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
       (%c99ds-ret
        ctx next-pos
        (cond
          ((and (pair? res) (string? (car res))
                (or (string=? (car res) "++") (string=? (car res) "--")))
           (ast-with-span (list 'c-unop (if (string=? (car res) "++") 'pre++ 'pre--) (list-ref res 2)) sp))
          ((and (pair? res) (pair? (car res)) (eq? (caar res) 'c-unop-tag))
           (ast-with-span (list 'c-unop (cadar res) (list-ref res 2)) sp))
          ((and (pair? res) (string? (car res)) (string=? (car res) "sizeof"))
           (if (= (length res) 9)
               (ast-with-span (list 'c-sizeof-type (list-ref res 5)) sp)
               (ast-with-span (list 'c-sizeof-expr (list-ref res 3)) sp)))
          ((and (pair? res) (string? (car res))
                (or (string=? (car res) "_Alignof")
                    (string=? (car res) "__alignof__")
                    (string=? (car res) "__alignof")))
           (if (= (length res) 9)
               (ast-with-span (list 'c-alignof-type (list-ref res 5)) sp)
               (ast-with-span (list 'c-alignof-expr (list-ref res 3)) sp)))
          ((and (pair? res) (string? (car res)) (string=? (car res) "__builtin_offsetof"))
           (ast-with-span (list 'c-offsetof (list-ref res 5) (list-ref res 8)) sp))
          ((and (pair? res) (string? (car res)) (string=? (car res) "__extension__"))
           (list-ref res 3))
          (else res)))))

    ((postfix_expr)
     (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
       (%c99ds-ret
        ctx next-pos
        (cond
          ((not (pair? res)) res)
          ((and (string? (car res)) (string=? (car res) "("))
           (let ((inits (list-ref res 7)))
             (ast-with-span (list 'c-compound-lit (list-ref res 2) (if (pair? inits) (car inits) '())) sp)))
          ((and (pair? (cdr res)) (string? (cadr res)))
           (let ((op (cadr res))
                 (base (car res)))
             (cond
               ((string=? op "[") (ast-with-span (list 'c-index base (list-ref res 3)) sp))
               ((string=? op "(")
                (let ((args (list-ref res 3)))
                  (ast-with-span (cons 'c-call (cons base (if (pair? args) args '()))) sp)))
               ((string=? op ".") (ast-with-span (list 'c-member base (list-ref res 3) #f) sp))
               ((string=? op "->") (ast-with-span (list 'c-member base (list-ref res 3) #t) sp))
               ((or (string=? op "++") (string=? op "--"))
                (ast-with-span (list 'c-unop (if (string=? op "++") 'post++ 'post--) base) sp))
               (else res))))
          (else res)))))

    ((primary_expr)
     (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
       (%c99ds-ret
        ctx next-pos
        (cond
          ((and (pair? res) (string? (car res)) (string=? (car res) "__builtin_va_arg"))
           (ast-with-span (list 'c-va-arg (list-ref res 5) (list-ref res 8)) sp))
          ((and (pair? res) (symbol? (car res)))
           (let* ((sym (car res))
                  (bid (c99-lookup-binding-id env sym)))
             (ast-with-span (list 'c-var-ref sym bid) sp)))
          ((and (pair? res)
                (ast-has-span? (car res))
                (eq? (car (ast-strip-span (car res))) 'c-const))
           (car res))
          ((and (pair? res) (string? (car res)) (string=? (car res) "("))
           (list-ref res 2))
          ((and (pair? res)
                (pair? (car res))
                (ast-has-span? (caar res))
                (eq? (car (ast-strip-span (caar res))) 'c-str))
           (%c99-merge-c-str-literals res env ctx pos next-pos))
          (else (ast-with-span res sp))))))

    ((selection_stmt)
     (let ((kw (car res)))
       (%c99ds-ret-span
        env ctx pos next-pos
        (if (string=? kw "if")
            (let ((opt-else (list-ref res 9)))
              (if (pair? opt-else)
                  (list 'c-if (list-ref res 5) (list-ref res 8) (list-ref opt-else 3))
                  (list 'c-if (list-ref res 5) (list-ref res 8))))
            (list 'c-switch (list-ref res 5) (list-ref res 8))))))

    ((iteration_stmt)
     (let ((kw (car res)))
       (%c99ds-ret-span
        env ctx pos next-pos
        (cond
          ((string=? kw "while")
           (list 'c-while (list-ref res 5) (list-ref res 8)))
          ((string=? kw "do")
           (list 'c-do-while (list-ref res 3) (list-ref res 9)))
          ((string=? kw "for")
           (let* ((c1 (list-ref res 5))
                  (c1-stripped (ast-strip-span c1))
                  (init-node (if (and (pair? c1-stripped)
                                      (memq (car c1-stripped) '(c-decl c-typedef)))
                                 c1
                                 (if (pair? c1) (car c1) #f)))
                  (cond-node (list-ref res 6))
                  (step-node (list-ref res 9))
                  (body-node (list-ref res 12)))
             (list 'c-for init-node cond-node step-node body-node)))
          (else (list 'c-iter res))))))

    ((jump_stmt)
     (let ((kw (car res)))
       (%c99ds-ret-span
        env ctx pos next-pos
        (cond
          ((string=? kw "goto") (list 'c-goto (list-ref res 3)))
          ((string=? kw "continue") '(c-continue))
          ((string=? kw "break") '(c-break))
          ((string=? kw "return") (list 'c-return (list-ref res 3)))
          (else (list 'c-jump res))))))

    ((labeled_stmt)
     (let ((head (car res)))
       (%c99ds-ret-span
        env ctx pos next-pos
        (cond
          ((and (string? head) (string=? head "case"))
           (list 'c-case (list-ref res 3) (list-ref res 6)))
          ((and (string? head) (string=? head "default"))
           (list 'c-default (list-ref res 5)))
          ((symbol? head)
           (c99-register-var! env head 'label)
           (list 'c-label head (list-ref res 4)))
          (else (list 'c-labeled res))))))

    ((expr_stmt)
     (%c99ds-ret-span env ctx pos next-pos (list 'c-expr-stmt (car res))))

    ((translation_unit)
     (%c99ds-ret-span env ctx pos next-pos (cons 'c-translation-unit (cadr res))))

    (else
     (%c99ds-ret ctx next-pos res))))

(define *c99ds-decorated-rules*
  '(typedef_name
    storage_class_specifier builtin_type_specifier type_qualifier function_specifier struct_or_union
    explicit_declaration_specifiers typedef_declaration_specifiers specifier_qualifier_list
    pointer direct_declarator declarator direct_abstract_declarator abstract_declarator
    type_name parameter_list parameter_type_list parameter_declaration
    typeof_specifier attr_arg gnu_attribute decl_asm_label init_declarator
    init_declarator_list typedef_init_declarator_list struct_declarator_list argument_expr_list
    attr_arg_list asm_operand_list asm_clobber_list
    struct_declarator struct_declaration designator designation
    initializer_item initializer_list enumerator_list initializer
    offsetof_designator_suffix offsetof_member_designator
    struct_or_union_specifier enum_specifier enumerator
    explicit_declaration typedef_declaration
    asm_template asm_operand asm_outputs asm_inputs asm_clobbers asm_stmt top_asm_decl
    expr assignment_operator assignment_expr conditional_expr cast_expr
    unary_operator unary_expr postfix_expr primary_expr
    selection_stmt iteration_stmt jump_stmt labeled_stmt expr_stmt translation_unit))

(define (c99-emit-scheme-options)
  (list
   (cons 'prefix "c99ds-")
   (cons 'entry 'translation_unit)
   (cons 'extra-params '(env))
   (cons 'memo-mode 'all)
   (cons 'no-memo '(typedef_name ws ident_cont c99_keyword identifier constant string_literal typedef_init_declarator
                    storage_class_specifier builtin_type_specifier type_qualifier function_specifier
                    struct_or_union enumeration_constant type_qualifier_list identifier_list
                    unary_operator assignment_operator c99_punctuator c99_raw_token
                    float_constant integer_constant char_constant escape_seq
                    float_suffix integer_suffix decimal_exponent binary_exponent
                    line_comment block_comment pp_line
                    compound_stmt function_definition block_item
                    asm_qual offsetof_designator_suffix decl_asm_label))
   (cons 'force-lr '(direct_declarator direct_abstract_declarator postfix_expr declarator abstract_declarator unary_expr cast_expr primary_expr))
   (cons 'force-memo '(logical_or_expr logical_and_expr inclusive_or_expr exclusive_or_expr and_expr equality_expr relational_expr shift_expr additive_expr multiplicative_expr))
   (cons 'rule-decorator (cons "c99ds-decorate-rule" *c99ds-decorated-rules*))
   (cons 'overrides
         (list
          (cons 'ws "(c99ds-leaf-ws ctx env pos)")
          (cons 'ident_cont "(c99ds-leaf-ident-cont ctx env pos)")
          (cons 'c99_keyword "(c99ds-leaf-keyword ctx env pos)")
          (cons 'identifier "(c99ds-leaf-identifier ctx env pos)")
          (cons 'constant "(c99ds-leaf-constant ctx env pos)")
          (cons 'string_literal "(c99ds-leaf-string-literal ctx env pos)")
          (cons 'typedef_init_declarator "(c99ds-override-typedef-init-declarator ctx env pos)")
          (cons 'compound_stmt "(c99ds-override-compound-stmt ctx env pos)")
          (cons 'function_definition "(c99ds-override-function-definition ctx env pos)")
          (cons 'logical_or_expr "(c99ds-pratt-binop ctx env pos 1)")
          (cons 'logical_and_expr "(c99ds-pratt-binop ctx env pos 2)")
          (cons 'inclusive_or_expr "(c99ds-pratt-binop ctx env pos 3)")
          (cons 'exclusive_or_expr "(c99ds-pratt-binop ctx env pos 4)")
          (cons 'and_expr "(c99ds-pratt-binop ctx env pos 5)")
          (cons 'equality_expr "(c99ds-pratt-binop ctx env pos 6)")
          (cons 'relational_expr "(c99ds-pratt-binop ctx env pos 7)")
          (cons 'shift_expr "(c99ds-pratt-binop ctx env pos 8)")
          (cons 'additive_expr "(c99ds-pratt-binop ctx env pos 9)")
          (cons 'multiplicative_expr "(c99ds-pratt-binop ctx env pos 10)")))))

;;; -----------------------------------------------------------------------
;;; 6. Top-Level Parse API & Pretty Diagnostic Integration
;;; -----------------------------------------------------------------------

(define (%c99-get-cached-env filename src-text)
  (let ((cached (car *c99-cached-env-parser*)))
    (if cached
        (let ((env (car cached)))
          (c99-parse-env-scope-mgr-set! env (c99-make-init-scope-manager))
          (c99-parse-env-file-set! env filename)
          (c99-parse-env-text-set! env src-text)
          (c99-parse-env-line-starts-set! env (%c99-build-line-starts src-text))
          env)
        (let ((env (make-c99-parse-env filename)))
          (c99-parse-env-text-set! env src-text)
          (c99-parse-env-line-starts-set! env (%c99-build-line-starts src-text))
          (set-car! *c99-cached-env-parser* (cons env #t))
          env))))

(define (%c99ds-dispatch-entry entry-rule ctx env)
  (case entry-rule
    ((translation_unit) (c99ds-translation_unit ctx env 0))
    ((expr) (c99ds-expr ctx env 0))
    (else (error "Unknown C99 grammar entry rule" entry-rule))))

(define (%c99-validate-grammar-env!)
  (let ((env-path (guard (ex (else #f)) (get-environment-variable "ULISP_C99_GRAMMAR"))))
    (if (and (string? env-path) (> (string-length env-path) 0))
        (if (not (%c99-safe-grammar-path? env-path))
            (error "Unsafe ULISP_C99_GRAMMAR path rejected" env-path)
            (if (not (file-exists? env-path))
                (error "ULISP_C99_GRAMMAR file not found" env-path))))))

(define (%c99ds-run-with-env src-text filename entry-rule env)
  (%c99-validate-grammar-env!)
  (diagnostic-register-source-string! filename src-text)
  (let* ((ctx (make-parse-context src-text))
         (txt-len (string-length src-text))
         (end-pos (%c99ds-dispatch-entry entry-rule ctx env)))
    (if (and end-pos (= end-pos txt-len))
        (parse-ctx-res-val ctx)
        (let* ((err-pos (parse-ctx-max-pos ctx))
               (lc (calc-line-col src-text err-pos))
               (exp (parse-ctx-expected ctx))
               (sp (make-source-span filename (car lc) (cdr lc) (car lc) (cdr lc)
                                     #f (next-source-span-id!)))
               (msg (string-append "C99 syntax error near "
                                   (if (pair? exp) (car exp) "unexpected token")))
               (diag (make-diagnostic 'error "C99-PARSE-001" sp msg)))
          (report-diagnostic diag)
          (raise (list 'c99-syntax-error msg sp exp "C99-PARSE-001"))))))

(define (%c99-run-entry-parser src-text filename entry-rule)
  (reset-alpha-symbol-counter!)
  (let ((env (%c99-get-cached-env filename src-text)))
    (%c99ds-run-with-env src-text filename entry-rule env)))

(define (parse-c99-string src-text . maybe-filename)
  (let ((fname (if (pair? maybe-filename) (car maybe-filename) "<c99-input>")))
    (%c99-run-entry-parser src-text fname 'translation_unit)))

(define (parse-c99-expr-string expr-text . maybe-filename)
  (let ((fname (if (pair? maybe-filename) (car maybe-filename) "<c99-expr>")))
    (%c99-run-entry-parser expr-text fname 'expr)))

(define (parse-c99-tokens tokens . maybe-filename)
  (let* ((fname (if (pair? maybe-filename)
                    (car maybe-filename)
                    (if (pair? tokens)
                        (span-file (c-token-span (car tokens)))
                        "<c99-tokens>")))
         (concat (c-concat-adjacent-string-tokens tokens))
         (src-str (c-tokens->source-string concat)))
    (parse-c99-string src-str fname)))

(define (parse-c99-preprocessed-string src-text . rest)
  (let* ((fname (if (pair? rest) (car rest) "<c99-input>"))
         (ctx   (if (and (pair? rest) (pair? (cdr rest)))
                    (cadr rest)
                    (make-default-cpp-context)))
         (pp-toks (cpp-preprocess-string src-text fname ctx)))
    (parse-c99-tokens pp-toks fname)))

(define (parse-c99-file filepath . maybe-cpp-ctx)
  (let* ((ctx (if (pair? maybe-cpp-ctx) (car maybe-cpp-ctx) (make-default-cpp-context)))
         (pp-toks (cpp-preprocess-file filepath ctx)))
    (parse-c99-tokens pp-toks filepath)))

;;; -----------------------------------------------------------------------
;;; 7. PCH Snapshot State Capture, Restoration & Incremental TU Parsing
;;; -----------------------------------------------------------------------

(define (%c99-only-eof-tokens? tokens)
  (let loop ((xs tokens))
    (cond
      ((null? xs) #t)
      ((eq? (c-token-kind (car xs)) 'eof) (loop (cdr xs)))
      (else #f))))

(define (%c99-clone-binding b)
  (make-binding (binding-id b)
                (binding-source-name b)
                (binding-unique-sym b)
                (binding-kind b)
                (binding-namespace b)
                (binding-scope-id b)
                (binding-storage-class b)
                (binding-type-attr b)
                (binding-visibility b)
                (binding-scope-set b)
                (binding-source-span b)))

(define (%c99-run-entry-parser-with-scope src-text filename entry-rule scope-mgr)
  (let ((env (%c99-get-cached-env filename src-text)))
    (c99-parse-env-scope-mgr-set! env scope-mgr)
    (%c99ds-run-with-env src-text filename entry-rule env)))

(define (c99-capture-parse-pch-state)
  (let* ((cached (car *c99-cached-env-parser*))
         (mgr (if cached
                  (c99-parse-env-scope-mgr (car cached))
                  (c99-make-init-scope-manager)))
         (root (scope-manager-root mgr)))
    (list 'c99-parse-pch-v1
          (cons 'alpha-counter (car *alpha-symbol-counter*))
          (cons 'binding-id-counter (car *binding-id-counter*))
          (cons 'hygiene-scope-counter (car *hygiene-scope-counter*))
          (cons 'scope-id-counter (car *scope-id-counter*))
          (cons 'root-id (scope-node-id root))
          (cons 'root-bindings
                (map (lambda (p) (cons (car p) (cdr p)))
                     (scope-node-bindings root)))
          (cons 'root-ns-bindings
                (map %c99-clone-binding (scope-node-ns-bindings root))))))

(define (c99-restore-parse-pch-state! pch-state)
  (if (or (not (pair? pch-state)) (not (eq? (car pch-state) 'c99-parse-pch-v1)))
      (error "Invalid C99 parse PCH state" pch-state))
  (let* ((alist (cdr pch-state))
         (alpha-c (cdr (assq 'alpha-counter alist)))
         (bind-c (cdr (assq 'binding-id-counter alist)))
         (hyg-c (cdr (assq 'hygiene-scope-counter alist)))
         (scope-c (cdr (assq 'scope-id-counter alist)))
         (root-id (cdr (assq 'root-id alist)))
         (raw-bs (cdr (assq 'root-bindings alist)))
         (raw-nbs (cdr (assq 'root-ns-bindings alist)))
         (cloned-bs (map (lambda (p) (cons (car p) (cdr p))) raw-bs))
         (cloned-nbs (map %c99-clone-binding raw-nbs))
         (fresh-root (list 'scope-node
                           #f
                           'top-level
                           (cons cloned-bs '())
                           (cons '() '())
                           (cons '() '())
                           root-id
                           (cons cloned-nbs '())
                           (cons '() '())))
         (fresh-mgr (list 'scope-manager fresh-root (cons fresh-root '()))))
    (reset-binding-registry!)
    (set-car! *alpha-symbol-counter* alpha-c)
    (set-car! *binding-id-counter* bind-c)
    (set-car! *hygiene-scope-counter* hyg-c)
    (set-car! *scope-id-counter* scope-c)
    (for-each register-binding! cloned-nbs)
    fresh-mgr))

(define (parse-c99-tokens-capturing-pch tokens . maybe-filename)
  (let* ((fname (if (pair? maybe-filename)
                    (car maybe-filename)
                    (if (pair? tokens)
                        (span-file (c-token-span (car tokens)))
                        "<c99-tokens>")))
         (ast
          (if (%c99-only-eof-tokens? tokens)
              (begin
                (reset-alpha-symbol-counter!)
                (%c99-get-cached-env fname "")
                '(c-translation-unit))
              (parse-c99-tokens tokens fname))))
    (cons ast (c99-capture-parse-pch-state))))

(define (parse-c99-tokens-with-pch tokens parse-pch-state . maybe-filename)
  (let* ((fname (if (pair? maybe-filename)
                    (car maybe-filename)
                    (if (pair? tokens)
                        (span-file (c-token-span (car tokens)))
                        "<c99-tokens>")))
         (fresh-mgr (c99-restore-parse-pch-state! parse-pch-state)))
    (if (%c99-only-eof-tokens? tokens)
        (let ((env (%c99-get-cached-env fname "")))
          (c99-parse-env-scope-mgr-set! env fresh-mgr)
          '(c-translation-unit))
        (let* ((concat (c-concat-adjacent-string-tokens tokens))
               (src-str (c-tokens->source-string concat)))
          (%c99-run-entry-parser-with-scope src-str fname 'translation_unit fresh-mgr)))))
