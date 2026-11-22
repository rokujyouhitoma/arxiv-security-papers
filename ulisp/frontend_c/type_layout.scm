;;; =======================================================================
;;; ULisp C99 Frontend: SysV AMD64 Type Layout, Bitfields & ABI Classifier
;;; Conforms to System V AMD64 psABI §3.1/§3.2.3, ISO C99 §6.7.2, Issue #918
;;; Zero local `set!` (ULisp AOT safe).
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Object Size Bounds & Checked Integer Arithmetic (CWE-190)
;;; -----------------------------------------------------------------------

(define *c99-max-object-size* #x7fffffff) ; 2 GiB - 1 signed object size ceiling

(define (c99-checked-add a b . maybe-err)
  (let ((err-fn (if (pair? maybe-err) (car maybe-err) #f)))
    (if (or (< a 0) (< b 0) (> b (- *c99-max-object-size* a)))
        (if err-fn
            (err-fn "C99-LAY-004" "Object size overflow exceeds SysV C99 maximum object size (CWE-190)")
            (error "Object size overflow" (list a b)))
        (+ a b))))

(define (c99-checked-mul a b . maybe-err)
  (let ((err-fn (if (pair? maybe-err) (car maybe-err) #f)))
    (cond
      ((or (< a 0) (< b 0))
       (if err-fn
           (err-fn "C99-LAY-004" "Negative object size or count in layout computation (CWE-190)")
           (error "Negative size" (list a b))))
      ((or (= a 0) (= b 0)) 0)
      ((> a (quotient *c99-max-object-size* b))
       (if err-fn
           (err-fn "C99-LAY-004" "Object size multiplication overflow exceeds maximum object size (CWE-190)")
           (error "Object size overflow" (list a b))))
      (else (* a b)))))

(define (c99-align-up-checked n align . maybe-err)
  (let ((err-fn (if (pair? maybe-err) (car maybe-err) #f)))
    (if (<= align 1)
        n
        (let ((rem (modulo n align)))
          (if (= rem 0)
              n
              (c99-checked-add n (- align rem) err-fn))))))

;;; -----------------------------------------------------------------------
;;; 2. Layout Records & Scoped Layout Environment (<c-layout-env>)
;;; -----------------------------------------------------------------------

(define-record-type <c-field-layout>
  (%make-c-field-layout name ctype offset bit-offset bit-width storage-unit-offset storage-unit-type anon-chain)
  c-field-layout?
  (name                c-field-layout-name)
  (ctype               c-field-layout-ctype)
  (offset              c-field-layout-offset)
  (bit-offset          c-field-layout-bit-offset)
  (bit-width           c-field-layout-bit-width)
  (storage-unit-offset c-field-layout-storage-unit-offset)
  (storage-unit-type   c-field-layout-storage-unit-type)
  (anon-chain          c-field-layout-anon-chain))

(define-record-type <c-struct-layout>
  (%make-c-struct-layout tag-id kind tag size align fields direct-fields has-fam? complete? eightbytes)
  c-struct-layout?
  (tag-id        c-struct-layout-tag-id)
  (kind          c-struct-layout-kind)
  (tag           c-struct-layout-tag)
  (size          c-struct-layout-size          c-struct-layout-size-set!)
  (align         c-struct-layout-align         c-struct-layout-align-set!)
  (fields        c-struct-layout-fields        c-struct-layout-fields-set!)
  (direct-fields c-struct-layout-direct-fields c-struct-layout-direct-fields-set!)
  (has-fam?      c-struct-layout-has-fam?      c-struct-layout-has-fam?-set!)
  (complete?     c-struct-layout-complete?     c-struct-layout-complete?-set!)
  (eightbytes    c-struct-layout-eightbytes    c-struct-layout-eightbytes-set!))

(define-record-type <c-enum-layout>
  (%make-c-enum-layout tag-id tag complete? enumerators)
  c-enum-layout?
  (tag-id      c-enum-layout-tag-id)
  (tag         c-enum-layout-tag)
  (complete?   c-enum-layout-complete?   c-enum-layout-complete?-set!)
  (enumerators c-enum-layout-enumerators c-enum-layout-enumerators-set!))

(define-record-type <c-layout-env>
  (%make-c-layout-env next-id vec-box)
  c-layout-env?
  (next-id c-layout-env-next-id)
  (vec-box c-layout-env-vec-box))

(define (make-c99-layout-env)
  (%make-c-layout-env (cons 0 '()) (cons (make-vector 64 #f) '())))

(define (c99-layout-env-alloc-tag-id! lenv)
  (let* ((box (c-layout-env-next-id lenv))
         (id (car box)))
    (set-car! box (+ id 1))
    id))

(define (%c99-layout-ensure-cap! lenv idx)
  (let* ((vbox (c-layout-env-vec-box lenv))
         (vec (car vbox))
         (cap (vector-length vec)))
    (if (>= idx cap)
        (let loop ((new-cap (* cap 2)))
          (if (<= new-cap idx)
              (loop (* new-cap 2))
              (let ((nvec (make-vector new-cap #f)))
                (let copy ((i 0))
                  (if (< i cap)
                      (begin
                        (vector-set! nvec i (vector-ref vec i))
                        (copy (+ i 1)))))
                (set-car! vbox nvec)))))))

(define (c99-layout-env-set! lenv tag-id entry)
  (%c99-layout-ensure-cap! lenv tag-id)
  (vector-set! (car (c-layout-env-vec-box lenv)) tag-id entry)
  entry)

(define (c99-layout-env-ref lenv tag-id)
  (let ((vec (car (c-layout-env-vec-box lenv))))
    (if (and (integer? tag-id) (>= tag-id 0) (< tag-id (vector-length vec)))
        (vector-ref vec tag-id)
        #f)))

(define (%c-layout-env-lookup-by-tag lenv kind tag-sym)
  (let ((vec (car (c-layout-env-vec-box lenv)))
        (limit (car (c-layout-env-next-id lenv))))
    (let loop ((i (- limit 1)))
      (if (< i 0)
          #f
          (let ((e (vector-ref vec i)))
            (if (and (c-struct-layout? e)
                     (eq? (c-struct-layout-kind e) kind)
                     (eq? (c-struct-layout-tag e) tag-sym))
                e
                (loop (- i 1))))))))

(define (c-layout-env-lookup-struct lenv tag-sym)
  (%c-layout-env-lookup-by-tag lenv 'struct tag-sym))

(define (c-layout-env-lookup-union lenv tag-sym)
  (%c-layout-env-lookup-by-tag lenv 'union tag-sym))

(define (c99-make-incomplete-struct-layout tag-id kind tag)
  (%make-c-struct-layout tag-id kind tag 0 1 '() '() #f #f #f))

(define (c99-make-incomplete-enum-layout tag-id tag)
  (%make-c-enum-layout tag-id tag #f '()))

;;; -----------------------------------------------------------------------
;;; 3. Completeness, Size, Alignment & Field Lookup Queries
;;; -----------------------------------------------------------------------

(define (c-type-layout-in lenv ty)
  (cond
    ((not lenv) #f)
    ((or (c-struct-ref-type? ty) (c-union-ref-type? ty))
     (c99-layout-env-ref lenv (c-tag-ref-id ty)))
    (else #f)))

(define (c-type-complete? lenv ty)
  (cond
    ((eq? ty 'void) #f)
    ((or (c-arithmetic-type? ty) (c-pointer-type? ty) (c-function-type? ty))
     (if (c-enum-ref-type? ty)
         (let ((el (c99-layout-env-ref lenv (c-tag-ref-id ty))))
           (if el (c-enum-layout-complete? el) #t))
         #t))
    ((c-array-type? ty)
     (let ((len (c-array-length ty)))
       (and (integer? len)
            (>= len 0)
            (c-type-complete? lenv (c-array-elem ty)))))
    ((or (c-struct-ref-type? ty) (c-union-ref-type? ty))
     (let ((sl (c-type-layout-in lenv ty)))
       (and sl (c-struct-layout-complete? sl) #t)))
    ((or (c-struct-type? ty) (c-union-type? ty)) #t)
    (else #f)))

(define (c-type-has-fam? lenv ty)
  (let ((sl (c-type-layout-in lenv ty)))
    (and sl (c-struct-layout-has-fam? sl) #t)))

(define (c-type-size-in lenv t . maybe-err)
  (let ((err-fn (if (pair? maybe-err) (car maybe-err) #f)))
    (cond
      ((eq? t 'void) 0)
      ((memq t '(bool i8 u8)) 1)
      ((memq t '(i16 u16)) 2)
      ((memq t '(i32 u32 f32)) 4)
      ((memq t '(i64 u64 f64)) 8)
      ((c-enum-type? t) 4)
      ((c-pointer-type? t) 8)
      ((c-function-type? t) 8)
      ((c-array-type? t)
       (let ((cnt (c-array-length t))
             (esz (c-type-size-in lenv (c-array-elem t) err-fn)))
         (if (integer? cnt)
             (c99-checked-mul cnt esz err-fn)
             esz)))
      ((or (c-struct-ref-type? t) (c-union-ref-type? t))
       (let ((sl (c-type-layout-in lenv t)))
         (if sl
             (c-struct-layout-size sl)
             (c-type-size t))))
      (else (c-type-size t)))))

(define (c-type-align-in lenv t)
  (cond
    ((eq? t 'void) 1)
    ((memq t '(bool i8 u8)) 1)
    ((memq t '(i16 u16)) 2)
    ((memq t '(i32 u32 f32)) 4)
    ((memq t '(i64 u64 f64)) 8)
    ((c-enum-type? t) 4)
    ((c-pointer-type? t) 8)
    ((c-function-type? t) 8)
    ((c-array-type? t) (c-type-align-in lenv (c-array-elem t)))
    ((or (c-struct-ref-type? t) (c-union-ref-type? t))
     (let ((sl (c-type-layout-in lenv t)))
       (if sl
           (c-struct-layout-align sl)
           1)))
    (else (c-type-align t))))

(define (%c99-storage-unit-lir-type bytes)
  (case bytes
    ((1) 'u8)
    ((2) 'u16)
    ((4) 'u32)
    (else 'u64)))

(define (c-struct-layout-find-field lenv agg-ty field-sym)
  (let ((sl (c-type-layout-in lenv agg-ty)))
    (if (not sl)
        #f
        (let loop ((fs (c-struct-layout-fields sl)))
          (cond
            ((null? fs) #f)
            ((eq? (c-field-layout-name (car fs)) field-sym) (car fs))
            (else (loop (cdr fs))))))))

;;; -----------------------------------------------------------------------
;;; 4. SysV AMD64 Struct / Union / Bitfield / FAM / Anonymous Layout Engine
;;; -----------------------------------------------------------------------
;;; Member specs passed in: list of (name ctype bit-width-or-#f)
;;; - Normal member: (sym ctype #f)
;;; - FAM member: (sym (array elem #f) #f)
;;; - Named bitfield: (sym int-ctype width)
;;; - Unnamed bitfield / : 0: (#f int-ctype width)
;;; - Anonymous struct/union: (#f aggregate-ref-ctype #f)

(define (%c99-shift-anon-field fl base-off parent-idx)
  (%make-c-field-layout
   (c-field-layout-name fl)
   (c-field-layout-ctype fl)
   (+ base-off (c-field-layout-offset fl))
   (c-field-layout-bit-offset fl)
   (c-field-layout-bit-width fl)
   (if (c-field-layout-storage-unit-offset fl)
       (+ base-off (c-field-layout-storage-unit-offset fl))
       #f)
   (c-field-layout-storage-unit-type fl)
   (cons parent-idx (or (c-field-layout-anon-chain fl) '()))))

(define (c99-compute-struct-layout! lenv tag-id kind tag member-specs . maybe-err)
  (let ((err-fn (if (pair? maybe-err) (car maybe-err) #f))
        (is-union? (eq? kind 'union)))
    (let loop ((ms member-specs)
               (idx 0)
               (bit-pos 0)
               (max-bytes 0)
               (max-align 1)
               (has-fam? #f)
               (seen-names '())
               (rev-direct '())
               (rev-fields '()))
      (if (null? ms)
          (let* ((raw-bytes (if is-union?
                                max-bytes
                                (if (= bit-pos 0)
                                    0
                                    (quotient (+ bit-pos 7) 8))))
                 (total-sz (if (= raw-bytes 0)
                               0
                               (c99-align-up-checked raw-bytes max-align err-fn)))
                 (existing (and tag-id (c99-layout-env-ref lenv tag-id)))
                 (sl (if existing
                         existing
                         (%make-c-struct-layout tag-id kind tag 0 1 '() '() #f #f #f))))
            (c-struct-layout-size-set! sl total-sz)
            (c-struct-layout-align-set! sl max-align)
            (c-struct-layout-fields-set! sl (reverse rev-fields))
            (c-struct-layout-direct-fields-set! sl (reverse rev-direct))
            (c-struct-layout-has-fam?-set! sl has-fam?)
            (c-struct-layout-complete?-set! sl #t)
            (c-struct-layout-eightbytes-set! sl #f)
            (if tag-id
                (c99-layout-env-set! lenv tag-id sl))
            sl)
          (let* ((m (car ms))
                 (mname (list-ref m 0))
                 (mtype (list-ref m 1))
                 (mbitw (list-ref m 2))
                 (is-anon-comp? (and (not mname)
                                     (not mbitw)
                                     (or (c-struct-ref-type? mtype)
                                         (c-union-ref-type? mtype))))
                 (is-fam? (and (not mbitw)
                               (c-array-type? mtype)
                               (not (c-array-length mtype)))))
            ;; Check duplicate name among already seen fields
            (if (and mname (memq mname seen-names) err-fn)
                (err-fn "C99-LAY-002"
                        (string-append "Duplicate member '" (symbol->string mname) "' in struct/union")))
            (cond
              ;; Case 1: Bitfield (named or unnamed, including : 0)
              (mbitw
               (let* ((unit-bytes (max 1 (c-type-size-in lenv mtype err-fn)))
                      (unit-bits (* 8 unit-bytes))
                      (fa (max 1 (c-type-align-in lenv mtype)))
                      (su-type (%c99-storage-unit-lir-type unit-bytes)))
                 (cond
                   (is-union?
                    (let* ((new-align (if mname (max max-align fa) max-align))
                           (req-bytes (if (= mbitw 0) 0 (quotient (+ mbitw 7) 8)))
                           (new-max (max max-bytes req-bytes))
                           (fl (%make-c-field-layout mname mtype 0 0 mbitw 0 su-type #f)))
                      (loop (cdr ms) (+ idx 1) 0 new-max new-align has-fam?
                            (if mname (cons mname seen-names) seen-names)
                            (cons fl rev-direct)
                            (if mname (cons fl rev-fields) rev-fields))))
                   ((= mbitw 0)
                    ;; Zero-width bitfield aligns bit cursor to unit boundary, no align contribution
                    (let* ((rem (modulo bit-pos unit-bits))
                           (next-bit-pos (if (= rem 0) bit-pos (+ bit-pos (- unit-bits rem))))
                           (fl (%make-c-field-layout #f mtype (quotient next-bit-pos 8) 0 0 (quotient next-bit-pos 8) su-type #f)))
                      (loop (cdr ms) (+ idx 1) next-bit-pos max-bytes max-align has-fam?
                            seen-names
                            (cons fl rev-direct)
                            rev-fields)))
                   (else
                    (let* ((rem (modulo bit-pos unit-bits))
                           (start-bit (if (> (+ rem mbitw) unit-bits)
                                          (+ bit-pos (- unit-bits rem))
                                          bit-pos))
                           (end-bit (+ start-bit mbitw))
                           (su-idx (quotient start-bit unit-bits))
                           (su-off (* su-idx unit-bytes))
                           (bit-off (modulo start-bit unit-bits))
                           (byte-off (quotient start-bit 8))
                           (new-align (if mname (max max-align fa) max-align))
                           (fl (%make-c-field-layout mname mtype byte-off bit-off mbitw su-off su-type #f)))
                      (if (and err-fn (> (quotient (+ end-bit 7) 8) *c99-max-object-size*))
                          (err-fn "C99-LAY-001" "Object size overflow in bit-field layout"))
                      (loop (cdr ms) (+ idx 1) end-bit max-bytes new-align has-fam?
                            (if mname (cons mname seen-names) seen-names)
                            (cons fl rev-direct)
                            (if mname (cons fl rev-fields) rev-fields)))))))

              ;; Case 2: Flexible Array Member (T arr[])
              (is-fam?
               (let* ((fa (max 1 (c-type-align-in lenv (c-array-elem mtype))))
                      (aligned-bits (let ((rem (modulo bit-pos (* 8 fa))))
                                      (if (= rem 0) bit-pos (+ bit-pos (- (* 8 fa) rem)))))
                      (off (quotient aligned-bits 8))
                      (new-align (max max-align fa))
                      (fl (%make-c-field-layout mname mtype off #f #f #f #f #f)))
                 (loop (cdr ms) (+ idx 1) aligned-bits max-bytes new-align #t
                       (if mname (cons mname seen-names) seen-names)
                       (cons fl rev-direct)
                       (cons fl rev-fields))))

              ;; Case 3: Normal field or Anonymous struct/union member
              (else
               (let* ((fa (max 1 (c-type-align-in lenv mtype)))
                      (fsz (c-type-size-in lenv mtype err-fn))
                      (off (if is-union?
                               0
                               (let ((cur-byte (quotient (+ bit-pos 7) 8)))
                                 (c99-align-up-checked cur-byte fa err-fn))))
                      (next-bit-pos (if is-union?
                                        0
                                        (* (c99-checked-add off fsz err-fn) 8)))
                      (new-max (if is-union? (max max-bytes fsz) max-bytes))
                      (new-align (max max-align fa))
                      (fl (%make-c-field-layout mname mtype off #f #f #f #f #f)))
                 (if is-anon-comp?
                     (let* ((inner-sl (c-type-layout-in lenv mtype))
                            (inner-fields (if inner-sl (c-struct-layout-fields inner-sl) '())))
                       (let promote ((ifs inner-fields)
                                     (cur-seen seen-names)
                                     (cur-fields rev-fields))
                         (if (null? ifs)
                             (loop (cdr ms) (+ idx 1) next-bit-pos new-max new-align has-fam?
                                   cur-seen
                                   (cons fl rev-direct)
                                   cur-fields)
                             (let* ((ifl (car ifs))
                                    (iname (c-field-layout-name ifl)))
                               (if (and iname (memq iname cur-seen) err-fn)
                                   (err-fn "C99-LAY-002"
                                           (string-append "Anonymous aggregate member '"
                                                          (symbol->string iname)
                                                          "' collides with existing field")))
                               (promote (cdr ifs)
                                        (if iname (cons iname cur-seen) cur-seen)
                                        (cons (%c99-shift-anon-field ifl off idx) cur-fields))))))
                     (loop (cdr ms) (+ idx 1) next-bit-pos new-max new-align has-fam?
                           (if mname (cons mname seen-names) seen-names)
                           (cons fl rev-direct)
                           (if mname (cons fl rev-fields) rev-fields)))))))))))

;;; -----------------------------------------------------------------------
;;; 5. SysV AMD64 psABI §3.2.3 Classification & Unified Param/Ret Planner
;;; -----------------------------------------------------------------------

(define (%c99-abi-merge-class c1 c2)
  (cond
    ((eq? c1 c2) c1)
    ((eq? c1 'NO_CLASS) c2)
    ((eq? c2 'NO_CLASS) c1)
    ((or (eq? c1 'MEMORY) (eq? c2 'MEMORY)) 'MEMORY)
    ((or (eq? c1 'INTEGER) (eq? c2 'INTEGER)) 'INTEGER)
    ((or (eq? c1 'X87) (eq? c2 'X87)
         (eq? c1 'X87UP) (eq? c2 'X87UP)
         (eq? c1 'COMPLEX_X87) (eq? c2 'COMPLEX_X87))
     'MEMORY)
    (else 'SSE)))

(define (%c99-abi-classify-into! lenv vec ty byte-off)
  (cond
    ((or (eq? ty 'void))
     #t)
    ((or (c-integer-type? ty) (c-pointer-type? ty) (c-function-type? ty))
     (let* ((al (c-type-align-in lenv ty))
            (sz (c-type-size-in lenv ty)))
       (if (not (= (modulo byte-off al) 0))
           (vector-set! vec 0 'MEMORY)
           (if (> sz 0)
               (let* ((eb0 (quotient byte-off 8))
                      (eb1 (quotient (+ byte-off sz -1) 8)))
                 (let loop ((i eb0))
                   (if (<= i eb1)
                       (begin
                         (if (< i (vector-length vec))
                             (vector-set! vec i (%c99-abi-merge-class (vector-ref vec i) 'INTEGER)))
                         (loop (+ i 1))))))))))
    ((c-float-type? ty)
     (let* ((al (c-type-align-in lenv ty))
            (sz (c-type-size-in lenv ty)))
       (if (not (= (modulo byte-off al) 0))
           (vector-set! vec 0 'MEMORY)
           (let* ((eb0 (quotient byte-off 8))
                  (eb1 (quotient (+ byte-off sz -1) 8)))
             (let loop ((i eb0))
               (if (<= i eb1)
                   (begin
                     (if (< i (vector-length vec))
                         (vector-set! vec i (%c99-abi-merge-class (vector-ref vec i) 'SSE)))
                     (loop (+ i 1)))))))))
    ((c-array-type? ty)
     (let ((len (c-array-length ty))
           (elem (c-array-elem ty)))
       (if (integer? len)
           (let ((esz (c-type-size-in lenv elem)))
             (if (> esz 0)
                 (let loop ((i 0))
                   (if (< i len)
                       (begin
                         (%c99-abi-classify-into! lenv vec elem (+ byte-off (* i esz)))
                         (loop (+ i 1))))))))))
    ((or (c-struct-ref-type? ty) (c-union-ref-type? ty))
     (let ((sl (c-type-layout-in lenv ty)))
       (if sl
           (for-each
            (lambda (dfl)
              (let ((bw (c-field-layout-bit-width dfl))
                    (bo (c-field-layout-bit-offset dfl))
                    (foff (c-field-layout-offset dfl))
                    (ftype (c-field-layout-ctype dfl)))
                (cond
                  (bw
                   (if (> bw 0)
                       (let* ((abs-bit0 (+ (* byte-off 8)
                                           (* (c-field-layout-storage-unit-offset dfl) 8)
                                           bo))
                              (abs-bit1 (- (+ abs-bit0 bw) 1))
                              (eb0 (quotient abs-bit0 64))
                              (eb1 (quotient abs-bit1 64)))
                         (let loop ((i eb0))
                           (if (<= i eb1)
                               (begin
                                 (if (< i (vector-length vec))
                                     (vector-set! vec i (%c99-abi-merge-class (vector-ref vec i) 'INTEGER)))
                                 (loop (+ i 1))))))))
                  (else
                   (%c99-abi-classify-into! lenv vec ftype (+ byte-off foff))))))
            (c-struct-layout-direct-fields sl))
           (vector-set! vec 0 'MEMORY))))
    (else
     (vector-set! vec 0 'MEMORY))))

(define (c99-classify-sysv-aggregate lenv ty)
  (let ((sl (c-type-layout-in lenv ty)))
    (if (and sl (c-struct-layout-eightbytes sl))
        (c-struct-layout-eightbytes sl)
        (let* ((sz (c-type-size-in lenv ty))
               (res
                (cond
                  ((= sz 0) 'empty)
                  ((> sz 16) 'MEMORY)
                  (else
                   (let* ((neb (quotient (+ sz 7) 8))
                          (vec (make-vector neb 'NO_CLASS)))
                     (%c99-abi-classify-into! lenv vec ty 0)
                     (let loop ((i 0) (has-mem? #f) (acc '()))
                       (if (= i neb)
                           (if has-mem? 'MEMORY (reverse acc))
                           (let ((c (vector-ref vec i)))
                             (loop (+ i 1)
                                   (or has-mem? (eq? c 'MEMORY))
                                   (cons c acc))))))))))
          (if sl (c-struct-layout-eightbytes-set! sl res))
          res))))

(define (c99-sysv-type-abi-class lenv ty)
  (cond
    ((eq? ty 'void) 'VOID)
    ((or (c-struct-ref-type? ty) (c-union-ref-type? ty))
     (c99-classify-sysv-aggregate lenv ty))
    ((c-float-type? ty)
     (list 'SSE))
    (else
     (list 'INTEGER))))

(define (c99-plan-sysv-abi lenv ret-ty param-tys)
  (let* ((gpr-arg-regs '(%rdi %rsi %rdx %rcx %r8 %r9))
         (xmm-arg-regs '(%xmm0 %xmm1 %xmm2 %xmm3 %xmm4 %xmm5 %xmm6 %xmm7))
         (gpr-ret-regs '(%rax %rdx))
         (xmm-ret-regs '(%xmm0 %xmm1))
         (ret-cls (c99-sysv-type-abi-class lenv ret-ty))
         (ret-sz (c-type-size-in lenv ret-ty))
         (ret-al (c-type-align-in lenv ret-ty))
         (sret? (eq? ret-cls 'MEMORY))
         (ret-plan
          (cond
            ((eq? ret-cls 'VOID) '(void))
            ((eq? ret-cls 'empty) '(empty))
            (sret? (list 'sret ret-sz ret-al))
            (else
             (let loop ((cs ret-cls) (off 0) (rem ret-sz) (gi 0) (xi 0) (pieces '()))
               (if (null? cs)
                   (list 'regs (reverse pieces))
                   (let* ((c (car cs))
                          (psz (min 8 rem)))
                     (if (eq? c 'INTEGER)
                         (loop (cdr cs) (+ off 8) (- rem psz) (+ gi 1) xi
                               (cons (list 'gpr (list-ref gpr-ret-regs gi) off psz) pieces))
                         (loop (cdr cs) (+ off 8) (- rem psz) gi (+ xi 1)
                               (cons (list 'sse (list-ref xmm-ret-regs xi) off psz) pieces))))))))))
    (let loop ((ps param-tys)
               (used-gpr (if sret? 1 0))
               (used-xmm 0)
               (stack-off 0)
               (acc '()))
      (if (null? ps)
          (list ret-plan (reverse acc) stack-off)
          (let* ((pty (car ps))
                 (psz (c-type-size-in lenv pty))
                 (pal (max 8 (c-type-align-in lenv pty)))
                 (cls (c99-sysv-type-abi-class lenv pty)))
            (cond
              ((or (eq? cls 'empty) (eq? cls 'VOID))
               (loop (cdr ps) used-gpr used-xmm stack-off (cons '(empty) acc)))
              ((eq? cls 'MEMORY)
               (let* ((aligned-st (c99-align-up-checked stack-off pal))
                      (next-st (c99-align-up-checked (+ aligned-st psz) 8)))
                 (loop (cdr ps) used-gpr used-xmm next-st
                       (cons (list 'stack aligned-st psz) acc))))
              (else
               (let* ((need-g (let count-g ((xs cls) (k 0))
                                (if (null? xs) k (count-g (cdr xs) (if (eq? (car xs) 'INTEGER) (+ k 1) k)))))
                      (need-x (- (length cls) need-g)))
                 (if (and (<= (+ used-gpr need-g) 6)
                          (<= (+ used-xmm need-x) 8))
                     (let assign ((cs cls) (off 0) (rem psz) (gi used-gpr) (xi used-xmm) (pieces '()))
                       (if (null? cs)
                           (loop (cdr ps) gi xi stack-off
                                 (cons (list 'regs (reverse pieces)) acc))
                           (let* ((c (car cs))
                                  (csz (min 8 rem)))
                             (if (eq? c 'INTEGER)
                                 (assign (cdr cs) (+ off 8) (- rem csz) (+ gi 1) xi
                                         (cons (list 'gpr (list-ref gpr-arg-regs gi) off csz) pieces))
                                 (assign (cdr cs) (+ off 8) (- rem csz) gi (+ xi 1)
                                         (cons (list 'sse (list-ref xmm-arg-regs xi) off csz) pieces))))))
                     (let* ((aligned-st (c99-align-up-checked stack-off pal))
                            (next-st (c99-align-up-checked (+ aligned-st psz) 8)))
                       (loop (cdr ps) used-gpr used-xmm next-st
                             (cons (list 'stack aligned-st psz) acc))))))))))))

;;; -----------------------------------------------------------------------
;;; 6. Little-Endian Static Data Byte Encoders
;;; -----------------------------------------------------------------------

(define (c99-int->le-bytes val nbytes)
  (let ((mask (arithmetic-shift 1 (* 8 nbytes))))
    (let ((u (modulo val mask)))
      (let loop ((i 0) (x u) (acc '()))
        (if (>= i nbytes)
            (reverse acc)
            (loop (+ i 1) (quotient x 256) (cons (modulo x 256) acc)))))))

(define (c99-f32->le-bytes val)
  (cond
    ((and (pair? val) (eq? (car val) 'c-static-fp))
     (let ((fty (cadr val))
           (bits (caddr val)))
       (c99-int->le-bytes (if (eq? fty 'f64) (c99-ieee754-f64-bits->f32-bits bits) bits) 4)))
    ((and (pair? val) (eq? (car val) 'c-float-bits))
     (c99-int->le-bytes (cadr val) 4))
    (else
     (c99-int->le-bytes (vm-f32->ieee754-u32 val) 4))))

(define (c99-f64->le-bytes val)
  (cond
    ((and (pair? val) (eq? (car val) 'c-static-fp))
     (let ((fty (cadr val))
           (bits (caddr val)))
       (c99-int->le-bytes (if (eq? fty 'f32) (c99-ieee754-f32-bits->f64-bits bits) bits) 8)))
    ((and (pair? val) (eq? (car val) 'c-float-bits))
     (c99-int->le-bytes (cadr val) 8))
    (else
     (c99-int->le-bytes (vm-f64->ieee754-u64 val) 8))))
