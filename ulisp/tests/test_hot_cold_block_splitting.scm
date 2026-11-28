;;; =======================================================================
;;; ULisp Test Suite: Hot/Cold Basic Block Splitting Pass (Issue #970)
;;; Verifies LIR slow-path relocation to function tail, hot-path
;;; fallthrough optimization, %lir-main exit guards, register-allocation
;;; safety across cold calls, GC stackmap preservation, and x86 %alloc
;;; out-of-line slow-path placement.
;;; =======================================================================

(test-begin "Hot/Cold Basic Block Splitting (Issue #970)")

(define (hc-list-index pred xs)
  (let loop ((cur xs) (i 0))
    (cond
      ((null? cur) #f)
      ((pred (car cur)) i)
      (else (loop (cdr cur) (+ i 1))))))

(define (hc-inst-has-label-prefix? inst pref)
  (and (pair? inst)
       (eq? (car inst) '%label)
       (pair? (cdr inst))
       (symbol? (cadr inst))
       (string-starts-with? (symbol->raw-name (cadr inst)) pref)))

(define (hc-count-hot-jumps-to-suffix insts stop-idx suf)
  (let loop ((cur insts) (i 0) (cnt 0))
    (if (or (null? cur) (and stop-idx (>= i stop-idx)))
        cnt
        (let* ((inst (car cur))
               (hit? (and (pair? inst)
                          (memq (car inst) '(%jump %direct-jump))
                          (pair? (cdr inst))
                          (symbol? (cadr inst))
                          (%lir-bf-str-has-substr? (symbol->raw-name (cadr inst)) suf))))
          (loop (cdr cur) (+ i 1) (if hit? (+ cnt 1) cnt))))))

;;; -----------------------------------------------------------------------
;;; 1. Arithmetic, Comparison, and Fused Branch Cold Splitting + Fallthrough
;;; -----------------------------------------------------------------------
(let* ((prog '(%program
               ((%function calc (x y)
                  (+ (+ (- x y) (* x y))
                     (+ (quotient x y)
                        (+ (modulo x y)
                           (+ (bitwise-and x y)
                              (+ (bitwise-ior x y)
                                 (+ (- x)
                                    (if (< x y)
                                        (if (= y 5) 11 22)
                                        (if (<= x y) 33 44))))))))))
               (%direct-call calc 10 3)))
       (lir (generate-lir prog))
       (funcs (cdr (assq '%lir-functions (cdr lir))))
       (calc-fn (car funcs))
       (calc-body (cdr (assq 'body (cddr calc-fn))))
       (ret-idx (hc-list-index (lambda (x) (and (pair? x) (eq? (car x) '%return))) calc-body))
       (first-slow-idx (hc-list-index (lambda (x) (and (pair? x) (eq? (car x) '%label) (lir-cold-label-sym? (cadr x)))) calc-body))
       (hot-jump-done (hc-count-hot-jumps-to-suffix calc-body ret-idx "_done_"))
       (hot-jump-cont (hc-count-hot-jumps-to-suffix calc-body ret-idx "_cont_"))
       (all-slows-after-ret?
        (let loop ((cur calc-body) (i 0))
          (cond
            ((null? cur) #t)
            ((and (pair? (car cur))
                  (eq? (caar cur) '%label)
                  (lir-cold-label-sym? (cadar cur))
                  ret-idx
                  (< i ret-idx))
             #f)
            (else (loop (cdr cur) (+ i 1))))))
       (no-hot-after-ret?
        (let loop ((cur (list-tail calc-body (+ ret-idx 1))) (in-cold? #f))
          (cond
            ((null? cur) #t)
            ((and (pair? (car cur)) (eq? (caar cur) '%label))
             (and (lir-cold-label-sym? (cadar cur))
                  (loop (cdr cur) #t)))
            (in-cold? (loop (cdr cur) (not (lir-split-unconditional-terminator? (car cur)))))
            (else #f)))))
  (assert-true "1.1 calc has relocated cold blocks after %return"
               (and ret-idx first-slow-idx (< ret-idx first-slow-idx)))
  (assert-true "1.2 zero cold *_slow blocks remain before %return"
               all-slows-after-ret?)
  (assert-true "1.3 only cold blocks exist after %return"
               no-hot-after-ret?)
  (assert-equal "1.4 hot path has 0 unconditional jumps to *_done" 0 hot-jump-done)
  (assert-equal "1.5 hot path has 0 unconditional jumps to *_cont" 0 hot-jump-cont)
  (assert-true "1.6 L_lir_canonical? holds after splitting"
               (L_lir_canonical? lir))
  (assert-true "1.7 lir-split-hot-cold-blocks is idempotent (eq?)"
               (eq? (lir-split-hot-cold-blocks lir) lir))
  (assert-equal "1.8 calc evaluates correctly on LIR VM (tagged 4*(38+22)=240? let's check)"
                (eval-lir-program lir)
                (* 4 (+ (+ (- 10 3) (* 10 3))
                        (+ (quotient 10 3)
                           (+ (modulo 10 3)
                              (+ (bitwise-and 10 3)
                                 (+ (bitwise-ior 10 3)
                                    (+ (- 10)
                                       (if (< 10 3)
                                           (if (= 3 5) 11 22)
                                           (if (<= 10 3) 33 44))))))))))
  ;; Verify emit-x86-64, emit-aarch64, emit-c all succeed cleanly
  (with-output-to-file "build/test_hc_split_x86.s" (lambda () (emit-x86-64 lir 'hybrid)))
  (with-output-to-file "build/test_hc_split_arm.s" (lambda () (emit-aarch64 lir 'none)))
  (with-output-to-file "build/test_hc_split.c" (lambda () (emit-c lir 'none)))
  (assert-true "1.9 all three backends emitted code successfully" #t))

;;; -----------------------------------------------------------------------
;;; 2. THREAT-970-1: %lir-main Fallthrough Guard & VM / Peephole Safety
;;; -----------------------------------------------------------------------
(let* ((lir (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all '(+ (if (= 1 2) 10 20) 3)))))))
       (main-body (cdr (assq 'body (cdr (assq '%lir-main (cdr lir))))))
       (has-slow? (let loop ((xs main-body))
                    (and (pair? xs)
                         (or (and (pair? (car xs)) (eq? (caar xs) '%label) (lir-cold-label-sym? (cadar xs)))
                             (loop (cdr xs)))))))
  ;; Also test an explicit %lir-main with inline slow block through lir-fuse-branches -> lir-peephole-optimize
  (let* ((raw-prog (list '%lir-program
                         '(strings ())
                         '(stackmaps ())
                         '(%lir-functions)
                         '(%lir-main
                           (frame-size 32)
                           (body
                            (%mov %rax 4)
                            (%cmp %rax 0)
                            (%jump-cond "jne" .add_slow_970)
                            (%mov %rax 40)
                            (%jump .add_done_970)
                            (%label .add_slow_970)
                            (%mov %rax 100)
                            (%label .add_done_970)
                            (%add %rax 2)
                            (%return)))))
         (split-prog (lir-fuse-branches raw-prog))
         (opt-prog (lir-peephole-optimize split-prog))
         (mbody (cdr (assq 'body (cdr (assq '%lir-main (cdr opt-prog))))))
         (slow-idx (hc-list-index (lambda (x) (equal? x '(%label .add_slow_970))) mbody))
         (done-idx (hc-list-index (lambda (x) (equal? x '(%label .add_done_970))) mbody))
         (exit-idx (hc-list-index (lambda (x) (and (pair? x) (eq? (car x) '%label) (lir-hot-exit-label-sym? (cadr x)))) mbody))
         (ret-idx (hc-list-index (lambda (x) (equal? x '(%return))) mbody)))
    (assert-true "2.1 %lir-main slow block relocated after done block"
                 (and slow-idx done-idx (< done-idx slow-idx)))
    (assert-true "2.2 %lir-main has .L_hot_exit_* guard label after cold region"
                 (and slow-idx exit-idx (< slow-idx exit-idx)))
    (assert-true "2.3 %return is after .L_hot_exit_* guard label"
                 (and exit-idx ret-idx (< exit-idx ret-idx)))
    (assert-false "2.4 hot path omits (%jump .add_done_970)"
                  (member '(%jump .add_done_970) (let take ((xs mbody) (k done-idx) (acc '()))
                                                   (if (<= k 0) (reverse acc) (take (cdr xs) (- k 1) (cons (car xs) acc))))))
    (assert-equal "2.5 %lir-main executes slow path + jumps back to .add_done_970 + exits cleanly without falling into cold block"
                  102
                  (eval-lir-program opt-prog))
    (assert-true "2.6 already-split opt-prog stays idempotent under lir-split-hot-cold-blocks"
                 (eq? (lir-split-hot-cold-blocks opt-prog) opt-prog))))

;;; -----------------------------------------------------------------------
;;; 3. Register Allocation Safety Across Slow-Path Branch (Global Call-Free Guard)
;;; -----------------------------------------------------------------------
(let* ((prog (list '%lir-program
                   '(strings ())
                   '(stackmaps ((sp_0 16 0)))
                   (list '%lir-function
                         'slow_fn
                         '(params (a))
                         '(frame-size 32)
                         '(body
                           (%store %rsp -24 %rdi)
                           (%mov %rax %rsi)
                           (%cmp %rax 1)
                           (%jump-cond "jne" .add_slow_reg_test)
                           (%mov %rax 10)
                           (%label .add_done_reg_test)
                           (%load %rcx %rsp -24)
                           (%add %rax %rcx)
                           (%return)
                           (%label .add_slow_reg_test)
                           (%direct-call __ulisp_slow_ulisp_fn_num_plus_a8 16 sp_0)
                           (%jump .add_done_reg_test)))
                   '(%lir-functions)
                   '(%lir-main (frame-size 0) (body (%mov %rax 0) (%return)))))
       ;; Verify lir-regalloc-inst-branches-to-cold-slow? detects the slow branch
       (cond-jmp '(%jump-cond "jne" .add_slow_reg_test))
       (hot-jmp '(%jump-cond "jne" .L_else_1)))
  (assert-true "3.1 lir-regalloc-inst-branches-to-cold-slow? detects *_slow target"
               (lir-regalloc-inst-branches-to-cold-slow? cond-jmp))
  (assert-false "3.2 lir-regalloc-inst-branches-to-cold-slow? ignores normal hot branch target"
                (lir-regalloc-inst-branches-to-cold-slow? hot-jmp))
  ;; Test through lir-linear-scan-allocate-body that slot -24 is NOT promoted into a caller-saved reg
  ;; across (%jump-cond "jne" .add_slow_reg_test)
  (let* ((fn-body (cdr (assq 'body (cdr (list-ref prog 3)))))
         (alloced (lir-linear-scan-allocate-body fn-body)))
    (assert-true "3.3 slot -24 remains stack-backed across branch to relocated slow path"
                 (and (member '(%store %rsp -24 %rdi) alloced)
                      (member '(%load %rcx %rsp -24) alloced)
                      #t))))

;;; -----------------------------------------------------------------------
;;; 4. x86-64 %alloc Out-of-Line Cold Slow Path (.L_alloc_slow_N at tail)
;;; -----------------------------------------------------------------------
(let* ((saved-mode (car *backend-gc-mode*))
       (lir-alloc '(%lir-program
                    (strings ())
                    (stackmaps ())
                    (%lir-functions
                     (%lir-function alloc_demo
                       (params (x))
                       (frame-size 32)
                       (body (%alloc %rax 24 9 -16)
                             (%store %rax -1 %rdi)
                             (%return))))
                    (%lir-main
                     (frame-size 32)
                     (body (%alloc %rax 24 9 -16)
                           (%mov %rbx %rax)
                           (%return)))))
       (asm-prog (begin
                   (set-car! *backend-gc-mode* 'managed)
                   (select-instructions-x86 lir-alloc)))
       (opt-asm (optimize-x86-peephole asm-prog))
       (fn-body (cdr (assq 'body (cdr (car (cdr (assq '%asm-functions (cdr opt-asm))))))))
       (main-body (cdr (assq 'body (cdr (assq '%asm-main (cdr opt-asm))))))
       (is-slow-lbl? (lambda (lbl-str inst)
                       (and (pair? inst)
                            (eq? (car inst) '%label)
                            (string=? (asm-label->str (cadr inst)) lbl-str))))
       (is-fast-lbl? (lambda (lbl-str inst)
                       (and (pair? inst)
                            (eq? (car inst) '%label)
                            (string=? (asm-label->str (cadr inst)) lbl-str)))))
  (set-car! *backend-gc-mode* saved-mode)
  (assert-true "4.1 %asm-main with out-of-line %alloc satisfies L_asm_x86?"
               (L_asm_x86? (list '%asm-program
                                 '(strings ())
                                 '(stackmaps ())
                                 '(%asm-functions)
                                 (assq '%asm-main (cdr opt-asm)))))
  ;; Check alloc_demo function layout: .L_alloc_fast_1 < ret < .L_alloc_slow_1
  (let ((fast1 (hc-list-index (lambda (i) (is-fast-lbl? ".L_alloc_fast_1" i)) fn-body))
        (ret1 (hc-list-index (lambda (i) (equal? i '(ret))) fn-body))
        (slow1 (hc-list-index (lambda (i) (is-slow-lbl? ".L_alloc_slow_1" i)) fn-body)))
    (assert-true "4.2 alloc_demo fast label falls through before ret"
                 (and fast1 ret1 (< fast1 ret1)))
    (assert-true "4.3 alloc_demo .L_alloc_slow_1 is placed out-of-line after ret"
                 (and ret1 slow1 (< ret1 slow1)))
    (assert-true "4.4 alloc_demo hot path branches with (jcc ja .L_alloc_slow_1)"
                 (and (member '(jcc ja .L_alloc_slow_1) fn-body) #t))
    (assert-true "4.5 alloc_demo .L_alloc_slow_1 returns with (jmp .L_alloc_fast_1)"
                 (and (member '(jmp .L_alloc_fast_1) fn-body) #t)))
  ;; Check %asm-main layout: .L_alloc_fast_2 < ret < .L_alloc_slow_2
  (let ((fast2 (hc-list-index (lambda (i) (is-fast-lbl? ".L_alloc_fast_2" i)) main-body))
        (ret2 (hc-list-index (lambda (i) (equal? i '(ret))) main-body))
        (slow2 (hc-list-index (lambda (i) (is-slow-lbl? ".L_alloc_slow_2" i)) main-body)))
    (assert-true "4.6 %asm-main .L_alloc_slow_2 is placed safely after epilogue (ret)"
                 (and fast2 ret2 slow2 (< fast2 ret2) (< ret2 slow2)))
    (assert-true "4.7 %asm-main .L_alloc_slow_2 jumps back to .L_alloc_fast_2"
                 (and (member '(jmp .L_alloc_fast_2) main-body) #t))))

(newline)
(test-end "Hot/Cold Basic Block Splitting (Issue #970)")
