;;; =======================================================================
;;; ULisp Standard Library: port.scm
;;; R7RS String Ports and Port Management Procedures (R7RS Section 6.13)
;;; Conforms to DSN-33 Architecture Specification & Issue #534
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; §6.13.1 Standard Port Constants and Current Port Procedures
;;; -----------------------------------------------------------------------

(define *stdin-port* (list '%standard-input-port 0))
(define *stdout-port* (list '%standard-output-port 1))
(define *stderr-port* (list '%standard-output-port 2))

(define *current-input-port-cell* (cons *stdin-port* '()))
(define *current-output-port-cell* (cons *stdout-port* '()))
(define *current-error-port-cell* (cons *stderr-port* '()))

(define (current-input-port arg)
  (if (= (%num-args) 0)
      (car *current-input-port-cell*)
      (begin
        (set-car! *current-input-port-cell* arg)
        arg)))

(define (current-output-port arg)
  (if (= (%num-args) 0)
      (car *current-output-port-cell*)
      (begin
        (set-car! *current-output-port-cell* arg)
        arg)))

(define (current-error-port arg)
  (if (= (%num-args) 0)
      (car *current-error-port-cell*)
      (begin
        (set-car! *current-error-port-cell* arg)
        arg)))

;;; -----------------------------------------------------------------------
;;; §6.13.1 Port Predicates
;;; -----------------------------------------------------------------------

(define (string-input-port? p)
  (and (pair? p) (eq? (car p) '%string-input-port)))

(define (string-output-port? p)
  (and (pair? p) (eq? (car p) '%string-output-port)))

(define (file-input-port? p)
  (and (pair? p) (eq? (car p) '%file-input-port)))

(define (file-output-port? p)
  (and (pair? p) (eq? (car p) '%file-output-port)))

(define (bytevector-input-port? p)
  (and (pair? p) (eq? (car p) '%bytevector-input-port)))

(define (bytevector-output-port? p)
  (and (pair? p) (eq? (car p) '%bytevector-output-port)))

(define (standard-input-port? p)
  (and (pair? p) (eq? (car p) '%standard-input-port)))

(define (standard-output-port? p)
  (and (pair? p) (eq? (car p) '%standard-output-port)))

(define (port? p)
  (or (string-input-port? p)
      (or (string-output-port? p)
          (or (bytevector-input-port? p)
              (or (bytevector-output-port? p)
                  (or (file-input-port? p)
                      (or (file-output-port? p)
                          (or (standard-input-port? p)
                              (standard-output-port? p)))))))))

(define (input-port? p)
  (or (string-input-port? p)
      (or (bytevector-input-port? p)
          (or (file-input-port? p)
              (standard-input-port? p)))))

(define (output-port? p)
  (or (string-output-port? p)
      (or (bytevector-output-port? p)
          (or (file-output-port? p)
              (standard-output-port? p)))))

(define (file-input-binary? p)
  (let ((tail (cddddr (cddddr p))))
    (if (pair? tail)
        (car tail)
        #f)))

(define (file-output-binary? p)
  (let ((tail (cdr (cddddr p))))
    (if (pair? tail)
        (car tail)
        #f)))

(define (binary-port? p)
  (cond
    ((bytevector-input-port? p) #t)
    ((bytevector-output-port? p) #t)
    ((file-input-port? p) (file-input-binary? p))
    ((file-output-port? p) (file-output-binary? p))
    (else #f)))

(define (textual-port? p)
  (and (port? p) (not (binary-port? p))))

(define (port-open? p)
  (cond
    ((string-input-port? p) (or (null? (cddddr p)) (car (cddddr p))))
    ((string-output-port? p) (or (null? (cddddr p)) (car (cddddr p))))
    ((bytevector-input-port? p) (>= (car (cadr p)) 0))
    ((bytevector-output-port? p) (>= (car (cadr p)) 0))
    ((file-input-port? p) (>= (cadr p) 0))
    ((file-output-port? p) (>= (cadr p) 0))
    (else (port? p))))

;; §6.13.1 Input and output port open predicates (R7RS-small)
(define (input-port-open? p)
  (if (input-port? p) (port-open? p) #f))

(define (output-port-open? p)
  (if (output-port? p) (port-open? p) #f))

(define (port-flush-output p)
  (cond
    ((file-output-port? p)
     (let* ((fd (cadr p))
            (buf-cell (caddr p))
            (len-cell (cadddr p))
            (buf (car buf-cell))
            (len (car len-cell)))
       (if (and (>= fd 0) (> len 0))
           (begin
             (sys-write fd (%ptr-untag buf) len)
             (set-car! len-cell 0)
             #t)
           #t)))
    (else
     (ulisp-flush))))

(define (close-port p)
  (cond
    ((string-input-port? p)
     (set-cdr! (cdddr p) (cons #f '()))
     #t)
    ((string-output-port? p)
     (set-cdr! (cdddr p) (cons #f '()))
     #t)
    ((bytevector-input-port? p)
     (set-car! (cadr p) -1)
     #t)
    ((bytevector-output-port? p)
     (set-car! (cadr p) -1)
     #t)
    ((file-input-port? p)
     (let ((fd (cadr p)))
       (if (>= fd 0)
           (begin
             (sys-close fd)
             (set-car! (cdr p) -1)
             #t)
           #t)))
    ((file-output-port? p)
     (let ((fd (cadr p)))
       (if (>= fd 0)
           (begin
             (port-flush-output p)
             (sys-close fd)
             (set-car! (cdr p) -1)
             #t)
           #t)))
    (else #t)))

(define (close-input-port p)
  (close-port p))

(define (close-output-port p)
  (close-port p))

;;; -----------------------------------------------------------------------
;;; §6.13.1 String and Bytevector Port Constructors and Extractors
;;; -----------------------------------------------------------------------

(define (open-input-string str)
  (list '%string-input-port str (cons 0 '()) (string-length str)))

(define (open-input-bytevector bv)
  (list '%bytevector-input-port (cons 1 '()) bv (cons 0 '()) (bytevector-length bv)))

(define (open-input-file filename)
  (let ((fd (sys-open filename 0 0)))
    (if (< fd 0)
        #f
        (let ((buf (make-string 4096)))
          (list '%file-input-port
                fd
                (cons buf '())
                (cons 0 '())        ; read pos
                (cons 0 '())        ; buffer len
                (cons 1 '())        ; line (1-indexed)
                (cons 1 '())        ; col (1-indexed)
                filename
                #f)))))             ; binary? #f

(define (open-binary-input-file filename)
  (let ((fd (sys-open filename 0 0)))
    (if (< fd 0)
        #f
        (let ((buf (make-string 4096)))
          (list '%file-input-port
                fd
                (cons buf '())
                (cons 0 '())        ; read pos
                (cons 0 '())        ; buffer len
                (cons 1 '())        ; line (1-indexed)
                (cons 1 '())        ; col (1-indexed)
                filename
                #t)))))             ; binary? #t

;; O_WRONLY(1) | O_CREAT(64) | O_TRUNC(512) = 577, mode = 0666 (438)
(define (open-output-file filename)
  (let ((fd (sys-open filename 577 438)))
    (if (< fd 0)
        (error "open-output-file: failed to open file" filename)
        (let ((buf (make-string 4096)))
          (list '%file-output-port
                fd
                (cons buf '())
                (cons 0 '())        ; write len
                filename
                #f)))))             ; binary? #f

(define (open-binary-output-file filename)
  (let ((fd (sys-open filename 577 438)))
    (if (< fd 0)
        (error "open-binary-output-file: failed to open file" filename)
        (let ((buf (make-string 4096)))
          (list '%file-output-port
                fd
                (cons buf '())
                (cons 0 '())        ; write len
                filename
                #t)))))             ; binary? #t

(define (port-line p)
  (cond
    ((file-input-port? p) (car (cadr (cddddr p))))
    (else 1)))

(define (port-col p)
  (cond
    ((file-input-port? p) (car (caddr (cddddr p))))
    (else 1)))

(define (port-filename p)
  (cond
    ((file-input-port? p) (car (cdddr (cddddr p))))
    ((file-output-port? p) (car (cddddr p)))
    (else "")))

(define (open-output-string)
  (let ((init-cap 64))
    (list '%string-output-port
          (cons (make-string init-cap) '())
          (cons 0 '())
          (cons init-cap '()))))

(define (get-output-string p)
  (if (string-output-port? p)
      (let* ((buf-cell (cadr p))
             (len-cell (caddr p))
             (buf (car buf-cell))
             (len (car len-cell)))
        (substring buf 0 len))
      ""))

(define (%port-bytevector-copy! dest dest-start src src-start count)
  (let loop ((i 0))
    (if (< i count)
        (begin
          (bytevector-u8-set! dest (+ dest-start i) (bytevector-u8-ref src (+ src-start i)))
          (loop (+ i 1)))
        63)))

(define (open-output-bytevector)
  (let ((init-cap 64))
    (list '%bytevector-output-port
          (cons 1 '())
          (cons (%make-bytevector init-cap) '())
          (cons 0 '())
          (cons init-cap '()))))

(define (get-output-bytevector p)
  (if (bytevector-output-port? p)
      (let* ((buf-cell (caddr p))
             (len-cell (cadddr p))
             (buf (car buf-cell))
             (len (car len-cell))
             (res (%make-bytevector len)))
        (%port-bytevector-copy! res 0 buf 0 len)
        res)
      (%make-bytevector 0)))

;;; -----------------------------------------------------------------------
;;; §6.13.2 Port Input/Output Procedures
;;; -----------------------------------------------------------------------

(define (port-read-char p)
  (cond
    ((string-input-port? p)
     (let* ((str (cadr p))
            (pos-cell (caddr p))
            (len (cadddr p))
            (pos (car pos-cell)))
       (if (>= pos len)
           (eof-object)
           (let ((ch (string-ref str pos)))
             (set-car! pos-cell (+ pos 1))
             ch))))
    ((file-input-port? p)
     (let* ((fd (cadr p))
            (buf-cell (caddr p))
            (pos-cell (cadddr p))
            (len-cell (car (cddddr p)))
            (line-cell (cadr (cddddr p)))
            (col-cell (caddr (cddddr p)))
            (buf (car buf-cell))
            (pos (car pos-cell))
            (len (car len-cell)))
       (if (>= pos len)
           (let ((ret (sys-read fd (%ptr-untag buf) 4096)))
             (if (<= ret 0)
                 (eof-object)
                 (begin
                   (set-car! pos-cell 1)
                   (set-car! len-cell ret)
                   (let ((ch (string-ref buf 0)))
                     (if (char=? ch #\newline)
                         (begin
                           (set-car! line-cell (+ (car line-cell) 1))
                           (set-car! col-cell 1))
                         (set-car! col-cell (+ (car col-cell) 1)))
                     ch))))
           (let ((ch (string-ref buf pos)))
             (set-car! pos-cell (+ pos 1))
             (if (char=? ch #\newline)
                 (begin
                   (set-car! line-cell (+ (car line-cell) 1))
                   (set-car! col-cell 1))
                 (set-car! col-cell (+ (car col-cell) 1)))
             ch))))
    ((bytevector-input-port? p)
     (let* ((bv (caddr p))
            (pos-cell (cadddr p))
            (len (car (cddddr p)))
            (pos (car pos-cell)))
       (if (>= pos len)
           (eof-object)
           (let ((b (bytevector-u8-ref bv pos)))
             (set-car! pos-cell (+ pos 1))
             (integer->char b)))))
    (else
     (%read-char))))

(define (port-peek-char p)
  (cond
    ((string-input-port? p)
     (let* ((str (cadr p))
            (pos-cell (caddr p))
            (len (cadddr p))
            (pos (car pos-cell)))
       (if (>= pos len)
           (eof-object)
           (string-ref str pos))))
    ((file-input-port? p)
     (let* ((fd (cadr p))
            (buf-cell (caddr p))
            (pos-cell (cadddr p))
            (len-cell (car (cddddr p)))
            (buf (car buf-cell))
            (pos (car pos-cell))
            (len (car len-cell)))
       (if (>= pos len)
           (let ((ret (sys-read fd (%ptr-untag buf) 4096)))
             (if (<= ret 0)
                 (eof-object)
                 (begin
                   (set-car! pos-cell 0)
                   (set-car! len-cell ret)
                   (string-ref buf 0))))
           (string-ref buf pos))))
    ((bytevector-input-port? p)
     (let* ((bv (caddr p))
            (pos-cell (cadddr p))
            (len (car (cddddr p)))
            (pos (car pos-cell)))
       (if (>= pos len)
           (eof-object)
           (integer->char (bytevector-u8-ref bv pos)))))
    (else
     (%peek-char))))

(define (port-write-char ch p)
  (cond
    ((string-output-port? p)
     (let* ((buf-cell (cadr p))
            (len-cell (caddr p))
            (cap-cell (cadddr p))
            (len (car len-cell))
            (cap (car cap-cell)))
       (if (>= len cap)
           (let* ((new-cap (* cap 2))
                  (new-buf (make-string new-cap))
                  (old-buf (car buf-cell)))
             (let copy-loop ((i 0))
               (if (< i len)
                   (begin
                     (string-set! new-buf i (string-ref old-buf i))
                     (copy-loop (+ i 1)))
                   #t))
             (set-car! buf-cell new-buf)
             (set-car! cap-cell new-cap)))
       (let ((buf (car buf-cell)))
         (string-set! buf len ch)
         (set-car! len-cell (+ len 1))
         #t)))
    ((bytevector-output-port? p)
     (port-write-u8 (char->integer ch) p))
    ((file-output-port? p)
     (let* ((fd (cadr p))
            (buf-cell (caddr p))
            (len-cell (cadddr p))
            (buf (car buf-cell))
            (len (car len-cell)))
       (if (>= len 4096)
           (begin
             (sys-write fd (%ptr-untag buf) len)
             (string-set! buf 0 ch)
             (set-car! len-cell 1)
             #t)
           (begin
             (string-set! buf len ch)
             (set-car! len-cell (+ len 1))
             #t))))
    ((and (pair? p) (eq? (car p) '%standard-output-port) (= (cadr p) 2))
     (let ((buf (cons 0 (cons 0 '()))))
       (%raw-store! (%ptr-untag buf) 0 (%to-raw (char->integer ch)))
       (sys-write 2 (%ptr-untag buf) 1)))
    (else
     (%write-char ch))))

(define (port-write-string str p)
  (cond
    ((string-output-port? p)
     (let ((slen (string-length str)))
       (let loop ((i 0))
         (if (< i slen)
             (begin
               (port-write-char (string-ref str i) p)
               (loop (+ i 1)))
             #t))))
    ((file-output-port? p)
     (let* ((fd (cadr p))
            (slen (string-length str)))
       (if (>= slen 4096)
           (begin
             (port-flush-output p)
             (sys-write fd (%ptr-untag str) slen)
             #t)
           (let loop ((i 0))
             (if (< i slen)
                 (begin
                   (port-write-char (string-ref str i) p)
                   (loop (+ i 1)))
                 #t)))))
    ((and (pair? p) (eq? (car p) '%standard-output-port) (= (cadr p) 2))
     (let ((slen (string-length str)))
       (if (> slen 0)
           (sys-write 2 (%ptr-untag str) slen)
           0)))
    (else
     (%write-string str))))

;;; -----------------------------------------------------------------------
;;; §6.13.1 High-Level Port Control & File Port Procedures
;;; -----------------------------------------------------------------------

(define (call-with-port port proc)
  (guard (exc (else (close-port port) (raise exc)))
    (let ((ans (proc port)))
      (close-port port)
      ans)))

(define (call-with-input-file filename proc)
  (let ((p (open-input-file filename)))
    (if (not p)
        (error "call-with-input-file: failed to open file" filename)
        (call-with-port p proc))))

(define (call-with-output-file filename proc)
  (call-with-port (open-output-file filename) proc))

(define (with-input-from-file filename thunk)
  (let ((p (open-input-file filename)))
    (if (not p)
        (error "with-input-from-file: failed to open file" filename)
        (let ((old-p (current-input-port)))
          (current-input-port p)
          (guard (exc (else
                       (current-input-port old-p)
                       (close-port p)
                       (raise exc)))
            (let ((ans (thunk)))
              (current-input-port old-p)
              (close-port p)
              ans))))))

(define (with-output-to-file filename thunk)
  (let ((p (open-output-file filename)))
    (let ((old-p (current-output-port)))
      (current-output-port p)
      (guard (exc (else
                   (current-output-port old-p)
                   (close-port p)
                   (raise exc)))
        (let ((ans (thunk)))
          (current-output-port old-p)
          (close-port p)
          ans)))))

(define (port-read-u8 p)
  (cond
    ((bytevector-input-port? p)
     (let* ((bv (caddr p))
            (pos-cell (cadddr p))
            (len (car (cddddr p)))
            (pos (car pos-cell)))
       (if (>= pos len)
           (eof-object)
           (let ((b (bytevector-u8-ref bv pos)))
             (set-car! pos-cell (+ pos 1))
             b))))
    (else
     (let ((ch (port-read-char p)))
       (if (eof-object? ch)
           ch
           (char->integer ch))))))

(define (port-peek-u8 p)
  (cond
    ((bytevector-input-port? p)
     (let* ((bv (caddr p))
            (pos-cell (cadddr p))
            (len (car (cddddr p)))
            (pos (car pos-cell)))
       (if (>= pos len)
           (eof-object)
           (bytevector-u8-ref bv pos))))
    (else
     (let ((ch (port-peek-char p)))
       (if (eof-object? ch)
           ch
           (char->integer ch))))))

(define (port-write-u8 b p)
  (cond
    ((bytevector-output-port? p)
     (let* ((buf-cell (caddr p))
            (len-cell (cadddr p))
            (cap-cell (car (cddddr p)))
            (buf (car buf-cell))
            (len (car len-cell))
            (cap (car cap-cell)))
       (if (>= len cap)
           (let* ((new-cap (* cap 2))
                  (new-buf (%make-bytevector new-cap)))
             (%port-bytevector-copy! new-buf 0 buf 0 len)
             (bytevector-u8-set! new-buf len b)
             (set-car! buf-cell new-buf)
             (set-car! cap-cell new-cap)
             (set-car! len-cell (+ len 1))
             #t)
           (begin
             (bytevector-u8-set! buf len b)
             (set-car! len-cell (+ len 1))
             #t))))
    (else
     (port-write-char (integer->char b) p))))

(define (port-read-line p)
  (let ((ch (port-read-char p)))
    (if (eof-object? ch)
        ch
        (let loop ((acc (list ch)))
          (let ((next (port-peek-char p)))
            (cond
              ((eof-object? next)
               (list->string (reverse acc)))
              ((char=? next #\newline)
               (port-read-char p)
               (list->string (reverse acc)))
              ((char=? next (integer->char 13))
               (port-read-char p)
               (let ((after-cr (port-peek-char p)))
                 (if (and (not (eof-object? after-cr)) (char=? after-cr #\newline))
                     (port-read-char p)
                     #t))
               (list->string (reverse acc)))
              (else
               (port-read-char p)
               (loop (cons next acc)))))))))

;;; -----------------------------------------------------------------------
;;; §6.13 R7RS Polymorphic Macros for Standard Port Operations
;;; -----------------------------------------------------------------------

(define-syntax flush-output-port
  (syntax-rules ()
    ((flush-output-port) (port-flush-output (current-output-port)))
    ((flush-output-port p) (port-flush-output p))))

(define-syntax read-char
  (syntax-rules ()
    ((read-char) (port-read-char (current-input-port)))
    ((read-char p) (port-read-char p))))

(define-syntax peek-char
  (syntax-rules ()
    ((peek-char) (port-peek-char (current-input-port)))
    ((peek-char p) (port-peek-char p))))

(define-syntax read-line
  (syntax-rules ()
    ((read-line) (port-read-line (current-input-port)))
    ((read-line p) (port-read-line p))))

(define-syntax read-u8
  (syntax-rules ()
    ((read-u8) (port-read-u8 (current-input-port)))
    ((read-u8 p) (port-read-u8 p))))

(define-syntax peek-u8
  (syntax-rules ()
    ((peek-u8) (port-peek-u8 (current-input-port)))
    ((peek-u8 p) (port-peek-u8 p))))

(define-syntax write-char
  (syntax-rules ()
    ((write-char c) (port-write-char c (current-output-port)))
    ((write-char c p) (port-write-char c p))))

(define-syntax write-u8
  (syntax-rules ()
    ((write-u8 b) (port-write-u8 b (current-output-port)))
    ((write-u8 b p) (port-write-u8 b p))))

(define-syntax write-string
  (syntax-rules ()
    ((write-string s) (port-write-string s (current-output-port)))
    ((write-string s p) (port-write-string s p))))

(define (port-char-ready? p)
  (cond
    ((string-input-port? p) #t)
    ((bytevector-input-port? p) #t)
    ((file-input-port? p) #t)
    ((standard-input-port? p) #t)
    (else #t)))

(define (port-u8-ready? p)
  (port-char-ready? p))

(define-syntax char-ready?
  (syntax-rules ()
    ((char-ready?) (port-char-ready? (current-input-port)))
    ((char-ready? p) (port-char-ready? p))))

(define-syntax u8-ready?
  (syntax-rules ()
    ((u8-ready?) (port-u8-ready? (current-input-port)))
    ((u8-ready? p) (port-u8-ready? p))))

