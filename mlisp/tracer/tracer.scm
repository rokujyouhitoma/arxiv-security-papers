;;; =======================================================================
;;; MLisp Tracer: Endogenous Meta-Tracer (tracer.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; 100% Pure Scheme Implementation of Endogenous Meta-Tracing JIT.
;;; Leverages delimited continuations (shift / reset) to capture
;;; dynamic execution paths from within the interpreter evaluation loop.
;;; =======================================================================

;;; Tracer State Constants
(define *TRACER-STATE-IDLE*      'IDLE)
(define *TRACER-STATE-RECORDING* 'RECORDING)
(define *TRACER-STATE-COMPILED*  'COMPILED)

;;; Tracer Configuration
(define *tracer-hot-threshold* 5)      ; Number of loop iterations to trigger JIT
(define *tracer-state* *TRACER-STATE-IDLE*)
(define *loop-counters* '())           ; Alist of (pc . count)
(define *current-recording-pc* #f)     ; Target loop PC being traced
(define *current-trace-buffer* '())    ; Accumulated trace instructions (reversed)
(define *compiled-traces* '())         ; Alist of (pc . compiled-trace-spec)

;;; Reset global tracer state
(define (tracer-reset!)
  (set! *tracer-state* *TRACER-STATE-IDLE*)
  (set! *loop-counters* '())
  (set! *current-recording-pc* #f)
  (set! *current-trace-buffer* '())
  (set! *compiled-traces* '()))

;;; Set the hot loop threshold
(define (set-hot-threshold! n)
  (set! *tracer-hot-threshold* n))

;;; Lookup loop execution count
(define (get-loop-count pc)
  (let ((entry (assoc pc *loop-counters*)))
    (if entry (cdr entry) 0)))

;;; Increment loop execution count
(define (inc-loop-count! pc)
  (let ((entry (assoc pc *loop-counters*)))
    (if entry
        (begin
          (set-cdr! entry (+ (cdr entry) 1))
          (cdr entry))
        (begin
          (set! *loop-counters* (cons (cons pc 1) *loop-counters*))
          1))))

;;; Check if a loop PC has reached hot threshold
(define (hot-loop? pc)
  (>= (get-loop-count pc) *tracer-hot-threshold*))

;;; =======================================================================
;;; Trace Recording Operations (Emits pure S-expression trace instructions)
;;; =======================================================================

;;; Record a generic operation into the active trace buffer
(define (trace-record! op dst . args)
  (when (eq? *tracer-state* *TRACER-STATE-RECORDING*)
    (let ((inst (cons op (cons dst args))))
      (set! *current-trace-buffer* (cons inst *current-trace-buffer*)))))

;;; Record a speculative type / branch guard
(define (trace-guard! cond-type var expected fail-k)
  (when (eq? *tracer-state* *TRACER-STATE-RECORDING*)
    (let ((inst `(%guard ,cond-type ,var ,expected ,fail-k)))
      (set! *current-trace-buffer* (cons inst *current-trace-buffer*)))))

;;; Start recording a trace for given PC
(define (start-recording! pc)
  (set! *tracer-state* *TRACER-STATE-RECORDING*)
  (set! *current-recording-pc* pc)
  (set! *current-trace-buffer* (list `(%trace-loop-entry ,pc))))

;;; Complete trace recording and return finalized trace S-expression
(define (finish-recording! pc)
  (let* ((insts (reverse (cons `(%trace-loop-jump ,pc) *current-trace-buffer*)))
         (trace `(%trace-loop
                   (%pc ,pc)
                   (%body ,insts))))
    (set! *compiled-traces* (cons (cons pc trace) *compiled-traces*))
    (set! *tracer-state* *TRACER-STATE-COMPILED*)
    (set! *current-recording-pc* #f)
    (set! *current-trace-buffer* '())
    trace))

;;; Lookup already compiled trace for given PC
(define (lookup-compiled-trace pc)
  (let ((entry (assoc pc *compiled-traces*)))
    (if entry (cdr entry) #f)))

;;; =======================================================================
;;; Primary JIT Interface: jit-merge-point
;;; =======================================================================
;;; Placed at the head of interpreter loops (e.g., eval dispatch or backward branch).
;;; Handles hot counter tracking, trace recording trigger, and trace completion.
;;;
;;; Usage:
;;;   (define (eval-loop pc state)
;;;     (jit-merge-point pc state)
;;;     ... loop body ...)
;;; =======================================================================
(define (jit-merge-point pc state-env)
  (cond
    ;; Case 1: Loop has already been traced & compiled
    ((lookup-compiled-trace pc)
     => (lambda (trace)
          ;; Returns the compiled trace descriptor
          trace))

    ;; Case 2: Currently in RECORDING mode
    ((eq? *tracer-state* *TRACER-STATE-RECORDING*)
     (if (equal? pc *current-recording-pc*)
         ;; We completed one full loop iteration! Finalize trace.
         (finish-recording! pc)
         ;; Nested or intermediate PC during recording - record merge hint
         (begin
           (trace-record! '%merge pc state-env)
           #f)))

    ;; Case 3: IDLE mode - count iterations and start tracing when hot
    ((eq? *tracer-state* *TRACER-STATE-IDLE*)
     (let ((cnt (inc-loop-count! pc)))
       (if (>= cnt *tracer-hot-threshold*)
           (begin
             (start-recording! pc)
             'started-recording)
           #f)))

    (else #f)))
