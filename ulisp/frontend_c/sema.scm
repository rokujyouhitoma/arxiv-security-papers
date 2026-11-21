;;; =======================================================================
;;; ULisp C99 Frontend: Semantic Analyzer & Type Checker (L_c_ast -> L_c_typed)
;;; Conforms to DSN-33-11 §4.2/§4.3, DSN-33-32 & Issue #916
;;; Implements:
;;;   - Scope/Namespace resolution (variables, functions, typedefs, enums)
;;;   - Integer Promotions (ISO C99 §6.3.1.1)
;;;   - Usual Arithmetic Conversions (ISO C99 §6.3.1.8)
;;;   - Implicit Cast insertion (c-implicit-cast)
;;;   - Lvalue & Function Prototype validation
;;;   - Span-annotated diagnostics C99-SEMA-001 .. C99-SEMA-005 (#833)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Typed AST Constructors & Accessors
;;; -----------------------------------------------------------------------

(define (make-c-typed ty inner)
  (list 'c-typed ty inner))

(define (c-typed? node)
  (and (pair? node) (eq? (car node) 'c-typed)))

(define (c-typed-type node)
  (if (c-typed? node) (cadr node) 'i32))

(define (c-typed-inner node)
  (if (c-typed? node) (caddr node) node))

(define (c99-apply-implicit-cast typed-expr target-type)
  (let ((src-type (c-typed-type typed-expr)))
    (if (equal? src-type target-type)
        typed-expr
        (make-c-typed target-type (list 'c-implicit-cast target-type typed-expr)))))

;;; -----------------------------------------------------------------------
;;; 2. Diagnostic Helper (C99-SEMA-001 .. C99-SEMA-005)
;;; -----------------------------------------------------------------------

(define (%c99-sema-error! code msg node-or-span)
  (let* ((sp (cond
               ((source-span? node-or-span) node-or-span)
               ((ast-has-span? node-or-span) (ast-source-span node-or-span))
               (else (make-source-span "<c99-sema>" 1 1 1 1 #f (next-source-span-id!)))))
         (diag (make-diagnostic 'error code sp msg)))
    (report-diagnostic diag)
    (raise (list 'c99-sema-error code msg sp))))

;;; -----------------------------------------------------------------------
;;; 3. Semantic Environment (<c99-sema-env>)
;;; -----------------------------------------------------------------------

(define *c99-sema-var-id-counter* (cons 0 '()))

(define (c99-reset-sema-var-id!)
  (set-car! *c99-sema-var-id-counter* 0))

(define (c99-next-sema-var-id! sym)
  (let ((id (car *c99-sema-var-id-counter*)))
    (set-car! *c99-sema-var-id-counter* (+ id 1))
    (string->symbol
     (string-append (symbol->string sym) "_" (number->string id)))))

;; Sema scope entry types:
;; - ('var unique-sym c-type global? param-idx-or-#f)
;; - ('enum-const val)
;; - ('typedef c-type)
;; - ('fn sym fn-type defined?)
(define-record-type <c99-sema-env>
  (%make-sema-env scopes fn-table enum-tags struct-tags curr-ret loop-depth switch-depth)
  c99-sema-env?
  (scopes       sema-env-scopes       sema-env-scopes-set!)
  (fn-table     sema-env-fn-table     sema-env-fn-table-set!)
  (enum-tags    sema-env-enum-tags    sema-env-enum-tags-set!)
  (struct-tags  sema-env-struct-tags  sema-env-struct-tags-set!)
  (curr-ret     sema-env-curr-ret     sema-env-curr-ret-set!)
  (loop-depth   sema-env-loop-depth   sema-env-loop-depth-set!)
  (switch-depth sema-env-switch-depth sema-env-switch-depth-set!))

(define (make-c99-sema-env)
  (let ((env (%make-sema-env (list '()) '() '() '() 'i32 0 0)))
    ;; Pre-populate common libc external prototypes for SysV ABI calls
    (sema-register-fn! env 'printf (make-c-fn-type 'i32 (list (make-c-ptr-type 'i8)) #t) #f)
    (sema-register-fn! env 'puts (make-c-fn-type 'i32 (list (make-c-ptr-type 'i8)) #f) #f)
    (sema-register-fn! env 'putchar (make-c-fn-type 'i32 '(i32) #f) #f)
    (sema-register-fn! env 'malloc (make-c-fn-type (make-c-ptr-type 'void) '(u64) #f) #f)
    (sema-register-fn! env 'calloc (make-c-fn-type (make-c-ptr-type 'void) '(u64 u64) #f) #f)
    (sema-register-fn! env 'realloc (make-c-fn-type (make-c-ptr-type 'void) (list (make-c-ptr-type 'void) 'u64) #f) #f)
    (sema-register-fn! env 'free (make-c-fn-type 'void (list (make-c-ptr-type 'void)) #f) #f)
    (sema-register-fn! env 'memcpy (make-c-fn-type (make-c-ptr-type 'void) (list (make-c-ptr-type 'void) (make-c-ptr-type 'void) 'u64) #f) #f)
    (sema-register-fn! env 'memset (make-c-fn-type (make-c-ptr-type 'void) (list (make-c-ptr-type 'void) 'i32 'u64) #f) #f)
    (sema-register-fn! env 'strlen (make-c-fn-type 'u64 (list (make-c-ptr-type 'i8)) #f) #f)
    (sema-register-fn! env 'strcmp (make-c-fn-type 'i32 (list (make-c-ptr-type 'i8) (make-c-ptr-type 'i8)) #f) #f)
    (sema-register-fn! env 'strncmp (make-c-fn-type 'i32 (list (make-c-ptr-type 'i8) (make-c-ptr-type 'i8) 'u64) #f) #f)
    (sema-register-fn! env 'exit (make-c-fn-type 'void '(i32) #f) #f)
    (sema-register-fn! env 'abort (make-c-fn-type 'void '() #f) #f)
    env))

(define (sema-push-scope! env)
  (sema-env-scopes-set! env (cons '() (sema-env-scopes env))))

(define (sema-pop-scope! env)
  (let ((sc (sema-env-scopes env)))
    (if (pair? (cdr sc))
        (sema-env-scopes-set! env (cdr sc)))))

(define (sema-in-global-scope? env)
  (null? (cdr (sema-env-scopes env))))

(define (sema-bind-ordinary! env sym entry)
  (let ((sc (sema-env-scopes env)))
    (set-car! sc (cons (cons sym entry) (car sc)))))

(define (sema-lookup-ordinary-local env sym)
  (let ((slot (assq sym (car (sema-env-scopes env)))))
    (if slot (cdr slot) #f)))

(define (sema-lookup-ordinary env sym)
  (let loop ((scs (sema-env-scopes env)))
    (if (null? scs)
        #f
        (let ((slot (assq sym (car scs))))
          (if slot (cdr slot) (loop (cdr scs)))))))

(define (sema-lookup-typedef env sym)
  (let ((ent (sema-lookup-ordinary env sym)))
    (if (and ent (eq? (car ent) 'typedef))
        (cadr ent)
        #f)))

(define (sema-register-fn! env sym fn-type defined?)
  (let ((slot (assq sym (sema-env-fn-table env))))
    (if slot
        (let ((prev (cdr slot)))
          (set-cdr! slot (list 'fn sym fn-type (or defined? (list-ref prev 3)))))
        (let ((ent (list 'fn sym fn-type defined?)))
          (sema-env-fn-table-set! env (cons (cons sym ent) (sema-env-fn-table env)))
          (sema-bind-ordinary! env sym ent)))))

(define (sema-lookup-fn env sym)
  (let ((slot (assq sym (sema-env-fn-table env))))
    (if slot (cdr slot) #f)))

;;; -----------------------------------------------------------------------
;;; 4. C99 Integer Constant & Literal Parser + Constant Evaluator
;;; -----------------------------------------------------------------------

(define (%c99-sema-hex-val ch)
  (let ((c (char->integer ch)))
    (cond
      ((and (>= c 48) (<= c 57)) (- c 48))
      ((and (>= c 97) (<= c 102)) (+ 10 (- c 97)))
      ((and (>= c 65) (<= c 70)) (+ 10 (- c 65)))
      (else -1))))

(define (%c99-sema-parse-radix str start end radix)
  (let loop ((i start) (acc 0))
    (if (>= i end)
        acc
        (loop (+ i 1) (+ (* acc radix) (%c99-sema-hex-val (string-ref str i)))))))

(define (%c99-sema-decode-char-lit lex)
  (let* ((start (if (and (> (string-length lex) 0) (char=? (string-ref lex 0) #\L)) 2 1))
         (end (- (string-length lex) 1)))
    (if (>= start end)
        0
        (let ((ch (string-ref lex start)))
          (if (not (char=? ch #\\))
              (char->integer ch)
              (if (>= (+ start 1) end)
                  0
                  (let ((esc (string-ref lex (+ start 1))))
                    (case esc
                      ((#\n) 10)
                      ((#\t) 9)
                      ((#\r) 13)
                      ((#\a) 7)
                      ((#\b) 8)
                      ((#\f) 12)
                      ((#\v) 11)
                      ((#\\) 92)
                      ((#\') 39)
                      ((#\") 34)
                      ((#\?) 63)
                      ((#\x) (%c99-sema-parse-radix lex (+ start 2) end 16))
                      (else
                       (let ((code (char->integer esc)))
                         (if (and (>= code 48) (<= code 55))
                             (%c99-sema-parse-radix lex (+ start 1) end 8)
                             code)))))))))))

(define (c99-decode-string-literal lex)
  (let* ((n (string-length lex))
         (start (if (and (>= n 2) (char=? (string-ref lex 0) #\L) (char=? (string-ref lex 1) #\")) 2 1))
         (end (if (> n 0) (- n 1) 0)))
    (let loop ((i start) (chars '()))
      (if (>= i end)
          (list->string (reverse chars))
          (let ((ch (string-ref lex i)))
            (if (or (not (char=? ch #\\)) (>= (+ i 1) end))
                (loop (+ i 1) (cons ch chars))
                (let ((esc (string-ref lex (+ i 1))))
                  (case esc
                    ((#\n) (loop (+ i 2) (cons #\newline chars)))
                    ((#\t) (loop (+ i 2) (cons #\tab chars)))
                    ((#\r) (loop (+ i 2) (cons (integer->char 13) chars)))
                    ((#\a) (loop (+ i 2) (cons (integer->char 7) chars)))
                    ((#\b) (loop (+ i 2) (cons (integer->char 8) chars)))
                    ((#\f) (loop (+ i 2) (cons (integer->char 12) chars)))
                    ((#\v) (loop (+ i 2) (cons (integer->char 11) chars)))
                    ((#\\) (loop (+ i 2) (cons #\\ chars)))
                    ((#\') (loop (+ i 2) (cons #\' chars)))
                    ((#\") (loop (+ i 2) (cons #\" chars)))
                    ((#\?) (loop (+ i 2) (cons #\? chars)))
                    ((#\x)
                     (let scan-x ((j (+ i 2)) (acc 0))
                       (if (and (< j end) (>= (%c99-sema-hex-val (string-ref lex j)) 0))
                           (scan-x (+ j 1) (+ (* acc 16) (%c99-sema-hex-val (string-ref lex j))))
                           (loop j (cons (integer->char (bitwise-and acc 255)) chars)))))
                    (else
                     (let ((ec (char->integer esc)))
                       (if (and (>= ec 48) (<= ec 55))
                           (let scan-o ((j (+ i 1)) (k 0) (acc 0))
                             (if (and (< j end) (< k 3)
                                      (let ((c2 (char->integer (string-ref lex j))))
                                        (and (>= c2 48) (<= c2 55))))
                                 (scan-o (+ j 1) (+ k 1)
                                         (+ (* acc 8) (- (char->integer (string-ref lex j)) 48)))
                                 (loop j (cons (integer->char (bitwise-and acc 255)) chars))))
                           (loop (+ i 2) (cons esc chars)))))))))))))

(define (c99-parse-constant-info lex)
  (let ((len (string-length lex)))
    (cond
      ((and (>= len 2)
            (or (char=? (string-ref lex 0) #\')
                (and (char=? (string-ref lex 0) #\L) (char=? (string-ref lex 1) #\'))))
       (cons (%c99-sema-decode-char-lit lex) 'i32))
      ;; Float check
      ((let check-f ((i 0) (hex? (and (>= len 2) (char=? (string-ref lex 0) #\0)
                                      (or (char=? (string-ref lex 1) #\x)
                                          (char=? (string-ref lex 1) #\X)))))
         (if (>= i len)
             #f
             (let ((c (string-ref lex i)))
               (if (or (char=? c #\.)
                       (and (not hex?) (or (char=? c #\e) (char=? c #\E)))
                       (and hex? (or (char=? c #\p) (char=? c #\P))))
                   #t
                   (check-f (+ i 1) hex?)))))
       (let ((last-ch (string-ref lex (- len 1))))
         (cons 0.0 (if (or (char=? last-ch #\f) (char=? last-ch #\F)) 'f32 'f64))))
      (else
       ;; Integer constant with optional u/l/ll suffixes
       (let strip-suf ((end len) (u? #f) (l-cnt 0))
         (if (<= end 0)
             (cons 0 'i32)
             (let ((c (string-ref lex (- end 1))))
               (cond
                 ((or (char=? c #\u) (char=? c #\U))
                  (strip-suf (- end 1) #t l-cnt))
                 ((or (char=? c #\l) (char=? c #\L))
                  (strip-suf (- end 1) u? (+ l-cnt 1)))
                 (else
                  (let* ((hex? (and (>= end 2) (char=? (string-ref lex 0) #\0)
                                    (or (char=? (string-ref lex 1) #\x)
                                        (char=? (string-ref lex 1) #\X))))
                         (oct? (and (not hex?) (> end 1) (char=? (string-ref lex 0) #\0)))
                         (val (cond
                                (hex? (%c99-sema-parse-radix lex 2 end 16))
                                (oct? (%c99-sema-parse-radix lex 1 end 8))
                                (else (%c99-sema-parse-radix lex 0 end 10))))
                         (ty (cond
                               ((and u? (>= l-cnt 1)) 'u64)
                               ((>= l-cnt 1) 'i64)
                               (u? (if (> val #xffffffff) 'u64 'u32))
                               ((and (<= val #x7fffffff)) 'i32)
                               ((and (or hex? oct?) (<= val #xffffffff)) 'u32)
                               ((<= val #x7fffffffffffffff) 'i64)
                               (else 'u64))))
                    (cons val ty)))))))))))

(define (c99-eval-const-int-expr env node)
  (let ((raw (ast-strip-span node)))
    (cond
      ((and (pair? raw) (eq? (car raw) 'c-const))
       (car (c99-parse-constant-info (cadr raw))))
      ((and (pair? raw) (eq? (car raw) 'c-var-ref))
       (let ((ent (sema-lookup-ordinary env (cadr raw))))
         (if (and ent (eq? (car ent) 'enum-const))
             (cadr ent)
             #f)))
      ((and (pair? raw) (eq? (car raw) 'c-unop))
       (let ((v (c99-eval-const-int-expr env (caddr raw))))
         (if (not v)
             #f
             (case (cadr raw)
               ((neg) (- 0 v))
               ((uplus) v)
               ((lnot) (if (= v 0) 1 0))
               ((bit-not) (bitwise-not v))
               (else #f)))))
      ((and (pair? raw) (eq? (car raw) 'c-binop))
       (let ((l (c99-eval-const-int-expr env (caddr raw)))
             (r (c99-eval-const-int-expr env (cadddr raw))))
         (if (or (not l) (not r))
             #f
             (case (cadr raw)
               ((+) (+ l r))
               ((-) (- l r))
               ((*) (* l r))
               ((/) (if (= r 0) #f (quotient l r)))
               ((rem) (if (= r 0) #f (remainder l r)))
               ((<<) (arithmetic-shift l r))
               ((>>) (arithmetic-shift l (- 0 r)))
               ((==) (if (= l r) 1 0))
               ((!=) (if (= l r) 0 1))
               ((<) (if (< l r) 1 0))
               ((<=) (if (<= l r) 1 0))
               ((>) (if (> l r) 1 0))
               ((>=) (if (>= l r) 1 0))
               ((bit-and) (bitwise-and l r))
               ((bit-or) (bitwise-ior l r))
               ((bit-xor) (bitwise-xor l r))
               ((land) (if (and (not (= l 0)) (not (= r 0))) 1 0))
               ((lor) (if (or (not (= l 0)) (not (= r 0))) 1 0))
               (else #f)))))
      ((and (pair? raw) (eq? (car raw) 'c-sizeof-type))
       (c-type-size (sema-resolve-type-name env (cadr raw))))
      (else #f))))

;;; -----------------------------------------------------------------------
;;; 5. Integer Promotions, Usual Arithmetic Conversions & Type Resolution
;;; -----------------------------------------------------------------------

(define (c99-integer-promote t)
  (if (or (memq t '(bool i8 u8 i16 u16)) (c-enum-type? t))
      'i32
      t))

(define (c99-usual-arithmetic-type t1 t2)
  (let ((p1 (c99-integer-promote t1))
        (p2 (c99-integer-promote t2)))
    (cond
      ((or (eq? p1 'f64) (eq? p2 'f64)) 'f64)
      ((or (eq? p1 'f32) (eq? p2 'f32)) 'f32)
      ((eq? p1 p2) p1)
      ((eq? (c-signed-type? p1) (c-signed-type? p2))
       (if (>= (c-type-rank p1) (c-type-rank p2)) p1 p2))
      ((c-unsigned-type? p1)
       (cond
         ((>= (c-type-rank p1) (c-type-rank p2)) p1)
         ((> (c-type-size p2) (c-type-size p1)) p2)
         (else (c-type->unsigned-counterpart p2))))
      (else
       (cond
         ((>= (c-type-rank p2) (c-type-rank p1)) p2)
         ((> (c-type-size p1) (c-type-size p2)) p1)
         (else (c-type->unsigned-counterpart p1)))))))

(define (c99-array-decay t)
  (if (c-array-type? t)
      (make-c-ptr-type (c-array-elem t))
      t))

(define (sema-process-enum-specifiers! env specs)
  (for-each
   (lambda (item)
     (let ((raw (ast-strip-span item)))
       (if (and (pair? raw) (eq? (car raw) 'c-enum))
           (let loop ((enums (caddr raw)) (next-val 0))
             (if (pair? enums)
                 (let* ((en (ast-strip-span (car enums)))
                        (esym (cadr en))
                        (expr (caddr en))
                        (val (if expr
                                 (or (c99-eval-const-int-expr env expr) next-val)
                                 next-val)))
                   (if esym
                       (sema-bind-ordinary! env esym (list 'enum-const val)))
                   (loop (cdr enums) (+ val 1))))))))
   specs))

(define (sema-resolve-param-list env param-list-node)
  (let* ((raw (ast-strip-span param-list-node))
         (params (if (and (pair? raw) (eq? (car raw) 'c-param-list)) (cadr raw) '()))
         (var? (if (and (pair? raw) (eq? (car raw) 'c-param-list)) (caddr raw) #f)))
    (if (and (= (length params) 1)
             (not var?)
             (let* ((p0 (ast-strip-span (car params)))
                    (specs (cadr p0))
                    (decl (caddr p0)))
               (and (not decl) (equal? (cdr (c-parse-decl-specs specs (lambda (s) (sema-lookup-typedef env s)))) 'void))))
        (cons '() #f)
        (let ((resolved
               (map (lambda (pnode)
                      (let* ((p (ast-strip-span pnode))
                             (specs (cadr p))
                             (decl (caddr p))
                             (base-ty (cdr (c-parse-decl-specs specs (lambda (s) (sema-lookup-typedef env s)))))
                             (res (c99-resolve-declarator-type env base-ty decl))
                             ;; Array parameters decay to pointers in C99
                             (final-ty (c99-array-decay (cdr res))))
                        (cons (car res) final-ty)))
                    params)))
          (cons resolved var?)))))

(define (c99-resolve-declarator-type env cur-ty decl-node)
  (if (not decl-node)
      (cons #f cur-ty)
      (let ((raw (ast-strip-span decl-node)))
        (cond
          ((not (pair? raw)) (cons #f cur-ty))
          ((eq? (car raw) 'c-decl-id)
           (cons (cadr raw) cur-ty))
          ((eq? (car raw) 'c-init-decl)
           (c99-resolve-declarator-type env cur-ty (cadr raw)))
          ((eq? (car raw) 'c-ptr-declarator)
           (let loop ((levels (cadr raw)) (t cur-ty))
             (if (null? levels)
                 (c99-resolve-declarator-type env t (caddr raw))
                 (loop (cdr levels) (make-c-ptr-type t)))))
          ((eq? (car raw) 'c-arr-declarator)
           (let* ((sz-expr (caddr raw))
                  (sz-val (if sz-expr
                              (let ((v (c99-eval-const-int-expr env sz-expr)))
                                (if (or (not v) (<= v 0))
                                    (%c99-sema-error! "C99-SEMA-005" "Invalid array size in declaration" decl-node)
                                    v))
                              #f)))
             (c99-resolve-declarator-type env (make-c-array-type cur-ty sz-val) (cadr raw))))
          ((eq? (car raw) 'c-fn-declarator)
           (let* ((pinfo (sema-resolve-param-list env (caddr raw)))
                  (ptypes (map cdr (car pinfo)))
                  (fn-ty (make-c-fn-type cur-ty ptypes (cdr pinfo))))
             (c99-resolve-declarator-type env fn-ty (cadr raw))))
          (else (cons #f cur-ty))))))

(define (sema-resolve-type-name env type-name-node)
  (let* ((raw (ast-strip-span type-name-node))
         (specs (cadr raw))
         (abs-decl (caddr raw))
         (base-ty (cdr (c-parse-decl-specs specs (lambda (s) (sema-lookup-typedef env s))))))
    (cdr (c99-resolve-declarator-type env base-ty abs-decl))))

;;; -----------------------------------------------------------------------
;;; 6. Lvalue Predicate & Expression Type Checking
;;; -----------------------------------------------------------------------

(define (c99-lvalue-expr? env node)
  (let* ((raw (ast-strip-span (c-typed-inner node)))
         (tag (if (pair? raw) (car raw) #f)))
    (case tag
      ((c-var-ref)
       (let ((ty (c-typed-type node)))
         (and (not (c-function-type? ty))
              (not (c-array-type? ty)))))
      ((c-index c-member) #t)
      ((c-unop) (eq? (cadr raw) 'deref))
      (else #f))))

(define (c99-analyze-expr env node)
  (if (not (pair? node))
      (%c99-sema-error! "C99-SEMA-003" "Expected expression node" node))
  (let* ((sp (ast-source-span node))
         (raw (ast-strip-span node))
         (tag (car raw)))
    (case tag
      ((c-var-ref)
       (let* ((sym (cadr raw))
              (ent (sema-lookup-ordinary env sym)))
         (if (not ent)
             (%c99-sema-error! "C99-SEMA-001"
                               (string-append "Undeclared identifier '" (symbol->string sym) "'")
                               (or sp node))
             (case (car ent)
               ((var)
                (make-c-typed (caddr ent) (list 'c-var-ref (cadr ent) sym (cadddr ent))))
               ((enum-const)
                (make-c-typed 'i32 (list 'c-enum-const (cadr ent))))
               ((fn)
                (make-c-typed (caddr ent) (list 'c-fn-ref sym)))
               (else
                (%c99-sema-error! "C99-SEMA-001"
                                  (string-append "'" (symbol->string sym) "' does not name a value")
                                  (or sp node)))))))

      ((c-const)
       (let* ((info (c99-parse-constant-info (cadr raw)))
              (ty (cdr info)))
         (make-c-typed ty (list 'c-const-val (car info) (cadr raw)))))

      ((c-str)
       (let ((decoded (c99-decode-string-literal (cadr raw))))
         (make-c-typed (make-c-ptr-type 'i8) (list 'c-str-val decoded))))

      ((c-unop)
       (let* ((op (cadr raw))
              (sub (c99-analyze-expr env (caddr raw)))
              (sty (c-typed-type sub)))
         (case op
           ((uplus neg)
            (if (not (c-arithmetic-type? sty))
                (%c99-sema-error! "C99-SEMA-003" "Unary arithmetic requires arithmetic operand" (or sp node)))
            (let* ((pt (c99-integer-promote sty))
                   (csub (c99-apply-implicit-cast sub pt)))
              (make-c-typed pt (list 'c-unop op csub))))
           ((bit-not)
            (if (not (c-integer-type? sty))
                (%c99-sema-error! "C99-SEMA-003" "Bitwise '~' requires integer operand" (or sp node)))
            (let* ((pt (c99-integer-promote sty))
                   (csub (c99-apply-implicit-cast sub pt)))
              (make-c-typed pt (list 'c-unop op csub))))
           ((lnot)
            (if (not (c-scalar-type? (c99-array-decay sty)))
                (%c99-sema-error! "C99-SEMA-003" "Logical '!' requires scalar operand" (or sp node)))
            (make-c-typed 'i32 (list 'c-unop 'lnot sub)))
           ((pre++ pre-- post++ post--)
            (if (not (c99-lvalue-expr? env sub))
                (%c99-sema-error! "C99-SEMA-002" "Expression is not an assignable lvalue for '++'/'--'" (or sp node)))
            (if (not (or (c-arithmetic-type? sty) (c-pointer-type? sty)))
                (%c99-sema-error! "C99-SEMA-003" "Invalid operand type for increment/decrement" (or sp node)))
            (make-c-typed sty (list 'c-unop op sub)))
           ((addr)
            (let* ((inner (ast-strip-span (c-typed-inner sub)))
                   (itag (car inner)))
              (if (or (memq itag '(c-var-ref c-index c-member))
                      (and (eq? itag 'c-unop) (eq? (cadr inner) 'deref)))
                  (make-c-typed (make-c-ptr-type sty) (list 'c-unop 'addr sub))
                  (%c99-sema-error! "C99-SEMA-002" "Cannot take address '&' of rvalue expression" (or sp node)))))
           ((deref)
            (let ((dt (c99-array-decay sty)))
              (if (not (c-pointer-type? dt))
                  (%c99-sema-error! "C99-SEMA-003" "Dereference '*' requires pointer operand" (or sp node)))
              (make-c-typed (c-ptr-target dt) (list 'c-unop 'deref sub))))
           (else
            (%c99-sema-error! "C99-SEMA-003" "Unsupported unary operator" (or sp node))))))

      ((c-binop)
       (let* ((op (cadr raw))
              (lhs (c99-analyze-expr env (caddr raw)))
              (rhs (c99-analyze-expr env (cadddr raw)))
              (lt (c99-array-decay (c-typed-type lhs)))
              (rt (c99-array-decay (c-typed-type rhs))))
         (case op
           ((comma)
            (make-c-typed rt (list 'c-binop 'comma lhs rhs)))
           ((land lor)
            (if (or (not (c-scalar-type? lt)) (not (c-scalar-type? rt)))
                (%c99-sema-error! "C99-SEMA-003" "Logical operators require scalar operands" (or sp node)))
            (make-c-typed 'i32 (list 'c-binop op lhs rhs)))
           ((<< >>)
            (if (or (not (c-integer-type? lt)) (not (c-integer-type? rt)))
                (%c99-sema-error! "C99-SEMA-003" "Shift operators require integer operands" (or sp node)))
            (let ((plt (c99-integer-promote lt))
                  (prt (c99-integer-promote rt)))
              (make-c-typed plt
                            (list 'c-binop op
                                  (c99-apply-implicit-cast lhs plt)
                                  (c99-apply-implicit-cast rhs prt)))))
           ((bit-and bit-xor bit-or)
            (if (or (not (c-integer-type? lt)) (not (c-integer-type? rt)))
                (%c99-sema-error! "C99-SEMA-003" "Bitwise operators require integer operands" (or sp node)))
            (let ((ct (c99-usual-arithmetic-type lt rt)))
              (make-c-typed ct
                            (list 'c-binop op
                                  (c99-apply-implicit-cast lhs ct)
                                  (c99-apply-implicit-cast rhs ct)))))
           ((+ -)
            (cond
              ((and (c-pointer-type? lt) (c-integer-type? rt))
               (make-c-typed lt (list 'c-binop op lhs (c99-apply-implicit-cast rhs 'i64))))
              ((and (eq? op '+) (c-integer-type? lt) (c-pointer-type? rt))
               (make-c-typed rt (list 'c-binop '+ (c99-apply-implicit-cast lhs 'i64) rhs)))
              ((and (eq? op '-) (c-pointer-type? lt) (c-pointer-type? rt))
               (make-c-typed 'i64 (list 'c-binop '- lhs rhs)))
              ((and (c-arithmetic-type? lt) (c-arithmetic-type? rt))
               (let ((ct (c99-usual-arithmetic-type lt rt)))
                 (make-c-typed ct
                               (list 'c-binop op
                                     (c99-apply-implicit-cast lhs ct)
                                     (c99-apply-implicit-cast rhs ct)))))
              (else
               (%c99-sema-error! "C99-SEMA-003" "Invalid operand types for '+' / '-'" (or sp node)))))
           ((* / rem)
            (if (and (eq? op 'rem) (or (not (c-integer-type? lt)) (not (c-integer-type? rt))))
                (%c99-sema-error! "C99-SEMA-003" "Modulo '%' requires integer operands" (or sp node)))
            (if (or (not (c-arithmetic-type? lt)) (not (c-arithmetic-type? rt)))
                (%c99-sema-error! "C99-SEMA-003" "Multiplicative operator requires arithmetic operands" (or sp node)))
            (if (and (memq op '(/ rem))
                     (let ((rv (c99-eval-const-int-expr env (cadddr raw))))
                       (and rv (= rv 0))))
                (%c99-sema-error! "C99-SEMA-005" "Compile-time division or modulo by zero" (or sp node)))
            (let ((ct (c99-usual-arithmetic-type lt rt)))
              (make-c-typed ct
                            (list 'c-binop op
                                  (c99-apply-implicit-cast lhs ct)
                                  (c99-apply-implicit-cast rhs ct)))))
           ((< <= > >= == !=)
            (cond
              ((and (c-pointer-type? lt) (c-pointer-type? rt))
               (make-c-typed 'i32 (list 'c-binop op lhs rhs)))
              ((and (c-pointer-type? lt) (c-integer-type? rt))
               (make-c-typed 'i32 (list 'c-binop op lhs (c99-apply-implicit-cast rhs 'u64))))
              ((and (c-integer-type? lt) (c-pointer-type? rt))
               (make-c-typed 'i32 (list 'c-binop op (c99-apply-implicit-cast lhs 'u64) rhs)))
              ((and (c-arithmetic-type? lt) (c-arithmetic-type? rt))
               (let ((ct (c99-usual-arithmetic-type lt rt)))
                 (make-c-typed 'i32
                               (list 'c-binop op
                                     (c99-apply-implicit-cast lhs ct)
                                     (c99-apply-implicit-cast rhs ct)))))
              (else
               (%c99-sema-error! "C99-SEMA-003" "Incompatible operand types for comparison" (or sp node)))))
           (else
            (%c99-sema-error! "C99-SEMA-003" "Unsupported binary operator" (or sp node))))))

      ((c-assign)
       (let* ((op (cadr raw))
              (lhs (c99-analyze-expr env (caddr raw)))
              (rhs (c99-analyze-expr env (cadddr raw)))
              (lt (c-typed-type lhs))
              (rt (c99-array-decay (c-typed-type rhs))))
         (if (not (c99-lvalue-expr? env lhs))
             (%c99-sema-error! "C99-SEMA-002" "Assignment target is not a modifiable lvalue" (or sp node)))
         (if (eq? lt 'void)
             (%c99-sema-error! "C99-SEMA-003" "Cannot assign to void" (or sp node)))
         (if (and (eq? op '=) (not (c-types-compatible? lt rt)))
             (%c99-sema-error! "C99-SEMA-003"
                               (string-append "Incompatible assignment from "
                                              (c-type->string rt) " to " (c-type->string lt))
                               (or sp node)))
         (if (eq? op '=)
             (make-c-typed lt (list 'c-assign '= lhs (c99-apply-implicit-cast rhs lt)))
             (let ((comp-ty (if (and (memq op '(+= -=)) (c-pointer-type? lt))
                                'i64
                                (if (memq op '(<<= >>=))
                                    (c99-integer-promote lt)
                                    (c99-usual-arithmetic-type lt rt)))))
               (make-c-typed lt (list 'c-assign op lhs (c99-apply-implicit-cast rhs comp-ty)))))))

      ((c-ternary)
       (let* ((cnd (c99-analyze-expr env (cadr raw)))
              (thn (c99-analyze-expr env (caddr raw)))
              (els (c99-analyze-expr env (cadddr raw)))
              (tt (c99-array-decay (c-typed-type thn)))
              (et (c99-array-decay (c-typed-type els)))
              (res-ty (cond
                        ((and (c-arithmetic-type? tt) (c-arithmetic-type? et))
                         (c99-usual-arithmetic-type tt et))
                        ((equal? tt et) tt)
                        ((c-pointer-type? tt) tt)
                        (else tt))))
         (make-c-typed res-ty
                       (list 'c-ternary cnd
                             (c99-apply-implicit-cast thn res-ty)
                             (c99-apply-implicit-cast els res-ty)))))

      ((c-cast)
       (let* ((target-ty (sema-resolve-type-name env (cadr raw)))
              (sub (c99-analyze-expr env (caddr raw))))
         (make-c-typed target-ty (list 'c-cast target-ty sub))))

      ((c-sizeof-type)
       (let ((sz (c-type-size (sema-resolve-type-name env (cadr raw)))))
         (make-c-typed 'u64 (list 'c-const-val sz (number->string sz)))))

      ((c-sizeof-expr)
       (let ((raw-sub (ast-strip-span (cadr raw))))
         (if (and (pair? raw-sub) (eq? (car raw-sub) 'c-str))
             (let ((sz (+ (string-length (c99-decode-string-literal (cadr raw-sub))) 1)))
               (make-c-typed 'u64 (list 'c-const-val sz (number->string sz))))
             (let* ((typed-sub (c99-analyze-expr env (cadr raw)))
                    (sz (c-type-size (c-typed-type typed-sub))))
               (make-c-typed 'u64 (list 'c-const-val sz (number->string sz)))))))

      ((c-call)
       (let* ((fn-expr (c99-analyze-expr env (cadr raw)))
              (raw-fty (c-typed-type fn-expr))
              (fty (if (and (c-pointer-type? raw-fty) (c-function-type? (c-ptr-target raw-fty)))
                       (c-ptr-target raw-fty)
                       raw-fty)))
         (if (not (c-function-type? fty))
             (%c99-sema-error! "C99-SEMA-004" "Called object is not a function or function pointer" (or sp node)))
         (let* ((ret-ty (c-fn-ret fty))
                (param-tys (c-fn-params fty))
                (var? (c-fn-variadic? fty))
                (arg-nodes (cddr raw))
                (nparams (length param-tys))
                (nargs (length arg-nodes)))
           (if (if var? (< nargs nparams) (not (= nargs nparams)))
               (%c99-sema-error! "C99-SEMA-004"
                                 (string-append "Function argument count mismatch: expected "
                                                (number->string nparams)
                                                (if var? "+ arguments" " arguments")
                                                ", got " (number->string nargs))
                                 (or sp node)))
           (let ((typed-args
                  (let aloop ((as arg-nodes) (pts param-tys) (acc '()))
                    (if (null? as)
                        (reverse acc)
                        (let ((ta (c99-analyze-expr env (car as))))
                          (if (pair? pts)
                              (let ((pt (car pts))
                                    (at (c99-array-decay (c-typed-type ta))))
                                (if (not (c-types-compatible? pt at))
                                    (%c99-sema-error! "C99-SEMA-004"
                                                      (string-append "Incompatible argument type: expected "
                                                                     (c-type->string pt)
                                                                     ", got " (c-type->string at))
                                                      (car as)))
                                (aloop (cdr as) (cdr pts) (cons (c99-apply-implicit-cast ta pt) acc)))
                              ;; Default argument promotions for variadic trailing args
                              (let* ((at (c99-array-decay (c-typed-type ta)))
                                     (prom (cond
                                             ((eq? at 'f32) 'f64)
                                             ((c-integer-type? at) (c99-integer-promote at))
                                             (else at))))
                                (aloop (cdr as) '() (cons (c99-apply-implicit-cast ta prom) acc)))))))))
             (make-c-typed ret-ty (cons 'c-call (cons fn-expr typed-args)))))))

      ((c-index)
       (let* ((arr (c99-analyze-expr env (cadr raw)))
              (idx (c99-analyze-expr env (caddr raw)))
              (at (c99-array-decay (c-typed-type arr))))
         (if (not (c-pointer-type? at))
             (%c99-sema-error! "C99-SEMA-003" "Subscripted value is neither array nor pointer" (or sp node)))
         (if (not (c-integer-type? (c-typed-type idx)))
             (%c99-sema-error! "C99-SEMA-003" "Array subscript is not an integer" (or sp node)))
         (make-c-typed (c-ptr-target at)
                       (list 'c-index arr (c99-apply-implicit-cast idx 'i64)))))

      (else
       (%c99-sema-error! "C99-SEMA-003" "Unsupported expression node in sema" (or sp node))))))

;;; -----------------------------------------------------------------------
;;; 7. Declaration & Statement Analysis
;;; -----------------------------------------------------------------------

(define (sema-analyze-decl env decl-node)
  (let* ((raw (ast-strip-span decl-node))
         (tag (car raw))
         (specs (cadr raw))
         (inits (caddr raw)))
    (sema-process-enum-specifiers! env specs)
    (let* ((parsed-specs (c-parse-decl-specs specs (lambda (s) (sema-lookup-typedef env s))))
           (storage (car parsed-specs))
           (base-ty (cdr parsed-specs)))
      (if (eq? tag 'c-typedef)
          (begin
            (for-each
             (lambda (init-node)
               (let* ((r (c99-resolve-declarator-type env base-ty init-node))
                      (sym (car r))
                      (ty (cdr r)))
                 (if sym
                     (sema-bind-ordinary! env sym (list 'typedef ty)))))
             inits)
            '())
          (let loop ((xs inits) (acc '()))
            (if (null? xs)
                (reverse acc)
                (let* ((id-node (ast-strip-span (car xs)))
                       (decl (cadr id-node))
                       (init-expr (caddr id-node))
                       (resolved (c99-resolve-declarator-type env base-ty decl))
                       (sym (car resolved))
                       (ty (cdr resolved)))
                  (if (not sym)
                      (loop (cdr xs) acc)
                      (if (c-function-type? ty)
                          (begin
                            (sema-register-fn! env sym ty #f)
                            (loop (cdr xs) acc))
                          (let ((existing (sema-lookup-ordinary-local env sym)))
                            (if (and existing (not (eq? storage 'extern)) (not (sema-in-global-scope? env)))
                                (%c99-sema-error! "C99-SEMA-001"
                                                  (string-append "Redefinition of local variable '"
                                                                 (symbol->string sym) "'")
                                                  decl-node))
                            (let* ((u-sym (c99-next-sema-var-id! sym))
                                   (global? (or (sema-in-global-scope? env) (eq? storage 'static) (eq? storage 'extern)))
                                   (typed-init (if init-expr
                                                   (let ((te (c99-analyze-expr env init-expr)))
                                                     (if (not (c-types-compatible? ty (c99-array-decay (c-typed-type te))))
                                                         (%c99-sema-error! "C99-SEMA-003"
                                                                           (string-append "Incompatible initializer type for '"
                                                                                          (symbol->string sym) "'")
                                                                           decl-node))
                                                     (c99-apply-implicit-cast te ty))
                                                   #f)))
                              (sema-bind-ordinary! env sym (list 'var u-sym ty global? #f))
                              (loop (cdr xs)
                                    (cons (list 'c-typed-decl u-sym sym ty global? typed-init)
                                          acc)))))))))))))

(define (sema-analyze-stmt env stmt-node)
  (let* ((sp (ast-source-span stmt-node))
         (raw (ast-strip-span stmt-node))
         (tag (car raw)))
    (case tag
      ((c-decl c-typedef)
       (cons 'c-typed-decls (sema-analyze-decl env stmt-node)))

      ((c-block)
       (sema-push-scope! env)
       (let ((res (map (lambda (it) (sema-analyze-stmt env it)) (cdr raw))))
         (sema-pop-scope! env)
         (cons 'c-block res)))

      ((c-expr-stmt)
       (list 'c-expr-stmt (if (cadr raw) (c99-analyze-expr env (cadr raw)) #f)))

      ((c-return)
       (let ((ret-ty (sema-env-curr-ret env))
             (val-expr (cadr raw)))
         (cond
           ((and (eq? ret-ty 'void) val-expr)
            (%c99-sema-error! "C99-SEMA-003" "Non-void return inside void function" (or sp stmt-node)))
           ((and (not (eq? ret-ty 'void)) (not val-expr))
            (%c99-sema-error! "C99-SEMA-003" "Missing return expression in non-void function" (or sp stmt-node)))
           (val-expr
            (let ((te (c99-analyze-expr env val-expr)))
              (if (not (c-types-compatible? ret-ty (c99-array-decay (c-typed-type te))))
                  (%c99-sema-error! "C99-SEMA-003" "Incompatible return value type" (or sp stmt-node)))
              (list 'c-return (c99-apply-implicit-cast te ret-ty))))
           (else '(c-return #f)))))

      ((c-if)
       (let* ((cnd (c99-analyze-expr env (cadr raw)))
              (thn (sema-analyze-stmt env (caddr raw)))
              (els (if (and (pair? (cdddr raw)) (cadddr raw))
                       (sema-analyze-stmt env (cadddr raw))
                       #f)))
         (list 'c-if cnd thn els)))

      ((c-while)
       (let ((cnd (c99-analyze-expr env (cadr raw))))
         (sema-env-loop-depth-set! env (+ (sema-env-loop-depth env) 1))
         (let ((body (sema-analyze-stmt env (caddr raw))))
           (sema-env-loop-depth-set! env (- (sema-env-loop-depth env) 1))
           (list 'c-while cnd body))))

      ((c-do-while)
       (sema-env-loop-depth-set! env (+ (sema-env-loop-depth env) 1))
       (let ((body (sema-analyze-stmt env (cadr raw))))
         (sema-env-loop-depth-set! env (- (sema-env-loop-depth env) 1))
         (let ((cnd (c99-analyze-expr env (caddr raw))))
           (list 'c-do-while body cnd))))

      ((c-for)
       (sema-push-scope! env)
       (let* ((init-raw (cadr raw))
              (cond-raw (caddr raw))
              (step-raw (cadddr raw))
              (body-raw (list-ref raw 4))
              (init-typed
               (if init-raw
                   (let ((si (ast-strip-span init-raw)))
                     (if (and (pair? si) (memq (car si) '(c-decl c-typedef)))
                         (cons 'c-typed-decls (sema-analyze-decl env init-raw))
                         (c99-analyze-expr env init-raw)))
                   #f))
              (cond-typed (if cond-raw (c99-analyze-expr env cond-raw) #f))
              (step-typed (if step-raw (c99-analyze-expr env step-raw) #f)))
         (sema-env-loop-depth-set! env (+ (sema-env-loop-depth env) 1))
         (let ((body-typed (sema-analyze-stmt env body-raw)))
           (sema-env-loop-depth-set! env (- (sema-env-loop-depth env) 1))
           (sema-pop-scope! env)
           (list 'c-for init-typed cond-typed step-typed body-typed))))

      ((c-switch)
       (let ((cnd (c99-analyze-expr env (cadr raw))))
         (sema-env-switch-depth-set! env (+ (sema-env-switch-depth env) 1))
         (let ((body (sema-analyze-stmt env (caddr raw))))
           (sema-env-switch-depth-set! env (- (sema-env-switch-depth env) 1))
           (list 'c-switch cnd body))))

      ((c-case)
       (let* ((val (c99-eval-const-int-expr env (cadr raw)))
              (sub (sema-analyze-stmt env (caddr raw))))
         (if (not val)
             (%c99-sema-error! "C99-SEMA-005" "case label does not reduce to an integer constant" (or sp stmt-node)))
         (list 'c-case val sub)))

      ((c-default)
       (list 'c-default (sema-analyze-stmt env (cadr raw))))

      ((c-break)
       (if (and (<= (sema-env-loop-depth env) 0) (<= (sema-env-switch-depth env) 0))
           (%c99-sema-error! "C99-SEMA-005" "'break' statement not within loop or switch" (or sp stmt-node)))
       '(c-break))

      ((c-continue)
       (if (<= (sema-env-loop-depth env) 0)
           (%c99-sema-error! "C99-SEMA-005" "'continue' statement not within a loop" (or sp stmt-node)))
       '(c-continue))

      ((c-goto)
       (list 'c-goto (cadr raw)))

      ((c-label)
       (list 'c-label (cadr raw) (sema-analyze-stmt env (caddr raw))))

      (else
       (%c99-sema-error! "C99-SEMA-003" "Unsupported statement in sema" (or sp stmt-node))))))

(define (sema-analyze-fn-def env fn-node)
  (let* ((raw (ast-strip-span fn-node))
         (fn-sym (cadr raw))
         (specs (caddr raw))
         (decl (cadddr raw))
         (body (if (>= (length raw) 7) (list-ref raw 6) (list-ref raw 5))))
    (sema-process-enum-specifiers! env specs)
    (let* ((base-ret (cdr (c-parse-decl-specs specs (lambda (s) (sema-lookup-typedef env s)))))
           (resolved (c99-resolve-declarator-type env base-ret decl))
           (fn-type (cdr resolved))
           (ret-ty (c-fn-ret fn-type))
           ;; Extract parameter (name . type) pairs directly from the fn-declarator
           (param-pairs
            (let find-fn ((d (ast-strip-span decl)))
              (cond
                ((not (pair? d)) '())
                ((eq? (car d) 'c-fn-declarator)
                 (let ((inner (ast-strip-span (cadr d))))
                   (if (and (pair? inner) (eq? (car inner) 'c-decl-id))
                       (car (sema-resolve-param-list env (caddr d)))
                       (let ((sub (find-fn inner)))
                         (if (pair? sub) sub (car (sema-resolve-param-list env (caddr d))))))))
                ((eq? (car d) 'c-ptr-declarator)
                 (find-fn (ast-strip-span (caddr d))))
                (else '())))))
      (sema-register-fn! env fn-sym fn-type #t)
      (sema-push-scope! env)
      (let ((prev-ret (sema-env-curr-ret env)))
        (sema-env-curr-ret-set! env ret-ty)
        (let* ((typed-params
                (let loop ((ps param-pairs) (idx 0) (acc '()))
                  (if (null? ps)
                      (reverse acc)
                      (let* ((psym (caar ps))
                             (pty (cdar ps))
                             (u-sym (c99-next-sema-var-id! (or psym 'param))))
                        (if psym
                            (sema-bind-ordinary! env psym (list 'var u-sym pty #f idx)))
                        (loop (cdr ps) (+ idx 1) (cons (list u-sym psym pty idx) acc))))))
               (typed-body (sema-analyze-stmt env body)))
          (sema-env-curr-ret-set! env prev-ret)
          (sema-pop-scope! env)
          (list 'c-typed-fn fn-sym ret-ty (c-fn-variadic? fn-type) typed-params typed-body))))))

;;; -----------------------------------------------------------------------
;;; 8. Top-Level Entrypoint: (c99-analyze-program ast)
;;; -----------------------------------------------------------------------

(define (c99-analyze-program ast)
  (c99-reset-sema-var-id!)
  (let* ((env (make-c99-sema-env))
         (raw (ast-strip-span ast))
         (ext-decls (if (and (pair? raw) (eq? (car raw) 'c-translation-unit))
                        (cdr raw)
                        (%c99-sema-error! "C99-SEMA-003" "Expected c-translation-unit" ast))))
    (let loop ((ds ext-decls) (globals '()) (funcs '()))
      (if (null? ds)
          (list 'c-typed-unit (reverse globals) (reverse funcs))
          (let* ((d (car ds))
                 (di (ast-strip-span d))
                 (tag (if (pair? di) (car di) #f)))
            (case tag
              ((c-decl c-typedef)
               (let ((glist (sema-analyze-decl env d)))
                 (loop (cdr ds)
                       (append (reverse glist) globals)
                       funcs)))
              ((c-fn-def)
               (let ((fnode (sema-analyze-fn-def env d)))
                 (loop (cdr ds) globals (cons fnode funcs))))
              (else
               (%c99-sema-error! "C99-SEMA-003" "Invalid top-level external declaration" d))))))))
