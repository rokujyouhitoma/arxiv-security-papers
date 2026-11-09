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

(define (elf64-build-rel-symtab sym-table globl-syms weak-syms sym-types reloc-records)
  ;; Collect unique named symbols from globl-syms, weak-syms, and string targets in reloc-records
  (let* ((add-uniq (lambda (s lst)
                     (if (asm-str-list-member? s lst)
                         lst
                         (cons s lst))))
         (s1 (let loop ((gs globl-syms) (acc '()))
               (if (null? gs) acc (loop (cdr gs) (add-uniq (car gs) acc)))))
         (s2 (let loop ((ws weak-syms) (acc s1))
               (if (null? ws) acc (loop (cdr ws) (add-uniq (car ws) acc)))))
         (named-syms (let loop ((rs reloc-records) (acc s2))
                       (if (null? rs)
                           (reverse acc)
                           (let ((tgt (caddr (car rs))))
                             (if (string? tgt)
                                 (loop (cdr rs) (add-uniq tgt acc))
                                 (loop (cdr rs) acc))))))
         ;; Assign string table offsets and symbol indices (starting at 7)
         (syms-meta
           (let loop ((syms named-syms) (idx 7) (stroff 1) (acc '()))
             (if (null? syms)
                 (reverse acc)
                 (let* ((name (car syms))
                        (slen (string-length name)))
                   (loop (cdr syms) (+ idx 1) (+ (+ stroff slen) 1)
                         (cons (list name idx stroff) acc))))))
         (sym-idx-map
           (let loop ((ms syms-meta) (acc '()))
             (if (null? ms)
                 acc
                 (loop (cdr ms) (cons (cons (caar ms) (cadar ms)) acc)))))
         (strtab-len (if (null? syms-meta)
                         1
                         (let ((last-m (let l ((x syms-meta)) (if (null? (cdr x)) (car x) (l (cdr x))))))
                           (+ (+ (caddr last-m) (string-length (car last-m))) 1))))
         (strtab-bv (make-bytevector strtab-len))
         (num-syms (+ 7 (length syms-meta)))
         (symtab-bv (make-bytevector (* num-syms 24))))
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
                 (is-weak? (asm-str-list-member? name weak-syms))
                 (bind (if is-weak? 2 1)) ;; 2=STB_WEAK, 1=STB_GLOBAL
                 (def-entry (assoc name sym-table))
                 (type-entry (assoc name sym-types))
                 (stt (if type-entry
                          (cdr type-entry)
                          (if (and def-entry (eq? (cadr def-entry) 'text))
                              2 ;; STT_FUNC
                              0))) ;; STT_NOTYPE
                 (st-info (+ (* bind 16) stt))
                 (shndx (if def-entry (asm-sec->shndx (cadr def-entry)) 0))
                 (st-val (if def-entry (caddr def-entry) 0)))
            (elf64-set-u32-le! symtab-bv off soff)
            (elf64-set-u8! symtab-bv (+ off 4) st-info)
            (elf64-set-u8! symtab-bv (+ off 5) 0)
            (elf64-set-u16-le! symtab-bv (+ off 6) shndx)
            (elf64-set-u64-le! symtab-bv (+ off 8) st-val)
            (elf64-set-u64-le! symtab-bv (+ off 16) 0)
            (sym-loop (cdr ms)))))
    (list symtab-bv strtab-bv sym-idx-map)))

(define (elf64-build-rela-section sec-name reloc-records sym-idx-map)
  (let* ((sec-rels (let loop ((rs reloc-records) (acc '()))
                     (if (null? rs)
                         (reverse acc)
                         (if (eq? (caar rs) sec-name)
                             (loop (cdr rs) (cons (car rs) acc))
                             (loop (cdr rs) acc)))))
         (count (length sec-rels))
         (bv (make-bytevector (* count 24))))
    (let loop ((rs sec-rels) (i 0))
      (if (pair? rs)
          (let* ((r (car rs))
                 (r-offset (cadr r))
                 (target (caddr r))
                 (r-type (cadddr r))
                 (r-addend (car (cddddr r)))
                 (sym-idx (if (number? target)
                              target
                              (let ((e (assoc target sym-idx-map)))
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
         (sym-res (elf64-build-rel-symtab sym-table globl-syms weak-syms sym-types reloc-records))
         (symtab-bv (car sym-res))
         (strtab-bv (cadr sym-res))
         (sym-idx-map (caddr sym-res))
         (rela-text-bv (elf64-build-rela-section 'text reloc-records sym-idx-map))
         (rela-rodata-bv (elf64-build-rela-section 'rodata reloc-records sym-idx-map))
         (rela-data-bv (elf64-build-rela-section 'data reloc-records sym-idx-map))
         (rela-init-bv (elf64-build-rela-section 'init_array reloc-records sym-idx-map))
         (rela-globals-bv (elf64-build-rela-section 'ulisp_globals_sec reloc-records sym-idx-map))
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
         (elf-bv (make-bytevector total-len)))
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
    ;; 13: .symtab (SHT_SYMTAB=2, flags=0, link=14 (.strtab), info=7 (first non-local symbol))
    (elf64-write-shdr! elf-bv shoff 13 148 2 0 0 symtab-off symtab-len 14 7 8 24)
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
  (let ((dst (make-bytevector len)))
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
    (assoc key bucket)))

(define (symbol-map-set! sm key val)
  (let* ((h (modulo (elf64-string-hash key) (vector-length sm)))
         (bucket (vector-ref sm h))
         (entry (assoc key bucket)))
    (if entry
        (set-cdr! entry val)
        (vector-set! sm h (cons (cons key val) bucket)))))

;; Binary file reader returning raw bytevector
(define (read-binary-file-to-bytevector path)
  (cond-expand
    (gauche
     (call-with-input-file path
       (lambda (p) (read-bytevector 1000000000 p))
       :element-type :binary))
    (else
     (let ((fd (sys-open path 0 0)))
       (if (< fd 0)
           (begin
             (display-stderr (string-append "ulisp --ld: error: cannot open input object file: " path "\n"))
             (compiler-abort-and-cleanup! 1))
           (let* ((file-size (sys-lseek fd 0 2)))
             (if (< file-size 0)
                 (begin
                   (sys-close fd)
                   (display-stderr (string-append "ulisp --ld: error: failed to seek file: " path "\n"))
                   (compiler-abort-and-cleanup! 1))
                 (begin
                   (sys-lseek fd 0 0)
                   (let ((bv (make-bytevector file-size)))
                     (let loop ((read-total 0))
                       (if (< read-total file-size)
                           (let* ((buf-ptr (%ptr-add (%ptr-untag bv) (+ 8 read-total)))
                                  (n (sys-read fd buf-ptr (- file-size read-total))))
                             (if (<= n 0)
                                 (begin
                                   (sys-close fd)
                                   (display-stderr (string-append "ulisp --ld: error: unexpected EOF reading: " path "\n"))
                                   (compiler-abort-and-cleanup! 1))
                                 (loop (+ read-total n))))
                           (begin
                             (sys-close fd)
                             bv))))))))))))

;; Parse an ELF64 ET_REL relocatable object file into structured vectors
;; Returns: (vector path sec-vec sym-vec relocs)
(define (elf64-parse-relocatable-object bv path)
  (if (< (bytevector-length bv) 64)
      (begin
        (display-stderr (string-append "ulisp --ld: error: file too small for ELF header: " path "\n"))
        (compiler-abort-and-cleanup! 1)))
  (if (not (and (= (elf64-get-u8 bv 0) 127)
                (= (elf64-get-u8 bv 1) 69)
                (= (elf64-get-u8 bv 2) 76)
                (= (elf64-get-u8 bv 3) 70)
                (= (elf64-get-u8 bv 4) 2)   ;; ELFCLASS64
                (= (elf64-get-u8 bv 5) 1)   ;; ELFDATA2LSB
                (= (elf64-get-u16-le bv 16) 1) ;; e_type == ET_REL
                (= (elf64-get-u16-le bv 18) 62))) ;; e_machine == EM_X86_64
      (begin
        (display-stderr (string-append "ulisp --ld: error: " path " is not an x86-64 ELF relocatable object (ET_REL)\n"))
        (compiler-abort-and-cleanup! 1)))
  (let* ((e-shoff (elf64-get-u64-le bv 40))
         (e-shentsize (elf64-get-u16-le bv 58))
         (e-shnum (elf64-get-u16-le bv 60))
         (e-shstrndx (elf64-get-u16-le bv 62))
         (shstr-shdr-off (+ e-shoff (* e-shstrndx e-shentsize)))
         (shstr-file-off (elf64-get-u64-le bv (+ shstr-shdr-off 24)))
         (shstr-size (elf64-get-u64-le bv (+ shstr-shdr-off 32)))
         (shstrtab-bv (elf64-sub-bytevector bv shstr-file-off shstr-size)))
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
                 (sh-align (elf64-get-u64-le bv (+ shdr-off 48)))
                 (data-bv (if (and (> sh-size 0) (not (= sh-type 8)))
                              (elf64-sub-bytevector bv sh-offset sh-size)
                              (make-bytevector 0))))
            (loop-shdr (+ idx 1)
                       (cons (vector idx sec-name sh-type sh-flags sh-size sh-align sh-link sh-info data-bv)
                             sections)))
          (let* ((sec-vec (list->vector (reverse sections)))
                 (symtab-sec (let find-sym ((i 0))
                               (if (< i (vector-length sec-vec))
                                   (let ((s (vector-ref sec-vec i)))
                                     (if (= (vector-ref s 2) 2) s (find-sym (+ i 1))))
                                   #f)))
                 (symtab-bv (if symtab-sec (vector-ref symtab-sec 8) (make-bytevector 0)))
                 (strtab-idx (if symtab-sec (vector-ref symtab-sec 6) 0))
                 (strtab-sec (if (< strtab-idx (vector-length sec-vec))
                                 (vector-ref sec-vec strtab-idx)
                                 #f))
                 (strtab-bv (if strtab-sec (vector-ref strtab-sec 8) (make-bytevector 0)))
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
                               (target-sec (if (< target-shndx (vector-length sec-vec))
                                               (vector-ref sec-vec target-shndx)
                                               #f))
                               (target-sec-name (if target-sec (vector-ref target-sec 1) ""))
                               (rela-bv (vector-ref s 8))
                               (rela-count (quotient (bytevector-length rela-bv) 24)))
                          (let inner ((r-idx 0) (sec-relocs '()))
                            (if (< r-idx rela-count)
                                (let* ((off (* r-idx 24))
                                       (r-offset (elf64-get-u64-le rela-bv off))
                                       (r-info (elf64-get-u64-le rela-bv (+ off 8)))
                                       (r-addend (elf64-get-s64-le rela-bv (+ off 16)))
                                       (sym-idx (quotient r-info 4294967296))
                                       (r-type (modulo r-info 4294967296)))
                                  (inner (+ r-idx 1)
                                         (cons (vector target-shndx target-sec-name r-offset r-type sym-idx r-addend)
                                               sec-relocs)))
                                (loop-rela (+ s-idx 1) (append (reverse sec-relocs) all-relocs)))))
                        (loop-rela (+ s-idx 1) all-relocs)))
                  (vector path sec-vec sym-vec (reverse all-relocs)))))))))

(define (elf64-obj-find-section obj sec-name)
  (let* ((sec-vec (vector-ref obj 1))
         (len (vector-length sec-vec)))
    (let loop ((i 0))
      (if (< i len)
          (let ((s (vector-ref sec-vec i)))
            (if (string=? (vector-ref s 1) sec-name)
                s
                (loop (+ i 1))))
          #f))))

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

(define (elf64-plan-section-placements objs sec-name base-vaddr start-off align-bytes)
  (let loop ((os objs) (cur-off start-off) (acc '()))
    (if (null? os)
        (cons (- cur-off start-off) (reverse acc))
        (let* ((obj (car os))
               (s (elf64-obj-find-section obj sec-name))
               (sz (if s (vector-ref s 4) 0))
               (aligned-off (elf64-align-up cur-off align-bytes))
               (vaddr (+ base-vaddr aligned-off)))
          (loop (cdr os) (+ aligned-off sz) (cons (list obj vaddr aligned-off sz) acc))))))

(define (elf64-lookup-obj-sec-vaddr obj sec-name places-vec)
  (let ((placements
         (cond
           ((string=? sec-name ".text") (vector-ref places-vec 0))
           ((string=? sec-name ".rodata") (vector-ref places-vec 1))
           ((string=? sec-name ".init_array") (vector-ref places-vec 2))
           ((string=? sec-name ".data") (vector-ref places-vec 3))
           ((string=? sec-name "ulisp_globals_sec") (vector-ref places-vec 4))
           ((string=? sec-name ".bss") (vector-ref places-vec 5))
           (else #f))))
    (if placements
        (let ((e (assoc obj placements)))
          (if e (cadr e) 0))
        0)))

;; Main Static Linker Procedure: Links multiple ELF64 ET_REL objects into a single ET_EXEC binary bytevector
(define (link-elf64-relocatable-objects obj-paths entry-sym)
  (if (null? obj-paths)
      (begin
        (display-stderr "ulisp --ld: error: no input object files specified\n")
        (compiler-abort-and-cleanup! 1)))
  ;; 1. Parse all input ELF64 ET_REL object files
  (let* ((parsed-objs (let loop-p ((paths obj-paths) (acc '()))
                        (if (null? paths)
                            (reverse acc)
                            (let* ((p (car paths))
                                   (bv (if (bytevector? p) p (read-binary-file-to-bytevector p)))
                                   (label (if (bytevector? p) "<memory.o>" p))
                                   (obj (elf64-parse-relocatable-object bv label)))
                              (loop-p (cdr paths) (cons obj acc))))))
         ;; 2. Plan Segment 1 (RX: 0x400000) layout
         ;; text-file-offset = 240 (64 ehdr + 3 * 56 phdr = 232 -> aligned 16 = 240)
         (text-file-offset 240)
         (text-base-vaddr (+ 4194304 text-file-offset))
         ;; Plan .text placement
         (text-plan (elf64-plan-section-placements parsed-objs ".text" text-base-vaddr 0 16))
         (merged-text-len (car text-plan))
         (obj-text-placements (cdr text-plan))

         ;; Plan .rodata placement
         (rodata-file-offset (elf64-align-up (+ text-file-offset merged-text-len) 16))
         (rodata-base-vaddr (+ 4194304 rodata-file-offset))
         (rodata-plan (elf64-plan-section-placements parsed-objs ".rodata" rodata-base-vaddr 0 16))
         (merged-rodata-len (car rodata-plan))
         (obj-rodata-placements (cdr rodata-plan))

         (seg1-raw-end (+ rodata-file-offset merged-rodata-len))
         (seg1-filesz (elf64-align-up seg1-raw-end 4096))
         (seg1-memsz seg1-filesz)

         ;; 3. Plan Segment 2 (RW) layout: dynamically placed after Segment 1 aligned to 2MB
         (seg2-base-vaddr (elf64-align-up (+ 4194304 seg1-filesz) 2097152))
         ;; Plan .init_array placement
         (init-plan (elf64-plan-section-placements parsed-objs ".init_array" seg2-base-vaddr 0 8))
         (merged-init-len (car init-plan))
         (obj-init-placements (cdr init-plan))
         (init-array-start seg2-base-vaddr)
         (init-array-end (+ seg2-base-vaddr merged-init-len))

         ;; Plan .data placement
         (data-start-off (elf64-align-up merged-init-len 16))
         (data-plan (elf64-plan-section-placements parsed-objs ".data" seg2-base-vaddr data-start-off 16))
         (merged-data-len (car data-plan))
         (obj-data-placements (cdr data-plan))

         ;; Plan ulisp_globals_sec placement
         (globals-start-off (elf64-align-up (+ data-start-off merged-data-len) 8))
         (start-ulisp-globals-sec (+ seg2-base-vaddr globals-start-off))
         (globals-plan (elf64-plan-section-placements parsed-objs "ulisp_globals_sec" seg2-base-vaddr globals-start-off 8))
         (merged-globals-len (car globals-plan))
         (obj-globals-placements (cdr globals-plan))
         (stop-ulisp-globals-sec (+ start-ulisp-globals-sec merged-globals-len))

         ;; Plan .bss placement
         (bss-start-off (elf64-align-up (+ globals-start-off merged-globals-len) 8))
         (bss-plan (elf64-plan-section-placements parsed-objs ".bss" seg2-base-vaddr bss-start-off 8))
         (merged-bss-len (car bss-plan))
         (obj-bss-placements (cdr bss-plan))

         (seg2-filesz bss-start-off)
         (seg2-memsz (+ seg2-filesz merged-bss-len))

         ;; Allocate Segment Buffers
         (seg1-bv (make-bytevector seg1-filesz 0))
         (seg2-bv (make-bytevector seg2-filesz 0)))

    ;; Copy payload into Segment 1
    (let copy-s1 ((t-places obj-text-placements))
      (if (pair? t-places)
          (let* ((entry (car t-places))
                 (obj (car entry))
                 (off (+ text-file-offset (caddr entry)))
                 (sz (cadddr entry))
                 (s (elf64-obj-find-section obj ".text")))
            (if (and s (> sz 0))
                (elf64-copy-bytes! seg1-bv off (vector-ref s 8) 0 sz))
            (copy-s1 (cdr t-places)))))

    (let copy-ro ((r-places obj-rodata-placements))
      (if (pair? r-places)
          (let* ((entry (car r-places))
                 (obj (car entry))
                 (off (+ rodata-file-offset (caddr entry)))
                 (sz (cadddr entry))
                 (s (elf64-obj-find-section obj ".rodata")))
            (if (and s (> sz 0))
                (elf64-copy-bytes! seg1-bv off (vector-ref s 8) 0 sz))
            (copy-ro (cdr r-places)))))

    ;; Copy payload into Segment 2
    (let copy-init ((i-places obj-init-placements))
      (if (pair? i-places)
          (let* ((entry (car i-places))
                 (obj (car entry))
                 (off (caddr entry))
                 (sz (cadddr entry))
                 (s (elf64-obj-find-section obj ".init_array")))
            (if (and s (> sz 0))
                (elf64-copy-bytes! seg2-bv off (vector-ref s 8) 0 sz))
            (copy-init (cdr i-places)))))

    (let copy-d ((d-places obj-data-placements))
      (if (pair? d-places)
          (let* ((entry (car d-places))
                 (obj (car entry))
                 (off (caddr entry))
                 (sz (cadddr entry))
                 (s (elf64-obj-find-section obj ".data")))
            (if (and s (> sz 0))
                (elf64-copy-bytes! seg2-bv off (vector-ref s 8) 0 sz))
            (copy-d (cdr d-places)))))

    (let copy-g ((g-places obj-globals-placements))
      (if (pair? g-places)
          (let* ((entry (car g-places))
                 (obj (car entry))
                 (off (caddr entry))
                 (sz (cadddr entry))
                 (s (elf64-obj-find-section obj "ulisp_globals_sec")))
            (if (and s (> sz 0))
                (elf64-copy-bytes! seg2-bv off (vector-ref s 8) 0 sz))
            (copy-g (cdr g-places)))))

    ;; 4. Build Global Symbol Map & Local Symbol Vectors
    (let* ((places-vec (vector obj-text-placements
                               obj-rodata-placements
                               obj-init-placements
                               obj-data-placements
                               obj-globals-placements
                               obj-bss-placements))
           (lookup-sec (lambda (obj sec-name)
                         (elf64-lookup-obj-sec-vaddr obj sec-name places-vec)))
           (global-syms (make-symbol-map 4096))
           ;; Register Linker Synthetic Boundary Symbols
           (_dummy1 (symbol-map-set! global-syms "__init_array_start" (list init-array-start 1 "linker")))
           (_dummy2 (symbol-map-set! global-syms "__init_array_end" (list init-array-end 1 "linker")))
           (_dummy3 (symbol-map-set! global-syms "__start_ulisp_globals_sec" (list start-ulisp-globals-sec 1 "linker")))
           (_dummy4 (symbol-map-set! global-syms "__stop_ulisp_globals_sec" (list stop-ulisp-globals-sec 1 "linker")))
           ;; Process defined symbols from each object into obj-local-sym-vecs
           (obj-local-sym-vecs
             (let loop-objs ((objs parsed-objs) (acc '()))
               (if (null? objs)
                   (reverse acc)
                   (let* ((obj (car objs))
                          (path (vector-ref obj 0))
                          (sec-vec (vector-ref obj 1))
                          (sym-vec (vector-ref obj 2))
                          (sym-count (vector-length sym-vec))
                          (local-vec (make-vector sym-count 0)))
                     (let loop-s ((idx 0))
                       (if (< idx sym-count)
                           (let* ((sym (vector-ref sym-vec idx))
                                  (s-name (vector-ref sym 1))
                                  (s-bind (vector-ref sym 2))
                                  (s-type (vector-ref sym 3))
                                  (s-shndx (vector-ref sym 4))
                                  (s-val (vector-ref sym 5)))
                             (if (and (> s-shndx 0) (< s-shndx (vector-length sec-vec)))
                                 (let* ((sec (vector-ref sec-vec s-shndx))
                                        (sec-name (vector-ref sec 1))
                                        (sec-base (lookup-sec obj sec-name))
                                        (sym-vaddr (+ sec-base s-val)))
                                   (if (= s-bind 0) ;; STB_LOCAL
                                       (vector-set! local-vec idx sym-vaddr)
                                       ;; STB_GLOBAL (1) or STB_WEAK (2)
                                       (let ((existing (symbol-map-get global-syms s-name)))
                                         (cond
                                           ((not existing)
                                            (symbol-map-set! global-syms s-name (list sym-vaddr s-bind path)))
                                           ((and (= (cadr (cdr existing)) 2) (= s-bind 1))
                                            ;; WEAK overridden by GLOBAL
                                            (symbol-map-set! global-syms s-name (list sym-vaddr s-bind path)))
                                           ((and (= (cadr (cdr existing)) 1) (= s-bind 2))
                                            ;; GLOBAL retains precedence over new WEAK
                                            #t)
                                           ((and (= (cadr (cdr existing)) 2) (= s-bind 2))
                                            ;; First WEAK retains precedence
                                            #t)
                                           ((and (= (cadr (cdr existing)) 1) (= s-bind 1))
                                            ;; Multiple GLOBAL definition error
                                            (display-stderr (string-append "ulisp --ld: error: multiple definition of `" s-name "` in " path " (first defined in " (caddr (cdr existing)) ")\n"))
                                            (compiler-abort-and-cleanup! 1))))))
                                 (if (= s-bind 0)
                                     (vector-set! local-vec idx 0)))
                             (loop-s (+ idx 1)))))
                     (loop-objs (cdr objs) (cons (cons obj local-vec) acc)))))))

      ;; 5. Verify Undefined References
      (let check-objs ((objs parsed-objs))
        (if (pair? objs)
            (let* ((obj (car objs))
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
                      (if (= s-shndx 0) ;; SHN_UNDEF
                          (let ((resolved (symbol-map-get global-syms s-name)))
                            (cond
                              (resolved #t)
                              ((= s-bind 2)
                               ;; Undefined WEAK symbol resolves to NULL (0)
                               (symbol-map-set! global-syms s-name (list 0 2 "weak-null")))
                              (else
                               (display-stderr (string-append "ulisp --ld: error: undefined reference to `" s-name "` in " path "\n"))
                               (compiler-abort-and-cleanup! 1)))))
                      (check-r (cdr rs)))))
              (check-objs (cdr objs)))))

      ;; 6. Apply Relocations
      (let apply-objs ((objs parsed-objs))
        (if (pair? objs)
            (let* ((obj (car objs))
                   (sec-vec (vector-ref obj 1))
                   (sym-vec (vector-ref obj 2))
                   (relocs (vector-ref obj 3))
                   (local-vec (cdr (assoc obj obj-local-sym-vecs))))
              (let apply-r ((rs relocs))
                (if (pair? rs)
                    (let* ((r (car rs))
                           (target-sec-name (vector-ref r 1))
                           (r-offset (vector-ref r 2))
                           (r-type (vector-ref r 3))
                           (sym-idx (vector-ref r 4))
                           (r-addend (vector-ref r 5))
                           (sym (vector-ref sym-vec sym-idx))
                           (s-name (vector-ref sym 1))
                           (s-bind (vector-ref sym 2))
                           (s-type (vector-ref sym 3))
                           (s-shndx (vector-ref sym 4))
                           (target-sec-vaddr (lookup-sec obj target-sec-name))
                           (P (+ target-sec-vaddr r-offset))
                           ;; Determine Symbol Value S
                           (S (cond
                                ((= s-type 3) ;; STT_SECTION
                                 (if (and (> s-shndx 0) (< s-shndx (vector-length sec-vec)))
                                     (let* ((sec (vector-ref sec-vec s-shndx))
                                            (sname (vector-ref sec 1)))
                                       (lookup-sec obj sname))
                                     0))
                                ((= s-bind 0) ;; STB_LOCAL
                                 (vector-ref local-vec sym-idx))
                                (else ;; STB_GLOBAL or STB_WEAK
                                 (let ((g (symbol-map-get global-syms s-name)))
                                   (if g (car (cdr g)) 0)))))
                           ;; Determine Target Buffer & Buffer Offset
                           (buf-pair (cond
                                       ((string=? target-sec-name ".text")
                                        (let* ((entry (assoc obj obj-text-placements))
                                               (boff (+ (+ text-file-offset (caddr entry)) r-offset)))
                                          (cons seg1-bv boff)))
                                       ((string=? target-sec-name ".rodata")
                                        (let* ((entry (assoc obj obj-rodata-placements))
                                               (boff (+ (+ rodata-file-offset (caddr entry)) r-offset)))
                                          (cons seg1-bv boff)))
                                       ((string=? target-sec-name ".init_array")
                                        (let* ((entry (assoc obj obj-init-placements))
                                               (boff (+ (caddr entry) r-offset)))
                                          (cons seg2-bv boff)))
                                       ((string=? target-sec-name ".data")
                                        (let* ((entry (assoc obj obj-data-placements))
                                               (boff (+ (caddr entry) r-offset)))
                                          (cons seg2-bv boff)))
                                       ((string=? target-sec-name "ulisp_globals_sec")
                                        (let* ((entry (assoc obj obj-globals-placements))
                                               (boff (+ (caddr entry) r-offset)))
                                          (cons seg2-bv boff)))
                                       (else #f))))
                      (if buf-pair
                          (let ((target-bv (car buf-pair))
                                (buf-off (cdr buf-pair)))
                            (cond
                              ((= r-type 1) ;; R_X86_64_64
                               (let ((val (+ S r-addend)))
                                 (elf64-set-u64-le! target-bv buf-off val)))
                              ((or (= r-type 2) (= r-type 4)) ;; R_X86_64_PC32 or PLT32
                               (let ((disp (- (+ S r-addend) P)))
                                 (if (or (< disp *elf64-min-disp32*) (> disp *elf64-max-disp32*))
                                     (begin
                                       (display-stderr (string-append "ulisp --ld: error: relocation overflow for " s-name "\n"))
                                       (compiler-abort-and-cleanup! 1))
                                     (elf64-set-u32-le! target-bv buf-off disp))))
                              ((or (= r-type 10) (= r-type 11)) ;; R_X86_64_32 or 32S
                               (let ((val (+ S r-addend)))
                                 (elf64-set-u32-le! target-bv buf-off val)))
                              (else
                               (display-stderr (string-append "ulisp --ld: warning: unsupported relocation type: " (number->string r-type) "\n"))))))
                      (apply-r (cdr rs)))))
              (apply-objs (cdr objs)))))

      ;; 7. Resolve Entry Point Symbol
      (let* ((entry-name (if entry-sym entry-sym "_start"))
             (entry-lookup (symbol-map-get global-syms entry-name))
             (entry-vaddr (if entry-lookup
                              (car (cdr entry-lookup))
                              (begin
                                (display-stderr (string-append "ulisp --ld: error: entry point symbol '" entry-name "' not found\n"))
                                (compiler-abort-and-cleanup! 1)))))

        ;; 8. Write ELF64 Header & Program Headers (3 headers: PT_LOAD RX, PT_LOAD RW, PT_GNU_STACK)
        (elf64-write-ehdr-ex! seg1-bv entry-vaddr 64 3)
        ;; Program Header 0: PT_LOAD RX (flags 5)
        (elf64-write-phdr-base! seg1-bv 64 1 5 0 4194304)
        (elf64-write-phdr-sizes! seg1-bv 64 seg1-filesz seg1-memsz 4096)
        ;; Program Header 1: PT_LOAD RW (flags 6)
        (elf64-write-phdr-base! seg1-bv 120 1 6 seg1-filesz seg2-base-vaddr)
        (elf64-write-phdr-sizes! seg1-bv 120 seg2-filesz seg2-memsz 4096)
        ;; Program Header 2: PT_GNU_STACK RW (flags 6, p_type 0x6474e551)
        (elf64-write-phdr-base! seg1-bv 176 1685382481 6 0 0)
        (elf64-write-phdr-sizes! seg1-bv 176 0 0 16)

        ;; 9. Assemble Complete Binary Bytevector
        (let* ((total-size (+ seg1-filesz seg2-filesz))
               (final-bv (make-bytevector total-size 0)))
          (elf64-copy-bytes! final-bv 0 seg1-bv 0 seg1-filesz)
          (elf64-copy-bytes! final-bv seg1-filesz seg2-bv 0 seg2-filesz)
          final-bv)))))


