;;; =======================================================================
;;; ULisp R7RS-large / SRFI 158 & SRFI 121 Generators & Accumulators Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #704
;;; =======================================================================

(define (test name expected actual)
  (if (equal? expected actual)
      (begin
        (write-string "  [PASS] ")
        (write-string name)
        (write-char #\newline)
        (flush-output-port)
        #t)
      (begin
        (write-string "  [FAIL] ")
        (write-string name)
        (write-string " - Expected: ")
        (display expected)
        (write-string ", Actual: ")
        (display actual)
        (write-char #\newline)
        (flush-output-port)
        (exit 1))))

(write-string "=== Running ULisp SRFI 158 Generators & Accumulators Test Suite ===\n")

;;; --- Test 1: Generator Constructors ---
(write-string "--- Test 1: Generator Constructors ---\n")
(test "empty generator returns eof" #t (eof-object? ((generator))))
(test "generator->list basic" '(10 20 30) (generator->list (generator 10 20 30)))
(test "circular-generator take 5" '(a b a b a) (generator->list (circular-generator 'a 'b) 5))
(test "make-iota-generator default" '(0 1 2 3) (generator->list (make-iota-generator 4)))
(test "make-iota-generator start step" '(10 13 16) (generator->list (make-iota-generator 3 10 3)))
(test "make-range-generator bounded" '(2 3 4 5) (generator->list (make-range-generator 2 6)))
(test "make-range-generator step" '(10 8 6) (generator->list (make-range-generator 10 4 -2)))
(test "make-range-generator infinite take 4" '(5 6 7 8) (generator->list (make-range-generator 5) 4))
(test "list->generator" '(x y z) (generator->list (list->generator '(x y z))))
(test "vector->generator full" '(1 2 3) (generator->list (vector->generator (vector 1 2 3))))
(test "vector->generator subrange" '(20 30) (generator->list (vector->generator (vector 10 20 30 40) 1 3)))
(test "reverse-vector->generator" '(3 2 1) (generator->list (reverse-vector->generator (vector 1 2 3))))
(test "string->generator" '(#\h #\i) (generator->list (string->generator "hi")))
(test "bytevector->generator" '(65 66) (generator->list (bytevector->generator (bytevector 65 66))))
(test "make-for-each-generator" '(1 2 3) (generator->list (make-for-each-generator for-each '(1 2 3))))
(test "make-unfold-generator"
      '(0 2 4 6)
      (generator->list (make-unfold-generator (lambda (s) (> s 3))
                                              (lambda (s) (* s 2))
                                              (lambda (s) (+ s 1))
                                              0)))

;;; --- Test 2: Coroutine Generator ---
(write-string "--- Test 2: Coroutine Generator ---\n")
(let ((g (make-coroutine-generator
          (lambda (yield)
            (let loop ((i 1))
              (if (<= i 4)
                  (begin
                    (yield (* i 10))
                    (loop (+ i 1)))
                  #f))))))
  (test "make-coroutine-generator yields sequence" '(10 20 30 40) (generator->list g))
  (test "make-coroutine-generator stays at eof" #t (eof-object? (g))))

;;; --- Test 3: Generator Operations & Combinators ---
(write-string "--- Test 3: Generator Operations & Combinators ---\n")
(test "gcons*" '(1 2 3 4) (generator->list (gcons* 1 2 (generator 3 4))))
(test "gappend" '(1 2 3 4 5) (generator->list (gappend (generator 1 2) (generator) (generator 3 4 5))))
(test "gflatten" '(1 2 3 4 5) (generator->list (gflatten (generator '(1 2) '() '(3 4 5)))))
(test "ggroup exact" '((1 2) (3 4)) (generator->list (ggroup (make-range-generator 1 5) 2)))
(test "ggroup partial" '((1 2) (3)) (generator->list (ggroup (make-range-generator 1 4) 2)))
(test "ggroup padded" '((1 2) (3 0)) (generator->list (ggroup (make-range-generator 1 4) 2 0)))
(test "gmerge"
      '(1 2 3 4 5 6)
      (generator->list (gmerge (lambda (a b) (< a b))
                               (generator 1 3 5)
                               (generator 2 4 6))))
(test "gmap single" '(2 4 6) (generator->list (gmap (lambda (x) (* x 2)) (generator 1 2 3))))
(test "gmap multi" '(11 22 33) (generator->list (gmap (lambda (a b) (+ a b)) (generator 1 2 3) (generator 10 20 30 40))))
(test "gcombine running sum"
      '(1 3 6 10)
      (generator->list
       (gcombine (lambda (x acc)
                   (let ((next (+ x acc)))
                     (values next next)))
                 0
                 (generator 1 2 3 4))))
(test "gfilter" '(2 4) (generator->list (gfilter (lambda (x) (= (modulo x 2) 0)) (make-range-generator 1 6))))
(test "gremove" '(1 3 5) (generator->list (gremove (lambda (x) (= (modulo x 2) 0)) (make-range-generator 1 6))))
(test "gtake and gdrop" '(3 4 5) (generator->list (gtake (gdrop (make-range-generator 0 10) 3) 3)))
(test "gtake padded" '(1 2 99 99) (generator->list (gtake (generator 1 2) 4 99)))
(test "gtake-while" '(0 1 2) (generator->list (gtake-while (lambda (x) (< x 3)) (make-range-generator 0 6))))
(test "gdrop-while" '(3 4 5) (generator->list (gdrop-while (lambda (x) (< x 3)) (make-range-generator 0 6))))
(test "gdelete" '(1 3 4) (generator->list (gdelete 2 (generator 1 2 3 2 4))))
(test "gdelete-neighbor-dups" '(1 2 3 2 1) (generator->list (gdelete-neighbor-dups (list->generator '(1 1 2 2 2 3 2 2 1)))))
(test "gindex" '(b d) (generator->list (gindex (list->generator '(a b c d e)) (generator 1 3))))
(test "gselect" '(a c e) (generator->list (gselect (list->generator '(a b c d e)) (list->generator '(#t #f #t #f #t)))))

;;; --- Test 4: Generator Consumers ---
(write-string "--- Test 4: Generator Consumers ---\n")
(test "generator->reverse-list" '(3 2 1) (generator->reverse-list (generator 1 2 3)))
(test "generator->vector" (vector 10 20) (generator->vector (generator 10 20)))
(test "generator->string" "abc" (generator->string (generator #\a #\b #\c)))
(test "generator-fold" 10 (generator-fold (lambda (x acc) (+ x acc)) 0 (generator 1 2 3 4)))
(test "generator-map->list" '(2 4 6) (generator-map->list (lambda (x) (* x 2)) (generator 1 2 3)))
(test "generator-find" 4 (generator-find (lambda (x) (> x 3)) (generator 1 2 4 5)))
(test "generator-count" 3 (generator-count (lambda (x) (> x 2)) (generator 1 2 3 4 5)))
(test "generator-any" #t (generator-any (lambda (x) (= x 3)) (generator 1 2 3 4)))
(test "generator-every" #t (generator-every (lambda (x) (> x 0)) (generator 1 2 3)))

;;; --- Test 5: Accumulators (SRFI 158) ---
(write-string "--- Test 5: Accumulators ---\n")
(let ((acc (list-accumulator)))
  (acc 'a)
  (acc 'b)
  (acc 'c)
  (test "list-accumulator result" '(a b c) (acc (eof-object))))

(let ((acc (reverse-list-accumulator)))
  (acc 1)
  (acc 2)
  (acc 3)
  (test "reverse-list-accumulator result" '(3 2 1) (acc (eof-object))))

(let ((acc (count-accumulator)))
  (acc 'x)
  (acc 'y)
  (test "count-accumulator result" 2 (acc (eof-object))))

(let ((acc (sum-accumulator)))
  (acc 10)
  (acc 20)
  (acc 5)
  (test "sum-accumulator result" 35 (acc (eof-object))))

(let ((acc (product-accumulator)))
  (acc 2)
  (acc 3)
  (acc 4)
  (test "product-accumulator result" 24 (acc (eof-object))))

(let ((acc (string-accumulator)))
  (acc #\u)
  (acc #\l)
  (acc #\i)
  (acc #\s)
  (acc #\p)
  (test "string-accumulator result" "ulisp" (acc (eof-object))))

(let ((acc (vector-accumulator)))
  (acc 7)
  (acc 8)
  (test "vector-accumulator result" (vector 7 8) (acc (eof-object))))

(let ((acc (bytevector-accumulator)))
  (acc 10)
  (acc 20)
  (test "bytevector-accumulator result" (bytevector 10 20) (acc (eof-object))))

(write-string "=== All SRFI 158 Generators & Accumulators Tests Passed Successfully! ===\n")

