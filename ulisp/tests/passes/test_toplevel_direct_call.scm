;;; =======================================================================
;;; ULisp Test Suite: Top-level Separate Pipeline & %direct-call Optimization
;;; Issue #539
;;; =======================================================================

(define *total-tests* (cons 0 '()))
(define *passed-tests* (cons 0 '()))

(define (test-assert name condition)
  (set-car! *total-tests* (+ (car *total-tests*) 1))
  (if condition
      (begin
        (set-car! *passed-tests* (+ (car *passed-tests*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (newline)
        (exit 1))))

(display "=======================================================")
(newline)
(display " Starting Pass 05 Top-level Direct Call Test Suite (#539)")
(newline)
(display "=======================================================")
(newline)

;; Test 1: Desugaring generates %program without hoisting into letrec
(let* ((input '((define (square x) (* x x))
                (define (cube x) (* x (square x)))
                (cube 3)))
       (rewritten (rewrite-top-level input))
       (desugared (desugar-all rewritten)))
  (test-assert "rewrite-top-level produces %program"
               (and (pair? rewritten) (eq? (car rewritten) '%program)))
  (test-assert "%program has 2 definitions"
               (= (length (cadr rewritten)) 2))
  (test-assert "desugar-all preserves %program"
               (and (pair? desugared) (eq? (car desugared) '%program))))

;; Test 2: Closure conversion produces direct %function definitions and %direct-call
(let* ((prog '(%program ((define square (lambda (x) (* x x)))
                         (define cube (lambda (x) (* x (square x)))))
                        (cube 3)))
       (cc (closure-convert prog))
       (funcs (cadr cc))
       (main (caddr cc)))
  (test-assert "closure-convert produces %program with lifted functions"
               (and (pair? cc) (eq? (car cc) '%program) (= (length funcs) 2)))
  (test-assert "main-expr calls cube via %direct-call"
               (and (pair? main) (eq? (car main) '%direct-call)))
  ;; Inspect cube body for direct-call to square
  (let* ((cube-fn (car (cdr funcs))) ;; second function
         (cube-body (cadddr cube-fn)))
    (test-assert "cube body contains direct-call to square"
                 (let has-dc? ((e cube-body))
                   (cond
                     ((not (pair? e)) #f)
                     ((eq? (car e) '%direct-call) #t)
                     (else (or (has-dc? (car e)) (has-dc? (cdr e)))))))))

;; Test 3: Top-level variable definition produces %global-set! and %global-ref
(let* ((prog '(%program ((define counter 0)
                         (define inc (lambda () (+ counter 1))))
                        (inc)))
       (cc (closure-convert prog))
       (main (caddr cc)))
  (test-assert "main initializes top-level variable via %global-set!"
               (let has-gset? ((e main))
                 (cond
                   ((not (pair? e)) #f)
                   ((eq? (car e) '%global-set!) #t)
                   (else (or (has-gset? (car e)) (has-gset? (cdr e))))))))

;; Test 4: Escaping top-level function instantiates static closure (%make-closure)
(let* ((prog '(%program ((define inc (lambda (x) (+ x 1))))
                        (let ((f inc))
                          (f 10))))
       (cc (closure-convert prog))
       (main (caddr cc)))
  (test-assert "escaped top-level fn references %make-closure"
               (let has-mc? ((e main))
                 (cond
                   ((not (pair? e)) #f)
                   ((memq (car e) '(%make-closure %make-closure-env)) #t)
                   (else (or (has-mc? (car e)) (has-mc? (cdr e))))))))

(newline)
(display "=======================================================")
(newline)
(display " Top-level Direct Call Tests: ")
(display (car *passed-tests*))
(display "/")
(display (car *total-tests*))
(display " passed.")
(newline)
(display "=======================================================")
(newline)
