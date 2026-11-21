;;; =======================================================================
;;; ULisp JIT Annotations: Loop Merge Point & Type Guard Engine
;;; Conforms to DSN-33-05 §3 & §4, DSN-33-04 §6, and Issue #898
;;; Pure Scheme. Zero External Dependencies. Zero Shell Invocation.
;;; =======================================================================
;;; Provides:
;;; - Configuration: *jit-enabled*, *jit-max-trace-length*, *jit-max-guard-count*
;;; - Core Annotations: (jit-merge-point! pc state), (jit-guard-type! val type fail-k)
;;; - Type Predicate Dispatch: (%jit-val-matches-type? val type-sym)
;;; - Safe Deoptimization & Bailout Protocol (CWE-617 & CWE-400 mitigations)
;;; - Introspection API: jit-enabled?, set-jit-enabled!, jit-recording?, jit-compiled?
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Configuration & Security Hard Limits
;;; -----------------------------------------------------------------------

(define *jit-enabled* (cons #t '()))

;; CWE-400 Mitigation: Hard limits on trace expansion to prevent resource exhaustion
(define *jit-max-trace-length* 1000)
(define *jit-max-guard-count* 256)

(define (jit-enabled?)
  (car *jit-enabled*))

(define (set-jit-enabled! bool)
  (set-car! *jit-enabled* (if bool #t #f)))

;;; -----------------------------------------------------------------------
;;; 2. Type Predicate Engine for Dynamic Type Guards
;;; -----------------------------------------------------------------------

(define (%jit-val-matches-type? val type-sym)
  (case type-sym
    ((any) #t)
    ((fixnum integer int) (and (integer? val) (exact? val)))
    ((flonum float real)  (and (number? val) (inexact? val)))
    ((number num)         (number? val))
    ((string str)         (string? val))
    ((symbol sym)         (symbol? val))
    ((boolean bool)       (boolean? val))
    ((vector vec)         (vector? val))
    ((pair cons)          (pair? val))
    ((null empty-list)    (null? val))
    ((char character)     (char? val))
    ((bytevector bv)      (bytevector? val))
    ((procedure proc)     (procedure? val))
    (else
     ;; Custom record or tagged object check
     (if (and (pair? val) (eq? (car val) type-sym))
         #t
         #f))))

;;; -----------------------------------------------------------------------
;;; 3. Runtime Hook: %jit-merge-point-runtime
;;; -----------------------------------------------------------------------

(define (%jit-merge-point-runtime pc state-env)
  (if (not (jit-enabled?))
      #f
      (cond
        ;; Case 1: Loop has already been compiled into native trace
        ((lookup-compiled-trace pc)
         => (lambda (trace) trace))

        ;; Case 2: Currently in RECORDING mode
        ((eq? *tracer-state* *TRACER-STATE-RECORDING*)
         ;; CWE-400 check: Guard against runaway trace length
         (if (>= (length *current-trace-buffer*) *jit-max-trace-length*)
             (begin
               ;; Trace too long: abort recording safely to protect resources
               (tracer-reset!)
               #f)
             (if (equal? pc *current-recording-pc*)
                 ;; Full loop iteration completed! Finalize and return trace.
                 (finish-recording! pc)
                 ;; Intermediate backward branch or loop merge point within recording
                 (begin
                   (trace-record! '%merge pc state-env)
                   #f))))

        ;; Case 3: IDLE mode - hot loop iteration threshold counting
        ((eq? *tracer-state* *TRACER-STATE-IDLE*)
         (let ((cnt (inc-loop-count! pc)))
           (if (>= cnt *tracer-hot-threshold*)
               (begin
                 (start-recording! pc)
                 'started-recording)
               #f)))

        (else #f))))

;;; -----------------------------------------------------------------------
;;; 4. Runtime Hook: %jit-guard-type-runtime (CWE-617 Safe Deopt)
;;; -----------------------------------------------------------------------

(define (%jit-guard-type-runtime val type-sym fail-k)
  (if (not (jit-enabled?))
      val
      (if (%jit-val-matches-type? val type-sym)
          ;; Type matches expected speculation
          (begin
            (when (eq? *tracer-state* *TRACER-STATE-RECORDING*)
              ;; CWE-400 check: limit total guards per trace
              (let ((guard-count (let loop ((buf *current-trace-buffer*) (c 0))
                                   (cond ((null? buf) c)
                                         ((and (pair? (car buf)) (eq? (caar buf) '%guard))
                                          (loop (cdr buf) (+ c 1)))
                                         (else (loop (cdr buf) c))))))
                (if (>= guard-count *jit-max-guard-count*)
                    ;; Guard limit exceeded: abort recording
                    (tracer-reset!)
                    ;; Emit speculative guard instruction into active trace buffer
                    (trace-guard! type-sym val type-sym fail-k))))
            val)
          ;; Type mismatch: Speculation failed! Trigger Bailout (Deoptimization)
          (cond
            ((procedure? fail-k)
             (fail-k val))
            ((and (pair? fail-k) (procedure? (car fail-k)))
             ((car fail-k) val))
            (else
             ;; Fallback bailout token indicating deopt was taken
             (list 'jit-bailout-deopt type-sym val fail-k))))))

;;; -----------------------------------------------------------------------
;;; 5. Syntactic Macros: jit-merge-point! & jit-guard-type!
;;; -----------------------------------------------------------------------

;; Macro: (jit-merge-point! pc state-env)
;; Zero-overhead when JIT is disabled.
(define-syntax jit-merge-point!
  (syntax-rules ()
    ((jit-merge-point! pc state-env)
     (if (jit-enabled?)
         (%jit-merge-point-runtime pc state-env)
         #f))))

;; Macro: (jit-guard-type! val type-sym fail-k)
;; Transparently returns val when type matches, or invokes fail-k on mismatch.
(define-syntax jit-guard-type!
  (syntax-rules ()
    ((jit-guard-type! val type-sym fail-k)
     (if (jit-enabled?)
         (%jit-guard-type-runtime val type-sym fail-k)
         val))))

;; Procedure aliases for dynamic / higher-order usage
(define jit-merge-point %jit-merge-point-runtime)
(define jit-guard-type %jit-guard-type-runtime)

;;; -----------------------------------------------------------------------
;;; 6. Introspection and Lifecycle Helpers
;;; -----------------------------------------------------------------------

(define (jit-recording?)
  (eq? *tracer-state* *TRACER-STATE-RECORDING*))

(define (jit-compiled? pc)
  (if (lookup-compiled-trace pc) #t #f))

(define (jit-reset!)
  (tracer-reset!))

(define (jit-compiled-trace-count)
  (length *compiled-traces*))
