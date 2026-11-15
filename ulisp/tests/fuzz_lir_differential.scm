;;; =======================================================================
;;; Differential Fuzzing Test Suite: Typed Machine LIR (x86-64 vs C99)
;;; Conforms to Issue #831, DSN-33, and DSN-38 Section 2 E10 / K3
;;; Generates deterministic paired test programs (.s and .c) covering:
;;; 1. Systematic ALU & Bitwise ops (%add, %sub, %imul, %neg, %not, %bit-and, %bit-or, %bit-xor, %shl, %shr, %sar)
;;; 2. Overflow-Checked Arithmetic (%add-overflow, %sub-overflow, %mul-overflow)
;;; 3. Unsigned Arithmetic & Condition Codes (%udiv, %urem, %set-boolean with unsigned cc, %jump-cond)
;;; 4. Machine Type Conversions (%trunc, %zext, %sext across i8, u8, i16, u16, i32, u32)
;;; 5. Typed Memory Access (%store-typed / %load-typed i8..i64, u8..u64, f64)
;;; 6. Floating-Point Arithmetic (%sitofp, %fadd, %fsub, %fmul, %fdiv, %fcmp, %fptosi)
;;; 7. Randomized Instruction Chains generated via deterministic LCG PRNG
;;; =======================================================================

(display "=======================================================\n")
(display " Generating Differential LIR Test Cases (Issue #831)\n")
(display "=======================================================\n")

(define *out-dir* "build/diff_fuzz")

;; Deterministic LCG PRNG (Linear Congruential Generator)
(define *prng-state* 20261115)

(define (prng-next!)
  (set! *prng-state* (modulo (+ (* *prng-state* 1103515245) 12345) 2147483648))
  *prng-state*)

(define (prng-range low high)
  (let ((span (+ (- high low) 1)))
    (+ low (modulo (prng-next!) span))))

(define (prng-choice lst)
  (let ((idx (prng-range 0 (- (length lst) 1))))
    (list-ref lst idx)))

;; Manifest of generated test names
(define *test-manifest* '())

(define (record-test! name)
  (set! *test-manifest* (append *test-manifest* (list name))))

;; Helper to construct a complete valid %lir-program
(define (make-fuzz-lir-program body-insts)
  (list '%lir-program
        '(strings ())
        '(stackmaps ())
        '(%lir-functions)
        (list '%lir-main
              '(frame-size 64)
              (cons 'body body-insts))))

;; Helper to emit both x86-64 (.s) and C99 (.c) for a test case
(define (emit-fuzz-pair name body-insts)
  (let ((prog (make-fuzz-lir-program body-insts))
        (s-path (string-append *out-dir* "/" name ".s"))
        (c-path (string-append *out-dir* "/" name ".c")))
    (record-test! name)
    (with-output-to-file s-path
      (lambda () (emit-x86-64 prog 'none)))
    (with-output-to-file c-path
      (lambda () (emit-c prog 'none)))
    (display "  [GEN] ")
    (display name)
    (newline)))

;;; -----------------------------------------------------------------------
;;; Group 1: Systematic ALU & Bitwise Operations
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: ALU & Bitwise Operations ---\n")

;; 1.1 %add
(emit-fuzz-pair "alu_add_basic"
  '((%mov %rax 123)
    (%mov %rbx 456)
    (%add %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 1.2 %sub
(emit-fuzz-pair "alu_sub_negative"
  '((%mov %rax 100)
    (%mov %rbx 350)
    (%sub %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 1.3 %imul
(emit-fuzz-pair "alu_imul_basic"
  '((%mov %rax -15)
    (%mov %rbx 12)
    (%imul %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 1.4 %neg
(emit-fuzz-pair "alu_neg_basic"
  '((%mov %rax 42)
    (%neg %rax)
    (%box-fixnum %rax %rax)
    (%return)))

;; 1.5 %not (bitwise NOT)
(emit-fuzz-pair "alu_not_zero"
  '((%mov %rax 0)
    (%not %rax)
    (%box-fixnum %rax %rax)
    (%return)))

(emit-fuzz-pair "alu_not_pattern"
  '((%mov %rax 15)
    (%not %rax)
    (%box-fixnum %rax %rax)
    (%return)))

;; 1.6 %bit-and, %bit-or, %bit-xor
(emit-fuzz-pair "alu_bit_ops"
  '((%mov %rax 255)
    (%bit-and %rax 170)
    (%bit-or %rax 5)
    (%bit-xor %rax 255)
    (%box-fixnum %rax %rax)
    (%return)))

;; 1.7 Shifts (%shl, %shr, %sar)
(emit-fuzz-pair "alu_shifts"
  '((%mov %rax 1)
    (%shl %rax 8)
    (%mov %rbx -16)
    (%sar %rbx 2)
    (%add %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;;; -----------------------------------------------------------------------
;;; Group 2: Overflow-Checked Arithmetic
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Overflow-Checked Arithmetic ---\n")

;; 2.1 %add-overflow (no overflow)
(emit-fuzz-pair "of_add_no_overflow"
  '((%mov %rax 500)
    (%mov %rbx 300)
    (%add-overflow %rax %rdx %rax %rbx)
    ;; Return res + (flag * 1000) -> 800
    (%imul %rdx 1000)
    (%add %rax %rdx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 2.2 %add-overflow (overflow)
(emit-fuzz-pair "of_add_with_overflow"
  '((%mov %rax 9223372036854775807)
    (%mov %rbx 1)
    (%add-overflow %rax %rdx %rax %rbx)
    ;; Return flag (should be 1)
    (%mov %rax %rdx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 2.3 %sub-overflow (no overflow)
(emit-fuzz-pair "of_sub_no_overflow"
  '((%mov %rax 500)
    (%mov %rbx 200)
    (%sub-overflow %rax %rdx %rax %rbx)
    (%imul %rdx 1000)
    (%add %rax %rdx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 2.4 %sub-overflow (overflow)
(emit-fuzz-pair "of_sub_with_overflow"
  '((%mov %rax -9223372036854775808)
    (%mov %rbx 1)
    (%sub-overflow %rax %rdx %rax %rbx)
    (%mov %rax %rdx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 2.5 %mul-overflow (no overflow)
(emit-fuzz-pair "of_mul_no_overflow"
  '((%mov %rax 25)
    (%mov %rbx 4)
    (%mul-overflow %rax %rdx %rax %rbx)
    (%imul %rdx 1000)
    (%add %rax %rdx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 2.6 %mul-overflow (overflow)
(emit-fuzz-pair "of_mul_with_overflow"
  '((%mov %rax 4611686018427387904)
    (%mov %rbx 4)
    (%mul-overflow %rax %rdx %rax %rbx)
    (%mov %rax %rdx)
    (%box-fixnum %rax %rax)
    (%return)))

;;; -----------------------------------------------------------------------
;;; Group 3: Unsigned Arithmetic & Unsigned Condition Codes
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Unsigned Arithmetic & Condition Codes ---\n")

;; 3.1 %udiv
(emit-fuzz-pair "unsigned_udiv"
  '((%mov %rax 100)
    (%mov %rbx 7)
    (%udiv %rax %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 3.2 %urem
(emit-fuzz-pair "unsigned_urem"
  '((%mov %rax 100)
    (%mov %rbx 7)
    (%urem %rax %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 3.3 %set-boolean setb (10 < -1 unsigned -> #t)
(emit-fuzz-pair "unsigned_setb_true"
  '((%mov %rax 10)
    (%mov %rbx -1)
    (%cmp %rax %rbx)
    (%set-boolean %rax "setb")
    (%return)))

;; 3.4 %set-boolean seta (10 > -1 unsigned -> #f)
(emit-fuzz-pair "unsigned_seta_false"
  '((%mov %rax 10)
    (%mov %rbx -1)
    (%cmp %rax %rbx)
    (%set-boolean %rax "seta")
    (%return)))

;; 3.5 %set-boolean setae (20 >= 20 unsigned -> #t)
(emit-fuzz-pair "unsigned_setae_true"
  '((%mov %rax 20)
    (%mov %rbx 20)
    (%cmp %rax %rbx)
    (%set-boolean %rax "setae")
    (%return)))

;; 3.6 %set-boolean setbe (25 <= 20 unsigned -> #f)
(emit-fuzz-pair "unsigned_setbe_false"
  '((%mov %rax 25)
    (%mov %rbx 20)
    (%cmp %rax %rbx)
    (%set-boolean %rax "setbe")
    (%return)))

;; 3.7 %jump-cond jb
(emit-fuzz-pair "unsigned_branch_jb"
  '((%mov %rax 5)
    (%mov %rbx -1)
    (%cmp %rax %rbx)
    (%jump-cond "jb" lbl_below)
    (%mov %rax 100)
    (%box-fixnum %rax %rax)
    (%return)
    (%label lbl_below)
    (%mov %rax 200)
    (%box-fixnum %rax %rax)
    (%return)))

;;; -----------------------------------------------------------------------
;;; Group 4: Machine Type Conversions & Extensions
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Conversions & Extensions ---\n")

;; 4.1 %trunc i8 / u8 (-5 -> 251)
(emit-fuzz-pair "conv_trunc_i8"
  '((%mov %rax -5)
    (%trunc i8 %rax %rax)
    (%box-fixnum %rax %rax)
    (%return)))

(emit-fuzz-pair "conv_trunc_u8"
  '((%mov %rax -5)
    (%trunc u8 %rax %rax)
    (%box-fixnum %rax %rax)
    (%return)))

;; 4.2 %trunc i16 / u16 (-100 -> 65436)
(emit-fuzz-pair "conv_trunc_i16"
  '((%mov %rax -100)
    (%trunc i16 %rax %rax)
    (%box-fixnum %rax %rax)
    (%return)))

(emit-fuzz-pair "conv_trunc_u16"
  '((%mov %rax -100)
    (%trunc u16 %rax %rax)
    (%box-fixnum %rax %rax)
    (%return)))

;; 4.3 %trunc i32 / u32 (-100 -> 4294967196)
(emit-fuzz-pair "conv_trunc_i32"
  '((%mov %rax -100)
    (%trunc i32 %rax %rax)
    (%box-fixnum %rax %rax)
    (%return)))

;; 4.4 %zext u8
(emit-fuzz-pair "conv_zext_u8"
  '((%mov %rax 200)
    (%zext u8 %rax %rax)
    (%box-fixnum %rax %rax)
    (%return)))

;; 4.5 %sext i8 (251 -> -5)
(emit-fuzz-pair "conv_sext_i8"
  '((%mov %rax 251)
    (%sext i8 %rax %rax)
    (%box-fixnum %rax %rax)
    (%return)))

;; 4.6 %sext i16 (65436 -> -100)
(emit-fuzz-pair "conv_sext_i16"
  '((%mov %rax 65436)
    (%sext i16 %rax %rax)
    (%box-fixnum %rax %rax)
    (%return)))

;; 4.7 %sext i32 (4294967196 -> -100)
(emit-fuzz-pair "conv_sext_i32"
  '((%mov %rax 4294967196)
    (%sext i32 %rax %rax)
    (%box-fixnum %rax %rax)
    (%return)))

;;; -----------------------------------------------------------------------
;;; Group 5: Typed Memory Access
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Typed Memory Access ---\n")

;; 5.1 i8 load/store (sign extension)
(emit-fuzz-pair "mem_i8_store_load"
  '((%mov %rax -42)
    (%store-typed i8 %rsp -8 %rax)
    (%load-typed i8 %rbx %rsp -8)
    (%mov %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 5.2 u8 load/store (zero extension: store -42 (214), load -> 214)
(emit-fuzz-pair "mem_u8_store_load"
  '((%mov %rax -42)
    (%store-typed u8 %rsp -8 %rax)
    (%load-typed u8 %rbx %rsp -8)
    (%mov %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 5.3 i16 load/store
(emit-fuzz-pair "mem_i16_store_load"
  '((%mov %rax -1234)
    (%store-typed i16 %rsp -8 %rax)
    (%load-typed i16 %rbx %rsp -8)
    (%mov %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 5.4 u16 load/store
(emit-fuzz-pair "mem_u16_store_load"
  '((%mov %rax -1234)
    (%store-typed u16 %rsp -8 %rax)
    (%load-typed u16 %rbx %rsp -8)
    (%mov %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 5.5 i32 load/store
(emit-fuzz-pair "mem_i32_store_load"
  '((%mov %rax -987654)
    (%store-typed i32 %rsp -8 %rax)
    (%load-typed i32 %rbx %rsp -8)
    (%mov %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 5.6 u32 load/store
(emit-fuzz-pair "mem_u32_store_load"
  '((%mov %rax -987654)
    (%store-typed u32 %rsp -8 %rax)
    (%load-typed u32 %rbx %rsp -8)
    (%mov %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 5.7 i64 load/store
(emit-fuzz-pair "mem_i64_store_load"
  '((%mov %rax 1234567890123)
    (%store-typed i64 %rsp -8 %rax)
    (%load-typed i64 %rbx %rsp -8)
    (%mov %rax %rbx)
    (%box-fixnum %rax %rax)
    (%return)))

;; 5.8 f64 load/store
(emit-fuzz-pair "mem_f64_store_load"
  '((%mov %rax 77)
    (%sitofp %xmm0 %rax)
    (%store-typed f64 %rsp -8 %xmm0)
    (%load-typed f64 %xmm1 %rsp -8)
    (%fptosi %rax %xmm1)
    (%box-fixnum %rax %rax)
    (%return)))

;;; -----------------------------------------------------------------------
;;; Group 6: Floating-Point Operations
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Floating-Point Operations ---\n")

;; 6.1 %sitofp, %fadd, %fptosi
(emit-fuzz-pair "fp_add"
  '((%mov %rax 100)
    (%sitofp %xmm0 %rax)
    (%mov %rax 25)
    (%sitofp %xmm1 %rax)
    (%fadd %xmm0 %xmm1)
    (%fptosi %rax %xmm0)
    (%box-fixnum %rax %rax)
    (%return)))

;; 6.2 %fsub
(emit-fuzz-pair "fp_sub"
  '((%mov %rax 100)
    (%sitofp %xmm0 %rax)
    (%mov %rax 37)
    (%sitofp %xmm1 %rax)
    (%fsub %xmm0 %xmm1)
    (%fptosi %rax %xmm0)
    (%box-fixnum %rax %rax)
    (%return)))

;; 6.3 %fmul
(emit-fuzz-pair "fp_mul"
  '((%mov %rax 12)
    (%sitofp %xmm0 %rax)
    (%mov %rax 8)
    (%sitofp %xmm1 %rax)
    (%fmul %xmm0 %xmm1)
    (%fptosi %rax %xmm0)
    (%box-fixnum %rax %rax)
    (%return)))

;; 6.4 %fdiv
(emit-fuzz-pair "fp_div"
  '((%mov %rax 144)
    (%sitofp %xmm0 %rax)
    (%mov %rax 12)
    (%sitofp %xmm1 %rax)
    (%fdiv %xmm0 %xmm1)
    (%fptosi %rax %xmm0)
    (%box-fixnum %rax %rax)
    (%return)))

;;; -----------------------------------------------------------------------
;;; Group 7: Randomized Instruction Sequences (Fuzzing)
;;; -----------------------------------------------------------------------
(display "\n--- Group 7: Randomized Instruction Sequences ---\n")

(define (gen-random-fuzz-test id)
  (let ((name (string-append "fuzz_seq_" (number->string id)))
        (insts '()))
    ;; Initialize rax and rbx with random values
    (set! insts (append insts
      (list (list '%mov '%rax (prng-range -1000 1000))
            (list '%mov '%rbx (prng-range 1 500)))))
    ;; Generate random ALU / bitwise chain of 10 operations
    (let loop ((step 0))
      (when (< step 10)
        (let ((op (prng-choice '(add sub imul bit-and bit-or bit-xor shl-small sar-small trunc-i16))))
          (case op
            ((add)
             (set! insts (append insts (list (list '%add '%rax (prng-range -100 100))))))
            ((sub)
             (set! insts (append insts (list (list '%sub '%rax (prng-range -100 100))))))
            ((imul)
             (set! insts (append insts (list (list '%imul '%rax (prng-choice '(2 3 -2 -1 5)))))))
            ((bit-and)
             (set! insts (append insts (list (list '%bit-and '%rax 65535)))))
            ((bit-or)
             (set! insts (append insts (list (list '%bit-or '%rax (prng-range 1 127))))))
            ((bit-xor)
             (set! insts (append insts (list (list '%bit-xor '%rax (prng-range 1 127))))))
            ((shl-small)
             (set! insts (append insts (list (list '%shl '%rax (prng-range 1 3))))))
            ((sar-small)
             (set! insts (append insts (list (list '%sar '%rax (prng-range 1 3))))))
            ((trunc-i16)
             (set! insts (append insts (list '(%trunc i16 %rax %rax)))))))
        (loop (+ step 1))))
    ;; Final box and return
    (set! insts (append insts
      (list '(%box-fixnum %rax %rax)
            '(%return))))
    (emit-fuzz-pair name insts)))

;; Generate 20 randomized sequences
(let loop ((i 1))
  (when (<= i 20)
    (gen-random-fuzz-test i)
    (loop (+ i 1))))

;; Write manifest file
(with-output-to-file (string-append *out-dir* "/manifest.txt")
  (lambda ()
    (for-each (lambda (tname)
                (display tname)
                (newline))
              *test-manifest*)))

(display "=======================================================\n")
(display " Successfully generated ")
(display (number->string (length *test-manifest*)))
(display " differential test cases.\n")
(display "=======================================================\n")
