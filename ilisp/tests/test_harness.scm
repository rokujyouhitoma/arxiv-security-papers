;;;; =========================================================================
;;;; ILISP Portable Test Harness & Conformance Runner
;;;; =========================================================================
;;;;
;;;; Project: ILISP (arxiv-security-papers)
;;;; Copyright (C) 2026 Project ILISP Authors
;;;; License: MIT License
;;;;
;;;; Provides test assertion macros (test, test-assert, test-error, test-values),
;;;; precision comparison, and result aggregation for test suites.
;;;; =========================================================================

(define *test-passes* 0)
(define *test-failures* 0)
(define *test-errors* 0)
(define *test-failure-log* '())
(define *test-group-stack* '())

(define (test-begin . name)
  (let ((group-name (if (null? name) "unnamed" (car name))))
    (set! *test-group-stack* (cons group-name *test-group-stack*))))

(define (test-end . name)
  (if (not (null? *test-group-stack*))
      (set! *test-group-stack* (cdr *test-group-stack*))))

(define (test-approx-equal? a b)
  (cond
    ((and (number? a) (number? b))
     (or (= a b)
         (and (nan? a) (nan? b))
         (and (or (inexact? a) (inexact? b))
              (< (abs (- a b)) 0.0001))))
    ((and (pair? a) (pair? b))
     (and (test-approx-equal? (car a) (car b))
          (test-approx-equal? (cdr a) (cdr b))))
    ((and (vector? a) (vector? b))
     (and (= (vector-length a) (vector-length b))
          (let loop ((i 0))
            (if (= i (vector-length a))
                #t
                (and (test-approx-equal? (vector-ref a i) (vector-ref b i))
                     (loop (+ i 1)))))))
    (else (equal? a b))))

(define-macro (test . args)
  (let* ((has-name (and (pair? (cdr args)) (pair? (cddr args))))
         (name (if has-name (car args) #f))
         (expect (if has-name (cadr args) (car args)))
         (expr (if has-name (caddr args) (cadr args))))
    `(guard (exn
             (else
              (set! *test-errors* (+ *test-errors* 1))
              (set! *test-failure-log*
                    (cons (list 'ERROR ',expr exn) *test-failure-log*))
              (display "[ERROR] ")
              (write ',expr)
              (display " -> EXN: ")
              (write exn)
              (newline)))
       (let ((expected-val ,expect)
             (actual-val ,expr))
         (if (test-approx-equal? expected-val actual-val)
             (set! *test-passes* (+ *test-passes* 1))
             (begin
               (set! *test-failures* (+ *test-failures* 1))
               (set! *test-failure-log*
                     (cons (list 'FAIL ',expr expected-val actual-val) *test-failure-log*))
               (display "[FAIL] ")
               (write ',expr)
               (display " => expected: ")
               (write expected-val)
               (display ", got: ")
               (write actual-val)
               (newline)))))))

(define-macro (test-assert . args)
  (let* ((has-name (pair? (cdr args)))
         (expr (if has-name (cadr args) (car args))))
    `(guard (exn
             (else
              (set! *test-errors* (+ *test-errors* 1))
              (set! *test-failure-log*
                    (cons (list 'ERROR-ASSERT ',expr exn) *test-failure-log*))
              (display "[ERROR in assert] ")
              (write ',expr)
              (display " -> EXN: ")
              (write exn)
              (newline)))
       (let ((res ,expr))
         (if res
             (set! *test-passes* (+ *test-passes* 1))
             (begin
               (set! *test-failures* (+ *test-failures* 1))
               (set! *test-failure-log*
                     (cons (list 'FAIL-ASSERT ',expr) *test-failure-log*))
               (display "[FAIL assert] ")
               (write ',expr)
               (newline)))))))

(define-macro (test-error . args)
  (let* ((has-name (pair? (cdr args)))
         (expr (if has-name (cadr args) (car args))))
    `(let ((caught #f))
       (guard (exn
               (else (set! caught #t)))
         ,expr)
       (if caught
           (set! *test-passes* (+ *test-passes* 1))
           (begin
             (set! *test-failures* (+ *test-failures* 1))
             (set! *test-failure-log*
                   (cons (list 'FAIL-EXPECTED-ERROR ',expr) *test-failure-log*))
             (display "[FAIL expected error] ")
             (write ',expr)
             (newline))))))

(define-macro (test-values . args)
  (let* ((has-name (and (pair? (cdr args)) (pair? (cddr args))))
         (name (if has-name (car args) #f))
         (expect-form (if has-name (cadr args) (car args)))
         (expr (if has-name (caddr args) (cadr args))))
    `(guard (exn
             (else
              (set! *test-errors* (+ *test-errors* 1))
              (set! *test-failure-log*
                    (cons (list 'ERROR-VALUES ',expr exn) *test-failure-log*))
              (display "[ERROR in values] ")
              (write ',expr)
              (display " -> EXN: ")
              (write exn)
              (newline)))
       (let ((expected (call-with-values (lambda () ,expect-form) list))
             (actual (call-with-values (lambda () ,expr) list)))
         (if (test-approx-equal? expected actual)
             (set! *test-passes* (+ *test-passes* 1))
             (begin
               (set! *test-failures* (+ *test-failures* 1))
               (set! *test-failure-log*
                     (cons (list 'FAIL-VALUES ',expr expected actual) *test-failure-log*))
               (display "[FAIL values] ")
               (write ',expr)
               (display " => expected: ")
               (write expected)
               (display ", got: ")
               (write actual)
               (newline)))))))

(define (test-report-summary)
  (list (cons 'passes *test-passes*)
        (cons 'failures *test-failures*)
        (cons 'errors *test-errors*)
        (cons 'log (reverse *test-failure-log*))))
