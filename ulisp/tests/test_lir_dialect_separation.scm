;;; =======================================================================
;;; Unit Test Suite: ULisp Core Machine LIR & Managed Dialect Separation
;;; Conforms to DSN-33, DSN-38 Specifications & Issue #835
;;; =======================================================================

(display "=== [Test Suite: Core Machine LIR & Managed Dialect Separation (Issue #835)] ===\n")

;; Helper to build minimal test programs
(define (make-dialect-test-prog fns main-body)
  (list '%lir-program
        '(strings ())
        '(stackmaps ())
        (cons '%lir-functions fns)
        (list '%lir-main '(frame-size 0) (cons 'body main-body))))

;;; -----------------------------------------------------------------------
;;; Group 1: Nanopass Language Hierarchy & Predicates
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Nanopass Language Hierarchy & Predicates ---\n")

;; 1.1 Languages are registered in Nanopass repository
(assert-true "1.1 L_lir_core is registered"
             (nanopass-language? (nanopass-lookup-language 'L_lir_core)))

(assert-true "1.2 L_lir_managed is registered"
             (nanopass-language? (nanopass-lookup-language 'L_lir_managed)))

;; 1.2 Language inheritance chain
(assert-equal "1.3 language-parent-chain for L_lir_managed is (L_lir_core L_lir_managed)"
              '(L_lir_core L_lir_managed)
              (language-parent-chain 'L_lir_managed))

;; 1.3 L_lir_core? recognizes pure Core Machine LIR
(define pure-core-prog
  (make-dialect-test-prog
   '()
   '((%mov %rax 42)
     (%mov %rbx 10)
     (%add %rax %rbx)
     (%return %rax))))

(assert-true "1.4 L_lir_core? accepts pure Core Machine LIR program"
             (L_lir_core? pure-core-prog))

;; 1.4 L_lir_core? rejects Managed Dialect instructions
(define managed-alloc-prog
  (make-dialect-test-prog
   '()
   '((%alloc %rax 24 1)
     (%return %rax))))

(assert-false "1.5 L_lir_core? rejects program containing %alloc"
              (L_lir_core? managed-alloc-prog))

(define managed-box-prog
  (make-dialect-test-prog
   '()
   '((%mov %rax 10)
     (%box-fixnum %rax %rax)
     (%return %rax))))

(assert-false "1.6 L_lir_core? rejects program containing %box-fixnum"
              (L_lir_core? managed-box-prog))

(define managed-safepoint-prog
  (make-dialect-test-prog
   '()
   '((%managed-safepoint-poll)
     (%return 0))))

(assert-false "1.7 L_lir_core? rejects program containing %managed-safepoint-poll"
              (L_lir_core? managed-safepoint-prog))

;; 1.5 L_lir_managed? recognizes both Core and Managed Dialect
(assert-true "1.8 L_lir_managed? accepts pure Core Machine LIR program"
             (L_lir_managed? pure-core-prog))

(assert-true "1.9 L_lir_managed? accepts program containing %alloc"
             (L_lir_managed? managed-alloc-prog))

(assert-true "1.10 L_lir_managed? accepts program containing %box-fixnum"
             (L_lir_managed? managed-box-prog))

(assert-true "1.11 L_lir_managed? accepts program containing %managed-safepoint-poll"
             (L_lir_managed? managed-safepoint-prog))

;;; -----------------------------------------------------------------------
;;; Group 2: Core Machine LIR Verifier (validate-core-lir & Opcode Guards)
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Core Machine LIR Verifier ---\n")

;; 2.1 Pure Core Machine LIR passes validate-core-lir
(assert-true "2.1 validate-core-lir accepts pure Core Machine LIR"
             (validate-core-lir pure-core-prog))

;; 2.2 Managed opcodes are recognized by predicate
(assert-true "2.2 managed-dialect-opcode? recognizes %alloc"
             (managed-dialect-opcode? '%alloc))
(assert-true "2.3 managed-dialect-opcode? recognizes %alloc-stack"
             (managed-dialect-opcode? '%alloc-stack))
(assert-true "2.4 managed-dialect-opcode? recognizes %managed-alloc"
             (managed-dialect-opcode? '%managed-alloc))
(assert-true "2.5 managed-dialect-opcode? recognizes %managed-safepoint-poll"
             (managed-dialect-opcode? '%managed-safepoint-poll))
(assert-true "2.6 managed-dialect-opcode? recognizes %box-fixnum"
             (managed-dialect-opcode? '%box-fixnum))
(assert-true "2.7 managed-dialect-opcode? recognizes %unbox-fixnum"
             (managed-dialect-opcode? '%unbox-fixnum))
(assert-true "2.8 managed-dialect-opcode? recognizes %capture-cc"
             (managed-dialect-opcode? '%capture-cc))
(assert-false "2.9 managed-dialect-opcode? returns #f for core opcode %mov"
              (managed-dialect-opcode? '%mov))
(assert-false "2.10 managed-dialect-opcode? returns #f for core opcode %add"
              (managed-dialect-opcode? '%add))
(assert-false "2.11 managed-dialect-opcode? returns #f for core opcode %load"
              (managed-dialect-opcode? '%load))

;; 2.3 validate-core-lir statically rejects managed opcodes (THREAT-835-1)
(assert-false "2.12 validate-core-lir rejects %alloc"
              (validate-core-lir managed-alloc-prog))

(assert-false "2.13 validate-core-lir rejects %alloc-stack"
              (validate-core-lir
               (make-dialect-test-prog '() '((%alloc-stack %rax -32 1) (%return %rax)))))

(assert-false "2.14 validate-core-lir rejects %box-fixnum"
              (validate-core-lir managed-box-prog))

(assert-false "2.15 validate-core-lir rejects %unbox-fixnum"
              (validate-core-lir
               (make-dialect-test-prog '() '((%unbox-fixnum %rax %rax) (%return %rax)))))

(assert-false "2.16 validate-core-lir rejects %box-flonum"
              (validate-core-lir
               (make-dialect-test-prog '() '((%box-flonum %rax %xmm0) (%return %rax)))))

(assert-false "2.17 validate-core-lir rejects %capture-cc"
              (validate-core-lir
               (make-dialect-test-prog '() '((%capture-cc .L_ret -8) (%label .L_ret) (%return 0)))))

(assert-false "2.18 validate-core-lir rejects %push-handler"
              (validate-core-lir
               (make-dialect-test-prog '() '((%push-handler .L_c -16 -24) (%label .L_c) (%return 0)))))

(assert-false "2.19 validate-core-lir rejects nested %alloc inside %block"
              (validate-core-lir
               (make-dialect-test-prog
                '()
                '((%jump .L_b ())
                  (%block .L_b ()
                    (%alloc %rax 16 3)
                    (%return %rax))))))

;; 2.4 validate-lir with dialect parameter
(assert-true "2.20 validate-lir with 'core dialect succeeds on pure Core LIR"
             (validate-lir pure-core-prog 'core))

(assert-false "2.21 validate-lir with 'core dialect rejects %alloc"
              (validate-lir managed-alloc-prog 'core))

(assert-true "2.22 validate-lir without dialect parameter preserves backward compatibility"
             (validate-lir managed-alloc-prog))

;;; -----------------------------------------------------------------------
;;; Group 3: Pass 131 Lowering of Managed Dialect Instructions
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Pass 131 Lowering of Managed Dialect Instructions ---\n")

;; 3.1 %alloc lowering to bump pointer operations
(define alloc-insts '((%alloc %rax 24 1)))
(define lowered-alloc (lower-managed-inst-list alloc-insts))

(assert-equal "3.1 %alloc expands to (%mov %rax %r12) (%add %rax 1) (%add %r12 24)"
              '((%mov %rax %r12)
                (%add %rax 1)
                (%add %r12 24))
              lowered-alloc)

;; 3.2 %alloc-stack lowering to %rsp relative address
(define alloc-stack-insts '((%alloc-stack %rbx -32 1)))
(define lowered-alloc-stack (lower-managed-inst-list alloc-stack-insts))

(assert-equal "3.2 %alloc-stack expands to (%mov %rbx %rsp) (%add %rbx -31)"
              '((%mov %rbx %rsp)
                (%add %rbx -31))
              lowered-alloc-stack)

;; 3.3 %box-fixnum lowering (same dst/src)
(define box-same '((%box-fixnum %rax %rax)))
(assert-equal "3.3 %box-fixnum same reg expands to (%shl %rax 2)"
              '((%shl %rax 2))
              (lower-managed-inst-list box-same))

;; 3.4 %box-fixnum lowering (different dst/src)
(define box-diff '((%box-fixnum %rax %rcx)))
(assert-equal "3.4 %box-fixnum different reg expands to (%mov %rax %rcx) (%shl %rax 2)"
              '((%mov %rax %rcx)
                (%shl %rax 2))
              (lower-managed-inst-list box-diff))

;; 3.5 %unbox-fixnum lowering (same dst/src)
(define unbox-same '((%unbox-fixnum %rax %rax)))
(assert-equal "3.5 %unbox-fixnum same reg expands to (%sar %rax 2)"
              '((%sar %rax 2))
              (lower-managed-inst-list unbox-same))

;; 3.6 %unbox-fixnum lowering (different dst/src)
(define unbox-diff '((%unbox-fixnum %rax %rcx)))
(assert-equal "3.6 %unbox-fixnum different reg expands to (%mov %rax %rcx) (%sar %rax 2)"
              '((%mov %rax %rcx)
                (%sar %rax 2))
              (lower-managed-inst-list unbox-diff))

;; 3.7 %managed-safepoint-poll lowering
(define safepoint-insts '((%managed-safepoint-poll)))
(assert-equal "3.7 %managed-safepoint-poll expands to (%safepoint-poll)"
              '((%safepoint-poll))
              (lower-managed-inst-list safepoint-insts))

;; 3.8 %managed-write-barrier lowering
(define wb-insts '((%managed-write-barrier %rdi 16 %rsi)))
(assert-equal "3.8 %managed-write-barrier expands to card table store sequence"
              '((%mov %r11 %rdi)
                (%add %r11 16)
                (%shr %r11 9)
                (%global-ref %r10 ulisp_card_table_base)
                (%store-byte %r10 %r11 1))
              (lower-managed-inst-list wb-insts))

;; 3.9 Nested %block lowering
(define block-insts
  '((%block .L_worker (count state)
      (%alloc %rax 16 3)
      (%box-fixnum %rbx count)
      (%jump .L_done (%rax %rbx)))))

(define lowered-block (lower-managed-inst-list block-insts))
(assert-equal "3.9 nested %block lowers interior managed instructions"
              '((%block .L_worker (count state)
                  (%mov %rax %r12)
                  (%add %rax 3)
                  (%add %r12 16)
                  (%mov %rbx count)
                  (%shl %rbx 2)
                  (%jump .L_done (%rax %rbx))))
              lowered-block)

;; 3.10 Full program lowering
(define full-managed-prog
  (make-dialect-test-prog
   (list '(%lir-function .L_helper
                          (params (n))
                          (frame-size 16)
                          (body
                           (%alloc %rax 32 9)
                           (%box-fixnum %rax n)
                           (%return %rax))))
   '((%alloc %rax 24 1)
     (%alloc-stack %rbx -16 1)
     (%box-fixnum %rcx 42)
     (%return %rax))))

(define lowered-full-prog (lower-managed-dialect full-managed-prog))

(assert-true "3.11 full program lowering output satisfies validate-core-lir"
             (validate-core-lir lowered-full-prog))

(assert-true "3.12 full program lowering output satisfies L_lir_core?"
             (L_lir_core? lowered-full-prog))

;;; -----------------------------------------------------------------------
;;; Group 4: Reference VM Execution of Lowered Core Machine LIR
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Reference VM Execution of Lowered Core Machine LIR ---\n")

;; 4.1 Evaluation of pure Core LIR
(assert-equal "4.1 Reference VM evaluates pure Core LIR arithmetic"
              52
              (eval-lir-program pure-core-prog))

;; 4.2 Evaluation of lowered heap allocation (%alloc)
(define alloc-eval-prog
  (make-dialect-test-prog
   '()
   '((%alloc %rax 24 1)
     (%store %rax -1 42)
     (%load %rbx %rax -1)
     (%return %rbx))))

(define lowered-alloc-eval (lower-managed-dialect alloc-eval-prog))

(assert-true "4.3 lowered alloc eval program satisfies validate-core-lir"
             (validate-core-lir lowered-alloc-eval))

(assert-equal "4.4 Reference VM executes lowered heap allocation and loads stored value"
              42
              (eval-lir-program lowered-alloc-eval))

;; 4.3 Evaluation of lowered Fixnum boxing and unboxing
(define box-unbox-prog
  (make-dialect-test-prog
   '()
   '((%mov %rax 25)
     (%box-fixnum %rax %rax)    ; 25 << 2 = 100
     (%mov %rbx %rax)
     (%unbox-fixnum %rbx %rbx)  ; 100 >> 2 = 25
     (%return %rbx))))

(define lowered-box-unbox (lower-managed-dialect box-unbox-prog))

(assert-true "4.5 lowered box/unbox program satisfies validate-core-lir"
             (validate-core-lir lowered-box-unbox))

(assert-equal "4.6 Reference VM executes lowered fixnum box and unbox"
              25
              (eval-lir-program lowered-box-unbox))

;; 4.4 Function call with lowered dialect
(define fn-call-prog
  (make-dialect-test-prog
   (list '(%lir-function .L_double_and_box
                          (params (val))
                          (frame-size 8)
                          (body
                           (%mov %rax val)
                           (%add %rax val)
                           (%box-fixnum %rax %rax)
                           (%return %rax))))
   '((%direct-call .L_double_and_box 0)
     (%unbox-fixnum %rax %rax)
     (%return %rax))))

;; Pre-fill %rdi with 21 in main before call
(define fn-call-prog-with-arg
  (make-dialect-test-prog
   (list '(%lir-function .L_double_and_box
                          (params (val))
                          (frame-size 8)
                          (body
                           (%mov %rax %rdi)
                           (%add %rax %rdi)
                           (%box-fixnum %rax %rax)
                           (%return %rax))))
   '((%mov %rdi 21)
     (%direct-call .L_double_and_box 0)
     (%unbox-fixnum %rax %rax)
     (%return %rax))))

(define lowered-fn-call (lower-managed-dialect fn-call-prog-with-arg))

(assert-true "4.7 lowered function call program satisfies validate-core-lir"
             (validate-core-lir lowered-fn-call))

(assert-equal "4.8 Reference VM executes lowered function call (21 * 2 = 42)"
              42
              (eval-lir-program lowered-fn-call))

;;; -----------------------------------------------------------------------
;;; Group 5: Pipeline & C-Language Direct Core LIR Integration
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Pipeline & C-Language Direct Core LIR Integration ---\n")

(init-default-pass-registry!)

;; 5.1 Pass Manager includes pass-131-lower-managed-dialect
(define p-desc (lookup-pass 'pass-131-lower-managed-dialect))
(assert-true "5.1 pass-131-lower-managed-dialect is registered in pass manager"
             (and p-desc #t))

(assert-equal "5.2 pass-131 input language is L_lir_managed"
              'L_lir_managed
              (pass-in-lang p-desc))

(assert-equal "5.3 pass-131 output language is L_lir_core"
              'L_lir_core
              (pass-out-lang p-desc))

(assert-equal "5.4 pass-131 verification phase is core-lir"
              'core-lir
              (pass-verifier-phase p-desc))

;; 5.5 Pipeline continuity verification
(define aot-pipeline-passes (pipeline-desc-passes (lookup-pipeline 'aot-native-pipeline)))
(assert-true "5.5 aot-native-pipeline contains pass-131-lower-managed-dialect"
             (memq 'pass-131-lower-managed-dialect aot-pipeline-passes))

(assert-true "5.6 aot-native-pipeline passes language continuity check with pass-131"
             (validate-pipeline-continuity-by-ids aot-pipeline-passes))

;; 5.6b Issue #979: Strict LIR dialect compatibility & pass-130 -> L_lir_managed contract
(define p130-desc (lookup-pass 'pass-130-lir))
(assert-equal "5.6b pass-130-lir output language is L_lir_managed"
              'L_lir_managed
              (pass-out-lang p130-desc))
(assert-false "5.6c nanopass-language-compatible? rejects L_lir_managed -> L_lir_core"
              (nanopass-language-compatible? 'L_lir_managed 'L_lir_core))
(assert-false "5.6d check-pipeline-continuity-by-ids rejects skipping pass-131"
              (check-pipeline-continuity-by-ids
               '(pass-110-closure-convert pass-130-lir pass-128-lir-branch-fusion)))

;; 5.7 C Frontend Direct Core Machine LIR Bypass (DSN-38 §2 B5 / E8)
;; C code emits Core Machine LIR directly, completely bypassing Managed Dialect & Pass 131.
(define c-frontend-direct-core-lir
  (make-dialect-test-prog
   (list '(%lir-function .c_fib
                          (params (n))
                          (frame-size 16)
                          (body
                           (%cmp %rdi 1)
                           (%jump-cond jle .c_fib_base)
                           (%mov %rax %rdi)
                           (%sub %rax 1)
                           (%return %rax)
                           (%label .c_fib_base)
                           (%mov %rax %rdi)
                           (%return %rax))))
   '((%mov %rdi 5)
     (%direct-call .c_fib 0)
     (%return %rax))))

(assert-true "5.7 C frontend direct Core LIR passes validate-core-lir without any lowering"
             (validate-core-lir c-frontend-direct-core-lir))

(assert-true "5.8 C frontend direct Core LIR satisfies L_lir_core?"
             (L_lir_core? c-frontend-direct-core-lir))

;; Verify C LIR evaluates cleanly in VM
(assert-equal "5.9 Reference VM executes direct C Core LIR"
              4
              (eval-lir-program c-frontend-direct-core-lir))

;; 5.10 Full Scheme AOT pipeline compilation produces pure Core Machine LIR
(define scheme-ast '((+ 10 (* 4 8))))
(define compiled-lir (run-pass-pipeline scheme-ast #t #f))

(assert-true "5.10 Scheme AOT compiled LIR satisfies validate-core-lir (zero managed opcodes)"
             (validate-core-lir compiled-lir))

(assert-true "5.11 Scheme AOT compiled LIR satisfies L_lir_core?"
             (L_lir_core? compiled-lir))

;; Verify execution result
(assert-equal "5.12 Reference VM executes Scheme AOT compiled LIR (10 + 32 = 42)"
              42
              (eval-lir-program-unboxed compiled-lir))

;;; -----------------------------------------------------------------------
;;; Group 6: Issue #966 - L_mir_ssa & L_lir_mach 2-Tier Separation
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: L_mir_ssa & L_lir_mach 2-Tier Separation (Issue #966) ---\n")

(assert-true "6.1 L_mir_ssa is registered"
             (nanopass-language? (nanopass-lookup-language 'L_mir_ssa)))

(assert-true "6.2 L_lir_mach is registered"
             (nanopass-language? (nanopass-lookup-language 'L_lir_mach)))

(assert-equal "6.3 language-parent-chain for L_mir_ssa is (L_lir_core L_mir_ssa)"
              '(L_lir_core L_mir_ssa)
              (language-parent-chain 'L_mir_ssa))

(assert-equal "6.4 language-parent-chain for L_lir_mach is (L_lir_core L_mir_ssa L_lir_mach)"
              '(L_lir_core L_mir_ssa L_lir_mach)
              (language-parent-chain 'L_lir_mach))

(define mir-ssa-vreg-prog
  (make-dialect-test-prog
   '()
   '((%mov (%reg v1) 20)
     (%mov (%reg i64 v2) 22)
     (%add (%reg v1) (%reg i64 v2))
     (%mov %rax (%reg v1))
     (%return %rax))))

(assert-true "6.5 L_mir_ssa? accepts virtual registers (%reg v1) and (%reg i64 v2)"
             (L_mir_ssa? mir-ssa-vreg-prog))

(assert-true "6.6 validate-mir-ssa accepts virtual-register SSA program"
             (validate-mir-ssa mir-ssa-vreg-prog))

(assert-false "6.7 L_mir_ssa? rejects Managed Dialect instruction %alloc"
              (L_mir_ssa? managed-alloc-prog))

(assert-false "6.8 validate-mir-ssa rejects Managed Dialect instruction %box-fixnum"
              (validate-mir-ssa managed-box-prog))

(assert-true "6.9 L_lir_mach? accepts physical-register Core Machine LIR"
             (L_lir_mach? pure-core-prog))

(assert-true "6.10 validate-mach-lir accepts physical-register Core Machine LIR"
             (validate-mach-lir pure-core-prog))

(assert-false "6.11 L_lir_mach? rejects unallocated virtual register (%reg v1)"
              (L_lir_mach? mir-ssa-vreg-prog))

(assert-false "6.12 validate-mach-lir rejects unallocated virtual register (%reg v1)"
              (validate-mach-lir mir-ssa-vreg-prog))

(define mir-ssa-freg-prog
  (make-dialect-test-prog
   '()
   '((%fmov (%freg f1) %xmm0)
     (%return 0))))

(assert-true "6.13 L_mir_ssa? accepts (%freg f1)"
             (L_mir_ssa? mir-ssa-freg-prog))

(assert-false "6.14 L_lir_mach? rejects (%freg f1)"
              (L_lir_mach? mir-ssa-freg-prog))

(assert-false "6.15 validate-mach-lir rejects (%freg f1)"
              (validate-mach-lir mir-ssa-freg-prog))

(define mir-ssa-block-param-prog
  (make-dialect-test-prog
   '()
   '((%jump .L_init (10 32))
     (%block .L_init (x y)
       (%add (%reg x) (%reg y))
       (%mov %rax (%reg x))
       (%return %rax)))))

(assert-true "6.16 validate-lir 'mir-ssa accepts virtual-param %block SSA"
             (validate-lir mir-ssa-block-param-prog 'mir-ssa))

(assert-false "6.17 validate-lir 'mach rejects virtual %block param SSA"
              (validate-lir mir-ssa-block-param-prog 'mach))

;; 6.18-6.20 lower-mir-ssa-to-mach-lir lowers virtual regs and swaps parallel %block args cleanly
(define lowered-vreg-mach (lower-mir-ssa-to-mach-lir mir-ssa-vreg-prog))
(assert-true "6.18 lowered mir-ssa-vreg-prog satisfies L_lir_mach? and validate-mach-lir"
             (and (L_lir_mach? lowered-vreg-mach)
                  (validate-mach-lir lowered-vreg-mach)))
(assert-equal "6.19 Reference VM evaluates lowered vreg program (20 + 22 = 42)"
              42
              (eval-lir-program lowered-vreg-mach))

(define mir-ssa-parallel-swap-prog
  (make-dialect-test-prog
   '()
   '((%jump .L_swap (30 12))
     (%block .L_swap (a b)
       (%jump .L_calc ((%reg b) (%reg a))))
     (%block .L_calc (x y)
       (%mov (%reg i64 r) (%reg x))
       (%sub (%reg i64 r) (%reg y))
       (%mov %rax (%reg i64 r))
       (%return %rax)))))

(define lowered-swap-mach (lower-mir-ssa-to-mach-lir mir-ssa-parallel-swap-prog))
(assert-true "6.20 parallel swap %block program lowers to valid L_lir_mach"
             (and (L_lir_mach? lowered-swap-mach)
                  (validate-mach-lir lowered-swap-mach)))
(assert-equal "6.21 Reference VM evaluates lowered parallel swap (12 - 30 = -18)"
              -18
              (eval-lir-program lowered-swap-mach))

;; 6.22 Call-containing function forces safe stack slots (%stack) instead of volatile scratch regs
(define mir-ssa-call-vreg-prog
  (make-dialect-test-prog
   (list '(%lir-function .L_id
                          (params ())
                          (frame-size 0)
                          (body
                           (%mov %rax 21)
                           (%return %rax))))
   '((%mov (%reg keep1) 21)
     (%direct-call .L_id 0)
     (%add %rax (%reg keep1))
     (%return %rax))))

(define lowered-call-mach (lower-mir-ssa-to-mach-lir mir-ssa-call-vreg-prog))
(assert-true "6.22 call-crossing virtual reg program lowers to valid L_lir_mach"
             (and (L_lir_mach? lowered-call-mach)
                  (validate-mach-lir lowered-call-mach)))
(assert-equal "6.23 Reference VM preserves virtual reg across call (21 + 21 = 42)"
              42
              (eval-lir-program lowered-call-mach))

;; 6.24 Scheme compiled LIR converges cleanly via lir-to-mir-ssa -> lower-mir-ssa-to-mach-lir
(define scheme-mir-full (lir-to-mir-ssa compiled-lir))
(define scheme-mach-full (lower-mir-ssa-to-mach-lir scheme-mir-full))
(assert-true "6.24 Scheme pipeline converges on L_mir_ssa and lowers to L_lir_mach"
             (and (validate-mir-ssa scheme-mir-full)
                  (L_lir_mach? scheme-mach-full)
                  (validate-mach-lir scheme-mach-full)))

;; 6.25 3-cycle %block args lower cleanly and evaluate on Reference VM (#969)
(define mir-ssa-3cycle-prog
  (make-dialect-test-prog
   '()
   '((%jump .L_rot (1 20 300))
     (%block .L_rot (a b c)
       (%jump .L_out ((%reg b) (%reg c) (%reg a))))
     (%block .L_out (x y z)
       (%mov (%reg i64 r) (%reg x))
       (%imul (%reg i64 r) 100)
       (%add (%reg i64 r) (%reg y))
       (%add (%reg i64 r) (%reg z))
       (%mov %rax (%reg i64 r))
       (%return %rax)))))
(define lowered-3cycle-mach (lower-mir-ssa-to-mach-lir mir-ssa-3cycle-prog))
(assert-true "6.25 3-cycle %block program lowers to valid L_lir_mach"
             (and (L_lir_mach? lowered-3cycle-mach) (validate-mach-lir lowered-3cycle-mach)))
(assert-equal "6.26 Reference VM evaluates lowered 3-cycle (20*100 + 300 + 1 = 2301)"
              2301
              (eval-lir-program lowered-3cycle-mach))

;; 6.27 FPR %xmm* %block swap lowers to valid L_lir_mach and runs on Reference VM (#969)
(define mir-ssa-fpr-swap-prog
  (make-dialect-test-prog
   '()
   '((%mov %rax 7)
     (%sitofp (%freg fa) %rax)
     (%mov %rax 50)
     (%sitofp (%freg fb) %rax)
     (%jump .L_fswap ((%freg fa) (%freg fb)))
     (%block .L_fswap (fx fy)
       (%jump .L_fcalc ((%freg fy) (%freg fx))))
     (%block .L_fcalc (p q)
       (%fsub (%freg p) (%freg q))
       (%fptosi %rax (%freg p))
       (%return %rax)))))
(define lowered-fpr-mach (lower-mir-ssa-to-mach-lir mir-ssa-fpr-swap-prog))
(assert-true "6.27 FPR %block swap lowers to valid L_lir_mach"
             (and (L_lir_mach? lowered-fpr-mach) (validate-mach-lir lowered-fpr-mach)))
(assert-equal "6.28 Reference VM evaluates lowered FPR swap (50 - 7 = 43)"
              43
              (eval-lir-program lowered-fpr-mach))

;; 6.29 5-arg %switch with cyclic block args lowers and runs on Reference VM (#969)
(define mir-ssa-switch-cycle-prog
  (make-dialect-test-prog
   '()
   '((%mov %rax 2)
     (%jump .L_sw (10 52))
     (%block .L_sw (a b)
       (%switch %rax .L_done ((%reg a) (%reg b))
                ((1 .L_done ((%reg a) (%reg b)))
                 (2 .L_done ((%reg b) (%reg a))))))
     (%block .L_done (x y)
       (%mov %rax (%reg x))
       (%sub %rax (%reg y))
       (%return %rax)))))
(define lowered-sw-mach (lower-mir-ssa-to-mach-lir mir-ssa-switch-cycle-prog))
(assert-true "6.29 5-arg %switch cyclic block args lower to valid L_lir_mach"
             (and (L_lir_mach? lowered-sw-mach) (validate-mach-lir lowered-sw-mach)))
(assert-equal "6.30 Reference VM evaluates %switch cyclic edge (52 - 10 = 42)"
              42
              (eval-lir-program lowered-sw-mach))

;;; -----------------------------------------------------------------------
;;; Test Suite Result Summary
;;; -----------------------------------------------------------------------
(display "\n-------------------------------------------------------\n")
(display " [RESULT] Core Machine LIR & Managed Dialect Separation: ALL TESTS PASSED!\n")
(display "-------------------------------------------------------\n")
