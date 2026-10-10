;;; =======================================================================
;;; MLisp Runtime: Pure Scheme JIT Buffer & Dispatch Manager (jit_buffer.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; 100% Pure Scheme Implementation of JIT Execution Lifecycle:
;;; - JIT code buffer management (W^X status tracking)
;;; - Native JIT function dispatch and execution
;;; - Speculative guard failure & Bailout handling (Deoptimization)
;;; =======================================================================

(define *JIT-BUFFER-STATUS-UNALLOCATED* 'UNALLOCATED)
(define *JIT-BUFFER-STATUS-WRITABLE*    'WRITABLE)
(define *JIT-BUFFER-STATUS-EXECUTABLE*  'EXECUTABLE)

;;; JIT Execution Context
(define *jit-buffer-table* '())       ; Alist: (pc . buffer-descriptor)
(define *jit-bailout-handlers* '())   ; Alist: (label . continuation-or-handler)
(define *jit-stats-executed* 0)
(define *jit-stats-bailouts* 0)

;;; Reset JIT runtime state
(define (jit-runtime-reset!)
  (set! *jit-buffer-table* '())
  (set! *jit-bailout-handlers* '())
  (set! *jit-stats-executed* 0)
  (set! *jit-stats-bailouts* 0))

;;; Create a virtual JIT executable buffer descriptor for given PC
(define (make-jit-buffer pc lir-prog)
  (list 'jit-buffer
        (cons 'pc pc)
        (cons 'status *JIT-BUFFER-STATUS-WRITABLE*)
        (cons 'lir-prog lir-prog)
        (cons 'entry-point (string->symbol (string-append "jit_entry_" (symbol->string pc))))))

;;; Transition buffer permissions to EXECUTABLE (W^X principle)
(define (jit-buffer-make-executable! buf)
  (let ((status-entry (assq 'status (cdr buf))))
    (if status-entry
        (set-cdr! status-entry *JIT-BUFFER-STATUS-EXECUTABLE*))))

;;; Register a bailout / deoptimization continuation target
(define (register-bailout-handler! label handler)
  (set! *jit-bailout-handlers* (cons (cons label handler) *jit-bailout-handlers*)))

;;; Trigger a guard exit (deoptimize from JIT back to interpreter)
(define (trigger-bailout! label state)
  (set! *jit-stats-bailouts* (+ *jit-stats-bailouts* 1))
  (let ((handler-entry (assq label *jit-bailout-handlers*)))
    (if handler-entry
        ((cdr handler-entry) state)
        (error "Unregistered JIT bailout target:" label))))

;;; Register and install compiled LIR program for given PC
(define (install-jit-code! pc lir-prog)
  (let ((buf (make-jit-buffer pc lir-prog)))
    (jit-buffer-make-executable! buf)
    (set! *jit-buffer-table* (cons (cons pc buf) *jit-buffer-table*))
    buf))

;;; Lookup installed JIT code buffer
(define (lookup-jit-buffer pc)
  (let ((entry (assq pc *jit-buffer-table*)))
    (if entry (cdr entry) #f)))

;;; Dispatch and execute JIT loop
(define (dispatch-jit-loop pc initial-state)
  (let ((buf (lookup-jit-buffer pc)))
    (if (not buf)
        #f
        (begin
          (set! *jit-stats-executed* (+ *jit-stats-executed* 1))
          ;; Returns execution descriptor
          (list 'jit-executed pc initial-state)))))
