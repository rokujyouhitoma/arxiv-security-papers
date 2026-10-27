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

(define (emergency-exit code)
  (sys-exit code))

;; sys-write: sys_write(fd, buf_ptr, count) -> syscall 1
(define (sys-write fd buf-ptr count)
  (%to-fixnum (%raw-syscall (%to-raw 1) (%to-raw fd) buf-ptr (%to-raw count) 0 0 0)))

;; sys-read: sys_read(fd, buf_ptr, count) -> syscall 0
(define (sys-read fd buf-ptr count)
  (%to-fixnum (%raw-syscall (%to-raw 0) (%to-raw fd) buf-ptr (%to-raw count) 0 0 0)))

;; sys-open: sys_open(path, flags, mode) -> syscall 2
(define (sys-open path flags mode)
  (let ((path-ptr (if (string? path) (%ptr-untag path) path)))
    (%to-fixnum (%raw-syscall (%to-raw 2) path-ptr (%to-raw flags) (%to-raw mode) 0 0 0))))

;; sys-close: sys_close(fd) -> syscall 3
(define (sys-close fd)
  (%to-fixnum (%raw-syscall (%to-raw 3) (%to-raw fd) 0 0 0 0 0)))

;; sys-mmap: sys_mmap(addr, len, prot, flags, fd, offset) -> syscall 9
;; PROT_READ|PROT_WRITE = 3, MAP_PRIVATE|MAP_ANONYMOUS = 34, fd = -1, offset = 0
(define (sys-mmap length)
  (%raw-syscall (%to-raw 9) 0 (%to-raw length) (%to-raw 3) (%to-raw 34) (%to-raw -1) 0))

;; sys-mremap: sys_mremap(old_address, old_size, new_size, flags) -> syscall 25
;; MREMAP_MAYMOVE = 1
(define (sys-mremap old-addr old-size new-size flags)
  (%raw-syscall (%to-raw 25) old-addr (%to-raw old-size) (%to-raw new-size) (%to-raw flags) 0 0))

;; sys-clock-gettime-monotonic: sys_clock_gettime(CLOCK_MONOTONIC=1, &timespec) -> syscall 228
;; 16-byte raw buffer for timespec (tv_sec: 8 bytes, tv_nsec: 8 bytes)
(define *posix-timespec-cell* (cons 0 (cons 0 '())))

(define (sys-clock-gettime-monotonic)
  (let* ((ptr (%ptr-untag *posix-timespec-cell*))
         (ret (%to-fixnum (%raw-syscall (%to-raw 228) (%to-raw 1) ptr 0 0 0 0))))
    (if (= ret 0)
        (let ((sec (%to-fixnum (%raw-load ptr 0)))
              (nsec (%to-fixnum (%raw-load ptr 8))))
          (cons sec nsec))
        (cons 0 0))))



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

;;; -----------------------------------------------------------------------
;;; 5. Process Context & Environment Variables (R7RS §6.14)
;;; -----------------------------------------------------------------------

(define (command-line)
  '("ulisp"))

(define (sys-environ-ptr)
  (let ((slot (%get-environ-ptr)))
    (if (= slot 0)
        0
        (%raw-load slot 0))))

(define (%raw-c-strlen ptr)
  (let loop ((i 0))
    (if (= (%raw-load-u8 ptr i) 0)
        i
        (loop (+ i 1)))))

(define (get-environment-variable name)
  (if (not (string? name))
      #f
      (let ((envp (sys-environ-ptr)))
        (if (= envp 0)
            #f
            (let ((klen (string-length name)))
              (let scan-loop ((idx 0))
                (if (>= idx 65536)
                    #f
                    (let ((entry-ptr (%raw-load envp (* idx 8))))
                      (if (= entry-ptr 0)
                          #f
                          (let match-key ((k 0))
                            (if (< k klen)
                                (let ((b (%raw-load-u8 entry-ptr k))
                                      (expected (char->integer (string-ref name k))))
                                  (if (= b expected)
                                      (match-key (+ k 1))
                                      (scan-loop (+ idx 1))))
                                ;; All characters of name matched.
                                ;; Next character MUST be '=' (ASCII 61)
                                (if (= (%raw-load-u8 entry-ptr klen) 61)
                                    ;; Key matches! Extract value
                                    (let* ((total-len (%raw-c-strlen entry-ptr))
                                           (val-len (- total-len (+ klen 1)))
                                           (val (make-string val-len)))
                                      (let copy-val ((i 0))
                                        (if (< i val-len)
                                            (begin
                                              (string-set! val i
                                                           (integer->char (%raw-load-u8 entry-ptr (+ klen 1 i))))
                                              (copy-val (+ i 1)))
                                            val)))
                                    ;; Did not end with '=', e.g. "NAME_OTHER=val"
                                    (scan-loop (+ idx 1))))))))))))))

(define (%posix-reverse lst)
  (let loop ((rest lst) (res '()))
    (if (pair? rest)
        (loop (cdr rest) (cons (car rest) res))
        res)))

(define (get-environment-variables)
  (let ((envp (sys-environ-ptr)))
    (if (= envp 0)
        '()
        (let scan-loop ((idx 0) (acc '()))
          (if (>= idx 65536)
              (%posix-reverse acc)
              (let ((entry-ptr (%raw-load envp (* idx 8))))
                (if (= entry-ptr 0)
                    (%posix-reverse acc)
                    (let* ((total-len (%raw-c-strlen entry-ptr))
                           (eq-pos
                            (let find-eq ((i 0))
                              (cond
                                ((>= i total-len) #f)
                                ((= (%raw-load-u8 entry-ptr i) 61) i)
                                (else (find-eq (+ i 1)))))))
                      (if (not eq-pos)
                          (scan-loop (+ idx 1) acc)
                          (let* ((key (make-string eq-pos))
                                 (val-len (- total-len (+ eq-pos 1)))
                                 (val (make-string val-len)))
                            (let copy-key ((i 0))
                              (if (< i eq-pos)
                                  (begin
                                    (string-set! key i (integer->char (%raw-load-u8 entry-ptr i)))
                                    (copy-key (+ i 1)))))
                            (let copy-val ((j 0))
                              (if (< j val-len)
                                  (begin
                                    (string-set! val j (integer->char (%raw-load-u8 entry-ptr (+ eq-pos 1 j))))
                                    (copy-val (+ j 1)))))
                            (scan-loop (+ idx 1) (cons (cons key val) acc))))))))))))

;; Environment variable query fallback (Issue #621)
(define (sys-getenv name)
  (get-environment-variable name))

