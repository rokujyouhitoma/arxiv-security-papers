;;; =======================================================================
;;; ULisp Compiler Backend: Common Static ELF64 Executable Builder
;;; Conforms to DSN-33 Architecture Specification & Issue #616
;;; System V ABI AMD64 Architecture Processor Supplement Compliant
;;; =======================================================================
;;; Synthesizes standalone, self-contained ELF64 ET_EXEC executable binaries
;;; directly into a Scheme bytevector with strict W^X separation.
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

;; -----------------------------------------------------------------------
;; Section Header Table String Helper
;; -----------------------------------------------------------------------
;; "\x00.text\x00.rodata\x00.data\x00.bss\x00.shstrtab\x00"
(define (elf64-make-shstrtab-bytes)
  ;; Indices:
  ;; 0: ""
  ;; 1: ".text"
  ;; 7: ".rodata"
  ;; 15: ".data"
  ;; 21: ".bss"
  ;; 26: ".shstrtab"
  (elf64-list->bytevector
    '(0
      46 116 101 120 116 0          ; .text\0
      46 114 111 100 97 116 97 0    ; .rodata\0
      46 100 97 116 97 0            ; .data\0
      46 98 115 115 0               ; .bss\0
      46 115 104 115 116 114 116 97 98 0))) ; .shstrtab\0

;; -----------------------------------------------------------------------
;; Main ELF64 Executable Builder
;; -----------------------------------------------------------------------
;; Arguments:
;;   text-bv        : bytevector of machine code (.text)
;;   rodata-bv      : bytevector of read-only data (.rodata)
;;   data-bv        : bytevector of mutable data (.data)
;;   bss-size       : integer size in bytes of zero-initialized .bss
;;   entry-offset   : byte offset within text-bv where _start entrypoint begins
;; Returns:
;;   Full ELF64 executable bytevector ready to write to disk.
(define (build-elf64-executable text-bv rodata-bv data-bv bss-size entry-offset)
  (let* (;; Fixed Header Layout
         (ehdr-size 64)
         (phdr-entry-size 56)
         (phnum 2) ;; 1: PT_LOAD RX (Text + Rodata), 2: PT_LOAD RW (Data + Bss)
         (phdrs-size (* phnum phdr-entry-size))
         (headers-total-size (+ ehdr-size phdrs-size)) ;; 64 + 112 = 176 (0xB0)

         ;; Text Segment starts at file offset headers-total-size
         (text-file-offset headers-total-size)
         (text-len (bytevector-length text-bv))
         (rodata-len (bytevector-length rodata-bv))
         (data-len (bytevector-length data-bv))

         ;; Virtual Memory Base Addresses (conforms to Linux System V ABI x86-64)
         (vaddr-text-base 4194304)
         (entry-vaddr (+ (+ vaddr-text-base text-file-offset) entry-offset))
         (vaddr-data-base 6291456)

         ;; Total filesz of Text segment includes headers + text + rodata
         ;; Padded to 4096 (0x1000) alignment to satisfy Linux kernel requirement:
         ;; (p_vaddr % PAGE_SIZE) == (p_offset % PAGE_SIZE)
         (rx-content-len (+ (+ text-file-offset text-len) rodata-len))
         (text-segment-filesz (elf64-align-up rx-content-len 4096))

         ;; Data Segment starts at file offset text-segment-filesz (4KB aligned)
         (data-file-offset text-segment-filesz)
         (data-segment-filesz data-len)
         (data-segment-memsz (+ data-len bss-size))

         ;; Section Header Table Layout
         (shdr-entry-size 64)
         (shnum 6) ;; 0: NULL, 1: .text, 2: .rodata, 3: .data, 4: .bss, 5: .shstrtab
         (shdrs-total-size (* shnum shdr-entry-size))
         (shstrtab-bytes (elf64-make-shstrtab-bytes))
         (shstrtab-len (bytevector-length shstrtab-bytes))

         ;; Place Section Header Table after data content
         (shoff (elf64-align-up (+ data-file-offset data-len) 8))
         (shstrtab-offset (+ shoff shdrs-total-size))
         (total-elf-size (+ shstrtab-offset shstrtab-len))

         ;; Allocate complete binary bytevector
         (elf-bv (make-bytevector total-elf-size)))

    ;; -------------------------------------------------------------------
    ;; 1. Write ELF Header (64 bytes)
    ;; -------------------------------------------------------------------
    ;; e_ident[0..3] = 0x7f, 'E', 'L', 'F'
    (elf64-set-u8! elf-bv 0 127)
    (elf64-set-u8! elf-bv 1 69)
    (elf64-set-u8! elf-bv 2 76)
    (elf64-set-u8! elf-bv 3 70)
    (elf64-set-u8! elf-bv 4 2)   ;; EI_CLASS = 2 (64-bit)
    (elf64-set-u8! elf-bv 5 1)   ;; EI_DATA = 1 (Little Endian)
    (elf64-set-u8! elf-bv 6 1)   ;; EI_VERSION = 1
    (elf64-set-u8! elf-bv 7 0)   ;; EI_OSABI = 0 (System V)
    (elf64-set-u8! elf-bv 8 0)   ;; EI_ABIVERSION = 0

    (elf64-set-u16-le! elf-bv 16 2)               ;; e_type = ET_EXEC (2)
    (elf64-set-u16-le! elf-bv 18 62)              ;; e_machine = EM_X86_64 (62)
    (elf64-set-u32-le! elf-bv 20 1)               ;; e_version = 1
    (elf64-set-u64-le! elf-bv 24 entry-vaddr)     ;; e_entry
    (elf64-set-u64-le! elf-bv 32 ehdr-size)       ;; e_phoff = 64
    (elf64-set-u64-le! elf-bv 40 shoff)           ;; e_shoff
    (elf64-set-u32-le! elf-bv 48 0)               ;; e_flags = 0
    (elf64-set-u16-le! elf-bv 52 ehdr-size)       ;; e_ehsize = 64
    (elf64-set-u16-le! elf-bv 54 phdr-entry-size) ;; e_phentsize = 56
    (elf64-set-u16-le! elf-bv 56 phnum)           ;; e_phnum = 2
    (elf64-set-u16-le! elf-bv 58 shdr-entry-size) ;; e_shentsize = 64
    (elf64-set-u16-le! elf-bv 60 shnum)           ;; e_shnum = 6
    (elf64-set-u16-le! elf-bv 62 5)               ;; e_shstrndx = 5 (.shstrtab)

    ;; -------------------------------------------------------------------
    ;; 2. Write Program Headers (2 x 56 bytes = 112 bytes)
    ;; -------------------------------------------------------------------
    ;; Phdr 1: PT_LOAD RX Segment (.text + .rodata + headers)
    (let ((ph1-off 64))
      (elf64-set-u32-le! elf-bv ph1-off 1)                     ;; p_type = PT_LOAD (1)
      (elf64-set-u32-le! elf-bv (+ ph1-off 4) 5)               ;; p_flags = PF_R | PF_X (5)
      (elf64-set-u64-le! elf-bv (+ ph1-off 8) 0)               ;; p_offset = 0
      (elf64-set-u64-le! elf-bv (+ ph1-off 16) vaddr-text-base) ;; p_vaddr
      (elf64-set-u64-le! elf-bv (+ ph1-off 24) vaddr-text-base) ;; p_paddr
      (elf64-set-u64-le! elf-bv (+ ph1-off 32) text-segment-filesz) ;; p_filesz
      (elf64-set-u64-le! elf-bv (+ ph1-off 40) text-segment-filesz) ;; p_memsz
      (elf64-set-u64-le! elf-bv (+ ph1-off 48) 4096))        ;; p_align = 4KB

    ;; Phdr 2: PT_LOAD RW Segment (.data + .bss)
    (let ((ph2-off (+ 64 phdr-entry-size)))
      (elf64-set-u32-le! elf-bv ph2-off 1)                     ;; p_type = PT_LOAD (1)
      (elf64-set-u32-le! elf-bv (+ ph2-off 4) 6)               ;; p_flags = PF_R | PF_W (6)
      (elf64-set-u64-le! elf-bv (+ ph2-off 8) data-file-offset) ;; p_offset (4KB aligned)
      (elf64-set-u64-le! elf-bv (+ ph2-off 16) vaddr-data-base) ;; p_vaddr
      (elf64-set-u64-le! elf-bv (+ ph2-off 24) vaddr-data-base) ;; p_paddr
      (elf64-set-u64-le! elf-bv (+ ph2-off 32) data-segment-filesz) ;; p_filesz
      (elf64-set-u64-le! elf-bv (+ ph2-off 40) data-segment-memsz)  ;; p_memsz
      (elf64-set-u64-le! elf-bv (+ ph2-off 48) 4096))        ;; p_align = 4KB

    ;; -------------------------------------------------------------------
    ;; 3. Copy Segment Payloads into elf-bv
    ;; -------------------------------------------------------------------
    ;; Copy text-bv
    (if (> text-len 0)
        (elf64-copy-bytes! elf-bv text-file-offset text-bv 0 text-len))

    ;; Copy rodata-bv right after text-bv
    (let ((rodata-file-offset (+ text-file-offset text-len)))
      (if (> rodata-len 0)
          (elf64-copy-bytes! elf-bv rodata-file-offset rodata-bv 0 rodata-len)))

    ;; Fill padding between rodata and data-file-offset with NOP (0x90)
    (let loop ((i (+ (+ text-file-offset text-len) rodata-len)))
      (if (< i data-file-offset)
          (begin
            (bytevector-u8-set! elf-bv i 144)
            (loop (+ i 1)))))

    ;; Copy data-bv
    (if (> data-len 0)
        (elf64-copy-bytes! elf-bv data-file-offset data-bv 0 data-len))

    ;; -------------------------------------------------------------------
    ;; 4. Write Section Header Table (6 entries x 64 bytes)
    ;; -------------------------------------------------------------------
    (let ((rodata-file-offset (+ text-file-offset text-len))
          (vaddr-rodata (+ (+ vaddr-text-base text-file-offset) text-len))
          (vaddr-bss (+ vaddr-data-base data-len)))

      ;; Entry 0: SHN_UNDEF (all zeroes) - already 0

      ;; Entry 1: .text (PROGBITS, SHF_ALLOC | SHF_EXECINSTR = 6)
      (let ((s1 (+ shoff (* 1 shdr-entry-size))))
        (elf64-set-u32-le! elf-bv s1 1)                               ;; sh_name -> ".text"
        (elf64-set-u32-le! elf-bv (+ s1 4) 1)                         ;; sh_type = SHT_PROGBITS (1)
        (elf64-set-u64-le! elf-bv (+ s1 8) 6)                         ;; sh_flags = SHF_ALLOC | SHF_EXECINSTR
        (elf64-set-u64-le! elf-bv (+ s1 16) (+ vaddr-text-base text-file-offset)) ;; sh_addr
        (elf64-set-u64-le! elf-bv (+ s1 24) text-file-offset)         ;; sh_offset
        (elf64-set-u64-le! elf-bv (+ s1 32) text-len)                 ;; sh_size
        (elf64-set-u64-le! elf-bv (+ s1 48) 16))                      ;; sh_addralign = 16

      ;; Entry 2: .rodata (PROGBITS, SHF_ALLOC = 2)
      (let ((s2 (+ shoff (* 2 shdr-entry-size))))
        (elf64-set-u32-le! elf-bv s2 7)                               ;; sh_name -> ".rodata"
        (elf64-set-u32-le! elf-bv (+ s2 4) 1)                         ;; sh_type = SHT_PROGBITS (1)
        (elf64-set-u64-le! elf-bv (+ s2 8) 2)                         ;; sh_flags = SHF_ALLOC (2)
        (elf64-set-u64-le! elf-bv (+ s2 16) vaddr-rodata)             ;; sh_addr
        (elf64-set-u64-le! elf-bv (+ s2 24) rodata-file-offset)       ;; sh_offset
        (elf64-set-u64-le! elf-bv (+ s2 32) rodata-len)               ;; sh_size
        (elf64-set-u64-le! elf-bv (+ s2 48) 8))                       ;; sh_addralign = 8

      ;; Entry 3: .data (PROGBITS, SHF_ALLOC | SHF_WRITE = 3)
      (let ((s3 (+ shoff (* 3 shdr-entry-size))))
        (elf64-set-u32-le! elf-bv s3 15)                              ;; sh_name -> ".data"
        (elf64-set-u32-le! elf-bv (+ s3 4) 1)                         ;; sh_type = SHT_PROGBITS (1)
        (elf64-set-u64-le! elf-bv (+ s3 8) 3)                         ;; sh_flags = SHF_ALLOC | SHF_WRITE (3)
        (elf64-set-u64-le! elf-bv (+ s3 16) vaddr-data-base)          ;; sh_addr
        (elf64-set-u64-le! elf-bv (+ s3 24) data-file-offset)         ;; sh_offset
        (elf64-set-u64-le! elf-bv (+ s3 32) data-len)                 ;; sh_size
        (elf64-set-u64-le! elf-bv (+ s3 48) 8))                       ;; sh_addralign = 8

      ;; Entry 4: .bss (NOBITS, SHF_ALLOC | SHF_WRITE = 3)
      (let ((s4 (+ shoff (* 4 shdr-entry-size))))
        (elf64-set-u32-le! elf-bv s4 21)                              ;; sh_name -> ".bss"
        (elf64-set-u32-le! elf-bv (+ s4 4) 8)                         ;; sh_type = SHT_NOBITS (8)
        (elf64-set-u64-le! elf-bv (+ s4 8) 3)                         ;; sh_flags = SHF_ALLOC | SHF_WRITE (3)
        (elf64-set-u64-le! elf-bv (+ s4 16) vaddr-bss)                ;; sh_addr
        (elf64-set-u64-le! elf-bv (+ s4 24) (+ data-file-offset data-len)) ;; sh_offset
        (elf64-set-u64-le! elf-bv (+ s4 32) bss-size)                 ;; sh_size
        (elf64-set-u64-le! elf-bv (+ s4 48) 8))                       ;; sh_addralign = 8

      ;; Entry 5: .shstrtab (STRTAB = 3)
      (let ((s5 (+ shoff (* 5 shdr-entry-size))))
        (elf64-set-u32-le! elf-bv s5 26)                              ;; sh_name -> ".shstrtab"
        (elf64-set-u32-le! elf-bv (+ s5 4) 3)                         ;; sh_type = SHT_STRTAB (3)
        (elf64-set-u64-le! elf-bv (+ s5 8) 0)                         ;; sh_flags = 0
        (elf64-set-u64-le! elf-bv (+ s5 16) 0)                        ;; sh_addr = 0
        (elf64-set-u64-le! elf-bv (+ s5 24) shstrtab-offset)          ;; sh_offset
        (elf64-set-u64-le! elf-bv (+ s5 32) shstrtab-len)             ;; sh_size
        (elf64-set-u64-le! elf-bv (+ s5 48) 1)))                      ;; sh_addralign = 1

    ;; Write .shstrtab bytes
    (elf64-copy-bytes! elf-bv shstrtab-offset shstrtab-bytes 0 shstrtab-len)

    ;; Return synthesized executable bytevector
    elf-bv))
