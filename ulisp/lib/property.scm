;;; =======================================================================
;;; ULisp Standard Library: Property Testing (SRFI 252)
;;; Conforms to DSN-33 Architecture Specification & Issue #821
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1. Deterministic PRNG & Seed Management
;; ---------------------------------------------------------------------

(define *property-random-seed* (box 123456789))

(define (property-random-seed-set! seed)
  (let ((s (if (= seed 0)
               123456789
               (if (< seed 0) (- 0 seed) seed))))
    (set-box! *property-random-seed* s)
    s))

(define (property-random-seed-get)
  (unbox *property-random-seed*))

(define (%property-bitwise-xor a b)
  (- (bitwise-ior a b) (bitwise-and a b)))

(define (%property-next-random!)
  (let* ((seed (unbox *property-random-seed*))
         ;; Marsaglia Xorshift32 on 31-bit positive integers
         (x1 (%property-bitwise-xor seed (bitwise-and (* seed 8192) 2147483647)))
         (x2 (%property-bitwise-xor x1 (quotient x1 131072)))
         (x3 (%property-bitwise-xor x2 (bitwise-and (* x2 32) 2147483647)))
         (next (if (= x3 0) 123456789 x3)))
    (set-box! *property-random-seed* next)
    next))

(define (%property-random-range low high)
  (if (= low high)
      low
      (let* ((lo (if (< low high) low high))
             (hi (if (< low high) high low))
             (range (+ (- hi lo) 1)))
        (+ lo (modulo (%property-next-random!) range)))))

(define (%property-random-boolean)
  (= (modulo (%property-next-random!) 2) 0))

;; ---------------------------------------------------------------------
;; §2. Built-in Type Generators (SRFI 252 & SRFI 158)
;; ---------------------------------------------------------------------

(define (boolean-generator)
  (lambda () (%property-random-boolean)))

(define char-generator
  (case-lambda
    (() (char-generator #\space #\~))
    ((min-c max-c)
     (let ((lo (char->integer min-c))
           (hi (char->integer max-c)))
       (lambda ()
         (integer->char (%property-random-range lo hi)))))))

(define string-generator
  (case-lambda
    (() (string-generator (char-generator) 16))
    ((c-gen) (string-generator c-gen 16))
    ((c-gen max-len)
     (lambda ()
       (let* ((cap (if (< max-len 0) 0 (if (> max-len 32) 32 max-len)))
              (len (%property-random-range 0 cap))
              (s (make-string len)))
         (let loop ((i 0))
           (if (< i len)
               (begin
                 (string-set! s i (c-gen))
                 (loop (+ i 1)))
               s)))))))

(define (%property-ident-char-generator)
  (let ((chars "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-*/"))
    (lambda ()
      (string-ref chars (%property-random-range 0 (- (string-length chars) 1))))))

(define symbol-generator
  (case-lambda
    (() (symbol-generator 8))
    ((max-len)
     (let ((c-gen (%property-ident-char-generator))
           (init-chars "abcdefghijklmnopqrstuvwxyz"))
       (lambda ()
         (let* ((cap (if (< max-len 1) 1 (if (> max-len 32) 32 max-len)))
                (len (%property-random-range 1 cap))
                (s (make-string len)))
           (string-set! s 0 (string-ref init-chars (%property-random-range 0 (- (string-length init-chars) 1))))
           (let loop ((i 1))
             (if (< i len)
                 (begin
                   (string-set! s i (c-gen))
                   (loop (+ i 1)))
                 (string->symbol s)))))))))

(define bytevector-generator
  (case-lambda
    (() (bytevector-generator 16))
    ((max-len)
     (lambda ()
       (let* ((cap (if (< max-len 0) 0 (if (> max-len 32) 32 max-len)))
              (len (%property-random-range 0 cap))
              (bv (make-bytevector len)))
         (let loop ((i 0))
           (if (< i len)
               (begin
                 (bytevector-u8-set! bv i (%property-random-range 0 255))
                 (loop (+ i 1)))
               bv)))))))

(define exact-integer-generator
  (case-lambda
    (() (exact-integer-generator -1000 1000))
    ((low high)
     (let ((edge-cases (list 0 1 -1 low high)))
       (lambda ()
         ;; 15% edge case bias
         (if (< (%property-random-range 0 99) 15)
             (let ((idx (%property-random-range 0 (- (length edge-cases) 1))))
               (list-ref edge-cases idx))
             (%property-random-range low high)))))))

(define (exact-rational-generator)
  (let ((int-gen (exact-integer-generator -1000 1000)))
    (lambda ()
      (let ((num (int-gen))
            (den (let loop ()
                   (let ((d (int-gen)))
                     (if (= d 0) (loop) d)))))
        (/ num den)))))

(define (exact-complex-generator)
  (let ((int-gen (exact-integer-generator -1000 1000)))
    (lambda ()
      (make-rectangular (int-gen) (int-gen)))))

(define (exact-real-generator)
  (let ((int-gen (exact-integer-generator -1000 1000))
        (rat-gen (exact-rational-generator)))
    (lambda ()
      (if (%property-random-boolean)
          (int-gen)
          (rat-gen)))))

(define (exact-number-generator)
  (let ((real-gen (exact-real-generator))
        (cplx-gen (exact-complex-generator)))
    (lambda ()
      (if (%property-random-boolean)
          (real-gen)
          (cplx-gen)))))

(define (inexact-real-generator)
  (let ((int-gen (exact-integer-generator -10000 10000)))
    (lambda ()
      (exact->inexact (/ (int-gen) 100)))))

(define (inexact-integer-generator)
  (let ((int-gen (exact-integer-generator -1000 1000)))
    (lambda ()
      (exact->inexact (int-gen)))))

(define (inexact-rational-generator)
  (inexact-real-generator))

(define (inexact-complex-generator)
  (let ((r-gen (inexact-real-generator)))
    (lambda ()
      (make-rectangular (r-gen) (r-gen)))))

(define (inexact-number-generator)
  (let ((r-gen (inexact-real-generator))
        (c-gen (inexact-complex-generator)))
    (lambda ()
      (if (%property-random-boolean)
          (r-gen)
          (c-gen)))))

(define (pair-generator car-gen cdr-gen)
  (lambda ()
    (cons (car-gen) (cdr-gen))))

(define list-generator
  (case-lambda
    ((elem-gen) (list-generator elem-gen 16))
    ((elem-gen max-len)
     (lambda ()
       (let* ((cap (if (< max-len 0) 0 (if (> max-len 32) 32 max-len)))
              (len (%property-random-range 0 cap)))
         (let loop ((i 0) (acc '()))
           (if (< i len)
               (loop (+ i 1) (cons (elem-gen) acc))
               acc)))))))

(define vector-generator
  (case-lambda
    ((elem-gen) (vector-generator elem-gen 16))
    ((elem-gen max-len)
     (lambda ()
       (let* ((cap (if (< max-len 0) 0 (if (> max-len 32) 32 max-len)))
              (len (%property-random-range 0 cap))
              (vec (make-vector len)))
         (let loop ((i 0))
           (if (< i len)
               (begin
                 (vector-set! vec i (elem-gen))
                 (loop (+ i 1)))
               vec)))))))

(define sexpr-generator
  (case-lambda
    (() (sexpr-generator 4))
    ((max-depth)
     (let ((sym-gen (symbol-generator 6))
           (int-gen (exact-integer-generator -100 100))
           (bool-gen (boolean-generator))
           (str-gen (string-generator (char-generator #\a #\z) 6)))
       (define (gen-atom)
         (case (%property-random-range 0 3)
           ((0) (sym-gen))
           ((1) (int-gen))
           ((2) (bool-gen))
           (else (str-gen))))
       (define (gen-expr depth)
         (if (or (<= depth 0) (< (%property-random-range 0 99) 45))
             (gen-atom)
             (let ((len (%property-random-range 0 4)))
               (let loop ((i 0) (acc '()))
                 (if (< i len)
                     (loop (+ i 1) (cons (gen-expr (- depth 1)) acc))
                     acc)))))
       (lambda ()
         (gen-expr max-depth))))))

;; ---------------------------------------------------------------------
;; §3. Property Testing Execution Engine
;; ---------------------------------------------------------------------

(define (%test-property-eval prop args)
  (guard (ex (else (cons 'property-exception ex)))
    (apply prop args)))

(define (%test-property-report-fail name iter seed args res)
  (write-string "\n*** Property test failed: ")
  (display name)
  (write-string "\n  Iteration:      ")
  (display iter)
  (write-string "\n  Seed:           ")
  (display seed)
  (write-string "\n  Counterexample: ")
  (write args)
  (write-string "\n  Result:         ")
  (write res)
  (newline)
  (flush-output-port))

(define (%test-property-core name prop gen-list runs expect-kind expected-type)
  (let ((runner (test-runner-current)))
    (if runner
        (begin
          (test-result-alist! runner (list (cons 'test-name name)))
          (%test-on-test-begin runner))))
  (if (eq? expect-kind 'skip)
      (let ((runner (test-runner-current)))
        (if runner
            (begin
              (%test-on-test-end runner #t)
              (test-runner-skip-count! runner (+ (test-runner-skip-count runner) 1))
              (%test-report-result)))
        #t)
      (let ((initial-seed (property-random-seed-get)))
        (let loop ((i 1))
          (if (> i runs)
              ;; All iterations completed successfully
              (let ((passed? (if (or (eq? expect-kind 'pass)
                                     (eq? expect-kind 'xfail)
                                     (eq? expect-kind 'error)
                                     (eq? expect-kind 'error-type))
                                 #t
                                 #f)))
                (let ((runner (test-runner-current)))
                  (if runner
                      (if (eq? expect-kind 'xfail)
                          (begin
                            ;; Unexpected success for expect-fail -> XPASS
                            (test-result-set! runner 'result-kind 'xpass)
                            (test-runner-xpass-count! runner (+ (test-runner-xpass-count runner) 1))
                            (%test-on-test-end runner #t)
                            (%test-report-result))
                          (begin
                            (test-result-set! runner 'result-kind (if passed? 'pass 'fail))
                            (if passed?
                                (test-runner-pass-count! runner (+ (test-runner-pass-count runner) 1))
                                (test-runner-fail-count! runner (+ (test-runner-fail-count runner) 1)))
                            (%test-on-test-end runner passed?)
                            (%test-report-result)))))
                passed?)
              ;; Next iteration
              (let* ((args (map (lambda (g) (g)) gen-list))
                     (res (%test-property-eval prop args)))
                (cond
                  ;; Normal evaluation returned value (no exception)
                  ((not (and (pair? res) (eq? (car res) 'property-exception)))
                   (if (eq? expect-kind 'error)
                       ;; Expected exception, but got normal value -> FAIL
                       (begin
                         (%test-property-report-fail name i initial-seed args "Expected exception, but returned normal value")
                         (let ((runner (test-runner-current)))
                           (if runner
                               (begin
                                 (test-result-set! runner 'result-kind 'fail)
                                 (test-result-set! runner 'counterexample args)
                                 (test-result-set! runner 'random-seed initial-seed)
                                 (test-runner-fail-count! runner (+ (test-runner-fail-count runner) 1))
                                 (%test-on-test-end runner #f)
                                 (%test-report-result))))
                         #f)
                       (if res
                           ;; Truthy result -> iteration passed
                           (loop (+ i 1))
                           ;; Falsy result -> FAIL
                           (if (eq? expect-kind 'xfail)
                               ;; Expected failure -> XFAIL
                               (let ((runner (test-runner-current)))
                                 (if runner
                                     (begin
                                       (test-result-set! runner 'result-kind 'xfail)
                                       (test-result-set! runner 'counterexample args)
                                       (test-result-set! runner 'random-seed initial-seed)
                                       (test-runner-xfail-count! runner (+ (test-runner-xfail-count runner) 1))
                                       (%test-on-test-end runner #t)
                                       (%test-report-result)))
                                 #t)
                               ;; Unexpected failure -> FAIL
                               (begin
                                 (%test-property-report-fail name i initial-seed args #f)
                                 (let ((runner (test-runner-current)))
                                   (if runner
                                       (begin
                                         (test-result-set! runner 'result-kind 'fail)
                                         (test-result-set! runner 'counterexample args)
                                         (test-result-set! runner 'random-seed initial-seed)
                                         (test-runner-fail-count! runner (+ (test-runner-fail-count runner) 1))
                                         (%test-on-test-end runner #f)
                                         (%test-report-result))))
                                 #f)))))
                  ;; Exception was captured
                  (else
                   (let ((ex (cdr res)))
                     (if (or (eq? expect-kind 'error)
                             (and (eq? expect-kind 'error-type)
                                  (or (eq? expected-type #t)
                                      (equal? expected-type ex))))
                         ;; Exception was expected! Continue iteration.
                         (loop (+ i 1))
                         ;; Exception was NOT expected -> FAIL
                         (if (eq? expect-kind 'xfail)
                             ;; Expected failure -> XFAIL
                             (let ((runner (test-runner-current)))
                               (if runner
                                   (begin
                                     (test-result-set! runner 'result-kind 'xfail)
                                     (test-result-set! runner 'counterexample args)
                                     (test-result-set! runner 'random-seed initial-seed)
                                     (test-runner-xfail-count! runner (+ (test-runner-xfail-count runner) 1))
                                     (%test-on-test-end runner #t)
                                     (%test-report-result)))
                               #t)
                             (begin
                               (%test-property-report-fail name i initial-seed args (cons 'exception ex))
                               (let ((runner (test-runner-current)))
                                 (if runner
                                     (begin
                                       (test-result-set! runner 'result-kind 'fail)
                                       (test-result-set! runner 'counterexample args)
                                       (test-result-set! runner 'random-seed initial-seed)
                                       (test-runner-fail-count! runner (+ (test-runner-fail-count runner) 1))
                                       (%test-on-test-end runner #f)
                                       (%test-report-result))))
                               #f))))))))))))

(define test-property
  (case-lambda
    ((prop gen-list)
     (%test-property-core "test-property" prop gen-list 100 'pass #f))
    ((a b c)
     (if (procedure? a)
         (%test-property-core "test-property" a b c 'pass #f)
         (%test-property-core a b c 100 'pass #f)))
    ((name prop gen-list runs)
     (%test-property-core name prop gen-list runs 'pass #f))))

(define test-property-expect-fail
  (case-lambda
    ((prop gen-list)
     (%test-property-core "test-property-expect-fail" prop gen-list 100 'xfail #f))
    ((a b c)
     (if (procedure? a)
         (%test-property-core "test-property-expect-fail" a b c 'xfail #f)
         (%test-property-core a b c 100 'xfail #f)))
    ((name prop gen-list runs)
     (%test-property-core name prop gen-list runs 'xfail #f))))

(define test-property-skip
  (case-lambda
    ((prop gen-list)
     (%test-property-core "test-property-skip" prop gen-list 100 'skip #f))
    ((a b c)
     (if (procedure? a)
         (%test-property-core "test-property-skip" a b c 'skip #f)
         (%test-property-core a b c 100 'skip #f)))
    ((name prop gen-list runs)
     (%test-property-core name prop gen-list runs 'skip #f))))

(define test-property-error
  (case-lambda
    ((prop gen-list)
     (%test-property-core "test-property-error" prop gen-list 100 'error #f))
    ((a b c)
     (if (procedure? a)
         (%test-property-core "test-property-error" a b c 'error #f)
         (%test-property-core a b c 100 'error #f)))
    ((name prop gen-list runs)
     (%test-property-core name prop gen-list runs 'error #f))))

(define test-property-error-type
  (case-lambda
    ((error-type prop gen-list)
     (%test-property-core "test-property-error-type" prop gen-list 100 'error-type error-type))
    ((error-type a b c)
     (if (procedure? a)
         (%test-property-core "test-property-error-type" a b c 'error-type error-type)
         (%test-property-core a b c 100 'error-type error-type)))
    ((error-type name prop gen-list runs)
     (%test-property-core name prop gen-list runs 'error-type error-type))))

;; ---------------------------------------------------------------------
;; §4. SRFI 64 Integration & Custom Test Runner
;; ---------------------------------------------------------------------

(define (property-test-runner)
  (test-runner-simple))
