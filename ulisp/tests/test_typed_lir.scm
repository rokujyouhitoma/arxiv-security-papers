;;; =======================================================================
;;; Unit Test Suite: Typed Machine LIR & Orthogonal Boxing (Issue #826)
;;; Conforms to DSN-33 Architecture Specification & Nanopass Quality Standards
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Typed Machine LIR Unit Test Suite (#826)\n")
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

;; Helper to build minimal valid LIR program with custom main and funcs
(define (make-test-lir-program funcs main-insts)
  (list '%lir-program
        '(strings ())
        '(stackmaps ())
        (cons '%lir-functions funcs)
        (list '%lir-main
              '(frame-size 16)
              (cons 'body main-insts))))

;;; -----------------------------------------------------------------------
;;; Group 1: Machine Types & Float Register Classification
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Machine Types & Register Classification ---\n")

;; 1.1 Machine types validation
(assert-true "machine type: i8" (lir-machine-type? 'i8))
(assert-true "machine type: i16" (lir-machine-type? 'i16))
(assert-true "machine type: i32" (lir-machine-type? 'i32))
(assert-true "machine type: i64" (lir-machine-type? 'i64))
(assert-true "machine type: u8" (lir-machine-type? 'u8))
(assert-true "machine type: u16" (lir-machine-type? 'u16))
(assert-true "machine type: u32" (lir-machine-type? 'u32))
(assert-true "machine type: u64" (lir-machine-type? 'u64))
(assert-true "machine type: f32" (lir-machine-type? 'f32))
(assert-true "machine type: f64" (lir-machine-type? 'f64))
(assert-true "machine type: ptr" (lir-machine-type? 'ptr))
(assert-true "machine type: raw-bits" (lir-machine-type? 'raw-bits))
(assert-true "machine type: scheme-val" (lir-machine-type? 'scheme-val))
(assert-false "reject invalid machine type" (lir-machine-type? 'unknown-type))

;; 1.2 Float register recognition
(assert-true "float register: %xmm0" (lir-float-register? '%xmm0))
(assert-true "float register: %xmm7" (lir-float-register? '%xmm7))
(assert-true "float register: %xmm15" (lir-float-register? '%xmm15))
(assert-true "float register: (%freg r)" (lir-float-register? '(%freg r)))
(assert-true "float register: (%reg f64 r)" (lir-float-register? '(%reg f64 r)))
(assert-false "gpr is not float register: %rax" (lir-float-register? '%rax))
(assert-false "gpr is not float register: %rsp" (lir-float-register? '%rsp))

;; 1.3 General register validation includes float registers
(assert-true "valid register: %rax" (lir-valid-register? '%rax))
(assert-true "valid register: %xmm0" (lir-valid-register? '%xmm0))
(assert-true "valid register: (%reg i32 x)" (lir-valid-register? '(%reg i32 x)))
(assert-true "valid register: (%reg f64 x)" (lir-valid-register? '(%reg f64 x)))
(assert-false "reject unknown register symbol" (lir-valid-register? '%invalid-reg))

;;; -----------------------------------------------------------------------
;;; Group 2: Typed Load & Store Instructions
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Typed Load & Store Instructions ---\n")

;; 2.1 Valid typed loads
(assert-true "valid %load-typed i8"
             (validate-lir
              (make-test-lir-program '()
                                     '((%load-typed i8 %rax %rsp 0)
                                       (%return)))))

(assert-true "valid %load-typed u16"
             (validate-lir
              (make-test-lir-program '()
                                     '((%load-typed u16 %rax %rsp 8)
                                       (%return)))))

(assert-true "valid %load-typed i32"
             (validate-lir
              (make-test-lir-program '()
                                     '((%load-typed i32 %rax %rsp 16)
                                       (%return)))))

(assert-true "valid %load-typed i64"
             (validate-lir
              (make-test-lir-program '()
                                     '((%load-typed i64 %rax %rsp 24)
                                       (%return)))))

(assert-true "valid %load-typed f64 to %xmm0"
             (validate-lir
              (make-test-lir-program '()
                                     '((%load-typed f64 %xmm0 %rsp 0)
                                       (%return)))))

(assert-true "valid %load-typed ptr"
             (validate-lir
              (make-test-lir-program '()
                                     '((%load-typed ptr %rax %rsp 8)
                                       (%return)))))

;; 2.2 Valid typed stores
(assert-true "valid %store-typed i8"
             (validate-lir
              (make-test-lir-program '()
                                     '((%store-typed i8 %rsp 0 %rax)
                                       (%return)))))

(assert-true "valid %store-typed i32 immediate"
             (validate-lir
              (make-test-lir-program '()
                                     '((%store-typed i32 %rsp 0 42)
                                       (%return)))))

(assert-true "valid %store-typed f64 from %xmm0"
             (validate-lir
              (make-test-lir-program '()
                                     '((%store-typed f64 %rsp 8 %xmm0)
                                       (%return)))))

;;; -----------------------------------------------------------------------
;;; Group 3: Floating-Point Arithmetic Instructions
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Floating-Point Arithmetic Instructions ---\n")

(assert-true "valid %fmov"
             (validate-lir
              (make-test-lir-program '()
                                     '((%fmov %xmm0 %xmm1)
                                       (%return)))))

(assert-true "valid %fadd"
             (validate-lir
              (make-test-lir-program '()
                                     '((%fadd %xmm0 %xmm1)
                                       (%return)))))

(assert-true "valid %fsub"
             (validate-lir
              (make-test-lir-program '()
                                     '((%fsub %xmm0 %xmm2)
                                       (%return)))))

(assert-true "valid %fmul"
             (validate-lir
              (make-test-lir-program '()
                                     '((%fmul %xmm0 %xmm3)
                                       (%return)))))

(assert-true "valid %fdiv"
             (validate-lir
              (make-test-lir-program '()
                                     '((%fdiv %xmm0 %xmm4)
                                       (%return)))))

(assert-true "valid %fcmp"
             (validate-lir
              (make-test-lir-program '()
                                     '((%fcmp %xmm0 %xmm1)
                                       (%return)))))

;;; -----------------------------------------------------------------------
;;; Group 4: CWE-843 Type Confusion Defense & Rejection Tests
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: CWE-843 Type Confusion Defense ---\n")

;; 4.1 Reject integer register passed to float arithmetic (%fadd %rax %rbx)
(assert-false "reject integer register passed to %fadd"
              (validate-lir
               (make-test-lir-program '()
                                      '((%fadd %rax %rbx)
                                        (%return)))))

;; 4.2 Reject %load-typed f64 into general-purpose integer register
(assert-false "reject %load-typed f64 into %rax"
              (validate-lir
               (make-test-lir-program '()
                                      '((%load-typed f64 %rax %rsp 0)
                                        (%return)))))

;; 4.3 Reject %store-typed f64 from integer register
(assert-false "reject %store-typed f64 from %rax"
              (validate-lir
               (make-test-lir-program '()
                                      '((%store-typed f64 %rsp 0 %rax)
                                        (%return)))))

;; 4.4 Reject invalid machine type in %load-typed
(assert-false "reject invalid machine type in %load-typed"
              (validate-lir
               (make-test-lir-program '()
                                      '((%load-typed bad-type %rax %rsp 0)
                                        (%return)))))

;;; -----------------------------------------------------------------------
;;; Group 5: Conversions & Orthogonal Boxing Operations
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Conversions & Orthogonal Boxing ---\n")

(assert-true "valid %sitofp (int to float)"
             (validate-lir
              (make-test-lir-program '()
                                     '((%sitofp %xmm0 %rax)
                                       (%return)))))

(assert-true "valid %fptosi (float to int)"
             (validate-lir
              (make-test-lir-program '()
                                     '((%fptosi %rax %xmm0)
                                       (%return)))))

(assert-true "valid %box-flonum"
             (validate-lir
              (make-test-lir-program '()
                                     '((%box-flonum %rax %xmm0)
                                       (%return)))))

(assert-true "valid %unbox-flonum"
             (validate-lir
              (make-test-lir-program '()
                                     '((%unbox-flonum %xmm0 %rax)
                                       (%return)))))

(assert-true "valid %trunc"
             (validate-lir
              (make-test-lir-program '()
                                     '((%trunc i32 %rax %rbx)
                                       (%return)))))

(assert-true "valid %zext"
             (validate-lir
              (make-test-lir-program '()
                                     '((%zext u32 %rax %rbx)
                                       (%return)))))

(assert-true "valid %sext"
             (validate-lir
              (make-test-lir-program '()
                                     '((%sext i32 %rax %rbx)
                                       (%return)))))

;;; -----------------------------------------------------------------------
;;; Group 6: Pass 133 Peephole Box-Unbox Pair Elimination
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Peephole Box-Unbox Optimization ---\n")

(define (extract-main-body prog)
  (let ((main-entry (assq '%lir-main (cddr prog))))
    (if main-entry
        (let ((b (assq 'body (cdr main-entry))))
          (if b (cdr b) '()))
        '())))

(define (run-peephole-on-insts insts)
  (let* ((prog (make-test-lir-program '() insts))
         (opt (lir-peephole-optimize prog)))
    (extract-main-body opt)))

;; 6.1 Fixnum box then unbox to different register
(let* ((in-insts '((%box-fixnum %rax %rbx)
                   (%unbox-fixnum %rcx %rax)
                   (%return)))
       (out (run-peephole-on-insts in-insts)))
  (assert-equal "redundant box-unbox fixnum forwarded to mov"
                '((%mov %rcx %rbx) (%return))
                out))

;; 6.2 Fixnum unbox then box to different register
(let* ((in-insts '((%unbox-fixnum %rax %rbx)
                   (%box-fixnum %rcx %rax)
                   (%return)))
       (out (run-peephole-on-insts in-insts)))
  (assert-equal "redundant unbox-box fixnum forwarded to mov"
                '((%mov %rcx %rbx) (%return))
                out))

;; 6.3 Flonum box then unbox cancels directly to fmov
(let* ((in-insts '((%box-flonum %rax %xmm0)
                   (%unbox-flonum %xmm1 %rax)
                   (%return)))
       (out (run-peephole-on-insts in-insts)))
  (assert-equal "redundant box-unbox flonum forwarded to fmov"
                '((%fmov %xmm1 %xmm0) (%return))
                out))

;; 6.4 Roundtrip self-cancelling box-unbox eliminated
(let* ((in-insts '((%box-fixnum %rax %rax)
                   (%unbox-fixnum %rax %rax)
                   (%return)))
       (out (run-peephole-on-insts in-insts)))
  (assert-equal "self-cancelling fixnum box-unbox removed completely"
                '((%return))
                out))

;;; -----------------------------------------------------------------------
;;; Group 7: Backend Lowering Code Generation
;;; -----------------------------------------------------------------------
(display "\n--- Group 7: Backend Lowering Code Generation ---\n")

;; 7.1 x86_64 lowering of %load-typed i8
(let ((lowered (lower-lir-instruction '(%load-typed i8 %rax %rsp 0))))
  (assert-equal "%load-typed i8 lowers to movsx"
                '((%raw-asm "    movsx rax, byte ptr [rsp - 0]"))
                lowered))

;; 7.2 x86_64 lowering of %load-typed u16
(let ((lowered (lower-lir-instruction '(%load-typed u16 %rax %rsp 8))))
  (assert-equal "%load-typed u16 lowers to movzx"
                '((%raw-asm "    movzx rax, word ptr [rsp + 8]"))
                lowered))

;; 7.3 x86_64 lowering of %load-typed f64
(let ((lowered (lower-lir-instruction '(%load-typed f64 %xmm0 %rsp 16))))
  (assert-equal "%load-typed f64 lowers to movsd"
                '((%raw-asm "    movsd xmm0, qword ptr [rsp + 16]"))
                lowered))

;; 7.4 x86_64 lowering of %fadd
(let ((lowered (lower-lir-instruction '(%fadd %xmm0 %xmm1))))
  (assert-equal "%fadd lowers to addsd"
                '((%raw-asm "    addsd xmm0, xmm1"))
                lowered))

;; 7.5 x86_64 lowering of %sitofp
(let ((lowered (lower-lir-instruction '(%sitofp %xmm0 %rax))))
  (assert-equal "%sitofp lowers to cvtsi2sd"
                '((%raw-asm "    cvtsi2sd xmm0, rax"))
                lowered))

;; 7.6 x86_64 lowering of %fptosi
(let ((lowered (lower-lir-instruction '(%fptosi %rax %xmm0))))
  (assert-equal "%fptosi lowers to cvttsd2si"
                '((%raw-asm "    cvttsd2si rax, xmm0"))
                lowered))

;;; -----------------------------------------------------------------------
;;; Final Report
;;; -----------------------------------------------------------------------
(display "\n=======================================================\n")
(display " Typed Machine LIR Test Suite Finished\n")
(display " Passed: ")
(display (car *pass-count*))
(display " / ")
(display (car *test-count*))
(newline)
(display "=======================================================\n")
(if (= (car *pass-count*) (car *test-count*))
    (display "ALL TYPED MACHINE LIR TESTS PASSED!\n")
    (error "Some tests failed!"))
