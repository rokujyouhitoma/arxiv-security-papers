# ULisp メタコンパイラ R7RS 仕様準拠状況リファレンス (Specification Compliance)

本ドキュメントは、**ULisp (Underlying LISP)** ネイティブ AOT メタコンパイラにおける **R7RS-small (Revised^7 Report on the Algorithmic Language Scheme - Small Language, 2013)** および **R7RS-large (Large Language: Red Edition, Tangerine Edition, 主要 SRFI)** の仕様準拠状況、対応機能、未対応機能、ならびに該当する仕様番号（Section 番号 / SRFI 番号）を網羅した包括的技術リファレンスである。

システム全体の設計思想および ABI 規約については、正典仕様書である [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) を参照すること。

---

## 凡例 (Status Legend)

| 記号 | ステータス | 定義 |
| :---: | :--- | :--- |
| **◎** | **完全サポート (Supported)** | AOT ネイティブコンパイル (x86-64) および Portable C バックエンドで完全動作し、テストスイートで検証済み。 |
| **△** | **部分サポート (Partial)** | 基本機能は動作するが、オプショナル引数の省略や一部機能制限（例: 整数 Fixnum 限定等）がある状態。 |
| **×** | **未サポート (Not Supported)** | 現時点で未実装。将来的な Issue で順次実装が計画されているものを含む。 |
| **✕\*** | **AOT 対象外 (Out of Scope)** | 事前コンパイル型 (AOT) ネイティブコンパイラの特性（スタンドアロン静的バイナリ出力）上、意図的に除外または制限している機能（動的 `eval`, `load`, 対話型 `repl` 等）。 |

---

## 1. R7RS-small 言語仕様準拠状況

### 1.1 式とコア構文 (Section 4: Expressions)

| R7RS 仕様番号 | 構文 / 手続き名 | 形式・記法 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **4.1.1** | 変数参照 (Variable references) | `<variable>` | **◎** | [Pass 040](../passes/040_analysis.scm) | 静的スコープ解決・レキシカル環境 |
| **4.1.2** | リテラル式 (Literal expressions) | `(quote <datum>)`, `'<datum>` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm)<br>[Pass 030](../passes/030_desugar.scm) | 即値・S 式定数化 |
| **4.1.3** | 手続き呼び出し (Procedure calls) | `(<operator> <operand> ...)` | **◎** | [Pass 130](../passes/130_lir.scm) | TCO (末尾呼び出し最適化) 完全保証 |
| **4.1.4** | ラムダ式 (Procedures) | `(lambda <formals> <body>)` | **◎** | [Pass 110](../passes/110_closure_convert.scm) | 固定引数およびレスト引数 `(lambda (x . rest) ...)` 対応 |
| **4.1.5** | 条件式 (Conditionals) | `(if <test> <consequent> <alternate>)` | **◎** | [Pass 030](../passes/030_desugar.scm) | 2分岐・3分岐条件ジャンプ展開 |
| **4.1.6** | 代入 (Assignments) | `(set! <variable> <expression>)` | **◎** | [Pass 030](../passes/030_desugar.scm)<br>[Pass 130](../passes/130_lir.scm) | 局所・大域変数の破壊的再束縛 |
| **4.1.7** | ファイル包含 (Inclusion) | `(include <string1> ...)` | **△** | [Pass 010](../passes/010_library.scm) | ビルド時静的ファイル結合で対応 |
| **4.1.7** | ファイル包含 (大文字小文字無視) | `(include-ci <string1> ...)` | **×** | - | 未実装 |
| **4.2.1** | 条件分岐 (Conditionals) | `(cond <clause1> ...)` | **◎** | [Pass 030](../passes/030_desugar.scm) | `else` 節およびパイプライン構文 `(=> <proc>)` 完全脱糖 |
| **4.2.1** | メンバマッチング分岐 | `(case <key> <clause1> ...)` | **◎** | [Pass 030](../passes/030_desugar.scm) | `memq` 比較連鎖に脱糖 |
| **4.2.1** | 短絡論理積 | `(and <test1> ...)` | **◎** | [Pass 030](../passes/030_desugar.scm) | ネストした `if` に脱糖 |
| **4.2.1** | 短絡論理和 | `(or <test1> ...)` | **◎** | [Pass 030](../passes/030_desugar.scm) | 一時束縛付き `if` に脱糖 |
| **4.2.1** | 1方向真分岐 | `(when <test> <body>)` | **◎** | [Pass 020](../passes/020_macro_expander.scm)<br>[Pass 030](../passes/030_desugar.scm) | マクロ展開 |
| **4.2.1** | 1方向偽分岐 | `(unless <test> <body>)` | **◎** | [Pass 020](../passes/020_macro_expander.scm)<br>[Pass 030](../passes/030_desugar.scm) | マクロ展開 |
| **4.2.1** | 条件付き機能展開 | `(cond-expand <ce-clause> ...)` | **△** | [Pass 010](../passes/010_library.scm) | プラットフォーム基本識別のみ |
| **4.2.2** | 並列束縛 (Binding constructs) | `(let (<binding> ...) <body>)` | **◎** | [Pass 030](../passes/030_desugar.scm) | 局所変数フレーム・即時適用ラムダ脱糖 |
| **4.2.2** | 名前付き let (Named let) | `(let <variable> (<binding> ...) <body>)` | **◎** | [Pass 030](../passes/030_desugar.scm) | 局所末尾再帰ループ `letrec` に脱糖 |
| **4.2.2** | 直列束縛 | `(let* (<binding> ...) <body>)` | **◎** | [Pass 030](../passes/030_desugar.scm) | ネストした `let` に脱糖 |
| **4.2.2** | 相互再帰束縛 | `(letrec (<binding> ...) <body>)` | **◎** | [Pass 030](../passes/030_desugar.scm)<br>[Pass 110](../passes/110_closure_convert.scm) | 相互再帰クロージャ束縛 |
| **4.2.2** | 評価順序保証相互再帰 | `(letrec* (<binding> ...) <body>)` | **△** | [Pass 030](../passes/030_desugar.scm) | `letrec` と同等として処理 |
| **4.2.2** | 多値束縛 | `(let-values (<mv-binding> ...) <body>)` | **◎** | [Pass 030](../passes/030_desugar.scm) | `call-with-values` に脱糖 ([Issue #538](../../docs/issues/closed/538-implement-r7rs-multiple-values-call-with-values.md)) |
| **4.2.2** | 直列多値束縛 | `(let*-values (<mv-binding> ...) <body>)` | **◎** | [Pass 030](../passes/030_desugar.scm) | ネストした `let-values` に脱糖 ([Issue #538](../../docs/issues/closed/538-implement-r7rs-multiple-values-call-with-values.md)) |
| **4.2.3** | 順序実行 (Sequencing) | `(begin <expression1> ...)` | **◎** | [Pass 030](../passes/030_desugar.scm)<br>[Pass 070](../passes/070_anf.scm) | 直列実行ブロック |
| **4.2.4** | 反復実行 (Iteration) | `(do ((<var> <init> <step>) ...) ...)` | **×** | - | [Issue #559](../../docs/issues/559-implement-r7rs-do-loop-syntax.md) にて実装予定 |
| **4.2.5** | 遅延評価 (Delayed evaluation) | `(delay <expression>)` | **◎** | [Pass 030](../passes/030_desugar.scm)<br>[ulisp/lib/promise.scm](../lib/promise.scm) | SRFI-45 準拠プロミス脱糖 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| **4.2.5** | プロミス強制評価 | `(force <promise>)` | **◎** | [ulisp/lib/promise.scm](../lib/promise.scm) | メモ化・再入可能・トランポリン平坦化評価 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| **4.2.5** | 末尾遅延評価 | `(delay-force <expression>)` | **◎** | [Pass 030](../passes/030_desugar.scm)<br>[ulisp/lib/promise.scm](../lib/promise.scm) | 定数空間反復遅延評価・空間リーク防止 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| **4.2.5** | プロミス生成 | `(make-promise <obj>)` | **◎** | [ulisp/lib/promise.scm](../lib/promise.scm) | 既存プロミス透過・即値プロミス化 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| **4.2.5** | プロミス述語 | `(promise? <obj>)` | **◎** | [ulisp/lib/promise.scm](../lib/promise.scm) | プロミスタグ検査述語 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| **4.2.6** | 動的パラメータ (Dynamic bindings)| `(make-parameter <init> [<conv>])` | **◎** | [ulisp/lib/parameter.scm](../lib/parameter.scm) | 動的環境セル生成 ([Issue #537](../../docs/issues/closed/537-implement-r7rs-parameters-and-parameterize.md)) |
| **4.2.6** | パラメータ一時束縛 | `(parameterize ((<param> <val>) ...) <body>)` | **◎** | [Pass 030](../passes/030_desugar.scm) | `dynamic-wind` と連携する復元保証脱糖 |
| **4.2.7** | 例外処理 (Exception handling) | `(guard (<var> <clause1> ...) <body>)` | **◎** | [Pass 030](../passes/030_desugar.scm) | 動的例外スタック脱糖 ([Issue #531](../../docs/issues/closed/531-implement-lightweight-exception-handling-guard-raise.md)) |
| **4.2.8** | 準引用 (Quasiquotation) | `` `<qq-template> ``, `,`, `,@` | **◎** | [Pass 030](../passes/030_desugar.scm) | リスト構築 `cons`/`append` へのマクロ脱糖 |
| **4.3.1** | 局所マクロ束縛 | `(let-syntax (<binding> ...) <body>)` | **×** | - | トップレベルマクロ優先のため未実装 |
| **4.3.1** | 局所再帰マクロ束縛 | `(letrec-syntax (<binding> ...) <body>)` | **×** | - | 同上 |
| **4.3.2** | 衛生的マクロ (Pattern language)| `(syntax-rules (<literal> ...) <syntax-rule> ...)` | **◎** | [Pass 020](../passes/020_macro_expander.scm) | パターン変数・省略記号 `...`・リテラル完全照合 ([Issue #533](../../docs/issues/closed/533-implement-hygienic-syntax-rules-macro-expander.md)) |
| **4.3.3** | マクロ構文エラー | `(syntax-error <message> <args> ...)` | **×** | - | 未実装 |

---

### 1.2 プログラム構造とモジュール (Section 5: Program Structure)

| R7RS 仕様番号 | 構文 / 項目 | 形式・記法 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **5.1** | プログラム (Programs) | トップレベル式および定義の並び | **◎** | [Pass 030](../passes/030_desugar.scm) | `%program` ノードによる全体構造化 |
| **5.2 / 5.6** | モジュールインポート | `(import <import-set> ...)` | **◎** | [Pass 010](../passes/010_library.scm) | ライブラリ依存解決・シンボル修飾 ([Issue #548](../../docs/issues/closed/548-implement-r7rs-define-library-and-import-syntax.md)) |
| **5.3.1** | トップレベル変数定義 | `(define <variable> <expression>)` | **◎** | [Pass 030](../passes/030_desugar.scm) | グローバルシンボル束縛 |
| **5.3.1** | 手続き定義短縮構文 | `(define (<variable> <formals>) <body>)` | **◎** | [Pass 030](../passes/030_desugar.scm) | `lambda` 束縛への自動脱糖 |
| **5.3.2** | 内部定義 (Internal definitions) | ブロック先頭の `(define ...)` | **◎** | [Pass 030](../passes/030_desugar.scm) | `letrec*` 構造への自動巻き直し |
| **5.3.3** | 多値定義 | `(define-values <formals> <expression>)` | **×** | - | [Issue #560](../../docs/issues/560-implement-r7rs-define-values-syntax.md) にて実装中 |
| **5.4** | マクロ定義 (Syntax definitions)| `(define-syntax <keyword> <transformer>)` | **◎** | [Pass 020](../passes/020_macro_expander.scm) | コンパイル時マクロテーブル登録 |
| **5.5** | レコード型定義 (Record-types) | `(define-record-type <name> (<ctor> ...) <pred> ...)` | **◎** | [Pass 030](../passes/030_desugar.scm) | 固定長ベクタ脱糖マクロ・型述語・アクセサ・ミューテータ完備 ([Issue #549](../../docs/issues/closed/549-implement-r7rs-define-record-type-macro.md)) |
| **5.6** | ライブラリ定義 (Libraries) | `(define-library (<name> ...) <lib-decl> ...)` | **◎** | [Pass 010](../passes/010_library.scm) | R7RS-small モジュール宣言・フラット展開 ([Issue #548](../../docs/issues/closed/548-implement-r7rs-define-library-and-import-syntax.md)) |
| **5.6** | シンボルエクスポート | `(export <export-spec> ...)` | **◎** | [Pass 010](../passes/010_library.scm) | 名前空間公開設定・`rename` 対応 |

---

### 1.3 標準手続き・データ型 (Section 6: Standard Procedures)

#### 6.1 等価性述語 (Equivalence Predicates)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.1** | `(eq? x y)` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | ポインタ同一性および即値タグの一致判定 |
| **6.1** | `(eqv? x y)` | **◎** | [ulisp/lib/equality.scm](../lib/equality.scm) | 数値・文字の同一性を含む R7RS 完全準拠判定 ([Issue #532](../../docs/issues/closed/532-implement-r7rs-eqv-and-standard-type-predicates.md)) |
| **6.1** | `(equal? x y)` | **◎** | [ulisp/lib/equality.scm](../lib/equality.scm) | ペア・ベクタ・文字列・バイトベクタの再帰的同値比較 |

#### 6.2 数値演算 (Numbers: 63-bit Tagged Fixnum Architecture)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.2.6** | `number?`, `integer?`, `exact?`, `exact-integer?` | **◎** | [ulisp/lib/predicates.scm](../lib/predicates.scm) | 最下位 3-bit タグ (`000b`) による Fixnum 判定 |
| **6.2.6** | `real?`, `rational?`, `complex?` | **△** | [ulisp/lib/predicates.scm](../lib/predicates.scm) | 整数塔のみサポートのため `integer?` のエイリアスとして実装 |
| **6.2.6** | `inexact?` | **△** | [ulisp/lib/predicates.scm](../lib/predicates.scm) | 常に `#f` を返却 (浮動小数点数非サポート) |
| **6.2.6** | `zero?`, `positive?`, `negative?` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 符号・ゼロ判定プリミティブ |
| **6.2.6** | `odd?`, `even?` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | LSB ビット判定 |
| **6.2.6** | `+`, `-`, `*` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm)<br>[Pass 130](../passes/130_lir.scm) | 63-bit 加減乗算、定数畳み込み、x86/C バックエンド直結 |
| **6.2.6** | `/`, `quotient`, `modulo` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 整数除算・剰余、ゼロ除算トラップ保護 |
| **6.2.6** | `=`, `<`, `>`, `<=`, `>=` | **◎** | [Pass 130](../passes/130_lir.scm) | 整数比較、分岐融合 (Branch Fusion) 最適化 ([Issue #545](../../docs/issues/closed/545-implement-condition-branch-flag-fusion.md)) |
| **6.2.6** | `max`, `min`, `abs` | **△** | [compiler/primitives.scm](../compiler/primitives.scm) | 2引数固定で基本演算を提供 |
| **6.2.6** | `floor/`, `floor-quotient`, `floor-remainder` | **×** | - | 未実装 |
| **6.2.6** | `truncate/`, `truncate-quotient`, `truncate-remainder` | **×** | - | 未実装 |
| **6.2.6** | `remainder`, `gcd`, `lcm`, `square`, `expt` | **×** | - | [Issue #558](../../docs/issues/558-implement-r7rs-elementary-integer-math-procedures.md) にて実装予定 |
| **6.2.6** | `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `exp`, `log`, `sqrt` | **×** | - | 超越関数 (浮動小数点非サポートのため未実装) |

#### 6.3 真偽値 (Booleans)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.3** | `not` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | `#f` 判定 (Scheme の偽値は `#f` のみ) |
| **6.3** | `boolean?` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 即値ブールタグ (`00101111b`, `01101111b`) 判定 |
| **6.3** | `boolean=?` | **◎** | [ulisp/lib/equality.scm](../lib/equality.scm) | 真偽値同値判定 |

#### 6.4 ペアとリスト (Pairs and Lists)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.4** | `pair?`, `null?` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | ヒープペア型タグ判定・空リスト (`'()`) 判定 |
| **6.4** | `cons`, `car`, `cdr` | **◎** | [Pass 060](../passes/060_lvn.scm)<br>[Pass 130](../passes/130_lir.scm) | ペア生成・要素取得、LVN / 純粋アクセサ最適化 |
| **6.4** | `set-car!`, `set-cdr!` | **◎** | [ulisp/lib/gc.scm](../lib/gc.scm) | 破壊的代入、世代別 GC ライトバリア・リメンバーセット記録 |
| **6.4** | `caar`, `cadr`, `cdar`, `cddr`, `caddr`, `cdddr`, `cadddr` | **◎** | [Pass 030](../passes/030_desugar.scm) | リスト短縮アクセサ |
| **6.4** | `list?`, `list`, `length`, `reverse`, `append` | **◎** | [ulisp/lib/predicates.scm](../lib/predicates.scm)<br>[ulisp/lib/string.scm](../lib/string.scm) | 基本リスト操作 |
| **6.4** | `memq`, `memv`, `member` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 要素探索 |
| **6.4** | `assq`, `assv`, `assoc` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 連想リストキー探索 |
| **6.4** | `make-list`, `list-copy` | **◎** | [ulisp/lib/list.scm](../lib/list.scm)<br>[Pass 030](../passes/030_desugar.scm) | 浅いスパイン複製・充填生成 ([Issue #551](../../docs/issues/closed/551-expand-r7rs-standard-library-procedures.md)) |
| **6.4** | `list-tail`, `list-ref`, `list-set!` | **×** (△) | - | [Issue #555](../../docs/issues/555-implement-r7rs-list-accessors-list-tail-ref-set.md) にて実装予定 |

#### 6.5 シンボル (Symbols)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.5** | `symbol?` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | シンボル型タグ判定 |
| **6.5** | `symbol=?` | **◎** | [ulisp/lib/equality.scm](../lib/equality.scm) | シンボル一意比較 |
| **6.5** | `symbol->string`, `string->symbol` | **◎** | [ulisp/lib/string.scm](../lib/string.scm) | グローバルシンボルレジストリ・インターン ([Issue #528](../../docs/issues/closed/528-implement-static-symbol-interning-and-dead-code-elimination.md)) |

#### 6.6 文字 (Characters)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.6** | `char?`, `char=?` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 即値文字タグ判定・比較 |
| **6.6** | `char->integer`, `integer->char` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | コードポイント相互変換 |
| **6.6** | `char<?`, `char>?`, `char<=?`, `char>=?` | **×** | - | [Issue #556](../../docs/issues/556-implement-r7rs-character-comparison-predicates.md) にて実装予定 |
| **6.6** | `char-ci=?`, `char-alphabetic?`, `char-numeric?` 等 | **×** | - | Unicode 特性判定 (未実装) |

#### 6.7 文字列 (Strings)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.7** | `string?`, `make-string`, `string-length` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | ヒープ文字列アロケーション・長さ取得 |
| **6.7** | `string-ref`, `string-set!` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | インデックスアクセスおよびインプレース更新 |
| **6.7** | `string=?` | **◎** | [ulisp/lib/string.scm](../lib/string.scm) | 文字列内容比較 |
| **6.7** | `substring`, `string-append` | **◎** | [Pass 030](../passes/030_desugar.scm)<br>[ulisp/lib/string.scm](../lib/string.scm) | スライシング・2分木分割結合脱糖 |
| **6.7** | `string-copy`, `string-copy!`, `string-fill!`, `string-map`, `string-for-each` | **◎** | [ulisp/lib/string.scm](../lib/string.scm)<br>[Pass 030](../passes/030_desugar.scm) | オーバーラップ安全コピー・充填・反復マッピング ([Issue #551](../../docs/issues/closed/551-expand-r7rs-standard-library-procedures.md)) |
| **6.7** | `string`, `string<?`, `string>?`, `string<=?`, `string>=?` | **×** | - | [Issue #557](../../docs/issues/557-implement-r7rs-string-vector-list-conversions-and-string-ordering.md) にて実装予定 |
| **6.7** | `string->list`, `list->string` | **×** | - | [Issue #557](../../docs/issues/557-implement-r7rs-string-vector-list-conversions-and-string-ordering.md) にて実装予定 |

#### 6.8 ベクタ (Vectors)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.8** | `vector?`, `make-vector`, `vector` | **◎** | [ulisp/lib/vector.scm](../lib/vector.scm) | 連続ヒープベクタ型 ([Issue #536](../../docs/issues/closed/536-implement-complete-r7rs-vectors-and-indexing.md)) |
| **6.8** | `vector-length`, `vector-ref`, `vector-set!` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | O(1) ランダムアクセス・更新 |
| **6.8** | `vector-copy`, `vector-copy!`, `vector-append`, `vector-fill!` | **◎** | [ulisp/lib/vector.scm](../lib/vector.scm)<br>[Pass 030](../passes/030_desugar.scm) | スライス複製・破壊的転送・充填 |
| **6.8** | `vector->list`, `list->vector` | **◎** | [ulisp/lib/vector.scm](../lib/vector.scm)<br>[Pass 030](../passes/030_desugar.scm) | リスト・ベクタ相互変換 |
| **6.8** | `vector-map`, `vector-for-each` | **◎** | [ulisp/lib/vector.scm](../lib/vector.scm) | ベクタ要素マッピング・走査 |
| **6.8** | `vector->string`, `string->vector` | **×** | - | 直接相互変換 (未実装) |

#### 6.9 バイトベクタ (Bytevectors)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.9** | `bytevector?`, `make-bytevector`, `bytevector` | **◎** | [ulisp/lib/bytevector.scm](../lib/bytevector.scm) | 8-bit 生バイト配列型 ([Issue #535](../../docs/issues/closed/535-implement-r7rs-bytevectors-for-binary-security.md)) |
| **6.9** | `bytevector-length`, `bytevector-u8-ref`, `bytevector-u8-set!` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | バイト単位の読み書き |
| **6.9** | `bytevector-copy`, `bytevector-copy!`, `bytevector-append`, `bytevector=?`| **◎** | [ulisp/lib/bytevector.scm](../lib/bytevector.scm)<br>[Pass 030](../passes/030_desugar.scm) | メモリブロック高速コピー・比較 |
| **6.9** | `utf8->string`, `string->utf8` | **◎** | [ulisp/lib/bytevector.scm](../lib/bytevector.scm)<br>[Pass 030](../passes/030_desugar.scm) | UTF-8 エンコード / デコード変換 |

#### 6.10 制御機能・継続・多値 (Control Features)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.10** | `procedure?` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 手続き型タグ判定 |
| **6.10** | `apply` | **◎** | [Pass 110](../passes/110_closure_convert.scm)<br>[Pass 130](../passes/130_lir.scm) | クロージャへの可変長引数アンパック呼び出し |
| **6.10** | `call-with-current-continuation`, `call/cc` | **◎** | [continuations_and_unwind.md](continuations_and_unwind.md) | スタックセグメントコピー方式ファーストクラス継続 ([Issue #540](../../docs/issues/closed/540-implement-full-first-class-call-with-current-continuation-call-cc.md)) |
| **6.10** | `dynamic-wind` | **◎** | [ulisp/lib/continuation.scm](../lib/continuation.scm) | LCA (Lowest Common Ancestor) による unwind/rewind 遷移 |
| **6.10** | `values`, `call-with-values` | **◎** | [ulisp/lib/values.scm](../lib/values.scm) | ゼロアロケーション多値返却・受け渡し ABI ([Issue #538](../../docs/issues/closed/538-implement-r7rs-multiple-values-call-with-values.md)) |
| **6.10** | `map`, `for-each` (複数引数リスト版) | **△** | [ulisp/lib/list.scm](../lib/list.scm) | 単一リストおよびベクタ版は提供。多変数リスト版は未対応 |

#### 6.11 例外機構 (Exceptions)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.11** | `with-exception-handler` | **◎** | [ulisp/lib/exception.scm](../lib/exception.scm) | 動的例外ハンドラ登録 ([Issue #531](../../docs/issues/closed/531-implement-lightweight-exception-handling-guard-raise.md)) |
| **6.11** | `raise`, `raise-continuable` | **◎** | [ulisp/lib/exception.scm](../lib/exception.scm) | 脱出型・復帰型例外送出 |
| **6.11** | `error` | **◎** | [Pass 030](../passes/030_desugar.scm) | エラーオブジェクト生成・送出マクロ |
| **6.11** | `error-object?`, `error-object-message`, `error-object-irritants` | **◎** | [ulisp/lib/exception.scm](../lib/exception.scm) | エラー情報抽出アクセサ |
| **6.11** | `read-error?`, `file-error?` | **◎** | [ulisp/lib/exception.scm](../lib/exception.scm) | エラーカテゴリ型判定 |

#### 6.12 環境と動的評価 (Environments and Evaluation)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.12** | `eval`, `environment` | **✕\*** | - | 純粋 AOT ネイティブコンパイラのため実行時動的 eval は除外 (マクロ展開で完結) |

#### 6.13 入出力とポート (Input and Output)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.13.1** | `port?`, `input-port?`, `output-port?` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | ポート型述語 ([Issue #537](../../docs/issues/closed/537-implement-r7rs-parameters-and-parameterize.md)) |
| **6.13.1** | `textual-port?`, `binary-port?`, `port-open?` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | テキスト/バイナリ識別および状態判定 |
| **6.13.1** | `close-port`, `close-input-port`, `close-output-port` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | ポートクローズ |
| **6.13.1** | `current-input-port`, `current-output-port` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | 標準入力 (`*stdin-port*`)・標準出力 (`*stdout-port*`) |
| **6.13.1** | `open-input-string`, `open-output-string`, `get-output-string` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | メモリ上文字列ポート ([Issue #534](../../docs/issues/closed/534-implement-r7rs-string-ports.md)) |
| **6.13.2** | `read` | **◎** | [ulisp/lib/reader.scm](../lib/reader.scm) | 自前完全再帰下降 S 式パーサ |
| **6.13.2** | `read-char`, `peek-char` | **◎** | [ulisp/lib/port.scm](../lib/port.scm)<br>[ulisp/lib/posix.scm](../lib/posix.scm) | 1文字先読み・消費 |
| **6.13.2** | `eof-object?`, `eof-object` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | EOF 即値タグ判定 |
| **6.13.3** | `write`, `display` | **◎** | [ulisp/lib/printer.scm](../lib/printer.scm) | S 式シリアライザおよび文字列表現出力 |
| **6.13.3** | `write-char`, `write-string`, `newline`, `flush-output-port` | **◎** | [ulisp/lib/port.scm](../lib/port.scm)<br>[ulisp/lib/posix.scm](../lib/posix.scm) | バッファ付きテキスト出力 |
| **6.13.3** | `write-shared`, `write-simple` | **×** | - | 循環参照出力 (未実装) |

#### 6.14 システムインターフェース (System Interface)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.14** | `exit`, `emergency-exit` | **◎** | [ulisp/lib/posix.scm](../lib/posix.scm) | POSIX `sys-exit` 終了コード返却 |
| **6.14** | `load` | **✕\*** | - | 動的コードロード (AOT のためビルド時静的リンクで代替) |
| **6.14** | `file-exists?`, `delete-file` | **△** | [ulisp/lib/posix.scm](../lib/posix.scm) | 低レベル syscall で可能。ポート API 未整備 |
| **6.14** | `command-line` | **△** | [runtime.c](../runtime.c) | ランタイム引数渡しで基本対応 |
| **6.14** | `get-environment-variable`, `get-environment-variables` | **×** | - | 環境変数取得 (未実装) |
| **6.14** | `current-second`, `current-jiffy`, `jiffies-per-second` | **×** | - | 高精度タイマー (未実装) |

---

### 1.4 R7RS-small 標準 16 ライブラリ別網羅表

| ライブラリ識別子 | 主な責務・内容 | サポート率 | 内部実装ファイル | 主なサポート機能 / 未サポート理由 |
| :--- | :--- | :--- | :--- | :--- |
| `(scheme base)` | コア構文、算術、リスト、ベクタ、継続、多値、ポート | **約 85%** | [ulisp/lib/scheme/base.sld](../lib/scheme/base.sld)<br>([ulisp/lib/*.scm](../lib/)) | 構文・`call/cc`・多値・ベクタ・GC 完備。有理数・複素数・浮動小数演算のみ非サポート ([Issue #562](../../docs/issues/562-implement-r7rs-standard-library-definitions-sld.md)) |
| `(scheme case-lambda)` | 可変個引数パターンマッチング | **× 0%** | [ulisp/lib/scheme/case-lambda.sld](../lib/scheme/case-lambda.sld) | `case-lambda` 未実装（レスト引数 `(lambda (x . rest) ...)` で代替可能） |
| `(scheme char)` | Unicode 大文字小文字変換・判定 | **約 20%** | [ulisp/lib/scheme/char.sld](../lib/scheme/char.sld)<br>([compiler/primitives.scm](../compiler/primitives.scm)) | `char=?`, `char->integer` のみ。Unicode 大小比較・Case-folding 未実装 |
| `(scheme complex)` | 複素数算術 | **× 0%** | [ulisp/lib/scheme/complex.sld](../lib/scheme/complex.sld) | 非サポート（Fixnum 優先アーキテクチャ） |
| `(scheme cxr)` | `caaa...r` 〜 `cddddr` (全24種) | **◎ 100%** | [ulisp/lib/scheme/cxr.sld](../lib/scheme/cxr.sld) | R7RS 規定の全 24 種合成ペアアクセサをライブラリ定義内で完備 |
| `(scheme eval)` | 動的評価 (`eval`, `environment`) | **✕\* 0%** | [ulisp/lib/scheme/eval.sld](../lib/scheme/eval.sld) | AOT の性質上除外（事前コンパイル時マクロ展開で完結） |
| `(scheme file)` | ファイル入出力 | **△ 約 40%** | [ulisp/lib/scheme/file.sld](../lib/scheme/file.sld)<br>([ulisp/lib/posix.scm](../lib/posix.scm)) | POSIX `sys-read`/`sys-write` 実装済み。上位ストリーム関数は未整備 |
| `(scheme inexact)` | 浮動小数点数・超越関数 | **× 0%** | [ulisp/lib/scheme/inexact.sld](../lib/scheme/inexact.sld) | 非サポート（整数・Tagged Pointer 設計） |
| `(scheme lazy)` | 遅延評価 (`delay`, `force`) | **◎ 100%** | [ulisp/lib/scheme/lazy.sld](../lib/scheme/lazy.sld)<br>([ulisp/lib/promise.scm](../lib/promise.scm)) | SRFI-45 準拠プロミス完備 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| `(scheme load)` | スクリプト動的ロード | **✕\* 0%** | [ulisp/lib/scheme/load.sld](../lib/scheme/load.sld) | AOT の性質上除外（`import` またはビルド時結合で代替） |
| `(scheme process-context)` | プロセス環境 (`exit`, `command-line`) | **約 50%** | [ulisp/lib/scheme/process-context.sld](../lib/scheme/process-context.sld)<br>([ulisp/lib/posix.scm](../lib/posix.scm)) | `exit`, `emergency-exit` 完備。`get-environment-variable` は未実装 |
| `(scheme r5rs)` | R5RS 互換仕様シンボル群 | **約 85%** | [ulisp/lib/scheme/r5rs.sld](../lib/scheme/r5rs.sld) | R5RS 標準シンボル群の互換エクスポート定義 |
| `(scheme read)` | S 式リーダー (`read`) | **◎ 100%** | [ulisp/lib/scheme/read.sld](../lib/scheme/read.sld)<br>([ulisp/lib/reader.scm](../lib/reader.scm)) | 自前完全再帰下降パーサ完備 |
| `(scheme repl)` | 対話型 REPL | **✕\* 0%** | [ulisp/lib/scheme/repl.sld](../lib/scheme/repl.sld) | AOT コンパイラのため静的バイナリ出力が正典 |
| `(scheme time)` | 時間計測 (`current-second`) | **△ 約 30%** | [ulisp/lib/scheme/time.sld](../lib/scheme/time.sld) | `current-second`, `current-jiffy`, `jiffies-per-second` 基本ラッパー定義 |
| `(scheme write)` | S 式ライター (`write`, `display`) | **約 70%** | [ulisp/lib/scheme/write.sld](../lib/scheme/write.sld)<br>([ulisp/lib/printer.scm](../lib/printer.scm)) | `write`, `display` 完備。`write-shared` は未実装 |

---

## 2. R7RS-large 言語仕様準拠状況

R7RS-large は、Scheme コミュニティの SRFI 群を「エディション (Editions)」として標準化した仕様です。

### 2.1 Red Edition (データ構造・アルゴリズム)

| 仕様番号 (SRFI) | 名称・対象機能 | ステータス | 内部実装ファイル | 備考・代替手段 |
| :--- | :--- | :---: | :--- | :--- |
| **SRFI 1** | Lists (高機能リスト処理: `fold`, `unfold`, `filter`, `take`, `drop` 等) | **△** | [ulisp/lib/list.scm](../lib/list.scm) | 基本関数（`append`, `reverse`, `length`, `memq`, `assq`）のみ。高階畳み込み系は未提供 |
| **SRFI 9** | Records (`define-record-type`) | **◎** | [Pass 030](../passes/030_desugar.scm) | 完全サポート ([Issue #549](../../docs/issues/closed/549-implement-r7rs-define-record-type-macro.md)) |
| **SRFI 11** | Syntax for multiple values (`let-values`, `let*-values`) | **◎** | [Pass 030](../passes/030_desugar.scm) | 完全サポート ([Issue #538](../../docs/issues/closed/538-implement-r7rs-multiple-values-call-with-values.md)) |
| **SRFI 39** | Parameter objects (`make-parameter`, `parameterize`) | **◎** | [ulisp/lib/parameter.scm](../lib/parameter.scm) | 完全サポート ([Issue #537](../../docs/issues/closed/537-implement-r7rs-parameters-and-parameterize.md)) |
| **SRFI 111** | Boxes (単一要素可変セル: `box`, `unbox`, `set-box!`) | **△** | - | 1要素ベクタまたはペア `(cons val '())` で代用可能（専用関数は未提供） |
| **SRFI 113** | Sets and Bags (集合・マルチセット) | **×** | - | 未実装 |
| **SRFI 116** | Immutable Pairs and Lists (不変リスト・ペア) | **×** | - | 未実装 |
| **SRFI 117** | Queues based on Lists (リストベースキュー) | **×** | - | 未実装 |
| **SRFI 121** | Generators (ジェネレータ・イテレータ) | **△** | - | ファーストクラス継続 (`call/cc`) によるコルーチンジェネレータ作成可能 |
| **SRFI 125** | Intermediate Hash Tables (ハッシュテーブル) | **△** | - | `*symbol-registry*` で内部ハッシュ探索あり。ユーザ向け汎用テーブル API は未提供 |
| **SRFI 128** | Comparators (比較器) | **×** | - | 未実装 |
| **SRFI 132** | Sort Libraries (ソート・マージアルゴリズム) | **×** | - | 未実装 |
| **SRFI 133** | Vectors (高機能ベクタ操作) | **◎** (準拠) | [ulisp/lib/vector.scm](../lib/vector.scm)<br>[Pass 030](../passes/030_desugar.scm) | `vector-copy`, `vector-copy!`, `vector-append`, `vector-fill!`, `vector-map`, `vector-for-each` 等を網羅 |
| **SRFI 134** | Immutable Deques (不変両端キュー) | **×** | - | 未実装 |
| **SRFI 135** | Immutable Texts (不変テキスト) | **×** | - | 未実装 |
| **SRFI 146** | Mappings (赤黒木 / AVL 木マップ) | **×** | - | 未実装 |

---

### 2.2 Tangerine Edition (数値・ビット演算・低レベル)

| 仕様番号 (SRFI) | 名称・対象機能 | ステータス | 内部実装ファイル | 備考・代替手段 |
| :--- | :--- | :---: | :--- | :--- |
| **SRFI 141** | Integer Division (6モードの整数除算) | **△** | [compiler/primitives.scm](../compiler/primitives.scm) | `quotient`, `modulo`, `/` のみサポート |
| **SRFI 143** | Fixnums (Fixnum 専用高速演算: `fx+`, `fx-`, `fxadd1` 等) | **◎** | [Pass 090](../passes/090_rtyper.scm) | `fxadd1`, `fxsub1` 等コンパイラ内部プリミティブおよび AOT アンボクシング対応 |
| **SRFI 144** | Flonums (浮動小数点数演算) | **×** | - | 浮動小数点型非対応のため未実装 |
| **SRFI 151** | Bitwise Operations (ビット演算) | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | `bitwise-and`, `bitwise-ior`, `bitwise-arithmetic-shift` サポート |
| **SRFI 160** | Homogeneous numeric vectors (u8, s8, u16 等の型付きベクタ) | **△** | [ulisp/lib/bytevector.scm](../lib/bytevector.scm) | `u8` (バイトベクタ) を完全サポート。16/32/64bit 型付きベクタは未実装 |
| **SRFI 179** | Nonempty Intervals and Arrays (多次元配列) | **×** | - | 未実装 |

---

### 2.3 その他主要 SRFI (システム・メタプログラミング)

| 仕様番号 (SRFI) | 名称・対象機能 | ステータス | 内部実装ファイル | 備考・代替手段 |
| :--- | :--- | :---: | :--- | :--- |
| **SRFI 170** | POSIX API (低レベルシステムコール) | **◎** (一部) | [ulisp/lib/posix.scm](../lib/posix.scm) | `sys-read`, `sys-write`, `sys-mmap`, `sys-exit`, `%raw-syscall` を実装 |
| **SRFI 64** | Test Suites API (ユニットテスト) | **△** | [ulisp/test.sh](../test.sh)<br>[ulisp/test_c.sh](../test_c.sh) | 自前アサーション・テストドライバで運用 |
| **SRFI 18 / 226**| Multithreading (スレッド並行処理) | **×** | - | シングルスレッドモデル |
| **SRFI 115** | Regular Expressions (正規表現) | **×** | - | 未実装 |
| **SRFI 145** | Assumptions (`assert`, `assume`) | **△** | [Pass 030](../passes/030_desugar.scm) | `guard` / `raise` / `error` で代用可能 |

---

## 3. R7RS 仕様トレーサビリティとライブラリメタデータ管理規約 (Issue #561)

ULisp における R7RS 標準準拠ライブラリおよびコンパイラモジュールの開発・保守においては、**「パターンB（ライブラリ宣言でのメタデータ集約）」と「セクションコメント（`;; §X.Y.Z`）」のハイブリッド方式** を公式規約として採用する。

### 3.1 ハイブリッド方式採択の理由
1. **R7RS 構文規則への完全適合**:
   `define-library` (§5.1) 配下の節は `export`, `import`, `begin`, `include`, `cond-expand` 等に限定されており、独自拡張構文を避けてコメント形式で仕様節を明記することで、コンパイラパーサ ([Pass 010](../passes/010_library.scm)) を一切阻害せず、100% の規格ポータビリティを保証する。
2. **粒度 (Granularity) の整合**:
   R7RS 仕様書の節番号（例: §5.3.3, §6.10）は機能グループ単位で定義されているため、ライブラリファイルヘッダおよび手続きセクション見出しコメントで管理することが自然であり、重複や保守コストを最小化できる。
3. **AOT ネイティブコンパイラとの親和性**:
   手続き内の docstring 式（パターンA）のような実行時メタデータ保持機構を排除し、コードサイズ・ヒープ割当・実行時オーバーヘッドを完全にゼロに保つ。

### 3.2 具体的コーディング記法

#### ① ライブラリ定義ファイル (`*.sld`)
ライブラリヘッダに R7RS 仕様番号および本ドキュメントへのトレーサビリティを明記する：
```scheme
;;; =====================================================================
;;; (scheme base) -- R7RS-small §5.1, §5.3, §6.1-§6.4
;;; Specification:
;;;   - §5.3.3: Derived expression types (let*, letrec*, cond, ...)
;;;   - §6.10:  Control features (values, call-with-values, dynamic-wind)
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;; =====================================================================

(define-library (scheme base)
  (export cond case and or let* letrec*
          values call-with-values
          dynamic-wind)
  (import (scheme core-primitives))
  (include "base/derived-syntax.scm"
           "base/control.scm"))
```

#### ② モジュール実装ファイル (`ulisp/lib/*.scm`)
各マクロ定義・手続き定義の直前にセクション番号見出しコメントを付与する：
```scheme
;; ---------------------------------------------------------------------
;; §5.3.3 Derived expression types: let*
;; ---------------------------------------------------------------------
(define-syntax let*
  (syntax-rules ()
    ((let* () body1 body2 ...)
     (let () body1 body2 ...))
    ((let* ((name val) rest ...) body1 body2 ...)
     (let ((name val))
       (let* (rest ...) body1 body2 ...)))))
```

#### ③ コンパイラ内部エラー診断 (Diagnostic Traceability)
マクロ展開器 ([Pass 020](../passes/020_macro_expander.scm)) や構文脱糖器 ([Pass 030](../passes/030_desugar.scm)) で構文エラーを検出した場合、エラーメッセージに仕様節タグを含める：
```scheme
(error "syntax-error [R7RS §5.3.3]: invalid formals in define-values" form)
```

---

## 4. まとめと今後のロードマップ

1. **R7RS-small コア言語としての達成度**:
   - 構文、第一級継続 (`call/cc` + `dynamic-wind`)、多値 (`values` / `call-with-values`)、完全ゼロアロケーション 2-Space GC、ベクタ、バイトベクタ、遅延評価 (`delay` / `force`)、衛生的マクロ展開器、自前 S 式パーサ/プリンタなど、スタンドアロンな Scheme ネイティブ実行系として **基盤機能の約 85% を完備**。
2. **実装完了済みの主要機能 (Recently Closed Issues)**:
   - [Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md): `delay`, `force`, `delay-force`, `promise?` (遅延評価)
   - [Issue #551](../../docs/issues/closed/551-expand-r7rs-standard-library-procedures.md): `list-copy`, `make-list`, `string-copy!`, `string-fill!` 等のシーケンス操作拡充
3. **進行中および直近の実装予定 (Open Issues)**:
   - [Issue #555](../../docs/issues/555-implement-r7rs-list-accessors-list-tail-ref-set.md): `list-tail`, `list-ref`, `list-set!` (リストインデックス操作)
   - [Issue #556](../../docs/issues/556-implement-r7rs-character-comparison-predicates.md): `char<?`, `char>?`, `char<=?`, `char>=?` (文字順序比較)
   - [Issue #557](../../docs/issues/557-implement-r7rs-string-vector-list-conversions-and-string-ordering.md): 文字列・ベクタ・リスト相互変換および文字列順序比較述語
   - [Issue #558](../../docs/issues/558-implement-r7rs-elementary-integer-math-procedures.md): `square`, `gcd`, `lcm`, `expt`, `remainder` (基本整数算術)
   - [Issue #559](../../docs/issues/559-implement-r7rs-do-loop-syntax.md): `do` (反復実行構文)
   - [Issue #560](../../docs/issues/560-implement-r7rs-define-values-syntax.md): `define-values` (多値定義構文)
   - [Issue #561](../../docs/issues/561-establish-r7rs-library-metadata-standard-and-link-compliance-tables.md): R7RS ライブラリメタデータ管理規約の確立と準拠表実装リンクの網羅
4. **アーキテクチャ特性に基づく設計トレードオフ**:
   - `eval`, `load`, `repl` などの動的実行系は、AOT コンパイラのバイナリ独立性・フットプリント最小化を優先して意図的に除外。
   - 数値塔（Number Tower）は 63-bit 即値 Fixnum を基本とし、ポインタタグの最小化と高速実行を優先。
