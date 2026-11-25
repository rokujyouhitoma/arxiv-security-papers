;;; =======================================================================
;;; Test Suite: Pure Scheme PEG Compiler Self-Hosting & Fixed-Point Verification
;;; Conforms to DSN-25 Phase 4 & DSN-33-04 §3.2, Issue #894
;;; =======================================================================

(display "\n=== [Test Suite: Pure Scheme PEG Compiler Self-Hosting (Issue #894)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Parse Meta-Grammar Specification (tools/grammars/peg_meta.peg)
;;; -----------------------------------------------------------------------

(display "--- Group 1: Parse peg_meta.peg with Bootstrap Parser ---\n")

(define meta-grammar-text
  (read-all-file-text "../tools/grammars/peg_meta.peg"))

(assert-true "peg_meta.peg text loaded" (> (string-length meta-grammar-text) 0))

(define stage0-ast
  (parse-peg-grammar meta-grammar-text))

(assert-true "stage0-ast is <peg-grammar-def>" (peg-grammar-def? stage0-ast))
(assert-equal "grammar name is MetaGrammar" 'MetaGrammar (peg-grammar-def-name stage0-ast))
(assert-true "stage0-ast has rules" (> (length (peg-grammar-def-rules stage0-ast)) 10))

(display (string-append "Parsed "
                        (number->string (length (peg-grammar-def-rules stage0-ast)))
                        " rules from peg_meta.peg\n"))

;;; -----------------------------------------------------------------------
;;; Group 2: Self-Host Synthesized Stage 1 Parser
;;; -----------------------------------------------------------------------

(display "--- Group 2: Synthesize Stage 1 Parser from AST ---\n")

(define stage1-parser
  (compile-peg-grammar stage0-ast 'grammar_file))

(assert-true "stage1-parser procedure synthesized" (procedure? stage1-parser))

;; Test Stage 1 Parser on a sample grammar
(define sample-calc-grammar
"grammar Mini
expr: term '+' expr | term
term: [0-9]+
")

(let ((res (peg-parse-partial stage1-parser sample-calc-grammar)))
  (assert-true "stage1-parser parses sample grammar" (pair? res))
  (display "Stage 1 parser successfully parsed sample grammar.\n"))

;;; -----------------------------------------------------------------------
;;; Group 3: Fixed-Point Self-Hosting Verification: P1(peg_meta.peg)
;;; -----------------------------------------------------------------------

(display "--- Group 3: Fixed-Point Verification P1(peg_meta.peg) ---\n")

(let* ((ctx (make-parse-context meta-grammar-text))
       (res (vector #f #f 0)))
  (stage1-parser
   ctx 0
   (lambda (val next-pos fk)
     (vector-set! res 0 #t)
     (vector-set! res 1 val)
     (vector-set! res 2 next-pos))
   (lambda ()
     (vector-set! res 0 #f)))
  (let ((matched (vector-ref res 0))
        (result-pos (vector-ref res 2)))
    (display (string-append "Matched: " (if matched "#t" "#f")
                            ", result-pos: " (number->string result-pos)
                            ", max-pos: " (number->string (parse-ctx-max-pos ctx))
                            " / " (number->string (string-length meta-grammar-text)) "\n"))
    (assert-true "stage1-parser parses peg_meta.peg itself (Fixed-Point)" matched)
    (assert-equal "stage1-parser consumes full peg_meta.peg to EOF"
                  (string-length meta-grammar-text)
                  result-pos)))

;;; -----------------------------------------------------------------------
;;; Group 4: Direct-Style Source Self-Hosting Fixed-Point (Stage 1 == Stage 2)
;;; -----------------------------------------------------------------------

(display "--- Group 4: Direct-Style Source Self-Hosting Fixed-Point (Issue #948) ---\n")

(let* ((opts '((prefix . "peg-meta-")))
       (stage1-scm (emit-peg-grammar->scheme stage0-ast opts))
       (stage1-path "build/peg_meta_stage1.scm")
       (stage2-path "build/peg_meta_stage2.scm"))
  (call-with-output-file stage1-path
    (lambda (port)
      (display stage1-scm port)))
  (load stage1-path)
  (let* ((parse-fn (eval 'peg-meta-parse (interaction-environment)))
         (cst1 (parse-fn meta-grammar-text))
         (stage1-ast (optimize-grammar (peg-meta-cst->ast cst1)))
         (stage2-scm (emit-peg-grammar->scheme stage1-ast opts)))
    (call-with-output-file stage2-path
      (lambda (port)
        (display stage2-scm port)))
    (assert-equal "Stage 1 CST->AST matches Stage 0 optimized AST"
                  (ast->sexpr (optimize-grammar stage0-ast))
                  (ast->sexpr stage1-ast))
    (assert-true "Direct-Style Stage 1 .scm == Stage 2 .scm (byte-identical fixed point)"
                 (string=? stage1-scm stage2-scm))
    (display (string-append "[PASS] Stage 1 == Stage 2 fixed-point verified ("
                            (number->string (string-length stage1-scm))
                            " bytes).\n"))))

(display "\n[PASS] All PEG Self-Hosting tests passed successfully.\n\n")
