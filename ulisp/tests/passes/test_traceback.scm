;;; =======================================================================
;;; Unit Test Suite: Compiler Call Stack Traceback & Diagnostics (Issue #604)
;;; Conforms to DSN-33 Architecture Specification & Issue #604
;;; =======================================================================

(define *tb-tests-run* 0)
(define *tb-tests-passed* 0)

(define (assert-true label cond)
  (set! *tb-tests-run* (+ *tb-tests-run* 1))
  (if cond
      (begin
        (set! *tb-tests-passed* (+ *tb-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label) (newline)
        (error "Assertion failed:" label))))

(define (assert-equal label expected actual)
  (set! *tb-tests-run* (+ *tb-tests-run* 1))
  (if (equal? expected actual)
      (begin
        (set! *tb-tests-passed* (+ *tb-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(display "=======================================================\n")
(display " Starting Pass 604 (Call Stack Traceback) Test Suite\n")
(display "=======================================================\n")

;;; --- Group 1: Basic Call Frame Operations ---
(display "--- Group 1: Basic Call Frame Operations ---\n")

(reset-compiler-context!)
(assert-equal "initial stack empty" '() (current-call-stack))

;; When disabled (default), push/pop are zero-overhead no-ops
(disable-call-stack-trace!)
(assert-equal "tracing disabled by default" #f (call-stack-trace-enabled?))
(push-call-frame! 'test-fn '(test 1 2 3))
(assert-equal "push-call-frame does nothing when disabled" '() (current-call-stack))

;; Enable tracing
(enable-call-stack-trace!)
(assert-equal "tracing enabled" #t (call-stack-trace-enabled?))

(push-call-frame! 'outer-frame '(outer 42))
(assert-equal "stack has 1 frame" 1 (length (current-call-stack)))
(let ((fr (car (current-call-stack))))
  (assert-equal "frame name is outer-frame" 'outer-frame (car fr))
  (assert-equal "frame summary preserved" '(outer 42) (cdr fr)))

(push-call-frame! 'inner-frame '(inner 99))
(assert-equal "stack has 2 frames" 2 (length (current-call-stack)))
(assert-equal "top frame is inner-frame" 'inner-frame (caar (current-call-stack)))

(pop-call-frame!)
(assert-equal "stack has 1 frame after pop" 1 (length (current-call-stack)))
(assert-equal "top frame is outer-frame after pop" 'outer-frame (caar (current-call-stack)))

(reset-call-stack!)
(assert-equal "stack empty after reset" '() (current-call-stack))

;;; --- Group 2: with-call-frame Scoped Context ---
(display "--- Group 2: with-call-frame Scoped Context ---\n")

(reset-call-stack!)
(let ((res (with-call-frame 'func-a '(func-a 10)
             (lambda ()
               (assert-equal "func-a in stack" 1 (length (current-call-stack)))
               (with-call-frame 'func-b '(func-b 20)
                 (lambda ()
                   (assert-equal "func-b in stack" 2 (length (current-call-stack)))
                   (with-call-frame 'func-c '(func-c 30)
                     (lambda ()
                       (assert-equal "func-c in stack" 3 (length (current-call-stack)))
                       'completed-inner))))))))
  (assert-equal "with-call-frame returned expected value" 'completed-inner res)
  (assert-equal "stack unwound completely after with-call-frame" 0 (length (current-call-stack))))

;;; --- Group 3: Bounded Stack Depth Limit (Ring Buffer) ---
(display "--- Group 3: Bounded Stack Depth Limit ---\n")

(reset-call-stack!)
(let ((orig-limit (call-stack-depth-limit)))
  (set-call-stack-depth-limit! 5)
  (assert-equal "limit set to 5" 5 (call-stack-depth-limit))

  ;; Push 10 frames
  (let loop ((i 1))
    (if (<= i 10)
        (begin
          (push-call-frame! (string->symbol (string-append "frame-" (number->string i))) i)
          (loop (+ i 1)))))

  (assert-equal "stack clamped at depth limit 5" 5 (length (current-call-stack)))
  (assert-equal "most recent frame is frame-10" 'frame-10 (caar (current-call-stack)))

  ;; Restore original limit
  (set-call-stack-depth-limit! orig-limit)
  (assert-equal "limit restored to default 32" 32 (call-stack-depth-limit)))

;;; --- Group 4: Traceback Formatting ---
(display "--- Group 4: Traceback Formatting ---\n")

(reset-call-stack!)
(let ((empty-tb (format-call-stack-traceback (current-call-stack))))
  (assert-true "empty traceback mentions DEBUG=1"
               (string? empty-tb)))

(push-call-frame! 'pass-010-library '(forms))
(push-call-frame! 'pass-030-desugar '(ast))
(push-call-frame! 'lir-compile-function '(fn 'my-proc))
(push-call-frame! 'lir-compile-variable 'x)

(let ((tb-str (format-call-stack-traceback (current-call-stack))))
  (assert-true "traceback contains pass-010-library" (string? tb-str))
  (assert-true "captured stack has 4 frames" (= 4 (length (capture-call-stack)))))

;;; --- Group 5: Error Object Traceback Integration ---
(display "--- Group 5: Error Object Traceback Integration ---\n")

;; Error object without traceback
(let ((err-plain (make-error-object "standard error" '(10 20))))
  (assert-true "err-plain is error-object" (error-object? err-plain))
  (assert-equal "err-plain message" "standard error" (error-object-message err-plain))
  (assert-equal "err-plain irritants" '(10 20) (error-object-irritants err-plain))
  (assert-equal "err-plain traceback is empty list" '() (error-object-traceback err-plain)))

;; Error object with traceback
(let* ((captured (capture-call-stack))
       (err-with-tb (make-error-object-with-traceback "crash in compiler" '(foo bar) captured)))
  (assert-true "err-with-tb is error-object" (error-object? err-with-tb))
  (assert-equal "err-with-tb message" "crash in compiler" (error-object-message err-with-tb))
  ;; Irritants must exclude %traceback
  (assert-equal "err-with-tb irritants clean" '(foo bar) (error-object-irritants err-with-tb))
  (assert-equal "err-with-tb traceback matches captured" captured (error-object-traceback err-with-tb))
  (assert-equal "traceback length is 4" 4 (length (error-object-traceback err-with-tb))))

;;; --- Group 6: Recursive Safety & Context Reset ---
(display "--- Group 6: Recursive Safety & Context Reset ---\n")

(reset-compiler-context!)
(assert-equal "reset-compiler-context resets call stack" '() (current-call-stack))

(display "\n=======================================================\n")
(display " Test Suite Results: ")
(display *tb-tests-passed*)
(display " / ")
(display *tb-tests-run*)
(display " Passed\n")
(display "=======================================================\n")
