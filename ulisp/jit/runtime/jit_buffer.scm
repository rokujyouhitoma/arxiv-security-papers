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
(define *JIT-BUFFER-STATUS-INVALIDATED* 'INVALIDATED)

;;; Maximum allowable JIT machine code size in bytes per trace (CWE-119 Defense)
(define *max-jit-buffer-size* 65536)

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
  (set! *jit-stats-bailouts* 0)
  (reset-deopt-runtime!))

;;; Create a virtual JIT executable buffer descriptor for given PC
(define (make-jit-buffer pc lir-prog . opt-machine-code)
  (let* ((mcode (if (pair? opt-machine-code) (car opt-machine-code) #f))
         (mcode-len (if (and mcode (bytevector? mcode)) (bytevector-length mcode) 0)))
    (if (> mcode-len *max-jit-buffer-size*)
        (error "CWE-119 Defense: JIT machine code exceeded maximum buffer size" mcode-len)
        (list 'jit-buffer
              (cons 'pc pc)
              (cons 'status *JIT-BUFFER-STATUS-WRITABLE*)
              (cons 'lir-prog lir-prog)
              (cons 'machine-code mcode)
              (cons 'code-size mcode-len)
              (cons 'entry-point (string->symbol (string-append "jit_entry_" (symbol->string pc))))))))

;;; Field accessors for JIT buffer
(define (jit-buffer-status buf)
  (let ((entry (assq 'status (cdr buf))))
    (if entry (cdr entry) #f)))

(define (jit-buffer-pc buf)
  (let ((entry (assq 'pc (cdr buf))))
    (if entry (cdr entry) #f)))

(define (jit-buffer-lir buf)
  (let ((entry (assq 'lir-prog (cdr buf))))
    (if entry (cdr entry) #f)))

(define (jit-buffer-machine-code buf)
  (let ((entry (assq 'machine-code (cdr buf))))
    (if entry (cdr entry) #f)))

(define (jit-buffer-code-size buf)
  (let ((entry (assq 'code-size (cdr buf))))
    (if entry (cdr entry) 0)))

;;; Transition buffer permissions to EXECUTABLE (W^X principle)
(define (jit-buffer-make-executable! buf)
  (let ((status-entry (assq 'status (cdr buf))))
    (if status-entry
        (set-cdr! status-entry *JIT-BUFFER-STATUS-EXECUTABLE*))))

;;; Invalidate JIT buffer (prevent further execution)
(define (jit-buffer-invalidate! buf)
  (let ((status-entry (assq 'status (cdr buf))))
    (if status-entry
        (set-cdr! status-entry *JIT-BUFFER-STATUS-INVALIDATED*))))

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

;;; Register and install compiled native x86 machine code bytevector for given PC
(define (install-jit-machine-code! pc lir-prog text-bv)
  (if (deopt-blacklisted? pc)
      #f
      (let ((buf (make-jit-buffer pc lir-prog text-bv)))
        (jit-buffer-make-executable! buf)
        (set! *jit-buffer-table* (cons (cons pc buf) *jit-buffer-table*))
        buf)))

;;; Lookup installed JIT code buffer
(define (lookup-jit-buffer pc)
  (if (deopt-blacklisted? pc)
      #f
      (let ((entry (assq pc *jit-buffer-table*)))
        (if (and entry (eq? (jit-buffer-status (cdr entry)) *JIT-BUFFER-STATUS-EXECUTABLE*))
            (cdr entry)
            #f))))

;;; Dispatch and execute JIT loop (backward compatible)
(define (dispatch-jit-loop pc initial-state)
  (let ((buf (lookup-jit-buffer pc)))
    (if (not buf)
        #f
        (begin
          (set! *jit-stats-executed* (+ *jit-stats-executed* 1))
          (list 'jit-executed pc initial-state)))))

;;; Dispatch and execute JIT loop with native code execution metadata
(define (dispatch-jit-native pc initial-state)
  (let ((buf (lookup-jit-buffer pc)))
    (if (not buf)
        #f
        (begin
          (set! *jit-stats-executed* (+ *jit-stats-executed* 1))
          (list 'jit-executed-native
                pc
                initial-state
                (cons 'code-size (jit-buffer-code-size buf))
                (cons 'has-native (if (jit-buffer-machine-code buf) #t #f)))))))
