;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 131 (GC Safepoint & Stackmap Bitmaps)
;;; Conforms to Issue #572 & Nanopass Architecture Quality Standard
;;; =======================================================================




(test-begin "Pass 131 (LIR Safepoint & Stackmap)")

;; 1. power-of-2 helper
(assert-equal "power-of-2 0" 1 (power-of-2 0))
(assert-equal "power-of-2 1" 2 (power-of-2 1))
(assert-equal "power-of-2 3" 8 (power-of-2 3))
(assert-equal "power-of-2 8" 256 (power-of-2 8))

;; 2. safepoint label generator & reset
(reset-safepoints!)
(let ((lbl1 (new-safepoint-label!))
      (lbl2 (new-safepoint-label!)))
  (assert-equal "first safepoint label" "__safepoint_1" lbl1)
  (assert-equal "second safepoint label" "__safepoint_2" lbl2)
  (record-safepoint! lbl1 32 3)
  (assert-true "safepoints recorded" (pair? (car *lir-safepoints*))))

;; 3. compute-stackmap-bitmap for empty env (slot -8 is NOT marked live without %self)
(let ((bm (compute-stackmap-bitmap 32 -16 '() '())))
  (assert-true "bitmap is an integer" (integer? bm))
  (assert-equal "empty env marks no pointer roots (including -8)" 0 bm))

;; 4. compute-stackmap-bitmap marks [rsp - 8] only when %self is present in env
(let* ((env-with-self (list (cons '%self (cons 'self -8))))
       ;; frame-shift 32: k=3 -> slot-offset = 24 - 32 = -8 -> bit 3 = 8
       (bm-self (compute-stackmap-bitmap 32 -24 '() env-with-self))
       ;; frame-shift 32: %self in raw-vars must not be marked live
       (bm-raw (compute-stackmap-bitmap 32 -24 '() (cons '(%raw-vars %self) env-with-self))))
  (assert-equal "env with %self marks [rsp - 8] root bit" 8 bm-self)
  (assert-equal "raw-vars %self clears [rsp - 8] root bit" 0 bm-raw))

(test-end "Pass 131 (LIR Safepoint & Stackmap)")
