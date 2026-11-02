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
      (if (memq item cur)
          #t
          (if (>= (length cur) max-limit)
              (error err-msg (length cur))
              (if (atomic-cas! box cur (cons item cur))
                  #t
                  (retry)))))))

(define (%remove-from-atomic-list! box item)
  (let retry ()
    (let ((cur (atomic-ref box)))
      (if (not (memq item cur))
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

(define (task-link! task-a task-b)
  (if (or (not (task-context? task-a)) (not (task-context? task-b)))
      (error "task-link!: expected <task-context> (CWE-843)" (list task-a task-b))
      (if (eq? task-a task-b)
          #t
          (begin
            ;; Check if either task is already terminated
            (if (eq? (task-state task-b) 'terminated)
                (begin
                  (task-handle-termination! task-b 'noproc #f)
                  #t)
                (if (eq? (task-state task-a) 'terminated)
                    (begin
                      (task-handle-termination! task-a 'noproc #f)
                      #t)
                    (begin
                      (%add-to-atomic-list! (task-links-box task-a) task-b *max-task-links*
                                            "task-link!: maximum task links limit exceeded (CWE-400)")
                      (%add-to-atomic-list! (task-links-box task-b) task-a *max-task-links*
                                            "task-link!: maximum task links limit exceeded (CWE-400)")
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
               ;; Check if target is already dead
               (if (eq? (task-state target-task) 'terminated)
                   (begin
                     (if notify-channel
                         (channel-try-send! notify-channel (list 'DOWN ref 'process (task-tid target-task) 'noproc)))
                     ref)
                   (begin
                     ;; Register on observer: (cons ref target-task)
                     (let retry-obs ()
                       (let ((cur (atomic-ref obs-box)))
                         (if (>= (length cur) *max-task-monitors*)
                             (error "task-monitor: maximum monitors limit exceeded (CWE-400)" (length cur))
                             (if (atomic-cas! obs-box cur (cons (cons ref target-task) cur))
                                 #t
                                 (retry-obs)))))
                     ;; Register on target: (list ref (task-tid observer-task) notify-channel observer-task)
                     (let retry-target ()
                       (let ((cur (atomic-ref target-box)))
                         (if (atomic-cas! target-box cur (cons (list ref (task-tid observer-task) notify-channel observer-task) cur))
                             #t
                             (retry-target))))
                     ref))))))))

(define (task-demonitor observer-task ref)
  (if (not (task-context? observer-task))
      (error "task-demonitor: expected <task-context>" observer-task)
      (if (not (integer? ref))
          (error "task-demonitor: ref must be an integer (CWE-843)" ref)
          (let* ((obs-box (task-monitors-box observer-task))
                 (found-target
                  (let retry ()
                    (let ((cur (atomic-ref obs-box)))
                      (let ((entry (assq ref cur)))
                        (if (not entry)
                            #f
                            (let ((new-list (let remove-ref ((xs cur))
                                              (cond ((null? xs) '())
                                                    ((eqv? (car (car xs)) ref) (cdr xs))
                                                    (else (cons (car xs) (remove-ref (cdr xs))))))))
                              (if (atomic-cas! obs-box cur new-list)
                                  (cdr entry)
                                  (retry)))))))))
            (if (and found-target (task-context? found-target))
                ;; Also clean up on target
                (let* ((target-box (task-monitored-by-box found-target)))
                  (let retry-target ()
                    (let ((cur (atomic-ref target-box)))
                      (let ((new-list (let remove-target-ref ((xs cur))
                                        (cond ((null? xs) '())
                                              ((eqv? (car (car xs)) ref) (cdr xs))
                                              (else (cons (car xs) (remove-target-ref (cdr xs))))))))
                        (if (atomic-cas! target-box cur new-list)
                            #t
                            (retry-target))))))
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
         (begin
           ;; Mark task state as terminated
           (task-state-set! task 'terminated)

           ;; Step 1: Poison all owned channels (CWE-833 Deadlock Prevention)
           (task-poison-owned-channels! task reason wake-hook)

           ;; Step 2: Notify all unidirectional monitors with 'DOWN message
           (let ((monitors (atomic-swap! (task-monitored-by-box task) '())))
             (let notify-loop ((ms monitors))
               (if (null? ms)
                   #t
                   (let* ((entry (car ms))
                          (ref (car entry))
                          (target-tid (task-tid task))
                          (ch (caddr entry))
                          (obs-task (cadddr entry))
                          (down-msg (list 'DOWN ref 'process target-tid reason)))
                     (if (channel? ch)
                         (channel-try-send! ch down-msg)
                         (if (task-context? obs-task)
                             (task-set-handoff! obs-task down-msg)))
                     (if (and obs-task (task-context? obs-task))
                         (task-wake! obs-task wake-hook))
                     (notify-loop (cdr ms))))))

           ;; Step 3: Propagate EXIT signals across bi-directional links
           (let ((links (atomic-swap! (task-links-box task) '())))
             (let propagate-loop ((ls links))
               (if (null? ls)
                   #t
                   (let ((linked (car ls)))
                     ;; Unlink the other direction to break cycles
                     (%remove-from-atomic-list! (task-links-box linked) task)

                     (if (task-trap-exit? linked)
                         ;; Trapped: deliver EXIT message without killing linked task
                         (let ((exit-msg (list 'EXIT (task-tid task) reason)))
                           (task-set-handoff! linked exit-msg)
                           (task-wake! linked wake-hook))
                         ;; Not trapped: check reason
                         (if (eq? reason 'normal)
                             ;; Normal exit does not kill linked tasks
                             #t
                             ;; Abnormal exit: cascade kill linked task!
                             (task-handle-termination! linked reason wake-hook)))
                     (propagate-loop (cdr ls))))))
           #t)))))

(define task-exit!
  (case-lambda
    ((task) (task-exit! task 'normal #f))
    ((task reason) (task-exit! task reason #f))
    ((task reason wake-hook)
     (task-handle-termination! task reason wake-hook))))
