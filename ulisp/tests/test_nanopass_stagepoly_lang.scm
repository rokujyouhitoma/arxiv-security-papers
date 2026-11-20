;;; =======================================================================
;;; Test Suite: Nanopass Languages L-StagePoly & L-Residual-ANF
;;; Conforms to DSN-33-03 §6.1, §6.2 & Issue #878
;;; =======================================================================

(display "\n=== [Test Suite: Nanopass Languages L-StagePoly & L-Residual-ANF (Issue #878)] ===\n")

;;; Helper to check if a production rule exists in a language nonterminal
(define (get-language-productions lang nt-name)
  (let ((nts (nanopass-lang-nonterminals lang)))
    (let loop ((rem nts))
      (cond
        ((null? rem) '())
        ((eq? (caar rem) nt-name)
         (caddr (car rem)))
        (else (loop (cdr rem)))))))

(define (has-production? lang nt-name head-sym)
  (let ((prods (get-language-productions lang nt-name)))
    (let loop ((ps prods))
      (cond
        ((null? ps) #f)
        ((and (pair? (car ps)) (eq? (caar ps) head-sym)) #t)
        ((eq? (car ps) head-sym) #t)
        (else (loop (cdr ps)))))))

;;; -----------------------------------------------------------------------
;;; Group 1: Language Registration & Lookup
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Language Registration & Lookup ---\n")

(let ((lang-poly (nanopass-lookup-language-opt 'L-StagePoly))
      (lang-anf  (nanopass-lookup-language-opt 'L-Residual-ANF)))
  (assert-equal "1.1 L-StagePoly is registered" #t (and (nanopass-language? lang-poly) #t))
  (assert-equal "1.2 L-Residual-ANF is registered" #t (and (nanopass-language? lang-anf) #t))
  (assert-equal "1.3 L-StagePoly name" 'L-StagePoly (nanopass-lang-name lang-poly))
  (assert-equal "1.4 L-Residual-ANF name" 'L-Residual-ANF (nanopass-lang-name lang-anf))
  (assert-equal "1.5 L-Residual-ANF extends L-StagePoly" 'L-StagePoly (nanopass-lang-parent lang-anf)))

;;; -----------------------------------------------------------------------
;;; Group 2: L-StagePoly Meta-Syntax Invariants (DSN-33-03 §6.1)
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: L-StagePoly Meta-Syntax Invariants ---\n")

(let ((lang-poly (nanopass-lookup-language 'L-StagePoly)))
  ;; Standard constructs
  (assert-equal "2.1 L-StagePoly has if" #t (has-production? lang-poly 'Expr 'if))
  (assert-equal "2.2 L-StagePoly has let" #t (has-production? lang-poly 'Expr 'let))
  (assert-equal "2.3 L-StagePoly has lambda" #t (has-production? lang-poly 'Expr 'lambda))
  (assert-equal "2.4 L-StagePoly has call" #t (has-production? lang-poly 'Expr 'call))

  ;; Meta-Stage Syntax (DSN-33-03 §6.1)
  (assert-equal "2.5 L-StagePoly has stage-now" #t (has-production? lang-poly 'Expr 'stage-now))
  (assert-equal "2.6 L-StagePoly has stage-later" #t (has-production? lang-poly 'Expr 'stage-later))
  (assert-equal "2.7 L-StagePoly has stage-lift" #t (has-production? lang-poly 'Expr 'stage-lift))
  (assert-equal "2.8 L-StagePoly has stage-quasiquote" #t (has-production? lang-poly 'Expr 'stage-quasiquote)))

;;; -----------------------------------------------------------------------
;;; Group 3: L-Residual-ANF Subtractive Elimination (DSN-33-03 §6.2)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: L-Residual-ANF Subtractive Elimination ---\n")

(let ((lang-anf (nanopass-lookup-language 'L-Residual-ANF)))
  ;; Complete elimination of meta-stage constructs!
  (assert-equal "3.1 stage-now eliminated from L-Residual-ANF" #f (has-production? lang-anf 'Expr 'stage-now))
  (assert-equal "3.2 stage-later eliminated from L-Residual-ANF" #f (has-production? lang-anf 'Expr 'stage-later))
  (assert-equal "3.3 stage-lift eliminated from L-Residual-ANF" #f (has-production? lang-anf 'Expr 'stage-lift))
  (assert-equal "3.4 stage-quasiquote eliminated from L-Residual-ANF" #f (has-production? lang-anf 'Expr 'stage-quasiquote))

  ;; Non-ANF general let and call eliminated!
  (assert-equal "3.5 General let eliminated from L-Residual-ANF" #f (has-production? lang-anf 'Expr 'let))
  (assert-equal "3.6 General call eliminated from L-Residual-ANF" #f (has-production? lang-anf 'Expr 'call)))

;;; -----------------------------------------------------------------------
;;; Group 4: L-Residual-ANF Additive ANF Syntax (DSN-33-03 §6.2)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: L-Residual-ANF Additive ANF Syntax ---\n")

(let ((lang-anf (nanopass-lookup-language 'L-Residual-ANF)))
  (assert-equal "4.1 L-Residual-ANF has let-anf" #t (has-production? lang-anf 'Expr 'let-anf))
  (assert-equal "4.2 L-Residual-ANF has let-call" #t (has-production? lang-anf 'Expr 'let-call))
  (assert-equal "4.3 L-Residual-ANF has atom-value" #t (has-production? lang-anf 'Expr 'atom-value))
  (assert-equal "4.4 L-Residual-ANF retains if" #t (has-production? lang-anf 'Expr 'if)))

(display "\n[RESULT] All Nanopass L-StagePoly & L-Residual-ANF tests PASSED!\n")
