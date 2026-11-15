;;; =======================================================================
;;; Unit Test Suite: Pluggable Value Representation & Boxing Engine
;;; Conforms to DSN-33 §2.1, DSN-33-02 §5.1, DSN-38 §2 & Issue #836
;;; =======================================================================

(display "=== [Test Suite: Pluggable Value Representation (Issue #836)] ===\n")

(define (make-repr-test-prog main-body)
  (list '%lir-program
        '(strings ())
        '(stackmaps ())
        '(%lir-functions)
        (list '%lir-main '(frame-size 0) (cons 'body main-body))))

;;; -----------------------------------------------------------------------
;;; Group 1: define-value-repr DSL, Registry, Aliases & Validation
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: define-value-repr DSL, Registry & Validation ---\n")

(assert-true "1.1 repr:scheme-64bit-tagged is a valid value-repr"
             (value-repr? repr:scheme-64bit-tagged))

(assert-true "1.2 scheme-standard alias matches repr:scheme-64bit-tagged"
             (equal? (get-value-repr 'scheme-standard)
                     (get-value-repr 'repr:scheme-64bit-tagged)))

(assert-true "1.3 c-unboxed alias matches repr:c-unboxed"
             (equal? (get-value-repr 'c-unboxed)
                     (get-value-repr 'repr:c-unboxed)))

(assert-true "1.4 nan-boxing-64bit alias matches repr:nan-boxing-64bit"
             (equal? (get-value-repr 'nan-boxing-64bit)
                     (get-value-repr 'repr:nan-boxing-64bit)))

(assert-equal "1.5 default current-value-repr is repr:scheme-64bit-tagged"
              'repr:scheme-64bit-tagged
              (value-repr-name (current-value-repr)))

;; Custom 1-bit tagged representation via define-value-repr (DSN-33-02 §5.1 style)
(define-value-repr repr:custom-1bit
  (:word-bits 64)
  (:aliases custom-1bit)
  (:fixnum (:shift 1) (:tag-bits 1) (:tag-mask 1) (:step 2))
  (:immediates (:boolean-false 15) (:boolean-true 31) (:null 47) (:eof 63)
               (:char-shift 8) (:char-tag 6))
  (:pointer (:align 8) (:tag-mask 7) (:pair-tag 2) (:closure-tag 2)
            (:string-tag 4) (:vector-tag 6) (:bytevector-tag 0) (:flonum-tag 4)))

(assert-true "1.6 custom define-value-repr registered under custom-1bit alias"
             (equal? repr:custom-1bit (get-value-repr 'custom-1bit)))

;; Threat Model Validation (THREAT-836-1 / 2 / 3)
(assert-true "1.7 THREAT-836-2: reject fixnum shift > 16"
             (guard (ex (else #t))
               (make-value-repr-from-clauses
                 'bad-shift
                 '((:fixnum (:shift 32) (:tag-bits 0) (:tag-mask 0))))
               #f))

(assert-true "1.8 THREAT-836-1: reject fixnum tag exceeding tag-mask"
             (guard (ex (else #t))
               (make-value-repr-from-clauses
                 'bad-mask
                 '((:fixnum (:shift 2) (:tag-bits 4) (:tag-mask 1))))
               #f))

(assert-true "1.9 THREAT-836-3: reject non-power-of-two pointer alignment"
             (guard (ex (else #t))
               (make-value-repr-from-clauses
                 'bad-align
                 '((:pointer (:align 6) (:pair-tag 1))))
               #f))

(assert-true "1.10 THREAT-836-3: reject heap tag >= alignment"
             (guard (ex (else #t))
               (make-value-repr-from-clauses
                 'bad-ptr-tag
                 '((:pointer (:align 8) (:pair-tag 8))))
               #f))

(assert-true "1.11 THREAT-836-1: reject colliding pair-tag and fixnum tag"
             (guard (ex (else #t))
               (make-value-repr-from-clauses
                 'colliding-tags
                 '((:fixnum (:shift 1) (:tag-bits 1) (:tag-mask 1))
                   (:pointer (:align 8) (:pair-tag 3))))
               #f))

;;; -----------------------------------------------------------------------
;;; Group 2: Immediate Encoding & Decoding Across Representations
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Immediate Encoding & Decoding ---\n")

(assert-equal "2.1 scheme-standard encode fixnum 42"
              168
              (repr-encode-fixnum 42 'scheme-standard))

(assert-equal "2.2 scheme-standard encode negative fixnum -5"
              -20
              (repr-encode-fixnum -5 'scheme-standard))

(assert-equal "2.3 scheme-standard decode fixnum -20"
              -5
              (repr-decode-fixnum -20 'scheme-standard))

(assert-equal "2.4 scheme-standard immediates (#t #f '() eof #\\A)"
              (list 111 47 63 79 16654)
              (list (repr-encode-boolean #t 'scheme-standard)
                    (repr-encode-boolean #f 'scheme-standard)
                    (repr-encode-null 'scheme-standard)
                    (repr-encode-eof 'scheme-standard)
                    (repr-encode-char #\A 'scheme-standard)))

(assert-equal "2.5 c-unboxed encode fixnum 42 and -5 (no shift)"
              (list 42 -5 -5)
              (list (repr-encode-fixnum 42 'c-unboxed)
                    (repr-encode-fixnum -5 'c-unboxed)
                    (repr-decode-fixnum -5 'c-unboxed)))

(assert-equal "2.6 c-unboxed immediates (#t #f '() eof #\\A)"
              (list 1 0 0 -1 65)
              (list (repr-encode-boolean #t 'c-unboxed)
                    (repr-encode-boolean #f 'c-unboxed)
                    (repr-encode-null 'c-unboxed)
                    (repr-encode-eof 'c-unboxed)
                    (repr-encode-char #\A 'c-unboxed)))

(assert-equal "2.7 nan-boxing-64bit encode & decode positive/negative fixnums"
              (list #t 42 -5 1000000 -1000000)
              (list (repr-nan-boxed? 'nan-boxing-64bit)
                    (repr-decode-fixnum (repr-encode-fixnum 42 'nan-boxing-64bit) 'nan-boxing-64bit)
                    (repr-decode-fixnum (repr-encode-fixnum -5 'nan-boxing-64bit) 'nan-boxing-64bit)
                    (repr-decode-fixnum (repr-encode-fixnum 1000000 'nan-boxing-64bit) 'nan-boxing-64bit)
                    (repr-decode-fixnum (repr-encode-fixnum -1000000 'nan-boxing-64bit) 'nan-boxing-64bit)))

(assert-equal "2.8 custom-1bit encode & decode fixnum 21 (21 * 2 | 1 = 43)"
              (list 43 21 -7 15 31)
              (list (repr-encode-fixnum 21 'custom-1bit)
                    (repr-decode-fixnum 43 'custom-1bit)
                    (repr-decode-fixnum (repr-encode-fixnum -7 'custom-1bit) 'custom-1bit)
                    (repr-encode-boolean #f 'custom-1bit)
                    (repr-encode-boolean #t 'custom-1bit)))

;;; -----------------------------------------------------------------------
;;; Group 3: Heap Pointer Tags & Field Offset Derivation
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Heap Pointer Tags & Field Offsets ---\n")

(assert-equal "3.1 scheme-standard heap tags & pair car/cdr offsets"
              (list 1 -1 7 3 5 7 11)
              (list (repr-heap-tag 'pair 'scheme-standard)
                    (repr-field-offset 'pair 0 'scheme-standard)
                    (repr-field-offset 'pair 8 'scheme-standard)
                    (repr-heap-tag 'string 'scheme-standard)
                    (repr-heap-tag 'vector 'scheme-standard)
                    (repr-heap-tag 'bytevector 'scheme-standard)
                    (repr-heap-tag 'flonum 'scheme-standard)))

(assert-equal "3.2 c-unboxed zero tags & unshifted car/cdr offsets"
              (list 0 0 8 0 0 0)
              (list (repr-heap-tag 'pair 'c-unboxed)
                    (repr-field-offset 'pair 0 'c-unboxed)
                    (repr-field-offset 'pair 8 'c-unboxed)
                    (repr-heap-tag 'string 'c-unboxed)
                    (repr-heap-tag 'vector 'c-unboxed)
                    (repr-heap-tag 'flonum 'c-unboxed)))

;;; -----------------------------------------------------------------------
;;; Group 4: Boxing Code Generators & Scoped Switching
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Boxing Code Generators & Context Safety ---\n")

(assert-equal "4.1 scheme-standard box-fixnum same/different reg"
              (list '((%shl %rax 2))
                    '((%mov %rax %rcx) (%shl %rax 2)))
              (list (repr-emit-box-fixnum '%rax '%rax 'scheme-standard)
                    (repr-emit-box-fixnum '%rax '%rcx 'scheme-standard)))

(assert-equal "4.2 scheme-standard unbox-fixnum same/different reg"
              (list '((%sar %rax 2))
                    '((%mov %rax %rcx) (%sar %rax 2)))
              (list (repr-emit-unbox-fixnum '%rax '%rax 'scheme-standard)
                    (repr-emit-unbox-fixnum '%rax '%rcx 'scheme-standard)))

(assert-equal "4.3 c-unboxed box/unbox fixnum (zero shifts)"
              (list '()
                    '((%mov %rax %rcx))
                    '()
                    '((%mov %rax %rcx)))
              (list (repr-emit-box-fixnum '%rax '%rax 'c-unboxed)
                    (repr-emit-box-fixnum '%rax '%rcx 'c-unboxed)
                    (repr-emit-unbox-fixnum '%rax '%rax 'c-unboxed)
                    (repr-emit-unbox-fixnum '%rax '%rcx 'c-unboxed)))

(assert-equal "4.4 custom-1bit box/unbox fixnum (shift 1 + bit-or tag 1)"
              (list '((%shl %rax 1) (%bit-or %rax 1))
                    '((%sar %rax 1)))
              (list (repr-emit-box-fixnum '%rax '%rax 'custom-1bit)
                    (repr-emit-unbox-fixnum '%rax '%rax 'custom-1bit)))

(assert-equal "4.5 scheme-standard vs c-unboxed flonum box/unbox"
              (list '((%mov %rax %r12) (%add %rax 11) (%add %r12 16) (%store-typed f64 %rax -3 %xmm0))
                    '((%load-typed f64 %xmm0 %rax -3))
                    '((%fmov %rax %xmm0))
                    '((%fmov %xmm0 %rax))
                    '())
              (list (repr-emit-box-flonum '%rax '%xmm0 'scheme-standard)
                    (repr-emit-unbox-flonum '%xmm0 '%rax 'scheme-standard)
                    (repr-emit-box-flonum '%rax '%xmm0 'c-unboxed)
                    (repr-emit-unbox-flonum '%xmm0 '%rax 'c-unboxed)
                    (repr-emit-box-flonum '%xmm0 '%xmm0 'c-unboxed)))

;; THREAT-836-4: Verify with-value-repr restores active context even on exception
(guard (ex (else #t))
  (with-value-repr 'c-unboxed
    (lambda ()
      (assert-false "4.6 inside with-value-repr c-unboxed, repr-requires-boxing? is #f"
                    (repr-requires-boxing?))
      (raise "simulated compilation failure inside c-unboxed"))))

(assert-equal "4.7 THREAT-836-4: with-value-repr restores default representation after error"
              'repr:scheme-64bit-tagged
              (value-repr-name (current-value-repr)))

;;; -----------------------------------------------------------------------
;;; Group 5: End-to-End Pass Integration & Reference VM Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Pass Integration & Reference VM Verification ---\n")

;; 5.1 Pass 090 (S-RTyper) repr-requires-boxing? integration
(assert-equal "5.1 S-RTyper wrapping obeys active value representation"
              (list '(%box-fixnum (%raw-add x y))
                    '(%raw-add x y))
              (list (with-value-repr 'scheme-standard
                      (lambda () (rtyper-wrap-box-fixnum '(%raw-add x y))))
                    (with-value-repr 'c-unboxed
                      (lambda () (rtyper-wrap-box-fixnum '(%raw-add x y))))))

;; 5.2 Pass 130 (lir-immediate) dynamic encoding under scheme-standard vs c-unboxed
(assert-equal "5.2 Pass 130 lir-immediate switches dynamically with value-repr"
              (list '(168 111 47 63)
                    '(42 1 0 0))
              (list (with-value-repr 'scheme-standard
                      (lambda () (map lir-immediate '(42 #t #f ()))))
                    (with-value-repr 'c-unboxed
                      (lambda () (map lir-immediate '(42 #t #f ()))))))

;; 5.3 Pass 129 (lir-compile-unary) switches tag/offset constants dynamically
(define (capture-unary-lir repr-name op arg)
  (with-value-repr repr-name
    (lambda ()
      (reset-lir!)
      (lir-compile-unary op arg -8 '((x . -8)))
      (reverse (car *lir-instructions*)))))

(assert-equal "5.3 Pass 129 car offset derives from value-repr (-1 vs 0)"
              (list '((%load %rax %rsp -8) (%load %rax %rax -1))
                    '((%load %rax %rsp -8) (%load %rax %rax 0)))
              (list (capture-unary-lir 'scheme-standard 'car 'x)
                    (capture-unary-lir 'c-unboxed 'car 'x)))

(assert-equal "5.4 Pass 129 fxadd1 step derives from value-repr (4 vs 1)"
              (list '((%load %rax %rsp -8) (%add %rax 4))
                    '((%load %rax %rsp -8) (%add %rax 1)))
              (list (capture-unary-lir 'scheme-standard 'fxadd1 'x)
                    (capture-unary-lir 'c-unboxed 'fxadd1 'x)))

;; 5.5 Pass 131 lowering under scheme-standard vs c-unboxed + Reference VM execution
(define managed-arith-prog
  (make-repr-test-prog
    '((%mov %rax 10)
      (%mov %rbx 32)
      (%add %rax %rbx)
      (%box-fixnum %rax %rax)
      (%return %rax))))

(define lowered-scheme-prog
  (with-value-repr 'scheme-standard
    (lambda () (lower-managed-dialect managed-arith-prog))))

(define lowered-c-prog
  (with-value-repr 'c-unboxed
    (lambda () (lower-managed-dialect managed-arith-prog))))

(assert-true "5.5 Lowered Scheme LIR passes validate-core-lir"
             (validate-core-lir lowered-scheme-prog))

(assert-true "5.6 Lowered C Unboxed LIR passes validate-core-lir"
             (validate-core-lir lowered-c-prog))

(assert-equal "5.7 Reference VM executes Scheme-lowered Core LIR -> tagged 168 (decoded 42)"
              (list 168 42)
              (let ((raw-rax (eval-lir-program lowered-scheme-prog)))
                (list raw-rax (repr-decode-fixnum raw-rax 'scheme-standard))))

(assert-equal "5.8 Reference VM executes C-Unboxed-lowered Core LIR -> raw 42 directly"
              42
              (eval-lir-program lowered-c-prog))

(display "\n-------------------------------------------------------\n")
(display " [RESULT] Pluggable Value Representation: ALL TESTS PASSED!\n")
(display "-------------------------------------------------------\n")
