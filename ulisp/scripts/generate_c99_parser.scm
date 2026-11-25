;;; =======================================================================
;;; Build-time C99 Direct-Style Static Scheme Parser Generator (Issue #949)
;;; Generates frontend_c/generated_c99_parser.scm from tools/grammars/c99.peg
;;; =======================================================================

(let ((in-path (if (file-exists? "../tools/grammars/c99.peg")
                   "../tools/grammars/c99.peg"
                   "tools/grammars/c99.peg"))
      (out-path (if (file-exists? "frontend_c/parser.scm")
                    "frontend_c/generated_c99_parser.scm"
                    "ulisp/frontend_c/generated_c99_parser.scm")))
  (write-peg-file->scheme! in-path out-path (c99-emit-scheme-options))
  (display (string-append "[PASS] Generated Direct-Style C99 parser: " out-path "\n")))
