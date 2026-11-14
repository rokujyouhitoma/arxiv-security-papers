;;; =======================================================================
;;; Synapse Epoch Fencing & Distributed Rollback Test Suite
;;; Path: tests/concurrency/test_epoch.scm
;;; Conforms to DSN-37 Section 8.2, 8.3 & Phase 4 Task 4.2 (Issue #642)
;;; =======================================================================

(load "ulisp/runtime/concurrency/arena.scm")
(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/epoch.scm")

(test-begin "concurrency-epoch")

(define-syntax assert-true
  (syntax-rules ()
    ((assert-true val msg)
     (test-assert msg val))
    ((assert-true val)
     (test-assert "assert-true" val))))

(define-syntax assert-false
  (syntax-rules ()
    ((assert-false val msg)
     (test-assert msg (not val)))
    ((assert-false val)
     (test-assert "assert-false" (not val)))))

(define-syntax assert-eq
  (syntax-rules ()
    ((assert-eq actual expected msg)
     (test-equal msg expected actual))))

(define-syntax assert-equal
  (syntax-rules ()
    ((assert-equal actual expected msg)
     (test-equal msg expected actual))))

(define-syntax assert-error
  (syntax-rules ()
    ((assert-error thunk msg)
     (let ((caught
            (guard (exn (#t #t))
              (thunk)
              #f)))
       (test-assert msg caught)))))


;; -----------------------------------------------------------------------
;; Helper: Mock Task Context Creation
;; -----------------------------------------------------------------------

(define (make-test-task id epoch arena)
  (make-task-context id epoch))

;;; -----------------------------------------------------------------------
;;; Group 1: Epoch Counter & Transitions
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 1: Epoch Counter & Transitions ---\n")
(flush-output-port)

(epoch-reset-global!)

(assert-equal (epoch-current) 1 "1.1 initial epoch is 1")
(assert-equal (epoch-floor) 1 "1.2 initial floor is 1")

(let ((next-ep (epoch-advance!)))
  (assert-equal next-ep 2 "1.3 epoch-advance! increments to 2")
  (assert-equal (epoch-current) 2 "1.4 epoch-current reflects updated value"))

(epoch-set-floor! 2)
(assert-equal (epoch-floor) 2 "1.5 epoch-set-floor! updates floor to 2")
(assert-true (epoch-aborted? 1) "1.6 epoch 1 (< floor) is treated as aborted")
(assert-false (epoch-aborted? 2) "1.7 epoch 2 (>= floor) is not aborted")

;; Guard against invalid floor
(let ((rejected (guard (exn (else #t))
                  (epoch-set-floor! 0)
                  #f)))
  (assert-true rejected "1.8 epoch-set-floor! rejects 0 (CWE-190)"))

;; Atomic return value verification (#672)
(let* ((ep3 (epoch-advance!))
       (ep4 (epoch-advance!))
       (ep5 (epoch-advance!))
       (ep6 (epoch-advance!))
       (ep7 (epoch-advance!)))
  (assert-equal ep3 3 "1.9a epoch-advance! atomically returns 3")
  (assert-equal ep4 4 "1.9b epoch-advance! atomically returns 4")
  (assert-equal ep5 5 "1.9c epoch-advance! atomically returns 5")
  (assert-equal ep6 6 "1.9d epoch-advance! atomically returns 6")
  (assert-equal ep7 7 "1.9e epoch-advance! atomically returns 7")
  (assert-equal (epoch-current) 7 "1.10 epoch-current matches last advanced epoch (7)"))

;;; -----------------------------------------------------------------------
;;; Group 2: Task Epoch Binding & Registration Registry
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 2: Task Epoch Binding & Registration Registry ---\n")
(flush-output-port)

(epoch-reset-global!)

(let* ((arena1 (make-task-arena 4096))
       (task1 (make-test-task 101 0 arena1)))
  (epoch-bind-task! task1)
  (assert-equal (task-epoch task1) 1 "2.1 default epoch bound to task is current epoch (1)")
  (assert-equal (length (epoch-registered-tasks)) 1 "2.2 task1 registered in registry"))

(let* ((arena2 (make-task-arena 4096))
       (task2 (make-test-task 102 0 arena2)))
  (epoch-bind-task! task2 42)
  (assert-equal (task-epoch task2) 42 "2.3 explicit epoch 42 bound to task2")
  (assert-equal (length (epoch-registered-tasks)) 2 "2.4 task2 registered in registry"))

;; Unbind task1
(let* ((tasks (epoch-registered-tasks))
       (task1 (caar (cdr tasks))))
  (epoch-unbind-task! task1)
  (assert-equal (length (epoch-registered-tasks)) 1 "2.5 task1 cleanly unbound from registry"))

;;; -----------------------------------------------------------------------
;;; Group 3: Speculative Rollback & O(1) Arena Reclamation
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 3: Speculative Rollback & O(1) Arena Reclamation ---\n")
(flush-output-port)

(epoch-reset-global!)

(let* ((arena-a (make-task-arena 4096))
       (arena-b (make-task-arena 4096))
       (arena-c (make-task-arena 4096)))

  ;; Bump allocate in arena-b and arena-c
  (arena-allocate! arena-b 128 8)
  (arena-allocate! arena-c 256 8)
  (assert-true (> (arena-offset arena-b) 0) "3.1 arena-b has allocated bytes")
  (assert-true (> (arena-offset arena-c) 0) "3.2 arena-c has allocated bytes")

  (let* ((task-a (make-test-task 201 2 arena-a))
         (task-b (make-test-task 202 3 arena-b))
         (task-c (make-test-task 203 4 arena-c)))

    (epoch-bind-task! task-a 2 arena-a)
    (epoch-bind-task! task-b 3 arena-b)
    (epoch-bind-task! task-c 4 arena-c)

    (assert-equal (length (epoch-registered-tasks)) 3 "3.3 3 tasks registered")

    ;; Advance global epoch to 4
    (atomic-set! *epoch-global-counter* 4)

    ;; Perform rollback to Epoch 2 (abort Epochs > 2, i.e., 3 and 4)
    (let ((fresh-ep (epoch-rollback-to! 2)))
      (assert-true (>= fresh-ep 5) "3.4 rollback advances to fresh epoch >= 5")
      (assert-equal (task-state task-a) 'ready "3.5 survivor task-a remains in ready state")
      (assert-equal (task-state task-b) 'terminated "3.6 aborted task-b transitioned to terminated")
      (assert-equal (task-state task-c) 'terminated "3.7 aborted task-c transitioned to terminated")

      (assert-equal (task-reductions task-b) 0 "3.8 task-b reductions atomically zeroed")
      (assert-equal (task-reductions task-c) 0 "3.9 task-c reductions atomically zeroed")

      (assert-equal (arena-offset arena-b) 0 "3.10 arena-b reset in O(1)")
      (assert-equal (arena-offset arena-c) 0 "3.11 arena-c reset in O(1)")

      (assert-true (epoch-aborted? 3) "3.12 epoch 3 is marked aborted")
      (assert-true (epoch-aborted? 4) "3.13 epoch 4 is marked aborted")
      (assert-false (epoch-aborted? 2) "3.14 target epoch 2 is NOT aborted")

      (assert-equal (length (epoch-registered-tasks)) 1 "3.15 only survivor task-a remains in registry"))))

;;; -----------------------------------------------------------------------
;;; Group 4: Generation Gate & Channel Waiter Protection (DSN-37 Section 8.3)
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 4: Generation Gate & Channel Waiter Protection ---\n")
(flush-output-port)

(epoch-reset-global!)
(install-epoch-channel-gate!)

(let* ((task-live (make-test-task 401 1 (make-task-arena 4096)))
       (task-term (make-test-task 402 1 (make-task-arena 4096))))
  (epoch-bind-task! task-live 1)
  (epoch-bind-task! task-term 1)
  (abort-task! task-term)
  ;; 4.1-4.2 Validation predicate checks
  (assert-true (epoch-task-valid? task-live) "4.1 live task passes Generation Gate")
  (assert-false (epoch-task-valid? task-term) "4.2 terminated task fails Generation Gate"))

;; Create channel and put a task to sleep in an epoch that gets aborted
(let* ((ch (make-channel 2))
       (arena-waiter (make-task-arena 4096))
       (task-waiter (make-test-task 301 2 arena-waiter)))
  (epoch-bind-task! task-waiter 2)

  ;; Simulate task-waiter blocking on channel
  (%task-state-set! task-waiter 'blocked)
  (let ((waiter (make-channel-waiter task-waiter #f)))
    (enqueue-lockfree! (%channel-recv-wait-queue ch) waiter)
    (assert-equal (queue-size (%channel-recv-wait-queue ch)) 1 "4.3 waiter queued on channel")

    ;; Now abort epoch 2
    (epoch-rollback-to! 1)
    (assert-false (epoch-task-valid? task-waiter) "4.4 task-waiter epoch is now aborted")

    ;; Send message on channel from new epoch:
    ;; Channel's %pop-live-waiter! should detect Generation Gate failure on task-waiter,
    ;; transition task-waiter to 'terminated, drop the waiter, and buffer the message!
    (let* ((send-sender (make-test-task 302 (epoch-current) (make-task-arena 4096)))
           (send-result (channel-send! ch "epoch-safe-payload" send-sender)))
      (assert-equal send-result #t "4.5 channel-send! succeeds")
      (assert-equal (task-state task-waiter) 'terminated "4.6 Generation Gate transitioned stale waiter to terminated")
      (assert-equal (queue-size (%channel-recv-wait-queue ch)) 0 "4.7 stale waiter removed from channel wait queue")
      (assert-equal (channel-count ch) 1 "4.8 message buffered instead of leaking to stale task (Shared-Nothing safe)"))))

;;; -----------------------------------------------------------------------
;;; Group 5: First-Class call/cc Backtracking Integration
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 5: First-Class call/cc Backtracking Integration ---\n")
(flush-output-port)

(epoch-reset-global!)

(let* ((arena-spec (make-task-arena 4096))
       (spec-task (make-test-task 501 0 arena-spec))
       (cp-result
        (epoch-checkpoint
         (lambda (rollback)
           (let ((spec-ep (epoch-advance!)))
             (epoch-bind-task! spec-task spec-ep arena-spec)
             ;; Simulate speculative branch prune
             (rollback 'prune-dead-branch))))))

  (assert-equal (car cp-result) 'rollback "5.1 call/cc checkpoint returned from rollback")
  (assert-equal (cadr cp-result) 'prune-dead-branch "5.2 rollback reason captured")
  (assert-equal (task-state spec-task) 'terminated "5.3 speculative task cleanly aborted on call/cc backtrack")
  (assert-equal (task-reductions spec-task) 0 "5.4 speculative task reduction budget zeroed"))

;;; -----------------------------------------------------------------------
;;; Group 6: 10,000 Tasks Rollback Endurance Stress Test
;;; -----------------------------------------------------------------------

(write-string "\n--- Group 6: 10,000 Tasks Rollback Endurance Stress Test ---\n")
(flush-output-port)

(epoch-reset-global!)

(let ((base-epoch (epoch-current))
      (num-stress-tasks 10000))

  (write-string "Spawning 10,000 speculative tasks across 5 epochs...\n")
  (flush-output-port)

  (let loop ((i 0))
    (if (< i num-stress-tasks)
        (let* ((task-ep (+ base-epoch (+ 1 (modulo i 5))))
               (t (make-task-context (+ 10000 i) task-ep)))
          (epoch-bind-task! t task-ep)
          (loop (+ i 1)))))

  (assert-equal (length (epoch-registered-tasks)) num-stress-tasks "6.1 all 10,000 tasks registered in registry")

  (write-string "Rolling back to base epoch...\n")
  (flush-output-port)

  (epoch-rollback-to! base-epoch)

  (assert-equal (length (epoch-registered-tasks)) 0 "6.2 all 10,000 speculative tasks removed from registry")

  (let* ((stats (epoch-stats))
         (aborted-tasks-stat (cdr (assq 'aborted-tasks stats))))
    (assert-equal aborted-tasks-stat num-stress-tasks "6.3 exactly 10,000 aborted tasks recorded in telemetry")))

(test-end "concurrency-epoch")
