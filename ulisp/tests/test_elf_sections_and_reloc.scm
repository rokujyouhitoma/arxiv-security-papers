;;; =======================================================================
;;; Unit Test Suite: ELF Section Abstraction & Relocations in Assembler & Linker
;;; Issue #830 - Conforms to DSN-38 Section 2 (C3/E7/F1/F2/H2) & DSN-33
;;; =======================================================================

(display "=======================================================\n")
(display " Starting ELF Sections & Relocations Test Suite (#830)\n")
(display "=======================================================\n")

;; Helper to write bytevector to binary file
(define (write-bytevector-to-file path bv)
  (let ((p (open-binary-output-file path)))
    (let loop ((i 0) (len (bytevector-length bv)))
      (if (< i len)
          (begin
            (write-u8 (bytevector-u8-ref bv i) p)
            (loop (+ i 1) len))
          (close-output-port p)))))

(define (find-reloc-by-type relocs target-type)
  (let loop ((rs relocs))
    (if (null? rs)
        #f
        (let ((r (car rs)))
          (if (and (pair? (cdddr r))
                   (= (cadddr r) target-type))
              r
              (loop (cdr rs)))))))

(test-begin "ELF Sections and Relocations Suite (#830)")

;;; -----------------------------------------------------------------------
;;; Group 1: Assembler Data Directives
;;; -----------------------------------------------------------------------
(print-group "--- Group 1: Assembler Data Directives ---")

;; 1.1 .byte directive (comma-separated, hex, decimal, negative)
(let* ((lines '(".data" ".byte 10, 20, 0x30, -5"))
       (res (assemble-x86-lines lines))
       (data-bv (caddr res)))
  (assert-equal ".byte 4 elements length" 4 (bytevector-length data-bv))
  (assert-equal ".byte elem 0" 10 (bytevector-u8-ref data-bv 0))
  (assert-equal ".byte elem 1" 20 (bytevector-u8-ref data-bv 1))
  (assert-equal ".byte elem 2 (0x30)" 48 (bytevector-u8-ref data-bv 2))
  (assert-equal ".byte elem 3 (-5 -> 251)" 251 (bytevector-u8-ref data-bv 3)))

;; 1.2 .short and .2byte directives
(let* ((lines '(".data" ".short 0x1234, -1" ".2byte 0x5678"))
       (res (assemble-x86-lines lines))
       (data-bv (caddr res)))
  (assert-equal ".short/.2byte total length 6" 6 (bytevector-length data-bv))
  (assert-equal ".short 0x1234 le" #x1234 (elf64-get-u16-le data-bv 0))
  (assert-equal ".short -1 le" #xffff (elf64-get-u16-le data-bv 2))
  (assert-equal ".2byte 0x5678 le" #x5678 (elf64-get-u16-le data-bv 4)))

;; 1.3 .long and .4byte directives
(let* ((lines '(".data" ".long 0x12345678, -2" ".4byte 0xaabbccdd"))
       (res (assemble-x86-lines lines))
       (data-bv (caddr res)))
  (assert-equal ".long/.4byte total length 12" 12 (bytevector-length data-bv))
  (assert-equal ".long 0x12345678 le" #x12345678 (elf64-get-u32-le data-bv 0))
  (assert-equal ".long -2 le" (- 4294967296 2) (elf64-get-u32-le data-bv 4))
  (assert-equal ".4byte 0xaabbccdd le" #xaabbccdd (elf64-get-u32-le data-bv 8)))

;; 1.4 .quad and .8byte directives
(let* ((lines '(".data" ".quad 0x0102030405060708" ".8byte 42"))
       (res (assemble-x86-lines lines))
       (data-bv (caddr res)))
  (assert-equal ".quad/.8byte total length 16" 16 (bytevector-length data-bv))
  (assert-equal ".quad value" #x0102030405060708 (elf64-get-u64-le data-bv 0))
  (assert-equal ".8byte value" 42 (elf64-get-u64-le data-bv 8)))

;; 1.5 String directives (.string, .asciz, .ascii)
(let* ((lines '(".rodata" ".string \"hello\"" ".asciz \"ab\"" ".ascii \"xyz\""))
       (res (assemble-x86-lines lines))
       (rodata-bv (cadr res)))
  ;; "hello\0" (6) + "ab\0" (3) + "xyz" (3) = 12 bytes
  (assert-equal "string directives length 12" 12 (bytevector-length rodata-bv))
  (assert-equal ".string byte 0 'h'" (char->integer #\h) (bytevector-u8-ref rodata-bv 0))
  (assert-equal ".string byte 4 'o'" (char->integer #\o) (bytevector-u8-ref rodata-bv 4))
  (assert-equal ".string null term 0" 0 (bytevector-u8-ref rodata-bv 5))
  (assert-equal ".asciz byte 0 'a'" (char->integer #\a) (bytevector-u8-ref rodata-bv 6))
  (assert-equal ".asciz null term 0" 0 (bytevector-u8-ref rodata-bv 8))
  (assert-equal ".ascii byte 0 'x'" (char->integer #\x) (bytevector-u8-ref rodata-bv 9))
  (assert-equal ".ascii byte 2 'z'" (char->integer #\z) (bytevector-u8-ref rodata-bv 11)))

;; 1.6 Storage directives (.space, .zero, .fill)
(let* ((lines '(".data" ".space 4, 0xaa" ".zero 2" ".fill 3, 2, 0x1234"))
       (res (assemble-x86-lines lines))
       (data-bv (caddr res)))
  ;; 4 bytes (0xaa) + 2 bytes (0x00) + 6 bytes (0x34 0x12 0x34 0x12 0x34 0x12) = 12 bytes
  (assert-equal "space/zero/fill length 12" 12 (bytevector-length data-bv))
  (assert-equal ".space bytes pos 0" #xaa (bytevector-u8-ref data-bv 0))
  (assert-equal ".space bytes pos 3" #xaa (bytevector-u8-ref data-bv 3))
  (assert-equal ".zero bytes pos 4" 0 (bytevector-u8-ref data-bv 4))
  (assert-equal ".zero bytes pos 5" 0 (bytevector-u8-ref data-bv 5))
  (assert-equal ".fill repeat 0" #x1234 (elf64-get-u16-le data-bv 6))
  (assert-equal ".fill repeat 1" #x1234 (elf64-get-u16-le data-bv 8))
  (assert-equal ".fill repeat 2" #x1234 (elf64-get-u16-le data-bv 10)))

;;; -----------------------------------------------------------------------
;;; Group 2: Section Switching & Alignment (.section, .pushsection, .align)
;;; -----------------------------------------------------------------------
(print-group "--- Group 2: Section Switching & Alignment ---")

(let* ((lines '(".section .text"
                "  nop"
                ".section .rodata"
                "  .byte 1, 2"
                ".section .data"
                "  .long 0x11223344"
                ".pushsection .text"
                "  nop"
                ".pushsection .data"
                "  .align 16"
                "  .byte 0xff"
                ".section .bss"
                "  .space 32"
                ".section .init_array"
                "  .quad 0x1234"
                ".section ulisp_globals_sec"
                "  .quad 0x5678"))
       (res (assemble-x86-relocatable lines))
       (text-bv (car res))
       (rodata-bv (cadr res))
       (data-bv (caddr res))
       (bss-len (cadddr res))
       (init-bv (car (cddddr res)))
       (globals-bv (cadr (cddddr res))))
  (assert-equal "multi-section text length (2 nops)" 2 (bytevector-length text-bv))
  (assert-equal "multi-section rodata length" 2 (bytevector-length rodata-bv))
  (assert-true "multi-section data aligned to 16 with .byte" (>= (bytevector-length data-bv) 17))
  (assert-equal "multi-section bss size" 32 bss-len)
  (assert-equal "multi-section init_array length" 8 (bytevector-length init-bv))
  (assert-equal "multi-section ulisp_globals_sec length" 8 (bytevector-length globals-bv)))

;;; -----------------------------------------------------------------------
;;; Group 3: Symbol Binding & Type Directives (.globl, .weak, .type)
;;; -----------------------------------------------------------------------
(print-group "--- Group 3: Symbol Binding & Type Directives ---")

(let* ((lines '(".intel_syntax noprefix"
                ".globl fn_g1, fn_g2"
                ".weak fn_w1"
                ".type fn_g1, @function"
                ".type obj_1, @object"
                ".text"
                "fn_g1:"
                "  ret"
                "fn_g2:"
                "  ret"
                "fn_w1:"
                "  ret"
                ".data"
                "obj_1:"
                "  .long 99"))
       (res (assemble-x86-relocatable lines))
       (globls (cadddr (cddddr res)))
       (rest8 (cddddr (cddddr res)))
       (weaks (car rest8))
       (types (cadr rest8)))
  (assert-true "globl fn_g1 extracted" (if (member "fn_g1" globls) #t #f))
  (assert-true "globl fn_g2 extracted" (if (member "fn_g2" globls) #t #f))
  (assert-true "weak fn_w1 extracted" (if (member "fn_w1" weaks) #t #f))
  (assert-equal "type of fn_g1 is @function (STT_FUNC = 2)" 2 (cdr (assoc "fn_g1" types)))
  (assert-equal "type of obj_1 is @object (STT_OBJECT = 1)" 1 (cdr (assoc "obj_1" types))))

;;; -----------------------------------------------------------------------
;;; Group 4: Relocation Types (R_X86_64_64, PC32, PLT32, 32)
;;; -----------------------------------------------------------------------
(print-group "--- Group 4: Relocation Types ---")

(let* ((lines '(".intel_syntax noprefix"
                ".globl _start, ext_fn, ext_data"
                ".text"
                "_start:"
                "  call ext_fn"
                "  mov rax, [rip + ext_data]"
                ".data"
                "table:"
                "  .long ext_data"
                "  .quad ext_fn"))
       (res (assemble-x86-relocatable lines))
       (rest8 (cddddr (cddddr res)))
       (relocs (caddr rest8)))
  (let ((has-plt32 (find-reloc-by-type relocs 4))
        (has-pc32 (find-reloc-by-type relocs 2))
        (has-abs32 (find-reloc-by-type relocs 10))
        (has-abs64 (find-reloc-by-type relocs 1)))
    (assert-true "reloc R_X86_64_PLT32 (4) emitted for call ext_fn" (pair? has-plt32))
    (assert-true "reloc R_X86_64_PC32 (2) emitted for rip + ext_data" (pair? has-pc32))
    (assert-true "reloc R_X86_64_32 (10) emitted for .long ext_data" (pair? has-abs32))
    (assert-true "reloc R_X86_64_64 (1) emitted for .quad ext_fn" (pair? has-abs64))))

;;; -----------------------------------------------------------------------
;;; Group 5: build-elf64-relocatable & Symbol Table Partitioning
;;; -----------------------------------------------------------------------
(print-group "--- Group 5: build-elf64-relocatable & Symbol Table Partitioning ---")

(let* ((lines '(".intel_syntax noprefix"
                ".globl global_entry"
                ".type global_entry, @function"
                ".type local_calc, @function"
                ".text"
                "local_calc:"
                "  mov eax, 42"
                "  ret"
                "global_entry:"
                "  call local_calc"
                "  ret"))
       (assembled (assemble-x86-relocatable lines))
       (obj-bv (build-elf64-relocatable assembled)))
  (write-bytevector-to-file "build/test_reloc_part.o" obj-bv)
  (let ((parsed (elf64-parse-relocatable-object obj-bv "build/test_reloc_part.o")))
    (assert-true "parsed relocatable object valid vector" (vector? parsed))
    (let* ((sec-vec (vector-ref parsed 1))
           (symtab-sec (let loop ((i 0))
                         (if (< i (vector-length sec-vec))
                             (let ((s (vector-ref sec-vec i)))
                               (if (string=? (vector-ref s 1) ".symtab")
                                   s
                                   (loop (+ i 1))))
                             #f)))
           (sh-info (vector-ref symtab-sec 7))
           (sym-vec (vector-ref parsed 2)))
      (assert-true "symtab section header found" (vector? symtab-sec))
      (assert-true "sh_info is positive (points to first non-local)" (> sh-info 0))
      ;; Verify strict ELF partitioning: every symbol before sh-info has STB_LOCAL (0)
      ;; and every symbol from sh-info onwards has STB_GLOBAL (1) or STB_WEAK (2)
      (let loop ((i 1))
        (if (< i (vector-length sym-vec))
            (let* ((sym (vector-ref sym-vec i))
                   (bind (vector-ref sym 2)))
              (if (< i sh-info)
                  (assert-equal (string-append "sym " (vector-ref sym 1) " before sh_info is STB_LOCAL") 0 bind)
                  (assert-true (string-append "sym " (vector-ref sym 1) " at/after sh_info is STB_GLOBAL/WEAK") (> bind 0)))
              (loop (+ i 1)))
            #t)))))

;;; -----------------------------------------------------------------------
;;; Group 6: Static Multi-Object Linking
;;; -----------------------------------------------------------------------
(print-group "--- Group 6: Static Multi-Object Linking ---")

(let* ((mod1-lines '(".intel_syntax noprefix"
                     ".globl _start, compute_answer"
                     ".text"
                     "_start:"
                     "  call compute_answer"
                     "  mov rdi, rax"
                     "  mov eax, 60"
                     "  syscall"))
       (mod2-lines '(".intel_syntax noprefix"
                     ".globl compute_answer, answer_data"
                     ".data"
                     "answer_data:"
                     "  .long 42"
                     ".text"
                     "compute_answer:"
                     "  mov eax, [rip + answer_data]"
                     "  ret"))
       (obj1-bv (build-elf64-relocatable (assemble-x86-relocatable mod1-lines)))
       (obj2-bv (build-elf64-relocatable (assemble-x86-relocatable mod2-lines)))
       (exec-bv (link-elf64-relocatable-objects (list obj1-bv obj2-bv) "_start")))
  (assert-true "linked executable bytevector generated" (> (bytevector-length exec-bv) 0))
  (assert-equal "ELF magic 0 (127)" 127 (elf64-get-u8 exec-bv 0))
  (assert-equal "ELF magic 1 ('E')" 69 (elf64-get-u8 exec-bv 1))
  (assert-equal "ELF magic 2 ('L')" 76 (elf64-get-u8 exec-bv 2))
  (assert-equal "ELF magic 3 ('F')" 70 (elf64-get-u8 exec-bv 3))
  (assert-equal "e_type == ET_EXEC (2)" 2 (elf64-get-u16-le exec-bv 16))
  (write-bytevector-to-file "build/test_linked_multi_obj" exec-bv))

(test-end "ELF Sections and Relocations Suite (#830)")
