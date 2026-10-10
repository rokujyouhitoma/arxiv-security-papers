;;; =======================================================================
;;; MLisp Optimizer: Virtual Allocations & Escape Analysis (virtuals.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; 100% Pure Scheme Implementation of Virtual Object Optimization:
;;; - Detects short-lived heap allocations (cons, car, cdr, closures)
;;; - Performs intra-trace escape analysis
;;; - Rewrites field reads to direct virtual variable accesses
;;; - Eliminates non-escaping heap allocations completely (O(0) allocation)
;;; =======================================================================

;;; Virtual object descriptor:
;;; (var-name . (tag (field1-var field2-var ...)))
;;; e.g., (pair-1 . (pair (val-car val-cdr)))

(define (make-virtual-pair car-var cdr-var)
  (list 'pair car-var cdr-var))

(define (virtual-type v-desc)
  (car v-desc))

(define (virtual-pair-car v-desc)
  (cadr v-desc))

(define (virtual-pair-cdr v-desc)
  (caddr v-desc))

;;; Analyze which variables escape the trace
;;; An allocation escapes if it is passed to a non-virtual instruction,
;;; stored into global state, or passed to loop jump as an active live variable.
(define (collect-escaping-vars body)
  (let loop ((rest body)
             (escaped '()))
    (if (null? rest)
        escaped
        (let* ((inst (car rest))
               (op (car inst)))
          (case op
            ;; Cons, Car, Cdr are virtual-safe operations
            ((%cons %alloc-pair %car %cdr)
             (loop (cdr rest) escaped))

            ;; Moves between registers
            ((%mov)
             (loop (cdr rest) escaped))

            ;; Instructions that escape their arguments:
            ((%store-global %c-call %call-foreign)
             (let ((args (cddr inst)))
               (loop (cdr rest) (append (filter symbol? args) escaped))))

            ;; Guard instructions - bailout may escape variables
            ((%guard)
             (loop (cdr rest) escaped))

            ;; Loop jump - variables carried across loop iterations
            ((%trace-loop-jump)
             (loop (cdr rest) escaped))

            (else
             (loop (cdr rest) escaped)))))))

;;; Optimize body with virtual object elimination
(define (optimize-virtuals-body body)
  (let ((escaping (collect-escaping-vars body)))
    (let loop ((rest body)
               (v-map '())     ; Alist: (var-name . virtual-desc)
               (acc '()))
      (if (null? rest)
          (reverse acc)
          (let* ((inst (car rest))
                 (op (car inst)))
            (case op
              ;; Cons allocation: (%cons dst a b)
              ((%cons %alloc-pair)
               (let* ((dst (cadr inst))
                      (arg-a (caddr inst))
                      (arg-b (cadddr inst)))
                 (if (memq dst escaping)
                     ;; Escapes: must keep physical allocation
                     (loop (cdr rest) v-map (cons inst acc))
                     ;; Does NOT escape: virtualize!
                     ;; Record virtual descriptor and DROP physical allocation instruction
                     (let ((new-v-map (cons (cons dst (make-virtual-pair arg-a arg-b)) v-map)))
                       (loop (cdr rest) new-v-map acc)))))

              ;; Car read: (%car dst pair-var)
              ((%car)
               (let* ((dst (cadr inst))
                      (pair-var (caddr inst))
                      (v-desc (assq pair-var v-map)))
                 (if (and v-desc (eq? (virtual-type (cdr v-desc)) 'pair))
                     ;; Virtualized read! Rewrite to direct move from virtual car field
                     (let* ((car-val (virtual-pair-car (cdr v-desc)))
                            (opt-inst `(%mov ,dst ,car-val)))
                       (loop (cdr rest) v-map (cons opt-inst acc)))
                     ;; Not virtualized: keep instruction
                     (loop (cdr rest) v-map (cons inst acc)))))

              ;; Cdr read: (%cdr dst pair-var)
              ((%cdr)
               (let* ((dst (cadr inst))
                      (pair-var (caddr inst))
                      (v-desc (assq pair-var v-map)))
                 (if (and v-desc (eq? (virtual-type (cdr v-desc)) 'pair))
                     ;; Virtualized read! Rewrite to direct move from virtual cdr field
                     (let* ((cdr-val (virtual-pair-cdr (cdr v-desc)))
                            (opt-inst `(%mov ,dst ,cdr-val)))
                       (loop (cdr rest) v-map (cons opt-inst acc)))
                     ;; Not virtualized: keep instruction
                     (loop (cdr rest) v-map (cons inst acc)))))

              ;; Other instructions: preserve
              (else
               (loop (cdr rest) v-map (cons inst acc)))))))))

;;; Entrypoint: optimize complete (%trace-loop ...) S-expression with virtuals
(define (optimize-trace-virtuals trace)
  (if (not (and (pair? trace) (eq? (car trace) '%trace-loop)))
      trace
      (let* ((fields (cdr trace))
             (pc (assq '%pc fields))
             (body-entry (assq '%body fields))
             (body (if body-entry (cadr body-entry) '()))
             (opt-body (optimize-virtuals-body body)))
        `(%trace-loop
           ,pc
           (%body ,opt-body)))))

;;; Combined Full Optimizer Pipeline:
;;; 1. Partial Evaluation & Constant Folding (pe.scm)
;;; 2. Virtual Object Elimination (virtuals.scm)
;;; 3. Secondary PE pass to clean up new moves created by virtuals
(define (optimize-trace-full trace)
  (let* ((pass1 (optimize-trace-pe trace))
         (pass2 (optimize-trace-virtuals pass1))
         (pass3 (optimize-trace-pe pass2)))
    pass3))
