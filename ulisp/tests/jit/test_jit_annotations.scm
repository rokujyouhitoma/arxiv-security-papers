;;; =======================================================================
;;; Unit & Integration Test Suite: JIT Loop Merge Point & Guard Annotations
;;; Conforms to DSN-33-05 §3 & §4, DSN-33-04 §6, and Issue #898
;;; Pure Scheme. Zero External Dependencies.
;;; =======================================================================

(test-begin "JIT Loop Merge Point & Guard Annotations (Issue #898)")

;;; -----------------------------------------------------------------------
;;; Group 1: Zero-Overhead Mode & JIT Disable Flag
;;; -----------------------------------------------------------------------
(print-group "--- Group 1: Zero-Overhead Mode when JIT Disabled ---")

(set-jit-enabled! #f)
(assert-false "1.1 jit-enabled? returns #f when disabled" (jit-enabled?))

;; When JIT is disabled, jit-merge-point! must immediately return #f without tracking
(assert-false "1.2 jit-merge-point! returns #f when disabled"
              (jit-merge-point! 'disabled-loop-1 '(a b)))

;; When JIT is disabled, jit-guard-type! must pass through value transparently without checking
(let ((fail-invoked #f))
  (let ((res (jit-guard-type! "not-a-number" 'fixnum (lambda (v) (set! fail-invoked #t) v))))
    (assert-equal "1.3 jit-guard-type! returns value untouched when disabled" "not-a-number" res)
    (assert-false "1.4 fail-k was not invoked when disabled" fail-invoked)))

(set-jit-enabled! #t)
(assert-true "1.5 jit-enabled? re-enabled" (jit-enabled?))

;;; -----------------------------------------------------------------------
;;; Group 2: jit-merge-point! Iteration Counter & State Machine
;;; -----------------------------------------------------------------------
(print-group "--- Group 2: jit-merge-point! Counter & State Machine ---")

(jit-reset!)
(set-hot-threshold! 3)

;; Iterations 1 & 2: Below hot threshold
(assert-equal "2.1 Iteration 1 returns #f" #f (jit-merge-point! 'test-loop-pc '(x y)))
(assert-equal "2.2 Loop count is 1" 1 (get-loop-count 'test-loop-pc))
(assert-false "2.3 Not yet recording" (jit-recording?))

(assert-equal "2.4 Iteration 2 returns #f" #f (jit-merge-point! 'test-loop-pc '(x y)))
(assert-equal "2.5 Loop count is 2" 2 (get-loop-count 'test-loop-pc))
(assert-false "2.6 Not yet recording" (jit-recording?))

;; Iteration 3: Reaches hot threshold -> transitions to RECORDING
(assert-equal "2.7 Iteration 3 triggers recording" 'started-recording (jit-merge-point! 'test-loop-pc '(x y)))
(assert-true "2.8 Now in RECORDING mode" (jit-recording?))
(assert-equal "2.9 Tracer state is RECORDING" 'RECORDING *tracer-state*)

;; Subsequent loop cycle with same PC -> finishes recording and transitions to COMPILED
(let ((trace (jit-merge-point! 'test-loop-pc '(x y))))
  (assert-true "2.10 Finished trace is a pair" (pair? trace))
  (assert-equal "2.11 Root tag is %trace-loop" '%trace-loop (car trace))
  (assert-false "2.12 No longer recording" (jit-recording?))
  (assert-true "2.13 PC is marked compiled" (jit-compiled? 'test-loop-pc))
  (assert-equal "2.14 Compiled trace count is 1" 1 (jit-compiled-trace-count)))

;; Subsequent invocation on compiled PC returns compiled trace directly
(let ((cached-trace (jit-merge-point! 'test-loop-pc '(x y))))
  (assert-true "2.15 Cached trace returned" (pair? cached-trace))
  (assert-equal "2.16 Tag is %trace-loop" '%trace-loop (car cached-trace)))

;;; -----------------------------------------------------------------------
;;; Group 3: jit-guard-type! Speculation & Trace Emission
;;; -----------------------------------------------------------------------
(print-group "--- Group 3: jit-guard-type! Speculation & Trace Emission ---")

(jit-reset!)
(set-hot-threshold! 1)

;; Start recording
(jit-merge-point! 'guard-test-loop '(n str vec))
(assert-true "3.1 In recording mode for guard test" (jit-recording?))

;; Guard operations on various matching types
(let ((val-fix (jit-guard-type! 42 'fixnum (lambda (v) 'fail)))
      (val-flt (jit-guard-type! 3.14 'flonum (lambda (v) 'fail)))
      (val-str (jit-guard-type! "security" 'string (lambda (v) 'fail)))
      (val-sym (jit-guard-type! 'threat 'symbol (lambda (v) 'fail)))
      (val-vec (jit-guard-type! #(1 2 3) 'vector (lambda (v) 'fail)))
      (val-pr  (jit-guard-type! '(a . b) 'pair (lambda (v) 'fail)))
      (val-bln (jit-guard-type! #t 'boolean (lambda (v) 'fail))))

  (assert-equal "3.2 fixnum matches" 42 val-fix)
  (assert-equal "3.3 flonum matches" 3.14 val-flt)
  (assert-equal "3.4 string matches" "security" val-str)
  (assert-equal "3.5 symbol matches" 'threat val-sym)
  (assert-equal "3.6 vector matches" #(1 2 3) val-vec)
  (assert-equal "3.7 pair matches" '(a . b) val-pr)
  (assert-equal "3.8 boolean matches" #t val-bln))

;; Verify accumulated guards in trace buffer
(let ((guards (filter (lambda (inst) (and (pair? inst) (eq? (car inst) '%guard)))
                      *current-trace-buffer*)))
  (assert-equal "3.9 Seven %guard instructions emitted" 7 (length guards)))

;; Finish trace
(jit-merge-point! 'guard-test-loop '(n str vec))

;;; -----------------------------------------------------------------------
;;; Group 4: Guard Failure & Safe Deoptimization Bailout (CWE-617)
;;; -----------------------------------------------------------------------
(print-group "--- Group 4: Guard Failure & Safe Deopt Bailout ---")

(jit-reset!)
(set-hot-threshold! 1)
(jit-merge-point! 'deopt-loop '(x))

;; Test 4.1: Bailout via failure procedure
(let ((deopt-invoked #f)
      (deopt-val #f))
  (let ((res (jit-guard-type! "not-a-number" 'fixnum
                              (lambda (actual-val)
                                (set! deopt-invoked #t)
                                (set! deopt-val actual-val)
                                'bailout-to-interpreter))))
    (assert-true "4.1 Bailout procedure was invoked" deopt-invoked)
    (assert-equal "4.2 Bailout received actual mismatch value" "not-a-number" deopt-val)
    (assert-equal "4.3 Guard return value is bailout result" 'bailout-to-interpreter res)))

;; Test 4.2: Bailout without procedure (fallback token)
(let ((res (jit-guard-type! #(vector) 'string 'bailout-tag-99)))
  (assert-true "4.4 Fallback bailout returns structured token" (pair? res))
  (assert-equal "4.5 Token head is jit-bailout-deopt" 'jit-bailout-deopt (car res))
  (assert-equal "4.6 Token specifies expected type" 'string (cadr res))
  (assert-equal "4.7 Token holds mismatch value" #(vector) (caddr res)))

;;; -----------------------------------------------------------------------
;;; Group 5: Runaway Trace Length Guard (CWE-400 DoS Protection)
;;; -----------------------------------------------------------------------
(print-group "--- Group 5: Runaway Trace Guard (CWE-400 Protection) ---")

(jit-reset!)
(set-hot-threshold! 1)
(jit-merge-point! 'runaway-loop '(i))
(assert-true "5.1 Recording started" (jit-recording?))

;; Emit instructions up to the limit
(let loop ((count 0))
  (if (>= count *jit-max-trace-length*)
      #t
      (begin
        (trace-record! '%add 'r 'r 1)
        (loop (+ count 1)))))

;; Attempting another operation must trigger runaway guard and safely abort
(trace-record! '%add 'r 'r 1)
(assert-false "5.2 Runaway trace automatically aborted and reset" (jit-recording?))
(assert-equal "5.3 Tracer state returned to IDLE" 'IDLE *tracer-state*)

;;; -----------------------------------------------------------------------
;;; Group 6: Auto-Instrumentation & E2E Loop Execution
;;; -----------------------------------------------------------------------
(print-group "--- Group 6: Auto-Instrumentation & E2E Loop ---")

(jit-reset!)
(set-hot-threshold! 2)

;; Unannotated countdown function
(define sample-source
  '(define (run-counter n acc)
     (if (<= n 0)
         acc
         (run-counter (- n 1) (+ acc n)))))

(let ((instrumented (auto-instrument-form sample-source)))
  (assert-true "6.1 Form instrumented" (pair? instrumented))
  (assert-equal "6.2 Define preserved" 'define (car instrumented))
  (let ((body (cddr instrumented)))
    (assert-true "6.3 Body has injected merge point"
                 (already-instrumented? body))))

(display "\n[PASS] All JIT Loop Merge Point & Guard Annotation tests passed successfully!\n\n")
