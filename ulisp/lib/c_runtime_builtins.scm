;;; =======================================================================
;;; ULisp C99 Runtime Builtins: %inline-asm setjmp / longjmp (Issue #922)
;;; Conforms to DSN-33-32 §4.2, DSN-33-13 §2.4, ISO C99 §7.13 & SysV AMD64.
;;; Zero local `set!` (ULisp AOT safe).
;;; =======================================================================

(define *c99-jmp-buf-slots* 8)
(define *c99-jmp-buf-size* 64)
(define *c99-jmp-buf-align* 8)

(define *c99-setjmp-fn-names*
  '(setjmp _setjmp sigsetjmp __ulisp_setjmp))

(define *c99-longjmp-fn-names*
  '(longjmp _longjmp siglongjmp __ulisp_longjmp))

(define *c99-builtin-weak-fn-names*
  '(__ulisp_setjmp __ulisp_longjmp))

(define (c99-setjmp-fn-sym? sym)
  (and (symbol? sym) (memq sym *c99-setjmp-fn-names*) #t))

(define (c99-longjmp-fn-sym? sym)
  (and (symbol? sym) (memq sym *c99-longjmp-fn-names*) #t))

(define (c99-setjmp-or-longjmp-sym? sym)
  (or (c99-setjmp-fn-sym? sym)
      (c99-longjmp-fn-sym? sym)))

(define (c99-builtin-weak-fn-sym? sym)
  (and (symbol? sym) (memq sym *c99-builtin-weak-fn-names*) #t))

;;; 64-byte jmp_buf slot layout (SysV AMD64):
;;;   +0  (%rbx), +8  (%rbp), +16 (%r12), +24 (%r13),
;;;   +32 (%r14), +40 (%r15), +48 (caller %rsp = rsp+8), +56 (return %rip = [rsp])
(define (make-c99-builtin-setjmp-lir)
  (list '%lir-function
        '__ulisp_setjmp
        '(params (env))
        '(frame-size 0)
        '(body
          (%inline-asm
            "mov [rdi + 0], rbx\nmov [rdi + 8], rbp\nmov [rdi + 16], r12\nmov [rdi + 24], r13\nmov [rdi + 32], r14\nmov [rdi + 40], r15\nlea rdx, [rsp + 8]\nmov [rdi + 48], rdx\nmov rdx, [rsp]\nmov [rdi + 56], rdx\nxor eax, eax"
            (:outputs (((%reg %rax) "=a")))
            (:inputs  (((%reg %rdi) "D")))
            (:clobbers ("%rdx" "cc" "memory"))
            (:volatile? #t))
          (%return %rax))))

(define (make-c99-builtin-longjmp-lir)
  (list '%lir-function
        '__ulisp_longjmp
        '(params (env val))
        '(frame-size 0)
        '(body
          (%inline-asm
            "movsxd rax, esi\nmov rcx, 1\ntest esi, esi\ncmove rax, rcx\nmov rbx, [rdi + 0]\nmov rbp, [rdi + 8]\nmov r12, [rdi + 16]\nmov r13, [rdi + 24]\nmov r14, [rdi + 32]\nmov r15, [rdi + 40]\nmov rdx, [rdi + 56]\nmov rsp, [rdi + 48]\njmp rdx"
            (:inputs  (((%reg %rdi) "D")
                       ((%reg %rsi) "S")))
            (:clobbers ("%rax" "%rcx" "%rdx" "cc" "memory"))
            (:volatile? #t))
          (%return %rax))))
