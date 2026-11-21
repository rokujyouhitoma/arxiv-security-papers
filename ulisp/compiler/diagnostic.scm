;;; =======================================================================
;;; ULisp Compiler Component: Pretty Diagnostic Reporter
;;; Conforms to DSN-33-02 §3.4, DSN-38 §1/§2 & Issue #833
;;; Provides Clang/Rustc-style pretty diagnostics with line snippets,
;;; carets, underlines, macro expansion traces, similar symbol help,
;;; and configurable ANSI color support (--color=auto|always|never).
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Global Diagnostic Configuration & State
;;; -----------------------------------------------------------------------

(define *diagnostic-color-mode* (cons 'auto '())) ; 'auto | 'always | 'never
(define *diagnostic-error-count* (cons 0 '()))
(define *diagnostic-warning-count* (cons 0 '()))
(define *diagnostic-isatty-override* (cons #f '()))
(define *diagnostic-source-cache* (cons '() '())) ; ((file . #(line0 line1 ...)) ...)

(define *diagnostic-max-source-lines* 4096)
(define *diagnostic-max-line-len* 256)

(define (reset-diagnostic-state!)
  (set-car! *diagnostic-error-count* 0)
  (set-car! *diagnostic-warning-count* 0)
  (set-car! *diagnostic-source-cache* '()))

(define (diagnostic-error-count)
  (car *diagnostic-error-count*))

(define (diagnostic-warning-count)
  (car *diagnostic-warning-count*))

(define (set-diagnostic-color-mode! mode)
  (if (memq mode '(auto always never))
      (set-car! *diagnostic-color-mode* mode)
      (set-car! *diagnostic-color-mode* 'auto)))

(define (diagnostic-color-mode)
  (car *diagnostic-color-mode*))

(define (set-diagnostic-isatty-override! val)
  (set-car! *diagnostic-isatty-override* val))

(define (diagnostic-color-enabled?)
  (let ((mode (car *diagnostic-color-mode*)))
    (cond
      ((eq? mode 'never) #f)
      ((eq? mode 'always) #t)
      (else
       ;; 'auto mode: check NO_COLOR and TERM environment variables
       (let ((no-color (sys-getenv "NO_COLOR"))
             (term (sys-getenv "TERM"))
             (override (car *diagnostic-isatty-override*)))
         (cond
           ((and (string? no-color) (> (string-length no-color) 0)) #f)
           ((and (string? term) (string=? term "dumb")) #f)
           ((boolean? override) override)
           (else #t)))))))

;;; -----------------------------------------------------------------------
;;; 2. ANSI Escape Codes
;;; -----------------------------------------------------------------------

(define *esc-char* (integer->char 27))
(define *ansi-reset-str*   (string *esc-char* #\[ #\0 #\m))
(define *ansi-bold-str*    (string *esc-char* #\[ #\1 #\m))
(define *ansi-red-str*     (string *esc-char* #\[ #\1 #\; #\3 #\1 #\m))
(define *ansi-yellow-str*  (string *esc-char* #\[ #\1 #\; #\3 #\3 #\m))
(define *ansi-cyan-str*    (string *esc-char* #\[ #\1 #\; #\3 #\6 #\m))
(define *ansi-green-str*   (string *esc-char* #\[ #\1 #\; #\3 #\2 #\m))
(define *ansi-dim-str*     (string *esc-char* #\[ #\2 #\m))
(define *ansi-gutter-str*  (string *esc-char* #\[ #\3 #\6 #\m))

(define (diagnostic-color-reset)
  (if (diagnostic-color-enabled?) *ansi-reset-str* ""))

(define (diagnostic-color-bold)
  (if (diagnostic-color-enabled?) *ansi-bold-str* ""))

(define (diagnostic-color-red)
  (if (diagnostic-color-enabled?) *ansi-red-str* ""))

(define (diagnostic-color-yellow)
  (if (diagnostic-color-enabled?) *ansi-yellow-str* ""))

(define (diagnostic-color-cyan)
  (if (diagnostic-color-enabled?) *ansi-cyan-str* ""))

(define (diagnostic-color-green)
  (if (diagnostic-color-enabled?) *ansi-green-str* ""))

(define (diagnostic-color-dim)
  (if (diagnostic-color-enabled?) *ansi-dim-str* ""))

(define (diagnostic-color-gutter)
  (if (diagnostic-color-enabled?) *ansi-gutter-str* ""))

;;; -----------------------------------------------------------------------
;;; 3. Diagnostic Data Structure (<diagnostic>)
;;; -----------------------------------------------------------------------

(define-record-type <diagnostic>
  (%make-diagnostic-raw level code span message labels-box notes-box help-box)
  diagnostic?
  (level       diagnostic-level)
  (code        diagnostic-code)
  (span        diagnostic-span)
  (message     diagnostic-message)
  (labels-box  %diagnostic-labels-box)
  (notes-box   %diagnostic-notes-box)
  (help-box    %diagnostic-help-box))

(define (diagnostic-labels diag)
  (car (%diagnostic-labels-box diag)))

(define (diagnostic-notes diag)
  (car (%diagnostic-notes-box diag)))

(define (diagnostic-help diag)
  (car (%diagnostic-help-box diag)))

(define (make-diagnostic level code span message)
  (let* ((clean-level (if (memq level '(error warning note help)) level 'error))
         (clean-code (cond
                       ((symbol? code) code)
                       ((string? code) (string->symbol code))
                       (else #f)))
         (dspan (cond
                  ((dual-source-span? span) span)
                  ((and (ast-has-span? span) (dual-source-span? (ast-source-span span)))
                   (ast-source-span span))
                  (else #f)))
         (clean-span (cond
                       ((dual-source-span? span) (dual-source-span->source-span span))
                       ((source-span? span) span)
                       ((source-loc? span) (ast-source-span span))
                       ((ast-has-span? span)
                        (let ((s (ast-source-span span)))
                          (if (dual-source-span? s)
                              (dual-source-span->source-span s)
                              s)))
                       (else #f)))
         (clean-msg (if (string? message)
                        message
                        (let ((p (open-output-string)))
                          (display message p)
                          (get-output-string p))))
         (diag (%make-diagnostic-raw clean-level clean-code clean-span clean-msg
                                     (cons '() '())
                                     (cons '() '())
                                     (cons '() '()))))
    (if (and dspan
             (string? (span-interp-file dspan))
             (not (string=? (span-interp-file dspan) "<unknown>")))
        (diagnostic-add-note! diag
                              (string-append "evaluator context: "
                                             (span-interp-file dspan)
                                             ":"
                                             (number->string (span-interp-line dspan)))))
    diag))

(define (diagnostic-add-label! diag span label-text)
  (let* ((box (%diagnostic-labels-box diag))
         (clean-span (cond
                       ((dual-source-span? span) (dual-source-span->source-span span))
                       ((source-span? span) span)
                       ((source-loc? span) (ast-source-span span))
                       ((ast-has-span? span)
                        (let ((s (ast-source-span span)))
                          (if (dual-source-span? s)
                              (dual-source-span->source-span s)
                              s)))
                       (else #f)))
         (entry (cons clean-span (if (string? label-text) label-text ""))))
    (set-car! box (append (car box) (list entry)))
    diag))

(define (diagnostic-add-note! diag note-item)
  (let ((box (%diagnostic-notes-box diag)))
    (set-car! box (append (car box) (list note-item)))
    diag))

(define (diagnostic-add-help! diag help-str)
  (let ((box (%diagnostic-help-box diag))
        (clean-help (if (string? help-str) help-str "")))
    (set-car! box (append (car box) (list clean-help)))
    diag))

;;; -----------------------------------------------------------------------
;;; 4. Source Line Caching & Sanitization (THREAT-833-1, THREAT-833-3)
;;; -----------------------------------------------------------------------

(define (sanitize-diagnostic-line-chars line)
  (let* ((len (string-length line))
         (out (make-string len)))
    (let loop ((i 0))
      (if (>= i len)
          out
          (let* ((ch (string-ref line i))
                 (code (char->integer ch)))
            (cond
              ;; Preserve TAB
              ((= code 9)
               (string-set! out i #\space))
              ;; Sanitize ASCII control characters (< 32, DEL 127)
              ((or (< code 32) (= code 127))
               (string-set! out i #\space))
              (else
               (string-set! out i ch)))
            (loop (+ i 1)))))))

(define (truncate-diagnostic-line line)
  (if (> (string-length line) *diagnostic-max-line-len*)
      (string-append (substring line 0 *diagnostic-max-line-len*) " ...")
      line))

(define (string-contains? str sub)
  (let ((len-str (string-length str))
        (len-sub (string-length sub)))
    (if (= len-sub 0)
        #t
        (if (> len-sub len-str)
            #f
            (let loop ((i 0))
              (if (> (+ i len-sub) len-str)
                  #f
                  (let check ((j 0))
                    (if (= j len-sub)
                        #t
                        (if (char=? (string-ref str (+ i j)) (string-ref sub j))
                            (check (+ j 1))
                            (loop (+ i 1)))))))))))

(define (diagnostic-register-source-lines! file-path lines-vector)
  (if (and (string? file-path) (vector? lines-vector))
      (let ((clean (sanitize-source-path file-path)))
        (set-car! *diagnostic-source-cache*
                  (cons (cons clean lines-vector)
                        (car *diagnostic-source-cache*))))))

(define (diagnostic-register-source-string! file-path source-string)
  (if (and (string? file-path) (string? source-string))
      (let ((len (string-length source-string)))
        (let loop ((i 0) (start 0) (acc '()))
          (cond
            ((>= i len)
             (let* ((last-line (substring source-string start len))
                    (all-lines (reverse (cons last-line acc)))
                    (vec (list->vector all-lines)))
               (diagnostic-register-source-lines! file-path vec)))
            ((char=? (string-ref source-string i) #\newline)
             (let ((line (substring source-string start i)))
               (loop (+ i 1) (+ i 1) (cons line acc))))
            (else
             (loop (+ i 1) start acc)))))))

(define (diagnostic-load-file-lines file-path)
  (if (not (string? file-path))
      #f
      (let* ((clean (sanitize-source-path file-path))
             (entry (assoc clean (car *diagnostic-source-cache*))))
        (if entry
            (cdr entry)
            (if (or (string=? clean "<unknown>")
                    (string=? clean "")
                    (string=? clean "none")
                    (string=? clean "-")
                    (not (file-exists? clean)))
                #f
                (let ((p (open-input-file clean)))
                  (if (not p)
                      #f
                      (let loop ((lines '()) (count 0))
                        (if (>= count *diagnostic-max-source-lines*)
                            (begin
                              (close-input-port p)
                              (let ((vec (list->vector (reverse lines))))
                                (diagnostic-register-source-lines! clean vec)
                                vec))
                            (let ((line (port-read-line p)))
                              (if (eof-object? line)
                                  (begin
                                    (close-input-port p)
                                    (let ((vec (list->vector (reverse lines))))
                                      (diagnostic-register-source-lines! clean vec)
                                      vec))
                                  (loop (cons line lines) (+ count 1)))))))))))))

(define (diagnostic-get-source-line file-path line-no)
  (if (or (not (integer? line-no)) (< line-no 1))
      #f
      (let ((vec (diagnostic-load-file-lines file-path)))
        (if (not vec)
            #f
            (let ((idx (- line-no 1)))
              (if (and (>= idx 0) (< idx (vector-length vec)))
                  (truncate-diagnostic-line
                   (sanitize-diagnostic-line-chars (vector-ref vec idx)))
                  #f))))))

;;; -----------------------------------------------------------------------
;;; 5. Visual Formatting Engine (Clang / Rustc Style)
;;; -----------------------------------------------------------------------

(define (%diagnostic-make-string-fill len ch)
  (let ((s (make-string (max 0 len))))
    (let loop ((i 0))
      (if (>= i len)
          s
          (begin
            (string-set! s i ch)
            (loop (+ i 1)))))))

(define (diagnostic-pad-spaces count)
  (%diagnostic-make-string-fill count #\space))

(define (format-diagnostic diag)
  (let* ((p (open-output-string))
         (lvl (diagnostic-level diag))
         (code (diagnostic-code diag))
         (span (diagnostic-span diag))
         (msg (diagnostic-message diag))
         (lvl-str (cond
                    ((eq? lvl 'error) "error")
                    ((eq? lvl 'warning) "warning")
                    ((eq? lvl 'note) "note")
                    ((eq? lvl 'help) "help")
                    (else "error")))
         (lvl-color (cond
                      ((eq? lvl 'error) (diagnostic-color-red))
                      ((eq? lvl 'warning) (diagnostic-color-yellow))
                      ((eq? lvl 'note) (diagnostic-color-cyan))
                      ((eq? lvl 'help) (diagnostic-color-green))
                      (else (diagnostic-color-red)))))

    ;; Line 1: Header (e.g. error[S0001]: unbound variable)
    (display lvl-color p)
    (display lvl-str p)
    (if code
        (begin
          (display "[" p)
          (display (if (symbol? code) (symbol->string code) code) p)
          (display "]" p)))
    (display (diagnostic-color-bold) p)
    (display ": " p)
    (display msg p)
    (display (diagnostic-color-reset) p)
    (newline p)

    ;; Line 2+: Source Location & Snippet
    (if span
        (let* ((file (span-file span))
               (s-line (span-start-line span))
               (s-col (span-start-col span))
               (e-line (span-end-line span))
               (e-col (span-end-col span))
               (s-line-str (number->string s-line))
               (gutter-width (string-length s-line-str))
               (gutter-pad (diagnostic-pad-spaces gutter-width)))

          ;; Location arrow: --> file:line:col
          (display (diagnostic-color-cyan) p)
          (display "  --> " p)
          (display (diagnostic-color-reset) p)
          (display file p)
          (display ":" p)
          (display s-line p)
          (display ":" p)
          (display s-col p)
          (newline p)

          ;; Source snippet if line is loadable
          (let ((source-line (diagnostic-get-source-line file s-line)))
            (if source-line
                (let* ((col-offset (max 0 (- s-col 1)))
                       (col-span (if (and (= s-line e-line) (>= e-col s-col))
                                     (+ 1 (- e-col s-col))
                                     1))
                       (safe-caret-len (max 1 (min col-span 80)))
                       (caret-ch (if (eq? lvl 'error) #\^ (if (eq? lvl 'warning) #\^ #\-)))
                       (labels (diagnostic-labels diag))
                       (label-text (if (pair? labels)
                                       (cdr (car labels))
                                       "")))
                  ;; Empty gutter line
                  (display gutter-pad p)
                  (display (diagnostic-color-gutter) p)
                  (display " |" p)
                  (display (diagnostic-color-reset) p)
                  (newline p)

                  ;; Source code line
                  (display s-line-str p)
                  (display (diagnostic-color-gutter) p)
                  (display " | " p)
                  (display (diagnostic-color-reset) p)
                  (display source-line p)
                  (newline p)

                  ;; Carets / underline line
                  (display gutter-pad p)
                  (display (diagnostic-color-gutter) p)
                  (display " | " p)
                  (display (diagnostic-color-reset) p)
                  (display (diagnostic-pad-spaces col-offset) p)
                  (display lvl-color p)
                  (display (%diagnostic-make-string-fill safe-caret-len caret-ch) p)
                  (if (and (string? label-text) (> (string-length label-text) 0))
                      (begin
                        (display " " p)
                        (display label-text p)))
                  (display (diagnostic-color-reset) p)
                  (newline p))))

          ;; Macro origin trace
          (let loop-macro ((cur-origin (span-macro-origin span)))
            (if (and cur-origin (source-span? cur-origin))
                (begin
                  (display "   " p)
                  (display (diagnostic-color-cyan) p)
                  (display "= note: " p)
                  (display (diagnostic-color-reset) p)
                  (display "expanded from macro at " p)
                  (display (span-file cur-origin) p)
                  (display ":" p)
                  (display (span-start-line cur-origin) p)
                  (display ":" p)
                  (display (span-start-col cur-origin) p)
                  (newline p)
                  (loop-macro (span-macro-origin cur-origin)))))))

    ;; Secondary Notes
    (let loop-notes ((ns (diagnostic-notes diag)))
      (if (pair? ns)
          (let ((note (car ns)))
            (display "   " p)
            (display (diagnostic-color-cyan) p)
            (display "= note: " p)
            (display (diagnostic-color-reset) p)
            (cond
              ((string? note)
               (display note p))
              ((and (pair? note) (source-span? (car note)))
               (display (cdr note) p)
               (display " (at " p)
               (display (span-file (car note)) p)
               (display ":" p)
               (display (span-start-line (car note)) p)
               (display ":" p)
               (display (span-start-col (car note)) p)
               (display ")" p))
              (else
               (display note p)))
            (newline p)
            (loop-notes (cdr ns)))))

    ;; Fix-it / Help suggestions
    (let loop-help ((hs (diagnostic-help diag)))
      (if (pair? hs)
          (let ((h (car hs)))
            (display "   " p)
            (display (diagnostic-color-green) p)
            (display "= help: " p)
            (display (diagnostic-color-reset) p)
            (display h p)
            (newline p)
            (loop-help (cdr hs)))))

    (get-output-string p)))

(define (diagnostic-default-error-port)
  (cond
    ((and (procedure? get-compiler-error-port) (not (null? (get-compiler-error-port))))
     (get-compiler-error-port))
    ((and (procedure? current-error-port) (not (null? (current-error-port))))
     (current-error-port))
    (else *stdout-port*)))

(define (render-diagnostic diag port)
  (let ((formatted (format-diagnostic diag)))
    (display formatted port)))

(define (render-diagnostic-default diag)
  (render-diagnostic diag (diagnostic-default-error-port)))

(define (report-diagnostic diag)
  (let ((lvl (diagnostic-level diag)))
    (cond
      ((eq? lvl 'error)
       (set-car! *diagnostic-error-count* (+ (car *diagnostic-error-count*) 1)))
      ((eq? lvl 'warning)
       (set-car! *diagnostic-warning-count* (+ (car *diagnostic-warning-count*) 1))))
    (render-diagnostic diag (diagnostic-default-error-port))))

;;; -----------------------------------------------------------------------
;;; 6. High-Level Emission Helpers
;;; -----------------------------------------------------------------------

(define (emit-diagnostic-error code span message help-str)
  (let ((diag (make-diagnostic 'error code span message)))
    (if (and (string? help-str) (> (string-length help-str) 0))
        (diagnostic-add-help! diag help-str))
    (report-diagnostic diag)
    diag))

(define (emit-diagnostic-warning code span message help-str)
  (let ((diag (make-diagnostic 'warning code span message)))
    (if (and (string? help-str) (> (string-length help-str) 0))
        (diagnostic-add-help! diag help-str))
    (report-diagnostic diag)
    diag))

(define (emit-diagnostic-note code span message)
  (let ((diag (make-diagnostic 'note code span message)))
    (report-diagnostic diag)
    diag))
