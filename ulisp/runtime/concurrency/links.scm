;;; =======================================================================
;;; ULisp Runtime Concurrency: Task Links & Monitors (links.scm)
;;; Conforms to DSN-37 Section 8.4.1 & 8.4.2 (Issue #666)
;;;
;;; Implements:
;;;   1. Bi-directional task links (task-link!, task-unlink!, task-linked?)
;;;   2. Unidirectional monitors (task-monitor, task-demonitor)
;;;   3. EXIT signal cascade propagation and trap-exit management
;;;   4. Automatic channel poisoning on task crash
;;;   5. CWE-833 (Deadlock), CWE-362 (Race), CWE-400 (Limit), CWE-843 (Type) guards
;;; =======================================================================

;; -----------------------------------------------------------------------
;; 1. Configuration Constants & Reference Allocator
;; -----------------------------------------------------------------------

(define *max-task-links* 1024)       ; CWE-400 mitigation: upper limit on linked tasks
(define *max-task-monitors* 1024)    ; CWE-400 mitigation: upper limit on monitored tasks

(define *task-termination-registry-unregister-hook* (vector #f))

(define *monitor-next-id* (make-atomic-box 1))

(define (allocate-monitor-ref!)
  (atomic-fetch-add! *monitor-next-id* 1))

(define (monitor-next-id-current)
  (atomic-ref *monitor-next-id*))

(define (monitor-reset-next-id! val)
  (if (not (integer? val))
      (error "monitor-reset-next-id!: val must be an integer" val)
      (atomic-set! *monitor-next-id* val)))

;; -----------------------------------------------------------------------
;; 2. Bi-directional Task Links (DSN-37 Section 8.4.1)
;; -----------------------------------------------------------------------

(define (%add-to-atomic-list! box item max-limit err-msg)
  (let retry ()
    (let ((cur (atomic-ref box)))
      (if (eq? cur 'closed)
          'closed
          (if (memq item cur)
              #t
              (if (>= (length cur) max-limit)
                  (error err-msg (length cur))
                  (if (atomic-cas! box cur (cons item cur))
                      #t
                      (retry))))))))

(define (%remove-from-atomic-list! box item)
  (let retry ()
    (let ((cur (atomic-ref box)))
      (if (or (eq? cur 'closed) (not (list? cur)) (not (memq item cur)))
          #t
          (let ((new-list (let remove-item ((xs cur))
                            (cond ((null? xs) '())
                                  ((eq? (car xs) item) (cdr xs))
                                  (else (cons (car xs) (remove-item (cdr xs))))))))
            (if (atomic-cas! box cur new-list)
                #t
                (retry)))))))

(define (task-linked? task-a task-b)
  (if (or (not (task-context? task-a)) (not (task-context? task-b)))
      (error "task-linked?: expected <task-context>" (list task-a task-b))
      (if (eq? task-a task-b)
          #f
          (let ((links (task-links task-a)))
            (if (memq task-b links) #t #f)))))

(define (%try-register-link-atomic! target-task peer-task)
  (let ((box (task-links-box target-task)))
    (let retry ()
      (let ((cur (atomic-ref box)))
        (if (or (eq? cur 'closed) (eq? (task-state target-task) 'terminated))
            'closed
            (if (memq peer-task cur)
                #t
                (if (>= (length cur) *max-task-links*)
                    (error "task-link!: maximum task links limit exceeded (CWE-400)" (length cur))
                    (if (atomic-cas! box cur (cons peer-task cur))
                        #t
                        (retry)))))))))

(define (%notify-link-noproc! live-task dead-task)
  (if (task-trap-exit? live-task)
      (begin
        (task-set-handoff! live-task (list 'EXIT (task-tid dead-task) 'noproc))
        (task-wake! live-task #f))
      (task-handle-termination! live-task 'noproc #f)))

(define (task-link! task-a task-b)
  (if (or (not (task-context? task-a)) (not (task-context? task-b)))
      (error "task-link!: expected <task-context> (CWE-843)" (list task-a task-b))
      (if (eq? task-a task-b)
          #t
          ;; Atomic check-and-register on task-b, then task-a (Issue #725, Item B4)
          (let ((res-b (%try-register-link-atomic! task-b task-a)))
            (if (eq? res-b 'closed)
                (begin
                  (%notify-link-noproc! task-a task-b)
                  #t)
                (let ((res-a (%try-register-link-atomic! task-a task-b)))
                  (if (eq? res-a 'closed)
                      (begin
                        (%remove-from-atomic-list! (task-links-box task-b) task-a)
                        (%notify-link-noproc! task-b task-a)
                        #t)
                      #t)))))))

(define (task-unlink! task-a task-b)
  (if (or (not (task-context? task-a)) (not (task-context? task-b)))
      (error "task-unlink!: expected <task-context> (CWE-843)" (list task-a task-b))
      (if (eq? task-a task-b)
          #t
          (begin
            (%remove-from-atomic-list! (task-links-box task-a) task-b)
            (%remove-from-atomic-list! (task-links-box task-b) task-a)
            #t))))

;; -----------------------------------------------------------------------
;; 3. Unidirectional Monitors (DSN-37 Section 8.4.1)
;; -----------------------------------------------------------------------

(define *monitor-down-dispatch-hook-box* (make-atomic-box #f))

(define (set-monitor-down-dispatch-hook! proc)
  (atomic-set! *monitor-down-dispatch-hook-box* proc))

(define (%deliver-monitor-down! observer-task notify-channel ref target-tid reason wake-hook)
  (let ((down-msg (list 'DOWN ref 'process target-tid (channel-deep-copy reason))))
    (if (channel? notify-channel)
        (channel-try-send! notify-channel down-msg)
        (if (task-context? observer-task)
            (task-set-handoff! observer-task down-msg)))
    (if (and observer-task (task-context? observer-task))
        (begin
          (task-wake! observer-task wake-hook)
          (if (not (channel? notify-channel))
              (let ((dispatch-hook (atomic-ref *monitor-down-dispatch-hook-box*)))
                (if (procedure? dispatch-hook)
                    (dispatch-hook observer-task)
                    #f)))))))

(define task-monitor
  (case-lambda
    ((observer-task target-task)
     (task-monitor observer-task target-task #f))
    ((observer-task target-task notify-channel)
     (if (or (not (task-context? observer-task)) (not (task-context? target-task)))
         (error "task-monitor: expected <task-context> (CWE-843)" (list observer-task target-task))
         (if (and notify-channel (not (channel? notify-channel)))
             (error "task-monitor: expected <channel> or #f" notify-channel)
             (let ((ref (allocate-monitor-ref!))
                   (obs-box (task-monitors-box observer-task))
                   (target-box (task-monitored-by-box target-task)))
               ;; Step 1: Atomically check target liveness & register on target in a single CAS (Issue #725, Item B4)
               (let ((reg-status
                      (let retry-target ()
                        (let ((cur (atomic-ref target-box)))
                          (if (or (eq? cur 'closed) (eq? (task-state target-task) 'terminated))
                              'closed
                              (if (atomic-cas! target-box cur
                                               (cons (list ref (task-tid observer-task) notify-channel observer-task) cur))
                                  'registered
                                  (retry-target)))))))
                 (if (eq? reg-status 'closed)
                     ;; Target already terminated or closed registration: deliver 'noproc immediately
                     (begin
                       (%deliver-monitor-down! observer-task notify-channel ref (task-tid target-task) 'noproc #f)
                       ref)
                     (begin
                       ;; Step 2: Record monitor ref on observer for demonitor lookup
                       (let retry-obs ()
                         (let ((cur (atomic-ref obs-box)))
                           (if (not (list? cur))
                               #t
                               (if (>= (length cur) *max-task-monitors*)
                                   (error "task-monitor: maximum monitors limit exceeded (CWE-400)" (length cur))
                                   (if (atomic-cas! obs-box cur (cons (cons ref target-task) cur))
                                       #t
                                       (retry-obs))))))
                       ref)))))))))

(define (task-demonitor observer-task ref)
  (if (not (task-context? observer-task))
      (error "task-demonitor: expected <task-context>" observer-task)
      (if (not (integer? ref))
          (error "task-demonitor: ref must be an integer (CWE-843)" ref)
          (let* ((obs-box (task-monitors-box observer-task))
                 (found-target
                  (let retry ()
                    (let ((cur (atomic-ref obs-box)))
                      (if (not (list? cur))
                          #f
                          (let ((entry (assq ref cur)))
                            (if (not entry)
                                #f
                                (let ((new-list (let remove-ref ((xs cur))
                                                  (cond ((null? xs) '())
                                                        ((eqv? (car (car xs)) ref) (cdr xs))
                                                        (else (cons (car xs) (remove-ref (cdr xs))))))))
                                  (if (atomic-cas! obs-box cur new-list)
                                      (cdr entry)
                                      (retry))))))))))
            (if (and found-target (task-context? found-target))
                ;; Also clean up on target if not yet closed
                (let* ((target-box (task-monitored-by-box found-target)))
                  (let retry-target ()
                    (let ((cur (atomic-ref target-box)))
                      (if (not (list? cur))
                          #t
                          (let ((new-list (let remove-target-ref ((xs cur))
                                            (cond ((null? xs) '())
                                                  ((eqv? (car (car xs)) ref) (cdr xs))
                                                  (else (cons (car xs) (remove-target-ref (cdr xs))))))))
                            (if (atomic-cas! target-box cur new-list)
                                #t
                                (retry-target)))))))
                #t)
            #t))))

;; -----------------------------------------------------------------------
;; 4. Termination & Signal Cascade Propagation (DSN-37 Section 8.4.1 & 8.4.2)
;; -----------------------------------------------------------------------

(define task-handle-termination!
  (case-lambda
    ((task reason)
     (task-handle-termination! task reason #f))
    ((task reason wake-hook)
     (if (not (task-context? task))
         (error "task-handle-termination!: expected <task-context>" task)
         ;; Deep-copy exit reason before notifying monitors/links or resetting task arena (Issue #724, Item B5)
         (let ((safe-reason (channel-deep-copy reason)))
           ;; Mark task state as terminated and zero out reductions so it exits at next safepoint (Issue #723, Item B6)
           (task-state-set! task 'terminated)
           (task-reductions-set! task 0)

           ;; Step 1: Cleanup owned channels: Graceful Close if normal, Poison if crash (Issue #752)
           (task-cleanup-owned-channels! task safe-reason wake-hook)

           ;; Step 2: Atomically close monitor registration ('closed) before dispatching 'DOWN (Issue #725, Item B4)
           (let ((monitors (atomic-swap! (task-monitored-by-box task) 'closed)))
             (if (list? monitors)
                 (let notify-loop ((ms monitors))
                   (if (null? ms)
                       #t
                       (let* ((entry (car ms))
                              (ref (car entry))
                              (target-tid (task-tid task))
                              (ch (caddr entry))
                              (obs-task (cadddr entry)))
                         (%deliver-monitor-down! obs-task ch ref target-tid safe-reason wake-hook)
                         (notify-loop (cdr ms)))))
                 #t))

           ;; Step 3: Atomically close link registration ('closed) before propagating EXIT signals (Issue #725, Item B4)
           (let ((links (atomic-swap! (task-links-box task) 'closed)))
             (if (list? links)
                 (let propagate-loop ((ls links))
                   (if (null? ls)
                       #t
                       (let ((linked (car ls)))
                         ;; Unlink the other direction to break cycles
                         (%remove-from-atomic-list! (task-links-box linked) task)

                         (if (task-trap-exit? linked)
                             ;; Trapped: deliver EXIT message with deep-copied reason without killing linked task
                             (let ((exit-msg (list 'EXIT (task-tid task) (channel-deep-copy safe-reason))))
                               (task-set-handoff! linked exit-msg)
                               (task-wake! linked wake-hook))
                             ;; Not trapped: check reason
                             (if (eq? safe-reason 'normal)
                                 ;; Normal exit does not kill linked tasks
                                 #t
                                 ;; Abnormal exit: cascade kill linked task!
                                 (task-handle-termination! linked (channel-deep-copy safe-reason) wake-hook)))
                         (propagate-loop (cdr ls)))))
                 #t))

           ;; Step 4: Auto-unregister from process registry (Issue #730, Item C5)
           (let ((unreg-hook (vector-ref *task-termination-registry-unregister-hook* 0)))
             (if (procedure? unreg-hook)
                 (unreg-hook task)
                 #t))

           ;; Step 5: Auto-unregister from global task table (Issue #733, Item B2)
           (task-table-unregister! task)
           #t)))))

(define task-exit!
  (case-lambda
    ((task) (task-exit! task 'normal #f))
    ((task reason) (task-exit! task reason #f))
    ((task reason wake-hook)
     (task-handle-termination! task reason wake-hook))))

;; Connect task-handle-termination! into global exit hook box (#741)
(vector-set! *task-exit-hook-box* 0
  (lambda (task reason)
    (task-handle-termination! task reason #f)))
