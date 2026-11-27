;;; =======================================================================
;;; ULisp Compiler Pass 140: Native x86-64 Backend Driver
;;; Modularized top-level entrypoint (Issue #968) coordinating:
;;;   140a_x86_isel.scm, 140c_x86_layout.scm, 140d_x86_emit.scm,
;;;   140e_x86_runtime_stubs.scm.
;;; =======================================================================
;;; -----------------------------------------------------------------------
;;; Pass 140 Entrypoint: Pipeline from LIR to Optimized x86 Assembly
;;; -----------------------------------------------------------------------

(define (emit-x86-64 prog gc-mode)
  (set-car! *backend-gc-mode* gc-mode)
  (set-car! *alloc-counter* 0)
  (let* ((asm-ast (select-instructions-x86 prog))
         (asm-opt (optimize-x86-peephole asm-ast)))
    (emit-x86-asm-program asm-opt gc-mode)
    asm-opt))

(define (emit-x86-64-profiled prog gc-mode)
  (set-car! *backend-gc-mode* gc-mode)
  (set-car! *alloc-counter* 0)
  (let* ((t0 (current-time-monotonic-us))
         (asm-ast (select-instructions-x86 prog))
         (t1 (current-time-monotonic-us))
         (asm-opt (optimize-x86-peephole asm-ast))
         (t2 (current-time-monotonic-us)))
    (emit-x86-asm-program asm-opt gc-mode)
    (let* ((t3 (current-time-monotonic-us))
           (d-isel (- t1 t0))
           (d-peep (- t2 t1))
           (d-emit (- t3 t2)))
      (list asm-opt
            (if (< d-isel 0) 0 d-isel)
            (if (< d-peep 0) 0 d-peep)
            (if (< d-emit 0) 0 d-emit)))))
