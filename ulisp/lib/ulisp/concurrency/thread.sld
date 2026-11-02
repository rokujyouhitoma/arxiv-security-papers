;;; =======================================================================
;;; R7RS Library: (ulisp concurrency thread)
;;; Conforms to DSN-37 Section 7.4 & Phase 7 Task 7.1 (Issue #675)
;;; =======================================================================

(define-library (ulisp concurrency thread)
  (export
    native-thread-supported?
    online-cpu-count
    set-thread-affinity!
    spawn-native-thread
    exit-native-thread!
    %sys-spawn-thread
    %sys-set-affinity!
    %sys-online-cpu-count
    %sys-thread-exit!)

  (import
    (scheme base))

  (include "../../../runtime/concurrency/thread.scm"))

