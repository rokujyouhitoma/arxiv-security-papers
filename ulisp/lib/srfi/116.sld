;;; =======================================================================
;;; ULisp SRFI 116 Library: (srfi 116) — Immutable Pairs and Lists
;;; Specification: SRFI 116 / R7RS-large (scheme ilist)
;;; Conforms to DSN-33 Architecture Specification & Issue #710
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 116)
  (import (scheme ilist))
  (export
    ipair ilist xipair ipair* make-ilist ilist-tabulate ilist-copy iiota
    ipair? proper-ilist? ilist? dotted-ilist? not-ipair? null-ilist? ilist=
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
    ilength iappend iconcatenate ireverse iappend-reverse
    izip iunzip1 iunzip2 iunzip3 iunzip4 iunzip5 icount
    ifold iunfold ipair-fold ireduce
    ifold-right iunfold-right ipair-fold-right ireduce-right
    iappend-map ipair-for-each ifilter-map imap-in-order
    imap ifor-each
    ifilter ipartition iremove
    ifind ifind-tail itake-while idrop-while ispan ibreak
    iany ievery ilist-index imember imemq imemv
    idelete idelete-duplicates
    iassoc iassq iassv ialist-cons ialist-delete
    replace-icar replace-icdr
    pair->ipair ipair->pair list->ilist ilist->list
    tree->itree itree->tree gtree->itree gtree->tree
    iapply
    ipair-comparator ilist-comparator
    make-ilist-comparator make-improper-ilist-comparator
    make-ipair-comparator make-icar-comparator make-icdr-comparator)
  (begin))

