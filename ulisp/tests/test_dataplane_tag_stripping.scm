;;; =======================================================================
;;; Test Suite: Data Plane Tag Stripping & Single-Word Repr (Issue #884)
;;; Conforms to DSN-33-03 §7.3 & §4.2
;;; =======================================================================

(display "\n=== [Test Suite: Data Plane Tag Stripping & Single-Word Repr (Issue #884)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: 64-bit Word Packing
;;; -----------------------------------------------------------------------
(display "--- Group 1: 64-bit Word Packing ---\n")

(let* ((raw-ptr #x7FFF00001000) ; 8-byte aligned address
       (tag-pair 2)             ; 0b010
       (tag-vec 3)              ; 0b011
       (packed-pair (data-plane-pack-word raw-ptr tag-pair))
       (packed-vec (data-plane-pack-word raw-ptr tag-vec)))
  (assert-equal "1.1 Packed pair word has lower 3 bits = 2"
                2
                (bitwise-and packed-pair 7))
  (assert-equal "1.2 Packed vector word has lower 3 bits = 3"
                3
                (bitwise-and packed-vec 7)))

;;; -----------------------------------------------------------------------
;;; Group 2: Tag Stripping & Pointer Reconstruction
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Tag Stripping & Pointer Reconstruction ---\n")

(let* ((raw-ptr #x7FFF00002008)
       (tag 5)
       (packed (data-plane-pack-word raw-ptr tag))
       (stripped (data-plane-strip-tag packed)))
  (assert-equal "2.1 Stripped word exactly restores original aligned pointer"
                raw-ptr
                stripped))

;;; -----------------------------------------------------------------------
;;; Group 3: Tag Extraction & Match Predicate
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Tag Extraction & Match Predicate ---\n")

(let* ((raw-ptr #x10000000)
       (w (data-plane-pack-word raw-ptr 4)))
  (assert-equal "3.1 Extracted tag is 4"
                4
                (data-plane-extract-tag w))
  (assert-equal "3.2 Tag match predicate is #t for 4"
                #t
                (data-plane-tag-match? w 4))
  (assert-equal "3.3 Tag match predicate is #f for 2"
                #f
                (data-plane-tag-match? w 2)))

;;; -----------------------------------------------------------------------
;;; Group 4: LIR Redundant Tag Check Elimination Optimizer
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: LIR Redundant Tag Check Elimination Optimizer ---\n")

(let* ((input-insts '((%mov %rax %rdi)
                      (%bit-and %rbx %rdi 7)
                      (%cmp %rbx 2)
                      (%set-boolean %rbx "sete")
                      (%return)))
       ;; When %rdi is statically known to be of the expected Data Plane type
       (optimized (optimize-dataplane-tag-stripping input-insts '(%rdi))))
  (assert-equal "4.1 Optimization folds 3-instruction tag check into single constant mov"
                '((%mov %rax %rdi)
                  (%mov %rbx 1)
                  (%return))
                optimized))

(display "\n[RESULT] All Data Plane Tag Stripping & Single-Word Repr tests PASSED!\n")
