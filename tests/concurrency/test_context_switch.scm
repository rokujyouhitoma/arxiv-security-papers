;;; =======================================================================
;;; ULisp Concurrency Test Suite: System V AMD64 Native Context Switch (#634)
;;; Tests:
;;;   Group 1: <task-stack> Allocation, 16-Byte Alignment & Canaries
;;;   Group 2: setup-task-stack Frame Layout & ABI Invariants
;;;   Group 3: System V AMD64 Callee-Saved Registers (rbp, rbx, r12-r15) & Alignment
;;;   Group 4: Scheme Coroutines (context-resume!, context-yield!, P2P context-switch!)
;;;   Group 5: 10,000,000 Context Switches Endurance Stress Test
;;;   Group 6: Security & Boundary Guards (CWE-787 / CWE-843 / CWE-416)
;;; =======================================================================

(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/context.scm")

(test-begin "concurrency-context_switch")

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
;; Group 1: <task-stack> Allocation, 16-Byte Alignment & Canaries
;; -----------------------------------------------------------------------
(write-string "--- Group 1: <task-stack> Allocation, 16-Byte Alignment & Canaries ---\n")
(flush-output-port)

(let ((s-def (make-task-stack))
      (s-4k  (make-task-stack 4096))
      (s-16k (make-task-stack 16384)))
  (assert-true (task-stack? s-def) "s-def satisfies task-stack?")
  (assert-true (task-stack? s-4k) "s-4k satisfies task-stack?")
  (assert-true (not (task-stack? 42)) "fixnum is not task-stack?")
  (assert-true (not (task-stack? (vector 1 2 3))) "raw vector is not task-stack?")
  (assert-equal (task-stack-size s-def) 8192 "default task stack size is 8192 (8KB)")
  (assert-equal (task-stack-size s-4k) 4096 "4KB task stack size is 4096")
  (assert-equal (task-stack-size s-16k) 16384 "16KB task stack size is 16384")
  (assert-true (> (task-stack-base s-def) 0) "task-stack-base is a valid mmap address")
  (assert-equal (modulo (task-stack-top s-def) 16) 0 "task-stack-top is 16-byte aligned")
  (assert-equal (modulo (task-stack-initial-sp s-def) 16) 0 "task-stack-initial-sp is 16-byte aligned")
  (assert-true (task-stack-check-canary s-def) "s-def bottom and top stack canaries are intact")
  (assert-true (task-stack-check-canary s-4k) "s-4k bottom and top stack canaries are intact")
  (assert-true (not (task-stack-freed? s-def)) "s-def is not freed initially")
  (assert-true (free-task-stack! s-def) "free-task-stack! returns #t on first free")
  (assert-true (task-stack-freed? s-def) "s-def is marked freed after free-task-stack!")
  (assert-true (not (free-task-stack! s-def)) "second free-task-stack! is a safe no-op returning #f")
  (free-task-stack! s-4k)
  (free-task-stack! s-16k))

;; -----------------------------------------------------------------------
;; Group 2: setup-task-stack Frame Layout & ABI Invariants
;; -----------------------------------------------------------------------
(write-string "--- Group 2: setup-task-stack Frame Layout & ABI Invariants ---\n")
(flush-output-port)

(let* ((stk (make-task-stack 8192))
       (dummy-fn (lambda () 123))
       (sp1 (setup-task-stack stk dummy-fn))
       (top (task-stack-top stk))
       (frame-top (- top *context-tcb-header-size*))
       (entry-tramp (%asm-get-trampoline-addr 0))
       (exit-tramp (%asm-get-trampoline-addr 1)))
  (assert-equal sp1 (- top (+ *context-tcb-header-size* (context-frame-size))) "setup-task-stack returns initial_sp = top - (tcb + frame)")
  (assert-equal (modulo sp1 16) 0 "initial_sp is 16-byte aligned (0 mod 16)")
  ;; After swap_context pops 6 registers (48B) and executes ret (8B), rsp = initial_sp + 56 = frame_top - 8
  (assert-equal (modulo (+ sp1 56) 16) 8 "post-ret function entry rsp has System V ABI alignment (rsp % 16 == 8)")
  (assert-equal (%context-raw-u64-ref frame-top -8) exit-tramp "[frame_top - 8] holds ulisp_task_exit_trampoline")
  (assert-equal (%context-raw-u64-ref frame-top -16) entry-tramp "[frame_top - 16] holds ulisp_task_entry_trampoline")
  (assert-equal (%context-raw-u64-ref frame-top -24) frame-top "[frame_top - 24] (initial rbp) holds frame_top")
  (assert-equal (%context-raw-u64-ref frame-top -32) top "[frame_top - 32] (initial rbx) holds TCB top")
  ;; Also verify 3-argument (setup-task-stack base size entry-fn)
  (let ((sp2 (setup-task-stack (task-stack-base stk) (task-stack-size stk) dummy-fn)))
    (assert-equal sp2 sp1 "3-arg (setup-task-stack base size entry-fn) produces identical initial_sp"))
  (free-task-stack! stk))

;; -----------------------------------------------------------------------
;; Group 3: System V AMD64 Callee-Saved Registers & 16-Byte ABI Alignment
;; -----------------------------------------------------------------------
(write-string "--- Group 3: System V AMD64 Callee-Saved Registers & Alignment ---\n")
(flush-output-port)

(let ((stats0 (context-stats)))
  (assert-true (> (cdr (assq 'swap-context-addr stats0)) 0) "swap_context native code address is linked")
  (assert-true (> (cdr (assq 'entry-trampoline stats0)) 0) "ulisp_task_entry_trampoline native address is linked")
  (assert-true (> (cdr (assq 'exit-trampoline stats0)) 0) "ulisp_task_exit_trampoline native address is linked"))

(let ((s1 (make-task-stack 8192))
      (s2 (make-task-stack 8192)))
  (assert-true (verify-swap-context-abi! s1 s2)
               "swap_context preserves all 6 callee-saved regs (rbp, rbx, r12, r13, r14, r15) & 16-byte ABI alignment")
  (assert-true (task-stack-check-canary s1) "s1 stack canary intact after register verification")
  (assert-true (task-stack-check-canary s2) "s2 stack canary intact after register verification")
  (free-task-stack! s1)
  (free-task-stack! s2))

;; -----------------------------------------------------------------------
;; Group 4: Scheme Coroutines (Resume / Yield / Heap Alloc / P2P Switch)
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Scheme Coroutines (Resume / Yield / Heap Alloc / P2P Switch) ---\n")
(flush-output-port)

;; 4a. Coroutine with multiple yields, bidirectional value passing & heap allocation
(let* ((trace (vector '()))
       (co (make-coroutine-context
            (lambda ()
              ;; Allocate pairs and a vector on the uLisp heap while on custom 8KB stack!
              (let ((v (vector 10 20 30)))
                (vector-set! trace 0 (cons 'step-1 (vector-ref trace 0)))
                (let ((in1 (context-yield! (+ (vector-ref v 0) (vector-ref v 1)))))
                  (vector-set! trace 0 (cons in1 (vector-ref trace 0)))
                  (let ((in2 (context-yield! (cons 'from-co in1))))
                    (vector-set! trace 0 (cons in2 (vector-ref trace 0)))
                    (+ (vector-ref v 2) in2))))))))
  (assert-true (coroutine-context? co) "co satisfies coroutine-context?")
  (assert-equal (coroutine-state co) 'ready "co initial state is 'ready")
  (assert-true (not (coroutine-terminated? co)) "co is not terminated initially")

  ;; First resume: runs until first (context-yield! 30)
  (let ((y1 (context-resume! co)))
    (assert-equal y1 30 "first context-resume! returns yielded value 30")
    (assert-equal (coroutine-state co) 'suspended "co state after yield #1 is 'suspended")
    (assert-equal (car (vector-ref trace 0)) 'step-1 "co executed step-1 before yield #1"))

  ;; Second resume: sends 100 into co, runs until second (context-yield! '(from-co . 100))
  (let ((y2 (context-resume! co 100)))
    (assert-true (and (pair? y2) (eq? (car y2) 'from-co) (= (cdr y2) 100))
                 "second context-resume! receives heap-allocated pair (from-co . 100) from coroutine")
    (assert-equal (coroutine-state co) 'suspended "co state after yield #2 is 'suspended"))

  ;; Third resume: sends 70 into co, runs to completion and returns 30 + 70 = 100
  (let ((final-val (context-resume! co 70)))
    (assert-equal final-val 100 "third context-resume! returns final coroutine result 100")
    (assert-equal (coroutine-state co) 'terminated "co state after return is 'terminated")
    (assert-true (coroutine-terminated? co) "coroutine-terminated? is #t after return")
    (assert-equal (coroutine-switch-count co) 3 "coroutine recorded 3 resumes"))

  (free-coroutine-context! co))

;; 4b. Direct Peer-to-Peer Coroutine Switching (context-switch! ctx-a <-> ctx-b)
(let* ((ping-pong-log (vector '()))
       (ctx-a-box (vector #f))
       (ctx-b-box (vector #f)))
  (vector-set! ctx-a-box 0
    (make-coroutine-context
     (lambda ()
       (vector-set! ping-pong-log 0 (cons 'a1 (vector-ref ping-pong-log 0)))
       (let ((from-b1 (context-switch! (vector-ref ctx-a-box 0) (vector-ref ctx-b-box 0) 11)))
         (vector-set! ping-pong-log 0 (cons (cons 'a2 from-b1) (vector-ref ping-pong-log 0)))
         (let ((from-b2 (context-switch! (vector-ref ctx-a-box 0) (vector-ref ctx-b-box 0) 22)))
           (vector-set! ping-pong-log 0 (cons (cons 'a3 from-b2) (vector-ref ping-pong-log 0)))
           'done-a)))))
  (vector-set! ctx-b-box 0
    (make-coroutine-context
     (lambda ()
       (vector-set! ping-pong-log 0 (cons 'b1 (vector-ref ping-pong-log 0)))
       (let ((back-to-a1 (context-switch! (vector-ref ctx-b-box 0) (vector-ref ctx-a-box 0) 110)))
         (vector-set! ping-pong-log 0 (cons (cons 'b2 back-to-a1) (vector-ref ping-pong-log 0)))
         (context-switch! (vector-ref ctx-b-box 0) (vector-ref ctx-a-box 0) 220)))))

  (let ((res-a (context-resume! (vector-ref ctx-a-box 0))))
    (assert-equal (eq? res-a 'done-a) #t "P2P context-switch! ping-pong completed and returned 'done-a")
    (assert-equal (coroutine-state (vector-ref ctx-a-box 0)) 'terminated "ctx-a terminated cleanly after P2P ping-pong")
    (assert-equal (length (vector-ref ping-pong-log 0)) 5 "ping-pong-log recorded all 5 interleaved steps across ctx-a and ctx-b")
    (assert-equal (cdr (car (vector-ref ping-pong-log 0))) 220 "ctx-a received 220 from ctx-b on final switch"))

  (free-coroutine-context! (vector-ref ctx-a-box 0))
  (free-coroutine-context! (vector-ref ctx-b-box 0)))

;; 4c. Atomic Coroutine ID Allocation & Monotonic Increment (#671)
(write-string "--- Group 4c: Atomic Coroutine ID Allocation & Invariants (#671) ---\n")
(flush-output-port)

(let* ((initial-id (coroutine-next-id-current))
       (id1 (allocate-coroutine-id!))
       (id2 (allocate-coroutine-id!))
       (id3 (allocate-coroutine-id!)))
  (assert-equal id2 (+ id1 1) "allocate-coroutine-id! id2 is id1 + 1")
  (assert-equal id3 (+ id2 1) "allocate-coroutine-id! id3 is id2 + 1")
  (assert-equal (coroutine-next-id-current) (+ id3 1) "coroutine-next-id-current matches id3 + 1"))

;; Verify make-coroutine-context automatically assigns sequential atomic IDs
(let* ((c-base (coroutine-next-id-current))
       (co1 (make-coroutine-context (lambda () 1)))
       (co2 (make-coroutine-context (lambda () 2)))
       (co3 (make-coroutine-context (lambda () 3))))
  (assert-equal (coroutine-id co1) c-base "co1 has atomic id equal to c-base")
  (assert-equal (coroutine-id co2) (+ c-base 1) "co2 has atomic id c-base + 1")
  (assert-equal (coroutine-id co3) (+ c-base 2) "co3 has atomic id c-base + 2")
  (free-coroutine-context! co1)
  (free-coroutine-context! co2)
  (free-coroutine-context! co3))

;; Verify coroutine-reset-next-id!
(coroutine-reset-next-id! 1000)
(assert-equal (coroutine-next-id-current) 1000 "coroutine-reset-next-id! resets to 1000")
(let ((co-1000 (make-coroutine-context (lambda () 10))))
  (assert-equal (coroutine-id co-1000) 1000 "co-1000 has coroutine-id 1000")
  (assert-equal (coroutine-next-id-current) 1001 "coroutine-next-id-current advances to 1001")
  (free-coroutine-context! co-1000))

;; Verify coroutine-reset-next-id! rejects non-integer (CWE-843)
(assert-error (lambda () (coroutine-reset-next-id! "not-an-integer"))
              "coroutine-reset-next-id! rejects string (CWE-843)")

;; -----------------------------------------------------------------------
;; Group 5: 10,000,000 Context Switches Endurance Stress Test
;; -----------------------------------------------------------------------
(write-string "--- Group 5: 10,000,000 Context Switches Endurance Stress Test ---\n")
(flush-output-port)

(let* ((s1 (make-task-stack 8192))
       (s2 (make-task-stack 8192))
       (target-switches 10000000)
       (completed (bench-swap-context! target-switches s1 s2))
       (stats (context-stats)))
  (assert-equal completed 10000000 "10,000,000 native swap_context switches completed with 0 faults")
  (assert-true (task-stack-check-canary s1) "s1 stack canary uncorrupted after 10,000,000 switches")
  (assert-true (task-stack-check-canary s2) "s2 stack canary uncorrupted after 10,000,000 switches")
  (assert-true (>= (cdr (assq 'total-switches stats)) 10000000)
               "context-stats total-switches >= 10,000,000")
  (free-task-stack! s1)
  (free-task-stack! s2))

;; -----------------------------------------------------------------------
;; Group 6: Security & Boundary Guards (CWE-787 / CWE-843 / CWE-416)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Security & Boundary Guards (CWE-787 / CWE-843 / CWE-416) ---\n")
(flush-output-port)

;; 6a. Stack size boundary checks (CWE-787)
(assert-error (lambda () (make-task-stack 2048))
              "make-task-stack rejects stack size < 4096 (CWE-787)")
(assert-error (lambda () (make-task-stack 131072))
              "make-task-stack rejects stack size > 65536 (CWE-787)")
(assert-error (lambda () (make-task-stack -4096))
              "make-task-stack rejects negative stack size (CWE-20)")

;; 6b. Type confusion checks (CWE-843)
(assert-error (lambda () (make-coroutine-context 12345))
              "make-coroutine-context rejects non-procedure entry-fn (CWE-843)")
(assert-error (lambda () (context-resume! 'not-a-coroutine))
              "context-resume! rejects non-coroutine-context (CWE-843)")
(assert-error (lambda () (context-switch! 'bad-from 'bad-to))
              "context-switch! rejects non-coroutine-context (CWE-843)")

;; 6c. Re-entering terminated coroutine or freed stack (CWE-416)
(let ((co-done (make-coroutine-context (lambda () 'finished))))
  (assert-equal (eq? (context-resume! co-done) 'finished) #t "co-done runs once to completion")
  (assert-error (lambda () (context-resume! co-done))
                "context-resume! rejects re-entering terminated coroutine (CWE-416)")
  (free-coroutine-context! co-done)
  (assert-error (lambda () (context-resume! co-done))
                "context-resume! rejects resuming coroutine with freed stack (CWE-416)"))

;; 6d. Stack overflow canary corruption detection (CWE-787)
(let* ((co-tampered (make-coroutine-context (lambda () 42)))
       (stk (coroutine-stack co-tampered)))
  ;; Simulate stack overflow overwriting bottom canary at [base + 0]
  (%context-raw-u64-set! (task-stack-base stk) 0 999999)
  (assert-true (not (task-stack-check-canary stk))
               "task-stack-check-canary detects corrupted bottom canary (CWE-787)")
  (assert-error (lambda () (context-resume! co-tampered))
                "context-resume! aborts when stack canary is corrupted (CWE-787)")
  (free-coroutine-context! co-tampered))

;; -----------------------------------------------------------------------
;; Group 7: Per-Task Exception Handler Chain Isolation Across Switches (#719)
;; -----------------------------------------------------------------------
(write-string "--- Group 7: Per-Task Exception Handler Chain Isolation (#719) ---\n")
(flush-output-port)

(let* ((caught-a (vector #f))
       (caught-b (vector #f))
       (caught-host (vector #f))
       (co-a (make-coroutine-context
              (lambda ()
                (guard (exn (#t (vector-set! caught-a 0 exn) 'handled-a))
                  (context-yield! 'a-ready)
                  (raise 'boom-a)))))
       (co-b (make-coroutine-context
              (lambda ()
                (guard (exn (#t (vector-set! caught-b 0 exn) 'handled-b))
                  (context-yield! 'b-ready)
                  (raise 'boom-b))))))
  (guard (host-exn (#t (vector-set! caught-host 0 host-exn)))
    (assert-equal (eq? (context-resume! co-a) 'a-ready) #t "co-a installs guard and yields 'a-ready")
    (assert-equal (eq? (context-resume! co-b) 'b-ready) #t "co-b installs guard and yields 'b-ready without clobbering co-a")
    (assert-equal (eq? (context-resume! co-a) 'handled-a) #t "co-a resumes with its own handler chain and catches 'boom-a")
    (assert-equal (eq? (context-resume! co-b) 'handled-b) #t "co-b resumes with its own handler chain and catches 'boom-b")
    (raise 'boom-host))
  (assert-equal (eq? (vector-ref caught-a 0) 'boom-a) #t "co-a caught 'boom-a exclusively")
  (assert-equal (eq? (vector-ref caught-b 0) 'boom-b) #t "co-b caught 'boom-b exclusively")
  (assert-equal (eq? (vector-ref caught-host 0) 'boom-host) #t "host handler chain remained intact after coroutine switches")
  (free-coroutine-context! co-a)
  (free-coroutine-context! co-b))

;; -----------------------------------------------------------------------
;; Group 8: Coroutine Exception Handler Chain After Yield (#740, Issue #787)
;; -----------------------------------------------------------------------
(write-string "--- Group 8: Coroutine Exception Handler Chain After Yield (#740, Issue #787) ---\n")
(flush-output-port)

;; 8a. Coroutine without local handler yields, then raises exception on 2nd resume
(let* ((caught (vector #f))
       (co-no-handler (make-coroutine-context
                       (lambda ()
                         (context-yield! 'first-yield)
                         ;; No local handler installed; exception must propagate to current host boundary
                         (car '())))))
  ;; 1st resume: receives yielded value
  (assert-equal (context-resume! co-no-handler) 'first-yield
                "8a.1 coroutine yields 'first-yield without local handler")
  ;; 2nd resume: exception occurs inside coroutine; must be caught by host boundary without crashing
  (guard (exn (#t
               (vector-set! caught 0 #t)
               ;; Mark terminated upon escape
               (%context-raw-u64-set! (task-stack-top (coroutine-stack co-no-handler)) -24 3)))
    (context-resume! co-no-handler))
  (assert-true (vector-ref caught 0)
               "8a.2 host boundary safely caught (car '()) from coroutine resumed after yield")
  (assert-true (coroutine-terminated? co-no-handler)
               "8a.3 coroutine marked terminated after unhandled exception")
  (free-coroutine-context! co-no-handler))

;; 8b. Coroutine yields multiple times before raising exception
(let* ((caught-multi (vector #f))
       (step (vector 0))
       (co-multi-yield (make-coroutine-context
                        (lambda ()
                          (vector-set! step 0 1)
                          (context-yield! 'step-1)
                          (vector-set! step 0 2)
                          (context-yield! 'step-2)
                          (vector-set! step 0 3)
                          (context-yield! 'step-3)
                          (vector-set! step 0 4)
                          (raise 'boom-after-3-yields)))))
  (assert-equal (context-resume! co-multi-yield) 'step-1 "8b.1 resume 1 yields step-1")
  (assert-equal (context-resume! co-multi-yield) 'step-2 "8b.2 resume 2 yields step-2")
  (assert-equal (context-resume! co-multi-yield) 'step-3 "8b.3 resume 3 yields step-3")
  (guard (exn (#t (vector-set! caught-multi 0 exn)))
    (context-resume! co-multi-yield))
  (assert-equal (vector-ref caught-multi 0) 'boom-after-3-yields
                "8b.4 host boundary caught 'boom-after-3-yields on 4th resume")
  (assert-equal (vector-ref step 0) 4 "8b.5 coroutine progressed to step 4")
  (free-coroutine-context! co-multi-yield))

;; 8c. Coroutine with local handler yields, resumes, and catches its own exception
(let* ((local-caught (vector #f))
       (co-local-handler (make-coroutine-context
                          (lambda ()
                            (guard (e (#t (vector-set! local-caught 0 e) 'local-ok))
                              (context-yield! 'yield-in-guard)
                              (raise 'local-boom))))))
  (assert-equal (context-resume! co-local-handler) 'yield-in-guard
                "8c.1 coroutine yields from within guard body")
  (assert-equal (context-resume! co-local-handler) 'local-ok
                "8c.2 coroutine resumes and its local guard catches 'local-boom")
  (assert-equal (vector-ref local-caught 0) 'local-boom
                "8c.3 local guard recorded 'local-boom")
  (free-coroutine-context! co-local-handler))

(test-end "concurrency-context_switch")
