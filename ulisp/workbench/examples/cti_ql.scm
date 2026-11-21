;;; =======================================================================
;;; CTI-QL (CTI Query Language) Reference Implementation
;;; Conforms to DSN-33-04 §7 (CTI-QL Workbench Architecture), Issue #897
;;; Pure Scheme. Zero External Dependencies.
;;; =======================================================================
;;; Provides:
;;; - Guest Object Model: <cti-event> (threat, ip-addr, port, cve-score)
;;; - Guest Frame Descriptor: (make-cti-event-gfd)
;;; - Declarative PEG Grammar Specification: cti-ql-grammar-rules
;;; - Parser with Dual Source Span Tracking: (parse-cti-ql str filename)
;;; - Single-Source Reference Evaluator: (eval-cti-ql ast event)
;;; - Direct Cogen Compiler Derivation Rules: cti-ql-cogen-rules
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Guest Object Model: <cti-event>
;;; -----------------------------------------------------------------------

;; CTI Event representation: 4-slot fixed memory descriptor
;; Slot 0: threat    (:string or :symbol)
;; Slot 1: ip-addr   (:string)
;; Slot 2: port      (:fixnum)
;; Slot 3: cve-score (:fixnum)

(define (make-cti-event threat ip-addr port cve-score)
  (vector threat ip-addr port cve-score))

(define (cti-event? obj)
  (and (vector? obj) (= (vector-length obj) 4)))

(define (cti-event-threat ev)    (vector-ref ev 0))
(define (cti-event-ip-addr ev)   (vector-ref ev 1))
(define (cti-event-port ev)      (vector-ref ev 2))
(define (cti-event-cve-score ev) (vector-ref ev 3))

(define (cti-event-field-slot name)
  (case name
    ((threat) 0)
    ((ip ip-addr) 1)
    ((port) 2)
    ((cve cve-score) 3)
    (else #f)))

(define (make-cti-event-gfd)
  (let ((gfd (gfd-empty)))
    (gfd-add-slot! gfd 'threat 'string)
    (gfd-add-slot! gfd 'ip-addr 'string)
    (gfd-add-slot! gfd 'port 'fixnum)
    (gfd-add-slot! gfd 'cve-score 'fixnum)
    gfd))

;;; -----------------------------------------------------------------------
;;; 2. Single-Source Reference Interpreter: eval-cti-ql
;;; -----------------------------------------------------------------------

(define (cti-error msg irritant)
  (raise (list 'cti-error msg irritant)))

(define (cti-eval-field field-sym ev)
  (let ((slot (cti-event-field-slot field-sym)))
    (if slot
        (vector-ref ev slot)
        (cti-error "cti-eval-field: unknown CTI field" field-sym))))

(define (eval-cti-ql ast ev)
  (let ((node (if (ast-has-span? ast) (ast-strip-span ast) ast)))
    (cond
      ((not (pair? node)) node)
      (else
       (let ((tag (car node)))
         (case tag
           ((query)
            (eval-cti-ql (cadr node) ev))
           ((AND and)
            (and (eval-cti-ql (cadr node) ev)
                 (eval-cti-ql (caddr node) ev)))
           ((OR or)
            (or (eval-cti-ql (cadr node) ev)
                (eval-cti-ql (caddr node) ev)))
           ((==)
            (let ((lhs (if (symbol? (cadr node)) (cti-eval-field (cadr node) ev) (eval-cti-ql (cadr node) ev)))
                  (rhs (if (symbol? (caddr node)) (cti-eval-field (caddr node) ev) (eval-cti-ql (caddr node) ev))))
              (equal? lhs rhs)))
           ((!=)
            (let ((lhs (if (symbol? (cadr node)) (cti-eval-field (cadr node) ev) (eval-cti-ql (cadr node) ev)))
                  (rhs (if (symbol? (caddr node)) (cti-eval-field (caddr node) ev) (eval-cti-ql (caddr node) ev))))
              (not (equal? lhs rhs))))
           ((>=)
            (let ((lhs (if (symbol? (cadr node)) (cti-eval-field (cadr node) ev) (eval-cti-ql (cadr node) ev)))
                  (rhs (if (symbol? (caddr node)) (cti-eval-field (caddr node) ev) (eval-cti-ql (caddr node) ev))))
              (>= lhs rhs)))
           ((<=)
            (let ((lhs (if (symbol? (cadr node)) (cti-eval-field (cadr node) ev) (eval-cti-ql (cadr node) ev)))
                  (rhs (if (symbol? (caddr node)) (cti-eval-field (caddr node) ev) (eval-cti-ql (caddr node) ev))))
              (<= lhs rhs)))
           ((>)
            (let ((lhs (if (symbol? (cadr node)) (cti-eval-field (cadr node) ev) (eval-cti-ql (cadr node) ev)))
                  (rhs (if (symbol? (caddr node)) (cti-eval-field (caddr node) ev) (eval-cti-ql (caddr node) ev))))
              (> lhs rhs)))
           ((<)
            (let ((lhs (if (symbol? (cadr node)) (cti-eval-field (cadr node) ev) (eval-cti-ql (cadr node) ev)))
                  (rhs (if (symbol? (caddr node)) (cti-eval-field (cadr node) ev) (eval-cti-ql (caddr node) ev))))
              (< lhs rhs)))
           (else
            (cti-error "eval-cti-ql: unsupported AST operator" tag))))))))

;;; -----------------------------------------------------------------------
;;; 3. Declarative PEG Grammar Specification
;;; -----------------------------------------------------------------------

(define cti-ql-grammar-rules
  '((query       (seq expr end-of-input))
    (expr        (alt (seq term "OR" expr) term))
    (term        (alt (seq factor "AND" term) factor))
    (factor      (alt (seq "(" expr ")") predicate))
    (predicate   (seq field-name op-cmp literal-val))
    (field-name  (alt "threat" "ip" "ip-addr" "port" "cve" "cve-score"))
    (op-cmp      (alt "==" "!=" ">=" "<=" ">" "<"))
    (literal-val (alt string-lit num-lit))))

;;; -----------------------------------------------------------------------
;;; 4. Tokenizer & Parser with Dual Source Span (CWE-20 Mitigation)
;;; -----------------------------------------------------------------------

(define (cti-whitespace-char? c)
  (or (char=? c #\space) (char=? c #\tab) (char=? c #\newline) (char=? c (integer->char 13))))

(define (cti-tokenize str)
  (let ((len (string-length str)))
    (let loop ((i 0) (line 1) (col 1) (acc '()))
      (if (>= i len)
          (reverse acc)
          (let ((c (string-ref str i)))
            (cond
              ((char=? c #\newline)
               (loop (+ i 1) (+ line 1) 1 acc))
              ((cti-whitespace-char? c)
               (loop (+ i 1) line (+ col 1) acc))
              ((char=? c #\()
               (loop (+ i 1) line (+ col 1) (cons (list 'LPAREN "(" line col) acc)))
              ((char=? c #\))
               (loop (+ i 1) line (+ col 1) (cons (list 'RPAREN ")" line col) acc)))
              ;; Operators
              ((and (< (+ i 1) len)
                    (or (string=? (substring str i (+ i 2)) "==")
                        (string=? (substring str i (+ i 2)) "!=")
                        (string=? (substring str i (+ i 2)) ">=")
                        (string=? (substring str i (+ i 2)) "<=")))
               (let ((op (string->symbol (substring str i (+ i 2)))))
                 (loop (+ i 2) line (+ col 2) (cons (list 'OP op line col) acc))))
              ((or (char=? c #\>) (char=? c #\<))
               (let ((op (string->symbol (string c))))
                 (loop (+ i 1) line (+ col 1) (cons (list 'OP op line col) acc))))
              ;; String literals
              ((char=? c #\")
               (let s-loop ((j (+ i 1)) (s-acc '()))
                 (if (>= j len)
                     (cti-error "cti-tokenize: unclosed string literal (CWE-20)" line)
                     (let ((sc (string-ref str j)))
                       (if (char=? sc #\")
                           (loop (+ j 1) line (+ col (- j i) 1)
                                 (cons (list 'STRING (list->string (reverse s-acc)) line col) acc))
                           (s-loop (+ j 1) (cons sc s-acc)))))))
              ;; Identifiers or Keywords or Numbers
              (else
               (let id-loop ((j i) (id-acc '()))
                 (if (or (>= j len)
                         (let ((jc (string-ref str j)))
                           (or (cti-whitespace-char? jc)
                               (char=? jc #\() (char=? jc #\))
                               (char=? jc #\=) (char=? jc #\!)
                               (char=? jc #\>) (char=? jc #\<)
                               (char=? jc #\"))))
                     (let* ((token-str (list->string (reverse id-acc)))
                            (tok-len (- j i))
                            (tok (cond
                                   ((or (string=? token-str "AND") (string=? token-str "and"))
                                    (list 'AND 'AND line col))
                                   ((or (string=? token-str "OR") (string=? token-str "or"))
                                    (list 'OR 'OR line col))
                                   ((and (> (string-length token-str) 0)
                                         (let ((c0 (string-ref token-str 0)))
                                           (or (and (char>=? c0 #\0) (char<=? c0 #\9))
                                               (and (char=? c0 #\-) (> (string-length token-str) 1)))))
                                    (list 'NUMBER (string->number token-str) line col))
                                   (else
                                    (list 'IDENT (string->symbol token-str) line col)))))
                       (loop j line (+ col tok-len) (cons tok acc)))
                     (id-loop (+ j 1) (cons (string-ref str j) id-acc)))))))))))

;; Parse CTI-QL tokens into AST with Dual Source Span attached
(define (parse-cti-ql-tokens tokens guest-file)
  (define interp-file "ulisp/workbench/examples/cti_ql.scm")
  
  (define (make-node-span tok-line tok-col interp-line)
    (make-dual-source-span guest-file (if tok-line tok-line 1) (if tok-col tok-col 1)
                           interp-file interp-line 1))

  (define (parse-expr toks)
    (let-values (((term-ast rem-toks) (parse-term toks)))
      (if (and (pair? rem-toks) (eq? (caar rem-toks) 'OR))
          (let* ((or-tok (car rem-toks))
                 (span (make-node-span (caddr or-tok) (cadddr or-tok) 100)))
            (let-values (((next-ast next-rem) (parse-expr (cdr rem-toks))))
              (values (ast-with-span (list 'OR term-ast next-ast) span) next-rem)))
          (values term-ast rem-toks))))

  (define (parse-term toks)
    (let-values (((factor-ast rem-toks) (parse-factor toks)))
      (if (and (pair? rem-toks) (eq? (caar rem-toks) 'AND))
          (let* ((and-tok (car rem-toks))
                 (span (make-node-span (caddr and-tok) (cadddr and-tok) 105)))
            (let-values (((next-ast next-rem) (parse-term (cdr rem-toks))))
              (values (ast-with-span (list 'AND factor-ast next-ast) span) next-rem)))
          (values factor-ast rem-toks))))

  (define (parse-factor toks)
    (if (null? toks)
        (cti-error "parse-cti-ql: unexpected EOF in factor (CWE-20)" guest-file)
        (let ((tok (car toks)))
          (cond
            ((eq? (car tok) 'LPAREN)
             (let-values (((inner-ast rem) (parse-expr (cdr toks))))
               (if (or (null? rem) (not (eq? (caar rem) 'RPAREN)))
                   (cti-error "parse-cti-ql: missing closing parenthesis (CWE-20)" guest-file)
                   (values inner-ast (cdr rem)))))
            (else
             (parse-predicate toks))))))

  (define (parse-predicate toks)
    (if (or (null? toks) (null? (cdr toks)) (null? (cddr toks)))
        (cti-error "parse-cti-ql: incomplete predicate" toks)
        (let* ((id-tok (car toks))
               (op-tok (cadr toks))
               (val-tok (caddr toks)))
          (if (not (eq? (car id-tok) 'IDENT))
              (cti-error "parse-cti-ql: expected field identifier" id-tok))
          (if (not (eq? (car op-tok) 'OP))
              (cti-error "parse-cti-ql: expected comparison operator" op-tok))
          (let* ((field (cadr id-tok))
                 (op (cadr op-tok))
                 (val (cond
                        ((eq? (car val-tok) 'STRING) (cadr val-tok))
                        ((eq? (car val-tok) 'NUMBER) (cadr val-tok))
                        ((eq? (car val-tok) 'IDENT) (cadr val-tok))
                        (else (cti-error "parse-cti-ql: unexpected literal" val-tok))))
                 (span (make-node-span (caddr id-tok) (cadddr id-tok) 120))
                 (pred-ast (ast-with-span (list op field val) span)))
            (values pred-ast (cdddr toks))))))

  (if (null? tokens)
      '(query #t)
      (let-values (((ast rem) (parse-expr tokens)))
        (if (not (null? rem))
            (cti-error "parse-cti-ql: trailing tokens after query" (caar rem))
            (list 'query ast)))))

(define (parse-cti-ql str guest-file)
  (let ((tokens (cti-tokenize str)))
    (parse-cti-ql-tokens tokens guest-file)))

;;; -----------------------------------------------------------------------
;;; 5. Direct Cogen Specializer Rules for CTI-QL (Tower Collapse)
;;; -----------------------------------------------------------------------

(define cti-ql-cogen-rules
  (list
   ;; Query wrapper
   (cons 'query
         (lambda (node rules gfd runtime-model depth)
           (cogen-lower-ast (cadr node) rules gfd runtime-model depth)))

   ;; Logical AND
   (cons 'AND
         (lambda (node rules gfd runtime-model depth)
           (let ((lhs (cogen-lower-ast (cadr node) rules gfd runtime-model depth))
                 (rhs (cogen-lower-ast (caddr node) rules gfd runtime-model depth)))
             (make-lir-binop 'AND lhs rhs))))

   ;; Logical OR
   (cons 'OR
         (lambda (node rules gfd runtime-model depth)
           (let ((lhs (cogen-lower-ast (cadr node) rules gfd runtime-model depth))
                 (rhs (cogen-lower-ast (caddr node) rules gfd runtime-model depth)))
             (make-lir-binop 'OR lhs rhs))))

   ;; Comparison operators: resolve field to static slot
   (cons '==
         (lambda (node rules gfd runtime-model depth)
           (let* ((field (cadr node))
                  (slot (cti-event-field-slot field))
                  (val (caddr node)))
             (if (not slot)
                 (cti-error "cti-cogen: unknown field in comparison" field)
                 (make-lir-binop '== (make-lir-slot-ref slot field) (make-lir-const val))))))

   (cons '!=
         (lambda (node rules gfd runtime-model depth)
           (let* ((field (cadr node))
                  (slot (cti-event-field-slot field))
                  (val (caddr node)))
             (if (not slot)
                 (cti-error "cti-cogen: unknown field in comparison" field)
                 (make-lir-binop '!= (make-lir-slot-ref slot field) (make-lir-const val))))))

   (cons '>=
         (lambda (node rules gfd runtime-model depth)
           (let* ((field (cadr node))
                  (slot (cti-event-field-slot field))
                  (val (caddr node)))
             (if (not slot)
                 (cti-error "cti-cogen: unknown field in comparison" field)
                 (make-lir-binop '>= (make-lir-slot-ref slot field) (make-lir-const val))))))

   (cons '<=
         (lambda (node rules gfd runtime-model depth)
           (let* ((field (cadr node))
                  (slot (cti-event-field-slot field))
                  (val (caddr node)))
             (if (not slot)
                 (cti-error "cti-cogen: unknown field in comparison" field)
                 (make-lir-binop '<= (make-lir-slot-ref slot field) (make-lir-const val))))))

   (cons '>
         (lambda (node rules gfd runtime-model depth)
           (let* ((field (cadr node))
                  (slot (cti-event-field-slot field))
                  (val (caddr node)))
             (if (not slot)
                 (cti-error "cti-cogen: unknown field in comparison" field)
                 (make-lir-binop '> (make-lir-slot-ref slot field) (make-lir-const val))))))

   (cons '<
         (lambda (node rules gfd runtime-model depth)
           (let* ((field (cadr node))
                  (slot (cti-event-field-slot field))
                  (val (caddr node)))
             (if (not slot)
                 (cti-error "cti-cogen: unknown field in comparison" field)
                 (make-lir-binop '< (make-lir-slot-ref slot field) (make-lir-const val))))))))
