;;; =======================================================================
;;; Synapse Concurrency Hotpath Inlining & Type Check Elimination Test Suite
;;; Path: tests/concurrency/test_pass_inline_hotpath.scm
;;; Conforms to DSN-37 Section 4.3, 12.4 & Phase 4 Task 4.1 (Issue #682)
;;; =======================================================================

(test-begin "Synapse Hotpath Inlining & Type Check Elimination")

;;; -----------------------------------------------------------------------
;;; Group 1: Utilities, AST Predicates & Type Environment
;;; -----------------------------------------------------------------------
(newline)
(display "--- Group 1: Utilities, AST Predicates & Type Environment ---\n")

(assert-true "1.1 linear-var-name? detects channel prefixes and suffixes"
             (and (linear-var-name? 'chan)
                  (linear-var-name? 'chan-req)
                  (linear-var-name? 'rx)
                  (linear-var-name? 'tx)
                  (linear-var-name? 'my-channel)
                  (linear-var-name? 'data-ch)
                  (linear-var-name? 'resp-buf)))

(assert-false "1.2 linear-var-name? rejects non-linear symbols"
              (or (linear-var-name? 'foo)
                  (linear-var-name? 'count)
                  (linear-var-name? 'x)
                  (linear-var-name? 1234)))

(assert-true "1.3 arena-var-name? detects arena names"
             (and (arena-var-name? 'arena)
                  (arena-var-name? 'arena-task)
                  (arena-var-name? 'task-arena)))

(assert-false "1.4 arena-var-name? rejects other symbols"
              (or (arena-var-name? 'box)
                  (arena-var-name? 'obj)))

(assert-true "1.5 atomic-box-var-name? detects atomic boxes"
             (and (atomic-box-var-name? 'box)
                  (atomic-box-var-name? 'counter-box)
                  (atomic-box-var-name? 'atomic-state)))

(assert-false "1.6 atomic-box-var-name? rejects other symbols"
              (or (atomic-box-var-name? 'channel)
                  (atomic-box-var-name? 'val)))

(assert-true "1.7 task-var-name? detects task context symbols"
             (and (task-var-name? 'task)
                  (task-var-name? 'worker-task)))

(assert-true "1.7b scheduler-var-name? detects scheduler symbols"
             (and (scheduler-var-name? 'sched)
                  (scheduler-var-name? 'scheduler)
                  (scheduler-var-name? 'worker-sched)
                  (scheduler-var-name? 'main-scheduler)))

(assert-false "1.7c scheduler-var-name? rejects non-scheduler symbols"
              (or (scheduler-var-name? 'box)
                  (scheduler-var-name? 'channel)
                  (scheduler-var-name? 'count)
                  (scheduler-var-name? 1234)))

;; Test Type Environment
(define env1 (make-type-env))
(define env2 (type-env-extend env1 'tx 'channel))
(define env3 (type-env-extend env2 'local-arena 'ephemeral-arena))
(define env4 (type-env-extend env3 'state-box 'atomic-box))
(define env5 (type-env-extend env4 'spsc-tx 'spsc-channel))
(define env6 (type-env-extend env5 'my-sched 'scheduler))

(assert-equal "1.8 type-env-lookup finds mapped type"
              'channel
              (type-env-lookup env5 'tx))

(assert-equal "1.9 type-env-lookup finds mapped arena"
              'ephemeral-arena
              (type-env-lookup env5 'local-arena))

(assert-false "1.10 type-env-lookup returns #f for unmapped symbol"
              (type-env-lookup env5 'unknown-var))

(assert-true "1.11 statically-typed? returns #t on matching type"
             (statically-typed? env5 'tx 'channel))

(assert-false "1.12 statically-typed? returns #f on mismatched type"
              (statically-typed? env5 'tx 'ephemeral-arena))

(assert-false "1.13 statically-typed? returns #f on unknown symbol"
              (statically-typed? env5 'not-in-env 'channel))

(assert-true "1.14 statically-typed? treats spsc-channel as subtype of channel"
             (and (statically-typed? env5 'spsc-tx 'spsc-channel)
                  (statically-typed? env5 'spsc-tx 'channel)))

(assert-false "1.15 generic channel is not recognized as spsc-channel"
              (statically-typed? env5 'tx 'spsc-channel))

;;; -----------------------------------------------------------------------
;;; Group 2: Redundant Type Assertion Elimination
;;; -----------------------------------------------------------------------
(newline)
(display "--- Group 2: Redundant Type Assertion Elimination ---\n")

;; 2.1 Positive check with proven variable: (if (channel? tx) (send-msg tx 42) (error ...))
(define if-positive-check
  '(if (channel? tx)
       (send-msg tx 42)
       (error "expected channel")))

(define eliminated-pos
  (inline-hotpath-expr if-positive-check env5))

(assert-equal "2.1 (if (channel? tx) ...) simplifies directly to then-branch"
              '(send-msg tx 42)
              eliminated-pos)

;; 2.1b SPSC Positive check with proven spsc-channel
(define if-spsc-check
  '(if (channel-spsc? spsc-tx)
       (send-msg spsc-tx 42)
       (error "expected spsc channel")))

(define eliminated-spsc
  (inline-hotpath-expr if-spsc-check env5))

(assert-equal "2.1b (if (channel-spsc? spsc-tx) ...) simplifies directly to then-branch"
              '(send-msg spsc-tx 42)
              eliminated-spsc)

;; 2.2 Negative assertion guard: (if (not (channel? tx)) (error "not a channel"))
(define if-negative-guard
  '(if (not (channel? tx))
       (error "expected channel")))

(define eliminated-neg
  (inline-hotpath-expr if-negative-guard env5))

(assert-true "2.2 (if (not (channel? tx)) ...) produces %eliminated-assertion%"
             (eliminated-assertion? eliminated-neg))

;; 2.3 Assertion in begin sequence: cleaned from sequence!
(define seq-with-assertion
  '(begin
     (if (not (channel? tx))
         (error "expected channel"))
     (send-msg tx 42)))

(define cleaned-seq
  (inline-hotpath-expr seq-with-assertion env5))

(assert-equal "2.3 eliminated assertion is stripped from begin sequence"
              '(send-msg tx 42)
              cleaned-seq)

;; 2.4 Arena positive type check: (if (task-arena? local-arena) (arena-reset! local-arena) #f)
(define if-arena-check
  '(if (task-arena? local-arena)
       (arena-reset! local-arena)
       #f))

(define arena-check-result
  (inline-hotpath-expr if-arena-check env4))

(assert-true "2.4 (if (task-arena? ...) ...) simplifies to inlined arena-reset!"
             (and (pair? arena-check-result)
                  (eq? (car arena-check-result) 'let)
                  (equal? (caadr arena-check-result) '(%%arena local-arena))))

;; 2.5 Atomic box positive type check: (if (atomic-box? state-box) (atomic-ref state-box) 0)
(define if-box-check
  '(if (atomic-box? state-box)
       (atomic-ref state-box)
       0))

(define box-check-result
  (inline-hotpath-expr if-box-check env4))

(assert-equal "2.5 (if (atomic-box? ...) ...) simplifies to inlined (%atomic-box-val state-box)"
              '(%atomic-box-val state-box)
              box-check-result)

;; 2.6 Guard on unproven / dynamic variable MUST BE RETAINED (CWE-843 mitigation)
(define if-unproven-dynamic
  '(if (channel? dynamic-obj)
       (channel-send! dynamic-obj 100)
       (error "unknown object")))

(define unproven-result
  (inline-hotpath-expr if-unproven-dynamic env4))

(assert-equal "2.6 type check on unproven variable is safely preserved (CWE-843)"
              if-unproven-dynamic
              unproven-result)

;; 2.7 Scheduler positive type check (#806)
(define if-sched-check
  '(if (work-stealing-scheduler? my-sched)
       (run-task my-sched)
       (error "not a scheduler")))

(define sched-check-result
  (inline-hotpath-expr if-sched-check env6))

(assert-equal "2.7 (if (work-stealing-scheduler? my-sched) ...) simplifies directly to then-branch"
              '(run-task my-sched)
              sched-check-result)

;;; -----------------------------------------------------------------------
;;; Group 3: Hotpath Primitive Inlining
;;; -----------------------------------------------------------------------
(newline)
(display "--- Group 3: Hotpath Primitive Inlining ---\n")

;; 3.1 arena-allocate! inlining
(define alloc-expr '(arena-allocate! local-arena 64))
(define inlined-alloc (inline-hotpath-expr alloc-expr env4))

(assert-true "3.1 inlined arena-allocate! uses let* form"
             (and (pair? inlined-alloc) (eq? (car inlined-alloc) 'let*)))

(define alloc-bindings (cadr inlined-alloc))
(assert-equal "3.2 inlined arena-allocate! binds %%arena and %%sz"
              '((%%arena local-arena)
                (%%sz 64))
              alloc-bindings)

(define alloc-body (caddr inlined-alloc))
(assert-true "3.3 inlined arena-allocate! keeps CWE-190 size guard and capacity check"
             (and (pair? alloc-body)
                  (eq? (car alloc-body) 'if)
                  (equal? (cadr alloc-body)
                          '(and (integer? %%sz) (> %%sz 0) (<= %%sz 1048576)))
                  ;; invalid sizes are dispatched to the fully-checked slow path
                  (equal? (cadddr alloc-body) '(arena-allocate! %%arena %%sz))
                  (let ((fast (caddr alloc-body)))
                    (and (eq? (car fast) 'let*)
                         (equal? (cadr (caddr fast))
                                 '(and (null? (arena-chunks %%arena))
                                       (<= %%next (arena-capacity %%arena))))))))

;; 3.2 arena-reset! inlining
(define reset-expr '(arena-reset! local-arena))
(define inlined-reset (inline-hotpath-expr reset-expr env4))

(assert-true "3.4 inlined arena-reset! directly clears offset and chunks"
             (and (pair? inlined-reset)
                  (eq? (car inlined-reset) 'let)
                  (equal? (caddr inlined-reset)
                          '(begin
                             (arena-offset-set! %%arena 0)
                             (if (not (null? (arena-chunks %%arena)))
                                 (begin
                                   (arena-chunks-set! %%arena '())
                                   (arena-chunk-count-set! %%arena 0)))
                             (arena-reset-count-set! %%arena (+ (arena-reset-count %%arena) 1))
                             #t))))

;; 3.3 atomic-ref inlining
(define ref-expr '(atomic-ref state-box))
(define inlined-ref (inline-hotpath-expr ref-expr env4))

(assert-equal "3.5 inlined atomic-ref converts to (%atomic-box-val state-box)"
              '(%atomic-box-val state-box)
              inlined-ref)

;; 3.4 atomic-set! inlining
(define set-expr '(atomic-set! state-box 999))
(define inlined-set (inline-hotpath-expr set-expr env4))

(assert-equal "3.6 inlined atomic-set! converts to %%b %%v with %memory-fence"
              '(let ((%%b state-box) (%%v 999))
                 (begin
                   (%atomic-box-val-set! %%b %%v)
                   (%memory-fence)
                   %%v))
              inlined-set)

;; 3.5 atomic-cas! inlining
(define cas-expr '(atomic-cas! state-box 0 1))
(define inlined-cas (inline-hotpath-expr cas-expr env4))

(assert-equal "3.7 inlined atomic-cas! converts to (%atomic-cas! state-box 0 1)"
              '(%atomic-cas! state-box 0 1)
              inlined-cas)

;;; -----------------------------------------------------------------------
;;; Group 3b: Channel Hotpath Inlining Transformations (#688)
;;; -----------------------------------------------------------------------
(newline)
(display "--- Group 3b: Channel Hotpath Inlining Transformations (#688) ---\n")

;; 3b.1 channel-send! on proven spsc-channel
(define spsc-send-expr '(channel-send! spsc-tx 42))
(define inlined-spsc-send (inline-hotpath-expr spsc-send-expr env5))

(assert-true "3b.1 inlined spsc channel-send! uses let form binding %%ch and %%v"
             (and (pair? inlined-spsc-send)
                  (eq? (car inlined-spsc-send) 'let)
                  (equal? (cadr inlined-spsc-send) '((%%ch spsc-tx) (%%v 42)))))

(assert-true "3b.2 inlined spsc channel-send! checks capacity and directly updates ring buffer"
             (let ((body (caddr inlined-spsc-send)))
               (and (eq? (car body) 'if)
                    (equal? (cadr body) '(> (%channel-capacity %%ch) 0))
                    (equal? (cadddr body) '(%channel-send-core! %%ch %%v #f #f #t)))))

;; 3b.3 channel-send! on generic channel includes runtime spsc check
(define gen-send-expr '(channel-send! tx 42))
(define inlined-gen-send (inline-hotpath-expr gen-send-expr env5))

(assert-true "3b.3 inlined generic channel-send! includes runtime SPSC check"
             (let ((body (caddr inlined-gen-send)))
               (and (eq? (car body) 'if)
                    (equal? (cadr body) '(and (%channel-spsc? %%ch) (> (%channel-capacity %%ch) 0))))))

;; 3b.4 channel-recv! on proven spsc-channel
(define spsc-recv-expr '(channel-recv! spsc-tx))
(define inlined-spsc-recv (inline-hotpath-expr spsc-recv-expr env5))

(assert-true "3b.4 inlined spsc channel-recv! uses let form binding %%ch"
             (and (pair? inlined-spsc-recv)
                  (eq? (car inlined-spsc-recv) 'let)
                  (equal? (cadr inlined-spsc-recv) '((%%ch spsc-tx)))))

(assert-true "3b.5 inlined spsc channel-recv! directly dequeues from ring with wait-queue check"
             (let ((body (caddr inlined-spsc-recv)))
               (and (eq? (car body) 'if)
                    (equal? (cadr body) '(> (%channel-capacity %%ch) 0))
                    (equal? (cadddr body) '(%channel-recv-val! %%ch #f #f #t 'suspended)))))

;; 3b.6 channel-recv! on generic channel
(define gen-recv-expr '(channel-recv! tx))
(define inlined-gen-recv (inline-hotpath-expr gen-recv-expr env5))

(assert-true "3b.6 inlined generic channel-recv! includes runtime SPSC check"
             (let ((body (caddr inlined-gen-recv)))
               (and (eq? (car body) 'if)
                    (equal? (cadr body) '(and (%channel-spsc? %%ch) (> (%channel-capacity %%ch) 0))))))

;; 3b.7 channel-try-send! and channel-try-recv!
(define try-send-expr '(channel-try-send! spsc-tx 99))
(define inlined-try-send (inline-hotpath-expr try-send-expr env5))
(assert-true "3b.7 inlined channel-try-send! binds %%ch and %%v with non-blocking branch"
             (and (pair? inlined-try-send)
                  (eq? (car inlined-try-send) 'let)
                  (equal? (cadr inlined-try-send) '((%%ch spsc-tx) (%%v 99)))))

(define try-recv-expr '(channel-try-recv! spsc-tx))
(define inlined-try-recv (inline-hotpath-expr try-recv-expr env5))
(assert-true "3b.8 inlined channel-try-recv! binds %%ch with non-blocking branch"
             (and (pair? inlined-try-recv)
                  (eq? (car inlined-try-recv) 'let)
                  (equal? (cadr inlined-try-recv) '((%%ch spsc-tx)))))

;; 3b.9 channel-spsc-try-enqueue! and channel-spsc-try-dequeue-val!
(assert-equal "3b.9 inlined channel-spsc-try-enqueue! converts to %channel-spsc-try-enqueue!"
              '(%channel-spsc-try-enqueue! spsc-tx 123)
              (inline-hotpath-expr '(channel-spsc-try-enqueue! spsc-tx 123) env5))

(assert-equal "3b.10 inlined channel-spsc-try-dequeue-val! converts to %channel-spsc-try-dequeue-val!"
              '(%channel-spsc-try-dequeue-val! spsc-tx)
              (inline-hotpath-expr '(channel-spsc-try-dequeue-val! spsc-tx) env5))

;; 3b.11 CWE-843: Unproven dynamic variable is NOT inlined
(define unproven-chan-send '(channel-send! dynamic-chan 42))
(assert-equal "3b.11 unproven dynamic variable is not inlined (CWE-843)"
              unproven-chan-send
              (inline-hotpath-expr unproven-chan-send env5))

;;; -----------------------------------------------------------------------
;;; Group 3c: Scheduler Spawn Hotpath Inlining Transformations (#806)
;;; -----------------------------------------------------------------------
(newline)
(display "--- Group 3c: Scheduler Spawn Hotpath Inlining Transformations (#806) ---\n")

;; 3c.1 Inlined scheduler-spawn! with explicit target-worker
(define sched-spawn-expr '(scheduler-spawn! my-sched my-thunk 0))
(define inlined-sched-spawn (inline-hotpath-expr sched-spawn-expr env6))

(assert-true "3c.1 inlined scheduler-spawn! uses let form binding %%sched %%task %%target"
             (and (pair? inlined-sched-spawn)
                  (eq? (car inlined-sched-spawn) 'let)
                  (equal? (cadr inlined-sched-spawn)
                          '((%%sched my-sched)
                            (%%task my-thunk)
                            (%%target 0)))))

(assert-true "3c.2 inlined scheduler-spawn! includes l1-ring-push! and task-context acquisition"
             (let* ((inner-let (caddr inlined-sched-spawn))
                    (if-form (caddr inner-let)))
               (and (pair? inner-let)
                    (eq? (car inner-let) 'let)
                    (equal? (cadr inner-let) '((%%target-id %%target)))
                    (eq? (car if-form) 'if)
                    (equal? (cadr if-form)
                            '(>= (scheduler-live-tasks %%sched) (vector-ref *scheduler-max-tasks-box* 0))))))

;; 3c.3 Inlined scheduler-spawn! default target-worker (2 arguments)
(define sched-spawn-default-expr '(scheduler-spawn! my-sched my-thunk))
(define inlined-sched-spawn-default (inline-hotpath-expr sched-spawn-default-expr env6))

(assert-true "3c.3 inlined scheduler-spawn! defaults target to #f"
             (and (pair? inlined-sched-spawn-default)
                  (eq? (car inlined-sched-spawn-default) 'let)
                  (equal? (cadr inlined-sched-spawn-default)
                          '((%%sched my-sched)
                            (%%task my-thunk)))
                  (let ((inner (caddr inlined-sched-spawn-default)))
                    (and (eq? (car inner) 'let)
                         (equal? (cadr inner) '((%%target-id #f)))))))

;; 3c.4 CWE-843: Unproven dynamic scheduler variable is NOT inlined
(define unproven-sched-spawn '(scheduler-spawn! dynamic-sched my-thunk 0))
(assert-equal "3c.4 unproven dynamic scheduler is not inlined (CWE-843)"
              unproven-sched-spawn
              (inline-hotpath-expr unproven-sched-spawn env6))

;;; -----------------------------------------------------------------------
;;; Group 4: Let & Let* Type Propagation
;;; -----------------------------------------------------------------------
(newline)
(display "--- Group 4: Let & Let* Type Propagation ---\n")

;; 4.1 Type inference from constructor (make-channel) inside let
(define let-chan-expr
  '(let ((ch (make-channel 4)))
     (if (not (channel? ch))
         (error "expected channel"))
     (channel-send! ch 100)))

(define transformed-let-chan
  (inline-hotpath-expr let-chan-expr env1))

(assert-true "4.1 let binding with make-channel propagates type, eliminates assertion, and inlines channel-send!"
             (and (pair? transformed-let-chan)
                  (eq? (car transformed-let-chan) 'let)
                  (equal? (caadr transformed-let-chan) '(ch (make-channel 4)))
                  (= (length (cddr transformed-let-chan)) 1)
                  (let ((b (caddr transformed-let-chan)))
                    (and (eq? (car b) 'let)
                         (equal? (cadr b) '((%%ch ch) (%%v 100)))))))

;; 4.1b Type inference from make-spsc-channel inside let
(define let-spsc-expr
  '(let ((ch (make-spsc-channel 1024)))
     (if (not (channel? ch))
         (error "expected channel"))
     (channel-send! ch 200)))

(define transformed-let-spsc
  (inline-hotpath-expr let-spsc-expr env1))

(assert-true "4.1b let binding with make-spsc-channel propagates spsc-channel type and inlines without runtime spsc check"
             (and (pair? transformed-let-spsc)
                  (eq? (car transformed-let-spsc) 'let)
                  (let* ((inlined-send (caddr transformed-let-spsc))
                         (send-if (caddr inlined-send)))
                    (equal? (cadr send-if) '(> (%channel-capacity %%ch) 0)))))

;; 4.2 Type inference from constructor (make-task-arena) inside let*
(define let-arena-expr
  '(let* ((ar (make-task-arena 4096))
          (p (arena-allocate! ar 32)))
     p))

(define transformed-let-arena
  (inline-hotpath-expr let-arena-expr env1))

(assert-true "4.2 let* binding with make-task-arena inlines arena-allocate!"
             (and (pair? transformed-let-arena)
                  (eq? (car transformed-let-arena) 'let*)
                  ;; Second binding rhs was inlined from (arena-allocate! ar 32)
                  (let ((b2 (cadr (cadr transformed-let-arena))))
                    (and (eq? (car b2) 'p)
                         (pair? (cadr b2))
                         (eq? (caadr b2) 'let*)))))

;; 4.3 Type inference from make-work-stealing-scheduler inside let (#806)
(define let-sched-expr
  '(let ((sched (make-work-stealing-scheduler 4)))
     (if (not (work-stealing-scheduler? sched))
         (error "expected scheduler"))
     (scheduler-spawn! sched my-thunk 0)))

(define transformed-let-sched
  (inline-hotpath-expr let-sched-expr env1))

(assert-true "4.3 let binding with make-work-stealing-scheduler propagates type, eliminates assertion, and inlines scheduler-spawn!"
             (and (pair? transformed-let-sched)
                  (eq? (car transformed-let-sched) 'let)
                  (equal? (caadr transformed-let-sched) '(sched (make-work-stealing-scheduler 4)))
                  (= (length (cddr transformed-let-sched)) 1)
                  (let ((b (caddr transformed-let-sched)))
                    (and (eq? (car b) 'let)
                         (equal? (cadr b) '((%%sched sched) (%%task my-thunk) (%%target 0)))))))

;;; -----------------------------------------------------------------------
;;; Group 5: Complete %asc-kernel Transformation
;;; -----------------------------------------------------------------------
(newline)
(display "--- Group 5: Complete %asc-kernel Transformation ---\n")

(define full-kernel
  '(%asc-kernel (my-kernel tx-chan task-arena counter-box)
     (if (not (channel? tx-chan))
         (error "not a channel"))
     (if (not (task-arena? task-arena))
         (error "not an arena"))
     (atomic-set! counter-box 1)
     (let ((buf (arena-allocate! task-arena 128)))
       (channel-send! tx-chan buf))))

(define transformed-kernel
  (inline-hotpath-kernel full-kernel))

(assert-true "5.1 kernel transformed retains %asc-kernel header"
             (and (pair? transformed-kernel)
                  (eq? (car transformed-kernel) '%asc-kernel)
                  (equal? (cadr transformed-kernel)
                          '(my-kernel tx-chan task-arena counter-box))))

(define kernel-body (cddr transformed-kernel))

;; The kernel body should have eliminated both (if (not ...)) assertions
;; leaving atomic-set! (inlined) and let (with inlined arena-allocate! and inlined channel-send!)
(assert-equal "5.2 kernel body length is 2 (both defensive assertions eliminated)"
              2
              (length kernel-body))

(assert-true "5.3 first statement in kernel is inlined atomic-set!"
             (and (pair? (car kernel-body))
                  (eq? (caar kernel-body) 'let)
                  (equal? (cadar kernel-body) '((%%b counter-box) (%%v 1)))))

(assert-true "5.4 second statement is let buf with inlined arena-allocate!"
             (and (pair? (cadr kernel-body))
                  (eq? (caadr kernel-body) 'let)
                  (let ((b (caadr (cadr kernel-body))))
                    (and (eq? (car b) 'buf)
                         (pair? (cadr b))
                         (eq? (caadr b) 'let*)))))

(assert-true "5.5 channel-send! inside kernel let-body is inlined"
             (let* ((let-stmt (cadr kernel-body))
                    (let-inner-body (caddr let-stmt)))
               (and (pair? let-inner-body)
                    (eq? (car let-inner-body) 'let)
                    (equal? (cadr let-inner-body) '((%%ch tx-chan) (%%v buf))))))

;;; -----------------------------------------------------------------------
;;; Group 5b: CWE-843 Fail-Safe (Name Heuristics & Shadowing)
;;; -----------------------------------------------------------------------
(newline)
(display "--- Group 5b: CWE-843 Fail-Safe (Name Heuristics & Shadowing) ---\n")

;; Local binding named like an atomic box but bound to a literal: must NOT inline
(define let-fake-box '(let ((box 5)) (atomic-ref box)))
(assert-equal "5b.1 let-bound literal named 'box' is not treated as atomic-box"
              let-fake-box
              (inline-hotpath-expr let-fake-box env1))

;; Free variable whose name looks like an arena (no provenance): must NOT inline
(define free-arena-alloc '(arena-allocate! arena-x 16))
(assert-equal "5b.2 unproven free variable named like arena keeps checked call"
              free-arena-alloc
              (inline-hotpath-expr free-arena-alloc env1))

;; Inner let shadows a proven channel with a non-channel: check must be retained
(define shadow-let
  '(let ((tx 5))
     (if (channel? tx) (channel-send! tx 1) (error "not a channel"))))
(assert-equal "5b.3 let shadowing a proven channel retains its type check"
              shadow-let
              (inline-hotpath-expr shadow-let env4))

;; Inner lambda parameter shadows a proven channel: check must be retained
(define shadow-lambda
  '(lambda (tx)
     (if (channel? tx) (channel-send! tx 1) (error "not a channel"))))
(assert-equal "5b.4 lambda param shadowing a proven channel retains its type check"
              shadow-lambda
              (inline-hotpath-expr shadow-lambda env4))

;; Named-let loop variable shadows a proven atomic box: must NOT inline
(define shadow-named-let
  '(let loop ((state-box 0))
     (atomic-ref state-box)))
(assert-equal "5b.5 named-let variable shadowing a proven box is not inlined"
              shadow-named-let
              (inline-hotpath-expr shadow-named-let env4))

;;; -----------------------------------------------------------------------
;;; Group 6: Pass Descriptor & Injection API
;;; -----------------------------------------------------------------------
(newline)
(display "--- Group 6: Pass Descriptor & Injection API ---\n")

(define desc (synapse-inline-hotpath-descriptor))

(assert-true "6.1 synapse-inline-hotpath-descriptor is a pass-descriptor record"
             (pass-descriptor? desc))

(assert-equal "6.2 pass descriptor id is 'pass-synapse-inline-hotpath"
              'pass-synapse-inline-hotpath
              (pass-id desc))

(assert-equal "6.3 pass descriptor prerequisites include 'pass-synapse-fbip"
              '(pass-synapse-fbip)
              (pass-prerequisites desc))

;;; -----------------------------------------------------------------------
;;; Group 7: Pipeline Integration & Canonical Pass Ordering
;;; -----------------------------------------------------------------------
(newline)
(display "--- Group 7: Pipeline Integration & Canonical Pass Ordering ---\n")

(define (pass-after? p1 p2 p-list)
  (let loop ((ps p-list))
    (cond
      ((null? ps) #f)
      ((null? (cdr ps)) #f)
      ((and (eq? (car ps) p1) (eq? (cadr ps) p2)) #t)
      (else (loop (cdr ps))))))

(define (remove-all-synapse-passes!)
  (remove-synapse-safepoints-pass!)
  (remove-synapse-inline-hotpath-pass!)
  (remove-synapse-fbip-pass!)
  (remove-synapse-check-affine-pass!)
  (remove-synapse-split-planes-pass!))

;; Order A: hotpath injected before safepoints
(init-default-pass-registry!)
(inject-synapse-split-planes-pass!)
(inject-synapse-check-affine-pass!)
(inject-synapse-fbip-pass!)
(inject-synapse-inline-hotpath-pass!)
(inject-synapse-safepoints-pass!)
(define pipeline-a (build-pipeline 0 '()))
(define ids-a (map pass-id pipeline-a))

(assert-true "7.1 pass-synapse-inline-hotpath present in pipeline"
             (memq 'pass-synapse-inline-hotpath ids-a))
(assert-true "7.2 [order A] inline-hotpath directly follows fbip"
             (pass-after? 'pass-synapse-fbip 'pass-synapse-inline-hotpath ids-a))
(assert-true "7.3 [order A] inject-safepoints directly follows inline-hotpath"
             (pass-after? 'pass-synapse-inline-hotpath 'pass-synapse-inject-safepoints ids-a))
(assert-true "7.4 [order A] pipeline satisfies all DAG prerequisites"
             (validate-pipeline-prerequisites pipeline-a))
(remove-all-synapse-passes!)

;; Order B: safepoints injected before hotpath
(inject-synapse-split-planes-pass!)
(inject-synapse-check-affine-pass!)
(inject-synapse-fbip-pass!)
(inject-synapse-safepoints-pass!)
(inject-synapse-inline-hotpath-pass!)
(define ids-b (map pass-id (build-pipeline 0 '())))

(assert-true "7.5 [order B] inline-hotpath directly follows fbip"
             (pass-after? 'pass-synapse-fbip 'pass-synapse-inline-hotpath ids-b))
(assert-true "7.6 [order B] inject-safepoints directly follows inline-hotpath"
             (pass-after? 'pass-synapse-inline-hotpath 'pass-synapse-inject-safepoints ids-b))

;; Pass function over a mixed forms list
(define forms-out (inline-hotpath-pass (list '(define (caller) 42) full-kernel)))
(assert-equal "7.7 inline-hotpath-pass preserves non-kernel forms"
              '(define (caller) 42)
              (car forms-out))
(assert-equal "7.8 inline-hotpath-pass transforms kernel forms"
              transformed-kernel
              (cadr forms-out))

(remove-all-synapse-passes!)
(assert-false "7.9 inline-hotpath pass cleanly removed"
              (memq 'pass-synapse-inline-hotpath (map pass-id (build-pipeline 0 '()))))

(test-end "Synapse Hotpath Inlining & Type Check Elimination")
