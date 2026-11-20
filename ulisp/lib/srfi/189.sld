;;; =======================================================================
;;; SRFI Standard Library: (srfi 189)
;;; Conforms to SRFI 189: Maybe and Either: optional container types
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 189)
  (export
    ;; Constructors & Predicates
    maybe?
    either?
    just
    nothing
    left
    right
    nothing?
    just?
    maybe=
    left?
    right?
    either=
    either-swap

    ;; Accessors
    maybe-ref
    maybe-ref/default
    either-ref
    either-ref/default

    ;; Join, Bind & Compose
    maybe-join
    maybe-bind
    maybe-compose
    either-join
    either-bind
    either-compose

    ;; Sequence Operations
    maybe-length
    maybe-filter
    maybe-remove
    either-length
    either-filter
    either-remove
    maybe-sequence
    either-sequence

    ;; Protocol Conversion
    maybe->either
    either->maybe
    list->just
    list->right
    maybe->list
    either->list
    maybe->truth
    either->truth
    truth->maybe
    maybe->values
    maybe->two-values
    values->maybe
    either->values
    values->either
    two-values->maybe
    maybe-for-each
    either-for-each
    maybe->generation
    generation->maybe
    list->left
    list->maybe
    list->either
    maybe->list-truth
    either->list-truth
    list-truth->maybe
    list-truth->either
    truth->either
    either->generation
    generation->either
    exception->either

    ;; Map, Fold & Unfold
    maybe-map
    maybe-fold
    maybe-unfold
    either-map
    either-fold
    either-unfold

    ;; Trivalent Logic
    tri-not
    tri=?
    tri-and
    tri-or
    tri-merge

    ;; Syntax Forms
    maybe-if
    maybe-and
    maybe-or
    maybe-let*
    maybe-let*-values
    either-and
    either-or
    either-let*
    either-let*-values
    either-guard)
  (include "../maybe.scm"))
