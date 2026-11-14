;;; =======================================================================
;;; ULisp Test Suite: R7RS §6.13.3 Output Procedures & Datum Labels
;;; Conforms to DSN-33 Architecture Specification & Issue #656
;;; Tests write-simple, write-shared, write, display, newline
;;; =======================================================================

(test-begin "printer")

(define-syntax assert-equal
  (syntax-rules ()
    ((assert-equal name actual expected)
     (test-equal name expected actual))))

(define-syntax assert-true
  (syntax-rules ()
    ((assert-true name expr)
     (test-assert name expr))))

(define-syntax assert-false
  (syntax-rules ()
    ((assert-false name expr)
     (test-assert name (not expr)))))




;;; -----------------------------------------------------------------------
;;; Intern Symbols for runtime symbol->string lookups
;;; -----------------------------------------------------------------------
(define sym-alpha (string->symbol "alpha"))
(define sym-a (string->symbol "a"))
(define sym-b (string->symbol "b"))
(define sym-c (string->symbol "c"))
(define sym-x (string->symbol "x"))
(define sym-y (string->symbol "y"))

;;; -----------------------------------------------------------------------
;;; Capture Helpers
;;; -----------------------------------------------------------------------

(define (capture-write-simple x)
  (let ((p (open-output-string)))
    (write-simple x p)
    (get-output-string p)))

(define (capture-write-shared x)
  (let ((p (open-output-string)))
    (write-shared x p)
    (get-output-string p)))

(define (capture-write x)
  (let ((p (open-output-string)))
    (write x p)
    (get-output-string p)))

(define (capture-display x)
  (let ((p (open-output-string)))
    (display x p)
    (get-output-string p)))

;;; -----------------------------------------------------------------------
;;; Safe Heap Cyclic Data Constructors (Guaranteed Escape from Stack)
;;; -----------------------------------------------------------------------

(define (make-circular-pair val)
  (let ((c (cons val '())))
    (set-cdr! c c)
    c))

(define (make-circular-2 a b)
  (let* ((tail (cons b '()))
         (head (cons a tail)))
    (set-cdr! tail head)
    head))

(define (make-circular-car)
  (let ((c (cons '() '())))
    (set-car! c c)
    c))

(define (make-cycle-tail head-val a b)
  (let* ((tail (cons b '()))
         (mid (cons a tail))
         (head (cons head-val mid)))
    (set-cdr! tail mid)
    head))

(define (make-circular-vector val)
  (let ((v (vector val 0)))
    (vector-set! v 1 v)
    v))

(define (make-mutual-vectors val1 val2)
  (let ((v1 (vector val1 0))
        (v2 (vector val2 0)))
    (vector-set! v1 1 v2)
    (vector-set! v2 1 v1)
    v1))

;;; -----------------------------------------------------------------------
;;; Test Suite Execution
;;; -----------------------------------------------------------------------

;; --- Group 1: write-simple basic output ---
(write-string "--- Group 1: write-simple basic output ---\n")
(assert-equal "write-simple integer" (capture-write-simple 123) "123")
(assert-equal "write-simple negative integer" (capture-write-simple -45) "-45")
(assert-equal "write-simple string with escape" (capture-write-simple "hello\nworld") "\"hello\\nworld\"")
(assert-equal "write-simple character literal" (capture-write-simple #\a) "#\\a")
(assert-equal "write-simple space character" (capture-write-simple #\space) "#\\space")
(assert-equal "write-simple symbol" (capture-write-simple sym-alpha) "alpha")
(assert-equal "write-simple boolean #t" (capture-write-simple #t) "#t")
(assert-equal "write-simple boolean #f" (capture-write-simple #f) "#f")
(assert-equal "write-simple empty list" (capture-write-simple '()) "()")
(assert-equal "write-simple proper list" (capture-write-simple '(1 2 3)) "(1 2 3)")
(assert-equal "write-simple dotted pair" (capture-write-simple '(1 . 2)) "(1 . 2)")
(assert-equal "write-simple vector" (capture-write-simple #(1 2 3)) "#(1 2 3)")

;; --- Group 2: write-shared non-shared output ---
(write-string "--- Group 2: write-shared non-shared output ---\n")
(assert-equal "write-shared integer" (capture-write-shared 42) "42")
(assert-equal "write-shared string" (capture-write-shared "test") "\"test\"")
(assert-equal "write-shared proper list" (capture-write-shared (list sym-a sym-b sym-c)) "(a b c)")
(assert-equal "write-shared vector" (capture-write-shared #(1 "two" 3)) "#(1 \"two\" 3)")
(assert-equal "write-shared nested list" (capture-write-shared '((1 2) (3 4))) "((1 2) (3 4))")

;; --- Group 3: write-shared circular list datum label output ---
(write-string "--- Group 3: write-shared circular list datum label output ---\n")
(let ((c1 (make-circular-pair 1)))
  (assert-equal "write-shared self-referencing cdr" (capture-write-shared c1) "#1=(1 . #1#)"))

(let ((c2 (make-circular-2 1 2)))
  (assert-equal "write-shared 2-element cycle" (capture-write-shared c2) "#1=(1 2 . #1#)"))

(let ((c3 (make-circular-car)))
  (assert-equal "write-shared self-referencing car" (capture-write-shared c3) "#1=(#1#)"))

(let ((head (make-cycle-tail 1 2 3)))
  (assert-equal "write-shared cycle in tail" (capture-write-shared head) "(1 . #1=(2 3 . #1#))"))

;; --- Group 4: write-shared circular vector datum label output ---
(write-string "--- Group 4: write-shared circular vector datum label output ---\n")
(let ((v1 (make-circular-vector 1)))
  (assert-equal "write-shared self-referencing vector" (capture-write-shared v1) "#1=#(1 #1#)"))

(let ((v1 (make-mutual-vectors 1 2)))
  (assert-equal "write-shared mutually referencing vectors" (capture-write-shared v1) "#1=#(1 #(2 #1#))"))

(let* ((v1 (make-mutual-vectors 1 2))
       (v2 (vector-ref v1 1))
       (pair-v (list v1 v2)))
  (assert-equal "write-shared mutual vectors in list" (capture-write-shared pair-v) "(#1=#(1 #2=#(2 #1#)) #2#)"))

;; --- Group 5: write-shared DAG shared structure datum label output ---
(write-string "--- Group 5: write-shared DAG shared structure datum label output ---\n")
(let ((sub (list sym-a sym-b)))
  (let ((dag (list sub sub)))
    (assert-equal "write-shared shared sublist in list" (capture-write-shared dag) "(#1=(a b) #1#)")))

(let ((sub-v (vector 10 20)))
  (let ((dag-v (list sub-v sub-v)))
    (assert-equal "write-shared shared vector in list" (capture-write-shared dag-v) "(#1=#(10 20) #1#)")))

;; --- Group 6: write cycle safety (R7RS §6.13.3) ---
(write-string "--- Group 6: write cycle safety ---\n")
(let ((c (make-circular-2 sym-x sym-y)))
  (assert-equal "write cycle produces shared datum label" (capture-write c) "#1=(x y . #1#)"))

;; --- Group 7: First-class procedural wrappers & case-lambda ---
(write-string "--- Group 7: First-class procedural wrappers & case-lambda ---\n")
(assert-true "procedure? write-simple" (procedure? write-simple))
(assert-true "procedure? write-shared" (procedure? write-shared))
(assert-true "procedure? write" (procedure? write))
(assert-true "procedure? display" (procedure? display))
(assert-true "procedure? newline" (procedure? newline))

(let ((procs (list write-simple write-shared write display newline)))
  (let loop ((ps procs))
    (if (pair? ps)
        (begin
          (assert-true "higher-order procedure check" (procedure? (car ps)))
          (loop (cdr ps)))
        #t)))

;; Check display without quotes
(assert-equal "display string without quotes" (capture-display "hello") "hello")
(assert-equal "display char direct" (capture-display #\z) "z")

(test-end "printer")
