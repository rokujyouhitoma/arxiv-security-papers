;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 144 (Direct ELF64 Static Binary Generator)
;;; Conforms to Issue #616 & Nanopass Architecture Quality Standard
;;; =======================================================================

(define *pass-tests-passed* 0)
(define *pass-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *pass-tests-passed* (+ *pass-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *pass-tests-failed* (+ *pass-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting Pass 144 (Direct ELF64 Generator) Unit Test Suite") (newline)
(display "=======================================================") (newline)

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

(display "=======================================================") (newline)
(display " Pass 144 Unit Tests: ")
(display *pass-tests-passed*)
(display " passed, ")
(display *pass-tests-failed*)
(display " failed.")
(newline)
(display "=======================================================") (newline)

(if (> *pass-tests-failed* 0)
    (error "Pass 144 unit test suite failed"))
