;;; =======================================================================
;;; test_c99_setjmp_longjmp.scm
;;; Non-local Jumps (<setjmp.h>: setjmp / longjmp / _setjmp / sigsetjmp)
;;; & returns_twice Live-Variable Stack Spill Protection
;;; Conforms to ISO C99 §7.13, DSN-33-32 §4.2, DSN-33-13 §2.4 & Issue #922
;;; Zero local `set!` (ULisp AOT safe).
;;; =======================================================================

(define *tests-passed* (cons 0 '()))
(define *tests-failed* (cons 0 '()))

(define (assert-true desc val)
  (if val
      (begin
        (set-car! *tests-passed* (+ (car *tests-passed*) 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set-car! *tests-failed* (+ (car *tests-failed*) 1))
        (display "  [FAIL] ") (display desc) (newline)
        (error "Assertion failed: expected #t" desc))))

(define (assert-equal desc expected actual)
  (if (equal? expected actual)
      (begin
        (set-car! *tests-passed* (+ (car *tests-passed*) 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set-car! *tests-failed* (+ (car *tests-failed*) 1))
        (display "  [FAIL] ") (display desc)
        (display " (expected ") (write expected)
        (display ", got ") (write actual) (display ")") (newline)
        (error "Assertion failed: values not equal" desc))))

(define (c99-run-code src)
  (let ((lir (c99-compile-string-to-lir src "<test-setjmp>")))
    (eval-lir-program lir)))

(define (c99-expect-error err-code src)
  (guard (ex
          ((and (pair? ex) (pair? (cdr ex)) (equal? (cadr ex) err-code))
           #t)
          (else
           (display "  [UNEXPECTED ERROR] Expected ") (display err-code)
           (display ", got: ") (write ex) (newline)
           #f))
    (let* ((ast (parse-c99-preprocessed-string src "<test-setjmp-err>"))
           (typed (c99-analyze-program ast)))
      (c99-lower-to-lir typed)
      #f)))

(define (sj-sym-contains? sym needle)
  (let* ((s (symbol->string sym))
         (slen (string-length s))
         (nlen (string-length needle)))
    (let loop ((i 0))
      (cond
        ((> (+ i nlen) slen) #f)
        ((string=? (substring s i (+ i nlen)) needle) #t)
        (else (loop (+ i 1)))))))

(define (sj-lir-walk-has? obj pred)
  (cond
    ((pred obj) #t)
    ((pair? obj)
     (or (sj-lir-walk-has? (car obj) pred)
         (sj-lir-walk-has? (cdr obj) pred)))
    (else #f)))

(display "=== [Test Suite: C99 <setjmp.h> %inline-asm & Spill Protection (Issue #922)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Built-in <setjmp.h> Resolution, Layout & -isystem Override
;;; -----------------------------------------------------------------------
(display "--- Group 1: Built-in <setjmp.h>, sizeof/Alignof(jmp_buf) & Override ---\n")

(assert-equal "1.1 sizeof(jmp_buf) == 64, sizeof(sigjmp_buf) == 64, _Alignof == 8 + idempotent include"
  6408
  (c99-run-code "
#include <setjmp.h>
#include <setjmp.h>
int main(void) {
    jmp_buf env;
    sigjmp_buf senv;
    return (int)(sizeof(jmp_buf) * 100 + _Alignof(jmp_buf) + (sizeof(env) - 64) + (sizeof(senv) - 64));
}"))

(let* ((ctx (make-default-cpp-context))
       (toks (cpp-preprocess-string "#include <setjmp.h>\njmp_buf jb;\n" "<builtin-sj>" ctx))
       (txt (c-tokens->source-string toks)))
  (assert-true "1.2 Default CPP resolves #include <setjmp.h> to jmp_buf typedef"
               (and (string? txt) (> (string-length txt) 20))))

(let ((ctx (make-default-cpp-context)))
  (cpp-register-virtual-file! ctx "/tmp/custom_sj_inc/setjmp.h" "#define CUSTOM_SJ_OVERRIDE 888\n")
  (cpp-add-include-path! ctx "/tmp/custom_sj_inc" #t)
  (let* ((toks (cpp-preprocess-string "#include <setjmp.h>\nint v = CUSTOM_SJ_OVERRIDE;\n" "<override>" ctx))
         (ast (parse-c99-tokens toks))
         (typed (c99-analyze-program ast))
         (lir (c99-lower-to-lir typed)))
    (assert-true "1.3 User -isystem path overrides built-in <setjmp.h>"
                 (L_lir_core? lir))))

;;; -----------------------------------------------------------------------
;;; Group 2: Basic ISO C99 setjmp / longjmp Semantics on Reference VM
;;; -----------------------------------------------------------------------
(display "--- Group 2: Basic ISO C99 setjmp / longjmp Semantics ---\n")

(assert-equal "2.1 setjmp returns 0 on initial entry without longjmp"
  100
  (c99-run-code "
#include <setjmp.h>
int main(void) {
    jmp_buf env;
    int r = setjmp(env);
    if (r == 0) return 100;
    return 999;
}"))

(assert-equal "2.2 longjmp(env, 42) returns 42 to setjmp call site"
  42
  (c99-run-code "
#include <setjmp.h>
void trigger(jmp_buf env, int code) {
    longjmp(env, code);
}
int main(void) {
    jmp_buf env;
    int r = setjmp(env);
    if (r == 0) {
        trigger(env, 42);
        return -1;
    }
    return r;
}"))

(assert-equal "2.3 ISO C99 §7.13.2.1: longjmp(env, 0) normalizes return value to 1"
  1
  (c99-run-code "
#include <setjmp.h>
void trigger0(jmp_buf env) {
    longjmp(env, 0);
}
int main(void) {
    jmp_buf env;
    int r = setjmp(env);
    if (r == 0) {
        trigger0(env);
        return 999;
    }
    return r;
}"))

(assert-equal "2.4 longjmp(env, -7) preserves negative 32-bit signed return value"
  -7
  (c99-run-code "
#include <setjmp.h>
int main(void) {
    jmp_buf env;
    int r = setjmp(env);
    if (r == 0) {
        longjmp(env, -7);
    }
    return r;
}"))

(assert-equal "2.5 _setjmp/_longjmp and sigsetjmp/siglongjmp variants execute cleanly"
  133
  (c99-run-code "
#include <setjmp.h>
int test_underscore(void) {
    jmp_buf b;
    int v = _setjmp(b);
    if (v == 0) _longjmp(b, 100);
    return v;
}
int test_sig(void) {
    sigjmp_buf sb;
    int v = sigsetjmp(sb, 1);
    if (v == 0) siglongjmp(sb, 33);
    return v;
}
int main(void) {
    return test_underscore() + test_sig();
}"))

;;; -----------------------------------------------------------------------
;;; Group 3: Deep Recursion, Lua luaD_rawrunprotected Nesting & Loops
;;; -----------------------------------------------------------------------
(display "--- Group 3: Deep Recursion, Lua Nested Try/Catch & Loop Re-entry ---\n")

(assert-equal "3.1 Deep recursion (depth 15) unwinds directly to caller"
  1575
  (c99-run-code "
#include <setjmp.h>
int recurse_and_throw(jmp_buf env, int depth, int target) {
    int local_pad = depth * 100;
    if (depth == target) {
        longjmp(env, local_pad + 75);
    }
    return recurse_and_throw(env, depth + 1, target) + 9999;
}
int main(void) {
    jmp_buf env;
    int r = setjmp(env);
    if (r == 0) {
        return recurse_and_throw(env, 0, 15);
    }
    return r;
}"))

(assert-equal "3.2 Lua luaD_rawrunprotected / struct lua_longjmp 3-level nested recovery & rethrow"
  1234
  (c99-run-code "
#include <setjmp.h>
struct lua_longjmp {
    struct lua_longjmp *previous;
    jmp_buf b;
    volatile int status;
};
struct lua_State {
    struct lua_longjmp *errorJmp;
    int trace;
};
void luaD_throw(struct lua_State *L, int errcode) {
    if (L->errorJmp) {
        L->errorJmp->status = errcode;
        longjmp(L->errorJmp->b, 1);
    }
}
int luaD_rawrunprotected(struct lua_State *L, void (*f)(struct lua_State *, void *), void *ud) {
    struct lua_longjmp lj;
    lj.status = 0;
    lj.previous = L->errorJmp;
    L->errorJmp = &lj;
    if (setjmp(lj.b) == 0) {
        f(L, ud);
    }
    L->errorJmp = lj.previous;
    return lj.status;
}
void level3(struct lua_State *L, void *ud) {
    int *p = (int *)ud;
    L->trace += 4;
    if (*p > 0) luaD_throw(L, 200);
}
void level2(struct lua_State *L, void *ud) {
    L->trace += 30;
    int st = luaD_rawrunprotected(L, level3, ud);
    L->trace += st * 5;
    luaD_throw(L, 1);
}
void level1(struct lua_State *L, void *ud) {
    L->trace += 200;
    int st = luaD_rawrunprotected(L, level2, ud);
    if (st == 1) {
        L->trace += 0;
    }
}
int main(void) {
    struct lua_State L;
    L.errorJmp = 0;
    L.trace = 0;
    int flag = 1;
    int st = luaD_rawrunprotected(&L, level1, &flag);
    /* 200 + 30 + 4 + 1000 + st(0) = 1234 */
    return L.trace + st;
}"))

(assert-equal "3.3 2000-iteration loop re-entering setjmp + array/struct/indirect longjmp"
  2255
  (c99-run-code "
#include <setjmp.h>
struct Box { jmp_buf jb; int tag; };
int helper_fp(jmp_buf jb, void (*lj)(jmp_buf, int), int v) {
    lj(jb, v);
    return -1000;
}
int main(void) {
    int sum = 0;
    jmp_buf arr[2];
    for (int i = 0; i < 2000; i++) {
        int r = setjmp(arr[i & 1]);
        if (r == 0) {
            if ((i % 200) == 199) {
                longjmp(arr[i & 1], 1);
            }
            sum += 1;
        } else {
            sum += 10;
        }
    }
    /* 1990 non-throwing * 1 + 10 throws * 10 = 2090 */
    struct Box box;
    box.tag = 5;
    void (*lj_ptr)(jmp_buf, int) = longjmp;
    int r2 = setjmp(box.jb);
    if (r2 == 0) {
        helper_fp(box.jb, lj_ptr, 160);
    }
    return sum + r2 + box.tag;
}"))

;;; -----------------------------------------------------------------------
;;; Group 4: returns_twice Spill Protection (AST, Escape, Braun SSA, Peephole)
;;; -----------------------------------------------------------------------
(display "--- Group 4: returns_twice Spill Protection (AST, Braun SSA, Peephole) ---\n")

(let* ((src "
#include <setjmp.h>
void throw_err(jmp_buf env) {
    longjmp(env, 7);
}
int with_sj(int p) {
    jmp_buf env;
    int local_acc = p + 5;
    int loop_sum = 0;
    if (setjmp(env) == 0) {
        local_acc = local_acc + 30;
        for (int k = 1; k <= 4; k++) loop_sum += k;
        throw_err(env);
    }
    return local_acc + loop_sum;
}
int without_sj(int a) {
    int x = a + 1;
    return x * 2;
}
int shadowed_sj(int a) {
    int setjmp = a + 3;
    return setjmp;
}
int main(void) {
    return with_sj(10) + without_sj(1) + shadowed_sj(2);
}")
       (ast (parse-c99-preprocessed-string src "<spill-test>"))
       (typed (c99-analyze-program ast))
       (funcs (list-ref typed 2))
       (fn-with-sj (list-ref funcs 1))
       (fn-without-sj (list-ref funcs 2))
       (fn-shadowed (list-ref funcs 3))
       (escaped (c99-collect-escaped-bindings fn-with-sj))
       (cands-sj (c99-function-candidate-mem2reg-offsets fn-with-sj '((p_0 local -24 i32) (local_acc_1 local -32 i32))))
       (cands-no-sj (c99-function-candidate-mem2reg-offsets fn-without-sj '((x_1 local -24 i32))))
       (lir-prog (c99-lower-to-lir typed))
       (opt-lir (lir-peephole-optimize lir-prog))
       (fns-clause (assq '%lir-functions (cdr lir-prog)))
       (sj-lir (let fl ((fs (cdr fns-clause)))
                 (if (eq? (list-ref (car fs) 1) 'with_sj) (car fs) (fl (cdr fs)))))
       ;; Intentionally force non-empty candidate-offsets to test Pass 132 defense-in-depth
       (ssa-cfg (c99-lir-fn->braun-cfg sj-lir '(-16 -24 -32 -40 -48 -56 -64 -72 -80 -88 -96)))
       (ssa-fn (c99-braun-ssa-transform-fn sj-lir '(-16 -24 -32 -40 -48 -56 -64 -72 -80 -88 -96)))
       (ssa-prog (map (lambda (item)
                        (if (and (pair? item) (eq? (car item) '%lir-functions))
                            (cons '%lir-functions
                                  (map (lambda (f) (if (eq? (list-ref f 1) 'with_sj) ssa-fn f))
                                       (cdr item)))
                            item))
                      lir-prog)))
  (assert-true "4.1 c99-fn-has-setjmp? detects setjmp in with_sj, #f in normal & shadowed_sj"
               (and (c99-fn-has-setjmp? fn-with-sj)
                    (not (c99-fn-has-setjmp? fn-without-sj))
                    (not (c99-fn-has-setjmp? fn-shadowed))))
  (assert-true "4.2 c99-collect-escaped-bindings forces all locals & params (local_acc, loop_sum, p) in setjmp fn"
               (and (let check ((xs escaped))
                      (and (pair? xs) (or (sj-sym-contains? (car xs) "local_acc") (check (cdr xs)))))
                    (let check ((xs escaped))
                      (and (pair? xs) (or (sj-sym-contains? (car xs) "loop_sum") (check (cdr xs)))))
                    (let check ((xs escaped))
                      (and (pair? xs) (or (sj-sym-contains? (car xs) "p") (check (cdr xs)))))))
  (assert-equal "4.3 c99-function-candidate-mem2reg-offsets returns '() for setjmp fn (non-empty for normal fn)"
                (list '() '(-24))
                (list cands-sj cands-no-sj))
  (assert-true "4.4 Pass 132 braun-cfg-has-returns-twice? prevents mem2reg even with forced offsets & passes L_lir_core"
               (and (braun-cfg-has-returns-twice? ssa-cfg)
                    (braun-verify-cfg ssa-cfg)
                    (L_lir_core? ssa-prog)
                    (validate-core-lir ssa-prog)
                    (sj-lir-walk-has? ssa-fn (lambda (x)
                                               (and (pair? x)
                                                    (or (and (eq? (car x) '%store) (eq? (cadr x) '%rsp))
                                                        (and (eq? (car x) '%store-typed) (eq? (caddr x) '%rsp))))))
                    (sj-lir-walk-has? ssa-fn (lambda (x)
                                               (and (pair? x)
                                                    (or (and (eq? (car x) '%load) (eq? (caddr x) '%rsp))
                                                        (and (eq? (car x) '%load-typed) (eq? (cadddr x) '%rsp))))))))
  (assert-true "4.5 LIR verifier validates builtin __ulisp_setjmp / __ulisp_longjmp %inline-asm & peephole preserves barrier"
               (and (L_lir_core? lir-prog)
                    (validate-core-lir lir-prog)
                    (L_lir_canonical? opt-lir)
                    (validate-core-lir opt-lir)))
  (assert-equal "4.6 Non-volatile locals survive longjmp across Braun SSA, Pass 133 peephole & VM execution (55+4+5=64)"
                64
                (eval-lir-program opt-lir))
  (assert-equal "4.7 Forced Braun SSA program preserves exact non-volatile local values (64)"
                64
                (eval-lir-program ssa-prog)))

;;; -----------------------------------------------------------------------
;;; Group 5: Diagnostics (C99-JMP-001) & Reference VM Invalid jmp_buf Trap
;;; -----------------------------------------------------------------------
(display "--- Group 5: Security Diagnostics (C99-JMP-001) & VM Invalid jmp_buf Trap ---\n")

(assert-true "5.1 C99-JMP-001 on undersized array (< 64 bytes)"
  (c99-expect-error "C99-JMP-001" "
#include <setjmp.h>
int main(void) {
    long small[4];
    return setjmp(small);
}"))

(assert-true "5.2 C99-JMP-001 on int[16] or void* passed to setjmp/longjmp"
  (and
    (c99-expect-error "C99-JMP-001" "
#include <setjmp.h>
int main(void) {
    int wrong_elem[16];
    return setjmp(wrong_elem);
}")
    (c99-expect-error "C99-JMP-001" "
#include <setjmp.h>
int main(void) {
    jmp_buf env;
    void *vp = env;
    longjmp(vp, 1);
    return 0;
}")))

(assert-true "5.3 C99-JMP-001 on wrong argument counts & non-integer val"
  (and
    (c99-expect-error "C99-JMP-001" "
#include <setjmp.h>
int main(void) { return setjmp(); }")
    (c99-expect-error "C99-JMP-001" "
#include <setjmp.h>
int main(void) { jmp_buf env; return sigsetjmp(env); }")
    (c99-expect-error "C99-JMP-001" "
#include <setjmp.h>
int main(void) { jmp_buf env; longjmp(env); return 0; }")
    (c99-expect-error "C99-JMP-001" "
#include <setjmp.h>
int main(void) { jmp_buf env; longjmp(env, \"bad\"); return 0; }")))

(assert-equal "5.4 Shadowed local variable named setjmp works without C99-JMP-001"
  27
  (c99-run-code "
#include <setjmp.h>
int add_one(int x) { return x + 1; }
int main(void) {
    int (*setjmp)(int) = add_one;
    return setjmp(26);
}"))

(let* ((uninit-lir
        (c99-compile-string-to-lir "
#include <setjmp.h>
int main(void) {
    jmp_buf env = {0};
    longjmp(env, 1);
    return 0;
}" "<uninit-jmp>"))
       (vm (make-lir-vm)))
  (lir-vm-load! vm uninit-lir)
  (let ((st (lir-vm-run! vm)))
    (assert-true "5.5 Reference VM traps with 'invalid-jmp-buf on uninitialized jmp_buf"
                 (and (eq? st 'trapped)
                      (vm-trap? (vm-last-trap vm))
                      (eq? (vm-trap-type (vm-last-trap vm)) 'invalid-jmp-buf)))))

(display "\n=== [Summary: ")
(display (car *tests-passed*))
(display " passed, ")
(display (car *tests-failed*))
(display " failed] ===\n")
(if (> (car *tests-failed*) 0)
    (exit 1))
