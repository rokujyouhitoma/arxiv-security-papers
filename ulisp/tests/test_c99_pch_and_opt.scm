;;; =======================================================================
;;; ULisp C99 PCH (.sbi v2) & -O2 Iterative Optimization Verification Suite
;;; Issue #927
;;; Verifies:
;;;   1. WP1: .sbi PCH serialization/deserialization (macros, typedefs,
;;;      struct/union/bitfield/enum layouts, <source-span>, <binding>, deps)
;;;   2. Determinism: L_c_typed & L_lir_core identical with/without -include-pch
;;;   3. WP2: "C99-PCH-001" warning + safe fallback (-D mismatch / stale dep)
;;;      and "C99-PCH-002" error + abort (missing / corrupt .sbi)
;;;   4. WP3: -O2 iterative PassManager fixpoint (mem2reg + branch fusion
;;;      + peephole) reduces instructions & preserves exact VM semantics
;;;      across leaf, branching, narrow types, escaped locals, setjmp & stack args
;;; =======================================================================

(define *tpo-pass* (cons 0 '()))
(define *tpo-fail* (cons 0 '()))

(define (tpo-assert-true name pred)
  (if pred
      (begin
        (set-car! *tpo-pass* (+ (car *tpo-pass*) 1))
        (display "  [PASS] ") (display name) (newline))
      (begin
        (set-car! *tpo-fail* (+ (car *tpo-fail*) 1))
        (display "  [FAIL] ") (display name) (newline))))

(define (tpo-assert-equal name expected actual)
  (if (equal? expected actual)
      (begin
        (set-car! *tpo-pass* (+ (car *tpo-pass*) 1))
        (display "  [PASS] ") (display name) (newline))
      (begin
        (set-car! *tpo-fail* (+ (car *tpo-fail*) 1))
        (display "  [FAIL] ") (display name)
        (display " expected=") (write expected)
        (display " actual=") (write actual)
        (newline))))

(define (tpo-write-file path content)
  (let ((p (open-output-file path)))
    (write-string content p)
    (close-output-port p)))

(define (tpo-find-fn lir name)
  (let* ((fns (cdr (assq '%lir-functions (cdr lir)))))
    (let loop ((xs fns))
      (cond
        ((null? xs) #f)
        ((eq? (cadr (car xs)) name) (car xs))
        (else (loop (cdr xs)))))))

(define (tpo-fn-inst-count fn)
  (length (cdr (assq 'body (cddr fn)))))

(define (tpo-fn-rsp-mem-count fn)
  (let ((body (cdr (assq 'body (cddr fn)))))
    (let loop ((xs body) (n 0))
      (if (null? xs)
          n
          (let ((i (car xs)))
            (if (and (pair? i)
                     (or (and (memq (car i) '(%load %load-byte-zx)) (eq? (caddr i) '%rsp))
                         (and (eq? (car i) '%load-typed) (eq? (cadddr i) '%rsp))
                         (and (memq (car i) '(%store %store-byte)) (eq? (cadr i) '%rsp))
                         (and (eq? (car i) '%store-typed) (eq? (caddr i) '%rsp))))
                (loop (cdr xs) (+ n 1))
                (loop (cdr xs) n)))))))

(define (tpo-total-inst-count lir)
  (let* ((fns (cdr (assq '%lir-functions (cdr lir))))
         (main-b (cdr (assq 'body (cdr (assq '%lir-main (cdr lir)))))))
    (let loop ((fs fns) (acc (length main-b)))
      (if (null? fs)
          acc
          (loop (cdr fs) (+ acc (tpo-fn-inst-count (car fs))))))))

(define (tpo-run-vm lir)
  (let ((res (eval-lir-program lir)))
    (if (integer? res) res res)))

(display "========================================================================\n")
(display " C99 .sbi PCH & -O2 Iterative Optimization Verification Suite (#927)\n")
(display "========================================================================\n")

(let* ((tmp-dir "build/test_c99_pch_opt_scm_tmp")
       (hdr-sub (string-append tmp-dir "/sub_hdr.h"))
       (hdr-main (string-append tmp-dir "/hdr1.h"))
       (hdr-macros (string-append tmp-dir "/macros_only.h"))
       (pch-main (string-append tmp-dir "/hdr1.h.sbi"))
       (pch-macros (string-append tmp-dir "/macros_only.h.sbi"))
       (pch-corrupt (string-append tmp-dir "/corrupt.sbi"))
       (pch-badmagic (string-append tmp-dir "/badmagic.sbi"))
       (tu1 (string-append tmp-dir "/tu1.c"))
       (tu2 (string-append tmp-dir "/tu2.c"))
       (tu-mac (string-append tmp-dir "/tu_mac.c"))
       (opt-c (string-append tmp-dir "/opt_test.c")))
  (process-exec (list "rm" "-rf" tmp-dir))
  (process-exec (list "mkdir" "-p" tmp-dir))

  (tpo-write-file hdr-sub
    (string-append
     "#ifndef SUB_HDR_H\n#define SUB_HDR_H\n"
     "#define SUB_MULT 3\n"
     "typedef unsigned int u32_alias;\n"
     "enum Kind { K_A = 10, K_B, K_C = 42 };\n"
     "#endif\n"))

  (tpo-write-file hdr-main
    (string-append
     "#ifndef HDR1_H\n#define HDR1_H\n"
     "#include <stdio.h>\n"
     "#include <stdint.h>\n"
     "#include \"sub_hdr.h\"\n"
     "#define SQUARE(x) ((x) * (x))\n"
     "#define PICK_LINE(base) ((base) + __LINE__)\n"
     "#ifndef FOO_VAL\n#define FOO_VAL 1\n#endif\n"
     "typedef struct FwdNode FwdNode;\n"
     "typedef struct { int id; unsigned flags : 3; signed mode : 5; } Rec;\n"
     "union NumBox { int i; double d; };\n"
     "extern int tentative_arr[];\n"
     "int helper_proto(int x);\n"
     "#endif\n"))

  (tpo-write-file hdr-macros
    (string-append
     "#ifndef MACROS_ONLY_H\n#define MACROS_ONLY_H\n"
     "#define MAGIC_OFFSET 17\n"
     "#endif\n"))

  ;; -------------------------------------------------------------------
  ;; Group 1: PCH Emission & Transitive Dependency Tracking (WP1)
  ;; -------------------------------------------------------------------
  (display "\n--- Group 1: WP1 C99 .sbi PCH Emission & Dependency Table ---\n")
  (let* ((emit-opts (parse-c-driver-args (list "-DFOO_VAL=7" "-emit-pch" hdr-main "-o" pch-main)))
         (out-p (c99-emit-pch-file hdr-main pch-main emit-opts))
         (v-res (sbi-read-pch-validated pch-main)))
    (tpo-assert-equal "1.1 c99-emit-pch-file returns output path" pch-main out-p)
    (tpo-assert-true "1.2 .sbi PCH file has USBI v2 magic" (sbi-binary-file? pch-main))
    (tpo-assert-equal "1.3 sbi-read-pch-validated status == 'ok" 'ok (car v-res))
    (let* ((deps (caddr v-res))
           (dep-paths (map (lambda (d) (car d)) deps)))
      (tpo-assert-true "1.4 PCH deps include main header" (if (member hdr-main dep-paths) #t #f))
      (tpo-assert-true "1.5 PCH deps include transitive header sub_hdr.h" (if (member hdr-sub dep-paths) #t #f))))

  ;; Macro-only header PCH (0 external declarations)
  (let ((emit-m-opts (parse-c-driver-args (list "-emit-pch" hdr-macros "-o" pch-macros))))
    (c99-emit-pch-file hdr-macros pch-macros emit-m-opts)
    (tpo-assert-true "1.6 macro-only header produces valid .sbi PCH" (sbi-binary-file? pch-macros)))

  ;; -------------------------------------------------------------------
  ;; Group 2: Bit-Identical LIR Determinism (With vs Without -include-pch)
  ;; -------------------------------------------------------------------
  (display "\n--- Group 2: Determinism & LIR Equality With vs Without PCH ---\n")
  (tpo-write-file tu1
    (string-append
     "#include \"hdr1.h\"\n"
     "struct FwdNode { int key; FwdNode *next; };\n"
     "int tentative_arr[3] = { 1, 2, 3 };\n"
     "static int s_helper(int v) { return v * SUB_MULT + FOO_VAL; }\n"
     "int helper_proto(int x) {\n"
     "  Rec r;\n"
     "  union NumBox u;\n"
     "  r.id = x;\n"
     "  r.flags = 5U;\n"
     "  r.mode = -3;\n"
     "  u.i = (int)(r.id + (int)r.flags + r.mode + K_C);\n"
     "  return SQUARE(2) + s_helper(u.i) + tentative_arr[2];\n"
     "}\n"
     "int main(void) {\n"
     "  struct FwdNode fn;\n"
     "  fn.key = helper_proto(4);\n"
     "  fn.next = (FwdNode *)0;\n"
     "  return fn.key + PICK_LINE(0);\n"
     "}\n"))

  (tpo-write-file tu2
    (string-append
     "#include \"hdr1.h\"\n"
     "struct FwdNode { int other_field; int extra; };\n"
     "int main(void) {\n"
     "  u32_alias a = (u32_alias)K_B;\n"
     "  struct FwdNode n;\n"
     "  n.other_field = (int)a;\n"
     "  n.extra = FOO_VAL;\n"
     "  return n.other_field * n.extra + SQUARE(3);\n"
     "}\n"))

  (tpo-write-file tu-mac
    (string-append
     "#include \"macros_only.h\"\n"
     "int main(void) { return MAGIC_OFFSET + 25; }\n"))

  (let* ((opts-nopch (parse-c-driver-args (list "-O2" "--target=vm" "-DFOO_VAL=7" "-c" tu1)))
         (opts-pch   (parse-c-driver-args (list "-O2" "--target=vm" "-DFOO_VAL=7" "-include-pch" pch-main "-c" tu1)))
         (lir-nopch  (c99-compile-file-to-lir tu1 opts-nopch))
         (lir-pch    (c99-compile-file-to-lir tu1 opts-pch))
         (vm-nopch   (tpo-run-vm lir-nopch))
         (vm-pch     (tpo-run-vm lir-pch)))
    (tpo-assert-equal "2.1 L_lir_core is 100% equal? with and without -include-pch" lir-nopch lir-pch)
    (tpo-assert-equal "2.2 VM return value matches identically with and without PCH" vm-nopch vm-pch))

  ;; Multi-TU batch isolation test (tu1 completed FwdNode with {key, next}; tu2 completes FwdNode differently)
  (c99-with-pch-batch-cache
   (lambda ()
     (let* ((o1 (parse-c-driver-args (list "-O2" "--target=vm" "-DFOO_VAL=7" "-include-pch" pch-main "-c" tu1)))
            (o2 (parse-c-driver-args (list "-O2" "--target=vm" "-DFOO_VAL=7" "-include-pch" pch-main "-c" tu2)))
            (l1 (c99-compile-file-to-lir tu1 o1))
            (l2 (c99-compile-file-to-lir tu2 o2)))
       (tpo-assert-equal "2.3 batch cache isolates FwdNode completion across tu1 & tu2" (+ (* 11 7) 9) (tpo-run-vm l2))
       (tpo-assert-equal "2.4 tu1 under batch cache keeps identical VM output" (tpo-run-vm l1) (tpo-run-vm (c99-compile-file-to-lir tu1 o1))))))

  (let* ((om-no (parse-c-driver-args (list "-O2" "--target=vm" "-c" tu-mac)))
         (om-pch (parse-c-driver-args (list "-O2" "--target=vm" "-include-pch" pch-macros "-c" tu-mac))))
    (tpo-assert-equal "2.5 macro-only PCH yields identical LIR & VM value (42)"
                      (c99-compile-file-to-lir tu-mac om-no)
                      (c99-compile-file-to-lir tu-mac om-pch))
    (tpo-assert-equal "2.6 macro-only PCH executes to 42" 42 (tpo-run-vm (c99-compile-file-to-lir tu-mac om-pch))))

  ;; -------------------------------------------------------------------
  ;; Group 3: Diagnostics C99-PCH-001 (Fallback) & C99-PCH-002 (Reject)
  ;; -------------------------------------------------------------------
  (display "\n--- Group 3: Diagnostics C99-PCH-001 (Warning+Fallback) & C99-PCH-002 (Error) ---\n")
  (let* ((w0 (car *diagnostic-warning-count*))
         (opts-mismatch (parse-c-driver-args (list "-O2" "--target=vm" "-DFOO_VAL=99" "-include-pch" pch-main "-c" tu2)))
         (lir-fb (c99-compile-file-to-lir tu2 opts-mismatch))
         (w1 (car *diagnostic-warning-count*)))
    (tpo-assert-true "3.1 -DFOO_VAL mismatch emits C99-PCH-001 warning" (> w1 w0))
    (tpo-assert-equal "3.2 fallback full compilation uses new -DFOO_VAL=99" (+ (* 11 99) 9) (tpo-run-vm lir-fb)))

  ;; Modify sub_hdr.h -> stale dependency must warn & fall back cleanly
  (tpo-write-file hdr-sub
    (string-append
     "#ifndef SUB_HDR_H\n#define SUB_HDR_H\n"
     "#define SUB_MULT 5\n"
     "typedef unsigned int u32_alias;\n"
     "enum Kind { K_A = 10, K_B = 20, K_C = 42 };\n"
     "#endif\n"))
  (let* ((w0 (car *diagnostic-warning-count*))
         (opts-stale (parse-c-driver-args (list "-O2" "--target=vm" "-DFOO_VAL=7" "-include-pch" pch-main "-c" tu2)))
         (lir-stale (c99-compile-file-to-lir tu2 opts-stale))
         (w1 (car *diagnostic-warning-count*)))
    (tpo-assert-true "3.3 stale header dep SHA-256 emits C99-PCH-001 warning" (> w1 w0))
    (tpo-assert-equal "3.4 stale PCH falls back to updated header (K_B=20 -> 149)" (+ (* 20 7) 9) (tpo-run-vm lir-stale)))

  ;; Restore sub_hdr.h
  (tpo-write-file hdr-sub
    (string-append
     "#ifndef SUB_HDR_H\n#define SUB_HDR_H\n"
     "#define SUB_MULT 3\n"
     "typedef unsigned int u32_alias;\n"
     "enum Kind { K_A = 10, K_B, K_C = 42 };\n"
     "#endif\n"))

  ;; C99-PCH-002 missing file
  (let ((caught-miss-box (cons #f '())))
    (guard (ex (else (set-car! caught-miss-box ex)))
      (c99-compile-file-to-lir tu1 (parse-c-driver-args (list "-include-pch" (string-append tmp-dir "/missing.sbi") "-c" tu1))))
    (let ((cm (car caught-miss-box)))
      (tpo-assert-true "3.5 missing .sbi raises c99-driver-error C99-PCH-002"
                       (and (pair? cm) (eq? (car cm) 'c99-driver-error)
                            (string=? (cadr cm) "C99-PCH-002")))))

  ;; C99-PCH-002 1-byte corrupted payload -> SHA-256 rejection
  (let* ((orig-bv (sbi-read-file-bytes pch-main))
         (bad-bv (bytevector-copy orig-bv))
         (last-i (- (bytevector-length bad-bv) 1)))
    (bytevector-u8-set! bad-bv last-i (modulo (+ (bytevector-u8-ref bad-bv last-i) 1) 256))
    (sbi-write-file-bytes pch-corrupt bad-bv)
    (let ((caught-corr-box (cons #f '())))
      (guard (ex (else (set-car! caught-corr-box ex)))
        (c99-compile-file-to-lir tu1 (parse-c-driver-args (list "-include-pch" pch-corrupt "-c" tu1))))
      (let ((cc (car caught-corr-box)))
        (tpo-assert-true "3.6 corrupted .sbi SHA-256 rejected with C99-PCH-002"
                         (and (pair? cc) (eq? (car cc) 'c99-driver-error)
                              (string=? (cadr cc) "C99-PCH-002"))))))

  ;; C99-PCH-002 invalid magic header
  (tpo-write-file pch-badmagic "NOT_AN_SBI_PCH_FILE_AT_ALL_123456789012345678901234567890")
  (let ((caught-mag-box (cons #f '())))
    (guard (ex (else (set-car! caught-mag-box ex)))
      (c99-compile-file-to-lir tu1 (parse-c-driver-args (list "-include-pch" pch-badmagic "-c" tu1))))
    (let ((cm (car caught-mag-box)))
      (tpo-assert-true "3.7 invalid magic .sbi rejected with C99-PCH-002"
                       (and (pair? cm) (eq? (car cm) 'c99-driver-error)
                            (string=? (cadr cm) "C99-PCH-002")))))

  ;; -------------------------------------------------------------------
  ;; Group 4: WP3 -O2 Iterative Pipeline (mem2reg + Branch Fusion + Peephole)
  ;; -------------------------------------------------------------------
  (display "\n--- Group 4: WP3 -O2 Iterative Pipeline & Safety Invariants ---\n")
  (tpo-write-file opt-c
    (string-append
     "#include <setjmp.h>\n"
     "int leaf_sum(int n) {\n"
     "  int s = 0;\n"
     "  int i = 1;\n"
     "  while (i <= n) {\n"
     "    s += i;\n"
     "    i++;\n"
     "  }\n"
     "  return s;\n"
     "}\n"
     "int cmp_logic(int x, int y) {\n"
     "  if ((x > 0 && x < 100) || y == 42) {\n"
     "    return (x == 50) ? 100 : 10;\n"
     "  }\n"
     "  return 1;\n"
     "}\n"
     "int fold_bits(int x) {\n"
     "  int t = (1 << 4) | 3;\n"
     "  int u = -(-5);\n"
     "  return x + t + u;\n"
     "}\n"
     "int narrow_args(unsigned char uc, signed char sc, unsigned short us, short ss, unsigned int ui, int si) {\n"
     "  int a = (int)uc + (int)sc + (int)us + (int)ss;\n"
     "  return a + (int)(ui & 255U) + si;\n"
     "}\n"
     "static void bump_ptr(int *p) { *p += 7; }\n"
     "int escaped_addr(int x) {\n"
     "  int v = x + 3;\n"
     "  bump_ptr(&v);\n"
     "  return v * 2;\n"
     "}\n"
     "int stack_args8(int a, int b, int c, int d, int e, int f, int g, int h) {\n"
     "  return a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7 + h * 8;\n"
     "}\n"
     "int call_stack_args8(int base) {\n"
     "  return stack_args8(base, 2, 3, 4, 5, 6, 7, 8);\n"
     "}\n"
     "int setjmp_test(int n) {\n"
     "  jmp_buf env;\n"
     "  int x = n + 10;\n"
     "  if (setjmp(env) == 0) {\n"
     "    x += 5;\n"
     "    longjmp(env, 1);\n"
     "  }\n"
     "  return x;\n"
     "}\n"
     "int main(void) {\n"
     "  return leaf_sum(10) + cmp_logic(50, 0) + cmp_logic(-1, 42) + cmp_logic(-1, 0)\n"
     "       + fold_bits(5) + narrow_args((unsigned char)250, (signed char)-5, (unsigned short)60000, (short)-100, 300U, 9)\n"
     "       + escaped_addr(10) + call_stack_args8(1) + setjmp_test(7);\n"
     "}\n"))

  (let* ((lir-o0 (c99-compile-file-to-lir opt-c (parse-c-driver-args (list "-O0" "--target=vm" "-c" opt-c))))
         (lir-o1 (c99-compile-file-to-lir opt-c (parse-c-driver-args (list "-O1" "--target=vm" "-c" opt-c))))
         (lir-o2 (c99-compile-file-to-lir opt-c (parse-c-driver-args (list "-O2" "--target=vm" "-c" opt-c))))
         (stats (analysis-cache-stats))
         (recomps (let ((p (assq 'recomputations stats))) (if p (cdr p) 0)))
         (invs (let ((p (assq 'invalidations stats))) (if p (cdr p) 0)))
         (tot0 (tpo-total-inst-count lir-o0))
         (tot1 (tpo-total-inst-count lir-o1))
         (tot2 (tpo-total-inst-count lir-o2))
         (leaf0 (tpo-fn-rsp-mem-count (tpo-find-fn lir-o0 'leaf_sum)))
         (leaf2 (tpo-fn-rsp-mem-count (tpo-find-fn lir-o2 'leaf_sum)))
         (cmp1 (tpo-fn-inst-count (tpo-find-fn lir-o1 'cmp_logic)))
         (cmp2 (tpo-fn-inst-count (tpo-find-fn lir-o2 'cmp_logic)))
         (v0 (tpo-run-vm lir-o0))
         (v1 (tpo-run-vm lir-o1))
         (v2 (tpo-run-vm lir-o2)))
    (tpo-assert-true "4.1 -O2 PassManager fixpoint converges" (last-fixpoint-converged?))
    (tpo-assert-true "4.2 -O2 fixpoint bounded (<= 4 iterations)" (<= (last-fixpoint-iterations) 4))
    (tpo-assert-true "4.3 PassManager recorded analysis recomputations & invalidations" (and (> recomps 0) (> invs 0)))
    (tpo-assert-true "4.4 -O2 reduces total LIR instructions vs -O1 and -O0" (and (< tot2 tot1) (< tot1 tot0)))
    (tpo-assert-equal "4.5 leaf_sum mem2reg eliminates ALL [rsp] loads/stores at -O2" 0 leaf2)
    (tpo-assert-true "4.6 leaf_sum had stack accesses before -O2" (> leaf0 0))
    (tpo-assert-true "4.7 cmp_logic branch fusion reduces instructions (-O2 < -O1)" (< cmp2 cmp1))
    (tpo-assert-equal "4.8 -O0 and -O1 VM results match" v0 v1)
    (tpo-assert-equal "4.9 -O0 and -O2 VM results match (narrow/escape/setjmp/8args sound!)" v0 v2))

  (process-exec (list "rm" "-rf" tmp-dir)))

(newline)
(display "========================================================================\n")
(display " C99 PCH & -O2 Opt Suite (#927): ")
(display (car *tpo-pass*)) (display " passed, ")
(display (car *tpo-fail*)) (display " failed.\n")
(display "========================================================================\n")
(if (> (car *tpo-fail*) 0) (exit 1) (exit 0))
