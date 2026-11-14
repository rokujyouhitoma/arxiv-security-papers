;;; =======================================================================
;;; Synapse Concurrency Runtime: BSD / macOS kqueue Event Loop (io_kqueue.scm)
;;; Conforms to DSN-37 Section 7.4.3 & Phase 7 Task 7.3 (Issue #697)
;;;
;;; Implements:
;;;   1. <kqueue-loop> record type with native kernel & user-space fallback dual-mode
;;;   2. kevent registration: EVFILT_READ, EVFILT_WRITE, EVFILT_TIMER
;;;   3. Task suspension: transition to 'waiting-io and cooperative yield
;;;   4. Event polling and automatic task resumption: transition to 'ready
;;;   5. Graceful degradation simulator under Linux/Windows/sandbox environments
;;;   6. CWE-119, CWE-400, CWE-416, CWE-833, CWE-843 security mitigations
;;; =======================================================================

(define *kqueue-default-entries* 128)
(define *kqueue-max-entries* 4096)

;; -----------------------------------------------------------------------
;; 1. Kqueue Filter and Flag Constants (POSIX / Darwin ABI)
;; -----------------------------------------------------------------------
(define EVFILT_READ     -1)
(define EVFILT_WRITE    -2)
(define EVFILT_AIO      -3)
(define EVFILT_VNODE    -4)
(define EVFILT_PROC     -5)
(define EVFILT_SIGNAL   -6)
(define EVFILT_TIMER    -7)

(define EV_ADD          1)
(define EV_DELETE       2)
(define EV_ENABLE       4)
(define EV_DISABLE      8)
(define EV_ONESHOT      16)
(define EV_CLEAR        32)
(define EV_RECEIPT      64)
(define EV_DISPATCH     128)
(define EV_UDATA_SPECIFIC 256)
(define EV_EOF          32768)
(define EV_ERROR        16384)

;; -----------------------------------------------------------------------
;; 2. Low-Level System Call Stubs (Overridden at link-time on macOS/BSD)
;; -----------------------------------------------------------------------
(define (%sys-kqueue-create)
  #f)

(define (%sys-kevent-register fd ident filter flags fflags data udata)
  #f)

(define (%sys-kevent-poll fd max-events timeout-ms)
  #f)

(define (%sys-kqueue-close! fd)
  #f)

;; -----------------------------------------------------------------------
;; 3. <kqueue-loop> Record Definition
;; -----------------------------------------------------------------------

(define-record-type <kqueue-loop>
  (%make-kqueue-loop fd capacity native?
                     active-box events-box pending-box completed-box
                     submitted-box completed-count-box)
  kqueue-loop?
  (fd                  kqueue-loop-fd)
  (capacity            kqueue-loop-capacity)
  (native?             kqueue-loop-native?)
  (active-box          %kqueue-loop-active-box)
  (events-box          %kqueue-loop-events-box)
  (pending-box         %kqueue-loop-pending-box)
  (completed-box       %kqueue-loop-completed-box)
  (submitted-box       %kqueue-loop-submitted-box)
  (completed-count-box %kqueue-loop-completed-count-box))

(define (kqueue-loop-active? loop)
  (declare (no-safepoints))
  (if (not (kqueue-loop? loop))
      (error "kqueue-loop-active?: expected <kqueue-loop> (CWE-843)" loop)
      (atomic-ref (%kqueue-loop-active-box loop))))

(define (kqueue-submitted-count loop)
  (declare (no-safepoints))
  (if (not (kqueue-loop? loop))
      (error "kqueue-submitted-count: expected <kqueue-loop> (CWE-843)" loop)
      (atomic-ref (%kqueue-loop-submitted-box loop))))

(define (kqueue-completed-count loop)
  (declare (no-safepoints))
  (if (not (kqueue-loop? loop))
      (error "kqueue-completed-count: expected <kqueue-loop> (CWE-843)" loop)
      (atomic-ref (%kqueue-loop-completed-count-box loop))))

(define (kqueue-pending-count loop)
  (declare (no-safepoints))
  (if (not (kqueue-loop? loop))
      (error "kqueue-pending-count: expected <kqueue-loop> (CWE-843)" loop)
      (length (atomic-ref (%kqueue-loop-pending-box loop)))))

(define (kqueue-registered-count loop)
  (declare (no-safepoints))
  (if (not (kqueue-loop? loop))
      (error "kqueue-registered-count: expected <kqueue-loop> (CWE-843)" loop)
      (length (atomic-ref (%kqueue-loop-events-box loop)))))

;; -----------------------------------------------------------------------
;; 4. Kqueue Factory & Lifecycle Management
;; -----------------------------------------------------------------------

(define make-kqueue-loop
  (begin (declare (no-safepoints))
   (case-lambda
    (()
     (make-kqueue-loop *kqueue-default-entries*))
    ((capacity)
     (if (not (integer? capacity))
         (error "make-kqueue-loop: capacity must be an integer (CWE-843)" capacity)
         (if (or (<= capacity 0) (> capacity *kqueue-max-entries*))
             (error "make-kqueue-loop: capacity out of bounds (CWE-400)" capacity)
             (let* ((kq-fd (if (procedure? %sys-kqueue-create)
                               (%sys-kqueue-create)
                               #f))
                    (is-native (and (integer? kq-fd) (>= kq-fd 0))))
               (%make-kqueue-loop (if is-native kq-fd #f)
                                  capacity
                                  is-native
                                  (make-atomic-box #t)
                                  (make-atomic-box '())
                                  (make-atomic-box '())
                                  (make-atomic-box '())
                                  (make-atomic-box 0)
                                  (make-atomic-box 0)))))))))

(define (kqueue-loop-close! loop)
  (declare (no-safepoints))
  (if (not (kqueue-loop? loop))
      (error "kqueue-loop-close!: expected <kqueue-loop> (CWE-843)" loop)
      (let ((was-active (atomic-swap! (%kqueue-loop-active-box loop) #f)))
        (if was-active
            (begin
              (if (and (kqueue-loop-native? loop) (integer? (kqueue-loop-fd loop)))
                  (if (procedure? %sys-kqueue-close!)
                      (%sys-kqueue-close! (kqueue-loop-fd loop))
                      #f)
                  #f)
              #t)
            #f))))

;; -----------------------------------------------------------------------
;; 5. Event Registration & Submission
;; -----------------------------------------------------------------------

(define (%kqueue-register-event! loop ident filter flags data udata task)
  (let* ((active? (kqueue-loop-active? loop))
         (cap (kqueue-loop-capacity loop))
         (events-box (%kqueue-loop-events-box loop))
         (pending-box (%kqueue-loop-pending-box loop))
         (submitted-box (%kqueue-loop-submitted-box loop)))
    (if (not active?)
        (error "kqueue-register: loop is closed (CWE-833)" loop)
        (let retry ()
          (let* ((cur (atomic-ref events-box))
                 (cur-len (length cur)))
            (if (>= cur-len cap)
                (error "kqueue registration: capacity exceeded (CWE-400)" 'queue_full)
                (let* ((entry (vector ident filter flags data udata task))
                       (new-cur (cons entry cur)))
                  (if (not (atomic-cas! events-box cur new-cur))
                      (retry)
                      (begin
                        ;; If native kqueue is active, invoke kernel kevent register
                        (if (and (kqueue-loop-native? loop) (procedure? %sys-kevent-register))
                            (%sys-kevent-register (kqueue-loop-fd loop) ident filter flags 0 data udata)
                            #f)
                        ;; Add to pending queue for poll dispatch
                        (let p-retry ()
                          (let* ((p-cur (atomic-ref pending-box))
                                 (p-new (cons entry p-cur)))
                            (if (not (atomic-cas! pending-box p-cur p-new))
                                (p-retry)
                                (begin
                                  (atomic-fetch-add! submitted-box 1)
                                  ;; Suspend task if task-context provided
                                  (if (and task (procedure? task-context?) (task-context? task))
                                      (task-state-set! task 'waiting-io)
                                      #f)
                                  #t)))))))))))))

(define kqueue-register-read!
  (begin (declare (no-safepoints))
   (case-lambda
    ((loop fd udata)
     (kqueue-register-read! loop fd udata #f))
    ((loop fd udata task)
     (if (not (kqueue-loop? loop))
         (error "kqueue-register-read!: expected <kqueue-loop> (CWE-843)" loop)
         (if (not (integer? fd))
             (error "kqueue-register-read!: fd must be an integer (CWE-843)" fd)
             (%kqueue-register-event! loop fd EVFILT_READ (bitwise-ior EV_ADD EV_ENABLE) 0 udata task)))))))

(define kqueue-register-write!
  (begin (declare (no-safepoints))
   (case-lambda
    ((loop fd udata)
     (kqueue-register-write! loop fd udata #f))
    ((loop fd udata task)
     (if (not (kqueue-loop? loop))
         (error "kqueue-register-write!: expected <kqueue-loop> (CWE-843)" loop)
         (if (not (integer? fd))
             (error "kqueue-register-write!: fd must be an integer (CWE-843)" fd)
             (%kqueue-register-event! loop fd EVFILT_WRITE (bitwise-ior EV_ADD EV_ENABLE) 0 udata task)))))))

(define kqueue-register-timer!
  (begin (declare (no-safepoints))
   (case-lambda
    ((loop timer-id ms udata)
     (kqueue-register-timer! loop timer-id ms udata #f))
    ((loop timer-id ms udata task)
     (if (not (kqueue-loop? loop))
         (error "kqueue-register-timer!: expected <kqueue-loop> (CWE-843)" loop)
         (if (not (integer? timer-id))
             (error "kqueue-register-timer!: timer-id must be integer (CWE-843)" timer-id)
             (if (or (not (integer? ms)) (< ms 0))
                 (error "kqueue-register-timer!: ms must be non-negative integer (CWE-400)" ms)
                 (%kqueue-register-event! loop timer-id EVFILT_TIMER (bitwise-ior EV_ADD EV_ONESHOT) ms udata task))))))))

(define (kqueue-unregister! loop ident filter)
  (declare (no-safepoints))
  (if (not (kqueue-loop? loop))
      (error "kqueue-unregister!: expected <kqueue-loop> (CWE-843)" loop)
      (let ((events-box (%kqueue-loop-events-box loop)))
        (let retry ()
          (let* ((cur (atomic-ref events-box))
                 (filtered (let filter-loop ((lst cur) (acc '()))
                             (if (null? lst)
                                 (reverse acc)
                                 (let* ((e (car lst))
                                        (i (vector-ref e 0))
                                        (f (vector-ref e 1)))
                                   (if (and (= i ident) (= f filter))
                                       (filter-loop (cdr lst) acc)
                                       (filter-loop (cdr lst) (cons e acc))))))))
            (if (not (atomic-cas! events-box cur filtered))
                (retry)
                (begin
                  (if (and (kqueue-loop-native? loop) (procedure? %sys-kevent-register))
                      (%sys-kevent-register (kqueue-loop-fd loop) ident filter EV_DELETE 0 0 0)
                      #f)
                  #t)))))))

;; -----------------------------------------------------------------------
;; 6. Event Polling & Task Resumption
;; -----------------------------------------------------------------------

(define kqueue-poll-events!
  (begin (declare (no-safepoints))
   (case-lambda
    ((loop)
     (kqueue-poll-events! loop 32 0))
    ((loop max-events)
     (kqueue-poll-events! loop max-events 0))
    ((loop max-events timeout-ms)
     (if (not (kqueue-loop? loop))
         (error "kqueue-poll-events!: expected <kqueue-loop> (CWE-843)" loop)
         (if (not (kqueue-loop-active? loop))
             (error "kqueue-poll-events!: loop is closed (CWE-833)" loop)
             (let* ((pending-box (%kqueue-loop-pending-box loop))
                    (completed-box (%kqueue-loop-completed-box loop))
                    (completed-cnt-box (%kqueue-loop-completed-count-box loop))
                    ;; In native mode, poll kevent if available
                    (native-events
                     (if (and (kqueue-loop-native? loop) (procedure? %sys-kevent-poll))
                         (%sys-kevent-poll (kqueue-loop-fd loop) max-events timeout-ms)
                         #f)))
               (if (and native-events (list? native-events))
                   native-events
                   ;; Fallback / Simulated Mode
                   (let ((requests (atomic-swap! pending-box '())))
                     (if (null? requests)
                         '()
                         (let loop-req ((reqs (reverse requests))
                                        (count 0)
                                        (results '()))
                           (if (or (null? reqs) (>= count max-events))
                               (begin
                                 ;; Put unhandled requests back
                                 (if (pair? reqs)
                                     (let ret-loop ()
                                       (let* ((cur (atomic-ref pending-box))
                                              (new-cur (append reqs cur)))
                                         (if (not (atomic-cas! pending-box cur new-cur))
                                             (ret-loop)
                                             #t)))
                                     #t)
                                 (reverse results))
                               (let* ((req (car reqs))
                                      (ident (vector-ref req 0))
                                      (filter (vector-ref req 1))
                                      (flags (vector-ref req 2))
                                      (data (vector-ref req 3))
                                      (udata (vector-ref req 4))
                                      (task (vector-ref req 5))
                                      ;; Simulated result: (cons udata filter)
                                      (ev (cons udata filter)))
                                 ;; Store into completed box
                                 (let rec-loop ()
                                   (let* ((cur-c (atomic-ref completed-box))
                                          (new-c (cons ev cur-c)))
                                     (if (not (atomic-cas! completed-box cur-c new-c))
                                         (rec-loop)
                                         #t)))
                                 (atomic-fetch-add! completed-cnt-box 1)

                                 ;; Resume task if task exists and not terminated (CWE-416)
                                 (if (and task (procedure? task-context?) (task-context? task))
                                     (let ((st (task-state task)))
                                       (if (or (eq? st 'waiting-io) (eq? st 'blocked))
                                           (begin
                                             (if (procedure? task-set-handoff!)
                                                 (task-set-handoff! task (cons 'kqueue_event filter))
                                                 #f)
                                             (task-state-set! task 'ready)
                                             #t)
                                           #f))
                                     #f)
                                 (loop-req (cdr reqs) (+ count 1) (cons ev results)))))))))))))))

(define (kqueue-dequeue-completion! loop)
  (declare (no-safepoints))
  (if (not (kqueue-loop? loop))
      (error "kqueue-dequeue-completion!: expected <kqueue-loop> (CWE-843)" loop)
      (let ((completed-box (%kqueue-loop-completed-box loop)))
        (let retry ()
          (let ((cur (atomic-ref completed-box)))
            (if (null? cur)
                #f
                (let* ((rev (reverse cur))
                       (item (car rev))
                       (new-cur (reverse (cdr rev))))
                  (if (atomic-cas! completed-box cur new-cur)
                      item
                      (retry)))))))))

(define (kqueue-stats loop)
  (declare (no-safepoints))
  (if (not (kqueue-loop? loop))
      (error "kqueue-stats: expected <kqueue-loop> (CWE-843)" loop)
      (list (cons 'native? (kqueue-loop-native? loop))
            (cons 'capacity (kqueue-loop-capacity loop))
            (cons 'active? (kqueue-loop-active? loop))
            (cons 'registered (kqueue-registered-count loop))
            (cons 'pending (kqueue-pending-count loop))
            (cons 'submitted (kqueue-submitted-count loop))
            (cons 'completed (kqueue-completed-count loop)))))
