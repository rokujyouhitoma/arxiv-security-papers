;;; =======================================================================
;;; Unit Test Suite: PSDS & Provenance (Issue #871)
;;; Conforms to DSN-33-03 §3.4
;;; =======================================================================

(test-begin "PSDS & Provenance (Issue #871)")

;;; -----------------------------------------------------------------------
;;; Group 1: <stage-val> Record Instantiation & Predicates
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: <stage-val> Instantiation & Predicates ---\n")

(define sv-stat (make-static-val 'integer 42 "host.scm:1" "guest.dsl:1"))
(define sv-dyn  (make-dynamic-val 'unknown 'x "host.scm:2" "guest.dsl:2"))
(define sv-psds (make-psds-val 'pair (cons sv-stat sv-dyn) "host.scm:3" "guest.dsl:3"))

(assert-equal "1.1 sv-stat is stage-val?" #t (stage-val? sv-stat))
(assert-equal "1.2 sv-stat is pure-static?" #t (stage-val-pure-static? sv-stat))
(assert-equal "1.3 sv-stat is not pure-dynamic?" #f (stage-val-pure-dynamic? sv-stat))
(assert-equal "1.4 sv-dyn is pure-dynamic?" #t (stage-val-pure-dynamic? sv-dyn))
(assert-equal "1.5 sv-psds is partially-static?" #t (stage-val-partially-static? sv-psds))
(assert-equal "1.6 sv-stat payload is 42" 42 (stage-val-payload sv-stat))
(assert-equal "1.7 sv-dyn payload is x" 'x (stage-val-payload sv-dyn))

;;; -----------------------------------------------------------------------
;;; Group 2: PSDS Pair Construction & Static Spine Elimination
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: PSDS Pair Static Spine Elimination ---\n")

(define later-d (make-later-dict))

;; Case A: Both pure-static -> Pure-static pair
(define pair-stat (stage-cons sv-stat (make-static-val 'integer 100 "h" "g") "h" "g"))
(assert-equal "2.1 Both static -> pure-static pair" #t (stage-val-pure-static? pair-stat))
(assert-equal "2.2 Static pair payload" '(42 . 100) (stage-val-payload pair-stat))

;; stage-car and stage-cdr on pure-static pair
(define car-from-stat (stage-car later-d pair-stat "callsite:1"))
(assert-equal "2.3 stage-car on static pair returns pure-static" #t (stage-val-pure-static? car-from-stat))
(assert-equal "2.4 stage-car on static pair payload is 42" 42 (stage-val-payload car-from-stat))

;; Case B: Static car + Dynamic cdr -> Partially-Static Pair
(define pair-psds (stage-cons sv-stat sv-dyn "h-cons" "g-cons"))
(assert-equal "2.5 Static + Dynamic -> partially-static pair" #t (stage-val-partially-static? pair-psds))

;; CRITICAL Futamura Property: stage-car and stage-cdr on PSDS must NOT emit residual code!
(define car-from-psds (stage-car later-d pair-psds "callsite:2"))
(assert-equal "2.6 stage-car on PSDS directly returns static car" #t (stage-val-pure-static? car-from-psds))
(assert-equal "2.7 stage-car on PSDS payload is 42 (zero residual instructions!)" 42 (stage-val-payload car-from-psds))

(define cdr-from-psds (stage-cdr later-d pair-psds "callsite:3"))
(assert-equal "2.8 stage-cdr on PSDS directly returns dynamic cdr" #t (stage-val-pure-dynamic? cdr-from-psds))
(assert-equal "2.9 stage-cdr on PSDS payload is x (zero residual instructions!)" 'x (stage-val-payload cdr-from-psds))

;;; -----------------------------------------------------------------------
;;; Group 3: Pure Dynamic Fallback (Residual Instruction Emission)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Pure Dynamic Residual Fallback ---\n")

(define dyn-pair (make-dynamic-val 'pair 'my-pair "h-dyn" "g-dyn"))

(define car-from-dyn (stage-car later-d dyn-pair "callsite:4"))
(assert-equal "3.1 stage-car on dynamic returns pure-dynamic" #t (stage-val-pure-dynamic? car-from-dyn))
(assert-equal "3.2 stage-car on dynamic emits residual (car my-pair)" '(car my-pair) (stage-val-payload car-from-dyn))

(define cdr-from-dyn (stage-cdr later-d dyn-pair "callsite:5"))
(assert-equal "3.3 stage-cdr on dynamic returns pure-dynamic" #t (stage-val-pure-dynamic? cdr-from-dyn))
(assert-equal "3.4 stage-cdr on dynamic emits residual (cdr my-pair)" '(cdr my-pair) (stage-val-payload cdr-from-dyn))

;;; -----------------------------------------------------------------------
;;; Group 4: Dual Source Span Provenance Stack
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Dual Source Span Provenance Stack ---\n")

(define sv-with-span (make-static-val 'symbol 'query-var "evaluator.scm:145:8" "user_query.dsl:42:15"))
(define prov (stage-val-provenance sv-with-span))

(assert-equal "4.1 guest span correctly tracked" "user_query.dsl:42:15" (cdr (assq 'guest prov)))
(assert-equal "4.2 host span correctly tracked" "evaluator.scm:145:8" (cdr (assq 'host prov)))

;; End of tests
