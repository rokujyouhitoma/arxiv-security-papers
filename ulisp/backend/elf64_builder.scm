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
         (bv (make-bytevector len)))
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
  (let ((bv (make-bytevector 40)))
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

(define (build-debug-line-section file-table line-table text-vaddr text-len)
  (let* ((files (if (pair? file-table) file-table '((1 . "source.scm"))))
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
                                                          (let ((bv (make-bytevector 8)))
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
         (bv (make-bytevector total-len)))
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
  (let* ((text-syms (let loop ((st sym-table) (acc '()))
                      (if (null? st)
                          (reverse acc)
                          (let* ((entry (car st))
                                 (name (car entry))
                                 (info (cdr entry)))
                            (if (and (pair? info) (eq? (car info) 'text))
                                (loop (cdr st) (cons (cons name (cadr info)) acc))
                                (loop (cdr st) acc))))))
         (syms-with-stroff
           (let loop ((syms text-syms) (stroff 1) (acc '()))
             (if (null? syms)
                 (reverse acc)
                 (let* ((s (car syms))
                        (name (car s))
                        (off (cdr s))
                        (slen (string-length name)))
                   (loop (cdr syms) (+ (+ stroff slen) 1) (cons (list name off stroff) acc))))))
         (strtab-bytes
           (let loop ((syms syms-with-stroff) (acc '(0)))
             (if (null? syms)
                 (elf64-list->bytevector (reverse acc))
                 (let* ((name (caar syms))
                        (chars (dwarf-string->bytes name)))
                   (loop (cdr syms) (dwarf-app3 '(0) (reverse chars) acc))))))
         (num-syms (+ (length syms-with-stroff) 1))
         (symtab-len (* num-syms 24))
         (symtab-bv (make-bytevector symtab-len)))
    (let loop ((syms syms-with-stroff) (idx 1))
      (if (pair? syms)
          (let* ((s (car syms))
                 (name (car s))
                 (off (cadr s))
                 (stroff (caddr s))
                 (sym-off (* idx 24))
                 (val (+ text-vaddr off)))
            (elf64-set-u32-le! symtab-bv sym-off stroff)     ;; st_name
            (elf64-set-u8! symtab-bv (+ sym-off 4) 18)       ;; st_info = 0x12 (STB_GLOBAL | STT_FUNC)
            (elf64-set-u8! symtab-bv (+ sym-off 5) 0)        ;; st_other = 0
            (elf64-set-u16-le! symtab-bv (+ sym-off 6) 1)    ;; st_shndx = 1 (.text)
            (elf64-set-u64-le! symtab-bv (+ sym-off 8) val)  ;; st_value
            (elf64-set-u64-le! symtab-bv (+ sym-off 16) text-len) ;; st_size
            (loop (cdr syms) (+ idx 1)))))
    (list symtab-bv strtab-bytes)))

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
         (elf-bv (make-bytevector (+ shstrtab-offset shstrtab-len))))
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
         (elf-bv (make-bytevector (+ shstrtab-offset shstrtab-len))))
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
               (pair? (cadr debug-payload))))
      (build-elf64-debug text-bv rodata-bv data-bv bss-size entry-offset debug-payload)
      (build-elf64-plain text-bv rodata-bv data-bv bss-size entry-offset)))

(define (build-elf64-executable text-bv rodata-bv data-bv bss-size entry-offset)
  (build-elf64-executable-ex text-bv rodata-bv data-bv bss-size entry-offset #f))
