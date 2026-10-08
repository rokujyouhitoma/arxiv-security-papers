;;; =======================================================================
;;; ULisp Compiler Pass 3: Low-Level Assembly Emitter & Symbol/String Tables
;;; Conforms to DSN-33 Architecture Specification
;;; =======================================================================

;;; Boxed global counters and tables for closure sharing
(define *label-counter* (cons 0 '()))
(define (unique-label prefix)
  (let ((l (string-append "." prefix "_" (number->string (car *label-counter*)))))
    (set-car! *label-counter* (+ (car *label-counter*) 1))
    l))

(define *symbol-table* (cons '() '()))
(define (intern-symbol sym)
  (let ((entry (assq sym (car *symbol-table*))))
    (if entry
        (cdr entry)
        (let ((id (+ (* (length (car *symbol-table*)) 256) 2)))
          (set-car! *symbol-table* (cons (cons sym id) (car *symbol-table*)))
          id))))

(define *string-counter* (cons 0 '()))
(define *strings* (cons '() '()))
(define (intern-string str)
  (let ((label (string-append ".L_str_" (number->string (car *string-counter*)))))
    (set-car! *string-counter* (+ (car *string-counter*) 1))
    (set-car! *strings* (cons (cons label str) (car *strings*)))
    label))

(define (emit-string-literal str)
  (let ((label (intern-string str)))
    (emit (string-append "    lea rax, [rip + " label " + 3]"))))

;;; Accumulated compiled lambda code blocks (boxed list)
(define *lambdas* (cons '() '()))

(define (emit line)
  (display line)
  (newline))

(define (emit-boolean-from-set set-inst)
  (emit (string-append "    " set-inst " al"))
  (emit "    movzx eax, al")
  (emit "    shl rax, 6")
  (emit "    add rax, 0x2F"))

(define (emit-boolean)
  (emit-boolean-from-set "sete"))

(define (offset->string offset)
  (if (< offset 0)
      (string-append "- " (number->string (- 0 offset)))
      (string-append "+ " (number->string offset))))

(define (align-frame-shift needed)
  (if (= (modulo needed 16) 8)
      needed
      (+ needed 8)))
