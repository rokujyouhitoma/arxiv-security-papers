;;; =======================================================================
;;; Test Suite: tools/grammars/*.peg All 13 Grammar Files Build & Execution
;;; Conforms to Issue #894 & Issue #908
;;; =======================================================================

(display "\n=== [Test Suite: tools/grammars/*.peg All 13 Files Build (Issue #894)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Compile and Build All 13 Grammar Files
;;; -----------------------------------------------------------------------

(display "--- Group 1: Parse and Compile All 13 Grammar Files ---\n")

(define grammar-files
  '("calc.peg"
    "search_query.peg"
    "graph_query.peg"
    "yaml_frontmatter.peg"
    "sql_expr.peg"
    "sql_dql.peg"
    "sql_dml.peg"
    "sql_ddl.peg"
    "sql_admin.peg"
    "bibtex.peg"
    "pdf_cmap.peg"
    "turtle.peg"
    "peg_meta.peg"
    "c99.peg"))

(for-each
 (lambda (fname)
   (let* ((fpath (string-append "../tools/grammars/" fname))
          (content (read-all-file-text fpath)))
     (assert-true (string-append fname " is not empty") (> (string-length content) 0))
     (let ((ast (parse-peg-grammar content)))
       (assert-true (string-append fname " parses into <peg-grammar-def>") (peg-grammar-def? ast))
       (assert-true (string-append fname " has rules") (> (length (peg-grammar-def-rules ast)) 0))
       (let ((parser (compile-peg-grammar ast)))
         (assert-true (string-append fname " synthesizes entry parser") (procedure? parser))
         (display (string-append "[PASS] " fname " ("
                                 (number->string (length (peg-grammar-def-rules ast)))
                                 " rules compiled successfully)\n"))))))
 grammar-files)

;;; -----------------------------------------------------------------------
;;; Group 2: E2E Parse Execution on calc.peg
;;; -----------------------------------------------------------------------

(display "--- Group 2: E2E Parse Execution on calc.peg ---\n")

(define calc-parser
  (compile-peg-file "../tools/grammars/calc.peg" 'expr))

(let ((res1 (peg-parse-partial calc-parser "10 + 20 * 3"))
      (res2 (peg-parse-partial calc-parser "(10 + 20) * 3"))
      (res3 (peg-parse-partial calc-parser "42")))
  (assert-true "calc.peg parses 10 + 20 * 3" (pair? res1))
  (assert-true "calc.peg parses (10 + 20) * 3" (pair? res2))
  (assert-true "calc.peg parses 42" (pair? res3))
  (display "calc.peg E2E execution PASS.\n"))

(display "\n[PASS] All 13 grammar files built and verified successfully.\n\n")
