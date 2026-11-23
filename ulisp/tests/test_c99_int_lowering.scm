;;; =======================================================================
;;; Test Suite: C99 Sema Core & Integer Subset Core LIR Lowering (Issue #916)
;;; Conforms to DSN-33-11 §4.2/§4.3, DSN-33-13, #834 (Ref VM), #835 (Core LIR)
;;; =======================================================================

(enable-verifier!)
(set-verifier-level! 3)
(set-verifier-strict! #t)

(test-begin "C99 Sema Core & Integer Subset Core LIR Lowering (Issue #916)")

(define (eval-c99-vm src fname)
  (let ((lir (c99-compile-string-to-lir src fname)))
    (assert-true (string-append fname ": passes L_lir_core?") (L_lir_core? lir))
    (assert-true (string-append fname ": passes validate-core-lir") (validate-core-lir lir))
    (eval-lir-program lir)))

;;; -----------------------------------------------------------------------
;;; Group 1: Basic Integer Arithmetic, Bitwise & Signed/Unsigned Semantics
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Integer Arithmetic, Shifts & Unsigned Wrapping ---\n")

(assert-equal "1.1 arithmetic precedence & bitwise ops"
              42
              (eval-c99-vm
               "int main(void) {
                  int a = 10;
                  int b = 3;
                  int c = (a * b) + ((0xFF & 0x0F) - (1 << 2)) + (~(-2));
                  return c;
                }"
               "t1_arith.c"))

(assert-equal "1.2 signed vs unsigned right shift and modulo"
              7
              (eval-c99-vm
               "int main(void) {
                  int s = -16;
                  unsigned int u = 23U;
                  int r1 = s >> 2;         /* -4 */
                  unsigned int r2 = u % 8; /* 7 */
                  return (r1 == -4) ? (int)r2 : 0;
                }"
               "t1_shift_mod.c"))

(assert-equal "1.3 dynamic runtime shift count (barrel shifter)"
              165
              (eval-c99-vm
               "int sh(int x, int n) { return (x << n) + (x >> (n - 3)); }
                int main(void) { return sh(10, 4); }"
               "t1_dynshift.c"))

(assert-equal "1.4 unsigned 32-bit wrap & signed/unsigned comparison"
              1
              (eval-c99-vm
               "int main(void) {
                  unsigned int u = 0xFFFFFFFFU;
                  unsigned int zero_m1 = 0U - 1U;
                  int neg = -1;
                  return (u > 1U) && (zero_m1 == u) && (u == (unsigned int)neg);
                }"
               "t1_u32.c"))

(assert-equal "1.5 C99 integer promotion (unsigned char / short -> int)"
              257
              (eval-c99-vm
               "int main(void) {
                  unsigned char c = 250;
                  signed char d = 7;
                  return c + d;
                }"
               "t1_promo.c"))

;;; -----------------------------------------------------------------------
;;; Group 2: Short-Circuiting, Ternary, Control Flow & Block Shadowing
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Short-Circuiting, Loops & Block Shadowing ---\n")

(assert-equal "2.1 short-circuit && and || prevent RHS side effects"
              12
              (eval-c99-vm
               "int side = 10;
                int bump(void) { side += 100; return 1; }
                int main(void) {
                  int a = (0 && bump());
                  int b = (1 || bump());
                  return side + a + b + 1; /* 10 + 0 + 1 + 1 = 12 */
                }"
               "t2_short_circuit.c"))

(assert-equal "2.2 for / while / do-while / continue / break control flow"
              42
              (eval-c99-vm
               "int main(void) {
                  int acc = 0;
                  for (int i = 0; i < 10; i++) {
                    if (i == 5) continue;
                    if (i == 9) break;
                    acc += i; /* 0+1+2+3+4+6+7+8 = 31 */
                  }
                  int k = 0;
                  while (k < 4) { acc += 2; k++; } /* 31 + 8 = 39 */
                  do { acc += 3; } while (0);       /* 42 */
                  return acc;
                }"
               "t2_loops.c"))

(assert-equal "2.3 block shadowing & postfix/prefix ++/-- operators"
              30
              (eval-c99-vm
               "int main(void) {
                  int x = 10;
                  {
                    int x = 50;
                    x--;
                  }
                  int y = x++; /* y=10, x=11 */
                  int z = ++x; /* z=12, x=12 */
                  return y + z + 8; /* 10 + 12 + 8 = 30 */
                }"
               "t2_shadow.c"))

;;; -----------------------------------------------------------------------
;;; Group 3: Functions, Recursion (fib), 8-Arg SysV Spill & Enum/sizeof
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Functions, Recursion, >6 Args & Enums ---\n")

(assert-equal "3.1 recursive fib(10) == 55"
              55
              (eval-c99-vm
               "int fib(int n) {
                  if (n <= 1) return n;
                  return fib(n - 1) + fib(n - 2);
                }
                int main(void) { return fib(10); }"
               "t3_fib.c"))

(assert-equal "3.2 8-argument C function across SysV GPR + stack spill"
              36
              (eval-c99-vm
               "int sum8(int a, int b, int c, int d, int e, int f, int g, int h) {
                  return a + b + c + d + e + f + g + h;
                }
                int main(void) {
                  return sum8(1, 2, 3, 4, 5, 6, 7, 8);
                }"
               "t3_sum8.c"))

(assert-equal "3.3 enum constants & compile-time sizeof / preprocessor macros"
              18
              (eval-c99-vm
               "#define SCALE 2
                enum Tag { TAG_NONE = 1, TAG_NUM = 3, TAG_STR };
                int main(void) {
                  return (TAG_STR + (int)sizeof(long)) * SCALE - 6; /* (4 + 8)*2 - 6 = 18 */
                }"
               "t3_enum_sizeof.c"))

;;; -----------------------------------------------------------------------
;;; Group 4: String Literals (.rodata) & Foreign 'sysv Call on Reference VM
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: String Literals & External 'sysv Call ---\n")

(let* ((lir (c99-compile-string-to-lir
             "int main(void) {
                puts(\"Hello, C99 LIR!\");
                return 99;
              }"
             "t4_puts.c"))
       (vm (make-lir-vm))
       (captured ""))
  (assert-true "4.1 puts program satisfies validate-core-lir" (validate-core-lir lir))
  (assert-true "4.2 puts program satisfies L_lir_core?" (L_lir_core? lir))
  (register-c-foreign-handler!
   vm 'puts
   (lambda (m)
     (let ((ptr (vm-get-reg m '%rdi)))
       (let loop ((i 0) (acc '()))
         (let ((b (vm-mem-read-u8 m (+ ptr i))))
           (if (= b 0)
               (begin
                 (set! captured (list->string (reverse acc)))
                 (vm-set-reg! m '%rax i))
               (loop (+ i 1) (cons (integer->char b) acc))))))))
  (lir-vm-load! vm lir)
  (lir-vm-run! vm)
  (assert-equal "4.3 Reference VM captured NUL-terminated string from %str-ref"
                "Hello, C99 LIR!"
                captured)
  (assert-equal "4.4 main return value after puts call is 99"
                99
                (vm-get-reg vm '%rax)))

;;; -----------------------------------------------------------------------
;;; Group 5: Semantic Error Diagnostics (C99-SEMA-001 .. C99-SEMA-005)
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Span-Annotated Semantic Diagnostics ---\n")

(let ((e1 (guard (ex (else ex))
            (c99-compile-string-to-lir "int main(void) { return missing_var; }" "err_undef.c"))))
  (assert-true "5.1 undeclared variable raises C99-SEMA-001"
               (and (pair? e1) (eq? (car e1) 'c99-sema-error)
                    (equal? (cadr e1) "C99-SEMA-001"))))

(let ((e2 (guard (ex (else ex))
            (c99-compile-string-to-lir "int main(void) { int a = 1; (a + 2) = 3; return a; }" "err_lval.c"))))
  (assert-true "5.2 non-lvalue assignment raises C99-SEMA-002"
               (and (pair? e2) (eq? (car e2) 'c99-sema-error)
                    (equal? (cadr e2) "C99-SEMA-002"))))

(let ((e3 (guard (ex (else ex))
            (c99-compile-string-to-lir "void foo(void) { return 1; } int main(void) { return 0; }" "err_ret.c"))))
  (assert-true "5.3 returning value in void function raises C99-SEMA-003"
               (and (pair? e3) (eq? (car e3) 'c99-sema-error)
                    (equal? (cadr e3) "C99-SEMA-003"))))

(let ((e4 (guard (ex (else ex))
            (c99-compile-string-to-lir "int f(int a) { return a; } int main(void) { return f(1, 2); }" "err_argc.c"))))
  (assert-true "5.4 argument count mismatch raises C99-SEMA-004"
               (and (pair? e4) (eq? (car e4) 'c99-sema-error)
                    (equal? (cadr e4) "C99-SEMA-004"))))

(let ((e5 (guard (ex (else ex))
            (c99-compile-string-to-lir "int main(void) { return 10 / 0; }" "err_div0.c"))))
  (assert-true "5.5 compile-time division by zero raises C99-SEMA-005"
               (and (pair? e5) (eq? (car e5) 'c99-sema-error)
                    (equal? (cadr e5) "C99-SEMA-005"))))

;;; -----------------------------------------------------------------------
;;; Group 6: Register-Only Expr Lowering, imm32 Safety & Call Args (#934)
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Temporary Spill Elimination & Register Forwarding ---\n")

;; 6.1 Width-safe imm32: (unsigned int)-1 must NOT sign-extend to 64-bit -1
(let* ((src "
int main(void) {
  unsigned long ul = 0x00000000FFFFFFFFUL;
  unsigned int u = (unsigned int)ul;
  int r1 = (ul == (unsigned long)(unsigned int)-1) ? 10 : 0;
  int r2 = (u < (unsigned int)-1) ? 0 : 20;
  int r3 = ((int)-1 < 0) ? 4 : 0;
  return r1 + r2 + r3;
}")
       (lir (c99-compile-string-to-lir src "imm32_sign.c"))
       (opt (lir-peephole-optimize lir))
       (vm (make-lir-vm)))
  (assert-true "6.1a unsigned imm32 safety satisfies L_lir_core" (L_lir_core? opt))
  (lir-vm-load! vm opt)
  (lir-vm-run! vm)
  (assert-equal "6.1b (unsigned int)-1 compares as 0x00000000FFFFFFFF"
                34
                (vm-get-reg vm '%rax)))

;; 6.2 Deeply nested call-free arithmetic + member + index produces 0 temporary spills
(let* ((src "
struct Pt { long x; long y; long z; };
long eval_deep(struct Pt *p, long *arr, long a, long b, long c, long d, long e) {
  return (a + (b * (c - 3))) + p->y + arr[2] + (e ^ d);
}
int main(void) {
  struct Pt pt;
  long arr[4];
  pt.x = 1; pt.y = 100; pt.z = 2;
  arr[0] = 5; arr[1] = 6; arr[2] = 50; arr[3] = 7;
  return (int)eval_deep(&pt, arr, 10, 2, 20, 3, 4);
}")
       (lir (c99-compile-string-to-lir src "deep_reg_stack.c"))
       (opt (lir-peephole-optimize lir))
       (vm (make-lir-vm))
       (funcs (cdr (assq '%lir-functions (cdr opt))))
       (eval-fn (let find-fn ((fs funcs))
                  (cond
                    ((null? fs) #f)
                    ((and (pair? (car fs)) (pair? (cdar fs)) (eq? (cadar fs) 'eval_deep))
                     (car fs))
                    (else (find-fn (cdr fs))))))
       (eval-body (cdr (assq 'body (cddr eval-fn))))
       (rsp-stores (let count-s ((is eval-body) (k 0))
                     (if (null? is)
                         k
                         (let ((in (car is)))
                           (count-s (cdr is)
                                    (if (and (pair? in)
                                             (memq (car in) '(%store %store-typed))
                                             (or (eq? (cadr in) '%rsp)
                                                 (and (eq? (car in) '%store-typed)
                                                      (eq? (caddr in) '%rsp))))
                                        (+ k 1)
                                        k)))))))
  (lir-vm-load! vm opt)
  (lir-vm-run! vm)
  ;; c-3=17, b*17=34, a+34=44, +100 +50 + (4^3=7) = 201
  (assert-equal "6.2a deeply nested call-free expression computes exact value"
                201
                (vm-get-reg vm '%rax))
  (assert-true "6.2b eval_deep has zero extra temporary stack spill stores beyond param homes"
               (<= rsp-stores 7)))

;; 6.3 Multi-arg call side-effect order preserved across register & stack fallbacks
(let* ((src "
int g_log = 0;
int bump(int k) { g_log = g_log * 10 + k; return g_log; }
int f4(int a, int b, int c, int d) {
  return a * 1000 + b * 100 + c * 10 + d;
}
int main(void) {
  int x = 2;
  int r1 = f4(bump(1), x, (x += 3), bump(4));
  int r2 = f4(1, 2, 3, 4);
  return r1 + r2 + x;
}")
       (lir (c99-compile-string-to-lir src "call_order.c"))
       (opt (lir-peephole-optimize lir))
       (vm (make-lir-vm)))
  (assert-true "6.3a call order program satisfies L_lir_canonical?" (L_lir_canonical? opt))
  (lir-vm-load! vm opt)
  (lir-vm-run! vm)
  ;; bump(1)->1 (g_log=1); x->2; x+=3->5; bump(4)->14
  ;; r1 = 1*1000 + 2*100 + 5*10 + 14 = 1264; r2 = 1234; x = 5 => 2503
  (assert-equal "6.3b multi-arg call preserves left-to-right side effects without spills"
                2503
                (vm-get-reg vm '%rax)))

(test-end "C99 Sema Core & Integer Subset Core LIR Lowering (Issue #916)")
