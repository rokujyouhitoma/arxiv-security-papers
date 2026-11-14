;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 144 (Direct ELF64 Static Binary Generator)
;;; Conforms to Issue #616 & Nanopass Architecture Quality Standard
;;; =======================================================================




(test-begin "Pass 144 (Direct ELF64 Generator)")

;; Helper to write bytevector to binary file
(define (test-write-bv-to-file path bv)
  (let ((p (open-binary-output-file path)))
    (let loop ((i 0) (len (bytevector-length bv)))
      (if (< i len)
          (begin
            (write-u8 (bytevector-u8-ref bv i) p)
            (loop (+ i 1) len))
          (close-output-port p)))))

;; 1. Direct Assembly to ELF via assemble-and-build-elf
(let* ((lines '("    .intel_syntax noprefix"
                "    .text"
                "    .globl _start"
                "_start:"
                "    mov eax, 60"
                "    mov edi, 42"
                "    syscall"))
       (elf (assemble-and-build-elf lines)))
  (assert-true "ELF bytevector generated" (bytevector? elf))
  (assert-equal "ELF magic 0" #x7f (bytevector-u8-ref elf 0))
  (assert-equal "ELF magic 1 'E'" 69 (bytevector-u8-ref elf 1))
  (assert-equal "ELF magic 2 'L'" 76 (bytevector-u8-ref elf 2))
  (assert-equal "ELF magic 3 'F'" 70 (bytevector-u8-ref elf 3))
  (assert-equal "ELF Class ELF64" 2 (bytevector-u8-ref elf 4))
  (test-write-bv-to-file "/tmp/test_pass144_exit42" elf))

;; 2. End-to-End LIR to ELF Generation via emit-x86-64-elf
(let* ((lir-prog '(%lir-program
                   (strings ())
                   (stackmaps ())
                   (%lir-functions)
                   (%lir-main
                     (frame-size 16)
                     (body
                       (%mov %rax 84)
                       (%return)))))
       ;; Mock stdout writing to /dev/null during unit test
       (elf-out (with-output-to-file "/dev/null"
                  (lambda ()
                    (emit-x86-64-elf lir-prog 'none)))))
  (assert-true "emit-x86-64-elf returned bytevector" (bytevector? elf-out))
  (assert-true "ELF size > 4096" (> (bytevector-length elf-out) 4096))
  (test-write-bv-to-file "/tmp/test_pass144_lir_bin" elf-out))

;; 3. Relocatable ELF64 Object Generation (ET_REL, Issue #783)
(let* ((lines '("    .intel_syntax noprefix"
                "    .text"
                "    .globl _start"
                "    .type _start, @function"
                "_start:"
                "    lea rdi, [rip + .L_msg]"
                "    call ext_helper"
                "    mov eax, 60"
                "    xor edi, edi"
                "    syscall"
                "    .section .rodata"
                ".L_msg:"
                "    .asciz \"hello\""
                "    .section .init_array, \"aw\""
                "    .quad _start"
                "    .section ulisp_globals_sec, \"a\""
                "    .quad my_gvar"
                "    .bss"
                "    .globl my_gvar"
                "    .weak my_gvar"
                "my_gvar:"
                "    .quad 0"))
       (obj-bv (assemble-and-build-elf-obj lines)))
  (assert-true "ET_REL bytevector generated" (bytevector? obj-bv))
  (assert-equal "ET_REL magic 0" #x7f (bytevector-u8-ref obj-bv 0))
  (assert-equal "ET_REL e_type == 1 (ET_REL)" 1 (bytevector-u8-ref obj-bv 16))
  (assert-equal "ET_REL e_machine == 62 (EM_X86_64)" 62 (bytevector-u8-ref obj-bv 18))
  (assert-equal "ET_REL e_phnum == 0" 0 (bytevector-u8-ref obj-bv 56))
  (assert-equal "ET_REL e_shnum == 16" 16 (bytevector-u8-ref obj-bv 60))
  (test-write-bv-to-file "/tmp/test_pass144_rel.o" obj-bv))


(test-end "Pass 144 (Direct ELF64 Generator)")
