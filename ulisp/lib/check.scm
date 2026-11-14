;;; =======================================================================
;;; ULisp Standard Library: Lightweight Testing (SRFI 78)
;;; Conforms to DSN-33 Architecture Specification & Issue #820
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1. State Management & Modes
;; ---------------------------------------------------------------------

(define *check-mode* (box 'report-failed))
(define *check-passed-count* (box 0))
(define *check-failed-count* (box 0))
(define *check-total-count* (box 0))

(define (check-set-mode! mode)
  (if (memq mode '(off summary report-failed report))
      (set-box! *check-mode* mode)
      (error "check-set-mode!: invalid mode (expected off, summary, report-failed, report)" mode)))

(define (check-reset!)
  (set-box! *check-passed-count* 0)
  (set-box! *check-failed-count* 0)
  (set-box! *check-total-count* 0)
  #t)

;; ---------------------------------------------------------------------
;; §2. Reporting & Query Procedures
;; ---------------------------------------------------------------------

(define check-passed?
  (case-lambda
    (()
     (= (unbox *check-failed-count*) 0))
    ((expected-total-passed)
     (and (= (unbox *check-failed-count*) 0)
          (= (unbox *check-passed-count*) expected-total-passed)))))

(define (check-report)
  (let ((mode (unbox *check-mode*))
        (passed (unbox *check-passed-count*))
        (failed (unbox *check-failed-count*))
        (total (unbox *check-total-count*)))
    (if (not (eq? mode 'off))
        (begin
          (write-string ";; ")
          (if (= failed 0)
              (begin
                (write-string "All ")
                (write total)
                (write-string " checks correct.\n"))
              (begin
                (write-string "CHECKS FAILED: ")
                (write failed)
                (write-string " of ")
                (write total)
                (write-string " failed (")
                (write passed)
                (write-string " passed).\n")))
          (flush-output-port)))
    (= failed 0)))

;; ---------------------------------------------------------------------
;; §3. Core Check Syntax & Evaluation Engine
;; ---------------------------------------------------------------------

(define (%check-record expr-tree res passed? exp)
  (let ((mode (unbox *check-mode*)))
    (if (not (eq? mode 'off))
        (let ((real-passed? (if (and (pair? res) (eq? (car res) 'check-exception))
                                #f
                                (if passed? #t #f))))
          (set-box! *check-total-count* (+ (unbox *check-total-count*) 1))
          (if real-passed?
              (begin
                (set-box! *check-passed-count* (+ (unbox *check-passed-count*) 1))
                (if (eq? mode 'report)
                    (begin
                      (write-string "(check ")
                      (write expr-tree)
                      (write-string " => ")
                      (write res)
                      (write-string ") ; correct\n")
                      (flush-output-port)))
                (let ((runner (test-runner-current)))
                  (if runner
                      (begin
                        (test-result-alist! runner (list (cons 'test-name expr-tree)))
                        (%test-on-test-begin runner)
                        (test-result-set! runner 'expected-value exp)
                        (test-result-set! runner 'actual-value res)
                        (%test-on-test-end runner #t)
                        (%test-report-result)))))
              (begin
                (set-box! *check-failed-count* (+ (unbox *check-failed-count*) 1))
                (if (or (eq? mode 'report) (eq? mode 'report-failed))
                    (begin
                      (write-string "\n*** Check failed: ")
                      (write expr-tree)
                      (write-string "\n  Expected: ")
                      (write exp)
                      (write-string "\n  Actual:   ")
                      (if (and (pair? res) (eq? (car res) 'check-exception))
                          (begin
                            (write-string "EXCEPTION: ")
                            (write (cdr res)))
                          (write res))
                      (write-char #\newline)
                      (flush-output-port)))
                (let ((runner (test-runner-current)))
                  (if runner
                      (begin
                        (test-result-alist! runner (list (cons 'test-name expr-tree)))
                        (%test-on-test-begin runner)
                        (test-result-set! runner 'expected-value exp)
                        (test-result-set! runner 'actual-value res)
                        (%test-on-test-end runner #f)
                        (%test-report-result))))))
          real-passed?)
        #t)))

(define-syntax check
  (syntax-rules (=>)
    ((check expr => expected)
     (let ((exp expected))
       (let ((res (guard (ex (else (cons 'check-exception ex)))
                    expr)))
         (%check-record (quote expr) res (equal? exp res) exp))))
    ((check expr (=> equal-pred) expected)
     (let ((exp expected))
       (let ((res (guard (ex (else (cons 'check-exception ex)))
                    expr)))
         (%check-record (quote expr) res (equal-pred exp res) exp))))))

;; ---------------------------------------------------------------------
;; §4. Eager Comprehension Check (check-ec)
;; ---------------------------------------------------------------------

(define-syntax check-ec
  (syntax-rules (=> : :list :range)
    ((check-ec (: var from to) expr => expected)
     (let loop ((var from))
       (if (< var to)
           (begin
             (check expr => expected)
             (loop (+ var 1))))))
    ((check-ec (: var to) expr => expected)
     (check-ec (: var 0 to) expr => expected))
    ((check-ec (:list var lst) expr => expected)
     (let loop ((cur lst))
       (if (pair? cur)
           (let ((var (car cur)))
             (check expr => expected)
             (loop (cdr cur))))))
    ((check-ec (: var from to) expr (=> equal) expected)
     (let loop ((var from))
       (if (< var to)
           (begin
             (check expr (=> equal) expected)
             (loop (+ var 1))))))
    ((check-ec (: var to) expr (=> equal) expected)
     (check-ec (: var 0 to) expr (=> equal) expected))
    ((check-ec (:list var lst) expr (=> equal) expected)
     (let loop ((cur lst))
       (if (pair? cur)
           (let ((var (car cur)))
             (check expr (=> equal) expected)
             (loop (cdr cur))))))
    ((check-ec var lst expr => expected)
     (check-ec (:list var lst) expr => expected))
    ((check-ec var lst expr (=> equal) expected)
     (check-ec (:list var lst) expr (=> equal) expected))))
