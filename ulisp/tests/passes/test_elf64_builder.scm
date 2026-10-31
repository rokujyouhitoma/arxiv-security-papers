;;; =======================================================================
;;; Unit Test for ELF64 Executable Builder (elf64_builder.scm)
;;; =======================================================================

(include "lib/bytevector.scm")
(include "backend/elf64_builder.scm")

;; Helper to write bytevector to binary file
(define (write-bytevector-to-file path bv)
  (let ((p (open-binary-output-file path)))
    (let loop ((i 0) (len (bytevector-length bv)))
      (if (< i len)
          (begin
            (write-u8 (bytevector-u8-ref bv i) p)
            (loop (+ i 1) len))
          (close-output-port p)))))

;; Test 1: Exit(42) Minimal Executable
;; Machine code for:
;;   mov eax, 60 (0xb8, 0x3c, 0x00, 0x00, 0x00)
;;   mov edi, 42 (0xbf, 0x2a, 0x00, 0x00, 0x00)
;;   syscall     (0x0f, 0x05)
(let* ((code (elf64-list->bytevector '(#xb8 #x3c #x00 #x00 #x00
                                       #xbf #x2a #x00 #x00 #x00
                                       #x0f #x05)))
       (empty-bv (make-bytevector 0 0))
       (elf (build-elf64-executable code empty-bv empty-bv 0 0)))
  (write-bytevector-to-file "/tmp/test_scheme_elf_builder_42" elf)
  (display "ELF64 binary successfully generated, size: ")
  (display (bytevector-length elf))
  (newline))
