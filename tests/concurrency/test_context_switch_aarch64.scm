;;; =======================================================================
;;; ULisp Concurrency Test Suite: ARM64 AAPCS64 Native Context Switch (#692)
;;; Tests:
;;;   Group 1: <task-stack> Allocation, 16-Byte Alignment & Canaries
;;;   Group 2: setup-task-stack Frame Layout & AAPCS64 Invariants (96B Frame)
;;;   Group 3: AAPCS64 Callee-Saved Regs (x19-x28, fp, lr) & 16-Byte Alignment
;;;   Group 4: Scheme Coroutines (context-resume!, context-yield!, P2P context-switch!)
;;;   Group 5: Context Switches Endurance Benchmark under QEMU
;;;   Group 6: Security & Boundary Guards (CWE-787 / CWE-843 / CWE-416)
;;;   Group 7: Per-Task Exception Handler Chain Isolation (#719, #740)
;;; =======================================================================

(!allow-extern #t)

;; Minimal POSIX syscall bindings for standalone AArch64 execution
(define *sys-mmap* 222)
(define *sys-munmap* 215)

(define (sys-mmap length)
  (%raw-syscall (%to-raw *sys-mmap*) 0 (%to-raw length) (%to-raw 3) (%to-raw 34) (%to-raw -1) 0))

(define (sys-munmap addr length)
  (%to-fixnum (%raw-syscall (%to-raw *sys-munmap*) (%to-raw addr) (%to-raw length) 0 0 0 0)))

(define (assq key alist)
  (if (null? alist)
      #f
      (if (eq? (car (car alist)) key)
          (car alist)
          (assq key (cdr alist)))))

(define (length lst)
  (let loop ((l lst) (n 0))
    (if (null? l) n (loop (cdr l) (+ n 1)))))

(define (string-append2 s1 s2) s1)

(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/context.scm")

(test-begin "concurrency-context_switch_aarch64")

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
;; Group 2: setup-task-stack Frame Layout & AAPCS64 Invariants (96B Frame)
;; -----------------------------------------------------------------------
(write-string "--- Group 2: setup-task-stack Frame Layout & AAPCS64 Invariants ---\n")

(let* ((stk (make-task-stack 8192))
       (dummy-fn (lambda () 123))
       (sp1 (setup-task-stack stk dummy-fn))
       (top (task-stack-top stk))
       (frame-top (- top 64))
       (entry-tramp (%asm-get-trampoline-addr 0))
       (exit-tramp (%asm-get-trampoline-addr 1))
       (frame-sz (context-frame-size)))
  (assert-equal frame-sz 96 "context-frame-size is 96 on AArch64 (12 callee-saved registers)")
  (assert-equal sp1 (- top 160) "setup-task-stack returns initial_sp = top - 160")
  (assert-equal (modulo sp1 16) 0 "initial_sp is 16-byte aligned (sp % 16 == 0)")
  (assert-equal (modulo frame-top 16) 0 "frame-top is 16-byte aligned (sp % 16 == 0)")
  (assert-equal (%context-raw-u64-ref frame-top -8) entry-tramp "[frame_top - 8] holds ulisp_task_entry_trampoline (x30/lr)")
  (assert-equal (%context-raw-u64-ref frame-top -16) frame-top "[frame_top - 16] (initial x29/fp) holds frame_top")
  (assert-equal (%context-raw-u64-ref frame-top -88) top "[frame_top - 88] (initial x20/top) holds TCB top")
  (let ((sp2 (setup-task-stack (task-stack-base stk) (task-stack-size stk) dummy-fn)))
    (assert-equal sp2 sp1 "3-arg (setup-task-stack base size entry-fn) produces identical initial_sp"))
  (free-task-stack! stk))

;; -----------------------------------------------------------------------
;; Group 3: AAPCS64 Callee-Saved Registers & 16-Byte ABI Alignment
;; -----------------------------------------------------------------------
(write-string "--- Group 3: AAPCS64 Callee-Saved Registers & Alignment ---\n")

(let ((stats0 (context-stats)))
  (assert-true (> (cdr (assq 'swap-context-addr stats0)) 0) "swap_context native code address is linked")
  (assert-true (> (cdr (assq 'entry-trampoline stats0)) 0) "ulisp_task_entry_trampoline native address is linked")
  (assert-true (> (cdr (assq 'exit-trampoline stats0)) 0) "ulisp_task_exit_trampoline native address is linked")
  (assert-equal (%asm-get-trampoline-addr 7) 96 "trampoline query 7 returns 96 (AAPCS64 frame size)"))

(let ((s1 (make-task-stack 8192))
      (s2 (make-task-stack 8192)))
  (assert-true (verify-swap-context-abi! s1 s2)
               "swap_context preserves all 12 callee-saved regs (x19-x28, x29/fp, x30/lr) & 16-byte alignment")
  (assert-true (task-stack-check-canary s1) "s1 stack canary intact after register verification")
  (assert-true (task-stack-check-canary s2) "s2 stack canary intact after register verification")
  (free-task-stack! s1)
  (free-task-stack! s2))

;; -----------------------------------------------------------------------
;; Group 4: Scheme Coroutines (Resume / Yield / Heap Alloc / P2P Switch)
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Scheme Coroutines (Resume / Yield / Heap Alloc / P2P Switch) ---\n")

;; 4a. Coroutine with multiple yields, bidirectional value passing & heap allocation
(let* ((trace (vector '()))
       (co (make-coroutine-context
            (lambda ()
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
                 "second context-resume! receives heap-allocated pair (from-co . 100)")
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
    (assert-equal (length (vector-ref ping-pong-log 0)) 5 "ping-pong-log recorded all 5 interleaved steps")
    (assert-equal (cdr (car (vector-ref ping-pong-log 0))) 220 "ctx-a received 220 from ctx-b on final switch"))

  (free-coroutine-context! (vector-ref ctx-a-box 0))
  (free-coroutine-context! (vector-ref ctx-b-box 0)))

;; 4c. Atomic Coroutine ID Allocation & Invariants
(let* ((c-base (coroutine-next-id-current))
       (co1 (make-coroutine-context (lambda () 1)))
       (co2 (make-coroutine-context (lambda () 2))))
  (assert-equal (coroutine-id co1) c-base "co1 has atomic id equal to c-base")
  (assert-equal (coroutine-id co2) (+ c-base 1) "co2 has atomic id c-base + 1")
  (free-coroutine-context! co1)
  (free-coroutine-context! co2))

;; -----------------------------------------------------------------------
;; Group 5: Context Switches Endurance Benchmark under QEMU
;; -----------------------------------------------------------------------
(write-string "--- Group 5: Context Switches Endurance Benchmark under QEMU ---\n")

(let* ((s1 (make-task-stack 8192))
       (s2 (make-task-stack 8192))
       (target-switches 100000)
       (completed (bench-swap-context! target-switches s1 s2))
       (stats (context-stats)))
  (assert-equal completed 100000 "100,000 native AAPCS64 swap_context switches completed with 0 faults under QEMU")
  (assert-true (task-stack-check-canary s1) "s1 stack canary uncorrupted after 100,000 switches")
  (assert-true (task-stack-check-canary s2) "s2 stack canary uncorrupted after 100,000 switches")
  (assert-true (>= (cdr (assq 'total-switches stats)) 100000)
               "context-stats total-switches >= 100,000")
  (free-task-stack! s1)
  (free-task-stack! s2))

;; -----------------------------------------------------------------------
;; Group 6: Security & Boundary Guards (CWE-787 / CWE-843 / CWE-416)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Security & Boundary Guards (CWE-787 / CWE-843 / CWE-416) ---\n")

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

(test-end "concurrency-context_switch_aarch64")
