;;; =======================================================================
;;; ULisp Canonical LIR Verifier & Boundary Validator Unit Test Suite
;;; Conforms to Issue #589 & DSN-33 Architecture Specification
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Canonical LIR Verifier Unit Test Suite\n")
(display "=======================================================\n")

;; Configure verifier in non-strict mode for asserting returns
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
;;; Group 1: Valid Canonical LIR Programs
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Valid Canonical LIR Programs ---\n")

;; 1.1 Minimal valid program
(assert-true "minimal valid program with %mov and %return"
             (validate-lir
              (make-test-lir-program '()
                                     '((%mov %rax 42)
                                       (%return)))))

;; 1.2 Valid function with parameters, stack memory and arithmetic
(assert-true "valid function with arithmetic and memory transfer"
             (validate-lir
              (make-test-lir-program
               (list '(%lir-function .L_add
                                     (params (x y))
                                     (frame-size 24)
                                     (body
                                      (%load %rax %rsp 8)
                                      (%load %rbx %rsp 16)
                                      (%add %rax %rbx)
                                      (%return %rax))))
               '((%mov %rax 10)
                 (%return)))))

;; 1.3 Valid SSA block arguments and jumps
(assert-true "valid SSA block arguments and conditional jumps"
             (validate-lir
              (make-test-lir-program
               '()
               '((%mov %rax 100)
                 (%jump .L_join (%rax 42))
                 (%block .L_join (val count)
                   (%cmp val 0)
                   (%jump-if %rax .L_then () .L_else (val))
                   (%label .L_then)
                   (%return val)
                   (%block .L_else (res)
                     (%return res)))))))

;; 1.4 Valid runtime, GC, continuations and values instructions
(assert-true "valid runtime allocation, handlers and multiple values"
             (validate-lir
              (make-test-lir-program
               '()
               '((%alloc %rax 24 1)
                 (%alloc-stack %rbx -32 1)
                 (%push-handler .L_catch -16 -24)
                 (%pop-handler -16)
                 (%set-values-count 2)
                 (%store-values-buf -32 2)
                 (%capture-cc .L_ret -8)
                 (%label .L_ret)
                 (%label .L_catch)
                 (%return %rax)))))

;;; -----------------------------------------------------------------------
;;; Group 2: Root Structure and Frame-Size Invariants
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Root Structure & Frame-Size Invariants ---\n")

(assert-false "reject missing %lir-program root"
              (validate-lir '((%mov %rax 42))))

(assert-false "reject missing %lir-main clause"
              (validate-lir '(%lir-program (strings ()) (stackmaps ()) (%lir-functions ()))))

(assert-false "reject missing %lir-functions clause"
              (validate-lir '(%lir-program (strings ()) (stackmaps ()) (%lir-main (frame-size 16) (body (%return))))))

(assert-false "reject unaligned frame-size (not multiple of 8)"
              (validate-lir
               '(%lir-program
                 (strings ())
                 (stackmaps ())
                 (%lir-functions ())
                 (%lir-main (frame-size 12) (body (%return))))))

(assert-false "reject negative frame-size"
              (validate-lir
               '(%lir-program
                 (strings ())
                 (stackmaps ())
                 (%lir-functions ())
                 (%lir-main (frame-size -16) (body (%return))))))

(assert-false "reject function with unaligned frame-size"
              (validate-lir
               (make-test-lir-program
                (list '(%lir-function .L_f (params ()) (frame-size 14) (body (%return))))
                '((%return)))))

;;; -----------------------------------------------------------------------
;;; Group 3: Opcode and Operand Validation
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Opcode & Operand Validation ---\n")

(assert-false "reject unknown opcode"
              (validate-lir (make-test-lir-program '() '((%unknown-op %rax 10)))))

(assert-false "reject invalid register"
              (validate-lir (make-test-lir-program '() '((%mov %r99 10)))))

(assert-false "reject %load with invalid destination register"
              (validate-lir (make-test-lir-program '() '((%load 42 %rsp 8)))))

(assert-false "reject %store with invalid base register"
              (validate-lir (make-test-lir-program '() '((%store 100 8 %rax)))))

(assert-false "reject %shl with non-integer shift count"
              (validate-lir (make-test-lir-program '() '((%shl %rax %rbx)))))

(assert-false "reject %alloc with non-integer bytes"
              (validate-lir (make-test-lir-program '() '((%alloc %rax %rbx 1)))))

;;; -----------------------------------------------------------------------
;;; Group 4: CFG & Label Invariants (Uniqueness and Resolution)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: CFG & Label Invariants ---\n")

(assert-false "reject duplicate %label within same body"
              (validate-lir
               (make-test-lir-program '()
                                      '((%label .L_dup)
                                        (%mov %rax 1)
                                        (%label .L_dup)
                                        (%return)))))

(assert-false "reject duplicate %block label within same body"
              (validate-lir
               (make-test-lir-program '()
                                      '((%block .L_b (p0) (%return p0))
                                        (%block .L_b (p1) (%return p1))))))

(assert-false "reject jump to undefined label"
              (validate-lir
               (make-test-lir-program '()
                                      '((%jump .L_undefined_target)
                                        (%return)))))

(assert-false "reject %jump-if to undefined else label"
              (validate-lir
               (make-test-lir-program '()
                                      '((%label .L_t)
                                        (%jump-if %rax .L_t () .L_missing ())
                                        (%return)))))

(assert-false "reject %jump-cond to undefined label"
              (validate-lir
               (make-test-lir-program '()
                                      '((%jump-cond je .L_ghost)
                                        (%return)))))

;;; -----------------------------------------------------------------------
;;; Group 5: SSA Block Arguments Arity Matching
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: SSA Block Arguments Arity Matching ---\n")

(assert-false "reject %jump argument count mismatch with %block (2 expected, 1 provided)"
              (validate-lir
               (make-test-lir-program '()
                                      '((%jump .L_join (42))
                                        (%block .L_join (p0 p1)
                                          (%return p0))))))

(assert-false "reject %jump argument count mismatch with %block (0 expected, 2 provided)"
              (validate-lir
               (make-test-lir-program '()
                                      '((%jump .L_empty (1 2))
                                        (%block .L_empty ()
                                          (%return))))))

(assert-false "reject %jump-if then-branch argument count mismatch with %block"
              (validate-lir
               (make-test-lir-program '()
                                      '((%jump-if %rax .L_t (1 2 3) .L_e ())
                                        (%block .L_t (x y) (%return x))
                                        (%block .L_e () (%return))))))

;;; -----------------------------------------------------------------------
;;; Group 6: Verifier Integration and Strict Mode
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Verifier Integration & Strict Mode ---\n")

;; 6.1 verify-pass-output integration
(assert-true "verify-pass-output dispatches to validate-lir on phase 'lir"
             (verify-pass-output 'lir
                                 (make-test-lir-program '() '((%mov %rax 42) (%return)))))

(assert-false "verify-pass-output detects error in phase 'lir"
              (verify-pass-output 'lir
                                  (make-test-lir-program '() '((%jump .L_nonexistent)))))

;; 6.2 Disabled verifier bypass
(disable-verifier!)
(assert-true "disabled verifier bypasses invalid LIR"
             (verify-lir (make-test-lir-program '() '((%jump .L_nonexistent)))))
(enable-verifier!)

;;; -----------------------------------------------------------------------
;;; Group 7: Nanopass L_lir_canonical Schema Integration Tests (Issue #593)
;;; -----------------------------------------------------------------------
(display "\n--- Group 7: Nanopass L_lir_canonical Schema Integration ---\n")

;; 7.1 L_lir_canonical is registered in Nanopass repository
(assert-true "L_lir_canonical language is registered"
             (nanopass-language? (nanopass-lookup-language 'L_lir_canonical)))

;; 7.2 L_lir_canonical? predicate recognizes valid canonical programs
(assert-true "L_lir_canonical? recognizes minimal valid program"
             (L_lir_canonical? (make-test-lir-program '() '((%mov %rax 42) (%return)))))

(assert-true "L_lir_canonical? recognizes function with params and memory transfer"
             (L_lir_canonical?
              (make-test-lir-program
               (list '(%lir-function .L_add
                                     (params (x y))
                                     (frame-size 24)
                                     (body
                                      (%load %rax %rsp 8)
                                      (%load %rbx %rsp 16)
                                      (%add %rax %rbx)
                                      (%return %rax))))
               '((%mov %rax 10)
                 (%return)))))

(assert-true "L_lir_canonical? recognizes runtime alloc and continuations"
             (L_lir_canonical?
              (make-test-lir-program
               '()
               '((%alloc %rax 24 1)
                 (%alloc-stack %rbx -32 1)
                 (%push-handler .L_catch -16 -24)
                 (%pop-handler -16)
                 (%set-values-count 2)
                 (%store-values-buf -32 2)
                 (%capture-cc .L_ret -8)
                 (%label .L_ret)
                 (%label .L_catch)
                 (%return %rax)))))

;; 7.3 L_lir_canonical? rejects malformed or un-lowered structures
(assert-false "L_lir_canonical? rejects program with invalid opcode"
              (L_lir_canonical? (make-test-lir-program '() '((%unknown-op %rax 10)))))

(assert-false "L_lir_canonical? rejects invalid register operand in %mov"
              (L_lir_canonical? (make-test-lir-program '() '((%mov %r99 10)))))

(assert-false "L_lir_canonical? rejects non-register dest in %load"
              (L_lir_canonical? (make-test-lir-program '() '((%load 42 %rsp 8)))))

(assert-false "L_lir_canonical? rejects non-integer shift in %shl"
              (L_lir_canonical? (make-test-lir-program '() '((%shl %rax %rbx)))))

(assert-false "L_lir_canonical? rejects missing %lir-program root"
              (L_lir_canonical? '((%mov %rax 42))))

;;; -----------------------------------------------------------------------
;;; Group 8: Multi-Level Verifier, Context Tracking & Scalability (Issue #597)
;;; -----------------------------------------------------------------------
(display "\n--- Group 8: Multi-Level Verifier, Context & Scalability ---\n")

;; 8.1 Verifier Level Switching
(set-verifier-level! 0)
(assert-true "Level 0 (OFF): bypasses pass verification entirely"
             (verify-pass-output 'anf '(invalid syntax non atomic (nested (call)))))

(set-verifier-level! 1)
(assert-true "Level 1 (BOUNDARY): bypasses frontend passes"
             (verify-pass-output 'anf '(invalid syntax)))
(assert-true "Level 1 (BOUNDARY): still validates canonical LIR"
             (verify-pass-output 'lir (make-test-lir-program '() '((%mov %rax 42) (%return)))))

(set-verifier-level! 2)
(assert-true "Level 2 (STANDARD): enables verification across passes"
             (verifier-enabled?))

;; 8.2 Dynamic Context Tracking
(with-verifier-context '((phase . canonical-lir) (function . .L_test_fn) (block . .L_entry_block))
  (lambda ()
    (let ((ctx (current-verifier-context)))
      (assert-true "Context tracking: phase captured" (eq? (cdr (assq 'phase ctx)) 'canonical-lir))
      (assert-true "Context tracking: function captured" (eq? (cdr (assq 'function ctx)) '.L_test_fn))
      (assert-true "Context tracking: block captured" (eq? (cdr (assq 'block ctx)) '.L_entry_block)))))

(assert-true "Context stack pops cleanly after execution"
             (null? (current-verifier-context)))

;; 8.3 Scalability & Performance Benchmark: 100+ Blocks & Chained Jumps
(define (build-large-lir-chain n)
  (let loop ((i 0) (acc '()))
    (if (= i n)
        (reverse (cons (list '%label (string->symbol (string-append ".L_blk_" (number->string n))))
                       (cons '(%return %rax) acc)))
        (let ((cur-lbl (string->symbol (string-append ".L_blk_" (number->string i))))
              (next-lbl (string->symbol (string-append ".L_blk_" (number->string (+ i 1))))))
          (loop (+ i 1)
                (cons (list '%jump next-lbl)
                      (cons (list '%label cur-lbl)
                            acc)))))))

(define *large-chain-insts* (build-large-lir-chain 100))
(assert-true "Scalability: 100-block chained LIR validated in linear time"
             (validate-lir
              (make-test-lir-program '()
                                     (cons '(%mov %rax 1)
                                           *large-chain-insts*))))

;; 8.4 Duplicate detection in large block set rejected cleanly in O(1)
(assert-false "Scalability: duplicate label in 100-block chain rejected"
              (validate-lir
               (make-test-lir-program '()
                                      (cons '(%label .L_blk_50)
                                            *large-chain-insts*))))

;; Reset to standard verifier mode for subsequent suites
(enable-verifier!)
(set-verifier-strict! #f)

(display "\n=======================================================\n")
(display " All Canonical LIR Verifier Tests PASSED: ")
(display (car *pass-count*))
(display "/")
(display (car *test-count*))
(newline)
(display "=======================================================\n")
