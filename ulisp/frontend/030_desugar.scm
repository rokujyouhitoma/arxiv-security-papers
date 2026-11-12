;;; =======================================================================
;;; ULisp Compiler Pass 030: Core Syntax Desugaring & Normalization Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Framework Standard
;;; Implements derived expression lowering per [R7RS §4.2] and [R7RS §7.3].
;;; Migrated to Declarative Pass Fusion (fuse-rules) per Issue #763 (DSN-33-01 T4.2).
;;; Automatically combines all 31 Picopasses/Attopasses from Passes 026-029 into
;;; a single O(1) Head-Tag dispatch traversal with local re-dispatch.
;;; =======================================================================

(define-pass desugar-all : L_src (ir) -> L_core ()
  (Program : Program (ir) -> Program ()
    ((%program (,d ...) ,e)
     (let ((map-def (lambda (def)
                      (if (and (pair? def) (eq? (car def) 'define))
                          (list 'define (cadr def) (Expr (caddr def)))
                          (Expr def)))))
       (list '%program (map map-def d) (Expr e))))
    (,e (Expr e)))
  (Expr : Expr (ir) -> Expr ()
    (fuse-rules
      ;; --- Pass 026: Composite Literals & Constructors ---
      rule-desugar-list
      rule-desugar-vector
      rule-desugar-bytevector
      rule-desugar-string-ops
      rule-desugar-vector-ops
      rule-desugar-bytevector-ops
      rule-desugar-math-variadic
      rule-desugar-format
      rule-desugar-cxr

      ;; --- Pass 027: Conditionals & Comparisons ---
      rule-desugar-cond-expand
      rule-desugar-cond
      rule-desugar-case
      rule-desugar-and
      rule-desugar-or
      rule-desugar-chain-cmp

      ;; --- Pass 028: Bindings & Internal Definitions ---
      rule-desugar-case-lambda
      rule-desugar-let*
      rule-desugar-letrec*
      rule-desugar-named-let
      rule-desugar-multi-body
      rule-desugar-do
      rule-desugar-internal-define

      ;; --- Pass 029: Dynamic Environment & Values ---
      rule-desugar-let-values
      rule-desugar-define-values
      rule-desugar-guard
      rule-desugar-parameterize
      rule-desugar-delay
      rule-desugar-parameter-ops
      rule-desugar-values
      rule-desugar-error-assume
      atto-no-unexpanded-let-syntax)))
