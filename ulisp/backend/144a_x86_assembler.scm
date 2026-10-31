;;; =======================================================================
;;; ULisp Compiler Pass 144a: Standalone x86-64 Machine Code Assembler
;;; Conforms to DSN-33 Architecture Specification & Issue #616
;;; System V ABI AMD64 Architecture Processor Supplement Compliant
;;; =======================================================================
;;; Translates L_asm_x86 AST and GAS Intel-syntax assembly lines into
;;; native x86-64 machine code bytevectors with 2-pass deterministic
;;; label resolution and relocation patching.
;;; =======================================================================

;; -----------------------------------------------------------------------
;; 1. Register Metadata & Helpers
;; -----------------------------------------------------------------------
(define (string=? s1 s2)
  (and (string? s1) (string? s2)
       (= (string-length s1) (string-length s2))
       (let loop ((i 0) (len (string-length s1)))
         (if (= i len)
             #t
             (if (char=? (string-ref s1 i) (string-ref s2 i))
                 (loop (+ i 1) len)
                 #f)))))

;; Each register entry: (list sym id size ext?)
;; size: 8 (64-bit), 4 (32-bit), 1 (8-bit)
;; ext?: #t if id >= 8 or spl/bpl/sil/dil
(define *x86-reg-table*
  '(("rax" 0 8 #f #f) ("rcx" 1 8 #f #f) ("rdx" 2 8 #f #f) ("rbx" 3 8 #f #f)
    ("rsp" 4 8 #f #f) ("rbp" 5 8 #f #f) ("rsi" 6 8 #f #f) ("rdi" 7 8 #f #f)
    ("r8"  8 8 #t #t) ("r9"  9 8 #t #t) ("r10" 10 8 #t #t) ("r11" 11 8 #t #t)
    ("r12" 12 8 #t #t) ("r13" 13 8 #t #t) ("r14" 14 8 #t #t) ("r15" 15 8 #t #t)

    ("%rax" 0 8 #f #f) ("%rcx" 1 8 #f #f) ("%rdx" 2 8 #f #f) ("%rbx" 3 8 #f #f)
    ("%rsp" 4 8 #f #f) ("%rbp" 5 8 #f #f) ("%rsi" 6 8 #f #f) ("%rdi" 7 8 #f #f)
    ("%r8"  8 8 #t #t) ("%r9"  9 8 #t #t) ("%r10" 10 8 #t #t) ("%r11" 11 8 #t #t)
    ("%r12" 12 8 #t #t) ("%r13" 13 8 #t #t) ("%r14" 14 8 #t #t) ("%r15" 15 8 #t #t)

    ("eax" 0 4 #f #f) ("ecx" 1 4 #f #f) ("edx" 2 4 #f #f) ("ebx" 3 4 #f #f)
    ("esp" 4 4 #f #f) ("ebp" 5 4 #f #f) ("esi" 6 4 #f #f) ("edi" 7 4 #f #f)
    ("r8d" 8 4 #t #t) ("r9d" 9 4 #t #t) ("r10d" 10 4 #t #t) ("r11d" 11 4 #t #t)
    ("r12d" 12 4 #t #t) ("r13d" 13 4 #t #t) ("r14d" 14 4 #t #t) ("r15d" 15 4 #t #t)

    ("al" 0 1 #f #f) ("cl" 1 1 #f #f) ("dl" 2 1 #f #f) ("bl" 3 1 #f #f)
    ("spl" 4 1 #f #t) ("bpl" 5 1 #f #t) ("sil" 6 1 #f #t) ("dil" 7 1 #f #t)
    ("r8b" 8 1 #t #t) ("r9b" 9 1 #t #t) ("r10b" 10 1 #t #t) ("r11b" 11 1 #t #t)
    ("r12b" 12 1 #t #t) ("r13b" 13 1 #t #t) ("r14b" 14 1 #t #t) ("r15b" 15 1 #t #t)
    ("%al" 0 1 #f #f) ("%cl" 1 1 #f #f)

    (rax 0 8 #f #f) (rcx 1 8 #f #f) (rdx 2 8 #f #f) (rbx 3 8 #f #f)
    (rsp 4 8 #f #f) (rbp 5 8 #f #f) (rsi 6 8 #f #f) (rdi 7 8 #f #f)
    (r8  8 8 #t #t) (r9  9 8 #t #t) (r10 10 8 #t #t) (r11 11 8 #t #t)
    (r12 12 8 #t #t) (r13 13 8 #t #t) (r14 14 8 #t #t) (r15 15 8 #t #t)
    (%rax 0 8 #f #f) (%rcx 1 8 #f #f) (%rdx 2 8 #f #f) (%rbx 3 8 #f #f)
    (%rsp 4 8 #f #f) (%rbp 5 8 #f #f) (%rsi 6 8 #f #f) (%rdi 7 8 #f #f)
    (%r8  8 8 #t #t) (%r9  9 8 #t #t) (%r10 10 8 #t #t) (%r11 11 8 #t #t)
    (%r12 12 8 #t #t) (%r13 13 8 #t #t) (%r14 14 8 #t #t) (%r15 15 8 #t #t)
    (eax 0 4 #f #f) (ecx 1 4 #f #f) (edx 2 4 #f #f) (ebx 3 4 #f #f)
    (esp 4 4 #f #f) (ebp 5 4 #f #f) (esi 6 4 #f #f) (edi 7 4 #f #f)
    (r8d 8 4 #t #t) (r9d 9 4 #t #t) (r10d 10 4 #t #t) (r11d 11 4 #t #t)
    (r12d 12 4 #t #t) (r13d 13 4 #t #t) (r14d 14 4 #t #t) (r15d 15 4 #t #t)
    (al 0 1 #f #f) (cl 1 1 #f #f) (dl 2 1 #f #f) (bl 3 1 #f #f)
    (spl 4 1 #f #t) (bpl 5 1 #f #t) (sil 6 1 #f #t) (dil 7 1 #f #t)
    (r8b 8 1 #t #t) (r9b 9 1 #t #t) (r10b 10 1 #t #t) (r11b 11 1 #t #t)
    (r12b 12 1 #t #t) (r13b 13 1 #t #t) (r14b 14 1 #t #t) (r15b 15 1 #t #t)
    (%al 0 1 #f #f) (%cl 1 1 #f #f)))

(define (reg->string reg)
  (cond
    ((string? reg) (safe-string-downcase reg))
    ((symbol? reg)
     (case reg
       ((rax %rax) "rax") ((rcx %rcx) "rcx") ((rdx %rdx) "rdx") ((rbx %rbx) "rbx")
       ((rsp %rsp) "rsp") ((rbp %rbp) "rbp") ((rsi %rsi) "rsi") ((rdi %rdi) "rdi")
       ((r8 %r8) "r8") ((r9 %r9) "r9") ((r10 %r10) "r10") ((r11 %r11) "r11")
       ((r12 %r12) "r12") ((r13 %r13) "r13") ((r14 %r14) "r14") ((r15 %r15) "r15")
       ((eax) "eax") ((ecx) "ecx") ((edx) "edx") ((ebx) "ebx")
       ((esp) "esp") ((ebp) "ebp") ((esi) "esi") ((edi) "edi")
       ((r8d) "r8d") ((r9d) "r9d") ((r10d) "r10d") ((r11d) "r11d")
       ((r12d) "r12d") ((r13d) "r13d") ((r14d) "r14d") ((r15d) "r15d")
       ((al %al) "al") ((cl %cl) "cl") ((dl) "dl") ((bl) "bl")
       ((spl) "spl") ((bpl) "bpl") ((sil) "sil") ((dil) "dil")
       ((r8b) "r8b") ((r9b) "r9b") ((r10b) "r10b") ((r11b) "r11b")
       ((r12b) "r12b") ((r13b) "r13b") ((r14b) "r14b") ((r15b) "r15b")
       (else "")))
    (else "")))

(define (lookup-x86-reg reg)
  (let ((s (reg->string reg)))
    (let loop ((entries *x86-reg-table*))
      (if (pair? entries)
          (if (and (string? (caar entries)) (string=? s (caar entries)))
              (cdar entries)
              (loop (cdr entries)))
          #f))))

(define (x86-reg? reg)
  (pair? (lookup-x86-reg reg)))

(define (canonical-mnem sym-or-str)
  (if (symbol? sym-or-str)
      (case sym-or-str
        ((nop) 'nop) ((ret) 'ret) ((syscall) 'syscall) ((cld) 'cld) ((cqo) 'cqo)
        ((rep-movsb rep) 'rep-movsb) ((push) 'push) ((pop) 'pop) ((call) 'call) ((jmp) 'jmp)
        ((je jz) 'je) ((jne jnz) 'jne) ((jb) 'jb) ((jae jnc) 'jae) ((jbe) 'jbe) ((ja) 'ja)
        ((js) 'js) ((jns) 'jns) ((jl) 'jl) ((jge) 'jge) ((jle) 'jle) ((jg) 'jg)
        ((sete setz) 'sete) ((setne setnz) 'setne) ((setb) 'setb) ((setae) 'setae)
        ((setbe) 'setbe) ((seta) 'seta) ((setl) 'setl) ((setge) 'setge) ((setle) 'setle) ((setg) 'setg)
        ((cmove cmovz) 'cmove) ((cmovne cmovnz) 'cmovne) ((cmovl) 'cmovl) ((cmovge) 'cmovge)
        ((cmovle) 'cmovle) ((cmovg) 'cmovg) ((movzx) 'movzx) ((lea) 'lea) ((mov) 'mov)
        ((add) 'add) ((sub) 'sub) ((and) 'and) ((or) 'or) ((xor) 'xor) ((cmp) 'cmp)
        ((bt) 'bt) ((test) 'test) ((imul) 'imul) ((idiv) 'idiv) ((div) 'div)
        ((shl) 'shl) ((shr) 'shr) ((sar) 'sar) ((neg) 'neg) ((not) 'not)
        ((inc) 'inc) ((dec) 'dec) ((mfence) 'mfence) ((cmpxchg) 'cmpxchg)
        (else 'unknown))
      (let ((s (if (string? sym-or-str) (safe-string-downcase sym-or-str) "")))
        (cond
          ((string=? s "nop") 'nop)
          ((string=? s "ret") 'ret)
          ((string=? s "syscall") 'syscall)
          ((string=? s "cld") 'cld)
          ((string=? s "cqo") 'cqo)
          ((or (string=? s "rep-movsb") (string=? s "rep")) 'rep-movsb)
          ((string=? s "push") 'push)
          ((string=? s "pop") 'pop)
          ((string=? s "call") 'call)
          ((string=? s "jmp") 'jmp)
          ((or (string=? s "je") (string=? s "jz")) 'je)
          ((or (string=? s "jne") (string=? s "jnz")) 'jne)
          ((string=? s "jb") 'jb)
          ((or (string=? s "jae") (string=? s "jnc")) 'jae)
          ((string=? s "jbe") 'jbe)
          ((string=? s "ja") 'ja)
          ((string=? s "js") 'js)
          ((string=? s "jns") 'jns)
          ((string=? s "jl") 'jl)
          ((string=? s "jge") 'jge)
          ((string=? s "jle") 'jle)
          ((string=? s "jg") 'jg)
          ((or (string=? s "sete") (string=? s "setz")) 'sete)
          ((or (string=? s "setne") (string=? s "setnz")) 'setne)
          ((string=? s "setb") 'setb)
          ((string=? s "setae") 'setae)
          ((string=? s "setbe") 'setbe)
          ((string=? s "seta") 'seta)
          ((string=? s "setl") 'setl)
          ((string=? s "setge") 'setge)
          ((string=? s "setle") 'setle)
          ((string=? s "setg") 'setg)
          ((or (string=? s "cmove") (string=? s "cmovz")) 'cmove)
          ((or (string=? s "cmovne") (string=? s "cmovnz")) 'cmovne)
          ((string=? s "cmovl") 'cmovl)
          ((string=? s "cmovge") 'cmovge)
          ((string=? s "cmovle") 'cmovle)
          ((string=? s "cmovg") 'cmovg)
          ((string=? s "movzx") 'movzx)
          ((string=? s "lea") 'lea)
          ((string=? s "mov") 'mov)
          ((string=? s "add") 'add)
          ((string=? s "sub") 'sub)
          ((string=? s "and") 'and)
          ((string=? s "or") 'or)
          ((string=? s "xor") 'xor)
          ((string=? s "cmp") 'cmp)
          ((string=? s "bt") 'bt)
          ((string=? s "test") 'test)
          ((string=? s "imul") 'imul)
          ((string=? s "idiv") 'idiv)
          ((string=? s "div") 'div)
          ((string=? s "shl") 'shl)
          ((string=? s "shr") 'shr)
          ((string=? s "sar") 'sar)
          ((string=? s "neg") 'neg)
          ((string=? s "not") 'not)
          ((string=? s "inc") 'inc)
          ((string=? s "dec") 'dec)
          ((string=? s "mfence") 'mfence)
          ((or (string=? s "cmpxchg") (string=? s "cmpxchgq")) 'cmpxchg)
          (else 'unknown)))))

(define (reg-id info) (if (pair? info) (car info) 0))
(define (reg-size info) (if (and (pair? info) (pair? (cdr info))) (cadr info) 8))
(define (reg-ext? info) (if (and (pair? info) (pair? (cdr info)) (pair? (cddr info))) (caddr info) #f))
(define (reg-rex? info) (if (and (pair? info) (pair? (cdr info)) (pair? (cddr info)) (pair? (cdddr info))) (cadddr info) #f))

;; Accessors for parsed operands
(define (op-is-reg? op) (and (pair? op) (eq? (car op) 'reg)))
(define (op-is-mem? op) (and (pair? op) (eq? (car op) 'mem)))
(define (op-is-imm? op) (and (pair? op) (eq? (car op) 'imm)))

(define (reg-op-sym op) (if (and (pair? op) (pair? (cdr op))) (cadr op) #f))
(define (reg-op-id op) (if (and (pair? op) (pair? (cdr op)) (pair? (cddr op))) (caddr op) 0))
(define (reg-op-size op) (if (and (pair? op) (pair? (cdr op)) (pair? (cddr op)) (pair? (cdddr op))) (cadddr op) 8))
(define (reg-op-ext? op) (if (and (pair? op) (pair? (cdr op)) (pair? (cddr op)) (pair? (cdddr op)) (pair? (cddddr op))) (car (cddddr op)) #f))

(define (reloc-sym op) (if (and (pair? op) (pair? (cdr op))) (cadr op) ""))
(define (reloc-addend op) (if (and (pair? op) (pair? (cdr op)) (pair? (cddr op))) (caddr op) 0))

(define (mem-base op) (if (and (pair? op) (pair? (cdr op))) (cadr op) #f))
(define (mem-index op) (if (and (pair? op) (pair? (cdr op)) (pair? (cddr op))) (caddr op) #f))
(define (mem-scale op) (if (and (pair? op) (pair? (cdr op)) (pair? (cddr op)) (pair? (cdddr op))) (cadddr op) 1))
(define (mem-disp op) (if (and (pair? op) (pair? (cdr op)) (pair? (cddr op)) (pair? (cdddr op)) (pair? (cddddr op))) (car (cddddr op)) 0))
(define (mem-size op) (if (and (pair? op) (pair? (cdr op)) (pair? (cddr op)) (pair? (cdddr op)) (pair? (cddddr op)) (pair? (cdr (cddddr op)))) (cadr (cddddr op)) 8))
(define (mem-rip-sym op) (if (and (pair? op) (pair? (cdr op)) (pair? (cddr op)) (pair? (cdddr op)) (pair? (cddddr op)) (pair? (cdr (cddddr op))) (pair? (cddr (cddddr op)))) (caddr (cddddr op)) #f))

;; -----------------------------------------------------------------------
;; 2. Instruction Encoding Helpers (REX, ModR/M, SIB)
;; -----------------------------------------------------------------------
;; REX: 0x40 | (W << 3) | (R << 2) | (X << 1) | B
(define (make-rex w r x b)
  (+ (+ (+ (+ 64 (if w 8 0))
           (if r 4 0))
        (if x 2 0))
     (if b 1 0)))

;; ModR/M: (mod << 6) | (reg << 3) | rm
(define (make-modrm mod reg rm)
  (+ (+ (* (modulo mod 4) 64)
        (* (modulo reg 8) 8))
     (modulo rm 8)))

;; SIB: (scale << 6) | (index << 3) | base
(define (make-sib scale index base)
  (+ (+ (* (modulo scale 4) 64)
        (* (modulo index 8) 8))
     (modulo base 8)))

(define (asm-concat-2 l1 l2)
  (if (null? l1)
      l2
      (cons (car l1) (asm-concat-2 (cdr l1) l2))))

(define (asm-flatten lists)
  (let loop ((rest lists))
    (cond
      ((null? rest) '())
      ((null? (cdr rest)) (car rest))
      (else (asm-concat-2 (car rest) (loop (cdr rest)))))))

(define (enc-rex enc) (car enc))
(define (enc-modrm enc) (cadr enc))
(define (enc-sib enc) (caddr enc))
(define (enc-disp enc) (cadddr enc))

;; Little-Endian list of bytes for 16, 32, 64-bit integers
(define (split-u16-le val)
  (let ((u (if (< val 0) (+ val 65536) val)))
    (list (modulo u 256)
          (modulo (quotient u 256) 256))))

(define (split-u32-le val)
  (let ((u (if (< val 0) (+ val 4294967296) val)))
    (list (modulo u 256)
          (modulo (quotient u 256) 256)
          (modulo (quotient u 65536) 256)
          (modulo (quotient u 16777216) 256))))

(define (split-u64-le val)
  (append (split-u32-le (modulo val 4294967296))
          (split-u32-le (quotient val 4294967296))))

;; -----------------------------------------------------------------------
;; 3. String & Token Utilities for Assembly Line Parsing
;; -----------------------------------------------------------------------
(define (string-starts-with? s prefix)
  (let ((slen (string-length s))
        (plen (string-length prefix)))
    (if (< slen plen)
        #f
        (let loop ((i 0))
          (if (= i plen)
              #t
              (if (char=? (string-ref s i) (string-ref prefix i))
                  (loop (+ i 1))
                  #f))))))

(define (safe-string-downcase str)
  (let* ((len (string-length str))
         (res (make-string len)))
    (let loop ((i 0))
      (if (< i len)
          (let* ((c (string-ref str i))
                 (code (char->integer c))
                 (new-c (if (and (>= code 65) (<= code 90))
                            (integer->char (+ code 32))
                            c)))
            (string-set! res i new-c)
            (loop (+ i 1)))
          res))))

(define (safe-string->number val)
  (cond
    ((number? val) val)
    ((symbol? val) (safe-string->number (symbol->string val)))
    ((string? val)
     (let ((len (string-length val)))
       (if (= len 0)
           #f
           (let* ((c0 (string-ref val 0))
                  (neg? (char=? c0 #\-))
                  (pos? (char=? c0 #\+))
                  (start (if (or neg? pos?) 1 0)))
             (if (and (< (+ start 2) len)
                      (char=? (string-ref val start) #\0)
                      (let ((c1 (string-ref val (+ start 1))))
                        (or (char=? c1 #\x) (char=? c1 #\X))))
                 ;; Hexadecimal: 0x...
                 (let loop ((i (+ start 2)) (acc 0))
                   (if (>= i len)
                       (if neg? (- 0 acc) acc)
                       (let* ((c (string-ref val i))
                              (code (char->integer c))
                              (digit (cond
                                       ((and (>= code 48) (<= code 57)) (- code 48))
                                       ((and (>= code 97) (<= code 102)) (+ 10 (- code 97)))
                                       ((and (>= code 65) (<= code 70)) (+ 10 (- code 65)))
                                       (else #f))))
                         (if digit
                             (loop (+ i 1) (+ (* acc 16) digit))
                             #f))))
                 ;; Decimal
                 (if (and (= start 1) (= len 1))
                     #f
                     (let loop ((i start) (acc 0))
                       (if (>= i len)
                           (if neg? (- 0 acc) acc)
                           (let ((c (string-ref val i)))
                             (if (and (char>=? c #\0) (char<=? c #\9))
                                 (loop (+ i 1) (+ (* acc 10) (- (char->integer c) 48)))
                                 #f))))))))))
    (else #f)))

(define (asm-char-whitespace? c)
  (let ((code (char->integer c)))
    (or (= code 32) (= code 9) (= code 10) (= code 13))))

(define (asm-trim-string str)
  (let* ((len (string-length str))
         (start (let loop ((i 0))
                  (if (and (< i len) (asm-char-whitespace? (string-ref str i)))
                      (loop (+ i 1))
                      i)))
         (end (let loop ((j len))
                (if (and (> j start) (asm-char-whitespace? (string-ref str (- j 1))))
                    (loop (- j 1))
                    j))))
    (if (and (= start 0) (= end len))
        str
        (substring str start end))))

(define (asm-strip-comment line)
  (let ((len (string-length line)))
    (let loop ((i 0) (in-quote #f))
      (if (>= i len)
          line
          (let ((c (string-ref line i)))
            (cond
              ((char=? c #\") (loop (+ i 1) (not in-quote)))
              ((and (not in-quote) (or (char=? c #\#) (char=? c #\;)))
               (substring line 0 i))
              (else (loop (+ i 1) in-quote))))))))

(define (asm-tokenize-line line)
  (let* ((clean (asm-trim-string (asm-strip-comment line)))
         (len (string-length clean)))
    (if (= len 0)
        '()
        (let loop ((i 0) (tokens '()))
          (if (>= i len)
              (reverse tokens)
              (let ((c (string-ref clean i)))
                (cond
                  ((asm-char-whitespace? c)
                   (loop (+ i 1) tokens))
                  ((char=? c #\,)
                   (loop (+ i 1) (cons "," tokens)))
                  ((char=? c #\:)
                   (loop (+ i 1) (cons ":" tokens)))
                  ((char=? c #\")
                   (let str-loop ((j (+ i 1)) (escaped #f) (chars '()))
                     (if (>= j len)
                         (reverse (cons (list->string (reverse chars)) tokens))
                         (let ((sc (string-ref clean j)))
                           (cond
                             (escaped
                              (str-loop (+ j 1) #f (cons (case sc ((#\n) #\newline) ((#\t) #\tab) ((#\\) #\\) ((#\") #\") (else sc)) chars)))
                             ((char=? sc #\\)
                              (str-loop (+ j 1) #t chars))
                             ((char=? sc #\")
                              (loop (+ j 1) (cons (list->string (reverse chars)) tokens)))
                             (else
                              (str-loop (+ j 1) #f (cons sc chars))))))))
                  (else
                   (let tok-loop ((j i))
                     (if (or (>= j len)
                             (asm-char-whitespace? (string-ref clean j))
                             (char=? (string-ref clean j) #\,)
                             (char=? (string-ref clean j) #\:))
                         (loop j (cons (substring clean i j) tokens))
                         (tok-loop (+ j 1))))))))))))

;; -----------------------------------------------------------------------
;; 4. Direct x86-64 Instruction Encoding Engine
;; -----------------------------------------------------------------------
;; Operand AST definitions:
;; - (list 'reg name id size ext?)
;; - (list 'mem base-id index-id scale disp size rip-sym?)
;; - (list 'imm val)
;; - (list 'rel-sym sym addend)

(define (encode-modrm-sib-disp w r-info mem-op)
  ;; mem-op: (list 'mem base-info index-info scale disp size rip-sym)
  (let* ((mem-op (if (and (pair? mem-op) (eq? (car mem-op) 'rel-sym))
                     (list 'mem #f #f 1 0 8 (cadr mem-op))
                     mem-op))
         (r-id (if (pair? r-info) (reg-id r-info) 0))
         (r-ext? (if (pair? r-info) (reg-ext? r-info) #f))
         (r-rex? (if (pair? r-info) (reg-rex? r-info) #f))
         (base-info (mem-base mem-op))
         (index-info (mem-index mem-op))
         (scale (mem-scale mem-op))
         (disp (mem-disp mem-op))
         (rip-sym (mem-rip-sym mem-op)))
    (cond
      ;; RIP-relative: [rip + sym/disp] -> mod=00, rm=5 (disp32)
      (rip-sym
       (let* ((rex (make-rex w r-ext? #f #f))
              (modrm (make-modrm 0 r-id 5))
              (disp-bytes (split-u32-le disp)))
         (list (if (or w r-ext? r-rex?) (list rex) '())
               (list modrm)
               '()
               disp-bytes)))

      ;; Memory with Index register (SIB): [base + index*scale + disp]
      (index-info
       (let* ((b-id (if base-info (reg-id base-info) 0))
              (b-ext? (if base-info (reg-ext? base-info) #f))
              (b-rex? (if base-info (reg-rex? base-info) #f))
              (i-id (if index-info (reg-id index-info) 0))
              (i-ext? (if index-info (reg-ext? index-info) #f))
              (i-rex? (if index-info (reg-rex? index-info) #f))
              (mod (cond ((= disp 0) (if (or (= b-id 5) (= b-id 13)) 1 0))
                         ((and (>= disp -128) (<= disp 127)) 1)
                         (else 2)))
              (rex (make-rex w r-ext? i-ext? b-ext?))
              (modrm (make-modrm mod r-id 4))
              (sib (make-sib (case scale ((1) 0) ((2) 1) ((4) 2) ((8) 3) (else 0))
                             (modulo i-id 8)
                             (modulo b-id 8)))
              (disp-bytes (cond ((= mod 0) '())
                                ((= mod 1) (list (modulo (if (< disp 0) (+ disp 256) disp) 256)))
                                (else (split-u32-le disp)))))
         (list (if (or w r-ext? i-ext? b-ext? r-rex? b-rex? i-rex?) (list rex) '())
               (list modrm)
               (list sib)
               disp-bytes)))

      ;; Base-only (or RSP/R12 which forces SIB 0x24)
      (else
       (let* ((b-id (if base-info (reg-id base-info) 0))
              (b-ext? (if base-info (reg-ext? base-info) #f))
              (b-rex? (if base-info (reg-rex? base-info) #f))
              (force-sib? (or (= b-id 4) (= b-id 12))) ;; rsp, r12 require SIB
              (mod (cond ((and (= disp 0) (not (or (= b-id 5) (= b-id 13)))) 0)
                         ((and (>= disp -128) (<= disp 127)) 1)
                         (else 2)))
              (rex (make-rex w r-ext? #f b-ext?))
              (modrm (make-modrm mod r-id (if force-sib? 4 (modulo b-id 8))))
              (sib-bytes (if force-sib? (list (make-sib 0 4 (modulo b-id 8))) '()))
              (disp-bytes (cond ((= mod 0) '())
                                ((= mod 1) (list (modulo (if (< disp 0) (+ disp 256) disp) 256)))
                                (else (split-u32-le disp)))))
         (list (if (or w r-ext? b-ext? r-rex? b-rex?) (list rex) '())
               (list modrm)
               sib-bytes
               disp-bytes))))))

;; Helper to parse memory string: e.g. "[rsp - 8]", "[rip + .L_1]", "byte ptr [rax]"
(define (parse-mem-operand-str str)
  (let* ((clean (asm-trim-string str))
         ;; detect width prefix
         (is-byte? (or (string-starts-with? clean "byte ptr") (string-starts-with? clean "BYTE PTR")))
         (is-dword? (or (string-starts-with? clean "dword ptr") (string-starts-with? clean "DWORD PTR")))
         (is-qword? (or (string-starts-with? clean "qword ptr") (string-starts-with? clean "QWORD PTR")))
         (size (cond (is-byte? 1) (is-dword? 4) (else 8)))
         ;; extract bracket contents
         (lb (let loop ((i 0)) (if (or (>= i (string-length clean)) (char=? (string-ref clean i) #\[)) i (loop (+ i 1)))))
         (rb (let loop ((i (- (string-length clean) 1))) (if (or (< i 0) (char=? (string-ref clean i) #\])) i (loop (- i 1)))))
         (inner (if (and (< lb rb) (< lb (string-length clean)))
                    (asm-trim-string (substring clean (+ lb 1) rb))
                    "rsp")))
    ;; Parse inner components: e.g. "rsp - 8", "rax + 96", "rip + ulisp_state", "rdx + rcx*8"
    (let ((tokens (let loop ((i 0) (cur '()) (acc '()))
                    (if (>= i (string-length inner))
                        (if (null? cur) (reverse acc) (reverse (cons (list->string (reverse cur)) acc)))
                        (let ((c (string-ref inner i)))
                          (cond
                            ((or (char=? c #\+) (char=? c #\-))
                             (let ((a (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
                               (loop (+ i 1) '() (cons (string c) a))))
                            ((asm-char-whitespace? c)
                             (if (null? cur)
                                 (loop (+ i 1) '() acc)
                                 (loop (+ i 1) '() (cons (list->string (reverse cur)) acc))))
                            (else
                             (loop (+ i 1) (cons c cur) acc))))))))
      (let* ((first-tok (if (pair? tokens) (car tokens) "rsp"))
             (is-rip? (string=? (safe-string-downcase first-tok) "rip")))
        (if is-rip?
            ;; RIP-relative: (list 'mem #f #f 0 disp size rip-sym)
            (let* ((sign (if (and (pair? (cdr tokens)) (string=? (cadr tokens) "-")) -1 1))
                   (sym-or-disp (if (pair? (cddr tokens)) (caddr tokens) "0"))
                   (num (safe-string->number sym-or-disp)))
              (if num
                  (list 'mem #f #f 0 (* num sign) size "rip_disp")
                  (let loop ((rem (cdddr tokens)) (disp 0))
                    (cond
                      ((null? rem)
                       (list 'mem #f #f 0 disp size sym-or-disp))
                      ((or (string=? (car rem) "+") (string=? (car rem) "-"))
                       (let* ((s (if (string=? (car rem) "-") -1 1))
                              (n (if (pair? (cdr rem)) (safe-string->number (cadr rem)) 0)))
                         (loop (cddr rem) (+ disp (* (if n n 0) s)))))
                      (else
                       (loop (cdr rem) disp))))))
            ;; Register base + disp or index
            (let* ((b-info (lookup-x86-reg first-tok))
                   (b-reg (if b-info b-info (lookup-x86-reg "rsp")))
                   (rest (cdr tokens)))
              (let parse-rest ((ts rest) (idx-info #f) (scale 1) (disp 0))
                (cond
                  ((null? ts)
                   (list 'mem b-reg idx-info scale disp size #f))
                  ((or (string=? (car ts) "+") (string=? (car ts) "-"))
                   (let* ((sign (if (string=? (car ts) "-") -1 1))
                          (next-tok (if (pair? (cdr ts)) (cadr ts) "0"))
                          (num (safe-string->number next-tok)))
                     (if num
                         (parse-rest (cddr ts) idx-info scale (+ disp (* num sign)))
                         ;; check if next-tok is reg or reg*scale
                         (let* ((star-pos (let loop ((k 0)) (if (or (>= k (string-length next-tok)) (char=? (string-ref next-tok k) #\*)) k (loop (+ k 1)))))
                                (r-name (if (< star-pos (string-length next-tok))
                                            (substring next-tok 0 star-pos)
                                            next-tok))
                                (sc (if (< star-pos (string-length next-tok))
                                        (safe-string->number (substring next-tok (+ star-pos 1) (string-length next-tok)))
                                        1))
                                (r-info (lookup-x86-reg r-name)))
                           (if r-info
                               (parse-rest (cddr ts) r-info (if sc sc 1) disp)
                               (parse-rest (cddr ts) idx-info scale disp))))))
                  (else
                   (parse-rest (cdr ts) idx-info scale disp))))))))))

;; Helper to parse register or immediate or memory from token
(define (parse-operand-str tok)
  (let* ((str (cond ((string? tok) tok)
                    ((symbol? tok) (symbol->string tok))
                    ((number? tok) (number->string tok))
                    (else (error "Invalid operand token" tok))))
         (clean (asm-trim-string str)))
    (cond
      ((or (string-starts-with? clean "[")
           (string-starts-with? clean "byte ptr")
           (string-starts-with? clean "BYTE PTR")
           (string-starts-with? clean "dword ptr")
           (string-starts-with? clean "DWORD PTR")
           (string-starts-with? clean "qword ptr")
           (string-starts-with? clean "QWORD PTR"))
       (parse-mem-operand-str clean))
      ((x86-reg? clean)
       (let ((info (lookup-x86-reg clean)))
         (list 'reg (safe-string-downcase clean) (reg-id info) (reg-size info) (reg-ext? info))))
      ((safe-string->number clean)
       (list 'imm (safe-string->number clean)))
      ((and (>= (string-length clean) 3)
            (char=? (string-ref clean 0) #\')
            (char=? (string-ref clean (- (string-length clean) 1)) #\'))
       (let ((c (string-ref clean 1)))
         (list 'imm (if (and (= (string-length clean) 4) (char=? c #\\))
                        (case (string-ref clean 2)
                          ((#\n) 10)
                          ((#\t) 9)
                          ((#\0) 0)
                          ((#\r) 13)
                          (else (char->integer (string-ref clean 2))))
                        (char->integer c)))))
      (else
       ;; Label or symbol reference
       (list 'rel-sym clean 0)))))

;; -----------------------------------------------------------------------
;; 5. Single Instruction Assembler Function
;; -----------------------------------------------------------------------
;; Returns: (list (bytes ...) reloc-or-#f)
;; reloc format: (list type sym addend patch-offset)
;; type: 'rel32, 'rip_disp32, 'abs64
(define (assemble-inst raw-mnem opnds curr-off)
  (let ((mnem (canonical-mnem raw-mnem)))
    (case mnem
    ((nop)
     (list '(144) #f)) ;; 0x90

    ((ret)
     (list '(195) #f)) ;; 0xC3

    ((syscall)
     (list '(15 5) #f)) ;; 0x0F 0x05

    ((cld)
     (list '(252) #f)) ;; 0xFC

    ((cqo)
     (list '(72 153) #f))

    ((rep-movsb rep)
     (list '(243 164) #f))

    ((push)
     (let ((op (car opnds)))
       (case (car op)
         ((reg)
          (let ((id (reg-op-id op)) (ext? (reg-op-ext? op)))
            (list (append (if ext? '(65) '()) (list (+ 80 (modulo id 8)))) #f)))
         ((imm)
          (let ((val (cadr op)))
            (if (and (>= val -128) (<= val 127))
                (list (list 106 (modulo (if (< val 0) (+ val 256) val) 256)) #f)
                (list (cons 104 (split-u32-le val)) #f))))
         ((mem rel-sym)
          ;; push mem: FF /6
          (let ((enc (encode-modrm-sib-disp #f (list 0 8 #f) op)))
            (let* ((modrm (car (enc-modrm enc)))
                   (modrm-ext (+ (+ (modulo modrm 8) 48) (modulo (quotient modrm 64) 4)))) ;; /6 = opcode ext 6 (6<<3 = 48)
              (list (asm-flatten (list (enc-rex enc) (list 255 modrm-ext) (enc-sib enc) (enc-disp enc))) #f))))
         (else
          (list '(144) #f)))))

    ((pop)
     (let ((op (car opnds)))
       (case (car op)
         ((reg)
          (let ((id (reg-op-id op)) (ext? (reg-op-ext? op)))
            (list (append (if ext? '(65) '()) (list (+ 88 (modulo id 8)))) #f)))
         ((mem rel-sym)
          ;; pop mem: 8F /0
          (let ((enc (encode-modrm-sib-disp #f (list 0 8 #f) op)))
            (list (asm-flatten (list (enc-rex enc) (list 143) (enc-modrm enc) (enc-sib enc) (enc-disp enc))) #f)))
         (else
          (list '(144) #f)))))

    ((call)
     (let ((op (car opnds)))
       (case (car op)
         ((reg)
          ;; call reg: FF /2
          (let ((id (reg-op-id op)) (ext? (reg-op-ext? op)))
            (list (append (if ext? '(65) '()) (list 255 (make-modrm 3 2 id))) #f)))
         (else
          ;; call rel32: E8 cd
          (let ((sym (reloc-sym op)) (addend (reloc-addend op)))
            (list '(232 0 0 0 0)
                  (list 'rel32 (+ curr-off 1) sym addend)))))))

    ((jmp)
     (let ((op (car opnds)))
       (case (car op)
         ((reg)
          ;; jmp reg: FF /4
          (let ((id (reg-op-id op)) (ext? (reg-op-ext? op)))
            (list (append (if ext? '(65) '()) (list 255 (make-modrm 3 4 id))) #f)))
         (else
          ;; jmp rel32: E9 cd
          (let ((sym (reloc-sym op)) (addend (reloc-addend op)))
            (list '(233 0 0 0 0)
                  (list 'rel32 (+ curr-off 1) sym addend)))))))

    ;; Conditional Jumps: jcc label -> 0F 80+cc rel32
    ((je jz jne jnz jl jle jg jge jb jbe ja jae jnc js jns)
     (let* ((cc-code (case mnem
                       ((je jz) 132)
                       ((jne jnz) 133)
                       ((jb) 130)
                       ((jae jnc) 131)
                       ((jbe) 134)
                       ((ja) 135)
                       ((js) 136)
                       ((jns) 137)
                       ((jl) 140)
                       ((jge) 141)
                       ((jle) 142)
                       ((jg) 143)
                       (else 132)))
            (op (car opnds))
            (sym (reloc-sym op))
            (addend (reloc-addend op)))
       (list (list 15 cc-code 0 0 0 0)
             (list 'rel32 (+ curr-off 2) sym addend))))

    ;; Condition Set: setcc r8 -> 0F 90+cc ModR/M
    ((sete setz setne setnz setl setle setg setge setb setbe seta setae)
     (let* ((cc-code (case mnem
                       ((sete setz) 148)
                       ((setne setnz) 149)
                       ((setb) 146)
                       ((setae) 147)
                       ((setbe) 150)
                       ((seta) 151)
                       ((setl) 156)
                       ((setge) 157)
                       ((setle) 158)
                       ((setg) 159)
                       (else 148)))
            (dst (car opnds))
            (d-id (caddr dst))
            (d-ext? (car (cddddr dst))))
       (list (append (if d-ext? '(64) '()) (list 15 cc-code (make-modrm 3 0 d-id))) #f)))

    ;; Conditional Move: cmovcc r64, r64/mem -> REX.W 0F 40+cc ModR/M
    ((cmove cmovz cmovne cmovnz cmovl cmovle cmovg cmovge)
     (let* ((cc-code (case mnem
                       ((cmove cmovz) 68)
                       ((cmovne cmovnz) 69)
                       ((cmovl) 76)
                       ((cmovge) 77)
                       ((cmovle) 78)
                       ((cmovg) 79)
                       (else 68)))
            (dst (car opnds))
            (src (cadr opnds)))
       (case (car src)
         ((reg)
          (let* ((rex (make-rex #t (reg-ext? (lookup-x86-reg (cadr dst))) #f (reg-ext? (lookup-x86-reg (cadr src)))))
                 (modrm (make-modrm 3 (caddr dst) (caddr src))))
            (list (list rex 15 cc-code modrm) #f)))
         ((mem)
          (let ((enc (encode-modrm-sib-disp #t (lookup-x86-reg (cadr dst)) src)))
            (list (asm-flatten (list (enc-rex enc) (list 15 cc-code) (enc-modrm enc) (enc-sib enc) (enc-disp enc))) #f))))))

    ;; MOVZX: movzx r32/r64, byte/word ptr [mem]
    ((movzx)
     (let* ((dst (car opnds))
            (src (cadr opnds))
            (d-info (lookup-x86-reg (cadr dst))))
       (case (car src)
         ((mem)
          (let* ((enc (encode-modrm-sib-disp #f d-info src))
                 (rip-sym (mem-rip-sym src)))
            (if (and rip-sym (not (string=? rip-sym "rip_disp")))
                (list (asm-flatten (list (enc-rex enc) (list 15 182) (enc-modrm enc) (enc-sib enc) '(0 0 0 0)))
                      (list 'rip_disp32 (+ curr-off (length (asm-flatten (list (enc-rex enc) (list 15 182) (enc-modrm enc) (enc-sib enc))))) rip-sym (mem-disp src) 0))
                (list (asm-flatten (list (enc-rex enc) (list 15 182) (enc-modrm enc) (enc-sib enc) (enc-disp enc))) #f))))
         (else
          (let ((rex (make-rex #f (reg-ext? d-info) #f (reg-ext? (lookup-x86-reg (cadr src))))))
            (list (append (if (or (reg-ext? d-info) (reg-ext? (lookup-x86-reg (cadr src)))) (list rex) '())
                          (list 15 182 (make-modrm 3 (reg-id d-info) (caddr src)))) #f))))))

    ;; LEA: lea r64, [mem]
    ((lea)
     (let* ((dst (car opnds))
            (raw-src (cadr opnds))
            (src (if (and (pair? raw-src) (eq? (car raw-src) 'rel-sym))
                     (list 'mem #f #f 1 0 8 (cadr raw-src))
                     raw-src))
            (d-info (lookup-x86-reg (cadr dst)))
            (enc (encode-modrm-sib-disp #t d-info src))
            (rip-sym (mem-rip-sym src)))
       (if (and rip-sym (not (string=? rip-sym "rip_disp")))
           (list (asm-flatten (list (enc-rex enc) (list 141) (enc-modrm enc) (enc-sib enc) '(0 0 0 0)))
                 (list 'rip_disp32 (+ curr-off (length (asm-flatten (list (enc-rex enc) (list 141) (enc-modrm enc) (enc-sib enc))))) rip-sym (mem-disp src) 0))
           (list (asm-flatten (list (enc-rex enc) (list 141) (enc-modrm enc) (enc-sib enc) (enc-disp enc))) #f))))

    ;; MOV
    ((mov)
     (let ((dst (car opnds))
           (src (cadr opnds)))
       (cond
         ;; mov reg, reg
         ((and (eq? (car dst) 'reg) (eq? (car src) 'reg))
          (let* ((d-info (lookup-x86-reg (cadr dst)))
                 (s-info (lookup-x86-reg (cadr src)))
                 (w (= (reg-size d-info) 8))
                 (rex (make-rex w (reg-ext? s-info) #f (reg-ext? d-info)))
                 (modrm (make-modrm 3 (reg-id s-info) (reg-id d-info)))
                 (opc (if (= (reg-size d-info) 1) 136 137)))
            (list (append (if (or w (reg-ext? s-info) (reg-ext? d-info) (reg-rex? s-info) (reg-rex? d-info)) (list rex) '())
                          (list opc modrm)) #f)))

         ;; mov reg, imm
         ((and (eq? (car dst) 'reg) (eq? (car src) 'imm))
          (let* ((d-info (lookup-x86-reg (cadr dst)))
                 (val (cadr src))
                 (sz (reg-size d-info)))
            (cond
              ;; 8-bit reg: B0+rb imm8
              ((= sz 1)
               (let* ((rex (make-rex #f #f #f (reg-ext? d-info)))
                      (opc (+ 176 (modulo (reg-id d-info) 8))))
                 (list (append (if (or (reg-ext? d-info) (reg-rex? d-info)) (list rex) '())
                               (list opc (modulo (if (< val 0) (+ val 256) val) 256))) #f)))

              ;; 32-bit reg: B8+rd imm32
              ((= sz 4)
               (let* ((rex (make-rex #f #f #f (reg-ext? d-info)))
                      (opc (+ 184 (modulo (reg-id d-info) 8))))
                 (list (append (if (reg-ext? d-info) (list rex) '())
                               (cons opc (split-u32-le val))) #f)))

              ;; 64-bit reg:
              ((let ((q (quotient val 4)))
                 (and (>= q -536870912) (<= q 536870911)))
               ;; 32-bit sign-extended: REX.W C7 /0 imm32
               (let* ((rex (make-rex #t #f #f (reg-ext? d-info)))
                      (modrm (make-modrm 3 0 (reg-id d-info))))
                 (list (cons rex (cons 199 (cons modrm (split-u32-le val)))) #f)))

              (else
               ;; 64-bit full imm: REX.W B8+rd imm64
               (let ((rex (make-rex #t #f #f (reg-ext? d-info))))
                 (list (cons rex (cons (+ 184 (modulo (reg-id d-info) 8)) (split-u64-le val))) #f))))))

         ;; mov reg, [mem]
         ((and (eq? (car dst) 'reg) (eq? (car src) 'mem))
          (let* ((d-info (lookup-x86-reg (cadr dst)))
                 (sz (mem-size src))
                 (w (= (reg-size d-info) 8))
                 (enc (encode-modrm-sib-disp w d-info src))
                 (opc (if (= (reg-size d-info) 1) 138 139))
                 (rip-sym (mem-rip-sym src)))
            (if (and rip-sym (not (string=? rip-sym "rip_disp")))
                (list (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc) '(0 0 0 0)))
                      (list 'rip_disp32 (+ curr-off (length (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc))))) rip-sym (mem-disp src) 0))
                (list (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc) (enc-disp enc))) #f))))

         ;; mov [mem], reg
         ((and (eq? (car dst) 'mem) (eq? (car src) 'reg))
          (let* ((s-info (lookup-x86-reg (cadr src)))
                 (sz (mem-size dst))
                 (w (= (reg-size s-info) 8))
                 (enc (encode-modrm-sib-disp w s-info dst))
                 (opc (if (= (reg-size s-info) 1) 136 137))
                 (rip-sym (mem-rip-sym dst)))
            (if (and rip-sym (not (string=? rip-sym "rip_disp")))
                (list (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc) '(0 0 0 0)))
                      (list 'rip_disp32 (+ curr-off (length (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc))))) rip-sym (mem-disp dst) 0))
                (list (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc) (enc-disp enc))) #f))))

         ;; mov [mem], imm
         ((and (eq? (car dst) 'mem) (eq? (car src) 'imm))
          (let* ((val (cadr src))
                 (sz (mem-size dst))
                 (w (= sz 8)))
            (if (= sz 1)
                ;; byte ptr: C6 /0 imm8
                (let ((enc (encode-modrm-sib-disp #f (list 0 1 #f) dst)))
                  (list (asm-flatten (list (enc-rex enc) (list 198) (enc-modrm enc) (enc-sib enc) (enc-disp enc) (list (modulo (if (< val 0) (+ val 256) val) 256)))) #f))
                ;; qword/dword ptr: REX.W C7 /0 imm32
                (let ((enc (encode-modrm-sib-disp w (list 0 8 #f) dst)))
                  (list (asm-flatten (list (enc-rex enc) (list 199) (enc-modrm enc) (enc-sib enc) (enc-disp enc) (split-u32-le val))) #f)))))
         (else
          (list '(144) #f)))))

    ;; ADD, SUB, AND, OR, XOR, CMP
    ((add sub and or xor cmp)
     (let* ((dst (car opnds))
            (src (cadr opnds))
            (ext-op (case mnem ((add) 0) ((or) 1) ((and) 4) ((sub) 5) ((xor) 6) ((cmp) 7)))
            (base-op (case mnem ((add) 1) ((or) 9) ((and) 33) ((sub) 41) ((xor) 49) ((cmp) 57))))
       (cond
         ;; op r64, r64
         ((and (eq? (car dst) 'reg) (eq? (car src) 'reg))
          (let* ((d-info (lookup-x86-reg (cadr dst)))
                 (s-info (lookup-x86-reg (cadr src)))
                 (rex (make-rex #t (reg-ext? s-info) #f (reg-ext? d-info)))
                 (modrm (make-modrm 3 (reg-id s-info) (reg-id d-info))))
            (list (list rex base-op modrm) #f)))

         ;; op r64, imm
         ((and (eq? (car dst) 'reg) (eq? (car src) 'imm))
          (let* ((d-info (lookup-x86-reg (cadr dst)))
                 (val (cadr src))
                 (rex (make-rex #t #f #f (reg-ext? d-info))))
            (if (and (>= val -128) (<= val 127))
                ;; 83 /ext imm8
                (list (list rex 131 (make-modrm 3 ext-op (reg-id d-info))
                            (modulo (if (< val 0) (+ val 256) val) 256)) #f)
                ;; 81 /ext imm32
                (list (append (list rex 129 (make-modrm 3 ext-op (reg-id d-info)))
                              (split-u32-le val)) #f))))

         ;; op r64, [mem]
         ((and (eq? (car dst) 'reg) (eq? (car src) 'mem))
          (let* ((d-info (lookup-x86-reg (cadr dst)))
                 (sz (mem-size src))
                 (w (= (reg-size d-info) 8))
                 (enc (encode-modrm-sib-disp w d-info src))
                 (opc (+ base-op 2))
                 (rip-sym (mem-rip-sym src)))
            (if (and rip-sym (not (string=? rip-sym "rip_disp")))
                (list (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc) '(0 0 0 0)))
                      (list 'rip_disp32 (+ curr-off (length (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc))))) rip-sym (mem-disp src) 0))
                (list (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc) (enc-disp enc))) #f))))

         ;; cmp [mem], imm
         ((and (eq? mnem 'cmp) (eq? (car dst) 'mem) (eq? (car src) 'imm))
          (let* ((val (cadr src))
                 (sz (mem-size dst))
                 (w (= sz 8))
                 (enc (encode-modrm-sib-disp w (list ext-op 8 #f) dst))
                 (opc (if (= sz 1) 128 131))
                 (rip-sym (mem-rip-sym dst)))
            (if (and rip-sym (not (string=? rip-sym "rip_disp")))
                (list (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc) '(0 0 0 0) (list (modulo (if (< val 0) (+ val 256) val) 256))))
                      (list 'rip_disp32 (+ curr-off (length (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc))))) rip-sym (mem-disp dst) 1))
                (list (asm-flatten (list (enc-rex enc) (list opc) (enc-modrm enc) (enc-sib enc) (enc-disp enc) (list (modulo (if (< val 0) (+ val 256) val) 256)))) #f))))

         (else
          (list '(144) #f)))))

    ;; BT: bt r64, r64 -> REX.W 0F A3 /r
    ((bt)
     (let* ((dst (car opnds))
            (src (cadr opnds))
            (d-info (lookup-x86-reg (cadr dst)))
            (s-info (lookup-x86-reg (cadr src)))
            (rex (make-rex #t (reg-ext? s-info) #f (reg-ext? d-info)))
            (modrm (make-modrm 3 (modulo (reg-id s-info) 8) (modulo (reg-id d-info) 8))))
       (list (list rex 15 163 modrm) #f)))

    ;; TEST: test r64, r64 -> REX.W 85 /r, test r64, imm -> REX.W F7 /0 imm32
    ((test)
     (let* ((dst (car opnds))
            (src (cadr opnds))
            (d-info (lookup-x86-reg (cadr dst))))
       (case (car src)
         ((reg)
          (let* ((s-info (lookup-x86-reg (cadr src)))
                 (sz (reg-size d-info))
                 (w (= sz 8))
                 (rex (make-rex w (reg-ext? s-info) #f (reg-ext? d-info)))
                 (opc (if (= sz 1) 132 133))
                 (modrm (make-modrm 3 (reg-id s-info) (reg-id d-info))))
            (list (append (if (or w (reg-ext? s-info) (reg-ext? d-info) (= sz 1)) (list rex) '())
                          (list opc modrm)) #f)))
         ((imm)
          (let* ((val (cadr src))
                 (sz (reg-size d-info))
                 (w (= sz 8))
                 (rex (make-rex w #f #f (reg-ext? d-info))))
            (if (= sz 1)
                (list (append (if (reg-ext? d-info) (list rex) '())
                              (list 246 (make-modrm 3 0 (reg-id d-info))
                                    (modulo (if (< val 0) (+ val 256) val) 256))) #f)
                (list (append (list rex 247 (make-modrm 3 0 (reg-id d-info)))
                              (split-u32-le val)) #f))))
         (else
          (list '(144) #f)))))

    ;; IMUL: imul r64, r64/mem -> REX.W 0F AF /r, imul r64, imm -> REX.W 6B/69, imul r64, r64, imm -> REX.W 6B/69
    ((imul)
     (cond
       ;; 3-operand: imul dst, src, imm
       ((pair? (cddr opnds))
        (let* ((dst (car opnds))
               (src (cadr opnds))
               (imm-op (caddr opnds))
               (d-info (lookup-x86-reg (cadr dst)))
               (s-info (lookup-x86-reg (cadr src)))
               (val (cadr imm-op))
               (rex (make-rex #t (reg-ext? d-info) #f (reg-ext? s-info)))
               (modrm (make-modrm 3 (reg-id d-info) (reg-id s-info))))
          (if (and (>= val -128) (<= val 127))
              (list (list rex 107 modrm (modulo (if (< val 0) (+ val 256) val) 256)) #f)
              (list (append (list rex 105 modrm) (split-u32-le val)) #f))))

       ;; 2-operand
       (else
        (let* ((dst (car opnds))
               (src (cadr opnds))
               (d-info (lookup-x86-reg (cadr dst))))
          (case (car src)
            ((reg)
             (let* ((s-info (lookup-x86-reg (cadr src)))
                    (rex (make-rex #t (reg-ext? d-info) #f (reg-ext? s-info)))
                    (modrm (make-modrm 3 (reg-id d-info) (reg-id s-info))))
               (list (list rex 15 175 modrm) #f)))
            ((mem)
             (let ((enc (encode-modrm-sib-disp #t d-info src)))
               (list (asm-flatten (list (enc-rex enc) (list 15 175) (enc-modrm enc) (enc-sib enc) (enc-disp enc))) #f)))
            ((imm)
             (let* ((val (cadr src))
                    (rex (make-rex #t (reg-ext? d-info) #f (reg-ext? d-info)))
                    (modrm (make-modrm 3 (reg-id d-info) (reg-id d-info))))
               (if (and (>= val -128) (<= val 127))
                   (list (list rex 107 modrm (modulo (if (< val 0) (+ val 256) val) 256)) #f)
                   (list (append (list rex 105 modrm) (split-u32-le val)) #f))))
            (else
             (list '(144) #f)))))))

    ;; IDIV, DIV: REX.W F7 /7 (idiv), F7 /6 (div)
    ((idiv div)
     (let* ((ext (if (eq? mnem 'idiv) 7 6))
            (op (car opnds))
            (r-info (lookup-x86-reg (cadr op)))
            (rex (make-rex #t #f #f (reg-ext? r-info)))
            (modrm (make-modrm 3 ext (reg-id r-info))))
       (list (list rex 247 modrm) #f)))

    ;; SHL, SHR, SAR: REX.W C1 /ext imm8, D1 /ext (by 1), D3 /ext (by cl)
    ((shl shr sar)
     (let* ((ext (case mnem ((shl) 4) ((shr) 5) ((sar) 7)))
            (dst (car opnds))
            (d-info (lookup-x86-reg (if (pair? dst) (cadr dst) dst)))
            (rex (make-rex #t #f #f (reg-ext? d-info)))
            (src (if (pair? (cdr opnds)) (cadr opnds) '(imm 1))))
       (cond
         ((and (pair? src) (eq? (car src) 'reg) (let ((rn (cadr src))) (or (equal? rn 'cl) (equal? rn "cl") (equal? rn '%cl) (equal? rn "%cl"))))
          ;; by CL: REX.W D3 /ext
          (list (list rex 211 (make-modrm 3 ext (reg-id d-info))) #f))
         ((and (pair? src) (eq? (car src) 'imm))
          (let ((imm (cadr src)))
            (if (= imm 1)
                (list (list rex 209 (make-modrm 3 ext (reg-id d-info))) #f)
                (list (list rex 193 (make-modrm 3 ext (reg-id d-info)) (modulo (if (< imm 0) (+ imm 256) imm) 256)) #f))))
         (else
          (list (list rex 209 (make-modrm 3 ext (reg-id d-info))) #f)))))

    ;; NEG, NOT: REX.W F7 /3 (neg), F7 /2 (not)
    ((neg not)
     (let* ((ext (if (eq? mnem 'neg) 3 2))
            (op (car opnds))
            (r-info (lookup-x86-reg (cadr op)))
            (rex (make-rex #t #f #f (reg-ext? r-info)))
            (modrm (make-modrm 3 ext (reg-id r-info))))
       (list (list rex 247 modrm) #f)))

    ;; INC, DEC: REX.W FF /0 (inc), FF /1 (dec)
    ((inc dec)
     (let* ((ext (if (eq? mnem 'inc) 0 1))
            (op (car opnds))
            (r-info (lookup-x86-reg (cadr op)))
            (rex (make-rex #t #f #f (reg-ext? r-info)))
            (modrm (make-modrm 3 ext (reg-id r-info))))
       (list (list rex 255 modrm) #f)))

    ;; MFENCE: 0F AE F0
    ((mfence)
     (list '(15 174 240) #f))

    ;; CMPXCHG r/m64, r64: REX.W 0F B1 /r
    ((cmpxchg)
     (let* ((dst (car opnds))
            (src (cadr opnds))
            (s-info (lookup-x86-reg (cadr src))))
       (case (car dst)
         ((mem)
          (let ((enc (encode-modrm-sib-disp #t s-info dst)))
            (list (asm-flatten (list (enc-rex enc) '(15 177) (enc-modrm enc) (enc-sib enc) (enc-disp enc))) #f)))
         ((reg)
          (let* ((d-info (lookup-x86-reg (cadr dst)))
                 (rex (make-rex #t (reg-ext? s-info) #f (reg-ext? d-info)))
                 (modrm (make-modrm 3 (reg-id s-info) (reg-id d-info))))
            (list (list rex 15 177 modrm) #f)))
         (else
          (list '(144) #f)))))

    (else
     (list '(144) #f)))))

;; -----------------------------------------------------------------------

;; -----------------------------------------------------------------------
(define (asm-copy-op-bytes! bv base-off bytes)
  (let loop ((bs bytes) (i 0))
    (if (pair? bs)
        (begin
          (bytevector-u8-set! bv (+ base-off i) (car bs))
          (loop (cdr bs) (+ i 1)))
        i)))

;; Main interface:
;; (assemble-x86-lines lines)
;; Returns: (list text-bv rodata-bv data-bv bss-size entry-offset [file-table line-table sym-table])
(define (assemble-x86-lines lines)
  (let ((file-table-box (cons '() '()))
        (line-table-box (cons '() '())))
    (let pass1-loop ((lines-rest lines)
                   (sym-table '())
                   (relocs '())
                   (text-ops '())
                   (rodata-ops '())
                   (data-ops '())
                   (cur-sec 'text)
                   (text-len 0)
                   (rodata-len 0)
                   (data-len 0)
                   (bss-len 0)
                   (entry-off -1))
    (if (pair? lines-rest)
        (let* ((line (car lines-rest))
               (clean (asm-trim-string (asm-strip-comment line))))
          (if (= (string-length clean) 0)
              (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                          cur-sec text-len rodata-len data-len bss-len entry-off)
              (let ((tokens (asm-tokenize-line clean)))
                (if (null? tokens)
                    (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                cur-sec text-len rodata-len data-len bss-len entry-off)
                    (let ((first (car tokens)))
                      (cond
                        ;; Label definition: "NAME:"
                        ((or (and (pair? (cdr tokens)) (string=? (cadr tokens) ":"))
                             (char=? (string-ref first (- (string-length first) 1)) #\:))
                         (let* ((lbl-name (if (char=? (string-ref first (- (string-length first) 1)) #\:)
                                              (substring first 0 (- (string-length first) 1))
                                              first))
                                (off (case cur-sec
                                       ((text) text-len)
                                       ((rodata) rodata-len)
                                       ((data) data-len)
                                       ((bss) bss-len)
                                       (else text-len)))
                                (new-entry-off (cond
                                                 ((string=? lbl-name "_start") off)
                                                 ((and (= entry-off -1) (string=? lbl-name "scheme_entry")) off)
                                                 (else entry-off))))
                           (pass1-loop (cdr lines-rest)
                                       (cons (cons lbl-name (list cur-sec off)) sym-table)
                                       relocs text-ops rodata-ops data-ops
                                       cur-sec text-len rodata-len data-len bss-len new-entry-off)))

                        ;; Section switching directives
                        ((string=? first ".text")
                         (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                     'text text-len rodata-len data-len bss-len entry-off))
                        ((or (string=? first ".data") (string=? first ".section .data"))
                         (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                     'data text-len rodata-len data-len bss-len entry-off))
                        ((or (string=? first ".rodata") (string=? first ".section .rodata"))
                         (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                     'rodata text-len rodata-len data-len bss-len entry-off))
                        ((string=? first ".bss")
                         (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                     'bss text-len rodata-len data-len bss-len entry-off))
                        ((string-starts-with? clean ".section ulisp_globals_sec")
                         (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                     'rodata text-len rodata-len data-len bss-len entry-off))
                        ((string-starts-with? clean ".section .init_array")
                         (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                     'data text-len rodata-len data-len bss-len entry-off))
                        ((or (string-starts-with? clean ".section .note")
                             (string=? first ".globl") (string=? first ".weak") (string=? first ".type")
                             (string=? first ".intel_syntax"))
                         (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                     cur-sec text-len rodata-len data-len bss-len entry-off))

                        ;; DWARF directives (Issue #619)
                        ((string=? first ".file")
                         (let* ((fid (if (pair? (cdr tokens)) (safe-string->number (cadr tokens)) 1))
                                (fpath (if (and (pair? (cdr tokens)) (pair? (cddr tokens))) (caddr tokens) "source.scm")))
                           (set-car! file-table-box (cons (cons (if fid fid 1) fpath) (car file-table-box)))
                           (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                       cur-sec text-len rodata-len data-len bss-len entry-off)))
                        ((string=? first ".loc")
                         (let* ((fid (if (pair? (cdr tokens)) (safe-string->number (cadr tokens)) 1))
                                (line (if (and (pair? (cdr tokens)) (pair? (cddr tokens))) (safe-string->number (caddr tokens)) 1))
                                (col (if (and (pair? (cdr tokens)) (pair? (cddr tokens)) (pair? (cdddr tokens)))
                                         (safe-string->number (cadddr tokens)) 0)))
                           (set-car! line-table-box (cons (list (if fid fid 1) (if line line 1) (if col col 0) text-len) (car line-table-box)))
                           (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                       cur-sec text-len rodata-len data-len bss-len entry-off)))

                        ;; Alignment
                        ((or (string=? first ".align") (string=? first ".p2align"))
                         (let* ((val (if (pair? (cdr tokens)) (safe-string->number (cadr tokens)) 8))
                                (align (if (string=? first ".p2align") (expt 2 val) val)))
                           (case cur-sec
                             ((text)
                              (let* ((rem (modulo text-len align))
                                     (pad (if (= rem 0) 0 (- align rem))))
                                (pass1-loop (cdr lines-rest) sym-table relocs
                                            (cons (cons 'pad-nop pad) text-ops)
                                            rodata-ops data-ops cur-sec
                                            (+ text-len pad) rodata-len data-len bss-len entry-off)))
                             ((rodata)
                              (let* ((rem (modulo rodata-len align))
                                     (pad (if (= rem 0) 0 (- align rem))))
                                (pass1-loop (cdr lines-rest) sym-table relocs text-ops
                                            (cons (cons 'pad-zero pad) rodata-ops)
                                            data-ops cur-sec text-len
                                            (+ rodata-len pad) data-len bss-len entry-off)))
                             ((data)
                              (let* ((rem (modulo data-len align))
                                     (pad (if (= rem 0) 0 (- align rem))))
                                (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops
                                            (cons (cons 'pad-zero pad) data-ops)
                                            cur-sec text-len rodata-len
                                            (+ data-len pad) bss-len entry-off)))
                             ((bss)
                              (let* ((rem (modulo bss-len align))
                                     (pad (if (= rem 0) 0 (- align rem))))
                                (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                            cur-sec text-len rodata-len data-len
                                            (+ bss-len pad) entry-off)))
                             (else
                              (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                          cur-sec text-len rodata-len data-len bss-len entry-off)))))

                        ;; Data directives: .byte
                        ((string=? first ".byte")
                         (let byte-loop ((ts (cdr tokens))
                                         (cur-text-ops text-ops) (cur-rodata-ops rodata-ops) (cur-data-ops data-ops)
                                         (cur-tlen text-len) (cur-rlen rodata-len) (cur-dlen data-len))
                           (if (pair? ts)
                               (if (string=? (car ts) ",")
                                   (byte-loop (cdr ts) cur-text-ops cur-rodata-ops cur-data-ops cur-tlen cur-rlen cur-dlen)
                                   (let* ((b-num (safe-string->number (car ts)))
                                          (b (if b-num b-num 0)))
                                     (case cur-sec
                                       ((text)
                                        (byte-loop (cdr ts) (cons (list b) cur-text-ops) cur-rodata-ops cur-data-ops
                                                   (+ cur-tlen 1) cur-rlen cur-dlen))
                                       ((data)
                                        (byte-loop (cdr ts) cur-text-ops cur-rodata-ops (cons (list b) cur-data-ops)
                                                   cur-tlen cur-rlen (+ cur-dlen 1)))
                                       (else
                                        (byte-loop (cdr ts) cur-text-ops (cons (list b) cur-rodata-ops) cur-data-ops
                                                   cur-tlen (+ cur-rlen 1) cur-dlen)))))
                               (pass1-loop (cdr lines-rest) sym-table relocs
                                           cur-text-ops cur-rodata-ops cur-data-ops cur-sec
                                           cur-tlen cur-rlen cur-dlen bss-len entry-off))))

                        ;; Data directives: .quad
                        ((string=? first ".quad")
                         (let* ((args (cdr tokens))
                                (arg-str (let loop ((ts args) (acc ""))
                                           (if (null? ts) (asm-trim-string acc)
                                               (loop (cdr ts) (string-append acc (car ts) " ")))))
                                (num (safe-string->number arg-str)))
                           (if num
                               (let ((bs (split-u64-le num)))
                                 (case cur-sec
                                   ((text)
                                    (pass1-loop (cdr lines-rest) sym-table relocs (cons bs text-ops) rodata-ops data-ops
                                                cur-sec (+ text-len 8) rodata-len data-len bss-len entry-off))
                                   ((data)
                                    (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops (cons bs data-ops)
                                                cur-sec text-len rodata-len (+ data-len 8) bss-len entry-off))
                                   (else
                                    (pass1-loop (cdr lines-rest) sym-table relocs text-ops (cons bs rodata-ops) data-ops
                                                cur-sec text-len (+ rodata-len 8) data-len bss-len entry-off))))
                               (let* ((plus-pos (let loop ((i 0))
                                                  (if (or (>= i (string-length arg-str)) (char=? (string-ref arg-str i) #\+))
                                                      i
                                                      (loop (+ i 1)))))
                                      (sym-name (asm-trim-string (if (< plus-pos (string-length arg-str))
                                                                     (substring arg-str 0 plus-pos)
                                                                     arg-str)))
                                      (addend (if (< plus-pos (string-length arg-str))
                                                  (let ((n (safe-string->number (asm-trim-string (substring arg-str (+ plus-pos 1) (string-length arg-str))))))
                                                    (if n n 0))
                                                  0)))
                                 (case cur-sec
                                   ((data)
                                    (pass1-loop (cdr lines-rest) sym-table
                                                (cons (list 'abs64 'data data-len sym-name addend) relocs)
                                                text-ops rodata-ops (cons '(0 0 0 0 0 0 0 0) data-ops)
                                                cur-sec text-len rodata-len (+ data-len 8) bss-len entry-off))
                                   (else
                                    (pass1-loop (cdr lines-rest) sym-table
                                                (cons (list 'abs64 'rodata rodata-len sym-name addend) relocs)
                                                text-ops (cons '(0 0 0 0 0 0 0 0) rodata-ops) data-ops
                                                cur-sec text-len (+ rodata-len 8) data-len bss-len entry-off)))))))

                        ;; Data directives: .asciz / .ascii
                        ((or (string=? first ".asciz") (string=? first ".ascii"))
                         (let* ((null-term? (string=? first ".asciz"))
                                (str-tok (if (pair? (cdr tokens)) (cadr tokens) ""))
                                (bytes (let loop ((i 0) (acc '()))
                                         (if (>= i (string-length str-tok))
                                             (reverse (if null-term? (cons 0 acc) acc))
                                             (loop (+ i 1) (cons (char->integer (string-ref str-tok i)) acc)))))
                                (blen (length bytes)))
                           (case cur-sec
                             ((text)
                              (pass1-loop (cdr lines-rest) sym-table relocs (cons bytes text-ops) rodata-ops data-ops
                                          cur-sec (+ text-len blen) rodata-len data-len bss-len entry-off))
                             ((data)
                              (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops (cons bytes data-ops)
                                          cur-sec text-len rodata-len (+ data-len blen) bss-len entry-off))
                             (else
                              (pass1-loop (cdr lines-rest) sym-table relocs text-ops (cons bytes rodata-ops) data-ops
                                          cur-sec text-len (+ rodata-len blen) data-len bss-len entry-off)))))

                        ;; Data directives: .space / .zero
                        ((or (string=? first ".space") (string=? first ".zero"))
                         (let ((cnt (if (pair? (cdr tokens)) (safe-string->number (cadr tokens)) 0)))
                           (if (and cnt (> cnt 0))
                               (case cur-sec
                                 ((bss)
                                  (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                              cur-sec text-len rodata-len data-len (+ bss-len cnt) entry-off))
                                 ((data)
                                  (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops (cons (cons 'pad-zero cnt) data-ops)
                                              cur-sec text-len rodata-len (+ data-len cnt) bss-len entry-off))
                                 (else
                                  (pass1-loop (cdr lines-rest) sym-table relocs text-ops (cons (cons 'pad-zero cnt) rodata-ops) data-ops
                                              cur-sec text-len (+ rodata-len cnt) data-len bss-len entry-off)))
                               (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                           cur-sec text-len rodata-len data-len bss-len entry-off))))

                        ;; Instruction
                        (else
                         (let* ((has-lock? (and (string=? (safe-string-downcase first) "lock") (pair? (cdr tokens))))
                                (mnem (if has-lock? (cadr tokens) first))
                                (raw-opnd-tokens (if has-lock? (cddr tokens) (cdr tokens)))
                                (opnd-strs (let loop ((ts raw-opnd-tokens) (cur '()) (acc '()))
                                             (cond
                                               ((null? ts)
                                                (if (null? cur) (reverse acc)
                                                    (reverse (cons (let l ((cs (reverse cur)) (s ""))
                                                                     (if (null? cs) s (l (cdr cs) (string-append s (car cs) " ")))) acc))))
                                               ((string=? (car ts) ",")
                                                (loop (cdr ts) '()
                                                      (cons (let l ((cs (reverse cur)) (s ""))
                                                              (if (null? cs) s (l (cdr cs) (string-append s (car cs) " ")))) acc)))
                                               (else
                                                (loop (cdr ts) (cons (car ts) cur) acc)))))
                                (opnds (map parse-operand-str opnd-strs))
                                (res (assemble-inst mnem opnds (if has-lock? (+ text-len 1) text-len))))
                           (if (pair? res)
                               (let* ((bytes (if has-lock? (cons 240 (car res)) (car res)))
                                      (reloc (cadr res))
                                      (new-relocs (if reloc
                                                      (cons (cons (car reloc) (cons 'text (cdr reloc))) relocs)
                                                      relocs))
                                      (blen (length bytes)))
                                 (pass1-loop (cdr lines-rest) sym-table new-relocs (cons bytes text-ops) rodata-ops data-ops
                                             cur-sec (+ text-len blen) rodata-len data-len bss-len entry-off))
                               (pass1-loop (cdr lines-rest) sym-table relocs text-ops rodata-ops data-ops
                                           cur-sec text-len rodata-len data-len bss-len entry-off))))))))))
        ;; ---------------------------------------------------------------
        ;; Pass 2: Allocate bytevectors, copy bytes, patch relocations
        ;; ---------------------------------------------------------------
        (let* ((text-bv (make-bytevector text-len))
               (rodata-bv (make-bytevector rodata-len))
               (data-bv (make-bytevector data-len))

               ;; Virtual Addresses
               (vaddr-text-base (+ 4194304 176))
               (vaddr-rodata-base (+ vaddr-text-base text-len))
               (vaddr-data-base 6291456)
               (vaddr-bss-base (+ vaddr-data-base data-len)))

          ;; Copy text bytes
          (let loop ((ops (reverse text-ops)) (off 0))
            (if (pair? ops)
                (let ((op (car ops)))
                  (cond
                    ((and (pair? op) (eq? (car op) 'pad-nop))
                     (let ((pad (cdr op)))
                       (let fill ((k 0))
                         (if (< k pad)
                             (begin
                               (bytevector-u8-set! text-bv (+ off k) 144)
                               (fill (+ k 1)))
                             (loop (cdr ops) (+ off pad))))))
                    (else
                     (let ((n (asm-copy-op-bytes! text-bv off op)))
                       (loop (cdr ops) (+ off n))))))
                #t))

          ;; Copy rodata bytes
          (let loop ((ops (reverse rodata-ops)) (off 0))
            (if (pair? ops)
                (let ((op (car ops)))
                  (cond
                    ((and (pair? op) (eq? (car op) 'pad-zero))
                     (loop (cdr ops) (+ off (cdr op))))
                    (else
                     (let ((n (asm-copy-op-bytes! rodata-bv off op)))
                       (loop (cdr ops) (+ off n))))))
                #t))

          ;; Copy data bytes
          (let loop ((ops (reverse data-ops)) (off 0))
            (if (pair? ops)
                (let ((op (car ops)))
                  (cond
                    ((and (pair? op) (eq? (car op) 'pad-zero))
                     (loop (cdr ops) (+ off (cdr op))))
                    (else
                     (let ((n (asm-copy-op-bytes! data-bv off op)))
                       (loop (cdr ops) (+ off n))))))
                #t))

          ;; Apply Relocations
          (let reloc-loop ((rels relocs))
            (if (pair? rels)
                (let* ((rel (car rels))
                       (type (car rel))
                       (sec (cadr rel))
                       (patch-off (caddr rel))
                       (sym (cadddr rel))
                       (addend (car (cddddr rel)))
                       (adj (if (pair? (cdr (cddddr rel))) (cadr (cddddr rel)) 0))
                       (sym-vaddr (let ((entry (assoc sym sym-table)))
                                    (if entry
                                        (let ((s (cadr entry))
                                              (o (caddr entry)))
                                          (case s
                                            ((text) (+ vaddr-text-base o))
                                            ((rodata) (+ vaddr-rodata-base o))
                                            ((data) (+ vaddr-data-base o))
                                            ((bss) (+ vaddr-bss-base o))
                                            (else (+ vaddr-text-base o))))
                                        0)))
                       (target-vaddr (+ sym-vaddr addend)))
                  (case type
                    ((rel32)
                     (let* ((patch-vaddr (+ vaddr-text-base patch-off))
                            (next-ip (+ patch-vaddr 4))
                            (diff (- target-vaddr next-ip)))
                       (elf64-set-u32-le! text-bv patch-off diff)))

                    ((rip_disp32)
                     (let* ((patch-vaddr (+ vaddr-text-base patch-off))
                            (next-ip (+ (+ patch-vaddr 4) adj))
                            (diff (if (= sym-vaddr 0)
                                      (- 0 next-ip)
                                      (- target-vaddr next-ip))))
                       (elf64-set-u32-le! text-bv patch-off diff)))

                    ((abs64)
                     (let ((target-bv (if (eq? sec 'data) data-bv rodata-bv)))
                       (elf64-set-u64-le! target-bv patch-off target-vaddr))))
                  (reloc-loop (cdr rels)))
                #t))

          ;; Return tuple: (text-bv rodata-bv data-bv bss-size entry-offset file-table line-table sym-table)
          (list text-bv rodata-bv data-bv bss-len (if (= entry-off -1) 0 entry-off)
                (reverse (car file-table-box))
                (reverse (car line-table-box))
                sym-table))))))
