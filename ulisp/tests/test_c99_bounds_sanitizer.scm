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

;;; -----------------------------------------------------------------------
;;; Group 5: CWE Differential Coverage Matrix against LIR VM Shadow Oracle (#963)
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Sanitizer vs LIR VM Shadow Oracle CWE Coverage Matrix ---\n")

(define (san-classify-cwe-case entry)
  (let* ((case-id (list-ref entry 0))
         (cwe-id  (list-ref entry 1))
         (desc    (list-ref entry 2))
         (unsafe? (list-ref entry 3))
         (src     (list-ref entry 6))
         (oracle-res (san-eval-vm-outcome src #f))
         (san-res    (san-eval-vm-outcome src #t))
         (oracle-trapped? (eq? (car oracle-res) 'trap))
         (san-trap? (and (eq? (car san-res) 'trap)
                         (eq? (cadr san-res) 'sanitizer-trap)))
         (cls
          (if (not unsafe?)
              (if (and (eq? (car oracle-res) 'ok)
                       (eq? (car san-res) 'ok)
                       (= (cadr oracle-res) 0)
                       (= (cadr san-res) 0))
                  'clean-pass
                  'false-positive)
              (cond
                ((and san-trap? oracle-trapped?) 'caught-both)
                (san-trap? 'sanitizer-only)
                ((eq? (car san-res) 'trap) 'gap-vm-only)
                (else 'missed-by-both)))))
    (list case-id
          cwe-id
          desc
          cls
          (if oracle-trapped? (cadr oracle-res) 'ok)
          (if (eq? (car san-res) 'trap) (cadr san-res) 'ok)
          (if (and (eq? (car san-res) 'trap) (pair? (cddr san-res)))
              (caddr san-res)
              ""))))

(define *san-cwe-coverage-suite*
  (list
    ;; CWE-121 / CWE-125 / CWE-787: Static / Stack Array Bounds (Sanitizer-Only vs VM)
    (list "CWE121_01_stack_pos_oob" "CWE-121" "Stack array positive OOB a[4]"
          #t 'sanitizer-only 'ok
          "int get(int i) { int a[4] = {1,2,3,4}; return a[i]; }\nint main(void) { return get(4); }\n")
    (list "CWE121_02_stack_neg_oob" "CWE-121" "Stack array negative index a[-1]"
          #t 'sanitizer-only 'ok
          "int get(int i) { int a[4] = {1,2,3,4}; return a[i]; }\nint main(void) { return get(-1); }\n")
    (list "CWE121_03_static_addr_oob" "CWE-121" "Static array address &a[5] OOB"
          #t 'sanitizer-only 'ok
          "int *addr(int i) { static int a[4]; return &a[i]; }\nint main(void) { return addr(5) != 0 ? 1 : 0; }\n")

    ;; CWE-476: NULL Pointer Dereference
    (list "CWE476_01_null_deref" "CWE-476" "Direct NULL *p dereference"
          #t 'caught-both 'out-of-bounds
          "int main(void) { int *p = 0; return *p; }\n")
    (list "CWE476_02_null_member" "CWE-476" "NULL struct member s->y"
          #t 'caught-both 'out-of-bounds
          "struct S { int x; int y; };\nint main(void) { struct S *s = 0; return s->y; }\n")
    (list "CWE476_03_null_subscript" "CWE-476" "NULL subscript p[0]"
          #t 'caught-both 'out-of-bounds
          "int main(void) { int *p = 0; return p[0]; }\n")
    (list "CWE476_04_libc_strlen_null" "CWE-476" "Libc strlen(NULL)"
          #t 'gap-vm-only 'out-of-bounds
          "#include <string.h>\nint main(void) { return (int)strlen((const char *)0); }\n")

    ;; CWE-122: Heap-based Buffer Overflow / Underflow (First-Projection Gap)
    (list "CWE122_01_heap_1byte_tail_oob" "CWE-122" "malloc(5) 1-byte tail read p[5]"
          #t 'gap-vm-only 'heap-out-of-bounds
          "#include <stdlib.h>\nint main(void) { char *p = (char *)malloc(5); p[4] = 'a'; return (unsigned char)p[5]; }\n")
    (list "CWE122_02_heap_neg_underflow" "CWE-122" "malloc(16) underflow p[-1] = 1"
          #t 'gap-vm-only 'heap-out-of-bounds
          "#include <stdlib.h>\nint main(void) { int *p = (int *)malloc(16); p[-1] = 1; return 0; }\n")
    (list "CWE122_03_calloc_elem_oob" "CWE-122" "calloc(4, int) element OOB p[4]"
          #t 'gap-vm-only 'heap-out-of-bounds
          "#include <stdlib.h>\nint main(void) { int *p = (int *)calloc(4, sizeof(int)); return p[4]; }\n")
    (list "CWE122_04_strcpy_heap_overflow" "CWE-122" "strcpy into malloc(4)"
          #t 'gap-vm-only 'heap-out-of-bounds
          "#include <stdlib.h>\n#include <string.h>\nint main(void) { char *p = (char *)malloc(4); strcpy(p, \"hello\"); return 0; }\n")

    ;; CWE-416: Use After Free (First-Projection Gap)
    (list "CWE416_01_uaf_after_free" "CWE-416" "Read *p after free(p)"
          #t 'gap-vm-only 'use-after-free
          "#include <stdlib.h>\nint main(void) { int *p = (int *)malloc(8); *p = 7; free(p); return *p; }\n")
    (list "CWE416_02_uaf_after_realloc" "CWE-416" "Read old ptr after realloc"
          #t 'gap-vm-only 'use-after-free
          "#include <stdlib.h>\nint main(void) { char *p = (char *)malloc(8); p[0] = 3; char *q = (char *)realloc(p, 32); (void)q; return p[0]; }\n")

    ;; CWE-415: Double Free (First-Projection Gap)
    (list "CWE415_01_double_free" "CWE-415" "Duplicate free(p)"
          #t 'gap-vm-only 'double-free
          "#include <stdlib.h>\nint main(void) { void *p = malloc(16); free(p); free(p); return 0; }\n")

    ;; CWE-590: Invalid Free (First-Projection Gap)
    (list "CWE590_01_free_stack_ptr" "CWE-590" "free(&stack_var)"
          #t 'gap-vm-only 'invalid-free
          "#include <stdlib.h>\nint main(void) { int x = 1; free(&x); return 0; }\n")
    (list "CWE590_02_free_interior_ptr" "CWE-590" "free(p + 4) interior pointer"
          #t 'gap-vm-only 'invalid-free
          "#include <stdlib.h>\nint main(void) { char *p = (char *)malloc(16); free(p + 4); return 0; }\n")

    ;; Negative Controls (Valid Programs -> Zero False Positives)
    (list "NEG_01_sentinel_loop" "Negative" "Valid array + &arr[N] sentinel loop"
          #f 'clean-pass 'ok
          "int main(void) { int a[4] = {1,2,3,4}; int *p = &a[0]; int *e = &a[4]; int s = 0; while (p < e) s += *p++; return s == 10 ? 0 : 1; }\n")
    (list "NEG_02_lua_trailing_fam_heap" "Negative" "Heap-allocated Lua trailing [1] FAM"
          #f 'clean-pass 'ok
          "#include <stdlib.h>\nstruct TString { int len; char s[1]; };\nint main(void) { struct TString *ts = (struct TString *)malloc(sizeof(struct TString) + 8); ts->len = 6; ts->s[5] = 42; int ok = (ts->s[5] == 42) ? 0 : 1; free(ts); return ok; }\n")
    (list "NEG_03_valid_heap_lifecycle" "Negative" "Valid calloc/realloc/free(NULL) lifecycle"
          #f 'clean-pass 'ok
          "#include <stdlib.h>\nint main(void) { free((void *)0); char *p = (char *)calloc(2, 4); p[0] = 5; char *q = (char *)realloc(p, 16); q[15] = 9; int ok = (q[0] == 5 && q[15] == 9) ? 0 : 1; free(q); return ok; }\n")))

(let ((unsafe-cnt-box   (cons 0 '()))
      (san-cnt-box      (cons 0 '()))
      (both-cnt-box     (cons 0 '()))
      (san-only-cnt-box (cons 0 '()))
      (gap-cnt-box      (cons 0 '()))
      (neg-cnt-box      (cons 0 '()))
      (fp-cnt-box       (cons 0 '())))
  (for-each
    (lambda (entry)
      (let* ((case-id        (list-ref entry 0))
             (cwe-id         (list-ref entry 1))
             (desc           (list-ref entry 2))
             (unsafe?        (list-ref entry 3))
             (exp-class      (list-ref entry 4))
             (exp-oracle     (list-ref entry 5))
             (res            (san-classify-cwe-case entry))
             (actual-class   (list-ref res 3))
             (oracle-detail  (list-ref res 4))
             (san-detail     (list-ref res 5))
             (diag-msg       (list-ref res 6)))
        (display "  [") (display cwe-id) (display "] ")
        (display case-id) (display " => ")
        (display actual-class)
        (display " (oracle=") (display oracle-detail)
        (display ", san=") (display san-detail) (display ")\n")
        (if unsafe?
            (begin
              (set-car! unsafe-cnt-box (+ (car unsafe-cnt-box) 1))
              (if (or (eq? actual-class 'caught-both) (eq? actual-class 'sanitizer-only))
                  (set-car! san-cnt-box (+ (car san-cnt-box) 1)))
              (if (eq? actual-class 'caught-both)
                  (set-car! both-cnt-box (+ (car both-cnt-box) 1)))
              (if (eq? actual-class 'sanitizer-only)
                  (set-car! san-only-cnt-box (+ (car san-only-cnt-box) 1)))
              (if (eq? actual-class 'gap-vm-only)
                  (set-car! gap-cnt-box (+ (car gap-cnt-box) 1))))
            (begin
              (set-car! neg-cnt-box (+ (car neg-cnt-box) 1))
              (if (not (eq? actual-class 'clean-pass))
                  (set-car! fp-cnt-box (+ (car fp-cnt-box) 1)))))
        (assert-equal (string-append "5.x " case-id " class matches baseline")
                      exp-class actual-class)
        (assert-equal (string-append "5.x " case-id " oracle outcome matches")
                      exp-oracle oracle-detail)
        (if (or (eq? actual-class 'caught-both) (eq? actual-class 'sanitizer-only))
            (assert-true (string-append "5.x " case-id " includes source-span diagnostics")
                         (and (san-str-contains? diag-msg "san_vm_test.c:")
                              (or (san-str-contains? diag-msg "C99-SAN-001")
                                  (san-str-contains? diag-msg "C99-SAN-002")))))))
    *san-cwe-coverage-suite*)
  (display "\n=== [Sanitizer vs LIR VM Oracle Summary (#963)] ===\n")
  (display "  Unsafe Total               : ") (display (car unsafe-cnt-box)) (newline)
  (display "  Sanitizer Caught (Total)   : ") (display (car san-cnt-box)) (newline)
  (display "    - Caught by Both         : ") (display (car both-cnt-box)) (newline)
  (display "    - Sanitizer-Only (Stack) : ") (display (car san-only-cnt-box)) (newline)
  (display "  VM-Only Oracle (Gap)       : ") (display (car gap-cnt-box)) (newline)
  (display "  Negative Controls          : ") (display (car neg-cnt-box)) (newline)
  (display "  False Positives            : ") (display (car fp-cnt-box)) (newline)
  (assert-equal "5.S1 Unsafe benchmark total is 16" 16 (car unsafe-cnt-box))
  (assert-equal "5.S2 Sanitizer baseline catches 6/16" 6 (car san-cnt-box))
  (assert-equal "5.S3 Caught by Both (NULL direct) = 3" 3 (car both-cnt-box))
  (assert-equal "5.S4 Sanitizer-Only (CWE-121 stack/static) = 3" 3 (car san-only-cnt-box))
  (assert-equal "5.S5 VM-only First-Projection gaps = 10/16" 10 (car gap-cnt-box))
  (assert-equal "5.S6 Negative controls total is 3" 3 (car neg-cnt-box))
  (assert-equal "5.S7 Zero false positives on negative controls" 0 (car fp-cnt-box)))

(display "\n=== [Results: ")
(display (car *san-tests-passed*)) (display " passed, ")
(display (car *san-tests-failed*)) (display " failed] ===\n")
(if (> (car *san-tests-failed*) 0)
    (exit 1))
