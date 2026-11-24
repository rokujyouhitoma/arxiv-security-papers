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

;; Test 4: Issue #933 - Backward Short Jump (rel8: EB cb / 75 cb) encoding
(let* ((lines '("    .intel_syntax noprefix"
                "    .text"
                ".L_loop:"
                "    sub rdi, 1"
                "    jne .L_loop"
                "    jmp .L_loop"))
       (res (assemble-x86-lines lines))
       (text-bv (car res))
       (tlen (bytevector-length text-bv)))
  ;; sub rdi, 1 is 4 bytes (48 83 EF 01)
  ;; backward jne .L_loop is 2 bytes (75 FA = disp8 -6)
  ;; backward jmp .L_loop is 2 bytes (EB F8 = disp8 -8)
  ;; Total text-bv length must be 8 bytes (instead of 4 + 6 + 5 = 15 bytes)
  (if (and (= tlen 8)
           (= (bytevector-u8-ref text-bv 4) 117) ;; 0x75 (jne rel8)
           (= (bytevector-u8-ref text-bv 5) 250) ;; 0xFA (-6)
           (= (bytevector-u8-ref text-bv 6) 235) ;; 0xEB (jmp rel8)
           (= (bytevector-u8-ref text-bv 7) 248)) ;; 0xF8 (-8)
      (display "[PASS] Test 4: backward short jump rel8 (EB cb / 75 cb) encoded in 2 bytes\n")
      (begin
        (display "[FAIL] Test 4: unexpected text-bv length or bytes: ")
        (display tlen)
        (newline)
        (exit 1))))

;; Test 5: Issue #935 - Variable Shift by CL (shl/shr/sar rax, cl -> 48 D3 E0/E8/F8)
(let* ((lines '("    .intel_syntax noprefix"
                "    .text"
                "    shl rax, cl"
                "    shr rax, cl"
                "    sar rax, cl"))
       (res (assemble-x86-lines lines))
       (text-bv (car res))
       (tlen (bytevector-length text-bv)))
  (if (and (= tlen 9)
           (= (bytevector-u8-ref text-bv 0) 72)
           (= (bytevector-u8-ref text-bv 1) 211)
           (= (bytevector-u8-ref text-bv 2) 224)
           (= (bytevector-u8-ref text-bv 3) 72)
           (= (bytevector-u8-ref text-bv 4) 211)
           (= (bytevector-u8-ref text-bv 5) 232)
           (= (bytevector-u8-ref text-bv 6) 72)
           (= (bytevector-u8-ref text-bv 7) 211)
           (= (bytevector-u8-ref text-bv 8) 248))
      (display "[PASS] Test 5: shl/shr/sar rax, cl encoded as REX.W D3 E0/E8/F8\n")
      (begin
        (display "[FAIL] Test 5: unexpected CL shift encoding length/bytes: ")
        (display tlen)
        (newline)
        (exit 1))))

;; Test 6: Issue #953 - Short 32-bit zero-extending encoding for mov r64, imm32 (0 <= imm < 2^32)
(let* ((lines '("    .intel_syntax noprefix"
                "    .text"
                "    mov rax, 42"
                "    mov r10, 42"
                "    mov rax, -1"))
       (res (assemble-x86-lines lines))
       (text-bv (car res))
       (tlen (bytevector-length text-bv)))
  ;; mov rax, 42  -> B8 2A 00 00 00 (5 bytes)
  ;; mov r10, 42  -> 41 BA 2A 00 00 00 (6 bytes)
  ;; mov rax, -1  -> 48 C7 C0 FF FF FF FF (7 bytes)
  ;; Total: 18 bytes
  (if (and (= tlen 18)
           (= (bytevector-u8-ref text-bv 0) 184) ;; 0xB8
           (= (bytevector-u8-ref text-bv 1) 42)
           (= (bytevector-u8-ref text-bv 5) 65)  ;; 0x41 (REX.B)
           (= (bytevector-u8-ref text-bv 6) 186) ;; 0xBA
           (= (bytevector-u8-ref text-bv 7) 42)
           (= (bytevector-u8-ref text-bv 11) 72) ;; 0x48 (REX.W)
           (= (bytevector-u8-ref text-bv 12) 199) ;; 0xC7
           (= (bytevector-u8-ref text-bv 13) 192)) ;; 0xC0
      (display "[PASS] Test 6: mov r64, imm32 short 5/6-byte encoding verified (#953)\n")
      (begin
        (display "[FAIL] Test 6: unexpected mov r64, imm32 encoding length/bytes: ")
        (display tlen)
        (newline)
        (exit 1))))

;; Test 7: Issue #955 - jo / jno short (70/71 rel8) and near (0F 80/81 rel32) encoding
(let* ((lines '("    .intel_syntax noprefix"
                "    .text"
                ".L_back:"
                "    jo .L_fwd"
                "    jno .L_fwd"
                "    jo .L_back"
                "    jno .L_back"
                ".L_fwd:"
                "    ret"))
       (res (assemble-x86-lines lines))
       (text-bv (car res))
       (tlen (bytevector-length text-bv)))
  ;; forward jo rel32  : 0F 80 + 4 bytes (len 6, target offset 16 -> rel32 = 10)
  ;; forward jno rel32 : 0F 81 + 4 bytes (len 6, target offset 16 -> rel32 = 4)
  ;; backward jo rel8  : 70 F2 (len 2, disp8 = 0 - 14 = -14 = 0xF2 = 242)
  ;; backward jno rel8 : 71 F0 (len 2, disp8 = 0 - 16 = -16 = 0xF0 = 240)
  ;; ret               : C3 (len 1)
  ;; Total: 17 bytes
  (if (and (= tlen 17)
           (= (bytevector-u8-ref text-bv 0) 15)   ;; 0x0F
           (= (bytevector-u8-ref text-bv 1) 128)  ;; 0x80 (jo rel32)
           (= (bytevector-u8-ref text-bv 2) 10)   ;; rel32 = 10
           (= (bytevector-u8-ref text-bv 6) 15)   ;; 0x0F
           (= (bytevector-u8-ref text-bv 7) 129)  ;; 0x81 (jno rel32)
           (= (bytevector-u8-ref text-bv 8) 4)    ;; rel32 = 4
           (= (bytevector-u8-ref text-bv 12) 112) ;; 0x70 (jo rel8)
           (= (bytevector-u8-ref text-bv 13) 242) ;; 0xF2 (-14)
           (= (bytevector-u8-ref text-bv 14) 113) ;; 0x71 (jno rel8)
           (= (bytevector-u8-ref text-bv 15) 240) ;; 0xF0 (-16)
           (= (bytevector-u8-ref text-bv 16) 195));; 0xC3 (ret)
      (display "[PASS] Test 7: jo/jno short (70/71) and near (0F 80/81) encoding verified (#955)\n")
      (begin
        (display "[FAIL] Test 7: unexpected jo/jno encoding length/bytes: ")
        (display tlen)
        (newline)
        (exit 1))))


