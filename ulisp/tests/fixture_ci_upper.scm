;;; Fixture file written with uppercase Scheme symbols for testing include-ci
(DEFINE (CALCULATE-UPPER-SUM A B)
  (+ A B))

(DEFINE UPPERCASE-TEST-CONSTANT 42)

(DEFINE UPPERCASE-LITERAL-STRING "HELLO WORLD")

(DEFINE (EVALUATE-UPPER-COND FLAG VAL)
  (IF FLAG
      (* VAL 2)
      (- VAL 2)))

