;;; =======================================================================
;;; ULisp Language Workbench: Guest Dynamic Value Tagging (3-bit Tagging)
;;; Conforms to DSN-33-04 §2.3, DSN-33-02 §5.1, DSN-33-03 §4.4 & Issue #893
;;; =======================================================================
;;; Provides:
;;; - 3-bit Tagged Pointer scheme for 64-bit architectures
;;; - Tag definitions: Fixnum (000), Pair (001), Symbol (010), Closure (011),
;;;   Vector (100), Instance (101), Flonum (110), Special/Immediates (111)
;;; - Pure Scheme packing, unpacking, type predicates, and assertions
;;; - Residual ANF / LIR code emission helpers with compile-time tag stripping
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. 3-bit Tag Constants (Derived from repr:guest-3bit-tagged SSOT)
;;; -----------------------------------------------------------------------

(define GUEST_TAG_FIXNUM   (repr-fixnum-tag 'repr:guest-3bit-tagged))
(define GUEST_TAG_PAIR     (repr-heap-tag 'pair 'repr:guest-3bit-tagged))
(define GUEST_TAG_SYMBOL   (repr-heap-tag 'symbol 'repr:guest-3bit-tagged))
(define GUEST_TAG_CLOSURE  (repr-heap-tag 'closure 'repr:guest-3bit-tagged))
(define GUEST_TAG_VECTOR   (repr-heap-tag 'vector 'repr:guest-3bit-tagged))
(define GUEST_TAG_INSTANCE (repr-heap-tag 'instance 'repr:guest-3bit-tagged))
(define GUEST_TAG_FLONUM   (repr-heap-tag 'flonum 'repr:guest-3bit-tagged))
(define GUEST_TAG_SPECIAL  (repr-special-tag 'repr:guest-3bit-tagged))
(define GUEST_TAG_MASK     (repr-pointer-mask 'repr:guest-3bit-tagged))
(define GUEST_FIXNUM_SHIFT (repr-fixnum-shift 'repr:guest-3bit-tagged))

;; Special immediate codes embedded in bits [5:3] with tag 7
(define GUEST_SPECIAL_FALSE (value-repr-prop repr:guest-3bit-tagged 'immediates ':special-false 0))
(define GUEST_SPECIAL_TRUE  (value-repr-prop repr:guest-3bit-tagged 'immediates ':special-true 1))
(define GUEST_SPECIAL_NIL   (value-repr-prop repr:guest-3bit-tagged 'immediates ':special-nil 2))
(define GUEST_SPECIAL_UNDEF (value-repr-prop repr:guest-3bit-tagged 'immediates ':special-undef 3))

;; Fixnum bounds for 61-bit signed integer (64 - 3 bits tag)
(define GUEST_FIXNUM_MAX (repr-fixnum-max 'repr:guest-3bit-tagged))
(define GUEST_FIXNUM_MIN (repr-fixnum-min 'repr:guest-3bit-tagged))

;;; -----------------------------------------------------------------------
;;; 2. Pure Scheme Helper Bitwise Wrappers & Error Handling
;;; -----------------------------------------------------------------------

(define (guest-tag-error! msg detail)
  (raise (list 'guest-tag-error msg detail)))

(define (%guest-bit-and a b)
  (if (and (number? a) (number? b))
      (bitwise-and a b)
      0))

(define (%guest-bit-ior a b)
  (if (and (number? a) (number? b))
      (bitwise-ior a b)
      0))

(define (%guest-bit-shift n bits)
  (if (number? n)
      (bitwise-arithmetic-shift n bits)
      0))

;;; -----------------------------------------------------------------------
;;; 3. Fixnum Packing & Unpacking (CWE-190 Defense)
;;; -----------------------------------------------------------------------

;;; Packs a signed integer into a 61-bit tagged fixnum.
;;; Raises an error on overflow to prevent silent tag corruption.
(define (guest-pack-fixnum n)
  (if (not (integer? n))
      (guest-tag-error! "guest-pack-fixnum: not an integer" n)
      (if (or (> n GUEST_FIXNUM_MAX) (< n GUEST_FIXNUM_MIN))
          (guest-tag-error! "guest-pack-fixnum: integer overflow for 61-bit representation" n)
          (repr-encode-fixnum n 'repr:guest-3bit-tagged))))

;;; Unpacks a 61-bit tagged fixnum into an integer.
;;; Arithmetic right shift preserves the sign bit.
(define (guest-unpack-fixnum v)
  (if (not (guest-fixnum? v))
      (guest-tag-error! "guest-unpack-fixnum: type assertion failure, not a tagged fixnum" v)
      (repr-decode-fixnum v 'repr:guest-3bit-tagged)))

;;; Tests whether value v has the Fixnum tag (000)
(define (guest-fixnum? v)
  (and (integer? v)
       (= (%guest-bit-and v GUEST_TAG_MASK) GUEST_TAG_FIXNUM)))

;;; -----------------------------------------------------------------------
;;; 4. Pointer Packing & Unpacking (CWE-843 Defense)
;;; -----------------------------------------------------------------------

;;; Packs an 8-byte aligned heap pointer with a 3-bit tag.
;;; Asserts that the lowest 3 bits of the raw pointer are zero.
(define (guest-pack-pointer ptr tag)
  (if (not (integer? ptr))
      (guest-tag-error! "guest-pack-pointer: invalid pointer address" ptr)
      (if (not (= (%guest-bit-and ptr GUEST_TAG_MASK) 0))
          (guest-tag-error! "guest-pack-pointer: unaligned pointer (lower 3 bits non-zero)" ptr)
          (%guest-bit-ior ptr (%guest-bit-and tag GUEST_TAG_MASK)))))

;;; Unpacks a pointer with a specific expected tag.
;;; Throws type assertion error if tag does not match (CWE-843 protection).
(define (guest-unpack-pointer v expected-tag)
  (if (not (guest-pointer-of-tag? v expected-tag))
      (guest-tag-error! "guest-unpack-pointer: type assertion failed" (list v expected-tag))
      (- v expected-tag)))

;;; Extracts the 3-bit tag from a tagged value
(define (guest-tag-of v)
  (if (integer? v)
      (%guest-bit-and v GUEST_TAG_MASK)
      #f))

;;; Checks if value v has the specified tag
(define (guest-pointer-of-tag? v tag)
  (and (integer? v)
       (= (%guest-bit-and v GUEST_TAG_MASK) tag)))

;; Type-specific predicates
(define (guest-pair? v)     (guest-pointer-of-tag? v GUEST_TAG_PAIR))
(define (guest-symbol? v)   (guest-pointer-of-tag? v GUEST_TAG_SYMBOL))
(define (guest-closure? v)  (guest-pointer-of-tag? v GUEST_TAG_CLOSURE))
(define (guest-vector? v)   (guest-pointer-of-tag? v GUEST_TAG_VECTOR))
(define (guest-instance? v) (guest-pointer-of-tag? v GUEST_TAG_INSTANCE))
(define (guest-flonum-ptr? v) (guest-pointer-of-tag? v GUEST_TAG_FLONUM))

;;; -----------------------------------------------------------------------
;;; 5. Special Immediates Packing & Unpacking
;;; -----------------------------------------------------------------------

;;; Packs an immediate code into a tagged special value
(define (guest-pack-special id)
  (repr-encode-special id 'repr:guest-3bit-tagged))

;;; Unpacks an immediate code from a tagged special value
(define (guest-unpack-special v)
  (if (not (guest-special? v))
      (guest-tag-error! "guest-unpack-special: not a special immediate" v)
      (repr-decode-special v 'repr:guest-3bit-tagged)))

;;; Predicate for special immediates
(define (guest-special? v)
  (and (integer? v)
       (= (%guest-bit-and v GUEST_TAG_MASK) GUEST_TAG_SPECIAL)))

(define (guest-false? v) (= v (guest-pack-special GUEST_SPECIAL_FALSE)))
(define (guest-true? v)  (= v (guest-pack-special GUEST_SPECIAL_TRUE)))
(define (guest-nil? v)   (= v (guest-pack-special GUEST_SPECIAL_NIL)))
(define (guest-undef? v) (= v (guest-pack-special GUEST_SPECIAL_UNDEF)))

;;; -----------------------------------------------------------------------
;;; 6. Type Assertion Guard (CWE-843 Runtime Attestation)
;;; -----------------------------------------------------------------------

(define (guest-tag-assert! v expected-tag msg)
  (if (not (= (%guest-bit-and v GUEST_TAG_MASK) expected-tag))
      (guest-tag-error! (string-append "guest-tag-assert: " msg) (list v expected-tag))
      #t))

;;; -----------------------------------------------------------------------
;;; 7. Residual Code / LIR Emitter Helpers (Compile-Time Lowering)
;;; -----------------------------------------------------------------------

;; Emits residual expression for tag check: (= (bitwise-and v 7) tag)
(define (guest-emit-tag-check v-expr tag)
  (list '= (list 'bitwise-and v-expr GUEST_TAG_MASK) tag))

;; Emits residual expression for untagging: (- v tag)
(define (guest-emit-untag v-expr tag)
  (if (= tag 0)
      v-expr
      (list '- v-expr tag)))

;; Emits residual expression for fixnum packing: (arithmetic-shift n 3)
(define (guest-emit-pack-fixnum n-expr)
  (list 'arithmetic-shift n-expr GUEST_FIXNUM_SHIFT))

;; Emits residual expression for fixnum unpacking: (arithmetic-shift v -3)
(define (guest-emit-unpack-fixnum v-expr)
  (list 'arithmetic-shift v-expr (- GUEST_FIXNUM_SHIFT)))
