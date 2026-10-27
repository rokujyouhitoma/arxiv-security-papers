;;; =======================================================================
;;; ULisp Compiler Module Header & Interface Specification
;;; Conforms to DSN-33 Architecture Specification & Issue #608
;;; =======================================================================

;; I/O Compatibility Macros (expanding to stdlib runtime ports)
(define-syntax newline
  (syntax-rules ()
    ((newline) (port-newline *stdout-port*))
    ((newline p) (port-newline p))))

(define-syntax display
  (syntax-rules ()
    ((display val) (port-display val *stdout-port*))
    ((display val p) (port-display val p))))

(define-syntax write
  (syntax-rules ()
    ((write val) (port-write val *stdout-port*))
    ((write val p) (port-write val p))))

(define-syntax read
  (syntax-rules ()
    ((read) (port-read *stdin-port*))
    ((read p) (port-read p))))

;; String-append macro (expanding to stdlib string-append2)
(define-syntax string-append
  (syntax-rules ()
    ((string-append) "")
    ((string-append s) s)
    ((string-append s1 s2) (string-append2 s1 s2))
    ((string-append s1 s2 s3) (string-append2 s1 (string-append2 s2 s3)))
    ((string-append s1 s2 s3 s4) (string-append2 s1 (string-append2 s2 (string-append2 s3 s4))))
    ((string-append s1 s2 s3 s4 s5) (string-append2 s1 (string-append2 s2 (string-append2 s3 (string-append2 s4 s5)))))
    ((string-append s1 s2 s3 s4 s5 s6 ...) (string-append2 s1 (string-append s2 s3 s4 s5 s6 ...)))))

;; Declare inter-module extern identifiers so the compiler's reader interns them into *symbol-registry*
(define-syntax %declare-extern-identifiers
  (syntax-rules ()
    ((%declare-extern-identifiers id ...)
     (begin))))

(%declare-extern-identifiers
  string-append2
  vector-append2
  bytevector-append2
  nanopass-try-clause
  nanopass-catamorphism-step
  set-current-pass!
  nanopass-verifier-enabled?
  nanopass-verify-ast
  with-call-frame
  nanopass-display-ast-diff
  nanopass-trace-enabled?
  nanopass-register-language!
  nanopass-parse-language-spec
  nanopass-parse
  nanopass-unparse
  nanopass-ast-valid?
  nanopass-parse-nt
  current-jiffy
  jiffies-per-second
  sys-getenv
  sys-bench-passes?
  sys-clock-gettime-monotonic
  gc-current-heap-bytes
  occurs-in?
  unboxed-fn?
  *top-level-vars*
  *top-level-fns*
  slurp-single-file
  desugar-libraries-and-imports
  expand-dsl-forms
  expand-macros-in-forms
  rewrite-top-level
  desugar-all
  cp0-optimize
  lvn-all
  anf-all
  annotate-all
  rtyper-all
  contify-all
  closure-convert
  alias-escape-all
  generate-lir
  lir-fuse-branches
  lir-peephole-optimize)


