;;; =======================================================================
;;; Unit Test Suite: Braun SSA for Arbitrary CFG & Block Arguments (#827)
;;; Conforms to DSN-33, DSN-33-02 Section 6.1 & Braun et al. (2013)
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Braun SSA Arbitrary CFG Test Suite (#827)\n")
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
        (display " | Expected: ")
        (write expected)
        (display " | Got: ")
        (write actual)
        (newline)
        (error "Assertion failed" name))))

;;; =======================================================================
;;; Group 1: CFG Topology & Arbitrary Successor/Predecessor Tracking
;;; =======================================================================
(display "\n--- Group 1: CFG Topology & Successor Tracking ---\n")

(let ((cfg (make-braun-cfg)))
  (assert-true "initial cfg is pair" (pair? cfg))
  (assert-equal "initial order empty" '() (braun-cfg-ref cfg 'order))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'b1)
  (braun-new-block! cfg 'b2)
  (braun-new-block! cfg 'exit)
  (assert-equal "block order preserved" '(entry b1 b2 exit) (braun-cfg-ref cfg 'order))
  
  ;; Forward edge
  (braun-add-edge! cfg 'entry 'b1)
  ;; Forward goto (skipping b1)
  (braun-add-edge! cfg 'entry 'b2)
  ;; Converge to exit
  (braun-add-edge! cfg 'b1 'exit)
  (braun-add-edge! cfg 'b2 'exit)
  
  (assert-equal "preds of b1" '(entry) (braun-get-preds cfg 'b1))
  (assert-equal "preds of b2" '(entry) (braun-get-preds cfg 'b2))
  (assert-equal "preds of exit" '(b1 b2) (braun-get-preds cfg 'exit))
  
  (assert-equal "succs of entry" '(b1 b2) (braun-get-succs cfg 'entry))
  (assert-equal "succs of b1" '(exit) (braun-get-succs cfg 'b1))
  (assert-equal "succs of b2" '(exit) (braun-get-succs cfg 'b2))
  (assert-equal "succs of exit" '() (braun-get-succs cfg 'exit)))

;; Auto terminator edges
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'b0)
  (braun-new-block! cfg 'b_then)
  (braun-new-block! cfg 'b_else)
  (braun-auto-add-terminator-edges! cfg 'b0 '(%jump-if %r0 b_then b_else))
  (assert-equal "auto edges for %jump-if" '(b_then b_else) (braun-get-succs cfg 'b0))
  (assert-equal "preds of b_then" '(b0) (braun-get-preds cfg 'b_then))
  (assert-equal "preds of b_else" '(b0) (braun-get-preds cfg 'b_else)))

;; Auto terminator edges for switch
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'sw_head)
  (braun-new-block! cfg 'def_tgt)
  (braun-new-block! cfg 'c1_tgt)
  (braun-new-block! cfg 'c2_tgt)
  (braun-auto-add-terminator-edges! cfg 'sw_head '(%switch %rax def_tgt ((1 c1_tgt) (2 c2_tgt))))
  (assert-equal "succs of switch head" '(def_tgt c1_tgt c2_tgt) (braun-get-succs cfg 'sw_head))
  (assert-equal "preds of def_tgt" '(sw_head) (braun-get-preds cfg 'def_tgt))
  (assert-equal "preds of c1_tgt" '(sw_head) (braun-get-preds cfg 'c1_tgt))
  (assert-equal "preds of c2_tgt" '(sw_head) (braun-get-preds cfg 'c2_tgt)))

;;; =======================================================================
;;; Group 2: Incomplete Block Delayed Resolution & seal-block! Protocol
;;; =======================================================================
(display "\n--- Group 2: Incomplete Block Delayed Resolution & Sealing ---\n")

;; Loop with back-edge: header is unsealed when body is created
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'header)
  (braun-new-block! cfg 'body)
  (braun-new-block! cfg 'exit)

  ;; Entry edge to header
  (braun-add-edge! cfg 'entry 'header)
  (braun-write-variable! cfg 'i 'entry 0)
  (braun-seal-block! cfg 'entry)

  ;; In header: read variable i before back-edge body->header is added!
  ;; header is NOT sealed yet.
  (let ((header-i (braun-read-variable cfg 'i 'header)))
    (assert-true "header parameter created for unsealed block" (symbol? header-i))
    (assert-equal "incomplete entry recorded for header" 1 (length (cdr (assq 'header (braun-cfg-ref cfg 'incomplete)))))
    
    ;; Body reads header-i, computes i + 1, writes to i
    (braun-add-edge! cfg 'header 'body)
    (braun-write-variable! cfg 'i 'body '%i_next)
    (braun-seal-block! cfg 'body)

    ;; Now add back-edge body -> header
    (braun-add-edge! cfg 'body 'header)
    (assert-equal "header predecessors after back-edge" '(entry body) (braun-get-preds cfg 'header))

    ;; Now seal header: resolves incomplete arguments
    (braun-seal-block! cfg 'header)
    (braun-add-edge! cfg 'header 'exit)
    (braun-seal-block! cfg 'exit)

    ;; Incoming values for header-i
    (assert-equal "incoming from entry is 0" 0 (braun-get-incoming cfg header-i 'entry))
    (assert-equal "incoming from body is %i_next" '%i_next (braun-get-incoming cfg header-i 'body))))

;; braun-seal-all-blocks!
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'b1)
  (braun-new-block! cfg 'b2)
  (braun-add-edge! cfg 'b1 'b2)
  (braun-seal-all-blocks! cfg)
  (assert-true "b1 sealed" (memq 'b1 (braun-cfg-ref cfg 'sealed)))
  (assert-true "b2 sealed" (memq 'b2 (braun-cfg-ref cfg 'sealed))))

;;; =======================================================================
;;; Group 3: Recursive Trivial Phi Elimination (Braun et al. 2013)
;;; =======================================================================
(display "\n--- Group 3: Recursive Trivial Phi Elimination ---\n")

;; Test 3.1: Diamond join with identical incoming values (trivial phi)
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'then_b)
  (braun-new-block! cfg 'else_b)
  (braun-new-block! cfg 'join_b)
  (braun-add-edge! cfg 'entry 'then_b)
  (braun-add-edge! cfg 'entry 'else_b)
  (braun-add-edge! cfg 'then_b 'join_b)
  (braun-add-edge! cfg 'else_b 'join_b)

  (braun-write-variable! cfg 'x 'then_b 42)
  (braun-write-variable! cfg 'x 'else_b 42)

  (braun-seal-block! cfg 'entry)
  (braun-seal-block! cfg 'then_b)
  (braun-seal-block! cfg 'else_b)
  (braun-seal-block! cfg 'join_b)

  (let ((val (braun-read-variable cfg 'x 'join_b)))
    (assert-equal "identical incoming 42 replaced trivial phi" 42 val)
    (assert-equal "no block arguments in join_b" '() (braun-get-params cfg 'join_b))))

;; Test 3.2: Loop invariant variable (self-referencing trivial phi)
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'header)
  (braun-new-block! cfg 'body)
  (braun-add-edge! cfg 'entry 'header)

  (braun-write-variable! cfg 'const_k 'entry 99)
  (braun-seal-block! cfg 'entry)

  ;; In header, read const_k while unsealed
  (let ((hk (braun-read-variable cfg 'const_k 'header)))
    ;; Body doesn't change const_k, back-edge added
    (braun-add-edge! cfg 'header 'body)
    (braun-seal-block! cfg 'body)
    (braun-add-edge! cfg 'body 'header)

    ;; Now seal header: incoming from entry is 99, from body is hk itself!
    (braun-seal-block! cfg 'header)
    (let ((resolved (braun-resolve-val cfg hk)))
      (assert-equal "self-referential loop invariant phi eliminated to 99" 99 resolved)
      (assert-equal "header has 0 block parameters" '() (braun-get-params cfg 'header)))))

;; Test 3.3: Cascading / Transitive Trivial Phis (Braun 2013 Section 3.2)
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'mid)
  (braun-new-block! cfg 'join)
  (braun-add-edge! cfg 'entry 'mid)
  (braun-add-edge! cfg 'entry 'join)
  (braun-add-edge! cfg 'mid 'join)

  (braun-write-variable! cfg 'a 'entry 100)
  (braun-seal-block! cfg 'entry)
  (braun-seal-block! cfg 'mid)
  (braun-seal-block! cfg 'join)

  (let ((res (braun-read-variable cfg 'a 'join)))
    (assert-equal "transitive single-def variable is 100" 100 res)))

;; Test 3.4: Cycle Detection Defense (CWE-400)
(let ((cfg (make-braun-cfg)))
  (let ((reps (braun-cfg-ref cfg 'replacements)))
    ;; Artificially create a cycle in replacements: x -> y, y -> x
    (braun-cfg-set! cfg 'replacements (list (cons 'p_cycle_x 'p_cycle_y)
                                            (cons 'p_cycle_y 'p_cycle_x))))
  ;; braun-resolve-val must not loop infinitely
  (let ((res (braun-resolve-val cfg 'p_cycle_x)))
    (assert-true "braun-resolve-val terminates safely on cycle (CWE-400 defense)" (symbol? res))))

;;; =======================================================================
;;; Group 4: Dominator Tree & Dominance Frontiers (Cooper et al. 2001)
;;; =======================================================================
(display "\n--- Group 4: Dominator Tree & Dominance Frontiers ---\n")

;; Diamond CFG dominators
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'then_b)
  (braun-new-block! cfg 'else_b)
  (braun-new-block! cfg 'join_b)
  (braun-add-edge! cfg 'entry 'then_b)
  (braun-add-edge! cfg 'entry 'else_b)
  (braun-add-edge! cfg 'then_b 'join_b)
  (braun-add-edge! cfg 'else_b 'join_b)

  (let ((idom (braun-compute-dominators cfg)))
    (assert-equal "idom of entry is entry" 'entry (cdr (assq 'entry idom)))
    (assert-equal "idom of then_b is entry" 'entry (cdr (assq 'then_b idom)))
    (assert-equal "idom of else_b is entry" 'entry (cdr (assq 'else_b idom)))
    (assert-equal "idom of join_b is entry" 'entry (cdr (assq 'join_b idom)))

    (let ((df (braun-compute-dominance-frontiers cfg idom)))
      (assert-equal "DF of entry is empty" '() (cdr (assq 'entry df)))
      (assert-equal "DF of then_b is (join_b)" '(join_b) (cdr (assq 'then_b df)))
      (assert-equal "DF of else_b is (join_b)" '(join_b) (cdr (assq 'else_b df)))
      (assert-equal "DF of join_b is empty" '() (cdr (assq 'join_b df))))))

;; Loop CFG dominators
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'header)
  (braun-new-block! cfg 'body)
  (braun-new-block! cfg 'exit)
  (braun-add-edge! cfg 'entry 'header)
  (braun-add-edge! cfg 'header 'body)
  (braun-add-edge! cfg 'body 'header)
  (braun-add-edge! cfg 'header 'exit)

  (let ((idom (braun-compute-dominators cfg)))
    (assert-equal "loop: idom of entry is entry" 'entry (cdr (assq 'entry idom)))
    (assert-equal "loop: idom of header is entry" 'entry (cdr (assq 'header idom)))
    (assert-equal "loop: idom of body is header" 'header (cdr (assq 'body idom)))
    (assert-equal "loop: idom of exit is header" 'header (cdr (assq 'exit idom)))

    (let ((df (braun-compute-dominance-frontiers cfg idom)))
      (assert-equal "loop: DF of body is (header)" '(header) (cdr (assq 'body df))))))

;;; =======================================================================
;;; Group 5: Multi-Way Switch & Block Arguments LIR Generation
;;; =======================================================================
(display "\n--- Group 5: Multi-Way Switch & Block Arguments LIR Generation ---\n")

(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'case1)
  (braun-new-block! cfg 'case2)
  (braun-new-block! cfg 'def_block)

  (braun-add-edge! cfg 'entry 'case1)
  (braun-add-edge! cfg 'entry 'case2)
  (braun-add-edge! cfg 'entry 'def_block)

  (braun-write-variable! cfg 'val 'entry 10)
  (braun-write-variable! cfg 'val 'case1 100)
  (braun-write-variable! cfg 'val 'case2 200)
  (braun-write-variable! cfg 'val 'def_block 999)

  (braun-set-terminator! cfg 'entry '(%switch %rax def_block ((1 case1) (2 case2))))
  (braun-set-terminator! cfg 'case1 '(%return %rax))
  (braun-set-terminator! cfg 'case2 '(%return %rax))
  (braun-set-terminator! cfg 'def_block '(%return %rax))

  (braun-seal-all-blocks! cfg)
  (let ((lir-blocks (braun-cfg->lir cfg)))
    (assert-true "generated lir is list" (list? lir-blocks))
    (assert-equal "4 lir blocks generated" 4 (length lir-blocks))
    
    (let ((entry-block (car lir-blocks)))
      (assert-equal "entry block tag is %block" '%block (car entry-block))
      (assert-equal "entry block label is entry" 'entry (cadr entry-block))
      (let ((term (car (reverse (cdddr entry-block)))))
        (assert-equal "terminator is %switch" '%switch (car term))
        (assert-equal "switch default label is def_block" 'def_block (caddr term))
        (assert-equal "switch cases length is 2" 2 (length (car (cddddr term))))))))

;;; =======================================================================
;;; Group 6: mem2reg Stack Variable Promotion (DSN-38 Section 2 D1)
;;; =======================================================================
(display "\n--- Group 6: mem2reg Stack Variable Promotion ---\n")

(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'then_b)
  (braun-new-block! cfg 'else_b)
  (braun-new-block! cfg 'join_b)

  (braun-add-edge! cfg 'entry 'then_b)
  (braun-add-edge! cfg 'entry 'else_b)
  (braun-add-edge! cfg 'then_b 'join_b)
  (braun-add-edge! cfg 'else_b 'join_b)

  ;; Store to stack offset 8 in then and else
  (braun-emit-inst! cfg 'then_b '(%store %rsp 8 111))
  (braun-emit-inst! cfg 'else_b '(%store %rsp 8 222))
  ;; Load from stack offset 8 in join_b
  (braun-emit-inst! cfg 'join_b '(%load %rax %rsp 8))

  (braun-set-terminator! cfg 'entry '(%jump-if %r0 then_b else_b))
  (braun-set-terminator! cfg 'then_b '(%jump join_b))
  (braun-set-terminator! cfg 'else_b '(%jump join_b))
  (braun-set-terminator! cfg 'join_b '(%return %rax))

  ;; Promote offset 8 to SSA register!
  (braun-promote-alloca-to-ssa cfg '(8))
  (braun-seal-all-blocks! cfg)

  ;; Verify that %store and %load at offset 8 have been promoted
  (let ((then-insts (braun-get-insts cfg 'then_b))
        (else-insts (braun-get-insts cfg 'else_b))
        (join-insts (braun-get-insts cfg 'join_b)))
    (assert-equal "then_b %store eliminated" 0 (length then-insts))
    (assert-equal "else_b %store eliminated" 0 (length else-insts))
    (assert-equal "join_b %load converted to %mov" '%mov (caar join-insts))
    ;; join_b now has block argument for stk_8
    (assert-equal "join_b has 1 block argument for promoted stack var" 1 (length (braun-get-params cfg 'join_b)))))

;;; =======================================================================
;;; Group 7: Full CFG Verifier (braun-verify-cfg)
;;; =======================================================================
(display "\n--- Group 7: Full CFG Verifier (braun-verify-cfg) ---\n")

;; Valid sealed CFG passes verification
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'b0)
  (braun-new-block! cfg 'b1)
  (braun-add-edge! cfg 'b0 'b1)
  (braun-set-terminator! cfg 'b0 '(%jump b1))
  (braun-set-terminator! cfg 'b1 '(%return %rax))
  (braun-seal-all-blocks! cfg)
  (assert-true "valid sealed CFG passes verification" (braun-verify-cfg cfg)))

;; Summary
(display "\n=======================================================\n")
(display " Tests Run:    ") (display (car *test-count*)) (newline)
(display " Tests Passed: ") (display (car *pass-count*)) (newline)
(display "=======================================================\n")
(if (= (car *test-count*) (car *pass-count*))
    (display "All Braun SSA Arbitrary CFG Tests Passed Successfully!\n")
    (error "Some tests failed!"))
