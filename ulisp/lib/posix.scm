;;; =======================================================================
;;; ULisp Standard Library: 100% Pure Scheme Bare-Metal Linux Runtime
;;; Conforms to DSN-33 / Issue #516
;;; ZERO libc / ZERO external libraries / Direct Linux x86-64 Syscalls
;;; =======================================================================

(!disable-pass pass-synapse-inject-safepoints)

;;; -----------------------------------------------------------------------
;;; §6.14 / SRFI 170 Raw Linux System Calls (Multi-Architecture Abstracted)
;;; Conforms to Issue #690 / DSN-33 §2.2
;;; -----------------------------------------------------------------------

(cond-expand
  ((or aarch64 arm64)
   (define *sys-read* 63)
   (define *sys-write* 64)
   (define *sys-close* 57)
   (define *sys-exit* 93)
   (define *sys-openat* 56)
   (define *sys-faccessat* 48)
   (define *sys-unlinkat* 35)
   (define *sys-dup3* 24)
   (define *sys-mmap* 222)
   (define *sys-mremap* 216)
   (define *sys-munmap* 215)
   (define *sys-lseek* 62)
   (define *sys-clock-gettime* 113)
   (define *sys-at-fdcwd* -100))
  (else
   (define *sys-read* 0)
   (define *sys-write* 1)
   (define *sys-open* 2)
   (define *sys-close* 3)
   (define *sys-lseek* 8)
   (define *sys-access* 21)
   (define *sys-dup2* 33)
   (define *sys-exit* 60)
   (define *sys-unlink* 87)
   (define *sys-mmap* 9)
   (define *sys-munmap* 11)
   (define *sys-mremap* 25)
   (define *sys-clock-gettime* 228)
   (define *sys-openat* 257)
   (define *sys-at-fdcwd* -100)))

;; sys-exit: sys_exit(status)
(define (sys-exit code)
  (flush-output-port)
  (%raw-syscall (%to-raw *sys-exit*) (%to-raw code) 0 0 0 0 0))

(define (exit code)
  (sys-exit code))

(define (emergency-exit code)
  (sys-exit code))

;; sys-write: sys_write(fd, buf_ptr, count)
(define (sys-write fd buf-ptr count)
  (%to-fixnum (%raw-syscall (%to-raw *sys-write*) (%to-raw fd) buf-ptr (%to-raw count) 0 0 0)))

;; sys-read: sys_read(fd, buf_ptr, count)
(define (sys-read fd buf-ptr count)
  (%to-fixnum (%raw-syscall (%to-raw *sys-read*) (%to-raw fd) buf-ptr (%to-raw count) 0 0 0)))

;; sys-open: sys_open(path, flags, mode)
(cond-expand
  ((or aarch64 arm64)
   (define (sys-open path flags mode)
     (let ((path-ptr (if (string? path) (%ptr-untag path) path)))
       (%to-fixnum (%raw-syscall (%to-raw *sys-openat*) (%to-raw *sys-at-fdcwd*) path-ptr (%to-raw flags) (%to-raw mode) 0 0)))))
  (else
   (define (sys-open path flags mode)
     (let ((path-ptr (if (string? path) (%ptr-untag path) path)))
       (%to-fixnum (%raw-syscall (%to-raw *sys-open*) path-ptr (%to-raw flags) (%to-raw mode) 0 0 0))))))

;; sys-close: sys_close(fd)
(define (sys-close fd)
  (%to-fixnum (%raw-syscall (%to-raw *sys-close*) (%to-raw fd) 0 0 0 0 0)))

;; sys-dup2: sys_dup2(oldfd, newfd)
(cond-expand
  ((or aarch64 arm64)
   (define (sys-dup2 oldfd newfd)
     (%to-fixnum (%raw-syscall (%to-raw *sys-dup3*) (%to-raw oldfd) (%to-raw newfd) 0 0 0 0))))
  (else
   (define (sys-dup2 oldfd newfd)
     (%to-fixnum (%raw-syscall (%to-raw *sys-dup2*) (%to-raw oldfd) (%to-raw newfd) 0 0 0 0)))))

;; sys-access: sys_access(path, mode)
(cond-expand
  ((or aarch64 arm64)
   (define (sys-access path mode)
     (let ((path-ptr (if (string? path) (%ptr-untag path) path)))
       (%to-fixnum (%raw-syscall (%to-raw *sys-faccessat*) (%to-raw *sys-at-fdcwd*) path-ptr (%to-raw mode) 0 0 0)))))
  (else
   (define (sys-access path mode)
     (let ((path-ptr (if (string? path) (%ptr-untag path) path)))
       (%to-fixnum (%raw-syscall (%to-raw *sys-access*) path-ptr (%to-raw mode) 0 0 0 0))))))

;; sys-unlink: sys_unlink(path)
(cond-expand
  ((or aarch64 arm64)
   (define (sys-unlink path)
     (let ((path-ptr (if (string? path) (%ptr-untag path) path)))
       (%to-fixnum (%raw-syscall (%to-raw *sys-unlinkat*) (%to-raw *sys-at-fdcwd*) path-ptr 0 0 0 0)))))
  (else
   (define (sys-unlink path)
     (let ((path-ptr (if (string? path) (%ptr-untag path) path)))
       (%to-fixnum (%raw-syscall (%to-raw *sys-unlink*) path-ptr 0 0 0 0 0))))))

;; sys-chmod: sys_chmod(path, mode) (Issue #785)
(cond-expand
  ((or aarch64 arm64)
   (define (sys-chmod path mode)
     (let ((path-ptr (if (string? path) (%ptr-untag path) path)))
       (%to-fixnum (%raw-syscall (%to-raw 268) (%to-raw *sys-at-fdcwd*) path-ptr (%to-raw mode) 0 0 0)))))
  (else
   (define (sys-chmod path mode)
     (let ((path-ptr (if (string? path) (%ptr-untag path) path)))
       (%to-fixnum (%raw-syscall (%to-raw 90) path-ptr (%to-raw mode) 0 0 0 0))))))

;; sys-lseek: sys_lseek(fd, offset, whence) (Issue #784)
(define (sys-lseek fd offset whence)
  (%to-fixnum (%raw-syscall (%to-raw *sys-lseek*) (%to-raw fd) (%to-raw offset) (%to-raw whence) 0 0 0)))

;; R7RS §6.14 File management
(define (file-exists? filename)
  (= (sys-access filename 0) 0))

(define (delete-file filename)
  (let ((ret (sys-unlink filename)))
    (if (= ret 0)
        #t
        (error "delete-file: failed to delete file" filename))))

(define (sys-write-stderr str)
  (let ((len (string-length str)))
    (if (> len 0)
        (sys-write 2 (%ptr-untag str) len)
        0)))

;; sys-mmap: sys_mmap(addr, len, prot, flags, fd, offset)
;; PROT_READ|PROT_WRITE = 3, MAP_PRIVATE|MAP_ANONYMOUS = 34, fd = -1, offset = 0
(define (sys-mmap length)
  (%raw-syscall (%to-raw *sys-mmap*) 0 (%to-raw length) (%to-raw 3) (%to-raw 34) (%to-raw -1) 0))

;; sys-munmap: sys_munmap(addr, length)
(define (sys-munmap addr length)
  (%to-fixnum (%raw-syscall (%to-raw *sys-munmap*) (%to-raw addr) (%to-raw length) 0 0 0 0)))

;; sys-mremap: sys_mremap(old_address, old_size, new_size, flags)
;; MREMAP_MAYMOVE = 1
(define (sys-mremap old-addr old-size new-size flags)
  (%raw-syscall (%to-raw *sys-mremap*) old-addr (%to-raw old-size) (%to-raw new-size) (%to-raw flags) 0 0))

;; sys-clock-gettime-monotonic: sys_clock_gettime(CLOCK_MONOTONIC=1, &timespec)
;; Uses per-call 16-byte pair buffer and restores tagged 0s for thread & GC safety (Issue #728)
(define (sys-clock-gettime-monotonic)
  (let* ((cell (cons 0 0))
         (ptr (%ptr-untag cell))
         (ret (%to-fixnum (%raw-syscall (%to-raw *sys-clock-gettime*) (%to-raw 1) ptr 0 0 0 0))))
    (if (= ret 0)
        (let ((sec (%to-fixnum (%raw-load ptr 0)))
              (nsec (%to-fixnum (%raw-load ptr 8))))
          (%raw-store! ptr 0 0)
          (%raw-store! ptr 8 0)
          (cons sec nsec))
        (cons 0 0))))

;; sys-clock-gettime-realtime: sys_clock_gettime(CLOCK_REALTIME=0, &timespec)
(define (sys-clock-gettime-realtime)
  (let* ((cell (cons 0 0))
         (ptr (%ptr-untag cell))
         (ret (%to-fixnum (%raw-syscall (%to-raw *sys-clock-gettime*) 0 ptr 0 0 0 0))))
    (if (= ret 0)
        (let ((sec (%to-fixnum (%raw-load ptr 0)))
              (nsec (%to-fixnum (%raw-load ptr 8))))
          (%raw-store! ptr 0 0)
          (%raw-store! ptr 8 0)
          (cons sec nsec))
        (cons 0 0))))

;; R7RS §6.14 System interface: Time procedures
(define (current-second)
  (car (sys-clock-gettime-realtime)))

(define (jiffies-per-second)
  1000000)

(define (current-jiffy)
  (let* ((ts (sys-clock-gettime-monotonic))
         (sec (car ts))
         (nsec (cdr ts)))
    (+ (* sec 1000000) (quotient nsec 1000))))



;;; -----------------------------------------------------------------------
;;; §6.14 Pure Scheme Heap Management (Direct Kernel MMap)
;;; -----------------------------------------------------------------------

(define (ulisp-init-heap! size-bytes)
  (let ((heap-ptr (sys-mmap size-bytes)))
    (%set-heap-ptr! heap-ptr)
    heap-ptr))

;;; -----------------------------------------------------------------------
;;; §6.13 / §6.14 Zero-libc I/O Primitives
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
;;; §6.13.3 Pure Scheme Number Printer (Output Formatters)
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

(define (sys-argc)
  (let ((slot (%get-environ-ptr)))
    (if (= slot 0)
        0
        (%to-fixnum (%raw-load slot 8)))))

(define (sys-argv-ptr)
  (let ((slot (%get-environ-ptr)))
    (if (= slot 0)
        0
        (%raw-load slot 16))))

(define (%posix-cstr->string ptr)
  (let* ((len (%raw-c-strlen ptr))
         (s (make-string len)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (string-set! s i (integer->char (%raw-load-u8 ptr i)))
            (loop (+ i 1)))
          s))))

(define *command-line-override* (cons #f '()))
(define *script-file-override* (cons #f '()))

(define (%raw-command-line)
  (let ((argc (sys-argc))
        (argv-ptr (sys-argv-ptr)))
    (if (or (<= argc 0) (= argv-ptr 0))
        '("ulisp")
        (let loop ((i (- argc 1)) (acc '()))
          (if (< i 0)
              acc
              (let ((str-ptr (%raw-load argv-ptr (* i 8))))
                (if (= str-ptr 0)
                    (loop (- i 1) (cons "" acc))
                    (let ((s (%posix-cstr->string str-ptr)))
                      (loop (- i 1) (cons s acc))))))))))

;; §6.14 / SRFI 193 command-line parameter & procedure
(define command-line
  (case-lambda
    (()
     (let ((ov (car *command-line-override*)))
       (if ov ov (%raw-command-line))))
    ((new-cmd-line)
     (set-car! *command-line-override* new-cmd-line)
     new-cmd-line)))

;; SRFI 193 command-name, command-args, script-file, script-directory
(define (%posix-substring str start end)
  (let* ((len (- end start))
         (res (make-string len)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (string-set! res i (string-ref str (+ start i)))
            (loop (+ i 1)))
          res))))

(define (%srfi193-last-slash-index s)
  (let loop ((i (- (string-length s) 1)))
    (cond
      ((< i 0) -1)
      ((char=? (string-ref s i) #\/) i)
      (else (loop (- i 1))))))

(define (%srfi193-strip-scm-ext s)
  (let ((len (string-length s)))
    (if (and (> len 4)
             (char=? (string-ref s (- len 4)) #\.)
             (char=? (string-ref s (- len 3)) #\s)
             (char=? (string-ref s (- len 2)) #\c)
             (char=? (string-ref s (- len 1)) #\m))
        (%posix-substring s 0 (- len 4))
        s)))

(define (command-name)
  (let ((cmd (command-line)))
    (if (not (pair? cmd))
        #f
        (let ((arg0 (car cmd)))
          (if (or (not (string? arg0)) (= (string-length arg0) 0))
              #f
              (let* ((slash-idx (%srfi193-last-slash-index arg0))
                     (base (if (>= slash-idx 0)
                               (%posix-substring arg0 (+ slash-idx 1) (string-length arg0))
                               arg0)))
                (if (= (string-length base) 0)
                    #f
                    (%srfi193-strip-scm-ext base))))))))

(define (command-args)
  (let ((cmd (command-line)))
    (if (pair? cmd)
        (cdr cmd)
        '())))

(define script-file
  (case-lambda
    (() (car *script-file-override*))
    ((new-path)
     (set-car! *script-file-override* new-path)
     new-path)))

(define (script-directory)
  (let ((sf (script-file)))
    (if (not (string? sf))
        #f
        (let ((slash-idx (%srfi193-last-slash-index sf)))
          (if (>= slash-idx 0)
              (%posix-substring sf 0 (+ slash-idx 1))
              "./")))))

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
                                                           (integer->char (%raw-load-u8 entry-ptr (+ (+ klen 1) i))))
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
                                    (string-set! val j (integer->char (%raw-load-u8 entry-ptr (+ (+ eq-pos 1) j))))
                                    (copy-val (+ j 1)))))
                            (scan-loop (+ idx 1) (cons (cons key val) acc))))))))))))

;; Environment variable query fallback (Issue #621)
(define (sys-getenv name)
  (get-environment-variable name))

;; §6.14 System interface - features (R7RS-small, Issue #705, #706, #707, #708, #709, #710, #819, #820, #821)
(cond-expand
  ((or aarch64 arm64)
   (define (features)
     '(r7rs ulisp exact-closed ieee-float full-unicode little-endian aarch64 arm64 lp64 posix linux unix gnu-linux srfi-14 srfi-64 srfi-78 srfi-116 srfi-117 srfi-127 srfi-134 srfi-146 srfi-193 srfi-252)))
  (else
   (define (features)
     '(r7rs ulisp exact-closed ieee-float full-unicode little-endian x86-64 lp64 posix linux unix gnu-linux srfi-14 srfi-64 srfi-78 srfi-116 srfi-117 srfi-127 srfi-134 srfi-146 srfi-193 srfi-252))))


