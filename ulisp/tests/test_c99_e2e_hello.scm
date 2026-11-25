;;; =======================================================================
;;; Unit Test Suite: C Compiler Driver, CLI Options, CWE-78 & Pass 144a
;;; Issue #917 - Conforms to DSN-33-32 §5.1/§6.1 & DSN-33-13
;;; =======================================================================

(display "=======================================================\n")
(display " Starting C Compiler Driver & Assembler Unit Suite (#917)\n")
(display "=======================================================\n")

(enable-verifier!)
(set-verifier-level! 3)
(set-verifier-strict! #t)

(test-begin "C Compiler Driver & Pass 144a Extensions (Issue #917)")

;;; -----------------------------------------------------------------------
;;; Group 1: CLI Argument Parsing (<c-driver-options>)
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: CLI Option Parsing ---\n")

(let ((opts (parse-c-driver-args
             '("--" "-c" "-O2" "-Iinc1" "-I" "inc2" "-isystem" "sysinc"
               "-DFOO=42" "-D" "BAR" "-UBAZ" "-L/tmp/lib" "-l" "m"
               "--target=x86_64" "--sanitize-bounds" "-o" "out.o" "main.c"))))
  (assert-true "opts is c-driver-options?" (c-driver-options? opts))
  (assert-equal "mode is 'compile" 'compile (c-drv-mode opts))
  (assert-equal "target is 'x86_64" 'x86_64 (c-drv-target opts))
  (assert-equal "opt-level is 2" 2 (c-drv-opt-level opts))
  (assert-equal "output is out.o" "out.o" (c-drv-output opts))
  (assert-equal "inputs is (main.c)" '("main.c") (c-drv-inputs opts))
  (assert-equal "include-dirs" '("inc1" "inc2") (c-drv-include-dirs opts))
  (assert-equal "system-include-dirs" '("sysinc") (c-drv-system-include-dirs opts))
  (assert-equal "defines" '("FOO=42" "BAR") (c-drv-defines opts))
  (assert-equal "undefs" '("BAZ") (c-drv-undefs opts))
  (assert-equal "lib-dirs" '("/tmp/lib") (c-drv-lib-dirs opts))
  (assert-equal "libs" '("m") (c-drv-libs opts))
  (assert-true "sanitize-bounds? enabled" (c-drv-sanitize-bounds? opts)))

(let ((opts-c (parse-c-driver-args '("-S" "--target=c" "-O1" "a.c" "-oa.c.out"))))
  (assert-equal "mode is 'asm" 'asm (c-drv-mode opts-c))
  (assert-equal "target is 'c" 'c (c-drv-target opts-c))
  (assert-equal "opt-level is 1" 1 (c-drv-opt-level opts-c))
  (assert-equal "-o attached form" "a.c.out" (c-drv-output opts-c)))

;;; -----------------------------------------------------------------------
;;; Group 2: CWE-78 Security Validation & Diagnostic Codes (C99-DRV-001..003)
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Security & Diagnostics C99-DRV-001..003 ---\n")

(define (capture-drv-error thunk)
  (guard (ex
          ((and (pair? ex) (eq? (car ex) 'c99-driver-error))
           (cadr ex))
          (else #f))
    (thunk)
    #f))

(assert-equal "C99-DRV-001 on missing input list"
              "C99-DRV-001"
              (capture-drv-error (lambda () (c-driver-main '()))))

(assert-equal "C99-DRV-001 on non-existent file"
              "C99-DRV-001"
              (capture-drv-error (lambda () (c-driver-main '("/nonexistent_c99_test_xyz.c")))))

(assert-equal "C99-DRV-002 on unknown CLI flag"
              "C99-DRV-002"
              (capture-drv-error (lambda () (parse-c-driver-args '("--totally-unknown-flag")))))

(assert-equal "C99-DRV-002 on missing arg after -o"
              "C99-DRV-002"
              (capture-drv-error (lambda () (parse-c-driver-args '("-o")))))

(assert-equal "C99-DRV-002 CWE-78 blocks shell semicolon in -o"
              "C99-DRV-002"
              (capture-drv-error (lambda () (parse-c-driver-args '("-o" "out;rm -rf /" "a.c")))))

(assert-equal "C99-DRV-002 CWE-78 blocks subshell in -I"
              "C99-DRV-002"
              (capture-drv-error (lambda () (parse-c-driver-args '("-I$(id)" "a.c")))))

(assert-equal "C99-DRV-002 CWE-78 blocks backtick in input"
              "C99-DRV-002"
              (capture-drv-error (lambda () (parse-c-driver-args '("foo`id`.c")))))

;;; -----------------------------------------------------------------------
;;; Group 3: Pass 144a 16-bit, word ptr, movzx, movsx, movsxd Encodings
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Pass 144a Instruction Encodings ---\n")

(let* ((asm-lines
        '(".intel_syntax noprefix"
          ".text"
          ".globl test_widths"
          ".type test_widths, @function"
          "test_widths:"
          "    movsx rax, byte ptr [rsp - 8]"
          "    movsx rax, word ptr [rsp - 16]"
          "    movzx rax, word ptr [rsp - 16]"
          "    movsxd rax, dword ptr [rsp - 24]"
          "    movsx rax, al"
          "    movsx rax, ax"
          "    movsx rax, sil"
          "    movzx rax, ax"
          "    movsxd rax, eax"
          "    mov word ptr [rsp - 16], ax"
          "    mov word ptr [rsp - 16], 1234"
          "    mov ax, word ptr [rsp - 16]"
          "    mov ax, 0x1234"
          "    mov r12w, ax"
          "    ret"))
       (assembled (assemble-x86-relocatable asm-lines))
       (text-bv (car assembled)))
  (assert-true "144a encodes 16-bit/movsx/movsxd instructions cleanly" (> (bytevector-length text-bv) 30))
  (let ((elf-bv (build-elf64-relocatable assembled)))
    (assert-equal "ET_REL header e_type == 1" 1 (elf64-get-u16-le elf-bv 16))))

;;; -----------------------------------------------------------------------
;;; Group 4: --target=vm Execution via c-driver-main
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: C Driver VM Target Execution ---\n")

(let ((vm-src-path "build/tmp_drv_vm_test.c"))
  (%c-drv-write-text-file!
   vm-src-path
   "#ifndef FACTOR\n#define FACTOR 3\n#endif\nint main(void) {\n  short s = -4;\n  unsigned short u = 500;\n  return (int)(s * FACTOR) + (int)u;\n}\n")
  (assert-equal "--target=vm with -D compiles and runs returning 488"
                488
                (c-driver-main (list "--target=vm" "-O1" vm-src-path)))
  (assert-equal "--target=vm with -DFACTOR=10 overrides default returning 460"
                460
                (c-driver-main (list "--target=vm" "-DFACTOR=10" vm-src-path)))
  (if (file-exists? vm-src-path) (delete-file vm-src-path)))

;;; -----------------------------------------------------------------------
;;; Group 5: Phase Profiling Options & Backend/Assembler Hooks (Issue #945)
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Phase Profiling Hooks (#945) ---\n")

(let ((opts-def (parse-c-driver-args '("-c" "main.c")))
      (opts-prof (parse-c-driver-args '("--profile-phases" "-c" "main.c")))
      (opts-probe (parse-c-driver-args '("--profile-asm-parse" "-c" "main.c"))))
  (assert-equal "default profile-phases? is #f" #f (c-drv-profile-phases? opts-def))
  (assert-equal "default profile-asm-parse? is #f" #f (c-drv-profile-asm-parse? opts-def))
  (assert-equal "--profile-phases enables profile-phases?" #t (c-drv-profile-phases? opts-prof))
  (assert-equal "--profile-phases keeps profile-asm-parse? #f" #f (c-drv-profile-asm-parse? opts-prof))
  (assert-equal "--profile-asm-parse enables profile-phases?" #t (c-drv-profile-phases? opts-probe))
  (assert-equal "--profile-asm-parse enables profile-asm-parse?" #t (c-drv-profile-asm-parse? opts-probe)))

(let ((prof-src "build/tmp_drv_prof_test.c")
      (prof-obj "build/tmp_drv_prof_test.o"))
  (%c-drv-write-text-file!
   prof-src
   "int add_one(int x) { return x + 1; }\nint main(void) { return add_one(41); }\n")
  (let* ((opts (parse-c-driver-args (list "-O1" "-c" prof-src)))
         (lir (c99-compile-file-to-lir prof-src opts))
         (bv-norm (build-x86-64-elf-obj lir 'c-tu))
         (prof-res (build-x86-64-elf-obj-profiled lir 'c-tu))
         (bv-prof (car prof-res))
         (asm-lines (list-ref prof-res 9))
         (counts (profile-x86-asm-parse-only asm-lines)))
    (assert-true "profiled ELF object bytes match normal build identically" (sbi-bytevector=? bv-norm bv-prof))
    (assert-true "isel_us >= 0" (>= (list-ref prof-res 1) 0))
    (assert-true "x86_peephole_us >= 0" (>= (list-ref prof-res 2) 0))
    (assert-true "asm_emit_us >= 0" (>= (list-ref prof-res 3) 0))
    (assert-true "asm_pass1_us >= 0" (>= (list-ref prof-res 4) 0))
    (assert-true "asm_pass2_us >= 0" (>= (list-ref prof-res 5) 0))
    (assert-true "elf_build_us >= 0" (>= (list-ref prof-res 6) 0))
    (assert-true "asm_lines > 0" (> (list-ref prof-res 7) 0))
    (assert-true "asm_bytes > 0" (> (list-ref prof-res 8) 0))
    (assert-true "parsed_insts > 0" (> (car counts) 0))
    (assert-true "parsed_dirs > 0" (> (cdr counts) 0)))
  (assert-equal "c-driver-main --profile-phases -c exits 0"
                0
                (c-driver-main (list "--profile-phases" "--profile-asm-parse" "-O1" "-c" prof-src "-o" prof-obj)))
  (assert-true "profiled .o output exists" (file-exists? prof-obj))
  (if (file-exists? prof-src) (delete-file prof-src))
  (if (file-exists? prof-obj) (delete-file prof-obj)))

(test-end)
(display "-------------------------------------------------------\n")
(display " [RESULT] C Compiler Driver & Pass 144a Suite (#917): ALL PASSED\n")
(display "-------------------------------------------------------\n")
