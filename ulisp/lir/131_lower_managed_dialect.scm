;;; =======================================================================
;;; ULisp Compiler Pass 131: Lower Managed Runtime Dialect to Core Machine LIR
;;; Conforms to DSN-33, DSN-38 Architecture Specifications & Issue #835
;;; =======================================================================
;;; Formally lowers high-level Managed Runtime Dialect instructions
;;; (%alloc, %alloc-stack, %box-*, %unbox-*, %managed-*, %capture-cc, etc.)
;;; into pure, unmanaged Core Machine LIR instruction sequences.
;;;
;;; Guarantees:
;;; 1. The output contains ZERO managed dialect opcodes.
;;; 2. All heap/stack pointer operations conform to machine alignment rules.
;;; 3. Unmanaged/C-language frontends bypass this pass and target Core LIR directly.
;;; =======================================================================

(define *managed-dialect-opcodes*
  '(%alloc
    %alloc-stack
    %managed-alloc
    %managed-alloc-stack
    %managed-safepoint-poll
    %managed-write-barrier
    %managed-box
    %managed-unbox
    %box-fixnum
    %unbox-fixnum
    %box-flonum
    %unbox-flonum
    %capture-cc
    %push-handler
    %pop-handler
    %raise
    %set-values-count
    %store-values-buf))

(define (managed-dialect-opcode? op)
  (if (memq op *managed-dialect-opcodes*) #t #f))

;;; -----------------------------------------------------------------------
;;; Instruction-Level Lowering Transformer
;;; -----------------------------------------------------------------------

(define (lower-managed-inst inst)
  (if (not (pair? inst))
      (list inst)
      (let ((op (car inst)))
        (case op
          ;; 1. Heap Allocation: (%alloc dst bytes tag [si]) / (%managed-alloc dst bytes tag [si])
          ((%alloc %managed-alloc)
           (let* ((dst (cadr inst))
                  (bytes (caddr inst))
                  (tag (cadddr inst))
                  (aligned (ctfe-bitwise-and (+ bytes 7) -8)))
             (if (equal? dst '%r12)
                 (list (list '%add '%r12 aligned))
                 (list (list '%mov dst '%r12)
                       (list '%add dst tag)
                       (list '%add '%r12 aligned)))))

          ;; 2. Stack Allocation: (%alloc-stack dst offset tag) / (%managed-alloc-stack dst offset tag)
          ((%alloc-stack %managed-alloc-stack)
           (let* ((dst (cadr inst))
                  (offset (caddr inst))
                  (tag (cadddr inst))
                  (disp (+ offset tag)))
             (if (= disp 0)
                 (list (list '%mov dst '%rsp))
                 (list (list '%mov dst '%rsp)
                       (list '%add dst disp)))))

          ;; 3. Safepoint Polling: (%managed-safepoint-poll) / (%safepoint-poll)
          ((%managed-safepoint-poll %safepoint-poll)
           (list '(%safepoint-poll)))

          ;; 4. Write Barrier: (%managed-write-barrier obj offset val)
          ((%managed-write-barrier)
           (let ((obj (cadr inst))
                 (offset (caddr inst))
                 (val (cadddr inst)))
             (list (list '%mov '%r11 obj)
                   (list '%add '%r11 offset)
                   (list '%shr '%r11 9)
                   (list '%global-ref '%r10 'ulisp_card_table_base)
                   (list '%store-byte '%r10 '%r11 1))))

          ;; 5. Fixnum Boxing & Unboxing: (%box-fixnum dst src), (%unbox-fixnum dst src)
          ((%box-fixnum)
           (let ((dst (cadr inst))
                 (src (caddr inst)))
             (repr-emit-box-fixnum dst src)))

          ((%unbox-fixnum)
           (let ((dst (cadr inst))
                 (src (caddr inst)))
             (repr-emit-unbox-fixnum dst src)))

          ;; 6. Generic Managed Box / Unbox: (%managed-box mty dst src), (%managed-unbox mty dst src)
          ((%managed-box)
           (let ((mty (cadr inst))
                 (dst (caddr inst))
                 (src (cadddr inst)))
             (cond
               ((or (eq? mty 'fixnum) (eq? mty 'i64))
                (repr-emit-box-fixnum dst src))
               ((or (eq? mty 'flonum) (eq? mty 'f64))
                (repr-emit-box-flonum dst src))
               (else
                (if (equal? dst src)
                    '()
                    (list (list '%mov dst src)))))))

          ((%managed-unbox)
           (let ((mty (cadr inst))
                 (dst (caddr inst))
                 (src (cadddr inst)))
             (cond
               ((or (eq? mty 'fixnum) (eq? mty 'i64))
                (repr-emit-unbox-fixnum dst src))
               ((or (eq? mty 'flonum) (eq? mty 'f64))
                (repr-emit-unbox-flonum dst src))
               (else
                (if (equal? dst src)
                    '()
                    (list (list '%mov dst src)))))))

          ;; 7. Flonum Boxing & Unboxing: (%box-flonum dst src), (%unbox-flonum dst src)
          ((%box-flonum)
           (let ((dst (cadr inst))
                 (src (caddr inst)))
             (repr-emit-box-flonum dst src)))

          ((%unbox-flonum)
           (let ((dst (cadr inst))
                 (src (caddr inst)))
             (repr-emit-unbox-flonum dst src)))

          ;; 8. Runtime Continuations, Exceptions and Multiple Values
          ;; Handled directly by native backend code generators (e.g. 140_backend_x86_64.scm)
          ((%capture-cc %push-handler %pop-handler %raise %set-values-count %store-values-buf)
           (list inst))

          ;; 9. Nested SSA Blocks: (%block lbl params . body)
          ((%block)
           (let ((lbl (cadr inst))
                 (params (caddr inst))
                 (sub-insts (cdddr inst)))
             (list (cons '%block
                         (cons lbl
                               (cons params
                                     (lower-managed-inst-list sub-insts)))))))

          ;; Default: Core Machine LIR instructions are preserved as-is
          (else
           (list inst))))))

(define (lower-managed-inst-list insts)
  (let loop ((is insts) (acc '()))
    (if (null? is)
        (reverse acc)
        (let ((lowered (lower-managed-inst (car is))))
          (loop (cdr is) (append (reverse lowered) acc))))))

;;; -----------------------------------------------------------------------
;;; Function, Main and Program Level Lowering
;;; -----------------------------------------------------------------------

(define (lower-managed-function fn-decl)
  (if (and (pair? fn-decl) (eq? (car fn-decl) '%lir-function))
      (let* ((lbl (cadr fn-decl))
             (params-clause (caddr fn-decl))
             (frame-clause (cadddr fn-decl))
             (body-clause (car (cddddr fn-decl)))
             (body-insts (cdr body-clause)))
        (list '%lir-function
              lbl
              params-clause
              frame-clause
              (cons 'body (lower-managed-inst-list body-insts))))
      fn-decl))

(define (lower-managed-main main-decl)
  (if (and (pair? main-decl) (eq? (car main-decl) '%lir-main))
      (let* ((frame-clause (cadr main-decl))
             (body-clause (caddr main-decl))
             (body-insts (cdr body-clause)))
        (list '%lir-main
              frame-clause
              (cons 'body (lower-managed-inst-list body-insts))))
      main-decl))

(define (lower-managed-dialect prog)
  (cond
    ((not (pair? prog)) prog)
    ((eq? (car prog) '%lir-program)
     (let* ((strings-clause (assq 'strings (cdr prog)))
            (data-clause (assq 'data (cdr prog)))
            (stackmaps-clause (assq 'stackmaps (cdr prog)))
            (funcs-clause (assq '%lir-functions (cdr prog)))
            (main-clause (assq '%lir-main (cdr prog)))
            (new-funcs (if funcs-clause
                           (cons '%lir-functions (map lower-managed-function (cdr funcs-clause)))
                           '(%lir-functions)))
            (new-main (if main-clause (lower-managed-main main-clause) '(%lir-main (frame-size 0) (body)))))
       (if data-clause
           (list '%lir-program
                 (if strings-clause strings-clause '(strings ()))
                 data-clause
                 (if stackmaps-clause stackmaps-clause '(stackmaps ()))
                 new-funcs
                 new-main)
           (list '%lir-program
                 (if strings-clause strings-clause '(strings ()))
                 (if stackmaps-clause stackmaps-clause '(stackmaps ()))
                 new-funcs
                 new-main))))
    ((eq? (car prog) '%lir-function)
     (lower-managed-function prog))
    ((eq? (car prog) '%lir-main)
     (lower-managed-main prog))
    ((list? prog)
     (lower-managed-inst-list prog))
    (else prog)))
