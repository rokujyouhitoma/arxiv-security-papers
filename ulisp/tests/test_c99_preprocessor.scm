;;; =======================================================================
;;; Test Suite: Pure Scheme C99 Preprocessor (CPP) (Issue #914)
;;; Conforms to DSN-33-11 §3.3/§4.1, DSN-33-32 §3.1 & Issue #914
;;; =======================================================================

(test-begin "Pure Scheme C99 Preprocessor (CPP) (Issue #914)")

;;; -----------------------------------------------------------------------
;;; Group 1: Object/Function Macros, #undef, -D/-U & Built-in Macros
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Macros, #undef, -D & Builtin Macros ---\n")

(let* ((ctx (make-default-cpp-context))
       (_ (cpp-define-string! ctx "CMD_FLAG=77"))
       (src "
#define ADD(a, b) ((a) + (b))
#define OBJ (x)
#define VAL 10
int x1 = VAL + CMD_FLAG;
int x2 = ADD(ADD(1, 2), 3);
#undef VAL
int val_after = VAL;
int ln = __LINE__;
const char *fn = __FILE__;
long stdc = __STDC_VERSION__;
int y = OBJ;
")
       (toks (%cpp-strip-eof (cpp-preprocess-string src "unit1.c" ctx)))
       (text (c-tokens->source-string toks))
       (ast  (parse-c99-string text "unit1.c")))
  (assert-true "1.1 macro-expanded code parses into L_c_ast"
               (and (ast-has-span? ast) (eq? (car (ast-strip-span ast)) 'c-translation-unit)))
  (assert-true "1.2 CMD_FLAG=77 (-D) expanded into output" (string-contains? text "77"))
  (assert-true "1.3 #define OBJ (x) stays object-like" (string-contains? text "y = (x)"))
  (assert-true "1.4 __FILE__ expanded to \"unit1.c\"" (string-contains? text "\"unit1.c\""))
  (assert-true "1.5 __STDC_VERSION__ expanded to 199901" (string-contains? text "199901"))
  (assert-true "1.6 #undef restores VAL identifier" (string-contains? text "val_after = VAL")))

;;; -----------------------------------------------------------------------
;;; Group 2: # Stringification, ## Token Pasting & Variadic __VA_ARGS__
;;; -----------------------------------------------------------------------
(display "--- Group 2: Stringification #, Token Pasting ## & __VA_ARGS__ ---\n")

(let* ((src "
#define STR(s) #s
#define CAT(a, b) a ## b
#define XCAT(a, b) CAT(a, b)
#define BASE foo
#define SUF _bar
#define MAKE_CALL(fn, ...) fn(__VA_ARGS__)
#define OPT_CALL(fn, ...) fn(0, ##__VA_ARGS__)
const char *s1 = STR(hello   world);
int CAT(my_, var) = 1;
int XCAT(BASE, SUF) = 2;
int c1 = MAKE_CALL(sum, 10, 20, 30);
int c2 = OPT_CALL(noop);
int c3 = OPT_CALL(with_arg, 99);
")
       (text (cpp-preprocess-to-string src "paste.c"))
       (ast  (parse-c99-string text "paste.c")))
  (assert-true "2.1 # stringify collapses whitespace to single space"
               (string-contains? text "\"hello world\""))
  (assert-true "2.2 CAT(my_, var) pastes to my_var" (string-contains? text "my_var"))
  (assert-true "2.3 XCAT(BASE, SUF) pre-expands args to foo_bar" (string-contains? text "foo_bar"))
  (assert-true "2.4 MAKE_CALL variadic __VA_ARGS__ expands" (string-contains? text "sum(10, 20, 30)"))
  (assert-true "2.5 empty , ## __VA_ARGS__ elides comma -> noop(0)" (string-contains? text "noop(0)"))
  (assert-true "2.6 non-empty , ## __VA_ARGS__ keeps comma -> with_arg(0, 99)"
               (string-contains? text "with_arg(0, 99)"))
  (assert-true "2.7 entire Group 2 parses cleanly into L_c_ast"
               (eq? (car (ast-strip-span ast)) 'c-translation-unit)))

;;; -----------------------------------------------------------------------
;;; Group 3: Dave Prosser Blue-Painted (hide-set) Recursion Suppression
;;; -----------------------------------------------------------------------
(display "--- Group 3: Blue-Painted (hide-set) Recursion Suppression ---\n")

(let* ((src "
#define SELF (1 + SELF)
#define A (B + 2)
#define B (A + 3)
#define M(x) M(x)
int r1 = SELF;
int r2 = A;
int r3 = M(42);
")
       (text (cpp-preprocess-to-string src "blue.c")))
  (assert-true "3.1 self-referential macro terminates cleanly"
               (string-contains? text "r1 = (1 + SELF)"))
  (assert-true "3.2 mutually recursive macros terminate via hide-set"
               (string-contains? text "r2 = ((A + 3) + 2)"))
  (assert-true "3.3 self-referential function macro stops on rescan"
               (string-contains? text "r3 = M(42)")))

;;; -----------------------------------------------------------------------
;;; Group 4: #if / #elif / defined / CTFE Bitwise & Short-Circuit Evaluation
;;; -----------------------------------------------------------------------
(display "--- Group 4: #if / #elif / defined / CTFE Expression Evaluation ---\n")

(let* ((src "
#define VER 504
#define MASK 0x0F
#if defined(VER) && (VER >= 500) && ((1 << 3) == 8) && (~0 == -1)
int ok_branch = 1;
#else
int ok_branch = 0;
#endif
#if 0 && (1 / 0)
int short_and = 1;
#elif 1 || (1 / 0)
int short_or = (0 ? (1 / 0) : 42);
#endif
#if UNDEFINED_SYM == 0 && ('A' == 65) && ((3 ? 10 : (1 / 0)) == 10)
int sym_zero = 1;
#endif
")
       (text (cpp-preprocess-to-string src "cond.c"))
       (ast  (parse-c99-string text "cond.c")))
  (assert-true "4.1 defined() + shift + ~0 evaluated true" (string-contains? text "ok_branch = 1"))
  (assert-false "4.2 false #else skipped" (string-contains? text "ok_branch = 0"))
  (assert-true "4.3 short-circuit && and || avoided div-by-zero"
               (string-contains? text "short_or = (0 ? (1 / 0) : 42)"))
  (assert-true "4.4 undefined ident -> 0, char literal 'A' -> 65, lazy ternary OK"
               (string-contains? text "sym_zero = 1"))
  (assert-true "4.5 #if output parses cleanly into L_c_ast"
               (eq? (car (ast-strip-span ast)) 'c-translation-unit)))

;;; -----------------------------------------------------------------------
;;; Group 5: #include Resolution, #pragma once & Include-Guard Bypass
;;; -----------------------------------------------------------------------
(display "--- Group 5: #include, #pragma once & Include-Guard Bypass ---\n")

(cpp-reset-metrics!)
(let* ((ctx (make-default-cpp-context '("/virt/inc")))
       (_ (cpp-add-include-path! ctx "/virt/sys" #t))
       (_ (cpp-register-virtual-file!
           ctx "/virt/inc/once_hdr.h"
           "#pragma once\nint once_decl = 11;\n"))
       (_ (cpp-register-virtual-file!
           ctx "/virt/sys/guarded.h"
           "#ifndef GUARDED_H\n#define GUARDED_H\ntypedef int my_i32;\n#endif\n"))
       (main-src "
#include \"once_hdr.h\"
#include \"once_hdr.h\"
#include <guarded.h>
#include <guarded.h>
my_i32 gv = 99;
")
       (text (cpp-preprocess-to-string main-src "/virt/src/main.c" ctx))
       (ast  (parse-c99-string text "/virt/src/main.c")))
  (assert-true "5.1 pragma once header included once" (string-contains? text "once_decl = 11"))
  (assert-true "5.2 system guarded header included" (string-contains? text "typedef int my_i32"))
  (assert-equal "5.3 both repeated #includes skipped via pragma once / guard cache"
                2 (cpp-include-skip-count))
  (assert-true "5.4 combined included AST parses cleanly"
               (eq? (car (ast-strip-span ast)) 'c-translation-unit)))

;;; -----------------------------------------------------------------------
;;; Group 6: Lua 5.x Macro E2E -> C99 PEG L_c_ast
;;; -----------------------------------------------------------------------
(display "--- Group 6: Lua 5.x Nested Macros E2E -> L_c_ast ---\n")

(let* ((lua-macro-src "
#define LUA_NUMBER double
#define LUA_INTEGER long long
#define cast(t, exp) ((t)(exp))
#define LUA_OK 0
#define l_likely(x) (x)
#define check_exp(c, e) (e)
#define setivalue(obj, x) ((obj)->i = cast(LUA_INTEGER, x))

typedef LUA_NUMBER lua_Number;
typedef LUA_INTEGER lua_Integer;
typedef struct TVal { lua_Integer i; lua_Number n; } TVal;

int set_lua_val(TVal *v, int x) {
  if (l_likely(x > 0)) {
    setivalue(v, x + 1);
  }
  return check_exp(1, LUA_OK);
}
")
       (text (cpp-preprocess-to-string lua-macro-src "lua_macros.c"))
       (ast  (parse-c99-string text "lua_macros.c")))
  (assert-true "6.1 Lua cast/setivalue/check_exp macros expand and parse into L_c_ast"
               (and (ast-has-span? ast) (eq? (car (ast-strip-span ast)) 'c-translation-unit)))
  (assert-true "6.2 cast macro expanded properly"
               (string-contains? text "((long long)(x + 1))")))

;;; -----------------------------------------------------------------------
;;; Group 7: Security & Diagnostic Error Reporting (C99-CPP-001..005)
;;; -----------------------------------------------------------------------
(display "--- Group 7: Security Guards & Diagnostic Codes (C99-CPP-001..005) ---\n")

(let* ((ctx-cyc (make-default-cpp-context))
       (_ (cpp-register-virtual-file! ctx-cyc "/virt/a.h" "#include \"b.h\"\n"))
       (_ (cpp-register-virtual-file! ctx-cyc "/virt/b.h" "#include \"a.h\"\n"))
       (err1 (guard (ex (else ex))
               (cpp-preprocess-string "#include \"a.h\"\n" "/virt/top.c" ctx-cyc)))
       (err2 (guard (ex (else ex))
               (cpp-preprocess-string "#error \"unsupported target\"\n" "err2.c")))
       (err3 (guard (ex (else ex))
               (cpp-preprocess-string "#if 1\nint x;\n" "err3.c")))
       (err4 (guard (ex (else ex))
               (cpp-preprocess-string "#if 1 / 0\n#endif\n" "err4.c")))
       (err5 (guard (ex (else ex))
               (cpp-preprocess-string "#define BAD(a, b) a ## b\nBAD(+, /)\n" "err5.c"))))
  (assert-equal "7.1 cyclic #include caught by max-depth guard (C99-CPP-001)"
                "C99-CPP-001" (cadr err1))
  (assert-equal "7.2 #error triggers C99-CPP-002" "C99-CPP-002" (cadr err2))
  (assert-equal "7.3 unterminated #if triggers C99-CPP-003" "C99-CPP-003" (cadr err3))
  (assert-equal "7.4 active div-by-zero in #if triggers C99-CPP-004" "C99-CPP-004" (cadr err4))
  (assert-equal "7.5 invalid ## paste triggers C99-CPP-005" "C99-CPP-005" (cadr err5)))

(test-end "Pure Scheme C99 Preprocessor (CPP) (Issue #914)")
