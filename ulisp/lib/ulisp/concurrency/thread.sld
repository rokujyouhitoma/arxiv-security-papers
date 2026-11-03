;;; =======================================================================
;;; R7RS Library: (ulisp concurrency thread)
;;; Conforms to DSN-37 Section 7.4 & Phase 7 Task 7.1 (Issue #675)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency thread)
  (export
    native-thread-supported?
    online-cpu-count
    get-current-core-id
    get-current-node-id
    get-current-cpu-node
    set-thread-affinity!
    spawn-native-thread
    exit-native-thread!
    %sys-spawn-thread
    %sys-set-affinity!
    %sys-online-cpu-count
    %sys-getcpu-core
    %sys-getcpu-node
    %sys-thread-exit!)

  (import
    (scheme base))

  (include "ulisp/runtime/concurrency/thread.scm"))

