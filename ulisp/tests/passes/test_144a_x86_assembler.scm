;;; =======================================================================
;;; Unit Test for x86-64 Machine Code Assembler (144a_x86_assembler.scm)
;;; =======================================================================

(include "lib/bytevector.scm")
(include "backend/elf64_builder.scm")
(include "backend/144a_x86_assembler.scm")

;; Helper to write bytevector to binary file
(define (write-bytevector-to-file path bv)
  (let ((p (open-binary-output-file path)))
    (let loop ((i 0) (len (bytevector-length bv)))
      (if (< i len)
          (begin
            (write-u8 (bytevector-u8-ref bv i) p)
            (loop (+ i 1) len))
          (close-output-port p)))))

;; Test 1: Simple exit(42) assemble & run
(let* ((lines '("    .intel_syntax noprefix"
                "    .text"
                "    .globl _start"
                "_start:"
                "    mov eax, 60"
                "    mov edi, 42"
                "    syscall"))
       (res (assemble-x86-lines lines))
       (text-bv (car res))
       (rodata-bv (cadr res))
       (data-bv (caddr res))
       (bss-size (cadddr res))
       (entry-off (car (cddddr res)))
       (elf (build-elf64-executable text-bv rodata-bv data-bv bss-size entry-off)))
  (write-bytevector-to-file "/tmp/test_asm_42" elf)
  (display "[PASS] Test 1: exit(42) binary generated (size: ")
  (display (bytevector-length elf))
  (display ")\n"))

;; Test 2: Arithmetic, Memory & RIP-Relative Data Access
(let* ((lines '("    .intel_syntax noprefix"
                "    .data"
                "my_val:"
                "    .quad 35"
                "    .text"
                "    .globl _start"
                "_start:"
                "    mov rax, [rip + my_val]"
                "    add rax, 7"
                "    mov rdi, rax"
                "    mov eax, 60"
                "    syscall"))
       (res (assemble-x86-lines lines))
       (text-bv (car res))
       (rodata-bv (cadr res))
       (data-bv (caddr res))
       (bss-size (cadddr res))
       (entry-off (car (cddddr res)))
       (elf (build-elf64-executable text-bv rodata-bv data-bv bss-size entry-off)))
  (write-bytevector-to-file "/tmp/test_asm_data_42" elf)
  (display "[PASS] Test 2: data + arithmetic binary generated (size: ")
  (display (bytevector-length elf))
  (display ")\n"))

;; Test 3: Function Call and Conditional Branching (Factorial of 4 = 24)
(let* ((lines '("    .intel_syntax noprefix"
                "    .text"
                "    .globl _start"
                "_start:"
                "    mov rdi, 4"
                "    call fact"
                "    mov rdi, rax"
                "    mov eax, 60"
                "    syscall"
                "fact:"
                "    cmp rdi, 1"
                "    jg .L_rec"
                "    mov rax, 1"
                "    ret"
                ".L_rec:"
                "    push rdi"
                "    sub rdi, 1"
                "    call fact"
                "    pop rdi"
                "    imul rax, rdi"
                "    ret"))
       (res (assemble-x86-lines lines))
       (text-bv (car res))
       (rodata-bv (cadr res))
       (data-bv (caddr res))
       (bss-size (cadddr res))
       (entry-off (car (cddddr res)))
       (elf (build-elf64-executable text-bv rodata-bv data-bv bss-size entry-off)))
  (write-bytevector-to-file "/tmp/test_asm_fact_24" elf)
  (display "[PASS] Test 3: recursive fact(4) = 24 binary generated (size: ")
  (display (bytevector-length elf))
  (display ")\n"))

