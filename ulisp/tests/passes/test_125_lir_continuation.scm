;;; =======================================================================
;;; Unit Test: Pass 125 (LIR Continuation & Loop Fusion Lowering)
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================



(display "=======================================================\n")
(test-begin "Pass 125 (LIR Continuation & Loop Fusion)")
(display "=======================================================\n")

;; Test 1: cont-body-has-external-call? and expr-references-var?
(assert-true "expr-references-var?: finds variable in expression"
             (expr-references-var? '(+ x 1) 'x))
(assert-true "expr-references-var?: returns #f if variable is absent"
             (not (expr-references-var? '(+ y 1) 'x)))

(assert-true "cont-body-has-external-call?: identifies external call"
             (cont-body-has-external-call? '(%direct-call f 1 2) 'loop_k))
(assert-true "cont-body-has-external-call?: returns #f for internal continuation call"
             (not (cont-body-has-external-call? '(%cont-call loop_k 1 2) 'loop_k)))

;; Test 2: lir-compile-cont-call emits direct branch %jump
(reset-lir!)
(let ((test-env '((k_cont . (%cont-target L_k_target ((x . %rbx))))
                  (val . -8))))
  (lir-compile-cont-call 'k_cont '(val) -16 test-env))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "cont-call: emits %jump to continuation target label"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%jump) (eq? (cadr i) 'L_k_target))) insts))))

;; Test 3: 2-arg pure swap emits %mov via scratch without stack spills
(reset-lir!)
(let ((test-env '((loop_k . (%cont-target L_loop2 ((a . (reg . %rbx)) (b . (reg . %r13))))))))
  (lir-compile-cont-call 'loop_k '(b a) -16 test-env))
(let* ((insts (reverse (car *lir-instructions*)))
       (stores (filter (lambda (i) (and (pair? i) (eq? (car i) '%store))) insts))
       (movs (filter (lambda (i) (and (pair? i) (eq? (car i) '%mov))) insts)))
  (assert-equal "2-arg swap: zero stack stores" 0 (length stores))
  (assert-equal "2-arg swap: exactly 3 %mov instructions" 3 (length movs)))

;; Test 4: 3-arg pure 3-cycle (loop b c a) emits 0 stack spills and 4 %mov instructions
(reset-lir!)
(let ((test-env '((loop_k . (%cont-target L_loop3 ((a . (reg . %rbx)) (b . (reg . %r13)) (c . (reg . %r14))))))))
  (lir-compile-cont-call 'loop_k '(b c a) -24 test-env))
(let* ((insts (reverse (car *lir-instructions*)))
       (stores (filter (lambda (i) (and (pair? i) (eq? (car i) '%store))) insts))
       (loads (filter (lambda (i) (and (pair? i) (eq? (car i) '%load))) insts))
       (movs (filter (lambda (i) (and (pair? i) (eq? (car i) '%mov))) insts)))
  (assert-equal "3-arg cycle: zero stack stores" 0 (length stores))
  (assert-equal "3-arg cycle: zero stack loads" 0 (length loads))
  (assert-equal "3-arg cycle: exactly 4 %mov instructions (m+c)" 4 (length movs)))

;; Test 5: 3-arg DAG (loop (+ i 1) (+ acc i) (+ total acc)) peels in-place with 0 spills
(reset-lir!)
(let ((test-env '((loop_dag . (%cont-target L_dag ((i . (reg . %rbx)) (acc . (reg . %r13)) (total . (reg . %r14)))))
                  (i . (reg . %rbx))
                  (acc . (reg . %r13))
                  (total . (reg . %r14)))))
  (lir-compile-cont-call 'loop_dag '((+ i 1) (+ acc i) (+ total acc)) -24 test-env))
(let* ((insts (reverse (car *lir-instructions*)))
       (stores (filter (lambda (i) (and (pair? i) (eq? (car i) '%store))) insts))
       (adds (filter (lambda (i) (and (pair? i) (eq? (car i) '%add))) insts)))
  (assert-equal "3-arg DAG: zero stack stores" 0 (length stores))
  (assert-equal "3-arg DAG: 3 in-place %add instructions in reverse order"
                '((%add %r14 %r13) (%add %r13 %rbx) (%add %rbx 4))
                adds))

;; Test 6: 3-arg Fibonacci (loop b (+ a b) (- n 1)) uses at most 1 stack temp slot
(reset-lir!)
(let ((test-env '((fib_k . (%cont-target L_fib ((a . (reg . %rbx)) (b . (reg . %r13)) (n . (reg . %r14)))))
                  (a . (reg . %rbx))
                  (b . (reg . %r13))
                  (n . (reg . %r14)))))
  (lir-compile-cont-call 'fib_k '(b (+ a b) (- n 1)) -24 test-env))
(let* ((insts (reverse (car *lir-instructions*)))
       (stores (filter (lambda (i) (and (pair? i) (eq? (car i) '%store))) insts))
       (subs (filter (lambda (i) (and (pair? i) (eq? (car i) '%sub))) insts)))
  (assert-true "3-arg Fibonacci: at most 1 stack store" (<= (length stores) 1))
  (assert-equal "3-arg Fibonacci: n decremented in-place" '((%sub %r14 4)) subs))

;; Test 7: 4-arg mixed (identity + DAG + 2-cycle swap) with 0 stack spills
(reset-lir!)
(let ((test-env '((mix_k . (%cont-target L_mix ((k . (reg . %rbx)) (x . (reg . %r13)) (y . (reg . %r14)) (s . (reg . %r15)))))
                  (k . (reg . %rbx))
                  (x . (reg . %r13))
                  (y . (reg . %r14))
                  (s . (reg . %r15)))))
  (lir-compile-cont-call 'mix_k '(k y x (+ s 1)) -32 test-env))
(let* ((insts (reverse (car *lir-instructions*)))
       (stores (filter (lambda (i) (and (pair? i) (eq? (car i) '%store))) insts))
       (adds (filter (lambda (i) (and (pair? i) (eq? (car i) '%add))) insts))
       (movs (filter (lambda (i) (and (pair? i) (eq? (car i) '%mov))) insts)))
  (assert-equal "4-arg mixed: zero stack stores" 0 (length stores))
  (assert-equal "4-arg mixed: in-place %add on %r15" '((%add %r15 4)) adds)
  (assert-equal "4-arg mixed: 3 %mov instructions for swap" 3 (length movs)))

(test-end "Pass 125 (LIR Continuation & Loop Fusion)")
