;;; =======================================================================
;;; ULisp R7RS-large Library: (scheme ilist) — SRFI 116 Immutable Lists
;;; Specification: R7RS-large Red Edition / SRFI 116
;;; Conforms to DSN-33 Architecture Specification & Issue #710
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme ilist)
  (import (scheme base))
  (export
    ;; Constructors
    ipair ilist xipair ipair* make-ilist ilist-tabulate ilist-copy iiota
    ;; Predicates
    ipair? proper-ilist? ilist? dotted-ilist? not-ipair? null-ilist? ilist=
    ;; Selectors
    icar icdr
    icaar icadr icdar icddr
    icaaar icaadr icadar icaddr icdaar icdadr icddar icdddr
    icaaaar icaaadr icaadar icaaddr icadaar icadadr icaddar icadddr
    icdaaar icdaadr icdadar icdaddr icddaar icddadr icdddar icddddr
    ilist-ref
    ifirst isecond ithird ifourth ififth isixth iseventh ieighth ininth itenth
    icar+icdr
    itake idrop ilist-tail itake-right idrop-right isplit-at
    ilast last-ipair
    ;; Miscellaneous
    ilength iappend iconcatenate ireverse iappend-reverse
    izip iunzip1 iunzip2 iunzip3 iunzip4 iunzip5 icount
    ;; Fold, unfold & map
    ifold iunfold ipair-fold ireduce
    ifold-right iunfold-right ipair-fold-right ireduce-right
    iappend-map ipair-for-each ifilter-map imap-in-order
    imap ifor-each
    ;; Filtering & partitioning
    ifilter ipartition iremove
    ;; Searching
    ifind ifind-tail itake-while idrop-while ispan ibreak
    iany ievery ilist-index imember imemq imemv
    ;; Deletion
    idelete idelete-duplicates
    ;; Association lists
    iassoc iassq iassv ialist-cons ialist-delete
    ;; Replacement & conversion
    replace-icar replace-icdr
    pair->ipair ipair->pair list->ilist ilist->list
    tree->itree itree->tree gtree->itree gtree->tree
    iapply
    ;; Comparators
    ipair-comparator ilist-comparator
    make-ilist-comparator make-improper-ilist-comparator
    make-ipair-comparator make-icar-comparator make-icdr-comparator)
  (begin))

