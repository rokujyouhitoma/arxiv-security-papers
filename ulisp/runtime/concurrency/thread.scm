;;; =======================================================================
;;; uLisp Concurrency Runtime: Native Threading Subsystem (thread.scm)
;;; Conforms to DSN-37 Section 7.4 & Phase 7 Task 7.1 (Issue #675)
;;;
;;; Provides high-level Scheme APIs over Linux sys_clone and sched_setaffinity:
;;;   1. (native-thread-supported?) -> #t
;;;   2. (online-cpu-count) -> positive-fixnum
;;;   3. (set-thread-affinity! core-id) -> #t / #f
;;;   4. (spawn-native-thread proc arg) -> tid
;;;   5. (exit-native-thread! code) -> does not return
;;; =======================================================================

;; Low-level ASM stubs overridden at link-time by thread.o
(define (%sys-spawn-thread fn-ptr arg)
  (if (and fn-ptr arg) -1 -1))

(define (%sys-set-affinity! core-id)
  (if (integer? core-id) #f #f))

(define (%sys-online-cpu-count)
  1)

(define (%sys-getcpu-core)
  0)

(define (%sys-getcpu-node)
  0)

(define (%sys-thread-exit! code)
  (if (integer? code) 0 0))

;; -----------------------------------------------------------------------
;; High-Level Threading API
;; -----------------------------------------------------------------------

(define (native-thread-supported?)
  #t)

(define (online-cpu-count)
  (let ((cnt (%sys-online-cpu-count)))
    (if (and (integer? cnt) (> cnt 0))
        cnt
        1)))

(define (get-current-core-id)
  (let ((core (%sys-getcpu-core)))
    (if (and (integer? core) (>= core 0))
        core
        0)))

(define (get-current-node-id)
  (let ((node (%sys-getcpu-node)))
    (if (and (integer? node) (>= node 0))
        node
        0)))

(define (get-current-cpu-node)
  (cons (get-current-core-id) (get-current-node-id)))

(define (set-thread-affinity! core-id)
  (if (not (integer? core-id))
      (error "set-thread-affinity!: core-id must be an integer (CWE-843)" core-id)
      (if (or (< core-id 0) (> core-id 1023))
          (error "set-thread-affinity!: core-id out of range [0..1023] (CWE-20)" core-id)
          (%sys-set-affinity! core-id))))

(define (spawn-native-thread proc arg)
  (if (not (procedure? proc))
      (error "spawn-native-thread: proc must be a procedure (CWE-843)" proc)
      (let ((tid (%sys-spawn-thread proc arg)))
        (if (and (integer? tid) (> tid 0))
            tid
            (error "spawn-native-thread: failed to clone thread" tid)))))

(define (exit-native-thread! code)
  (let ((c (if (integer? code) code 0)))
    (%sys-thread-exit! c)))
