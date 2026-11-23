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

(define (%c99-read-grammar-text)
  (guard (ex (else
              (guard (ex2 (else
                           (error "Unable to locate tools/grammars/c99.peg" ex2)))
                (read-all-file-text "../tools/grammars/c99.peg"))))
    (read-all-file-text "tools/grammars/c99.peg")))

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
            (memq (car raw) '(c-struct c-union c-enum c-typedef-name)))
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
;;; 5. Environment-Aware C99 PEG Compiler (Produces L_c_ast with Span & Binding ID)
;;; -----------------------------------------------------------------------

(define (compile-c99-rule-getter env)
  (let* ((grammar (c99-peg-grammar-ast))
         (rules (peg-grammar-def-rules grammar))
         (rule-cells '()))
    (define (lookup-cell name)
      (let ((slot (assq name rule-cells)))
        (if slot (cdr slot) #f)))
    (define (lookup name)
      (let ((cell (lookup-cell name)))
        (if cell (car cell) #f)))

    ;; Initialize forward mutable cell slots (proc . '())
    (for-each
     (lambda (r)
       (set! rule-cells (cons (cons (peg-rule-def-name r) (cons #f '())) rule-cells)))
     rules)

    ;; Compile each rule with C99 semantic hooks, fast lexical leaves, Pratt expressions,
    ;; and lean non-LR Packrat memoization
    (for-each
     (lambda (r)
       (let* ((name (peg-rule-def-name r))
              (pratt-level
               (case name
                 ((logical_or_expr) 1)
                 ((logical_and_expr) 2)
                 ((inclusive_or_expr) 3)
                 ((exclusive_or_expr) 4)
                 ((and_expr) 5)
                 ((equality_expr) 6)
                 ((relational_expr) 7)
                 ((shift_expr) 8)
                 ((additive_expr) 9)
                 ((multiplicative_expr) 10)
                 (else #f)))
              (fast-leaf
               (case name
                 ((ws)
                  (lambda (ctx pos sk fk)
                    (let ((np (%c-scan-ws-end (parse-ctx-text ctx) (parse-ctx-length ctx) pos)))
                      (sk "" np fk))))
                 ((ident_cont)
                  (lambda (ctx pos sk fk)
                    (let ((txt (parse-ctx-text ctx))
                          (len (parse-ctx-length ctx)))
                      (if (and (< pos len) (%c-ident-cont-char? (string-ref txt pos)))
                          (sk (string (string-ref txt pos)) (+ pos 1) fk)
                          (fk)))))
                 ((c99_keyword)
                  (lambda (ctx pos sk fk)
                    (let* ((txt (parse-ctx-text ctx))
                           (len (parse-ctx-length ctx))
                           (end (%c-scan-ident-end txt len pos)))
                      (if (and end (memq (string->symbol (substring txt pos end)) *c99-keyword-symbols*))
                          (sk (substring txt pos end) end fk)
                          (fk)))))
                 ((identifier)
                  (lambda (ctx pos sk fk)
                    (let* ((txt (parse-ctx-text ctx))
                           (len (parse-ctx-length ctx))
                           (end (%c-scan-ident-end txt len pos)))
                      (if end
                          (let ((sym (string->symbol (substring txt pos end))))
                            (if (memq sym *c99-keyword-symbols*)
                                (begin
                                  (parse-ctx-update-max-pos! ctx pos "identifier")
                                  (fk))
                                (sk sym end fk)))
                          (begin
                            (parse-ctx-update-max-pos! ctx pos "identifier")
                            (fk))))))
                 ((constant)
                  (lambda (ctx pos sk fk)
                    (let* ((txt (parse-ctx-text ctx))
                           (len (parse-ctx-length ctx))
                           (end (or (%c-scan-float-end txt len pos)
                                    (%c-scan-int-end txt len pos)
                                    (%c-scan-char-lit-end txt len pos))))
                      (if end
                          (let ((sp (%c99-make-span-from-pos env ctx pos end)))
                            (sk (ast-with-span (list 'c-const (substring txt pos end)) sp) end fk))
                          (begin
                            (parse-ctx-update-max-pos! ctx pos "constant")
                            (fk))))))
                 ((string_literal)
                  (lambda (ctx pos sk fk)
                    (let* ((txt (parse-ctx-text ctx))
                           (len (parse-ctx-length ctx))
                           (end (%c-scan-string-lit-end txt len pos)))
                      (if end
                          (let ((sp (%c99-make-span-from-pos env ctx pos end)))
                            (sk (ast-with-span (list 'c-str (substring txt pos end)) sp) end fk))
                          (begin
                            (parse-ctx-update-max-pos! ctx pos "string_literal")
                            (fk))))))
                 (else #f)))
              (wrapped
               (cond
                 (pratt-level
                  (let ((p (%c99-make-pratt-binop-parser env lookup-cell pratt-level)))
                    (if (peg-rule-def-memoize? r)
                        (peg:rule-simple name p)
                        p)))
                 (fast-leaf fast-leaf)
                 (else
                  (let* ((raw-body
                          (cond
                            ;; Because typedef_name is strictly enforced by scope predicate,
                            ;; typedef_init_declarator can match full init_declarator (including "T *p;")
                            ((eq? name 'typedef_init_declarator)
                             (let ((init-cell (lookup-cell 'init_declarator)))
                               (lambda (ctx pos sk fk)
                                 ((car init-cell) ctx pos sk fk))))
                            (else
                             (compile-expr->parser-with-cells (peg-rule-def-expr r) lookup-cell))))
                         (decorated (decorate-c99-rule name raw-body env lookup)))
                    (if (peg-rule-def-memoize? r)
                        (cond
                          ;; Do not memoize context-sensitive typedef_name predicate globally across scope mutations
                          ((eq? name 'typedef_name) decorated)
                          ((memq name '(direct_declarator direct_abstract_declarator postfix_expr
                                        declarator abstract_declarator unary_expr cast_expr primary_expr))
                           (peg:rule name decorated))
                          (else
                           (peg:rule-simple name decorated)))
                        decorated))))))
         (let ((cell (lookup-cell name)))
           (set-car! cell wrapped))))
     rules)

    lookup))

(define (compile-c99-parser-with-env env . maybe-entry)
  (let ((entry-name (if (pair? maybe-entry) (car maybe-entry) 'translation_unit))
        (getter (compile-c99-rule-getter env)))
    (or (getter entry-name)
        (error "Unknown C99 grammar entry rule" entry-name))))

(define (decorate-c99-rule name base-parser env lookup)
  (case name
    ((identifier)
     (peg:map (lambda (res)
                (string->symbol (%c99-cst->string res)))
              base-parser))

    ((typedef_name)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (sym next-pos inner-fk)
                      (if (c99-typedef-bound? env sym)
                          (sk (list 'c-typedef-name sym (c99-lookup-binding-id env sym))
                              next-pos inner-fk)
                          (fk)))
                    fk)))

    ((storage_class_specifier builtin_type_specifier type_qualifier function_specifier struct_or_union)
     (peg:map (lambda (res)
                (string->symbol (%c99-string-trim-right-ws (%c99-cst->string res))))
              base-parser))

    ((explicit_declaration_specifiers typedef_declaration_specifiers specifier_qualifier_list)
     (peg:map %c99-flatten-decl-specs base-parser))

    ((constant)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (list 'c-const (%c99-cst->string res)))
               base-parser)))

    ((string_literal)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (list 'c-str (%c99-cst->string res)))
               base-parser)))

    ((pointer)
     (peg:map (lambda (res)
                (map (lambda (level)
                       (let ((q (if (>= (length level) 3) (list-ref level 2) #f)))
                         (if q (%c99-flatten-decl-specs q) '())))
                     res))
              base-parser))

    ((direct_declarator)
     (peg:map (lambda (res)
                (cond
                  ;; Base: identifier ws
                  ((and (pair? res) (symbol? (car res)))
                   (list 'c-decl-id (car res)))
                  ;; Parenthesized declarator: '(' ws decl ')' ws
                  ((and (pair? res) (string? (car res)) (string=? (car res) "("))
                   (list-ref res 2))
                  ;; Left-recursive array
                  ((and (pair? res) (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "["))
                   (let ((nlen (length res)))
                     (cond
                       ((= nlen 7)
                        (list 'c-arr-declarator (car res) (list-ref res 4)))
                       ((= nlen 10)
                        (list 'c-arr-declarator (car res) (list-ref res 7)))
                       (else
                        (list 'c-arr-declarator (car res) #f)))))
                  ;; Left-recursive fn
                  ((and (pair? res) (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "("))
                   (list 'c-fn-declarator (car res)
                         (let ((p (list-ref res 3)))
                           (if p p '(c-param-list () #f)))))
                  (else res)))
              base-parser))

    ((declarator)
     (peg:map (lambda (res)
                (let ((ptr (car res))
                      (dd (cadr res)))
                  (if (pair? ptr)
                      (list 'c-ptr-declarator ptr dd)
                      dd)))
              base-parser))

    ((direct_abstract_declarator)
     (peg:map (lambda (res)
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
                          ((= nlen 6)
                           (list 'c-arr-declarator #f (list-ref res 3)))
                          ((= nlen 9)
                           (list 'c-arr-declarator #f (list-ref res 6)))
                          (else
                           (list 'c-arr-declarator #f #f)))))
                     (else res)))
                  ((and (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "["))
                   (let ((nlen (length res)))
                     (cond
                       ((= nlen 7)
                        (list 'c-arr-declarator (car res) (list-ref res 4)))
                       ((= nlen 10)
                        (list 'c-arr-declarator (car res) (list-ref res 7)))
                       (else
                        (list 'c-arr-declarator (car res) #f)))))
                  ((and (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "("))
                   (list 'c-fn-declarator (car res) (or (list-ref res 3) '(c-param-list () #f))))
                  (else res)))
              base-parser))

    ((abstract_declarator)
     (peg:map (lambda (res)
                (if (and (pair? res) (pair? (car res))
                         (or (null? (caar res)) (list? (caar res)))
                         (not (memq (caar res) '(c-arr-declarator c-fn-declarator c-ptr-declarator))))
                    (list 'c-ptr-declarator (car res) (cadr res))
                    res))
              base-parser))

    ((type_name)
     (peg:map (lambda (res)
                (list 'c-type-name (car res) (cadr res)))
              base-parser))

    ((parameter_list)
     (peg:map (lambda (res)
                (cons (cdr (car res))
                      (map cadddr (cdr (cadr res)))))
              base-parser))

    ((parameter_type_list)
     (peg:map (lambda (res)
                (list 'c-param-list (car res) (if (cadr res) #t #f)))
              base-parser))

    ((parameter_declaration)
     (peg:map (lambda (res)
                (list 'c-param (car res) (cadr res)))
              base-parser))

    ((init_declarator)
     (peg:map (lambda (res)
                (let ((decl (car res))
                      (opt-init (cadr res)))
                  (list 'c-init-decl decl
                        (if (pair? opt-init) (list-ref opt-init 2) #f))))
              base-parser))

    ((init_declarator_list typedef_init_declarator_list struct_declarator_list argument_expr_list)
     (peg:map (lambda (res)
                (cons (cdr (car res))
                      (map caddr (cdr (cadr res)))))
              base-parser))

    ((struct_declarator)
     (peg:map (lambda (res)
                (if (and (pair? res) (>= (length res) 4)
                         (string? (cadr res)) (string=? (cadr res) ":"))
                    (list 'c-struct-decl (car res) (list-ref res 3))
                    (list 'c-struct-decl res #f)))
              base-parser))

    ((struct_declaration)
     (peg:map (lambda (res)
                (list 'c-field-decl (car res) (or (cadr res) '())))
              base-parser))

    ((designator)
     (peg:map (lambda (res)
                (if (string=? (car res) "[")
                    (list 'c-desig-index (list-ref res 2))
                    (list 'c-desig-field (list-ref res 2))))
              base-parser))

    ((designation)
     (peg:map car base-parser))

    ((initializer_item)
     (peg:map (lambda (res)
                (list 'c-init-item (car res) (cadr res)))
              base-parser))

    ((initializer_list enumerator_list)
     (peg:map (lambda (res)
                (cons (cdr (car res))
                      (map cadddr (cdr (cadr res)))))
              base-parser))

    ((initializer)
     (peg:map (lambda (res)
                (if (and (pair? res) (string? (car res)) (string=? (car res) "{"))
                    (let ((inner (list-ref res 2)))
                      (list 'c-init-list (if (pair? inner) (car inner) '())))
                    res))
              base-parser))

    ((offsetof_designator_suffix)
     (peg:map (lambda (res)
                (if (and (pair? res) (string? (car res)) (string=? (car res) "."))
                    (list 'c-desig-field (list-ref res 2))
                    (list 'c-desig-index (list-ref res 2))))
              base-parser))

    ((offsetof_member_designator)
     (peg:map (lambda (res)
                (cons (list 'c-desig-field (car res))
                      (or (list-ref res 2) '())))
              base-parser))

    ((struct_or_union_specifier)
     (%c99-wrap-span env
      (lambda (ctx pos sk fk)
        (base-parser ctx pos
                     (lambda (res next-pos inner-fk)
                       (let* ((is-union? (eq? (car res) 'union))
                              (tag-sym (list-ref res 2))
                              (fields (if (>= (length res) 7)
                                          (or (list-ref res 6) '())
                                          #f))
                              (sp (%c99-make-span-from-pos env ctx pos next-pos)))
                         (if (symbol? tag-sym)
                             (c99-register-var! env tag-sym (if is-union? 'tag-union 'tag-struct) sp))
                         (sk (list (if is-union? 'c-union 'c-struct)
                                   tag-sym
                                   fields)
                             next-pos inner-fk)))
                     fk))))

    ((enum_specifier)
     (%c99-wrap-span env
      (lambda (ctx pos sk fk)
        (base-parser ctx pos
                     (lambda (res next-pos inner-fk)
                       (let* ((tag-sym (list-ref res 3))
                              (enums (if (>= (length res) 8)
                                         (or (list-ref res 7) '())
                                         #f))
                              (sp (%c99-make-span-from-pos env ctx pos next-pos)))
                         (if (symbol? tag-sym)
                             (c99-register-var! env tag-sym 'tag-enum sp))
                         (sk (list 'c-enum tag-sym enums)
                             next-pos inner-fk)))
                     fk))))

    ((enumerator)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let* ((ec-sym (let ((syms (%c99-flatten-tag-syms (car res))))
                                       (if (pair? syms) (car syms) #f)))
                             (opt-eq (cadr res))
                             (val-expr (if (pair? opt-eq) (list-ref opt-eq 2) #f))
                             (sp (%c99-make-span-from-pos env ctx pos next-pos)))
                        (if ec-sym
                            (c99-register-var! env ec-sym 'enum-const sp))
                        (sk (list 'c-enumerator ec-sym val-expr)
                            next-pos inner-fk)))
                    fk)))

    ((explicit_declaration typedef_declaration)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
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
                        (let ((node (ast-with-span
                                     (list (if is-td? 'c-typedef 'c-decl)
                                           specs
                                           inits)
                                     sp)))
                          (sk node next-pos inner-fk))))
                    fk)))

    ((compound_stmt)
     (let ((ready #f) (p-lbrace #f) (p-items #f) (p-rbrace #f))
       (lambda (ctx pos sk fk)
         (if (not ready)
             (begin
               (set! p-lbrace (peg:seq (peg:lit "{") (lookup 'ws)))
               (set! p-items  (peg:star (lookup 'block_item)))
               (set! p-rbrace (peg:seq (peg:lit "}") (lookup 'ws)))
               (set! ready #t)))
         (p-lbrace ctx pos
                   (lambda (_lb pos1 fk1)
                     (c99-push-scope! env 'block)
                     (p-items ctx pos1
                              (lambda (items pos2 fk2)
                                (p-rbrace ctx pos2
                                          (lambda (_rb end-pos fk3)
                                            (c99-pop-scope! env)
                                            (let ((sp (%c99-make-span-from-pos env ctx pos end-pos)))
                                              (sk (ast-with-span (cons 'c-block items) sp)
                                                  end-pos fk3)))
                                          (lambda ()
                                            (c99-pop-scope! env)
                                            (fk2))))
                              (lambda ()
                                (c99-pop-scope! env)
                                (fk1))))
                   fk))))

    ((function_definition)
     (let ((ready #f) (p-specs #f) (p-decl #f) (p-dlist #f) (p-body #f))
       (lambda (ctx pos sk fk)
         (if (not ready)
             (begin
               (set! p-specs (lookup 'declaration_specifiers))
               (set! p-decl  (lookup 'declarator))
               (set! p-dlist (peg:opt (lookup 'declaration_list)))
               (set! p-body  (lookup 'compound_stmt))
               (set! ready #t)))
         (p-specs ctx pos
                  (lambda (specs pos1 fk1)
                    (p-decl ctx pos1
                            (lambda (decl pos2 fk2)
                              (let* ((fn-names (%c99-extract-declarator-names decl))
                                     (fn-sym (if (pair? fn-names) (car fn-names) 'anon_fn))
                                     (param-syms (%c99-extract-fn-param-names decl))
                                     (fn-sp (%c99-make-span-from-pos env ctx pos pos2)))
                                (c99-register-var! env fn-sym 'function fn-sp)
                                (c99-push-scope! env 'function)
                                (let ((param-bindings
                                       (map (lambda (psym)
                                              (let ((b (c99-register-var! env psym 'parameter fn-sp)))
                                                (list psym (binding-id b))))
                                            param-syms)))
                                  (p-dlist ctx pos2
                                           (lambda (dlist pos3 fk3)
                                             (p-body ctx pos3
                                                     (lambda (body end-pos fk4)
                                                       (c99-pop-scope! env)
                                                       (let ((sp (%c99-make-span-from-pos env ctx pos end-pos)))
                                                         (sk (ast-with-span
                                                              (list 'c-fn-def fn-sym specs decl param-bindings body)
                                                              sp)
                                                             end-pos fk4)))
                                                     (lambda ()
                                                       (c99-pop-scope! env)
                                                       (fk3))))
                                           (lambda ()
                                             (c99-pop-scope! env)
                                             (fk2))))))
                            fk1))
                  fk))))

    ((expr logical_or_expr logical_and_expr inclusive_or_expr exclusive_or_expr
      and_expr equality_expr relational_expr shift_expr additive_expr multiplicative_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (sk (%c99-fold-binop-cst res env ctx pos next-pos)
                          next-pos inner-fk))
                    fk)))

    ((assignment_operator)
     (peg:map (lambda (res)
                (list 'c-assign-op (%c99-assign-str->sym (%c99-string-trim-right-ws (%c99-cst->string res)))))
              base-parser))

    ((assignment_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (if (and (pair? res) (pair? (cdr res))
                               (pair? (cadr res)) (eq? (caadr res) 'c-assign-op))
                          (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                            (sk (ast-with-span
                                 (list 'c-assign (cadadr res) (car res) (list-ref res 3))
                                 sp)
                                next-pos inner-fk))
                          (sk res next-pos inner-fk)))
                    fk)))

    ((conditional_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (if (and (pair? res) (= (length res) 2))
                          (let ((opt-tail (cadr res)))
                            (if (pair? opt-tail)
                                (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                                  (sk (ast-with-span
                                       (list 'c-ternary (car res) (list-ref opt-tail 2) (list-ref opt-tail 5))
                                       sp)
                                      next-pos inner-fk))
                                (sk (car res) next-pos inner-fk)))
                          (sk res next-pos inner-fk)))
                    fk)))

    ((cast_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (if (and (pair? res) (string? (car res)) (string=? (car res) "("))
                          (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                            (sk (ast-with-span
                                 (list 'c-cast (list-ref res 2) (list-ref res 6))
                                 sp)
                                next-pos inner-fk))
                          (sk res next-pos inner-fk)))
                    fk)))

    ((unary_operator)
     (peg:map (lambda (res)
                (list 'c-unop-tag (%c99-unop-str->sym (%c99-string-trim-right-ws (%c99-cst->string res)))))
              base-parser))

    ((unary_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                        (cond
                          ((and (pair? res) (string? (car res))
                                (or (string=? (car res) "++") (string=? (car res) "--")))
                           (sk (ast-with-span
                                (list 'c-unop (if (string=? (car res) "++") 'pre++ 'pre--)
                                      (list-ref res 2))
                                sp)
                               next-pos inner-fk))
                          ((and (pair? res) (pair? (car res)) (eq? (caar res) 'c-unop-tag))
                           (sk (ast-with-span
                                (list 'c-unop (cadar res) (list-ref res 2))
                                sp)
                               next-pos inner-fk))
                          ((and (pair? res) (string? (car res)) (string=? (car res) "sizeof"))
                           (if (= (length res) 9)
                               (sk (ast-with-span (list 'c-sizeof-type (list-ref res 5)) sp)
                                   next-pos inner-fk)
                               (sk (ast-with-span (list 'c-sizeof-expr (list-ref res 3)) sp)
                                   next-pos inner-fk)))
                          ((and (pair? res) (string? (car res))
                                (or (string=? (car res) "_Alignof")
                                    (string=? (car res) "__alignof__")
                                    (string=? (car res) "__alignof")))
                           (if (= (length res) 9)
                               (sk (ast-with-span (list 'c-alignof-type (list-ref res 5)) sp)
                                   next-pos inner-fk)
                               (sk (ast-with-span (list 'c-alignof-expr (list-ref res 3)) sp)
                                   next-pos inner-fk)))
                          ((and (pair? res) (string? (car res))
                                (string=? (car res) "__builtin_offsetof"))
                           (sk (ast-with-span
                                (list 'c-offsetof (list-ref res 5) (list-ref res 8))
                                sp)
                               next-pos inner-fk))
                          (else
                           (sk res next-pos inner-fk)))))
                    fk)))

    ((postfix_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                        (cond
                          ((not (pair? res))
                           (sk res next-pos inner-fk))
                          ((and (string? (car res)) (string=? (car res) "("))
                           (let ((inits (list-ref res 7)))
                             (sk (ast-with-span
                                  (list 'c-compound-lit
                                        (list-ref res 2)
                                        (if (pair? inits) (car inits) '()))
                                  sp)
                                 next-pos inner-fk)))
                          ((and (pair? (cdr res)) (string? (cadr res)))
                           (let ((op (cadr res))
                                 (base (car res)))
                             (cond
                               ((string=? op "[")
                                (sk (ast-with-span (list 'c-index base (list-ref res 3)) sp)
                                    next-pos inner-fk))
                               ((string=? op "(")
                                (let ((args (list-ref res 3)))
                                  (sk (ast-with-span
                                       (cons 'c-call (cons base (if (pair? args) args '())))
                                       sp)
                                      next-pos inner-fk)))
                               ((string=? op ".")
                                (sk (ast-with-span (list 'c-member base (list-ref res 3) #f) sp)
                                    next-pos inner-fk))
                               ((string=? op "->")
                                (sk (ast-with-span (list 'c-member base (list-ref res 3) #t) sp)
                                    next-pos inner-fk))
                               ((or (string=? op "++") (string=? op "--"))
                                (sk (ast-with-span
                                     (list 'c-unop (if (string=? op "++") 'post++ 'post--) base)
                                     sp)
                                    next-pos inner-fk))
                               (else
                                (sk res next-pos inner-fk)))))
                          (else
                           (sk res next-pos inner-fk)))))
                    fk)))

    ((primary_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                        (cond
                          ((and (pair? res) (string? (car res))
                                (string=? (car res) "__builtin_va_arg"))
                           (sk (ast-with-span
                                (list 'c-va-arg (list-ref res 5) (list-ref res 8))
                                sp)
                               next-pos inner-fk))
                          ((and (pair? res) (symbol? (car res)))
                           (let* ((sym (car res))
                                  (bid (c99-lookup-binding-id env sym)))
                             (sk (ast-with-span (list 'c-var-ref sym bid) sp)
                                 next-pos inner-fk)))
                          ((and (pair? res)
                                (ast-has-span? (car res))
                                (eq? (car (ast-strip-span (car res))) 'c-const))
                           (sk (car res) next-pos inner-fk))
                          ((and (pair? res) (string? (car res)) (string=? (car res) "("))
                           (sk (list-ref res 2) next-pos inner-fk))
                          ((and (pair? res)
                                (pair? (car res))
                                (ast-has-span? (caar res))
                                (eq? (car (ast-strip-span (caar res))) 'c-str))
                           (sk (%c99-merge-c-str-literals res env ctx pos next-pos)
                               next-pos inner-fk))
                          (else
                           (sk (ast-with-span res sp) next-pos inner-fk)))))
                    fk)))

    ((selection_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (let ((kw (car res)))
                   (if (string=? kw "if")
                       (let ((opt-else (list-ref res 9)))
                         (if (pair? opt-else)
                             (list 'c-if (list-ref res 5) (list-ref res 8) (list-ref opt-else 3))
                             (list 'c-if (list-ref res 5) (list-ref res 8))))
                       (list 'c-switch (list-ref res 5) (list-ref res 8)))))
               base-parser)))

    ((iteration_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (let ((kw (car res)))
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
                     (else (list 'c-iter res)))))
               base-parser)))

    ((jump_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (let ((kw (car res)))
                   (cond
                     ((string=? kw "goto") (list 'c-goto (list-ref res 3)))
                     ((string=? kw "continue") '(c-continue))
                     ((string=? kw "break") '(c-break))
                     ((string=? kw "return") (list 'c-return (list-ref res 3)))
                     (else (list 'c-jump res)))))
               base-parser)))

    ((labeled_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (let ((head (car res)))
                   (cond
                     ((and (string? head) (string=? head "case"))
                      (list 'c-case (list-ref res 3) (list-ref res 6)))
                     ((and (string? head) (string=? head "default"))
                      (list 'c-default (list-ref res 5)))
                     ((symbol? head)
                      (c99-register-var! env head 'label)
                      (list 'c-label head (list-ref res 4)))
                     (else (list 'c-labeled res)))))
               base-parser)))

    ((expr_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (list 'c-expr-stmt (car res)))
               base-parser)))

    ((translation_unit)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (cons 'c-translation-unit (cadr res)))
               base-parser)))

    (else base-parser)))

;;; -----------------------------------------------------------------------
;;; 6. Top-Level Parse API & Pretty Diagnostic Integration
;;; -----------------------------------------------------------------------

(define (%c99-get-cached-env-and-getter filename src-text)
  (let ((cached (car *c99-cached-env-parser*)))
    (if cached
        (let ((env (car cached)))
          (c99-parse-env-scope-mgr-set! env (c99-make-init-scope-manager))
          (c99-parse-env-file-set! env filename)
          (c99-parse-env-text-set! env src-text)
          (c99-parse-env-line-starts-set! env (%c99-build-line-starts src-text))
          cached)
        (let* ((env (make-c99-parse-env filename))
               (getter (compile-c99-rule-getter env))
               (pair (cons env getter)))
          (c99-parse-env-text-set! env src-text)
          (c99-parse-env-line-starts-set! env (%c99-build-line-starts src-text))
          (set-car! *c99-cached-env-parser* pair)
          pair))))

(define (%c99-run-entry-parser src-text filename entry-rule)
  (reset-alpha-symbol-counter!)
  (diagnostic-register-source-string! filename src-text)
  (let* ((cached (%c99-get-cached-env-and-getter filename src-text))
         (getter (cdr cached))
         (parser (or (getter entry-rule)
                     (error "Unknown C99 grammar entry rule" entry-rule)))
         (ctx (make-parse-context src-text))
         (txt-len (string-length src-text))
         (matched #f)
         (result-val #f)
         (result-pos 0))
    (parser
     ctx 0
     (lambda (val next-pos fk)
       (if (= next-pos txt-len)
           (begin
             (set! matched #t)
             (set! result-val val)
             (set! result-pos next-pos))
           (fk)))
     (lambda ()
       (set! matched #f)))
    (if matched
        result-val
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
