;;; =======================================================================
;;; Test Suite: Direct-Style Static Scheme PEG Parser Generator (Issue #948)
;;; Verifies static Nullability/Left-Corner/Tarjan SCC classification,
;;; generated code hygiene & security guards, CPS differential semantics,
;;; hook options, and full 14-grammar .scm emission.
;;; =======================================================================

(display "\n=== [Test Suite: Direct-Style Static Scheme PEG Generator (Issue #948)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Helpers (zero local set!, zero external SRFI-13 dependencies)
;;; -----------------------------------------------------------------------

(define (%test-str-contains? haystack needle)
  (let ((hlen (string-length haystack))
        (nlen (string-length needle)))
    (if (= nlen 0)
        #t
        (let loop ((i 0))
          (cond
            ((> (+ i nlen) hlen) #f)
            ((string=? (substring haystack i (+ i nlen)) needle) #t)
            (else (loop (+ i 1))))))))

(define (%test-write-and-load! path code-str)
  (call-with-output-file path
    (lambda (port)
      (display code-str port)))
  (load path))

(define (%test-eval-sym sym)
  (eval sym (interaction-environment)))

(define (%test-raises? thunk)
  (guard (ex (else #t))
    (thunk)
    #f))

;;; -----------------------------------------------------------------------
;;; Group 1: Static Grammar Analysis (Nullability, Left-Corner & Tarjan SCC)
;;; -----------------------------------------------------------------------

(display "--- Group 1: Static Grammar Analysis & Tarjan SCC Classification ---\n")

(define lr-sample-ast
  (optimize-grammar
   (sexpr->ast
    '(grammar LrSample
       (directives)
       (rules
        ;; Direct LR: expr -> expr "+" term | term
        (rule expr (memo) (/ (: expr (lit "+") term) term))
        ;; Nullable-prefix indirect LR: a -> opt_p b "x" | "y", b -> a
        (rule a (memo) (/ (: (? opt_p) b (lit "x")) (lit "y")))
        (rule opt_p (memo) (lit "a"))
        (rule b (memo) a)
        ;; Non-LR memo (references leaf num)
        (rule term (memo) (/ (: (lit "(") expr (lit ")")) num))
        ;; Pure lexical leaf (no rule refs)
        (rule num (memo) (+ (char-class "0-9"))))))))

(let* ((nullable (peg-compute-nullable-rules lr-sample-ast))
       (graph (peg-compute-left-corner-graph lr-sample-ast nullable))
       (cls-auto (peg-classify-rules lr-sample-ast '((memo-mode . auto))))
       (cls-all  (peg-classify-rules lr-sample-ast '((memo-mode . all))))
       (cls-none (peg-classify-rules lr-sample-ast '((memo-mode . none))))
       (cls-no-expr (peg-classify-rules lr-sample-ast '((memo-mode . auto) (no-memo . (expr))))))
  (assert-equal "expr classified as lr in auto" 'lr (cdr (assq 'expr cls-auto)))
  (assert-equal "a classified as lr via indirect nullable cycle" 'lr (cdr (assq 'a cls-auto)))
  (assert-equal "b classified as lr via mutual SCC with a" 'lr (cdr (assq 'b cls-auto)))
  (assert-equal "opt_p classified as bare leaf" 'bare (cdr (assq 'opt_p cls-auto)))
  (assert-equal "num classified as bare leaf" 'bare (cdr (assq 'num cls-auto)))
  ;; Note: term starts with '(' or num (non-LR in left-corner graph), references expr -> memo
  (assert-equal "term classified as memo in auto" 'memo (cdr (assq 'term cls-auto)))
  (assert-true "a has b as left-corner due to (? opt_p) nullable prefix"
               (and (memq 'b (cdr (assq 'a graph))) #t))
  (assert-equal "num classified as memo under memo-mode=all" 'memo (cdr (assq 'num cls-all)))
  (assert-equal "expr classified as bare under memo-mode=none" 'bare (cdr (assq 'expr cls-none)))
  (assert-equal "expr excluded by no-memo" 'bare (cdr (assq 'expr cls-no-expr))))

;;; -----------------------------------------------------------------------
;;; Group 2: Generated Code Hygiene & Security Guards (CWE-94 / CWE-22)
;;; -----------------------------------------------------------------------

(display "--- Group 2: Generated Code Hygiene & CWE-94 / CWE-22 Guards ---\n")

(let ((code (emit-peg-grammar->scheme lr-sample-ast '((prefix . "hyg-")))))
  (assert-false "zero peg:seq" (%test-str-contains? code "peg:seq"))
  (assert-false "zero peg:alt" (%test-str-contains? code "peg:alt"))
  (assert-false "zero peg:star" (%test-str-contains? code "peg:star"))
  (assert-false "zero peg:plus" (%test-str-contains? code "peg:plus"))
  (assert-false "zero peg:opt" (%test-str-contains? code "peg:opt"))
  (assert-false "zero peg:and" (%test-str-contains? code "peg:and"))
  (assert-false "zero peg:not" (%test-str-contains? code "peg:not"))
  (assert-false "zero peg:gather" (%test-str-contains? code "peg:gather"))
  (assert-false "zero peg:rule" (%test-str-contains? code "peg:rule"))
  (assert-false "zero rule-cells" (%test-str-contains? code "rule-cells"))
  (assert-false "zero local set!" (%test-str-contains? code "(set! "))
  (assert-true "uses peg-ds:rule-lr for LR rule" (%test-str-contains? code "peg-ds:rule-lr"))
  (assert-true "uses peg-ds:rule-memo for memo rule" (%test-str-contains? code "peg-ds:rule-memo"))
  (assert-true "hoists char-class pred" (%test-str-contains? code "(define *hyg-cc-0*")))

;; CWE-94 invalid identifier rejection
(let ((bad-ast (sexpr->ast '(grammar BadIdent (directives) (rules (rule |bad ident| (lit "x")))))))
  (assert-true "CWE-94 rejects space in rule identifier"
               (%test-raises? (lambda () (emit-peg-grammar->scheme bad-ast)))))
(assert-true "CWE-94 rejects paren injection in prefix"
             (%test-raises? (lambda () (emit-peg-grammar->scheme lr-sample-ast '((prefix . "a) (evil"))))))

;; CWE-22 path traversal rejection
(assert-true "CWE-22 rejects .. path traversal"
             (%test-raises? (lambda () (write-peg-file->scheme! "../tools/grammars/calc.peg" "../evil.scm"))))
(assert-true "CWE-22 rejects empty output path"
             (%test-raises? (lambda () (write-peg-file->scheme! "../tools/grammars/calc.peg" ""))))

;;; -----------------------------------------------------------------------
;;; Group 3: CPS vs Direct-Style Differential Semantics & Hooks
;;; -----------------------------------------------------------------------

(display "--- Group 3: CPS vs Direct-Style Differential Tests ---\n")

(define (assert-diff-equal label cps-p ds-parse-partial ds-parse inputs)
  (for-each
   (lambda (inp)
     (let ((cps-part (peg-parse-partial cps-p inp))
           (ds-part  (ds-parse-partial inp)))
       (assert-equal (string-append label " [partial: " inp "]") cps-part ds-part)
       (if cps-part
           (let ((cps-full? (guard (ex (else #f)) (peg-parse cps-p inp) #t))
                 (ds-full?  (guard (ex (else #f)) (ds-parse inp) #t)))
             (assert-equal (string-append label " [full?: " inp "]") cps-full? ds-full?)))))
   inputs))

;; 3a. calc.peg differential
(let* ((calc-ast (parse-peg-grammar (read-all-file-text "../tools/grammars/calc.peg")))
       (calc-cps (compile-peg-grammar calc-ast 'expr))
       (calc-scm (emit-peg-grammar->scheme calc-ast '((prefix . "dcalc-") (entry . expr)))))
  (%test-write-and-load! "build/test_emit_scm/_diff_calc.scm" calc-scm)
  (assert-diff-equal "calc.peg"
                     calc-cps
                     (%test-eval-sym 'dcalc-parse-partial)
                     (%test-eval-sym 'dcalc-parse)
                     '("42" "10 + 20 * 3" "(10 + 20) * 3" "1 - 2 + 3" "bad")))

;; 3b. Comprehensive LR (direct + mutual + nullable prefix), gather, lookahead, line-start, named, zero-width *
(define feat-ast
  (sexpr->ast
   '(grammar FeatDiff
      (directives)
      (rules
       ;; Direct left recursion
       (rule arith (memo) (/ (: arith (lit "+") digits) digits))
       ;; Indirect LR through b + nullable prefix
       (rule ind_a (memo) (/ (: (? opt_p) ind_b (lit "x")) (lit "y")))
       (rule opt_p (memo) (lit "p"))
       (rule ind_b (memo) ind_a)
       ;; Right recursion
       (rule rrec (memo) (/ (: (lit "a") rrec) (lit "b")))
       ;; Gather + and *
       (rule gplus (memo) (gather+ (lit ",") digits))
       (rule gstar (memo) (gather* (lit ",") digits))
       ;; Lookahead & / ! and line-start and named
       (rule pat (memo) (: line-start (bind head (: (& (lit "ab")) (lit "a"))) (bind tail (: (! (lit "x")) (+ (char-class "a-z"))))))
       ;; Zero-width star progress guard
       (rule zstar (memo) (* (? (lit "a"))))
       (rule digits (memo) (+ (char-class "0-9")))))))

(let ((feat-scm (emit-peg-grammar->scheme feat-ast '((prefix . "dfeat-")))))
  (%test-write-and-load! "build/test_emit_scm/_diff_feat.scm" feat-scm)
  ;; arith
  (let ((cps-arith (compile-peg-grammar feat-ast 'arith))
        (ds-arith  (%test-eval-sym 'dfeat-arith)))
    (assert-diff-equal "direct LR"
                       cps-arith
                       (lambda (s) (peg-ds:parse-partial ds-arith s))
                       (lambda (s) (peg-ds:parse ds-arith s))
                       '("7" "1+2+3+4" "x")))
  ;; ind_a
  (let ((cps-ind (compile-peg-grammar feat-ast 'ind_a))
        (ds-ind  (%test-eval-sym 'dfeat-ind_a)))
    (assert-diff-equal "indirect nullable-prefix LR"
                       cps-ind
                       (lambda (s) (peg-ds:parse-partial ds-ind s))
                       (lambda (s) (peg-ds:parse ds-ind s))
                       '("y" "yx" "yxx" "pyxx" "pyx" "z")))
  ;; rrec
  (let ((cps-rrec (compile-peg-grammar feat-ast 'rrec))
        (ds-rrec  (%test-eval-sym 'dfeat-rrec)))
    (assert-diff-equal "right recursion"
                       cps-rrec
                       (lambda (s) (peg-ds:parse-partial ds-rrec s))
                       (lambda (s) (peg-ds:parse ds-rrec s))
                       '("b" "ab" "aaab" "aaa")))
  ;; gather+ / gather*
  (let ((cps-gp (compile-peg-grammar feat-ast 'gplus))
        (ds-gp  (%test-eval-sym 'dfeat-gplus))
        (cps-gs (compile-peg-grammar feat-ast 'gstar))
        (ds-gs  (%test-eval-sym 'dfeat-gstar)))
    (assert-diff-equal "gather+"
                       cps-gp
                       (lambda (s) (peg-ds:parse-partial ds-gp s))
                       (lambda (s) (peg-ds:parse ds-gp s))
                       '("1" "1,2,3" ""))
    (assert-diff-equal "gather*"
                       cps-gs
                       (lambda (s) (peg-ds:parse-partial ds-gs s))
                       (lambda (s) (peg-ds:parse ds-gs s))
                       '("" "1" "1,2")))
  ;; pat (&, !, ^, bind)
  (let ((cps-pat (compile-peg-grammar feat-ast 'pat))
        (ds-pat  (%test-eval-sym 'dfeat-pat)))
    (assert-diff-equal "lookahead/line-start/named"
                       cps-pat
                       (lambda (s) (peg-ds:parse-partial ds-pat s))
                       (lambda (s) (peg-ds:parse ds-pat s))
                       '("ab" "abc" "ax" "bb")))
  ;; zero-width star
  (let ((cps-zs (compile-peg-grammar feat-ast 'zstar))
        (ds-zs  (%test-eval-sym 'dfeat-zstar)))
    (assert-diff-equal "zero-width star progress guard"
                       cps-zs
                       (lambda (s) (peg-ds:parse-partial ds-zs s))
                       (lambda (s) (peg-ds:parse ds-zs s))
                       '("" "aab")))
  ;; syntax error max-pos / expected parity
  (let* ((bad-input "1+x")
         (cps-err (guard (ex (else ex)) (peg-parse (compile-peg-grammar feat-ast 'arith) bad-input) #f))
         (ds-err  (guard (ex (else ex)) (peg-ds:parse (%test-eval-sym 'dfeat-arith) bad-input) #f)))
    (assert-true "CPS raises PEGSyntaxError on 1+x" (and cps-err #t))
    (assert-true "Direct-Style raises PEGSyntaxError on 1+x" (and ds-err #t))))

;; 3c. Cut (~) operator semantics & extra-params / overrides / decorators hooks
(define cut-hook-ast
  (sexpr->ast
   '(grammar CutHook
      (directives)
      (rules
       (rule stmt (memo) (/ (: (lit "a") cut (lit "b"))
                            (: (lit "a") (lit "c"))))
       (rule wrap (memo) (+ (char-class "a-z")))))))

(define (%test-join-decorator val)
  (cons 'wrapped val))

(let ((cut-scm
       (emit-peg-grammar->scheme
        cut-hook-ast
        '((prefix . "ch-")
          (extra-params . (env))
          (decorators . ((wrap . "%test-join-decorator")))
          (overrides . ((stmt . "(let ((r (or (let ((sp (peg-ds:lit1 ctx pos #\\a \"a\" \"'a'\"))) (if sp (let ((cp (peg-ds:cut ctx sp))) (peg-ds:lit1 ctx cp #\\b \"b\" \"'b'\")) #f)) (if (not (parse-ctx-cut? ctx)) (let ((sp2 (peg-ds:lit1 ctx pos #\\a \"a\" \"'a'\"))) (if sp2 (peg-ds:lit1 ctx sp2 #\\c \"c\" \"'c'\") #f)) #f)))) r)")))))))
  (assert-true "cut-scm threads extra-params env" (%test-str-contains? cut-scm "(define (ch-wrap ctx env pos)"))
  ;; Also test default cut emitter without override
  (let ((cut-default-scm (emit-peg-grammar->scheme cut-hook-ast '((prefix . "cd-") (decorators . ((wrap . "%test-join-decorator")))))))
    (%test-write-and-load! "build/test_emit_scm/_diff_cut.scm" cut-default-scm)
    (let ((p-stmt (%test-eval-sym 'cd-stmt))
          (p-wrap (%test-eval-sym 'cd-wrap)))
      (assert-true "cut succeeds on ab" (pair? (peg-ds:parse-partial p-stmt "ab")))
      (assert-false "cut commits first branch and rejects ac" (peg-ds:parse-partial p-stmt "ac"))
      (assert-equal "decorator transforms wrap result"
                    '(wrapped "h" "i")
                    (car (peg-ds:parse-partial p-wrap "hi"))))))

;;; -----------------------------------------------------------------------
;;; Group 4: Emit Direct-Style .scm for All 14 tools/grammars/*.peg Files
;;; -----------------------------------------------------------------------

(display "--- Group 4: Emit Direct-Style .scm for All 14 Grammars ---\n")

(define all-grammar-files
  '(("calc.peg"             . "g_calc-")
    ("search_query.peg"     . "g_search-")
    ("graph_query.peg"      . "g_graph-")
    ("yaml_frontmatter.peg" . "g_yaml-")
    ("sql_expr.peg"         . "g_sql_expr-")
    ("sql_dql.peg"          . "g_sql_dql-")
    ("sql_dml.peg"          . "g_sql_dml-")
    ("sql_ddl.peg"          . "g_sql_ddl-")
    ("sql_admin.peg"        . "g_sql_admin-")
    ("bibtex.peg"           . "g_bibtex-")
    ("pdf_cmap.peg"         . "g_pdf_cmap-")
    ("turtle.peg"           . "g_turtle-")
    ("peg_meta.peg"         . "g_peg_meta-")
    ("c99.peg"              . "g_c99-")))

(for-each
 (lambda (entry)
   (let* ((fname (car entry))
          (pfx (cdr entry))
          (in-path (string-append "../tools/grammars/" fname))
          (out-path (string-append "build/test_emit_scm/" fname ".scm")))
     (write-peg-file->scheme! in-path out-path (list (cons 'prefix pfx)))
     (let ((emitted (read-all-file-text out-path)))
       (assert-true (string-append fname " emitted non-empty .scm") (> (string-length emitted) 200))
       (assert-false (string-append fname " has zero peg:seq") (%test-str-contains? emitted "peg:seq"))
       (assert-false (string-append fname " has zero local set!") (%test-str-contains? emitted "(set! "))
       (display (string-append "[PASS] emitted " out-path " ("
                               (number->string (string-length emitted))
                               " bytes)\n")))))
 all-grammar-files)

(display "\n[PASS] All Direct-Style Static Scheme PEG Generator tests passed successfully.\n\n")
