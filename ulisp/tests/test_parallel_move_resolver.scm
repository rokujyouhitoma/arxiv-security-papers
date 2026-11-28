;;; =======================================================================
;;; Unit & Exhaustive Verification Test Suite: General Parallel Move Resolver (#969)
;;; =======================================================================

(test-begin "General Parallel Move Resolver (Issue #969)")

(define (make-pmov-vm-prog body-insts)
  (list '%lir-program
        '(strings ())
        '(stackmaps ())
        '(%lir-functions)
        (list '%lir-main
              '(frame-size 64)
              (cons 'body body-insts))))

(define (pmov-expected-min-moves pairs)
  (let* ((non-self (filter (lambda (p) (not (lir-pmov-loc-equal? (car p) (cdr p)))) pairs))
         (m (length non-self))
         (visited-box (cons '() '()))
         (cycles-box (cons 0 '())))
    (define (find-src loc)
      (let loop ((ps non-self))
        (cond
          ((null? ps) #f)
          ((lir-pmov-loc-equal? (caar ps) loc) (cdar ps))
          (else (loop (cdr ps))))))
    (for-each
     (lambda (p)
       (let ((start (car p)))
         (if (not (member start (car visited-box)))
             (let walk ((cur start) (path '()))
               (cond
                 ((member cur path)
                  ;; Found a newly discovered cycle! (cur and everything in path were unvisited)
                  (set-car! cycles-box (+ (car cycles-box) 1))
                  (for-each (lambda (x)
                              (if (not (member x (car visited-box)))
                                  (set-car! visited-box (cons x (car visited-box)))))
                            path))
                 ((member cur (car visited-box))
                  (for-each (lambda (x)
                              (if (not (member x (car visited-box)))
                                  (set-car! visited-box (cons x (car visited-box)))))
                            path))
                 (else
                  (let ((nxt (find-src cur)))
                    (if nxt
                        (walk nxt (cons cur path))
                        (for-each (lambda (x)
                                    (if (not (member x (car visited-box)))
                                        (set-car! visited-box (cons x (car visited-box)))))
                                  (cons cur path))))))))))
     non-self)
    (+ m (car cycles-box))))

(define (pmov-verify-and-check-min! label pairs gpr-s fpr-s fb)
  (let* ((plan (lir-parallel-move-plan pairs gpr-s fpr-s fb))
         (allowed (append gpr-s (append fpr-s (if fb (list fb) '()))))
         (ok? (lir-verify-parallel-move-plan pairs plan allowed))
         (min-len (pmov-expected-min-moves pairs)))
    (assert-true (string-append label " [symbolic equivalence]") ok?)
    (assert-equal (string-append label " [theoretical minimum m+c]") min-len (length plan))
    plan))

;;; -----------------------------------------------------------------------
;;; Group 1: Edge Cases, Fan-out, Chains, Cycles & Multi-Cycles (N=0..8)
;;; -----------------------------------------------------------------------
(assert-equal "1.1 empty parallel move returns empty plan"
              '()
              (lir-parallel-move-plan '() *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f))

(pmov-verify-and-check-min!
 "1.2 all identity moves"
 '((%rax . %rax) (%rbx . %rbx) ((%stack -8) . (%stack -8)))
 *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)

(pmov-verify-and-check-min!
 "1.3 fan-out single source to multiple destinations"
 '((%rax . %rsi) (%rbx . %rsi) (%rcx . %rsi) ((%stack -8) . %rsi))
 *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)

(pmov-verify-and-check-min!
 "1.4 5-node dependency chain (DAG peel, 0 scratches)"
 '((%rax . %rbx) (%rbx . %rcx) (%rcx . %rdx) (%rdx . %rsi) (%rsi . %rdi))
 *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)

(pmov-verify-and-check-min!
 "1.5 2-cycle swap"
 '((%rax . %rbx) (%rbx . %rax))
 *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)

(pmov-verify-and-check-min!
 "1.6 3-cycle permutation"
 '((%rax . %rbx) (%rbx . %rcx) (%rcx . %rax))
 *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)

(pmov-verify-and-check-min!
 "1.7 5-cycle permutation"
 '((%rax . %rbx) (%rbx . %rcx) (%rcx . %rdx) (%rdx . %rsi) (%rsi . %rax))
 *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)

(let ((plan-2cyc
       (pmov-verify-and-check-min!
        "1.8 two disjoint 2-cycles reuse single scratch"
        '((%rax . %rbx) (%rbx . %rax) (%rcx . %rdx) (%rdx . %rcx))
        *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)))
  (assert-equal "1.8b two disjoint 2-cycles emit 6 moves (4 + 2)" 6 (length plan-2cyc)))

(pmov-verify-and-check-min!
 "1.9 mixed DAG + 3-cycle + fan-out + identity (8 vars)"
 '((%rdi . %rax) (%rsi . %rax) (%rax . %rbx) (%rbx . %rcx) (%rcx . %rax)
   (%r8 . %r9) (%r9 . %r9) ((%stack -8) . %rdi))
 *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)

;;; -----------------------------------------------------------------------
;;; Group 2: Collision Avoidance, Subregister Aliasing, Stack, FPR & Fallback
;;; -----------------------------------------------------------------------
(let ((plan-r10-r11
       (pmov-verify-and-check-min!
        "2.1 live %r10 and %r11 forces selection of %rax scratch"
        '((%r10 . %r11) (%r11 . %r10))
        *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)))
  (assert-true "2.1b scratch selected is neither %r10 nor %r11 nor %r12 nor %rsp"
               (let ((tmp (caar plan-r10-r11)))
                 (and (not (memq tmp '(%r10 %r11 %r12 %rsp)))
                      (eq? tmp '%rax)))))

(pmov-verify-and-check-min!
 "2.2 subregister alias %al/%rax avoids clobbering %rax"
 '((%al . %rbx) (%rbx . %al))
 '(%rax %r10) *lir-pmov-fpr-scratch-pool* #f)

(pmov-verify-and-check-min!
 "2.3 stack-to-stack 3-cycle"
 '(((%stack -8) . (%stack -16))
   ((%stack -16) . (%stack -24))
   ((%stack -24) . (%stack -8)))
 *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)

(let ((plan-fpr
       (pmov-verify-and-check-min!
        "2.4 FPR %xmm* 3-cycle"
        '((%xmm0 . %xmm1) (%xmm1 . %xmm2) (%xmm2 . %xmm0))
        *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)))
  (assert-true "2.4b FPR cycle uses %xmm15 scratch"
               (eq? (caar plan-fpr) '%xmm15)))

(pmov-verify-and-check-min!
 "2.5 mixed GPR + FPR + stack parallel moves"
 '((%rax . %rbx) (%rbx . %rax)
   (%xmm0 . %xmm1) (%xmm1 . %xmm0)
   ((%stack -8) . (%stack -16)) ((%stack -16) . (%stack -8)))
 *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f)

(let* ((res-fb (lir-emit-parallel-moves-with-usage
                '(%r10 %r11) '(%r11 %r10)
                '(%r10 %r11) *lir-pmov-fpr-scratch-pool* '(%stack -32)))
       (insts-fb (car res-fb))
       (used-fb? (cdr res-fb)))
  (assert-true "2.6 fallback stack slot used when all scratch GPRs are live" used-fb?)
  (assert-true "2.6b fallback plan passes symbolic verifier"
               (lir-verify-parallel-move-plan
                '((%r10 . %r11) (%r11 . %r10))
                (lir-parallel-move-plan '((%r10 . %r11) (%r11 . %r10))
                                        '(%r10 %r11) *lir-pmov-fpr-scratch-pool* '(%stack -32))
                '((%stack -32)))))

;; Fail-closed checks: duplicate destination and %rsp destination
(let ((orig-abort (car *compiler-abort-on-error*))
      (orig-suppress (car *compiler-suppress-diagnostics*)))
  (set-car! *compiler-abort-on-error* #f)
  (set-car! *compiler-suppress-diagnostics* #t)
  (assert-false "2.7 duplicate destination rejected"
                (lir-parallel-move-plan '((%rax . %rbx) (%rax . %rcx))
                                        *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f))
  (assert-false "2.8 %rsp destination rejected"
                (lir-parallel-move-plan '((%rsp . %rax))
                                        *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f))
  (set-car! *compiler-abort-on-error* orig-abort)
  (set-car! *compiler-suppress-diagnostics* orig-suppress))

;;; -----------------------------------------------------------------------
;;; Group 3: Exhaustive 4! = 24 Permutations Verification
;;; -----------------------------------------------------------------------
(define (pmov-gen-perms lst)
  (if (null? lst)
      '(())
      (let loop ((xs lst) (acc '()))
        (if (null? xs)
            acc
            (let* ((x (car xs))
                   (rest (filter (lambda (y) (not (eq? y x))) lst))
                   (sub-perms (pmov-gen-perms rest)))
              (loop (cdr xs)
                    (append acc (map (lambda (sp) (cons x sp)) sub-perms))))))))

(let* ((locs '(%rax %rbx %rcx %rdx))
       (all-perms (pmov-gen-perms locs))
       (all-ok?
        (let loop ((ps all-perms) (idx 0))
          (if (null? ps)
              #t
              (let* ((perm (car ps))
                     (pairs (let zip ((ds locs) (ss perm) (acc '()))
                              (if (null? ds)
                                  (reverse acc)
                                  (zip (cdr ds) (cdr ss) (cons (cons (car ds) (car ss)) acc)))))
                     (plan (lir-parallel-move-plan pairs *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f))
                     (min-m (pmov-expected-min-moves pairs)))
                (and (lir-verify-parallel-move-plan pairs plan *lir-pmov-gpr-scratch-pool*)
                     (= (length plan) min-m)
                     (loop (cdr ps) (+ idx 1))))))))
  (assert-equal "3.1 permutation count is 24" 24 (length all-perms))
  (assert-true "3.2 all 24 permutations pass symbolic equivalence and m+c minimality" all-ok?))

;;; -----------------------------------------------------------------------
;;; Group 4: Reference VM End-to-End Execution Checks
;;; -----------------------------------------------------------------------
;; 4.1 3-cycle in GPRs
(let* ((moves (lir-emit-parallel-moves
               '(%rax %rbx %rcx) '(%rbx %rcx %rax)
               *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f))
       (prog (make-pmov-vm-prog
              (append '((%mov %rax 1) (%mov %rbx 20) (%mov %rcx 300))
                      (append moves
                              '((%imul %rax 100)
                                (%add %rax %rbx)
                                (%add %rax %rcx)
                                (%return %rax)))))))
  ;; Expected after rotation (a,b,c) <- (b,c,a): a=20, b=300, c=1 => 20*100 + 300 + 1 = 2301
  (assert-equal "4.1 Reference VM 3-cycle rotation produces 2301" 2301 (eval-lir-program prog)))

;; 4.2 5-cycle in GPRs
(let* ((moves (lir-emit-parallel-moves
               '(%rax %rbx %rcx %rdx %rsi) '(%rbx %rcx %rdx %rsi %rax)
               *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f))
       (prog (make-pmov-vm-prog
              (append '((%mov %rax 1) (%mov %rbx 2) (%mov %rcx 3) (%mov %rdx 4) (%mov %rsi 5))
                      (append moves
                              '((%imul %rax 10000)
                                (%imul %rbx 1000)
                                (%imul %rcx 100)
                                (%imul %rdx 10)
                                (%add %rax %rbx)
                                (%add %rax %rcx)
                                (%add %rax %rdx)
                                (%add %rax %rsi)
                                (%return %rax)))))))
  ;; Expected after rotation: a=2, b=3, c=4, d=5, e=1 => 23451
  (assert-equal "4.2 Reference VM 5-cycle rotation produces 23451" 23451 (eval-lir-program prog)))

;; 4.3 Stack-to-stack swap
(let* ((moves (lir-emit-parallel-moves
               '((%stack -8) (%stack -16)) '((%stack -16) (%stack -8))
               *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f))
       (prog (make-pmov-vm-prog
              (append '((%store %rsp -8 10) (%store %rsp -16 42))
                      (append moves
                              '((%load %rax %rsp -8)
                                (%load %rbx %rsp -16)
                                (%sub %rax %rbx)
                                (%return %rax)))))))
  ;; Expected: (-8)=42, (-16)=10 => 42 - 10 = 32
  (assert-equal "4.3 Reference VM stack-to-stack swap produces 32" 32 (eval-lir-program prog)))

;; 4.4 FPR %xmm0 <-> %xmm1 swap
(let* ((moves (lir-emit-parallel-moves
               '(%xmm0 %xmm1) '(%xmm1 %xmm0)
               *lir-pmov-gpr-scratch-pool* *lir-pmov-fpr-scratch-pool* #f))
       (prog (make-pmov-vm-prog
              (append '((%mov %rax 10) (%sitofp %xmm0 %rax)
                        (%mov %rax 35) (%sitofp %xmm1 %rax))
                      (append moves
                              '((%fsub %xmm0 %xmm1)
                                (%fptosi %rax %xmm0)
                                (%return %rax)))))))
  ;; Expected: xmm0=35, xmm1=10 => 35 - 10 = 25
  (assert-equal "4.4 Reference VM FPR %xmm0<->%xmm1 swap produces 25" 25 (eval-lir-program prog)))

(test-end "General Parallel Move Resolver (Issue #969)")
