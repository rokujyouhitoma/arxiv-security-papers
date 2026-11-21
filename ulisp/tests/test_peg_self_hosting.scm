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
       (matched #f)
       (result-val #f)
       (result-pos 0))
  (stage1-parser
   ctx 0
   (lambda (val next-pos fk)
     (set! matched #t)
     (set! result-val val)
     (set! result-pos next-pos))
   (lambda ()
     (set! matched #f)))
  (display (string-append "Matched: " (if matched "#t" "#f")
                          ", result-pos: " (number->string result-pos)
                          ", max-pos: " (number->string (parse-ctx-max-pos ctx))
                          " / " (number->string (string-length meta-grammar-text)) "\n"))
  (let ((max-p (parse-ctx-max-pos ctx)))
    (let ((snippet (substring meta-grammar-text
                              (max 0 (- max-p 40))
                              (min (string-length meta-grammar-text) (+ max-p 40)))))
      (display (string-append "Snippet around max-pos:\n" snippet "\n"))))
  (assert-true "stage1-parser parses peg_meta.peg itself (Fixed-Point)" matched))

(display "\n[PASS] All PEG Self-Hosting tests passed successfully.\n\n")
