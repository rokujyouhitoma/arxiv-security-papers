;;; =======================================================================
;;; ULisp Compiler Pass 015: Nanopass DSL Procedural Expander
;;; Conforms to DSN-33 Architecture Specification & Issue #587
;;;
;;; Pre-emptively expands Nanopass DSL forms (define-language, define-pass,
;;; define-parser, define-unparser) into canonical Scheme definitions
;;; before syntax-rules macro expansion (Pass 020). Also filters out
;;; host-only define-macro declarations to keep downstream passes pure.
;;; =======================================================================

(define (expand-dsl-forms forms)
  (let loop ((fs forms) (res '()))
    (if (null? fs)
        (reverse res)
        (let ((f (car fs)))
          (cond
            ((and (pair? f) (eq? (car f) '%source-loc))
             (let ((file (cadr f))
                   (line (caddr f))
                   (col (cadddr f))
                   (inner (car (cddddr f))))
               (cond
                 ((and (pair? inner) (memq (car inner) '(define-language define-pass trace-define-pass define-parser define-unparser)))
                  (let ((exp-inner (expand-dsl-forms (list inner))))
                    (loop (append (map (lambda (x) (list '%source-loc file line col x)) exp-inner)
                                  (cdr fs))
                          res)))
                 ((and (pair? inner) (eq? (car inner) 'define-macro))
                  (loop (cdr fs) res))
                 (else
                  (loop (cdr fs) (cons f res))))))
            ((and (pair? f) (eq? (car f) 'begin))
             (loop (append (cdr f) (cdr fs)) res))
            ((and (pair? f) (eq? (car f) 'define-macro))
             ;; Discard host-only macro definitions in compiler pipeline
             (loop (cdr fs) res))
            ((and (pair? f) (eq? (car f) 'define-language))
             (let ((expanded (nanopass-expand-define-language f)))
               (loop (append (if (and (pair? expanded) (eq? (car expanded) 'begin))
                                 (cdr expanded)
                                 (list expanded))
                             (cdr fs))
                     res)))
            ((and (pair? f) (eq? (car f) 'define-pass))
             (let ((expanded (nanopass-expand-define-pass f)))
               (loop (append (if (and (pair? expanded) (eq? (car expanded) 'begin))
                                 (cdr expanded)
                                 (list expanded))
                             (cdr fs))
                     res)))
            ((and (pair? f) (eq? (car f) 'trace-define-pass))
             (let ((expanded (nanopass-expand-trace-define-pass f)))
               (loop (append (if (and (pair? expanded) (eq? (car expanded) 'begin))
                                 (cdr expanded)
                                 (list expanded))
                             (cdr fs))
                     res)))
            ((and (pair? f) (eq? (car f) 'define-parser))
             (let ((expanded (nanopass-expand-define-parser f)))
               (loop (cons expanded (cdr fs)) res)))
            ((and (pair? f) (eq? (car f) 'define-unparser))
             (let ((expanded (nanopass-expand-define-unparser f)))
               (loop (cons expanded (cdr fs)) res)))
            (else
             (loop (cdr fs) (cons f res))))))))
