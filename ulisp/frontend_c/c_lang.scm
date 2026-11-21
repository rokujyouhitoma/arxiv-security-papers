;;; =======================================================================
;;; ULisp C99 Frontend: Nanopass C AST (L_c_ast / L_c_typed) & <c-type>
;;; Conforms to DSN-33-11 §3.2/§4.2, DSN-33-32 & Issues #915 / #916
;;; Provides:
;;;   1. Canonical <c-type> representation and SysV ABI basic layout helpers
;;;   2. Nanopass language definitions: L_c_ast and L_c_typed
;;;   3. Structural & invariant verifier: (verify-c99-ast ast)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. <c-type> Representation & Predicates
;;; -----------------------------------------------------------------------

(define (c-type-void) 'void)
(define (c-type-bool) 'bool)
(define (c-type-i8)   'i8)
(define (c-type-u8)   'u8)
(define (c-type-i16)  'i16)
(define (c-type-u16)  'u16)
(define (c-type-i32)  'i32)
(define (c-type-u32)  'u32)
(define (c-type-i64)  'i64)
(define (c-type-u64)  'u64)
(define (c-type-f32)  'f32)
(define (c-type-f64)  'f64)

(define (make-c-ptr-type target)
  (list 'ptr target))

(define (make-c-array-type elem len-or-false)
  (list 'array elem len-or-false))

(define (make-c-struct-type tag fields)
  (list 'struct tag fields))

(define (make-c-union-type tag fields)
  (list 'union tag fields))

(define (make-c-enum-type tag)
  (list 'enum tag))

(define (make-c-fn-type ret params variadic?)
  (list 'fn ret params (if variadic? #t #f)))

(define (c-void-type? t)
  (eq? t 'void))

(define (c-enum-type? t)
  (and (pair? t) (eq? (car t) 'enum)))

(define (c-integer-type? t)
  (or (memq t '(bool i8 u8 i16 u16 i32 u32 i64 u64))
      (c-enum-type? t)))

(define (c-unsigned-type? t)
  (if (memq t '(bool u8 u16 u32 u64)) #t #f))

(define (c-signed-type? t)
  (or (memq t '(i8 i16 i32 i64))
      (c-enum-type? t)))

(define (c-float-type? t)
  (if (memq t '(f32 f64)) #t #f))

(define (c-arithmetic-type? t)
  (or (c-integer-type? t) (c-float-type? t)))

(define (c-pointer-type? t)
  (and (pair? t) (eq? (car t) 'ptr)))

(define (c-array-type? t)
  (and (pair? t) (eq? (car t) 'array)))

(define (c-struct-type? t)
  (and (pair? t) (eq? (car t) 'struct)))

(define (c-union-type? t)
  (and (pair? t) (eq? (car t) 'union)))

(define (c-function-type? t)
  (and (pair? t) (eq? (car t) 'fn)))

(define (c-scalar-type? t)
  (or (c-arithmetic-type? t) (c-pointer-type? t)))

(define (c-type? t)
  (or (eq? t 'void)
      (c-arithmetic-type? t)
      (and (pair? t)
           (memq (car t) '(ptr array struct union enum fn)))))

(define (c-ptr-target t)
  (if (c-pointer-type? t) (cadr t) #f))

(define (c-array-elem t)
  (if (c-array-type? t) (cadr t) #f))

(define (c-array-length t)
  (if (c-array-type? t) (caddr t) #f))

(define (c-aggregate-tag t)
  (if (or (c-struct-type? t) (c-union-type? t) (c-enum-type? t))
      (cadr t)
      #f))

(define (c-aggregate-fields t)
  (if (or (c-struct-type? t) (c-union-type? t))
      (caddr t)
      '()))

(define (c-fn-ret t)
  (if (c-function-type? t) (cadr t) #f))

(define (c-fn-params t)
  (if (c-function-type? t) (caddr t) '()))

(define (c-fn-variadic? t)
  (if (c-function-type? t) (cadddr t) #f))

;;; -----------------------------------------------------------------------
;;; 2. SysV AMD64 Size, Alignment, Integer Rank & LIR Type Mapping
;;; -----------------------------------------------------------------------

(define (c-type-align-up n align)
  (if (<= align 1)
      n
      (let ((rem (modulo n align)))
        (if (= rem 0) n (+ n (- align rem))))))

(define (c-type-size t)
  (cond
    ((eq? t 'void) 0)
    ((memq t '(bool i8 u8)) 1)
    ((memq t '(i16 u16)) 2)
    ((memq t '(i32 u32 f32)) 4)
    ((memq t '(i64 u64 f64)) 8)
    ((c-enum-type? t) 4)
    ((c-pointer-type? t) 8)
    ((c-function-type? t) 8)
    ((c-array-type? t)
     (let ((cnt (c-array-length t))
           (esz (c-type-size (c-array-elem t))))
       (if (integer? cnt) (* cnt esz) esz)))
    ((c-struct-type? t)
     (let loop ((fs (c-aggregate-fields t)) (off 0) (max-a 1))
       (if (null? fs)
           (c-type-align-up off max-a)
           (let* ((ft (cadar fs))
                  (fa (c-type-align ft))
                  (fsz (c-type-size ft))
                  (aligned-off (c-type-align-up off fa)))
             (loop (cdr fs) (+ aligned-off fsz) (max max-a fa))))))
    ((c-union-type? t)
     (let loop ((fs (c-aggregate-fields t)) (max-s 0) (max-a 1))
       (if (null? fs)
           (c-type-align-up max-s max-a)
           (let* ((ft (cadar fs))
                  (fa (c-type-align ft))
                  (fsz (c-type-size ft)))
             (loop (cdr fs) (max max-s fsz) (max max-a fa))))))
    (else 8)))

(define (c-type-align t)
  (cond
    ((eq? t 'void) 1)
    ((memq t '(bool i8 u8)) 1)
    ((memq t '(i16 u16)) 2)
    ((memq t '(i32 u32 f32)) 4)
    ((memq t '(i64 u64 f64)) 8)
    ((c-enum-type? t) 4)
    ((c-pointer-type? t) 8)
    ((c-function-type? t) 8)
    ((c-array-type? t) (c-type-align (c-array-elem t)))
    ((or (c-struct-type? t) (c-union-type? t))
     (let loop ((fs (c-aggregate-fields t)) (max-a 1))
       (if (null? fs)
           max-a
           (loop (cdr fs) (max max-a (c-type-align (cadar fs)))))))
    (else 8)))

(define (c-type-rank t)
  (cond
    ((eq? t 'bool) 1)
    ((memq t '(i8 u8)) 2)
    ((memq t '(i16 u16)) 3)
    ((or (memq t '(i32 u32)) (c-enum-type? t)) 4)
    ((memq t '(i64 u64)) 5)
    ((eq? t 'f32) 6)
    ((eq? t 'f64) 7)
    (else 0)))

(define (c-type->signed-counterpart t)
  (case t
    ((bool u8 i8) 'i8)
    ((u16 i16)    'i16)
    ((u32 i32)    'i32)
    ((u64 i64)    'i64)
    (else (if (c-enum-type? t) 'i32 t))))

(define (c-type->unsigned-counterpart t)
  (case t
    ((bool i8 u8) 'u8)
    ((i16 u16)    'u16)
    ((i32 u32)    'u32)
    ((i64 u64)    'u64)
    (else (if (c-enum-type? t) 'u32 t))))

(define (c-type->lir-ty t)
  (cond
    ((memq t '(bool u8)) 'u8)
    ((memq t '(i8 i16 u16 i32 u32 i64 u64 f32 f64)) t)
    ((c-enum-type? t) 'i32)
    ((or (c-pointer-type? t) (c-array-type? t) (c-function-type? t)) 'ptr)
    (else 'i64)))

(define (c-types-compatible? t1 t2)
  (cond
    ((equal? t1 t2) #t)
    ((and (c-pointer-type? t1) (c-pointer-type? t2))
     (or (eq? (c-ptr-target t1) 'void)
         (eq? (c-ptr-target t2) 'void)
         (c-types-compatible? (c-ptr-target t1) (c-ptr-target t2))))
    ((and (c-arithmetic-type? t1) (c-arithmetic-type? t2)) #t)
    (else #f)))

(define (c-type->string t)
  (cond
    ((symbol? t) (symbol->string t))
    ((c-pointer-type? t) (string-append (c-type->string (c-ptr-target t)) "*"))
    ((c-array-type? t) (string-append (c-type->string (c-array-elem t)) "[]"))
    ((c-enum-type? t) "enum")
    ((c-struct-type? t) "struct")
    ((c-union-type? t) "union")
    ((c-function-type? t) "fn")
    (else "c-type")))

;;; -----------------------------------------------------------------------
;;; 3. Declaration Specifier List -> Base <c-type> & Storage Class
;;; -----------------------------------------------------------------------

(define (%c-flatten-raw-specs node)
  (let ((raw (ast-strip-span node)))
    (cond
      ((null? raw) '())
      ((boolean? raw) '())
      ((and (string? raw) (string=? raw "")) '())
      ((symbol? raw) (list raw))
      ((and (pair? raw) (memq (car raw) '(c-struct c-union c-enum c-typedef-name)))
       (list raw))
      ((pair? raw)
       (append (%c-flatten-raw-specs (car raw))
               (%c-flatten-raw-specs (cdr raw))))
      (else '()))))

(define (c-parse-decl-specs specs-node typedef-lookup)
  (let ((items (%c-flatten-raw-specs specs-node)))
    (let loop ((xs items)
               (storage #f)
               (signedness #f)
               (long-count 0)
               (short? #f)
               (base #f))
      (if (null? xs)
          (let ((final-ty
                 (cond
                   ((and base (not (symbol? base))) base)
                   ((eq? base 'void) 'void)
                   ((eq? base 'bool) 'bool)
                   ((eq? base 'float) 'f32)
                   ((eq? base 'double) 'f64)
                   ((eq? base 'char)
                    (if (eq? signedness 'unsigned) 'u8 'i8))
                   (short?
                    (if (eq? signedness 'unsigned) 'u16 'i16))
                   ((>= long-count 1)
                    (if (eq? signedness 'unsigned) 'u64 'i64))
                   ((eq? signedness 'unsigned) 'u32)
                   (else 'i32))))
            (cons storage final-ty))
          (let ((it (car xs)))
            (cond
              ((memq it '(typedef extern static auto register))
               (loop (cdr xs) it signedness long-count short? base))
              ((memq it '(const restrict volatile inline))
               (loop (cdr xs) storage signedness long-count short? base))
              ((eq? it 'signed)
               (loop (cdr xs) storage 'signed long-count short? base))
              ((eq? it 'unsigned)
               (loop (cdr xs) storage 'unsigned long-count short? base))
              ((eq? it 'long)
               (loop (cdr xs) storage signedness (+ long-count 1) short? base))
              ((eq? it 'short)
               (loop (cdr xs) storage signedness long-count #t base))
              ((eq? it 'void)
               (loop (cdr xs) storage signedness long-count short? 'void))
              ((eq? it '_Bool)
               (loop (cdr xs) storage signedness long-count short? 'bool))
              ((eq? it 'char)
               (loop (cdr xs) storage signedness long-count short? 'char))
              ((eq? it 'int)
               (loop (cdr xs) storage signedness long-count short? (or base 'int)))
              ((eq? it 'float)
               (loop (cdr xs) storage signedness long-count short? 'float))
              ((eq? it 'double)
               (loop (cdr xs) storage signedness long-count short? 'double))
              ((and (pair? it) (eq? (car it) 'c-typedef-name))
               (let* ((td-sym (cadr it))
                      (resolved (and typedef-lookup (typedef-lookup td-sym))))
                 (loop (cdr xs) storage signedness long-count short? (or resolved 'i64))))
              ((and (pair? it) (eq? (car it) 'c-enum))
               (loop (cdr xs) storage signedness long-count short?
                     (make-c-enum-type (cadr it))))
              ((and (pair? it) (eq? (car it) 'c-struct))
               (loop (cdr xs) storage signedness long-count short?
                     (make-c-struct-type (cadr it) '())))
              ((and (pair? it) (eq? (car it) 'c-union))
               (loop (cdr xs) storage signedness long-count short?
                     (make-c-union-type (cadr it) '())))
              (else
               (loop (cdr xs) storage signedness long-count short? base))))))))

;;; -----------------------------------------------------------------------
;;; 4. Nanopass Language Definitions: L_c_ast & L_c_typed (Issue #915/#916)
;;; -----------------------------------------------------------------------

(define-language L_c_ast
  (entry TranslationUnit)
  (terminals
    (symbol  (sym op assign_op))
    (string  (str raw_str))
    (integer (n bid))
    (boolean (bool_val))
    (any     (any_node specs params inits items fields enums)))
  (TranslationUnit (tu)
    (c-translation-unit ext ...))
  (ExternalDecl (ext)
    (c-fn-def sym specs decl params stmt)
    (c-fn-def sym specs decl params stmt any_node)
    (c-decl specs inits)
    (c-typedef specs inits))
  (Declarator (decl)
    (c-decl-id sym)
    (c-decl-id sym bid)
    (c-ptr-declarator any_node decl)
    (c-arr-declarator decl any_node)
    (c-fn-declarator decl params)
    (c-init-decl decl any_node))
  (Stmt (stmt)
    (c-block items ...)
    (c-if expr stmt1)
    (c-if expr stmt1 stmt2)
    (c-switch expr stmt)
    (c-case expr stmt)
    (c-default stmt)
    (c-while expr stmt)
    (c-do-while stmt expr)
    (c-for any_node1 any_node2 any_node3 stmt)
    (c-goto sym)
    (c-label sym stmt)
    (c-continue)
    (c-break)
    (c-return any_node)
    (c-expr-stmt any_node)
    (c-decl specs inits)
    (c-typedef specs inits))
  (Expr (expr)
    (c-var-ref sym bid)
    (c-var-ref sym any_node)
    (c-const raw_str)
    (c-str raw_str)
    (c-unop op expr)
    (c-binop op expr1 expr2)
    (c-assign assign_op expr1 expr2)
    (c-ternary expr1 expr2 expr3)
    (c-call expr0 expr ...)
    (c-index expr1 expr2)
    (c-member expr sym bool_val)
    (c-cast any_node expr)
    (c-sizeof-type any_node)
    (c-sizeof-expr expr)
    (c-compound-lit any_node inits)))

(define-language L_c_typed
  (extends L_c_ast)
  (entry TranslationUnit)
  (terminals
    (+ (any (ctype))))
  (Expr (expr)
    (+ (c-typed ctype expr)
       (c-implicit-cast ctype expr))))

;;; -----------------------------------------------------------------------
;;; 5. L_c_ast Verification Helper (Source Span & Structure Check)
;;; -----------------------------------------------------------------------

(define *c99-valid-binops*
  '(+ - * / rem << >> < <= > >= == != bit-and bit-xor bit-or land lor comma))

(define *c99-valid-unops*
  '(pre++ pre-- post++ post-- addr deref uplus neg bit-not lnot))

(define *c99-valid-assign-ops*
  '(= *= /= rem= += -= <<= >>= bit-and= bit-xor= bit-or=))

(define (%c99-report-parse-violation msg node)
  (let* ((sp (if (ast-has-span? node)
                 (ast-source-span node)
                 (make-source-span "<c99-ast>" 1 1 1 1 #f (next-source-span-id!))))
         (diag (make-diagnostic 'error "C99-PARSE-003" sp msg)))
    (report-diagnostic diag)
    (raise (list 'c99-ast-error "C99-PARSE-003" msg node))))

(define (%c99-verify-expr-node node)
  (if (not (pair? node))
      (%c99-report-parse-violation "Expected C99 expression node" node)
      (let* ((inner (ast-strip-span node))
             (tag (if (pair? inner) (car inner) #f)))
        (case tag
          ((c-var-ref)
           (if (and (= (length inner) 3)
                    (symbol? (cadr inner))
                    (or (integer? (caddr inner)) (not (caddr inner))))
               #t
               (%c99-report-parse-violation "Malformed c-var-ref node" node)))
          ((c-const c-str)
           (if (and (= (length inner) 2) (string? (cadr inner)))
               #t
               (%c99-report-parse-violation "Malformed c-const/c-str literal node" node)))
          ((c-unop)
           (and (or (memq (cadr inner) *c99-valid-unops*)
                    (%c99-report-parse-violation "Invalid C99 unary operator" node))
                (%c99-verify-expr-node (caddr inner))))
          ((c-binop)
           (and (or (memq (cadr inner) *c99-valid-binops*)
                    (%c99-report-parse-violation "Invalid C99 binary operator" node))
                (%c99-verify-expr-node (caddr inner))
                (%c99-verify-expr-node (cadddr inner))))
          ((c-assign)
           (and (or (memq (cadr inner) *c99-valid-assign-ops*)
                    (%c99-report-parse-violation "Invalid C99 assignment operator" node))
                (%c99-verify-expr-node (caddr inner))
                (%c99-verify-expr-node (cadddr inner))))
          ((c-ternary)
           (and (%c99-verify-expr-node (cadr inner))
                (%c99-verify-expr-node (caddr inner))
                (%c99-verify-expr-node (cadddr inner))))
          ((c-call)
           (and (%c99-verify-expr-node (cadr inner))
                (let loop ((args (cddr inner)))
                  (if (null? args) #t
                      (and (%c99-verify-expr-node (car args))
                           (loop (cdr args)))))))
          ((c-index)
           (and (%c99-verify-expr-node (cadr inner))
                (%c99-verify-expr-node (caddr inner))))
          ((c-member)
           (and (%c99-verify-expr-node (cadr inner))
                (symbol? (caddr inner))
                (boolean? (cadddr inner))))
          ((c-cast)
           (%c99-verify-expr-node (caddr inner)))
          ((c-sizeof-type)
           #t)
          ((c-sizeof-expr)
           (%c99-verify-expr-node (cadr inner)))
          ((c-compound-lit)
           #t)
          (else
           (%c99-report-parse-violation "Unknown C99 expression tag" node))))))

(define (%c99-verify-stmt-node node)
  (if (not (pair? node))
      (%c99-report-parse-violation "Expected C99 statement node" node)
      (let* ((inner (ast-strip-span node))
             (tag (if (pair? inner) (car inner) #f)))
        (case tag
          ((c-block)
           (let loop ((items (cdr inner)))
             (if (null? items) #t
                 (and (%c99-verify-stmt-node (car items))
                      (loop (cdr items))))))
          ((c-if)
           (and (%c99-verify-expr-node (cadr inner))
                (%c99-verify-stmt-node (caddr inner))
                (if (and (pair? (cdddr inner)) (cadddr inner))
                    (%c99-verify-stmt-node (cadddr inner))
                    #t)))
          ((c-switch)
           (and (%c99-verify-expr-node (cadr inner))
                (%c99-verify-stmt-node (caddr inner))))
          ((c-case)
           (and (%c99-verify-expr-node (cadr inner))
                (%c99-verify-stmt-node (caddr inner))))
          ((c-default)
           (%c99-verify-stmt-node (cadr inner)))
          ((c-while)
           (and (%c99-verify-expr-node (cadr inner))
                (%c99-verify-stmt-node (caddr inner))))
          ((c-do-while)
           (and (%c99-verify-stmt-node (cadr inner))
                (%c99-verify-expr-node (caddr inner))))
          ((c-for)
           (let ((init (cadr inner))
                 (cond-e (caddr inner))
                 (step-e (cadddr inner))
                 (body (list-ref inner 4)))
             (and (if init
                      (let ((si (ast-strip-span init)))
                        (if (and (pair? si) (memq (car si) '(c-decl c-typedef)))
                            #t
                            (%c99-verify-expr-node init)))
                      #t)
                  (if cond-e (%c99-verify-expr-node cond-e) #t)
                  (if step-e (%c99-verify-expr-node step-e) #t)
                  (%c99-verify-stmt-node body))))
          ((c-goto)
           (if (symbol? (cadr inner)) #t
               (%c99-report-parse-violation "c-goto target must be symbol" node)))
          ((c-label)
           (and (symbol? (cadr inner))
                (%c99-verify-stmt-node (caddr inner))))
          ((c-continue c-break) #t)
          ((c-return)
           (if (cadr inner) (%c99-verify-expr-node (cadr inner)) #t))
          ((c-expr-stmt)
           (if (cadr inner) (%c99-verify-expr-node (cadr inner)) #t))
          ((c-decl c-typedef)
           #t)
          (else
           (%c99-report-parse-violation "Unknown C99 statement tag" node))))))

(define (verify-c99-ast ast)
  (if (not (ast-has-span? ast))
      (%c99-report-parse-violation "TranslationUnit root missing <source-span>" ast))
  (let ((raw (ast-strip-span ast)))
    (if (not (and (pair? raw) (eq? (car raw) 'c-translation-unit)))
        (%c99-report-parse-violation "AST root is not c-translation-unit" ast))
    (let loop ((decls (cdr raw)))
      (if (null? decls)
          #t
          (let* ((d (car decls))
                 (di (ast-strip-span d))
                 (tag (if (pair? di) (car di) #f)))
            (if (not (ast-has-span? d))
                (%c99-report-parse-violation "Top-level declaration missing <source-span>" d))
            (case tag
              ((c-fn-def)
               (let ((body (if (>= (length di) 7) (list-ref di 6) (list-ref di 5))))
                 (%c99-verify-stmt-node body)
                 (loop (cdr decls))))
              ((c-decl c-typedef)
               (loop (cdr decls)))
              (else
               (%c99-report-parse-violation "Invalid top-level ExternalDecl node" d))))))))
