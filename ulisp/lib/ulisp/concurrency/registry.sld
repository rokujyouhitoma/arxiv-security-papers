;;; =======================================================================
;;; R7RS Library: (ulisp concurrency registry)
;;; Conforms to DSN-37 Section 8.4.5 & Section 14.8 Task 6.4 (Issue #669)
;;; =======================================================================

(define-library (ulisp concurrency registry)
  (export
    <process-registry>
    process-registry?
    make-process-registry
    <registry-entry>
    registry-entry?
    registry-entry-name
    registry-entry-target
    registry-entry-epoch
    current-synapse-registry
    set-default-synapse-registry!
    synapse-register!
    synapse-unregister!
    synapse-whereis
    synapse-rebind!
    synapse-send-named!
    synapse-registered-names
    synapse-registry-count
    synapse-registry-clear!
    synapse-enable-supervisor-rebind!
    *registry-max-entries*)

  (import
    (scheme base))

  (include "ulisp/runtime/concurrency/registry.scm"))

