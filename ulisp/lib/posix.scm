;;; =======================================================================
;;; ULisp Standard Library: 100% Pure Scheme Bare-Metal Linux Runtime
;;; Conforms to DSN-33 / Issue #516
;;; ZERO libc / ZERO external libraries / Direct Linux x86-64 Syscalls
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Raw Linux x86-64 System Calls
;;; -----------------------------------------------------------------------

;; sys-exit: sys_exit(status) -> syscall 60
(define (sys-exit code)
  (flush-output-port)
  (%raw-syscall (%to-raw 60) (%to-raw code) 0 0 0 0 0))

(define (exit code)
  (sys-exit code))

;; sys-write: sys_write(fd, buf_ptr, count) -> syscall 1
(define (sys-write fd buf-ptr count)
  (%to-fixnum (%raw-syscall (%to-raw 1) (%to-raw fd) buf-ptr (%to-raw count) 0 0 0)))

;; sys-read: sys_read(fd, buf_ptr, count) -> syscall 0
(define (sys-read fd buf-ptr count)
  (%to-fixnum (%raw-syscall (%to-raw 0) (%to-raw fd) buf-ptr (%to-raw count) 0 0 0)))

;; sys-mmap: sys_mmap(addr, len, prot, flags, fd, offset) -> syscall 9
;; PROT_READ|PROT_WRITE = 3, MAP_PRIVATE|MAP_ANONYMOUS = 34, fd = -1, offset = 0
(define (sys-mmap length)
  (%raw-syscall (%to-raw 9) 0 (%to-raw length) (%to-raw 3) (%to-raw 34) (%to-raw -1) 0))

;; sys-mremap: sys_mremap(old_address, old_size, new_size, flags) -> syscall 25
;; MREMAP_MAYMOVE = 1
(define (sys-mremap old-addr old-size new-size flags)
  (%raw-syscall (%to-raw 25) old-addr (%to-raw old-size) (%to-raw new-size) (%to-raw flags) 0 0))


;;; -----------------------------------------------------------------------
;;; 2. Pure Scheme Heap Management (Direct Kernel MMap)
;;; -----------------------------------------------------------------------

(define (ulisp-init-heap! size-bytes)
  (let ((heap-ptr (sys-mmap size-bytes)))
    (%set-heap-ptr! heap-ptr)
    heap-ptr))

;;; -----------------------------------------------------------------------
;;; 3. Zero-libc I/O Primitives
;;; -----------------------------------------------------------------------

;; 16-byte raw buffer for single character I/O and integer formatting
(define *io-buf-cell* (cons 0 (cons 0 '())))

(define (raw-buf-ptr)
  (%ptr-untag *io-buf-cell*))

;; Flush any pending output in 4KB buffer
(define (sys-flush)
  (flush-output-port))

;; Write a single character directly to stdout (buffered)
(define (sys-write-char ch)
  (write-char ch))

;; Write an entire Scheme string to stdout (buffered)
(define (sys-write-string str)
  (write-string str))

;; Read a single character directly from stdin without libc
(define (sys-read-char)
  (let ((ret (sys-read 0 (raw-buf-ptr) 1)))
    (if (<= ret 0)
        (eof-object)
        (let ((raw-val (%to-fixnum (%raw-load (raw-buf-ptr) 0))))
          (integer->char (bitwise-and raw-val 255))))))

;; Write a newline to stdout
(define (sys-newline)
  (sys-write-char #\newline))

;;; -----------------------------------------------------------------------
;;; 4. Pure Scheme Number Printer (Output Formatters)
;;; -----------------------------------------------------------------------

(define (sys-write-fixnum n)
  (cond
    ((= n 0)
     (sys-write-char #\0))
    ((< n 0)
     (sys-write-char #\-)
     (sys-write-fixnum-positive (- 0 n)))
    (else
     (sys-write-fixnum-positive n))))

(define (sys-write-fixnum-positive n)
  (if (> n 0)
      (begin
        (sys-write-fixnum-positive (quotient n 10))
        (let* ((digit (modulo n 10))
               (ch (integer->char (+ digit 48))))
          (sys-write-char ch)))))
