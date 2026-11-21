;;; =======================================================================
;;; Test Suite: Pure Scheme Packrat PEG Runtime Engine
;;; Conforms to DSN-25 & DSN-33-04 §3.1, Issue #894
;;; =======================================================================

(display "\n=== [Test Suite: Pure Scheme Packrat PEG Runtime (Issue #894)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Basic Combinators (Literal, CharClass, AnyChar)
;;; -----------------------------------------------------------------------

(display "--- Group 1: Basic Combinators ---\n")

;; Literal
(let ((p (peg:lit "hello")))
  (let ((res (peg-parse-partial p "hello world")))
    (assert-true "lit 'hello' matches prefix" (pair? res))
    (assert-equal "matched value is 'hello'" "hello" (car res))
    (assert-equal "next pos is 5" 5 (cdr res)))
  (let ((fail-res (peg-parse-partial p "goodbye")))
    (assert-false "lit 'hello' fails on 'goodbye'" fail-res)))

;; CharClass
(let ((p-digits (peg:char-class "0-9"))
      (p-nondigit (peg:char-class "0-9" #t)))
  (let ((res (peg-parse-partial p-digits "7abc")))
    (assert-true "digit class matches '7'" (pair? res))
    (assert-equal "digit val is '7'" "7" (car res))
    (assert-equal "next pos is 1" 1 (cdr res)))
  (let ((res2 (peg-parse-partial p-nondigit "abc")))
    (assert-true "inverted class matches 'a'" (pair? res2))
    (assert-equal "val is 'a'" "a" (car res2))))

;; AnyChar
(let ((p (peg:any-char)))
  (let ((res (peg-parse-partial p "xyz")))
    (assert-true "any-char matches 'x'" (pair? res))
    (assert-equal "val is 'x'" "x" (car res))
    (assert-equal "next pos is 1" 1 (cdr res))))

;;; -----------------------------------------------------------------------
;;; Group 2: Sequence, Choice & Repetition
;;; -----------------------------------------------------------------------

(display "--- Group 2: Sequence, Choice, Repetition ---\n")

;; Sequence
(let ((p (peg:seq (peg:lit "foo") (peg:lit ":") (peg:lit "bar"))))
  (let ((res (peg-parse-partial p "foo:bar extra")))
    (assert-true "seq matches foo:bar" (pair? res))
    (assert-equal "matched values list" '("foo" ":" "bar") (car res))
    (assert-equal "next pos is 7" 7 (cdr res))))

;; Choice
(let ((p (peg:alt (peg:lit "apple") (peg:lit "banana") (peg:lit "cherry"))))
  (let ((r1 (peg-parse-partial p "banana"))
        (r2 (peg-parse-partial p "cherry"))
        (r3 (peg-parse-partial p "date")))
    (assert-equal "choice 1 matches banana" "banana" (car r1))
    (assert-equal "choice 2 matches cherry" "cherry" (car r2))
    (assert-false "choice fails on date" r3)))

;; Star and Plus
(let ((p-star (peg:star (peg:char-class "0-9")))
      (p-plus (peg:plus (peg:char-class "0-9"))))
  (let ((r1 (peg-parse-partial p-star "1234a"))
        (r2 (peg-parse-partial p-star "abc"))
        (r3 (peg-parse-partial p-plus "1234a"))
        (r4 (peg-parse-partial p-plus "abc")))
    (assert-equal "star matches '1234'" '("1" "2" "3" "4") (car r1))
    (assert-equal "star on empty returns empty list" '() (car r2))
    (assert-equal "star on empty pos is 0" 0 (cdr r2))
    (assert-equal "plus matches '1234'" '("1" "2" "3" "4") (car r3))
    (assert-false "plus on empty fails" r4)))

;; Optional
(let ((p (peg:seq (peg:lit "col") (peg:opt (peg:lit "or")))))
  (let ((r1 (peg-parse-partial p "color"))
        (r2 (peg-parse-partial p "col")))
    (assert-equal "matches color" '("col" "or") (car r1))
    (assert-equal "matches col with #f opt" '("col" #f) (car r2))))

;;; -----------------------------------------------------------------------
;;; Group 3: Lookahead Predicates (&, !) & Separator Lists (Gather)
;;; -----------------------------------------------------------------------

(display "--- Group 3: Lookahead & Gather ---\n")

;; And / Not lookahead
(let ((p-and (peg:seq (peg:and (peg:lit "def")) (peg:lit "def")))
      (p-not (peg:seq (peg:not (peg:lit "keyword")) (peg:plus (peg:char-class "a-z")))))
  (let ((r1 (peg-parse-partial p-and "default")))
    (assert-true "and lookahead succeeds" (pair? r1))
    (assert-equal "pos is 3" 3 (cdr r1)))
  (let ((r2 (peg-parse-partial p-not "keyword123"))
        (r3 (peg-parse-partial p-not "variable123")))
    (assert-false "not lookahead rejects 'keyword'" r2)
    (assert-true "not lookahead accepts 'variable'" (pair? r3))))

;; Gather (sep.elem+)
(let ((p (peg:gather (peg:lit ",") (peg:plus (peg:char-class "a-z")) #t)))
  (let ((res (peg-parse-partial p "foo,bar,baz rest")))
    (assert-true "gather succeeds" (pair? res))
    (assert-equal "elements count is 3" 3 (length (car res)))
    (assert-equal "elem 1 is foo" '("f" "o" "o") (car (car res)))
    (assert-equal "next pos is 11" 11 (cdr res))))

;;; -----------------------------------------------------------------------
;;; Group 4: Warth Left-Recursion (Direct & Indirect)
;;; Grammar: expr -> expr '+' num | num
;;; -----------------------------------------------------------------------

(display "--- Group 4: Warth Left-Recursion ---\n")

(define num-parser
  (peg:map (lambda (digits)
             (string->number (apply string-append digits)))
           (peg:plus (peg:char-class "0-9"))))

(define expr-parser
  (peg:rule
   'expr
   (peg:alt
    ;; Left-recursive branch: expr '+' num
    (peg:map (lambda (res)
               (let ((e (car res))
                     (n (caddr res)))
                 (+ e n)))
             (peg:seq (lambda (ctx pos sk fk) (expr-parser ctx pos sk fk))
                      (peg:lit "+")
                      num-parser))
    ;; Base branch: num
    num-parser)))

(let ((r1 (peg-parse expr-parser "42"))
      (r2 (peg-parse expr-parser "10+20"))
      (r3 (peg-parse expr-parser "1+2+3+4+5")))
  (assert-equal "base case 42 parses" 42 r1)
  (assert-equal "10+20 evaluates to 30 via left-recursion" 30 r2)
  (assert-equal "1+2+3+4+5 evaluates to 15" 15 r3))

(display "\n[PASS] All PEG Runtime tests passed successfully.\n\n")
