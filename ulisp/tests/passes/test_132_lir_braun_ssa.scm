;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 132 (Braun SSA & Block Arguments Engine)
;;; Conforms to Issue #572 & Nanopass Architecture Quality Standard
;;; =======================================================================




(test-begin "Pass 132 (Braun SSA Engine)")

;; 1. CFG creation
(let ((cfg (make-braun-cfg)))
  (assert-true "cfg is list" (pair? cfg))
  (assert-equal "initial order empty" '() (braun-cfg-ref cfg 'order)))

;; 2. Block creation and ordering
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'body)
  (braun-new-block! cfg 'exit)
  (assert-equal "block order preserved" '(entry body exit) (braun-cfg-ref cfg 'order))
  (assert-equal "current block is exit" 'exit (braun-cfg-ref cfg 'current-block)))

;; 3. Edge creation and predecessor tracking
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'b0)
  (braun-new-block! cfg 'b1)
  (braun-add-edge! cfg 'b0 'b1)
  (assert-equal "preds of b1 include b0" '(b0) (braun-get-preds cfg 'b1)))

;; 4. Local value definition and read
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'b0)
  (braun-write-variable! cfg 'x 'b0 '%v1)
  (assert-equal "read defined var" '%v1 (braun-read-variable cfg 'x 'b0)))

;; 5. Representation type lattice propagation (Issue #618)
(let ((cfg (make-braun-cfg)))
  ;; Test lattice meet/lub
  (assert-equal "rep lub bot raw is raw" 'raw-i64 (braun-rep-lub 'bot 'raw-i64))
  (assert-equal "rep lub raw raw is raw" 'raw-i64 (braun-rep-lub 'raw-i64 'raw-i64))
  (assert-equal "rep lub raw tagged is top" 'top (braun-rep-lub 'raw-i64 'tagged-fixnum))
  (assert-equal "rep lub raw top is top" 'top (braun-rep-lub 'raw-i64 'top))

  ;; Test CFG representation propagation to phi block arguments
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'then_b)
  (braun-new-block! cfg 'else_b)
  (braun-new-block! cfg 'join_b)
  (braun-add-edge! cfg 'entry 'then_b)
  (braun-add-edge! cfg 'entry 'else_b)
  (braun-add-edge! cfg 'then_b 'join_b)
  (braun-add-edge! cfg 'else_b 'join_b)

  (braun-write-variable! cfg 'v 'then_b 'v_then)
  (braun-write-variable! cfg 'v 'else_b 'v_else)
  (braun-set-rep-type! cfg 'v_then 'raw-i64)
  (braun-set-rep-type! cfg 'v_else 'raw-i64)

  (braun-seal-block! cfg 'entry)
  (braun-seal-block! cfg 'then_b)
  (braun-seal-block! cfg 'else_b)
  (braun-seal-block! cfg 'join_b)

  (let ((v-join (braun-read-variable cfg 'v 'join_b)))
    (braun-infer-block-params-rep! cfg)
    (assert-equal "inferred join param rep is raw-i64" 'raw-i64 (braun-get-rep-type cfg v-join))
    (assert-true "join param in raw-params list" (memq v-join (braun-get-raw-params cfg)))))

;; 6. Parallel move lowering via unified resolver (#969)
(let ((pmov-insts (%mir-emit-parallel-moves '(%r10 %r11) '(%r11 %r10))))
  (assert-true "live %r10/%r11 swap avoids clobbering %r10 or %r11 as scratch"
               (and (= (length pmov-insts) 3)
                    (not (eq? (cadr (car pmov-insts)) '%r10))
                    (not (eq? (cadr (car pmov-insts)) '%r11)))))

(let ((fpr-insts (%mir-emit-parallel-moves '(%xmm0 %xmm1) '(%xmm1 %xmm0))))
  (assert-true "FPR %xmm0<->%xmm1 swap emits %fmov instructions"
               (and (= (length fpr-insts) 3)
                    (eq? (caar fpr-insts) '%fmov))))

;; 7. %switch edge-argument lowering in lower-mir-ssa-to-mach-lir (#969)
(let* ((sw-prog
        (list '%lir-program
              '(strings ())
              '(stackmaps ())
              '(%lir-functions)
              '(%lir-main
                (frame-size 16)
                (body
                 (%mov %rax 1)
                 (%jump .L_sw (10 20))
                 (%block .L_sw (a b)
                   (%switch %rax .L_done ((%reg b) (%reg a))
                            ((1 .L_done ((%reg b) (%reg a)))
                             (2 .L_done ((%reg a) (%reg b))))))
                 (%block .L_done (x y)
                   (%mov %rax (%reg x))
                   (%sub %rax (%reg y))
                   (%return %rax))))))
       (mach (lower-mir-ssa-to-mach-lir sw-prog)))
  (assert-true "%switch cyclic block args lower to valid L_lir_mach?"
               (and (L_lir_mach? mach) (validate-mach-lir mach))))

(test-end "Pass 132 (Braun SSA Engine)")
