;;; =======================================================================
;;; test_c99_floating_point.scm
;;; Comprehensive Unit, Sema, Core LIR Verifier & LIR VM Execution Suite
;;; for C99 Floating-Point Sema, IEEE 754 Encoder & Core LIR Lowering (#923)
;;; Zero local `set!` (ULisp AOT safe).
;;; =======================================================================

(define *fp-tests-passed* (cons 0 '()))
(define *fp-tests-failed* (cons 0 '()))

(define (fp-assert-true desc val)
  (if val
      (begin
        (set-car! *fp-tests-passed* (+ (car *fp-tests-passed*) 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set-car! *fp-tests-failed* (+ (car *fp-tests-failed*) 1))
        (display "  [FAIL] ") (display desc) (newline)
        (error "Assertion failed: expected #t" desc))))

(define (fp-assert-equal desc expected actual)
  (if (equal? expected actual)
      (begin
        (set-car! *fp-tests-passed* (+ (car *fp-tests-passed*) 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set-car! *fp-tests-failed* (+ (car *fp-tests-failed*) 1))
        (display "  [FAIL] ") (display desc)
        (display " (expected ") (write expected)
        (display ", got ") (write actual) (display ")") (newline)
        (error "Assertion failed: values not equal" desc))))

(define (fp-assert-u64 desc expected-u64 actual-val)
  (let ((norm (modulo actual-val 18446744073709551616)))
    (fp-assert-equal desc expected-u64 norm)))

(define (fp-compile-verified src)
  (let ((lir (c99-compile-string-to-lir src "<test-fp>")))
    (fp-assert-true "validate-lir core passes" (validate-lir lir 'core))
    (fp-assert-true "verify-lir passes" (verify-lir lir))
    lir))

(define (fp-run-c src)
  (let ((lir (c99-compile-string-to-lir src "<test-fp>")))
    (if (not (validate-lir lir 'core))
        (error "validate-lir core failed" src))
    (if (not (verify-lir lir))
        (error "verify-lir failed" src))
    (eval-lir-program lir)))

(define (fp-expect-sema-error err-code src)
  (guard (ex
          ((and (pair? ex) (pair? (cdr ex)) (equal? (cadr ex) err-code))
           (fp-assert-true (string-append "sema error " err-code) #t))
          (else
           (display "  [FAIL] Expected sema error ") (display err-code)
           (display ", got: ") (write ex) (newline)
           (set-car! *fp-tests-failed* (+ (car *fp-tests-failed*) 1))
           (error "Unexpected error" ex)))
    (let* ((ast (parse-c99-preprocessed-string src "<test-fp-err>"))
           (typed (c99-analyze-program ast)))
      (c99-lower-to-lir typed)
      (fp-assert-true (string-append "expected error " err-code " but succeeded") #f))))

(define (fp-count-data-prefix lir prefix)
  (let* ((dc (assq 'data (cdr lir)))
         (entries (if (and dc (pair? (cdr dc))) (cadr dc) '()))
         (plen (string-length prefix)))
    (let loop ((es entries) (cnt 0))
      (if (null? es)
          cnt
          (let* ((de (car es))
                 (lbl (symbol->string (cadr de))))
            (loop (cdr es)
                  (if (and (>= (string-length lbl) plen)
                           (string=? (substring lbl 0 plen) prefix))
                      (+ cnt 1)
                      cnt)))))))

(define (fp-contains-inst? lir op)
  (let ((check-insts
         (lambda (insts)
           (let loop ((is insts))
             (cond
               ((null? is) #f)
               ((and (pair? (car is)) (eq? (caar is) '%block))
                (or (loop (cdddar is)) (loop (cdr is))))
               ((and (pair? (car is)) (eq? (caar is) op)) #t)
               (else (loop (cdr is))))))))
    (let* ((fc (assq '%lir-functions (cdr lir)))
           (funcs (if fc (cdr fc) '()))
           (mc (assq '%lir-main (cdr lir)))
           (mbody (if mc (cdr (assq 'body (cdr mc))) '())))
      (or (check-insts mbody)
          (let floop ((fs funcs))
            (if (null? fs)
                #f
                (let ((b (assq 'body (cddar fs))))
                  (or (and b (check-insts (cdr b)))
                      (floop (cdr fs))))))))))

(display "=== 1. IEEE 754 Arbitrary-Precision Encoder Unit Tests (#923) ===") (newline)

(let ((check-lit
       (lambda (desc lit exp-ty exp-bits)
         (let ((res (c99-parse-float-literal lit)))
           (fp-assert-equal (string-append desc " status") 'ok (car res))
           (fp-assert-equal (string-append desc " type") exp-ty (cadr res))
           (fp-assert-equal (string-append desc " bits") exp-bits (caddr res))))))
  (check-lit "0.0" "0.0" 'f64 #x0000000000000000)
  (check-lit "-0.0" "-0.0" 'f64 #x8000000000000000)
  (check-lit "1.5" "1.5" 'f64 #x3ff8000000000000)
  (check-lit "0.1" "0.1" 'f64 #x3fb999999999999a)
  (check-lit "1.5f" "1.5f" 'f32 #x3fc00000)
  (check-lit "-0.0f" "-0.0f" 'f32 #x80000000)
  (check-lit "0x1.921fb54442d18p+1" "0x1.921fb54442d18p+1" 'f64 #x400921fb54442d18)
  (check-lit "0x1p-1074 subnormal" "0x1p-1074" 'f64 #x0000000000000001)
  (check-lit "1e-320 dec subnormal" "1e-320" 'f64 #x00000000000007e8)
  (check-lit "1e500 +Inf" "1e500" 'f64 #x7ff0000000000000)
  (check-lit "-1e500 -Inf" "-1e500" 'f64 #xfff0000000000000)
  (check-lit "1e-500 underflow +0" "1e-500" 'f64 #x0000000000000000)
  (check-lit "-1e-500 underflow -0" "-1e-500" 'f64 #x8000000000000000)
  (check-lit "0x1.fffffep+127f" "0x1.fffffep+127f" 'f32 #x7f7fffff)
  (check-lit "0x1p-149f f32 min sub" "0x1p-149f" 'f32 #x00000001)
  (check-lit "7.038531e-26f exact single-round" "7.038531e-26f" 'f32 #x15ae43fd)
  (check-lit "1.000000059604644775390625f tie-to-even" "1.000000059604644775390625f" 'f32 #x3f800000)
  (check-lit "1.000000059604644775390625001f dec single-round up" "1.000000059604644775390625001f" 'f32 #x3f800001)
  (check-lit "0x1.00000100000000000001p0f single-round up" "0x1.00000100000000000001p0f" 'f32 #x3f800001)
  (check-lit "0x1.000001p0f tie-to-even" "0x1.000001p0f" 'f32 #x3f800000)
  (check-lit "3.14L long double->f64" "3.14L" 'f64 #x40091eb851eb851f))

(fp-assert-equal "malformed hex float without p" 'error (car (c99-parse-float-literal "0x1.0")))
(fp-assert-equal "malformed double suffix ff" 'error (car (c99-parse-float-literal "1.5ff")))
(fp-assert-equal "malformed trailing e" 'error (car (c99-parse-float-literal "1.5e")))
(fp-assert-equal "f32->f64 -0.0" #x8000000000000000 (c99-ieee754-f32-bits->f64-bits #x80000000))
(fp-assert-equal "f64->f32 single-round big" #x7f800000 (c99-ieee754-f64-bits->f32-bits #x47f0000000000000))
(fp-assert-equal "u64->f32 single-round edge" #x5f000001 (c99-ieee754-int->f32-bits #x8000017fffffffff))

(display "=== 2. C99 Sema Diagnostics Tests (C99-FP-001 / C99-FP-002) ===") (newline)

(fp-expect-sema-error "C99-FP-001" "int f(double d) { return (int)(~d); }")
(fp-expect-sema-error "C99-FP-001" "int f(double d) { return (int)(d << 1); }")
(fp-expect-sema-error "C99-FP-001" "int f(float x) { return 1 >> x; }")
(fp-expect-sema-error "C99-FP-001" "int f(double d) { return (int)(d & 1); }")
(fp-expect-sema-error "C99-FP-001" "int f(double d) { return (int)(d ^ 1); }")
(fp-expect-sema-error "C99-FP-001" "int f(double d) { return (int)(d | 1); }")
(fp-expect-sema-error "C99-FP-001" "int f(double d) { return (int)(d % 2); }")
(fp-expect-sema-error "C99-FP-001" "void f(double d) { d %= 2; }")
(fp-expect-sema-error "C99-FP-001" "void f(double d) { d &= 1; }")
(fp-expect-sema-error "C99-FP-001" "void f(int i) { i <<= 1.0; }")

(fp-assert-equal "sema constant parser flags 0x1.0 as c-float-error"
  'c-float-error (caar (c99-parse-constant-info "0x1.0")))
(fp-assert-equal "sema constant parser flags 1.5ff as c-float-error"
  'c-float-error (caar (c99-parse-constant-info "1.5ff")))
(fp-assert-equal "sema constant parser flags 1.5e as c-float-error"
  'c-float-error (caar (c99-parse-constant-info "1.5e")))
(fp-expect-sema-error "C99-FP-002" "int *f(double d) { return (int *)d; }")
(fp-expect-sema-error "C99-FP-002" "double f(int *p) { return (double)p; }")
(fp-expect-sema-error "C99-FP-002" "void f(double d) { int *p = 0; p = d; }")
(fp-expect-sema-error "C99-FP-002" "void f(int *p) { double d = p; }")

(display "=== 3. Core LIR Pool Deduplication & Instruction Lowering Tests ===") (newline)

(let ((lir (fp-compile-verified "
double f1(void) { return 1.5; }
double f2(double x) {
    double a = 1.5;
    double b = -x;
    return (a > b) ? a + 1.5 : (double)(unsigned long long)x;
}
int main(void) { return (int)f2(1.5); }
")))
  (fp-assert-equal "content-addressed .L_c99_fp64_ pool deduplication" 1 (fp-count-data-prefix lir ".L_c99_fp64_"))
  (fp-assert-true "emits %fneg" (fp-contains-inst? lir '%fneg))
  (fp-assert-true "emits %fcmp-ogt" (fp-contains-inst? lir '%fcmp-ogt))
  (fp-assert-true "emits %uitofp" (fp-contains-inst? lir '%uitofp)))

(display "=== 4. LIR VM Bit-Exact Execution Tests ===") (newline)

;; 4a. Negative zero, unary %fneg, float %fneg, subnormals, static initializers
(fp-assert-u64 "-(+0.0) produces -0.0" #x8000000000000000
  (fp-run-c "
union D { double d; unsigned long long u; };
long long main(void) {
    double z = 0.0;
    union D x;
    x.d = -z;
    return (long long)x.u;
}
"))

(fp-assert-u64 "-(+0.0f) produces -0.0f" #x80000000
  (fp-run-c "
union F { float f; unsigned int u; };
long long main(void) {
    float z = 0.0f;
    union F x;
    x.f = -z;
    return (long long)(unsigned long long)x.u;
}
"))

(fp-assert-u64 "static double -0.0 initializer preserved" #x8000000000000000
  (fp-run-c "
static double g_nz = -0.0;
union D { double d; unsigned long long u; };
long long main(void) {
    union D x;
    x.d = g_nz;
    return (long long)x.u;
}
"))

(fp-assert-u64 "static double 1.0/0.0 inf + min subnormal" #x7ff0000000000001
  (fp-run-c "
static double g_inf = 1.0 / 0.0;
static double g_sub = 0x1p-1074;
union D { double d; unsigned long long u; };
long long main(void) {
    union D a, b;
    a.d = g_inf;
    b.d = g_sub;
    return (long long)(a.u | b.u);
}
"))

;; 4b. NaN comparisons & runtime 0.0/0.0
(fp-assert-equal "IEEE 754 NaN and -0.0 comparisons" 1
  (fp-run-c "
int main(void) {
    double z = 0.0;
    double nz = -0.0;
    double nanv = z / z;
    double infp = 1.0 / 0;
    int ok = 1;
    if (!(nz == z)) ok = 0;
    if (nz != z) ok = 0;
    if (nanv == nanv) ok = 0;
    if (!(nanv != nanv)) ok = 0;
    if (nanv < 1.0 || nanv <= 1.0 || nanv > 1.0 || nanv >= 1.0) ok = 0;
    if (!(infp > 1e300)) ok = 0;
    return ok;
}
"))

;; 4c. All 8 float condition sites + !x + (_Bool)x
(fp-assert-equal "float conditions across control flow, short-circuit, ternary" 1
  (fp-run-c "
struct S { int k; };
static int check_val(double x) {
    int c1 = x ? 1 : 0;
    int c2 = !x;
    int c3 = (_Bool)x;
    int c4 = 0; if (x) c4 = 1;
    int c5 = 0; while (x) { c5 = 1; break; }
    int c6 = 0; double dv = x; do { c6++; if (c6 > 1) break; dv = 0.0; } while (dv);
    int c7 = 0; for (double fv = x; fv; fv = 0.0) { c7++; if (c7 > 1) break; }
    int c8 = (x && 1);
    int c9 = (0 || x);
    struct S sa = {1}, sb = {0};
    struct S sr = x ? sa : sb;
    return (c1 << 0) | (c2 << 1) | (c3 << 2) | (c4 << 3) |
           (c5 << 4) | ((c6 - 1) << 5) | (c7 << 6) | (c8 << 7) |
           (c9 << 8) | (sr.k << 9);
}
int main(void) {
    double z = 0.0;
    double nz = -0.0;
    double nanv = z / z;
    int r_pos0 = check_val(z);
    int r_neg0 = check_val(nz);
    int r_nan  = check_val(nanv);
    int r_nz   = check_val(2.5);
    /* false mask has bit 1 (!x) only = 2; true mask has bits 0,2,3,4,6,7,8,9 = 989 */
    return (r_pos0 == 2) && (r_neg0 == 2) && (r_nan == 989) && (r_nz == 989);
}
"))

;; 4d. Float ++/-- & mixed compound assignment
(fp-assert-equal "float inc/dec & mixed compound assignment" 1
  (fp-run-c "
int main(void) {
    double d = 1.5;
    double p1 = ++d;   /* d=2.5, p1=2.5 */
    double p2 = d--;   /* p2=2.5, d=1.5 */
    float f = 3.0f;
    float f1 = --f;    /* f1=2.0f, f=2.0f */
    float f2 = f++;    /* f2=2.0f, f=3.0f */
    int i = 10;
    i += 2.75;         /* 12 */
    int k = 8;
    k *= 0.25f;        /* 2 */
    double md = 4.0;
    md += 3;           /* 7.0 */
    float mf = 2.0f;
    mf += 0x1.0000008p-23; /* rounded once from double sum -> > 2.0f */
    return (p1 == 2.5) && (p2 == 2.5) && (d == 1.5) &&
           (f1 == 2.0f) && (f2 == 2.0f) && (f == 3.0f) &&
           (i == 12) && (k == 2) && (md == 7.0) && (mf > 2.0f);
}
"))

;; 4e. Signed negative -> float, u64 <-> double/float, single rounding i64/u64 -> f32
(fp-assert-u64 "i64/u64 -> f32 single-rounding & double -> u64 >= 2^63" 1
  (fp-run-c "
union F { float f; unsigned int u; };
union D { double d; unsigned long long u; };
int main(void) {
    long long neg = -42;
    double dn = (double)neg;
    unsigned long long ubig = 0x8000017fffffffffULL;
    long long sbig = -0x7fffffbfffffffffLL;
    union F fu, fs;
    fu.f = (float)ubig;
    fs.f = (float)sbig;
    unsigned long long uh = (unsigned long long)(9223372036854775808.0 + 4096.0);
    unsigned long long uz = (unsigned long long)(-0.75);
    union D dmax, dovf;
    dmax.d = (double)0xfffffffffffff800ULL;
    dovf.d = (double)0xffffffffffffffffULL;
    return (dn == -42.0) &&
           (fu.u == 0x5f000001U) &&
           (fs.u == 0xdeffffffU) &&
           (uh == 0x8000000000001000ULL) &&
           (uz == 0ULL) &&
           (dmax.u == 0x43efffffffffffffULL) &&
           (dovf.u == 0x43f0000000000000ULL) &&
           (sizeof(long double) == 8);
}
"))

(display "========================================================================") (newline)
(display " Floating-Point Test Suite Summary: ")
(display (car *fp-tests-passed*)) (display " passed, ")
(display (car *fp-tests-failed*)) (display " failed") (newline)
(display "========================================================================") (newline)
(if (> (car *fp-tests-failed*) 0)
    (exit 1))
