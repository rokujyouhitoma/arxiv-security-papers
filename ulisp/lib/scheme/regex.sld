;;; =======================================================================
;;; R7RS Standard Library: (scheme regex)
;;; Conforms to R7RS-large Tangerine Edition & SRFI 115
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme regex)
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
