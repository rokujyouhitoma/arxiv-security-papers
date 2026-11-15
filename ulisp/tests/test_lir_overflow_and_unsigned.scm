;;; =======================================================================
;;; Unit Test Suite: LIR Overflow-Checked Arithmetic & Unsigned Operations
;;; Issue #828 - Conforms to DSN-33-02 Section 4.3 & DSN-38 Section 2 E2
;;; =======================================================================

(display "=======================================================\n")
(display " Starting LIR Overflow & Unsigned Operations Suite (#828)\n")
(display "=======================================================\n")

;; Configure verifier
(enable-verifier!)
(set-verifier-strict! #f)

(define *test-count* (cons 0 '()))
(define *pass-count* (cons 0 '()))

(define (assert-true name expr-result)
  (set-car! *test-count* (+ (car *test-count*) 1))
  (if expr-result
      (begin
        (set-car! *pass-count* (+ (car *pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

(define (assert-false name expr-result)
  (set-car! *test-count* (+ (car *test-count*) 1))
  (if (not expr-result)
      (begin
        (set-car! *pass-count* (+ (car *pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] Expected failure/rejection: ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

(define (assert-equal name expected actual)
  (set-car! *test-count* (+ (car *test-count*) 1))
  (if (equal? expected actual)
      (begin
        (set-car! *pass-count* (+ (car *pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (display "\n    Expected: ")
        (write expected)
        (display "\n    Actual:   ")
        (write actual)
        (newline)
        (error "Assertion failed" name))))

;; Helper to run validate-lir on a single instruction
(define (make-test-lir-program funcs main-insts)
  (list '%lir-program
        '(strings ())
        '(stackmaps ())
        (cons '%lir-functions funcs)
        (list '%lir-main
              '(frame-size 16)
              (cons 'body main-insts))))

(define (valid-inst? inst)
  (validate-lir (make-test-lir-program '() (list inst '(%return)))))

(define (test-string-contains? str sub)
  (let ((str-len (string-length str))
        (sub-len (string-length sub)))
    (if (< str-len sub-len) #f
        (let loop ((i 0))
          (cond
            ((> (+ i sub-len) str-len) #f)
            ((string=? (substring str i (+ i sub-len)) sub) #t)
            (else (loop (+ i 1))))))))

(define (test-any pred lst)
  (cond
    ((null? lst) #f)
    ((pred (car lst)) #t)
    (else (test-any pred (cdr lst)))))

;;; -----------------------------------------------------------------------
;;; Group 1: Overflow-Checked Arithmetic (%add-overflow, %sub-overflow, %mul-overflow)
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Overflow-Checked Arithmetic ---\n")

(assert-true "valid %add-overflow register operands"
  (valid-inst? '(%add-overflow %rax %rdx %rbx %rcx)))

(assert-true "valid %add-overflow with immediate operand"
  (valid-inst? '(%add-overflow %rax %rdx %rbx 42)))

(assert-true "valid %add-overflow with boundary integer"
  (valid-inst? '(%add-overflow %rax %rdx %rbx 9223372036854775807)))

(assert-true "valid %sub-overflow register operands"
  (valid-inst? '(%sub-overflow %rax %rdx %rbx %rcx)))

(assert-true "valid %sub-overflow with immediate operand"
  (valid-inst? '(%sub-overflow %rax %rdx %rbx 1)))

(assert-true "valid %mul-overflow register operands"
  (valid-inst? '(%mul-overflow %rax %rdx %rbx %rcx)))

(assert-true "valid %mul-overflow with immediate operand"
  (valid-inst? '(%mul-overflow %rax %rdx %rbx 4)))

;; Distinct register invariant & CWE-843 defense
(assert-false "reject %add-overflow with identical dst-val and dst-flag"
  (valid-inst? '(%add-overflow %rax %rax %rbx %rcx)))

(assert-false "reject %sub-overflow with identical dst-val and dst-flag"
  (valid-inst? '(%sub-overflow %rax %rax %rbx %rcx)))

(assert-false "reject %mul-overflow with identical dst-val and dst-flag"
  (valid-inst? '(%mul-overflow %rax %rax %rbx %rcx)))

(assert-false "reject %add-overflow with float destination register (CWE-843 defense)"
  (valid-inst? '(%add-overflow %xmm0 %rdx %rbx %rcx)))

(assert-false "reject %add-overflow with float flag register (CWE-843 defense)"
  (valid-inst? '(%add-overflow %rax %xmm0 %rbx %rcx)))

(assert-false "reject %add-overflow with float source operand (CWE-843 defense)"
  (valid-inst? '(%add-overflow %rax %rdx %xmm0 %rcx)))

(assert-false "reject %mul-overflow with float source operand (CWE-843 defense)"
  (valid-inst? '(%mul-overflow %rax %rdx %rbx %xmm1)))

;;; -----------------------------------------------------------------------
;;; Group 2: Unsigned Division, Remainder and Logical Shift Right
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Unsigned Operations (%udiv, %urem, %shr) ---\n")

(assert-true "valid %udiv 1-operand form"
  (valid-inst? '(%udiv %rcx)))

(assert-true "valid %udiv 1-operand immediate form"
  (valid-inst? '(%udiv 10)))

(assert-true "valid %udiv 3-operand form"
  (valid-inst? '(%udiv %rax %rbx %rcx)))

(assert-true "valid %udiv 3-operand with immediate divisor"
  (valid-inst? '(%udiv %rax %rbx 2)))

(assert-true "valid %urem 1-operand form"
  (valid-inst? '(%urem %rcx)))

(assert-true "valid %urem 3-operand form"
  (valid-inst? '(%urem %rdx %rbx %rcx)))

(assert-true "valid %urem 3-operand with immediate divisor"
  (valid-inst? '(%urem %rdx %rbx 10)))

(assert-true "valid %shr 2-operand form"
  (valid-inst? '(%shr %rax 4)))

(assert-true "valid %shr 3-operand form"
  (valid-inst? '(%shr %rax %rbx 4)))

;; CWE-843 defense for unsigned operations
(assert-false "reject %udiv with float operand (CWE-843 defense)"
  (valid-inst? '(%udiv %xmm0)))

(assert-false "reject %urem with float destination register (CWE-843 defense)"
  (valid-inst? '(%urem %xmm0 %rax %rbx)))

(assert-false "reject %shr with non-integer shift count"
  (valid-inst? '(%shr %rax %rbx)))

(assert-false "reject %shr with float register destination"
  (valid-inst? '(%shr %xmm0 %rax 2)))

;;; -----------------------------------------------------------------------
;;; Group 3: Unsigned Condition Codes (%setb, %setbe, %seta, %setae)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Unsigned Condition Codes ---\n")

(assert-true "valid %setb 1-operand form (Below)"
  (valid-inst? '(%setb %rax)))

(assert-true "valid %setbe 1-operand form (Below or Equal)"
  (valid-inst? '(%setbe %rax)))

(assert-true "valid %seta 1-operand form (Above)"
  (valid-inst? '(%seta %rax)))

(assert-true "valid %setae 1-operand form (Above or Equal)"
  (valid-inst? '(%setae %rax)))

(assert-true "valid %setb 3-operand form"
  (valid-inst? '(%setb %rax %rbx %rcx)))

(assert-true "valid %setbe 3-operand form with immediate"
  (valid-inst? '(%setbe %rax %rbx 100)))

(assert-true "valid %seta 3-operand form with boundary integers"
  (valid-inst? '(%seta %rax %rbx -1)))

(assert-true "valid %setae 3-operand form"
  (valid-inst? '(%setae %rax %rbx %rcx)))

;; CWE-843 defense for unsigned setcc
(assert-false "reject %setb with float destination register (CWE-843 defense)"
  (valid-inst? '(%setb %xmm0)))

(assert-false "reject %seta 3-operand with float operand (CWE-843 defense)"
  (valid-inst? '(%seta %rax %xmm0 %rbx)))

;;; -----------------------------------------------------------------------
;;; Group 4: x86_64 Backend Lowering Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: x86_64 Backend Lowering Verification ---\n")

(let* ((asm-add-ov (lower-lir-instruction '(%add-overflow %rax %rdx %rbx %rcx)))
       (asm-strs (map (lambda (x) (if (eq? (car x) '%raw-asm) (cadr x) (symbol->string (car x)))) asm-add-ov)))
  (assert-true "x86_64 %add-overflow contains mov" (member "mov" asm-strs))
  (assert-true "x86_64 %add-overflow contains add" (member "add" asm-strs))
  (assert-true "x86_64 %add-overflow contains seto dl" (test-any (lambda (s) (and (string? s) (test-string-contains? s "seto dl"))) asm-strs))
  (assert-true "x86_64 %add-overflow contains movzx rdx, dl" (test-any (lambda (s) (and (string? s) (test-string-contains? s "movzx rdx, dl"))) asm-strs)))

(let* ((asm-sub-ov (lower-lir-instruction '(%sub-overflow %rax %rdx %rbx %rcx)))
       (asm-strs (map (lambda (x) (if (eq? (car x) '%raw-asm) (cadr x) (symbol->string (car x)))) asm-sub-ov)))
  (assert-true "x86_64 %sub-overflow contains sub" (member "sub" asm-strs))
  (assert-true "x86_64 %sub-overflow contains seto dl" (test-any (lambda (s) (and (string? s) (test-string-contains? s "seto dl"))) asm-strs)))

(let* ((asm-mul-ov (lower-lir-instruction '(%mul-overflow %rax %rdx %rbx %rcx)))
       (asm-strs (map (lambda (x) (if (eq? (car x) '%raw-asm) (cadr x) (symbol->string (car x)))) asm-mul-ov)))
  (assert-true "x86_64 %mul-overflow contains imul" (member "imul" asm-strs))
  (assert-true "x86_64 %mul-overflow contains seto dl" (test-any (lambda (s) (and (string? s) (test-string-contains? s "seto dl"))) asm-strs)))

(let* ((asm-udiv (lower-lir-instruction '(%udiv %rcx)))
       (asm-strs (map (lambda (x) (if (eq? (car x) '%raw-asm) (cadr x) (symbol->string (car x)))) asm-udiv)))
  (assert-true "x86_64 %udiv clears rdx with xor edx, edx" (test-any (lambda (s) (and (string? s) (test-string-contains? s "xor edx, edx"))) asm-strs))
  (assert-true "x86_64 %udiv contains div" (member "div" asm-strs)))

(let* ((asm-udiv3 (lower-lir-instruction '(%udiv %rsi %rax 10)))
       (asm-strs (map (lambda (x) (if (eq? (car x) '%raw-asm) (cadr x) (symbol->string (car x)))) asm-udiv3)))
  (assert-true "x86_64 3-operand %udiv loads immediate into r11" (member "mov" asm-strs))
  (assert-true "x86_64 3-operand %udiv contains div" (member "div" asm-strs)))

(let* ((asm-urem (lower-lir-instruction '(%urem %rsi %rax %rcx)))
       (asm-strs (map (lambda (x) (if (eq? (car x) '%raw-asm) (cadr x) (symbol->string (car x)))) asm-urem)))
  (assert-true "x86_64 3-operand %urem moves remainder from rdx to rsi" (member "mov" asm-strs)))

(let* ((asm-setb (lower-lir-instruction '(%setb %rax)))
       (asm-strs (map (lambda (x) (if (eq? (car x) '%raw-asm) (cadr x) (symbol->string (car x)))) asm-setb)))
  (assert-true "x86_64 %setb contains setb al" (test-any (lambda (s) (and (string? s) (test-string-contains? s "setb al"))) asm-strs))
  (assert-true "x86_64 %setb contains movzx rax, al" (test-any (lambda (s) (and (string? s) (test-string-contains? s "movzx rax, al"))) asm-strs)))

(let* ((asm-seta3 (lower-lir-instruction '(%seta %rax %rbx 10)))
       (asm-strs (map (lambda (x) (if (eq? (car x) '%raw-asm) (cadr x) (symbol->string (car x)))) asm-seta3)))
  (assert-true "x86_64 3-operand %seta contains cmp" (member "cmp" asm-strs))
  (assert-true "x86_64 3-operand %seta contains seta al" (test-any (lambda (s) (and (string? s) (test-string-contains? s "seta al"))) asm-strs)))

;;; -----------------------------------------------------------------------
;;; Group 5: Portable C Backend Lowering Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Portable C Backend Lowering Verification ---\n")

(let ((emitted '()))
  (set-emit-line-sink! (lambda (line) (set! emitted (cons line emitted))))
  (emit-c-instruction '(%add-overflow %rax %rdx %rbx %rcx))
  (emit-c-instruction '(%sub-overflow %rax %rdx %rbx %rcx))
  (emit-c-instruction '(%mul-overflow %rax %rdx %rbx %rcx))
  (emit-c-instruction '(%udiv %rax %rbx %rcx))
  (emit-c-instruction '(%urem %rdx %rbx %rcx))
  (emit-c-instruction '(%shr %rax %rbx 3))
  (emit-c-instruction '(%setb %rax %rbx %rcx))
  (emit-c-instruction '(%seta %rax %rbx %rcx))
  (set-emit-line-sink! #f)
  (let ((c-code (apply string-append (reverse (map (lambda (l) (string-append l "\n")) emitted)))))
    (assert-true "C backend emits ulisp_add_overflow_i64" (test-string-contains? c-code "ulisp_add_overflow_i64"))
    (assert-true "C backend emits ulisp_sub_overflow_i64" (test-string-contains? c-code "ulisp_sub_overflow_i64"))
    (assert-true "C backend emits ulisp_mul_overflow_i64" (test-string-contains? c-code "ulisp_mul_overflow_i64"))
    (assert-true "C backend emits unsigned division (uint64_t)" (test-string-contains? c-code "(uint64_t)reg_rbx / (uint64_t)reg_rcx"))
    (assert-true "C backend emits unsigned remainder (uint64_t)" (test-string-contains? c-code "(uint64_t)reg_rbx % (uint64_t)reg_rcx"))
    (assert-true "C backend emits unsigned right shift" (test-string-contains? c-code "(uint64_t)reg_rbx >> 3"))
    (assert-true "C backend emits unsigned comparison %setb" (test-string-contains? c-code "(uint64_t)reg_rbx < (uint64_t)reg_rcx"))
    (assert-true "C backend emits unsigned comparison %seta" (test-string-contains? c-code "(uint64_t)reg_rbx > (uint64_t)reg_rcx"))))

;;; -----------------------------------------------------------------------
;;; Group 6: AArch64 Backend Lowering Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: AArch64 Backend Lowering Verification ---\n")

(let ((emitted '()))
  (set-emit-line-sink! (lambda (line) (set! emitted (cons line emitted))))
  (emit-arm-lir-instruction '(%add-overflow %rax %rdx %rbx %rcx))
  (emit-arm-lir-instruction '(%sub-overflow %rax %rdx %rbx %rcx))
  (emit-arm-lir-instruction '(%mul-overflow %rax %rdx %rbx %rcx))
  (emit-arm-lir-instruction '(%udiv %rax %rbx %rcx))
  (emit-arm-lir-instruction '(%urem %rdx %rbx %rcx))
  (emit-arm-lir-instruction '(%shr %rax %rbx 3))
  (emit-arm-lir-instruction '(%setb %rax %rbx %rcx))
  (emit-arm-lir-instruction '(%seta %rax %rbx %rcx))
  (set-emit-line-sink! #f)
  (let ((arm-code (apply string-append (reverse (map (lambda (l) (string-append l "\n")) emitted)))))
    (assert-true "AArch64 emits adds for %add-overflow" (test-string-contains? arm-code "adds"))
    (assert-true "AArch64 emits cset ..., vs for overflow flag" (test-string-contains? arm-code "cset x2, vs"))
    (assert-true "AArch64 emits subs for %sub-overflow" (test-string-contains? arm-code "subs"))
    (assert-true "AArch64 emits smulh for %mul-overflow" (test-string-contains? arm-code "smulh"))
    (assert-true "AArch64 emits udiv for %udiv" (test-string-contains? arm-code "udiv"))
    (assert-true "AArch64 emits msub for %urem" (test-string-contains? arm-code "msub"))
    (assert-true "AArch64 emits lsr for %shr" (test-string-contains? arm-code "lsr"))
    (assert-true "AArch64 emits cset ..., cc for %setb" (test-string-contains? arm-code "cset x0, cc"))
    (assert-true "AArch64 emits cset ..., hi for %seta" (test-string-contains? arm-code "cset x0, hi"))))

;;; -----------------------------------------------------------------------
;;; Group 7: Nanopass Schema & Defs Extraction Integration
;;; -----------------------------------------------------------------------
(display "\n--- Group 7: Nanopass Schema & Defs Extraction ---\n")

(let* ((prog (make-test-lir-program
              '()
              '((%add-overflow %rax %rdx %rbx 10)
                (%udiv %rax %rax %rcx)
                (%urem %rdx %rax 5)
                (%setb %rax %rbx %rcx)
                (%return))))
       (recognized? (L_lir_canonical? prog)))
  (assert-true "L_lir_canonical? accepts program with new overflow/unsigned opcodes" recognized?))

(let ((defs-add (lir-inst-extract-defs '(%add-overflow %rax %rdx %rbx %rcx))))
  (assert-equal "%add-overflow extracts both dst-val and dst-flag as definitions"
                '(%rax %rdx) defs-add))

(let ((defs-udiv (lir-inst-extract-defs '(%udiv %rax %rbx %rcx))))
  (assert-equal "3-operand %udiv extracts destination register as definition"
                '(%rax) defs-udiv))

(let ((defs-udiv1 (lir-inst-extract-defs '(%udiv %rcx))))
  (assert-equal "1-operand %udiv extracts (%rax %rdx) as definitions"
                '(%rax %rdx) defs-udiv1))

(let ((defs-setb (lir-inst-extract-defs '(%setb %rax))))
  (assert-equal "%setb extracts destination register as definition"
                '(%rax) defs-setb))

;;; -----------------------------------------------------------------------
;;; Summary Report
;;; -----------------------------------------------------------------------
(display "\n=======================================================\n")
(display " Tests Run:    ") (display (car *test-count*)) (newline)
(display " Tests Passed: ") (display (car *pass-count*)) (newline)
(display "=======================================================\n")

(if (= (car *test-count*) (car *pass-count*))
    (display "All LIR Overflow & Unsigned Operations Tests Passed Successfully!\n")
    (error "Some tests failed!"))
