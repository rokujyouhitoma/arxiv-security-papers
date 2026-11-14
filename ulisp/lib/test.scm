;;; =======================================================================
;;; ULisp Standard Library: Test Suites (SRFI 64)
;;; Conforms to DSN-33 Architecture Specification & Issue #819
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1. Test Runner Record Type & Accessors
;; ---------------------------------------------------------------------

(define-record-type <test-runner>
  (%test-runner-alloc)
  test-runner?
  (pass-count test-runner-pass-count test-runner-pass-count!)
  (fail-count test-runner-fail-count test-runner-fail-count!)
  (xpass-count test-runner-xpass-count test-runner-xpass-count!)
  (xfail-count test-runner-xfail-count test-runner-xfail-count!)
  (skip-count test-runner-skip-count test-runner-skip-count!)
  (total-count %test-runner-total-count %test-runner-total-count!)
  (count-list %test-runner-count-list %test-runner-count-list!)
  (run-list %test-runner-run-list %test-runner-run-list!)
  (skip-list %test-runner-skip-list %test-runner-skip-list!)
  (fail-list %test-runner-fail-list %test-runner-fail-list!)
  (skip-save %test-runner-skip-save %test-runner-skip-save!)
  (fail-save %test-runner-fail-save %test-runner-fail-save!)
  (group-stack test-runner-group-stack test-runner-group-stack!)
  (result-alist test-result-alist test-result-alist!)
  (aux-value test-runner-aux-value test-runner-aux-value!)
  (on-test-begin test-runner-on-test-begin test-runner-on-test-begin!)
  (on-test-end test-runner-on-test-end test-runner-on-test-end!)
  (on-group-begin test-runner-on-group-begin test-runner-on-group-begin!)
  (on-group-end test-runner-on-group-end test-runner-on-group-end!)
  (on-final test-runner-on-final test-runner-on-final!)
  (on-bad-count test-runner-on-bad-count test-runner-on-bad-count!)
  (on-bad-end-name test-runner-on-bad-end-name test-runner-on-bad-end-name!))

(define (test-runner-reset runner)
  (test-runner-pass-count! runner 0)
  (test-runner-fail-count! runner 0)
  (test-runner-xpass-count! runner 0)
  (test-runner-xfail-count! runner 0)
  (test-runner-skip-count! runner 0)
  (%test-runner-total-count! runner 0)
  (%test-runner-count-list! runner '())
  (%test-runner-run-list! runner #t)
  (%test-runner-skip-list! runner '())
  (%test-runner-fail-list! runner '())
  (%test-runner-skip-save! runner '())
  (%test-runner-fail-save! runner '())
  (test-runner-group-stack! runner '())
  (test-result-alist! runner '())
  (test-runner-aux-value! runner #f))

(define (test-runner-group-path runner)
  (reverse (test-runner-group-stack runner)))

;; ---------------------------------------------------------------------
;; §2. Default & Null Test Runners
;; ---------------------------------------------------------------------

(define (%test-null-callback runner) #f)

(define (test-runner-null)
  (let ((runner (%test-runner-alloc)))
    (test-runner-reset runner)
    (test-runner-on-group-begin! runner (lambda (r name count) #f))
    (test-runner-on-group-end! runner %test-null-callback)
    (test-runner-on-final! runner %test-null-callback)
    (test-runner-on-test-begin! runner %test-null-callback)
    (test-runner-on-test-end! runner %test-null-callback)
    (test-runner-on-bad-count! runner (lambda (r count expected) #f))
    (test-runner-on-bad-end-name! runner (lambda (r begin end) #f))
    runner))

(define (test-runner-simple)
  (let ((runner (%test-runner-alloc)))
    (test-runner-reset runner)
    (test-runner-on-group-begin! runner test-on-group-begin-simple)
    (test-runner-on-group-end! runner test-on-group-end-simple)
    (test-runner-on-final! runner test-on-final-simple)
    (test-runner-on-test-begin! runner test-on-test-begin-simple)
    (test-runner-on-test-end! runner test-on-test-end-simple)
    (test-runner-on-bad-count! runner test-on-bad-count-simple)
    (test-runner-on-bad-end-name! runner test-on-bad-end-name-simple)
    runner))

(define (test-runner-unified)
  (let ((runner (%test-runner-alloc)))
    (test-runner-reset runner)
    (test-runner-on-group-begin! runner test-on-group-begin-unified)
    (test-runner-on-group-end! runner test-on-group-end-unified)
    (test-runner-on-final! runner test-on-final-unified)
    (test-runner-on-test-begin! runner test-on-test-begin-unified)
    (test-runner-on-test-end! runner test-on-test-end-unified)
    (test-runner-on-bad-count! runner test-on-bad-count-simple)
    (test-runner-on-bad-end-name! runner test-on-bad-end-name-simple)
    runner))

(define test-runner-current (make-parameter #f))
(define test-runner-factory (make-parameter test-runner-unified))

(define (test-runner-get)
  (let ((r (test-runner-current)))
    (if (not r)
        (error "test-runner not initialized - test-begin missing?")
        r)))

(define (test-runner-create)
  ((test-runner-factory)))

;; ---------------------------------------------------------------------
;; §3. Simple Runner Callbacks & Output Formatting
;; ---------------------------------------------------------------------

(define (%test-verbose?)
  (let ((v (or (guard (ex (else #f)) (get-environment-variable "ULISP_TEST_VERBOSE"))
               (guard (ex (else #f)) (sys-getenv "ULISP_TEST_VERBOSE")))))
    (and (string? v)
         (not (string=? v ""))
         (not (string=? v "0")))))

(define (test-on-group-begin-unified runner suite-name count)
  (if (null? (test-runner-group-stack runner))
      (begin
        (test-runner-aux-value! runner suite-name)
        (display "=== [Test Suite: ")
        (display (if suite-name suite-name "Unnamed"))
        (display "] ===\n")
        (flush-output-port))
      (if (%test-verbose?)
          (begin
            (display "--- Group: ")
            (display (if suite-name suite-name "Subgroup"))
            (display " ---\n")
            (flush-output-port)))))

(define (test-on-group-end-unified runner)
  #f)

(define (test-on-test-begin-unified runner)
  #f)

(define (test-on-test-end-unified runner)
  (let ((kind (test-result-ref runner 'result-kind))
        (name (test-result-ref runner 'test-name #f))
        (verbose? (%test-verbose?)))
    (cond
      ((or (eq? kind 'fail) (eq? kind 'xpass))
       (let ((expected (test-result-ref runner 'expected-value #f))
             (actual (test-result-ref runner 'actual-value #f)))
         (display (if (eq? kind 'xpass) "  [XPASS] " "  [FAIL] "))
         (if name
             (display name)
             (begin
               (display "(test #")
               (display (%test-runner-total-count runner))
               (display ")")))
         (newline)
         (display "    Expected: ")
         (write expected)
         (newline)
         (display "    Actual:   ")
         (write actual)
         (newline)
         (flush-output-port)))
      ((eq? kind 'xfail)
       (if verbose?
           (begin
             (display "  [XFAIL] ")
             (if name (display name) (display "(unnamed)"))
             (newline)
             (flush-output-port))))
      ((eq? kind 'skip)
       (if verbose?
           (begin
             (display "  [SKIP] ")
             (if name (display name) (display "(unnamed)"))
             (newline)
             (flush-output-port))))
      ((eq? kind 'pass)
       (if verbose?
           (begin
             (display "  [PASS] ")
             (if name (display name) (display "(unnamed)"))
             (newline)
             (flush-output-port)))))))

(define (test-on-final-unified runner)
  (let* ((pass (test-runner-pass-count runner))
         (fail (test-runner-fail-count runner))
         (xfail (test-runner-xfail-count runner))
         (xpass (test-runner-xpass-count runner))
         (skip (test-runner-skip-count runner))
         (total (%test-runner-total-count runner))
         (suite (test-runner-aux-value runner)))
    (display "-------------------------------------------------------\n")
    (if (and (= fail 0) (= xpass 0))
        (display " [RESULT] ")
        (display " [FAILED] "))
    (display (if suite suite "Test Suite"))
    (display ": ")
    (display pass)
    (display " passed")
    (if (> fail 0)
        (begin (display ", ") (display fail) (display " failed")))
    (if (> xfail 0)
        (begin (display ", ") (display xfail) (display " expected failures")))
    (if (> xpass 0)
        (begin (display ", ") (display xpass) (display " unexpected successes")))
    (if (> skip 0)
        (begin (display ", ") (display skip) (display " skipped")))
    (display " (Total: ")
    (display total)
    (display ")\n")
    (display "-------------------------------------------------------\n")
    (flush-output-port)))

(define (test-on-group-begin-simple runner suite-name count)
  #f)

(define (test-on-group-end-simple runner)
  #f)

(define (%test-on-bad-count-write runner count expected-count)
  (display "*** Total number of tests was ")
  (display count)
  (display " but should be ")
  (display expected-count)
  (display ". ***\n")
  (display "*** Discrepancy indicates testsuite error or exceptions. ***\n")
  (flush-output-port))

(define (test-on-bad-count-simple runner count expected-count)
  (%test-on-bad-count-write runner count expected-count))

(define (test-on-bad-end-name-simple runner begin-name end-name)
  (display "test-end ")
  (display begin-name)
  (display " does not match test-begin ")
  (display end-name)
  (newline)
  (flush-output-port)
  (error "test-end name mismatch" begin-name end-name))

(define (%test-final-report-line count label)
  (if (> count 0)
      (begin
        (display label)
        (display count)
        (newline))))

(define (test-on-final-simple runner)
  (%test-final-report-line (test-runner-pass-count runner)
                           "# of expected passes      ")
  (%test-final-report-line (test-runner-xfail-count runner)
                           "# of expected failures    ")
  (%test-final-report-line (test-runner-xpass-count runner)
                           "# of unexpected successes ")
  (%test-final-report-line (test-runner-fail-count runner)
                           "# of unexpected failures  ")
  (%test-final-report-line (test-runner-skip-count runner)
                           "# of skipped tests        ")
  (flush-output-port))

(define (test-on-test-begin-simple runner)
  #f)

(define (test-on-test-end-simple runner)
  (let ((kind (test-result-ref runner 'result-kind)))
    (if (or (eq? kind 'fail) (eq? kind 'xpass))
        (let ((name (test-result-ref runner 'test-name #f))
              (expected (test-result-ref runner 'expected-value #f))
              (actual (test-result-ref runner 'actual-value #f)))
          (display (if (eq? kind 'xpass) "XPASS" "FAIL"))
          (if name
              (begin
                (display " ")
                (display name)))
          (newline)
          (display "  expected:")
          (write expected)
          (newline)
          (display "    actual:")
          (write actual)
          (newline)
          (flush-output-port)))))

;; ---------------------------------------------------------------------
;; §4. Result Properties & Status Queries
;; ---------------------------------------------------------------------

(define test-result-ref
  (case-lambda
    ((runner pname)
     (let ((p (assq pname (test-result-alist runner))))
       (if p (cdr p) #f)))
    ((runner pname default)
     (let ((p (assq pname (test-result-alist runner))))
       (if p (cdr p) default)))))

(define (test-result-set! runner pname value)
  (let* ((alist (test-result-alist runner))
         (p (assq pname alist)))
    (if p
        (set-cdr! p value)
        (test-result-alist! runner (cons (cons pname value) alist)))))

(define (test-result-clear runner)
  (test-result-alist! runner '()))

(define (test-result-remove runner pname)
  (let* ((alist (test-result-alist runner))
         (filtered (let loop ((lst alist))
                     (cond
                       ((null? lst) '())
                       ((eq? (caar lst) pname) (loop (cdr lst)))
                       (else (cons (car lst) (loop (cdr lst))))))))
    (test-result-alist! runner filtered)))

(define test-result-kind
  (case-lambda
    (()
     (let ((r (test-runner-current)))
       (if r (test-result-ref r 'result-kind) #f)))
    ((runner)
     (test-result-ref runner 'result-kind))))

(define test-passed?
  (case-lambda
    (()
     (let ((r (test-runner-get)))
       (memq (test-result-ref r 'result-kind) '(pass xpass))))
    ((runner)
     (memq (test-result-ref runner 'result-kind) '(pass xpass)))))

(define (test-runner-test-name runner)
  (test-result-ref runner 'test-name ""))

;; ---------------------------------------------------------------------
;; §5. Specifiers & Filtering (Skip, Expect-Fail, Matchers)
;; ---------------------------------------------------------------------

(define (%test-specifier-matches spec runner)
  (spec runner))

(define (%test-any-specifier-matches spec-list runner)
  (let loop ((lst spec-list))
    (cond
      ((null? lst) #f)
      ((%test-specifier-matches (car lst) runner) #t)
      (else (loop (cdr lst))))))

(define (%test-should-execute runner)
  (let ((run (%test-runner-run-list runner)))
    (cond
      ((or (not (or (eq? run #t) (%test-any-specifier-matches run runner)))
           (%test-any-specifier-matches (%test-runner-skip-list runner) runner))
       (test-result-set! runner 'result-kind 'skip)
       #f)
      ((%test-any-specifier-matches (%test-runner-fail-list runner) runner)
       (test-result-set! runner 'result-kind 'xfail)
       'xfail)
      (else #t))))

(define (%test-match-nth n count)
  (let ((i (cons 0 '())))
    (lambda (runner)
      (set-car! i (+ (car i) 1))
      (and (>= (car i) n) (< (car i) (+ n count))))))

(define-syntax test-match-nth
  (syntax-rules ()
    ((test-match-nth n)
     (%test-match-nth n 1))
    ((test-match-nth n count)
     (%test-match-nth n count))))

(define (test-match-name name)
  (lambda (runner)
    (equal? name (test-runner-test-name runner))))

(define (%test-as-specifier specifier)
  (cond
    ((procedure? specifier) specifier)
    ((integer? specifier) (%test-match-nth 1 specifier))
    ((string? specifier) (test-match-name specifier))
    (else (error "not a valid test specifier" specifier))))

(define (%test-match-all-proc pred-list)
  (lambda (runner)
    (let loop ((lst pred-list))
      (cond
        ((null? lst) #t)
        (((car lst) runner) (loop (cdr lst)))
        (else #f)))))

(define-syntax test-match-all
  (syntax-rules ()
    ((test-match-all pred ...)
     (%test-match-all-proc (list (%test-as-specifier pred) ...)))))

(define (%test-match-any-proc pred-list)
  (lambda (runner)
    (let loop ((lst pred-list))
      (cond
        ((null? lst) #f)
        (((car lst) runner) #t)
        (else (loop (cdr lst)))))))

(define-syntax test-match-any
  (syntax-rules ()
    ((test-match-any pred ...)
     (%test-match-any-proc (list (%test-as-specifier pred) ...)))))

(define-syntax test-skip
  (syntax-rules ()
    ((test-skip pred ...)
     (let ((runner (test-runner-get)))
       (%test-runner-skip-list! runner
                                (cons (test-match-all pred ...)
                                      (%test-runner-skip-list runner)))))))

(define-syntax test-expect-fail
  (syntax-rules ()
    ((test-expect-fail pred ...)
     (let ((runner (test-runner-get)))
       (%test-runner-fail-list! runner
                                (cons (test-match-all pred ...)
                                      (%test-runner-fail-list runner)))))))

;; ---------------------------------------------------------------------
;; §6. Grouping & Test Execution Core
;; ---------------------------------------------------------------------

(define (%test-begin suite-name count)
  (if (not (test-runner-current))
      (test-runner-current (test-runner-create)))
  (let ((runner (test-runner-current)))
    ((test-runner-on-group-begin runner) runner suite-name count)
    (%test-runner-skip-save! runner
                             (cons (%test-runner-skip-list runner)
                                   (%test-runner-skip-save runner)))
    (%test-runner-fail-save! runner
                             (cons (%test-runner-fail-list runner)
                                   (%test-runner-fail-save runner)))
    (%test-runner-count-list! runner
                              (cons (cons (%test-runner-total-count runner)
                                          count)
                                    (%test-runner-count-list runner)))
    (test-runner-group-stack! runner (cons suite-name
                                           (test-runner-group-stack runner)))))

(define-syntax test-begin
  (syntax-rules ()
    ((test-begin suite-name)
     (%test-begin suite-name #f))
    ((test-begin suite-name count)
     (%test-begin suite-name count))))

(define (%test-end suite-name)
  (let* ((r (test-runner-get))
         (groups (test-runner-group-stack r)))
    (if (null? groups)
        (error "test-end not in a group"))
    (if (and suite-name (not (equal? suite-name (car groups))))
        ((test-runner-on-bad-end-name r) r suite-name (car groups)))
    (let* ((count-list (%test-runner-count-list r))
           (expected-count (cdar count-list))
           (saved-count (caar count-list))
           (group-count (- (%test-runner-total-count r) saved-count)))
      (if (and expected-count (not (= expected-count group-count)))
          ((test-runner-on-bad-count r) r group-count expected-count))
      ((test-runner-on-group-end r) r)
      (test-runner-group-stack! r (cdr (test-runner-group-stack r)))
      (%test-runner-skip-list! r (car (%test-runner-skip-save r)))
      (%test-runner-skip-save! r (cdr (%test-runner-skip-save r)))
      (%test-runner-fail-list! r (car (%test-runner-fail-save r)))
      (%test-runner-fail-save! r (cdr (%test-runner-fail-save r)))
      (%test-runner-count-list! r (cdr count-list))
      (if (null? (test-runner-group-stack r))
          ((test-runner-on-final r) r)))))

(define-syntax test-end
  (syntax-rules ()
    ((test-end)
     (%test-end #f))
    ((test-end suite-name)
     (%test-end suite-name))))

(define-syntax test-group
  (syntax-rules ()
    ((test-group suite-name body ...)
     (let ((r (test-runner-current)))
       (test-result-alist! r (list (cons 'test-name suite-name)))
       (if (%test-should-execute r)
           (dynamic-wind
             (lambda () (test-begin suite-name))
             (lambda () body ...)
             (lambda () (test-end suite-name))))))))

(define-syntax test-group-with-cleanup
  (syntax-rules ()
    ((test-group-with-cleanup suite-name form cleanup-form)
     (test-group suite-name
       (dynamic-wind
         (lambda () #f)
         (lambda () form)
         (lambda () cleanup-form))))
    ((test-group-with-cleanup suite-name form1 form2 rest ...)
     (test-group-with-cleanup suite-name (begin form1 form2) rest ...))))

(define-syntax test-with-runner
  (syntax-rules ()
    ((test-with-runner runner form ...)
     (parameterize ((test-runner-current runner))
       form ...))))

(define test-apply
  (case-lambda
    ((first)
     (if (test-runner? first)
         (test-with-runner first #t)
         (let ((r (test-runner-current)))
           (if r
               (let ((run-list (%test-runner-run-list r)))
                 (%test-runner-run-list! r (reverse run-list))
                 (first))
               (let ((new-r (test-runner-create)))
                 (test-with-runner new-r (first))
                 ((test-runner-on-final new-r) new-r))))))
    ((first second)
     (let ((suite second))
       (if (test-runner? first)
           (test-with-runner first (suite))
           (let ((r (test-runner-current)))
             (if r
                 (let ((run-list (%test-runner-run-list r)))
                   (%test-runner-run-list!
                    r
                    (if (eq? run-list #t) (list first) (cons first run-list)))
                   (suite)
                   (%test-runner-run-list! r run-list))
                 (let ((new-r (test-runner-create)))
                   (test-with-runner new-r
                     (first)
                     (suite))
                   ((test-runner-on-final new-r) new-r)))))))
    ((first second . rest)
     (let ((suites (cons second rest)))
       (if (test-runner? first)
           (test-with-runner first
             (for-each (lambda (s) (s)) suites))
           (let ((r (test-runner-current)))
             (if r
                 (let ((run-list (%test-runner-run-list r)))
                   (%test-runner-run-list!
                    r
                    (if (eq? run-list #t) (list first) (cons first run-list)))
                   (for-each (lambda (s) (s)) suites)
                   (%test-runner-run-list! r run-list))
                 (let ((new-r (test-runner-create)))
                   (test-with-runner new-r
                     (first)
                     (for-each (lambda (s) (s)) suites))
                   ((test-runner-on-final new-r) new-r)))))))))

(define (test-read-eval-string string)
  (let* ((port (open-input-string string))
         (form (port-read port)))
    (if (eof-object? (port-read-char port))
        (eval form (environment '(scheme base)))
        (error "test-read-eval-string: not at eof" string))))

;; ---------------------------------------------------------------------
;; §7. Assertion Macros & Evaluation Engine
;; ---------------------------------------------------------------------

(define (%test-report-result)
  (let* ((r (test-runner-get))
         (result-kind (test-result-kind r)))
    (case result-kind
      ((pass)
       (test-runner-pass-count! r (+ 1 (test-runner-pass-count r))))
      ((fail)
       (test-runner-fail-count! r (+ 1 (test-runner-fail-count r))))
      ((xpass)
       (test-runner-xpass-count! r (+ 1 (test-runner-xpass-count r))))
      ((xfail)
       (test-runner-xfail-count! r (+ 1 (test-runner-xfail-count r))))
      (else
       (test-runner-skip-count! r (+ 1 (test-runner-skip-count r)))))
    (%test-runner-total-count! r (+ 1 (%test-runner-total-count r)))
    ((test-runner-on-test-end r) r)))

(define (%test-on-test-begin r)
  (%test-should-execute r)
  ((test-runner-on-test-begin r) r)
  (not (eq? 'skip (test-result-ref r 'result-kind))))

(define (%test-on-test-end r result)
  (test-result-set! r 'result-kind
                    (if (eq? (test-result-ref r 'result-kind) 'xfail)
                        (if result 'xpass 'xfail)
                        (if result 'pass 'fail))))

(define-syntax %test-comp1body
  (syntax-rules ()
    ((%test-comp1body r expr)
     (let ()
       (if (%test-on-test-begin r)
           (let ()
             (test-result-set! r 'expected-value #t)
             (let ((res (guard (ex (else #f)) expr)))
               (test-result-set! r 'actual-value res)
               (%test-on-test-end r (if res #t #f)))))
       (%test-report-result)))))

(define-syntax %test-comp2body
  (syntax-rules ()
    ((%test-comp2body r comp expected expr)
     (let ()
       (if (%test-on-test-begin r)
           (let ((exp expected))
             (test-result-set! r 'expected-value exp)
             (let ((res (guard (ex (else (list 'unhandled-exception ex)))
                          expr)))
               (test-result-set! r 'actual-value res)
               (let ((compared (if (and (pair? res) (eq? (car res) 'unhandled-exception))
                                   #f
                                   (comp exp res))))
                 (%test-on-test-end r compared)))))
       (%test-report-result)))))

(define (%test-approximate= error)
  (lambda (expected actual)
    (let ((diff (magnitude (- actual expected))))
      (<= diff error))))

(define-syntax test-assert
  (syntax-rules ()
    ((test-assert tname test-expression)
     (let ((r (test-runner-get)))
       (test-result-alist! r (list (cons 'test-name tname)))
       (%test-comp1body r test-expression)))
    ((test-assert test-expression)
     (let ((r (test-runner-get)))
       (test-result-alist! r '())
       (%test-comp1body r test-expression)))))

(define-syntax %test-comp2
  (syntax-rules ()
    ((%test-comp2 comp tname expected expr)
     (let ((r (test-runner-get)))
       (test-result-alist! r (list (cons 'test-name tname)))
       (%test-comp2body r comp expected expr)))
    ((%test-comp2 comp expected expr)
     (let ((r (test-runner-get)))
       (test-result-alist! r '())
       (%test-comp2body r comp expected expr)))))

(define-syntax test-equal
  (syntax-rules ()
    ((test-equal . rest)
     (%test-comp2 equal? . rest))))

(define-syntax test-eqv
  (syntax-rules ()
    ((test-eqv . rest)
     (%test-comp2 eqv? . rest))))

(define-syntax test-eq
  (syntax-rules ()
    ((test-eq . rest)
     (%test-comp2 eq? . rest))))

(define-syntax test-approximate
  (syntax-rules ()
    ((test-approximate tname expected expr error)
     (%test-comp2 (%test-approximate= error) tname expected expr))
    ((test-approximate expected expr error)
     (%test-comp2 (%test-approximate= error) expected expr))))

(define-syntax %test-error-body
  (syntax-rules ()
    ((%test-error-body r etype expr)
     (let ()
       (if (%test-on-test-begin r)
           (let ()
             (test-result-set! r 'expected-error etype)
             (let ((caught (guard (ex (else
                                       (cond
                                         ((procedure? etype) (etype ex))
                                         ((eq? etype #t) #t)
                                         ((error-object? ex) #t)
                                         (else #t))))
                             (let ((v expr))
                               'no-error-raised))))
               (test-result-set! r 'actual-value caught)
               (%test-on-test-end r (not (eq? caught 'no-error-raised))))))
       (%test-report-result)))))

(define-syntax test-error
  (syntax-rules ()
    ((test-error name etype expr)
     (let ((r (test-runner-get)))
       (test-result-alist! r (list (cons 'test-name name)))
       (%test-error-body r etype expr)))
    ((test-error arg1 expr)
     (let ((r (test-runner-get))
           (a1 arg1))
       (if (string? a1)
           (begin
             (test-result-alist! r (list (cons 'test-name a1)))
             (%test-error-body r #t expr))
           (begin
             (test-result-alist! r '())
             (%test-error-body r a1 expr)))))
    ((test-error expr)
     (let ((r (test-runner-get)))
       (test-result-alist! r '())
       (%test-error-body r #t expr)))))
