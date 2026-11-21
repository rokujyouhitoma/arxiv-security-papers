;;; =======================================================================
;;; Test Suite: PEG-Synthesized C99 Lexer & <c-token> Stream (Issue #913)
;;; Conforms to DSN-33-11 §3.1, DSN-33-32 & Issue #913 / #931
;;; =======================================================================

(test-begin "PEG-Synthesized C99 Lexer & Token Stream (Issue #913)")

;;; -----------------------------------------------------------------------
;;; Group 1: All 37 C99 Keywords, Identifiers & Maximal-Munch Punctuators
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Keywords, Identifiers & Maximal-Munch Punctuators ---\n")

(define c99-all-keywords-src
  "auto break case char const continue default do double else enum extern
   float for goto if inline int long register restrict return short signed
   sizeof static struct switch typedef union unsigned void volatile while
   _Bool _Complex _Imaginary my_ident_123")

(let ((toks (c-tokenize-string c99-all-keywords-src "kw.c")))
  (assert-equal "1.1 37 keywords + 1 ident + 1 eof = 39 tokens" 39 (length toks))
  (let check-kws ((i 0))
    (if (< i 37)
        (begin
          (assert-equal (string-append "1.2 token #" (number->string i) " is keyword")
                        'keyword
                        (c-token-kind (list-ref toks i)))
          (check-kws (+ i 1)))))
  (assert-true "1.3 c-token-is-keyword? matches _Imaginary"
               (c-token-is-keyword? (list-ref toks 36) '_Imaginary))
  (let ((id-tok (list-ref toks 37))
        (eof-tok (list-ref toks 38)))
    (assert-equal "1.4 my_ident_123 is ident" 'ident (c-token-kind id-tok))
    (assert-equal "1.5 ident value is symbol my_ident_123" 'my_ident_123 (c-token-value id-tok))
    (assert-equal "1.6 trailing token is eof" 'eof (c-token-kind eof-tok))))

(let ((ptoks (c-tokenize-string "a <<= b >>= c ... -> ++ -- << >> <= >= == != && || += -= *= /= %= &= ^= |= ## <:" "punct.c")))
  (assert-true "1.7 3-char <<= recognized" (c-token-is-punct? (list-ref ptoks 1) "<<="))
  (assert-true "1.8 3-char >>= recognized" (c-token-is-punct? (list-ref ptoks 3) ">>="))
  (assert-true "1.9 3-char ... recognized" (c-token-is-punct? (list-ref ptoks 5) "..."))
  (assert-true "1.10 2-char -> recognized" (c-token-is-punct? (list-ref ptoks 6) "->"))
  (assert-true "1.11 2-char ## recognized" (c-token-is-punct? (list-ref ptoks 25) "##"))
  (assert-true "1.12 digraph <: recognized" (c-token-is-punct? (list-ref ptoks 26) "<:")))

;;; -----------------------------------------------------------------------
;;; Group 2: Integer, Float, Char, String Literals & Escape Decoding
;;; -----------------------------------------------------------------------
(display "--- Group 2: Numeric, Char, String Literals & String Concatenation ---\n")

(let ((ntoks (c-tokenize-string "42 0755 0xCAFEULL 3.14 0x1.8p+1 2.5e-1f" "nums.c")))
  (assert-equal "2.1 decimal 42 -> 42" 42 (c-token-value (list-ref ntoks 0)))
  (assert-equal "2.2 octal 0755 -> 493" 493 (c-token-value (list-ref ntoks 1)))
  (assert-equal "2.3 hex 0xCAFEULL -> 51966" 51966 (c-token-value (list-ref ntoks 2)))
  (let ((f1 (c-token-value (list-ref ntoks 3)))
        (f2 (c-token-value (list-ref ntoks 4)))
        (f3 (c-token-value (list-ref ntoks 5))))
    (assert-true "2.4 decimal float 3.14 decoded" (and (inexact? f1) (< (abs (- f1 3.14)) 0.0001)))
    (assert-true "2.5 C99 hex float 0x1.8p+1 == 3.0" (and (inexact? f2) (< (abs (- f2 3.0)) 0.0001)))
    (assert-true "2.6 scientific float 2.5e-1f == 0.25" (and (inexact? f3) (< (abs (- f3 0.25)) 0.0001)))))

(let ((ctoks (c-tokenize-string "'A' '\\n' '\\x41' '\\101' '\\0'" "chars.c")))
  (assert-equal "2.7 'A' -> 65" 65 (c-token-value (list-ref ctoks 0)))
  (assert-equal "2.8 '\\n' -> 10" 10 (c-token-value (list-ref ctoks 1)))
  (assert-equal "2.9 '\\x41' -> 65" 65 (c-token-value (list-ref ctoks 2)))
  (assert-equal "2.10 '\\101' -> 65" 65 (c-token-value (list-ref ctoks 3)))
  (assert-equal "2.11 '\\0' -> 0" 0 (c-token-value (list-ref ctoks 4))))

(let* ((stoks (c-tokenize-string "\"hello \" \"world\\n\" L\"!\"" "strs.c"))
       (merged (c-concat-adjacent-string-tokens stoks))
       (mtok (car merged)))
  (assert-equal "2.12 merged string + eof -> 2 tokens" 2 (length merged))
  (assert-equal "2.13 adjacent strings concatenated with escape decoded"
                "hello world\n!"
                (c-token-value mtok))
  (assert-equal "2.14 merged span starts at col 1" 1 (span-start-col (c-token-span mtok))))

;;; -----------------------------------------------------------------------
;;; Group 3: Line Continuation (\\\n), Physical Span, at-bol? & has-leading-space?
;;; -----------------------------------------------------------------------
(display "--- Group 3: Line Continuation, Source Span & CPP Whitespace Flags ---\n")

(let ((ltoks (c-tokenize-string "int fo\\\no = 1;\n#define FOO(x) x\n#define BAR (x)" "splice.c")))
  (let ((id-tok (list-ref ltoks 1))
        (eq-tok (list-ref ltoks 2))
        (foo-lparen (list-ref ltoks 8))
        (bar-lparen (list-ref ltoks 15))
        (hash-tok1 (list-ref ltoks 5)))
    (assert-equal "3.1 spliced identifier fo\\no reassembled as foo" 'foo (c-token-value id-tok))
    (assert-equal "3.2 spliced foo starts at physical line 1" 1 (span-start-line (c-token-span id-tok)))
    (assert-equal "3.3 spliced foo ends at physical line 2" 2 (span-end-line (c-token-span id-tok)))
    (assert-equal "3.4 '=' sits on physical line 2" 2 (span-start-line (c-token-span eq-tok)))
    (assert-true "3.5 '#' after newline has at-bol? = #t" (c-token-at-bol? hash-tok1))
    (assert-false "3.6 '(' in #define FOO(x) has has-leading-space? = #f"
                  (c-token-has-leading-space? foo-lparen))
    (assert-true "3.7 '(' in #define BAR (x) has has-leading-space? = #t"
                 (c-token-has-leading-space? bar-lparen))
    (let ((hs-tok (c-token-clone-with-hide-set id-tok '(MACRO_A))))
      (assert-equal "3.8 clone-with-hide-set preserves span and updates hide-set"
                    '(MACRO_A)
                    (c-token-hide-set hs-tok)))))

;;; -----------------------------------------------------------------------
;;; Group 4: Round-Trip Integration with #931 PEG C99 Parser (L_c_ast)
;;; -----------------------------------------------------------------------
(display "--- Group 4: Round-Trip Integration with #931 C99 PEG Parser ---\n")

(let* ((lua-src
        "typedef unsigned char lu_byte;
         typedef int (*lua_CFunction)(void *L);
         int lua_entry(void *L) {
           const char *msg = \"lua\" \"5.4\";
           lu_byte tag = 0x1A;
           return (int)tag;
         }")
       (toks (c-concat-adjacent-string-tokens (c-tokenize-string lua-src "lua_roundtrip.c")))
       (reconstructed (c-tokens->source-string toks))
       (ast (parse-c99-string reconstructed "lua_roundtrip.c")))
  (assert-true "4.1 c-tokens->source-string round-trips cleanly into #931 L_c_ast"
               (and (ast-has-span? ast)
                    (eq? (car (ast-strip-span ast)) 'c-translation-unit))))

;;; -----------------------------------------------------------------------
;;; Group 5: Security & Error Diagnostics (C99-LEX-001 / 002 / 003)
;;; -----------------------------------------------------------------------
(display "--- Group 5: Diagnostic Error Reporting on Malformed Input ---\n")

(let ((err1 (guard (ex (else ex))
              (c-tokenize-string "int x; /* unclosed comment" "err1.c")))
      (err2 (guard (ex (else ex))
              (c-tokenize-string "const char *s = \"unclosed" "err2.c")))
      (err3 (guard (ex (else ex))
              (c-tokenize-string "int x = @;" "err3.c")))
      (err4 (guard (ex (else ex))
              (c-tokenize-string "int x = 123abc;" "err4.c"))))
  (assert-equal "5.1 unterminated block comment raises C99-LEX-001" "C99-LEX-001" (cadr err1))
  (assert-equal "5.2 unterminated string literal raises C99-LEX-002" "C99-LEX-002" (cadr err2))
  (assert-equal "5.3 invalid character '@' raises C99-LEX-003" "C99-LEX-003" (cadr err3))
  (assert-equal "5.4 malformed numeric literal '123abc' raises C99-LEX-003" "C99-LEX-003" (cadr err4)))

(test-end "PEG-Synthesized C99 Lexer & Token Stream (Issue #913)")
