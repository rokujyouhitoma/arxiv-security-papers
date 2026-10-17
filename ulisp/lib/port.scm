;;; =======================================================================
;;; ULisp Standard Library: port.scm
;;; R7RS String Ports and Port Management Procedures (R7RS Section 6.13)
;;; Conforms to DSN-33 Architecture Specification & Issue #534
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Standard Port Constants and Current Port Procedures
;;; -----------------------------------------------------------------------

(define *stdin-port* (list '%standard-input-port 0))
(define *stdout-port* (list '%standard-output-port 1))

(define (current-input-port) *stdin-port*)
(define (current-output-port) *stdout-port*)

;;; -----------------------------------------------------------------------
;;; 2. Port Predicates (R7RS Section 6.13.1)
;;; -----------------------------------------------------------------------

(define (string-input-port? p)
  (and (pair? p) (eq? (car p) '%string-input-port)))

(define (string-output-port? p)
  (and (pair? p) (eq? (car p) '%string-output-port)))

(define (standard-input-port? p)
  (and (pair? p) (eq? (car p) '%standard-input-port)))

(define (standard-output-port? p)
  (and (pair? p) (eq? (car p) '%standard-output-port)))

(define (port? p)
  (or (string-input-port? p)
      (or (string-output-port? p)
          (or (standard-input-port? p)
              (standard-output-port? p)))))

(define (input-port? p)
  (or (string-input-port? p)
      (standard-input-port? p)))

(define (output-port? p)
  (or (string-output-port? p)
      (standard-output-port? p)))

(define (textual-port? p)
  (port? p))

(define (binary-port? p)
  #f)

(define (port-open? p)
  (port? p))

(define (close-port p)
  #t)

(define (close-input-port p)
  #t)

(define (close-output-port p)
  #t)

;;; -----------------------------------------------------------------------
;;; 3. String Port Constructors and Extractors (R7RS Section 6.13.1)
;;; -----------------------------------------------------------------------

(define (open-input-string str)
  (list '%string-input-port str (cons 0 '()) (string-length str)))

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

;;; -----------------------------------------------------------------------
;;; 4. Port I/O Low-level Operations
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
    (else
     (%write-string str))))

;;; -----------------------------------------------------------------------
;;; 5. R7RS Polymorphic Macros for Standard Port Operations
;;; -----------------------------------------------------------------------

(define-syntax read-char
  (syntax-rules ()
    ((read-char) (%read-char))
    ((read-char p) (port-read-char p))))

(define-syntax peek-char
  (syntax-rules ()
    ((peek-char) (%peek-char))
    ((peek-char p) (port-peek-char p))))

(define-syntax write-char
  (syntax-rules ()
    ((write-char c) (%write-char c))
    ((write-char c p) (port-write-char c p))))

(define-syntax write-string
  (syntax-rules ()
    ((write-string s) (%write-string s))
    ((write-string s p) (port-write-string s p))))

