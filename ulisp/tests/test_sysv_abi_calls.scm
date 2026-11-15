;;; =======================================================================
;;; Unit Test Suite: Calling Conventions (SysV AMD64 ABI & Scheme Fast)
;;; Issue #829 - Conforms to DSN-38 Section 2 (C2/E5/E6) & DSN-33-02 Section 5.1
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Calling Conventions & SysV ABI Suite (#829)\n")
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

(define (make-test-lir-program funcs main-insts)
  (list '%lir-program
        '(strings ())
        '(stackmaps ())
        (cons '%lir-functions funcs)
        (list '%lir-main
              '(frame-size 16)
              (cons 'body main-insts))))

;;; -----------------------------------------------------------------------
;;; Group 1: Calling Convention Registry & Predicates
;;; -----------------------------------------------------------------------
(print-group "--- Group 1: Calling Convention Registry & Predicates ---")

(assert-true "calling-convention? recognizes sysv-abi"
             (calling-convention? 'sysv-abi))
(assert-true "calling-convention? recognizes scheme-fast"
             (calling-convention? 'scheme-fast))
(assert-true "calling-convention? recognizes aapcs64"
             (calling-convention? 'aapcs64))
(assert-true "calling-convention? recognizes cdecl"
             (calling-convention? 'cdecl))
(assert-false "calling-convention? rejects unknown convention"
              (calling-convention? 'unknown-convention-foo))
(assert-equal "default-calling-convention returns scheme-fast"
              'scheme-fast
              (default-calling-convention))

;;; -----------------------------------------------------------------------
;;; Group 2: Type Classification for ABI Placement
;;; -----------------------------------------------------------------------
(print-group "--- Group 2: Type Classification for ABI Placement ---")

(assert-true "arg-type-float? for f64" (arg-type-float? 'f64))
(assert-true "arg-type-float? for f32" (arg-type-float? 'f32))
(assert-true "arg-type-float? for double" (arg-type-float? 'double))
(assert-true "arg-type-float? for float" (arg-type-float? 'float))
(assert-false "arg-type-float? for i64" (arg-type-float? 'i64))
(assert-false "arg-type-float? for ptr" (arg-type-float? 'ptr))
(assert-false "arg-type-float? for fixnum" (arg-type-float? 'fixnum))

(assert-true "arg-type-integer? for i64" (arg-type-integer? 'i64))
(assert-true "arg-type-integer? for ptr" (arg-type-integer? 'ptr))
(assert-true "arg-type-integer? for fixnum" (arg-type-integer? 'fixnum))
(assert-false "arg-type-integer? for f64" (arg-type-integer? 'f64))

;;; -----------------------------------------------------------------------
;;; Group 3: System V AMD64 ABI Layout Planning
;;; -----------------------------------------------------------------------
(print-group "--- Group 3: System V AMD64 ABI Layout Planning ---")

;; Test 3.1: Zero arguments
(let ((layout (compute-call-abi-layout 'sysv-abi '() #f)))
  (assert-equal "sysv-abi 0-arg: locations is empty" '() (abi-layout-locations layout))
  (assert-equal "sysv-abi 0-arg: num-gpr = 0" 0 (abi-layout-num-gpr layout))
  (assert-equal "sysv-abi 0-arg: num-xmm = 0" 0 (abi-layout-num-xmm layout))
  (assert-equal "sysv-abi 0-arg: stack-bytes = 0" 0 (abi-layout-stack-bytes layout))
  (assert-equal "sysv-abi 0-arg: al-val = #f" #f (abi-layout-al-val layout)))

;; Test 3.2: 3 Integer/Pointer arguments
(let* ((layout (compute-call-abi-layout 'sysv-abi '(i64 ptr i32) #f))
       (locs (abi-layout-locations layout)))
  (assert-equal "sysv-abi 3-arg: num-gpr = 3" 3 (abi-layout-num-gpr layout))
  (assert-equal "sysv-abi 3-arg: num-xmm = 0" 0 (abi-layout-num-xmm layout))
  (assert-equal "sysv-abi 3-arg: stack-bytes = 0" 0 (abi-layout-stack-bytes layout))
  (assert-equal "sysv-abi 3-arg loc 0: %rdi" '%rdi (abi-arg-loc-target (list-ref locs 0)))
  (assert-equal "sysv-abi 3-arg loc 1: %rsi" '%rsi (abi-arg-loc-target (list-ref locs 1)))
  (assert-equal "sysv-abi 3-arg loc 2: %rdx" '%rdx (abi-arg-loc-target (list-ref locs 2))))

;; Test 3.3: Mixed GPR and XMM arguments with Varargs
(let* ((layout (compute-call-abi-layout 'sysv-abi '(ptr f64 i64 f64) #t))
       (locs (abi-layout-locations layout)))
  (assert-equal "sysv-abi mixed varargs: num-gpr = 2" 2 (abi-layout-num-gpr layout))
  (assert-equal "sysv-abi mixed varargs: num-xmm = 2" 2 (abi-layout-num-xmm layout))
  (assert-equal "sysv-abi mixed varargs: al-val = 2" 2 (abi-layout-al-val layout))
  (assert-equal "sysv-abi mixed loc 0: %rdi (gpr)" '%rdi (abi-arg-loc-target (list-ref locs 0)))
  (assert-equal "sysv-abi mixed loc 1: %xmm0 (xmm)" '%xmm0 (abi-arg-loc-target (list-ref locs 1)))
  (assert-equal "sysv-abi mixed loc 2: %rsi (gpr)" '%rsi (abi-arg-loc-target (list-ref locs 2)))
  (assert-equal "sysv-abi mixed loc 3: %xmm1 (xmm)" '%xmm1 (abi-arg-loc-target (list-ref locs 3))))

;; Test 3.4: 8 Integer arguments (Spill to stack)
(let* ((layout (compute-call-abi-layout 'sysv-abi '(i64 i64 i64 i64 i64 i64 i64 i64) #f))
       (locs (abi-layout-locations layout)))
  (assert-equal "sysv-abi 8-arg: num-gpr = 6" 6 (abi-layout-num-gpr layout))
  (assert-equal "sysv-abi 8-arg: stack-bytes = 16" 16 (abi-layout-stack-bytes layout))
  (assert-equal "sysv-abi 8-arg: padding-bytes = 0" 0 (abi-layout-padding-bytes layout))
  (assert-equal "sysv-abi 8-arg loc 5: %r9" '%r9 (abi-arg-loc-target (list-ref locs 5)))
  (assert-equal "sysv-abi 8-arg loc 6: stack offset 0" 'stack (abi-arg-loc-kind (list-ref locs 6)))
  (assert-equal "sysv-abi 8-arg loc 6 offset" 0 (abi-arg-loc-offset (list-ref locs 6)))
  (assert-equal "sysv-abi 8-arg loc 7: stack offset 8" 'stack (abi-arg-loc-kind (list-ref locs 7)))
  (assert-equal "sysv-abi 8-arg loc 7 offset" 8 (abi-arg-loc-offset (list-ref locs 7))))

;; Test 3.5: 7 Integer arguments (Stack alignment padding verification)
(let* ((layout (compute-call-abi-layout 'sysv-abi '(i64 i64 i64 i64 i64 i64 i64) #f)))
  (assert-equal "sysv-abi 7-arg: stack-bytes = 8" 8 (abi-layout-stack-bytes layout))
  (assert-equal "sysv-abi 7-arg: padding-bytes = 8 (for 16-byte alignment)" 8 (abi-layout-padding-bytes layout))
  (assert-equal "sysv-abi 7-arg: total-shift = 16" 16 (abi-layout-total-shift layout)))

;; Test 3.6: 9 Floating-point arguments (XMM register exhaustion)
(let* ((layout (compute-call-abi-layout 'sysv-abi '(f64 f64 f64 f64 f64 f64 f64 f64 f64) #f))
       (locs (abi-layout-locations layout)))
  (assert-equal "sysv-abi 9-float: num-xmm = 8" 8 (abi-layout-num-xmm layout))
  (assert-equal "sysv-abi 9-float loc 7: %xmm7" '%xmm7 (abi-arg-loc-target (list-ref locs 7)))
  (assert-equal "sysv-abi 9-float loc 8: stack spill" 'stack (abi-arg-loc-kind (list-ref locs 8)))
  (assert-equal "sysv-abi 9-float loc 8 offset: 0" 0 (abi-arg-loc-offset (list-ref locs 8))))

;;; -----------------------------------------------------------------------
;;; Group 4: 16-Byte Stack Alignment Calculations
;;; -----------------------------------------------------------------------
(print-group "--- Group 4: 16-Byte Stack Alignment Calculations ---")

(assert-equal "align-frame-shift for 0 is 8" 8 (align-frame-shift 0))
(assert-equal "align-frame-shift for 8 is 8" 8 (align-frame-shift 8))
(assert-equal "align-frame-shift for 16 is 24" 24 (align-frame-shift 16))
(assert-equal "align-frame-shift for 24 is 24" 24 (align-frame-shift 24))

(assert-equal "stack alignment invariant: (8 + align-frame-shift(8)) % 16 == 0"
              0
              (modulo (+ 8 (align-frame-shift 8)) 16))
(assert-equal "stack alignment invariant: (8 + align-frame-shift(16)) % 16 == 0"
              0
              (modulo (+ 8 (align-frame-shift 16)) 16))
(assert-equal "stack alignment invariant: (8 + align-frame-shift(24)) % 16 == 0"
              0
              (modulo (+ 8 (align-frame-shift 24)) 16))

;;; -----------------------------------------------------------------------
;;; Group 5: LIR Lowering of %c-call & %call-foreign
;;; -----------------------------------------------------------------------
(print-group "--- Group 5: LIR Lowering of %c-call & %call-foreign ---")

;; Test 5.1: Parse foreign args helper
(let ((parsed (parse-foreign-args '((i64 100) (f64 3.14) "hello"))))
  (assert-equal "parse-foreign-args types" '(i64 f64 string) (car parsed))
  (assert-equal "parse-foreign-args exprs" '(100 3.14 "hello") (cdr parsed)))

;; Test 5.2: Compile %c-call to puts
(reset-lir!)
(track-lir-si! -8)
(lir-compile-expr '(%c-call "puts" ("Hello, SysV!")) -8 '() #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "emitted %sub %rax 3 for string cstr"
               (member '(%sub %rax 3) insts))
  (assert-true "emitted %load %rdi for arg 0"
               (member '(%load %rdi %rsp -8) insts))
  (assert-true "emitted %c-call puts instruction"
               (let loop ((is insts))
                 (cond
                   ((null? is) #f)
                   ((and (pair? (car is)) (eq? (caar is) '%c-call) (string=? (cadar is) "puts")) #t)
                   (else (loop (cdr is)))))))

;; Test 5.3: Compile %c-call to printf with Varargs
(reset-lir!)
(track-lir-si! -8)
(lir-compile-expr '(%c-call "printf" ("Val: %d\n" (i64 42)) int #t) -8 '() #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "varargs printf with 0 XMM emits %c-call with al-val 0"
               (let loop ((is insts))
                 (cond
                   ((null? is) #f)
                   ((and (pair? (car is))
                         (eq? (caar is) '%c-call)
                         (string=? (cadar is) "printf")
                         (eq? (car (cdddar is)) 0))
                    #t)
                   (else (loop (cdr is)))))))

;; Test 5.4: Compile %c-call to printf with Floating-Point Varargs
(reset-lir!)
(track-lir-si! -8)
(lir-compile-expr '(%c-call "printf" ("Float: %f\n" (f64 3.14)) int #t) -8 '() #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "varargs printf with 1 XMM emits %c-call with al-val 1"
               (let loop ((is insts))
                 (cond
                   ((null? is) #f)
                   ((and (pair? (car is))
                         (eq? (caar is) '%c-call)
                         (string=? (cadar is) "printf")
                         (eq? (car (cdddar is)) 1))
                    #t)
                   (else (loop (cdr is)))))))

;; Test 5.5: Compile %call-foreign with void return type
(reset-lir!)
(track-lir-si! -8)
(lir-compile-expr '(%call-foreign sysv-abi void "test_exit" ()) -8 '() #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "void foreign call emits %mov %rax 63"
               (member '(%mov %rax 63) insts)))

;;; -----------------------------------------------------------------------
;;; Group 6: LIR Verifier Validation for Call ABI
;;; -----------------------------------------------------------------------
(print-group "--- Group 6: LIR Verifier Validation for Call ABI ---")

(assert-true "valid %c-call passes verifier"
             (validate-lir (make-test-lir-program '() '((%c-call "puts" 8) (%return)))))

(assert-true "valid %c-call with al-val passes verifier"
             (validate-lir (make-test-lir-program '() '((%c-call "printf" 16 2) (%return)))))

(assert-true "valid %call-foreign passes verifier"
             (validate-lir (make-test-lir-program '() '((%call-foreign "sin" 8 1) (%return)))))

(assert-false "reject %c-call with non-string/symbol target"
              (validate-lir (make-test-lir-program '() '((%c-call 123 8) (%return)))))

(assert-false "reject %c-call with missing shift"
              (validate-lir (make-test-lir-program '() '((%c-call "puts") (%return)))))

;;; -----------------------------------------------------------------------
;;; Summary
;;; -----------------------------------------------------------------------
(display "-------------------------------------------------------\n")
(display " [RESULT] Calling Conventions (SysV ABI & Scheme Fast): ")
(display (car *pass-count*))
(display " passed (Total: ")
(display (car *test-count*))
(display ")\n")
(display "-------------------------------------------------------\n")
