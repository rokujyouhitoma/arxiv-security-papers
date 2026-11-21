;;; =======================================================================
;;; MLisp Runtime: JIT Deoptimization & Stack Reconstruction (deopt.scm)
;;; Conforms to DSN-33, DSN-34 & Issue #900
;;;
;;; 100% Pure Scheme Implementation of JIT Guard Bailout & Frame Recovery:
;;; - CWE-674 Defense: Deopt thrashing detector & automatic trace blacklisting
;;; - CWE-400 Defense: Bounded depth virtual object re-materialization
;;; - CWE-787 / CWE-125 Defense: Safe register/stack slot to frame mapping
;;; - Re-materialization of virtualized allocations (%cons / %alloc-pair)
;;; - Interpreter frame reconstruction (FrameDescriptor / variable environment)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Security Limits & Constants
;;; -----------------------------------------------------------------------

;;; Maximum consecutive deoptimization failures allowed before blacklisting (CWE-674)
(define *jit-max-deopt-thrash* 3)

;;; Maximum recursion depth for nested virtual object re-materialization (CWE-400)
(define *max-rematerialize-depth* 32)

;;; -----------------------------------------------------------------------
;;; Runtime State Tables
;;; -----------------------------------------------------------------------

;;; Consecutive deoptimization failure counters: ((pc . count) ...)
(define *jit-deopt-counters* '())

;;; Blacklisted PCs whose traces have been invalidated due to thrashing
(define *jit-deopt-blacklist* '())

;;; Registered deoptimization snapshots: ((fail-lbl . snapshot-desc) ...)
(define *jit-deopt-snapshots* '())

;;; Cumulative deopt execution statistics
(define *jit-stats-deopt-total* 0)
(define *jit-stats-rematerializations* 0)

;;; -----------------------------------------------------------------------
;;; Runtime State Management
;;; -----------------------------------------------------------------------

;;; Reset deopt runtime state
(define (reset-deopt-runtime!)
  (set! *jit-deopt-counters* '())
  (set! *jit-deopt-blacklist* '())
  (set! *jit-deopt-snapshots* '())
  (set! *jit-stats-deopt-total* 0)
  (set! *jit-stats-rematerializations* 0))

;;; Check if a PC is blacklisted
(define (deopt-blacklisted? pc)
  (if (memq pc *jit-deopt-blacklist*) #t #f))

;;; Invalidate and blacklist a trace for a given PC
(define (deopt-blacklist-trace! pc)
  (if (not (memq pc *jit-deopt-blacklist*))
      (set! *jit-deopt-blacklist* (cons pc *jit-deopt-blacklist*))))

;;; Record a deoptimization failure for a PC and check for thrashing (CWE-674)
;;; Returns #t if blacklisted, #f otherwise
(define (record-deopt-failure! pc)
  (set! *jit-stats-deopt-total* (+ *jit-stats-deopt-total* 1))
  (let* ((entry (assq pc *jit-deopt-counters*))
         (current-count (if entry (cdr entry) 0))
         (new-count (+ current-count 1)))
    (if entry
        (set-cdr! entry new-count)
        (set! *jit-deopt-counters* (cons (cons pc new-count) *jit-deopt-counters*)))
    (if (>= new-count *jit-max-deopt-thrash*)
        (begin
          (deopt-blacklist-trace! pc)
          #t)
        #f)))

;;; Register a deoptimization snapshot associated with a bailout label
(define (register-deopt-snapshot! fail-lbl snapshot)
  (let ((entry (assq fail-lbl *jit-deopt-snapshots*)))
    (if entry
        (set-cdr! entry snapshot)
        (set! *jit-deopt-snapshots* (cons (cons fail-lbl snapshot) *jit-deopt-snapshots*)))))

;;; Lookup a registered snapshot
(define (lookup-deopt-snapshot fail-lbl)
  (let ((entry (assq fail-lbl *jit-deopt-snapshots*)))
    (if entry (cdr entry) #f)))

;;; -----------------------------------------------------------------------
;;; Virtual Object Re-materialization (CWE-400 Defense)
;;; -----------------------------------------------------------------------

;;; Construct a snapshot descriptor
;;; (%deopt-snapshot (%pc <pc>) (%frame-vars ((var . loc) ...)) (%virtual-objects ((v-var type f1 f2) ...)))
(define (make-deopt-snapshot pc frame-vars virtual-objects)
  (list '%deopt-snapshot
        (list '%pc pc)
        (list '%frame-vars frame-vars)
        (list '%virtual-objects virtual-objects)))

;;; Extract field from snapshot
(define (snapshot-field snapshot tag)
  (if (and (pair? snapshot) (eq? (car snapshot) '%deopt-snapshot))
      (let ((entry (assq tag (cdr snapshot))))
        (if entry (cadr entry) '()))
      '()))

;;; Safe recursive lookup and re-materialization of values from machine state
(define (rematerialize-value val v-defs machine-state depth)
  (if (> depth *max-rematerialize-depth*)
      (error "CWE-400 Defense: Virtual object re-materialization exceeded max recursion depth" depth)
      (cond
        ;; Direct number, boolean, string, or nil
        ((or (number? val) (boolean? val) (string? val) (null? val))
         val)

        ;; Symbol: could be a virtual variable, a physical machine register/slot, or a constant
        ((symbol? val)
         (let ((v-entry (assq val v-defs)))
           (if v-entry
               ;; It is a virtual object! Re-materialize on heap!
               (let* ((v-desc (cdr v-entry))
                      (v-type (car v-desc))
                      (fields (cdr v-desc)))
                 (set! *jit-stats-rematerializations* (+ *jit-stats-rematerializations* 1))
                 (case v-type
                   ((pair cons)
                    (let ((car-val (rematerialize-value (car fields) v-defs machine-state (+ depth 1)))
                          (cdr-val (rematerialize-value (cadr fields) v-defs machine-state (+ depth 1))))
                      (cons car-val cdr-val)))
                   (else
                    (cons v-type (map (lambda (f)
                                        (rematerialize-value f v-defs machine-state (+ depth 1)))
                                      fields)))))
               ;; Look up in machine state (registers/stack slots)
               (let ((m-entry (assq val machine-state)))
                 (if m-entry
                     (rematerialize-value (cdr m-entry) v-defs machine-state (+ depth 1))
                     val)))))

        ;; Already a pair (non-virtual structured data)
        ((pair? val)
         (cons (rematerialize-value (car val) v-defs machine-state (+ depth 1))
               (rematerialize-value (cdr val) v-defs machine-state (+ depth 1))))

        (else val))))

;;; Re-materialize all virtual objects in snapshot into a concrete environment
(define (rematerialize-virtuals v-defs machine-state)
  (map (lambda (v-entry)
         (let ((v-sym (car v-entry)))
           (cons v-sym (rematerialize-value v-sym v-defs machine-state 0))))
       v-defs))

;;; -----------------------------------------------------------------------
;;; Frame Reconstruction (CWE-787 / CWE-125 Defense)
;;; -----------------------------------------------------------------------

;;; Reconstruct interpreter frame variable environment from snapshot and machine state
;;; Returns: ((var-name . resolved-concrete-value) ...)
(define (restore-interpreter-frame snapshot machine-state)
  (let* ((frame-vars (snapshot-field snapshot '%frame-vars))
         (v-defs (snapshot-field snapshot '%virtual-objects)))
    (map (lambda (binding)
           (let* ((var-name (car binding))
                  (loc-or-val (cdr binding))
                  ;; Resolve location from machine state if it's a register/slot symbol
                  (raw-val (if (symbol? loc-or-val)
                               (let ((m (assq loc-or-val machine-state)))
                                 (if m (cdr m) loc-or-val))
                               loc-or-val))
                  ;; Re-materialize if raw-val is/contains a virtual object
                  (concrete-val (rematerialize-value raw-val v-defs machine-state 0)))
             (cons var-name concrete-val)))
         frame-vars)))

;;; -----------------------------------------------------------------------
;;; Guard Bailout & Deopt Trampoline Trigger
;;; -----------------------------------------------------------------------

;;; Trigger a guard deoptimization from JIT execution back to interpreter
;;; - Updates thrashing counter (CWE-674)
;;; - Looks up snapshot associated with fail-lbl
;;; - Reconstructs interpreter frame
;;; - Dispatches to fail-handler with reconstructed frame
(define (trigger-guard-deopt! pc fail-lbl machine-state fail-handler)
  (let* ((blacklisted? (record-deopt-failure! pc))
         (snapshot (lookup-deopt-snapshot fail-lbl))
         (recovered-frame (if snapshot
                              (restore-interpreter-frame snapshot machine-state)
                              machine-state)))
    (if (procedure? fail-handler)
        (fail-handler pc fail-lbl recovered-frame blacklisted?)
        (list 'deopt-bailout-result
              (cons 'pc pc)
              (cons 'fail-lbl fail-lbl)
              (cons 'frame recovered-frame)
              (cons 'blacklisted blacklisted?)))))
