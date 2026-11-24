;;; =======================================================================
;;; Test Suite: Language Workbench Guest Value Tagging & NaN-Boxing
;;; Conforms to DSN-33-04 §2.3, Issue #893
;;; =======================================================================

(display "\n=== [Test Suite: Language Workbench Guest Value Tagging & NaN-Boxing (Issue #893)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: 3-bit Tagged Pointer Operations
;;; -----------------------------------------------------------------------

(display "--- Group 1: 3-bit Tagged Pointer Operations ---\n")

;; Fixnum packing and unpacking
(let ((test-nums '(0 1 -1 42 -42 1000 -999999 1073741823 -1073741824)))
  (let loop ((rest test-nums))
    (if (pair? rest)
        (let* ((n (car rest))
               (packed (guest-pack-fixnum n)))
          (assert-true (string-append "guest-fixnum? for " (number->string n))
                       (guest-fixnum? packed))
          (assert-equal (string-append "guest-tag-of fixnum is 0 for " (number->string n))
                        GUEST_TAG_FIXNUM (guest-tag-of packed))
          (assert-equal (string-append "unpack roundtrip for " (number->string n))
                        n (guest-unpack-fixnum packed))
          (loop (cdr rest))))))

;; Heap pointer packing and unpacking
(let ((raw-ptr-1 4096)   ; 0x1000 (8-byte aligned)
      (raw-ptr-2 65536)) ; 0x10000
  ;; Pair
  (let ((p (guest-pack-pointer raw-ptr-1 GUEST_TAG_PAIR)))
    (assert-true "guest-pair? is #t" (guest-pair? p))
    (assert-equal "tag of pair is 1" GUEST_TAG_PAIR (guest-tag-of p))
    (assert-equal "unpacked pair pointer" raw-ptr-1 (guest-unpack-pointer p GUEST_TAG_PAIR)))

  ;; Symbol
  (let ((s (guest-pack-pointer raw-ptr-1 GUEST_TAG_SYMBOL)))
    (assert-true "guest-symbol? is #t" (guest-symbol? s))
    (assert-equal "tag of symbol is 2" GUEST_TAG_SYMBOL (guest-tag-of s))
    (assert-equal "unpacked symbol pointer" raw-ptr-1 (guest-unpack-pointer s GUEST_TAG_SYMBOL)))

  ;; Closure
  (let ((c (guest-pack-pointer raw-ptr-1 GUEST_TAG_CLOSURE)))
    (assert-true "guest-closure? is #t" (guest-closure? c))
    (assert-equal "tag of closure is 3" GUEST_TAG_CLOSURE (guest-tag-of c))
    (assert-equal "unpacked closure pointer" raw-ptr-1 (guest-unpack-pointer c GUEST_TAG_CLOSURE)))

  ;; Vector
  (let ((v (guest-pack-pointer raw-ptr-2 GUEST_TAG_VECTOR)))
    (assert-true "guest-vector? is #t" (guest-vector? v))
    (assert-equal "tag of vector is 4" GUEST_TAG_VECTOR (guest-tag-of v))
    (assert-equal "unpacked vector pointer" raw-ptr-2 (guest-unpack-pointer v GUEST_TAG_VECTOR)))

  ;; Instance
  (let ((inst (guest-pack-pointer raw-ptr-2 GUEST_TAG_INSTANCE)))
    (assert-true "guest-instance? is #t" (guest-instance? inst))
    (assert-equal "tag of instance is 5" GUEST_TAG_INSTANCE (guest-tag-of inst))
    (assert-equal "unpacked instance pointer" raw-ptr-2 (guest-unpack-pointer inst GUEST_TAG_INSTANCE)))

  ;; Flonum pointer
  (let ((fl (guest-pack-pointer raw-ptr-2 GUEST_TAG_FLONUM)))
    (assert-true "guest-flonum-ptr? is #t" (guest-flonum-ptr? fl))
    (assert-equal "tag of flonum is 6" GUEST_TAG_FLONUM (guest-tag-of fl))
    (assert-equal "unpacked flonum pointer" raw-ptr-2 (guest-unpack-pointer fl GUEST_TAG_FLONUM))))

;; Special Immediates
(let ((v-false (guest-pack-special GUEST_SPECIAL_FALSE))
      (v-true  (guest-pack-special GUEST_SPECIAL_TRUE))
      (v-nil   (guest-pack-special GUEST_SPECIAL_NIL))
      (v-undef (guest-pack-special GUEST_SPECIAL_UNDEF)))
  (assert-true "guest-special? for false" (guest-special? v-false))
  (assert-true "guest-false? is #t" (guest-false? v-false))
  (assert-false "guest-true? is #f for false" (guest-true? v-false))
  (assert-true "guest-true? is #t" (guest-true? v-true))
  (assert-true "guest-nil? is #t" (guest-nil? v-nil))
  (assert-true "guest-undef? is #t" (guest-undef? v-undef))
  (assert-equal "unpack special nil" GUEST_SPECIAL_NIL (guest-unpack-special v-nil)))

;; Emitter Helpers
(assert-equal "guest-emit-tag-check format"
              '(= (bitwise-and x 7) 0)
              (guest-emit-tag-check 'x GUEST_TAG_FIXNUM))
(assert-equal "guest-emit-untag format for tag 1"
              '(- p 1)
              (guest-emit-untag 'p GUEST_TAG_PAIR))
(assert-equal "guest-emit-untag for tag 0 is identity"
              'n
              (guest-emit-untag 'n 0))

;;; -----------------------------------------------------------------------
;;; Group 2: 64-bit Quiet NaN-Boxing Operations
;;; -----------------------------------------------------------------------

(display "\n--- Group 2: 64-bit Quiet NaN-Boxing Operations ---\n")

;; 32-bit Integers
(let ((test-ints '(0 1 -1 42 -42 2147483647 -2147483648 1000000 -1000000)))
  (let loop ((rest test-ints))
    (if (pair? rest)
        (let* ((n (car rest))
               (boxed (nan-box-int32 n)))
          (assert-true (string-append "nan-boxed? for " (number->string n))
                       (nan-boxed? boxed))
          (assert-true (string-append "nan-is-int32? for " (number->string n))
                       (nan-is-int32? boxed))
          (assert-equal (string-append "nan-tag-of is NAN_TAG_INT32 for " (number->string n))
                        NAN_TAG_INT32 (nan-tag-of boxed))
          (assert-equal (string-append "nan-unbox-int32 roundtrip for " (number->string n))
                        n (nan-unbox-int32 boxed))
          (loop (cdr rest))))))

;; 48-bit Canonical Pointers
(let ((ptrs '(0 4096 1048576 281474976710655))) ; up to 48-bit payload mask
  (let loop ((rest ptrs))
    (if (pair? rest)
        (let* ((ptr (car rest))
               (boxed (nan-box-pointer ptr)))
          (assert-true "nan-boxed? is #t for pointer" (nan-boxed? boxed))
          (assert-true "nan-is-pointer? is #t" (nan-is-pointer? boxed))
          (assert-equal "nan-tag-of is NAN_TAG_POINTER" NAN_TAG_POINTER (nan-tag-of boxed))
          (assert-equal "nan-unbox-pointer roundtrip" ptr (nan-unbox-pointer boxed))
          (loop (cdr rest))))))

;; Special Immediates
(let ((n-false (nan-box-special NAN_SPECIAL_FALSE))
      (n-true  (nan-box-special NAN_SPECIAL_TRUE))
      (n-nil   (nan-box-special NAN_SPECIAL_NIL))
      (n-undef (nan-box-special NAN_SPECIAL_UNDEF)))
  (assert-true "nan-is-special? for false" (nan-is-special? n-false))
  (assert-true "nan-is-false? is #t" (nan-is-false? n-false))
  (assert-false "nan-is-true? is #f for false" (nan-is-true? n-false))
  (assert-true "nan-is-true? is #t for true" (nan-is-true? n-true))
  (assert-true "nan-is-nil? is #t" (nan-is-nil? n-nil))
  (assert-true "nan-is-undef? is #t" (nan-is-undef? n-undef))
  (assert-equal "nan-unbox-special nil" NAN_SPECIAL_NIL (nan-unbox-special n-nil)))

;; Flonums
(let ((floats '(0.0 1.0 -1.0 3.141592653589793 -0.00001 1.0e10)))
  (let loop ((rest floats))
    (if (pair? rest)
        (let* ((f (car rest))
               (boxed (nan-box-flonum f)))
          (assert-true "nan-is-flonum? is #t" (nan-is-flonum? boxed))
          (assert-equal "nan-unbox-flonum is identity" f (nan-unbox-flonum boxed))
          (loop (cdr rest))))))

;;; -----------------------------------------------------------------------
;;; Group 3: Security & Assertion Guards (CWE-843 & CWE-190 Defense)
;;; -----------------------------------------------------------------------

(display "\n--- Group 3: Security & Assertion Guards ---\n")

;; guest-tag-assert!
(let ((packed-fx (guest-pack-fixnum 100)))
  (assert-true "tag assertion succeeds for valid fixnum"
               (guest-tag-assert! packed-fx GUEST_TAG_FIXNUM "expected fixnum")))

;; Unpack assertion protection: unpacking a fixnum as pair throws error
(let ((packed-fx (guest-pack-fixnum 100))
      (caught #f))
  (guard (ex (else (set! caught #t)))
    (guest-unpack-pointer packed-fx GUEST_TAG_PAIR))
  (assert-true "guest-unpack-pointer rejected fixnum tag" caught))

;; Unaligned pointer packing protection
(let ((caught #f))
  (guard (ex (else (set! caught #t)))
    (guest-pack-pointer 4097 GUEST_TAG_PAIR)) ; 4097 is odd (unaligned)
  (assert-true "guest-pack-pointer rejected unaligned pointer" caught))

;; 32-bit integer overflow protection in nan-box-int32
(let ((caught #f))
  (guard (ex (else (set! caught #t)))
    (nan-box-int32 3000000000)) ; > INT32_MAX
  (assert-true "nan-box-int32 rejected 32-bit overflow" caught))

;;; -----------------------------------------------------------------------
;;; Group 4: First Futamura Projection × Tag Stripping
;;; -----------------------------------------------------------------------

(display "\n--- Group 4: First Futamura Projection with Tag Stripping ---\n")

;; Helper to recursively search an AST for a given symbol
(define (ast-contains? sym tree)
  (cond
    ((null? tree) #f)
    ((eq? tree sym) #t)
    ((pair? tree)
     (or (ast-contains? sym (car tree))
         (ast-contains? sym (cdr tree))))
    (else #f)))

;; Test 4.1: Tag Stripping on Fixnum Pack/Unpack in Partial Evaluation
(let* ((env (list (cons 'a (make-dynamic-val 'integer 'dyn_a #f #f))
                  (cons 'b (make-dynamic-val 'integer 'dyn_b #f #f))))
       ;; Dynamic program with boxing and unboxing:
       ;; (guest-unpack-fixnum (guest-pack-fixnum (+ a b)))
       (prog '(guest-unpack-fixnum (guest-pack-fixnum (+ a b))))
       (residual (stage-poly-lower prog env)))
  (display "Residual AST for Fixnum Tag Stripping: ")
  (write residual)
  (newline)

  ;; Assert that packing and unpacking are 100% stripped away!
  (assert-false "residual does not contain guest-pack-fixnum"
                (ast-contains? 'guest-pack-fixnum residual))
  (assert-false "residual does not contain guest-unpack-fixnum"
                (ast-contains? 'guest-unpack-fixnum residual))
  (assert-true "residual retains core addition (+)"
               (ast-contains? '+ residual)))

;; Test 4.2: Tag Stripping on NaN-Boxing Int32 Pack/Unpack
(let* ((env (list (cons 'x (make-dynamic-val 'integer 'dyn_x #f #f))
                  (cons 'y (make-dynamic-val 'integer 'dyn_y #f #f))))
       (prog '(nan-unbox-int32 (nan-box-int32 (+ x y))))
       (residual (stage-poly-lower prog env)))
  (display "Residual AST for NaN-Boxing Tag Stripping: ")
  (write residual)
  (newline)

  (assert-false "residual does not contain nan-box-int32"
                (ast-contains? 'nan-box-int32 residual))
  (assert-false "residual does not contain nan-unbox-int32"
                (ast-contains? 'nan-unbox-int32 residual))
  (assert-true "residual retains core addition (+)"
               (ast-contains? '+ residual)))

;; Test 4.3: Compile-time elimination of dynamic type check:
;; (if (guest-fixnum? (guest-pack-fixnum a)) (+ a 10) 0)
;; Since guest-fixnum? simplifies to #t at compile time, the if branch collapses completely!
(let* ((env (list (cons 'a (make-dynamic-val 'integer 'dyn_a #f #f))))
       (prog '(if (guest-fixnum? (guest-pack-fixnum a)) (+ a 10) 0))
       (residual (stage-poly-lower prog env)))
  (display "Residual AST for Conditional Type-Check Elimination: ")
  (write residual)
  (newline)

  (assert-false "residual does not contain if"
                (ast-contains? 'if residual))
  (assert-false "residual does not contain guest-fixnum?"
                (ast-contains? 'guest-fixnum? residual))
  (assert-true "residual contains (+ dyn_a 10)"
               (ast-contains? '+ residual)))

;;; -----------------------------------------------------------------------
;;; Group 5: SSOT Parity with define-value-repr (Issue #944)
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: SSOT Parity with define-value-repr ---\n")

(assert-equal "5.1 Guest 3-bit constants match repr:guest-3bit-tagged"
              (list GUEST_TAG_FIXNUM GUEST_TAG_PAIR GUEST_TAG_SYMBOL
                    GUEST_TAG_CLOSURE GUEST_TAG_VECTOR GUEST_TAG_INSTANCE
                    GUEST_TAG_FLONUM GUEST_TAG_SPECIAL GUEST_TAG_MASK
                    GUEST_FIXNUM_MIN GUEST_FIXNUM_MAX)
              (list (repr-fixnum-tag 'repr:guest-3bit-tagged)
                    (repr-heap-tag 'pair 'repr:guest-3bit-tagged)
                    (repr-heap-tag 'symbol 'repr:guest-3bit-tagged)
                    (repr-heap-tag 'closure 'repr:guest-3bit-tagged)
                    (repr-heap-tag 'vector 'repr:guest-3bit-tagged)
                    (repr-heap-tag 'instance 'repr:guest-3bit-tagged)
                    (repr-heap-tag 'flonum 'repr:guest-3bit-tagged)
                    (repr-special-tag 'repr:guest-3bit-tagged)
                    (repr-pointer-mask 'repr:guest-3bit-tagged)
                    (repr-fixnum-min 'repr:guest-3bit-tagged)
                    (repr-fixnum-max 'repr:guest-3bit-tagged)))

(assert-equal "5.2 NaN-boxing constants match repr:nan-boxing-64bit"
              (list NAN_BOX_BASE NAN_PAYLOAD_MASK NAN_TAG_UNIT
                    NAN_TAG_FLONUM NAN_TAG_INT32 NAN_TAG_SPECIAL NAN_TAG_POINTER)
              (list (repr-nan-box-base 'repr:nan-boxing-64bit)
                    (repr-nan-box-payload-mask 'repr:nan-boxing-64bit)
                    (repr-nan-box-tag-unit 'repr:nan-boxing-64bit)
                    (repr-nan-box-subtag 'flonum 'repr:nan-boxing-64bit)
                    (repr-nan-box-subtag 'fixnum 'repr:nan-boxing-64bit)
                    (repr-nan-box-subtag 'imm 'repr:nan-boxing-64bit)
                    (repr-nan-box-subtag 'pointer 'repr:nan-boxing-64bit)))

(assert-equal "5.3 Guest and NaN-box packers equal SSOT encoders"
              (list (guest-pack-fixnum -77)
                    (guest-pack-special GUEST_SPECIAL_UNDEF)
                    (nan-box-pointer 8192)
                    (nan-box-special NAN_SPECIAL_NIL))
              (list (repr-encode-fixnum -77 'repr:guest-3bit-tagged)
                    (repr-encode-special 3 'repr:guest-3bit-tagged)
                    (repr-nan-box-pointer 8192 'repr:nan-boxing-64bit)
                    (repr-nan-box-special 2 'repr:nan-boxing-64bit)))

(display "\n[RESULT] All Language Workbench Guest Value Tagging & NaN-Boxing tests PASSED!\n")
