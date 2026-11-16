;;; =======================================================================
;;; ULisp Standard Library: Ephemerons (SRFI 124, R7RS-large Red Edition)
;;; Conforms to DSN-33 Architecture Specification, Issue #856
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md §2.1
;;; Reference: Barry Hayes (1997) "Ephemerons: a New Finalization Mechanism"
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1. Type Definition: <ephemeron> Record (5-slot fixed vector layout)
;; ---------------------------------------------------------------------
;; Representation: #(%%record-type-<ephemeron> key datum broken? next)
;;   slot 0: Record type tag symbol '%%record-type-<ephemeron>
;;   slot 1: key (any Scheme object)
;;   slot 2: datum (any Scheme object)
;;   slot 3: broken? (#f or #t)
;;   slot 4: next (intrusive linked list pointer for GC pending list)

(define-record-type <ephemeron>
  (%make-raw-ephemeron key datum broken? next)
  ephemeron?
  (key %ephemeron-key %ephemeron-key-set!)
  (datum %ephemeron-datum %ephemeron-datum-set!)
  (broken? %ephemeron-broken? %ephemeron-broken-set!)
  (next %ephemeron-next %ephemeron-next-set!))

;; ---------------------------------------------------------------------
;; §2. Standard Constructor & Accessors (SRFI 124)
;; ---------------------------------------------------------------------

;; (make-ephemeron key datum) -> ephemeron
;; Constructs a new ephemeron holding key and datum.
(define (make-ephemeron key datum)
  (%make-raw-ephemeron key datum #f #f))

;; (ephemeron-broken? ephemeron) -> boolean
;; Returns #t if ephemeron has been broken by the garbage collector,
;; or if key has been determined to be unreachable. Otherwise returns #f.
(define (ephemeron-broken? e)
  (if (not (ephemeron? e))
      (error "ephemeron-broken?: argument is not an ephemeron (CWE-843)" e)
      (%ephemeron-broken? e)))

;; (ephemeron-key ephemeron) -> key / #f
;; Returns the key of ephemeron. If the ephemeron is broken, returns #f.
(define (ephemeron-key e)
  (if (not (ephemeron? e))
      (error "ephemeron-key: argument is not an ephemeron (CWE-843)" e)
      (if (%ephemeron-broken? e)
          #f
          (%ephemeron-key e))))

;; (ephemeron-datum ephemeron) -> datum / #f
;; Returns the datum of ephemeron. If the ephemeron is broken, returns #f.
(define (ephemeron-datum e)
  (if (not (ephemeron? e))
      (error "ephemeron-datum: argument is not an ephemeron (CWE-843)" e)
      (if (%ephemeron-broken? e)
          #f
          (%ephemeron-datum e))))

;; ---------------------------------------------------------------------
;; §3. Optimization & Reachability Barrier
;; ---------------------------------------------------------------------

;; (reference-barrier key) -> unspecified
;; Prevents the compiler and processor from dead-code eliminating or
;; reclaiming key prior to this point in execution.
(define (reference-barrier key)
  (%memory-fence)
  key)
