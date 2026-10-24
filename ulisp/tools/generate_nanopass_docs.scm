;;; =======================================================================
;;; ULisp Tool: generate_nanopass_docs.scm
;;; Automatically generates Markdown specifications and Mermaid transition
;;; diagrams from all registered Nanopass intermediate languages.
;;; Conforms to Issue #586
;;; =======================================================================

(define (generate-mermaid-diagram langs)
  (display "```mermaid\n")
  (display "graph TD\n")
  (for-each
   (lambda (lang-name)
     (let* ((decl (language-declaration lang-name))
            (p (cadr (assq 'parent (cddr decl)))))
       (display "    ")
       (display lang-name)
       (display "[\"")
       (display lang-name)
       (display "\"]\n")
       (if p
           (begin
             (display "    ")
             (display p)
             (display " --> ")
             (display lang-name)
             (newline)))))
   langs)
  (display "```\n\n"))

(define (generate-language-docs lang-name)
  (let* ((decl (language-declaration lang-name))
         (p (cadr (assq 'parent (cddr decl))))
         (entry (cadr (assq 'entry (cddr decl))))
         (nongenerative-id (cadr (assq 'nongenerative-id (cddr decl))))
         (terms (cdr (assq 'terminals (cddr decl))))
         (nts (cdr (assq 'nonterminals (cddr decl))))
         (kws (cdr (assq 'keywords (cddr decl))))
         (rm (cdr (assq 'removed (cddr decl)))))
    (display "### 言語: `")
    (display lang-name)
    (display "`\n\n")
    (display "- **親言語 (Parent)**: ")
    (if p (begin (display "`") (display p) (display "`")) (display "(ルート言語)"))
    (newline)
    (display "- **エントリ非終端記号 (Entry)**: `")
    (display entry)
    (display "`\n")
    (display "- **Nongenerative ID**: `")
    (write nongenerative-id)
    (display "`\n\n")

    ;; Terminals Table
    (display "#### 終端記号 (Terminals)\n\n")
    (display "| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |\n")
    (display "| :--- | :--- |\n")
    (for-each
     (lambda (t)
       (display "| `")
       (display (car t))
       (display "` | `")
       (write (cadr t))
       (display "` |\n"))
     terms)
    (newline)

    ;; Nonterminals Table
    (display "#### 非終端記号とプロダクション規則 (Nonterminals & Productions)\n\n")
    (for-each
     (lambda (nt)
       (let ((nt-name (car nt))
             (meta-vars (cadr nt))
             (prods (caddr nt)))
         (display "##### `")
         (display nt-name)
         (display "` ")
         (write meta-vars)
         (display "\n\n```scheme\n")
         (for-each
          (lambda (prod)
            (display "  ")
            (write prod)
            (newline))
          prods)
         (display "```\n\n")))
     nts)

    ;; Removed Productions
    (if (not (null? rm))
        (begin
          (display "#### 削除・排除された不変条件 (Removed Invariants)\n\n")
          (display "本言語では以下の構文が明示的に禁止・脱糖済みとして排除されています：\n\n")
          (for-each
           (lambda (r)
             (display "- `")
             (write r)
             (display "`\n"))
           rm)
          (newline)))
    (display "---\n\n")))

(define (main)
  (let ((all-langs (nanopass-get-all-languages)))
    (display "[ULisp トップ](../README.md) > [ドキュメント一覧](README.md) > **Nanopass Framework 言語仕様書**\n\n---\n\n")
    (display "# ULisp Nanopass Framework 言語仕様書 (Language Specifications)\n\n")
    (display "本書は `ulisp/tools/generate_nanopass_docs.scm` により、登録済みの中間言語メタ情報から完全自動生成された仕様ドキュメントです。\n\n")
    (display "- **関連仕様書**:\n")
    (display "  - [パイプライン・Nanopass 詳細仕様書](spec_pipeline.md)\n")
    (display "  - [低レベル IR (LIR) 正典仕様書](spec_lir.md)\n")
    (display "  - [バックエンド & コード生成仕様書](spec_backend.md)\n")
    (display "  - [テスト実行ガイド](guide_testing.md)\n\n---\n\n")
    (display "## 1. 言語継承・構文遷移図 (Language Derivation Graph)\n\n")
    (generate-mermaid-diagram all-langs)
    (display "## 2. 各言語の詳細定義 (Language Definitions)\n\n")
    (for-each generate-language-docs all-langs)))

(main)
