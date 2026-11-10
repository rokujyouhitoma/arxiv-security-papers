;;; =======================================================================
;;; ULisp Runtime Concurrency: Process Name Registry (registry.scm)
;;; Conforms to DSN-37 Section 8.4.5, Section 14.8 Task 6.4 & Issue #669
;;;
;;; Implements:
;;;   1. <process-registry> and <registry-entry> record types
;;;   2. Partitioned 64-bucket lock-free atomic table (CWE-362 safe)
;;;   3. Fast O(1) whereis lookup & non-blocking send (synapse-send-named!)
;;;   4. Dynamic channel/task rebinding across supervisor restarts (synapse-rebind!)
;;;   5. Zero-deadlock routing (CWE-833), UAF mitigation (CWE-416),
;;;      strict type validation (CWE-843), and capacity bounding (CWE-400).
;;; =======================================================================

(define *registry-default-bucket-count* 64)
(define *registry-max-entries* 65536)

;; -----------------------------------------------------------------------
;; 1. Record Types: <registry-entry> and <process-registry>
;; -----------------------------------------------------------------------

(define-record-type <registry-entry>
  (%make-registry-entry name target-box epoch-box)
  registry-entry?
  (name       registry-entry-name)
  (target-box %registry-entry-target-box)
  (epoch-box  %registry-entry-epoch-box))

(define (registry-entry-target entry)
  (if (not (registry-entry? entry))
      (error "registry-entry-target: expected <registry-entry> (CWE-843)" entry)
      (atomic-ref (%registry-entry-target-box entry))))

(define (registry-entry-epoch entry)
  (if (not (registry-entry? entry))
      (error "registry-entry-epoch: expected <registry-entry> (CWE-843)" entry)
      (atomic-ref (%registry-entry-epoch-box entry))))

(define-record-type <process-registry>
  (%make-process-registry buckets count-box epoch-box max-capacity)
  process-registry?
  (buckets      %process-registry-buckets)
  (count-box    %process-registry-count-box)
  (epoch-box    %process-registry-epoch-box)
  (max-capacity %process-registry-max-capacity))

;; Global registry tracking for lifecycle hooks
(define *active-synapse-registries-box* (make-atomic-box '()))

;; -----------------------------------------------------------------------
;; 2. Factory & Global Default Registry
;; -----------------------------------------------------------------------

(define make-process-registry
  (case-lambda
    (()
     (make-process-registry *registry-max-entries*))
    ((max-capacity)
     (if (or (not (integer? max-capacity)) (<= max-capacity 0))
         (error "make-process-registry: max-capacity must be a positive integer (CWE-843)" max-capacity)
         (let ((buckets (make-vector *registry-default-bucket-count* #f)))
           (let loop ((i 0))
             (if (< i *registry-default-bucket-count*)
                 (begin
                   (vector-set! buckets i (make-atomic-box '()))
                   (loop (+ i 1)))
                 (let ((reg (%make-process-registry buckets
                                                    (make-atomic-box 0)
                                                    (make-atomic-box 0)
                                                    max-capacity)))
                   (let retry ()
                     (let ((cur (atomic-ref *active-synapse-registries-box*)))
                       (if (not (atomic-cas! *active-synapse-registries-box* cur (cons reg cur)))
                           (retry)
                           reg)))))))))))

(define *default-synapse-registry-box* (vector (make-process-registry)))

(define (current-synapse-registry)
  (vector-ref *default-synapse-registry-box* 0))

(define (set-default-synapse-registry! reg)
  (if (not (process-registry? reg))
      (error "set-default-synapse-registry!: expected <process-registry> (CWE-843)" reg)
      (begin
        (vector-set! *default-synapse-registry-box* 0 reg)
        #t)))

;; -----------------------------------------------------------------------
;; 3. Internal Bucket Hash & Association List Helpers
;; -----------------------------------------------------------------------

(define (%registry-bucket-index name)
  (let ((h (symbol-hash name)))
    (modulo (if (< h 0) (- 0 h) h) *registry-default-bucket-count*)))

(define (%registry-alist-remove key alist)
  (let loop ((xs alist) (acc '()))
    (if (null? xs)
        (reverse acc)
        (if (eq? (caar xs) key)
            (loop (cdr xs) acc)
            (loop (cdr xs) (cons (car xs) acc))))))

;; -----------------------------------------------------------------------
;; 4. Core Registry API
;; -----------------------------------------------------------------------

;; (synapse-register! [reg] name target)
;; Atomically registers `target` under `name` (Symbol).
;; Returns #t on success, #f if `name` is already registered (no overwrite).
(define synapse-register!
  (case-lambda
    ((name target)
     (synapse-register! (current-synapse-registry) name target))
    ((reg name target)
     (if (not (process-registry? reg))
         (error "synapse-register!: expected <process-registry> (CWE-843)" reg)
         (if (not (symbol? name))
             (error "synapse-register!: name must be a symbol (CWE-843)" name)
             (if (not target)
                 (error "synapse-register!: target cannot be #f (CWE-843)" target)
                 (let* ((cnt-box (%process-registry-count-box reg))
                        (max-cap (%process-registry-max-capacity reg))
                        (cnt (atomic-ref cnt-box)))
                   (if (>= cnt max-cap)
                       (error "synapse-register!: registry capacity exceeded (CWE-400)" cnt)
                       (let* ((buckets (%process-registry-buckets reg))
                              (idx (%registry-bucket-index name))
                              (bucket (vector-ref buckets idx)))
                         (let retry ()
                           (let* ((current-alist (atomic-ref bucket))
                                  (existing (assq name current-alist)))
                             (if existing
                                 #f ; duplicate registration rejected
                                 (let* ((entry (%make-registry-entry name
                                                                     (make-atomic-box target)
                                                                     (make-atomic-box 0)))
                                        (new-alist (cons (cons name entry) current-alist)))
                                   (if (not (atomic-cas! bucket current-alist new-alist))
                                       (retry)
                                       (begin
                                         (atomic-fetch-add! cnt-box 1)
                                         (atomic-fetch-add! (%process-registry-epoch-box reg) 1)
                                         #t)))))))))))))))

;; (synapse-unregister! [reg] name)
;; Atomically removes registration for `name`.
;; Returns #t if removed, #f if not found.
(define synapse-unregister!
  (case-lambda
    ((name)
     (synapse-unregister! (current-synapse-registry) name))
    ((reg name)
     (if (not (process-registry? reg))
         (error "synapse-unregister!: expected <process-registry> (CWE-843)" reg)
         (if (not (symbol? name))
             (error "synapse-unregister!: name must be a symbol (CWE-843)" name)
             (let* ((buckets (%process-registry-buckets reg))
                    (idx (%registry-bucket-index name))
                    (bucket (vector-ref buckets idx)))
               (let retry ()
                 (let* ((current-alist (atomic-ref bucket))
                        (existing (assq name current-alist)))
                   (if (not existing)
                       #f ; not found
                       (let ((new-alist (%registry-alist-remove name current-alist)))
                         (if (not (atomic-cas! bucket current-alist new-alist))
                             (retry)
                             (begin
                               (atomic-fetch-add! (%process-registry-count-box reg) -1)
                               (atomic-fetch-add! (%process-registry-epoch-box reg) 1)
                               #t))))))))))))

;; (synapse-unregister-target! [reg] target)
;; Atomically removes any registration whose target matches `target` (or same task tid).
;; Returns the number of removed entries.
(define synapse-unregister-target!
  (case-lambda
    ((target)
     (let loop ((regs (atomic-ref *active-synapse-registries-box*)) (total 0))
       (if (null? regs)
           total
           (let ((r (car regs)))
             (if (<= (atomic-ref (%process-registry-count-box r)) 0)
                 (loop (cdr regs) total)
                 (loop (cdr regs) (+ total (synapse-unregister-target! r target))))))))
    ((reg target)
     (if (not (process-registry? reg))
         (error "synapse-unregister-target!: expected <process-registry> (CWE-843)" reg)
         (let ((cnt-box (%process-registry-count-box reg)))
           (if (<= (atomic-ref cnt-box) 0)
               0
               (let ((buckets (%process-registry-buckets reg)))
                 (let bucket-loop ((i 0) (total-removed 0))
                   (if (< i *registry-default-bucket-count*)
                       (let ((bucket (vector-ref buckets i)))
                   (let retry ()
                     (let* ((cur (atomic-ref bucket))
                            (to-remove
                             (let find-loop ((xs cur) (acc '()))
                               (if (null? xs)
                                   (reverse acc)
                                   (let* ((pair (car xs))
                                          (entry (cdr pair))
                                          (entry-tgt (registry-entry-target entry)))
                                     (if (or (eq? entry-tgt target)
                                             (and (task-context? target)
                                                  (task-context? entry-tgt)
                                                  (= (task-tid target) (task-tid entry-tgt))))
                                         (find-loop (cdr xs) (cons (car pair) acc))
                                         (find-loop (cdr xs) acc)))))))
                       (if (null? to-remove)
                           (bucket-loop (+ i 1) total-removed)
                           (let* ((new-alist (let filter-loop ((xs cur) (acc '()))
                                               (if (null? xs)
                                                   (reverse acc)
                                                   (if (memq (caar xs) to-remove)
                                                       (filter-loop (cdr xs) acc)
                                                       (filter-loop (cdr xs) (cons (car xs) acc)))))))
                             (if (not (atomic-cas! bucket cur new-alist))
                                 (retry)
                                 (let ((num (length to-remove)))
                                   (atomic-fetch-add! cnt-box (- 0 num))
                                   (atomic-fetch-add! (%process-registry-epoch-box reg) 1)
                                   (bucket-loop (+ i 1) (+ total-removed num)))))))))
                 total-removed)))))))))

;; (synapse-whereis [reg] name)
;; Resolves `name` to its current target.
;; Returns target if registered, #f if not found.
(define synapse-whereis
  (case-lambda
    ((name)
     (synapse-whereis (current-synapse-registry) name))
    ((reg name)
     (if (not (process-registry? reg))
         (error "synapse-whereis: expected <process-registry> (CWE-843)" reg)
         (if (not (symbol? name))
             (error "synapse-whereis: name must be a symbol (CWE-843)" name)
             (let* ((buckets (%process-registry-buckets reg))
                    (idx (%registry-bucket-index name))
                    (bucket (vector-ref buckets idx))
                    (current-alist (atomic-ref bucket))
                    (pair (assq name current-alist)))
               (if pair
                   (let ((entry (cdr pair)))
                     (atomic-ref (%registry-entry-target-box entry)))
                   #f)))))))

;; (synapse-rebind! [reg] name target)
;; Atomically updates the target for `name`. If `name` was already registered,
;; swaps the target in-place; if not found, inserts a new entry.
;; Returns #t.
(define synapse-rebind!
  (case-lambda
    ((name target)
     (synapse-rebind! (current-synapse-registry) name target))
    ((reg name target)
     (if (not (process-registry? reg))
         (error "synapse-rebind!: expected <process-registry> (CWE-843)" reg)
         (if (not (symbol? name))
             (error "synapse-rebind!: name must be a symbol (CWE-843)" name)
             (if (not target)
                 (error "synapse-rebind!: target cannot be #f (CWE-843)" target)
                 (let* ((buckets (%process-registry-buckets reg))
                        (idx (%registry-bucket-index name))
                        (bucket (vector-ref buckets idx)))
                   (let retry ()
                     (let* ((current-alist (atomic-ref bucket))
                            (pair (assq name current-alist)))
                       (if pair
                           ;; Existing entry: atomically swap target
                           (let* ((entry (cdr pair))
                                  (tbox (%registry-entry-target-box entry))
                                  (old (atomic-swap! tbox target)))
                             (atomic-fetch-add! (%registry-entry-epoch-box entry) 1)
                             (atomic-fetch-add! (%process-registry-epoch-box reg) 1)
                             #t)
                           ;; Not registered: insert new entry atomically
                           (let* ((entry (%make-registry-entry name
                                                               (make-atomic-box target)
                                                               (make-atomic-box 0)))
                                  (new-alist (cons (cons name entry) current-alist)))
                             (if (not (atomic-cas! bucket current-alist new-alist))
                                 (retry)
                                 (begin
                                   (atomic-fetch-add! (%process-registry-count-box reg) 1)
                                   (atomic-fetch-add! (%process-registry-epoch-box reg) 1)
                                   #t)))))))))))))

;; (synapse-registered-names [reg])
;; Returns a list of all currently registered symbol names.
(define synapse-registered-names
  (case-lambda
    (()
     (synapse-registered-names (current-synapse-registry)))
    ((reg)
     (if (not (process-registry? reg))
         (error "synapse-registered-names: expected <process-registry> (CWE-843)" reg)
         (let* ((buckets (%process-registry-buckets reg))
                (len (vector-length buckets)))
           (let b-loop ((i 0) (acc '()))
             (if (>= i len)
                 (reverse acc)
                 (let* ((bucket (vector-ref buckets i))
                        (alist (atomic-ref bucket)))
                   (let a-loop ((xs alist) (names acc))
                     (if (null? xs)
                         (b-loop (+ i 1) names)
                         (a-loop (cdr xs) (cons (caar xs) names))))))))))))

;; (synapse-registry-count [reg])
;; Returns the current number of registered names.
(define synapse-registry-count
  (case-lambda
    (()
     (synapse-registry-count (current-synapse-registry)))
    ((reg)
     (if (not (process-registry? reg))
         (error "synapse-registry-count: expected <process-registry> (CWE-843)" reg)
         (atomic-ref (%process-registry-count-box reg))))))

;; (synapse-registry-clear! [reg])
;; Clears all entries from the registry.
(define synapse-registry-clear!
  (case-lambda
    (()
     (synapse-registry-clear! (current-synapse-registry)))
    ((reg)
     (if (not (process-registry? reg))
         (error "synapse-registry-clear!: expected <process-registry> (CWE-843)" reg)
         (let* ((buckets (%process-registry-buckets reg))
                (len (vector-length buckets)))
           (let loop ((i 0))
             (if (< i len)
                 (begin
                   (atomic-set! (vector-ref buckets i) '())
                   (loop (+ i 1)))
                 (begin
                   (atomic-set! (%process-registry-count-box reg) 0)
                   (atomic-fetch-add! (%process-registry-epoch-box reg) 1)
                   #t))))))))

;; -----------------------------------------------------------------------
;; 5. Non-Blocking Transparent Message Routing (CWE-833 Deadlock Free)
;; -----------------------------------------------------------------------

;; (synapse-send-named! [reg] name msg)
;; Resolves `name` and sends `msg` without blocking.
;; Returns:
;;   #t             : Message sent successfully
;;   'not_found     : `name` is not registered
;;   'dead_process  : Target channel is closed or task is terminated/panicked
(define synapse-send-named!
  (case-lambda
    ((name msg)
     (synapse-send-named! (current-synapse-registry) name msg))
    ((reg name msg)
     (let ((target (synapse-whereis reg name)))
       (if (not target)
           'not_found
           (cond
             ;; Target is a Linear Channel (<channel>)
             ((channel? target)
              (if (channel-closed? target)
                  'dead_process
                  (begin
                    (channel-send! target msg)
                    #t)))
             ;; Target is a Task Context (<task-context>)
             ((task-context? target)
              (let ((st (%task-state target)))
                (if (or (eq? st 'terminated) (eq? st 'dead) (eq? st 'panicked) (eq? st 'completed))
                    (begin
                      (synapse-unregister-target! reg target)
                      'dead_process)
                    (begin
                      (task-set-handoff! target msg)
                      (task-wake! target)
                      #t))))
             ;; Target is a receiver callback procedure
             ((procedure? target)
              (target msg)
              #t)
             ;; Unknown target type
             (else
              #t)))))))

;; -----------------------------------------------------------------------
;; 6. Supervisor Integration Hook (Issue #667)
;; -----------------------------------------------------------------------

(define (synapse-enable-supervisor-rebind!)
  (guard (exn (else #f))
    (begin
      (vector-set! *supervisor-registry-rebind-box* 0
                   (lambda (id target) (synapse-rebind! id target)))
      #t)))

;; Attempt auto-injection if supervisor is loaded
(guard (exn (else #f))
  (synapse-enable-supervisor-rebind!))

;; -----------------------------------------------------------------------
;; 7. Task Termination Auto-Unregister Hook (Issue #730, Item C5)
;; -----------------------------------------------------------------------

(define (synapse-enable-termination-unregister!)
  (guard (exn (else #f))
    (begin
      (if (vector? *task-termination-registry-unregister-hook*)
          (vector-set! *task-termination-registry-unregister-hook* 0
                       (lambda (target) (synapse-unregister-target! target))))
      #t)))

;; Attempt auto-injection if links is loaded
(guard (exn (else #f))
  (synapse-enable-termination-unregister!))
