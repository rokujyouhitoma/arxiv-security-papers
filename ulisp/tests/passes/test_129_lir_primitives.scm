;;; =======================================================================
;;; Unit Test: Pass 129 (LIR Primitive Instruction Selection)
;;; =======================================================================

(define *tests-passed* 0)
(define *tests-failed* 0)

(define (assert-true test-name expr)
  (if expr
      (begin
        (set! *tests-passed* (+ *tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *tests-failed* (+ *tests-failed* 1))
        (display "  [FAIL] ")
        (display test-name)
        (newline)
        (exit 1))))

(display "=======================================================\n")
(display " Starting Pass 129 LIR Primitive Selection Test Suite\n")
(display "=======================================================\n")

;; Test 1: Zero-arg primitives emission
(reset-lir!)
(lir-compile-zero-arg '%get-rsp -8 '())
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "zero-arg: %get-rsp emits %mov %rax %rsp"
               (and (pair? insts) (equal? (car insts) '(%mov %rax %rsp)))))

(reset-lir!)
(lir-compile-zero-arg 'eof-object -8 '())
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "zero-arg: eof-object emits %mov %rax 79"
               (and (pair? insts) (equal? (car insts) '(%mov %rax 79)))))

;; Test 2: Unary primitives emission
(reset-lir!)
(lir-compile-unary 'fxadd1 10 -8 '())
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "unary: fxadd1 emits %add %rax 4"
               (pair? (filter (lambda (i) (equal? i '(%add %rax 4))) insts))))

(reset-lir!)
(lir-compile-unary 'car '(car x) -8 '((x . -8)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "unary: car emits %load %rax %rax -1"
               (pair? (filter (lambda (i) (equal? i '(%load %rax %rax -1))) insts))))

(reset-lir!)
(lir-compile-unary 'null? 'x -8 '((x . -8)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "unary: null? emits %cmp %rax 63"
               (pair? (filter (lambda (i) (equal? i '(%cmp %rax 63))) insts))))

;; Test 3: Binary primitives emission
(reset-lir!)
(lir-compile-binop '+ 'x 'y -8 '((x . -8) (y . -16)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "binop: + emits %add instruction"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%add))) insts))))

(reset-lir!)
(lir-compile-binop 'cons 'x 'y -8 '((x . -8) (y . -16)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "binop: cons emits %alloc instruction"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%alloc))) insts))))

;; Test 3b: Raw int64 immediate and stack-slot fast paths (Issue #626)
(reset-lir!)
(lir-compile-binop '%raw-sub 'n 1 -8 '((n . -8) (*raw-vars* n)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "binop: (%raw-sub n 1) emits immediate (%raw-sub %rax 1) without stack spill"
               (and (pair? (filter (lambda (i) (equal? i '(%raw-sub %rax 1))) insts))
                    (null? (filter (lambda (i) (and (pair? i) (eq? (car i) '%store))) insts)))))

(reset-lir!)
(lir-compile-binop '%raw-add 'x 'y -8 '((x . -8) (y . -16) (*raw-vars* x y)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "binop: (%raw-add x y) on stack slots emits (%raw-add %rax (%stack -16)) without spill"
               (and (pair? (filter (lambda (i) (equal? i '(%raw-add %rax (%stack -16)))) insts))
                    (null? (filter (lambda (i) (and (pair? i) (eq? (car i) '%store))) insts)))))

(reset-lir!)
(lir-compile-unary '%unbox-fixnum 30 -8 '())
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "unary: (%unbox-fixnum 30) emits direct (%mov %rax 30) without sar"
               (equal? insts '((%mov %rax 30)))))

;; Test 3c: SIB zero-cost collection indexing (Issue #618)
(reset-lir!)
(lir-compile-binop 'vector-ref 'v 'i -8 '((v . -8) (i . -16)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "vector-ref: tagged index emits SIB (%load %rax %rdx (%sib %rax 2 3))"
               (pair? (filter (lambda (i) (equal? i '(%load %rax %rdx (%sib %rax 2 3)))) insts))))

(reset-lir!)
(lir-compile-binop 'vector-ref 'v 'i -8 '((v . -8) (i . -16) (%raw-vars i)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "vector-ref: raw index emits SIB (%load %rax %rdx (%sib %rax 8 3))"
               (pair? (filter (lambda (i) (equal? i '(%load %rax %rdx (%sib %rax 8 3)))) insts))))

(reset-lir!)
(lir-compile-triop 'vector-set! 'v 'i 'val -8 '((v . -8) (i . -16) (val . -24)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "vector-set!: tagged index emits SIB (%store %rdx (%sib %rcx 2 3) %r10)"
               (pair? (filter (lambda (i) (equal? i '(%store %rdx (%sib %rcx 2 3) %r10))) insts))))

(reset-lir!)
(lir-compile-triop 'vector-set! 'v 'i 'val -8 '((v . -8) (i . -16) (val . -24) (%raw-vars i)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "vector-set!: raw index emits SIB (%store %rdx (%sib %rcx 8 3) %r10)"
               (pair? (filter (lambda (i) (equal? i '(%store %rdx (%sib %rcx 8 3) %r10))) insts))))

;; Test 4: End-to-end AST to LIR compilation using Pass 129 primitives
(let* ((ast '(let ((x 10) (y 20)) (+ x y)))
       (ast1 (desugar-all ast))
       (ast2 (cp0-optimize ast1))
       (ast2b (lvn-all ast2))
       (ast3 (anf-all ast2b))
       (ast3b (annotate-all ast3))
       (ast3c (rtyper-all ast3b))
       (ast3d (contify-all ast3c))
       (ast4 (closure-convert ast3d))
       (ast4b (alias-escape-all ast4))
       (lir (generate-lir ast4b)))
  (assert-true "Full LIR pipeline succeeds with Pass 129 extracted primitives"
               (and (pair? lir) (eq? (car lir) '%lir-program))))

(display "=== All Pass 129 LIR Primitive Selection Tests PASSED! ===\n")
