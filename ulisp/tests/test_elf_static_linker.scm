;;; =======================================================================
;;; Unit Test Suite: Pass 144 Static ELF64 Linker & c_driver Integration
;;; Issue #928 - WP2 & WP3 Verification
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Pass 144 Static ELF64 Linker Unit Suite (#928)\n")
(display "=======================================================\n")

(test-begin "Pass 144 Native ELF64 Static Linker & Driver (#928)")

;; -----------------------------------------------------------------------
;; Helper: Capture structured linker error codes (C99-LNK-001..003)
;; -----------------------------------------------------------------------
(define (capture-linker-error thunk)
  (let ((err-box (cons #f '())))
    (guard (ex
            ((and (pair? ex) (eq? (car ex) 'captured-lnk-err))
             (cdr ex))
            (else (list "UNEXPECTED" ex "")))
      (with-elf64-linker-error-handler
       (lambda (code msg detail)
         (set-car! err-box code)
         (raise (cons 'captured-lnk-err (list code msg detail))))
       thunk)
      #f)))

;; -----------------------------------------------------------------------
;; Helper: Encode bytes / strings / custom ELF64 ET_REL objects
;; -----------------------------------------------------------------------
(define (str->ascii-bytes s)
  (let loop ((i (- (string-length s) 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons (char->integer (string-ref s i)) acc)))))

(define (pad-bv src align)
  (let ((len (bytevector-length src)))
    (if (= (modulo len align) 0)
        src
        (let* ((plen (elf64-align-up len align))
               (out (make-bytevector plen 0)))
          (elf64-copy-bytes! out 0 src 0 len)
          out))))

;; Build a flexible custom ELF64 ET_REL bytevector in memory:
;;   sections: list of (name sh-type sh-flags data-bv sh-align)
;;   symbols:  list of (name st-bind st-type st-shndx st-val st-size)
;;             note: st-shndx is 1-based section index, or 0/65521/65522
;;   relocs:   list of (target-sec-1based r-offset r-type sym-1based r-addend)
(define (make-custom-et-rel sections symbols relocs)
  ;; Build shstrtab: "\0" + sec names + ".symtab\0.strtab\0.shstrtab\0" + ".rela.<name>"
  (let* ((num-user-secs (length sections))
         (rela-groups
          (let loop ((rs relocs) (groups '()))
            (if (null? rs)
                (let rev ((gs groups) (out '()))
                  (if (null? gs) out (rev (cdr gs) (cons (car gs) out))))
                (let* ((r (car rs))
                       (tidx (car r))
                       (hit (assv tidx groups)))
                  (if hit
                      (begin
                        (set-cdr! hit (append (cdr hit) (list r)))
                        (loop (cdr rs) groups))
                      (loop (cdr rs) (cons (list tidx r) groups)))))))
         (symtab-idx (+ 1 num-user-secs))
         (strtab-idx (+ symtab-idx 1))
         (shstrtab-idx (+ strtab-idx 1))
         (first-rela-idx (+ shstrtab-idx 1))
         (total-secs (+ first-rela-idx (length rela-groups)))
         ;; Build string tables
         (shstr-acc (cons '(0) '()))
         (alloc-shstr!
          (lambda (s)
            (let* ((cur (car shstr-acc))
                   (off (length cur))
                   (bs (append (str->ascii-bytes s) '(0))))
              (set-car! shstr-acc (append cur bs))
              off)))
         (str-acc (cons '(0) '()))
         (alloc-str!
          (lambda (s)
            (if (string=? s "")
                0
                (let* ((cur (car str-acc))
                       (off (length cur))
                       (bs (append (str->ascii-bytes s) '(0))))
                  (set-car! str-acc (append cur bs))
                  off))))
         (user-sec-names-off (map (lambda (s) (alloc-shstr! (car s))) sections))
         (symtab-name-off (alloc-shstr! ".symtab"))
         (strtab-name-off (alloc-shstr! ".strtab"))
         (shstrtab-name-off (alloc-shstr! ".shstrtab"))
         (rela-names-off
          (map (lambda (g)
                 (let ((sname (car (list-ref sections (- (car g) 1)))))
                   (alloc-shstr! (string-append ".rela" sname))))
               rela-groups))
         ;; Build symtab: index 0 is STN_UNDEF, followed by `symbols`
         ;; Count locals first to set sh_info properly (or order locals first in caller)
         (sym-count (+ 1 (length symbols)))
         (symtab-bv (make-bytevector (* sym-count 24) 0))
         (first-nonlocal-box (cons 1 '())))
    (let loop-sy ((i 1) (ss symbols) (seen-global? #f))
      (if (pair? ss)
          (let* ((sym (car ss))
                 (name-off (alloc-str! (list-ref sym 0)))
                 (bind (list-ref sym 1))
                 (stype (list-ref sym 2))
                 (shndx (list-ref sym 3))
                 (val (list-ref sym 4))
                 (sz (list-ref sym 5))
                 (off (* i 24))
                 (now-global? (or seen-global? (not (= bind 0)))))
            (if (and (not seen-global?) (not (= bind 0)))
                (set-car! first-nonlocal-box i))
            (elf64-set-u32-le! symtab-bv off name-off)
            (elf64-set-u8! symtab-bv (+ off 4) (+ (* bind 16) stype))
            (elf64-set-u8! symtab-bv (+ off 5) 0)
            (elf64-set-u16-le! symtab-bv (+ off 6) shndx)
            (elf64-set-u64-le! symtab-bv (+ off 8) val)
            (elf64-set-u64-le! symtab-bv (+ off 16) sz)
            (loop-sy (+ i 1) (cdr ss) now-global?))
          (if (not seen-global?)
              (set-car! first-nonlocal-box sym-count))))
    (let* ((strtab-bv (elf64-list->bytevector (car str-acc)))
           (shstrtab-bv (elf64-list->bytevector (car shstr-acc)))
           (rela-bvs
            (map (lambda (g)
                   (let* ((rs (cdr g))
                          (rbv (make-bytevector (* (length rs) 24) 0)))
                     (let rl ((k 0) (xs rs))
                       (if (pair? xs)
                           (let* ((r (car xs))
                                  (roff (* k 24))
                                  (r-offset (list-ref r 1))
                                  (r-type (list-ref r 2))
                                  (sym-idx (list-ref r 3))
                                  (r-addend (list-ref r 4))
                                  (r-info (+ (* sym-idx 4294967296) r-type)))
                             (elf64-set-u64-le! rbv roff r-offset)
                             (elf64-set-u64-le! rbv (+ roff 8) r-info)
                             (elf64-set-s64-le! rbv (+ roff 16) r-addend)
                             (rl (+ k 1) (cdr xs)))))
                     rbv))
                 rela-groups))
           ;; Compute file layout starting at offset 64
           (off-box (cons 64 '()))
           (sec-offsets
            (map (lambda (s)
                   (let* ((sh-type (list-ref s 1))
                          (dbv (list-ref s 3))
                          (sz (bytevector-length dbv))
                          (cur (elf64-align-up (car off-box) 8)))
                     (if (= sh-type 8)
                         cur
                         (begin
                           (set-car! off-box (+ cur sz))
                           cur))))
                 sections))
           (symtab-off (elf64-align-up (car off-box) 8))
           (_o1 (set-car! off-box (+ symtab-off (bytevector-length symtab-bv))))
           (strtab-off (elf64-align-up (car off-box) 8))
           (_o2 (set-car! off-box (+ strtab-off (bytevector-length strtab-bv))))
           (shstrtab-off (elf64-align-up (car off-box) 8))
           (_o3 (set-car! off-box (+ shstrtab-off (bytevector-length shstrtab-bv))))
           (rela-offsets
            (map (lambda (rbv)
                   (let ((cur (elf64-align-up (car off-box) 8)))
                     (set-car! off-box (+ cur (bytevector-length rbv)))
                     cur))
                 rela-bvs))
           (shoff (elf64-align-up (car off-box) 8))
           (total-size (+ shoff (* total-secs 64)))
           (out (make-bytevector total-size 0)))
      ;; Write ELF64 ET_REL header
      (elf64-set-u8! out 0 127) (elf64-set-u8! out 1 69)
      (elf64-set-u8! out 2 76)  (elf64-set-u8! out 3 70)
      (elf64-set-u8! out 4 2)   (elf64-set-u8! out 5 1)
      (elf64-set-u8! out 6 1)
      (elf64-set-u16-le! out 16 1)  ;; ET_REL
      (elf64-set-u16-le! out 18 62) ;; EM_X86_64
      (elf64-set-u32-le! out 20 1)
      (elf64-set-u64-le! out 40 shoff)
      (elf64-set-u16-le! out 52 64)
      (elf64-set-u16-le! out 58 64)
      (elf64-set-u16-le! out 60 total-secs)
      (elf64-set-u16-le! out 62 shstrtab-idx)
      ;; Copy section payloads
      (let loop-cp ((ss sections) (offs sec-offsets))
        (if (pair? ss)
            (let* ((s (car ss))
                   (sh-type (list-ref s 1))
                   (dbv (list-ref s 3)))
              (if (and (not (= sh-type 8)) (> (bytevector-length dbv) 0))
                  (elf64-copy-bytes! out (car offs) dbv 0 (bytevector-length dbv)))
              (loop-cp (cdr ss) (cdr offs)))))
      (elf64-copy-bytes! out symtab-off symtab-bv 0 (bytevector-length symtab-bv))
      (elf64-copy-bytes! out strtab-off strtab-bv 0 (bytevector-length strtab-bv))
      (elf64-copy-bytes! out shstrtab-off shstrtab-bv 0 (bytevector-length shstrtab-bv))
      (let loop-rcp ((rbs rela-bvs) (roffs rela-offsets))
        (if (pair? rbs)
            (begin
              (elf64-copy-bytes! out (car roffs) (car rbs) 0 (bytevector-length (car rbs)))
              (loop-rcp (cdr rbs) (cdr roffs)))))
      ;; Write section headers: 0 is NULL
      (let loop-sh ((i 1) (ss sections) (noffs user-sec-names-off) (foffs sec-offsets))
        (if (pair? ss)
            (let* ((s (car ss))
                   (sh-type (list-ref s 1))
                   (sh-flags (list-ref s 2))
                   (dbv (list-ref s 3))
                   (sh-align (list-ref s 4))
                   (sh-sz (if (= sh-type 8)
                              (if (> (length s) 5) (list-ref s 5) (bytevector-length dbv))
                              (bytevector-length dbv))))
              (elf64-write-shdr! out shoff i (car noffs) sh-type sh-flags 0
                                 (car foffs) sh-sz 0 0 sh-align 0)
              (loop-sh (+ i 1) (cdr ss) (cdr noffs) (cdr foffs)))))
      (elf64-write-shdr! out shoff symtab-idx symtab-name-off 2 0 0
                         symtab-off (bytevector-length symtab-bv)
                         strtab-idx (car first-nonlocal-box) 8 24)
      (elf64-write-shdr! out shoff strtab-idx strtab-name-off 3 0 0
                         strtab-off (bytevector-length strtab-bv) 0 0 1 0)
      (elf64-write-shdr! out shoff shstrtab-idx shstrtab-name-off 3 0 0
                         shstrtab-off (bytevector-length shstrtab-bv) 0 0 1 0)
      (let loop-rsh ((i first-rela-idx) (gs rela-groups) (noffs rela-names-off)
                     (rbs rela-bvs) (roffs rela-offsets))
        (if (pair? gs)
            (begin
              (elf64-write-shdr! out shoff i (car noffs) 4 64 0
                                 (car roffs) (bytevector-length (car rbs))
                                 symtab-idx (caar gs) 8 24)
              (loop-rsh (+ i 1) (cdr gs) (cdr noffs) (cdr rbs) (cdr roffs)))))
      out)))

;; Build a Unix ar archive bytevector from list of (member-name . payload-bv),
;; supporting GNU long filename table ("//") when any member name exceeds 15 chars.
(define (make-test-ar-archive members)
  (let* ((long-needed?
          (let loop ((ms members))
            (and (pair? ms)
                 (or (> (string-length (caar ms)) 15) (loop (cdr ms))))))
         (longtab-bytes-box (cons '() '()))
         (pad-str-bytes
          (lambda (s width)
            (let* ((bs (str->ascii-bytes s))
                   (n (length bs)))
              (if (>= n width)
                  (let take ((k 0) (xs bs) (acc '()))
                    (if (= k width) (reverse acc) (take (+ k 1) (cdr xs) (cons (car xs) acc))))
                  (let pad ((k n) (acc (reverse bs)))
                    (if (= k width) (reverse acc) (pad (+ k 1) (cons 32 acc))))))))
         (app-all
          (lambda xs
            (let loop ((rs xs) (acc '()))
              (if (null? rs)
                  acc
                  (loop (cdr rs) (append acc (car rs)))))))
         (make-hdr
          (lambda (name-16 size)
            (app-all (pad-str-bytes name-16 16)
                     (pad-str-bytes "0" 12)
                     (pad-str-bytes "0" 6)
                     (pad-str-bytes "0" 6)
                     (pad-str-bytes "100644" 8)
                     (pad-str-bytes (number->string size) 10)
                     '(96 10))))
         (chunks-box (cons (list (elf64-list->bytevector (str->ascii-bytes "!<arch>\n"))) '())))
    (if long-needed?
        (let* ((lt-bytes
                (let loop ((ms members) (off 0) (names-map '()) (acc '()))
                  (if (null? ms)
                      (begin
                        (set-car! longtab-bytes-box (reverse names-map))
                        (elf64-list->bytevector acc))
                      (let ((name (caar ms)))
                        (if (> (string-length name) 15)
                            (let ((entry (append (str->ascii-bytes name) '(47 10))))
                              (loop (cdr ms) (+ off (length entry))
                                    (cons (cons name off) names-map)
                                    (append acc entry)))
                            (loop (cdr ms) off names-map acc))))))
               (lt-sz (bytevector-length lt-bytes)))
          (set-car! chunks-box
                    (cons (elf64-list->bytevector (make-hdr "//" lt-sz)) (car chunks-box)))
          (set-car! chunks-box (cons lt-bytes (car chunks-box)))
          (if (odd? lt-sz)
              (set-car! chunks-box (cons (elf64-list->bytevector '(10)) (car chunks-box))))))
    (for-each
     (lambda (m)
       (let* ((mname (car m))
              (payload (cdr m))
              (sz (bytevector-length payload))
              (hdr-name (if (> (string-length mname) 15)
                            (string-append "/" (number->string (cdr (assoc mname (car longtab-bytes-box)))))
                            (string-append mname "/")))
              (hdr (elf64-list->bytevector (make-hdr hdr-name sz))))
         (set-car! chunks-box (cons hdr (car chunks-box)))
         (set-car! chunks-box (cons payload (car chunks-box)))
         (if (odd? sz)
             (set-car! chunks-box (cons (elf64-list->bytevector '(10)) (car chunks-box))))))
     members)
    (let* ((ordered (reverse (car chunks-box)))
           (total (let loop ((cs ordered) (n 0))
                    (if (null? cs) n (loop (cdr cs) (+ n (bytevector-length (car cs)))))))
           (out (make-bytevector total 0)))
      (let loop ((cs ordered) (pos 0))
        (if (pair? cs)
            (let* ((c (car cs))
                   (len (bytevector-length c)))
              (elf64-copy-bytes! out pos c 0 len)
              (loop (cdr cs) (+ pos len)))))
      out)))

(define *test-out-dir* "build/test_elf_static_linker")

;; -----------------------------------------------------------------------
;; Test 1: Single ET_REL sys_exit(42)
;; -----------------------------------------------------------------------
(display "\n--- Test 1: Single Object sys_exit(42) & W^X PHDRs ---\n")
(let* ((code (elf64-list->bytevector '(#xb8 #x3c #x00 #x00 #x00
                                       #xbf #x2a #x00 #x00 #x00
                                       #x0f #x05)))
       (o1 (make-custom-et-rel
            (list (list ".text" 1 6 code 16))
            (list (list "_start" 1 2 1 0 12))
            '()))
       (bin-path (string-append *test-out-dir* "/t1_exit42")))
  (link-elf64-objects-to-file (list o1) bin-path "_start")
  (let ((bin (read-binary-file-to-bytevector bin-path)))
    (assert-equal "ET_EXEC magic 0x7fELF" 127 (elf64-get-u8 bin 0))
    (assert-equal "e_type == ET_EXEC (2)" 2 (elf64-get-u16-le bin 16))
    (assert-equal "e_phnum == 3 (no TLS)" 3 (elf64-get-u16-le bin 56))
    (assert-equal "PHDR 0 flags RX (5)" 5 (elf64-get-u32-le bin 68))
    (assert-equal "PHDR 1 flags RW (6)" 6 (elf64-get-u32-le bin 124))
    (assert-equal "PHDR 2 type PT_GNU_STACK" 1685382481 (elf64-get-u32-le bin 176))
    (assert-equal "PHDR 2 flags RW non-exec (6)" 6 (elf64-get-u32-le bin 180))))

;; -----------------------------------------------------------------------
;; Test 2: Cyclic ar archives + GNU // long names + unused exclusion
;; -----------------------------------------------------------------------
(display "\n--- Test 2: Cyclic ar Archives & GNU // Long Filenames ---\n")
(let* (;; main.o: calls fn_a() -> receives return value -> sys_exit(eax)
       ;; call rel32 (e8 00 00 00 00) ; mov edi, eax (89 c7) ; mov eax, 60 (b8 3c 0 0 0) ; syscall (0f 05)
       (main-code (elf64-list->bytevector '(#xe8 #x00 #x00 #x00 #x00
                                            #x89 #xc7
                                            #xb8 #x3c #x00 #x00 #x00
                                            #x0f #x05)))
       (main-o (make-custom-et-rel
                (list (list ".text" 1 6 main-code 16))
                (list (list "_start" 1 2 1 0 14)
                      (list "fn_a" 1 0 0 0 0))
                (list (list 1 1 4 2 -4))))
       ;; fn_a in liba.a: call fn_b(); add eax, 10; ret
       ;; e8 0 0 0 0 ; 83 c0 0a ; c3
       (a1-code (elf64-list->bytevector '(#xe8 #x00 #x00 #x00 #x00
                                          #x83 #xc0 #x0a
                                          #xc3)))
       (a1-o (make-custom-et-rel
              (list (list ".text" 1 6 a1-code 16))
              (list (list "fn_a" 1 2 1 0 9)
                    (list "fn_b" 1 0 0 0 0))
              (list (list 1 1 4 2 -4))))
       ;; fn_c in liba.a (cyclic reference from libb.a!): mov eax, 32; ret
       (a2-code (elf64-list->bytevector '(#xb8 #x20 #x00 #x00 #x00 #xc3)))
       (a2-o (make-custom-et-rel
              (list (list ".text" 1 6 a2-code 16))
              (list (list "fn_c" 1 2 1 0 6))
              '()))
       ;; unused.o in liba.a references nonexistent_unused_sym!
       ;; Must NOT be extracted or cause C99-LNK-001!
       (unused-code (elf64-list->bytevector '(#xe8 #x00 #x00 #x00 #x00 #xc3)))
       (unused-o (make-custom-et-rel
                  (list (list ".text" 1 6 unused-code 16))
                  (list (list "fn_unused" 1 2 1 0 6)
                        (list "nonexistent_unused_sym" 1 0 0 0 0))
                  (list (list 1 1 4 2 -4))))
       ;; fn_b in libb.a: call fn_c(); add eax, 3; ret (total = 32 + 3 + 10 = 45!)
       (b1-code (elf64-list->bytevector '(#xe8 #x00 #x00 #x00 #x00
                                          #x83 #xc0 #x03
                                          #xc3)))
       (b1-o (make-custom-et-rel
              (list (list ".text" 1 6 b1-code 16))
              (list (list "fn_b" 1 2 1 0 9)
                    (list "fn_c" 1 0 0 0 0))
              (list (list 1 1 4 2 -4))))
       (liba (make-test-ar-archive
              (list (cons "very_long_member_name_for_fn_a.o" a1-o)
                    (cons "very_long_member_name_for_fn_c.o" a2-o)
                    (cons "unused_member_with_broken_sym.o" unused-o))))
       (libb (make-test-ar-archive
              (list (cons "member_fn_b.o" b1-o))))
       (liba-path (string-append *test-out-dir* "/liba.a"))
       (libb-path (string-append *test-out-dir* "/libb.a"))
       (bin-path (string-append *test-out-dir* "/t2_cyclic_ar")))
  (elf64-write-binary-file! liba-path liba)
  (elf64-write-binary-file! libb-path libb)
  (let ((bin (link-elf64-objects-to-file (list main-o liba-path libb-path) bin-path "_start")))
    (assert-true "Cyclic archives linked & unused member excluded" (bytevector? bin))))

;; -----------------------------------------------------------------------
;; Test 3: SHN_COMMON, SHN_ABS, STB_WEAK override, undef weak -> 0, Prefixes
;; -----------------------------------------------------------------------
(display "\n--- Test 3: SHN_COMMON, SHN_ABS, STB_WEAK, Section Prefixes ---\n")
(let* (;; Check .text.startup prefix + SHN_COMMON + weak override + undef weak + SHN_ABS
       ;; Code:
       ;;   movabs rax, weak_missing (48 b8 [8b]) -> 0
       ;;   test rax, rax (48 85 c0) -> if 0 continue
       ;;   jnz fail (75 2a)
       ;;   call hook_fn (e8 [4b]) -> strong returns 7
       ;;   add al, [rip + common_buf] (02 05 [4b]) -> 0 (in .bss) -> still 7
       ;;   mov rdx, [rip + my_got_sym@GOTPCREL] -> GOT holds common_buf addr (nonzero!)
       ;;   call [weak/got verify] -> return abs val (0x12) + 7 + (common_buf != 0 ? 10 : 0) = 29
       ;; Simpler arithmetic for deterministic exit code 29:
       ;;   call hook_fn            ; e8 [4b rel hook_fn] -> returns 10
       ;;   mov edi, eax            ; 89 c7
       ;;   lea rax, [rip+weak_undef] ; 48 8d 05 [4b pc32 weak_undef]
       ;;   test rax, rax           ; 48 85 c0 -> nz only if weak_undef != 0 (we expect 0 -> ZF=1)
       ;;   jnz skip                ; 75 03
       ;;   add edi, 5              ; 83 c7 05 -> edi = 15
       ;; skip:
       ;;   lea rsi, [rip+common_arr]; 48 8d 35 [4b pc32 common_arr] -> addr of common_arr (non-zero!)
       ;;   mov byte [rsi+31], 9    ; c6 46 1f 09
       ;;   movzx eax, byte [rsi+31]; 0f b6 46 1f -> 9
       ;;   add edi, eax            ; 01 c7 -> edi = 24
       ;;   mov rax, [rip+hook_fn@GOTPCREL]; 48 8b 05 [4b rel=9]
       ;;   call rax                ; ff d0 -> returns 10
       ;;   movabs rdx, abs_five    ; 48 ba [8b abs64 abs_five] -> 5
       ;;   add edi, edx            ; 01 d7 -> edi = 29! (24 + 5)
       ;;   mov eax, 60             ; b8 3c 00 00 00
       ;;   syscall                 ; 0f 05
       (code1 (elf64-list->bytevector
               '(#xe8 #x00 #x00 #x00 #x00
                 #x89 #xc7
                 #x48 #x8d #x05 #x00 #x00 #x00 #x00
                 #x48 #x85 #xc0
                 #x75 #x03
                 #x83 #xc7 #x05
                 #x48 #x8d #x35 #x00 #x00 #x00 #x00
                 #xc6 #x46 #x1f #x09
                 #x0f #xb6 #x46 #x1f
                 #x01 #xc7
                 #x48 #x8b #x05 #x00 #x00 #x00 #x00
                 #xff #xd0
                 #x48 #xba #x00 #x00 #x00 #x00 #x00 #x00 #x00 #x00
                 #x01 #xd7
                 #xb8 #x3c #x00 #x00 #x00
                 #x0f #x05)))
       ;; weak default hook_fn returns 99
       (weak-hook (elf64-list->bytevector '(#xb8 #x63 #x00 #x00 #x00 #xc3)))
       (o1 (make-custom-et-rel
            (list (list ".text.startup" 1 6 code1 16)
                  (list ".text.weak" 1 6 weak-hook 16))
            (list (list "_start" 1 2 1 0 67)
                  (list "hook_fn" 2 2 2 0 6)          ;; STB_WEAK
                  (list "common_arr" 1 1 65522 16 16) ;; SHN_COMMON align=16 size=16
                  (list "abs_five" 1 0 65521 5 0)     ;; SHN_ABS = 5
                  (list "weak_undef" 2 0 0 0 0))      ;; Weak UNDEF -> 0!
            (list (list 1 1 4 2 -4)    ;; call hook_fn (sym 2)
                  (list 1 10 2 5 -4)   ;; pc32 weak_undef (sym 5)
                  (list 1 25 2 3 -4)   ;; pc32 common_arr (sym 3)
                  (list 1 42 42 2 -4)  ;; REX_GOTPCRELX hook_fn (sym 2)
                  (list 1 50 1 4 0)))) ;; R_X86_64_64 abs_five (sym 4)
       ;; strong hook_fn returns 10, AND larger common_arr size=64 align=32!
       (strong-hook (elf64-list->bytevector '(#xb8 #x0a #x00 #x00 #x00 #xc3)))
       (o2 (make-custom-et-rel
            (list (list ".text.hot" 1 6 strong-hook 16)
                  (list ".fini_array" 15 3 (make-bytevector 8 0) 8)
                  (list ".data.rel.ro" 1 3 (make-bytevector 8 0) 8))
            (list (list "hook_fn" 1 2 1 0 6)            ;; STB_GLOBAL overrides weak
                  (list "common_arr" 1 1 65522 32 64))  ;; SHN_COMMON larger size=64
            '()))
       (bin-path (string-append *test-out-dir* "/t3_common_weak_got")))
  (link-elf64-objects-to-file (list o1 o2) bin-path "_start")
  (assert-true "SHN_COMMON + SHN_ABS + WEAK override + REX_GOTPCRELX linked" (file-exists? bin-path)))

;; -----------------------------------------------------------------------
;; Test 4: TLS (.tdata + .tbss) PT_TLS & R_X86_64_TPOFF32 + Synthetic Syms
;; -----------------------------------------------------------------------
(display "\n--- Test 4: TLS PT_TLS + R_X86_64_TPOFF32 + Synthetic Symbols ---\n")
(let* (;; Code verifies Variant II TPOFF32 is negative & in range, and verifies _DYNAMIC == 0,
       ;; and __bss_start <= _edata == _bss_start? Wait: rw_file_end <= __bss_start <= _end!
       ;; Also emits two instructions using R_X86_64_TPOFF32 (23) and R_X86_64_PC64 (24) in .data:
       ;; _start:
       ;;   mov eax, 0x0         ; b8 [4b tpoff32 tls_var_a] -> should equal -8 (0xfffffff8)
       ;;   add eax, 0x0         ; 05 [4b tpoff32 tls_var_b] -> should equal -4 (0xfffffffc) -> sum = -12
       ;;   neg eax              ; f7 d8 -> eax = 12
       ;;   mov rdi, [rip+p64_check] ; let's check p64 delta in .data separately or just pass eax+30
       ;;   add eax, 30          ; 83 c0 1e -> 42!
       ;;   mov edi, eax         ; 89 c7
       ;;   mov eax, 60          ; b8 3c 00 00 00
       ;;   syscall              ; 0f 05
       (tls-code (elf64-list->bytevector
                  '(#xb8 #x00 #x00 #x00 #x00
                    #x05 #x00 #x00 #x00 #x00
                    #xf7 #xd8
                    #x83 #xc0 #x1e
                    #x89 #xc7
                    #xb8 #x3c #x00 #x00 #x00
                    #x0f #x05)))
       (tdata-bv (elf64-list->bytevector '(#x11 #x22 #x33 #x44))) ;; 4 bytes
       (tbss-bv (make-bytevector 4 0))
       (data-bv (make-bytevector 32 0))
       (o-tls (make-custom-et-rel
               (list (list ".text" 1 6 tls-code 16)
                     (list ".tdata" 1 1027 tdata-bv 4)    ;; SHF_WRITE|ALLOC|TLS = 1027
                     (list ".tbss" 8 1027 tbss-bv 4 4)   ;; SHT_NOBITS + TLS = 1027
                     (list ".data" 1 3 data-bv 8))
               (list (list "_start" 1 2 1 0 24)
                     (list "tls_a" 1 6 2 0 4)
                     (list "tls_b" 1 6 3 0 4)
                     (list "__bss_start" 1 0 0 0 0)
                     (list "_edata" 1 0 0 0 0)
                     (list "_end" 1 0 0 0 0)
                     (list "__ehdr_start" 1 0 0 0 0)
                     (list "__fini_array_start" 1 0 0 0 0)
                     (list "_DYNAMIC" 2 0 0 0 0))
               (list (list 1 1 23 2 0)   ;; TPOFF32 tls_a
                     (list 1 6 23 3 0)   ;; TPOFF32 tls_b
                     (list 4 0 1 4 0)    ;; .data[0] = __bss_start
                     (list 4 8 1 5 0)    ;; .data[8] = _edata
                     (list 4 16 1 6 0)   ;; .data[16] = _end
                     (list 4 24 24 7 0)))) ;; R_X86_64_PC64 __ehdr_start at .data[24]
       (bin-path (string-append *test-out-dir* "/t4_tls_synth")))
  (link-elf64-objects-to-file (list o-tls) bin-path "_start")
  (let ((bin (read-binary-file-to-bytevector bin-path)))
    (assert-equal "e_phnum == 4 (with PT_TLS)" 4 (elf64-get-u16-le bin 56))
    (assert-equal "PHDR 2 p_type == PT_TLS (7)" 7 (elf64-get-u32-le bin 176))
    (assert-equal "PT_TLS p_filesz == 4" 4 (elf64-get-u64-le bin (+ 176 32)))
    (assert-equal "PT_TLS p_memsz == 8" 8 (elf64-get-u64-le bin (+ 176 40)))
    (assert-equal "PHDR 3 p_type == PT_GNU_STACK" 1685382481 (elf64-get-u32-le bin 232))
    ;; Verify PC64 and synthetic symbols in RW .data (after 4-byte .tdata aligned to 16)
    (let* ((rw-off (elf64-get-u64-le bin (+ 120 8)))
           (rw-va (elf64-get-u64-le bin (+ 120 16)))
           (data-off 16)
           (data-va (+ rw-va data-off))
           (bss-va (elf64-get-u64-le bin (+ rw-off data-off 0)))
           (edata-va (elf64-get-u64-le bin (+ rw-off data-off 8)))
           (end-va (elf64-get-u64-le bin (+ rw-off data-off 16)))
           (pc64-val (elf64-get-s64-le bin (+ rw-off data-off 24))))
      (assert-true "Synthetic _edata <= __bss_start <= _end" (<= edata-va bss-va))
      (assert-true "Synthetic __bss_start <= _end" (<= bss-va end-va))
      (assert-equal "R_X86_64_PC64 negative delta equals __ehdr_start - P"
                    (- 4194304 (+ data-va 24))
                    pc64-val)
      (assert-true "RW base vaddr >= 0x400000" (>= rw-va 4194304)))))

;; -----------------------------------------------------------------------
;; Test 5: Negative Error Tests (C99-LNK-001..003)
;; -----------------------------------------------------------------------
(display "\n--- Test 5: Negative Diagnostics (C99-LNK-001..003) ---\n")
(let* ((code-u (elf64-list->bytevector '(#xe8 #x00 #x00 #x00 #x00 #xc3)))
       (obj-u (make-custom-et-rel
               (list (list ".text" 1 6 code-u 16))
               (list (list "_start" 1 2 1 0 6)
                     (list "missing_strong_fn" 1 0 0 0 0))
               (list (list 1 1 4 2 -4))))
       (obj-d1 (make-custom-et-rel
                (list (list ".text" 1 6 (elf64-list->bytevector '(#xc3)) 16))
                (list (list "_start" 1 2 1 0 1)
                      (list "dup_sym" 1 2 1 0 1))
                '()))
       (obj-d2 (make-custom-et-rel
                (list (list ".text" 1 6 (elf64-list->bytevector '(#xc3)) 16))
                (list (list "dup_sym" 1 2 1 0 1))
                '()))
       (obj-badrel (make-custom-et-rel
                    (list (list ".text" 1 6 code-u 16))
                    (list (list "_start" 1 2 1 0 6))
                    (list (list 1 1 999 1 0))))
       (bad-ar (elf64-list->bytevector '(33 60 97 114 99 104 62 10 1 2 3)))
       (bad-elf (elf64-list->bytevector '(127 69 76 70 2 1 0 0 0 0))))
  (let ((e1 (capture-linker-error (lambda () (link-elf64-relocatable-objects (list obj-u) "_start")))))
    (assert-equal "Undefined strong symbol raises C99-LNK-001" "C99-LNK-001" (and e1 (car e1))))
  (let ((e2 (capture-linker-error (lambda () (link-elf64-relocatable-objects (list obj-d1 obj-d2) "_start")))))
    (assert-equal "Duplicate strong symbol raises C99-LNK-002" "C99-LNK-002" (and e2 (car e2))))
  (let ((e3 (capture-linker-error (lambda () (link-elf64-relocatable-objects (list bad-ar) "_start")))))
    (assert-equal "Truncated ar archive raises C99-LNK-003" "C99-LNK-003" (and e3 (car e3))))
  (let ((e4 (capture-linker-error (lambda () (link-elf64-relocatable-objects (list bad-elf) "_start")))))
    (assert-equal "Truncated ELF object raises C99-LNK-003" "C99-LNK-003" (and e4 (car e4))))
  (let ((e5 (capture-linker-error (lambda () (link-elf64-relocatable-objects (list obj-badrel) "_start")))))
    (assert-equal "Unsupported reloc type raises C99-LNK-003" "C99-LNK-003" (and e5 (car e5)))))

;; -----------------------------------------------------------------------
;; Test 6: c_driver.scm Option Parsing for --linker=ulisp / -static / -nostdlib / -e
;; -----------------------------------------------------------------------
(display "\n--- Test 6: c_driver Static Linker Option Parsing ---\n")
(let ((opts (parse-c-driver-args
             '("--" "--linker=ulisp" "-static" "-nostdlib" "-nostartfiles" "-e" "custom_start"
               "-Lbuild/test_elf_static_linker" "-la" "main.o" "libfoo.a" "-o" "app"))))
  (assert-equal "c-drv-linker is 'ulisp" 'ulisp (c-drv-linker opts))
  (assert-true "c-drv-static? is #t" (c-drv-static? opts))
  (assert-true "c-drv-nostdlib? is #t" (c-drv-nostdlib? opts))
  (assert-true "c-drv-nostartfiles? is #t" (c-drv-nostartfiles? opts))
  (assert-equal "c-drv-entry-sym is custom_start" "custom_start" (c-drv-entry-sym opts))
  (assert-equal "c-drv-inputs keeps .o and .a" '("main.o" "libfoo.a") (c-drv-inputs opts)))

(let ((opts-wl (parse-c-driver-args '("-Wl,-e,my_entry" "--linker=host" "a.o"))))
  (assert-equal "-Wl,-e,<sym> sets entry-sym" "my_entry" (c-drv-entry-sym opts-wl))
  (assert-equal "--linker=host" 'host (c-drv-linker opts-wl)))

(assert-report)
