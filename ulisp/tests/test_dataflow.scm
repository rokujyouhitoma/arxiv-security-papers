;;; =======================================================================
;;; ULisp Generic Dataflow Analysis Framework Test Suite
;;; Conforms to Issue #599 & DSN-33 Architecture Specification
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Generic Dataflow Analysis Test Suite\n")
(display "=======================================================\n")

(define *df-test-count* (cons 0 '()))
(define *df-pass-count* (cons 0 '()))

(define (df-assert-true name expr-result)
  (set-car! *df-test-count* (+ (car *df-test-count*) 1))
  (if expr-result
      (begin
        (set-car! *df-pass-count* (+ (car *df-pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

(define (df-assert-false name expr-result)
  (set-car! *df-test-count* (+ (car *df-test-count*) 1))
  (if (not expr-result)
      (begin
        (set-car! *df-pass-count* (+ (car *df-pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] Expected failure/rejection: ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

(define (df-assert-equal name expected actual)
  (set-car! *df-test-count* (+ (car *df-test-count*) 1))
  (if (equal? expected actual)
      (begin
        (set-car! *df-pass-count* (+ (car *df-pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (display " - Expected: ")
        (write expected)
        (display " but got: ")
        (write actual)
        (newline)
        (error "Assertion failed" name))))

;;; -----------------------------------------------------------------------
;;; Group 1: Boolean Lattice Tests
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Boolean Lattice Tests ---\n")

(let ((bl (make-boolean-lattice 'bool-lat)))
  (df-assert-true "lattice? on boolean lattice" (lattice? bl))
  (df-assert-equal "boolean lattice bottom" #f (lattice-bottom bl))
  (df-assert-equal "boolean lattice top" #t (lattice-top bl))
  ;; Order: #f <= #f, #f <= #t, #t <= #t, not (#t <= #f)
  (df-assert-true "bool #f <= #f" (lattice-leq? bl #f #f))
  (df-assert-true "bool #f <= #t" (lattice-leq? bl #f #t))
  (df-assert-true "bool #t <= #t" (lattice-leq? bl #t #t))
  (df-assert-false "bool not (#t <= #f)" (lattice-leq? bl #t #f))
  ;; Join
  (df-assert-equal "bool join #f #f" #f (lattice-join bl #f #f))
  (df-assert-equal "bool join #f #t" #t (lattice-join bl #f #t))
  (df-assert-equal "bool join #t #f" #t (lattice-join bl #t #f))
  (df-assert-equal "bool join #t #t" #t (lattice-join bl #t #t))
  ;; Meet
  (df-assert-equal "bool meet #f #f" #f (lattice-meet bl #f #f))
  (df-assert-equal "bool meet #f #t" #f (lattice-meet bl #f #t))
  (df-assert-equal "bool meet #t #t" #t (lattice-meet bl #t #t)))

;;; -----------------------------------------------------------------------
;;; Group 2: Flat Lattice Tests
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Flat Lattice Tests ---\n")

(let ((fl (make-flat-lattice 'const-flat equal?)))
  (df-assert-true "flat lattice bottom <= 42" (lattice-leq? fl *df-bottom* 42))
  (df-assert-true "flat 42 <= 42" (lattice-leq? fl 42 42))
  (df-assert-true "flat 42 <= top" (lattice-leq? fl 42 *df-top*))
  (df-assert-false "flat not (42 <= 99)" (lattice-leq? fl 42 99))
  (df-assert-false "flat not (top <= 42)" (lattice-leq? fl *df-top* 42))
  ;; Join
  (df-assert-equal "flat join bot 42 -> 42" 42 (lattice-join fl *df-bottom* 42))
  (df-assert-equal "flat join 42 42 -> 42" 42 (lattice-join fl 42 42))
  (df-assert-equal "flat join 42 99 -> top" *df-top* (lattice-join fl 42 99))
  (df-assert-equal "flat join 42 top -> top" *df-top* (lattice-join fl 42 *df-top*))
  ;; Meet
  (df-assert-equal "flat meet top 42 -> 42" 42 (lattice-meet fl *df-top* 42))
  (df-assert-equal "flat meet 42 42 -> 42" 42 (lattice-meet fl 42 42))
  (df-assert-equal "flat meet 42 99 -> bot" *df-bottom* (lattice-meet fl 42 99)))

;;; -----------------------------------------------------------------------
;;; Group 3: Powerset Lattice Tests
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Powerset Lattice Tests ---\n")

(let ((ps (make-powerset-lattice 'vars-set #f)))
  (df-assert-equal "powerset bottom is '()" '() (lattice-bottom ps))
  (df-assert-true "'() <= '(a b)" (lattice-leq? ps '() '(a b)))
  (df-assert-true "'(a) <= '(a b)" (lattice-leq? ps '(a) '(a b)))
  (df-assert-false "not ('(a c) <= '(a b))" (lattice-leq? ps '(a c) '(a b)))
  ;; Join = union
  (let ((j (lattice-join ps '(a b) '(b c))))
    (df-assert-true "join contains a" (if (memq 'a j) #t #f))
    (df-assert-true "join contains b" (if (memq 'b j) #t #f))
    (df-assert-true "join contains c" (if (memq 'c j) #t #f))
    (df-assert-equal "join length is 3" 3 (length j)))
  ;; Meet = intersect
  (let ((m (lattice-meet ps '(a b) '(b c))))
    (df-assert-equal "meet is '(b)" '(b) m)))

;;; -----------------------------------------------------------------------
;;; Group 4: Map / Environment Lattice Tests
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Map / Environment Lattice Tests ---\n")

(let* ((flat-lat (make-flat-lattice 'const equal?))
       (map-lat (make-map-lattice 'env-lat flat-lat))
       (env1 '((x . 10) (y . 20)))
       (env2 '((x . 10) (y . 30) (z . 40))))
  ;; Unbound in env1 (e.g. z) is bottom, so env1 <= env2 fails because y: 20 <= 30 is false
  (df-assert-false "not (env1 <= env2) because y conflict" (lattice-leq? map-lat env1 env2))
  (let ((env-same '((x . 10) (y . 20))))
    (df-assert-true "env1 <= env-same" (lattice-leq? map-lat env1 env-same)))
  ;; Join env1 and env2: x->10, y->*df-top*, z->40
  (let ((joined (lattice-join map-lat env1 env2)))
    (df-assert-equal "joined x is 10" 10 (cdr (assq 'x joined)))
    (df-assert-equal "joined y is *df-top*" *df-top* (cdr (assq 'y joined)))
    (df-assert-equal "joined z is 40" 40 (cdr (assq 'z joined)))))

;;; -----------------------------------------------------------------------
;;; Group 5: Forward Analysis: Reaching Definitions on CFG
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Forward Dataflow: Reaching Definitions ---\n")

;;; CFG Structure:
;;;        [entry] (d1: x=1, d2: y=2)
;;;        /     \
;;;   [b1] (d3: x=3)  [b2] (d4: y=4)
;;;        \     /
;;;        [exit] (uses x, y)
(let* ((nodes '(entry b1 b2 exit))
       (entry-nodes '(entry))
       (succs (lambda (n)
                (case n
                  ((entry) '(b1 b2))
                  ((b1) '(exit))
                  ((b2) '(exit))
                  ((exit) '()))))
       (preds (lambda (n)
                (case n
                  ((entry) '())
                  ((b1) '(entry))
                  ((b2) '(entry))
                  ((exit) '(b1 b2)))))
       ;; Gen/Kill table: (node gen kill)
       ;; d1: x, d2: y, d3: x, d4: y
       (gen-kill '((entry (d1 d2) ())
                   (b1 (d3) (d1))
                   (b2 (d4) (d2))
                   (exit () ())))
       (prob (make-reaching-defs-problem 'test-rd gen-kill))
       (results (dataflow-analyze prob nodes entry-nodes preds succs)))

  (let ((entry-out (dataflow-result-out results 'entry))
        (b1-out (dataflow-result-out results 'b1))
        (b2-out (dataflow-result-out results 'b2))
        (exit-in (dataflow-result-in results 'exit)))
    (df-assert-true "entry-out has d1" (if (memq 'd1 entry-out) #t #f))
    (df-assert-true "entry-out has d2" (if (memq 'd2 entry-out) #t #f))
    ;; b1 kills d1 and gens d3, keeps d2
    (df-assert-true "b1-out has d3" (if (memq 'd3 b1-out) #t #f))
    (df-assert-true "b1-out has d2" (if (memq 'd2 b1-out) #t #f))
    (df-assert-false "b1-out does not have d1 (killed)" (if (memq 'd1 b1-out) #t #f))
    ;; b2 kills d2 and gens d4, keeps d1
    (df-assert-true "b2-out has d4" (if (memq 'd4 b2-out) #t #f))
    (df-assert-true "b2-out has d1" (if (memq 'd1 b2-out) #t #f))
    (df-assert-false "b2-out does not have d2 (killed)" (if (memq 'd2 b2-out) #t #f))
    ;; exit-in is join of b1-out and b2-out: {d1, d2, d3, d4}
    (df-assert-true "exit-in has d1" (if (memq 'd1 exit-in) #t #f))
    (df-assert-true "exit-in has d2" (if (memq 'd2 exit-in) #t #f))
    (df-assert-true "exit-in has d3" (if (memq 'd3 exit-in) #t #f))
    (df-assert-true "exit-in has d4" (if (memq 'd4 exit-in) #t #f))))

;;; -----------------------------------------------------------------------
;;; Group 6: Backward Analysis: Liveness on CFG with Loop
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Backward Dataflow: Liveness Analysis ---\n")

;;; CFG with Loop:
;;;   [entry] def: {i, n} use: {}
;;;      |
;;;   [loop]  def: {}     use: {i, n}
;;;    /  \
;;; [body] [exit] use: {i}
;;;   |
;;; (back to loop) def: {i} use: {i}
(let* ((nodes '(entry loop body exit))
       (exit-nodes '(exit))
       (succs (lambda (n)
                (case n
                  ((entry) '(loop))
                  ((loop) '(body exit))
                  ((body) '(loop))
                  ((exit) '()))))
       (preds (lambda (n)
                (case n
                  ((entry) '())
                  ((loop) '(entry body))
                  ((body) '(loop))
                  ((exit) '(loop)))))
       (def-use '((entry (i n) ())
                  (loop () (i n))
                  (body (i) (i))
                  (exit () (i))))
       (prob (make-liveness-problem 'test-live def-use))
       ;; In backward analysis, exit-nodes acts as boundary
       (results (dataflow-analyze prob nodes exit-nodes preds succs)))

  (let ((exit-in (dataflow-result-in results 'exit))
        (loop-in (dataflow-result-in results 'loop))
        (entry-out (dataflow-result-out results 'entry))
        (entry-in (dataflow-result-in results 'entry)))
    (df-assert-true "exit-in has i" (if (memq 'i exit-in) #t #f))
    (df-assert-true "loop-in has i" (if (memq 'i loop-in) #t #f))
    (df-assert-true "loop-in has n" (if (memq 'n loop-in) #t #f))
    (df-assert-true "entry-out has i" (if (memq 'i entry-out) #t #f))
    (df-assert-true "entry-out has n" (if (memq 'n entry-out) #t #f))
    ;; entry defines i and n, so before entry, neither is live
    (df-assert-equal "entry-in is '() (no live vars before entry)" '() entry-in)))

;;; -----------------------------------------------------------------------
;;; Summary Report
;;; -----------------------------------------------------------------------
(display "\n=======================================================\n")
(display " Dataflow Test Suite Completed: ")
(display (car *df-pass-count*))
(display "/")
(display (car *df-test-count*))
(display " PASS\n")
(display "=======================================================\n")
