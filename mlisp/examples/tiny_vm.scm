;;; =======================================================================
;;; MLisp Example: Tiny Bytecode Virtual Machine (tiny_vm.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; 100% Pure Scheme Implementation of a Stack-Based Bytecode VM.
;;; Demonstrates RPython-style language implementation:
;;; - Author writes ONLY a simple interpreter loop
;;; - Inserts (jit-merge-point pc env) at loop header
;;; - MLisp automatically transforms it into an optimized JIT execution!
;;; =======================================================================

;;; Bytecode Instructions:
;;;   (PUSH val)       : Pushes constant to stack
;;;   (ADD)            : Pops b, pops a, pushes a + b
;;;   (SUB)            : Pops b, pops a, pushes a - b
;;;   (LOAD var)       : Pushes value of variable
;;;   (STORE var)      : Pops value and stores to variable
;;;   (JUMP target-pc) : Unconditional jump to target-pc
;;;   (JUMP-IF-LT target-pc) : Pops b, pops a; jumps if a < b
;;;   (HALT)           : Stops execution and returns top of stack

(define (vm-lookup-var env var)
  (let ((entry (assq var env)))
    (if entry (cdr entry) 0)))

(define (vm-store-var env var val)
  (cons (cons var val) (filter (lambda (e) (not (eq? (car e) var))) env)))

;;; Execute a TinyVM bytecode program with MLisp endogenous meta-tracing
(define (run-tiny-vm code initial-env)
  (let loop ((pc 0)
             (stack '())
             (env initial-env))
    (if (>= pc (length code))
        (if (null? stack) env (car stack))
        (let* ((inst (list-ref code pc))
               (op (car inst)))
          (case op
            ;; Loop header instruction triggers JIT merge point
            ((LOOP-HEADER)
             (let ((jit-status (jit-merge-point pc env)))
               (loop (+ pc 1) stack env)))

            ((PUSH)
             (let ((val (cadr inst)))
               (trace-record! '%mov 'reg-val val)
               (loop (+ pc 1) (cons val stack) env)))

            ((LOAD)
             (let* ((var (cadr inst))
                    (val (vm-lookup-var env var)))
               (trace-guard! 'type-fixnum val 'fixnum 'exit-guard)
               (trace-record! '%mov var val)
               (loop (+ pc 1) (cons val stack) env)))

            ((STORE)
             (let* ((var (cadr inst))
                    (val (car stack))
                    (new-stack (cdr stack))
                    (new-env (vm-store-var env var val)))
               (trace-record! '%mov var val)
               (loop (+ pc 1) new-stack new-env)))

            ((ADD)
             (let* ((b (car stack))
                    (a (cadr stack))
                    (rest-stack (cddr stack))
                    (res (+ a b)))
               (trace-record! '%add 'reg-res a b)
               (loop (+ pc 1) (cons res rest-stack) env)))

            ((SUB)
             (let* ((b (car stack))
                    (a (cadr stack))
                    (rest-stack (cddr stack))
                    (res (- a b)))
               (trace-record! '%sub 'reg-res a b)
               (loop (+ pc 1) (cons res rest-stack) env)))

            ((JUMP)
             (let ((target (cadr inst)))
               (loop target stack env)))

            ((JUMP-IF-LT)
             (let* ((target (cadr inst))
                    (limit (car stack))
                    (val (cadr stack))
                    (rest-stack (cddr stack)))
               (trace-guard! 'cmp-lt val limit 'exit-guard)
               (if (< val limit)
                   (loop target rest-stack env)
                   (loop (+ pc 1) rest-stack env))))

            ((HALT)
             (if (null? stack) env (car stack)))

            (else
             (error "Unknown TinyVM opcode:" op)))))))
