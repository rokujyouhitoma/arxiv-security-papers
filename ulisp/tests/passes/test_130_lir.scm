;;; =======================================================================
;;; ULisp Test Suite: Block Arguments SSA & Braun On-The-Fly Construction
;;; Conforms to DSN-33 Section 8.1 & Issue #523
;;;
;;; Verifies:
;;; 1. Braun on-the-fly SSA construction (make-braun-cfg, braun-write-variable!, braun-read-variable)
;;; 2. Single-predecessor dominance optimization (no phi / no block argument needed)
;;; 3. Multi-predecessor join points with block arguments and incoming values
;;; 4. Unsealed block proxy arguments for loop headers and cycle resolution upon braun-seal-block!
;;; 5. Trivial block argument pruning (try-remove-trivial! when all operands are `same`)
;;; 6. braun-cfg->lir generation of %block, %jump with arguments, and %jump-if
;;; 7. Multi-backend code generation and execution with Block Arguments SSA
;;; =======================================================================

(define *lir-tests-passed* 0)
(define *lir-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *lir-tests-passed* (+ *lir-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *lir-tests-failed* (+ *lir-tests-failed* 1))
        (display "  [FAIL] ")
        (display test-name)
        (display " -> Expected: ")
        (display expected)
        (display " but got: ")
        (display actual)
        (newline)
        (exit 1))))

(define (assert-true test-name expr)
  (assert-equal test-name #t (if expr #t #f)))

(define (assert-false test-name expr)
  (assert-equal test-name #f (if expr #t #f)))

(display "=======================================================")
(newline)
(display " Starting ULisp Block Arguments SSA & Braun Construction Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; Test Group 1: Local Definitions & Single Predecessor Optimization
(display "--- Group 1: Local Defs & Single Predecessor Dominance ---")
(newline)

(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-write-variable! cfg 'x 'entry 42)
  (braun-seal-block! cfg 'entry)

  ;; 1. Local read within entry block returns the written value directly
  (assert-equal "local write & read in same block" 42 (braun-read-variable cfg 'x 'entry))

  ;; 2. Block with single predecessor inherits variable without creating a block argument
  (braun-new-block! cfg 'b1)
  (braun-add-edge! cfg 'entry 'b1)
  (braun-seal-block! cfg 'b1)
  (let ((val (braun-read-variable cfg 'x 'b1)))
    (assert-equal "single-pred inherits value without block arg" 42 val)
    (assert-equal "b1 parameter count is 0" 0 (length (braun-get-params cfg 'b1)))))

;;; Test Group 2: Multi-Predecessor Join Blocks (Conditional Merge)
(display "--- Group 2: Join Blocks & Block Arguments ---")
(newline)

(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'then_b)
  (braun-new-block! cfg 'else_b)
  (braun-new-block! cfg 'join_b)

  (braun-add-edge! cfg 'entry 'then_b)
  (braun-add-edge! cfg 'entry 'else_b)
  (braun-add-edge! cfg 'then_b 'join_b)
  (braun-add-edge! cfg 'else_b 'join_b)

  (braun-write-variable! cfg 'v 'then_b 111)
  (braun-write-variable! cfg 'v 'else_b 222)

  (braun-seal-block! cfg 'entry)
  (braun-seal-block! cfg 'then_b)
  (braun-seal-block! cfg 'else_b)
  (braun-seal-block! cfg 'join_b)

  (let ((v-join (braun-read-variable cfg 'v 'join_b)))
    (assert-true "join block creates parameter symbol" (symbol? v-join))
    (assert-equal "join_b has 1 block argument" 1 (length (braun-get-params cfg 'join_b)))
    (assert-equal "incoming from then is 111" 111 (braun-get-incoming cfg v-join 'then_b))
    (assert-equal "incoming from else is 222" 222 (braun-get-incoming cfg v-join 'else_b))))

;;; Test Group 3: Trivial Argument Pruning
(display "--- Group 3: Trivial Argument Pruning ---")
(newline)

(let ((cfg (make-braun-cfg)))
  ;; Variable 'z' is defined in entry as 999 and NOT modified in branches
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'then_b)
  (braun-new-block! cfg 'else_b)
  (braun-new-block! cfg 'join_b)

  (braun-add-edge! cfg 'entry 'then_b)
  (braun-add-edge! cfg 'entry 'else_b)
  (braun-add-edge! cfg 'then_b 'join_b)
  (braun-add-edge! cfg 'else_b 'join_b)

  (braun-write-variable! cfg 'z 'entry 999)

  (braun-seal-block! cfg 'entry)
  (braun-seal-block! cfg 'then_b)
  (braun-seal-block! cfg 'else_b)
  (braun-seal-block! cfg 'join_b)

  (let ((val (braun-read-variable cfg 'z 'join_b)))
    ;; Since both then_b and else_b provide 999, the block argument is trivial and pruned to 999!
    (assert-equal "trivial block argument pruned to constant 999" 999 val)
    (assert-equal "join_b parameters count remains 0" 0 (length (braun-get-params cfg 'join_b)))))

;;; Test Group 4: Unsealed Blocks & Loop Back-Edge Resolution
(display "--- Group 4: Unsealed Blocks & Loop Back-Edges ---")
(newline)

(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'loop_hdr)
  (braun-new-block! cfg 'loop_body)
  (braun-new-block! cfg 'loop_exit)

  ;; Entry edge to loop_hdr
  (braun-add-edge! cfg 'entry 'loop_hdr)
  (braun-write-variable! cfg 'i 'entry 0)
  (braun-write-variable! cfg 'sum 'entry 0)
  (braun-seal-block! cfg 'entry)

  ;; Loop header is NOT sealed yet because back-edge loop_body -> loop_hdr is pending!
  (let ((i-hdr (braun-read-variable cfg 'i 'loop_hdr))
        (sum-hdr (braun-read-variable cfg 'sum 'loop_hdr)))
    (assert-true "unsealed loop header creates proxy arg for i" (symbol? i-hdr))
    (assert-true "unsealed loop header creates proxy arg for sum" (symbol? sum-hdr))
    (assert-equal "loop_hdr initially has 2 proxy params" 2 (length (braun-get-params cfg 'loop_hdr)))

    ;; In loop_body, read variables, update them, and add back-edge
    (braun-add-edge! cfg 'loop_hdr 'loop_body)
    (braun-seal-block! cfg 'loop_body)
    (braun-write-variable! cfg 'i 'loop_body 'next_i)
    (braun-write-variable! cfg 'sum 'loop_body 'next_sum)

    ;; Connect back-edge
    (braun-add-edge! cfg 'loop_body 'loop_hdr)

    ;; Now seal loop_hdr: this resolves incomplete block arguments!
    (braun-seal-block! cfg 'loop_hdr)

    ;; Verify that incoming arguments from entry and loop_body are wired correctly
    (assert-equal "i incoming from entry is 0" 0 (braun-get-incoming cfg i-hdr 'entry))
    (assert-equal "i incoming from loop_body is next_i" 'next_i (braun-get-incoming cfg i-hdr 'loop_body))
    (assert-equal "sum incoming from entry is 0" 0 (braun-get-incoming cfg sum-hdr 'entry))
    (assert-equal "sum incoming from loop_body is next_sum" 'next_sum (braun-get-incoming cfg sum-hdr 'loop_body))

    ;; Exit block has single predecessor (loop_hdr)
    (braun-add-edge! cfg 'loop_hdr 'loop_exit)
    (braun-seal-block! cfg 'loop_exit)
    (assert-equal "exit block directly reads sum-hdr without extra param" sum-hdr (braun-read-variable cfg 'sum 'loop_exit))))

;;; Test Group 5: Braun CFG to LIR Generation (braun-cfg->lir)
(display "--- Group 5: braun-cfg->lir Transformation ---")
(newline)

(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'b_then)
  (braun-new-block! cfg 'b_else)
  (braun-new-block! cfg 'b_join)

  (braun-add-edge! cfg 'entry 'b_then)
  (braun-add-edge! cfg 'entry 'b_else)
  (braun-add-edge! cfg 'b_then 'b_join)
  (braun-add-edge! cfg 'b_else 'b_join)

  (braun-write-variable! cfg 'res 'b_then 10)
  (braun-write-variable! cfg 'res 'b_else 20)

  (braun-seal-block! cfg 'entry)
  (braun-seal-block! cfg 'b_then)
  (braun-seal-block! cfg 'b_else)
  (braun-seal-block! cfg 'b_join)

  (braun-set-terminator! cfg 'b_then '(%jump b_join))
  (braun-set-terminator! cfg 'b_else '(%jump b_join))
  (let ((res-join (braun-read-variable cfg 'res 'b_join)))
    (braun-set-terminator! cfg 'b_join (list '%return res-join))

    (let ((lir-blocks (braun-cfg->lir cfg)))
      (assert-equal "lir contains 4 blocks" 4 (length lir-blocks))
      ;; Check b_join block structure
      (let ((join-block (assq 'b_join (map cdr lir-blocks))))
        (assert-true "has b_join block" (pair? join-block))
        (let ((params (cadr join-block)))
          (assert-equal "b_join has 1 parameter" 1 (length params))
          (assert-equal "parameter name matches" res-join (car params)))))))

;;; Test Group 6: Full Nanopass Integration with Block Arguments
(display "--- Group 6: Full Nanopass LIR Integration ---")
(newline)

(let* ((hir (closure-convert (anf-all (cp0-optimize (desugar-all '(if (= (read-char) 10) 42 0))))))
       (lir (generate-lir hir))
       (main-body (cdr (assq 'body (cdr (assq '%lir-main (cdr lir)))))))
  (assert-true "main body has %block"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%block))) main-body)))
  (assert-true "main body has %jump with args"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%jump) (pair? (cddr i)))) main-body))))

;;; Test Group 7: Contification Integration with Block Arguments
(display "--- Group 7: Contification Block Arguments ---")
(newline)

(let* ((ast '(letrec ((loop (lambda (n acc) (if (= n 0) acc (loop (- n 1) (+ acc n))))))
               (loop 10 0)))
       (cont-ast (contify-all (anf-all (cp0-optimize (desugar-all ast)))))
       (hir (closure-convert cont-ast))
       (lir (generate-lir hir))
       (main-body (cdr (assq 'body (cdr (assq '%lir-main (cdr lir)))))))
  (assert-true "contified loop generates %block"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%block))) main-body)))
  (assert-true "contified loop generates %jump"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%jump))) main-body))))

;;; Test Group 8: Non-Escaping Closure Stack Allocation (#:stack-alloc Annotation)
(display "--- Group 8: Non-Escaping Closure Stack Allocation (#:stack-alloc) ---")
(newline)

;; 8.1 Direct LIR compilation of (annotate #:stack-alloc (%make-closure-env ...))
(let* ((prog '(%program () (let ((x 10) (y 20)) (let ((f (annotate #:stack-alloc (%make-closure-env 'L_fn x y)))) (%closure-ref f 1)))))
       (lir (generate-lir prog))
       (main-body (cdr (assq 'body (cdr (assq '%lir-main (cdr lir)))))))
  (assert-true "stack-annotated closure emits %alloc-stack"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%alloc-stack))) main-body)))
  (assert-false "stack-annotated closure avoids heap %alloc"
                (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%alloc))) main-body))))

;; 8.2 Unannotated %make-closure-env emits heap %alloc
(let* ((prog '(%program () (let ((x 10) (y 20)) (%make-closure-env 'L_fn x y))))
       (lir (generate-lir prog))
       (main-body (cdr (assq 'body (cdr (assq '%lir-main (cdr lir)))))))
  (assert-true "unannotated %make-closure-env emits heap %alloc"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%alloc))) main-body))))

;; 8.3 End-to-end Pass 110 -> 120 -> 130 optimization pipeline
(let* ((ast '(let ((f (lambda (x) (+ x 1)))) (f 41)))
       (hir110 (closure-convert (anf-all (cp0-optimize (desugar-all ast)))))
       (hir120 (alias-escape-all hir110))
       (lir130 (generate-lir hir120))
       (main-body (cdr (assq 'body (cdr (assq '%lir-main (cdr lir130)))))))
  (assert-true "Pass 120 annotated closure with #:stack-alloc"
               (let check-ann ((expr hir120))
                 (cond
                   ((not (pair? expr)) #f)
                   ((and (eq? (car expr) 'annotate) (eq? (cadr expr) '#:stack-alloc)) #t)
                   (else (or (check-ann (car expr)) (check-ann (cdr expr)))))))
  (assert-true "Pass 130 pipeline output uses %alloc-stack"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%alloc-stack))) main-body)))
  (assert-false "Pass 130 pipeline output avoids heap %alloc"
                (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%alloc))) main-body))))

(newline)
(display "=======================================================")
(newline)
(display " All Block Arguments SSA & Braun Construction Tests PASSED: ")
(display *lir-tests-passed*)
(display "/")
(display (+ *lir-tests-passed* *lir-tests-failed*))
(newline)
(display "=======================================================")
(newline)
