;;; =======================================================================
;;; test_c99_funcptr_and_switch_cfg.scm
;;; C99 Function Pointers, %call-indirect & Switch/Goto Braun SSA CFG (Issue #920)
;;;
;;; Validates:
;;; 1. Recursive function pointer typing, typedef lua_CFunction, arrays,
;;;    struct callbacks, function returning function pointer, decay, *fp/**fp/&fn,
;;;    equality & ternary NULL unification.
;;; 2. %call-indirect on Reference VM (#834) with unique code-addr-table,
;;;    SysV >16B sret struct return, float + stack args, static table relocs,
;;;    external libc fn pointer (putchar), and 'invalid-call-target trap on NULL.
;;; 3. Giant dense switch (85+ cases), bounds-safe default fallback, sparse switch,
;;;    fallthrough, nested switch/loop break+continue, and Duff's device.
;;; 4. Forward/backward/mutual goto loops and &status escaped variable coherence.
;;; 5. Pass 132 Braun SSA 2-pass delayed seal-block + braun-verify-cfg +
;;;    L_lir_core? & validate-core-lir validation on complex switch/goto CFG.
;;; 6. Diagnostics C99-CFG-001..004 and C99-PTR-004.
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
  (let ((lir (c99-compile-string-to-lir src "<test-cfg>")))
    (eval-lir-program lir)))

(define (c99-expect-error err-code src)
  (guard (ex
          ((and (pair? ex) (pair? (cdr ex)) (equal? (cadr ex) err-code))
           #t)
          (else
           (display "  [UNEXPECTED ERROR] Expected ") (display err-code)
           (display ", got: ") (write ex) (newline)
           #f))
    (let* ((ast (parse-c99-preprocessed-string src "<test-error>"))
           (typed (c99-analyze-program ast)))
      (c99-lower-to-lir typed)
      #f)))

(define (string-contains-sub? str sub)
  (let ((n (string-length str))
        (m (string-length sub)))
    (let loop ((i 0))
      (cond
        ((> (+ i m) n) #f)
        ((string=? (substring str i (+ i m)) sub) #t)
        (else (loop (+ i 1)))))))

(define (make-n-branch-switch-cases n)
  (let loop ((i 0) (acc ""))
    (if (>= i n)
        acc
        (let* ((i-s (number->string i))
               (val-s (number->string (+ (* i 3) 7)))
               (arm (string-append "        case " i-s ": acc += " val-s "; break;\n")))
          (loop (+ i 1) (string-append acc arm))))))

(display "=== [Test Suite: C99 Function Pointers & Switch/Goto Braun SSA (Issue #920)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Function Pointer Typing, Decay, Deref & Equality
;;; -----------------------------------------------------------------------
(display "--- Group 1: Function Pointer Typing, Decay, Deref & Equality ---\n")

(assert-equal "1.1 Basic function pointer decay, &fn, *fp, **fp calls"
  112
  (c99-run-code "
int add2(int a, int b) { return a + b; }
int mul2(int a, int b) { return a * b; }
int main(void) {
    int (*fp)(int, int) = add2;
    int (*gp)(int, int) = &mul2;
    int r1 = fp(10, 5);
    int r2 = (*fp)(10, 5);
    int r3 = (**gp)(7, 11);
    int r4 = (*&add2)(2, 3);
    return r1 + r2 + r3 + r4;
}"))

(assert-equal "1.2 typedef lua_CFunction & struct callback dispatch"
  270
  (c99-run-code "
struct lua_State {
    int top;
    int stack[8];
};
typedef int (*lua_CFunction)(struct lua_State *L);
struct LuaReg {
    int op_id;
    lua_CFunction func;
};
int cfn_push_sum(struct lua_State *L) {
    int s = 0;
    for (int i = 0; i < L->top; i++) s += L->stack[i];
    return s;
}
int cfn_weighted(struct lua_State *L) {
    return L->stack[0] * 10 + L->stack[1] * 2;
}
int dispatch_reg(struct LuaReg *reg, struct lua_State *L) {
    return reg->func(L);
}
int main(void) {
    struct lua_State L = { 3, {10, 20, 35, 0, 0, 0, 0, 0} };
    struct LuaReg regs[2] = { {1, cfn_push_sum}, {2, cfn_weighted} };
    int a = regs[0].func(&L);
    int b = dispatch_reg(&regs[1], &L);
    int c = (*&cfn_push_sum)(&L);
    return a + b + c;
}"))

(assert-equal "1.3 Function returning function pointer (1-param and void-param find-fn check)"
  59
  (c99-run-code "
int f_add(int a, int b) { return a + b; }
int f_sub(int a, int b) { return a - b; }
int (*select_op(int op))(int, int) {
    return op == 0 ? f_add : f_sub;
}
int (*select_zero(void))(int, int) {
    return &f_add;
}
int apply(int (*fn)(int, int), int x, int y) {
    return fn(x, y);
}
int main(void) {
    int a = select_op(0)(20, 5);
    int b = select_op(1)(20, 5);
    int c = select_zero()(10, 9);
    int d = apply(f_add, 0, 0);
    return a + b + c + d;
}"))

(assert-equal "1.4 Unique function pointer equality, inequality, NULL & ternary 0 unification"
  15
  (c99-run-code "
int f1(int x) { return x + 1; }
int f2(int x) { return x + 2; }
int main(void) {
    int (*p)(int) = f1;
    int (*q)(int) = f2;
    int (*n)(int) = 0;
    int (*t1)(int) = (1 ? f1 : 0);
    int (*t2)(int) = (1 ? 0 : f2);
    int score = 0;
    if (p == f1) score += 1;
    if (p != q) score += 2;
    if (n == 0) score += 4;
    if (t1 == f1 && t2 == 0) score += 8;
    return score;
}"))

;;; -----------------------------------------------------------------------
;;; Group 2: %call-indirect VM ABI Parity (sret, floats, 8 args, static/ext, trap)
;;; -----------------------------------------------------------------------
(display "--- Group 2: %call-indirect VM ABI Parity & Trap Protection ---\n")

(assert-equal "2.1 Indirect call with >16B SysV sret struct, floats & 8-arg stack spillover"
  1760
  (c99-run-code "
struct BigRes {
    long a;
    long b;
    long c;
};
struct BigRes make_big(int a, int b, int c, int d, int e, int f, int g, int h, double w) {
    struct BigRes r;
    r.a = a + b + c + d;
    r.b = e + f + g + h;
    r.c = (long)(w * 10.0);
    return r;
}
int main(void) {
    struct BigRes (*fn)(int, int, int, int, int, int, int, int, double) = make_big;
    struct BigRes r = fn(10, 20, 30, 40, 100, 200, 300, 400, 66.0);
    return (int)(r.a + r.b + r.c);
}"))

(assert-equal "2.2 Static global function pointer table & external putchar pointer"
  101
  (c99-run-code "
int putchar(int ch);
int inc1(int x) { return x + 1; }
int inc2(int x) { return x + 2; }
int inc3(int x) { return x + 3; }
static int (*g_ops[3])(int) = { inc1, inc2, inc3 };
int main(void) {
    int (*pc)(int) = putchar;
    int ch = pc(65);
    int v = g_ops[0](10) + g_ops[1](10) + g_ops[2](10);
    return ch + v;
}"))

(assert-true "2.3 Reference VM traps with 'invalid-call-target on NULL indirect call"
  (let* ((src "
int main(void) {
    int (*fp)(int) = 0;
    return fp(42);
}")
         (lir (c99-compile-string-to-lir src "<null-call-trap>"))
         (vm (make-lir-vm)))
    (lir-vm-load! vm lir)
    (let ((status (lir-vm-run! vm)))
      (and (eq? status 'trapped)
           (vm-last-trap vm)
           (eq? (vm-trap-type (vm-last-trap vm)) 'invalid-call-target)))))

;;; -----------------------------------------------------------------------
;;; Group 3: Giant Switch (85+ cases), Sparse Switch, Nesting & Duff's Device
;;; -----------------------------------------------------------------------
(display "--- Group 3: Giant Switch, Sparse Switch, Fallthrough, Nesting & Duff's Device ---\n")

(let* ((src-85 (string-append "
int vm_exec(int code[], int len) {
    int acc = 0;
    for (int i = 0; i < len; i++) {
        switch (code[i]) {
" (make-n-branch-switch-cases 85) "        default: acc += 1000; break;
        }
    }
    return acc;
}
int main(void) {
    int prog[8] = {0, 1, 42, 83, 84, -5, 85, 999};
    return vm_exec(prog, 8);
}")))
  ;; expected: (0*3+7) + (1*3+7) + (42*3+7) + (83*3+7) + (84*3+7) + 3*1000
  ;;         = 7 + 10 + 133 + 256 + 259 + 3000 = 3665
  (assert-equal "3.1 85-branch dense switch with negative and upper out-of-bounds default"
    3665
    (c99-run-code src-85)))

(assert-equal "3.2 Sparse switch with large negative and >4096 values (BST tier)"
  562
  (c99-run-code "
int sparse_eval(long x) {
    switch (x) {
        case -1000000: return 10;
        case -500: return 20;
        case 0: return 30;
        case 7: return 40;
        case 5000: return 50;
        case 100000: return 60;
        case 1048576: return 70;
        case 2097152: return 80;
        case 4194304: return 90;
        case 8388608: return 100;
        default: return 162;
    }
}
int main(void) {
    return sparse_eval(-1000000) + sparse_eval(7) + sparse_eval(1048576) +
           sparse_eval(8388608) + sparse_eval(123456) + sparse_eval(2097152) +
           sparse_eval(8388608);
}"))

(assert-equal "3.3 Fallthrough, nested switch & break/continue loop boundaries"
  176
  (c99-run-code "
int main(void) {
    int sum = 0;
    for (int i = 0; i < 6; i++) {
        switch (i) {
            case 0:
            case 1:
                sum += 10;
                break;
            case 2:
                sum += 5;
                /* fallthrough */
            case 3:
                switch (i) {
                    case 2: sum += 1; break;
                    case 3: sum += 20; break;
                    default: break;
                }
                if (i == 2) continue;
                sum += 100;
                break;
            default:
                sum += 15;
                break;
        }
    }
    return sum;
}"))

(assert-equal "3.4 Duff's device (switch jumping into do-while body)"
  181
  (c99-run-code "
void duff_copy(int *to, const int *from, int count) {
    int n = (count + 3) / 4;
    switch (count % 4) {
        case 0: do { *to++ = *from++;
        case 3:      *to++ = *from++;
        case 2:      *to++ = *from++;
        case 1:      *to++ = *from++;
                } while (--n > 0);
    }
}
int main(void) {
    int src[6] = {11, 22, 33, 44, 55, 16};
    int dst[6] = {0, 0, 0, 0, 0, 0};
    duff_copy(dst, src, 6);
    int s = 0;
    for (int i = 0; i < 6; i++) s += dst[i];
    return s;
}"))

;;; -----------------------------------------------------------------------
;;; Group 4: Arbitrary Goto Loops & Escaped Variable Coherence
;;; -----------------------------------------------------------------------
(display "--- Group 4: Forward/Backward/Mutual Goto & Escaped &status Coherence ---\n")

(assert-equal "4.1 Forward, backward & mutual goto state machine"
  550
  (c99-run-code "
void bump_status(int *p, int d) { *p += d; }
int main(void) {
    int status = 100;
    int i = 0;
    goto state_a;
state_b:
    bump_status(&status, 30);
    i++;
    if (i < 5) goto state_a;
    goto done;
state_a:
    bump_status(&status, 60);
    goto state_b;
done:
    return status;
}"))

;;; -----------------------------------------------------------------------
;;; Group 5: Pass 132 Braun SSA 2-Pass Delayed Seal & Verifier Compliance
;;; -----------------------------------------------------------------------
(display "--- Group 5: Pass 132 Braun SSA 2-Pass Delayed Seal & L_lir_core Verifier ---\n")

(let* ((complex-src (string-append "
void ext_cb(int *st, int d) { *st += d; }
int complex_ssa_fn(int seed, int count) {
    long acc = seed;
    long step = 1;
    int status = 0;
    void (*cb)(int *, int) = ext_cb;
    int n = (count + 3) / 4;
    if (seed < 0) goto cleanup;
    switch (count % 4) {
        case 0: do { acc += step;
        case 3:      acc += step * 2;
        case 2:      acc += step * 3;
        case 1:      acc += step * 4;
                } while (--n > 0);
    }
    switch (seed) {
" (make-n-branch-switch-cases 85) "        default: acc += 1; break;
    }
    cb(&status, 50);
    goto finish;
cleanup:
    status = -10;
finish:
    return acc + status;
}
int main(void) {
    return complex_ssa_fn(3, 5);
}"))
       (ast (parse-c99-preprocessed-string complex-src "<braun-ssa-test>"))
       (typed (c99-analyze-program ast))
       (funcs (list-ref typed 2))
       (complex-ast (cadr funcs))
       (escaped (c99-collect-escaped-bindings complex-ast))
       (lir-prog (c99-lower-to-lir typed))
       (fns-clause (assq '%lir-functions (cdr lir-prog)))
       (complex-lir (cadr (cdr fns-clause)))
       (find-var-offset
        (lambda (name)
          ;; Inspect c-typed-decls in function block to build real var metadata
          ;; Local stack slots are assigned sequentially starting at -16 (seed), -24 (count),
          ;; then block locals in declaration order: acc=-32, step=-40, status=-48, cb=-56, n=-64
          #f))
       (body-decls (cdr (list-ref complex-ast 5)))
       (decl-items (let collect ((xs body-decls) (off -32) (acc '()))
                     (if (null? xs)
                         (reverse acc)
                         (let ((st (car xs)))
                           (if (and (pair? st) (eq? (car st) 'c-typed-decls))
                               (let dloop ((ds (cdr st)) (o off) (dacc acc))
                                 (if (null? ds)
                                     (collect (cdr xs) o dacc)
                                     (let ((d (car ds)))
                                       (dloop (cdr ds)
                                              (- o 8)
                                              (cons (list (list-ref d 1) 'local o (list-ref d 3)) dacc)))))
                               (collect (cdr xs) off acc))))))
       (cand-offsets (c99-function-candidate-mem2reg-offsets complex-ast decl-items))
       (status-u (car (filter (lambda (v) (string-contains-sub? (symbol->string (car v)) "status")) decl-items)))
       (acc-u (car (filter (lambda (v) (string-contains-sub? (symbol->string (car v)) "acc")) decl-items)))
       (cfg (c99-lir-fn->braun-cfg complex-lir cand-offsets))
       (ssa-fn (c99-braun-ssa-transform-fn complex-lir cand-offsets))
       (new-funcs-clause (cons '%lir-functions
                               (map (lambda (f)
                                      (if (eq? (list-ref f 1) 'complex_ssa_fn) ssa-fn f))
                                    (cdr fns-clause))))
       (ssa-prog (map (lambda (item)
                        (if (and (pair? item) (eq? (car item) '%lir-functions))
                            new-funcs-clause
                            item))
                      lir-prog)))
  (assert-true "5.1 c99-function-candidate-mem2reg-offsets excludes &status offset"
               (and (not (memv (list-ref status-u 2) cand-offsets))
                    (memv (list-ref acc-u 2) cand-offsets)))
  (assert-true "5.2 c99-lir-fn->braun-cfg seals and verifies 85-switch + Duff + goto CFG"
               (and (braun-verify-cfg cfg)
                    (>= (length (braun-cfg-ref cfg 'order)) 90)))
  (assert-true "5.3 c99-braun-ssa-transform-fn produces %block IR passing L_lir_core? & validate-core-lir"
               (and (let ((body-list (cdr (assq 'body (cddr ssa-fn)))))
                      (and (pair? body-list) (eq? (caar body-list) '%block)))
                    (L_lir_core? ssa-prog)
                    (validate-core-lir ssa-prog))))

;;; -----------------------------------------------------------------------
;;; Group 6: Semantic & Control-Flow Diagnostics (C99-CFG-001..004, C99-PTR-004)
;;; -----------------------------------------------------------------------
(display "--- Group 6: Diagnostics (C99-CFG-001..004 & C99-PTR-004) ---\n")

(assert-true "6.1 C99-CFG-001 on undeclared goto label"
  (c99-expect-error "C99-CFG-001"
    "int main(void) { goto missing_lbl; return 0; }"))

(assert-true "6.2 C99-CFG-001 on duplicate label definition"
  (c99-expect-error "C99-CFG-001"
    "int main(void) { retry: return 1; retry: return 2; }"))

(assert-true "6.3 C99-CFG-002 on duplicate case constant"
  (c99-expect-error "C99-CFG-002"
    "int main(void) { int x = 1; switch (x) { case 1: return 10; case 2: return 20; case 1: return 30; } return 0; }"))

(assert-true "6.4 C99-CFG-002 on multiple default labels in one switch"
  (c99-expect-error "C99-CFG-002"
    "int main(void) { int x = 1; switch (x) { default: return 1; case 2: return 2; default: return 3; } return 0; }"))

(assert-true "6.5 C99-CFG-003 on case outside switch"
  (c99-expect-error "C99-CFG-003"
    "int main(void) { case 1: return 0; }"))

(assert-true "6.6 C99-CFG-003 on default outside switch"
  (c99-expect-error "C99-CFG-003"
    "int main(void) { default: return 0; }"))

(assert-true "6.7 C99-CFG-003 on break outside loop/switch"
  (c99-expect-error "C99-CFG-003"
    "int main(void) { break; return 0; }"))

(assert-true "6.8 C99-CFG-003 on continue inside switch outside loop"
  (c99-expect-error "C99-CFG-003"
    "int main(void) { int x = 1; switch (x) { case 1: continue; } return 0; }"))

(assert-true "6.9 C99-CFG-004 on calling non-function int variable"
  (c99-expect-error "C99-CFG-004"
    "int main(void) { int x = 5; return x(1, 2); }"))

(assert-true "6.10 C99-CFG-004 on calling int* data pointer"
  (c99-expect-error "C99-CFG-004"
    "int main(void) { int a = 1; int *p = &a; return p(); }"))

(assert-true "6.11 C99-PTR-004 on incompatible function pointer signature assignment"
  (c99-expect-error "C99-PTR-004"
    "int f(int x) { return x; }
     int main(void) { int (*g)(int, int) = f; return 0; }"))

(assert-true "6.12 C99-PTR-004 on implicit conversion between void* and function pointer"
  (c99-expect-error "C99-PTR-004"
    "int f(int x) { return x; }
     int main(void) { void *vp = f; return vp != 0; }"))

(assert-true "6.13 C99-PTR-004 on relational < comparison of function pointers"
  (c99-expect-error "C99-PTR-004"
    "int f(int x) { return x; }
     int g(int x) { return x + 1; }
     int main(void) { return f < g; }"))

(display "\n-------------------------------------------------------\n")
(display " [RESULT] C99 Function Pointers & Switch/Goto CFG (Issue #920): ")
(display (car *tests-passed*)) (display " passed, ")
(display (car *tests-failed*)) (display " failed (Total: ")
(display (+ (car *tests-passed*) (car *tests-failed*))) (display ")\n")
(display "-------------------------------------------------------\n")

(if (> (car *tests-failed*) 0)
    (exit 1)
    (exit 0))
