;;; =======================================================================
;;; test_c99_bounds_sanitizer.scm
;;; Unit & Reference VM Tests for C99 Bounds & NULL Sanitizer (--sanitize-bounds)
;;; Conforms to DSN-33-32 §6.1/§6.4, DSN-33-11, DSN-33-13 & Issue #930
;;; Zero local `set!` (ULisp AOT safe).
;;; =======================================================================

(define *san-tests-passed* (cons 0 '()))
(define *san-tests-failed* (cons 0 '()))

(define (assert-true desc val)
  (if val
      (begin
        (set-car! *san-tests-passed* (+ (car *san-tests-passed*) 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set-car! *san-tests-failed* (+ (car *san-tests-failed*) 1))
        (display "  [FAIL] ") (display desc) (newline)
        (error "Assertion failed: expected #t" desc))))

(define (assert-equal desc expected actual)
  (if (equal? expected actual)
      (begin
        (set-car! *san-tests-passed* (+ (car *san-tests-passed*) 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set-car! *san-tests-failed* (+ (car *san-tests-failed*) 1))
        (display "  [FAIL] ") (display desc)
        (display " (expected ") (write expected)
        (display ", got ") (write actual) (display ")") (newline)
        (error "Assertion failed: values not equal" desc))))

(define (san-str-contains? haystack needle)
  (let ((hlen (string-length haystack))
        (nlen (string-length needle)))
    (if (= nlen 0)
        #t
        (let loop ((i 0))
          (cond
            ((> (+ i nlen) hlen) #f)
            ((string=? (substring haystack i (+ i nlen)) needle) #t)
            (else (loop (+ i 1))))))))

(define (san-lir-walk-has? obj pred)
  (cond
    ((pred obj) #t)
    ((pair? obj)
     (or (san-lir-walk-has? (car obj) pred)
         (san-lir-walk-has? (cdr obj) pred)))
    (else #f)))

(define (san-has-jump-cc? lir cc)
  (san-lir-walk-has?
   lir
   (lambda (x) (and (pair? x) (eq? (car x) '%jump-cond) (eq? (cadr x) cc)))))

(define (san-has-fn? lir fn-sym)
  (let ((fns (assq '%lir-functions (cdr lir))))
    (and fns
         (let loop ((fs (cdr fns)))
           (cond
             ((null? fs) #f)
             ((and (pair? (car fs)) (eq? (cadar fs) fn-sym)) #t)
             (else (loop (cdr fs))))))))

(define (san-eval-vm-outcome src . maybe-san)
  (let* ((san? (if (and (pair? maybe-san) (car maybe-san)) #t #f))
         (lir (c99-compile-string-to-lir src "san_vm_test.c" (list (cons 'sanitize-bounds? san?))))
         (vm (make-lir-vm)))
    (lir-vm-load! vm lir)
    (let ((res (lir-vm-run! vm)))
      (if (eq? res 'trapped)
          (list 'trap (vm-trap-type (vm-last-trap vm)) (vm-trap-message (vm-last-trap vm)))
          (list 'ok (vm-get-reg vm '%rax))))))

(display "=== [Test Suite: C99 Bounds & NULL Sanitizer (--sanitize-bounds, Issue #930)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Zero-Overhead Invariant (OFF vs Default)
;;; -----------------------------------------------------------------------
(display "--- Group 1: Zero-Overhead Invariant (OFF vs Default) ---\n")

(define *san-sample-c* "
struct Pair { int a; int b; };
int test_all(int *p, struct Pair *sp, int idx) {
    int arr[4] = {10, 20, 30, 40};
    int *endp = &arr[4];
    int s = arr[idx] + arr[2] + *p + sp->b + p[1];
    return (int)((long)endp - (long)&arr[0]) + s;
}
int main(void) {
    int x = 5;
    int two[2] = {1, 2};
    struct Pair pr = {7, 8};
    return test_all(two, &pr, 1) + x;
}
")

(let ((lir-default (c99-compile-string-to-lir *san-sample-c* "zero_ovh.c"))
      (lir-off     (c99-compile-string-to-lir *san-sample-c* "zero_ovh.c" '((sanitize-bounds? . #f))))
      (lir-on      (c99-compile-string-to-lir *san-sample-c* "zero_ovh.c" '((sanitize-bounds? . #t)))))
  (assert-equal "1.1 sanitize-bounds?=#f produces exact 0-diff LIR vs default" lir-default lir-off)
  (assert-true "1.2 sanitize-bounds?=#f emits no __ulisp_san_trap" (not (san-has-fn? lir-off '__ulisp_san_trap)))
  (assert-true "1.3 sanitize-bounds?=#t emits __ulisp_san_trap" (san-has-fn? lir-on '__ulisp_san_trap))
  (assert-true "1.4 sanitize-bounds?=#t emits jae guard for arr[idx]" (san-has-jump-cc? lir-on 'jae))
  (assert-true "1.5 sanitize-bounds?=#t emits ja guard for &arr[4]" (san-has-jump-cc? lir-on 'ja))
  (assert-true "1.6 sanitize-bounds?=#t emits je guard for NULL checks" (san-has-jump-cc? lir-on 'je)))

;;; -----------------------------------------------------------------------
;;; Group 2: <source-span> Location & CWE-117 Control-Char Sanitization
;;; -----------------------------------------------------------------------
(display "--- Group 2: <source-span> Location & CWE-117 Sanitization ---\n")

(let* ((dirty-fname (string-append "evil" (string (integer->char 27)) "[31m\r\n" (string (integer->char 127)) "file.c"))
       (lir-dirty (c99-compile-string-to-lir
                   "int main(void) {\n    int a[3] = {1,2,3};\n    return a[5];\n}\n"
                   dirty-fname
                   '((sanitize-bounds? . #t))))
       (strs-entry (assq 'strings (cdr lir-dirty)))
       (msgs (if strs-entry (map cadr (cadr strs-entry)) '())))
  (assert-true "2.1 Diagnostic string contains C99-SAN-001 and line:col"
               (san-lir-walk-has? msgs (lambda (s)
                                         (and (string? s)
                                              (san-str-contains? s "[ulisp-sanitizer] error[C99-SAN-001]:")
                                              (san-str-contains? s ":3:")))))
  (assert-true "2.2 CWE-117 ESC/CR/DEL stripped from filename in .rodata"
               (not (san-lir-walk-has? msgs (lambda (s)
                                              (and (string? s)
                                                   (or (san-str-contains? s (string (integer->char 27)))
                                                       (san-str-contains? s "\r")
                                                       (san-str-contains? s (string (integer->char 127))))))))))

;;; -----------------------------------------------------------------------
;;; Group 3: Trailing [1] FAM Exemption vs Non-Trailing [1] & Normal Arrays
;;; -----------------------------------------------------------------------
(display "--- Group 3: Trailing [1] FAM Exemption (Lua Idiom) ---\n")

(let ((lir-fam (c99-compile-string-to-lir "
struct LuaStr { int len; char contents[1]; };
int read_ch(struct LuaStr *ts, int i) { return ts->contents[i]; }
" "fam.c" '((sanitize-bounds? . #t))))
      (lir-non-fam (c99-compile-string-to-lir "
struct NotFam { char fixed1[1]; int tail; };
int read_nf(struct NotFam *nf, int i) { return nf->fixed1[i]; }
" "non_fam.c" '((sanitize-bounds? . #t)))))
  (assert-true "3.1 Trailing [1] struct FAM does not emit C99-SAN-001 bounds check"
               (not (san-lir-walk-has? lir-fam (lambda (x) (and (string? x) (san-str-contains? x "C99-SAN-001"))))))
  (assert-true "3.2 Trailing [1] struct FAM still checks base pointer NULL (C99-SAN-002)"
               (san-lir-walk-has? lir-fam (lambda (x) (and (string? x) (san-str-contains? x "C99-SAN-002")))))
  (assert-true "3.3 Non-trailing [1] member DOES emit C99-SAN-001 bounds check"
               (san-lir-walk-has? lir-non-fam (lambda (x) (and (string? x) (san-str-contains? x "C99-SAN-001"))))))

;;; -----------------------------------------------------------------------
;;; Group 4: Reference VM Execution & Trap Verification
;;; -----------------------------------------------------------------------
(display "--- Group 4: Reference VM Execution & Trap Verification ---\n")

(let ((ok-res (san-eval-vm-outcome "
int main(void) {
    int arr[4] = {10, 20, 30, 40};
    int *p = &arr[0];
    int *endp = &arr[4];
    int sum = 0;
    while (p < endp) { sum += *p; p++; }
    return sum == 100 ? 0 : 1;
}
" #t)))
  (assert-equal "4.1 Valid bounds + &arr[N] sentinel loop passes on VM" '(ok 0) ok-res))

(let ((oob-pos (san-eval-vm-outcome "
int get(int *dummy, int idx) { int a[4] = {1,2,3,4}; return a[idx]; }
int main(void) { return get(0, 4); }
" #t)))
  (assert-true "4.2 Positive OOB arr[4] traps on VM with C99-SAN-001"
               (and (eq? (car oob-pos) 'trap)
                    (eq? (cadr oob-pos) 'sanitizer-trap)
                    (san-str-contains? (caddr oob-pos) "C99-SAN-001"))))

(let ((oob-neg (san-eval-vm-outcome "
int get(int idx) { int a[4] = {1,2,3,4}; return a[idx]; }
int main(void) { return get(-1); }
" #t)))
  (assert-true "4.3 Negative index arr[-1] traps on VM with C99-SAN-001"
               (and (eq? (car oob-neg) 'trap)
                    (eq? (cadr oob-neg) 'sanitizer-trap)
                    (san-str-contains? (caddr oob-neg) "C99-SAN-001"))))

(let ((oob-addr (san-eval-vm-outcome "
int *bad_addr(int idx) { static int a[4]; return &a[idx]; }
int main(void) { return bad_addr(5) != 0 ? 1 : 0; }
" #t)))
  (assert-true "4.4 &arr[N+1] traps on VM with C99-SAN-001"
               (and (eq? (car oob-addr) 'trap)
                    (eq? (cadr oob-addr) 'sanitizer-trap)
                    (san-str-contains? (caddr oob-addr) "C99-SAN-001"))))

(let ((null-deref (san-eval-vm-outcome "
int main(void) { int *p = 0; return *p; }
" #t)))
  (assert-true "4.5 NULL *p deref traps on VM with C99-SAN-002"
               (and (eq? (car null-deref) 'trap)
                    (eq? (cadr null-deref) 'sanitizer-trap)
                    (san-str-contains? (caddr null-deref) "C99-SAN-002"))))

(let ((null-mem (san-eval-vm-outcome "
struct S { int x; int y; };
int main(void) { struct S *s = 0; return s->y; }
" #t)))
  (assert-true "4.6 NULL s->y traps on VM with C99-SAN-002"
               (and (eq? (car null-mem) 'trap)
                    (eq? (cadr null-mem) 'sanitizer-trap)
                    (san-str-contains? (caddr null-mem) "C99-SAN-002"))))

(let ((null-sub (san-eval-vm-outcome "
int main(void) { int *p = 0; return p[0]; }
" #t)))
  (assert-true "4.7 NULL p[0] traps on VM with C99-SAN-002"
               (and (eq? (car null-sub) 'trap)
                    (eq? (cadr null-sub) 'sanitizer-trap)
                    (san-str-contains? (caddr null-sub) "C99-SAN-002"))))

(display "\n=== [Results: ")
(display (car *san-tests-passed*)) (display " passed, ")
(display (car *san-tests-failed*)) (display " failed] ===\n")
(if (> (car *san-tests-failed*) 0)
    (exit 1))
