;;; =======================================================================
;;; ULisp Compiler Pass 132: Braun et al. (2013) SSA & Block Arguments Engine
;;; =======================================================================

;;; Conforms to DSN-33 Section 8.1 & Issue #523
;;; =======================================================================

(define (make-braun-cfg)
  (list (cons 'blocks '())            ; (label . (insts ...))
        (cons 'order '())             ; (lbl1 lbl2 ...)
        (cons 'preds '())             ; (label . (pred1 pred2 ...))
        (cons 'sealed '())            ; (lbl1 lbl2 ...)
        (cons 'params '())            ; (label . (p1 p2 ...))
        (cons 'defs '())              ; ((var . lbl) . val)
        (cons 'incomplete '())        ; (label . ((param . var) ...))
        (cons 'incoming '())          ; ((param . pred) . val)
        (cons 'replacements '())      ; (param . canonical-val)
        (cons 'terminators '())       ; (label . terminator-inst)
        (cons 'current-block #f)))

(define (braun-cfg-ref cfg key)
  (let ((entry (assq key cfg)))
    (if entry (cdr entry) '())))

(define (braun-cfg-set! cfg key val)
  (let ((entry (assq key cfg)))
    (if entry
        (set-cdr! entry val)
        (error "Unknown Braun CFG key:" key))))

(define (braun-new-block! cfg label)
  (let ((order (braun-cfg-ref cfg 'order))
        (blocks (braun-cfg-ref cfg 'blocks))
        (preds (braun-cfg-ref cfg 'preds))
        (params (braun-cfg-ref cfg 'params))
        (incomplete (braun-cfg-ref cfg 'incomplete))
        (terms (braun-cfg-ref cfg 'terminators)))
    (braun-cfg-set! cfg 'order (append order (list label)))
    (braun-cfg-set! cfg 'blocks (cons (cons label '()) blocks))
    (braun-cfg-set! cfg 'preds (cons (cons label '()) preds))
    (braun-cfg-set! cfg 'params (cons (cons label '()) params))
    (braun-cfg-set! cfg 'incomplete (cons (cons label '()) incomplete))
    (braun-cfg-set! cfg 'terminators (cons (cons label #f) terms))
    (braun-cfg-set! cfg 'current-block label)
    label))

(define (braun-add-edge! cfg from-lbl to-lbl)
  (let* ((preds (braun-cfg-ref cfg 'preds))
         (entry (assq to-lbl preds)))
    (if entry
        (if (not (memq from-lbl (cdr entry)))
            (set-cdr! entry (append (cdr entry) (list from-lbl))))
        (braun-cfg-set! cfg 'preds (cons (list to-lbl from-lbl) preds)))))

(define (braun-get-preds cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'preds))))
    (if entry (cdr entry) '())))

(define (braun-get-params cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'params))))
    (if entry (cdr entry) '())))

(define (braun-add-param! cfg block-lbl param)
  (let* ((params (braun-cfg-ref cfg 'params))
         (entry (assq block-lbl params)))
    (if entry
        (if (not (memq param (cdr entry)))
            (set-cdr! entry (append (cdr entry) (list param))))
        (braun-cfg-set! cfg 'params (cons (list block-lbl param) params)))))

(define (braun-write-variable! cfg var block-lbl val)
  (let* ((defs (braun-cfg-ref cfg 'defs))
         (key (cons var block-lbl))
         (entry (assoc key defs)))
    (if entry
        (set-cdr! entry val)
        (braun-cfg-set! cfg 'defs (cons (cons key val) defs)))))

(define (braun-resolve-val cfg val)
  (let* ((reps (braun-cfg-ref cfg 'replacements))
         (entry (assq val reps)))
    (if entry
        (braun-resolve-val cfg (cdr entry))
        val)))

(define (braun-set-incoming! cfg param pred val)
  (let* ((inc (braun-cfg-ref cfg 'incoming))
         (key (cons param pred))
         (entry (assoc key inc)))
    (if entry
        (set-cdr! entry val)
        (braun-cfg-set! cfg 'incoming (cons (cons key val) inc)))))

(define (braun-get-incoming cfg param pred)
  (let* ((inc (braun-cfg-ref cfg 'incoming))
         (key (cons param pred))
         (entry (assoc key inc)))
    (if entry (cdr entry) #f)))

(define (braun-try-remove-trivial! cfg block-lbl param)
  (let* ((preds (braun-get-preds cfg block-lbl)))
    (let loop ((ps preds) (same #f) (trivial? #t))
      (if (null? ps)
          (if trivial?
              (let ((replacement (if same same param)))
                (if (not (equal? replacement param))
                    (begin
                      (let ((reps (braun-cfg-ref cfg 'replacements)))
                        (braun-cfg-set! cfg 'replacements (cons (cons param replacement) reps)))
                      (let* ((params (braun-cfg-ref cfg 'params))
                             (p-entry (assq block-lbl params)))
                        (if p-entry
                            (set-cdr! p-entry (filter (lambda (p) (not (eq? p param))) (cdr p-entry)))))
                      replacement)
                    param))
              param)
          (let* ((pred (car ps))
                 (op (braun-resolve-val cfg (braun-get-incoming cfg param pred))))
            (cond
              ((or (equal? op param) (equal? op same))
               (loop (cdr ps) same trivial?))
              ((eq? same #f)
               (loop (cdr ps) op trivial?))
              (else
               (loop '() same #f))))))))

(define (braun-add-arguments! cfg block-lbl param var)
  (let ((preds (braun-get-preds cfg block-lbl)))
    (for-each
     (lambda (pred)
       (let ((val (braun-read-variable cfg var pred)))
         (braun-set-incoming! cfg param pred val)))
     preds)
    (braun-try-remove-trivial! cfg block-lbl param)))

(define (braun-read-variable-recursive cfg var block-lbl)
  (let* ((sealed (braun-cfg-ref cfg 'sealed))
         (is-sealed? (memq block-lbl sealed)))
    (if (not is-sealed?)
        ;; Incomplete CFG: block not sealed yet
        (let ((param (unique-label-sym (string-append "ba_" (symbol->string var) "_"))))
          (braun-add-param! cfg block-lbl param)
          (let* ((incomp (braun-cfg-ref cfg 'incomplete))
                 (entry (assq block-lbl incomp)))
            (if entry
                (set-cdr! entry (cons (cons param var) (cdr entry)))
                (braun-cfg-set! cfg 'incomplete (cons (list block-lbl (cons param var)) incomp))))
          (braun-write-variable! cfg var block-lbl param)
          param)
        ;; Sealed block
        (let ((preds (braun-get-preds cfg block-lbl)))
          (cond
            ((null? preds)
             var)
            ((null? (cdr preds))
             ;; Single predecessor optimization: no block argument needed!
             (let ((val (braun-read-variable cfg var (car preds))))
               (braun-write-variable! cfg var block-lbl val)
               val))
            (else
             ;; Multiple predecessors: create block argument
             (let ((param (unique-label-sym (string-append "ba_" (symbol->string var) "_"))))
               (braun-add-param! cfg block-lbl param)
               (braun-write-variable! cfg var block-lbl param)
               (let ((resolved (braun-add-arguments! cfg block-lbl param var)))
                 (braun-write-variable! cfg var block-lbl resolved)
                 resolved))))))))

(define (braun-read-variable cfg var block-lbl)
  (let* ((defs (braun-cfg-ref cfg 'defs))
         (key (cons var block-lbl))
         (entry (assoc key defs)))
    (if entry
        (braun-resolve-val cfg (cdr entry))
        (braun-read-variable-recursive cfg var block-lbl))))

(define (braun-seal-block! cfg block-lbl)
  (let ((sealed (braun-cfg-ref cfg 'sealed)))
    (if (not (memq block-lbl sealed))
        (begin
          (braun-cfg-set! cfg 'sealed (cons block-lbl sealed))
          (let* ((incomp-entry (assq block-lbl (braun-cfg-ref cfg 'incomplete)))
                 (incomps (if incomp-entry (cdr incomp-entry) '())))
            (if incomp-entry (set-cdr! incomp-entry '()))
            (for-each
             (lambda (pair)
               (let ((param (car pair))
                     (var (cdr pair)))
                 (braun-add-arguments! cfg block-lbl param var)))
             (reverse incomps)))))))

(define (braun-emit-inst! cfg block-lbl inst)
  (let* ((blocks (braun-cfg-ref cfg 'blocks))
         (entry (assq block-lbl blocks)))
    (if entry
        (set-cdr! entry (append (cdr entry) (list inst)))
        (braun-cfg-set! cfg 'blocks (cons (list block-lbl inst) blocks)))))

(define (braun-get-insts cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'blocks))))
    (if entry (cdr entry) '())))

(define (braun-set-terminator! cfg block-lbl term)
  (let* ((terms (braun-cfg-ref cfg 'terminators))
         (entry (assq block-lbl terms)))
    (if entry
        (set-cdr! entry term)
        (braun-cfg-set! cfg 'terminators (cons (cons block-lbl term) terms)))))

(define (braun-get-terminator cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'terminators))))
    (if entry (cdr entry) #f)))

;;; Path Splitting & Join Block Bypass for Braun SSA CFG (Chambers & Ungar 1989)
(define (braun-cfg-path-split! cfg)
  (let ((order (braun-cfg-ref cfg 'order)))
    (for-each
     (lambda (join-lbl)
       (let ((term (braun-get-terminator cfg join-lbl)))
         (if (and term (or (eq? (car term) '%jump-if) (eq? (car term) '%jump-if-false)))
             (let* ((cond-var (cadr term))
                    (then-target (if (eq? (car term) '%jump-if) (caddr term) #f))
                    (else-target (if (eq? (car term) '%jump-if) (cadddr term) (caddr term)))
                    (preds (braun-get-preds cfg join-lbl)))
               (for-each
                (lambda (pred-lbl)
                  (let* ((inc-val (braun-resolve-val cfg (braun-get-incoming cfg cond-var pred-lbl)))
                         (pred-term (braun-get-terminator cfg pred-lbl)))
                    (if (and inc-val pred-term (eq? (car pred-term) '%jump) (eq? (cadr pred-term) join-lbl))
                        ;; Check if incoming condition value is statically truthy or falsy
                        (let ((is-false? (or (eq? inc-val #f) (equal? inc-val 47))))
                          (cond
                            ((and is-false? else-target)
                             ;; Bypass join-lbl directly to else-target from pred-lbl
                             (let ((join-insts (braun-get-insts cfg join-lbl)))
                               (for-each (lambda (inst) (braun-emit-inst! cfg pred-lbl inst)) join-insts)
                               (braun-set-terminator! cfg pred-lbl (list '%jump else-target))
                               (braun-add-edge! cfg pred-lbl else-target)))
                            ((and (not is-false?) then-target)
                             ;; Bypass join-lbl directly to then-target from pred-lbl
                             (let ((join-insts (braun-get-insts cfg join-lbl)))
                               (for-each (lambda (inst) (braun-emit-inst! cfg pred-lbl inst)) join-insts)
                               (braun-set-terminator! cfg pred-lbl (list '%jump then-target))
                               (braun-add-edge! cfg pred-lbl then-target))))))))
                preds)))))
     order)
    cfg))

;;; Converts a Braun CFG into structured Block Arguments LIR
(define (braun-cfg->lir cfg)
  (let ((order (braun-cfg-ref cfg 'order)))
    (map
     (lambda (lbl)
       (let* ((params (braun-get-params cfg lbl))
              (raw-insts (braun-get-insts cfg lbl))
              ;; Resolve any variables in instructions
              (insts
               (map (lambda (inst)
                      (map (lambda (elem) (braun-resolve-val cfg elem)) inst))
                    raw-insts))
              (term (braun-get-terminator cfg lbl))
              (term-inst
               (cond
                 ((not term) '())
                 ((eq? (car term) '%jump)
                  (let* ((target (cadr term))
                         (target-params (braun-get-params cfg target))
                         (args (map (lambda (p)
                                      (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                    target-params)))
                    (list (list '%jump target args))))
                 ((eq? (car term) '%jump-if-false)
                  (let* ((cond-var (braun-resolve-val cfg (cadr term)))
                         (else-lbl (caddr term))
                         (else-params (braun-get-params cfg else-lbl))
                         (else-args (map (lambda (p)
                                           (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                         else-params)))
                    (list (list '%jump-if-false cond-var else-lbl else-args))))
                 ((eq? (car term) '%jump-if)
                  (let* ((cond-var (braun-resolve-val cfg (cadr term)))
                         (then-lbl (caddr term))
                         (else-lbl (cadddr term))
                         (then-params (braun-get-params cfg then-lbl))
                         (then-args (map (lambda (p)
                                           (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                         then-params))
                         (else-params (braun-get-params cfg else-lbl))
                         (else-args (map (lambda (p)
                                           (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                         else-params)))
                    (list (list '%jump-if cond-var then-lbl then-args else-lbl else-args))))
                 ((eq? (car term) '%return)
                  (let ((val (if (pair? (cdr term))
                                 (braun-resolve-val cfg (cadr term))
                                 '%rax)))
                    (list (list '%return val))))
                 (else (list term))))
              (block-body (append insts term-inst)))
         (cons '%block (cons lbl (cons params block-body)))))
     order)))
