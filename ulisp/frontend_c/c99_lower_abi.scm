;;; =======================================================================
;;; ULisp C99 Frontend: System V AMD64 ABI, Bit-Field & <stdarg.h> Lowering
;;; Extracted from lower_to_lir.scm (Issue #967).
;;; Covers Bit-Fields, SysV Aggregate Calls/Returns, <stdarg.h>, and Function Frames.
;;; Zero local `set!` (ULisp AOT safe).
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 3. Field Resolution & Bit-Field Read/Write Helpers
;;; -----------------------------------------------------------------------

(define (%c99-lower-member-field-layout ctx member-inner)
  (let* ((base (cadr member-inner))
         (fsym (caddr member-inner))
         (deref? (cadddr member-inner))
         (bty (c-typed-type base))
         (agg-ty (if deref? (c-ptr-target bty) bty)))
    (c-struct-layout-find-field (lower-ctx-layout-env ctx) agg-ty fsym)))

(define (%c99-lower-load-bitfield! ctx base-reg base-disp fl)
  (let* ((su-off (c-field-layout-storage-unit-offset fl))
         (su-ty (c-field-layout-storage-unit-type fl))
         (bit-off (c-field-layout-bit-offset fl))
         (w (c-field-layout-bit-width fl))
         (fty (c-field-layout-ctype fl))
         (unsigned? (or (c-unsigned-type? fty) (eq? fty 'bool))))
    (%c99-lower-load-from-mem! ctx '%rax base-reg (+ base-disp su-off) su-ty)
    (cond
      ((<= w 0)
       (%c99-lower-emit! ctx '(%mov %rax 0)))
      (unsigned?
       (if (> bit-off 0)
           (%c99-lower-emit! ctx (list '%shr '%rax bit-off)))
       (if (< w 64)
           (begin
             (if (<= w 31)
                 (%c99-lower-emit! ctx (list '%mov '%rcx (- (arithmetic-shift 1 w) 1)))
                 (%c99-lower-emit-u64-const! ctx '%rcx (- (arithmetic-shift 1 w) 1)))
             (%c99-lower-emit! ctx '(%bit-and %rax %rcx)))))
      (else
       (let ((left (- 64 (+ bit-off w)))
             (right (- 64 w)))
         (if (> left 0) (%c99-lower-emit! ctx (list '%shl '%rax left)))
         (if (> right 0) (%c99-lower-emit! ctx (list '%sar '%rax right))))))))

;; Expects new value in %rax and enclosing struct pointer in [%rsp + base-ptr-si].
;; Leaves normalized stored value in %rax.
(define (%c99-lower-store-bitfield-rax! ctx base-ptr-si fl)
  (let* ((su-off (c-field-layout-storage-unit-offset fl))
         (su-ty (c-field-layout-storage-unit-type fl))
         (bit-off (c-field-layout-bit-offset fl))
         (w (c-field-layout-bit-width fl))
         (fty (c-field-layout-ctype fl))
         (unsigned? (or (c-unsigned-type? fty) (eq? fty 'bool)))
         (ret-si (%c99-lower-alloc-slot! ctx))
         (ins-si (%c99-lower-alloc-slot! ctx)))
    (if (eq? fty 'bool)
        (%c99-lower-emit-cast! ctx 'bool))
    ;; Compute unsigned w-bit mask in %rcx
    (cond
      ((>= w 64)
       (%c99-lower-emit! ctx '(%mov %rcx -1)))
      ((<= w 31)
       (%c99-lower-emit! ctx (list '%mov '%rcx (- (arithmetic-shift 1 w) 1))))
      (else
       (%c99-lower-emit-u64-const! ctx '%rcx (- (arithmetic-shift 1 w) 1))))
    (%c99-lower-emit! ctx '(%bit-and %rax %rcx))
    ;; Save shifted insertion value
    (%c99-lower-emit! ctx '(%mov %r8 %rax))
    (if (> bit-off 0)
        (%c99-lower-emit! ctx (list '%shl '%r8 bit-off)))
    (%c99-lower-emit! ctx (list '%store '%rsp ins-si '%r8))
    ;; Sign-extend / preserve normalized return value in ret-si
    (if (and (not unsigned?) (< w 64))
        (let ((shift-amt (- 64 w)))
          (%c99-lower-emit! ctx (list '%shl '%rax shift-amt))
          (%c99-lower-emit! ctx (list '%sar '%rax shift-amt))))
    (%c99-lower-emit! ctx (list '%store '%rsp ret-si '%rax))
    ;; Read-Modify-Write storage unit
    (%c99-lower-emit! ctx (list '%load '%rdx '%rsp base-ptr-si))
    (%c99-lower-load-from-mem! ctx '%rax '%rdx su-off su-ty)
    (if (< w 64)
        (begin
          (if (<= w 31)
              (%c99-lower-emit! ctx (list '%mov '%rcx (- (arithmetic-shift 1 w) 1)))
              (%c99-lower-emit-u64-const! ctx '%rcx (- (arithmetic-shift 1 w) 1)))
          (if (> bit-off 0)
              (%c99-lower-emit! ctx (list '%shl '%rcx bit-off)))
          (%c99-lower-emit! ctx '(%bit-xor %rcx -1))
          (%c99-lower-emit! ctx '(%bit-and %rax %rcx))
          (%c99-lower-emit! ctx (list '%load '%r8 '%rsp ins-si))
          (%c99-lower-emit! ctx '(%bit-or %rax %r8)))
        (%c99-lower-emit! ctx (list '%load '%rax '%rsp ins-si)))
    (%c99-lower-store-to-mem! ctx '%rdx su-off '%rax su-ty)
    (%c99-lower-emit! ctx (list '%load '%rax '%rsp ret-si))))

;;; -----------------------------------------------------------------------
;;; 6. Full SysV AMD64 Call & Aggregate Return/Parameter Passing
;;; -----------------------------------------------------------------------

(define (%c99-map2 f xs ys)
  (let loop ((a xs) (b ys) (acc '()))
    (if (or (null? a) (null? b))
        (reverse acc)
        (loop (cdr a) (cdr b) (cons (f (car a) (car b)) acc)))))

(define (%c99-for-each2 f xs ys)
  (let loop ((a xs) (b ys))
    (if (and (pair? a) (pair? b))
        (begin
          (f (car a) (car b))
          (loop (cdr a) (cdr b))))))

(define (%c99-lower-store-ret-pieces! ctx pieces dst-ptr-si)
  ;; Snapshot return registers immediately before touching %rdx/%rax
  (let ((saved-pieces
         (map (lambda (pc)
                (let* ((kind (car pc))
                       (reg (cadr pc))
                       (off (caddr pc))
                       (csz (cadddr pc))
                       (tmp-si (%c99-lower-alloc-slot! ctx)))
                  (if (eq? kind 'gpr)
                      (%c99-lower-emit! ctx (list '%store '%rsp tmp-si reg))
                      (%c99-lower-emit! ctx (list '%store-typed (if (<= csz 4) 'f32 'f64) '%rsp tmp-si reg)))
                  (list kind tmp-si off csz)))
              pieces)))
    (for-each
     (lambda (sp)
       (let ((kind (list-ref sp 0))
             (tmp-si (list-ref sp 1))
             (off (list-ref sp 2))
             (csz (list-ref sp 3)))
         (%c99-lower-emit! ctx (list '%load '%rdx '%rsp dst-ptr-si))
         (if (eq? kind 'gpr)
             (begin
               (%c99-lower-emit! ctx (list '%load '%rcx '%rsp tmp-si))
               (%c99-lower-store-chunk-gpr! ctx '%rdx off '%rcx csz))
             (begin
               (%c99-lower-emit! ctx (list '%load-typed (if (<= csz 4) 'f32 'f64) '%xmm0 '%rsp tmp-si))
               (%c99-lower-emit! ctx (list '%store-typed (if (<= csz 4) 'f32 'f64) '%rdx off '%xmm0))))))
     saved-pieces)))

(define (%c99-extract-direct-fn-sym node)
  (let loop ((n node))
    (let ((in (c-typed-inner n)))
      (cond
        ((eq? (car in) 'c-fn-ref) (cadr in))
        ((eq? (car in) 'c-implicit-cast) (loop (caddr in)))
        ((and (eq? (car in) 'c-unop) (memq (cadr in) '(addr deref)))
         (loop (caddr in)))
        (else #f)))))

(define (%c99-compute-suffix-and bs)
  ;; Given (b0 b1 ...), returns (r0 r1 ...) where r_i = (and b_{i+1} ... b_{n-1}).
  (if (null? bs)
      '()
      (let loop ((xs (reverse bs)) (acc-and #t) (out '()))
        (if (null? xs)
            out
            (loop (cdr xs) (and acc-and (car xs)) (cons acc-and out))))))

(define (%c99-call-needs-al? fty arg-nodes)
  (or (not (c-function-type? fty))
      (c-fn-variadic? fty)
      (and (null? (c-fn-params fty)) (pair? arg-nodes))))

(define (%c99-lower-call! ctx inner call-ret-ty . maybe-dst-ptr-si)
  (let* ((fn-node (cadr inner))
         (arg-nodes (cddr inner))
         (direct-fn-sym (%c99-extract-direct-fn-sym fn-node))
         (raw-fty (c-typed-type fn-node))
         (fty (if (and (c-pointer-type? raw-fty) (c-function-type? (c-ptr-target raw-fty)))
                  (c-ptr-target raw-fty)
                  raw-fty))
         (proto-ret-ty (if (c-function-type? fty) (c-fn-ret fty) call-ret-ty))
         (decl-params (if (c-function-type? fty) (c-fn-params fty) '()))
         (arg-tys (map c-typed-type arg-nodes))
         (all-param-tys (let loop ((ps decl-params) (as arg-tys) (acc '()))
                          (cond
                            ((pair? ps) (loop (cdr ps) (if (pair? as) (cdr as) '()) (cons (car ps) acc)))
                            ((pair? as) (loop '() (cdr as) (cons (car as) acc)))
                            (else (reverse acc)))))
         (abi (c99-plan-sysv-abi (lower-ctx-layout-env ctx) proto-ret-ty all-param-tys))
         (ret-plan (car abi))
         (param-plans (cadr abi))
         (stack-arg-bytes (caddr abi))
         (saved-si (lower-ctx-next-si ctx))
         (saved-gpr (lower-ctx-gpr-temps ctx))
         (saved-xmm (lower-ctx-xmm-temps ctx))
         (xmm-used (let count-x ((ps param-plans) (k 0))
                     (if (null? ps)
                         k
                         (let ((p (car ps)))
                           (if (eq? (car p) 'regs)
                               (let count-p ((pcs (cadr p)) (kk k))
                                 (if (null? pcs)
                                     (count-x (cdr ps) kk)
                                     (count-p (cdr pcs)
                                              (if (eq? (caar pcs) 'sse) (+ kk 1) kk))))
                               (count-x (cdr ps) k))))))
         (all-scalar-reg-args?
          (and (= stack-arg-bytes 0)
               (not (%c99-lower-aggregate-like? call-ret-ty))
               (not (%c99-lower-aggregate-like? proto-ret-ty))
               (not (eq? (car ret-plan) 'sret))
               (= (length param-plans) (length arg-nodes))
               (= (length all-param-tys) (length arg-nodes))
               (let loop ((ps param-plans) (ts all-param-tys))
                 (if (null? ps)
                     #t
                     (let ((plan (car ps))
                           (pty (car ts)))
                       (and (not (%c99-lower-aggregate-like? pty))
                            (eq? (car plan) 'regs)
                            (pair? (cadr plan))
                            (null? (cdr (cadr plan)))
                            (memq (list-ref (caadr plan) 3) '(1 2 4 8))
                            (loop (cdr ps) (cdr ts)))))))))
    (if all-scalar-reg-args?
        (let* ((arg-preserves (map (lambda (a) (%c99-expr-preserves-temp-regs? ctx a)) arg-nodes))
               (suffix-preserves (%c99-compute-suffix-and arg-preserves))
               (all-args-preserve? (let allp ((bs arg-preserves))
                                     (or (null? bs) (and (car bs) (allp (cdr bs))))))
               (gpr-arg-cnt (let cg ((ps param-plans) (k 0))
                              (if (null? ps)
                                  k
                                  (cg (cdr ps)
                                      (if (eq? (caar (cadar ps)) 'gpr) (+ k 1) k)))))
               (fn-ptr-loc (if direct-fn-sym
                               #f
                               (if (and all-args-preserve?
                                        (<= gpr-arg-cnt 2)
                                        (pair? (lower-ctx-gpr-temps ctx)))
                                   (let ((freg (%c99-lower-alloc-gpr-temp! ctx)))
                                     (%c99-lower-expr! ctx fn-node)
                                     (%c99-lower-emit! ctx (list '%mov freg '%rax))
                                     (cons 'reg freg))
                                   (let ((psi (%c99-lower-alloc-slot! ctx)))
                                     (%c99-lower-expr! ctx fn-node)
                                     (%c99-lower-emit! ctx (list '%store '%rsp psi '%rax))
                                     (cons 'slot psi)))))
               (arg-records
                (let loop ((as arg-nodes) (ts all-param-tys) (ps param-plans) (sp suffix-preserves) (acc '()))
                  (if (null? as)
                      (reverse acc)
                      (let* ((arg (car as))
                             (pty (car ts))
                             (pc (car (cadar ps)))
                             (kind (list-ref pc 0))
                             (abi-reg (list-ref pc 1))
                             (csz (list-ref pc 3))
                             (preserves-later? (car sp))
                             (last? (null? (cdr as)))
                             (flt? (c-float-type? pty))
                             (raw-imm (and (not flt?) (eq? kind 'gpr) (%c99-lower-extract-imm32 arg)))
                             (norm-imm (and raw-imm
                                            (let ((nv (%c99-normalize-int-val (if (c-enum-type? pty) 'i32 pty) raw-imm)))
                                              (and (>= nv -2147483648) (<= nv 2147483647) nv))))
                             (rec
                              (cond
                                (norm-imm
                                 (list 'imm abi-reg norm-imm))
                                ((and last? flt? (eq? kind 'sse))
                                 (%c99-lower-expr! ctx arg)
                                 (list 'reg-move abi-reg '%xmm0 'sse))
                                ((and last? (not flt?) (eq? kind 'gpr))
                                 (%c99-lower-expr! ctx arg)
                                 (%c99-lower-emit-cast-reg! ctx pty '%rax)
                                 (list 'reg-move abi-reg '%rax 'gpr))
                                ((and preserves-later? flt? (eq? kind 'sse) (pair? (lower-ctx-xmm-temps ctx)))
                                 (let ((tx (%c99-lower-alloc-xmm-temp! ctx)))
                                   (%c99-lower-expr! ctx arg)
                                   (%c99-lower-emit! ctx (list '%fmov tx '%xmm0))
                                   (list 'reg-move abi-reg tx 'sse)))
                                ((and preserves-later? (not flt?) (eq? kind 'gpr) (pair? (lower-ctx-gpr-temps ctx)))
                                 (let ((tg (%c99-lower-alloc-gpr-temp! ctx)))
                                   (if (%c99-lower-direct-scalar-to-reg! ctx arg tg '%rdx #f)
                                       (begin
                                         (%c99-lower-direct-scalar-to-reg! ctx arg tg '%rdx #t)
                                         (%c99-lower-emit-cast-reg! ctx pty tg))
                                       (begin
                                         (%c99-lower-expr! ctx arg)
                                         (%c99-lower-emit-cast-reg! ctx pty '%rax)
                                         (%c99-lower-emit! ctx (list '%mov tg '%rax))))
                                   (list 'reg-move abi-reg tg 'gpr)))
                                (else
                                 (let* ((sz (max 8 (%c99-lower-type-size ctx pty)))
                                        (al (max 8 (%c99-lower-type-align ctx pty)))
                                        (slot-si (%c99-lower-alloc-bytes! ctx sz al)))
                                   (if flt?
                                       (begin
                                         (%c99-lower-expr! ctx arg)
                                         (%c99-lower-emit! ctx (list '%store-typed pty '%rsp slot-si '%xmm0)))
                                       (begin
                                         (%c99-lower-expr! ctx arg)
                                         (%c99-lower-emit-cast! ctx pty)
                                         (%c99-lower-emit! ctx (list '%store '%rsp slot-si '%rax))))
                                   (list 'slot abi-reg slot-si flt? csz))))))
                        (loop (cdr as) (cdr ts) (cdr ps) (cdr sp) (cons rec acc))))))
               (min-after-args (lower-ctx-next-si ctx))
               (needed (+ (- 0 min-after-args) stack-arg-bytes))
               (shift (align-frame-shift needed))
               (min-touch (- 0 shift))
               (gpr-pairs (let gp ((rs arg-records) (acc '()))
                            (if (null? rs)
                                (reverse acc)
                                (let ((r (car rs)))
                                  (if (and (eq? (car r) 'reg-move) (eq? (list-ref r 3) 'gpr))
                                      (gp (cdr rs) (cons (cons (list-ref r 1) (list-ref r 2)) acc))
                                      (gp (cdr rs) acc))))))
               (sse-pairs (let sp ((rs arg-records) (acc '()))
                            (if (null? rs)
                                (reverse acc)
                                (let ((r (car rs)))
                                  (if (and (eq? (car r) 'reg-move) (eq? (list-ref r 3) 'sse))
                                      (sp (cdr rs) (cons (cons (list-ref r 1) (list-ref r 2)) acc))
                                      (sp (cdr rs) acc)))))))
          (if (< min-touch (lower-ctx-min-si ctx))
              (lower-ctx-min-si-set! ctx min-touch))
          (if (and fn-ptr-loc (eq? (car fn-ptr-loc) 'reg))
              (%c99-lower-emit! ctx (list '%mov '%r11 (cdr fn-ptr-loc))))
          (%c99-lower-emit-parallel-moves! ctx '%mov '%r10 gpr-pairs)
          (%c99-lower-emit-parallel-moves! ctx '%fmov '%xmm10 sse-pairs)
          (for-each
           (lambda (r)
             (if (eq? (car r) 'slot)
                 (let ((abi-reg (list-ref r 1))
                       (slot-si (list-ref r 2))
                       (flt?    (list-ref r 3))
                       (csz     (list-ref r 4)))
                   (if flt?
                       (%c99-lower-emit! ctx (list '%load-typed (if (<= csz 4) 'f32 'f64) abi-reg '%rsp slot-si))
                       (%c99-lower-load-chunk-gpr! ctx abi-reg '%rsp slot-si csz)))))
           arg-records)
          (for-each
           (lambda (r)
             (if (eq? (car r) 'imm)
                 (%c99-lower-emit! ctx (list '%mov (cadr r) (caddr r)))))
           arg-records)
          (if (and direct-fn-sym (lower-ctx-sanitize-bounds? ctx))
              (%c99-san-check-call! ctx direct-fn-sym arg-nodes
                (or (and (pair? maybe-dst-ptr-si) (pair? (cdr maybe-dst-ptr-si)) (cadr maybe-dst-ptr-si))
                    (c-typed-span fn-node)
                    (and (pair? arg-nodes) (c-typed-span (car arg-nodes))))))
          (if direct-fn-sym
              (let* ((resolved-fn-sym (%c99-lower-resolve-runtime-fn! ctx direct-fn-sym))
                     (internal? (or (memq resolved-fn-sym (lower-ctx-internal-fns ctx))
                                    (c99-builtin-weak-fn-sym? resolved-fn-sym)))
                     (needs-al? (%c99-call-needs-al? fty arg-nodes)))
                (if internal?
                    (begin
                      (if needs-al?
                          (%c99-lower-emit! ctx (list '%mov '%rax (min 8 xmm-used))))
                      (%c99-lower-emit! ctx (list '%direct-call resolved-fn-sym shift)))
                    (if needs-al?
                        (%c99-lower-emit! ctx (list '%c-call (symbol->string resolved-fn-sym) shift (min 8 xmm-used)))
                        (%c99-lower-emit! ctx (list '%c-call (symbol->string resolved-fn-sym) shift)))))
              (begin
                (if (eq? (car fn-ptr-loc) 'slot)
                    (%c99-lower-emit! ctx (list '%load '%r11 '%rsp (cdr fn-ptr-loc))))
                (%c99-lower-emit! ctx (list '%call-indirect '%r11 shift (min 8 xmm-used)))))
          (if (and (not (eq? call-ret-ty 'void)) (not (c-float-type? call-ret-ty)))
              (%c99-lower-emit-cast! ctx call-ret-ty))
          (lower-ctx-next-si-set! ctx saved-si)
          (lower-ctx-gpr-temps-set! ctx saved-gpr)
          (lower-ctx-xmm-temps-set! ctx saved-xmm))
        ;; General call fallback (stack args, >16B sret, or aggregate params)
        (let* (;; Evaluate indirect function pointer expression BEFORE arguments
               (fn-ptr-si (if direct-fn-sym
                              #f
                              (let ((psi (%c99-lower-alloc-slot! ctx)))
                                (%c99-lower-expr! ctx fn-node)
                                (%c99-lower-emit! ctx (list '%store '%rsp psi '%rax))
                                psi)))
               ;; If returning via sret without destination buffer supplied, allocate caller scratch slot
               (sret-ptr-si (if (eq? (car ret-plan) 'sret)
                                (if (and (pair? maybe-dst-ptr-si) (car maybe-dst-ptr-si))
                                    (car maybe-dst-ptr-si)
                                    (let* ((buf-si (%c99-lower-alloc-bytes! ctx (cadr ret-plan) (caddr ret-plan)))
                                           (p-si (%c99-lower-alloc-slot! ctx)))
                                      (%c99-lower-emit! ctx '(%mov %rax %rsp))
                                      (%c99-lower-emit! ctx (list '%add '%rax buf-si))
                                      (%c99-lower-emit! ctx (list '%store '%rsp p-si '%rax))
                                      p-si))
                                (and (pair? maybe-dst-ptr-si) (car maybe-dst-ptr-si))))
               ;; Evaluate each argument left-to-right into temp stack buffers
               (arg-slots
                (%c99-map2
                 (lambda (arg pty)
                   (let* ((sz (max 8 (%c99-lower-type-size ctx pty)))
                          (al (max 8 (%c99-lower-type-align ctx pty)))
                          (slot-si (%c99-lower-alloc-bytes! ctx sz al)))
                     (cond
                       ((%c99-lower-aggregate-like? pty)
                        (%c99-lower-expr-to-stack-slot! ctx arg slot-si))
                       ((c-float-type? pty)
                        (%c99-lower-expr! ctx arg)
                        (%c99-lower-emit! ctx (list '%store-typed pty '%rsp slot-si '%xmm0)))
                       (else
                        (%c99-lower-expr! ctx arg)
                        (%c99-lower-emit-cast! ctx pty)
                        (%c99-lower-emit! ctx (list '%store '%rsp slot-si '%rax))))
                     slot-si))
                 arg-nodes all-param-tys))
               (min-after-args (lower-ctx-next-si ctx))
               (needed (+ (- 0 min-after-args) stack-arg-bytes))
               (shift (align-frame-shift needed))
               (min-touch (- 0 shift)))
          (if (< min-touch (lower-ctx-min-si ctx))
              (lower-ctx-min-si-set! ctx min-touch))
          ;; Copy stack-passed arguments first
          (%c99-for-each2
           (lambda (plan slot-si)
             (if (eq? (car plan) 'stack)
                 (let ((st-off (cadr plan))
                       (psz (caddr plan)))
                   (%c99-lower-memcpy-regs! ctx '%rsp (+ (- 0 shift) st-off) '%rsp slot-si psz))))
           param-plans arg-slots)
          ;; Load register-passed arguments
          (%c99-for-each2
           (lambda (plan slot-si)
             (if (eq? (car plan) 'regs)
                 (for-each
                  (lambda (pc)
                    (let ((kind (list-ref pc 0))
                          (reg (list-ref pc 1))
                          (off (list-ref pc 2))
                          (csz (list-ref pc 3)))
                      (if (eq? kind 'gpr)
                          (%c99-lower-load-chunk-gpr! ctx reg '%rsp (+ slot-si off) csz)
                          (%c99-lower-emit! ctx (list '%load-typed (if (<= csz 4) 'f32 'f64) reg '%rsp (+ slot-si off))))))
                  (cadr plan))))
           param-plans arg-slots)
          ;; Hidden sret argument passed in %rdi
          (if (eq? (car ret-plan) 'sret)
              (%c99-lower-emit! ctx (list '%load '%rdi '%rsp sret-ptr-si)))
          (if (and direct-fn-sym (lower-ctx-sanitize-bounds? ctx))
              (%c99-san-check-call! ctx direct-fn-sym arg-nodes
                (or (and (pair? maybe-dst-ptr-si) (pair? (cdr maybe-dst-ptr-si)) (cadr maybe-dst-ptr-si))
                    (c-typed-span fn-node)
                    (and (pair? arg-nodes) (c-typed-span (car arg-nodes))))))
          (if direct-fn-sym
              (let* ((resolved-fn-sym (%c99-lower-resolve-runtime-fn! ctx direct-fn-sym))
                     (internal? (or (memq resolved-fn-sym (lower-ctx-internal-fns ctx))
                                    (c99-builtin-weak-fn-sym? resolved-fn-sym)))
                     (needs-al? (%c99-call-needs-al? fty arg-nodes)))
                (if internal?
                    (begin
                      (if needs-al?
                          (%c99-lower-emit! ctx (list '%mov '%rax (min 8 xmm-used))))
                      (%c99-lower-emit! ctx (list '%direct-call resolved-fn-sym shift)))
                    (if needs-al?
                        (%c99-lower-emit! ctx (list '%c-call (symbol->string resolved-fn-sym) shift (min 8 xmm-used)))
                        (%c99-lower-emit! ctx (list '%c-call (symbol->string resolved-fn-sym) shift)))))
              (begin
                (%c99-lower-emit! ctx (list '%load '%r11 '%rsp fn-ptr-si))
                (%c99-lower-emit! ctx (list '%call-indirect '%r11 shift (min 8 xmm-used)))))
          ;; Handle aggregate or scalar return value
          (cond
            ((and (%c99-lower-aggregate-like? call-ret-ty)
                  (eq? (car ret-plan) 'regs)
                  sret-ptr-si)
             (%c99-lower-store-ret-pieces! ctx (cadr ret-plan) sret-ptr-si))
            ((and (%c99-lower-aggregate-like? call-ret-ty)
                  (eq? (car ret-plan) 'empty)
                  sret-ptr-si)
             #f)
            ((not (%c99-lower-aggregate-like? call-ret-ty))
             (if (and (not (eq? call-ret-ty 'void)) (not (c-float-type? call-ret-ty)))
                 (%c99-lower-emit-cast! ctx call-ret-ty))))
          (lower-ctx-next-si-set! ctx saved-si)
          (lower-ctx-gpr-temps-set! ctx saved-gpr)
          (lower-ctx-xmm-temps-set! ctx saved-xmm)))))

;;; -----------------------------------------------------------------------
;;; 6b. System V AMD64 psABI §3.5.7 <stdarg.h> Lowering
;;; -----------------------------------------------------------------------

(define (%c99-lower-va-emit-ovf! ctx ovf-step al)
  ;; Expects ap struct pointer in %rdx. Returns aligned arg pointer in %rcx
  ;; and advances ap->overflow_arg_area by ovf-step. Clobbers %rcx, %r8.
  (%c99-lower-emit! ctx '(%load %rcx %rdx 8))
  (if (> al 8)
      (begin
        (%c99-lower-emit! ctx (list '%add '%rcx (- al 1)))
        (%c99-lower-emit! ctx (list '%mov '%r8 (- 0 al)))
        (%c99-lower-emit! ctx '(%bit-and %rcx %r8))))
  (%c99-lower-emit! ctx '(%mov %r8 %rcx))
  (%c99-lower-emit! ctx (list '%add '%r8 ovf-step))
  (%c99-lower-emit! ctx '(%store %rdx 8 %r8)))

(define (%c99-lower-va-start! ctx inner)
  (let ((meta (lower-ctx-va-meta ctx)))
    (if (not meta)
        (error "va_start lowered inside non-variadic function" inner))
    (let ((rsa-si   (list-ref meta 0))
          (init-gp  (list-ref meta 1))
          (init-fp  (list-ref meta 2))
          (init-ovf (list-ref meta 3)))
      (%c99-lower-expr! ctx (cadr inner))
      (%c99-lower-emit! ctx '(%mov %rdx %rax))
      (%c99-lower-emit! ctx (list '%mov '%rax init-gp))
      (%c99-lower-emit! ctx '(%store-typed u32 %rdx 0 %rax))
      (%c99-lower-emit! ctx (list '%mov '%rax init-fp))
      (%c99-lower-emit! ctx '(%store-typed u32 %rdx 4 %rax))
      (%c99-lower-emit! ctx '(%mov %rax %rsp))
      (%c99-lower-emit! ctx (list '%add '%rax init-ovf))
      (%c99-lower-emit! ctx '(%store %rdx 8 %rax))
      (%c99-lower-emit! ctx '(%mov %rax %rsp))
      (%c99-lower-emit! ctx (list '%add '%rax rsa-si))
      (%c99-lower-emit! ctx '(%store %rdx 16 %rax)))))

(define (%c99-lower-va-copy! ctx inner)
  (let* ((saved-si (lower-ctx-next-si ctx))
         (dst-si (%c99-lower-alloc-slot! ctx))
         (src-si (%c99-lower-alloc-slot! ctx)))
    (%c99-lower-expr! ctx (cadr inner))
    (%c99-lower-emit! ctx (list '%store '%rsp dst-si '%rax))
    (%c99-lower-expr! ctx (caddr inner))
    (%c99-lower-emit! ctx (list '%store '%rsp src-si '%rax))
    (%c99-lower-emit! ctx (list '%load '%rdx '%rsp dst-si))
    (%c99-lower-emit! ctx (list '%load '%rcx '%rsp src-si))
    (%c99-lower-memcpy-regs! ctx '%rdx 0 '%rcx 0 *sysv-va-list-size*)
    (lower-ctx-next-si-set! ctx saved-si)))

(define (%c99-lower-va-end! ctx inner)
  (%c99-lower-expr! ctx (cadr inner)))

(define (%c99-lower-va-arg! ctx inner target-ty maybe-dst-ptr-si)
  (let* ((saved-si (lower-ctx-next-si ctx))
         (lenv (lower-ctx-layout-env ctx))
         (sz (max 1 (%c99-lower-type-size ctx target-ty)))
         (al (max 1 (%c99-lower-type-align ctx target-ty)))
         (cls (c99-sysv-type-abi-class lenv target-ty))
         (ovf-step (c-type-align-up (max 8 sz) 8)))
    (%c99-lower-expr! ctx (cadr inner))
    (%c99-lower-emit! ctx '(%mov %rdx %rax))
    (cond
      ;; Empty struct/union
      ((or (eq? cls 'empty) (eq? cls 'VOID) (not (pair? cls)))
       (if (not (eq? cls 'MEMORY))
           #f
           (begin
             (%c99-lower-va-emit-ovf! ctx ovf-step al)
             (if maybe-dst-ptr-si
                 (begin
                   (%c99-lower-emit! ctx (list '%load '%rdx '%rsp maybe-dst-ptr-si))
                   (%c99-lower-memcpy-regs! ctx '%rdx 0 '%rcx 0 sz))
                 (%c99-lower-load-from-mem! ctx (if (c-float-type? target-ty) '%xmm0 '%rax) '%rcx 0 target-ty)))))

      ;; 1-eightbyte INTEGER or SSE
      ((null? (cdr cls))
       (let* ((c0 (car cls))
              (is-sse? (eq? c0 'SSE))
              (off-disp (if is-sse? 4 0))
              (max-off (if is-sse? 160 40))
              (reg-step (if is-sse? 16 8))
              (ovf-lbl (%c99-lower-new-label ctx "va_ovf"))
              (done-lbl (%c99-lower-new-label ctx "va_done")))
         (%c99-lower-emit! ctx (list '%load-typed 'u32 '%rax '%rdx off-disp))
         (%c99-lower-emit! ctx (list '%cmp '%rax max-off))
         (%c99-lower-emit! ctx (list '%jump-cond 'ja ovf-lbl))
         (%c99-lower-emit! ctx '(%mov %r8 %rax))
         (%c99-lower-emit! ctx (list '%add '%rax reg-step))
         (%c99-lower-emit! ctx (list '%store-typed 'u32 '%rdx off-disp '%rax))
         (%c99-lower-emit! ctx '(%load %rcx %rdx 16))
         (%c99-lower-emit! ctx '(%add %rcx %r8))
         (%c99-lower-emit! ctx (list '%direct-jump done-lbl))
         (%c99-lower-emit! ctx (list '%label ovf-lbl))
         (%c99-lower-va-emit-ovf! ctx ovf-step al)
         (%c99-lower-emit! ctx (list '%label done-lbl))
         (if maybe-dst-ptr-si
             (begin
               (%c99-lower-emit! ctx (list '%load '%rdx '%rsp maybe-dst-ptr-si))
               (%c99-lower-memcpy-regs! ctx '%rdx 0 '%rcx 0 sz))
             (%c99-lower-load-from-mem! ctx (if is-sse? '%xmm0 '%rax) '%rcx 0 target-ty))))

      ;; 2-eightbyte (INTEGER INTEGER)
      ((and (eq? (car cls) 'INTEGER) (eq? (cadr cls) 'INTEGER))
       (let ((ovf-lbl (%c99-lower-new-label ctx "va_ovf"))
             (done-lbl (%c99-lower-new-label ctx "va_done")))
         (%c99-lower-emit! ctx '(%load-typed u32 %rax %rdx 0))
         (%c99-lower-emit! ctx '(%cmp %rax 32))
         (%c99-lower-emit! ctx (list '%jump-cond 'ja ovf-lbl))
         (%c99-lower-emit! ctx '(%mov %r8 %rax))
         (%c99-lower-emit! ctx '(%add %rax 16))
         (%c99-lower-emit! ctx '(%store-typed u32 %rdx 0 %rax))
         (%c99-lower-emit! ctx '(%load %rcx %rdx 16))
         (%c99-lower-emit! ctx '(%add %rcx %r8))
         (%c99-lower-emit! ctx (list '%direct-jump done-lbl))
         (%c99-lower-emit! ctx (list '%label ovf-lbl))
         (%c99-lower-va-emit-ovf! ctx ovf-step al)
         (%c99-lower-emit! ctx (list '%label done-lbl))
         (if maybe-dst-ptr-si
             (begin
               (%c99-lower-emit! ctx (list '%load '%rdx '%rsp maybe-dst-ptr-si))
               (%c99-lower-memcpy-regs! ctx '%rdx 0 '%rcx 0 sz)))))

      ;; 2-eightbyte (SSE SSE): XMM slots are stride-16 in RSA, stride-8 on overflow stack
      ((and (eq? (car cls) 'SSE) (eq? (cadr cls) 'SSE))
       (let ((ovf-lbl (%c99-lower-new-label ctx "va_ovf"))
             (done-lbl (%c99-lower-new-label ctx "va_done"))
             (src-si (%c99-lower-alloc-slot! ctx)))
         (%c99-lower-emit! ctx '(%load-typed u32 %rax %rdx 4))
         (%c99-lower-emit! ctx '(%cmp %rax 144))
         (%c99-lower-emit! ctx (list '%jump-cond 'ja ovf-lbl))
         (%c99-lower-emit! ctx '(%mov %r8 %rax))
         (%c99-lower-emit! ctx '(%add %rax 32))
         (%c99-lower-emit! ctx '(%store-typed u32 %rdx 4 %rax))
         (%c99-lower-emit! ctx '(%load %rcx %rdx 16))
         (%c99-lower-emit! ctx '(%add %rcx %r8))
         (%c99-lower-emit! ctx (list '%store '%rsp src-si '%rcx))
         (if maybe-dst-ptr-si
             (begin
               (%c99-lower-emit! ctx (list '%load '%rdx '%rsp maybe-dst-ptr-si))
               (%c99-lower-memcpy-regs! ctx '%rdx 0 '%rcx 0 8)
               (%c99-lower-emit! ctx (list '%load '%rcx '%rsp src-si))
               (%c99-lower-emit! ctx (list '%load '%rdx '%rsp maybe-dst-ptr-si))
               (%c99-lower-memcpy-regs! ctx '%rdx 8 '%rcx 16 (- sz 8))))
         (%c99-lower-emit! ctx (list '%direct-jump done-lbl))
         (%c99-lower-emit! ctx (list '%label ovf-lbl))
         (%c99-lower-va-emit-ovf! ctx ovf-step al)
         (if maybe-dst-ptr-si
             (begin
               (%c99-lower-emit! ctx (list '%load '%rdx '%rsp maybe-dst-ptr-si))
               (%c99-lower-memcpy-regs! ctx '%rdx 0 '%rcx 0 sz)))
         (%c99-lower-emit! ctx (list '%label done-lbl))))

      ;; Mixed 2-eightbyte (INTEGER SSE) or (SSE INTEGER): All-or-Nothing pre-check
      (else
       (let ((ovf-lbl (%c99-lower-new-label ctx "va_ovf"))
             (done-lbl (%c99-lower-new-label ctx "va_done"))
             (gp-si (%c99-lower-alloc-slot! ctx))
             (fp-si (%c99-lower-alloc-slot! ctx)))
         (%c99-lower-emit! ctx '(%load-typed u32 %rax %rdx 0))
         (%c99-lower-emit! ctx '(%cmp %rax 40))
         (%c99-lower-emit! ctx (list '%jump-cond 'ja ovf-lbl))
         (%c99-lower-emit! ctx '(%mov %r8 %rax))
         (%c99-lower-emit! ctx '(%load-typed u32 %rax %rdx 4))
         (%c99-lower-emit! ctx '(%cmp %rax 160))
         (%c99-lower-emit! ctx (list '%jump-cond 'ja ovf-lbl))
         (%c99-lower-emit! ctx '(%mov %r9 %rax))
         (%c99-lower-emit! ctx '(%load %rcx %rdx 16))
         (%c99-lower-emit! ctx '(%mov %r10 %rcx))
         (%c99-lower-emit! ctx '(%add %r10 %r8))
         (%c99-lower-emit! ctx (list '%store '%rsp gp-si '%r10))
         (%c99-lower-emit! ctx '(%mov %r10 %rcx))
         (%c99-lower-emit! ctx '(%add %r10 %r9))
         (%c99-lower-emit! ctx (list '%store '%rsp fp-si '%r10))
         (%c99-lower-emit! ctx '(%mov %rax %r8))
         (%c99-lower-emit! ctx '(%add %rax 8))
         (%c99-lower-emit! ctx '(%store-typed u32 %rdx 0 %rax))
         (%c99-lower-emit! ctx '(%mov %rax %r9))
         (%c99-lower-emit! ctx '(%add %rax 16))
         (%c99-lower-emit! ctx '(%store-typed u32 %rdx 4 %rax))
         (if maybe-dst-ptr-si
             (begin
               (%c99-lower-emit! ctx (list '%load '%rdx '%rsp maybe-dst-ptr-si))
               (%c99-lower-emit! ctx (list '%load '%rcx '%rsp (if (eq? (car cls) 'INTEGER) gp-si fp-si)))
               (%c99-lower-memcpy-regs! ctx '%rdx 0 '%rcx 0 8)
               (%c99-lower-emit! ctx (list '%load '%rdx '%rsp maybe-dst-ptr-si))
               (%c99-lower-emit! ctx (list '%load '%rcx '%rsp (if (eq? (cadr cls) 'INTEGER) gp-si fp-si)))
               (%c99-lower-memcpy-regs! ctx '%rdx 8 '%rcx 0 (- sz 8))))
         (%c99-lower-emit! ctx (list '%direct-jump done-lbl))
         (%c99-lower-emit! ctx (list '%label ovf-lbl))
         (%c99-lower-va-emit-ovf! ctx ovf-step al)
         (if maybe-dst-ptr-si
             (begin
               (%c99-lower-emit! ctx (list '%load '%rdx '%rsp maybe-dst-ptr-si))
               (%c99-lower-memcpy-regs! ctx '%rdx 0 '%rcx 0 sz)))
         (%c99-lower-emit! ctx (list '%label done-lbl)))))
    (lower-ctx-next-si-set! ctx saved-si)))


;;; -----------------------------------------------------------------------
;;; 8.3 SysV AMD64 Function Prologue / Epilogue
;;; -----------------------------------------------------------------------

(define (%c99-count-abi-reg-pieces ret-plan param-plans kind)
  (+ (if (and (eq? kind 'gpr) (eq? (car ret-plan) 'sret)) 1 0)
     (let loop ((ps param-plans) (k 0))
       (if (null? ps)
           k
           (let ((p (car ps)))
             (if (eq? (car p) 'regs)
                 (let ploop ((pcs (cadr p)) (kk k))
                   (if (null? pcs)
                       (loop (cdr ps) kk)
                       (ploop (cdr pcs) (if (eq? (caar pcs) kind) (+ kk 1) kk))))
                 (loop (cdr ps) k)))))))

(define (%c99-lower-function ctx fn-node globals)
  (let* ((fn-sym (list-ref fn-node 1))
         (ret-ty  (list-ref fn-node 2))
         (variadic? (list-ref fn-node 3))
         (params  (list-ref fn-node 4))
         (body    (list-ref fn-node 5))
         (param-tys (map caddr params))
         (abi (c99-plan-sysv-abi (lower-ctx-layout-env ctx) ret-ty param-tys))
         (ret-plan (car abi))
         (param-plans (cadr abi))
         (named-stack-bytes (caddr abi))
         (ret-lbl (%c99-lower-new-label ctx "ret")))
    (lower-ctx-vars-set! ctx '())
    (lower-ctx-insts-set! ctx '())
    (lower-ctx-cold-insts-set! ctx '())
    (lower-ctx-next-si-set! ctx -16)
    (lower-ctx-min-si-set! ctx -16)
    (lower-ctx-user-labels-set! ctx '())
    (lower-ctx-ret-lbl-set! ctx ret-lbl)
    (lower-ctx-ret-plan-set! ctx ret-plan)
    (lower-ctx-va-meta-set! ctx #f)
    (lower-ctx-gpr-temps-set! ctx *c99-gpr-temp-pool*)
    (lower-ctx-xmm-temps-set! ctx *c99-xmm-temp-pool*)
    (lower-ctx-san-ptr-meta-set! ctx '())
    (lower-ctx-san-last-cap-si-set! ctx
      (if (lower-ctx-sanitize-bounds? ctx) (%c99-lower-alloc-slot! ctx) #f))
    (for-each
     (lambda (g)
       (%c99-lower-bind-data-global! ctx (list-ref g 1) (list-ref g 3)))
     globals)
    ;; Variadic System V AMD64 Register Save Area prologue (176B at entry before sret/param spills)
    (if variadic?
        (let ((rsa-si (%c99-lower-alloc-bytes! ctx *sysv-va-reg-save-area-size* 16))
              (skip-xmm-lbl (%c99-lower-new-label ctx "va_skip_xmm"))
              (used-gpr (%c99-count-abi-reg-pieces ret-plan param-plans 'gpr))
              (used-xmm (%c99-count-abi-reg-pieces ret-plan param-plans 'sse)))
          (let sloop-g ((regs *sysv-gpr-arg-registers*) (off 0))
            (if (pair? regs)
                (begin
                  (%c99-lower-emit! ctx (list '%store '%rsp (+ rsa-si off) (car regs)))
                  (sloop-g (cdr regs) (+ off 8)))))
          (%c99-lower-emit! ctx '(%bit-and %rax 255))
          (%c99-lower-emit! ctx '(%cmp %rax 0))
          (%c99-lower-emit! ctx (list '%jump-cond 'je skip-xmm-lbl))
          (let sloop-x ((xregs *sysv-xmm-arg-registers*) (off *sysv-va-fp-base*))
            (if (pair? xregs)
                (begin
                  (%c99-lower-emit! ctx (list '%store-typed 'f64 '%rsp (+ rsa-si off) (car xregs)))
                  (sloop-x (cdr xregs) (+ off 16)))))
          (%c99-lower-emit! ctx (list '%label skip-xmm-lbl))
          (lower-ctx-va-meta-set!
           ctx
           (list rsa-si
                 (* 8 (min 6 used-gpr))
                 (+ *sysv-va-fp-base* (* 16 (min 8 used-xmm)))
                 (+ 8 named-stack-bytes)))))
    ;; Save hidden sret pointer if returning >16B struct
    (if (eq? (car ret-plan) 'sret)
        (let ((s-si (%c99-lower-alloc-slot! ctx)))
          (lower-ctx-sret-si-set! ctx s-si)
          (%c99-lower-emit! ctx (list '%store '%rsp s-si '%rdi)))
        (lower-ctx-sret-si-set! ctx #f))
    ;; Allocate local parameter slots & save incoming SysV args
    (let ((param-slots
           (%c99-map2
            (lambda (p plan)
              (let* ((u-sym (list-ref p 0))
                     (pty (list-ref p 2))
                     (si (%c99-lower-bind-local! ctx u-sym pty)))
                (if (and (lower-ctx-sanitize-bounds? ctx) (c-pointer-type? pty))
                    (%c99-san-alloc-ptr-meta! ctx u-sym))
                (if (eq? (car plan) 'regs)
                    (for-each
                     (lambda (pc)
                       (let ((kind (list-ref pc 0))
                             (reg (list-ref pc 1))
                             (off (list-ref pc 2))
                             (csz (list-ref pc 3)))
                         (if (eq? kind 'gpr)
                             (%c99-lower-store-chunk-gpr! ctx '%rsp (+ si off) reg csz)
                             (%c99-lower-emit! ctx (list '%store-typed (if (<= csz 4) 'f32 'f64) '%rsp (+ si off) reg)))))
                     (cadr plan)))
                (list si plan)))
            params param-plans)))
      ;; Copy stack-passed incoming args (callee sees caller arg at [rsp + 8 + st_off])
      (for-each
       (lambda (ps)
         (let ((si (car ps))
               (plan (cadr ps)))
           (if (eq? (car plan) 'stack)
               (let ((st-off (cadr plan))
                     (psz (caddr plan)))
                 (%c99-lower-memcpy-regs! ctx '%rsp si '%rsp (+ 8 st-off) psz)))))
       param-slots))
    (%c99-lower-stmt! ctx body)
    (%c99-lower-emit! ctx '(%mov %rax 0))
    (%c99-lower-emit! ctx (list '%label ret-lbl))
    (%c99-lower-emit! ctx '(%return))
    (let* ((used (- 0 (lower-ctx-min-si ctx)))
           (frame-sz (c-type-align-up (max 16 used) 16))
           (param-names (map cadr params))
           (meta-inits
            (if (lower-ctx-sanitize-bounds? ctx)
                (let mloop ((ms (lower-ctx-san-ptr-meta ctx)) (acc '()))
                  (if (null? ms)
                      (reverse acc)
                      (let* ((m (cdr (car ms)))
                             (prov-si (list-ref m 0))
                             (cap-si (list-ref m 1))
                             (freed-si (list-ref m 2)))
                        (mloop (cdr ms)
                               (append
                                (list (list '%store '%rsp freed-si '%r10)
                                      '(%mov %r10 0)
                                      (list '%store '%rsp cap-si '%r10)
                                      '(%mov %r10 -1)
                                      (list '%store '%rsp prov-si '%r10)
                                      '(%mov %r10 0))
                                acc)))))
                '()))
           (cold (lower-ctx-cold-insts ctx))
           (body-core (if (null? meta-inits)
                          (reverse (lower-ctx-insts ctx))
                          (append meta-inits (reverse (lower-ctx-insts ctx)))))
           (full-body (if (null? cold)
                          body-core
                          (append body-core (reverse cold)))))
      (list '%lir-function
            fn-sym
            (list 'params param-names)
            (list 'frame-size frame-sz)
            (cons 'body full-body)))))


;;; -----------------------------------------------------------------------
;;; 8.4 Modular C99 ABI Pass Entrypoints (Issue #967)
;;; -----------------------------------------------------------------------

(define (c99-lower-abi-fn ctx fn-node globals)
  (%c99-lower-function ctx fn-node globals))

(define (c99-lower-abi-run ir)
  (cond
    ((and (pair? ir) (eq? (car ir) 'c-typed-unit))
     (c99-lower-to-lir ir))
    (else ir)))

(set-car! *c99-lower-abi-hook* c99-lower-abi-run)
