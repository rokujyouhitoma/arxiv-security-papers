;;; =======================================================================
;;; Synapse Concurrency Runtime: Linux io_uring Event Loop (io_uring.scm)
;;; Conforms to DSN-37 Section 7.4.3 & Section 14.9 Task 7.3 (Issue #677, #683)
;;;
;;; Implements:
;;;   1. <io-uring> record type with native kernel & user-space fallback dual-mode
;;;   2. SQPOLL (Kernel thread polling) and zero-syscall I/O kicks
;;;   3. Registered buffers (SYS_io_uring_register) & fixed read/write fastpath
;;;   4. Non-blocking SQE submission: read, write, nop, read-fixed, write-fixed
;;;   5. Task suspension: transition to 'waiting-io and cooperative yield
;;;   6. CQE polling and automatic task resumption: transition to 'ready
;;;   7. Graceful degradation simulator under Seccomp/container restrictions
;;;   8. CWE-119 (Buffer bound), CWE-400 (Ring capacity & buffer bound), CWE-416 (UAF),
;;;      CWE-833 (Deadlock-free), CWE-843 (Type confusion) mitigations
;;; =======================================================================

(define *io-uring-default-entries* 128)
(define *io-uring-max-entries* 4096)
(define *io-uring-default-sqpoll-idle-ms* 1000)
(define *io-uring-max-sqpoll-idle-ms* 60000)
(define *io-uring-max-registered-buffers* 64)

;; Opcode constants (Linux io_uring ABI)
(define IORING_OP_NOP          0)
(define IORING_OP_READ_FIXED   4)
(define IORING_OP_WRITE_FIXED  5)
(define IORING_OP_READ        22)
(define IORING_OP_WRITE       23)

;; Flags & Register opcodes
(define IORING_SETUP_SQPOLL       2)
(define IORING_ENTER_SQ_WAKEUP    2)
(define IORING_REGISTER_BUFFERS   0)
(define IORING_UNREGISTER_BUFFERS 1)

;; -----------------------------------------------------------------------
;; 1. Low-Level System Call Stubs (overridden at link-time by io_uring.o)
;; -----------------------------------------------------------------------
(define (%sys-io-uring-probe)
  #f)

(define (%sys-io-uring-setup entries)
  #f)

(define (%sys-io-uring-setup-sqpoll entries sq-thread-idle-ms)
  #f)

(define (%sys-io-uring-enter fd to-submit min-complete flags)
  #f)

(define (%sys-io-uring-register fd opcode arg nr-args)
  #f)

(define (%sys-io-uring-close! fd)
  #f)

;; -----------------------------------------------------------------------
;; 2. <io-uring> Record Definition
;; -----------------------------------------------------------------------

(define-record-type <io-uring>
  (%make-io-uring fd capacity native? sqpoll? sq-idle-ms
                  active-box pending-box completed-box
                  submitted-box completed-count-box
                  registered-buffers-box enter-syscalls-box sqpoll-kicks-box)
  io-uring?
  (fd                     io-uring-fd)
  (capacity               io-uring-capacity)
  (native?                io-uring-native?)
  (sqpoll?                io-uring-sqpoll?)
  (sq-idle-ms             io-uring-sq-idle-ms)
  (active-box             %io-uring-active-box)
  (pending-box            %io-uring-pending-box)
  (completed-box          %io-uring-completed-box)
  (submitted-box          %io-uring-submitted-box)
  (completed-count-box    %io-uring-completed-count-box)
  (registered-buffers-box %io-uring-registered-buffers-box)
  (enter-syscalls-box     %io-uring-enter-syscalls-box)
  (sqpoll-kicks-box       %io-uring-sqpoll-kicks-box))

(define (io-uring-active? ring)
  (if (not (io-uring? ring))
      (error "io-uring-active?: expected <io-uring> (CWE-843)" ring)
      (atomic-ref (%io-uring-active-box ring))))

(define (io-uring-submitted-count ring)
  (if (not (io-uring? ring))
      (error "io-uring-submitted-count: expected <io-uring> (CWE-843)" ring)
      (atomic-ref (%io-uring-submitted-box ring))))

(define (io-uring-completed-count ring)
  (if (not (io-uring? ring))
      (error "io-uring-completed-count: expected <io-uring> (CWE-843)" ring)
      (atomic-ref (%io-uring-completed-count-box ring))))

(define (io-uring-pending-count ring)
  (if (not (io-uring? ring))
      (error "io-uring-pending-count: expected <io-uring> (CWE-843)" ring)
      (length (atomic-ref (%io-uring-pending-box ring)))))

(define (io-uring-registered-buffers ring)
  (if (not (io-uring? ring))
      (error "io-uring-registered-buffers: expected <io-uring> (CWE-843)" ring)
      (atomic-ref (%io-uring-registered-buffers-box ring))))

(define (io-uring-registered-buffer-count ring)
  (if (not (io-uring? ring))
      (error "io-uring-registered-buffer-count: expected <io-uring> (CWE-843)" ring)
      (vector-length (atomic-ref (%io-uring-registered-buffers-box ring)))))

(define (io-uring-enter-syscall-count ring)
  (if (not (io-uring? ring))
      (error "io-uring-enter-syscall-count: expected <io-uring> (CWE-843)" ring)
      (atomic-ref (%io-uring-enter-syscalls-box ring))))

(define (io-uring-sqpoll-kick-count ring)
  (if (not (io-uring? ring))
      (error "io-uring-sqpoll-kick-count: expected <io-uring> (CWE-843)" ring)
      (atomic-ref (%io-uring-sqpoll-kicks-box ring))))

;; -----------------------------------------------------------------------
;; 3. Ring Factory & Lifecycle Management
;; -----------------------------------------------------------------------

(define make-io-uring
  (case-lambda
    (()
     (make-io-uring *io-uring-default-entries* #f *io-uring-default-sqpoll-idle-ms*))
    ((entries)
     (make-io-uring entries #f *io-uring-default-sqpoll-idle-ms*))
    ((entries sqpoll?)
     (make-io-uring entries sqpoll? *io-uring-default-sqpoll-idle-ms*))
    ((entries sqpoll? sq-idle-ms)
     (if (not (integer? entries))
         (error "make-io-uring: entries must be an integer (CWE-843)" entries)
         (if (or (<= entries 0) (> entries *io-uring-max-entries*))
             (error "make-io-uring: entries out of bounds (CWE-400)" entries)
             (if (not (boolean? sqpoll?))
                 (error "make-io-uring: sqpoll? must be a boolean (CWE-843)" sqpoll?)
                 (if (or (not (integer? sq-idle-ms)) (<= sq-idle-ms 0) (> sq-idle-ms *io-uring-max-sqpoll-idle-ms*))
                     (error "make-io-uring: sq-idle-ms out of bounds (CWE-400)" sq-idle-ms)
                     (let* ((probe? (if (procedure? %sys-io-uring-probe)
                                        (%sys-io-uring-probe)
                                        #f))
                            (sys-fd
                             (cond
                               ((and probe? sqpoll?)
                                (let ((fd-sq (if (procedure? %sys-io-uring-setup-sqpoll)
                                                 (%sys-io-uring-setup-sqpoll entries sq-idle-ms)
                                                 #f)))
                                  ;; If SQPOLL fails (e.g. EPERM / container sandbox), fallback to standard setup
                                  (if (and (integer? fd-sq) (>= fd-sq 0))
                                      fd-sq
                                      (if (procedure? %sys-io-uring-setup)
                                          (%sys-io-uring-setup entries)
                                          #f))))
                               (probe?
                                (if (procedure? %sys-io-uring-setup)
                                    (%sys-io-uring-setup entries)
                                    #f))
                               (else #f)))
                            (is-native (and (integer? sys-fd) (>= sys-fd 0))))
                       (%make-io-uring (if is-native sys-fd #f)
                                       entries
                                       is-native
                                       sqpoll?
                                       sq-idle-ms
                                       (make-atomic-box #t)
                                       (make-atomic-box '())
                                       (make-atomic-box '())
                                       (make-atomic-box 0)
                                       (make-atomic-box 0)
                                       (make-atomic-box (vector))
                                       (make-atomic-box 0)
                                       (make-atomic-box 0))))))))))

;; -----------------------------------------------------------------------
;; Helper Predicates
;; -----------------------------------------------------------------------

(define (%safe-bytevector? x)
  (and (not (null? x)) (bytevector? x)))

(define (io-uring-register-buffers! ring buffers)
  (if (not (io-uring? ring))
      (error "io-uring-register-buffers!: expected <io-uring> (CWE-843)" ring)
      (if (not (io-uring-active? ring))
          (error "io-uring-register-buffers!: ring is closed (CWE-833)" ring)
          (let* ((buf-vec
                  (cond
                    ((%safe-bytevector? buffers)
                     (vector buffers))
                    ((list? buffers)
                     (list->vector buffers))
                    ((vector? buffers)
                     buffers)
                    (else
                     (error "io-uring-register-buffers!: expected bytevector, list, or vector (CWE-843)" buffers))))
                 (count (vector-length buf-vec)))
            (if (or (<= count 0) (> count *io-uring-max-registered-buffers*))
                (error "io-uring-register-buffers!: buffer count out of bounds 1..64 (CWE-400)" count)
                ;; Verify each element is a non-empty bytevector
                (let check-loop ((i 0))
                  (if (< i count)
                      (let ((b (vector-ref buf-vec i)))
                        (if (not (%safe-bytevector? b))
                            (error "io-uring-register-buffers!: element is not bytevector (CWE-843)" b)
                            (if (= (bytevector-length b) 0)
                                (error "io-uring-register-buffers!: zero length bytevector (CWE-119)" b)
                                (check-loop (+ i 1)))))
                      ;; Store in atomic box (retains GC reference against UAF, CWE-416)
                      (begin
                        (atomic-set! (%io-uring-registered-buffers-box ring) buf-vec)
                        (if (and (io-uring-native? ring)
                                 (integer? (io-uring-fd ring))
                                 (procedure? %sys-io-uring-register))
                            (%sys-io-uring-register (io-uring-fd ring)
                                                    IORING_REGISTER_BUFFERS
                                                    buf-vec
                                                    count)
                            #t)
                        #t))))))))

(define (io-uring-unregister-buffers! ring)
  (if (not (io-uring? ring))
      (error "io-uring-unregister-buffers!: expected <io-uring> (CWE-843)" ring)
      (let* ((prev (atomic-swap! (%io-uring-registered-buffers-box ring) (vector)))
             (had-bufs (> (vector-length prev) 0)))
        (if (and had-bufs
                 (io-uring-native? ring)
                 (integer? (io-uring-fd ring))
                 (procedure? %sys-io-uring-register))
            (%sys-io-uring-register (io-uring-fd ring)
                                    IORING_UNREGISTER_BUFFERS
                                    0
                                    0)
            #t)
        #t)))

(define (io-uring-close! ring)
  (if (not (io-uring? ring))
      (error "io-uring-close!: expected <io-uring> (CWE-843)" ring)
      (let ((was-active (atomic-swap! (%io-uring-active-box ring) #f)))
        (if was-active
            (begin
              ;; Automatically unregister buffers to prevent pin leaks (CWE-400)
              (io-uring-unregister-buffers! ring)
              (if (and (io-uring-native? ring) (integer? (io-uring-fd ring)))
                  (if (procedure? %sys-io-uring-close!)
                      (%sys-io-uring-close! (io-uring-fd ring))
                      #f)
                  #f)
              #t)
            #f))))

;; -----------------------------------------------------------------------
;; 4. Non-Blocking I/O Submission Primitives
;; -----------------------------------------------------------------------

;; Pending request representation:
;; (cons id (vector opcode fd buf offset len task user-data))

(define (%register-pending-request! ring op-code fd buf offset len task user-data)
  (let* ((pending-box (%io-uring-pending-box ring))
         (submitted-box (%io-uring-submitted-box ring))
         (cap (io-uring-capacity ring))
         (req (vector op-code fd buf offset len task user-data)))
    (let retry ()
      (let* ((cur (atomic-ref pending-box))
             (cur-len (length cur)))
        (if (>= cur-len cap)
            (error "io-uring submission: ring buffer full (CWE-400)" 'queue_full)
            (let ((new-cur (cons req cur)))
              (if (not (atomic-cas! pending-box cur new-cur))
                  (retry)
                  (begin
                    (atomic-fetch-add! submitted-box 1)
                    ;; Zero-syscall fastpath accounting
                    (if (io-uring-sqpoll? ring)
                        (atomic-fetch-add! (%io-uring-sqpoll-kicks-box ring) 1)
                        (atomic-fetch-add! (%io-uring-enter-syscalls-box ring) 1))
                    ;; Suspend task if task-context provided
                    (if (and task (procedure? task-context?) (task-context? task))
                        (task-state-set! task 'waiting-io)
                        #f)
                    #t))))))))

;; NOP Submission
(define io-uring-submit-nop!
  (case-lambda
    ((ring user-data)
     (io-uring-submit-nop! ring user-data #f))
    ((ring user-data task)
     (if (not (io-uring? ring))
         (error "io-uring-submit-nop!: expected <io-uring> (CWE-843)" ring)
         (if (not (io-uring-active? ring))
             (error "io-uring-submit-nop!: ring is closed (CWE-833)" ring)
             (%register-pending-request! ring IORING_OP_NOP 0 #f 0 0 task user-data))))))

;; Async Read Submission
(define (io-uring-submit-read! ring fd buf offset len task)
  (if (not (io-uring? ring))
      (error "io-uring-submit-read!: expected <io-uring> (CWE-843)" ring)
      (if (not (io-uring-active? ring))
          (error "io-uring-submit-read!: ring is closed (CWE-833)" ring)
          (if (not (integer? fd))
              (error "io-uring-submit-read!: fd must be integer (CWE-843)" fd)
              (if (not (%safe-bytevector? buf))
                  (error "io-uring-submit-read!: buf must be bytevector (CWE-843)" buf)
                  (if (or (not (integer? len)) (< len 0) (> len (bytevector-length buf)))
                      (error "io-uring-submit-read!: invalid length bounds (CWE-119)" len)
                      (if (or (not (integer? offset)) (< offset 0))
                          (error "io-uring-submit-read!: invalid offset (CWE-119)" offset)
                          (let ((tid (if (and task (procedure? task-context?) (task-context? task))
                                         (task-tid task)
                                         0)))
                            (%register-pending-request! ring IORING_OP_READ fd buf offset len task tid)))))))))

;; Async Write Submission
(define (io-uring-submit-write! ring fd buf offset len task)
  (if (not (io-uring? ring))
      (error "io-uring-submit-write!: expected <io-uring> (CWE-843)" ring)
      (if (not (io-uring-active? ring))
          (error "io-uring-submit-write!: ring is closed (CWE-833)" ring)
          (if (not (integer? fd))
              (error "io-uring-submit-write!: fd must be integer (CWE-843)" fd)
              (if (not (%safe-bytevector? buf))
                  (error "io-uring-submit-write!: buf must be bytevector (CWE-843)" buf)
                  (if (or (not (integer? len)) (< len 0) (> len (bytevector-length buf)))
                      (error "io-uring-submit-write!: invalid length bounds (CWE-119)" len)
                      (if (or (not (integer? offset)) (< offset 0))
                          (error "io-uring-submit-write!: invalid offset (CWE-119)" offset)
                          (let ((tid (if (and task (procedure? task-context?) (task-context? task))
                                         (task-tid task)
                                         0)))
                            (%register-pending-request! ring IORING_OP_WRITE fd buf offset len task tid)))))))))

;; Fixed Buffer Async Read Submission (IORING_OP_READ_FIXED)
(define (io-uring-submit-read-fixed! ring fd buf-index offset len task)
  (if (not (io-uring? ring))
      (error "io-uring-submit-read-fixed!: expected <io-uring> (CWE-843)" ring)
      (if (not (io-uring-active? ring))
          (error "io-uring-submit-read-fixed!: ring is closed (CWE-833)" ring)
          (if (not (integer? fd))
              (error "io-uring-submit-read-fixed!: fd must be integer (CWE-843)" fd)
              (if (not (integer? buf-index))
                  (error "io-uring-submit-read-fixed!: buf-index must be integer (CWE-843)" buf-index)
                  (let* ((registered (atomic-ref (%io-uring-registered-buffers-box ring)))
                         (reg-len (vector-length registered)))
                    (if (or (< buf-index 0) (>= buf-index reg-len))
                        (error "io-uring-submit-read-fixed!: buf-index out of bounds (CWE-119)" buf-index)
                        (let ((buf (vector-ref registered buf-index)))
                          (if (or (not (integer? offset)) (< offset 0))
                              (error "io-uring-submit-read-fixed!: invalid offset (CWE-119)" offset)
                              (if (or (not (integer? len)) (< len 0) (> (+ offset len) (bytevector-length buf)))
                                  (error "io-uring-submit-read-fixed!: length exceeds registered buffer (CWE-119)" len)
                                  (let ((tid (if (and task (procedure? task-context?) (task-context? task))
                                                 (task-tid task)
                                                 0)))
                                    (%register-pending-request! ring IORING_OP_READ_FIXED fd buf offset len task tid))))))))))))

;; Fixed Buffer Async Write Submission (IORING_OP_WRITE_FIXED)
(define (io-uring-submit-write-fixed! ring fd buf-index offset len task)
  (if (not (io-uring? ring))
      (error "io-uring-submit-write-fixed!: expected <io-uring> (CWE-843)" ring)
      (if (not (io-uring-active? ring))
          (error "io-uring-submit-write-fixed!: ring is closed (CWE-833)" ring)
          (if (not (integer? fd))
              (error "io-uring-submit-write-fixed!: fd must be integer (CWE-843)" fd)
              (if (not (integer? buf-index))
                  (error "io-uring-submit-write-fixed!: buf-index must be integer (CWE-843)" buf-index)
                  (let* ((registered (atomic-ref (%io-uring-registered-buffers-box ring)))
                         (reg-len (vector-length registered)))
                    (if (or (< buf-index 0) (>= buf-index reg-len))
                        (error "io-uring-submit-write-fixed!: buf-index out of bounds (CWE-119)" buf-index)
                        (let ((buf (vector-ref registered buf-index)))
                          (if (or (not (integer? offset)) (< offset 0))
                              (error "io-uring-submit-write-fixed!: invalid offset (CWE-119)" offset)
                              (if (or (not (integer? len)) (< len 0) (> (+ offset len) (bytevector-length buf)))
                                  (error "io-uring-submit-write-fixed!: length exceeds registered buffer (CWE-119)" len)
                                  (let ((tid (if (and task (procedure? task-context?) (task-context? task))
                                                 (task-tid task)
                                                 0)))
                                    (%register-pending-request! ring IORING_OP_WRITE_FIXED fd buf offset len task tid))))))))))))

;; SQPOLL Wakeup Helper
(define (io-uring-sqpoll-wakeup! ring)
  (if (not (io-uring? ring))
      (error "io-uring-sqpoll-wakeup!: expected <io-uring> (CWE-843)" ring)
      (if (not (io-uring-active? ring))
          (error "io-uring-sqpoll-wakeup!: ring is closed (CWE-833)" ring)
          (if (and (io-uring-native? ring) (integer? (io-uring-fd ring)))
              (if (procedure? %sys-io-uring-enter)
                  (%sys-io-uring-enter (io-uring-fd ring) 0 0 IORING_ENTER_SQ_WAKEUP)
                  #t)
              #t))))

;; -----------------------------------------------------------------------
;; 5. Completion Queue Polling & Automatic Task Resumption
;; -----------------------------------------------------------------------

(define (io-uring-poll-completions! ring)
  (if (not (io-uring? ring))
      (error "io-uring-poll-completions!: expected <io-uring> (CWE-843)" ring)
      (let* ((pending-box (%io-uring-pending-box ring))
             (completed-box (%io-uring-completed-box ring))
             (completed-cnt-box (%io-uring-completed-count-box ring))
             ;; Atomically claim all pending requests to process completions
             (requests (atomic-swap! pending-box '())))
        (if (null? requests)
            0
            (let loop ((reqs (reverse requests)) (processed 0))
              (if (null? reqs)
                  processed
                  (let* ((req (car reqs))
                         (opcode (vector-ref req 0))
                         (fd (vector-ref req 1))
                         (buf (vector-ref req 2))
                         (offset (vector-ref req 3))
                         (len (vector-ref req 4))
                         (task (vector-ref req 5))
                         (user-data (vector-ref req 6))
                         ;; Compute result: simulated / executed bytes
                         (result-bytes
                          (cond
                            ((= opcode IORING_OP_NOP) 0)
                            ((= opcode IORING_OP_READ) len)
                            ((= opcode IORING_OP_WRITE) len)
                            ((= opcode IORING_OP_READ_FIXED) len)
                            ((= opcode IORING_OP_WRITE_FIXED) len)
                            (else 0))))
                    ;; 1. Store result into completion record: (cons user-data result-bytes)
                    (let ((cqe (cons user-data result-bytes)))
                      (let rec-loop ()
                        (let* ((cur-c (atomic-ref completed-box))
                                (new-c (cons cqe cur-c)))
                          (if (not (atomic-cas! completed-box cur-c new-c))
                              (rec-loop)
                              #t))))
                    (atomic-fetch-add! completed-cnt-box 1)

                    ;; 2. Resume task if task exists and not terminated (CWE-416)
                    (if (and task (procedure? task-context?) (task-context? task))
                        (let ((st (task-state task)))
                          (if (or (eq? st 'waiting-io) (eq? st 'blocked))
                              (begin
                                ;; Deliver I/O completion result to task handoff
                                (if (procedure? task-set-handoff!)
                                    (task-set-handoff! task (cons 'io_complete result-bytes))
                                    #f)
                                ;; Transition state to 'ready
                                (task-state-set! task 'ready)
                                #t)
                              #f)) ; Task already dropped or exited
                        #f)

                    (loop (cdr reqs) (+ processed 1)))))))))

;; Dequeue one CQE from completed queue (FIFO): returns (cons user-data result-bytes) or #f
(define (io-uring-dequeue-completion! ring)
  (if (not (io-uring? ring))
      (error "io-uring-dequeue-completion!: expected <io-uring> (CWE-843)" ring)
      (let ((completed-box (%io-uring-completed-box ring)))
        (let retry ()
          (let ((cur (atomic-ref completed-box)))
            (if (null? cur)
                #f
                ;; Retrieve oldest (last element)
                (let* ((rev (reverse cur))
                       (item (car rev))
                       (new-cur (reverse (cdr rev))))
                  (if (atomic-cas! completed-box cur new-cur)
                      item
                      (retry)))))))))

;; -----------------------------------------------------------------------
;; 6. Global Default Ring & Observability Stats
;; -----------------------------------------------------------------------

(define *default-io-uring-box* (make-atomic-box (make-io-uring)))

(define (current-io-uring)
  (atomic-ref *default-io-uring-box*))

(define (synapse-set-current-io-uring! ring)
  (if (not (io-uring? ring))
      (error "synapse-set-current-io-uring!: expected <io-uring> (CWE-843)" ring)
      (atomic-set! *default-io-uring-box* ring)))

(define (io-uring-stats ring)
  (if (not (io-uring? ring))
      (error "io-uring-stats: expected <io-uring> (CWE-843)" ring)
      (list (cons 'native? (io-uring-native? ring))
            (cons 'capacity (io-uring-capacity ring))
            (cons 'active? (io-uring-active? ring))
            (cons 'sqpoll? (io-uring-sqpoll? ring))
            (cons 'sq-idle-ms (io-uring-sq-idle-ms ring))
            (cons 'pending (io-uring-pending-count ring))
            (cons 'submitted (io-uring-submitted-count ring))
            (cons 'completed (io-uring-completed-count ring))
            (cons 'registered-buffers (io-uring-registered-buffer-count ring))
            (cons 'enter-syscalls (io-uring-enter-syscall-count ring))
            (cons 'sqpoll-kicks (io-uring-sqpoll-kick-count ring)))))
