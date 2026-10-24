;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 143 (Native x86-64 Machine Peephole)
;;; Conforms to Issue #596 & Nanopass Architecture Quality Standard
;;; =======================================================================

(define *pass-tests-passed* 0)
(define *pass-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *pass-tests-passed* (+ *pass-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *pass-tests-failed* (+ *pass-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting Pass 143 (x86-64 Machine Peephole) Unit Test Suite") (newline)
(display "=======================================================") (newline)

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

(display "=======================================================") (newline)
(display " Pass 143: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
