;;; =======================================================================
;;; ULisp C99 Determinism & Reproducibility Unit Test Suite (Issue #929)
;;; Tests:
;;;   1. Single-TU repeated ELF64 object byte-identity
;;;   2. Multi-TU reverse-order batch compilation determinism
;;;   3. -ffile-prefix-map __FILE__ normalization across distinct dirs
;;;   4. Deterministic __DATE__ / __TIME__ builtins & epoch formatter
;;;   5. Pass 144 static ELF64 linking determinism & zero-filled padding
;;;   6. Invalid -ffile-prefix-map CLI diagnostics (C99-DRV-002)
;;; Zero local `set!` (ULisp AOT safe).
;;; =======================================================================

(display "=== [Test Suite: C99 Determinism & Reproducible ELF64 Builds (#929)] ===\n")

(define (ddc-read-file-bytes path)
  (let ((p (open-binary-input-file path)))
    (let loop ((acc '()))
      (let ((b (read-u8 p)))
        (if (eof-object? b)
            (begin
              (close-input-port p)
              (reverse acc))
            (loop (cons b acc)))))))

(define (ddc-bytevector->list bv)
  (let ((n (bytevector-length bv)))
    (let loop ((i 0) (acc '()))
      (if (>= i n)
          (reverse acc)
          (loop (+ i 1) (cons (bytevector-u8-ref bv i) acc))))))

(define (ddc-write-text path txt)
  (let ((p (open-output-file path)))
    (write-string txt p)
    (close-output-port p)))

(define (ddc-string-contains? hay needle)
  (let ((hlen (string-length hay))
        (nlen (string-length needle)))
    (if (= nlen 0)
        #t
        (let loop ((i 0))
          (if (> (+ i nlen) hlen)
              #f
              (if (string=? (substring hay i (+ i nlen)) needle)
                  #t
                  (loop (+ i 1))))))))

;; -----------------------------------------------------------------------
;; Group 1: Single-TU Repeated Compilation Byte-Identity
;; -----------------------------------------------------------------------
(display "\n--- Group 1: Single-TU Repeated Compilation Byte-Identity ---\n")

(let ((src-a "build/test_c_ddc/dir_a/alpha.c"))
  (ddc-write-text
   src-a
   (string-append
    "static int helper_fn(int x) {\n"
    "  switch (x & 3) {\n"
    "    case 0: return x + 10;\n"
    "    case 1: return x * 3;\n"
    "    default: return x - 1;\n"
    "  }\n"
    "}\n"
    "double mix_fp(double a, double b) { return a * 1.5 + b; }\n"
    "int entry_alpha(int v) {\n"
    "  const char *msg = \"alpha_const\";\n"
    "  return helper_fn(v) + (int)msg[0];\n"
    "}\n"))
  (let* ((opts (parse-c-driver-args (list "-O2" "-c" src-a)))
         (lir1 (c99-compile-file-to-lir src-a opts))
         (bv1  (build-x86-64-elf-obj lir1 'c-tu))
         (lir2 (c99-compile-file-to-lir src-a opts))
         (bv2  (build-x86-64-elf-obj lir2 'c-tu)))
    (assert-true "1.1 Single-TU non-empty ELF64 output" (> (bytevector-length bv1) 64))
    (assert-equal "1.2 Repeated Single-TU compilation produces identical ELF64 bytes"
                  (ddc-bytevector->list bv1)
                  (ddc-bytevector->list bv2))))

;; -----------------------------------------------------------------------
;; Group 2: Multi-TU Reverse-Order Batch Compilation Determinism
;; -----------------------------------------------------------------------
(display "\n--- Group 2: Multi-TU Reverse-Order Batch Determinism ---\n")

(let ((src-a "build/test_c_ddc/dir_a/alpha.c")
      (src-b "build/test_c_ddc/dir_a/beta.c")
      (out1-dir "build/test_c_ddc/dir_a/out1/")
      (out2-dir "build/test_c_ddc/dir_a/out2/"))
  (ddc-write-text
   src-b
   (string-append
    "extern int entry_alpha(int v);\n"
    "static const char *tag = \"beta_tag\";\n"
    "int main(void) {\n"
    "  int a = entry_alpha(5);\n"
    "  return (tag[0] == 'b') ? (a - 97) : 1;\n"
    "}\n"))
  (c-driver-main (list "-O2" "-c" "-o" out1-dir src-a src-b))
  (c-driver-main (list "-O2" "-c" "-o" out2-dir src-b src-a))
  (assert-equal "2.1 Batch alpha.o identical regardless of TU order (A,B vs B,A)"
                (ddc-read-file-bytes (string-append out1-dir "alpha.o"))
                (ddc-read-file-bytes (string-append out2-dir "alpha.o")))
  (assert-equal "2.2 Batch beta.o identical regardless of TU order (A,B vs B,A)"
                (ddc-read-file-bytes (string-append out1-dir "beta.o"))
                (ddc-read-file-bytes (string-append out2-dir "beta.o"))))

;; -----------------------------------------------------------------------
;; Group 3: -ffile-prefix-map __FILE__ Normalization Across Distinct Dirs
;; -----------------------------------------------------------------------
(display "\n--- Group 3: -ffile-prefix-map Cross-Dir __FILE__ Bit-Identity ---\n")

(let* ((file-a "build/test_c_ddc/dir_a/unit.c")
       (file-b "build/test_c_ddc/dir_b/unit.c")
       (obj-a  "build/test_c_ddc/dir_a/unit.o")
       (obj-b  "build/test_c_ddc/dir_b/unit.o")
       (pp-b   "build/test_c_ddc/dir_b/unit.i")
       (code   (string-append
                "const char *get_file(void) { return __FILE__; }\n"
                "int get_line(void) { return __LINE__; }\n")))
  (ddc-write-text file-a code)
  (ddc-write-text file-b code)
  (c-driver-main (list "-O2" "-ffile-prefix-map=build/test_c_ddc/dir_a=virtual_src" "-c" file-a "-o" obj-a))
  (c-driver-main (list "-O2" "-ffile-prefix-map=build/test_c_ddc/dir_b=virtual_src" "-c" file-b "-o" obj-b))
  (c-driver-main (list "-E" "-ffile-prefix-map=build/test_c_ddc/dir_b/=virtual_src/" file-b "-o" pp-b))
  (let ((pp-text (read-all-file-text pp-b)))
    (assert-true "3.1 Normalized __FILE__ appears in preprocessed output"
                 (ddc-string-contains? pp-text "\"virtual_src/unit.c\""))
    (assert-true "3.2 Original dir_b prefix absent after -ffile-prefix-map"
                 (not (ddc-string-contains? pp-text "dir_b"))))
  (assert-equal "3.3 Distinct directories with -ffile-prefix-map yield identical unit.o bytes"
                (ddc-read-file-bytes obj-a)
                (ddc-read-file-bytes obj-b)))

;; -----------------------------------------------------------------------
;; Group 4: Deterministic __DATE__ and __TIME__ Builtins
;; -----------------------------------------------------------------------
(display "\n--- Group 4: Deterministic __DATE__ and __TIME__ Builtins ---\n")

(let* ((dt-src "build/test_c_ddc/dir_a/dt_test.c")
       (dt-pp1 "build/test_c_ddc/dir_a/dt_test1.i")
       (dt-pp2 "build/test_c_ddc/dir_a/dt_test2.i"))
  (ddc-write-text dt-src "const char *d = __DATE__; const char *t = __TIME__;\n")
  (c-driver-main (list "-E" dt-src "-o" dt-pp1))
  (c-driver-main (list "-E" dt-src "-o" dt-pp2))
  (let ((txt1 (read-all-file-text dt-pp1))
        (txt2 (read-all-file-text dt-pp2)))
    (assert-equal "4.1 Repeated __DATE__/__TIME__ preprocessing identical" txt1 txt2)
    (assert-true "4.2 Deterministic __DATE__ default format check"
                 (or (ddc-string-contains? txt1 "\"Jan  1 1970\"")
                     (and (string? (get-environment-variable "SOURCE_DATE_EPOCH")) #t))))
  (assert-equal "4.3 Epoch 0 converts to Jan  1 1970 / 00:00:00"
                (cons "Jan  1 1970" "00:00:00")
                (%cpp-epoch->date-time-strings 0))
  (assert-equal "4.4 Epoch 1700000000 converts deterministically to Nov 14 2023 / 22:13:20"
                (cons "Nov 14 2023" "22:13:20")
                (%cpp-epoch->date-time-strings 1700000000)))

;; -----------------------------------------------------------------------
;; Group 5: Pass 144 Static ELF64 Linking Determinism & Zero-Filled Padding
;; -----------------------------------------------------------------------
(display "\n--- Group 5: Pass 144 Static Linking Determinism & Zero Padding ---\n")

(let ((start-src "build/test_c_ddc/dir_a/start_ddc.c")
      (start-obj "build/test_c_ddc/dir_a/start_ddc.o")
      (alpha-obj "build/test_c_ddc/dir_a/out1/alpha.o")
      (beta-obj  "build/test_c_ddc/dir_a/out1/beta.o")
      (bin1      "build/test_c_ddc/dir_a/bin1")
      (bin2      "build/test_c_ddc/dir_a/bin2"))
  (ddc-write-text
   start-src
   (string-append
    "extern int main(void);\n"
    "void _start(void) {\n"
    "  long rc = (long)main();\n"
    "  __asm__ volatile (\"syscall\" :: \"a\"(60L), \"D\"(rc));\n"
    "  while (1) {}\n"
    "}\n"))
  (c-driver-main (list "-O2" "-c" start-src "-o" start-obj))
  (c-driver-main (list "--linker=ulisp" "-static" "-nostdlib" start-obj alpha-obj beta-obj "-o" bin1))
  (c-driver-main (list "--linker=ulisp" "-static" "-nostdlib" start-obj alpha-obj beta-obj "-o" bin2))
  (let ((bytes1 (ddc-read-file-bytes bin1))
        (bytes2 (ddc-read-file-bytes bin2))
        (start-bytes (ddc-read-file-bytes start-obj)))
    (assert-equal "5.1 Pass 144 static ELF64 link produces byte-identical executables" bytes1 bytes2)
    (assert-true "5.2 ELF64 executable magic header verified"
                 (and (= (list-ref bytes1 0) 127)
                      (= (list-ref bytes1 1) 69)
                      (= (list-ref bytes1 2) 76)
                      (= (list-ref bytes1 3) 70)))
    (assert-equal "5.3 ET_REL e_ident[7..15] zero-padded"
                  '(0 0 0 0 0 0 0 0 0)
                  (let loop ((i 7) (acc '()))
                    (if (>= i 16) (reverse acc) (loop (+ i 1) (cons (list-ref start-bytes i) acc)))))))

;; -----------------------------------------------------------------------
;; Group 6: Negative CLI Diagnostics (C99-DRV-002) for -ffile-prefix-map
;; -----------------------------------------------------------------------
(display "\n--- Group 6: Negative CLI Validation (C99-DRV-002) ---\n")

(define (ddc-raises-drv-002? argv)
  (guard (ex
          ((and (pair? ex)
                (eq? (car ex) 'c99-driver-error)
                (string=? (cadr ex) "C99-DRV-002"))
           #t)
          (else #f))
    (parse-c-driver-args argv)
    #f))

(assert-true "6.1 Rejects -ffile-prefix-map without '=' (C99-DRV-002)"
             (ddc-raises-drv-002? '("-ffile-prefix-map=invalid")))
(assert-true "6.2 Rejects -ffile-prefix-map with empty OLD prefix (C99-DRV-002)"
             (ddc-raises-drv-002? '("-ffile-prefix-map==dst")))
(assert-true "6.3 Rejects -ffile-prefix-map with shell metacharacter ';' (C99-DRV-002)"
             (ddc-raises-drv-002? '("-ffile-prefix-map=a;b=c")))

(assert-report)
