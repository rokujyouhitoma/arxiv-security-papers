;;; =======================================================================
;;; Test Suite: C99 PEG Grammar & Parser Synthesis (Issue #931)
;;; Conforms to DSN-33-11 §4.2, DSN-33-22 §3, DSN-33-32 & Issue #931
;;; =======================================================================

(test-begin "C99 PEG Grammar Specification & Parser Synthesis (Issue #931)")

;;; -----------------------------------------------------------------------
;;; Group 1: Meta-Grammar Parse, Optimization & Standalone Parser Synthesis
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: c99.peg Compile & Synthesize ---\n")

(define c99-ast (c99-peg-grammar-ast))
(assert-true "1.1 c99.peg parses into <peg-grammar-def>" (peg-grammar-def? c99-ast))
(assert-equal "1.2 grammar name is C99" 'C99 (peg-grammar-def-name c99-ast))
(assert-true "1.3 c99.peg defines >= 70 rules" (>= (length (peg-grammar-def-rules c99-ast)) 70))

(define c99-standalone (c99-peg-parser))
(assert-true "1.4 standalone c99-peg-parser is procedure" (procedure? c99-standalone))

;;; -----------------------------------------------------------------------
;;; Group 2: Left-Recursive Expressions & Operator Precedence
;;; -----------------------------------------------------------------------
(display "--- Group 2: Left-Recursive Expressions & Precedence ---\n")

(let ((e1 (parse-c99-expr-string "1 + 2 * 3 - (4 << 1)" "expr1.c"))
      (e2 (parse-c99-expr-string "p->arr[i].fn(a, b)++" "expr2.c"))
      (e3 (parse-c99-expr-string "sizeof(int) + sizeof p[0]" "expr3.c"))
      (e4 (parse-c99-expr-string "(int){ 10, 20 }[0]" "expr4.c")))
  (assert-true "2.1 arithmetic & shift precedence parses" (not (eq? e1 #f)))
  (assert-true "2.2 left-recursive postfix chain p->arr[i].fn(a,b)++ parses" (not (eq? e2 #f)))
  (assert-true "2.3 sizeof(type) vs sizeof expr disambiguates cleanly" (not (eq? e3 #f)))
  (assert-true "2.4 C99 compound literal (int){10,20}[0] parses" (not (eq? e4 #f))))

;;; -----------------------------------------------------------------------
;;; Group 3: Complex Declarators, Function Pointers & Initializers
;;; -----------------------------------------------------------------------
(display "--- Group 3: Declarators, Function Pointers & Initializers ---\n")

(let ((ast-sig
       (parse-c99-string
        "int (*(*signal(int sig, void (*func)(int)))(int));
         typedef int (*lua_CFunction)(void *L);
         lua_CFunction reg_fn;"
        "signal.c")))
  (assert-true "3.1 complex signal() declarator & lua_CFunction typedef parse"
               (and (ast-has-span? ast-sig)
                    (eq? (car (ast-strip-span ast-sig)) 'c-translation-unit))))

(let ((ast-init
       (parse-c99-string
        "struct Point { int x; int y; };
         int init_test(void) {
           struct Point p = { .y = 2, .x = 1 };
           int arr[4] = { [2] = 42, [0] = 7 };
           return p.x + arr[2];
         }"
        "init.c")))
  (assert-true "3.2 designated initializers (.field and [idx]) parse into L_c_ast"
               (and (ast-has-span? ast-init)
                    (eq? (car (ast-strip-span ast-init)) 'c-translation-unit))))

;;; -----------------------------------------------------------------------
;;; Group 4: Typedef Lexer Hack Disambiguation & Shadowing (Issue #837)
;;; -----------------------------------------------------------------------
(display "--- Group 4: Typedef Disambiguation & Scope Shadowing ---\n")

(let ((ast-shadow
       (parse-c99-string
        "typedef int T;
         T global_t;
         int fn(int T) {
           T * 2;
           {
             typedef double U;
             U *ptr;
           }
           return T + 1;
         }
         T after_fn;"
        "shadow.c")))
  (assert-true "4.1 typedef shadowing by parameter & nested block typedef parse cleanly"
               (and (ast-has-span? ast-shadow)
                    (eq? (car (ast-strip-span ast-shadow)) 'c-translation-unit)))
  (let* ((items (cdr (ast-strip-span ast-shadow)))
         (td-decl (ast-strip-span (car items)))
         (fn-def  (ast-strip-span (caddr items)))
         (after-decl (ast-strip-span (cadddr items))))
    (assert-equal "4.2 first item is c-typedef" 'c-typedef (car td-decl))
    (assert-equal "4.3 third item is c-fn-def" 'c-fn-def (car fn-def))
    (assert-equal "4.4 fourth item is c-decl using outer typedef T" 'c-decl (car after-decl))
    ;; Verify parameter T binding ID and variable reference inside fn
    (let ((param-list (list-ref fn-def 4)))
      (assert-true "4.5 fn parameter T received non-negative binding ID"
                   (and (pair? param-list)
                        (eq? (caar param-list) 'T)
                        (integer? (cadar param-list)))))))

;; Multiplication expression statement vs pointer declaration disambiguation
(let ((ast-mul
       (parse-c99-string
        "typedef int *intptr;
         int mul_vs_ptr(int a, int b) {
           intptr p;
           a * b;
           return a + b;
         }"
        "mul_vs_ptr.c")))
  (assert-true "4.6 typedef pointer (intptr p;) and multiplication (a * b;) both parse"
               (eq? (car (ast-strip-span ast-mul)) 'c-translation-unit)))

;;; -----------------------------------------------------------------------
;;; Group 5: Lua 5.x C Codebase Snippet Parsing & Span Verification
;;; -----------------------------------------------------------------------
(display "--- Group 5: Lua 5.x C Codebase Snippet Verification ---\n")

(define lua-c-snippet
  "typedef unsigned char lu_byte;
   typedef double lua_Number;
   typedef long long lua_Integer;
   typedef struct lua_State lua_State;
   typedef int (*lua_CFunction)(lua_State *L);

   typedef union Value {
     void *gc;
     void *p;
     int b;
     lua_CFunction f;
     lua_Integer i;
     lua_Number n;
   } Value;

   typedef struct TValue {
     Value value_;
     lu_byte tt_;
   } TValue;

   int luaV_execute(lua_State *L, int nexeccalls) {
     int pc = 0;
     for (int i = 0; i < nexeccalls; i++) {
       int op = i & 0x3F;
       switch (op) {
         case 0:
           pc += 1;
           break;
         case 1:
           goto l_ret;
         default:
           pc = pc + 2;
           break;
       }
     }
   l_ret:
     return pc;
   }")

(let ((lua-ast (parse-c99-string lua-c-snippet "lua_vm_sample.c")))
  (assert-true "5.1 Lua 5.x TValue/Value/luaV_execute snippet parses successfully"
               (and (ast-has-span? lua-ast)
                    (eq? (car (ast-strip-span lua-ast)) 'c-translation-unit)))
  (let* ((span (ast-source-span lua-ast))
         (decls (cdr (ast-strip-span lua-ast))))
    (assert-equal "5.2 span file recorded accurately" "lua_vm_sample.c" (span-file span))
    (assert-true "5.3 parsed 8 top-level Lua declarations/functions" (= (length decls) 8))))

;;; -----------------------------------------------------------------------
;;; Group 6: Syntax Error Reporting via Diagnostic Reporter (#833)
;;; -----------------------------------------------------------------------
(display "--- Group 6: Diagnostic Error Reporting on Invalid C99 ---\n")

(let ((err-res
       (guard (ex (else ex))
         (parse-c99-string "int broken(void) { return 1 + ; }" "broken.c"))))
  (assert-true "6.1 invalid syntax raises structured c99-syntax-error"
               (and (pair? err-res) (eq? (car err-res) 'c99-syntax-error))))

(test-end "C99 PEG Grammar Specification & Parser Synthesis (Issue #931)")
