;;; =======================================================================
;;; ULisp First-Class Continuations (call/cc) & dynamic-wind Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #540
;;; =======================================================================

(define (equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (pair? a) (pair? b))
     (and (equal? (car a) (car b))
          (equal? (cdr a) (cdr b))))
    ((and (string? a) (string? b))
     (string=? a b))
    (else #f)))

(define (test name expected actual)
  (if (equal? expected actual)
      (begin
        (write-string "  [PASS] ")
        (write-string name)
        (write-char #\newline)
        (flush-output-port)
        #t)
      (begin
        (write-string "  [FAIL] ")
        (write-string name)
        (write-string " - Expected: ")
        (write-string (if (symbol? expected) (symbol->string expected) "val"))
        (write-char #\newline)
        (flush-output-port)
        (exit 1))))

(define (make-box val) (cons val '()))
(define (box-ref b) (car b))
(define (box-set! b val) (set-car! b val))

(write-string "=== Running ULisp First-Class call/cc & dynamic-wind Tests ===\n")

;;; --- Test 1: Simple Escape Continuation ---
(write-string "--- Test 1: Simple Escape Continuation ---\n")
(test "call/cc escape aborts pending addition"
      41
      (call/cc (lambda (k) (+ 1 (k 41)))))

(test "call/cc normal return without invocation"
      42
      (call/cc (lambda (k) 42)))

(test "call/cc nested in arithmetic expression"
      15
      (+ 10 (call/cc (lambda (k) (+ 100 (k 5))))))

;;; --- Test 2: Multi-shot Reentrancy ---
(write-string "--- Test 2: Multi-shot Reentrancy ---\n")
(let* ((saved-k-box (make-box #f))
       (counter-box (make-box 0))
       (val (call/cc (lambda (k)
                       (box-set! saved-k-box k)
                       10))))
  (box-set! counter-box (+ (box-ref counter-box) 1))
  (let ((cnt (box-ref counter-box)))
    (cond
      ((= cnt 1)
       (test "first run returns 10" 10 val)
       ((box-ref saved-k-box) 100))
      ((= cnt 2)
       (test "re-entry with 100 returns 100" 100 val)
       ((box-ref saved-k-box) 200))
      ((= cnt 3)
       (test "second re-entry with 200 returns 200" 200 val)
       #t))))

;;; --- Test 3: dynamic-wind Basic Evaluation ---
(write-string "--- Test 3: dynamic-wind Basic Evaluation ---\n")
(let* ((log-box (make-box '()))
       (res (dynamic-wind
              (lambda () (box-set! log-box (cons 'before (box-ref log-box))))
              (lambda () (box-set! log-box (cons 'thunk (box-ref log-box))) 777)
              (lambda () (box-set! log-box (cons 'after (box-ref log-box)))))))
  (test "dynamic-wind returns thunk result" 777 res)
  (test "before ran first" 'before (car (cdr (cdr (box-ref log-box)))))
  (test "thunk ran second" 'thunk (car (cdr (box-ref log-box))))
  (test "after ran third" 'after (car (box-ref log-box))))

;;; --- Test 4: dynamic-wind Unwinding on Escape ---
(write-string "--- Test 4: dynamic-wind Unwinding on Escape ---\n")
(let* ((log-box (make-box '()))
       (res (call/cc
              (lambda (k)
                (dynamic-wind
                  (lambda () (box-set! log-box (cons 'b1 (box-ref log-box))))
                  (lambda ()
                    (dynamic-wind
                      (lambda () (box-set! log-box (cons 'b2 (box-ref log-box))))
                      (lambda () (k 888))
                      (lambda () (box-set! log-box (cons 'a2 (box-ref log-box))))))
                  (lambda () (box-set! log-box (cons 'a1 (box-ref log-box)))))))))
  (test "escape returns target value" 888 res)
  (test "inner after ran on escape" 'a2 (car (cdr (box-ref log-box))))
  (test "outer after ran on escape" 'a1 (car (box-ref log-box))))

;;; --- Test 5: dynamic-wind Re-entry Rewinding ---
(write-string "--- Test 5: dynamic-wind Re-entry Rewinding ---\n")
(let* ((log-box (make-box '()))
       (saved-k-box (make-box #f))
       (counter-box (make-box 0))
       (val (dynamic-wind
              (lambda () (box-set! log-box (cons 'b-in (box-ref log-box))))
              (lambda ()
                (let ((v (call/cc (lambda (k) (box-set! saved-k-box k) 1))))
                  (box-set! log-box (cons v (box-ref log-box)))
                  v))
              (lambda () (box-set! log-box (cons 'a-out (box-ref log-box)))))))
  (box-set! counter-box (+ (box-ref counter-box) 1))
  (let ((cnt (box-ref counter-box)))
    (cond
      ((= cnt 1)
       (test "first run result is 1" 1 val)
       ((box-ref saved-k-box) 2))
      ((= cnt 2)
       (test "re-entry result is 2" 2 val)
       (test "log has 6 entries after re-entry" 6 (length (box-ref log-box)))))))

;;; --- Test 6: call/cc with Multiple Values (Issue #538 integration) ---
(write-string "--- Test 6: call/cc with Multiple Values ---\n")
(let ((sum (call-with-values
             (lambda ()
               (call/cc (lambda (k) (k (values 10 20)))))
             (lambda (a b) (+ a b)))))
  (test "call/cc passes multiple values to call-with-values" 30 sum))

(let ((sum (call-with-values
             (lambda ()
               (call/cc (lambda (k) (k (values 1 2 3)))))
             (lambda (a b c) (+ a (+ b c))))))
  (test "call/cc passes 3 multiple values" 6 sum))

;;; --- Test 7: Coroutine Generator ---
(write-string "--- Test 7: Coroutine Generator ---\n")
(let* ((yield-k-box (make-box #f))
       (return-k-box (make-box #f))
       (next (lambda ()
               (call/cc (lambda (k)
                          (box-set! return-k-box k)
                          (let ((yk (box-ref yield-k-box)))
                            (if yk
                                (yk #t)
                                (let loop ((i 10))
                                  (if (<= i 30)
                                      (begin
                                        (call/cc (lambda (new-yk)
                                                   (box-set! yield-k-box new-yk)
                                                   (let ((rk (box-ref return-k-box)))
                                                     (rk i))))
                                        (loop (+ i 10)))
                                      (let ((rk (box-ref return-k-box)))
                                        (rk 'done)))))))))))
  (test "coroutine first item is 10" 10 (next))
  (test "coroutine second item is 20" 20 (next))
  (test "coroutine third item is 30" 30 (next))
  (test "coroutine finished" 'done (next)))

(write-string "=== All First-Class call/cc & dynamic-wind Tests Complete ===\n")
