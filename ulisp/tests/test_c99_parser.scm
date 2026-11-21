;;; =======================================================================
;;; Test Suite: C99 Parser, Nanopass L_c_ast & CPP Integration (Issue #915)
;;; Conforms to DSN-33-11 §4.2, DSN-33-32 & Issue #915
;;; =======================================================================

(test-begin "C99 Parser, L_c_ast & Lexer Hack Disambiguation (Issue #915)")

;;; -----------------------------------------------------------------------
;;; Group 1: Nanopass L_c_ast / L_c_typed Registration & <c-type> Helpers
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: L_c_ast / L_c_typed & <c-type> Schema ---\n")

(assert-true "1.1 L_c_ast is registered in Nanopass language table"
             (nanopass-language? (nanopass-lookup-language 'L_c_ast)))
(assert-true "1.2 L_c_typed extends L_c_ast"
             (equal? '(L_c_ast L_c_typed) (language-parent-chain 'L_c_typed)))
(assert-equal "1.3 sizeof(int) = 4, sizeof(long) = 8, sizeof(double) = 8"
              '(4 8 8)
              (list (c-type-size 'i32) (c-type-size 'i64) (c-type-size 'f64)))
(assert-equal "1.4 sizeof(ptr) = 8, align(u16) = 2"
              '(8 2)
              (list (c-type-size (make-c-ptr-type 'i8)) (c-type-align 'u16)))
(assert-equal "1.5 unsigned long long parses to u64"
              (cons #f 'u64)
              (c-parse-decl-specs '(unsigned long long) #f))
(assert-equal "1.6 static unsigned char parses to (static . u8)"
              (cons 'static 'u8)
              (c-parse-decl-specs '(static unsigned char) #f))

;;; -----------------------------------------------------------------------
;;; Group 2: Normalized Expression ASTs & Precedence
;;; -----------------------------------------------------------------------
(display "--- Group 2: Normalized L_c_ast Expression Trees ---\n")

(let ((e1 (ast-strip-span-all (parse-c99-expr-string "1 + 2 * 3 - 4" "expr1.c"))))
  (assert-equal "2.1 1 + 2 * 3 - 4 normalizes to left-assoc ((1 + (2 * 3)) - 4)"
                '(c-binop -
                   (c-binop +
                     (c-const "1")
                     (c-binop * (c-const "2") (c-const "3")))
                   (c-const "4"))
                e1))

(let ((e2 (ast-strip-span-all (parse-c99-expr-string "a > 0 ? b += 1 : (c = 2)" "expr2.c"))))
  (assert-true "2.2 ternary and compound assignment normalize cleanly"
               (and (eq? (car e2) 'c-ternary)
                    (eq? (caadr e2) 'c-binop)
                    (eq? (caaddr e2) 'c-assign)
                    (eq? (car (cadddr e2)) 'c-assign))))

(let ((e3 (ast-strip-span-all (parse-c99-expr-string "p->arr[i].fn(x, y)++" "expr3.c"))))
  (assert-true "2.3 postfix chain normalizes to c-unop(post++) -> c-call -> c-member -> c-index"
               (and (eq? (car e3) 'c-unop)
                    (eq? (cadr e3) 'post++)
                    (eq? (caaddr e3) 'c-call))))

(let ((e4 (ast-strip-span-all (parse-c99-expr-string "(long)sizeof(int) + -x" "expr4.c"))))
  (assert-true "2.4 cast, sizeof(type), and unary minus normalize properly"
               (and (eq? (car e4) 'c-binop)
                    (eq? (caaddr e4) 'c-cast)
                    (eq? (car (cadddr e4)) 'c-unop))))

;;; -----------------------------------------------------------------------
;;; Group 3: Normalized Statements, For/Switch/Goto & verify-c99-ast
;;; -----------------------------------------------------------------------
(display "--- Group 3: Statements & verify-c99-ast Compliance ---\n")

(define sample-prog-ast
  (parse-c99-string
   "int sum_to(int n) {
      int acc = 0;
      for (int i = 0; i < n; i++) {
        if (i == 3) continue;
        acc += i;
      }
      switch (acc) {
        case 0: return -1;
        default: break;
      }
    done:
      return acc;
    }"
   "stmt_norm.c"))

(assert-true "3.1 verify-c99-ast passes on full function with for/if/switch/goto labels"
             (verify-c99-ast sample-prog-ast))
(assert-true "3.1b nanopass-ast-valid? 'L_c_ast passes on stripped sample AST"
             (nanopass-ast-valid? 'L_c_ast (ast-strip-span-all sample-prog-ast)))

(let ((ast-complex
       (parse-c99-string
        "int (*(*fp)(int));
         int (*(*signal(int sig, void (*func)(int)))(int));
         typedef int (*lua_Fn)(void *L, int n);"
        "complex_decl.c")))
  (assert-true "3.1c complex function pointer declarators verify cleanly under L_c_ast"
               (and (verify-c99-ast ast-complex)
                    (nanopass-ast-valid? 'L_c_ast (ast-strip-span-all ast-complex)))))

(let* ((unit-raw (ast-strip-span-all sample-prog-ast))
       (fn-node  (cadr unit-raw))
       (body     (list-ref fn-node 5))
       (for-stmt (caddr body)))
  (assert-equal "3.2 normalized function has c-fn-def" 'c-fn-def (car fn-node))
  (assert-equal "3.3 c-for has 5 elements (tag init cond step body)" 5 (length for-stmt))
  (assert-equal "3.4 c-for init is normalized c-decl" 'c-decl (caadr for-stmt)))

;;; -----------------------------------------------------------------------
;;; Group 4: 4-Namespace Separation, Typedef Disambiguation & Shadowing
;;; -----------------------------------------------------------------------
(display "--- Group 4: Typedef Lexer Hack Disambiguation & 4-Namespaces ---\n")

(define ns-prog
  "typedef int T;
   struct T { int T; };
   int test_shadow(int T) {
     int x = T * 2;
     {
       typedef long U;
       U y = (U)x;
       x = (int)y;
     }
     goto T;
   T:
     return x;
   }")

(define ns-ast (parse-c99-string ns-prog "namespaces.c"))
(assert-true "4.1 4-namespace isolation (typedef/struct tag/param/label all named T) parses & verifies"
             (verify-c99-ast ns-ast))

;;; -----------------------------------------------------------------------
;;; Group 5: CPP + Parser End-to-End Integration (Lua 5.x Style Code)
;;; -----------------------------------------------------------------------
(display "--- Group 5: Preprocessor -> Lexer -> Parser Pipeline ---\n")

(define cpp-lua-src
  "#define LUAI_MAXSTACK 1000
   #define cast(t, exp) ((t)(exp))
   #define MSG_PREFIX \"lua: \"
   typedef int lua_Integer;
   typedef struct SValue {
     int tt;
     lua_Integer val;
   } SValue;

   int check_val(SValue *v) {
     const char *msg = MSG_PREFIX \"ok\";
   #if LUAI_MAXSTACK > 500
     return cast(int, v->val) + (msg[0] == 'l');
   #else
     return 0;
   #endif
   }")

(define cpp-ast (parse-c99-preprocessed-string cpp-lua-src "lua_cpp_test.c"))
(assert-true "5.1 parse-c99-preprocessed-string parses expanded macros & adjacent strings into verified L_c_ast"
             (verify-c99-ast cpp-ast))

(let* ((raw (ast-strip-span-all cpp-ast))
       (decls (cdr raw)))
  (assert-equal "5.2 preprocessed program yields 3 external declarations" 3 (length decls)))

;;; -----------------------------------------------------------------------
;;; Group 6: Error Diagnostics (C99-PARSE-001 & C99-PARSE-003)
;;; -----------------------------------------------------------------------
(display "--- Group 6: Diagnostic Reporting C99-PARSE-001 / C99-PARSE-003 ---\n")

(let ((err1 (guard (ex (else ex))
              (parse-c99-string "int f( { return 0; }" "bad_syntax.c"))))
  (assert-true "6.1 syntax error raises C99-PARSE-001 diagnostic exception"
               (and (pair? err1)
                    (eq? (car err1) 'c99-syntax-error)
                    (member "C99-PARSE-001" err1))))

(let ((err2 (guard (ex (else ex))
              (verify-c99-ast '(not-a-translation-unit)))))
  (assert-true "6.2 invalid L_c_ast structure raises C99-PARSE-003"
               (and (pair? err2)
                    (eq? (car err2) 'c99-ast-error)
                    (equal? (cadr err2) "C99-PARSE-003"))))

(test-end "C99 Parser, L_c_ast & Lexer Hack Disambiguation (Issue #915)")
