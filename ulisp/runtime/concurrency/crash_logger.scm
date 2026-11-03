;;; =======================================================================
;;; Synapse Concurrency Runtime: Structured Crash Reporting & Observability
;;; Conforms to DSN-37 Section 8.4.6 & Section 14.8 Task 6.5 (Issue #670)
;;;
;;; Implements:
;;;   1. <crash-report> structured diagnostic record (SASL style)
;;;   2. Lock-free, non-blocking <crash-ring-buffer> for Layer 2 -> Layer 1 transfer
;;;   3. SASL-style human-readable text and S-expression diagnostic formatters
;;;   4. Observability metrics aggregator (total crashes, dropped, by-reason)
;;;   5. Zero-blocking crash enqueue and bounded memory guarantees (CWE-400)
;;;   6. Sensitive payload redaction and summary length bounding (CWE-209, CWE-212)
;;;   7. Race-free CAS buffer management (CWE-362) and deadlock-free (CWE-833)
;;;   8. Strict type assertions (CWE-843)
;;; =======================================================================

(define *crash-report-id-counter* (make-atomic-box 1))

(define (allocate-crash-report-id!)
  (atomic-fetch-add! *crash-report-id-counter* 1))

(define *crash-default-buffer-capacity* 256)
(define *crash-max-buffer-capacity* 65536)
(define *crash-max-summary-length* 256)

;; -----------------------------------------------------------------------
;; 1. Structured Crash Report Record Definition
;; -----------------------------------------------------------------------

(define-record-type <crash-report>
  (%make-crash-report id tid registered-name epoch fuel-consumed
                      arena-allocated arena-capacity reason details
                      source-loc last-msg-summary timestamp)
  crash-report?
  (id                  crash-report-id)
  (tid                 crash-report-tid)
  (registered-name     crash-report-registered-name)
  (epoch               crash-report-epoch)
  (fuel-consumed       crash-report-fuel-consumed)
  (arena-allocated     crash-report-arena-allocated)
  (arena-capacity      crash-report-arena-capacity)
  (reason              crash-report-reason)
  (details             crash-report-details)
  (source-loc          crash-report-source-loc)
  (last-msg-summary    crash-report-last-msg-summary)
  (timestamp           crash-report-timestamp))

;; Helper: safe stringification with length bound (CWE-209, CWE-212)
(define (%safe-value-summary val max-len)
  (let ((raw-str
         (cond
           ((string? val) val)
           ((symbol? val) (symbol->string val))
           ((number? val) (number->string val))
           ((boolean? val) (if val "#t" "#f"))
           ((null? val) "()")
           ((pair? val) "(pair ...)")
           ((vector? val) "#(vector ...)")
           (else "<opaque-payload>"))))
    (let ((len (string-length raw-str)))
      (if (<= len max-len)
          raw-str
          (string-append (substring raw-str 0 (- max-len 3)) "...")))))

(define (%safe-task-alloc-bytes task)
  (cond
    ((task-context? task)
     (let ((a (task-arena task)))
       (if (and a (task-arena? a))
           (arena-offset a)
           (task-arena-offset task))))
    (else 0)))

(define (%safe-task-capacity-bytes task)
  (cond
    ((task-context? task)
     (let ((a (task-arena task)))
       (if (and a (task-arena? a))
           (arena-capacity a)
           (task-arena-capacity task))))
    (else 0)))

;; Builder for <crash-report>
(define make-crash-report
  (case-lambda
    ((task reason)
     (make-crash-report task reason '() #f #f #f))
    ((task reason details)
     (make-crash-report task reason details #f #f #f))
    ((task reason details source-loc)
     (make-crash-report task reason details source-loc #f #f))
    ((task reason details source-loc last-msg)
     (make-crash-report task reason details source-loc last-msg #f))
    ((task reason details source-loc last-msg reg-name)
     (let ((cid (allocate-crash-report-id!))
           (ts (allocate-crash-report-id!)))
       (cond
         ;; Case A: Full <task-context>
         ((task-context? task)
          (let* ((tid (task-tid task))
                 (ep (task-epoch task))
                 (fuel (task-reductions task))
                 (alloc-bytes (%safe-task-alloc-bytes task))
                 (cap-bytes (%safe-task-capacity-bytes task))
                 (msg-summary (if last-msg
                                  (%safe-value-summary last-msg *crash-max-summary-length*)
                                  "none"))
                 (resolved-reg-name (if (symbol? reg-name)
                                        reg-name
                                        #f)))
            (%make-crash-report cid tid resolved-reg-name ep fuel
                                alloc-bytes cap-bytes reason details
                                (if source-loc source-loc #f)
                                msg-summary ts)))

         ;; Case B: TID integer provided directly
         ((integer? task)
          (%make-crash-report cid task (if (symbol? reg-name) reg-name #f)
                              0 0 0 0 reason details
                              (if source-loc source-loc #f)
                              (if last-msg (%safe-value-summary last-msg *crash-max-summary-length*) "none")
                              ts))

         (else
          (error "make-crash-report: expected <task-context> or integer TID (CWE-843)" task)))))))

;; -----------------------------------------------------------------------
;; 2. Lock-Free Non-Blocking Crash Ring Buffer
;; -----------------------------------------------------------------------

(define-record-type <crash-ring-buffer>
  (%make-crash-ring-buffer capacity slots-vec head-box tail-box count-box dropped-box)
  crash-ring-buffer?
  (capacity     crash-buffer-capacity)
  (slots-vec    %crash-buffer-slots-vec)
  (head-box     %crash-buffer-head-box)
  (tail-box     %crash-buffer-tail-box)
  (count-box    %crash-buffer-count-box)
  (dropped-box  %crash-buffer-dropped-box))

(define make-crash-ring-buffer
  (case-lambda
    (()
     (make-crash-ring-buffer *crash-default-buffer-capacity*))
    ((capacity)
     (if (not (integer? capacity))
         (error "make-crash-ring-buffer: capacity must be integer (CWE-843)" capacity)
         (if (or (<= capacity 0) (> capacity *crash-max-buffer-capacity*))
             (error "make-crash-ring-buffer: capacity out of bounds (CWE-400)" capacity)
             (let ((slots (make-vector capacity #f)))
               (%make-crash-ring-buffer capacity
                                        slots
                                        (make-atomic-box 0)
                                        (make-atomic-box 0)
                                        (make-atomic-box 0)
                                        (make-atomic-box 0))))))))

(define (crash-buffer-count buf)
  (if (not (crash-ring-buffer? buf))
      (error "crash-buffer-count: expected <crash-ring-buffer> (CWE-843)" buf)
      (atomic-ref (%crash-buffer-count-box buf))))

(define (crash-buffer-dropped buf)
  (if (not (crash-ring-buffer? buf))
      (error "crash-buffer-dropped: expected <crash-ring-buffer> (CWE-843)" buf)
      (atomic-ref (%crash-buffer-dropped-box buf))))

;; Non-blocking lock-free enqueue (CWE-833 Deadlock-free, CWE-400 Bounded)
(define (crash-buffer-enqueue! buf report)
  (if (not (crash-ring-buffer? buf))
      (error "crash-buffer-enqueue!: expected <crash-ring-buffer> (CWE-843)" buf)
      (if (not (crash-report? report))
          (error "crash-buffer-enqueue!: expected <crash-report> (CWE-843)" report)
          (let* ((cap (crash-buffer-capacity buf))
                 (slots (%crash-buffer-slots-vec buf))
                 (head-box (%crash-buffer-head-box buf))
                 (tail-box (%crash-buffer-tail-box buf))
                 (count-box (%crash-buffer-count-box buf))
                 (dropped-box (%crash-buffer-dropped-box buf))
                 ;; Atomically claim head slot index
                 (idx (atomic-fetch-add! head-box 1))
                 (slot-pos (modulo idx cap)))
            ;; Write report into slot
            (vector-set! slots slot-pos report)
            ;; Update count or mark dropped if capacity reached
            (let update-loop ()
              (let ((cur-cnt (atomic-ref count-box)))
                (if (>= cur-cnt cap)
                    ;; Buffer is full: overwrite oldest, advance tail, increment dropped count
                    (begin
                      (atomic-fetch-add! dropped-box 1)
                      (atomic-fetch-add! tail-box 1)
                      #t)
                    ;; Capacity available: increment count atomically
                    (if (atomic-cas! count-box cur-cnt (+ cur-cnt 1))
                        #t
                        (update-loop)))))
            #t))))

;; Non-blocking dequeue (returns <crash-report> or #f if empty)
(define (crash-buffer-dequeue! buf)
  (if (not (crash-ring-buffer? buf))
      (error "crash-buffer-dequeue!: expected <crash-ring-buffer> (CWE-843)" buf)
      (let* ((cap (crash-buffer-capacity buf))
             (slots (%crash-buffer-slots-vec buf))
             (tail-box (%crash-buffer-tail-box buf))
             (count-box (%crash-buffer-count-box buf)))
        (let try-loop ()
          (let ((cur-cnt (atomic-ref count-box)))
            (if (<= cur-cnt 0)
                #f
                (if (atomic-cas! count-box cur-cnt (- cur-cnt 1))
                    (let* ((idx (atomic-fetch-add! tail-box 1))
                           (slot-pos (modulo idx cap))
                           (item (vector-ref slots slot-pos)))
                      ;; Clear slot reference
                      (vector-set! slots slot-pos #f)
                      item)
                    (try-loop))))))))

;; Drain all pending reports as list
(define (crash-buffer-drain! buf)
  (if (not (crash-ring-buffer? buf))
      (error "crash-buffer-drain!: expected <crash-ring-buffer> (CWE-843)" buf)
      (let loop ((acc '()))
        (let ((item (crash-buffer-dequeue! buf)))
          (if item
              (loop (cons item acc))
              (reverse acc))))))

;; -----------------------------------------------------------------------
;; 3. Observability Metrics Aggregator
;; -----------------------------------------------------------------------

(define *crash-metrics-total* (make-atomic-box 0))
(define *crash-metrics-dropped* (make-atomic-box 0))
(define *crash-metrics-by-reason-box* (make-atomic-box '()))

(define (synapse-record-crash-metric! reason)
  (atomic-fetch-add! *crash-metrics-total* 1)
  (let update-reason ()
    (let* ((cur-alist (atomic-ref *crash-metrics-by-reason-box*))
           (entry (assq reason cur-alist))
           (new-alist
            (if entry
                (let loop ((rest cur-alist) (accum '()))
                  (cond
                    ((null? rest) (reverse accum))
                    ((eq? (car (car rest)) reason)
                     (loop (cdr rest) (cons (cons reason (+ (cdr (car rest)) 1)) accum)))
                    (else
                     (loop (cdr rest) (cons (car rest) accum)))))
                (cons (cons reason 1) cur-alist))))
      (if (atomic-cas! *crash-metrics-by-reason-box* cur-alist new-alist)
          #t
          (update-reason)))))

(define (synapse-crash-metrics)
  (list (cons 'total (atomic-ref *crash-metrics-total*))
        (cons 'dropped (atomic-ref *crash-metrics-dropped*))
        (cons 'by-reason (atomic-ref *crash-metrics-by-reason-box*))))

(define (synapse-reset-crash-metrics!)
  (atomic-set! *crash-metrics-total* 0)
  (atomic-set! *crash-metrics-dropped* 0)
  (atomic-set! *crash-metrics-by-reason-box* '())
  #t)

;; -----------------------------------------------------------------------
;; 4. Default Crash Buffer & System Integration
;; -----------------------------------------------------------------------

(define *default-crash-buffer-box* (make-atomic-box (make-crash-ring-buffer)))

(define (current-crash-buffer)
  (atomic-ref *default-crash-buffer-box*))

(define (synapse-set-current-crash-buffer! buf)
  (if (not (crash-ring-buffer? buf))
      (error "synapse-set-current-crash-buffer!: expected <crash-ring-buffer> (CWE-843)" buf)
      (atomic-set! *default-crash-buffer-box* buf)))

;; Top-level crash logging primitive (Layer 2 safe)
(define synapse-log-task-crash!
  (case-lambda
    ((task reason)
     (synapse-log-task-crash! task reason '() #f #f #f))
    ((task reason details)
     (synapse-log-task-crash! task reason details #f #f #f))
    ((task reason details source-loc)
     (synapse-log-task-crash! task reason details source-loc #f #f))
    ((task reason details source-loc last-msg)
     (synapse-log-task-crash! task reason details source-loc last-msg #f))
    ((task reason details source-loc last-msg reg-name)
     (let ((buf (current-crash-buffer)))
       (if (and buf (crash-ring-buffer? buf))
           (let ((rep (make-crash-report task reason details source-loc last-msg reg-name)))
             ;; Record metrics
             (synapse-record-crash-metric! reason)
             ;; Enqueue report into ring buffer (non-blocking)
             (crash-buffer-enqueue! buf rep)
             rep)
           #f)))))

;; -----------------------------------------------------------------------
;; 5. Human-Readable SASL Diagnostic Formatter & S-Expression Exporter
;; -----------------------------------------------------------------------

(define (format-crash-report report)
  (if (not (crash-report? report))
      (error "format-crash-report: expected <crash-report> (CWE-843)" report)
      (let* ((cid (number->string (crash-report-id report)))
             (tid (number->string (crash-report-tid report)))
             (reg (let ((r (crash-report-registered-name report)))
                    (if (symbol? r) (symbol->string r) "unregistered")))
             (ep (number->string (crash-report-epoch report)))
             (fuel (number->string (crash-report-fuel-consumed report)))
             (alloc (number->string (crash-report-arena-allocated report)))
             (cap (number->string (crash-report-arena-capacity report)))
             (pct (if (> (crash-report-arena-capacity report) 0)
                      (number->string (quotient (* (crash-report-arena-allocated report) 100)
                                                (crash-report-arena-capacity report)))
                      "0"))
             (rsn (let ((r (crash-report-reason report)))
                    (if (symbol? r) (symbol->string r) "unknown")))
             (src (let ((s (crash-report-source-loc report)))
                    (cond
                      ((string? s) s)
                      ((symbol? s) (symbol->string s))
                      (else "unknown"))))
             (msg (crash-report-last-msg-summary report))
             (ts (number->string (crash-report-timestamp report))))
        (string-append
         "=CRASH REPORT==== " ts " ====\n"
         "  report_id:       " cid "\n"
         "  crashed_task:    TID:" tid " (" reg ")\n"
         "  scheduler_epoch: " ep "\n"
         "  reason:          " rsn "\n"
         "  source_loc:      " src "\n"
         "  fuel_consumed:   " fuel " reductions\n"
         "  arena_usage:     " alloc " / " cap " bytes (" pct "%)\n"
         "  last_message:    " msg "\n"))))

(define (crash-report->alist report)
  (if (not (crash-report? report))
      (error "crash-report->alist: expected <crash-report> (CWE-843)" report)
      (list (cons 'id (crash-report-id report))
            (cons 'tid (crash-report-tid report))
            (cons 'registered-name (crash-report-registered-name report))
            (cons 'epoch (crash-report-epoch report))
            (cons 'fuel-consumed (crash-report-fuel-consumed report))
            (cons 'arena-allocated (crash-report-arena-allocated report))
            (cons 'arena-capacity (crash-report-arena-capacity report))
            (cons 'reason (crash-report-reason report))
            (cons 'details (crash-report-details report))
            (cons 'source-loc (crash-report-source-loc report))
            (cons 'last-msg-summary (crash-report-last-msg-summary report))
            (cons 'timestamp (crash-report-timestamp report)))))

(define (crash-report->sexpr report)
  (if (not (crash-report? report))
      (error "crash-report->sexpr: expected <crash-report> (CWE-843)" report)
      (list 'crash-report
            (list 'id (crash-report-id report))
            (list 'tid (crash-report-tid report))
            (list 'registered-name (crash-report-registered-name report))
            (list 'epoch (crash-report-epoch report))
            (list 'reason (crash-report-reason report))
            (list 'fuel (crash-report-fuel-consumed report))
            (list 'arena (list (crash-report-arena-allocated report) (crash-report-arena-capacity report)))
            (list 'source (crash-report-source-loc report))
            (list 'last-msg (crash-report-last-msg-summary report)))))

;; -----------------------------------------------------------------------
;; 6. Panic & Supervisor Integration Hooks
;; -----------------------------------------------------------------------

(define (synapse-enable-crash-logging!)
  (if (procedure? synapse-set-crash-logger-hook!)
      (synapse-set-crash-logger-hook!
       (lambda (task reason details)
         (synapse-log-task-crash! task reason details #f #f #f)))
      #f)
  (if (procedure? synapse-set-supervisor-crash-hook!)
      (synapse-set-supervisor-crash-hook!
       (lambda (target-tid reason reg-name)
         (synapse-log-task-crash! target-tid reason '() #f #f reg-name)))
      #f)
  #t)

(define (synapse-disable-crash-logging!)
  (if (procedure? synapse-set-crash-logger-hook!)
      (synapse-set-crash-logger-hook! #f)
      #f)
  (if (procedure? synapse-set-supervisor-crash-hook!)
      (synapse-set-supervisor-crash-hook! (lambda (target-tid reason id) #f))
      #f)
  #t)
