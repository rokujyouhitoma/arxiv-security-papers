;;; =======================================================================
;;; ULisp Compiler Backend: Common Static ELF64 Executable Builder
;;; Conforms to DSN-33 Architecture Specification & Issues #616, #619
;;; System V ABI AMD64 Architecture Processor Supplement Compliant
;;; DWARF 4 Debugging Information Format Compliant
;;; =======================================================================
;;; Synthesizes standalone, self-contained ELF64 ET_EXEC executable binaries
;;; directly into a Scheme bytevector with strict W^X separation.
;;; Optionally emits minimal DWARF (.debug_line, .debug_info, .debug_abbrev,
;;; .debug_str) and ELF symbol tables (.symtab, .strtab) for GDB / perf.
;;; =======================================================================

;; Little-Endian 16/32/64-bit integer writing primitives into bytevector
;; Implemented using portable arithmetic (modulo/quotient) for 100% compatibility
;; across ILisp interpreter, Gauche, and native ULisp AOT.
(define (elf64-set-u8! bv off val)
  (bytevector-u8-set! bv off (modulo (if (< val 0) (+ val 256) val) 256)))

(define (elf64-set-u16-le! bv off val)
  (let ((u (if (< val 0) (+ val 65536) val)))
    (bytevector-u8-set! bv off (modulo u 256))
    (bytevector-u8-set! bv (+ off 1) (modulo (quotient u 256) 256))))

(define (elf64-set-u32-le! bv off val)
  (let ((u (if (< val 0) (+ val 4294967296) val)))
    (bytevector-u8-set! bv off (modulo u 256))
    (bytevector-u8-set! bv (+ off 1) (modulo (quotient u 256) 256))
    (bytevector-u8-set! bv (+ off 2) (modulo (quotient u 65536) 256))
    (bytevector-u8-set! bv (+ off 3) (modulo (quotient u 16777216) 256))))

(define (elf64-set-u64-le! bv off val)
  (let ((lo (modulo val 4294967296))
        (hi (quotient val 4294967296)))
    (elf64-set-u32-le! bv off lo)
    (elf64-set-u32-le! bv (+ off 4) hi)))

(define (elf64-align-up val align)
  (let ((rem (modulo val align)))
    (if (= rem 0)
        val
        (+ val (- align rem)))))

(define (elf64-copy-bytes! dst dst-off src src-off count)
  (let loop ((i 0))
    (if (< i count)
        (begin
          (bytevector-u8-set! dst (+ dst-off i) (bytevector-u8-ref src (+ src-off i)))
          (loop (+ i 1)))
        #t)))

(define (elf64-list->bytevector lst)
  (let* ((len (length lst))
         (bv (make-bytevector len 0)))
    (let loop ((i 0) (rest lst))
      (if (null? rest)
          bv
          (begin
            (bytevector-u8-set! bv i (car rest))
            (loop (+ i 1) (cdr rest)))))))

(define (dwarf-string->bytes str)
  (let loop ((i (- (string-length str) 1)) (acc '()))
    (if (< i 0)
        acc
        (loop (- i 1) (cons (char->integer (string-ref str i)) acc)))))

;; Seed-compiler-safe n-ary list append helpers (builtin append is binary)
(define (dwarf-app3 a b c) (append a (append b c)))
(define (dwarf-app4 a b c d) (append a (append b (append c d))))
(define (dwarf-app5 a b c d e) (append a (append b (append c (append d e)))))

;; -----------------------------------------------------------------------
;; DWARF 4 Variable-Length Integer (LEB128) Encoders
;; -----------------------------------------------------------------------

(define (dwarf-uleb128 val)
  (let loop ((v (if (< val 0) 0 val)) (acc '()))
    (let* ((byte (modulo v 128))
           (next-v (quotient v 128)))
      (if (= next-v 0)
          (reverse (cons byte acc))
          (loop next-v (cons (+ byte 128) acc))))))

(define (dwarf-sleb128 val)
  (let loop ((v val) (acc '()))
    (let* ((byte (modulo v 128))
           (next-v (if (< v 0) (quotient (- v 127) 128) (quotient v 128)))
           (sign-bit (>= byte 64)))
      (if (or (and (= next-v 0) (not sign-bit))
              (and (= next-v -1) sign-bit))
          (reverse (cons byte acc))
          (loop next-v (cons (+ byte 128) acc))))))

(define (sort-line-table lines)
  (let sort ((lst lines))
    (if (or (null? lst) (null? (cdr lst)))
        lst
        (let* ((pivot (car lst))
               (p-off (cadddr pivot))
               (rest (cdr lst)))
          (let partition ((items rest) (less '()) (more '()))
            (if (null? items)
                (dwarf-app3 (sort less) (list pivot) (sort more))
                (if (< (cadddr (car items)) p-off)
                    (partition (cdr items) (cons (car items) less) more)
                    (partition (cdr items) less (cons (car items) more)))))))))

;; -----------------------------------------------------------------------
;; Section Header Table String Helpers
;; -----------------------------------------------------------------------

;; Standard 6-section shstrtab:
;; "\x00.text\x00.rodata\x00.data\x00.bss\x00.shstrtab\x00"
(define (elf64-make-shstrtab-bytes)
  ;; Indices: 0: "", 1: ".text", 7: ".rodata", 15: ".data", 21: ".bss", 26: ".shstrtab"
  (elf64-list->bytevector
    '(0
      46 116 101 120 116 0          ; .text\0
      46 114 111 100 97 116 97 0    ; .rodata\0
      46 100 97 116 97 0            ; .data\0
      46 98 115 115 0               ; .bss\0
      46 115 104 115 116 114 116 97 98 0))) ; .shstrtab\0

;; Debug 12-section shstrtab (Issue #619):
;; "\x00.text\x00.rodata\x00.data\x00.bss\x00.debug_line\x00.debug_info\x00.debug_abbrev\x00.debug_str\x00.symtab\x00.strtab\x00.shstrtab\x00"
(define (elf64-make-debug-shstrtab-bytes)
  ;; Indices:
  ;; 0: "", 1: ".text", 7: ".rodata", 15: ".data", 21: ".bss",
  ;; 26: ".debug_line", 38: ".debug_info", 50: ".debug_abbrev",
  ;; 64: ".debug_str", 75: ".symtab", 83: ".strtab", 91: ".shstrtab"
  (elf64-list->bytevector
    '(0
      46 116 101 120 116 0                             ; .text\0
      46 114 111 100 97 116 97 0                       ; .rodata\0
      46 100 97 116 97 0                               ; .data\0
      46 98 115 115 0                                  ; .bss\0
      46 100 101 98 117 103 95 108 105 110 101 0       ; .debug_line\0
      46 100 101 98 117 103 95 105 110 102 111 0       ; .debug_info\0
      46 100 101 98 117 103 95 97 98 98 114 101 118 0 ; .debug_abbrev\0
      46 100 101 98 117 103 95 115 116 114 0          ; .debug_str\0
      46 115 121 109 116 97 98 0                       ; .symtab\0
      46 115 116 114 116 97 98 0                       ; .strtab\0
      46 115 104 115 116 114 116 97 98 0)))            ; .shstrtab\0

;; -----------------------------------------------------------------------
;; DWARF Section Synthesis Helpers
;; -----------------------------------------------------------------------

(define (dwarf-make-debug-abbrev-bytes)
  (elf64-list->bytevector
    '(1                           ; Abbrev code 1
      17                          ; DW_TAG_compile_unit (0x11)
      0                           ; DW_CHILDREN_no (0)
      16 6                        ; DW_AT_stmt_list, DW_FORM_data4
      17 1                        ; DW_AT_low_pc, DW_FORM_addr
      18 1                        ; DW_AT_high_pc, DW_FORM_addr
      3 14                        ; DW_AT_name, DW_FORM_strp
      37 14                       ; DW_AT_producer, DW_FORM_strp
      0 0                         ; Attribute list terminator
      0)))                        ; Abbreviation table terminator

(define (dwarf-make-debug-str-bytes main-file)
  (let* ((f-bytes (dwarf-string->bytes main-file))
         (prod-bytes (dwarf-string->bytes "ULisp 2.0 AOT Native Compiler"))
         (str-list (dwarf-app4 f-bytes '(0) prod-bytes '(0))))
    (elf64-list->bytevector str-list)))

(define (dwarf-make-debug-info-bytes text-vaddr text-len name-str-off prod-str-off)
  (let ((bv (make-bytevector 40 0)))
    (elf64-set-u32-le! bv 0 36)                       ; unit_length = 36
    (elf64-set-u16-le! bv 4 3)                        ; version = 3
    (elf64-set-u32-le! bv 6 0)                        ; debug_abbrev_offset = 0
    (elf64-set-u8! bv 10 8)                           ; address_size = 8
    (elf64-set-u8! bv 11 1)                           ; abbrev_code = 1
    (elf64-set-u32-le! bv 12 0)                       ; DW_AT_stmt_list = 0
    (elf64-set-u64-le! bv 16 text-vaddr)              ; DW_AT_low_pc
    (elf64-set-u64-le! bv 24 (+ text-vaddr text-len)) ; DW_AT_high_pc
    (elf64-set-u32-le! bv 32 name-str-off)            ; DW_AT_name
    (elf64-set-u32-le! bv 36 prod-str-off)            ; DW_AT_producer
    bv))

(define (sort-file-table files)
  (if (or (null? files) (null? (cdr files)))
      files
      (let* ((pivot (car files))
             (p-id (if (pair? pivot) (car pivot) 1))
             (less (filter (lambda (x) (< (if (pair? x) (car x) 1) p-id)) (cdr files)))
             (more (filter (lambda (x) (>= (if (pair? x) (car x) 1) p-id)) (cdr files))))
        (append (sort-file-table less) (cons pivot (sort-file-table more))))))

(define (build-debug-line-section file-table line-table text-vaddr text-len)
  (let* ((raw-files (if (pair? file-table) file-table '((1 . "source.scm"))))
         (files (sort-file-table raw-files))
         (sorted-lines (sort-line-table line-table))
         (min-insn 1)
         (default-stmt 1)
         (line-base -5)
         (line-range 14)
         (opcode-base 13)
         (std-opcode-lens '(0 1 1 1 1 0 0 0 1 0 0 1))
         (file-bytes
           (let loop ((fs files) (acc '()))
             (if (null? fs)
                 (reverse (cons 0 acc))
                 (let* ((entry (car fs))
                        (fname (if (pair? entry) (cdr entry) "source.scm"))
                        (fn-chars (dwarf-string->bytes fname))
                        (fn-bytes (dwarf-app5 fn-chars '(0) (dwarf-uleb128 0) (dwarf-uleb128 0) (dwarf-uleb128 0))))
                   (loop (cdr fs) (append (reverse fn-bytes) acc))))))
         (inc-dirs '(0))
         (hdr-content (dwarf-app3 (list min-insn default-stmt
                                    (modulo (if (< line-base 0) (+ line-base 256) line-base) 256)
                                    line-range opcode-base)
                              std-opcode-lens
                              (append inc-dirs file-bytes)))
         (hdr-len (length hdr-content))
         (prog-bytes
           (let loop ((entries sorted-lines)
                      (cur-pc 0)
                      (cur-line 1)
                      (cur-file 1)
                      (first? #t)
                      (acc '()))
             (if (null? entries)
                 (let* ((pad-pc (if (< cur-pc text-len)
                                    (append '(2) (dwarf-uleb128 (- text-len cur-pc)))
                                    '()))
                        (end-seq '(0 1 1)))
                   (reverse (dwarf-app3 (reverse end-seq) (reverse pad-pc) acc)))
                 (let* ((entry (car entries))
                        (fid (car entry))
                        (line (cadr entry))
                        (off (cadddr entry)))
                   (if (<= line 0)
                       (loop (cdr entries) cur-pc cur-line cur-file first? acc)
                       (if first?
                           (let* ((target-pc (+ text-vaddr off))
                                  (set-addr-bytes (append '(0 9 2)
                                                          (let ((bv (make-bytevector 8 0)))
                                                            (elf64-set-u64-le! bv 0 target-pc)
                                                            (let bloop ((i 0) (ba '()))
                                                              (if (< i 8)
                                                                  (bloop (+ i 1) (cons (bytevector-u8-ref bv i) ba))
                                                                  (reverse ba))))))
                                  (set-file (if (not (= fid cur-file)) (append '(4) (dwarf-uleb128 fid)) '()))
                                  (line-delta (- line cur-line))
                                  (adv-line (append '(3) (dwarf-sleb128 line-delta)))
                                  (copy '(1))
                                  (new-acc (dwarf-app5 (reverse copy) (reverse adv-line) (reverse set-file) (reverse set-addr-bytes) acc)))
                             (loop (cdr entries) off line fid #f new-acc))
                           (let* ((pc-delta (- off cur-pc))
                                  (line-delta (- line cur-line))
                                  (set-file (if (not (= fid cur-file)) (append '(4) (dwarf-uleb128 fid)) '()))
                                  (adv-pc (if (> pc-delta 0) (append '(2) (dwarf-uleb128 pc-delta)) '()))
                                  (adv-line (if (not (= line-delta 0)) (append '(3) (dwarf-sleb128 line-delta)) '()))
                                  (copy '(1))
                                  (new-acc (dwarf-app5 (reverse copy) (reverse adv-line) (reverse adv-pc) (reverse set-file) acc)))
                             (loop (cdr entries) off line fid #f new-acc))))))))
         (unit-content-len (+ (+ 6 hdr-len) (length prog-bytes)))
         (total-len (+ 4 unit-content-len))
         (bv (make-bytevector total-len 0)))
    (elf64-set-u32-le! bv 0 unit-content-len)
    (elf64-set-u16-le! bv 4 3)
    (elf64-set-u32-le! bv 6 hdr-len)
    (let loop ((i 0) (rest hdr-content))
      (if (pair? rest)
          (begin
            (bytevector-u8-set! bv (+ 10 i) (car rest))
            (loop (+ i 1) (cdr rest)))))
    (let loop ((i 0) (rest prog-bytes))
      (if (pair? rest)
          (begin
            (bytevector-u8-set! bv (+ (+ 10 hdr-len) i) (car rest))
            (loop (+ i 1) (cdr rest)))))
    bv))

(define (build-symtab-and-strtab sym-table text-vaddr text-len)
  (let* ((rodata-vaddr (+ text-vaddr text-len))
         (parsed-syms
           (let loop ((st sym-table) (acc '()))
             (if (null? st)
                 (reverse acc)
                 (let* ((entry (car st))
                        (name (car entry))
                        (info (cdr entry)))
                   (cond
                     ((and (pair? info) (eq? (car info) 'text))
                      (loop (cdr st) (cons (list name (cadr info) 1 18 text-len) acc)))
                     ((and (pair? info) (eq? (car info) 'rodata))
                      (let ((off (cadr info))
                            (sz (if (pair? (cddr info)) (caddr info) 0)))
                        (loop (cdr st) (cons (list name off 2 17 sz) acc))))
                     (else
                      (loop (cdr st) acc)))))))
         (syms-with-stroff
           (let loop ((syms parsed-syms) (stroff 1) (acc '()))
             (if (null? syms)
                 (reverse acc)
                 (let* ((s (car syms))
                        (name (car s))
                        (slen (string-length name)))
                   (loop (cdr syms) (+ (+ stroff slen) 1) (cons (cons (cons name stroff) (cdr s)) acc))))))
         (strtab-bytes
           (let loop ((syms syms-with-stroff) (acc '(0)))
             (if (null? syms)
                 (elf64-list->bytevector (reverse acc))
                 (let* ((name (caar (car syms)))
                        (chars (dwarf-string->bytes name)))
                   (loop (cdr syms) (dwarf-app3 '(0) (reverse chars) acc))))))
         (num-syms (+ (length syms-with-stroff) 1))
         (symtab-len (* num-syms 24))
         (symtab-bv (make-bytevector symtab-len 0)))
    (let loop ((syms syms-with-stroff) (idx 1))
      (if (pair? syms)
          (let* ((item (car syms))
                 (name (caar item))
                 (stroff (cdar item))
                 (off (cadr item))
                 (shndx (caddr item))
                 (st-info (cadddr item))
                 (sz (car (cddddr item)))
                 (sym-off (* idx 24))
                 (val (if (= shndx 1)
                          (+ text-vaddr off)
                          (+ rodata-vaddr off))))
            (elf64-set-u32-le! symtab-bv sym-off stroff)     ;; st_name
            (elf64-set-u8! symtab-bv (+ sym-off 4) st-info)  ;; st_info
            (elf64-set-u8! symtab-bv (+ sym-off 5) 0)        ;; st_other = 0
            (elf64-set-u16-le! symtab-bv (+ sym-off 6) shndx);; st_shndx
            (elf64-set-u64-le! symtab-bv (+ sym-off 8) val)  ;; st_value
            (elf64-set-u64-le! symtab-bv (+ sym-off 16) sz)  ;; st_size
            (loop (cdr syms) (+ idx 1)))))
    (list symtab-bv strtab-bytes)))

;;; -----------------------------------------------------------------------
;;; ELF64 .rodata Frozen Graph Payload Integration (Issue #890 / DSN-33 §11.1)
;;; -----------------------------------------------------------------------

(define (elf64-append-rodata-payload-with-offset rodata-bv payload-bv)
  (let ((p-len (if (bytevector? payload-bv) (bytevector-length payload-bv) 0))
        (r-len (if (bytevector? rodata-bv) (bytevector-length rodata-bv) 0)))
    (if (= p-len 0)
        (cons (if (bytevector? rodata-bv) rodata-bv (make-bytevector 0 0)) 0)
        (let* ((aligned-r-len (elf64-align-up r-len 16))
               (total-len (+ aligned-r-len p-len)))
          (if (> total-len 67108864) ; *max-rodata-size* (64MB)
              (error "E-RODATA-OVERFLOW" total-len)
              (let ((new-bv (make-bytevector total-len 0)))
                (if (> r-len 0)
                    (elf64-copy-bytes! new-bv 0 rodata-bv 0 r-len))
                (elf64-copy-bytes! new-bv aligned-r-len payload-bv 0 p-len)
                (cons new-bv aligned-r-len)))))))

(define (elf64-append-rodata-payload rodata-bv payload-bv)
  (car (elf64-append-rodata-payload-with-offset rodata-bv payload-bv)))

;; -----------------------------------------------------------------------
;; Shared ELF Writing Helpers (kept small to stay within seed-compiler limits)
;; -----------------------------------------------------------------------
(define (elf64-write-shdr! bv shoff idx name type flags addr off size link info align entsize)
  (let ((s (+ shoff (* idx 64))))
    (elf64-set-u32-le! bv s name)
    (elf64-set-u32-le! bv (+ s 4) type)
    (elf64-set-u64-le! bv (+ s 8) flags)
    (elf64-set-u64-le! bv (+ s 16) addr)
    (elf64-set-u64-le! bv (+ s 24) off)
    (elf64-set-u64-le! bv (+ s 32) size)
    (elf64-set-u32-le! bv (+ s 40) link)
    (elf64-set-u32-le! bv (+ s 44) info)
    (elf64-set-u64-le! bv (+ s 48) align)
    (elf64-set-u64-le! bv (+ s 56) entsize)))

(define (elf64-write-ehdr! bv entry-vaddr shoff shnum shstrndx)
  (elf64-set-u8! bv 0 127)
  (elf64-set-u8! bv 1 69)
  (elf64-set-u8! bv 2 76)
  (elf64-set-u8! bv 3 70)
  (elf64-set-u8! bv 4 2)
  (elf64-set-u8! bv 5 1)
  (elf64-set-u8! bv 6 1)
  (elf64-set-u8! bv 7 0)
  (elf64-set-u8! bv 8 0)
  (elf64-set-u16-le! bv 16 2)
  (elf64-set-u16-le! bv 18 62)
  (elf64-set-u32-le! bv 20 1)
  (elf64-set-u64-le! bv 24 entry-vaddr)
  (elf64-set-u64-le! bv 32 64)
  (elf64-set-u64-le! bv 40 shoff)
  (elf64-set-u32-le! bv 48 0)
  (elf64-set-u16-le! bv 52 64)
  (elf64-set-u16-le! bv 54 56)
  (elf64-set-u16-le! bv 56 2)
  (elf64-set-u16-le! bv 58 64)
  (elf64-set-u16-le! bv 60 shnum)
  (elf64-set-u16-le! bv 62 shstrndx))

(define (elf64-write-phdr! bv off flags file-off vaddr filesz memsz)
  (elf64-set-u32-le! bv off 1)
  (elf64-set-u32-le! bv (+ off 4) flags)
  (elf64-set-u64-le! bv (+ off 8) file-off)
  (elf64-set-u64-le! bv (+ off 16) vaddr)
  (elf64-set-u64-le! bv (+ off 24) vaddr)
  (elf64-set-u64-le! bv (+ off 32) filesz)
  (elf64-set-u64-le! bv (+ off 40) memsz)
  (elf64-set-u64-le! bv (+ off 48) 4096))

(define (elf64-write-core! elf-bv entry-vaddr shoff shnum shstrndx text-bv rodata-bv data-bv
                           text-file-offset text-segment-filesz data-file-offset bss-size)
  (let ((text-len (bytevector-length text-bv))
        (rodata-len (bytevector-length rodata-bv))
        (data-len (bytevector-length data-bv)))
    (elf64-write-ehdr! elf-bv entry-vaddr shoff shnum shstrndx)
    (elf64-write-phdr! elf-bv 64 5 0 4194304 text-segment-filesz text-segment-filesz)
    (elf64-write-phdr! elf-bv 120 6 data-file-offset 6291456 data-len (+ data-len bss-size))
    (if (> text-len 0)
        (elf64-copy-bytes! elf-bv text-file-offset text-bv 0 text-len))
    (if (> rodata-len 0)
        (elf64-copy-bytes! elf-bv (+ text-file-offset text-len) rodata-bv 0 rodata-len))
    (let loop ((i (+ (+ text-file-offset text-len) rodata-len)))
      (if (< i data-file-offset)
          (begin
            (bytevector-u8-set! elf-bv i 144)
            (loop (+ i 1)))))
    (if (> data-len 0)
        (elf64-copy-bytes! elf-bv data-file-offset data-bv 0 data-len))
    ;; Section headers 1..4: .text .rodata .data .bss
    (elf64-write-shdr! elf-bv shoff 1 1 1 6 (+ 4194304 text-file-offset) text-file-offset text-len 0 0 16 0)
    (elf64-write-shdr! elf-bv shoff 2 7 1 2 (+ (+ 4194304 text-file-offset) text-len)
                       (+ text-file-offset text-len) rodata-len 0 0 8 0)
    (elf64-write-shdr! elf-bv shoff 3 15 1 3 6291456 data-file-offset data-len 0 0 8 0)
    (elf64-write-shdr! elf-bv shoff 4 21 8 3 (+ 6291456 data-len) (+ data-file-offset data-len) bss-size 0 0 8 0)))

;; Default minimal ELF (zero overhead, 6 sections)
(define (build-elf64-plain text-bv rodata-bv data-bv bss-size entry-offset)
  (let* ((text-file-offset 176)
         (text-len (bytevector-length text-bv))
         (rodata-len (bytevector-length rodata-bv))
         (data-len (bytevector-length data-bv))
         (text-segment-filesz (elf64-align-up (+ (+ text-file-offset text-len) rodata-len) 4096))
         (data-file-offset text-segment-filesz)
         (shstrtab-bytes (elf64-make-shstrtab-bytes))
         (shstrtab-len (bytevector-length shstrtab-bytes))
         (shoff (elf64-align-up (+ data-file-offset data-len) 8))
         (shstrtab-offset (+ shoff (* 6 64)))
         (elf-bv (make-bytevector (+ shstrtab-offset shstrtab-len) 0)))
    (elf64-write-core! elf-bv (+ (+ 4194304 text-file-offset) entry-offset) shoff 6 5
                       text-bv rodata-bv data-bv text-file-offset text-segment-filesz
                       data-file-offset bss-size)
    (elf64-write-shdr! elf-bv shoff 5 26 3 0 0 shstrtab-offset shstrtab-len 0 0 1 0)
    (elf64-copy-bytes! elf-bv shstrtab-offset shstrtab-bytes 0 shstrtab-len)
    elf-bv))

;; Debug ELF (12 sections incl. DWARF + symtab, Issue #619)
(define (build-elf64-debug text-bv rodata-bv data-bv bss-size entry-offset debug-payload)
  (let* ((file-table (car debug-payload))
         (line-table (cadr debug-payload))
         (sym-table (caddr debug-payload))
         (main-file (if (and (pair? file-table) (pair? (car file-table)))
                        (cdr (car file-table))
                        "source.scm"))
         (text-file-offset 176)
         (text-vaddr (+ 4194304 text-file-offset))
         (text-len (bytevector-length text-bv))
         (rodata-len (bytevector-length rodata-bv))
         (data-len (bytevector-length data-bv))
         (text-segment-filesz (elf64-align-up (+ (+ text-file-offset text-len) rodata-len) 4096))
         (data-file-offset text-segment-filesz)
         (debug-line-bv (build-debug-line-section file-table line-table text-vaddr text-len))
         (debug-abbrev-bv (dwarf-make-debug-abbrev-bytes))
         (debug-str-bv (dwarf-make-debug-str-bytes main-file))
         (debug-info-bv (dwarf-make-debug-info-bytes text-vaddr text-len 0 (+ (string-length main-file) 1)))
         (symtab-res (build-symtab-and-strtab sym-table text-vaddr text-len))
         (symtab-bv (car symtab-res))
         (strtab-bv (cadr symtab-res))
         (shstrtab-bytes (elf64-make-debug-shstrtab-bytes))
         (shstrtab-len (bytevector-length shstrtab-bytes))
         (debug-line-off (elf64-align-up (+ data-file-offset data-len) 8))
         (debug-info-off (elf64-align-up (+ debug-line-off (bytevector-length debug-line-bv)) 8))
         (debug-abbrev-off (elf64-align-up (+ debug-info-off (bytevector-length debug-info-bv)) 8))
         (debug-str-off (elf64-align-up (+ debug-abbrev-off (bytevector-length debug-abbrev-bv)) 8))
         (symtab-off (elf64-align-up (+ debug-str-off (bytevector-length debug-str-bv)) 8))
         (strtab-off (elf64-align-up (+ symtab-off (bytevector-length symtab-bv)) 8))
         (shoff (elf64-align-up (+ strtab-off (bytevector-length strtab-bv)) 8))
         (shstrtab-offset (+ shoff (* 12 64)))
         (elf-bv (make-bytevector (+ shstrtab-offset shstrtab-len) 0)))
    (elf64-write-core! elf-bv (+ text-vaddr entry-offset) shoff 12 11
                       text-bv rodata-bv data-bv text-file-offset text-segment-filesz
                       data-file-offset bss-size)
    (elf64-copy-bytes! elf-bv debug-line-off debug-line-bv 0 (bytevector-length debug-line-bv))
    (elf64-copy-bytes! elf-bv debug-info-off debug-info-bv 0 (bytevector-length debug-info-bv))
    (elf64-copy-bytes! elf-bv debug-abbrev-off debug-abbrev-bv 0 (bytevector-length debug-abbrev-bv))
    (elf64-copy-bytes! elf-bv debug-str-off debug-str-bv 0 (bytevector-length debug-str-bv))
    (elf64-copy-bytes! elf-bv symtab-off symtab-bv 0 (bytevector-length symtab-bv))
    (elf64-copy-bytes! elf-bv strtab-off strtab-bv 0 (bytevector-length strtab-bv))
    (elf64-copy-bytes! elf-bv shstrtab-offset shstrtab-bytes 0 shstrtab-len)
    (elf64-write-shdr! elf-bv shoff 5 26 1 0 0 debug-line-off (bytevector-length debug-line-bv) 0 0 1 0)
    (elf64-write-shdr! elf-bv shoff 6 38 1 0 0 debug-info-off (bytevector-length debug-info-bv) 0 0 1 0)
    (elf64-write-shdr! elf-bv shoff 7 50 1 0 0 debug-abbrev-off (bytevector-length debug-abbrev-bv) 0 0 1 0)
    (elf64-write-shdr! elf-bv shoff 8 64 1 48 0 debug-str-off (bytevector-length debug-str-bv) 0 0 1 1)
    (elf64-write-shdr! elf-bv shoff 9 75 2 0 0 symtab-off (bytevector-length symtab-bv) 10 1 8 24)
    (elf64-write-shdr! elf-bv shoff 10 83 3 0 0 strtab-off (bytevector-length strtab-bv) 0 0 1 0)
    (elf64-write-shdr! elf-bv shoff 11 91 3 0 0 shstrtab-offset shstrtab-len 0 0 1 0)
    elf-bv))

;; -----------------------------------------------------------------------
;; Main ELF64 Executable Builder
;; -----------------------------------------------------------------------
;; debug-payload: #f (no debug info) or (file-table line-table sym-table)
(define (build-elf64-executable-ex text-bv rodata-bv data-bv bss-size entry-offset debug-payload)
  (if (and (pair? debug-payload)
           (or (pair? (car debug-payload))
               (pair? (cadr debug-payload))
               (pair? (caddr debug-payload))))
      (build-elf64-debug text-bv rodata-bv data-bv bss-size entry-offset debug-payload)
      (build-elf64-plain text-bv rodata-bv data-bv bss-size entry-offset)))

(define (build-elf64-executable text-bv rodata-bv data-bv bss-size entry-offset)
  (build-elf64-executable-ex text-bv rodata-bv data-bv bss-size entry-offset #f))

;; -----------------------------------------------------------------------
;; Relocatable ELF64 Object (ET_REL) Builder (Issue #783)
;; -----------------------------------------------------------------------

(define (elf64-make-rel-shstrtab-bytes)
  ;; 16 sections:
  ;;  0: "" (0)
  ;;  1: ".text" (1)
  ;;  2: ".rodata" (7)
  ;;  3: ".data" (15)
  ;;  4: ".bss" (21)
  ;;  5: ".init_array" (26)
  ;;  6: "ulisp_globals_sec" (38)
  ;;  7: ".rela.text" (56)
  ;;  8: ".rela.rodata" (67)
  ;;  9: ".rela.data" (80)
  ;; 10: ".rela.init_array" (91)
  ;; 11: ".rela.ulisp_globals_sec" (108)
  ;; 12: ".note.GNU-stack" (132)
  ;; 13: ".symtab" (148)
  ;; 14: ".strtab" (156)
  ;; 15: ".shstrtab" (164)
  (elf64-list->bytevector
    '(0
      46 116 101 120 116 0                                                 ; .text\0
      46 114 111 100 97 116 97 0                                           ; .rodata\0
      46 100 97 116 97 0                                                   ; .data\0
      46 98 115 115 0                                                      ; .bss\0
      46 105 110 105 116 95 97 114 114 97 121 0                            ; .init_array\0
      117 108 105 115 112 95 103 108 111 98 97 108 115 95 115 101 99 0     ; ulisp_globals_sec\0
      46 114 101 108 97 46 116 101 120 116 0                               ; .rela.text\0
      46 114 101 108 97 46 114 111 100 97 116 97 0                         ; .rela.rodata\0
      46 114 101 108 97 46 100 97 116 97 0                                 ; .rela.data\0
      46 114 101 108 97 46 105 110 105 116 95 97 114 114 97 121 0          ; .rela.init_array\0
      46 114 101 108 97 46 117 108 105 115 112 95 103 108 111 98 97 108 115 95 115 101 99 0 ; .rela.ulisp_globals_sec\0
      46 110 111 116 101 46 71 78 85 45 115 116 97 99 107 0                ; .note.GNU-stack\0
      46 115 121 109 116 97 98 0                                           ; .symtab\0
      46 115 116 114 116 97 98 0                                           ; .strtab\0
      46 115 104 115 116 114 116 97 98 0)))                                ; .shstrtab\0

(define (elf64-write-rel-ehdr! bv shoff shnum shstrndx)
  (elf64-set-u8! bv 0 127)
  (elf64-set-u8! bv 1 69)
  (elf64-set-u8! bv 2 76)
  (elf64-set-u8! bv 3 70)
  (elf64-set-u8! bv 4 2)    ;; ELFCLASS64
  (elf64-set-u8! bv 5 1)    ;; ELFDATA2LSB
  (elf64-set-u8! bv 6 1)    ;; EV_CURRENT
  (elf64-set-u8! bv 7 0)    ;; ELFOSABI_NONE
  (elf64-set-u8! bv 8 0)
  (elf64-set-u16-le! bv 16 1)  ;; e_type = ET_REL (1)
  (elf64-set-u16-le! bv 18 62) ;; e_machine = EM_X86_64 (62)
  (elf64-set-u32-le! bv 20 1)  ;; e_version = EV_CURRENT (1)
  (elf64-set-u64-le! bv 24 0)  ;; e_entry = 0
  (elf64-set-u64-le! bv 32 0)  ;; e_phoff = 0
  (elf64-set-u64-le! bv 40 shoff)
  (elf64-set-u32-le! bv 48 0)  ;; e_flags = 0
  (elf64-set-u16-le! bv 52 64) ;; e_ehsize = 64
  (elf64-set-u16-le! bv 54 0)  ;; e_phentsize = 0
  (elf64-set-u16-le! bv 56 0)  ;; e_phnum = 0
  (elf64-set-u16-le! bv 58 64) ;; e_shentsize = 64
  (elf64-set-u16-le! bv 60 shnum)
  (elf64-set-u16-le! bv 62 shstrndx))

(define (elf64-set-s64-le! bv off val)
  (if (< val 0)
      (let* ((pos (- 0 (+ val 1)))
             (lo (modulo pos 4294967296))
             (hi (quotient pos 4294967296)))
        (elf64-set-u32-le! bv off (- 4294967295 lo))
        (elf64-set-u32-le! bv (+ off 4) (- 4294967295 hi)))
      (elf64-set-u64-le! bv off val)))

(define (elf64-build-rel-symtab-ex sym-table globl-syms weak-syms sym-types reloc-records)
  ;; Collect unique named symbols using O(1) hash maps while preserving exact symbol order
  (let* ((seen-nl (make-symbol-map 4096))
         (s1 (let loop ((gs globl-syms) (acc '()))
               (if (null? gs)
                   acc
                   (let ((s (car gs)))
                     (if (symbol-map-contains? seen-nl s)
                         (loop (cdr gs) acc)
                         (begin
                           (symbol-map-set! seen-nl s #t)
                           (loop (cdr gs) (cons s acc))))))))
         (s2 (let loop ((ws weak-syms) (acc s1))
               (if (null? ws)
                   acc
                   (let ((s (car ws)))
                     (if (symbol-map-contains? seen-nl s)
                         (loop (cdr ws) acc)
                         (begin
                           (symbol-map-set! seen-nl s #t)
                           (loop (cdr ws) (cons s acc))))))))
         (non-local-syms
          (let loop ((rs reloc-records) (acc s2))
            (if (null? rs)
                (reverse acc)
                (let ((tgt (caddr (car rs))))
                  (if (and (string? tgt) (not (symbol-map-contains? seen-nl tgt)))
                      (begin
                        (symbol-map-set! seen-nl tgt #t)
                        (loop (cdr rs) (cons tgt acc)))
                      (loop (cdr rs) acc))))))
         ;; Local symbols: symbols in sym-types not in non-local-syms
         (seen-loc (make-symbol-map 4096))
         (local-syms
          (let loop ((st sym-types) (acc '()))
            (if (null? st)
                (reverse acc)
                (let ((s (caar st)))
                  (if (or (symbol-map-contains? seen-nl s)
                          (symbol-map-contains? seen-loc s))
                      (loop (cdr st) acc)
                      (begin
                        (symbol-map-set! seen-loc s #t)
                        (loop (cdr st) (cons s acc))))))))
         (weak-set (make-symbol-map 1024))
         (globl-set (make-symbol-map 1024))
         (def-map (make-symbol-map 4096))
         (type-map (make-symbol-map 4096))
         (first-global-idx (+ 7 (length local-syms)))
         (ordered-syms (append local-syms non-local-syms))
         (syms-meta
          (let loop ((syms ordered-syms) (idx 7) (stroff 1) (acc '()))
            (if (null? syms)
                (reverse acc)
                (let* ((name (car syms))
                       (slen (string-length name)))
                  (loop (cdr syms) (+ idx 1) (+ (+ stroff slen) 1)
                        (cons (list name idx stroff) acc))))))
         (sym-idx-sm (make-symbol-map 4096))
         (sym-idx-map
          (let loop ((ms syms-meta) (acc '()))
            (if (null? ms)
                acc
                (begin
                  (symbol-map-set! sym-idx-sm (caar ms) (cadar ms))
                  (loop (cdr ms) (cons (cons (caar ms) (cadar ms)) acc))))))
         (strtab-len (if (null? syms-meta)
                         1
                         (let ((last-m (let l ((x syms-meta)) (if (null? (cdr x)) (car x) (l (cdr x))))))
                           (+ (+ (caddr last-m) (string-length (car last-m))) 1))))
         (strtab-bv (make-bytevector strtab-len 0))
         (num-syms (+ 7 (length syms-meta)))
         (symtab-bv (make-bytevector (* num-syms 24) 0)))
    (for-each (lambda (s) (symbol-map-set! weak-set s #t)) weak-syms)
    (for-each (lambda (s) (symbol-map-set! globl-set s #t)) globl-syms)
    (for-each (lambda (e)
                (if (not (symbol-map-contains? def-map (car e)))
                    (symbol-map-set! def-map (car e) (cdr e))))
              sym-table)
    (for-each (lambda (e)
                (if (not (symbol-map-contains? type-map (car e)))
                    (symbol-map-set! type-map (car e) (cdr e))))
              sym-types)
    ;; Write strtab-bv
    (bytevector-u8-set! strtab-bv 0 0)
    (let loop ((ms syms-meta))
      (if (pair? ms)
          (let* ((m (car ms))
                 (name (car m))
                 (soff (caddr m))
                 (slen (string-length name)))
            (let cloop ((i 0))
              (if (< i slen)
                  (begin
                    (bytevector-u8-set! strtab-bv (+ soff i) (char->integer (string-ref name i)))
                    (cloop (+ i 1)))
                  (bytevector-u8-set! strtab-bv (+ soff slen) 0)))
            (loop (cdr ms)))))
    ;; Write section symbols 1..6 (STB_LOCAL=0, STT_SECTION=3 -> st_info = 3)
    (let sec-loop ((sidx 1))
      (if (<= sidx 6)
          (let ((off (* sidx 24)))
            (elf64-set-u32-le! symtab-bv off 0)
            (elf64-set-u8! symtab-bv (+ off 4) 3)
            (elf64-set-u8! symtab-bv (+ off 5) 0)
            (elf64-set-u16-le! symtab-bv (+ off 6) sidx)
            (elf64-set-u64-le! symtab-bv (+ off 8) 0)
            (elf64-set-u64-le! symtab-bv (+ off 16) 0)
            (sec-loop (+ sidx 1)))))
    ;; Write named symbols 7..N
    (let sym-loop ((ms syms-meta))
      (if (pair? ms)
          (let* ((m (car ms))
                 (name (car m))
                 (idx (cadr m))
                 (soff (caddr m))
                 (off (* idx 24))
                 (is-weak? (symbol-map-contains? weak-set name))
                 (is-globl? (or (symbol-map-contains? globl-set name)
                                (not (symbol-map-contains? seen-loc name))))
                 (bind (cond (is-weak? 2) (is-globl? 1) (else 0))) ;; 0=STB_LOCAL, 1=STB_GLOBAL, 2=STB_WEAK
                 (def-hit (symbol-map-get def-map name))
                 (def-val (if def-hit (cdr def-hit) #f))
                 (type-hit (symbol-map-get type-map name))
                 (stt (if type-hit
                          (cdr type-hit)
                          (if (and def-val (eq? (car def-val) 'text))
                              2 ;; STT_FUNC
                              0))) ;; STT_NOTYPE
                 (st-info (+ (* bind 16) stt))
                 (shndx (if def-val (asm-sec->shndx (car def-val)) 0))
                 (st-val (if def-val (cadr def-val) 0)))
            (elf64-set-u32-le! symtab-bv off soff)
            (elf64-set-u8! symtab-bv (+ off 4) st-info)
            (elf64-set-u8! symtab-bv (+ off 5) 0)
            (elf64-set-u16-le! symtab-bv (+ off 6) shndx)
            (elf64-set-u64-le! symtab-bv (+ off 8) st-val)
            (elf64-set-u64-le! symtab-bv (+ off 16) 0)
            (sym-loop (cdr ms)))))
    (list symtab-bv strtab-bv sym-idx-map first-global-idx sym-idx-sm)))

(define (elf64-build-rel-symtab sym-table globl-syms weak-syms sym-types reloc-records)
  (let ((res (elf64-build-rel-symtab-ex sym-table globl-syms weak-syms sym-types reloc-records)))
    (list (car res) (cadr res) (caddr res) (cadddr res))))

(define (elf64-build-rela-section sec-name reloc-records sym-idx-map)
  (let* ((sec-rels (let loop ((rs reloc-records) (acc '()))
                     (if (null? rs)
                         (reverse acc)
                         (if (eq? (caar rs) sec-name)
                             (loop (cdr rs) (cons (car rs) acc))
                             (loop (cdr rs) acc)))))
         (count (length sec-rels))
         (is-sm? (vector? sym-idx-map))
         (bv (make-bytevector (* count 24) 0)))
    (let loop ((rs sec-rels) (i 0))
      (if (pair? rs)
          (let* ((r (car rs))
                 (r-offset (cadr r))
                 (target (caddr r))
                 (r-type (cadddr r))
                 (r-addend (car (cddddr r)))
                 (sym-idx (if (number? target)
                              target
                              (let ((e (if is-sm?
                                           (symbol-map-get sym-idx-map target)
                                           (assoc target sym-idx-map))))
                                (if e (cdr e) 0))))
                 (off (* i 24)))
            (elf64-set-u64-le! bv off r-offset)
            (elf64-set-u32-le! bv (+ off 8) r-type)
            (elf64-set-u32-le! bv (+ off 12) sym-idx)
            (elf64-set-s64-le! bv (+ off 16) r-addend)
            (loop (cdr rs) (+ i 1)))))
    bv))

(define (build-elf64-relocatable assembled)
  (let* ((text-bv (car assembled))
         (rodata-bv (cadr assembled))
         (data-bv (caddr assembled))
         (bss-len (cadddr assembled))
         (init-bv (car (cddddr assembled)))
         (globals-bv (cadr (cddddr assembled)))
         (sym-table (caddr (cddddr assembled)))
         (globl-syms (cadddr (cddddr assembled)))
         (rest8 (cddddr (cddddr assembled)))
         (weak-syms (car rest8))
         (sym-types (cadr rest8))
         (reloc-records (caddr rest8))
         (sym-res (elf64-build-rel-symtab-ex sym-table globl-syms weak-syms sym-types reloc-records))
         (symtab-bv (car sym-res))
         (strtab-bv (cadr sym-res))
         (sym-idx-sm (car (cddddr sym-res)))
         (first-global-idx (cadddr sym-res))
         (rela-text-bv (elf64-build-rela-section 'text reloc-records sym-idx-sm))
         (rela-rodata-bv (elf64-build-rela-section 'rodata reloc-records sym-idx-sm))
         (rela-data-bv (elf64-build-rela-section 'data reloc-records sym-idx-sm))
         (rela-init-bv (elf64-build-rela-section 'init_array reloc-records sym-idx-sm))
         (rela-globals-bv (elf64-build-rela-section 'ulisp_globals_sec reloc-records sym-idx-sm))
         (shstrtab-bv (elf64-make-rel-shstrtab-bytes))
         ;; Compute aligned section offsets
         (text-off 64)
         (text-len (bytevector-length text-bv))
         (rodata-off (elf64-align-up (+ text-off text-len) 8))
         (rodata-len (bytevector-length rodata-bv))
         (data-off (elf64-align-up (+ rodata-off rodata-len) 8))
         (data-len (bytevector-length data-bv))
         (bss-off (elf64-align-up (+ data-off data-len) 8))
         (init-off bss-off)
         (init-len (bytevector-length init-bv))
         (globals-off (elf64-align-up (+ init-off init-len) 8))
         (globals-len (bytevector-length globals-bv))
         (rela-text-off (elf64-align-up (+ globals-off globals-len) 8))
         (rela-text-len (bytevector-length rela-text-bv))
         (rela-rodata-off (elf64-align-up (+ rela-text-off rela-text-len) 8))
         (rela-rodata-len (bytevector-length rela-rodata-bv))
         (rela-data-off (elf64-align-up (+ rela-rodata-off rela-rodata-len) 8))
         (rela-data-len (bytevector-length rela-data-bv))
         (rela-init-off (elf64-align-up (+ rela-data-off rela-data-len) 8))
         (rela-init-len (bytevector-length rela-init-bv))
         (rela-globals-off (elf64-align-up (+ rela-init-off rela-init-len) 8))
         (rela-globals-len (bytevector-length rela-globals-bv))
         (symtab-off (elf64-align-up (+ rela-globals-off rela-globals-len) 8))
         (symtab-len (bytevector-length symtab-bv))
         (strtab-off (elf64-align-up (+ symtab-off symtab-len) 8))
         (strtab-len (bytevector-length strtab-bv))
         (shstrtab-off (elf64-align-up (+ strtab-off strtab-len) 8))
         (shstrtab-len (bytevector-length shstrtab-bv))
         (shoff (elf64-align-up (+ shstrtab-off shstrtab-len) 8))
         (total-len (+ shoff (* 16 64)))
         (elf-bv (make-bytevector total-len 0)))
    ;; Write ELF64 header (ET_REL, 16 sections, shstrndx = 15)
    (elf64-write-rel-ehdr! elf-bv shoff 16 15)
    ;; Copy section payloads
    (if (> text-len 0) (elf64-copy-bytes! elf-bv text-off text-bv 0 text-len))
    (if (> rodata-len 0) (elf64-copy-bytes! elf-bv rodata-off rodata-bv 0 rodata-len))
    (if (> data-len 0) (elf64-copy-bytes! elf-bv data-off data-bv 0 data-len))
    (if (> init-len 0) (elf64-copy-bytes! elf-bv init-off init-bv 0 init-len))
    (if (> globals-len 0) (elf64-copy-bytes! elf-bv globals-off globals-bv 0 globals-len))
    (if (> rela-text-len 0) (elf64-copy-bytes! elf-bv rela-text-off rela-text-bv 0 rela-text-len))
    (if (> rela-rodata-len 0) (elf64-copy-bytes! elf-bv rela-rodata-off rela-rodata-bv 0 rela-rodata-len))
    (if (> rela-data-len 0) (elf64-copy-bytes! elf-bv rela-data-off rela-data-bv 0 rela-data-len))
    (if (> rela-init-len 0) (elf64-copy-bytes! elf-bv rela-init-off rela-init-bv 0 rela-init-len))
    (if (> rela-globals-len 0) (elf64-copy-bytes! elf-bv rela-globals-off rela-globals-bv 0 rela-globals-len))
    (elf64-copy-bytes! elf-bv symtab-off symtab-bv 0 symtab-len)
    (elf64-copy-bytes! elf-bv strtab-off strtab-bv 0 strtab-len)
    (elf64-copy-bytes! elf-bv shstrtab-off shstrtab-bv 0 shstrtab-len)
    ;; Write Section Headers (0..15)
    ;; 0: NULL
    (elf64-write-shdr! elf-bv shoff 0 0 0 0 0 0 0 0 0 0 0)
    ;; 1: .text (SHT_PROGBITS=1, SHF_ALLOC|SHF_EXECINSTR=6)
    (elf64-write-shdr! elf-bv shoff 1 1 1 6 0 text-off text-len 0 0 16 0)
    ;; 2: .rodata (SHT_PROGBITS=1, SHF_ALLOC=2)
    (elf64-write-shdr! elf-bv shoff 2 7 1 2 0 rodata-off rodata-len 0 0 8 0)
    ;; 3: .data (SHT_PROGBITS=1, SHF_WRITE|SHF_ALLOC=3)
    (elf64-write-shdr! elf-bv shoff 3 15 1 3 0 data-off data-len 0 0 8 0)
    ;; 4: .bss (SHT_NOBITS=8, SHF_WRITE|SHF_ALLOC=3)
    (elf64-write-shdr! elf-bv shoff 4 21 8 3 0 bss-off bss-len 0 0 8 0)
    ;; 5: .init_array (SHT_INIT_ARRAY=14, SHF_WRITE|SHF_ALLOC=3)
    (elf64-write-shdr! elf-bv shoff 5 26 14 3 0 init-off init-len 0 0 8 8)
    ;; 6: ulisp_globals_sec (SHT_PROGBITS=1, SHF_WRITE|SHF_ALLOC=3)
    (elf64-write-shdr! elf-bv shoff 6 38 1 3 0 globals-off globals-len 0 0 8 0)
    ;; 7: .rela.text (SHT_RELA=4, SHF_INFO_LINK=64, link=13, info=1)
    (elf64-write-shdr! elf-bv shoff 7 56 4 64 0 rela-text-off rela-text-len 13 1 8 24)
    ;; 8: .rela.rodata (SHT_RELA=4, SHF_INFO_LINK=64, link=13, info=2)
    (elf64-write-shdr! elf-bv shoff 8 67 4 64 0 rela-rodata-off rela-rodata-len 13 2 8 24)
    ;; 9: .rela.data (SHT_RELA=4, SHF_INFO_LINK=64, link=13, info=3)
    (elf64-write-shdr! elf-bv shoff 9 80 4 64 0 rela-data-off rela-data-len 13 3 8 24)
    ;; 10: .rela.init_array (SHT_RELA=4, SHF_INFO_LINK=64, link=13, info=5)
    (elf64-write-shdr! elf-bv shoff 10 91 4 64 0 rela-init-off rela-init-len 13 5 8 24)
    ;; 11: .rela.ulisp_globals_sec (SHT_RELA=4, SHF_INFO_LINK=64, link=13, info=6)
    (elf64-write-shdr! elf-bv shoff 11 108 4 64 0 rela-globals-off rela-globals-len 13 6 8 24)
    ;; 12: .note.GNU-stack (SHT_PROGBITS=1, flags=0)
    (elf64-write-shdr! elf-bv shoff 12 132 1 0 0 symtab-off 0 0 0 1 0)
    ;; 13: .symtab (SHT_SYMTAB=2, flags=0, link=14 (.strtab), info=first-global-idx (first non-local symbol))
    (elf64-write-shdr! elf-bv shoff 13 148 2 0 0 symtab-off symtab-len 14 first-global-idx 8 24)
    ;; 14: .strtab (SHT_STRTAB=3)
    (elf64-write-shdr! elf-bv shoff 14 156 3 0 0 strtab-off strtab-len 0 0 1 0)
    ;; 15: .shstrtab (SHT_STRTAB=3)
    (elf64-write-shdr! elf-bv shoff 15 164 3 0 0 shstrtab-off shstrtab-len 0 0 1 0)
    elf-bv))

;; =======================================================================
;; ELF64 Static Linker Core Engine (--ld) (Issue #784)
;; Conforms to DSN-33 Architecture Specification & AMD64 System V ABI
;; =======================================================================

(define (elf64-get-u8 bv off)
  (bytevector-u8-ref bv off))

(define (elf64-get-u16-le bv off)
  (+ (bytevector-u8-ref bv off)
     (* (bytevector-u8-ref bv (+ off 1)) 256)))

(define (elf64-get-u32-le bv off)
  (+ (+ (+ (bytevector-u8-ref bv off)
           (* (bytevector-u8-ref bv (+ off 1)) 256))
        (* (bytevector-u8-ref bv (+ off 2)) 65536))
     (* (bytevector-u8-ref bv (+ off 3)) 16777216)))

(define *elf64-max-disp32* 2147483647)
(define *elf64-min-disp32* -2147483648)

(define (elf64-get-s32-le bv off)
  (let ((b3 (bytevector-u8-ref bv (+ off 3))))
    (if (>= b3 128)
        (- (elf64-get-u32-le bv off) 4294967296)
        (elf64-get-u32-le bv off))))

(define (elf64-get-u64-le bv off)
  (let ((lo (elf64-get-u32-le bv off))
        (hi (elf64-get-u32-le bv (+ off 4))))
    (+ lo (* hi 4294967296))))

(define (elf64-get-s64-le bv off)
  (let ((lo (elf64-get-u32-le bv off))
        (hi (elf64-get-s32-le bv (+ off 4))))
    (+ lo (* hi 4294967296))))

(define (elf64-read-string-from-strtab bv off)
  (let ((len (bytevector-length bv)))
    (let loop ((i off) (chars '()))
      (if (or (>= i len) (= (bytevector-u8-ref bv i) 0))
          (list->string (reverse chars))
          (loop (+ i 1) (cons (integer->char (bytevector-u8-ref bv i)) chars))))))

(define (elf64-sub-bytevector src off len)
  (let ((dst (make-bytevector len 0)))
    (elf64-copy-bytes! dst 0 src off len)
    dst))

;; String hash and bucket map for O(1) global symbol resolution
(define (elf64-string-hash str)
  (let ((len (string-length str)))
    (let loop ((i 0) (h 5381))
      (if (< i len)
          (loop (+ i 1)
                (modulo (+ (* h 33) (char->integer (string-ref str i))) 1000000007))
          h))))

(define (make-symbol-map size)
  (make-vector size '()))

(define (symbol-map-get sm key)
  (let* ((h (modulo (elf64-string-hash key) (vector-length sm)))
         (bucket (vector-ref sm h)))
    (let loop ((b bucket))
      (cond
        ((null? b) #f)
        ((string=? (caar b) key) (car b))
        (else (loop (cdr b)))))))

(define (symbol-map-contains? sm key)
  (let* ((h (modulo (elf64-string-hash key) (vector-length sm)))
         (bucket (vector-ref sm h)))
    (let loop ((b bucket))
      (cond
        ((null? b) #f)
        ((string=? (caar b) key) #t)
        (else (loop (cdr b)))))))

(define (symbol-map-set! sm key val)
  (let* ((h (modulo (elf64-string-hash key) (vector-length sm)))
         (bucket (vector-ref sm h)))
    (let loop ((b bucket))
      (cond
        ((null? b)
         (vector-set! sm h (cons (cons key val) bucket)))
        ((string=? (caar b) key)
         (set-cdr! (car b) val))
        (else (loop (cdr b)))))))

;; Structured linker error handler cell (cons cell avoids top-level set! in AOT)
(define *elf64-linker-error-handler* (cons #f '()))

(define (elf64-linker-error! code msg detail)
  (let ((h (car *elf64-linker-error-handler*)))
    (if (procedure? h)
        (h code msg detail)
        (begin
          (display-stderr (string-append "ulisp --ld: error [" code "]: " msg
                                         (if (and (string? detail) (> (string-length detail) 0))
                                             (string-append " (" detail ")")
                                             "")
                                         "\n"))
          (compiler-abort-and-cleanup! 1)))))

(define (with-elf64-linker-error-handler handler thunk)
  (let ((prev (car *elf64-linker-error-handler*)))
    (set-car! *elf64-linker-error-handler* handler)
    (let ((res (guard (ex (else
                           (set-car! *elf64-linker-error-handler* prev)
                           (raise ex)))
                 (thunk))))
      (set-car! *elf64-linker-error-handler* prev)
      res)))

(define (elf64-str-starts-with? s prefix)
  (let ((slen (string-length s))
        (plen (string-length prefix)))
    (if (< slen plen)
        #f
        (let loop ((i 0))
          (cond
            ((= i plen) #t)
            ((char=? (string-ref s i) (string-ref prefix i)) (loop (+ i 1)))
            (else #f))))))

(define (elf64-flag-set? flags bit)
  (= (modulo (quotient flags bit) 2) 1))

(define (elf64-set-s64-le! bv off val)
  (let* ((lo (modulo val 4294967296))
         (hi-raw (quotient (- val lo) 4294967296)))
    (elf64-set-u32-le! bv off lo)
    (elf64-set-u32-le! bv (+ off 4) (modulo hi-raw 4294967296))))

(define (elf64-write-binary-file! out-path bv)
  (let ((port (guard (ex (else #f)) (open-binary-output-file out-path))))
    (if (not port)
        (elf64-linker-error! "C99-LNK-003"
                             (string-append "Cannot open output binary file for writing: " out-path)
                             out-path))
    (guard (ex (else
                (guard (ex2 (else #f)) (close-output-port port))
                (elf64-linker-error! "C99-LNK-003"
                                     (string-append "Failed while writing binary file: " out-path)
                                     out-path)))
      (write-bytevector bv port)
      (close-output-port port))
    #t))

;; Portable binary file reader returning raw bytevector (works in Gauche, ILisp, and native ULisp)
(define (read-binary-file-to-bytevector path)
  (let ((port (guard (ex (else #f)) (open-binary-input-file path))))
    (if (not port)
        (elf64-linker-error! "C99-LNK-003"
                             (string-append "Cannot open input object or archive file: " path)
                             path)
        (let ((state (vector (make-bytevector 65536 0) 65536 0)))
          (guard (ex (else
                      (guard (ex2 (else #f)) (close-input-port port))
                      (elf64-linker-error! "C99-LNK-003"
                                           (string-append "Error reading binary file: " path)
                                           path)))
            (let loop ()
              (let ((b (read-u8 port)))
                (if (eof-object? b)
                    (let* ((buf (vector-ref state 0))
                           (len (vector-ref state 2))
                           (out (make-bytevector len 0)))
                      (close-input-port port)
                      (elf64-copy-bytes! out 0 buf 0 len)
                      out)
                    (let ((buf (vector-ref state 0))
                          (cap (vector-ref state 1))
                          (len (vector-ref state 2)))
                      (if (>= len cap)
                          (let* ((new-cap (* cap 2))
                                 (new-buf (make-bytevector new-cap 0)))
                            (elf64-copy-bytes! new-buf 0 buf 0 len)
                            (vector-set! state 0 new-buf)
                            (vector-set! state 1 new-cap)
                            (bytevector-u8-set! new-buf len b)
                            (vector-set! state 2 (+ len 1)))
                          (begin
                            (bytevector-u8-set! buf len b)
                            (vector-set! state 2 (+ len 1))))
                      (loop))))))))))

(define (elf64-has-elf-magic? bv)
  (and (>= (bytevector-length bv) 16)
       (= (elf64-get-u8 bv 0) 127)
       (= (elf64-get-u8 bv 1) 69)
       (= (elf64-get-u8 bv 2) 76)
       (= (elf64-get-u8 bv 3) 70)))

;; Parse an ELF64 ET_REL relocatable object file into structured vectors
;; Returns: (vector path sec-vec sym-vec relocs)
(define (elf64-parse-relocatable-object bv path)
  (let ((blen (bytevector-length bv)))
    (if (< blen 64)
        (elf64-linker-error! "C99-LNK-003"
                             (string-append "File too small for ELF64 header: " path)
                             path))
    (if (not (and (= (elf64-get-u8 bv 0) 127)
                  (= (elf64-get-u8 bv 1) 69)
                  (= (elf64-get-u8 bv 2) 76)
                  (= (elf64-get-u8 bv 3) 70)
                  (= (elf64-get-u8 bv 4) 2)    ;; ELFCLASS64
                  (= (elf64-get-u8 bv 5) 1)    ;; ELFDATA2LSB
                  (= (elf64-get-u16-le bv 16) 1)   ;; e_type == ET_REL
                  (= (elf64-get-u16-le bv 18) 62))) ;; e_machine == EM_X86_64
        (elf64-linker-error! "C99-LNK-003"
                             (string-append path " is not an x86-64 ELF64 relocatable object (ET_REL)")
                             path))
    (let* ((e-shoff (elf64-get-u64-le bv 40))
           (e-shentsize (elf64-get-u16-le bv 58))
           (e-shnum (elf64-get-u16-le bv 60))
           (e-shstrndx (elf64-get-u16-le bv 62)))
      (if (or (< e-shentsize 64)
              (= e-shnum 0)
              (< e-shoff 0)
              (> (+ e-shoff (* e-shnum e-shentsize)) blen)
              (>= e-shstrndx e-shnum))
          (elf64-linker-error! "C99-LNK-003"
                               (string-append "Malformed ELF64 section header table in: " path)
                               path))
      (let* ((shstr-shdr-off (+ e-shoff (* e-shstrndx e-shentsize)))
             (shstr-file-off (elf64-get-u64-le bv (+ shstr-shdr-off 24)))
             (shstr-size (elf64-get-u64-le bv (+ shstr-shdr-off 32))))
        (if (or (< shstr-file-off 0) (> (+ shstr-file-off shstr-size) blen))
            (elf64-linker-error! "C99-LNK-003"
                                 (string-append "Out-of-bounds .shstrtab section in: " path)
                                 path))
        (let ((shstrtab-bv (elf64-sub-bytevector bv shstr-file-off shstr-size)))
          (let loop-shdr ((idx 0) (sections '()))
            (if (< idx e-shnum)
                (let* ((shdr-off (+ e-shoff (* idx e-shentsize)))
                       (sh-name-idx (elf64-get-u32-le bv shdr-off))
                       (sec-name (elf64-read-string-from-strtab shstrtab-bv sh-name-idx))
                       (sh-type (elf64-get-u32-le bv (+ shdr-off 4)))
                       (sh-flags (elf64-get-u64-le bv (+ shdr-off 8)))
                       (sh-addr (elf64-get-u64-le bv (+ shdr-off 16)))
                       (sh-offset (elf64-get-u64-le bv (+ shdr-off 24)))
                       (sh-size (elf64-get-u64-le bv (+ shdr-off 32)))
                       (sh-link (elf64-get-u32-le bv (+ shdr-off 40)))
                       (sh-info (elf64-get-u32-le bv (+ shdr-off 44)))
                       (sh-align (elf64-get-u64-le bv (+ shdr-off 48))))
                  (if (and (> sh-size 0) (not (= sh-type 8))
                           (or (< sh-offset 0) (> (+ sh-offset sh-size) blen)))
                      (elf64-linker-error! "C99-LNK-003"
                                           (string-append "Out-of-bounds section `" sec-name "` in: " path)
                                           path))
                  (let ((data-bv (if (and (> sh-size 0) (not (= sh-type 8)))
                                     (elf64-sub-bytevector bv sh-offset sh-size)
                                     (make-bytevector 0 0))))
                    (loop-shdr (+ idx 1)
                               (cons (vector idx sec-name sh-type sh-flags sh-size
                                             (if (< sh-align 1) 1 sh-align)
                                             sh-link sh-info data-bv)
                                     sections))))
                (let* ((sec-vec (list->vector (reverse sections)))
                       (symtab-sec (let find-sym ((i 0))
                                     (if (< i (vector-length sec-vec))
                                         (let ((s (vector-ref sec-vec i)))
                                           (if (= (vector-ref s 2) 2) s (find-sym (+ i 1))))
                                         #f)))
                       (symtab-bv (if symtab-sec (vector-ref symtab-sec 8) (make-bytevector 0 0)))
                       (strtab-idx (if symtab-sec (vector-ref symtab-sec 6) 0))
                       (strtab-sec (if (and (>= strtab-idx 0) (< strtab-idx (vector-length sec-vec)))
                                       (vector-ref sec-vec strtab-idx)
                                       #f))
                       (strtab-bv (if strtab-sec (vector-ref strtab-sec 8) (make-bytevector 0 0)))
                       (sym-count (quotient (bytevector-length symtab-bv) 24))
                       (sym-vec (make-vector sym-count #f)))
                  (let loop-sym ((k 0))
                    (if (< k sym-count)
                        (let* ((sym-off (* k 24))
                               (st-name (elf64-get-u32-le symtab-bv sym-off))
                               (sym-name (elf64-read-string-from-strtab strtab-bv st-name))
                               (st-info (elf64-get-u8 symtab-bv (+ sym-off 4)))
                               (st-bind (quotient st-info 16))
                               (st-type (modulo st-info 16))
                               (st-other (elf64-get-u8 symtab-bv (+ sym-off 5)))
                               (st-shndx (elf64-get-u16-le symtab-bv (+ sym-off 6)))
                               (st-value (elf64-get-u64-le symtab-bv (+ sym-off 8)))
                               (st-size (elf64-get-u64-le symtab-bv (+ sym-off 16))))
                          (vector-set! sym-vec k (vector k sym-name st-bind st-type st-shndx st-value st-size))
                          (loop-sym (+ k 1)))))
                  (let loop-rela ((s-idx 0) (all-relocs '()))
                    (if (< s-idx (vector-length sec-vec))
                        (let* ((s (vector-ref sec-vec s-idx))
                               (stype (vector-ref s 2)))
                          (if (= stype 4) ;; SHT_RELA
                              (let* ((target-shndx (vector-ref s 7))
                                     (target-sec (if (and (>= target-shndx 0) (< target-shndx (vector-length sec-vec)))
                                                     (vector-ref sec-vec target-shndx)
                                                     #f))
                                     (target-sec-name (if target-sec (vector-ref target-sec 1) ""))
                                     (rela-bv (vector-ref s 8))
                                     (rela-count (quotient (bytevector-length rela-bv) 24)))
                                (let inner ((r-idx 0) (acc all-relocs))
                                  (if (< r-idx rela-count)
                                      (let* ((off (* r-idx 24))
                                             (r-offset (elf64-get-u64-le rela-bv off))
                                             (r-info (elf64-get-u64-le rela-bv (+ off 8)))
                                             (r-addend (elf64-get-s64-le rela-bv (+ off 16)))
                                             (sym-idx (quotient r-info 4294967296))
                                             (r-type (modulo r-info 4294967296)))
                                        (inner (+ r-idx 1)
                                               (cons (vector target-shndx target-sec-name r-offset r-type sym-idx r-addend)
                                                     acc)))
                                      (loop-rela (+ s-idx 1) acc))))
                              (loop-rela (+ s-idx 1) all-relocs)))
                        (vector path sec-vec sym-vec (reverse all-relocs))))))))))))

;; -----------------------------------------------------------------------
;; Unix ar Archive Parser & On-Demand Archive Indexer (CWE-125 Safe)
;; -----------------------------------------------------------------------

(define (elf64-ar-archive? bv)
  (and (>= (bytevector-length bv) 8)
       (= (bytevector-u8-ref bv 0) 33)   ;; !
       (= (bytevector-u8-ref bv 1) 60)   ;; <
       (= (bytevector-u8-ref bv 2) 97)   ;; a
       (= (bytevector-u8-ref bv 3) 114)  ;; r
       (= (bytevector-u8-ref bv 4) 99)   ;; c
       (= (bytevector-u8-ref bv 5) 104)  ;; h
       (= (bytevector-u8-ref bv 6) 62)   ;; >
       (= (bytevector-u8-ref bv 7) 10))) ;; \n

(define (elf64-ar-read-trimmed-field bv off len)
  (let loop-end ((end (+ off len)))
    (if (<= end off)
        ""
        (let ((b (bytevector-u8-ref bv (- end 1))))
          (if (= b 32)
              (loop-end (- end 1))
              (let loop-chars ((i off) (chars '()))
                (if (< i end)
                    (loop-chars (+ i 1) (cons (integer->char (bytevector-u8-ref bv i)) chars))
                    (list->string (reverse chars)))))))))

(define (elf64-ar-parse-decimal str path)
  (let ((len (string-length str)))
    (if (= len 0)
        (elf64-linker-error! "C99-LNK-003"
                             (string-append "Empty ar member size field in: " path)
                             path))
    (let loop ((i 0) (acc 0))
      (if (< i len)
          (let ((c (char->integer (string-ref str i))))
            (if (or (< c 48) (> c 57))
                (elf64-linker-error! "C99-LNK-003"
                                     (string-append "Invalid ar member size `" str "` in: " path)
                                     path)
                (loop (+ i 1) (+ (* acc 10) (- c 48)))))
          acc))))

(define (elf64-ar-read-longname strtab-bv off path)
  (if (not strtab-bv)
      (elf64-linker-error! "C99-LNK-003"
                           (string-append "GNU long ar filename without // table in: " path)
                           path))
  (let ((len (bytevector-length strtab-bv)))
    (if (or (< off 0) (>= off len))
        (elf64-linker-error! "C99-LNK-003"
                             (string-append "Out-of-bounds GNU long ar filename offset in: " path)
                             path))
    (let loop ((i off) (chars '()))
      (if (>= i len)
          (list->string (reverse chars))
          (let ((b (bytevector-u8-ref strtab-bv i)))
            (if (or (= b 0) (= b 10) (= b 47))
                (list->string (reverse chars))
                (loop (+ i 1) (cons (integer->char b) chars))))))))

(define (elf64-ar-resolve-member-name raw-name strtab-bv path)
  (let ((nlen (string-length raw-name)))
    (cond
      ((or (string=? raw-name "/")
           (string=? raw-name "//")
           (string=? raw-name "/SYM64/")
           (string=? raw-name "__.SYMDEF")
           (string=? raw-name "__.SYMDEF SORTED"))
       raw-name)
      ((and (> nlen 1)
            (char=? (string-ref raw-name 0) #\/)
            (let ((c1 (char->integer (string-ref raw-name 1))))
              (and (>= c1 48) (<= c1 57))))
       (let ((off (elf64-ar-parse-decimal (substring raw-name 1 nlen) path)))
         (elf64-ar-read-longname strtab-bv off path)))
      ((and (> nlen 0) (char=? (string-ref raw-name (- nlen 1)) #\/))
       (substring raw-name 0 (- nlen 1)))
      (else raw-name))))

;; Extract archive record: (vector 'ar-archive path members-vec sym->member-idx extracted-vec)
(define (elf64-parse-ar-archive path bv)
  (if (not (elf64-ar-archive? bv))
      (elf64-linker-error! "C99-LNK-003"
                           (string-append "Invalid Unix ar archive magic in: " path)
                           path))
  (let ((blen (bytevector-length bv))
        (strtab-box (cons #f '())))
    (let loop ((pos 8) (members '()))
      (if (>= pos blen)
          (let* ((members-vec (list->vector (reverse members)))
                 (mcount (vector-length members-vec))
                 (sym->idx (make-symbol-map (let ((sz (* mcount 8))) (if (< sz 256) 256 sz))))
                 (extracted-vec (make-vector mcount #f)))
            ;; Index defined global/weak symbols directly from each ELF member
            ;; Handles GNU '/', '/SYM64/', BSD '__.SYMDEF', AND symbol-table-less 'ar rcS' uniformly.
            (let idx-loop ((m 0))
              (if (< m mcount)
                  (let* ((entry (vector-ref members-vec m))
                         (m-name (vector-ref entry 0))
                         (m-bv (vector-ref entry 1))
                         (obj (elf64-parse-relocatable-object m-bv (string-append path "(" m-name ")"))))
                    (vector-set! entry 2 obj)
                    (let* ((sym-vec (vector-ref obj 2))
                           (scount (vector-length sym-vec)))
                      (let s-loop ((k 0))
                        (if (< k scount)
                            (let* ((sym (vector-ref sym-vec k))
                                   (s-name (vector-ref sym 1))
                                   (s-bind (vector-ref sym 2))
                                   (s-shndx (vector-ref sym 4)))
                              (if (and (> (string-length s-name) 0)
                                       (or (= s-bind 1) (= s-bind 2))
                                       (not (= s-shndx 0))
                                       (not (symbol-map-contains? sym->idx s-name)))
                                  (symbol-map-set! sym->idx s-name m))
                              (s-loop (+ k 1))))))
                    (idx-loop (+ m 1)))))
            (vector 'ar-archive path members-vec sym->idx extracted-vec))
          (begin
            (if (> (+ pos 60) blen)
                (elf64-linker-error! "C99-LNK-003"
                                     (string-append "Truncated ar member header in: " path)
                                     path))
            (if (not (and (= (bytevector-u8-ref bv (+ pos 58)) 96)
                          (= (bytevector-u8-ref bv (+ pos 59)) 10)))
                (elf64-linker-error! "C99-LNK-003"
                                     (string-append "Corrupt ar header trailer in: " path)
                                     path))
            (let* ((raw-name (elf64-ar-read-trimmed-field bv pos 16))
                   (size-str (elf64-ar-read-trimmed-field bv (+ pos 48) 10))
                   (m-size (elf64-ar-parse-decimal size-str path))
                   (data-start (+ pos 60))
                   (data-end (+ data-start m-size)))
              (if (> data-end blen)
                  (elf64-linker-error! "C99-LNK-003"
                                       (string-append "Out-of-bounds ar member payload (" raw-name ") in: " path)
                                       path))
              (let ((next-pos (elf64-align-up data-end 2)))
                (cond
                  ((string=? raw-name "//")
                   (set-car! strtab-box (elf64-sub-bytevector bv data-start m-size))
                   (loop next-pos members))
                  ((or (string=? raw-name "/")
                       (string=? raw-name "/SYM64/")
                       (string=? raw-name "__.SYMDEF")
                       (string=? raw-name "__.SYMDEF SORTED"))
                   (loop next-pos members))
                  (else
                   (let* ((m-name (elf64-ar-resolve-member-name raw-name (car strtab-box) path))
                          (m-bv (elf64-sub-bytevector bv data-start m-size)))
                     (if (elf64-has-elf-magic? m-bv)
                         (loop next-pos (cons (vector m-name m-bv #f) members))
                         (loop next-pos members))))))))))))

(define (elf64-synthetic-symbol-name? name)
  (or (string=? name "__init_array_start")
      (string=? name "__init_array_end")
      (string=? name "__fini_array_start")
      (string=? name "__fini_array_end")
      (string=? name "__preinit_array_start")
      (string=? name "__preinit_array_end")
      (string=? name "__start_ulisp_globals_sec")
      (string=? name "__stop_ulisp_globals_sec")
      (string=? name "__bss_start")
      (string=? name "_edata")
      (string=? name "_end")
      (string=? name "__ehdr_start")
      (string=? name "_DYNAMIC")
      (string=? name "_GLOBAL_OFFSET_TABLE_")))

(define (elf64-obj-collect-defined-into! obj def-map)
  (let* ((sym-vec (vector-ref obj 2))
         (scount (vector-length sym-vec)))
    (let loop ((k 0))
      (if (< k scount)
          (let* ((sym (vector-ref sym-vec k))
                 (s-name (vector-ref sym 1))
                 (s-bind (vector-ref sym 2))
                 (s-shndx (vector-ref sym 4)))
            (if (and (> (string-length s-name) 0)
                     (or (= s-bind 1) (= s-bind 2))
                     (not (= s-shndx 0)))
                (symbol-map-set! def-map s-name #t))
            (loop (+ k 1)))))))

(define (elf64-obj-collect-strong-undefs obj)
  (let* ((sym-vec (vector-ref obj 2))
         (relocs (vector-ref obj 3))
         (scount (vector-length sym-vec)))
    (let loop ((rs relocs) (acc '()))
      (if (null? rs)
          acc
          (let* ((r (car rs))
                 (sym-idx (vector-ref r 4)))
            (if (and (>= sym-idx 0) (< sym-idx scount))
                (let* ((sym (vector-ref sym-vec sym-idx))
                       (s-name (vector-ref sym 1))
                       (s-bind (vector-ref sym 2))
                       (s-shndx (vector-ref sym 4)))
                  (if (and (= s-shndx 0)
                           (= s-bind 1) ;; STB_GLOBAL only (weak undef MUST NOT pull archive members)
                           (> (string-length s-name) 0)
                           (not (elf64-synthetic-symbol-name? s-name)))
                      (loop (cdr rs) (cons s-name acc))
                      (loop (cdr rs) acc)))
                (loop (cdr rs) acc)))))))

(define (elf64-load-and-resolve-inputs inputs entry-sym)
  (let ((def-map (make-symbol-map 8192)))
    (let load-loop ((xs inputs)
                    (direct-acc '())
                    (arch-acc '())
                    (total-ar-members 0))
      (if (pair? xs)
          (let* ((p (car xs))
                 (is-bv? (bytevector? p))
                 (bv (if is-bv? p (read-binary-file-to-bytevector p)))
                 (label (if is-bv? "<memory>" p)))
            (if (elf64-ar-archive? bv)
                (let ((ar (elf64-parse-ar-archive label bv)))
                  (load-loop (cdr xs)
                             direct-acc
                             (cons ar arch-acc)
                             (+ total-ar-members (vector-length (vector-ref ar 2)))))
                (let ((obj (elf64-parse-relocatable-object bv (if is-bv? "<memory.o>" p))))
                  (elf64-obj-collect-defined-into! obj def-map)
                  (load-loop (cdr xs)
                             (cons obj direct-acc)
                             arch-acc
                             total-ar-members))))
          (let* ((direct-objs (reverse direct-acc))
                 (archives (reverse arch-acc))
                 (entry-name (if entry-sym entry-sym "_start"))
                 (max-iters (+ 10000 total-ar-members))
                 (init-undefs
                  (let loop-u ((os direct-objs)
                               (q (if (and (not (symbol-map-contains? def-map entry-name))
                                           (not (elf64-synthetic-symbol-name? entry-name)))
                                      (list entry-name)
                                      '())))
                    (if (null? os)
                        q
                        (loop-u (cdr os) (append (elf64-obj-collect-strong-undefs (car os)) q))))))
            ;; On-demand bounded fixed-point archive extraction (CWE-400 safe)
            (if (null? archives)
                direct-objs
                (let fix-loop ((iter 0) (loaded direct-objs) (undef-q init-undefs))
                  (if (> iter max-iters)
                      (elf64-linker-error! "C99-LNK-003"
                                           "Archive symbol resolution exceeded iteration bound"
                                           ""))
                  (let ((cur-undefs
                         (let filter-u ((us undef-q) (seen '()) (out '()))
                           (cond
                             ((null? us) (reverse out))
                             ((or (symbol-map-contains? def-map (car us))
                                  (member (car us) seen))
                              (filter-u (cdr us) seen out))
                             (else
                              (filter-u (cdr us) (cons (car us) seen) (cons (car us) out)))))))
                    (if (null? cur-undefs)
                        loaded
                        (let sym-loop ((us cur-undefs) (extracted? #f) (new-undefs '()) (added-objs '()))
                          (if (pair? us)
                              (let ((sym-name (car us)))
                                (if (symbol-map-contains? def-map sym-name)
                                    (sym-loop (cdr us) extracted? new-undefs added-objs)
                                    (let ar-loop ((ars archives))
                                      (if (pair? ars)
                                          (let* ((ar (car ars))
                                                 (sym->idx (vector-ref ar 3))
                                                 (hit (symbol-map-get sym->idx sym-name)))
                                            (if hit
                                                (let* ((m-idx (cdr hit))
                                                       (extracted-vec (vector-ref ar 4)))
                                                  (if (vector-ref extracted-vec m-idx)
                                                      (sym-loop (cdr us) extracted? new-undefs added-objs)
                                                      (let* ((entry (vector-ref (vector-ref ar 2) m-idx))
                                                             (obj (vector-ref entry 2)))
                                                        (vector-set! extracted-vec m-idx #t)
                                                        (elf64-obj-collect-defined-into! obj def-map)
                                                        (sym-loop (cdr us) #t
                                                                  (append (elf64-obj-collect-strong-undefs obj) new-undefs)
                                                                  (cons obj added-objs)))))
                                                (ar-loop (cdr ars))))
                                          (sym-loop (cdr us) extracted? new-undefs added-objs)))))
                              (let ((next-loaded (append loaded (reverse added-objs))))
                                (if extracted?
                                    (fix-loop (+ iter 1) next-loaded (append cur-undefs new-undefs))
                                    next-loaded)))))))))))))

(define (elf64-classify-section sec)
  (let* ((sec-name (vector-ref sec 1))
         (sh-type (vector-ref sec 2))
         (sh-flags (vector-ref sec 3))
         (sh-size (vector-ref sec 4))
         (alloc? (elf64-flag-set? sh-flags 2)))
    (cond
      ((or (= sh-type 0) (not alloc?)) #f)
      ((and (= sh-size 0)
            (not (string=? sec-name ".text"))
            (not (string=? sec-name ".rodata"))
            (not (string=? sec-name ".data"))
            (not (string=? sec-name ".bss"))
            (not (string=? sec-name ".init_array"))
            (not (string=? sec-name ".fini_array"))
            (not (string=? sec-name "ulisp_globals_sec")))
       #f)
      ((elf64-flag-set? sh-flags 1024) ;; SHF_TLS
       (if (= sh-type 8) 'tbss 'tdata))
      ((or (string=? sec-name ".init_array")
           (elf64-str-starts-with? sec-name ".init_array."))
       'init_array)
      ((or (string=? sec-name ".fini_array")
           (elf64-str-starts-with? sec-name ".fini_array."))
       'fini_array)
      ((string=? sec-name "ulisp_globals_sec")
       'ulisp_globals)
      ((elf64-flag-set? sh-flags 4) ;; SHF_EXECINSTR
       'text)
      ((not (elf64-flag-set? sh-flags 1)) ;; read-only SHF_ALLOC
       'rodata)
      ((= sh-type 8) ;; SHT_NOBITS
       'bss)
      ((or (string=? sec-name ".data.rel.ro")
           (elf64-str-starts-with? sec-name ".data.rel.ro."))
       'relro)
      (else 'data))))

(define (elf64-write-phdr-base! bv off p-type flags file-off vaddr)
  (elf64-set-u32-le! bv off p-type)
  (elf64-set-u32-le! bv (+ off 4) flags)
  (elf64-set-u64-le! bv (+ off 8) file-off)
  (elf64-set-u64-le! bv (+ off 16) vaddr)
  (elf64-set-u64-le! bv (+ off 24) vaddr))

(define (elf64-write-phdr-sizes! bv off filesz memsz align)
  (elf64-set-u64-le! bv (+ off 32) filesz)
  (elf64-set-u64-le! bv (+ off 40) memsz)
  (elf64-set-u64-le! bv (+ off 48) align))

(define (elf64-write-ehdr-ex! bv entry-vaddr phoff phnum)
  (elf64-set-u8! bv 0 127)
  (elf64-set-u8! bv 1 69)
  (elf64-set-u8! bv 2 76)
  (elf64-set-u8! bv 3 70)
  (elf64-set-u8! bv 4 2)    ;; ELFCLASS64
  (elf64-set-u8! bv 5 1)    ;; ELFDATA2LSB
  (elf64-set-u8! bv 6 1)    ;; EV_CURRENT
  (elf64-set-u8! bv 7 0)    ;; ELFOSABI_NONE
  (elf64-set-u8! bv 8 0)
  (elf64-set-u16-le! bv 16 2)  ;; e_type = ET_EXEC (2)
  (elf64-set-u16-le! bv 18 62) ;; e_machine = EM_X86_64 (62)
  (elf64-set-u32-le! bv 20 1)  ;; e_version = 1
  (elf64-set-u64-le! bv 24 entry-vaddr)
  (elf64-set-u64-le! bv 32 phoff)
  (elf64-set-u64-le! bv 40 0)
  (elf64-set-u32-le! bv 48 0)
  (elf64-set-u16-le! bv 52 64) ;; e_ehsize = 64
  (elf64-set-u16-le! bv 54 56) ;; e_phentsize = 56
  (elf64-set-u16-le! bv 56 phnum)
  (elf64-set-u16-le! bv 58 64) ;; e_shentsize = 64
  (elf64-set-u16-le! bv 60 0)
  (elf64-set-u16-le! bv 62 0))

;; Main Static Linker Procedure: Links ELF64 ET_REL objects & ar archives (.a) into an ET_EXEC binary
(define (link-elf64-relocatable-objects obj-paths entry-sym)
  (if (null? obj-paths)
      (elf64-linker-error! "C99-LNK-001" "No input object files specified" ""))
  (let* ((parsed-list (elf64-load-and-resolve-inputs obj-paths entry-sym))
         (parsed-vec (list->vector parsed-list))
         (obj-count (vector-length parsed-vec))
         ;; Classify all sections once and compute bucket layout offsets
         (obj-buckets-vec (make-vector obj-count #f))
         (placements-vec (make-vector obj-count #f))
         (max-tls-align-box (cons 1 '()))
         (max-bss-align-box (cons 8 '())))
    ;; Pass 0: Collect sections per bucket with per-section alignment
    (let loop-classify ((oi 0)
                        (text-cur 0)
                        (rodata-cur 0)
                        (tdata-cur 0)
                        (tbss-cur 0)
                        (init-cur 0)
                        (fini-cur 0)
                        (relro-cur 0)
                        (data-cur 0)
                        (globals-cur 0)
                        (bss-cur 0))
      (if (< oi obj-count)
          (let* ((obj (vector-ref parsed-vec oi))
                 (sec-vec (vector-ref obj 1))
                 (scount (vector-length sec-vec))
                 (sec-info-vec (make-vector scount #f)))
            (vector-set! obj-buckets-vec oi sec-info-vec)
            (vector-set! placements-vec oi (make-vector scount #f))
            (let loop-sec ((si 0)
                           (t text-cur) (r rodata-cur) (td tdata-cur) (tb tbss-cur)
                           (ia init-cur) (fa fini-cur) (rr relro-cur) (d data-cur)
                           (g globals-cur) (b bss-cur))
              (if (< si scount)
                  (let* ((sec (vector-ref sec-vec si))
                         (bucket (elf64-classify-section sec))
                         (sz (vector-ref sec 4))
                         (raw-al (vector-ref sec 5))
                         (al (if (< raw-al 1) 1 raw-al)))
                    (cond
                      ((not bucket)
                       (loop-sec (+ si 1) t r td tb ia fa rr d g b))
                      ((eq? bucket 'text)
                       (let* ((eff-al (if (< al 16) 16 al))
                              (off (elf64-align-up t eff-al)))
                         (vector-set! sec-info-vec si (vector bucket off sz al))
                         (loop-sec (+ si 1) (+ off sz) r td tb ia fa rr d g b)))
                      ((eq? bucket 'rodata)
                       (let* ((eff-al (if (< al 8) 8 al))
                              (off (elf64-align-up r eff-al)))
                         (vector-set! sec-info-vec si (vector bucket off sz al))
                         (loop-sec (+ si 1) t (+ off sz) td tb ia fa rr d g b)))
                      ((eq? bucket 'tdata)
                       (if (> al (car max-tls-align-box)) (set-car! max-tls-align-box al))
                       (let ((off (elf64-align-up td al)))
                         (vector-set! sec-info-vec si (vector bucket off sz al))
                         (loop-sec (+ si 1) t r (+ off sz) tb ia fa rr d g b)))
                      ((eq? bucket 'tbss)
                       (if (> al (car max-tls-align-box)) (set-car! max-tls-align-box al))
                       (let ((off (elf64-align-up tb al)))
                         (vector-set! sec-info-vec si (vector bucket off sz al))
                         (loop-sec (+ si 1) t r td (+ off sz) ia fa rr d g b)))
                      ((eq? bucket 'init_array)
                       (let* ((eff-al (if (< al 8) 8 al))
                              (off (elf64-align-up ia eff-al)))
                         (vector-set! sec-info-vec si (vector bucket off sz al))
                         (loop-sec (+ si 1) t r td tb (+ off sz) fa rr d g b)))
                      ((eq? bucket 'fini_array)
                       (let* ((eff-al (if (< al 8) 8 al))
                              (off (elf64-align-up fa eff-al)))
                         (vector-set! sec-info-vec si (vector bucket off sz al))
                         (loop-sec (+ si 1) t r td tb ia (+ off sz) rr d g b)))
                      ((eq? bucket 'relro)
                       (let* ((eff-al (if (< al 8) 8 al))
                              (off (elf64-align-up rr eff-al)))
                         (vector-set! sec-info-vec si (vector bucket off sz al))
                         (loop-sec (+ si 1) t r td tb ia fa (+ off sz) d g b)))
                      ((eq? bucket 'data)
                       (let* ((eff-al (if (< al 8) 8 al))
                              (off (elf64-align-up d eff-al)))
                         (vector-set! sec-info-vec si (vector bucket off sz al))
                         (loop-sec (+ si 1) t r td tb ia fa rr (+ off sz) g b)))
                      ((eq? bucket 'ulisp_globals)
                       (let* ((eff-al (if (< al 8) 8 al))
                              (off (elf64-align-up g eff-al)))
                         (vector-set! sec-info-vec si (vector bucket off sz al))
                         (loop-sec (+ si 1) t r td tb ia fa rr d (+ off sz) b)))
                      ((eq? bucket 'bss)
                       (if (> al (car max-bss-align-box)) (set-car! max-bss-align-box al))
                       (let* ((eff-al (if (< al 8) 8 al))
                              (off (elf64-align-up b eff-al)))
                         (vector-set! sec-info-vec si (vector bucket off sz al))
                         (loop-sec (+ si 1) t r td tb ia fa rr d g (+ off sz))))
                      (else
                       (loop-sec (+ si 1) t r td tb ia fa rr d g b))))
                  (loop-classify (+ oi 1) t r td tb ia fa rr d g b))))
          ;; Layout computed! Now scan symbols for SHN_COMMON, global definitions, and .got slots
          (let* ((tdata-len tdata-cur)
                 (tbss-len tbss-cur)
                 (has-tls? (or (> tdata-len 0) (> tbss-len 0)))
                 (tls-align (car max-tls-align-box))
                 (tbss-start-in-tls (elf64-align-up tdata-len tls-align))
                 (tls-memsz (if has-tls? (+ tbss-start-in-tls tbss-len) 0))
                 (tls-aligned-size (if has-tls? (elf64-align-up tls-memsz tls-align) 0))
                 ;; Pre-scan GOT slots across relocations (types 9, 41, 42)
                 (got-map (make-symbol-map 1024))
                 (got-list-box (cons '() '()))
                 (got-count-box (cons 0 '())))
            (let loop-got-o ((oi 0))
              (if (< oi obj-count)
                  (let* ((obj (vector-ref parsed-vec oi))
                         (sym-vec (vector-ref obj 2))
                         (scount (vector-length sym-vec))
                         (relocs (vector-ref obj 3)))
                    (let loop-got-r ((rs relocs))
                      (if (pair? rs)
                          (let* ((r (car rs))
                                 (rt (vector-ref r 3)))
                            (if (or (= rt 9) (= rt 41) (= rt 42))
                                (let* ((si (vector-ref r 4)))
                                  (if (and (>= si 0) (< si scount))
                                      (let* ((sym (vector-ref sym-vec si))
                                             (s-name (vector-ref sym 1))
                                             (s-bind (vector-ref sym 2))
                                             (key (if (= s-bind 0)
                                                      (string-append "__got_local#" (number->string oi) "#" (number->string si))
                                                      s-name)))
                                        (if (not (symbol-map-contains? got-map key))
                                            (let ((slot (car got-count-box)))
                                              (symbol-map-set! got-map key slot)
                                              (set-car! got-list-box (cons (vector key oi si s-bind s-name) (car got-list-box)))
                                              (set-car! got-count-box (+ slot 1))))))))
                            (loop-got-r (cdr rs)))))
                    (loop-got-o (+ oi 1)))))
            ;; First pass over global symbols to collect SHN_COMMON sizes/alignments
            (let ((global-syms (make-symbol-map 8192))
                  (common-names-box (cons '() '())))
              (let loop-pre-o ((oi 0))
                (if (< oi obj-count)
                    (let* ((obj (vector-ref parsed-vec oi))
                           (path (vector-ref obj 0))
                           (sym-vec (vector-ref obj 2))
                           (scount (vector-length sym-vec)))
                      (let loop-pre-s ((k 0))
                        (if (< k scount)
                            (let* ((sym (vector-ref sym-vec k))
                                   (s-name (vector-ref sym 1))
                                   (s-bind (vector-ref sym 2))
                                   (s-shndx (vector-ref sym 4))
                                   (s-val (vector-ref sym 5))
                                   (s-sz (vector-ref sym 6)))
                              (if (and (> (string-length s-name) 0)
                                       (or (= s-bind 1) (= s-bind 2)))
                                  (cond
                                    ((= s-shndx 65522) ;; SHN_COMMON
                                     (let ((cur (symbol-map-get global-syms s-name)))
                                       (cond
                                         ((not cur)
                                          (set-car! common-names-box (cons s-name (car common-names-box)))
                                          (symbol-map-set! global-syms s-name
                                                           (vector 'common s-bind s-val s-sz path 0 #f)))
                                         ((eq? (vector-ref (cdr cur) 0) 'common)
                                          (let ((rec (cdr cur)))
                                            (if (> s-sz (vector-ref rec 3)) (vector-set! rec 3 s-sz))
                                            (if (> s-val (vector-ref rec 2)) (vector-set! rec 2 s-val))))
                                         (else #t)))) ;; already defined strong/weak
                                    ((not (= s-shndx 0)) ;; defined non-common
                                     (let ((cur (symbol-map-get global-syms s-name)))
                                       (if (and cur (eq? (vector-ref (cdr cur) 0) 'common) (= s-bind 1))
                                           (symbol-map-set! global-syms s-name (vector 'pre-strong s-bind 0 0 path 0 #f)))))))
                              (loop-pre-s (+ k 1)))))
                      (loop-pre-o (+ oi 1)))))
              ;; Compute total SHN_COMMON bytes inside .bss bucket
              (let* ((common-allocs-box (cons '() '()))
                     (total-bss-len
                      (let loop-c ((cs (reverse (car common-names-box))) (b-off bss-cur))
                        (if (null? cs)
                            b-off
                            (let* ((cname (car cs))
                                   (hit (symbol-map-get global-syms cname))
                                   (rec (and hit (cdr hit))))
                              (if (and rec (eq? (vector-ref rec 0) 'common))
                                  (let* ((c-al (let ((a (vector-ref rec 2))) (if (< a 1) 1 a)))
                                         (c-sz (vector-ref rec 3))
                                         (aligned (elf64-align-up b-off c-al)))
                                    (set-car! common-allocs-box (cons (cons cname aligned) (car common-allocs-box)))
                                    (loop-c (cdr cs) (+ aligned c-sz)))
                                  (loop-c (cdr cs) b-off))))))
                     ;; Program header layout (W^X + optional PT_TLS)
                     (phnum (if has-tls? 4 3))
                     (hdr-bytes (+ 64 (* phnum 56)))
                     (text-file-offset (elf64-align-up hdr-bytes 16))
                     (base-vaddr 4194304)
                     (text-base-vaddr (+ base-vaddr text-file-offset))
                     (rodata-file-offset (elf64-align-up (+ text-file-offset text-cur) 16))
                     (rodata-base-vaddr (+ base-vaddr rodata-file-offset))
                     (seg1-raw-end (+ rodata-file-offset rodata-cur))
                     (seg1-filesz (elf64-align-up seg1-raw-end 4096))
                     (seg1-memsz seg1-filesz)

                     ;; Segment 2 (RW) layout
                     (seg2-base-vaddr (elf64-align-up (+ base-vaddr seg1-filesz) 2097152))
                     (tdata-start-off 0)
                     (init-start-off (elf64-align-up (+ tdata-start-off tdata-len) 8))
                     (init-array-start (+ seg2-base-vaddr init-start-off))
                     (init-array-end (+ init-array-start init-cur))
                     (fini-start-off (elf64-align-up (+ init-start-off init-cur) 8))
                     (fini-array-start (+ seg2-base-vaddr fini-start-off))
                     (fini-array-end (+ fini-array-start fini-cur))
                     (relro-start-off (elf64-align-up (+ fini-start-off fini-cur) 16))
                     (got-start-off (elf64-align-up (+ relro-start-off relro-cur) 8))
                     (got-len (* (car got-count-box) 8))
                     (got-vaddr (+ seg2-base-vaddr got-start-off))
                     (data-start-off (elf64-align-up (+ got-start-off got-len) 16))
                     (globals-start-off (elf64-align-up (+ data-start-off data-cur) 8))
                     (start-ulisp-globals-sec (+ seg2-base-vaddr globals-start-off))
                     (stop-ulisp-globals-sec (+ start-ulisp-globals-sec globals-cur))
                     (rw-file-end (+ globals-start-off globals-cur))
                     (bss-start-off (elf64-align-up rw-file-end (car max-bss-align-box)))
                     (bss-base-vaddr (+ seg2-base-vaddr bss-start-off))
                     (edata-vaddr (+ seg2-base-vaddr rw-file-end))
                     (end-vaddr (+ bss-base-vaddr total-bss-len))
                     (seg2-filesz rw-file-end)
                     (seg2-memsz (+ bss-start-off total-bss-len))
                     (seg1-bv (make-bytevector seg1-filesz 0))
                     (seg2-bv (make-bytevector seg2-filesz 0)))

                ;; Materialize O(1) section placements & copy file-backed sections
                (let loop-place-o ((oi 0))
                  (if (< oi obj-count)
                      (let* ((obj (vector-ref parsed-vec oi))
                             (sec-vec (vector-ref obj 1))
                             (sec-info-vec (vector-ref obj-buckets-vec oi))
                             (o-places (vector-ref placements-vec oi))
                             (scount (vector-length sec-vec)))
                        (let loop-place-s ((si 0))
                          (if (< si scount)
                              (let ((info (vector-ref sec-info-vec si)))
                                (if info
                                    (let* ((sec (vector-ref sec-vec si))
                                           (data-bv (vector-ref sec 8))
                                           (bucket (vector-ref info 0))
                                           (b-off (vector-ref info 1))
                                           (sz (vector-ref info 2)))
                                      (cond
                                        ((eq? bucket 'text)
                                         (let ((foff (+ text-file-offset b-off))
                                               (va (+ text-base-vaddr b-off)))
                                           (if (> sz 0) (elf64-copy-bytes! seg1-bv foff data-bv 0 sz))
                                           (vector-set! o-places si (vector bucket va foff #f seg1-bv))))
                                        ((eq? bucket 'rodata)
                                         (let ((foff (+ rodata-file-offset b-off))
                                               (va (+ rodata-base-vaddr b-off)))
                                           (if (> sz 0) (elf64-copy-bytes! seg1-bv foff data-bv 0 sz))
                                           (vector-set! o-places si (vector bucket va foff #f seg1-bv))))
                                        ((eq? bucket 'tdata)
                                         (let ((soff (+ tdata-start-off b-off))
                                               (va (+ seg2-base-vaddr (+ tdata-start-off b-off))))
                                           (if (> sz 0) (elf64-copy-bytes! seg2-bv soff data-bv 0 sz))
                                           (vector-set! o-places si (vector bucket va soff b-off seg2-bv))))
                                        ((eq? bucket 'tbss)
                                         (let ((tls-off (+ tbss-start-in-tls b-off)))
                                           (vector-set! o-places si (vector bucket (+ seg2-base-vaddr bss-start-off) -1 tls-off #f))))
                                        ((eq? bucket 'init_array)
                                         (let ((soff (+ init-start-off b-off)))
                                           (if (> sz 0) (elf64-copy-bytes! seg2-bv soff data-bv 0 sz))
                                           (vector-set! o-places si (vector bucket (+ seg2-base-vaddr soff) soff #f seg2-bv))))
                                        ((eq? bucket 'fini_array)
                                         (let ((soff (+ fini-start-off b-off)))
                                           (if (> sz 0) (elf64-copy-bytes! seg2-bv soff data-bv 0 sz))
                                           (vector-set! o-places si (vector bucket (+ seg2-base-vaddr soff) soff #f seg2-bv))))
                                        ((eq? bucket 'relro)
                                         (let ((soff (+ relro-start-off b-off)))
                                           (if (> sz 0) (elf64-copy-bytes! seg2-bv soff data-bv 0 sz))
                                           (vector-set! o-places si (vector bucket (+ seg2-base-vaddr soff) soff #f seg2-bv))))
                                        ((eq? bucket 'data)
                                         (let ((soff (+ data-start-off b-off)))
                                           (if (> sz 0) (elf64-copy-bytes! seg2-bv soff data-bv 0 sz))
                                           (vector-set! o-places si (vector bucket (+ seg2-base-vaddr soff) soff #f seg2-bv))))
                                        ((eq? bucket 'ulisp_globals)
                                         (let ((soff (+ globals-start-off b-off)))
                                           (if (> sz 0) (elf64-copy-bytes! seg2-bv soff data-bv 0 sz))
                                           (vector-set! o-places si (vector bucket (+ seg2-base-vaddr soff) soff #f seg2-bv))))
                                        ((eq? bucket 'bss)
                                         (vector-set! o-places si (vector bucket (+ bss-base-vaddr b-off) -1 #f #f))))))
                                (loop-place-s (+ si 1)))))
                        (loop-place-o (+ oi 1)))))

                ;; Reset global symbol map with resolved addresses + SHN_COMMON + SHN_ABS
                (let ((resolved-globals (make-symbol-map 8192))
                      (obj-local-vecs (make-vector obj-count #f)))
                  ;; Register allocated SHN_COMMON symbols first (strong definitions will override below)
                  (let reg-common ((cs (car common-allocs-box)))
                    (if (pair? cs)
                        (let ((ca (car cs)))
                          (symbol-map-set! resolved-globals (car ca)
                                           (vector 'common 2 (+ bss-base-vaddr (cdr ca)) #f "<common>"))
                          (reg-common (cdr cs)))))

                  ;; Populate local symbol tables and global/weak symbols across all objects
                  (let loop-syms-o ((oi 0))
                    (if (< oi obj-count)
                        (let* ((obj (vector-ref parsed-vec oi))
                               (path (vector-ref obj 0))
                               (sec-vec (vector-ref obj 1))
                               (sym-vec (vector-ref obj 2))
                               (o-places (vector-ref placements-vec oi))
                               (scount (vector-length sym-vec))
                               (local-vec (make-vector scount #f)))
                          (vector-set! obj-local-vecs oi local-vec)
                          (let loop-s ((k 0))
                            (if (< k scount)
                                (let* ((sym (vector-ref sym-vec k))
                                       (s-name (vector-ref sym 1))
                                       (s-bind (vector-ref sym 2))
                                       (s-shndx (vector-ref sym 4))
                                       (s-val (vector-ref sym 5)))
                                  (cond
                                    ((= s-shndx 65521) ;; SHN_ABS
                                     (if (= s-bind 0)
                                         (vector-set! local-vec k (cons s-val #f))
                                         (let ((existing (symbol-map-get resolved-globals s-name)))
                                           (cond
                                             ((or (not existing) (not (eq? (vector-ref (cdr existing) 0) 'defined)))
                                              (symbol-map-set! resolved-globals s-name
                                                               (vector 'defined s-bind s-val #f path)))
                                             ((and (= (vector-ref (cdr existing) 1) 2) (= s-bind 1))
                                              (symbol-map-set! resolved-globals s-name
                                                               (vector 'defined 1 s-val #f path)))
                                             ((and (= (vector-ref (cdr existing) 1) 1) (= s-bind 1))
                                              (elf64-linker-error!
                                               "C99-LNK-002"
                                               (string-append "multiple definition of `" s-name "` in " path
                                                              " (first defined in " (vector-ref (cdr existing) 4) ")")
                                               path))))))
                                    ((and (> s-shndx 0) (< s-shndx (vector-length sec-vec)))
                                     (let* ((pl (vector-ref o-places s-shndx))
                                            (sec-va (if pl (vector-ref pl 1) 0))
                                            (sec-tls-off (if pl (vector-ref pl 3) #f))
                                            (sym-va (+ sec-va s-val))
                                            (sym-tls (if sec-tls-off (+ sec-tls-off s-val) #f)))
                                       (if (= s-bind 0)
                                           (vector-set! local-vec k (cons sym-va sym-tls))
                                           (let ((existing (symbol-map-get resolved-globals s-name)))
                                             (cond
                                               ((or (not existing) (not (eq? (vector-ref (cdr existing) 0) 'defined)))
                                                (symbol-map-set! resolved-globals s-name
                                                                 (vector 'defined s-bind sym-va sym-tls path)))
                                               ((and (= (vector-ref (cdr existing) 1) 2) (= s-bind 1))
                                                (symbol-map-set! resolved-globals s-name
                                                                 (vector 'defined 1 sym-va sym-tls path)))
                                               ((= s-bind 2) #t) ;; retain existing strong or first weak
                                               ((and (= (vector-ref (cdr existing) 1) 1) (= s-bind 1))
                                                (elf64-linker-error!
                                                 "C99-LNK-002"
                                                 (string-append "multiple definition of `" s-name "` in " path
                                                                " (first defined in " (vector-ref (cdr existing) 4) ")")
                                                 path)))))))
                                    ((= s-bind 0)
                                     (vector-set! local-vec k (cons 0 #f))))
                                  (loop-s (+ k 1)))))
                          (loop-syms-o (+ oi 1)))))

                  ;; Register linker synthetic boundary symbols if not already defined
                  (let reg-synth ((ps (list (cons "__init_array_start" init-array-start)
                                            (cons "__init_array_end" init-array-end)
                                            (cons "__fini_array_start" fini-array-start)
                                            (cons "__fini_array_end" fini-array-end)
                                            (cons "__preinit_array_start" init-array-start)
                                            (cons "__preinit_array_end" init-array-start)
                                            (cons "__start_ulisp_globals_sec" start-ulisp-globals-sec)
                                            (cons "__stop_ulisp_globals_sec" stop-ulisp-globals-sec)
                                            (cons "__bss_start" bss-base-vaddr)
                                            (cons "_edata" edata-vaddr)
                                            (cons "_end" end-vaddr)
                                            (cons "__ehdr_start" base-vaddr)
                                            (cons "_GLOBAL_OFFSET_TABLE_" got-vaddr))))
                    (if (pair? ps)
                        (let* ((pair (car ps))
                               (name (car pair))
                               (val (cdr pair)))
                          (if (not (symbol-map-contains? resolved-globals name))
                              (symbol-map-set! resolved-globals name (vector 'defined 1 val #f "linker")))
                          (reg-synth (cdr ps)))))
                  (if (not (symbol-map-contains? resolved-globals "_DYNAMIC"))
                      (symbol-map-set! resolved-globals "_DYNAMIC" (vector 'defined 2 0 #f "linker-weak")))

                  ;; Verify undefined references across all objects
                  (let check-o ((oi 0))
                    (if (< oi obj-count)
                        (let* ((obj (vector-ref parsed-vec oi))
                               (path (vector-ref obj 0))
                               (sym-vec (vector-ref obj 2))
                               (relocs (vector-ref obj 3)))
                          (let check-r ((rs relocs))
                            (if (pair? rs)
                                (let* ((r (car rs))
                                       (sym-idx (vector-ref r 4))
                                       (sym (vector-ref sym-vec sym-idx))
                                       (s-name (vector-ref sym 1))
                                       (s-bind (vector-ref sym 2))
                                       (s-shndx (vector-ref sym 4)))
                                  (if (= s-shndx 0)
                                      (let ((resolved (symbol-map-get resolved-globals s-name)))
                                        (cond
                                          (resolved #t)
                                          ((= s-bind 2)
                                           (symbol-map-set! resolved-globals s-name (vector 'defined 2 0 #f "weak-null")))
                                          (else
                                           (elf64-linker-error!
                                            "C99-LNK-001"
                                            (string-append "undefined reference to `" s-name "` in " path)
                                            path)))))
                                  (check-r (cdr rs)))))
                          (check-o (+ oi 1)))))

                  ;; Materialize static .got entries in Segment 2
                  (let fill-got ((gs (car got-list-box)))
                    (if (pair? gs)
                        (let* ((g (car gs))
                               (key (vector-ref g 0))
                               (oi (vector-ref g 1))
                               (si (vector-ref g 2))
                               (s-bind (vector-ref g 3))
                               (s-name (vector-ref g 4))
                               (slot (cdr (symbol-map-get got-map key)))
                               (sym-val (if (= s-bind 0)
                                            (let ((lv (vector-ref obj-local-vecs oi)))
                                              (car (vector-ref lv si)))
                                            (let ((hit (symbol-map-get resolved-globals s-name)))
                                              (if hit (vector-ref (cdr hit) 2) 0)))))
                          (elf64-set-u64-le! seg2-bv (+ got-start-off (* slot 8)) sym-val)
                          (fill-got (cdr gs)))))

                  ;; Apply all relocations in O(1) placement lookup
                  (let apply-o ((oi 0))
                    (if (< oi obj-count)
                        (let* ((obj (vector-ref parsed-vec oi))
                               (path (vector-ref obj 0))
                               (sec-vec (vector-ref obj 1))
                               (sym-vec (vector-ref obj 2))
                               (relocs (vector-ref obj 3))
                               (o-places (vector-ref placements-vec oi))
                               (local-vec (vector-ref obj-local-vecs oi)))
                          (let apply-r ((rs relocs))
                            (if (pair? rs)
                                (let* ((r (car rs))
                                       (t-shndx (vector-ref r 0))
                                       (r-offset (vector-ref r 2))
                                       (r-type (vector-ref r 3))
                                       (sym-idx (vector-ref r 4))
                                       (r-addend (vector-ref r 5))
                                       (t-place (if (and (>= t-shndx 0) (< t-shndx (vector-length o-places)))
                                                    (vector-ref o-places t-shndx)
                                                    #f)))
                                  (if (and t-place (>= (vector-ref t-place 2) 0) (vector-ref t-place 4))
                                      (let* ((target-sec-vaddr (vector-ref t-place 1))
                                             (target-bv (vector-ref t-place 4))
                                             (buf-off (+ (vector-ref t-place 2) r-offset))
                                             (P (+ target-sec-vaddr r-offset))
                                             (sym (vector-ref sym-vec sym-idx))
                                             (s-name (vector-ref sym 1))
                                             (s-bind (vector-ref sym 2))
                                             (s-type (vector-ref sym 3))
                                             (s-shndx (vector-ref sym 4))
                                             (s-val (vector-ref sym 5))
                                             (S-tls (cond
                                                      ((= s-type 3) ;; STT_SECTION
                                                       (let ((sp (if (and (> s-shndx 0) (< s-shndx (vector-length o-places)))
                                                                     (vector-ref o-places s-shndx)
                                                                     #f)))
                                                         (if sp
                                                             (cons (vector-ref sp 1) (vector-ref sp 3))
                                                             (cons 0 #f))))
                                                      ((= s-bind 0)
                                                       (vector-ref local-vec sym-idx))
                                                      (else
                                                       (let ((g (symbol-map-get resolved-globals s-name)))
                                                         (if g
                                                             (cons (vector-ref (cdr g) 2) (vector-ref (cdr g) 3))
                                                             (cons 0 #f))))))
                                             (S (car S-tls))
                                             (S-tls-off (cdr S-tls)))
                                        (cond
                                          ((= r-type 0) #t) ;; R_X86_64_NONE
                                          ((= r-type 1) ;; R_X86_64_64
                                           (elf64-set-u64-le! target-bv buf-off (+ S r-addend)))
                                          ((or (= r-type 2) (= r-type 4)) ;; R_X86_64_PC32 / PLT32
                                           (let ((disp (- (+ S r-addend) P)))
                                             (if (or (< disp *elf64-min-disp32*) (> disp *elf64-max-disp32*))
                                                 (elf64-linker-error!
                                                  "C99-LNK-003"
                                                  (string-append "PC32 relocation overflow for `" s-name "`")
                                                  path)
                                                 (elf64-set-u32-le! target-bv buf-off disp))))
                                          ((or (= r-type 9) (= r-type 41) (= r-type 42)) ;; GOTPCREL / GOTPCRELX / REX_GOTPCRELX
                                           (let* ((key (if (= s-bind 0)
                                                           (string-append "__got_local#" (number->string oi) "#" (number->string sym-idx))
                                                           s-name))
                                                  (slot (cdr (symbol-map-get got-map key)))
                                                  (slot-vaddr (+ got-vaddr (* slot 8)))
                                                  (disp (- (+ slot-vaddr r-addend) P)))
                                             (if (or (< disp *elf64-min-disp32*) (> disp *elf64-max-disp32*))
                                                 (elf64-linker-error!
                                                  "C99-LNK-003"
                                                  (string-append "GOTPCREL relocation overflow for `" s-name "`")
                                                  path)
                                                 (elf64-set-u32-le! target-bv buf-off disp))))
                                          ((= r-type 10) ;; R_X86_64_32
                                           (let ((val (+ S r-addend)))
                                             (if (or (< val 0) (> val 4294967295))
                                                 (elf64-linker-error!
                                                  "C99-LNK-003"
                                                  (string-append "R_X86_64_32 overflow for `" s-name "`")
                                                  path)
                                                 (elf64-set-u32-le! target-bv buf-off val))))
                                          ((= r-type 11) ;; R_X86_64_32S
                                           (let ((val (+ S r-addend)))
                                             (if (or (< val *elf64-min-disp32*) (> val *elf64-max-disp32*))
                                                 (elf64-linker-error!
                                                  "C99-LNK-003"
                                                  (string-append "R_X86_64_32S overflow for `" s-name "`")
                                                  path)
                                                 (elf64-set-u32-le! target-bv buf-off val))))
                                          ((= r-type 23) ;; R_X86_64_TPOFF32
                                           (if (not S-tls-off)
                                               (elf64-linker-error!
                                                "C99-LNK-003"
                                                (string-append "TPOFF32 against non-TLS symbol `" s-name "`")
                                                path))
                                           (let ((tpoff (+ (- S-tls-off tls-aligned-size) r-addend)))
                                             (if (or (< tpoff *elf64-min-disp32*) (> tpoff *elf64-max-disp32*))
                                                 (elf64-linker-error!
                                                  "C99-LNK-003"
                                                  (string-append "TPOFF32 relocation overflow for `" s-name "`")
                                                  path)
                                                 (elf64-set-u32-le! target-bv buf-off tpoff))))
                                          ((= r-type 24) ;; R_X86_64_PC64
                                           (elf64-set-s64-le! target-bv buf-off (- (+ S r-addend) P)))
                                          (else
                                           (elf64-linker-error!
                                            "C99-LNK-003"
                                            (string-append "Unsupported relocation type " (number->string r-type)
                                                           " for `" s-name "`")
                                            path)))))
                                  (apply-r (cdr rs)))))
                          (apply-o (+ oi 1)))))

                  ;; Resolve entry point symbol
                  (let* ((entry-name (if entry-sym entry-sym "_start"))
                         (entry-lookup (symbol-map-get resolved-globals entry-name))
                         (entry-vaddr (if entry-lookup
                                          (vector-ref (cdr entry-lookup) 2)
                                          (elf64-linker-error!
                                           "C99-LNK-001"
                                           (string-append "entry point symbol '" entry-name "' not found")
                                           entry-name))))
                    ;; Write ELF64 Header & Program Headers
                    (elf64-write-ehdr-ex! seg1-bv entry-vaddr 64 phnum)
                    ;; PHDR 0: PT_LOAD RX (flags 5)
                    (elf64-write-phdr-base! seg1-bv 64 1 5 0 base-vaddr)
                    (elf64-write-phdr-sizes! seg1-bv 64 seg1-filesz seg1-memsz 4096)
                    ;; PHDR 1: PT_LOAD RW (flags 6)
                    (elf64-write-phdr-base! seg1-bv 120 1 6 seg1-filesz seg2-base-vaddr)
                    (elf64-write-phdr-sizes! seg1-bv 120 seg2-filesz seg2-memsz 4096)
                    (if has-tls?
                        (begin
                          ;; PHDR 2: PT_TLS R (p_type = 7, flags 4)
                          (elf64-write-phdr-base! seg1-bv 176 7 4
                                                  (+ seg1-filesz tdata-start-off)
                                                  (+ seg2-base-vaddr tdata-start-off))
                          (elf64-write-phdr-sizes! seg1-bv 176 tdata-len tls-memsz tls-align)
                          ;; PHDR 3: PT_GNU_STACK RW (flags 6)
                          (elf64-write-phdr-base! seg1-bv 232 1685382481 6 0 0)
                          (elf64-write-phdr-sizes! seg1-bv 232 0 0 16))
                        (begin
                          ;; PHDR 2: PT_GNU_STACK RW (flags 6)
                          (elf64-write-phdr-base! seg1-bv 176 1685382481 6 0 0)
                          (elf64-write-phdr-sizes! seg1-bv 176 0 0 16)))

                    ;; Assemble final binary bytevector
                    (let* ((total-size (+ seg1-filesz seg2-filesz))
                           (final-bv (make-bytevector total-size 0)))
                      (elf64-copy-bytes! final-bv 0 seg1-bv 0 seg1-filesz)
                      (elf64-copy-bytes! final-bv seg1-filesz seg2-bv 0 seg2-filesz)
                      final-bv))))))))))



