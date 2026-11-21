;;; =======================================================================
;;; Test Suite: Dual Source Span & Guest DWARF Debug Line Emitter
;;; Conforms to DSN-33-04 §5 (Guest-level Debug Transparency), Issue #896
;;; =======================================================================

(display "\n=== [Test Suite: Dual Source Span & Guest DWARF Line Emitter (Issue #896)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Dual Source Span Data Structure & Path Sanitization (CWE-22 / CWE-400)
;;; -----------------------------------------------------------------------

(display "--- Group 1: Dual Source Span Data Structure & Sanitization ---\n")

;; 1.1 Basic construction and field accessors
(let ((span (make-dual-source-span "rule.cti" 42 10 "interp.scm" 120 5)))
  (assert-true "dual-source-span? is true" (dual-source-span? span))
  (assert-true "any-source-span? is true" (any-source-span? span))
  (assert-false "source-span? is false for dual span" (source-span? span))
  (assert-equal "guest-file matches" "rule.cti" (span-guest-file span))
  (assert-equal "guest-line matches" 42 (span-guest-line span))
  (assert-equal "guest-col matches" 10 (span-guest-col span))
  (assert-equal "interp-file matches" "interp.scm" (span-interp-file span))
  (assert-equal "interp-line matches" 120 (span-interp-line span))
  (assert-equal "interp-col matches" 5 (span-interp-col span))
  (assert-true "node-id is a positive integer" (> (span-dual-node-id span) 0)))

;; 1.2 Polymorphic effective accessors (Priority: Guest > Interp)
(let ((dspan (make-dual-source-span "calc.expr" 5 1 "evaluator.scm" 99 2))
      (sspan (make-source-span "std.scm" 10 3 10 20 #f 100)))
  (assert-equal "effective file for dual span is guest-file" "calc.expr" (span-effective-file dspan))
  (assert-equal "effective line for dual span is guest-line" 5 (span-effective-line dspan))
  (assert-equal "effective col for dual span is guest-col" 1 (span-effective-col dspan))
  (assert-equal "effective interp-file is evaluator.scm" "evaluator.scm" (span-effective-interp-file dspan))
  (assert-equal "effective interp-line is 99" 99 (span-effective-interp-line dspan))
  (assert-equal "effective interp-col is 2" 2 (span-effective-interp-col dspan))

  (assert-equal "effective file for source-span is span-file" "std.scm" (span-effective-file sspan))
  (assert-equal "effective line for source-span is span-start-line" 10 (span-effective-line sspan))
  (assert-equal "effective col for source-span is span-start-col" 3 (span-effective-col sspan)))

;; 1.3 Path sanitization (CWE-22: Path Traversal defense)
(let ((span (make-dual-source-span "../../../etc/shadow\"" 1 1 "interp\n.scm" 1 1)))
  (assert-false "path sanitization strips double quotes"
                (let loop ((i 0) (s (span-guest-file span)))
                  (if (= i (string-length s)) #f
                      (if (char=? (string-ref s i) #\") #t
                          (loop (+ i 1) s)))))
  (assert-false "path sanitization strips newlines in interp-file"
                (let loop ((i 0) (s (span-interp-file span)))
                  (if (= i (string-length s)) #f
                      (if (char=? (string-ref s i) #\newline) #t
                          (loop (+ i 1) s))))))

;; 1.4 Large/Negative coordinate clipping (CWE-400: Resource exhaustion defense)
(let ((span (make-dual-source-span "a.src" -10 -5 "b.src" 99999999 50000)))
  (assert-equal "negative guest line normalized to 1" 1 (span-guest-line span))
  (assert-equal "negative guest col normalized to 1" 1 (span-guest-col span))
  (assert-equal "huge interp line clipped to 10000000" 10000000 (span-interp-line span))
  (assert-equal "huge interp col clipped to 10000" 10000 (span-interp-col span)))

;; 1.5 Conversion to standard source-span
(let* ((dspan (make-dual-source-span "rule.cti" 15 4 "interp.scm" 200 1))
       (sspan (dual-source-span->source-span dspan)))
  (assert-true "converted object is source-span?" (source-span? sspan))
  (assert-equal "file is guest file" "rule.cti" (span-file sspan))
  (assert-equal "start-line is guest line" 15 (span-start-line sspan))
  (assert-equal "start-col is guest col" 4 (span-start-col sspan)))

;;; -----------------------------------------------------------------------
;;; Group 2: AST Span Annotation & Propagation to LIR %loc Instructions
;;; -----------------------------------------------------------------------

(display "--- Group 2: AST Span Annotation & LIR %loc Generation ---\n")

;; 2.1 AST wrapping with dual span
(let* ((dspan (make-dual-source-span "detector.cti" 25 1 "eval.scm" 50 1))
       (raw-expr '(+ 10 20))
       (wrapped (ast-with-span raw-expr dspan)))
  (assert-true "ast-has-span? is true" (ast-has-span? wrapped))
  (assert-equal "ast-source-span retrieves dual span" dspan (ast-source-span wrapped))
  (assert-equal "ast-strip-span returns original form" raw-expr (ast-strip-span wrapped)))

;; 2.2 Function source location lookup with dual span
(reset-function-source-span-table!)
(reset-source-file-table!)
(let* ((fn-span (make-dual-source-span "guest_app.dsl" 12 1 "interp.scm" 88 4))
       (fn-sym 'guest_eval_main))
  (register-function-source-span! fn-sym fn-span)
  (let ((loc (lookup-function-source-loc fn-sym)))
    (assert-true "lookup-function-source-loc returns a triplet" (and (pair? loc) (= (length loc) 3)))
    (assert-equal "function file is guest file" "guest_app.dsl" (car loc))
    (assert-equal "function line is guest line" 12 (cadr loc))
    (assert-equal "function col is guest col" 1 (caddr loc))))

;; 2.3 LIR compilation of span-wrapped expression emits %loc
(enable-debug-symbols!)
(reset-lir!)
(reset-source-file-table!)
(let* ((dspan (make-dual-source-span "query.cti" 33 5 "interp.scm" 105 2))
       (expr (ast-with-span '(+ 1 2) dspan)))
  (track-lir-si! -8)
  (lir-compile-expr expr -8 '((%raw-vars . ()) (%stack-vars . ())) #f)
  (let ((insts (reverse (car *lir-instructions*))))
    ;; Check that %loc is among instructions
    (let ((loc-insts (filter (lambda (i) (and (pair? i) (eq? (car i) '%loc))) insts)))
      (assert-true "%loc instruction was emitted" (pair? loc-insts))
      (let* ((loc (car loc-insts))
             (fid (cadr loc))
             (line (caddr loc))
             (col (cadddr loc))
             (file-table (get-source-file-table)))
        (assert-equal "line in %loc is guest line 33" 33 line)
        (assert-equal "col in %loc is guest col 5" 5 col)
        (assert-true "source file table contains query.cti"
                     (pair? (filter (lambda (e) (string=? (car e) "query.cti")) file-table)))))))
(disable-debug-symbols!)

;;; -----------------------------------------------------------------------
;;; Group 3: LIR Peephole Redundant %loc Instruction Elimination
;;; -----------------------------------------------------------------------

(display "--- Group 3: LIR Peephole Redundant %loc Elimination ---\n")

;; Redundant consecutive %loc with same file and line should be collapsed
(let* ((insts (list '(%loc 1 10 1)
                    '(%loc 1 10 5)
                    '(%mov %rax 42)
                    '(%loc 1 20 1)
                    '(%loc 1 20 2)
                    '(%return)))
       (opt-insts (optimize-peephole-fixpoint insts)))
  (let ((locs (filter (lambda (i) (and (pair? i) (eq? (car i) '%loc))) opt-insts)))
    (assert-equal "collapsed redundant locs to 2 entries" 2 (length locs))
    (assert-equal "first loc line is 10 col is 5" '(1 10 5) (cdr (car locs)))
    (assert-equal "second loc line is 20 col is 2" '(1 20 2) (cdr (cadr locs)))))

;;; -----------------------------------------------------------------------
;;; Group 4: DWARF 3 .debug_line Section Binary Generation
;;; -----------------------------------------------------------------------

(display "--- Group 4: DWARF 3 .debug_line Section Generation ---\n")

;; 4.1 File table sorting
(let* ((unsorted '((2 . "interp.scm") (1 . "rule.cti") (3 . "lib.scm")))
       (sorted (sort-file-table unsorted)))
  (assert-equal "sort-file-table sorts by fid"
                '((1 . "rule.cti") (2 . "interp.scm") (3 . "lib.scm"))
                sorted))

;; 4.2 Building .debug_line bytevector
(let* ((file-table '((1 . "rule.cti") (2 . "interp.scm")))
       (line-table '((1 10 1 0) (1 15 1 16) (1 20 1 32)))
       (text-vaddr 4194480)
       (text-len 64)
       (dbg-line-bv (build-debug-line-section file-table line-table text-vaddr text-len)))
  (assert-true "build-debug-line-section returns bytevector" (bytevector? dbg-line-bv))
  (assert-true "debug_line section length > 30 bytes" (> (bytevector-length dbg-line-bv) 30))
  ;; Check DWARF 3 version (offset 4 is uint16 3)
  (let ((ver (+ (bytevector-u8-ref dbg-line-bv 4)
                (* (bytevector-u8-ref dbg-line-bv 5) 256))))
    (assert-equal "DWARF version is 3" 3 ver)))

;;; -----------------------------------------------------------------------
;;; Group 5: Diagnostic Reporter with Dual Source Span Integration
;;; -----------------------------------------------------------------------

(display "--- Group 5: Diagnostic Reporter with Dual Source Span ---\n")

(let* ((dspan (make-dual-source-span "bad_rule.cti" 18 7 "interp_parser.scm" 240 12))
       (diag (make-diagnostic 'error 'E_GUEST_SYNTAX dspan "Invalid expression in threat rule")))
  (assert-true "diagnostic? is true" (diagnostic? diag))
  (assert-equal "diagnostic code is E_GUEST_SYNTAX" 'E_GUEST_SYNTAX (diagnostic-code diag))
  ;; Effective span should point to guest file
  (let ((span (diagnostic-span diag)))
    (assert-true "diagnostic span is source-span?" (source-span? span))
    (assert-equal "diagnostic span file is bad_rule.cti" "bad_rule.cti" (span-file span))
    (assert-equal "diagnostic span line is 18" 18 (span-start-line span)))
  ;; Notes should include evaluator context
  (let ((notes (diagnostic-notes diag)))
    (assert-true "diagnostic notes contains evaluator context"
                 (let loop ((ns notes))
                   (if (null? ns) #f
                       (if (and (string? (car ns))
                                (let ((s (car ns)))
                                  (and (> (string-length s) 17)
                                       (string=? (substring s 0 17) "evaluator context"))))
                           #t
                           (loop (cdr ns))))))))

;;; -----------------------------------------------------------------------
;;; Group 6: E2E Standalone ELF Binary DWARF Line Table Verification
;;; -----------------------------------------------------------------------

(display "--- Group 6: E2E Standalone ELF Binary DWARF Line Table ---\n")

(let* ((file-table '((1 . "sample_rule.cti")))
       (line-table '((1 1 1 0) (1 2 1 10)))
       (sym-table '())
       (text-bv (make-bytevector 32 144)) ; 32 NOPs
       (rodata-bv (make-bytevector 16 0))
       (data-bv (make-bytevector 8 0))
       (bss-size 0)
       (entry-offset 0)
       (debug-payload (list file-table line-table sym-table))
       (elf-bv (build-elf64-debug text-bv rodata-bv data-bv bss-size entry-offset debug-payload)))
  (assert-true "build-elf64-debug returns bytevector" (bytevector? elf-bv))
  (assert-true "ELF binary length > 1024 bytes" (> (bytevector-length elf-bv) 1024))
  ;; Check ELF magic
  (assert-equal "ELF magic 0 is 0x7f" 127 (bytevector-u8-ref elf-bv 0))
  (assert-equal "ELF magic 'E'" 69 (bytevector-u8-ref elf-bv 1))
  (assert-equal "ELF magic 'L'" 76 (bytevector-u8-ref elf-bv 2))
  (assert-equal "ELF magic 'F'" 70 (bytevector-u8-ref elf-bv 3))
  ;; Check 64-bit ELF (class 2)
  (assert-equal "ELF class 2 (64-bit)" 2 (bytevector-u8-ref elf-bv 4))
  ;; Check executable type (ET_EXEC = 2) at offset 16
  (assert-equal "ELF type ET_EXEC" 2 (bytevector-u8-ref elf-bv 16))
  ;; Write ELF to file for external tool (readelf) verification
  (let ((p (open-binary-output-file "build/test_dwarf_guest.elf")))
    (write-bytevector elf-bv p)
    (close-output-port p)))

(display "\n[PASS] All Dual Source Span & Guest DWARF Line Emitter tests passed successfully!\n\n")
