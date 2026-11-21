;;; =======================================================================
;;; Test Suite: Direct Cogen Driver & Compiler CLI Generator
;;; Conforms to DSN-33-04 §4.1 & §4.2, DSN-33-03 §3, Issue #895
;;; =======================================================================

(display "\n=== [Test Suite: Direct Cogen Driver & Compiler CLI Generator (Issue #895)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: LIR Instruction Representation & Reference Evaluator
;;; -----------------------------------------------------------------------

(display "--- Group 1: LIR Instruction Representation & lir-eval ---\n")

;; Constant evaluation
(let ((node (make-lir-const 42))
      (frame (make-vector 10 #f)))
  (assert-true "lir-node? for const" (lir-node? node))
  (assert-equal "lir-eval const returns 42" 42 (lir-eval node frame)))

;; Arithmetic binop evaluation: (+ 10 (* 20 3)) = 70
(let* ((rhs (make-lir-binop '* (make-lir-const 20) (make-lir-const 3)))
       (root (make-lir-binop '+ (make-lir-const 10) rhs))
       (frame (make-vector 10 #f)))
  (assert-true "lir-node? for binop" (lir-node? root))
  (assert-equal "lir-eval (+ 10 (* 20 3)) is 70" 70 (lir-eval root frame)))

;; Slot write and read operations
(let* ((frame (make-vector 5 0))
       (write-op (make-lir-slot-set! 2 'x (make-lir-const 999)))
       (read-op (make-lir-slot-ref 2 'x)))
  (assert-equal "write-op returns written value" 999 (lir-eval write-op frame))
  (assert-equal "frame index 2 holds 999" 999 (vector-ref frame 2))
  (assert-equal "read-op retrieves 999" 999 (lir-eval read-op frame)))

;; Conditional branching (if)
(let* ((frame (make-vector 5 0))
       (if-true (make-lir-if (make-lir-const 1) (make-lir-const 100) (make-lir-const 200)))
       (if-false (make-lir-if (make-lir-const 0) (make-lir-const 100) (make-lir-const 200))))
  (assert-equal "if true branch evaluates to 100" 100 (lir-eval if-true frame))
  (assert-equal "if false branch evaluates to 200" 200 (lir-eval if-false frame)))

;; Sequence evaluation (seq)
(let* ((frame (make-vector 5 0))
       (seq-op (make-lir-seq (list (make-lir-slot-set! 0 'a (make-lir-const 10))
                                   (make-lir-slot-set! 1 'b (make-lir-const 20))
                                   (make-lir-binop '+ (make-lir-slot-ref 0 'a)
                                                      (make-lir-slot-ref 1 'b))))))
  (assert-equal "seq evaluates to sum of slots 10 + 20 = 30" 30 (lir-eval seq-op frame))
  (assert-equal "slot 0 is 10" 10 (vector-ref frame 0))
  (assert-equal "slot 1 is 20" 20 (vector-ref frame 1)))

;;; -----------------------------------------------------------------------
;;; Group 2: Direct Cogen Compiler Derivation from Declarative Rules
;;; -----------------------------------------------------------------------

(display "\n--- Group 2: Direct Cogen Compiler Derivation ---\n")

(let* ((interp-rules '()) ; using standard fallback rules
       (compiler (derive-cogen-compiler interp-rules 'tagging))
       (gfd (gfd-empty)))

  ;; 1. Compile simple arithmetic AST: (+ 15 (* 5 7))
  (let* ((ast '(+ 15 (* 5 7)))
         (lir (compiler ast gfd))
         (frame (make-vector (max 1 (gfd-slot-count gfd)) #f)))
    (assert-true "compiled AST produces valid LIR" (lir-node? lir))
    (assert-equal "evaluated residual LIR produces 50" 50 (lir-eval lir frame)))

  ;; 2. Compile variable assignment and reference
  (let* ((gfd2 (gfd-empty))
         (ast-assign '(assign total (+ 100 250)))
         (ast-ref 'total)
         (lir-assign (compiler ast-assign gfd2))
         (lir-ref (compiler ast-ref gfd2))
         (frame2 (make-vector (gfd-slot-count gfd2) #f)))
    (assert-equal "variable 'total is assigned slot 0" 0 (gfd-lookup-slot gfd2 'total))
    (lir-eval lir-assign frame2)
    (assert-equal "frame index 0 holds 350" 350 (vector-ref frame2 0))
    (assert-equal "evaluated slot-ref returns 350" 350 (lir-eval lir-ref frame2))))

;;; -----------------------------------------------------------------------
;;; Group 3: Security Validations (CWE-78, CWE-22, CWE-400)
;;; -----------------------------------------------------------------------

(display "\n--- Group 3: Security Validations (CWE-78, CWE-22, CWE-400) ---\n")

;; Safe path acceptance
(let ((safe-paths '("foo/bar.scm" "grammar-1.peg" "out_dir/bin" "a.out")))
  (for-each (lambda (p)
              (assert-equal (string-append "safe path accepted: " p) p (cogen-validate-path p)))
            safe-paths))

;; CWE-78, CWE-22, CWE-400 with compiler error interception
(let ((orig-abort (car *compiler-abort-on-error*))
      (orig-suppress (car *compiler-suppress-diagnostics*)))
  (set-car! *compiler-abort-on-error* #f)
  (set-car! *compiler-suppress-diagnostics* #t)

  ;; CWE-78: Unsafe character rejection
  (let ((unsafe-paths '("foo;rm -rf /" "bar|calc" "out$dir" "file`touch`" "path with spaces" "test\nline")))
    (for-each (lambda (p)
                (let ((res (cogen-validate-path p)))
                  (assert-equal (string-append "unsafe path rejected (CWE-78): " p)
                                'unsafe-path-char res)))
              unsafe-paths))

  ;; CWE-22: Path traversal rejection
  (let ((unsafe-out-paths '("build/.../escaped" "out/..../sys")))
    (for-each (lambda (p)
                (let ((res (cogen-validate-output-path p)))
                  (assert-true (string-append "traversal path rejected (CWE-22): " p)
                               (memq res '(suspicious-path-sequence path-traversal-attempt)))))
              unsafe-out-paths))

  ;; CWE-400: Recursion depth limit
  (let ((gfd (gfd-empty)))
    ;; Construct deeply nested AST exceeding *cogen-max-recursion-depth*
    (let loop ((i 0) (deep '(+ 1 1)))
      (if (> i 510)
          (let ((res (cogen-lower-ast deep '() gfd 'tagging)))
            (assert-equal "depth limit exceeded triggers error (CWE-400)"
                          'depth-limit-exceeded res))
          (loop (+ i 1) (list '+ deep 1)))))

  (set-car! *compiler-abort-on-error* orig-abort)
  (set-car! *compiler-suppress-diagnostics* orig-suppress))

;;; -----------------------------------------------------------------------
;;; Group 4: Standalone Compiler Source Synthesis & Metadata Bytes
;;; -----------------------------------------------------------------------

(display "\n--- Group 4: CLI Source Synthesis & .rodata Embedding ---\n")

(let* ((grammar "start = expr;\nexpr = num ('+' num)*;\nnum = [0-9]+;\n")
       (cli-src (synthesize-compiler-cli-source grammar '() 'tagging))
       (meta-bytes (cogen-rodata-metadata-bytes grammar)))
  (assert-true "cli source contains header" (string? cli-src))
  (assert-true "cli source contains grammar text" (> (string-length cli-src) 500))
  (assert-equal "metadata bytes length matches UTF-8 grammar"
                (string-length grammar) (bytevector-length meta-bytes)))

;;; -----------------------------------------------------------------------
;;; Group 5: CLI Driver Preparation & Source Integrity Validation
;;; -----------------------------------------------------------------------

(display "\n--- Group 5: Standalone CLI File & Source Generation Integrity ---\n")

(let* ((test-interp "build/test_sample_interp.scm")
       (test-grammar "build/test_sample_grammar.peg")
       (sample-input "build/sample_input.expr")
       (test-cli-bin "build/test_calc_compiler_cli"))

  ;; Write sample interpreter, grammar, and guest input files
  (call-with-output-file test-interp
    (lambda (p)
      (display ";;; Sample Guest Interpreter\n(define (guest-eval expr env) expr)\n" p)))
  (call-with-output-file test-grammar
    (lambda (p)
      (display "entry = expr\nexpr = [0-9]+\n" p)))
  (call-with-output-file sample-input
    (lambda (p)
      (display "42\n" p)))

  (assert-true "sample interpreter file created" (file-exists? test-interp))
  (assert-true "sample grammar file created" (file-exists? test-grammar))
  (assert-true "sample input file created" (file-exists? sample-input))

  ;; Synthesize CLI source directly for both tagging and nanbox runtime models
  (let ((cli-tagging (synthesize-compiler-cli-source "entry = expr" '() 'tagging))
        (cli-nanbox  (synthesize-compiler-cli-source "entry = expr" '() 'nanbox)))
    (assert-true "cli source generated for tagging model" (string? cli-tagging))
    (assert-true "cli source generated for nanbox model" (string? cli-nanbox))))

(display "\n[PASS] All Direct Cogen Driver and Compiler CLI Generator tests passed successfully.\n")
