;;; =======================================================================
;;; ULisp Test Suite: Pure Scheme IEEE 754 Binary64 Module (tests/test_ieee754.scm)
;;; Conforms to DSN-38 §2 A2 & Issue #832
;;; =======================================================================

(test-begin "ieee754")

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

;; =======================================================================
;; Group 1: Special IEEE 754 Values & Predicates
;; =======================================================================
(write-string "--- Group 1: Special IEEE 754 Values ---\n")

(let ((pzero (string->ieee754-u64 "0.0"))
      (nzero (string->ieee754-u64 "-0.0"))
      (pinf  (string->ieee754-u64 "+inf.0"))
      (ninf  (string->ieee754-u64 "-inf.0"))
      (pnan  (string->ieee754-u64 "+nan.0"))
      (nnan  (string->ieee754-u64 "-nan.0")))

  (assert-equal "+0.0 hex" (ieee754-u64->hex-string pzero) "0000000000000000")
  (assert-equal "-0.0 hex" (ieee754-u64->hex-string nzero) "8000000000000000")
  (assert-equal "+inf.0 hex" (ieee754-u64->hex-string pinf) "7ff0000000000000")
  (assert-equal "-inf.0 hex" (ieee754-u64->hex-string ninf) "fff0000000000000")
  (assert-equal "+nan.0 hex" (ieee754-u64->hex-string pnan) "7ff8000000000000")
  (assert-equal "-nan.0 hex" (ieee754-u64->hex-string nnan) "fff8000000000000")

  (assert-true "+0.0 zero?" (ieee754-zero? pzero))
  (assert-true "-0.0 zero?" (ieee754-zero? nzero))
  (assert-true "+inf.0 inf?" (ieee754-infinite? pinf))
  (assert-true "-inf.0 inf?" (ieee754-infinite? ninf))
  (assert-true "+nan.0 nan?" (ieee754-nan? pnan))
  (assert-true "-nan.0 nan?" (ieee754-nan? nnan))
  (assert-false "+inf.0 finite?" (ieee754-finite? pinf))
  (assert-false "+nan.0 finite?" (ieee754-finite? pnan))
  (assert-true "+0.0 finite?" (ieee754-finite? pzero)))

;; =======================================================================
;; Group 2: Exact Bit-Pattern Matching with GCC/Clang Reference
;; =======================================================================
(write-string "--- Group 2: Clang/GCC Reference Float Bit Patterns ---\n")

;; Reference 64-bit IEEE double hexadecimal values from standard IEEE 754 / Clang:
;;   1.0                    -> 3ff0000000000000
;;   0.5                    -> 3fe0000000000000
;;   0.25                   -> 3fd0000000000000
;;   2.0                    -> 4000000000000000
;;   3.141592653589793      -> 400921fb54442d18
;;   9007199254740992.0     -> 4340000000000000 (2^53)
;;   0.1                    -> 3fb999999999999a
;;   0.2                    -> 3fc999999999999a
;;   1e308                  -> 7fe1ccf385ebc8a0
;;   1e-300                 -> 01a56e1fc2f8f359

(assert-equal "1.0 bit pattern" (ieee754-u64->hex-string (string->ieee754-u64 "1.0")) "3ff0000000000000")
(assert-equal "0.5 bit pattern" (ieee754-u64->hex-string (string->ieee754-u64 "0.5")) "3fe0000000000000")
(assert-equal "0.25 bit pattern" (ieee754-u64->hex-string (string->ieee754-u64 "0.25")) "3fd0000000000000")
(assert-equal "2.0 bit pattern" (ieee754-u64->hex-string (string->ieee754-u64 "2.0")) "4000000000000000")
(assert-equal "3.141592653589793 bit pattern" (ieee754-u64->hex-string (string->ieee754-u64 "3.141592653589793")) "400921fb54442d18")
(assert-equal "9007199254740992.0 (2^53) bit pattern" (ieee754-u64->hex-string (string->ieee754-u64 "9007199254740992.0")) "4340000000000000")

;; Binary repeating fractions
(assert-equal "0.1 bit pattern" (ieee754-u64->hex-string (string->ieee754-u64 "0.1")) "3fb999999999999a")
(assert-equal "0.2 bit pattern" (ieee754-u64->hex-string (string->ieee754-u64 "0.2")) "3fc999999999999a")
(assert-equal "1e308 bit pattern" (ieee754-u64->hex-string (string->ieee754-u64 "1e308")) "7fe1ccf385ebc8a0")
(assert-equal "1e-300 bit pattern" (ieee754-u64->hex-string (string->ieee754-u64 "1e-300")) "01a56e1fc2f8f359")

;; =======================================================================
;; Group 3: Extreme Boundaries & Subnormal Numbers
;; =======================================================================
(write-string "--- Group 3: Extreme Boundaries & Subnormals ---\n")

;; Minimum Normal: 2.2250738585072014e-308 (biased exp = 1, fraction = 0)
(let ((min-normal (string->ieee754-u64 "2.2250738585072014e-308")))
  (assert-equal "min normal hex" (ieee754-u64->hex-string min-normal) "0010000000000000")
  (assert-false "min normal is not subnormal" (ieee754-subnormal? min-normal))
  (assert-true "min normal is finite" (ieee754-finite? min-normal)))

;; Maximum Subnormal: 2.2250738585072011e-308 (biased exp = 0, fraction = 2^52 - 1)
(let ((max-subnormal (string->ieee754-u64 "2.2250738585072011e-308")))
  (assert-equal "max subnormal hex" (ieee754-u64->hex-string max-subnormal) "000fffffffffffff")
  (assert-true "max subnormal is subnormal" (ieee754-subnormal? max-subnormal)))

;; Minimum Subnormal: 4.9406564584124654e-324 (biased exp = 0, fraction = 1)
(let ((min-subnormal (string->ieee754-u64 "4.9406564584124654e-324")))
  (assert-equal "min subnormal hex" (ieee754-u64->hex-string min-subnormal) "0000000000000001")
  (assert-true "min subnormal is subnormal" (ieee754-subnormal? min-subnormal)))

;; =======================================================================
;; Group 4: Formatter & Round-Trip Invariant
;; =======================================================================
(write-string "--- Group 4: Formatter & Round-Trip Invariant ---\n")

(define round-trip-cases
  (list "1.0" "0.5" "0.25" "2.0" "0.1" "0.2" "1e308" "1e-300"
        "2.2250738585072014e-308" "2.2250738585072011e-308"
        "4.9406564584124654e-324" "3.141592653589793"))

(for-each
  (lambda (tc)
    (let* ((u1 (string->ieee754-u64 tc))
           (formatted (ieee754-u64->string u1))
           (u2 (string->ieee754-u64 formatted))
           (hex1 (ieee754-u64->hex-string u1))
           (hex2 (ieee754-u64->hex-string u2)))
      (assert-equal (string-append "roundtrip " tc) hex1 hex2)))
  round-trip-cases)

(test-end "ieee754")
