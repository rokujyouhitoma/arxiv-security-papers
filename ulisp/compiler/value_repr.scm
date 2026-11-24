;;; =======================================================================
;;; ULisp Compiler: Pluggable Value Representation & Boxing Engine
;;; Conforms to DSN-33 §2.1, DSN-33-02 §5.1, DSN-38 §2 & Issue #836
;;; =======================================================================
;;; Centralizes value representation schemas (Fixnum shift/tag/mask,
;;; immediate encodings, heap pointer alignment/tags, and NaN-boxing)
;;; behind the declarative `define-value-repr` DSL and code generators.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Global Registry & Active Representation State
;;; -----------------------------------------------------------------------

(define *value-repr-registry* (cons '() '()))
(define *current-value-repr-cell* (cons #f '()))

(define (value-repr? x)
  (and (pair? x) (eq? (car x) 'value-repr)))

(define (value-repr-name spec)
  (let ((e (assq 'name (cdr spec))))
    (if e (cdr e) 'unknown)))

(define (value-repr-section spec section-key)
  (let ((e (assq section-key (cdr spec))))
    (if e (cdr e) '())))

(define (value-repr-prop spec section-key prop-key default-val)
  (let* ((sec (value-repr-section spec section-key))
         (entry (if (pair? sec) (assq prop-key sec) #f)))
    (if entry (cdr entry) default-val)))

;;; -----------------------------------------------------------------------
;;; 2. Representation Validation (CWE-843 / CWE-190 / CWE-119 Defense)
;;; -----------------------------------------------------------------------

(define (value-repr-error! msg detail)
  (raise (list 'value-repr-error msg detail)))

(define (power-of-two? n)
  (and (integer? n)
       (> n 0)
       (= (ctfe-bitwise-and n (- n 1)) 0)))

(define (validate-value-repr spec)
  (if (not (value-repr? spec))
      (value-repr-error! "validate-value-repr: not a value-repr descriptor" spec)
      (let* ((shift (value-repr-prop spec 'fixnum ':shift 0))
             (fx-tag (value-repr-prop spec 'fixnum ':tag-bits 0))
             (fx-mask (value-repr-prop spec 'fixnum ':tag-mask 0))
             (align (value-repr-prop spec 'pointer ':align 8))
             (pair-tag (value-repr-prop spec 'pointer ':pair-tag 0))
             (str-tag (value-repr-prop spec 'pointer ':string-tag 0))
             (vec-tag (value-repr-prop spec 'pointer ':vector-tag 0))
             (bv-tag (value-repr-prop spec 'pointer ':bytevector-tag 0)))
        ;; THREAT-836-2: Shift bounds check (0 <= shift <= 16)
        (if (or (not (integer? shift)) (< shift 0) (> shift 16))
            (value-repr-error! "validate-value-repr: fixnum :shift out of bounds [0, 16]" shift))
        ;; THREAT-836-1: Fixnum tag must fit within fixnum mask
        (if (not (= (ctfe-bitwise-and fx-tag fx-mask) fx-tag))
            (value-repr-error! "validate-value-repr: fixnum :tag-bits exceeds :tag-mask" (list fx-tag fx-mask)))
        ;; THREAT-836-3: Pointer alignment must be power of two
        (if (not (power-of-two? align))
            (value-repr-error! "validate-value-repr: pointer :align must be a power of 2" align))
        ;; THREAT-836-3: Heap tags must be strictly less than pointer alignment (except when align=1 and tag=0)
        (let check-tags ((tags (list pair-tag str-tag vec-tag bv-tag)))
          (if (pair? tags)
              (let ((t (car tags)))
                (if (or (< t 0) (and (> align 1) (>= t align)) (and (= align 1) (> t 0)))
                    (value-repr-error! "validate-value-repr: heap pointer tag violates alignment boundary" (list t align))
                    (check-tags (cdr tags))))))
        ;; THREAT-836-1: When fixnum mask > 0 and pointer tags > 0, check tag disjointness
        (if (and (> fx-mask 0) (> pair-tag 0) (= (ctfe-bitwise-and pair-tag fx-mask) fx-tag))
            (value-repr-error! "validate-value-repr: pair-tag collides with fixnum tag" (list pair-tag fx-tag fx-mask)))
        #t)))

;;; -----------------------------------------------------------------------
;;; 3. Clause Parser & Constructor for `define-value-repr`
;;; -----------------------------------------------------------------------

(define (parse-repr-kv-list items)
  (if (or (null? items) (eq? items 'none) (equal? items '(none)))
      '()
      (let loop ((rest items) (acc '()))
        (if (null? rest)
            (reverse acc)
            (let ((item (car rest)))
              (if (and (pair? item) (symbol? (car item)) (pair? (cdr item)))
                  (loop (cdr rest) (cons (cons (car item) (cadr item)) acc))
                  (loop (cdr rest) acc)))))))

(define (make-value-repr-from-clauses name clauses)
  (let loop ((rest clauses)
             (word-bits 64)
             (fx-alist '())
             (imm-alist '())
             (ptr-alist '())
             (nan-alist '())
             (aliases '()))
    (if (null? rest)
        (let ((spec (list 'value-repr
                          (cons 'name name)
                          (cons 'word-bits word-bits)
                          (cons 'aliases aliases)
                          (cons 'fixnum fx-alist)
                          (cons 'immediates imm-alist)
                          (cons 'pointer ptr-alist)
                          (cons 'nan-box nan-alist))))
          (validate-value-repr spec)
          spec)
        (let ((clause (car rest)))
          (if (not (pair? clause))
              (loop (cdr rest) word-bits fx-alist imm-alist ptr-alist nan-alist aliases)
              (let ((head (car clause))
                    (body (cdr clause)))
                (cond
                  ((eq? head ':word-bits)
                   (loop (cdr rest) (if (pair? body) (car body) 64) fx-alist imm-alist ptr-alist nan-alist aliases))
                  ((eq? head ':aliases)
                   (loop (cdr rest) word-bits fx-alist imm-alist ptr-alist nan-alist body))
                  ((eq? head ':fixnum)
                   (loop (cdr rest) word-bits (parse-repr-kv-list body) imm-alist ptr-alist nan-alist aliases))
                  ((eq? head ':immediates)
                   (loop (cdr rest) word-bits fx-alist (parse-repr-kv-list body) ptr-alist nan-alist aliases))
                  ((eq? head ':pointer)
                   (loop (cdr rest) word-bits fx-alist imm-alist (parse-repr-kv-list body) nan-alist aliases))
                  ((eq? head ':nan-box)
                   (loop (cdr rest) word-bits fx-alist imm-alist ptr-alist (parse-repr-kv-list body) aliases))
                  (else
                   (loop (cdr rest) word-bits fx-alist imm-alist ptr-alist nan-alist aliases)))))))))

(define (register-value-repr! spec)
  (validate-value-repr spec)
  (let* ((name (value-repr-name spec))
         (aliases (value-repr-section spec 'aliases))
         (all-names (cons name (if (list? aliases) aliases '()))))
    (for-each
      (lambda (sym)
        (let ((cur (car *value-repr-registry*)))
          (set-car! *value-repr-registry*
                    (cons (cons sym spec)
                          (let filter-out ((lst cur))
                            (cond
                              ((null? lst) '())
                              ((eq? (caar lst) sym) (filter-out (cdr lst)))
                              (else (cons (car lst) (filter-out (cdr lst))))))))))
      all-names)
    spec))

(define (get-value-repr name-or-spec)
  (cond
    ((value-repr? name-or-spec) name-or-spec)
    ((symbol? name-or-spec)
     (let ((entry (assq name-or-spec (car *value-repr-registry*))))
       (if entry
           (cdr entry)
           (value-repr-error! "get-value-repr: unknown value representation" name-or-spec))))
    (else
     (value-repr-error! "get-value-repr: expected symbol or value-repr descriptor" name-or-spec))))

(define (current-value-repr)
  (let ((cur (car *current-value-repr-cell*)))
    (if cur cur repr:scheme-64bit-tagged)))

(define (set-current-value-repr! name-or-spec)
  (let ((spec (get-value-repr name-or-spec)))
    (set-car! *current-value-repr-cell* spec)
    spec))

;; THREAT-836-4: Scoped context guard preventing representation leak across compilations
(define (with-value-repr name-or-spec thunk)
  (let ((prev (current-value-repr))
        (next (get-value-repr name-or-spec)))
    (set-car! *current-value-repr-cell* next)
    (let ((res (guard (ex (else
                           (set-car! *current-value-repr-cell* prev)
                           (raise ex)))
                 (thunk))))
      (set-car! *current-value-repr-cell* prev)
      res)))

;;; -----------------------------------------------------------------------
;;; 4. `define-value-repr` DSL Expander & Macro
;;; -----------------------------------------------------------------------

(define (expand-define-value-repr form)
  (if (and (pair? (cdr form)) (eq? (cadr form) ':bind-runtime-constants))
      (let* ((target (if (pair? (cddr form)) (caddr form) 'repr:scheme-64bit-tagged))
             (spec (get-value-repr target)))
        (repr-generate-runtime-printer-defs spec))
      (let ((name (cadr form))
            (clauses (cddr form)))
        (list 'define name
              (list 'register-value-repr!
                    (list 'make-value-repr-from-clauses
                          (list 'quote name)
                          (list 'quote clauses)))))))

(define-macro (define-value-repr . args)
  (expand-define-value-repr (cons 'define-value-repr args)))

(define (%nan-box-base-unit) 2251799813685248)
(define (default-nan-box-base) (* 4095 (%nan-box-base-unit)))

;;; -----------------------------------------------------------------------
;;; 5. Standard Value Representation Specifications
;;; -----------------------------------------------------------------------

;; 5.1 ULisp 64-bit Tagged Scheme Representation (Default)
(define repr:scheme-64bit-tagged
  (register-value-repr!
    (make-value-repr-from-clauses
      'repr:scheme-64bit-tagged
      '((:word-bits 64)
        (:aliases scheme-standard scheme-64bit-tagged)
        (:fixnum
          (:shift 2)
          (:tag-bits 0)
          (:tag-mask 3)
          (:step 4))
        (:immediates
          (:boolean-false 47)
          (:boolean-true  111)
          (:boolean-mask  -65)
          (:null          63)
          (:eof           79)
          (:void          111)
          (:char-shift    8)
          (:char-op-shift 6)
          (:char-tag      14)
          (:char-mask     255)
          (:symbol-shift  6)
          (:symbol-tag    2)
          (:symbol-mask   255))
        (:pointer
          (:align 8)
          (:tag-bits 0)
          (:tag-mask 7)
          (:untag-mask -8)
          (:pair-tag       1)
          (:closure-tag    1)
          (:string-tag     3)
          (:vector-tag     5)
          (:bytevector-tag 7)
          (:flonum-tag     11)
          (:flonum-cell-bytes 16)
          (:flonum-offset  -3))))))

(define scheme-standard repr:scheme-64bit-tagged)

;; 5.2 C-Language Unboxed Native Representation (Zero Tag Overhead)
(define repr:c-unboxed
  (register-value-repr!
    (make-value-repr-from-clauses
      'repr:c-unboxed
      '((:word-bits 64)
        (:aliases c-unboxed c-native)
        (:fixnum
          (:shift 0)
          (:tag-bits 0)
          (:tag-mask 0)
          (:step 1))
        (:immediates
          (:boolean-false 0)
          (:boolean-true  1)
          (:boolean-mask  -2)
          (:null          0)
          (:eof           -1)
          (:void          0)
          (:char-shift    0)
          (:char-op-shift 0)
          (:char-tag      0)
          (:char-mask     255)
          (:symbol-shift  0)
          (:symbol-tag    0)
          (:symbol-mask   0))
        (:pointer
          (:align 1)
          (:tag-bits 0)
          (:tag-mask 0)
          (:untag-mask -1)
          (:pair-tag       0)
          (:closure-tag    0)
          (:string-tag     0)
          (:vector-tag     0)
          (:bytevector-tag 0)
          (:flonum-tag     0)
          (:flonum-cell-bytes 8)
          (:flonum-offset  0))))))

(define c-unboxed repr:c-unboxed)

;; 5.3 64-bit IEEE 754 Quiet NaN-Boxing Representation
;; Quiet NaN base: 0x7FF8000000000000 = (* 4095 2251799813685248) = 9221120237041090560
;; 48-bit payload mask: 0x0000FFFFFFFFFFFF = 281474976710655
;; Tag unit (1 << 48): 281474976710656
(define repr:nan-boxing-64bit
  (register-value-repr!
    (make-value-repr-from-clauses
      'repr:nan-boxing-64bit
      '((:word-bits 64)
        (:aliases nan-boxing-64bit nan-boxed)
        (:fixnum
          (:shift 0)
          (:tag-bits 0)
          (:tag-mask 0)
          (:step 1))
        (:immediates
          (:boolean-false 2)
          (:boolean-true  3)
          (:boolean-mask  -2)
          (:null          4)
          (:eof           5)
          (:void          6)
          (:char-shift    8)
          (:char-op-shift 8)
          (:char-tag      7)
          (:char-mask     255)
          (:symbol-shift  8)
          (:symbol-tag    8)
          (:symbol-mask   255))
        (:pointer
          (:align 8)
          (:tag-bits 0)
          (:tag-mask 0)
          (:untag-mask -8)
          (:pair-tag       0)
          (:closure-tag    0)
          (:string-tag     0)
          (:vector-tag     0)
          (:bytevector-tag 0)
          (:flonum-tag     0)
          (:flonum-cell-bytes 8)
          (:flonum-offset  0))
        (:nan-box
          (:enabled #t)
          (:nan-base 0)
          (:payload-mask 281474976710655)
          (:tag-shift 48)
          (:tag-unit 281474976710656)
          (:flonum-nan-tag 0)
          (:fixnum-nan-tag 1)
          (:imm-nan-tag 2)
          (:pointer-nan-tag 3))))))

(define nan-boxing-64bit repr:nan-boxing-64bit)

;; 5.4 Guest Workbench 64-bit 3-bit Tagged Representation (DSN-33-04 §2.3 & Issue #944)
;; Low 3-bit tags: 0=Fixnum (61-bit signed), 1=Pair, 2=Symbol, 3=Closure,
;; 4=Vector, 5=Instance, 6=Flonum, 7=Special Immediates (#f=7, #t=15, nil=23, undef=31)
(define repr:guest-3bit-tagged
  (register-value-repr!
    (make-value-repr-from-clauses
      'repr:guest-3bit-tagged
      '((:word-bits 64)
        (:aliases guest-3bit-tagged guest-tagged)
        (:fixnum
          (:shift 3)
          (:tag-bits 0)
          (:tag-mask 7)
          (:step 8)
          (:min -1152921504606846976)
          (:max 1152921504606846975))
        (:immediates
          (:special-tag   7)
          (:special-shift 3)
          (:special-false 0)
          (:special-true  1)
          (:special-nil   2)
          (:special-undef 3)
          (:boolean-false 7)
          (:boolean-true  15)
          (:boolean-mask  -9)
          (:null          23)
          (:undef         31)
          (:eof           31)
          (:void          31)
          (:char-shift    8)
          (:char-op-shift 5)
          (:char-tag      15)
          (:char-mask     255)
          (:symbol-shift  3)
          (:symbol-tag    2)
          (:symbol-mask   7))
        (:pointer
          (:align 8)
          (:tag-bits 0)
          (:tag-mask 7)
          (:untag-mask -8)
          (:pair-tag       1)
          (:symbol-tag     2)
          (:closure-tag    3)
          (:vector-tag     4)
          (:instance-tag   5)
          (:flonum-tag     6)
          (:special-tag    7)
          (:string-tag     2)
          (:bytevector-tag 4)
          (:flonum-cell-bytes 16)
          (:flonum-offset  2))))))

(define guest-3bit-tagged repr:guest-3bit-tagged)
(define guest-tagged repr:guest-3bit-tagged)

;; Initialize default representation
(set-current-value-repr! repr:scheme-64bit-tagged)

;;; -----------------------------------------------------------------------
;;; 6. Representation Query & Immediate Encoding API
;;; -----------------------------------------------------------------------

(define (repr-nan-boxed-with? r)
  (if (value-repr-prop r 'nan-box ':enabled #f) #t #f))

(define repr-nan-boxed?
  (case-lambda
    (() (repr-nan-boxed-with? (current-value-repr)))
    ((opt-repr) (repr-nan-boxed-with? (get-value-repr opt-repr)))))

(define (repr-requires-boxing-with? r)
  (or (> (value-repr-prop r 'fixnum ':shift 0) 0)
      (> (value-repr-prop r 'fixnum ':tag-mask 0) 0)
      (repr-nan-boxed-with? r)))

(define repr-requires-boxing?
  (case-lambda
    (() (repr-requires-boxing-with? (current-value-repr)))
    ((opt-repr) (repr-requires-boxing-with? (get-value-repr opt-repr)))))

(define repr-fixnum-shift
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'fixnum ':shift 0))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'fixnum ':shift 0))))

(define repr-fixnum-tag
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'fixnum ':tag-bits 0))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'fixnum ':tag-bits 0))))

(define repr-fixnum-mask
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'fixnum ':tag-mask 0))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'fixnum ':tag-mask 0))))

(define (repr-arithmetic-shift n count)
  (cond
    ((= count 0) n)
    ((> count 0)
     (ctfe-arithmetic-shift n count))
    (else
     (let* ((denom (ctfe-arithmetic-shift 1 (- count)))
            (q (quotient n denom)))
       (if (and (< n 0) (not (= (* q denom) n)))
           (- q 1)
           q)))))

(define (repr-fixnum-step-with r)
  (let ((shift (value-repr-prop r 'fixnum ':shift 0)))
    (value-repr-prop r 'fixnum ':step (repr-arithmetic-shift 1 shift))))

(define repr-fixnum-step
  (case-lambda
    (() (repr-fixnum-step-with (current-value-repr)))
    ((opt-repr) (repr-fixnum-step-with (get-value-repr opt-repr)))))

(define (repr-encode-fixnum-with n r)
  (let ((shift (value-repr-prop r 'fixnum ':shift 0))
        (tag (value-repr-prop r 'fixnum ':tag-bits 0)))
    (if (repr-nan-boxed-with? r)
        (let* ((raw-nan-base (value-repr-prop r 'nan-box ':nan-base 0))
               (nan-base (if (= raw-nan-base 0) (default-nan-box-base) raw-nan-base))
               (tag-unit (value-repr-prop r 'nan-box ':tag-unit 281474976710656))
               (fx-nan-tag (value-repr-prop r 'nan-box ':fixnum-nan-tag 1))
               (mask (value-repr-prop r 'nan-box ':payload-mask 281474976710655)))
          (ctfe-bitwise-ior (+ nan-base (* fx-nan-tag tag-unit))
                            (ctfe-bitwise-and n mask)))
        (let ((shifted (repr-arithmetic-shift n shift)))
          (if (= tag 0)
              shifted
              (ctfe-bitwise-ior shifted tag))))))

(define repr-encode-fixnum
  (case-lambda
    ((n) (repr-encode-fixnum-with n (current-value-repr)))
    ((n opt-repr) (repr-encode-fixnum-with n (get-value-repr opt-repr)))))

(define (repr-decode-fixnum-with encoded r)
  (let ((shift (value-repr-prop r 'fixnum ':shift 0)))
    (if (repr-nan-boxed-with? r)
        (let* ((mask (value-repr-prop r 'nan-box ':payload-mask 281474976710655))
               (raw (ctfe-bitwise-and encoded mask))
               (sign-bit (repr-arithmetic-shift 1 47)))
          (if (>= raw sign-bit)
              (- raw (+ mask 1))
              raw))
        (repr-arithmetic-shift encoded (- shift)))))

(define repr-decode-fixnum
  (case-lambda
    ((encoded) (repr-decode-fixnum-with encoded (current-value-repr)))
    ((encoded opt-repr) (repr-decode-fixnum-with encoded (get-value-repr opt-repr)))))

(define (repr-encode-boolean-with b r)
  (if b
      (value-repr-prop r 'immediates ':boolean-true 111)
      (value-repr-prop r 'immediates ':boolean-false 47)))

(define repr-encode-boolean
  (case-lambda
    ((b) (repr-encode-boolean-with b (current-value-repr)))
    ((b opt-repr) (repr-encode-boolean-with b (get-value-repr opt-repr)))))

(define repr-boolean-mask
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':boolean-mask -65))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':boolean-mask -65))))

(define repr-encode-null
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':null 63))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':null 63))))

(define repr-encode-eof
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':eof 79))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':eof 79))))

(define repr-encode-void
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':void 111))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':void 111))))

(define repr-char-shift
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':char-shift 8))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':char-shift 8))))

(define repr-char-op-shift
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':char-op-shift 6))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':char-op-shift 6))))

(define repr-char-tag
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':char-tag 14))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':char-tag 14))))

(define repr-char-mask
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':char-mask 255))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':char-mask 255))))

(define (repr-encode-char-with ch r)
  (let ((code (if (char? ch) (char->integer ch) ch))
        (shift (value-repr-prop r 'immediates ':char-shift 8))
        (tag (value-repr-prop r 'immediates ':char-tag 14)))
    (+ (repr-arithmetic-shift code shift) tag)))

(define repr-encode-char
  (case-lambda
    ((ch) (repr-encode-char-with ch (current-value-repr)))
    ((ch opt-repr) (repr-encode-char-with ch (get-value-repr opt-repr)))))

(define repr-symbol-shift
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':symbol-shift 6))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':symbol-shift 6))))

(define repr-symbol-tag
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':symbol-tag 2))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':symbol-tag 2))))

(define repr-symbol-mask
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':symbol-mask 255))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':symbol-mask 255))))

(define (repr-encode-immediate-with expr r)
  (cond
    ((integer? expr) (repr-encode-fixnum-with expr r))
    ((boolean? expr) (repr-encode-boolean-with expr r))
    ((char? expr)    (repr-encode-char-with expr r))
    ((null? expr)    (value-repr-prop r 'immediates ':null 63))
    (else
     (value-repr-error! "repr-encode-immediate: unsupported immediate expression" expr))))

(define repr-encode-immediate
  (case-lambda
    ((expr) (repr-encode-immediate-with expr (current-value-repr)))
    ((expr opt-repr) (repr-encode-immediate-with expr (get-value-repr opt-repr)))))

;;; -----------------------------------------------------------------------
;;; 7. Heap Pointer Tag & Field Offset Calculator
;;; -----------------------------------------------------------------------

(define repr-pointer-align
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'pointer ':align 8))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'pointer ':align 8))))

(define repr-pointer-mask
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'pointer ':tag-mask 7))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'pointer ':tag-mask 7))))

(define (repr-pointer-untag-mask-with r)
  (value-repr-prop r 'pointer ':untag-mask (- (value-repr-prop r 'pointer ':align 8))))

(define repr-pointer-untag-mask
  (case-lambda
    (() (repr-pointer-untag-mask-with (current-value-repr)))
    ((opt-repr) (repr-pointer-untag-mask-with (get-value-repr opt-repr)))))

(define (repr-heap-tag-with kind r)
  (case kind
    ((pair)       (value-repr-prop r 'pointer ':pair-tag 1))
    ((symbol)     (value-repr-prop r 'pointer ':symbol-tag (value-repr-prop r 'immediates ':symbol-tag 2)))
    ((closure procedure) (value-repr-prop r 'pointer ':closure-tag 1))
    ((string)     (value-repr-prop r 'pointer ':string-tag 3))
    ((vector)     (value-repr-prop r 'pointer ':vector-tag 5))
    ((instance)   (value-repr-prop r 'pointer ':instance-tag 5))
    ((bytevector) (value-repr-prop r 'pointer ':bytevector-tag 7))
    ((flonum)     (value-repr-prop r 'pointer ':flonum-tag 11))
    ((special)    (value-repr-prop r 'pointer ':special-tag (value-repr-prop r 'immediates ':special-tag 7)))
    (else         (value-repr-prop r 'pointer ':tag-bits 0))))

(define repr-heap-tag
  (case-lambda
    ((kind) (repr-heap-tag-with kind (current-value-repr)))
    ((kind opt-repr) (repr-heap-tag-with kind (get-value-repr opt-repr)))))

(define (repr-field-offset-with kind byte-offset r)
  (- byte-offset (repr-heap-tag-with kind r)))

(define repr-field-offset
  (case-lambda
    ((kind byte-offset) (repr-field-offset-with kind byte-offset (current-value-repr)))
    ((kind byte-offset opt-repr) (repr-field-offset-with kind byte-offset (get-value-repr opt-repr)))))

(define (repr-untag-pointer-with ptr-val r)
  (if (repr-nan-boxed-with? r)
      (ctfe-bitwise-and ptr-val (repr-nan-box-payload-mask-with r))
      (ctfe-bitwise-and ptr-val (repr-pointer-untag-mask-with r))))

;;; -----------------------------------------------------------------------
;;; 7b. Guest Special Immediates, Fixnum Bounds & NaN-Boxing Helpers
;;; -----------------------------------------------------------------------

(define repr-special-tag
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':special-tag 7))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':special-tag 7))))

(define repr-special-shift
  (case-lambda
    (() (value-repr-prop (current-value-repr) 'immediates ':special-shift 3))
    ((opt-repr) (value-repr-prop (get-value-repr opt-repr) 'immediates ':special-shift 3))))

(define (repr-encode-special-with id r)
  (let ((shift (value-repr-prop r 'immediates ':special-shift 3))
        (tag (value-repr-prop r 'immediates ':special-tag 7)))
    (ctfe-bitwise-ior (repr-arithmetic-shift id shift) tag)))

(define repr-encode-special
  (case-lambda
    ((id) (repr-encode-special-with id (current-value-repr)))
    ((id opt-repr) (repr-encode-special-with id (get-value-repr opt-repr)))))

(define (repr-decode-special-with encoded r)
  (let ((shift (value-repr-prop r 'immediates ':special-shift 3)))
    (repr-arithmetic-shift encoded (- shift))))

(define repr-decode-special
  (case-lambda
    ((encoded) (repr-decode-special-with encoded (current-value-repr)))
    ((encoded opt-repr) (repr-decode-special-with encoded (get-value-repr opt-repr)))))

(define (repr-encode-undef-with r)
  (value-repr-prop r 'immediates ':undef (value-repr-prop r 'immediates ':void 111)))

(define repr-encode-undef
  (case-lambda
    (() (repr-encode-undef-with (current-value-repr)))
    ((opt-repr) (repr-encode-undef-with (get-value-repr opt-repr)))))

(define (repr-fixnum-min-with r)
  (let ((explicit (value-repr-prop r 'fixnum ':min #f)))
    (if explicit
        explicit
        (let ((shift (value-repr-prop r 'fixnum ':shift 0)))
          (- 0 (repr-arithmetic-shift 1 (- 62 shift)))))))

(define repr-fixnum-min
  (case-lambda
    (() (repr-fixnum-min-with (current-value-repr)))
    ((opt-repr) (repr-fixnum-min-with (get-value-repr opt-repr)))))

(define (repr-fixnum-max-with r)
  (let ((explicit (value-repr-prop r 'fixnum ':max #f)))
    (if explicit
        explicit
        (- 0 (+ (repr-fixnum-min-with r) 1)))))

(define repr-fixnum-max
  (case-lambda
    (() (repr-fixnum-max-with (current-value-repr)))
    ((opt-repr) (repr-fixnum-max-with (get-value-repr opt-repr)))))

(define (repr-nan-box-base-with r)
  (let ((raw (value-repr-prop r 'nan-box ':nan-base 0)))
    (if (= raw 0) (default-nan-box-base) raw)))

(define repr-nan-box-base
  (case-lambda
    (() (repr-nan-box-base-with (current-value-repr)))
    ((opt-repr) (repr-nan-box-base-with (get-value-repr opt-repr)))))

(define (repr-nan-box-payload-mask-with r)
  (value-repr-prop r 'nan-box ':payload-mask 281474976710655))

(define repr-nan-box-payload-mask
  (case-lambda
    (() (repr-nan-box-payload-mask-with (current-value-repr)))
    ((opt-repr) (repr-nan-box-payload-mask-with (get-value-repr opt-repr)))))

(define (repr-nan-box-tag-shift-with r)
  (value-repr-prop r 'nan-box ':tag-shift 48))

(define repr-nan-box-tag-shift
  (case-lambda
    (() (repr-nan-box-tag-shift-with (current-value-repr)))
    ((opt-repr) (repr-nan-box-tag-shift-with (get-value-repr opt-repr)))))

(define (repr-nan-box-tag-unit-with r)
  (value-repr-prop r 'nan-box ':tag-unit 281474976710656))

(define repr-nan-box-tag-unit
  (case-lambda
    (() (repr-nan-box-tag-unit-with (current-value-repr)))
    ((opt-repr) (repr-nan-box-tag-unit-with (get-value-repr opt-repr)))))

(define (repr-nan-box-subtag-with kind r)
  (case kind
    ((flonum)    (value-repr-prop r 'nan-box ':flonum-nan-tag 0))
    ((fixnum)    (value-repr-prop r 'nan-box ':fixnum-nan-tag 1))
    ((imm special) (value-repr-prop r 'nan-box ':imm-nan-tag 2))
    ((pointer)   (value-repr-prop r 'nan-box ':pointer-nan-tag 3))
    (else        0)))

(define repr-nan-box-subtag
  (case-lambda
    ((kind) (repr-nan-box-subtag-with kind (current-value-repr)))
    ((kind opt-repr) (repr-nan-box-subtag-with kind (get-value-repr opt-repr)))))

(define (repr-nan-boxed-value?-with v r)
  (and (integer? v)
       (>= v (repr-nan-box-base-with r))))

(define repr-nan-boxed-value?
  (case-lambda
    ((v) (repr-nan-boxed-value?-with v (current-value-repr)))
    ((v opt-repr) (repr-nan-boxed-value?-with v (get-value-repr opt-repr)))))

(define (repr-nan-tag-of-with v r)
  (if (not (repr-nan-boxed-value?-with v r))
      (repr-nan-box-subtag-with 'flonum r)
      (quotient (- v (repr-nan-box-base-with r))
                (repr-nan-box-tag-unit-with r))))

(define repr-nan-tag-of
  (case-lambda
    ((v) (repr-nan-tag-of-with v (current-value-repr)))
    ((v opt-repr) (repr-nan-tag-of-with v (get-value-repr opt-repr)))))

(define (repr-nan-box-pointer-with ptr r)
  (+ (+ (repr-nan-box-base-with r)
        (* (repr-nan-box-subtag-with 'pointer r) (repr-nan-box-tag-unit-with r)))
     ptr))

(define repr-nan-box-pointer
  (case-lambda
    ((ptr) (repr-nan-box-pointer-with ptr (current-value-repr)))
    ((ptr opt-repr) (repr-nan-box-pointer-with ptr (get-value-repr opt-repr)))))

(define (repr-nan-pointer?-with v r)
  (and (repr-nan-boxed-value?-with v r)
       (= (repr-nan-tag-of-with v r) (repr-nan-box-subtag-with 'pointer r))))

(define repr-nan-pointer?
  (case-lambda
    ((v) (repr-nan-pointer?-with v (current-value-repr)))
    ((v opt-repr) (repr-nan-pointer?-with v (get-value-repr opt-repr)))))

(define (repr-nan-unbox-pointer-with v r)
  (ctfe-bitwise-and v (repr-nan-box-payload-mask-with r)))

(define repr-nan-unbox-pointer
  (case-lambda
    ((v) (repr-nan-unbox-pointer-with v (current-value-repr)))
    ((v opt-repr) (repr-nan-unbox-pointer-with v (get-value-repr opt-repr)))))

(define (repr-nan-box-special-with id r)
  (+ (+ (repr-nan-box-base-with r)
        (* (repr-nan-box-subtag-with 'imm r) (repr-nan-box-tag-unit-with r)))
     id))

(define repr-nan-box-special
  (case-lambda
    ((id) (repr-nan-box-special-with id (current-value-repr)))
    ((id opt-repr) (repr-nan-box-special-with id (get-value-repr opt-repr)))))

(define (repr-nan-special?-with v r)
  (and (repr-nan-boxed-value?-with v r)
       (= (repr-nan-tag-of-with v r) (repr-nan-box-subtag-with 'imm r))))

(define repr-nan-special?
  (case-lambda
    ((v) (repr-nan-special?-with v (current-value-repr)))
    ((v opt-repr) (repr-nan-special?-with v (get-value-repr opt-repr)))))

(define (repr-nan-unbox-special-with v r)
  (ctfe-bitwise-and v (repr-nan-box-payload-mask-with r)))

(define repr-nan-unbox-special
  (case-lambda
    ((v) (repr-nan-unbox-special-with v (current-value-repr)))
    ((v opt-repr) (repr-nan-unbox-special-with v (get-value-repr opt-repr)))))

;;; -----------------------------------------------------------------------
;;; 7c. Unified GC Heap Tag Queries, Polymorphic Value Formatter & Printer SSOT
;;; -----------------------------------------------------------------------

(define (%repr-insert-sorted-unique x sorted)
  (cond
    ((null? sorted) (list x))
    ((= x (car sorted)) sorted)
    ((< x (car sorted)) (cons x sorted))
    (else (cons (car sorted) (%repr-insert-sorted-unique x (cdr sorted))))))

(define (repr-gc-heap-tags-with r)
  (let ((align (value-repr-prop r 'pointer ':align 8)))
    (cond
      ((repr-nan-boxed-with? r)
       (list (repr-nan-box-subtag-with 'pointer r)))
      ((<= align 1)
       '())
      (else
       (let ((special-tag (value-repr-prop r 'immediates ':special-tag -1))
             (prop-keys '(:pair-tag :symbol-tag :closure-tag :string-tag
                          :vector-tag :instance-tag :flonum-tag :bytevector-tag)))
         (let loop ((ks prop-keys) (res '()))
           (if (null? ks)
               res
               (let ((t (value-repr-prop r 'pointer (car ks) -1)))
                 (if (and (integer? t)
                          (> t 0)
                          (< t align)
                          (not (= t special-tag)))
                     (loop (cdr ks) (%repr-insert-sorted-unique t res))
                     (loop (cdr ks) res))))))))))

(define repr-gc-heap-tags
  (case-lambda
    (() (repr-gc-heap-tags-with (current-value-repr)))
    ((opt-repr) (repr-gc-heap-tags-with (get-value-repr opt-repr)))))

(define (repr-gc-heap-value?-with val r)
  (if (repr-nan-boxed-with? r)
      (repr-nan-pointer?-with val r)
      (and (integer? val)
           (> val 0)
           (let ((ptr-mask (value-repr-prop r 'pointer ':tag-mask 7))
                 (untag-mask (repr-pointer-untag-mask-with r))
                 (align (value-repr-prop r 'pointer ':align 8)))
             (and (> ptr-mask 0)
                  (>= (ctfe-bitwise-and val untag-mask) align)
                  (not (= val (value-repr-prop r 'immediates ':boolean-false -1)))
                  (not (= val (value-repr-prop r 'immediates ':boolean-true -1)))
                  (not (= val (value-repr-prop r 'immediates ':null -1)))
                  (not (= val (value-repr-prop r 'immediates ':eof -1)))
                  (not (= val (value-repr-prop r 'immediates ':void -1)))
                  (not (= val (value-repr-prop r 'immediates ':undef -1)))
                  (if (member (ctfe-bitwise-and val ptr-mask)
                              (repr-gc-heap-tags-with r))
                      #t
                      #f))))))

(define repr-gc-heap-value?
  (case-lambda
    ((val) (repr-gc-heap-value?-with val (current-value-repr)))
    ((val opt-repr) (repr-gc-heap-value?-with val (get-value-repr opt-repr)))))

(define (repr-gc-untag-ptr-with val r)
  (if (repr-nan-boxed-with? r)
      (repr-nan-unbox-pointer-with val r)
      (ctfe-bitwise-and val (repr-pointer-untag-mask-with r))))

(define repr-gc-untag-ptr
  (case-lambda
    ((val) (repr-gc-untag-ptr-with val (current-value-repr)))
    ((val opt-repr) (repr-gc-untag-ptr-with val (get-value-repr opt-repr)))))

(define (repr-format-tagged-value-with val r)
  (if (repr-nan-boxed-with? r)
      (if (not (repr-nan-boxed-value?-with val r))
          (string-append "#<flonum:" (if (number? val) (number->string val) "?") ">")
          (let ((subtag (repr-nan-tag-of-with val r)))
            (cond
              ((= subtag (repr-nan-box-subtag-with 'fixnum r))
               (number->string (repr-decode-fixnum-with val r)))
              ((= subtag (repr-nan-box-subtag-with 'imm r))
               (let ((code (repr-nan-unbox-special-with val r)))
                 (cond
                   ((= code 0) "#f")
                   ((= code 1) "#t")
                   ((= code 2) "()")
                   ((= code 3) "#<undef>")
                   (else (string-append "#<imm:" (number->string code) ">")))))
              ((= subtag (repr-nan-box-subtag-with 'pointer r))
               (string-append "#<ptr:" (number->string (repr-nan-unbox-pointer-with val r)) ">"))
              (else
               (string-append "#<nan:" (number->string val) ">")))))
      (if (not (integer? val))
          "#<non-int>"
          (let ((fx-mask (value-repr-prop r 'fixnum ':tag-mask 0))
                (fx-tag (value-repr-prop r 'fixnum ':tag-bits 0))
                (special-tag (value-repr-prop r 'immediates ':special-tag -1))
                (ptr-mask (value-repr-prop r 'pointer ':tag-mask 7)))
            (cond
              ((and (> fx-mask 0) (= (ctfe-bitwise-and val fx-mask) fx-tag))
               (number->string (repr-decode-fixnum-with val r)))
              ((and (> special-tag 0) (= (ctfe-bitwise-and val ptr-mask) special-tag))
               (let ((code (repr-decode-special-with val r)))
                 (cond
                   ((= code (value-repr-prop r 'immediates ':special-false 0)) "#f")
                   ((= code (value-repr-prop r 'immediates ':special-true 1)) "#t")
                   ((= code (value-repr-prop r 'immediates ':special-nil 2)) "()")
                   ((= code (value-repr-prop r 'immediates ':special-undef 3)) "#<undef>")
                   (else (string-append "#<special:" (number->string code) ">")))))
              ((> special-tag 0)
               (let ((ptag (ctfe-bitwise-and val ptr-mask))
                     (untagged (repr-untag-pointer-with val r)))
                 (cond
                   ((= ptag (repr-heap-tag-with 'pair r))     (string-append "#<pair:" (number->string untagged) ">"))
                   ((= ptag (repr-heap-tag-with 'symbol r))   (string-append "#<symbol:" (number->string untagged) ">"))
                   ((= ptag (repr-heap-tag-with 'closure r))  (string-append "#<closure:" (number->string untagged) ">"))
                   ((= ptag (repr-heap-tag-with 'vector r))   (string-append "#<vector:" (number->string untagged) ">"))
                   ((= ptag (repr-heap-tag-with 'instance r)) (string-append "#<instance:" (number->string untagged) ">"))
                   ((= ptag (repr-heap-tag-with 'flonum r))   (string-append "#<flonum:" (number->string untagged) ">"))
                   (else (string-append "#<unknown:" (number->string val) ">")))))
              ((= val (value-repr-prop r 'immediates ':boolean-false 47)) "#f")
              ((= val (value-repr-prop r 'immediates ':boolean-true 111)) "#t")
              ((= val (value-repr-prop r 'immediates ':null 63)) "()")
              ((= val (value-repr-prop r 'immediates ':eof 79)) "#<eof>")
              ((and (= (ctfe-bitwise-and val (value-repr-prop r 'immediates ':char-mask 255))
                       (value-repr-prop r 'immediates ':char-tag 14))
                    (> (value-repr-prop r 'immediates ':char-mask 255) 0))
               (let ((c (ctfe-bitwise-and (repr-arithmetic-shift val (- (value-repr-prop r 'immediates ':char-shift 8)))
                                          255)))
                 (cond
                   ((= c 10) "#\\newline")
                   ((= c 32) "#\\space")
                   ((= c 9)  "#\\tab")
                   ((= c 13) "#\\return")
                   (else (string-append "#\\" (list->string (list (integer->char c))))))))
              ((= (ctfe-bitwise-and val (value-repr-prop r 'immediates ':symbol-mask 255))
                  (value-repr-prop r 'immediates ':symbol-tag 2))
               (let* ((sym-shift (+ (value-repr-prop r 'immediates ':symbol-shift 6)
                                    (value-repr-prop r 'fixnum ':shift 2)))
                      (sym-id (repr-arithmetic-shift val (- sym-shift))))
                 (string-append "#<symbol-" (number->string sym-id) ">")))
              (else
               (let ((ptag (ctfe-bitwise-and val ptr-mask))
                     (untagged (repr-untag-pointer-with val r)))
                 (cond
                   ((= ptag (repr-heap-tag-with 'pair r))       (string-append "#<pair:" (number->string untagged) ">"))
                   ((= ptag (repr-heap-tag-with 'string r))     (string-append "#<string:" (number->string untagged) ">"))
                   ((= ptag (repr-heap-tag-with 'vector r))     (string-append "#<vector:" (number->string untagged) ">"))
                   ((= ptag (repr-heap-tag-with 'bytevector r)) (string-append "#<bytevector:" (number->string untagged) ">"))
                   (else (string-append "#<unknown:" (number->string val) ">"))))))))))

(define repr-format-tagged-value
  (case-lambda
    ((val) (repr-format-tagged-value-with val (current-value-repr)))
    ((val opt-repr) (repr-format-tagged-value-with val (get-value-repr opt-repr)))))

(define (repr-runtime-constant-alist r)
  (let* ((fx-mask (value-repr-prop r 'fixnum ':tag-mask 0))
         (fx-tag (value-repr-prop r 'fixnum ':tag-bits 0))
         (fx-shift (value-repr-prop r 'fixnum ':shift 0))
         (ptr-mask (value-repr-prop r 'pointer ':tag-mask 7))
         (sym-shift (value-repr-prop r 'immediates ':symbol-full-shift
                                     (+ (value-repr-prop r 'immediates ':symbol-shift 6)
                                        fx-shift))))
    (list
      (cons '*fixnum-mask*     fx-mask)
      (cons '*fixnum-tag*      fx-tag)
      (cons '*fixnum-shift*    fx-shift)
      (cons '*pair-mask*       ptr-mask)
      (cons '*pair-tag*        (repr-heap-tag-with 'pair r))
      (cons '*string-mask*     ptr-mask)
      (cons '*string-tag*      (repr-heap-tag-with 'string r))
      (cons '*vector-mask*     ptr-mask)
      (cons '*vector-tag*      (repr-heap-tag-with 'vector r))
      (cons '*bytevector-mask* ptr-mask)
      (cons '*bytevector-tag*  (repr-heap-tag-with 'bytevector r))
      (cons '*char-mask*       (value-repr-prop r 'immediates ':char-mask 255))
      (cons '*char-tag*        (value-repr-prop r 'immediates ':char-tag 14))
      (cons '*char-shift*      (value-repr-prop r 'immediates ':char-shift 8))
      (cons '*symbol-mask*     (value-repr-prop r 'immediates ':symbol-mask 255))
      (cons '*symbol-tag*      (value-repr-prop r 'immediates ':symbol-tag 2))
      (cons '*symbol-shift*    sym-shift)
      (cons '*bool-false*      (value-repr-prop r 'immediates ':boolean-false 47))
      (cons '*bool-true*       (value-repr-prop r 'immediates ':boolean-true 111))
      (cons '*empty-list*      (value-repr-prop r 'immediates ':null 63))
      (cons '*eof-object*      (value-repr-prop r 'immediates ':eof 79)))))

(define (repr-generate-runtime-printer-defs r)
  (cons 'begin
        (map (lambda (kv) (list 'define (car kv) (cdr kv)))
             (repr-runtime-constant-alist r))))

;;; -----------------------------------------------------------------------
;;; 8. Boxing & Unboxing LIR Code Generators
;;; -----------------------------------------------------------------------

(define (repr-emit-box-fixnum-with dst src r)
  (let ((shift (value-repr-prop r 'fixnum ':shift 0))
        (tag (value-repr-prop r 'fixnum ':tag-bits 0))
        (mov-prefix (if (equal? dst src) '() (list (list '%mov dst src)))))
    (cond
      ((and (= shift 0) (= tag 0))
       mov-prefix)
      ((= tag 0)
       (append mov-prefix (list (list '%shl dst shift))))
      ((= shift 0)
       (append mov-prefix (list (list '%bit-or dst tag))))
      (else
       (append mov-prefix
               (list (list '%shl dst shift)
                     (list '%bit-or dst tag)))))))

(define repr-emit-box-fixnum
  (case-lambda
    ((dst src) (repr-emit-box-fixnum-with dst src (current-value-repr)))
    ((dst src opt-repr) (repr-emit-box-fixnum-with dst src (get-value-repr opt-repr)))))

(define (repr-emit-unbox-fixnum-with dst src r)
  (let ((shift (value-repr-prop r 'fixnum ':shift 0))
        (mov-prefix (if (equal? dst src) '() (list (list '%mov dst src)))))
    (if (= shift 0)
        mov-prefix
        (append mov-prefix (list (list '%sar dst shift))))))

(define repr-emit-unbox-fixnum
  (case-lambda
    ((dst src) (repr-emit-unbox-fixnum-with dst src (current-value-repr)))
    ((dst src opt-repr) (repr-emit-unbox-fixnum-with dst src (get-value-repr opt-repr)))))

(define (repr-emit-box-flonum-with dst src r)
  (let* ((fl-tag (repr-heap-tag-with 'flonum r))
         (cell-bytes (value-repr-prop r 'pointer ':flonum-cell-bytes 16))
         (fl-offset (value-repr-prop r 'pointer ':flonum-offset (- 8 fl-tag))))
    (if (or (not (repr-requires-boxing-with? r)) (repr-nan-boxed-with? r) (= fl-tag 0))
        ;; Unboxed or NaN-boxed float representation: no heap allocation needed
        (if (equal? dst src)
            '()
            (list (list '%fmov dst src)))
        ;; Heap-allocated boxed flonum cell
        (list (list '%mov dst '%r12)
              (list '%add dst fl-tag)
              (list '%add '%r12 cell-bytes)
              (list '%store-typed 'f64 dst fl-offset src)))))

(define repr-emit-box-flonum
  (case-lambda
    ((dst src) (repr-emit-box-flonum-with dst src (current-value-repr)))
    ((dst src opt-repr) (repr-emit-box-flonum-with dst src (get-value-repr opt-repr)))))

(define (repr-emit-unbox-flonum-with dst src r)
  (let* ((fl-tag (repr-heap-tag-with 'flonum r))
         (fl-offset (value-repr-prop r 'pointer ':flonum-offset (- 8 fl-tag))))
    (if (or (not (repr-requires-boxing-with? r)) (repr-nan-boxed-with? r) (= fl-tag 0))
        (if (equal? dst src)
            '()
            (list (list '%fmov dst src)))
        (list (list '%load-typed 'f64 dst src fl-offset)))))

(define repr-emit-unbox-flonum
  (case-lambda
    ((dst src) (repr-emit-unbox-flonum-with dst src (current-value-repr)))
    ((dst src opt-repr) (repr-emit-unbox-flonum-with dst src (get-value-repr opt-repr)))))

(define (repr-emit-type-tag-check dst src mask expected-tag)
  (let ((mov-prefix (if (equal? dst src) '() (list (list '%mov dst src)))))
    (append mov-prefix
            (list (list '%bit-and dst mask)
                  (list '%cmp dst expected-tag)
                  (list '%set-boolean dst "sete")))))

;;; =======================================================================
;;; Data Plane 64-bit Single-Word Representation & Tag Stripping Engine
;;; Conforms to DSN-33-03 §7.3 & Issue #884
;;; =======================================================================

(define *dataplane-tag-mask* 7)     ; 0b111 (3-bit tag)
(define *dataplane-ptr-mask* -8)    ; 0xFFFFFFFFFFFFFFF8

(define (data-plane-pack-word ptr tag)
  (bitwise-ior (bitwise-and ptr *dataplane-ptr-mask*)
               (bitwise-and tag *dataplane-tag-mask*)))

(define (data-plane-strip-tag word)
  (bitwise-and word *dataplane-ptr-mask*))

(define (data-plane-extract-tag word)
  (bitwise-and word *dataplane-tag-mask*))

(define (data-plane-tag-match? word expected-tag)
  (= (data-plane-extract-tag word) expected-tag))

;; LIR-level Tag Stripping Optimizer:
;; Eliminates redundant type-tag check sequences (%bit-and + %cmp + %set-boolean)
;; when accessing variables that are statically proven to conform to known Data Plane types.
(define (optimize-dataplane-tag-stripping insts known-typed-vars)
  (let loop ((is insts) (acc '()))
    (cond
      ((null? is) (reverse acc))
      ;; Detect pattern:
      ;;   (%bit-and dst src 7)
      ;;   (%cmp dst expected-tag)
      ;;   (%set-boolean dst "sete")
      ((and (pair? is)
            (pair? (cdr is))
            (pair? (cddr is))
            (let ((i1 (car is))
                  (i2 (cadr is))
                  (i3 (caddr is)))
              (and (pair? i1) (eq? (car i1) '%bit-and)
                   (pair? (cdddr i1)) (equal? (cadddr i1) 7)
                   (pair? i2) (eq? (car i2) '%cmp)
                   (pair? i3) (eq? (car i3) '%set-boolean)
                   (let ((src (caddr i1)))
                     (memq src known-typed-vars)))))
       (let* ((i1 (car is))
              (dst (cadr i1))
              (rest (cdddr is)))
         (loop rest (cons (list '%mov dst 1) acc))))
      (else
       (loop (cdr is) (cons (car is) acc))))))
