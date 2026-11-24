;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 143 (Native x86-64 Machine Peephole)
;;; Conforms to Issue #596 & Nanopass Architecture Quality Standard
;;; =======================================================================




(test-begin "Pass 143 (x86-64 Machine Peephole)")

;; Helper to wrap instruction list in a canonical L_asm_x86 program
(define (make-test-asm-program insts)
  (list '%asm-program
        '(strings ())
        '(stackmaps ())
        '(%asm-functions)
        (list '%asm-main
              '(frame-size 0)
              (cons 'body insts))))

(define (extract-main-asm-body prog)
  (cdr (assq 'body (cdr (assq '%asm-main (cdr prog))))))

;; 1. Redundant self-move elimination: (mov rax rax)
(let* ((in-insts '((mov rax rax) (ret)))
       (out (optimize-x86-peephole-insts in-insts)))
  (assert-equal "redundant self-move eliminated"
                '((ret))
                out))

;; 2. Round-trip register move elimination: (mov rax rbx) followed by (mov rbx rax)
(let* ((in-insts '((mov rax rbx) (mov rbx rax) (ret)))
       (out (optimize-x86-peephole-insts in-insts)))
  (assert-equal "round-trip move eliminated"
                '((mov rax rbx) (ret))
                out))

;; 3. Zero-idiom XOR optimization: (mov rax 0) / (mov rax (%imm 0)) -> (xor rax rax)
(let* ((in-insts '((mov rax 0) (mov rbx (%imm 0)) (ret)))
       (out (optimize-x86-peephole-insts in-insts)))
  (assert-equal "zero-idiom xor optimization"
                '((xor rax rax) (xor rbx rbx) (ret))
                out))

;; 4. Redundant jump to immediate next label: (jmp L1) followed by (%label L1)
(let* ((in-insts '((jmp L1) (%label L1) (ret)))
       (out (optimize-x86-peephole-insts in-insts)))
  (assert-equal "jump to immediate next label eliminated"
                '((%label L1) (ret))
                out))

;; 5. Unreachable code elimination after unconditional terminator
(let* ((in-insts '((jmp L2) (mov rax 42) (add rax 10) (%label L1) (ret)))
       (out (optimize-x86-peephole-insts in-insts)))
  (assert-equal "dead code after jump eliminated"
                '((jmp L2) (%label L1) (ret))
                out))

;; 6. Cascading optimization: DCE exposing redundant jump to next label
(let* ((in-insts '((jmp L1) (mov rax 42) (%label L1) (ret)))
       (out (optimize-x86-peephole-insts in-insts)))
  (assert-equal "cascading DCE and jump elimination"
                '((%label L1) (ret))
                out))

;; 7. Program-level peephole optimization and schema validation
(let* ((orig (make-test-asm-program '((mov rax rax)
                                      (mov rcx 0)
                                      (jmp L1)
                                      (mov rdx 99)
                                      (%label L1)
                                      (ret))))
       (opt (optimize-x86-peephole orig))
       (body (extract-main-asm-body opt)))
  (assert-equal "program-level main body optimization"
                '((xor rcx rcx) (%label L1) (ret))
                body)
  (assert-true "optimized program satisfies L_asm_x86 schema"
               (L_asm_x86? opt)))

;; 8. Verification of peephole optimization on functions
(let* ((fn (list '%asm-function
                 'foo
                 '(frame-size 16)
                 '(body (mov rax rax)
                        (mov r8 0)
                        (ret))))
       (orig (list '%asm-program
                   '(strings ())
                   '(stackmaps ())
                   (list '%asm-functions fn)
                   (list '%asm-main '(frame-size 0) '(body (ret)))))
       (opt (optimize-x86-peephole orig))
       (funcs (cadr (assq '%asm-functions (cdr opt))))
       (fn-body (cdr (assq 'body (cddr funcs)))))
  (assert-equal "function body optimized with peephole"
                '((xor r8 r8) (ret))
                fn-body)
  (assert-true "function optimization satisfies L_asm_x86 schema"
               (L_asm_x86? opt)))

;; 9. Redundant jump over align to immediate next label (rule-x86-jump-p2align-next-label)
(let* ((in-insts '((jmp L1) (%p2align 4) (%label L1) (ret)))
       (out (optimize-x86-peephole-insts in-insts)))
  (assert-equal "jump over p2align to next label eliminated"
                '((%p2align 4) (%label L1) (ret))
                out))

;; 10. LEA optimization (rule-x86-lea-optimize)
(let* ((in-insts '((mov rax rbx) (add rax 8) (ret)))
       (out (optimize-x86-peephole-insts in-insts)))
  (assert-equal "mov + add immediate folded into lea"
                '((lea rax (%disp 8 rbx)) (ret))
                out))
(let* ((in-insts '((mov r10 r11) (add r10 (%imm 16)) (ret)))
       (out (optimize-x86-peephole-insts in-insts)))
  (assert-equal "mov + add %imm folded into lea"
                '((lea r10 (%disp 16 r11)) (ret))
                out))

;; 11. Jump to return across intermediate blocks (rule-x86-jump-to-ret)
(let* ((in-insts '((jmp L_end) (%label L_other) (mov rax 1) (%label L_end) (ret)))
       (out (optimize-x86-peephole-insts in-insts)))
  (assert-equal "jump across block to ret simplified to ret"
                '((ret) (%label L_other) (mov rax 1) (%label L_end) (ret))
                out))

;; 12. Direct Picopass rule invocation
(let ((out (rule-x86-self-mov-elim '((mov rax rax) (ret)))))
  (assert-equal "direct rule-x86-self-mov-elim eliminates self-mov"
                '((ret))
                out))
(let ((out (rule-x86-zero-xor '((mov rax 0) (ret)))))
  (assert-equal "direct rule-x86-zero-xor transforms mov 0 to xor"
                '((xor rax rax) (ret))
                out))

;; 13. Provenance Tracking & Firing Log Verification (Issue #769 / #814)
(reset-picopass-provenance!)
(enable-picopass-provenance!)
(let* ((in-insts '((mov rax rax)
                   (mov rbx 0)
                   (mov rcx rdx)
                   (add rcx 32)
                   (jmp L1)
                   (%label L1)
                   (ret)))
       (out (optimize-x86-peephole-insts in-insts))
       (counts (get-picopass-firing-counts))
       (log (get-picopass-firing-log)))
  (assert-equal "peephole optimized output with provenance"
                '((xor rbx rbx)
                  (lea rcx (%disp 32 rdx))
                  (%label L1)
                  (ret))
                out)
  (assert-true "provenance recorded rule-x86-self-mov-elim"
               (and (assq 'rule-x86-self-mov-elim counts)
                    (>= (cdr (assq 'rule-x86-self-mov-elim counts)) 1)))
  (assert-true "provenance recorded rule-x86-zero-xor"
               (and (assq 'rule-x86-zero-xor counts)
                    (>= (cdr (assq 'rule-x86-zero-xor counts)) 1)))
  (assert-true "provenance recorded rule-x86-lea-optimize"
               (and (assq 'rule-x86-lea-optimize counts)
                    (>= (cdr (assq 'rule-x86-lea-optimize counts)) 1)))
  (assert-true "provenance recorded rule-x86-jump-next-label"
               (and (assq 'rule-x86-jump-next-label counts)
                    (>= (cdr (assq 'rule-x86-jump-next-label counts)) 1)))
  (assert-true "provenance firing log non-empty"
               (> (length log) 0)))
(reset-picopass-provenance!)
(disable-picopass-provenance!)

;; 14. LEA + Add/Sub constant folding (rule-x86-lea-add-fold, Issue #936)
(assert-equal "lea + negative imm add folds displacement"
              '((lea rax (%disp 8 rsp)) (ret))
              (optimize-x86-peephole-insts '((lea rax (%disp 40 rsp)) (add rax (%imm -32)) (ret))))
(assert-equal "lea + negating add folds to mov base"
              '((mov rax rsp) (ret))
              (optimize-x86-peephole-insts '((lea rax (%disp 40 rsp)) (add rax (%imm -40)) (ret))))
(assert-equal "lea + positive sub folds displacement"
              '((lea rcx (%disp 40 rsp)) (ret))
              (optimize-x86-peephole-insts '((lea rcx (%disp 56 rsp)) (sub rcx 16) (ret))))
(assert-equal "lea + zero-sum self base eliminates completely"
              '((ret))
              (optimize-x86-peephole-insts '((lea rsp (%disp 16 rsp)) (sub rsp 16) (ret))))
(assert-equal "lea + add before flag-consuming jcc is NOT folded"
              '((lea rax (%disp 40 rsp)) (add rax (%imm -32)) (jcc je L_ok) (ret))
              (optimize-x86-peephole-insts '((lea rax (%disp 40 rsp)) (add rax (%imm -32)) (jcc je L_ok) (ret))))
(assert-true "folded lea program satisfies L_asm_x86?"
             (L_asm_x86? (optimize-x86-peephole
                           (make-test-asm-program '((lea rax (%disp 40 rsp)) (add rax (%imm -24)) (ret))))))

;; 15. Zero-idiom XOR preserves RFLAGS when followed by flag consumer (Issue #953)
(assert-equal "mov reg 0 before jcc is NOT folded to xor"
              '((mov rax 0) (jcc je L_ok) (ret))
              (optimize-x86-peephole-insts '((mov rax 0) (jcc je L_ok) (ret))))
(assert-equal "mov reg 0 before set is NOT folded to xor"
              '((mov rax (%imm 0)) (set e al) (ret))
              (optimize-x86-peephole-insts '((mov rax (%imm 0)) (set e al) (ret))))

;; 16. Overflow branch fusion: seto dl + movzx rdx, dl + cmp rdx, 0 + jne/je -> jo/jno (Issue #955)
(assert-equal "seto dl + movzx rdx, dl + cmp rdx 0 + jne fuses to jcc jo"
              '((add rcx (%disp -8 rsp)) (jcc jo L_slow) (ret))
              (optimize-x86-peephole-insts
                '((add rcx (%disp -8 rsp))
                  (%raw-asm "    seto dl")
                  (%raw-asm "    movzx rdx, dl")
                  (cmp rdx (%imm 0))
                  (jcc jne L_slow)
                  (ret))))
(assert-equal "seto dl + movzx rdx, dl + cmp rdx 0 + je fuses to jcc jno"
              '((sub rcx rax) (jcc jno L_ok) (ret))
              (optimize-x86-peephole-insts
                '((sub rcx rax)
                  (%raw-asm "    seto dl")
                  (%raw-asm "    movzx rdx, dl")
                  (cmp rdx 0)
                  (jcc je L_ok)
                  (ret))))

;; 17. Redundant cmp reg, 0 elimination after bitwise AND (Issue #955)
(assert-equal "and + cmp 0 + jcc jne eliminates redundant cmp 0"
              '((and rdx (%imm 3)) (jcc jne L_slow) (ret))
              (optimize-x86-peephole-insts
                '((and rdx (%imm 3))
                  (cmp rdx (%imm 0))
                  (jcc jne L_slow)
                  (ret))))
(assert-equal "and + cmp 0 + sete al eliminates redundant cmp 0"
              '((and rax (%imm 3)) (%raw-asm "    sete al") (ret))
              (optimize-x86-peephole-insts
                '((and rax (%imm 3))
                  (cmp rax (%imm 0))
                  (%raw-asm "    sete al")
                  (ret))))
(assert-equal "and + cmp 0 + signed jl preserves cmp 0 (OF check)"
              '((and rax (%imm 255)) (cmp rax 0) (jcc jl L_neg) (ret))
              (optimize-x86-peephole-insts
                '((and rax (%imm 255))
                  (cmp rax 0)
                  (jcc jl L_neg)
                  (ret))))

(test-end "Pass 143 (x86-64 Machine Peephole)")
