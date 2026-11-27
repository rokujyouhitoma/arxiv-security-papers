;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 133 (LIR Peephole & DCE)
;;; Conforms to Issue #595 & Nanopass Architecture Quality Standard
;;; =======================================================================




(test-begin "Pass 133 (LIR Peephole & DCE)")

;; Helper to wrap instruction list in a canonical program
(define (make-test-program insts)
  (list '%lir-program
        '(strings ())
        '(stackmaps ())
        '(%lir-functions)
        (list '%lir-main
              '(frame-size 0)
              (cons 'body insts))))

(define (extract-main-body prog)
  (cdr (assq 'body (cdr (assq '%lir-main (cdr prog))))))

;; 1. Redundant self-move elimination: (%mov %rax %rax)
(let* ((in-insts '((%mov %rax %rax) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "redundant self-move eliminated"
                '((%return))
                out))

;; 2. Round-trip register move elimination: (%mov %rax %rbx) followed by (%mov %rbx %rax)
(let* ((in-insts '((%mov %rax %rbx) (%mov %rbx %rax) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "round-trip move eliminated"
                '((%mov %rax %rbx) (%return))
                out))

;; 3. Redundant jump to immediate next label: (%jump L1) followed by (%label L1)
(let* ((in-insts '((%jump L1) (%label L1) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "jump to immediate next label eliminated"
                '((%label L1) (%return))
                out))

;; 4. Identity addition simplification: (%add %rax 0)
(let* ((in-insts '((%add %rax 0) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "identity add zero eliminated"
                '((%return))
                out))

;; 5. Identity subtraction simplification: (%sub %rcx 0)
(let* ((in-insts '((%sub %rcx 0) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "identity sub zero eliminated"
                '((%return))
                out))

;; 6. Identity multiplication simplification: (%imul %rdx 1)
(let* ((in-insts '((%imul %rdx 1) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "identity imul one eliminated"
                '((%return))
                out))

;; 7. Unreachable code elimination after unconditional jump (jump to distant label)
(let* ((in-insts '((%jump L2) (%mov %rax 42) (%add %rax 10) (%label L1) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "dead code after jump eliminated"
                '((%jump L2) (%label L1) (%return))
                out))

;; 8. Multi-pass cascading optimization: DCE exposing redundant jump to next label
(let* ((in-insts '((%jump L1) (%mov %rax 42) (%label L1) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  ;; Pass 1 drops (%mov %rax 42) -> (%jump L1) (%label L1)
  ;; Pass 2 drops (%jump L1) -> (%label L1) (%return)
  (assert-equal "cascading DCE and jump-elimination"
                '((%label L1) (%return))
                out))

;; 9. Full define-pass integration with L_lir_canonical schema validation
(let* ((orig (make-test-program '((%mov %rax %rax)
                                  (%add %rax 0)
                                  (%jump L1)
                                  (%mov %rbx 99)
                                  (%label L1)
                                  (%return))))
       (opt (lir-peephole-optimize orig))
       (body (extract-main-body opt)))
  (assert-equal "full pass optimizes main body"
                '((%label L1) (%return))
                body)
  (assert-true "optimized program satisfies L_lir_canonical schema"
               (L_lir_canonical? opt)))

;; 10. Verification of peephole optimization on functions
(let* ((fn (list '%lir-function
                 'foo
                 '(params (x))
                 '(frame-size 16)
                 '(body (%mov %rax %rax)
                        (%sub %rcx 0)
                        (%return))))
       (orig (list '%lir-program
                   '(strings ())
                   '(stackmaps ())
                   (list '%lir-functions fn)
                   (list '%lir-main '(frame-size 0) '(body (%return)))))
       (opt (lir-peephole-optimize orig))
       (funcs (cadr (assq '%lir-functions (cdr opt))))
       (fn-body (cdr (assq 'body (cdddr funcs)))))
  (assert-equal "function body optimized with peephole"
                '((%return))
                fn-body)
  (assert-true "function optimization satisfies L_lir_canonical schema"
               (L_lir_canonical? opt)))

;; 11. Distance-independent Store-Reload forwarding (distance = 2 instructions in between)
(let* ((in-insts '((%store %rsp 8 %rax)
                   (%mov %rbx 42)
                   (%store %rsp 16 %rcx)
                   (%load %rdx %rsp 8)
                   (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "non-adjacent store-load forwarded to mov across 2 instructions"
                '((%store %rsp 8 %rax)
                  (%mov %rbx 42)
                  (%store %rsp 16 %rcx)
                  (%mov %rdx %rax)
                  (%return))
                out))

;; 12. Non-adjacent Store-Reload elimination (same register, distance = 3 instructions)
(let* ((in-insts '((%store %rsp 8 %rax)
                   (%mov %rbx 1)
                   (%store %rsp 16 %rcx)
                   (%add %rbx 2)
                   (%load %rax %rsp 8)
                   (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "non-adjacent reload to same register eliminated across 3 instructions"
                '((%store %rsp 8 %rax)
                  (%mov %rbx 1)
                  (%store %rsp 16 %rcx)
                  (%add %rbx 2)
                  (%return))
                out))

;; 13. Source register clobber inhibits forwarding
(let* ((in-insts '((%store %rsp 8 %rax)
                   (%mov %rax 99)
                   (%load %rdx %rsp 8)
                   (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "source register clobber safely preserves load"
                '((%store %rsp 8 %rax)
                  (%mov %rax 99)
                  (%load %rdx %rsp 8)
                  (%return))
                out))

;; 14. Function call memory barrier inhibits forwarding
(let* ((in-insts '((%store %rsp 8 %rax)
                   (%direct-call foo 0)
                   (%load %rdx %rsp 8)
                   (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "function call barrier safely preserves load"
                '((%store %rsp 8 %rax)
                  (%direct-call foo 0)
                  (%load %rdx %rsp 8)
                  (%return))
                out))

;; 15. Overwritten stack slot forwards latest reaching value
(let* ((in-insts '((%store %rsp 8 %rax)
                   (%mov %rcx 10)
                   (%store %rsp 8 %rbx)
                   (%load %rdx %rsp 8)
                   (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "overwritten stack slot forwards latest reaching value"
                '((%store %rsp 8 %rax)
                  (%mov %rcx 10)
                  (%store %rsp 8 %rbx)
                  (%mov %rdx %rbx)
                  (%return))
                out))

;; 16. Redundant self fmov elimination (Issue #934)
(let* ((in-insts '((%fmov %xmm2 %xmm2) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "redundant self fmov eliminated"
                '((%return))
                out))

;; 17. f64 Store-Reload forwarding vs f32 precision guard (Issue #934)
(let* ((in-f64 '((%store-typed f64 %rsp 16 %xmm0)
                 (%mov %rcx 1)
                 (%load-typed f64 %xmm1 %rsp 16)
                 (%return)))
       (out-f64 (optimize-peephole-fixpoint in-f64))
       (in-f32 '((%store-typed f32 %rsp 16 %xmm0)
                 (%load-typed f32 %xmm1 %rsp 16)
                 (%return)))
       (out-f32 (optimize-peephole-fixpoint in-f32)))
  (assert-equal "f64 store-load forwarded to fmov across distance=1"
                '((%store-typed f64 %rsp 16 %xmm0)
                  (%mov %rcx 1)
                  (%fmov %xmm1 %xmm0)
                  (%return))
                out-f64)
  (assert-equal "f32 store-load NOT converted to fmov (160_backend_c precision preserved)"
                in-f32
                out-f32))

;; 18. Backward DSE kills overwritten negative slot store across basic block, preserves positive offsets
(let* ((in-insts '((%store %rsp -16 %rax)
                   (%store %rsp 8 %rdi)
                   (%mov %rbx 1)
                   (%store %rsp -16 %rcx)
                   (%jump L_read)
                   (%label L_dead)
                   (%return)
                   (%label L_read)
                   (%load %rdx %rsp -16)
                   (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "overwritten negative slot eliminated, caller +8 preserved"
                '((%store %rsp 8 %rdi)
                  (%mov %rbx 1)
                  (%store %rsp -16 %rcx)
                  (%jump L_read)
                  (%label L_dead)
                  (%return)
                  (%label L_read)
                  (%load %rdx %rsp -16)
                  (%return))
                out))

;; 19. Backward DSE eliminates dead store before %return, preserves (%stack -16) return operand
(let* ((in1 '((%store %rsp -16 %rax)
              (%mov %rax 7)
              (%return %rax)))
       (out1 (optimize-peephole-fixpoint in1))
       (in2 '((%store %rsp -16 %rax)
              (%store %rsp -24 %rbx)
              (%return (%stack -16))))
       (out2 (optimize-peephole-fixpoint in2)))
  (assert-equal "dead store before %return eliminated"
                '((%mov %rax 7)
                  (%return %rax))
                out1)
  (assert-equal "store live for (%stack -16) return preserved while -24 eliminated"
                '((%store %rsp -16 %rax)
                  (%return (%stack -16)))
                out2))

;; 20. Call memory barrier and %rsp escape conservatively preserve stores
(let* ((in-call '((%store %rsp -64 %rdi)
                  (%direct-call foo 64)
                  (%return)))
       (out-call (optimize-peephole-fixpoint in-call))
       (in-esc '((%store %rsp -16 %rdi)
                 (%mov %rdx %rsp)
                 (%add %rdx -16)
                 (%load %rax %rdx 0)
                 (%return)))
       (out-esc (optimize-peephole-fixpoint in-esc)))
  (assert-equal "outgoing stack store before call barrier preserved"
                in-call
                out-call)
  (assert-equal "%rsp escape conservatively preserves negative store before indirect load"
                in-esc
                out-esc))

;; 21. Leaf whole-function unread DSE vs overlapping partial u32 + i64 read interval safety
(let* ((in-leaf '((%store %rsp -16 %rdi)
                  (%store %rsp -24 %rsi)
                  (%jump-cond je L_zero)
                  (%load %rax %rsp -16)
                  (%return)
                  (%label L_zero)
                  (%mov %rax 0)
                  (%return)))
       (out-leaf (optimize-peephole-fixpoint in-leaf))
       (in-u64 '((%store-typed u32 %rsp -16 %rax)
                 (%store-typed u32 %rsp -12 %rcx)
                 (%load %rax %rsp -16)
                 (%return)))
       (out-u64 (optimize-peephole-fixpoint in-u64)))
  (assert-equal "leaf function drops completely unread -24 param spill across branch"
                '((%store %rsp -16 %rdi)
                  (%jump-cond je L_zero)
                  (%load %rax %rsp -16)
                  (%return)
                  (%label L_zero)
                  (%mov %rax 0)
                  (%return))
                out-leaf)
  (assert-equal "overlapping u32+u32 split stores preserved for 8B load at -16"
                in-u64
                out-u64))

;; 22. Issue #935: Identical and monotone integer extension folding + f32/f64 exclusion
(let* ((in-ident '((%mov %rax %rdi)
                   (%sext i32 %rax %rax)
                   (%sext i32 %rax %rax)
                   (%return %rax)))
       (in-u8 '((%load-typed u8 %rax %rsp -8)
                (%sext i32 %rax %rax)
                (%zext u32 %rax %rax)
                (%return %rax)))
       (in-i8 '((%load-typed i8 %rax %rsp -8)
                (%sext i32 %rax %rax)
                (%zext u32 %rax %rax)
                (%return %rax)))
       (in-u32 '((%load-typed u32 %rax %rsp -8)
                 (%sext i32 %rax %rax)
                 (%return %rax)))
       (in-i32 '((%load-typed i32 %rax %rsp -8)
                 (%sext i32 %rax %rax)
                 (%return %rax)))
       (in-imm1 '((%mov %rax 42)
                  (%sext i32 %rax %rax)
                  (%zext u8 %rax %rax)
                  (%return %rax)))
       (in-imm2 '((%mov %rax 300)
                  (%zext u8 %rax %rax)
                  (%return %rax)))
       (in-fp '((%trunc f32 %xmm0 %xmm0)
                (%zext f64 %xmm0 %xmm0)
                (%return))))
  (assert-equal "identical %sext i32 duplicate eliminated"
                '((%mov %rax %rdi) (%sext i32 %rax %rax) (%return %rax))
                (optimize-peephole-fixpoint in-ident))
  (assert-equal "u8 load subsumes both %sext i32 and %zext u32"
                '((%load-typed u8 %rax %rsp -8) (%return %rax))
                (optimize-peephole-fixpoint in-u8))
  (assert-equal "i8 load drops %sext i32 but keeps narrowing %zext u32"
                '((%load-typed i8 %rax %rsp -8) (%zext u32 %rax %rax) (%return %rax))
                (optimize-peephole-fixpoint in-i8))
  (assert-equal "u32 load does NOT subsume %sext i32"
                in-u32
                (optimize-peephole-fixpoint in-u32))
  (assert-equal "i32 load drops redundant %sext i32"
                '((%load-typed i32 %rax %rsp -8) (%return %rax))
                (optimize-peephole-fixpoint in-i32))
  (assert-equal "const 42 subsumes %sext i32 and %zext u8"
                '((%mov %rax 42) (%return %rax))
                (optimize-peephole-fixpoint in-imm1))
  (assert-equal "const 300 followed by %zext u8 folds to const 44"
                '((%mov %rax 44) (%return %rax))
                (optimize-peephole-fixpoint in-imm2))
  (assert-equal "f32/f64 conversions are never touched by integer extension folding"
                in-fp
                (optimize-peephole-fixpoint in-fp)))

;; 23. Issue #935: Adjacent overwrite, non-self %mov, shift/mask facts, call barrier, %rcx schema
(let* ((in-over '((%mov %rax %rdi)
                  (%zext u32 %rax %rax)
                  (%sext i32 %rax %rax)
                  (%return %rax)))
       (in-nonself '((%load-typed u8 %rbx %rsp -8)
                     (%zext u32 %rax %rbx)
                     (%return %rax)))
       (in-and '((%mov %rax %rdi)
                 (%bit-and %rax 255)
                 (%sext i32 %rax %rax)
                 (%return %rax)))
       (in-sar '((%mov %rax %rdi)
                 (%sext i32 %rax %rax)
                 (%sar %rax %rcx)
                 (%sext i32 %rax %rax)
                 (%return %rax)))
       (in-call '((%sext i32 %rax %rax)
                  (%direct-call foo 0)
                  (%sext i32 %rax %rax)
                  (%return %rax)))
       (rcx-prog (make-test-program '((%bit-and %rcx 31)
                                      (%zext u32 %rax %rax)
                                      (%shr %rax %rcx)
                                      (%return %rax)))))
  (assert-equal "adjacent equal/narrower ext overwrites previous ext"
                '((%mov %rax %rdi) (%sext i32 %rax %rax) (%return %rax))
                (optimize-peephole-fixpoint in-over))
  (assert-equal "subsumed non-self ext becomes plain %mov"
                '((%load-typed u8 %rbx %rsp -8) (%mov %rax %rbx) (%return %rax))
                (optimize-peephole-fixpoint in-nonself))
  (assert-equal "%bit-and 255 infers u8 and drops following %sext i32"
                '((%mov %rax %rdi) (%bit-and %rax 255) (%return %rax))
                (optimize-peephole-fixpoint in-and))
  (assert-equal "i32 preserved across variable %sar %rcx drops trailing %sext i32"
                '((%mov %rax %rdi) (%sext i32 %rax %rax) (%sar %rax %rcx) (%return %rax))
                (optimize-peephole-fixpoint in-sar))
  (assert-equal "call barrier invalidates extension state conservatively"
                in-call
                (optimize-peephole-fixpoint in-call))
  (assert-true "program with (%shr %rax %rcx) satisfies L_lir_canonical?"
               (L_lir_canonical? (lir-peephole-optimize rcx-prog))))

;; 23. Issue #961: Arbitrary-distance forwarding, CFG-DSE across <=6-arg calls, and call-free linear scan
(let* ((prog-cons-like
        (make-test-program
         '((%store %rsp -8 %rax)
           (%mov %rax %r12)
           (%add %rax 9)
           (%add %r12 24)
           (%mov %rdx 4196356)
           (%store %rax -9 %rdx)
           (%load %rdx %rsp -8)
           (%store %rax 7 %rdx)
           (%return %rax))))
       (opt-cons (lir-peephole-optimize prog-cons-like))
       (opt-cons-body (cdr (assq 'body (cdr (assq '%lir-main (cdr opt-cons))))))
       (has-rsp-mem?
        (let loop ((xs opt-cons-body))
          (and (pair? xs)
               (or (and (pair? (car xs))
                        (memq (caar xs) '(%store %load))
                        (lir-dse-tree-contains-sym? (car xs) '%rsp))
                   (loop (cdr xs))))))
       (prog-cfg-dse
        '(%lir-program
          (strings ())
          (stackmaps ((sp_dead 32 2)))
          (%lir-functions)
          (%lir-main
           (frame-size 32)
           (body
            (%store %rsp -24 %rdi)
            (%mov %rax 0)
            (%direct-call foo 32 sp_dead)
            (%mov %rax 4)
            (%return %rax)))))
       (opt-cfg (lir-peephole-optimize prog-cfg-dse))
       (opt-cfg-body (cdr (assq 'body (cdr (assq '%lir-main (cdr opt-cfg))))))
       (opt-cfg-sp (cadr (assq 'stackmaps (cdr opt-cfg)))))
  (assert-false "linear scan eliminates [rsp -8] store & reload across lowered alloc"
                has-rsp-mem?)
  (assert-true "linear scan output satisfies L_lir_canonical?"
               (L_lir_canonical? opt-cons))
  (assert-equal "CFG-DSE drops unread -24 spill before <=6-arg call & prunes dead stackmap bit"
                '((%mov %rax 0) (%direct-call foo 32 sp_dead) (%mov %rax 4) (%return %rax))
                opt-cfg-body)
  (assert-equal "dead stackmap bit cleared when pre-call store eliminated"
                '((sp_dead 32 0))
                opt-cfg-sp))

;; 24. %switch CFG successor liveness preserves stores read in switch arms (Issue #966 / Duff's device)
(let* ((prog-switch-dse
        '(%lir-program
          (strings ())
          (stackmaps ())
          (%lir-functions)
          (%lir-main
           (frame-size 24)
           (body
            (%store %rsp -16 %rdi)
            (%mov %rax %rsi)
            (%switch %rax .L_sw_def ((0 . .L_sw_0) (1 . .L_sw_1)))
            (%label .L_sw_0)
            (%load %rax %rsp -16)
            (%return %rax)
            (%label .L_sw_1)
            (%mov %rax 99)
            (%return %rax)
            (%label .L_sw_def)
            (%mov %rax 0)
            (%return %rax)))))
       (opt-sw (lir-peephole-optimize prog-switch-dse))
       (opt-sw-body (cdr (assq 'body (cdr (assq '%lir-main (cdr opt-sw))))))
       (kept-store? (let loop ((xs opt-sw-body))
                      (and (pair? xs)
                           (or (equal? (car xs) '(%store %rsp -16 %rdi))
                               (loop (cdr xs)))))))
  (assert-true "CFG-DSE preserves entry stack store read in %switch case arm"
               kept-store?))

(test-end "Pass 133 (LIR Peephole & DCE)")
