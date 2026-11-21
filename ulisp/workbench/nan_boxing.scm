;;; =======================================================================
;;; ULisp Language Workbench: Guest 64-bit Quiet NaN-Boxing Representation
;;; Conforms to DSN-33-04 §2.3, DSN-33-02 §5.1 & Issue #893
;;; =======================================================================
;;; Provides:
;;; - 64-bit IEEE-754 Quiet NaN-boxing for dynamic guest languages
;;; - Tag layout:
;;;     [63:48] = 0x7FF8 + Tag (16 bits)
;;;     [47:0]  = 48-bit Payload (pointer or 32-bit integer or immediate)
;;; - Tag classification:
;;;     Tag 0: Raw Flonum (IEEE-754 Double precision float)
;;;     Tag 1: 32-bit Integer (Fixnum)
;;;     Tag 2: Special Immediates (False, True, Nil, Undefined)
;;;     Tag 3: Heap Object Pointer (48-bit canonical pointer)
;;; - CWE-843 (Type Confusion), CWE-190 (Overflow), CWE-119 (OOB) defense
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. 64-bit NaN-Boxing Constants (DSN-33-04 §2.3)
;;; -----------------------------------------------------------------------

;; Quiet NaN base prefix: 0x7FF8000000000000
;; = (* 4095 2251799813685248) = 9221120237041090560
(define NAN_BOX_BASE 9221120237041090560)

;; 48-bit payload mask: 0x0000FFFFFFFFFFFF = 281474976710655
(define NAN_PAYLOAD_MASK 281474976710655)

;; 48-bit tag shift unit: 1 << 48 = 281474976710656
(define NAN_TAG_UNIT 281474976710656)

;; Tag IDs
(define NAN_TAG_FLONUM  0) ; Raw double / unboxed float
(define NAN_TAG_INT32   1) ; 32-bit signed int
(define NAN_TAG_SPECIAL 2) ; Immediates
(define NAN_TAG_POINTER 3) ; 48-bit heap pointer

;; Special Immediate Codes
(define NAN_SPECIAL_FALSE 0)
(define NAN_SPECIAL_TRUE  1)
(define NAN_SPECIAL_NIL   2)
(define NAN_SPECIAL_UNDEF 3)

;; 32-bit Integer Bounds
(define INT32_MIN -2147483648)
(define INT32_MAX  2147483647)
(define UINT32_MASK 4294967295) ; 0xFFFFFFFF

;;; -----------------------------------------------------------------------
;;; 2. Bitwise Helpers & Error Handling
;;; -----------------------------------------------------------------------

(define (nan-box-error! msg detail)
  (raise (list 'nan-box-error msg detail)))

(define (%nan-bit-and a b)
  (if (and (number? a) (number? b))
      (bitwise-and a b)
      0))

(define (%nan-bit-ior a b)
  (if (and (number? a) (number? b))
      (bitwise-ior a b)
      0))

;;; -----------------------------------------------------------------------
;;; 3. Tag Identification & Query
;;; -----------------------------------------------------------------------

;;; Returns #t if v is a NaN-boxed value (greater than or equal to NAN_BOX_BASE)
(define (nan-boxed? v)
  (and (integer? v)
       (>= v NAN_BOX_BASE)))

;;; Extracts the tag ID (0..3) from a NaN-boxed value.
;;; If v is a flonum or below NAN_BOX_BASE, returns 0 (NAN_TAG_FLONUM).
(define (nan-tag-of v)
  (if (not (nan-boxed? v))
      NAN_TAG_FLONUM
      (let* ((offset (- v NAN_BOX_BASE))
             (tag-idx (quotient offset NAN_TAG_UNIT)))
        tag-idx)))

;;; -----------------------------------------------------------------------
;;; 4. 32-bit Integer Packing & Unpacking (CWE-190 Defense)
;;; -----------------------------------------------------------------------

;;; Packs a 32-bit signed integer into a NaN-boxed word.
(define (nan-box-int32 n)
  (if (not (integer? n))
      (nan-box-error! "nan-box-int32: not an integer" n)
      (if (or (< n INT32_MIN) (> n INT32_MAX))
          (nan-box-error! "nan-box-int32: 32-bit integer overflow" n)
          (let ((u32 (if (< n 0) (+ n 4294967296) n)))
            (+ NAN_BOX_BASE (* NAN_TAG_INT32 NAN_TAG_UNIT) u32)))))

;;; Checks if v is a NaN-boxed 32-bit integer
(define (nan-is-int32? v)
  (and (nan-boxed? v)
       (= (nan-tag-of v) NAN_TAG_INT32)))

;;; Unpacks a NaN-boxed 32-bit integer.
;;; Converts unsigned 32-bit payload back to signed integer.
(define (nan-unbox-int32 v)
  (if (not (nan-is-int32? v))
      (nan-box-error! "nan-unbox-int32: type assertion failure, not a NaN-boxed int32" v)
      (let* ((payload (%nan-bit-and v UINT32_MASK)))
        (if (>= payload 2147483648)
            (- payload 4294967296)
            payload))))

;;; -----------------------------------------------------------------------
;;; 5. Heap Pointer Packing & Unpacking (CWE-843 & CWE-119 Defense)
;;; -----------------------------------------------------------------------

;;; Packs a 48-bit canonical pointer into a NaN-boxed word.
(define (nan-box-pointer ptr)
  (if (not (integer? ptr))
      (nan-box-error! "nan-box-pointer: invalid pointer" ptr)
      (if (or (< ptr 0) (> ptr NAN_PAYLOAD_MASK))
          (nan-box-error! "nan-box-pointer: non-canonical pointer exceeds 48 bits" ptr)
          (+ NAN_BOX_BASE (* NAN_TAG_POINTER NAN_TAG_UNIT) ptr))))

;;; Checks if v is a NaN-boxed heap pointer
(define (nan-is-pointer? v)
  (and (nan-boxed? v)
       (= (nan-tag-of v) NAN_TAG_POINTER)))

;;; Unpacks a 48-bit heap pointer
(define (nan-unbox-pointer v)
  (if (not (nan-is-pointer? v))
      (nan-box-error! "nan-unbox-pointer: type assertion failure, not a NaN-boxed pointer" v)
      (%nan-bit-and v NAN_PAYLOAD_MASK)))

;;; -----------------------------------------------------------------------
;;; 6. Special Immediates Packing & Unpacking
;;; -----------------------------------------------------------------------

;;; Packs a special immediate code into a NaN-boxed word
(define (nan-box-special id)
  (+ NAN_BOX_BASE (* NAN_TAG_SPECIAL NAN_TAG_UNIT) id))

;;; Checks if v is a NaN-boxed special immediate
(define (nan-is-special? v)
  (and (nan-boxed? v)
       (= (nan-tag-of v) NAN_TAG_SPECIAL)))

;;; Unpacks a special immediate code
(define (nan-unbox-special v)
  (if (not (nan-is-special? v))
      (nan-box-error! "nan-unbox-special: not a NaN-boxed special immediate" v)
      (%nan-bit-and v NAN_PAYLOAD_MASK)))

(define (nan-is-false? v) (= v (nan-box-special NAN_SPECIAL_FALSE)))
(define (nan-is-true? v)  (= v (nan-box-special NAN_SPECIAL_TRUE)))
(define (nan-is-nil? v)   (= v (nan-box-special NAN_SPECIAL_NIL)))
(define (nan-is-undef? v) (= v (nan-box-special NAN_SPECIAL_UNDEF)))

;;; -----------------------------------------------------------------------
;;; 7. Flonum (Double Float) Representation
;;; -----------------------------------------------------------------------

;;; Checks if v is treated as a double float.
;;; Any value not in the Quiet NaN-boxed payload space is a raw double float.
(define (nan-is-flonum? v)
  (or (real? v)
      (and (not (nan-boxed? v)))))

;;; Box a float: In pure Scheme / unboxed mode, a flonum is represented directly
(define (nan-box-flonum f)
  f)

;;; Unbox a float: Identity for unboxed IEEE-754 representation
(define (nan-unbox-flonum v)
  (if (nan-boxed? v)
      (nan-box-error! "nan-unbox-flonum: value is a boxed integer/pointer, not a float" v)
      v))

;;; -----------------------------------------------------------------------
;;; 8. Residual Code / LIR Emitter Helpers (Compile-Time Lowering)
;;; -----------------------------------------------------------------------

;; Emits residual expression for testing if v is int32:
;; (= (quotient (- v NAN_BOX_BASE) NAN_TAG_UNIT) NAN_TAG_INT32)
(define (nan-emit-is-int32 v-expr)
  (list 'nan-is-int32? v-expr))

;; Emits residual expression for unboxing int32:
(define (nan-emit-unbox-int32 v-expr)
  (list 'nan-unbox-int32 v-expr))

;; Emits residual expression for boxing int32:
(define (nan-emit-box-int32 n-expr)
  (list 'nan-box-int32 n-expr))

;; Emits residual expression for testing if v is a pointer:
(define (nan-emit-is-pointer v-expr)
  (list 'nan-is-pointer? v-expr))

;; Emits residual expression for unboxing pointer:
(define (nan-emit-unbox-pointer v-expr)
  (list 'nan-unbox-pointer v-expr))

;; Emits residual expression for boxing pointer:
(define (nan-emit-box-pointer ptr-expr)
  (list 'nan-box-pointer ptr-expr))
