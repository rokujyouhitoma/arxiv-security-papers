;;; =======================================================================
;;; ULisp Test Suite: R7RS define-record-type (Issue #549 / R7RS Section 5.5)
;;; =======================================================================

;; 1. 基本的な 2次元ポイント型
(define-record-type point
  (make-point x y)
  point?
  (x point-x point-set-x!)
  (y point-y point-set-y!))

;; 2. 読み取り専用フィールドと可変フィールドの混在 (社員レコード)
(define-record-type employee
  (make-employee id name salary dept)
  employee?
  (id employee-id)
  (name employee-name)
  (salary employee-salary employee-set-salary!)
  (dept employee-dept employee-set-dept!))

;; 3. 一部フィールドのみ初期化するコンストラクタ (初期値 #f)
(define-record-type task
  (create-task title)
  task?
  (title task-title)
  (completed? task-completed? task-set-completed!)
  (result task-result task-set-result!))

;; 4. ライブラリ内での define-record-type と export
(define-library (geometry circle)
  (export make-circle circle? circle-radius circle-set-radius! circle-area-approx)
  (import (scheme base))
  (begin
    (define-record-type circle
      (make-circle radius)
      circle?
      (radius circle-radius circle-set-radius!))

    (define (circle-area-approx c)
      (let ((r (circle-radius c)))
        (* 3 (* r r))))))

(import (geometry circle))

(define (assert-true val msg)
  (if (not val)
      (begin
        (display "FAIL: ")
        (display msg)
        (newline)
        (exit 1))
      (begin
        (display "PASS: ")
        (display msg)
        (newline))))

(define (assert-equal actual expected msg)
  (if (not (or (eqv? actual expected)
               (and (string? actual) (string? expected) (string=? actual expected))))
      (begin
        (display "FAIL: ")
        (display msg)
        (display " - expected: ")
        (display expected)
        (display " but got: ")
        (display actual)
        (newline)
        (exit 1))
      (begin
        (display "PASS: ")
        (display msg)
        (newline))))

;; =======================================================================
;; テスト実行
;; =======================================================================

;; Test 1: point の生成とアクセサ
(let ((p (make-point 10 20)))
  (assert-true (point? p) "p is point?")
  (assert-equal (point-x p) 10 "point-x is 10")
  (assert-equal (point-y p) 20 "point-y is 20")

  ;; point-set! による更新
  (point-set-x! p 99)
  (assert-equal (point-x p) 99 "point-x updated to 99")
  (point-set-y! p 123)
  (assert-equal (point-y p) 123 "point-y updated to 123"))

;; Test 2: 型述語の排他性・安全性
(let ((p (make-point 1 2))
      (emp (make-employee 101 "Alice" 50000 "Engineering"))
      (v (vector 1 2 3))
      (lst (list 1 2)))
  (assert-true (point? p) "point? on point is #t")
  (assert-true (not (point? emp)) "point? on employee is #f")
  (assert-true (not (point? v)) "point? on raw vector is #f")
  (assert-true (not (point? lst)) "point? on list is #f")
  (assert-true (not (point? 42)) "point? on fixnum is #f")

  (assert-true (employee? emp) "employee? on employee is #t")
  (assert-true (not (employee? p)) "employee? on point is #f"))

;; Test 3: employee のフィールド読み取りと給与更新
(let ((emp (make-employee 202 "Bob" 60000 "Security")))
  (assert-equal (employee-id emp) 202 "employee-id")
  (assert-equal (employee-name emp) "Bob" "employee-name")
  (assert-equal (employee-salary emp) 60000 "employee-salary")
  (assert-equal (employee-dept emp) "Security" "employee-dept")

  (employee-set-salary! emp 75000)
  (assert-equal (employee-salary emp) 75000 "employee-salary updated")
  (employee-set-dept! emp "Research")
  (assert-equal (employee-dept emp) "Research" "employee-dept updated"))

;; Test 4: 部分初期化コンストラクタと未初期化フィールド (#f)
(let ((t (create-task "Deploy uLisp")))
  (assert-true (task? t) "t is task?")
  (assert-equal (task-title t) "Deploy uLisp" "task-title")
  (assert-equal (task-completed? t) #f "uninitialized completed? is #f")
  (assert-equal (task-result t) #f "uninitialized result is #f")

  (task-set-completed! t #t)
  (task-set-result! t 42)
  (assert-equal (task-completed? t) #t "task-completed? updated to #t")
  (assert-equal (task-result t) 42 "task-result updated to 42"))

;; Test 5: インスタンスの独立性
(let ((p1 (make-point 1 2))
      (p2 (make-point 3 4)))
  (point-set-x! p1 100)
  (assert-equal (point-x p1) 100 "p1 x is 100")
  (assert-equal (point-x p2) 3 "p2 x unchanged"))

;; Test 6: ライブラリからエクスポートされたレコード型
(let ((c (make-circle 10)))
  (assert-true (circle? c) "circle? is #t")
  (assert-equal (circle-radius c) 10 "circle-radius is 10")
  (assert-equal (circle-area-approx c) 300 "circle-area-approx is 3*10*10=300")

  (circle-set-radius! c 5)
  (assert-equal (circle-radius c) 5 "circle-radius updated to 5")
  (assert-equal (circle-area-approx c) 75 "circle-area-approx is 3*5*5=75"))

(display "ALL DEFINE-RECORD-TYPE TESTS PASSED!")
(newline)
