;;; =======================================================================
;;; Unit Test Suite: ULisp Freestanding Raw Syscall Execution
;;; Conforms to DSN-33-07 / Issue #904
;;; Zero libc / Zero external runtime / Direct Linux x86-64 Syscalls
;;; =======================================================================

(include "lib/posix.scm")

;; 1. Direct sys-write to stdout
(sys-write-string "=== [TEST] Zero-libc Freestanding Raw Syscall Suite ===\n")

;; 2. Direct character and string formatting
(sys-write-string "[1/4] Testing character & fixnum output: ")
(sys-write-char #\O)
(sys-write-char #\K)
(sys-write-string " => ")
(sys-write-fixnum 2026)
(sys-newline)

;; 3. Dynamic Memory Allocation via sys-mmap and sys-munmap
(sys-write-string "[2/4] Testing sys-mmap (4096 bytes): ")
(let ((page-ptr (sys-mmap 4096)))
  (if (<= page-ptr 0)
      (begin
        (sys-write-string "FAIL (mmap returned error)\n")
        (sys-exit 1))
      (begin
        ;; Store and load a 64-bit value to verify memory access
        (%raw-store! page-ptr 0 (%to-raw 1337))
        (let ((val (%to-fixnum (%raw-load page-ptr 0))))
          (if (= val 1337)
              (begin
                (sys-write-string "PASS (stored and loaded: ")
                (sys-write-fixnum val)
                (sys-write-string ")\n"))
              (begin
                (sys-write-string "FAIL (value mismatch)\n")
                (sys-exit 2))))
        ;; Clean up with sys-munmap
        (let ((unmap-ret (sys-munmap page-ptr 4096)))
          (if (= unmap-ret 0)
              (sys-write-string "[3/4] Testing sys-munmap: PASS\n")
              (begin
                (sys-write-string "[3/4] Testing sys-munmap: FAIL\n")
                (sys-exit 3)))))))

;; 4. Clock gettime raw syscall
(sys-write-string "[4/4] Testing sys-clock-gettime-monotonic: ")
(let ((ts (sys-clock-gettime-monotonic)))
  (let ((sec (car ts))
        (nsec (cdr ts)))
    (if (and (>= sec 0) (>= nsec 0))
        (begin
          (sys-write-string "PASS (sec: ")
          (sys-write-fixnum sec)
          (sys-write-string ", nsec: ")
          (sys-write-fixnum nsec)
          (sys-write-string ")\n"))
        (begin
          (sys-write-string "FAIL (invalid timespec)\n")
          (sys-exit 4)))))

(sys-write-string "=== [SUCCESS] All Freestanding Syscalls Verified ===\n")
(sys-exit 0)
