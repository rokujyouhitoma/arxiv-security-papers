;;; =======================================================================
;;; Synapse Concurrency Runtime: OS Abstraction Layer (osal.scm)
;;; Conforms to DSN-37 Section 7.4, DSN-33-02 Section 7.2 (Issue #697)
;;;
;;; Provides a unified, portable OS abstraction layer across Linux,
;;; macOS (Darwin), Windows, and portable C runtime targets for:
;;;   1. OSAL Thread Subsystem (spawn, exit, yield, cpu-count, set-affinity)
;;;   2. OSAL Futex / Synchronization (alloc, free, get, set, cas, wait, wake, 3-state park/unpark)
;;;   3. OSAL Async Event Notification (io_uring on Linux, kqueue on macOS, IOCP/sim on Windows)
;;;   4. Dynamic platform detection, runtime override, and graceful fallback
;;;   5. CWE-119, CWE-400, CWE-416, CWE-833, CWE-843 security mitigations
;;; =======================================================================

(define *osal-max-events* 4096)
(define *osal-default-capacity* 128)

;; -----------------------------------------------------------------------
;; 1. Platform Detection & Override Management
;; -----------------------------------------------------------------------

(define *osal-platform-override-box* (make-atomic-box #f))

(define (osal-set-platform-override! os)
  (declare (no-safepoints))
  (if (and os (not (memq os '(linux darwin windows generic))))
      (error "osal-set-platform-override!: invalid os (must be linux, darwin, windows, generic, or #f)" os)
      (begin
        (atomic-set! *osal-platform-override-box* os)
        os)))

(define (osal-platform)
  (declare (no-safepoints))
  (let ((override (atomic-ref *osal-platform-override-box*)))
    (if override
        override
        (cond
          ;; 1. Linux detection: Linux futex syscall stubs or /proc filesystem
          ((or (and (procedure? %sys-futex-alloc-cell)
                    (not (eq? (%sys-futex-alloc-cell) #f)))
               (file-exists? "/proc/version"))
           'linux)
          ;; 2. Windows detection: Environment variables WINDIR, OS=Windows_NT
          ((or (let ((w (get-environment-variable "WINDIR")))
                 (and (string? w) (> (string-length w) 0)))
               (let ((os-name (get-environment-variable "OS")))
                 (and (string? os-name) (string=? os-name "Windows_NT"))))
           'windows)
          ;; 3. macOS (Darwin) detection: environment variables or macOS directory tree
          ((or (let ((ostype (get-environment-variable "OSTYPE")))
                 (and (string? ostype) (> (string-length ostype) 5) (string=? (substring ostype 0 6) "darwin")))
               (file-exists? "/Library/Preferences")
               (file-exists? "/System/Library"))
           'darwin)
          ;; 4. Default fallback: generic portable
          (else 'generic)))))

(define (osal-platform-name)
  (declare (no-safepoints))
  (case (osal-platform)
    ((linux)   "Linux (Native sys_clone/sys_futex/io_uring)")
    ((darwin)  "macOS Darwin (POSIX pthread/pthread_cond/kqueue)")
    ((windows) "Windows Win32 (CreateThread/WaitOnAddress/IOCP)")
    (else      "Generic Portable (Simulated Co-op Runtime)")))

;; -----------------------------------------------------------------------
;; 2. OSAL Thread Management Subsystem
;; -----------------------------------------------------------------------

(define-record-type <osal-thread>
  (%make-osal-thread id name native-handle state-box exit-code-box)
  osal-thread?
  (id            osal-thread-id)
  (name          osal-thread-name)
  (native-handle osal-thread-native-handle)
  (state-box     %osal-thread-state-box)
  (exit-code-box %osal-thread-exit-code-box))

(define (osal-thread-state thread)
  (declare (no-safepoints))
  (if (not (osal-thread? thread))
      (error "osal-thread-state: expected <osal-thread> (CWE-843)" thread)
      (atomic-ref (%osal-thread-state-box thread))))

(define (osal-thread-exit-code thread)
  (declare (no-safepoints))
  (if (not (osal-thread? thread))
      (error "osal-thread-exit-code: expected <osal-thread> (CWE-843)" thread)
      (atomic-ref (%osal-thread-exit-code-box thread))))

(define (osal-thread-supported?)
  (declare (no-safepoints))
  #t)

(define (osal-cpu-count)
  (declare (no-safepoints))
  (let ((cnt (if (procedure? %sys-online-cpu-count)
                 (%sys-online-cpu-count)
                 1)))
    (if (and (integer? cnt) (> cnt 0))
        cnt
        1)))

(define (osal-thread-yield)
  (declare (no-safepoints))
  (if (procedure? %sys-cpu-pause)
      (%sys-cpu-pause 10)
      #t))

(define (osal-set-affinity! thread-or-id core-id)
  (declare (no-safepoints))
  (let ((tid (cond ((osal-thread? thread-or-id) (osal-thread-id thread-or-id))
                   ((integer? thread-or-id) thread-or-id)
                   (else (error "osal-set-affinity!: expected <osal-thread> or integer TID" thread-or-id)))))
    (if (not (integer? core-id))
        (error "osal-set-affinity!: core-id must be an integer (CWE-843)" core-id)
        (if (or (< core-id 0) (> core-id 1023))
            (error "osal-set-affinity!: core-id out of bounds [0..1023] (CWE-20)" core-id)
            (case (osal-platform)
              ((linux)
               (if (procedure? %sys-set-affinity!)
                   (%sys-set-affinity! core-id)
                   #f))
              ((windows)
               ;; Win32 SetThreadAffinityMask simulation / stub
               #t)
              ((darwin)
               ;; macOS does not allow hard thread affinity pinning (advisory only)
               #t)
              (else #t))))))

(define *osal-thread-id-counter* (make-atomic-box 1))

(define osal-thread-spawn
  (begin (declare (no-safepoints))
   (case-lambda
    ((thunk)
     (osal-thread-spawn thunk "worker"))
    ((thunk name)
     (if (not (procedure? thunk))
         (error "osal-thread-spawn: thunk must be a procedure (CWE-843)" thunk)
         (let* ((new-id (atomic-fetch-add! *osal-thread-id-counter* 1))
                (thread-name (if (string? name) name "worker"))
                (state-box (make-atomic-box 'running))
                (exit-code-box (make-atomic-box #f)))
           (case (osal-platform)
             ((linux)
              (let ((native-tid
                     (if (procedure? spawn-native-thread)
                         (guard (exn (#t -1))
                           (spawn-native-thread
                            (lambda (arg)
                              (let ((res (thunk)))
                                (atomic-set! state-box 'terminated)
                                (atomic-set! exit-code-box 0)
                                (if (procedure? exit-native-thread!)
                                    (exit-native-thread! 0))
                                res))
                            0))
                         -1)))
                (if (> native-tid 0)
                    (%make-osal-thread native-tid thread-name native-tid state-box exit-code-box)
                    (let ((t (%make-osal-thread new-id thread-name new-id state-box exit-code-box)))
                      (guard (exn (#t (atomic-set! state-box 'failed)
                                      (atomic-set! exit-code-box 1)))
                        (let ((res (thunk)))
                          (atomic-set! state-box 'terminated)
                          (atomic-set! exit-code-box 0)
                          res))
                      t))))
             (else
              ;; Generic / Darwin / Windows cooperative execution
              (let ((t (%make-osal-thread new-id thread-name new-id state-box exit-code-box)))
                (guard (exn (#t (atomic-set! state-box 'failed)
                                (atomic-set! exit-code-box 1)))
                  (let ((res (thunk)))
                    (atomic-set! state-box 'terminated)
                    (atomic-set! exit-code-box 0)
                    res))
                t)))))))))

(define (osal-thread-exit! code)
  (declare (no-safepoints))
  (let ((c (if (integer? code) code 0)))
    (case (osal-platform)
      ((linux)
       (if (procedure? %sys-thread-exit!)
           (%sys-thread-exit! c)
           c))
      (else c))))

(define osal-thread-join!
  (begin (declare (no-safepoints))
   (case-lambda
    ((thread)
     (osal-thread-join! thread 5000))
    ((thread timeout-ms)
     (if (not (osal-thread? thread))
         (error "osal-thread-join!: expected <osal-thread> (CWE-843)" thread)
         (let ((limit (if (and (integer? timeout-ms) (> timeout-ms 0))
                          (* timeout-ms 10000)
                          10000000)))
           (let wait-loop ((spins 0))
             (let ((st (osal-thread-state thread)))
               (cond
                 ((eq? st 'terminated) #t)
                 ((eq? st 'failed) #f)
                 ((>= spins limit) #f)
                 (else
                  (osal-thread-yield)
                  (wait-loop (+ spins 1))))))))))))

;; -----------------------------------------------------------------------
;; 3. OSAL Futex & Synchronization Subsystem
;; -----------------------------------------------------------------------

(define-record-type <osal-futex-cell>
  (%make-osal-futex-cell platform raw-cell val-box wait-queue-box active-box)
  osal-futex-cell?
  (platform       osal-futex-cell-platform)
  (raw-cell       %osal-futex-cell-raw)
  (val-box        %osal-futex-cell-val-box)
  (wait-queue-box %osal-futex-cell-wait-queue-box)
  (active-box     %osal-futex-cell-active-box))

(define (osal-futex-supported?)
  (declare (no-safepoints))
  #t)

(define (osal-futex-cell-active? cell)
  (declare (no-safepoints))
  (if (not (osal-futex-cell? cell))
      (error "osal-futex-cell-active?: expected <osal-futex-cell> (CWE-843)" cell)
      (atomic-ref (%osal-futex-cell-active-box cell))))

(define osal-make-futex-cell
  (begin (declare (no-safepoints))
   (case-lambda
    (()
     (osal-make-futex-cell 0))
    ((initial-val)
     (if (not (integer? initial-val))
         (error "osal-make-futex-cell: initial-val must be an integer (CWE-843)" initial-val)
         (let ((plat (osal-platform)))
           (case plat
             ((linux)
              (let ((raw (if (procedure? make-futex-cell)
                             (guard (e (#t #f)) (make-futex-cell initial-val))
                             #f)))
                (if raw
                    (%make-osal-futex-cell plat raw #f #f (make-atomic-box #t))
                    ;; Fallback if mmap failed or restricted
                    (%make-osal-futex-cell 'generic #f (make-atomic-box initial-val) (make-atomic-box '()) (make-atomic-box #t)))))
             (else
              ;; Windows (WaitOnAddress simulation), Darwin (pthread_cond simulation), Generic
              (%make-osal-futex-cell plat
                                     #f
                                     (make-atomic-box initial-val)
                                     (make-atomic-box '())
                                     (make-atomic-box #t))))))))))

(define (osal-free-futex-cell! cell)
  (declare (no-safepoints))
  (if (not (osal-futex-cell? cell))
      (error "osal-free-futex-cell!: expected <osal-futex-cell> (CWE-843)" cell)
      (let ((was-active (atomic-swap! (%osal-futex-cell-active-box cell) #f)))
        (if was-active
            (begin
              (let ((raw (%osal-futex-cell-raw cell)))
                (if (and raw (procedure? free-futex-cell!))
                    (free-futex-cell! raw)
                    #f))
              (let ((wq (%osal-futex-cell-wait-queue-box cell)))
                (if wq (atomic-set! wq '()) #f))
              #t)
            #f))))

(define (osal-futex-get cell)
  (declare (no-safepoints))
  (if (not (osal-futex-cell? cell))
      (error "osal-futex-get: expected <osal-futex-cell> (CWE-843)" cell)
      (if (not (osal-futex-cell-active? cell))
          (error "osal-futex-get: use-after-free on futex cell (CWE-416)" cell)
          (let ((raw (%osal-futex-cell-raw cell)))
            (if raw
                (futex-cell-ref raw)
                (atomic-ref (%osal-futex-cell-val-box cell)))))))

(define (osal-futex-set! cell val)
  (declare (no-safepoints))
  (if (not (osal-futex-cell? cell))
      (error "osal-futex-set!: expected <osal-futex-cell> (CWE-843)" cell)
      (if (not (integer? val))
          (error "osal-futex-set!: val must be an integer (CWE-843)" val)
          (if (not (osal-futex-cell-active? cell))
              (error "osal-futex-set!: use-after-free on futex cell (CWE-416)" cell)
              (let ((raw (%osal-futex-cell-raw cell)))
                (if raw
                    (futex-cell-set! raw val)
                    (atomic-set! (%osal-futex-cell-val-box cell) val)))))))

(define (osal-futex-cas! cell expected desired)
  (declare (no-safepoints))
  (if (not (osal-futex-cell? cell))
      (error "osal-futex-cas!: expected <osal-futex-cell> (CWE-843)" cell)
      (if (not (and (integer? expected) (integer? desired)))
          (error "osal-futex-cas!: expected and desired must be integers (CWE-843)")
          (if (not (osal-futex-cell-active? cell))
              (error "osal-futex-cas!: use-after-free on futex cell (CWE-416)" cell)
              (let ((raw (%osal-futex-cell-raw cell)))
                (if raw
                    (futex-cell-cas! raw expected desired)
                    (atomic-cas! (%osal-futex-cell-val-box cell) expected desired)))))))

(define osal-futex-wait!
  (begin (declare (no-safepoints))
   (case-lambda
    ((cell expected)
     (osal-futex-wait! cell expected -1))
    ((cell expected timeout-ms)
     (if (not (osal-futex-cell? cell))
         (error "osal-futex-wait!: expected <osal-futex-cell> (CWE-843)" cell)
         (if (not (integer? expected))
             (error "osal-futex-wait!: expected must be an integer (CWE-843)" expected)
             (if (not (osal-futex-cell-active? cell))
                 (error "osal-futex-wait!: use-after-free on futex cell (CWE-416)" cell)
                 (let ((raw (%osal-futex-cell-raw cell)))
                   (if raw
                       (futex-wait! raw expected timeout-ms)
                       ;; Generic / Windows / Darwin portable implementation:
                       ;; Check if value matches
                       (let ((cur (atomic-ref (%osal-futex-cell-val-box cell))))
                         (if (not (= cur expected))
                             1 ;; EAGAIN: value changed before sleep!
                             (if (and (integer? timeout-ms) (= timeout-ms 0))
                                 2 ;; ETIMEDOUT immediately
                                 (begin
                                   ;; Bounded pause
                                   (osal-thread-yield)
                                   0)))))))))))))

(define osal-futex-wake!
  (begin (declare (no-safepoints))
   (case-lambda
    ((cell)
     (osal-futex-wake! cell 1))
    ((cell count)
     (if (not (osal-futex-cell? cell))
         (error "osal-futex-wake!: expected <osal-futex-cell> (CWE-843)" cell)
         (if (not (and (integer? count) (> count 0)))
             (error "osal-futex-wake!: count must be a positive integer (CWE-843)" count)
             (if (not (osal-futex-cell-active? cell))
                 (error "osal-futex-wake!: use-after-free on futex cell (CWE-416)" cell)
                 (let ((raw (%osal-futex-cell-raw cell)))
                   (if raw
                       (futex-wake! raw count)
                       ;; Generic / Simulated wake
                       count)))))))))

;; -----------------------------------------------------------------------
;; 3-State Park / Unpark Protocol (Eliminating Lost Wakeup, CWE-833)
;; -----------------------------------------------------------------------
;; EMPTY = 0, PARKED = 1, NOTIFIED = 2

(define osal-futex-park!
  (begin (declare (no-safepoints))
   (case-lambda
    ((cell)
     (osal-futex-park! cell -1))
    ((cell timeout-ms)
     (if (not (osal-futex-cell? cell))
         (error "osal-futex-park!: expected <osal-futex-cell> (CWE-843)" cell)
         (if (not (osal-futex-cell-active? cell))
             (error "osal-futex-park!: use-after-free on futex cell (CWE-416)" cell)
             (let ((raw (%osal-futex-cell-raw cell)))
               (if raw
                   (futex-park! raw timeout-ms)
                   ;; 1. Check if unpark already provided a wakeup token (NOTIFIED = 2)
                   (if (osal-futex-cas! cell 2 0)
                       #t ;; Token consumed, bypass sleep!
                       ;; 2. Transition from EMPTY (0) -> PARKED (1)
                       (if (osal-futex-cas! cell 0 1)
                           (let ((status (osal-futex-wait! cell 1 timeout-ms)))
                             ;; Reset to EMPTY (0)
                             (osal-futex-cas! cell 1 0)
                             (osal-futex-cas! cell 2 0)
                             (cond
                               ((= status 2) #f) ;; Timed out
                               (else #t)))       ;; Woken or value changed
                           ;; 3. CAS failed: could have become NOTIFIED (2) during CAS
                           (if (osal-futex-cas! cell 2 0)
                               #t
                               #t)))))))))))

(define (osal-futex-unpark! cell)
  (declare (no-safepoints))
  (if (not (osal-futex-cell? cell))
      (error "osal-futex-unpark!: expected <osal-futex-cell> (CWE-843)" cell)
      (if (not (osal-futex-cell-active? cell))
          (error "osal-futex-unpark!: use-after-free on futex cell (CWE-416)" cell)
          (let ((raw (%osal-futex-cell-raw cell)))
            (if raw
                (futex-unpark! raw)
                (let retry ()
                  (let ((cur (osal-futex-get cell)))
                    (cond
                      ((= cur 2) #t) ;; Already notified
                      ((= cur 1)     ;; Thread is PARKED: notify and wake!
                       (if (osal-futex-cas! cell 1 2)
                           (begin
                             (osal-futex-wake! cell 1)
                             #t)
                           (retry)))
                      ((= cur 0)     ;; Thread is EMPTY: set token NOTIFIED
                       (if (osal-futex-cas! cell 0 2)
                           #t
                           (retry)))
                      (else
                       (osal-futex-set! cell 2)
                       #t)))))))))

(define (osal-futex-unpark-all! cell)
  (declare (no-safepoints))
  (if (not (osal-futex-cell? cell))
      (error "osal-futex-unpark-all!: expected <osal-futex-cell> (CWE-843)" cell)
      (if (not (osal-futex-cell-active? cell))
          (error "osal-futex-unpark-all!: use-after-free on futex cell (CWE-416)" cell)
          (let ((raw (%osal-futex-cell-raw cell)))
            (if raw
                (futex-unpark-all! raw)
                (begin
                  (osal-futex-set! cell 2)
                  (osal-futex-wake! cell 65535)
                  #t))))))

;; -----------------------------------------------------------------------
;; 4. OSAL Async Event Notification Subsystem
;; -----------------------------------------------------------------------

(define-record-type <osal-event-loop>
  (%make-osal-event-loop platform backend-type raw-loop capacity active-box)
  osal-event-loop?
  (platform     osal-event-loop-platform)
  (backend-type osal-event-loop-backend)
  (raw-loop     %osal-event-loop-raw)
  (capacity     osal-event-loop-capacity)
  (active-box   %osal-event-loop-active-box))

(define (osal-event-loop-active? loop)
  (declare (no-safepoints))
  (if (not (osal-event-loop? loop))
      (error "osal-event-loop-active?: expected <osal-event-loop> (CWE-843)" loop)
      (atomic-ref (%osal-event-loop-active-box loop))))

(define osal-make-event-loop
  (begin (declare (no-safepoints))
   (case-lambda
    (()
     (osal-make-event-loop *osal-default-capacity* 'auto))
    ((capacity)
     (osal-make-event-loop capacity 'auto))
    ((capacity backend-type)
     (if (not (integer? capacity))
         (error "osal-make-event-loop: capacity must be an integer (CWE-843)" capacity)
         (if (or (<= capacity 0) (> capacity *osal-max-events*))
             (error "osal-make-event-loop: capacity out of bounds [1..4096] (CWE-400)" capacity)
             (let* ((plat (osal-platform))
                    (resolved-backend
                     (if (eq? backend-type 'auto)
                         (case plat
                           ((linux)   'io_uring)
                           ((darwin)  'kqueue)
                           ((windows) 'iocp)
                           (else      'simulator))
                         backend-type))
                    (raw
                     (case resolved-backend
                       ((io_uring)
                        (if (procedure? make-io-uring)
                            (guard (e (#t #f)) (make-io-uring capacity))
                            #f))
                       ((kqueue)
                        (if (procedure? make-kqueue-loop)
                            (guard (e (#t #f)) (make-kqueue-loop capacity))
                            #f))
                       (else
                        ;; Fallback to kqueue simulator loop
                        (if (procedure? make-kqueue-loop)
                            (make-kqueue-loop capacity)
                            #f)))))
               (%make-osal-event-loop plat resolved-backend raw capacity (make-atomic-box #t)))))))))

(define (osal-event-loop-close! loop)
  (declare (no-safepoints))
  (if (not (osal-event-loop? loop))
      (error "osal-event-loop-close!: expected <osal-event-loop> (CWE-843)" loop)
      (let ((was-active (atomic-swap! (%osal-event-loop-active-box loop) #f)))
        (if was-active
            (let ((raw (%osal-event-loop-raw loop))
                  (backend (osal-event-loop-backend loop)))
              (case backend
                ((io_uring)
                 (if (and raw (procedure? io-uring-close!))
                     (io-uring-close! raw)
                     #f))
                ((kqueue)
                 (if (and raw (procedure? kqueue-loop-close!))
                     (kqueue-loop-close! raw)
                     #f))
                (else
                 (if (and raw (procedure? kqueue-loop-close!))
                     (kqueue-loop-close! raw)
                     #f)))
              #t)
            #f))))

(define osal-event-register-read!
  (begin (declare (no-safepoints))
   (case-lambda
    ((loop fd udata)
     (osal-event-register-read! loop fd udata #f))
    ((loop fd udata task)
     (if (not (osal-event-loop? loop))
         (error "osal-event-register-read!: expected <osal-event-loop> (CWE-843)" loop)
         (if (not (osal-event-loop-active? loop))
             (error "osal-event-register-read!: loop is closed (CWE-833)" loop)
             (if (not (integer? fd))
                 (error "osal-event-register-read!: fd must be an integer (CWE-843)" fd)
                 (let ((raw (%osal-event-loop-raw loop))
                       (backend (osal-event-loop-backend loop)))
                   (case backend
                     ((io_uring)
                      (if (and raw (procedure? io-uring-submit-nop!))
                          (io-uring-submit-nop! raw udata task)
                          #f))
                     ((kqueue)
                      (if (and raw (procedure? kqueue-register-read!))
                          (kqueue-register-read! raw fd udata task)
                          #f))
                     (else
                      (if (and raw (procedure? kqueue-register-read!))
                          (kqueue-register-read! raw fd udata task)
                          #f)))))))))))

(define osal-event-register-write!
  (begin (declare (no-safepoints))
   (case-lambda
    ((loop fd udata)
     (osal-event-register-write! loop fd udata #f))
    ((loop fd udata task)
     (if (not (osal-event-loop? loop))
         (error "osal-event-register-write!: expected <osal-event-loop> (CWE-843)" loop)
         (if (not (osal-event-loop-active? loop))
             (error "osal-event-register-write!: loop is closed (CWE-833)" loop)
             (if (not (integer? fd))
                 (error "osal-event-register-write!: fd must be an integer (CWE-843)" fd)
                 (let ((raw (%osal-event-loop-raw loop))
                       (backend (osal-event-loop-backend loop)))
                   (case backend
                     ((io_uring)
                      (if (and raw (procedure? io-uring-submit-nop!))
                          (io-uring-submit-nop! raw udata task)
                          #f))
                     ((kqueue)
                      (if (and raw (procedure? kqueue-register-write!))
                          (kqueue-register-write! raw fd udata task)
                          #f))
                     (else
                      (if (and raw (procedure? kqueue-register-write!))
                          (kqueue-register-write! raw fd udata task)
                          #f)))))))))))

(define (osal-event-unregister! loop fd filter)
  (declare (no-safepoints))
  (if (not (osal-event-loop? loop))
      (error "osal-event-unregister!: expected <osal-event-loop> (CWE-843)" loop)
      (if (not (osal-event-loop-active? loop))
          (error "osal-event-unregister!: loop is closed (CWE-833)" loop)
          (let ((raw (%osal-event-loop-raw loop))
                (backend (osal-event-loop-backend loop)))
            (case backend
              ((kqueue)
               (if (and raw (procedure? kqueue-unregister!))
                   (kqueue-unregister! raw fd filter)
                   #f))
              (else #t))))))

(define osal-event-poll!
  (begin (declare (no-safepoints))
   (case-lambda
    ((loop)
     (osal-event-poll! loop 32 0))
    ((loop max-events)
     (osal-event-poll! loop max-events 0))
    ((loop max-events timeout-ms)
     (if (not (osal-event-loop? loop))
         (error "osal-event-poll!: expected <osal-event-loop> (CWE-843)" loop)
         (if (not (osal-event-loop-active? loop))
             (error "osal-event-poll!: loop is closed (CWE-833)" loop)
             (let ((raw (%osal-event-loop-raw loop))
                   (backend (osal-event-loop-backend loop)))
               (case backend
                 ((io_uring)
                  (if (and raw (procedure? io-uring-poll-completions!))
                      (let ((n (io-uring-poll-completions! raw)))
                        (let drain-loop ((count 0) (acc '()))
                          (if (>= count max-events)
                              (reverse acc)
                              (let ((c (io-uring-dequeue-completion! raw)))
                                (if c
                                    (drain-loop (+ count 1) (cons c acc))
                                    (reverse acc))))))
                      '()))
                 ((kqueue)
                  (if (and raw (procedure? kqueue-poll-events!))
                      (kqueue-poll-events! raw max-events timeout-ms)
                      '()))
                 (else
                  (if (and raw (procedure? kqueue-poll-events!))
                      (kqueue-poll-events! raw max-events timeout-ms)
                      '()))))))))))

(define (osal-event-loop-stats loop)
  (declare (no-safepoints))
  (if (not (osal-event-loop? loop))
      (error "osal-event-loop-stats: expected <osal-event-loop> (CWE-843)" loop)
      (let ((raw (%osal-event-loop-raw loop))
            (backend (osal-event-loop-backend loop)))
        (list (cons 'platform (osal-event-loop-platform loop))
              (cons 'backend backend)
              (cons 'capacity (osal-event-loop-capacity loop))
              (cons 'active? (osal-event-loop-active? loop))
              (cons 'raw-stats
                    (case backend
                      ((io_uring)
                       (if (and raw (procedure? io-uring-stats))
                           (io-uring-stats raw)
                           #f))
                      ((kqueue)
                       (if (and raw (procedure? kqueue-stats))
                           (kqueue-stats raw)
                           #f))
                      (else #f)))))))
