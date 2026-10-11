;;; =======================================================================
;;; MLisp Standalone Native AOT Executable: TinyVM (tiny_vm_aot.scm)
;;; Conforms to DSN-34 & RPython One-Binary Architecture
;;; =======================================================================

(define (memq item ls)
  (cond
    ((null? ls) #f)
    ((eq? (car ls) item) ls)
    (else (memq item (cdr ls)))))

(define (cadr x) (car (cdr x)))
(define (cddr x) (cdr (cdr x)))

(define (assq key ls)
  (cond
    ((null? ls) #f)
    ((eq? (car (car ls)) key) (car ls))
    (else (assq key (cdr ls)))))

(define (filter pred ls)
  (cond
    ((null? ls) '())
    ((pred (car ls)) (cons (car ls) (filter pred (cdr ls))))
    (else (filter pred (cdr ls)))))

(define (list-ref ls n)
  (if (= n 0)
      (car ls)
      (list-ref (cdr ls) (- n 1))))

(define (vm-lookup-var env var)
  (let ((entry (assq var env)))
    (if entry (cdr entry) 0)))

(define (vm-store-var env var val)
  (cons (cons var val) (filter (lambda (e) (not (eq? (car e) var))) env)))

(define (run-tiny-vm code initial-env)
  (let loop ((pc 0)
             (stack '())
             (env initial-env))
    (if (>= pc (length code))
        (if (null? stack) env (car stack))
        (let* ((inst (list-ref code pc))
               (op (car inst)))
          (case op
            ((LOOP-HEADER)
             (loop (+ pc 1) stack env))

            ((PUSH)
             (let ((val (cadr inst)))
               (loop (+ pc 1) (cons val stack) env)))

            ((LOAD)
             (let* ((var (cadr inst))
                    (val (vm-lookup-var env var)))
               (loop (+ pc 1) (cons val stack) env)))

            ((STORE)
             (let* ((var (cadr inst))
                    (val (car stack))
                    (new-stack (cdr stack))
                    (new-env (vm-store-var env var val)))
               (loop (+ pc 1) new-stack new-env)))

            ((ADD)
             (let* ((b (car stack))
                    (a (cadr stack))
                    (rest-stack (cddr stack))
                    (res (+ a b)))
               (loop (+ pc 1) (cons res rest-stack) env)))

            ((SUB)
             (let* ((b (car stack))
                    (a (cadr stack))
                    (rest-stack (cddr stack))
                    (res (- a b)))
               (loop (+ pc 1) (cons res rest-stack) env)))

            ((JUMP)
             (let ((target (cadr inst)))
               (loop target stack env)))

            ((JUMP-IF-LT)
             (let* ((target (cadr inst))
                    (limit (car stack))
                    (val (cadr stack))
                    (rest-stack (cddr stack)))
               (if (< val limit)
                   (loop target rest-stack env)
                   (loop (+ pc 1) rest-stack env))))

            ((HALT)
             (if (null? stack) env (car stack)))

            (else 0))))))

(define (main)
  (display-string "==================================================================\n")
  (display-string "  MLisp Native AOT Standalone Binary (RPython-Style Target)       \n")
  (display-string "==================================================================\n")
  (display-string ">>> Running TinyVM Bytecode Stack Machine...\n")
  (display-string "    Target: sum = 0; i = 0; while (i < 5) { sum += i; i += 1; }\n")
  (display-string "    => Result: sum = ")
  (let* ((prog '((PUSH 0) (STORE sum)
                 (PUSH 0) (STORE i)
                 (LOOP-HEADER)
                 (LOAD sum)
                 (LOAD i)
                 (ADD)
                 (STORE sum)
                 (LOAD i)
                 (PUSH 1)
                 (ADD)
                 (STORE i)
                 (LOAD i)
                 (PUSH 5)
                 (JUMP-IF-LT 4)
                 (LOAD sum)
                 (HALT)))
         (res (run-tiny-vm prog '())))
    res))

(main)
