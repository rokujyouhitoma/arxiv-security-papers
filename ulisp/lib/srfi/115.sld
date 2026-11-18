;;; =======================================================================
;;; SRFI Standard Library: (srfi 115)
;;; Conforms to SRFI 115: Scheme Regular Expressions
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 115)
  (export
    regexp
    rx
    regexp?
    valid-sre?
    regexp-matches
    regexp-matches?
    regexp-search
    regexp-match?
    regexp-match-count
    regexp-match-submatch
    regexp-match-submatch-start
    regexp-match-submatch-end
    regexp-fold
    regexp-extract
    regexp-split
    regexp-partition
    regexp-replace
    regexp-replace-all)
  (include "../regex.scm"))
