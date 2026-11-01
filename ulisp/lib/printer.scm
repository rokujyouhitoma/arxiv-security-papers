;;; =======================================================================
;;; ULisp Standard Library: printer.scm
;;; Formatted Scheme output procedures implemented purely in Scheme
;;; Extended with R7RS Port Specification & Issue #534 / Issue #656
;;; Implements write-simple, write-shared, write, display, newline
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Primitive Helpers
;;; -----------------------------------------------------------------------

(define (%printer-assq item ls)
  (let loop ((curr ls))
    (cond
      ((null? curr) #f)
      ((not (pair? curr)) #f)
      ((and (pair? (car curr)) (eq? item (caar curr))) (car curr))
      (else (loop (cdr curr))))))

(define (%printer-memq item ls)
  (let loop ((curr ls))
    (cond
      ((null? curr) #f)
      ((not (pair? curr)) #f)
      ((eq? item (car curr)) #t)
      (else (loop (cdr curr))))))

(define (port-newline p)
  (port-write-char #\newline p))

(define (port-display-string s p)
  (port-write-string s p))

(define (port-write-char-literal c p)
  (port-display-string "#\\" p)
  (cond
    ((char=? c #\newline) (port-display-string "newline" p))
    ((char=? c #\space)   (port-display-string "space" p))
    ((char=? c #\tab)     (port-display-string "tab" p))
    (else                 (port-write-char c p))))

(define (port-write-escaped-string val p)
  (port-write-char #\" p)
  (let ((len (string-length val)))
    (let loop ((i 0))
      (if (< i len)
          (let ((c (string-ref val i)))
            (cond
              ((char=? c #\newline)          (port-display-string "\\n" p))
              ((char=? c #\tab)              (port-display-string "\\t" p))
              ((char=? c (integer->char 13)) (port-display-string "\\r" p))
              ((char=? c #\\)                (port-display-string "\\\\" p))
              ((char=? c #\")                (port-display-string "\\\"" p))
              (else                          (port-write-char c p)))
            (loop (+ i 1)))
          #t)))
  (port-write-char #\" p))

;;; -----------------------------------------------------------------------
;;; port-display: Human-readable output (no quotes on strings/chars)
;;; -----------------------------------------------------------------------

(define (port-display val p)
  (cond
    ((string? val)
     (port-display-string val p))
    ((char? val)
     (port-write-char val p))
    ((boolean? val)
     (if val (port-display-string "#t" p) (port-display-string "#f" p)))
    ((null? val)
     (port-display-string "()" p))
    ((number? val)
     (port-display-string (number->string val) p))
    ((symbol? val)
     (port-display-string (symbol->string val) p))
    ((pair? val)
     (port-write-char #\( p)
     (let loop ((curr val) (first? #t))
       (cond
         ((null? curr)
          (port-write-char #\) p))
         ((pair? curr)
          (if (not first?) (port-write-char #\space p))
          (port-display (car curr) p)
          (loop (cdr curr) #f))
         (else
          (port-write-char #\space p)
          (port-write-char #\. p)
          (port-write-char #\space p)
          (port-display curr p)
          (port-write-char #\) p)))))
    ((eof-object? val)
     (port-display-string "#<eof>" p))
    ((bytevector? val)
     (port-display-string "#u8(" p)
     (let ((len (bytevector-length val)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (if (> i 0) (port-write-char #\space p))
               (port-display-string (number->string (bytevector-u8-ref val i)) p)
               (loop (+ i 1)))
             #t)))
     (port-write-char #\) p))
    ((vector? val)
     (port-display-string "#(" p)
     (let ((len (vector-length val)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (if (> i 0) (port-write-char #\space p))
               (port-display (vector-ref val i) p)
               (loop (+ i 1)))
             #t)))
     (port-write-char #\) p))
    (else
     (port-display-string "#<unknown>" p))))

;;; -----------------------------------------------------------------------
;;; port-write-simple: Fast direct tree-recursive serialization (R7RS §6.13.3)
;;; -----------------------------------------------------------------------

(define (port-write-simple val p)
  (cond
    ((string? val)
     (port-write-escaped-string val p))
    ((char? val)
     (port-write-char-literal val p))
    ((boolean? val)
     (if val (port-display-string "#t" p) (port-display-string "#f" p)))
    ((null? val)
     (port-display-string "()" p))
    ((number? val)
     (port-display-string (number->string val) p))
    ((symbol? val)
     (port-display-string (symbol->string val) p))
    ((eof-object? val)
     (port-display-string "#<eof>" p))
    ((bytevector? val)
     (port-display-string "#u8(" p)
     (let ((len (bytevector-length val)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (if (> i 0) (port-write-char #\space p))
               (port-display-string (number->string (bytevector-u8-ref val i)) p)
               (loop (+ i 1)))
             #t)))
     (port-write-char #\) p))
    ((vector? val)
     (port-display-string "#(" p)
     (let ((len (vector-length val)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (if (> i 0) (port-write-char #\space p))
               (port-write-simple (vector-ref val i) p)
               (loop (+ i 1)))
             #t)))
     (port-write-char #\) p))
    ((pair? val)
     (port-write-char #\( p)
     (let loop ((curr val) (first? #t))
       (cond
         ((null? curr)
          (port-write-char #\) p))
         ((pair? curr)
          (if (not first?) (port-write-char #\space p))
          (port-write-simple (car curr) p)
          (loop (cdr curr) #f))
         (else
          (port-write-char #\space p)
          (port-write-char #\. p)
          (port-write-char #\space p)
          (port-write-simple curr p)
          (port-write-char #\) p)))))
    (else
     (port-display-string "#<unknown>" p))))

;;; -----------------------------------------------------------------------
;;; port-write-shared: Two-pass datum label serialization (SRFI 38 / R7RS §6.13.3)
;;; -----------------------------------------------------------------------

;; Pass 1: Collect shared nodes and record pre-order appearance
(define (%printer-scan-node val state)
  (let ((table (car state))
        (order (cdr state)))
    (cond
      ((or (pair? val) (vector? val))
       (let ((entry (%printer-assq val table)))
         (if entry
             (begin
               (set-cdr! entry (+ (cdr entry) 1))
               state)
             (let ((new-table (cons (cons val 1) table))
                   (new-order (cons val order)))
               (let ((st1 (cons new-table new-order)))
                 (if (pair? val)
                     (let ((st2 (%printer-scan-node (car val) st1)))
                       (%printer-scan-node (cdr val) st2))
                     (let ((len (vector-length val)))
                       (let loop ((i 0) (cur-st st1))
                         (if (< i len)
                             (loop (+ i 1) (%printer-scan-node (vector-ref val i) cur-st))
                             cur-st)))))))))
      (else state))))

;; Build label map ((node . id) ...) for nodes with count >= 2 in order of appearance
(define (%printer-build-label-map state)
  (let ((table (car state))
        (order (reverse (cdr state))))
    (let loop ((nodes order) (next-id 1) (label-map '()))
      (if (null? nodes)
          label-map
          (let* ((node (car nodes))
                 (entry (%printer-assq node table)))
            (if (and entry (> (cdr entry) 1))
                (loop (cdr nodes) (+ next-id 1) (cons (cons node next-id) label-map))
                (loop (cdr nodes) next-id label-map)))))))

;; Pass 2: Print node with datum label resolution
(define (%port-write-shared-node val p label-map defined-box)
  (let ((label-entry (%printer-assq val label-map)))
    (if label-entry
        (let ((id (cdr label-entry)))
          (if (%printer-memq val (car defined-box))
              ;; Already defined: emit reference #<id>#
              (begin
                (port-write-char #\# p)
                (port-display-string (number->string id) p)
                (port-write-char #\# p))
              ;; Not defined yet: emit definition #<id>= and print body
              (begin
                (set-car! defined-box (cons val (car defined-box)))
                (port-write-char #\# p)
                (port-display-string (number->string id) p)
                (port-write-char #\= p)
                (%port-write-shared-val val p label-map defined-box))))
        ;; Not a shared node: print directly
        (%port-write-shared-val val p label-map defined-box))))

(define (%port-write-shared-val val p label-map defined-box)
  (cond
    ((string? val)
     (port-write-escaped-string val p))
    ((char? val)
     (port-write-char-literal val p))
    ((boolean? val)
     (if val (port-display-string "#t" p) (port-display-string "#f" p)))
    ((null? val)
     (port-display-string "()" p))
    ((number? val)
     (port-display-string (number->string val) p))
    ((symbol? val)
     (port-display-string (symbol->string val) p))
    ((eof-object? val)
     (port-display-string "#<eof>" p))
    ((bytevector? val)
     (port-display-string "#u8(" p)
     (let ((len (bytevector-length val)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (if (> i 0) (port-write-char #\space p))
               (port-display-string (number->string (bytevector-u8-ref val i)) p)
               (loop (+ i 1)))
             #t)))
     (port-write-char #\) p))
    ((vector? val)
     (port-display-string "#(" p)
     (let ((len (vector-length val)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (if (> i 0) (port-write-char #\space p))
               (%port-write-shared-node (vector-ref val i) p label-map defined-box)
               (loop (+ i 1)))
             #t)))
     (port-write-char #\) p))
    ((pair? val)
     (port-write-char #\( p)
     (let loop ((curr val) (first? #t))
       (cond
         ((null? curr)
          (port-write-char #\) p))
         ((pair? curr)
          (if (not first?)
              (let ((label-entry (%printer-assq curr label-map)))
                (if label-entry
                    ;; cdr is a shared node: emit as dot pair
                    (begin
                      (port-write-char #\space p)
                      (port-write-char #\. p)
                      (port-write-char #\space p)
                      (%port-write-shared-node curr p label-map defined-box)
                      (port-write-char #\) p))
                    ;; cdr is a regular pair: emit element and continue
                    (begin
                      (port-write-char #\space p)
                      (%port-write-shared-node (car curr) p label-map defined-box)
                      (loop (cdr curr) #f))))
              ;; First element
              (begin
                (%port-write-shared-node (car curr) p label-map defined-box)
                (loop (cdr curr) #f))))
         (else
          (port-write-char #\space p)
          (port-write-char #\. p)
          (port-write-char #\space p)
          (%port-write-shared-node curr p label-map defined-box)
          (port-write-char #\) p)))))
    (else
     (port-display-string "#<unknown>" p))))

(define (port-write-shared val p)
  (let* ((scan-state (%printer-scan-node val (cons '() '())))
         (label-map (%printer-build-label-map scan-state))
         (defined-box (cons '() '())))
    (%port-write-shared-node val p label-map defined-box)))

;; port-write is alias to port-write-shared for cycle safety (R7RS §6.13.3)
(define (port-write val p)
  (port-write-shared val p))

;;; -----------------------------------------------------------------------
;;; First-class Procedural Wrappers (R7RS Standard case-lambda Procedures)
;;; -----------------------------------------------------------------------

(define write-simple
  (case-lambda
    ((val) (port-write-simple val (current-output-port)))
    ((val p) (port-write-simple val p))))

(define write-shared
  (case-lambda
    ((val) (port-write-shared val (current-output-port)))
    ((val p) (port-write-shared val p))))

(define write
  (case-lambda
    ((val) (port-write-shared val (current-output-port)))
    ((val p) (port-write-shared val p))))

(define display
  (case-lambda
    ((val) (port-display val (current-output-port)))
    ((val p) (port-display val p))))

(define newline
  (case-lambda
    (() (port-newline (current-output-port)))
    ((p) (port-newline p))))
