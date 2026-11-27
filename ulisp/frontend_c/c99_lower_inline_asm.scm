;;; =======================================================================
;;; ULisp C99 Frontend: AT&T -> Intel Inline / Top-Level Asm Lowering Pass
;;; Extracted from lower_to_lir.scm (Issue #967).
;;; Translates GNU inline/top-level asm into Intel syntax and normalizes %inline-asm.
;;; Zero local `set!` (ULisp AOT safe).
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 8.0 AT&T -> Intel Inline / Top-Level Asm Translation & %inline-asm Lowering
;;; -----------------------------------------------------------------------

(define (%c99-asm-trim s)
  (let* ((n (string-length s)))
    (let loop-l ((i 0))
      (if (and (< i n) (char-whitespace? (string-ref s i)))
          (loop-l (+ i 1))
          (let loop-r ((j n))
            (if (and (> j i) (char-whitespace? (string-ref s (- j 1))))
                (loop-r (- j 1))
                (substring s i j)))))))

(define (%c99-asm-downcase s)
  (let* ((n (string-length s))
         (cs (let loop ((i 0) (acc '()))
               (if (>= i n)
                   (reverse acc)
                   (loop (+ i 1) (cons (char-downcase (string-ref s i)) acc))))))
    (list->string cs)))

(define (%c99-asm-str-contains? s sub)
  (let ((n (string-length s))
        (m (string-length sub)))
    (if (= m 0) #t
        (let loop ((i 0))
          (cond
            ((> (+ i m) n) #f)
            ((string=? (substring s i (+ i m)) sub) #t)
            (else (loop (+ i 1))))))))

(define (%c99-asm-strip-comments s)
  (let ((n (string-length s))
        (cr (integer->char 13)))
    (let loop ((i 0) (in-str? #f) (acc '()))
      (if (>= i n)
          (list->string (reverse acc))
          (let ((ch (string-ref s i)))
            (cond
              ((and in-str? (char=? ch #\\) (< (+ i 1) n))
               (loop (+ i 2) #t (cons (string-ref s (+ i 1)) (cons ch acc))))
              ((char=? ch #\")
               (loop (+ i 1) (not in-str?) (cons ch acc)))
              ((and (not in-str?) (< (+ i 1) n)
                    (char=? ch #\/) (char=? (string-ref s (+ i 1)) #\*))
               (let skip-blk ((j (+ i 2)))
                 (cond
                   ((>= j n) (loop n #f acc))
                   ((and (< (+ j 1) n) (char=? (string-ref s j) #\*) (char=? (string-ref s (+ j 1)) #\/))
                    (loop (+ j 2) #f (cons #\space acc)))
                   ((char=? (string-ref s j) #\newline)
                    (skip-blk (+ j 1)))
                   (else (skip-blk (+ j 1))))))
              ((and (not in-str?) (< (+ i 1) n)
                    (char=? ch #\/) (char=? (string-ref s (+ i 1)) #\/))
               (let skip-ln ((j (+ i 2)))
                 (if (or (>= j n) (char=? (string-ref s j) #\newline) (char=? (string-ref s j) cr))
                     (loop j #f acc)
                     (skip-ln (+ j 1)))))
              (else
               (loop (+ i 1) in-str? (cons ch acc)))))))))

(define (%c99-asm-split-statements raw-tpl-str)
  (let* ((tpl-str (%c99-asm-strip-comments raw-tpl-str))
         (n (string-length tpl-str))
         (cr (integer->char 13))
         (raw-segs
          (let loop ((i 0) (start 0) (in-str? #f) (acc '()))
            (if (>= i n)
                (let ((tail (%c99-asm-trim (substring tpl-str start n))))
                  (reverse (if (> (string-length tail) 0) (cons tail acc) acc)))
                (let ((ch (string-ref tpl-str i)))
                  (cond
                    ((and in-str? (char=? ch #\\) (< (+ i 1) n))
                     (loop (+ i 2) start #t acc))
                    ((char=? ch #\")
                     (loop (+ i 1) start (not in-str?) acc))
                    ((and (not in-str?) (or (char=? ch #\newline) (char=? ch cr) (char=? ch #\;)))
                     (let ((seg (%c99-asm-trim (substring tpl-str start i))))
                       (loop (+ i 1) (+ i 1) #f
                             (if (> (string-length seg) 0) (cons seg acc) acc))))
                    (else
                     (loop (+ i 1) start in-str? acc))))))))
    ;; Merge standalone prefix segments ("lock", "rep", "repe", "repz", "repne", "repnz") with following inst
    ;; and split inline "label: inst" into two segments
    (let* ((split-lbls
            (let sl ((xs raw-segs) (acc '()))
              (if (null? xs)
                  (reverse acc)
                  (let* ((s (car xs))
                         (len (string-length s))
                         (colon-idx
                          (if (and (> len 0) (not (char=? (string-ref s 0) #\.)))
                              (let find-c ((k 0))
                                (cond
                                  ((>= k (- len 1)) #f)
                                  ((or (char-whitespace? (string-ref s k))
                                       (char=? (string-ref s k) #\,)
                                       (char=? (string-ref s k) #\[)
                                       (char=? (string-ref s k) #\()) #f)
                                  ((char=? (string-ref s k) #\:)
                                   (if (and (< (+ k 1) len) (char-whitespace? (string-ref s (+ k 1)))) k #f))
                                  (else (find-c (+ k 1)))))
                              #f)))
                    (if colon-idx
                        (let ((lbl (substring s 0 (+ colon-idx 1)))
                              (rest (%c99-asm-trim (substring s (+ colon-idx 1) len))))
                          (sl (cdr xs) (if (> (string-length rest) 0) (cons rest (cons lbl acc)) (cons lbl acc))))
                        (sl (cdr xs) (cons s acc))))))))
      (let merge ((xs split-lbls) (acc '()))
        (cond
          ((null? xs) (reverse acc))
          ((and (pair? (cdr xs))
                (member (%c99-asm-downcase (car xs)) '("lock" "rep" "repe" "repz" "repne" "repnz")))
           (merge (cddr xs)
                  (cons (string-append (%c99-asm-downcase (car xs)) " " (cadr xs)) acc)))
          (else
           (merge (cdr xs) (cons (car xs) acc))))))))

(define (%c99-asm-split-args args-str)
  (let ((n (string-length args-str)))
    (let loop ((i 0) (start 0) (pdepth 0) (bdepth 0) (acc '()))
      (if (>= i n)
          (let ((tail (%c99-asm-trim (substring args-str start n))))
            (reverse (if (> (string-length tail) 0) (cons tail acc) acc)))
          (let ((ch (string-ref args-str i)))
            (cond
              ((char=? ch #\() (loop (+ i 1) start (+ pdepth 1) bdepth acc))
              ((char=? ch #\)) (loop (+ i 1) start (max 0 (- pdepth 1)) bdepth acc))
              ((char=? ch #\[) (loop (+ i 1) start pdepth (+ bdepth 1) acc))
              ((char=? ch #\]) (loop (+ i 1) start pdepth (max 0 (- bdepth 1)) acc))
              ((and (char=? ch #\,) (= pdepth 0) (= bdepth 0))
               (let ((seg (%c99-asm-trim (substring args-str start i))))
                 (loop (+ i 1) (+ i 1) 0 0 (if (> (string-length seg) 0) (cons seg acc) acc))))
              (else
               (loop (+ i 1) start pdepth bdepth acc))))))))

(define (%c99-asm-strip-reg-percent s top-level?)
  (let ((n (string-length s)))
    (cond
      ((and (>= n 2) (char=? (string-ref s 0) #\%) (char=? (string-ref s 1) #\%))
       (substring s 2 n))
      ((and top-level? (>= n 1) (char=? (string-ref s 0) #\%))
       (substring s 1 n))
      ((and (not top-level?) (>= n 2) (char=? (string-ref s 0) #\%)
            (not (or (and (char>=? (string-ref s 1) #\0) (char<=? (string-ref s 1) #\9))
                     (char=? (string-ref s 1) #\[)
                     (and (>= n 3) (memv (string-ref s 1) '(#\b #\w #\k #\q #\h #\l))
                          (or (and (char>=? (string-ref s 2) #\0) (char<=? (string-ref s 2) #\9))
                              (char=? (string-ref s 2) #\[))))))
       (substring s 1 n))
      (else s))))

(define (%c99-asm-placeholder-idx s)
  (let ((n (string-length s)))
    (if (and (>= n 2) (char=? (string-ref s 0) #\%))
        (let* ((start (if (and (>= n 3) (memv (string-ref s 1) '(#\b #\w #\k #\q #\h #\l))) 2 1))
               (rest (substring s start n)))
          (if (and (> (string-length rest) 0)
                   (let dloop ((k 0))
                     (if (>= k (string-length rest))
                         #t
                         (and (char>=? (string-ref rest k) #\0)
                              (char<=? (string-ref rest k) #\9)
                              (dloop (+ k 1))))))
              (string->number rest)
              #f))
        #f)))

(define (%c99-asm-convert-att-mem disp inner)
  (let* ((parts (map %c99-asm-trim (%c99-asm-split-args inner)))
         (raw-base (if (>= (length parts) 1) (%c99-asm-strip-reg-percent (list-ref parts 0) #t) ""))
         (raw-idx  (if (>= (length parts) 2) (%c99-asm-strip-reg-percent (list-ref parts 1) #t) ""))
         (raw-scl  (if (>= (length parts) 3) (list-ref parts 2) ""))
         (base (if (and (> (string-length raw-base) 0) (not (string=? raw-base "iz"))) raw-base ""))
         (idx  (if (and (> (string-length raw-idx) 0)  (not (string=? raw-idx "iz")))  raw-idx  ""))
         (terms
          (append
           (if (> (string-length base) 0) (list base) '())
           (append
            (if (> (string-length idx) 0)
                (list (if (and (> (string-length raw-scl) 0) (not (string=? raw-scl "1")))
                          (string-append idx "*" raw-scl)
                          idx))
                '())
            (if (and (> (string-length disp) 0) (not (string=? disp "0")))
                (list disp)
                '())))))
    (if (null? terms)
        "[0]"
        (let loop ((ts (cdr terms)) (s (car terms)))
          (if (null? ts)
              (string-append "[" s "]")
              (let ((t (car ts)))
                (if (and (> (string-length t) 0) (char=? (string-ref t 0) #\-))
                    (loop (cdr ts) (string-append s " - " (substring t 1 (string-length t))))
                    (loop (cdr ts) (string-append s " + " t)))))))))

(define (%c99-asm-convert-att-opnd op top-level? size-prefix)
  (let* ((t0 (%c99-asm-trim op))
         (t (if (and (> (string-length t0) 1) (char=? (string-ref t0 0) #\*))
                (%c99-asm-trim (substring t0 1 (string-length t0)))
                t0))
         (n (string-length t)))
    (cond
      ((= n 0) "")
      ;; Numeric local label forward/backward ref: 1f / 1b -> .L_asm_num_1
      ((and (= n 2)
            (char>=? (string-ref t 0) #\0) (char<=? (string-ref t 0) #\9)
            (or (char=? (string-ref t 1) #\f) (char=? (string-ref t 1) #\b)))
       (string-append ".L_asm_num_" (substring t 0 1)))
      ;; Immediate: $imm
      ((char=? (string-ref t 0) #\$)
       (substring t 1 n))
      ;; Already Intel bracket or ptr
      ((or (%c99-asm-str-contains? t "[")
           (%c99-asm-str-contains? (%c99-asm-downcase t) " ptr "))
       t)
      (else
       ;; Check segment prefix: %%fs: or %fs: or %%gs: or %gs:
       (let* ((seg-res
               (cond
                 ((and (>= n 5) (string=? (%c99-asm-downcase (substring t 0 5)) "%%fs:"))
                  (cons "fs:" (substring t 5 n)))
                 ((and (>= n 4) (string=? (%c99-asm-downcase (substring t 0 4)) "%fs:"))
                  (cons "fs:" (substring t 4 n)))
                 ((and (>= n 5) (string=? (%c99-asm-downcase (substring t 0 5)) "%%gs:"))
                  (cons "gs:" (substring t 5 n)))
                 ((and (>= n 4) (string=? (%c99-asm-downcase (substring t 0 4)) "%gs:"))
                  (cons "gs:" (substring t 4 n)))
                 (else (cons "" t))))
              (seg (car seg-res))
              (body (%c99-asm-trim (cdr seg-res)))
              (bn (string-length body)))
         (cond
           ;; Segment with bare disp, e.g. %%fs:0 -> fs:[0]
           ((and (> (string-length seg) 0)
                 (or (= bn 0) (not (char=? (string-ref body (- bn 1)) #\)))))
            (let ((addr (string-append seg "[" (if (= bn 0) "0" body) "]")))
              (if size-prefix (string-append size-prefix " " addr) addr)))
           ;; Memory with trailing (...): disp(base, idx, scale)
           ((and (> bn 0) (char=? (string-ref body (- bn 1)) #\)))
            (let find-lp ((k (- bn 2)))
              (if (< k 0)
                  body
                  (if (char=? (string-ref body k) #\()
                      (let* ((disp (%c99-asm-trim (substring body 0 k)))
                             (inner (substring body (+ k 1) (- bn 1)))
                             (addr (string-append seg (%c99-asm-convert-att-mem disp inner))))
                        (if size-prefix (string-append size-prefix " " addr) addr))
                      (find-lp (- k 1))))))
           (else
            (let ((reg-or-id (%c99-asm-strip-reg-percent body top-level?)))
              (if size-prefix
                  (string-append size-prefix " " reg-or-id)
                  reg-or-id)))))))))

(define (%c99-asm-normalize-mnem low-mnem has-xmm?)
  ;; Returns (list intel-mnem att-size-ptr-or-#f definite-att?)
  (let* ((exact-table
          '(("movq" . ("mov" "qword ptr" #t)) ("movl" . ("mov" "dword ptr" #t))
            ("movw" . ("mov" "word ptr" #t))  ("movb" . ("mov" "byte ptr" #t))
            ("addq" . ("add" "qword ptr" #t)) ("addl" . ("add" "dword ptr" #t))
            ("addw" . ("add" "word ptr" #t))  ("addb" . ("add" "byte ptr" #t))
            ("subq" . ("sub" "qword ptr" #t)) ("subl" . ("sub" "dword ptr" #t))
            ("subw" . ("sub" "word ptr" #t))  ("subb" . ("sub" "byte ptr" #t))
            ("andq" . ("and" "qword ptr" #t)) ("andl" . ("and" "dword ptr" #t))
            ("andw" . ("and" "word ptr" #t))  ("andb" . ("and" "byte ptr" #t))
            ("orq"  . ("or"  "qword ptr" #t)) ("orl"  . ("or"  "dword ptr" #t))
            ("orw"  . ("or"  "word ptr" #t))  ("orb"  . ("or"  "byte ptr" #t))
            ("xorq" . ("xor" "qword ptr" #t)) ("xorl" . ("xor" "dword ptr" #t))
            ("xorw" . ("xor" "word ptr" #t))  ("xorb" . ("xor" "byte ptr" #t))
            ("cmpq" . ("cmp" "qword ptr" #t)) ("cmpl" . ("cmp" "dword ptr" #t))
            ("cmpw" . ("cmp" "word ptr" #t))  ("cmpb" . ("cmp" "byte ptr" #t))
            ("testq" . ("test" "qword ptr" #t)) ("testl" . ("test" "dword ptr" #t))
            ("testw" . ("test" "word ptr" #t))  ("testb" . ("test" "byte ptr" #t))
            ("incq" . ("inc" "qword ptr" #t)) ("incl" . ("inc" "dword ptr" #t))
            ("incw" . ("inc" "word ptr" #t))  ("incb" . ("inc" "byte ptr" #t))
            ("decq" . ("dec" "qword ptr" #t)) ("decl" . ("dec" "dword ptr" #t))
            ("decw" . ("dec" "word ptr" #t))  ("decb" . ("dec" "byte ptr" #t))
            ("negq" . ("neg" "qword ptr" #t)) ("negl" . ("neg" "dword ptr" #t))
            ("notq" . ("not" "qword ptr" #t)) ("notl" . ("not" "dword ptr" #t))
            ("shlq" . ("shl" "qword ptr" #t)) ("shll" . ("shl" "dword ptr" #t))
            ("shrq" . ("shr" "qword ptr" #t)) ("shrl" . ("shr" "dword ptr" #t))
            ("sarq" . ("sar" "qword ptr" #t)) ("sarl" . ("sar" "dword ptr" #t))
            ("leaq" . ("lea" #f #t))          ("leal" . ("lea" #f #t))
            ("xchgq" . ("xchg" "qword ptr" #t)) ("xchgl" . ("xchg" "dword ptr" #t))
            ("cmpxchgq" . ("cmpxchg" "qword ptr" #t)) ("cmpxchgl" . ("cmpxchg" "dword ptr" #t))
            ("xaddq" . ("xadd" "qword ptr" #t)) ("xaddl" . ("xadd" "dword ptr" #t))
            ("bsfq" . ("bsf" #f #t)) ("bsfl" . ("bsf" #f #t))
            ("bsrq" . ("bsr" #f #t)) ("bsrl" . ("bsr" #f #t))
            ("btq"  . ("bt"  #f #t)) ("btl"  . ("bt"  #f #t))
            ("btsq" . ("bts" #f #t)) ("btsl" . ("bts" #f #t))
            ("btrq" . ("btr" #f #t)) ("btrl" . ("btr" #f #t))
            ("pushq" . ("push" #f #t)) ("popq" . ("pop" #f #t))
            ("callq" . ("call" #f #t)) ("jmpq" . ("jmp" #f #t)) ("retq" . ("ret" #f #t))
            ("movslq" . ("movsxd" #f #t)) ("cltq" . ("cdqe" #f #t)) ("cqto" . ("cqo" #f #t))))
         (hit (assoc low-mnem exact-table)))
    (cond
      ((and (string=? low-mnem "movq") has-xmm?)
       (list "movq" #f #t))
      (hit (cdr hit))
      (else (list low-mnem #f #f)))))

(define (%c99-asm-opnds-look-intel? opnds)
  (let loop ((xs opnds))
    (if (null? xs)
        #f
        (let* ((o (%c99-asm-trim (car xs)))
               (n (string-length o))
               (bare-int?
                (and (> n 0)
                     (or (and (char>=? (string-ref o 0) #\0) (char<=? (string-ref o 0) #\9))
                         (and (char=? (string-ref o 0) #\-) (> n 1)
                              (char>=? (string-ref o 1) #\0) (char<=? (string-ref o 1) #\9))))))
          (if (or bare-int?
                  (%c99-asm-str-contains? o "[")
                  (%c99-asm-str-contains? (%c99-asm-downcase o) " ptr "))
              #t
              (loop (cdr xs)))))))

(define (%c99-asm-opnds-look-att? opnds)
  (let loop ((xs opnds))
    (if (null? xs)
        #f
        (let ((o (%c99-asm-trim (car xs))))
          (if (or (%c99-asm-str-contains? o "%%")
                  (%c99-asm-str-contains? o "$")
                  (%c99-asm-str-contains? o "(%")
                  (%c99-asm-str-contains? o "*%")
                  (and (= (string-length o) 2)
                       (char>=? (string-ref o 0) #\0) (char<=? (string-ref o 0) #\9)
                       (or (char=? (string-ref o 1) #\f) (char=? (string-ref o 1) #\b)))
                  (and (>= (string-length o) 2)
                       (char=? (string-ref o 0) #\%)
                       (char-alphabetic? (string-ref o 1))))
              #t
              (loop (cdr xs)))))))

(define (%c99-asm-apply-width-modifier op-str op-types op-cstrs)
  (let ((idx (%c99-asm-placeholder-idx (%c99-asm-trim op-str))))
    (if (and idx (< idx (length op-types)))
        (let* ((ty (list-ref op-types idx))
               (cstr (if (< idx (length op-cstrs)) (list-ref op-cstrs idx) ""))
               (is-mem-cstr? (%c99-asm-str-contains? cstr "m"))
               (prefix-ch (and (not is-mem-cstr?)
                               (cond
                                 ((or (eq? ty 'i32) (eq? ty 'u32)) "k")
                                 ((or (eq? ty 'i16) (eq? ty 'u16)) "w")
                                 ((or (eq? ty 'i8) (eq? ty 'u8) (eq? ty 'bool)) "b")
                                 (else #f)))))
          (if (and prefix-ch (char=? (string-ref op-str 0) #\%)
                   (char>=? (string-ref op-str 1) #\0)
                   (char<=? (string-ref op-str 1) #\9))
              (string-append "%" prefix-ch (substring op-str 1 (string-length op-str)))
              op-str))
        op-str)))

(define (%c99-asm-mem-like? intel-op raw-op op-cstrs)
  (let ((t (%c99-asm-trim intel-op))
        (idx (%c99-asm-placeholder-idx (%c99-asm-trim raw-op))))
    (or (%c99-asm-str-contains? t "[")
        (%c99-asm-str-contains? (%c99-asm-downcase t) "fs:")
        (and idx (< idx (length op-cstrs)) (%c99-asm-str-contains? (list-ref op-cstrs idx) "m")))))

(define (%c99-asm-translate-line line top-level? op-types op-cstrs)
  (let ((t (%c99-asm-trim line)))
    (cond
      ((= (string-length t) 0) #f)
      ;; Assembler directive (.globl, .global, .weak, .hidden, .text, ...)
      ((char=? (string-ref t 0) #\.)
       (if (or (string=? t ".global")
               (and (> (string-length t) 8)
                    (string=? (substring t 0 8) ".global ")
                    #t)
               (and (> (string-length t) 8)
                    (string=? (substring t 0 8) ".global\t")))
           (string-append "    .globl" (substring t 7 (string-length t)))
           (string-append "    " t)))
      ;; Label definition (foo: or numeric 1:)
      ((char=? (string-ref t (- (string-length t) 1)) #\:)
       (if (and (= (string-length t) 2)
                (char>=? (string-ref t 0) #\0)
                (char<=? (string-ref t 0) #\9))
           (string-append ".L_asm_num_" (substring t 0 1) ":")
           t))
      (else
       ;; Peel lock/rep prefix if present
       (let* ((pfx-split
               (let loop ((i 0))
                 (if (or (>= i (string-length t)) (char-whitespace? (string-ref t i)))
                     (cons (%c99-asm-downcase (substring t 0 i))
                           (%c99-asm-trim (substring t i (string-length t))))
                     (loop (+ i 1)))))
              (has-pfx? (and (> (string-length (cdr pfx-split)) 0)
                             (member (car pfx-split) '("lock" "rep" "repe" "repz" "repne" "repnz"))))
              (pfx (if has-pfx? (car pfx-split) #f))
              (body (if has-pfx? (cdr pfx-split) t))
              (mnem-split
               (let loop ((i 0))
                 (if (or (>= i (string-length body)) (char-whitespace? (string-ref body i)))
                     (cons (%c99-asm-downcase (substring body 0 i))
                           (%c99-asm-trim (substring body i (string-length body))))
                     (loop (+ i 1)))))
              (raw-mnem (car mnem-split))
              (args-str (cdr mnem-split))
              (raw-opnds (if (= (string-length args-str) 0) '() (%c99-asm-split-args args-str)))
              (has-xmm?
               (or (%c99-asm-str-contains? (%c99-asm-downcase args-str) "xmm")
                   (let loop ((cs op-cstrs))
                     (if (null? cs) #f
                         (or (%c99-asm-str-contains? (car cs) "x") (loop (cdr cs)))))))
              (mnem-info (%c99-asm-normalize-mnem raw-mnem has-xmm?))
              (intel-mnem (car mnem-info))
              (size-hint (cadr mnem-info))
              (def-att? (caddr mnem-info))
              (is-att? (or def-att?
                           (%c99-asm-opnds-look-att? raw-opnds)
                           (and (not top-level?)
                                (not (%c99-asm-opnds-look-intel? raw-opnds)))))
              (need-mem-sz?
               (and size-hint
                    (or (= (length raw-opnds) 1)
                        (and (= (length raw-opnds) 2)
                             (or (char=? (string-ref (%c99-asm-trim (car raw-opnds)) 0) #\$)
                                 (let ((i0 (%c99-asm-placeholder-idx (car raw-opnds))))
                                   (and i0 (< i0 (length op-cstrs))
                                        (member (list-ref op-cstrs i0) '("i" "n" "I" "J" "K")))))))))
              (converted-opnds
               (if is-att?
                   (let ((rev-raw (if (>= (length raw-opnds) 2) (reverse raw-opnds) raw-opnds)))
                     (map (lambda (o)
                            (let* ((mem-sz (if (and need-mem-sz?
                                                    (%c99-asm-mem-like? (%c99-asm-convert-att-opnd o top-level? #f) o op-cstrs))
                                               size-hint
                                               #f))
                                   (intel-o (%c99-asm-convert-att-opnd o top-level? mem-sz)))
                              (if (and (not def-att?)
                                       (not top-level?)
                                       (member intel-mnem '("mov" "add" "sub" "and" "or" "xor" "cmp"
                                                            "test" "xchg" "xadd" "cmpxchg"
                                                            "inc" "dec" "neg" "not" "bsf" "bsr")))
                                  (%c99-asm-apply-width-modifier intel-o op-types op-cstrs)
                                  intel-o)))
                          rev-raw))
                   raw-opnds))
              (opnds-joined
               (if (null? converted-opnds)
                   ""
                   (let jloop ((os (cdr converted-opnds)) (s (car converted-opnds)))
                     (if (null? os) s (jloop (cdr os) (string-append s ", " (car os)))))))
              (inst-line
               (if (= (string-length opnds-joined) 0)
                   (if pfx (string-append pfx " " intel-mnem) intel-mnem)
                   (if pfx
                       (string-append pfx " " intel-mnem " " opnds-joined)
                       (string-append intel-mnem " " opnds-joined)))))
         (if top-level? (string-append "    " inst-line) inst-line))))))

(define (c99-att-asm->intel-asm tpl-str top-level? . maybe-meta)
  (let* ((op-types (if (and (pair? maybe-meta) (pair? (car maybe-meta))) (caar maybe-meta) '()))
         (op-cstrs (if (and (pair? maybe-meta) (pair? (car maybe-meta))) (cdar maybe-meta) '()))
         (segs (%c99-asm-split-statements tpl-str))
         (lines
          (let loop ((ss segs) (acc '()))
            (if (null? ss)
                (reverse acc)
                (let ((tr (%c99-asm-translate-line (car ss) top-level? op-types op-cstrs)))
                  (loop (cdr ss) (if tr (cons tr acc) acc)))))))
    (if top-level?
        lines
        (if (null? lines)
            "nop"
            (let jloop ((ls (cdr lines)) (s (car lines)))
              (if (null? ls) s (jloop (cdr ls) (string-append s "\n" (car ls)))))))))

(define (%c99-lower-asm-simple-local-var-si ctx texpr)
  (let ((inner (c-typed-inner texpr)))
    (if (and (pair? inner) (eq? (car inner) 'c-var-ref))
        (let ((ent (%c99-lower-lookup-var ctx (cadr inner))))
          (if (and ent (eq? (car ent) 'local) (not (%c99-lower-aggregate-like? (c-typed-type texpr))))
              (cadr ent)
              #f))
        #f)))

(define (%c99-lower-asm-mem-reg-pool clobs all-cstrs)
  (let ((bad '(%rax %r10 %r11 %rsp)))
    (let* ((bad1
            (let cl ((xs clobs) (acc bad))
              (if (null? xs) acc
                  (let* ((s (%c99-asm-downcase (if (symbol? (car xs)) (symbol->string (car xs)) (car xs))))
                         (rs (string->symbol (string-append "%" s))))
                    (cl (cdr xs) (cons rs acc))))))
           (bad2
            (let cs ((xs all-cstrs) (acc bad1))
              (if (null? xs) acc
                  (let ((c (car xs)))
                    (cond
                      ((%c99-asm-str-contains? c "a") (cs (cdr xs) (cons '%rax acc)))
                      ((%c99-asm-str-contains? c "b") (cs (cdr xs) (cons '%rbx acc)))
                      ((%c99-asm-str-contains? c "c") (cs (cdr xs) (cons '%rcx acc)))
                      ((%c99-asm-str-contains? c "d") (cs (cdr xs) (cons '%rdx acc)))
                      ((%c99-asm-str-contains? c "S") (cs (cdr xs) (cons '%rsi acc)))
                      ((%c99-asm-str-contains? c "D") (cs (cdr xs) (cons '%rdi acc)))
                      (else (cs (cdr xs) acc))))))))
      (let loop ((cand '(%r9 %r8 %rsi %rdi %rdx %rcx %rbx %r13 %r14 %r15 %r12)) (free '()))
        (if (null? cand)
            (reverse free)
            (if (memq (car cand) bad2)
                (loop (cdr cand) free)
                (loop (cdr cand) (cons (car cand) free))))))))

(define (%c99-lower-inline-asm! ctx stmt)
  (let* ((vol? (cadr stmt))
         (tpl-str (caddr stmt))
         (outs (cadddr stmt))
         (ins (list-ref stmt 4))
         (clobs (list-ref stmt 5))
         (all-ops (append outs ins))
         (op-types (map (lambda (op) (c-typed-type (caddr op))) all-ops))
         (op-cstrs (map cadr all-ops))
         (intel-tpl (c99-att-asm->intel-asm tpl-str #f (cons op-types op-cstrs)))
         (saved-si (lower-ctx-next-si ctx))
         (mem-pool (%c99-lower-asm-mem-reg-pool clobs op-cstrs))
         (pool-box (cons mem-pool '()))
         (mem-loads-box (cons '() '()))
         (writebacks-box (cons '() '()))
         (alloc-mem-reg!
          (lambda ()
            (let ((p (car pool-box)))
              (if (null? p) '%rbx (begin (set-car! pool-box (cdr p)) (car p))))))
         (prep-mem-operand!
          (lambda (texpr)
            (let ((si (%c99-lower-asm-simple-local-var-si ctx texpr)))
              (if si
                  (list '%stack si)
                  (let* ((ptr-si (%c99-lower-alloc-slot! ctx))
                         (mreg (alloc-mem-reg!)))
                    (%c99-lower-lvalue-addr! ctx texpr)
                    (%c99-lower-emit! ctx (list '%store '%rsp ptr-si '%rax))
                    (set-car! mem-loads-box (cons (cons ptr-si mreg) (car mem-loads-box)))
                    (list '%mem mreg 0))))))
         (lir-outs
          (map (lambda (o)
                 (let* ((oname (car o))
                        (ocstr (cadr o))
                        (oexpr (caddr o))
                        (oty (c-typed-type oexpr))
                        (is-mem? (%c99-asm-str-contains? ocstr "m"))
                        (is-rw? (and (> (string-length ocstr) 0) (char=? (string-ref ocstr 0) #\+)))
                        (si (%c99-lower-asm-simple-local-var-si ctx oexpr))
                        (opnd
                         (cond
                           (is-mem? (prep-mem-operand! oexpr))
                           (si (list '%stack si))
                           (else
                            (let ((tmp-si (%c99-lower-alloc-slot! ctx)))
                              (if is-rw?
                                  (begin
                                    (%c99-lower-expr! ctx oexpr)
                                    (if (c-float-type? oty)
                                        (%c99-lower-emit! ctx (list '%store-typed oty '%rsp tmp-si '%xmm0))
                                        (%c99-lower-emit! ctx (list '%store '%rsp tmp-si '%rax)))))
                              (set-car! writebacks-box (cons (list oexpr tmp-si oty) (car writebacks-box)))
                              (list '%stack tmp-si))))))
                   (if oname
                       (list oname ocstr opnd)
                       (list opnd ocstr))))
               outs))
         (lir-ins
          (map (lambda (in-op)
                 (let* ((iname (car in-op))
                        (icstr (cadr in-op))
                        (iexpr (caddr in-op))
                        (ity (c-typed-type iexpr))
                        (is-mem? (%c99-asm-str-contains? icstr "m"))
                        (is-imm? (member icstr '("i" "n" "I" "J" "K")))
                        (inner (c-typed-inner iexpr))
                        (si (%c99-lower-asm-simple-local-var-si ctx iexpr))
                        (opnd
                         (cond
                           (is-mem? (prep-mem-operand! iexpr))
                           ((and is-imm? (eq? (car inner) 'c-const-val) (integer? (cadr inner)))
                            (cadr inner))
                           ((and si (c-integer-type? ity) (= (%c99-lower-type-size ctx ity) 8))
                            (list '%stack si))
                           (else
                            (let ((tmp-si (%c99-lower-alloc-slot! ctx)))
                              (%c99-lower-expr! ctx iexpr)
                              (if (c-float-type? ity)
                                  (%c99-lower-emit! ctx (list '%store-typed ity '%rsp tmp-si '%xmm0))
                                  (%c99-lower-emit! ctx (list '%store '%rsp tmp-si '%rax)))
                              (list '%stack tmp-si))))))
                   (if iname
                       (list iname icstr opnd)
                       (list opnd icstr))))
               ins)))
    ;; Load computed pointer addresses into non-conflicting base registers right before %inline-asm
    (for-each
     (lambda (ml)
       (%c99-lower-emit! ctx (list '%load (cdr ml) '%rsp (car ml))))
     (reverse (car mem-loads-box)))
    (%c99-lower-emit! ctx
                      (list '%inline-asm
                            intel-tpl
                            (list ':outputs lir-outs)
                            (list ':inputs lir-ins)
                            (list ':clobbers clobs)
                            (list ':volatile? (if vol? #t #f))))
    ;; Perform deferred writebacks for non-local scalar outputs
    (for-each
     (lambda (wb)
       (let ((dst-expr (car wb))
             (tmp-si (cadr wb))
             (ty (caddr wb)))
         (let ((addr-si (%c99-lower-alloc-slot! ctx)))
           (%c99-lower-lvalue-addr! ctx dst-expr)
           (%c99-lower-emit! ctx (list '%store '%rsp addr-si '%rax))
           (if (c-float-type? ty)
               (begin
                 (%c99-lower-emit! ctx (list '%load-typed ty '%xmm0 '%rsp tmp-si))
                 (%c99-lower-emit! ctx (list '%load '%rdx '%rsp addr-si))
                 (%c99-lower-emit! ctx (list '%store-typed ty '%rdx 0 '%xmm0)))
               (begin
                 (%c99-lower-emit! ctx (list '%load '%rax '%rsp tmp-si))
                 (%c99-lower-emit! ctx (list '%load '%rdx '%rsp addr-si))
                 (%c99-lower-store-to-mem! ctx '%rdx 0 '%rax ty))))))
     (reverse (car writebacks-box)))
    (lower-ctx-next-si-set! ctx saved-si)))


;;; -----------------------------------------------------------------------
;;; 8.0b Modular C99 Inline Asm IR Pass & Hook (Issue #967)
;;; -----------------------------------------------------------------------

(define (%c99-normalize-inline-asm-inst inst)
  (if (not (pair? inst))
      inst
      (case (car inst)
        ((%block)
         (append (list (car inst) (cadr inst) (caddr inst))
                 (%c99-normalize-inline-asm-body (cdddr inst))))
        ((%inline-asm)
         (if (and (pair? (cdr inst))
                  (string? (cadr inst))
                  (%c99-asm-opnds-look-att? (list (cadr inst))))
             (cons '%inline-asm
                   (cons (c99-att-asm->intel-asm (cadr inst) #f)
                         (cddr inst)))
             inst))
        (else inst))))

(define (%c99-normalize-inline-asm-body insts)
  (map %c99-normalize-inline-asm-inst insts))

(define (c99-lower-inline-asm-ir ir)
  (if (not (and (pair? ir) (eq? (car ir) '%lir-program)))
      ir
      (cons '%lir-program
            (map (lambda (clause)
                   (if (not (pair? clause))
                       clause
                       (case (car clause)
                         ((%lir-functions)
                          (cons '%lir-functions
                                (map (lambda (fn)
                                       (if (not (and (pair? fn) (eq? (car fn) '%lir-function)))
                                           fn
                                           (map (lambda (fcl)
                                                  (if (and (pair? fcl) (eq? (car fcl) 'body))
                                                      (cons 'body (%c99-normalize-inline-asm-body (cdr fcl)))
                                                      fcl))
                                                fn)))
                                     (cdr clause))))
                         ((%lir-main)
                          (cons '%lir-main
                                (map (lambda (mcl)
                                       (if (and (pair? mcl) (eq? (car mcl) 'body))
                                           (cons 'body (%c99-normalize-inline-asm-body (cdr mcl)))
                                           mcl))
                                     (cdr clause))))
                         (else clause))))
                 (cdr ir)))))

(set-car! *c99-lower-inline-asm-hook* c99-lower-inline-asm-ir)
