;;; =======================================================================
;;; ULisp Compiler: General Parallel Move Resolver (Rideau-Serpette-Leroy 2008)
;;; Conforms to DSN-33 Architecture Specification & Issue #969
;;; =======================================================================
;;; Resolves an arbitrary N-element parallel assignment (dst_i <- src_i)
;;; into a minimal sequential move plan (m + c moves for m non-self moves
;;; and c disjoint cycles) via:
;;;   1. Self-move elimination (dst == src)
;;;   2. Directed dependency graph DAG reverse-topological peeling
;;;   3. Domain-matched, collision-free single-scratch cycle breaking
;;;      (reusing 1 scratch across disjoint cycles, or falling back to a
;;;       caller-supplied stack slot if all scratch registers are live)
;;;
;;; Self-hosting constraints:
;;;   - Fixed-arity definitions only (no variadic define)
;;;   - No internal defines, no lexical set!, no max/min/2-arg make-vector
;;;   - %rsp and %r12 are strictly excluded from scratch pools and targets
;;; =======================================================================

(define *lir-pmov-gpr-scratch-pool*
  '(%r10 %r11 %rax %rdx %rcx %r8 %r9))

(define *lir-pmov-fpr-scratch-pool*
  '(%xmm15 %xmm14 %xmm13 %xmm12))

(define (lir-pmov-unwrap-reg x)
  (cond
    ((and (pair? x) (eq? (car x) '%reg) (pair? (cdr x)))
     (let ((inner (if (pair? (cddr x)) (caddr x) (cadr x))))
       (if (lir-pmov-phys-reg-sym? inner) inner x)))
    ((and (pair? x) (eq? (car x) '%freg) (pair? (cdr x)))
     (let ((inner (cadr x)))
       (if (lir-pmov-phys-reg-sym? inner) inner x)))
    (else x)))

(define (lir-pmov-phys-reg-sym? s)
  (and (symbol? s)
       (case s
         ((%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp
           %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15
           %al %bl %cl %dl %sil %dil %bpl %spl
           %r8b %r9b %r10b %r11b %r12b %r13b %r14b %r15b
           %eax %ebx %ecx %edx %esi %edi %ebp %esp
           %r8d %r9d %r10d %r11d %r12d %r13d %r14d %r15d
           rax rbx rcx rdx rsi rdi rbp rsp
           r8 r9 r10 r11 r12 r13 r14 r15
           al bl cl dl sil dil bpl spl
           r8b r9b r10b r11b r12b r13b r14b r15b
           eax ebx ecx edx esi edi ebp esp
           r8d r9d r10d r11d r12d r13d r14d r15d
           %xmm0 %xmm1 %xmm2 %xmm3 %xmm4 %xmm5 %xmm6 %xmm7
           %xmm8 %xmm9 %xmm10 %xmm11 %xmm12 %xmm13 %xmm14 %xmm15
           xmm0 xmm1 xmm2 xmm3 xmm4 xmm5 xmm6 xmm7
           xmm8 xmm9 xmm10 xmm11 xmm12 xmm13 xmm14 xmm15)
          #t)
         (else #f))))

(define (lir-pmov-canon-exact-reg r)
  (case r
    ((%rax rax) '%rax) ((%rbx rbx) '%rbx) ((%rcx rcx) '%rcx) ((%rdx rdx) '%rdx)
    ((%rsi rsi) '%rsi) ((%rdi rdi) '%rdi) ((%rbp rbp) '%rbp) ((%rsp rsp) '%rsp)
    ((%r8  r8)  '%r8)  ((%r9  r9)  '%r9)  ((%r10 r10) '%r10) ((%r11 r11) '%r11)
    ((%r12 r12) '%r12) ((%r13 r13) '%r13) ((%r14 r14) '%r14) ((%r15 r15) '%r15)
    ((%eax eax) '%eax) ((%ebx ebx) '%ebx) ((%ecx ecx) '%ecx) ((%edx edx) '%edx)
    ((%esi esi) '%esi) ((%edi edi) '%edi) ((%ebp ebp) '%ebp) ((%esp esp) '%esp)
    ((%r8d r8d) '%r8d) ((%r9d r9d) '%r9d) ((%r10d r10d) '%r10d) ((%r11d r11d) '%r11d)
    ((%r12d r12d) '%r12d) ((%r13d r13d) '%r13d) ((%r14d r14d) '%r14d) ((%r15d r15d) '%r15d)
    ((%al  al)  '%al)  ((%bl  bl)  '%bl)  ((%cl  cl)  '%cl)  ((%dl  dl)  '%dl)
    ((%sil sil) '%sil) ((%dil dil) '%dil) ((%bpl bpl) '%bpl) ((%spl spl) '%spl)
    ((%r8b r8b) '%r8b) ((%r9b r9b) '%r9b) ((%r10b r10b) '%r10b) ((%r11b r11b) '%r11b)
    ((%r12b r12b) '%r12b) ((%r13b r13b) '%r13b) ((%r14b r14b) '%r14b) ((%r15b r15b) '%r15b)
    ((%xmm0 xmm0) '%xmm0) ((%xmm1 xmm1) '%xmm1) ((%xmm2 xmm2) '%xmm2) ((%xmm3 xmm3) '%xmm3)
    ((%xmm4 xmm4) '%xmm4) ((%xmm5 xmm5) '%xmm5) ((%xmm6 xmm6) '%xmm6) ((%xmm7 xmm7) '%xmm7)
    ((%xmm8 xmm8) '%xmm8) ((%xmm9 xmm9) '%xmm9) ((%xmm10 xmm10) '%xmm10) ((%xmm11 xmm11) '%xmm11)
    ((%xmm12 xmm12) '%xmm12) ((%xmm13 xmm13) '%xmm13) ((%xmm14 xmm14) '%xmm14) ((%xmm15 xmm15) '%xmm15)
    (else r)))

(define (lir-pmov-canon-gpr-family r)
  (let ((u (lir-pmov-unwrap-reg r)))
    (case u
      ((%rax rax %eax eax %al al) '%rax)
      ((%rbx rbx %ebx ebx %bl bl) '%rbx)
      ((%rcx rcx %ecx ecx %cl cl) '%rcx)
      ((%rdx rdx %edx edx %dl dl) '%rdx)
      ((%rsi rsi %esi esi %sil sil) '%rsi)
      ((%rdi rdi %edi edi %dil dil) '%rdi)
      ((%rbp rbp %ebp ebp %bpl bpl) '%rbp)
      ((%rsp rsp %esp esp %spl spl) '%rsp)
      ((%r8  r8  %r8d r8d %r8b r8b) '%r8)
      ((%r9  r9  %r9d r9d %r9b r9b) '%r9)
      ((%r10 r10 %r10d r10d %r10b r10b) '%r10)
      ((%r11 r11 %r11d r11d %r11b r11b) '%r11)
      ((%r12 r12 %r12d r12d %r12b r12b) '%r12)
      ((%r13 r13 %r13d r13d %r13b r13b) '%r13)
      ((%r14 r14 %r14d r14d %r14b r14b) '%r14)
      ((%r15 r15 %r15d r15d %r15b r15b) '%r15)
      (else u))))

(define (lir-pmov-gpr-sym? r)
  (let ((fam (lir-pmov-canon-gpr-family r)))
    (and (symbol? fam)
         (memq fam '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp
                     %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15)))))

(define (lir-pmov-loc-equal? a b)
  (let ((ua (lir-pmov-unwrap-reg a))
        (ub (lir-pmov-unwrap-reg b)))
    (cond
      ((and (symbol? ua) (symbol? ub))
       (eq? (lir-pmov-canon-exact-reg ua) (lir-pmov-canon-exact-reg ub)))
      ((and (pair? ua) (pair? ub))
       (and (eq? (car ua) (car ub))
            (cond
              ((eq? (car ua) '%stack)
               (and (pair? (cdr ua)) (pair? (cdr ub))
                    (equal? (cadr ua) (cadr ub))))
              ((eq? (car ua) '%mem)
               (and (pair? (cdr ua)) (pair? (cdr ub))
                    (pair? (cddr ua)) (pair? (cddr ub))
                    (lir-pmov-loc-equal? (cadr ua) (cadr ub))
                    (lir-pmov-loc-equal? (caddr ua) (caddr ub))))
              (else (equal? ua ub)))))
      (else (equal? ua ub)))))

(define (lir-pmov-reg-aliases? a b)
  (or (lir-pmov-loc-equal? a b)
      (and (lir-pmov-gpr-sym? a)
           (lir-pmov-gpr-sym? b)
           (eq? (lir-pmov-canon-gpr-family a)
                (lir-pmov-canon-gpr-family b)))))

(define (lir-pmov-float-loc? x)
  (cond
    ((symbol? x)
     (let ((c (lir-pmov-canon-exact-reg x)))
       (if (memq c '(%xmm0 %xmm1 %xmm2 %xmm3 %xmm4 %xmm5 %xmm6 %xmm7
                     %xmm8 %xmm9 %xmm10 %xmm11 %xmm12 %xmm13 %xmm14 %xmm15))
           #t #f)))
    ((and (pair? x) (eq? (car x) '%freg)) #t)
    ((and (pair? x) (eq? (car x) '%reg) (pair? (cdr x)))
     (cond
       ((and (pair? (cddr x)) (memq (cadr x) '(f32 f64))) #t)
       ((lir-pmov-float-loc? (cadr x)) #t)
       (else #f)))
    (else #f)))

(define (lir-pmov-stack-loc? x)
  (and (pair? x) (eq? (car x) '%stack) (pair? (cdr x)) (integer? (cadr x))))

(define (lir-pmov-mem-loc? x)
  (and (pair? x) (eq? (car x) '%mem) (pair? (cdr x)) (pair? (cddr x))))

(define (lir-pmov-rsp-loc? x)
  (let ((fam (lir-pmov-canon-gpr-family x)))
    (if (memq fam '(%rsp sp)) #t #f)))

(define (lir-pmov-loc-reads? expr loc)
  (cond
    ((lir-pmov-reg-aliases? expr loc) #t)
    ((lir-pmov-mem-loc? expr)
     (or (lir-pmov-loc-reads? (cadr expr) loc)
         (lir-pmov-loc-reads? (caddr expr) loc)))
    ((and (pair? expr) (eq? (car expr) '%sib) (= (length expr) 4))
     (lir-pmov-reg-aliases? (cadr expr) loc))
    ((and (pair? expr) (eq? (car expr) '%disp) (= (length expr) 3))
     (or (lir-pmov-loc-reads? (cadr expr) loc)
         (lir-pmov-loc-reads? (caddr expr) loc)))
    (else #f)))

(define (lir-pmov-dst-reads-addr? dst loc)
  (cond
    ((lir-pmov-mem-loc? dst)
     (or (lir-pmov-loc-reads? (cadr dst) loc)
         (lir-pmov-loc-reads? (caddr dst) loc)))
    ((and (pair? dst) (eq? (car dst) '%disp) (= (length dst) 3))
     (or (lir-pmov-loc-reads? (cadr dst) loc)
         (lir-pmov-loc-reads? (caddr dst) loc)))
    (else #f)))

(define (lir-pmov-loc-in-moves? cand moves)
  (let loop ((ms moves))
    (if (null? ms)
        #f
        (let ((d (caar ms))
              (s (cdar ms)))
          (if (or (lir-pmov-reg-aliases? d cand)
                  (lir-pmov-loc-reads? s cand)
                  (lir-pmov-dst-reads-addr? d cand))
              #t
              (loop (cdr ms)))))))

(define (lir-pmov-select-scratch candidates moves fallback-slot)
  (let loop ((cs candidates))
    (cond
      ((null? cs)
       (if (and fallback-slot
                (not (lir-pmov-rsp-loc? fallback-slot))
                (not (lir-pmov-loc-in-moves? fallback-slot moves)))
           fallback-slot
           (error "lir-pmov-select-scratch: no collision-free scratch location available" moves)))
      (else
       (let* ((cand (car cs))
              (fam (lir-pmov-canon-gpr-family cand)))
         (if (and (not (lir-pmov-rsp-loc? cand))
                  (not (eq? fam '%r12))
                  (not (lir-pmov-loc-in-moves? cand moves)))
             cand
             (loop (cdr cs))))))))

(define (lir-pmov-subst-expr expr old-loc new-loc)
  (cond
    ((lir-pmov-loc-equal? expr old-loc) new-loc)
    ((lir-pmov-mem-loc? expr)
     (list '%mem
           (lir-pmov-subst-expr (cadr expr) old-loc new-loc)
           (lir-pmov-subst-expr (caddr expr) old-loc new-loc)))
    ((and (pair? expr) (eq? (car expr) '%sib) (= (length expr) 4))
     (list '%sib
           (lir-pmov-subst-expr (cadr expr) old-loc new-loc)
           (caddr expr)
           (cadddr expr)))
    ((and (pair? expr) (eq? (car expr) '%disp) (= (length expr) 3))
     (list '%disp
           (lir-pmov-subst-expr (cadr expr) old-loc new-loc)
           (lir-pmov-subst-expr (caddr expr) old-loc new-loc)))
    (else expr)))

(define (lir-pmov-subst-dst-addr dst old-loc new-loc)
  (cond
    ((lir-pmov-mem-loc? dst)
     (list '%mem
           (lir-pmov-subst-expr (cadr dst) old-loc new-loc)
           (lir-pmov-subst-expr (caddr dst) old-loc new-loc)))
    ((and (pair? dst) (eq? (car dst) '%disp) (= (length dst) 3))
     (list '%disp
           (lir-pmov-subst-expr (cadr dst) old-loc new-loc)
           (lir-pmov-subst-expr (caddr dst) old-loc new-loc)))
    (else dst)))

(define (lir-pmov-validate-pairs pairs)
  (let loop ((ps pairs) (seen-dsts '()))
    (if (null? ps)
        #t
        (let ((d (caar ps)))
          (cond
            ((lir-pmov-rsp-loc? d)
             (error "lir-parallel-move-plan: destination cannot be %rsp" (car ps))
             #f)
            ((let dup-chk ((ds seen-dsts))
               (and (pair? ds)
                    (or (lir-pmov-reg-aliases? d (car ds))
                        (dup-chk (cdr ds)))))
             (error "lir-parallel-move-plan: duplicate destination in parallel move" d)
             #f)
            (else
             (loop (cdr ps) (cons d seen-dsts))))))))

(define (lir-pmov-find-ready rem)
  (let loop ((ms rem))
    (if (null? ms)
        #f
        (let* ((cand (car ms))
               (d (car cand))
               (blocked?
                (let chk ((all rem))
                  (and (pair? all)
                       (or (and (not (eq? (car all) cand))
                                (or (lir-pmov-loc-reads? (cdar all) d)
                                    (lir-pmov-dst-reads-addr? (caar all) d)))
                           (chk (cdr all)))))))
          (if blocked?
              (loop (cdr ms))
              cand)))))

(define (lir-pmov-remove-pair target lst)
  (let loop ((xs lst) (acc '()))
    (cond
      ((null? xs) (reverse acc))
      ((eq? (car xs) target) (append (reverse acc) (cdr xs)))
      (else (loop (cdr xs) (cons (car xs) acc))))))

(define (lir-parallel-move-plan pairs gpr-scratches fpr-scratches fallback-slot)
  (if (not (lir-pmov-validate-pairs pairs))
      #f
      (let ((initial
             (let drop-self ((ps pairs) (acc '()))
               (cond
                 ((null? ps) (reverse acc))
                 ((lir-pmov-loc-equal? (caar ps) (cdar ps))
                  (drop-self (cdr ps) acc))
                 (else
                  (drop-self (cdr ps) (cons (cons (caar ps) (cdar ps)) acc)))))))
        (let loop ((rem initial) (plan-rev '()))
          (if (null? rem)
              (reverse plan-rev)
              (let ((ready (lir-pmov-find-ready rem)))
                (if ready
                    (loop (lir-pmov-remove-pair ready rem)
                          (cons ready plan-rev))
                    ;; Pure cycle(s) remain: break head cycle with 1 collision-free scratch
                    (let* ((head (car rem))
                           (d0 (car head))
                           (pool (if (lir-pmov-float-loc? d0) fpr-scratches gpr-scratches))
                           (tmp (lir-pmov-select-scratch pool rem fallback-slot))
                           (updated-rem
                            (map (lambda (m)
                                   (cons (if (lir-pmov-loc-equal? (car m) d0)
                                             (car m)
                                             (lir-pmov-subst-dst-addr (car m) d0 tmp))
                                         (lir-pmov-subst-expr (cdr m) d0 tmp)))
                                 rem)))
                      (loop updated-rem (cons (cons tmp d0) plan-rev))))))))))

(define (lir-emit-single-move dst src mem-scratch)
  (cond
    ((lir-pmov-loc-equal? dst src) '())
    ((and (lir-pmov-float-loc? dst) (lir-pmov-float-loc? src))
     (list (list '%fmov dst src)))
    ((and (lir-pmov-float-loc? dst) (lir-pmov-stack-loc? src))
     (list (list '%load-typed 'f64 dst '%rsp (cadr src))))
    ((and (lir-pmov-stack-loc? dst) (lir-pmov-float-loc? src))
     (list (list '%store-typed 'f64 '%rsp (cadr dst) src)))
    ((and (lir-pmov-stack-loc? dst) (lir-pmov-stack-loc? src))
     (list (list '%load mem-scratch '%rsp (cadr src))
           (list '%store '%rsp (cadr dst) mem-scratch)))
    ((lir-pmov-stack-loc? dst)
     (list (list '%store '%rsp (cadr dst) src)))
    ((lir-pmov-stack-loc? src)
     (list (list '%load dst '%rsp (cadr src))))
    (else
     (list (list '%mov dst src)))))

(define (lir-emit-parallel-moves-with-usage dsts srcs gpr-scratches fpr-scratches fallback-slot)
  (if (not (= (length dsts) (length srcs)))
      (error "lir-emit-parallel-moves: dsts and srcs arity mismatch" (list dsts srcs))
      (let* ((pairs (let zip ((ds dsts) (ss srcs) (acc '()))
                      (if (null? ds)
                          (reverse acc)
                          (zip (cdr ds) (cdr ss) (cons (cons (car ds) (car ss)) acc)))))
             (plan (lir-parallel-move-plan pairs gpr-scratches fpr-scratches fallback-slot))
             (used-fb-box (cons #f '())))
        (let loop ((ps plan) (acc-rev '()))
          (if (null? ps)
              (cons (reverse acc-rev) (car used-fb-box))
              (let* ((step (car ps))
                     (d (car step))
                     (s (cdr step)))
                (if (and fallback-slot
                         (or (lir-pmov-loc-equal? d fallback-slot)
                             (lir-pmov-loc-equal? s fallback-slot)))
                    (set-car! used-fb-box #t))
                (let* ((mem-tmp (if (and (lir-pmov-stack-loc? d) (lir-pmov-stack-loc? s))
                                    (lir-pmov-select-scratch gpr-scratches ps #f)
                                    #f))
                       (insts (lir-emit-single-move d s mem-tmp)))
                  (loop (cdr ps) (append (reverse insts) acc-rev)))))))))

(define (lir-emit-parallel-moves dsts srcs gpr-scratches fpr-scratches fallback-slot)
  (car (lir-emit-parallel-moves-with-usage dsts srcs gpr-scratches fpr-scratches fallback-slot)))
