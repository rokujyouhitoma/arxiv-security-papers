[ULisp トップ](../README.md) > [ドキュメント一覧](README.md) > **R7RS 仕様準拠状況リファレンス**

---

# ULisp メタコンパイラ R7RS 仕様準拠状況リファレンス (Specification Compliance)

本ドキュメントは、**ULisp (Underlying LISP)** ネイティブ AOT メタコンパイラにおける **R7RS-small (Revised^7 Report on the Algorithmic Language Scheme - Small Language, 2013)** および **R7RS-large (Large Language: Red Edition, Tangerine Edition, Yellow / Orange / Hypnos Dockets, 主要 SRFI)** の仕様準拠状況、対応機能、未対応機能、ならびに該当する仕様番号（Section 番号 / SRFI 番号）を網羅した包括的技術リファレンスである。

- システム全体の設計思想および ABI 規約については、正典仕様書である [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) を参照すること。
- 関連仕様書:
  - [パイプライン・Nanopass 詳細仕様書](spec_pipeline.md)
  - [低レベル IR (LIR) 正典仕様書](spec_lir.md)
  - [ファーストクラス継続 & dynamic-wind 技術仕様書](spec_continuations_and_unwind.md)
- 本ドキュメント末尾の [第 5 章 原典・仕様規格参照情報源](#5-原典仕様規格参照情報源-primary-sources--official-specifications) に、R7RS-small、R7RS-large、および各 SRFI の公式一次情報源リンクをまとめて記載している。

---

## 凡例 (Status Legend)

| 記号 | ステータス | 定義 |
| :---: | :--- | :--- |
| **◎** | **完全サポート (Supported)** | AOT ネイティブコンパイル (x86-64 / AArch64) および Portable C バックエンドで完全動作し、テストスイートで検証済み。 |
| **△** | **部分サポート (Partial)** | 基本機能は動作するが、オプショナル引数の省略や一部機能制限（例: 整数 Fixnum 限定等）がある状態。 |
| **×** | **未サポート (Not Supported)** | 現時点で未実装。将来的な Issue で順次実装が計画されているものを含む。 |
| **✕\*** | **AOT 対象外 (Out of Scope)** | 事前コンパイル型 (AOT) ネイティブコンパイラの特性（スタンドアロン静的バイナリ出力）上、意図的に除外または制限している機能（動的 `eval`, `load`, 対話型 `repl` 等）。 |

---

## 1. R7RS-small 言語仕様準拠状況

### 1.1 式とコア構文 (Section 4: Expressions)

| R7RS 仕様番号 | 構文 / 手続き名 | 形式・記法 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **4.1.1** | 変数参照 (Variable references) | `<variable>` | **◎** | [Pass 040](../frontend/040_analysis.scm) | 静的スコープ解決・レキシカル環境 |
| **4.1.2** | リテラル式 (Literal expressions) | `(quote <datum>)`, `'<datum>` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 即値・S 式定数化 |
| **4.1.3** | 手続き呼び出し (Procedure calls) | `(<operator> <operand> ...)` | **◎** | [Pass 130](../lir/130_lir.scm) | TCO (末尾呼び出し最適化) 完全保証 |
| **4.1.4** | ラムダ式 (Procedures) | `(lambda <formals> <body>)` | **◎** | [Pass 110](../frontend/110_closure_convert.scm) | 固定引数およびレスト引数 `(lambda (x . rest) ...)` 対応 |
| **4.1.5** | 条件式 (Conditionals) | `(if <test> <consequent> <alternate>)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | 2分岐・3分岐条件ジャンプ展開 |
| **4.1.6** | 代入 (Assignments) | `(set! <variable> <expression>)` | **◎** | [Pass 030](../frontend/030_desugar.scm)<br>[Pass 130](../lir/130_lir.scm) | 局所・大域変数の破壊的再束縛 |
| **4.1.7** | ファイル包含 (Inclusion) | `(include <string1> ...)` | **◎** | [Pass 010](../frontend/010_library.scm) | ソース位置追跡付き静的ファイル結合・再帰インクルード対応 |
| **4.1.7** | ファイル包含 (大文字小文字無視) | `(include-ci <string1> ...)` | **◎** | [Pass 010](../frontend/010_library.scm) | 大小文字フォールディング静的ファイル結合・ソース位置追跡完全対応 ([Issue #659](../../docs/issues/closed/659-implement-r7rs-include-ci-syntax.md)) |
| **4.2.1** | 条件分岐 (Conditionals) | `(cond <clause1> ...)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | `else` 節およびパイプライン構文 `(=> <proc>)` 完全脱糖 |
| **4.2.1** | メンバマッチング分岐 | `(case <key> <clause1> ...)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | `else` 節、パイプライン構文 `(=> <proc>)`、`memq` 比較連鎖脱糖 |
| **4.2.1** | 短絡論理積 | `(and <test1> ...)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | ネストした `if` に脱糖 |
| **4.2.1** | 短絡論理和 | `(or <test1> ...)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | 一時束縛付き `if` に脱糖 |
| **4.2.1** | 1方向真分岐 | `(when <test> <body>)` | **◎** | [Pass 020](../frontend/020_macro_expander.scm)<br>[Pass 030](../frontend/030_desugar.scm) | マクロ展開 |
| **4.2.1** | 1方向偽分岐 | `(unless <test> <body>)` | **◎** | [Pass 020](../frontend/020_macro_expander.scm)<br>[Pass 030](../frontend/030_desugar.scm) | マクロ展開 |
| **4.2.1** | 条件付き機能展開 | `(cond-expand <ce-clause> ...)` | **◎** | [Pass 010](../frontend/010_library.scm) | R7RS 標準機能識別子群 (`r7rs`, `exact-closed`, `ratios`, `exact-complex`, `full-unicode`, `little-endian`, `big-endian`, `ulisp` 等) 完全網羅・再帰展開 ([Issue #658](../../docs/issues/closed/658-expand-r7rs-cond-expand-feature-identifiers.md)) |
| **4.2.1 / 4.3** | 補助構文識別子 (Auxiliary Syntax) | `else`, `=>`, `...`, `_` | **◎** | [Pass 020](../frontend/020_macro_expander.scm)<br>[Pass 030](../frontend/030_desugar.scm) | `(scheme base)` エクスポート予約語。`cond`/`case` 分岐補助および `syntax-rules` パターンマッチング照合補助 |
| **4.2.2** | 並列束縛 (Binding constructs) | `(let (<binding> ...) <body>)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | 局所変数フレーム・即時適用ラムダ脱糖 |
| **4.2.2** | 名前付き let (Named let) | `(let <variable> (<binding> ...) <body>)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | 局所末尾再帰ループ `letrec` に脱糖 |
| **4.2.2** | 直列束縛 | `(let* (<binding> ...) <body>)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | ネストした `let` に脱糖 |
| **4.2.2** | 相互再帰束縛 | `(letrec (<binding> ...) <body>)` | **◎** | [Pass 030](../frontend/030_desugar.scm)<br>[Pass 110](../frontend/110_closure_convert.scm) | 相互再帰クロージャ束縛 |
| **4.2.2** | 評価順序保証相互再帰 | `(letrec* (<binding> ...) <body>)` | **◎** | [Pass 028](../frontend/028_desugar_bindings.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 左から右への厳密評価・相互再帰脱糖 ([Issue #650](../../docs/issues/closed/650-implement-r7rs-letrec-star-evaluation-order.md)) |
| **4.2.2** | 多値束縛 | `(let-values (<mv-binding> ...) <body>)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | `call-with-values` に脱糖 ([Issue #538](../../docs/issues/closed/538-implement-r7rs-multiple-values-call-with-values.md)) |
| **4.2.2** | 直列多値束縛 | `(let*-values (<mv-binding> ...) <body>)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | ネストした `let-values` に脱糖 ([Issue #538](../../docs/issues/closed/538-implement-r7rs-multiple-values-call-with-values.md)) |
| **4.2.3** | 順序実行 (Sequencing) | `(begin <expression1> ...)` | **◎** | [Pass 030](../frontend/030_desugar.scm)<br>[Pass 070](../frontend/070_anf.scm) | 直列実行ブロック・トップレベルスプライシング |
| **4.2.4** | 反復実行 (Iteration) | `(do ((<var> <init> <step>) ...) ...)` | **◎** | [Pass 028](../frontend/028_desugar_bindings.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 名前付き let (`letrec`) への自動脱糖・並列変数更新・反復コマンド本体実行・複数終了式対応 ([Issue #559](../../docs/issues/closed/559-implement-r7rs-do-loop-syntax.md)) |
| **4.2.5** | 遅延評価 (Delayed evaluation) | `(delay <expression>)` | **◎** | [Pass 030](../frontend/030_desugar.scm)<br>[ulisp/lib/promise.scm](../lib/promise.scm) | SRFI-45 準拠プロミス脱糖 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| **4.2.5** | プロミス強制評価 | `(force <promise>)` | **◎** | [ulisp/lib/promise.scm](../lib/promise.scm) | メモ化・再入可能・トランポリン平坦化評価 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| **4.2.5** | 末尾遅延評価 | `(delay-force <expression>)` | **◎** | [Pass 030](../frontend/030_desugar.scm)<br>[ulisp/lib/promise.scm](../lib/promise.scm) | 定数空間反復遅延評価・空間リーク防止 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| **4.2.5** | プロミス生成 | `(make-promise <obj>)` | **◎** | [ulisp/lib/promise.scm](../lib/promise.scm) | 既存プロミス透過・即値プロミス化 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| **4.2.5** | プロミス述語 | `(promise? <obj>)` | **◎** | [ulisp/lib/promise.scm](../lib/promise.scm) | プロミスタグ検査述語 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| **4.2.6** | 動的パラメータ (Dynamic bindings)| `(make-parameter <init> [<conv>])` | **◎** | [ulisp/lib/parameter.scm](../lib/parameter.scm) | 動的環境セル生成 ([Issue #537](../../docs/issues/closed/537-implement-r7rs-parameters-and-parameterize.md)) |
| **4.2.6** | パラメータ一時束縛 | `(parameterize ((<param> <val>) ...) <body>)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | `dynamic-wind` と連携する復元保証脱糖 |
| **4.2.7** | 例外処理 (Exception handling) | `(guard (<var> <clause1> ...) <body>)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | 動的例外スタック脱糖 ([Issue #531](../../docs/issues/closed/531-implement-lightweight-exception-handling-guard-raise.md)) |
| **4.2.8** | 準引用 (Quasiquotation) | `(quasiquote <template>)`, `` `<qq-template> `` | **◎** | [Pass 030](../frontend/030_desugar.scm) | リスト構築 `cons`/`append` へのマクロ脱糖 |
| **4.2.8** | アンクオート (Unquote) | `(unquote <datum>)`, `,<datum>` | **◎** | [Pass 030](../frontend/030_desugar.scm) | 準引用テンプレート内式の動的評価展開 |
| **4.2.8** | アンクオートスプライス | `(unquote-splicing <datum>)`, `,@<datum>` | **◎** | [Pass 030](../frontend/030_desugar.scm) | 準引用テンプレート内リストのインライン展開 |
| **4.2.9** | 多重アリティ分岐 (Case-lambda) | `(case-lambda <clause> ...)` | **◎** | [Pass 028](../frontend/028_desugar_bindings.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 可変個引数パターンマッチング・動的アリティディスパッチ・GC安全スタックマップ ([Issue #609](../../docs/issues/closed/609-implement-r7rs-case-lambda-syntax.md)) |
| **4.3.1** | 局所マクロ束縛 | `(let-syntax (<binding> ...) <body>)` | **◎** | [Pass 020](../frontend/020_macro_expander.scm) | レキシカルスコープマクロ環境展開・非再帰性保証 ([Issue #657](../../docs/issues/closed/657-implement-r7rs-let-syntax-and-letrec-syntax.md)) |
| **4.3.1** | 局所再帰マクロ束縛 | `(letrec-syntax (<binding> ...) <body>)` | **◎** | [Pass 020](../frontend/020_macro_expander.scm) | 相互再帰および自己再帰マクロ展開・アリティディスパッチ完全サポート ([Issue #657](../../docs/issues/closed/657-implement-r7rs-let-syntax-and-letrec-syntax.md)) |
| **4.3.2** | 衛生的マクロ (Pattern language)| `(syntax-rules (<literal> ...) <syntax-rule> ...)` | **◎** | [Pass 020](../frontend/020_macro_expander.scm) | パターン変数・省略記号 `...`・リテラル完全照合 ([Issue #533](../../docs/issues/closed/533-implement-hygienic-syntax-rules-macro-expander.md)) |
| **4.3.3** | マクロ構文エラー | `(syntax-error <message> <args> ...)` | **◎** | [Pass 020](../frontend/020_macro_expander.scm)<br>[Pass 030](../frontend/030_desugar.scm) | マクロ展開時および脱糖時エラー検出・明示的コンパイル中断・予約語保護・irritants 報告 ([Issue #647](../../docs/issues/closed/647-implement-r7rs-syntax-error-syntax.md)) |

---

### 1.2 プログラム構造とモジュール (Section 5: Program Structure)

| R7RS 仕様番号 | 構文 / 項目 | 形式・記法 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **5.1** | プログラム (Programs) | トップレベル式および定義の並び | **◎** | [Pass 030](../frontend/030_desugar.scm) | `%program` ノードによる全体構造化 |
| **5.2 / 5.6** | モジュールインポート | `(import <import-set> ...)` | **◎** | [Pass 010](../frontend/010_library.scm) | ライブラリ依存解決・シンボル修飾 (`only`, `except`, `prefix`, `rename` 対応) ([Issue #548](../../docs/issues/closed/548-implement-r7rs-define-library-and-import-syntax.md)) |
| **5.3.1** | トップレベル変数定義 | `(define <variable> <expression>)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | グローバルシンボル束縛 |
| **5.3.1** | 手続き定義短縮構文 | `(define (<variable> <formals>) <body>)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | `lambda` 束縛への自動脱糖 |
| **5.3.2** | 内部定義 (Internal definitions) | ブロック先頭の `(define ...)` | **◎** | [Pass 028](../frontend/028_desugar_bindings.scm) / [030](../frontend/030_desugar.scm) | 内部変数定義（逐次 `let`）、内部手続き定義・相互再帰（集約 `letrec`）、カリー化短縮構文、スプライシング `begin` 完全対応・固定点ブートストラップ完了 ([Issue #592](../../docs/issues/592-implement-r7rs-internal-definition-desugaring.md)) |
| **5.3.3** | 多値定義 | `(define-values <formals> <expression>)` | **◎** | [Pass 025](../frontend/025_top_level.scm) / [029](../frontend/029_desugar_dynamic.scm) | トップレベルおよび内部定義対応、ゼロヒープ多値束縛・固定点ブートストラップ完了 ([Issue #560](../../docs/issues/closed/560-implement-r7rs-define-values-syntax.md)) |
| **5.4** | マクロ定義 (Syntax definitions)| `(define-syntax <keyword> <transformer>)` | **◎** | [Pass 020](../frontend/020_macro_expander.scm) | コンパイル時マクロテーブル登録 |
| **5.5** | レコード型定義 (Record-types) | `(define-record-type <name> (<ctor> ...) <pred> ...)` | **◎** | [Pass 030](../frontend/030_desugar.scm) | 固定長ベクタ脱糖マクロ・型述語・アクセサ・ミューテータ完備 ([Issue #549](../../docs/issues/closed/549-implement-r7rs-define-record-type-macro.md)) |
| **5.6** | ライブラリ定義 (Libraries) | `(define-library (<name> ...) <lib-decl> ...)` | **◎** | [Pass 010](../frontend/010_library.scm) | R7RS-small モジュール宣言・フラット展開 ([Issue #548](../../docs/issues/closed/548-implement-r7rs-define-library-and-import-syntax.md)) |
| **5.6** | シンボルエクスポート | `(export <export-spec> ...)` | **◎** | [Pass 010](../frontend/010_library.scm) | 名前空間公開設定・`rename` 対応 |
| **5.6** | ライブラリ内包宣言 | `(include-library-declarations <string1> ...)` | **◎** | [Pass 010](../frontend/010_library.scm) | ライブラリ宣言節の外部ファイル分割取り込み・再帰展開完全対応 ([Issue #706](../../docs/issues/closed/706-implement-r7rs-include-library-declarations-and-srfi-193-command-line.md)) |

---

### 1.3 標準手続き・データ型 (Section 6: Standard Procedures)

#### 6.1 等価性述語 (Equivalence Predicates)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.1** | `eq?` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | ポインタ同一性および即値タグの一致判定 |
| **6.1** | `eqv?` | **◎** | [ulisp/lib/equality.scm](../lib/equality.scm) | 数値・文字の同一性を含む R7RS 完全準拠判定 ([Issue #532](../../docs/issues/closed/532-implement-r7rs-eqv-and-standard-type-predicates.md)) |
| **6.1** | `equal?` | **◎** | [ulisp/lib/equality.scm](../lib/equality.scm) | ペア・ベクタ・文字列・バイトベクタの再帰的同値比較 |

#### 6.2 数値演算 (Numbers: 62-bit Tagged Fixnum Architecture)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.2.6** | `number?`, `integer?`, `exact?`, `exact-integer?` | **◎** | [ulisp/lib/predicates.scm](../lib/predicates.scm) | 最下位 2-bit タグ (`00b`) による Fixnum 判定 (`(val & 3) == 0`) |
| **6.2.6** | `complex?` | **◎** | [ulisp/lib/predicates.scm](../lib/predicates.scm) | Fixnum・`<ratnum>`・`<flonum>`・`<compnum>` 全数値塔に対する複素数判定完全準拠 ([Issue #714](../../docs/issues/closed/714-implement-r7rs-scheme-complex-arithmetic-library.md)) |
| **6.2.6** | `real?` | **◎** | [ulisp/lib/predicates.scm](../lib/predicates.scm) | Fixnum・正確有理数 (`<ratnum>`)・浮動小数点数 (`<flonum>`)・虚部ゼロ複素数に対する実数判定完全準拠 ([Issue #712](../../docs/issues/closed/712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates.md)) |
| **6.2.6** | `rational?` | **◎** | [ulisp/lib/predicates.scm](../lib/predicates.scm) | Fixnum・正確有理数 (`<ratnum>`)・有限浮動小数点数に対する有理数判定完全準拠 ([Issue #711](../../docs/issues/closed/711-implement-r7rs-exact-rationals-rounding-and-rationalize.md)) |
| **6.2.6** | `inexact?` | **◎** | [ulisp/lib/predicates.scm](../lib/predicates.scm) | `<flonum>` および不正確成分を持つ `<compnum>` に対する不正確性判定完全準拠 ([Issue #712](../../docs/issues/closed/712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates.md)) |
| **6.2.6** | `finite?` | **◎** | [ulisp/lib/predicates.scm](../lib/predicates.scm) | 有限数値判定 (`+inf.0`, `-inf.0`, `+nan.0` を `#f` として識別) ([Issue #712](../../docs/issues/closed/712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates.md)) |
| **6.2.6** | `infinite?`, `nan?` | **◎** | [ulisp/lib/predicates.scm](../lib/predicates.scm) | IEEE 754 無限大 (`+inf.0` / `-inf.0`) および非数 (`+nan.0`) 判定述語 ([Issue #712](../../docs/issues/closed/712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates.md)) |
| **6.2.6** | `zero?`, `positive?`, `negative?` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 符号・ゼロ判定プリミティブ |
| **6.2.6** | `odd?`, `even?` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | LSB ビット判定 |
| **6.2.6** | `+`, `-`, `*` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm)<br>[Pass 130](../lir/130_lir.scm) | 62-bit 加減乗算、定数畳み込み、x86/C バックエンド直結（加減算はタグシフト解除不要） |
| **6.2.6** | `/`, `quotient`, `modulo` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm)<br>[ulisp/lib/math.scm](../lib/math.scm) | 整数除算・床除算剰余、ゼロ除算トラップ保護。`modulo` は R7RS 準拠の `floor-remainder` として完全動作 ([Issue #610](../../docs/issues/610-implement-r7rs-base-core-procedures.md)) |
| **6.2.6** | `=`, `<`, `>`, `<=`, `>=` | **◎** | [Pass 130](../lir/130_lir.scm) | 整数比較、分岐融合 (Branch Fusion) 最適化 ([Issue #545](../../docs/issues/closed/545-implement-condition-branch-flag-fusion.md)) |
| **6.2.6** | `max`, `min` | **◎** | [ulisp/lib/math.scm](../lib/math.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 1引数以上可変長引数対応、インライン二項連鎖脱糖 (`max-2`/`min-2`)、case-lambda 第一級手続き ([Issue #653](../../docs/issues/closed/653-implement-r7rs-max-min-variadic-arguments.md)) |
| **6.2.6** | `abs` | **◎** | [compiler/helpers.scm](../compiler/helpers.scm)<br>[ulisp/lib/math.scm](../lib/math.scm) | 絶対値計算プリミティブ |
| **6.2.6** | `floor/`, `floor-quotient`, `floor-remainder` | **◎** | [ulisp/lib/math.scm](../lib/math.scm) | 床除算・剰余ペア (多値および単値) ([Issue #610](../../docs/issues/610-implement-r7rs-base-core-procedures.md)) |
| **6.2.6** | `truncate/`, `truncate-quotient`, `truncate-remainder` | **◎** | [ulisp/lib/math.scm](../lib/math.scm) | 切り捨て除算・剰余ペア (多値および単値) ([Issue #610](../../docs/issues/610-implement-r7rs-base-core-procedures.md)) |
| **6.2.6** | `floor`, `ceiling`, `truncate`, `round` | **◎** | [ulisp/lib/math.scm](../lib/math.scm) | 整数・有理数 (`<ratnum>`)・浮動小数点数に対する床・天井・ゼロ方向切り捨て・偶数丸め (round-to-even) 完全準拠 ([Issue #711](../../docs/issues/closed/711-implement-r7rs-exact-rationals-rounding-and-rationalize.md)) |
| **6.2.6** | `rationalize` | **◎** | [ulisp/lib/math.scm](../lib/math.scm) | 連分数展開 / Stern-Brocot 木探索による許容誤差 `|y|` 内の最簡有理数算出 ([Issue #711](../../docs/issues/closed/711-implement-r7rs-exact-rationals-rounding-and-rationalize.md)) |
| **6.2.6** | `numerator`, `denominator` | **◎** | [ulisp/lib/math.scm](../lib/math.scm) | GCD 既約正規化・正分母不変条件 (`d > 0`) に基づく分子・分母抽出 ([Issue #711](../../docs/issues/closed/711-implement-r7rs-exact-rationals-rounding-and-rationalize.md)) |
| **6.2.6** | `remainder`, `gcd`, `lcm`, `square`, `expt` | **◎** | [ulisp/lib/math.scm](../lib/math.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 切り捨て剰余、ユークリッド互除法 (可変長引数は `gcd-2`/`lcm-2` 左畳み込みへ脱糖)、繰り返し二乗法 O(log n) ([Issue #558](../../docs/issues/closed/558-implement-r7rs-elementary-integer-math-procedures.md)) |
| **6.2.6** | `exact-integer-sqrt` | **◎** | [ulisp/lib/math.scm](../lib/math.scm) | 平方根整数部と剰余の多値返却 (二分探索法) ([Issue #610](../../docs/issues/610-implement-r7rs-base-core-procedures.md)) |
| **6.2.6** | `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `exp`, `log`, `sqrt` | **◎** | [ulisp/lib/math.scm](../lib/math.scm)<br>[ulisp/lib/scheme/inexact.sld](../lib/scheme/inexact.sld) | 純粋 Scheme 範囲縮小・半角変換・Taylor/artanh 級数・完全平方正確判定による超越関数および平方根完全実装 ([Issue #713](../../docs/issues/closed/713-implement-r7rs-scheme-inexact-transcendental-math-library.md)) |
| **6.2.6** | `make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle` | **◎** | [ulisp/lib/math.scm](../lib/math.scm)<br>[ulisp/lib/scheme/complex.sld](../lib/scheme/complex.sld) | 直交座標・極座標複素数構築（虚部ゼロ時の実数自動降格）、実部・虚部抽出、絶対値 (`magnitude`)・偏角 (`angle`) および複素数四則演算完全準拠 ([Issue #714](../../docs/issues/closed/714-implement-r7rs-scheme-complex-arithmetic-library.md)) |
| **6.2.6** | `exact`, `inexact` | **◎** | [ulisp/lib/math.scm](../lib/math.scm) | 正確数 (Fixnum / `<ratnum>`) と不正確数 (`<flonum>`) 間の相互変換および R5RS エイリアス (`exact->inexact`, `inexact->exact`) 完全準拠 ([Issue #712](../../docs/issues/closed/712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates.md)) |
| **6.2.6** | `number->string` | **◎** | [ulisp/lib/string.scm](../lib/string.scm) | 基数指定 (2, 8, 10, 16) および Fixnum・有理数 (`p/q`)・浮動小数点数・複素数 (`a+bi`) の完全文字列変換 ([Issue #715](../../docs/issues/closed/715-implement-r7rs-numeric-tower-reader-printer-and-radix-formatting.md)) |
| **6.2.6** | `string->number` | **◎** | [ulisp/lib/reader.scm](../lib/reader.scm) | 基数 (2, 8, 10, 16)、プレフィックス (`#b`, `#o`, `#d`, `#x`, `#e`, `#i`)、分数 (`p/q`)・小数・指数・`+inf.0`/`-inf.0`/`+nan.0`・複素数 (`a+bi`, `r@θ`) 完全対応 ([Issue #652](../../docs/issues/closed/652-implement-r7rs-string-to-number-radix-support.md), [Issue #715](../../docs/issues/closed/715-implement-r7rs-numeric-tower-reader-printer-and-radix-formatting.md)) |

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
| **6.4** | `cons`, `car`, `cdr` | **◎** | [Pass 060](../frontend/060_lvn.scm)<br>[Pass 130](../lir/130_lir.scm) | ペア生成・要素取得、LVN / 純粋アクセサ最適化 |
| **6.4** | `set-car!`, `set-cdr!` | **◎** | [ulisp/lib/gc.scm](../lib/gc.scm) | 破壊的代入、世代別 GC ライトバリア・リメンバーセット記録 |
| **6.4** | `caar`, `cadr`, `cdar`, `cddr` | **◎** | [Pass 030](../frontend/030_desugar.scm) | `(scheme base)` 標準 2 階層合成アクセサ |
| **6.4 / cxr** | `caaar` 〜 `cddddr` (全 24 種) | **◎** | [ulisp/lib/scheme/cxr.sld](../lib/scheme/cxr.sld) | `(scheme cxr)` 規定の全 24 種合成ペアアクセサ (`caaar`, `caadr`, `cadar`, `caddr`, `cdaar`, `cdadr`, `cddar`, `cdddr`, `caaaar`, `caaadr`, `caadar`, `caaddr`, `cadaar`, `cadadr`, `caddar`, `cadddr`, `cdaaar`, `cdaadr`, `cdadar`, `cdaddr`, `cddaar`, `cddadr`, `cddar`, `cdddar`, `cddddr`) 完全完備 |
| **6.4** | `list?`, `list`, `length`, `reverse`, `append` | **◎** | [ulisp/lib/list.scm](../lib/list.scm)<br>[ulisp/lib/predicates.scm](../lib/predicates.scm) | 基本リスト操作 (length, reverse, append 完備) |
| **6.4** | `memq`, `memv`, `member` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 要素探索 |
| **6.4** | `assq`, `assv`, `assoc` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 連想リストキー探索 |
| **6.4** | `make-list`, `list-copy` | **◎** | [ulisp/lib/list.scm](../lib/list.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 浅いスパイン複製・充填生成 ([Issue #551](../../docs/issues/closed/551-expand-r7rs-standard-library-procedures.md)) |
| **6.4** | `list-tail`, `list-ref`, `list-set!` | **◎** | [ulisp/lib/list.scm](../lib/list.scm) | リスト末尾参照・インデックス取得・破壊的更新 ([Issue #555](../../docs/issues/closed/555-implement-r7rs-list-accessors-list-tail-ref-set.md)) |

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
| **6.6** | `char<?`, `char>?`, `char<=?`, `char>=?` | **◎** | [ulisp/lib/equality.scm](../lib/equality.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 複数引数対応文字順序比較述語 ([Issue #556](../../docs/issues/closed/556-implement-r7rs-character-comparison-predicates.md)) |
| **6.6** | `char-ci=?`, `char-ci<?`, `char-ci>?`, `char-ci<=?`, `char-ci>=?` | **◎** | [ulisp/lib/char.scm](../lib/char.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 大文字小文字同一視文字比較 (ASCII Case-folding / Pass 030 連鎖比較脱糖完全準拠) ([Issue #612](../../docs/issues/612-implement-r7rs-char-ascii-predicates-and-conversions.md)) |
| **6.6** | `char-alphabetic?`, `char-numeric?`, `char-whitespace?` | **◎** | [ulisp/lib/char.scm](../lib/char.scm) | 文字種判定述語 (ASCII 英字・数字・制御改行空白対応) ([Issue #612](../../docs/issues/612-implement-r7rs-char-ascii-predicates-and-conversions.md)) |
| **6.6** | `char-upper-case?`, `char-lower-case?` | **◎** | [ulisp/lib/char.scm](../lib/char.scm) | 大小文字判定述語 ([Issue #612](../../docs/issues/612-implement-r7rs-char-ascii-predicates-and-conversions.md)) |
| **6.6** | `digit-value` | **◎** | [ulisp/lib/char.scm](../lib/char.scm) | 数字文字の 10 進数値取得 (0-9、非数字は `#f`) ([Issue #612](../../docs/issues/612-implement-r7rs-char-ascii-predicates-and-conversions.md)) |
| **6.6** | `char-upcase`, `char-downcase`, `char-foldcase` | **◎** | [ulisp/lib/char.scm](../lib/char.scm) | 大小文字変換・ASCII 単純ケースフォールディング ([Issue #612](../../docs/issues/612-implement-r7rs-char-ascii-predicates-and-conversions.md)) |

#### 6.7 文字列 (Strings)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.7** | `string?`, `make-string`, `string-length` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | ヒープ文字列アロケーション・長さ取得 |
| **6.7** | `string-ref`, `string-set!` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | インデックスアクセスおよびインプレース更新 |
| **6.7** | `string=?` | **◎** | [ulisp/lib/string.scm](../lib/string.scm) | 文字列内容比較 |
| **6.7** | `substring`, `string-append` | **◎** | [Pass 030](../frontend/030_desugar.scm)<br>[ulisp/lib/string.scm](../lib/string.scm) | スライシング・2分木分割結合脱糖 |
| **6.7** | `string-copy`, `string-copy!`, `string-fill!`, `string-map`, `string-for-each` | **◎** | [ulisp/lib/string.scm](../lib/string.scm)<br>[Pass 030](../frontend/030_desugar.scm) | オーバーラップ安全コピー・充填・反復マッピング ([Issue #551](../../docs/issues/closed/551-expand-r7rs-standard-library-procedures.md)) |
| **6.7** | `string<?`, `string>?`, `string<=?`, `string>=?` | **◎** | [ulisp/lib/string.scm](../lib/string.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 複数引数対応辞書式順序比較述語 ([Issue #557](../../docs/issues/closed/557-implement-r7rs-string-vector-list-conversions-and-string-ordering.md)) |
| **6.7** | `string->list`, `list->string` | **◎** | [ulisp/lib/string.scm](../lib/string.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 文字列・リスト相互変換 (スライス対応) ([Issue #557](../../docs/issues/closed/557-implement-r7rs-string-vector-list-conversions-and-string-ordering.md)) |
| **6.7** | `string` | **◎** | [ulisp/lib/string.scm](../lib/string.scm)<br>[Pass 026](../frontend/026_desugar_constructors.scm) | 可変長引数文字並びからの文字列構築 (Pass 026 脱糖およびランタイム第一級関数) ([Issue #610](../../docs/issues/610-implement-r7rs-base-core-procedures.md)) |
| **6.7** | `string-ci=?`, `string-ci<?`, `string-ci>?`, `string-ci<=?`, `string-ci>=?` | **◎** | [ulisp/lib/string.scm](../lib/string.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 大文字小文字同一視辞書式順序比較 (Pass 030 連鎖比較脱糖対応) ([Issue #612](../../docs/issues/612-implement-r7rs-char-ascii-predicates-and-conversions.md)) |
| **6.7** | `string-upcase`, `string-downcase`, `string-foldcase` | **◎** | [ulisp/lib/string.scm](../lib/string.scm) | 文字列大小文字変換およびケースフォールディング (`string-map` 連携) ([Issue #612](../../docs/issues/612-implement-r7rs-char-ascii-predicates-and-conversions.md)) |

#### 6.8 ベクタ (Vectors)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.8** | `vector?`, `make-vector`, `vector` | **◎** | [ulisp/lib/vector.scm](../lib/vector.scm) | 連続ヒープベクタ型 ([Issue #536](../../docs/issues/closed/536-implement-complete-r7rs-vectors-and-indexing.md)) |
| **6.8** | `vector-length`, `vector-ref`, `vector-set!` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | O(1) ランダムアクセス・更新 |
| **6.8** | `vector-copy`, `vector-copy!`, `vector-append`, `vector-fill!` | **◎** | [ulisp/lib/vector.scm](../lib/vector.scm)<br>[Pass 030](../frontend/030_desugar.scm) | スライス複製・破壊的転送・充填 |
| **6.8** | `vector->list`, `list->vector` | **◎** | [ulisp/lib/vector.scm](../lib/vector.scm)<br>[Pass 030](../frontend/030_desugar.scm) | リスト・ベクタ相互変換 |
| **6.8** | `vector-map`, `vector-for-each` | **◎** | [ulisp/lib/vector.scm](../lib/vector.scm) | ベクタ要素マッピング・走査 |
| **6.8** | `vector->string`, `string->vector` | **◎** | [ulisp/lib/vector.scm](../lib/vector.scm)<br>[Pass 030](../frontend/030_desugar.scm) | 文字列・ベクタ直接相互変換 (スライス対応) ([Issue #557](../../docs/issues/closed/557-implement-r7rs-string-vector-list-conversions-and-string-ordering.md)) |

#### 6.9 バイトベクタ (Bytevectors)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.9** | `bytevector?`, `make-bytevector`, `bytevector` | **◎** | [ulisp/lib/bytevector.scm](../lib/bytevector.scm) | 8-bit 生バイト配列型 ([Issue #535](../../docs/issues/closed/535-implement-r7rs-bytevectors-for-binary-security.md)) |
| **6.9** | `bytevector-length`, `bytevector-u8-ref`, `bytevector-u8-set!` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | バイト単位の読み書き |
| **6.9** | `bytevector-copy`, `bytevector-copy!`, `bytevector-append`, `bytevector=?`| **◎** | [ulisp/lib/bytevector.scm](../lib/bytevector.scm)<br>[Pass 030](../frontend/030_desugar.scm) | メモリブロック高速コピー・比較 |
| **6.9** | `utf8->string`, `string->utf8` | **◎** | [ulisp/lib/bytevector.scm](../lib/bytevector.scm)<br>[Pass 030](../frontend/030_desugar.scm) | UTF-8 エンコード / デコード変換 |

#### 6.10 制御機能・継続・多値 (Control Features)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.10** | `procedure?` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 手続き型タグ判定 |
| **6.10** | `apply` | **◎** | [Pass 110](../frontend/110_closure_convert.scm)<br>[Pass 130](../lir/130_lir.scm) | クロージャへの可変長引数アンパック呼び出し |
| **6.10** | `call-with-current-continuation`, `call/cc` | **◎** | [spec_continuations_and_unwind.md](spec_continuations_and_unwind.md) | スタックセグメントコピー方式ファーストクラス継続 ([Issue #540](../../docs/issues/closed/540-implement-full-first-class-call-with-current-continuation-call-cc.md)) |
| **6.10** | `dynamic-wind` | **◎** | [ulisp/lib/continuation.scm](../lib/continuation.scm) | LCA (Lowest Common Ancestor) による unwind/rewind 遷移 |
| **6.10** | `values`, `call-with-values` | **◎** | [ulisp/lib/values.scm](../lib/values.scm) | ゼロアロケーション多値返却・受け渡し ABI ([Issue #538](../../docs/issues/closed/538-implement-r7rs-multiple-values-call-with-values.md)) |
| **6.10** | `map`, `for-each` (複数引数リスト版) | **◎** | [ulisp/lib/list.scm](../lib/list.scm) | 単一リスト・2リスト高速走査および任意複数リスト引数対応 (最短終了) ([Issue #610](../../docs/issues/610-implement-r7rs-base-core-procedures.md)) |

#### 6.11 例外機構 (Exceptions)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.11** | `with-exception-handler` | **◎** | [ulisp/lib/exception.scm](../lib/exception.scm) | 動的例外ハンドラ登録 ([Issue #531](../../docs/issues/closed/531-implement-lightweight-exception-handling-guard-raise.md)) |
| **6.11** | `raise`, `raise-continuable` | **◎** | [ulisp/lib/exception.scm](../lib/exception.scm) | 脱出型・復帰型例外送出 |
| **6.11** | `error` | **◎** | [Pass 030](../frontend/030_desugar.scm) | エラーオブジェクト生成・送出マクロ |
| **6.11** | `error-object?`, `error-object-message`, `error-object-irritants` | **◎** | [ulisp/lib/exception.scm](../lib/exception.scm) | エラー情報抽出アクセサ |
| **6.11** | `read-error?`, `file-error?` | **◎** | [ulisp/lib/exception.scm](../lib/exception.scm) | エラーカテゴリ型判定 |

#### 6.12 環境と動的評価 (Environments and Evaluation)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.12** | `environment` | **◎** | [ulisp/lib/eval.scm](../lib/eval.scm) | R7RS 第一級環境指定子。`(scheme base)` 等のインポート指定子および `only`, `except`, `prefix`, `rename` 修飾子に対応 ([Issue #716](../../docs/issues/closed/716-implement-r7rs-environment-specifiers-and-library-import-environments.md)) |
| **6.12** | `eval` | **◎** | [ulisp/lib/eval.scm](../lib/eval.scm) | R7RS 準拠オンデマンド埋め込み型メタ循環評価器。環境指定子・動的クロージャ・多値・例外・末尾再帰に完全対応 ([Issue #717](../../docs/issues/closed/717-implement-r7rs-scheme-eval-embedded-metacircular-evaluator.md)) |
| **6.12** | `scheme-report-environment`, `null-environment`, `interaction-environment` | **◎** | [ulisp/lib/eval.scm](../lib/eval.scm) | R5RS/R7RS 互換の環境指定子および対話型可変グローバル環境 ([Issue #716](../../docs/issues/closed/716-implement-r7rs-environment-specifiers-and-library-import-environments.md)) |

#### 6.13 入出力とポート (Input and Output)

##### 6.13.1 ポート (Ports)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.13.1** | `call-with-port` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | ポートスコープ保護・自動クローズ実行 |
| **6.13.1** | `port?`, `input-port?`, `output-port?` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | ポート型述語 ([Issue #537](../../docs/issues/closed/537-implement-r7rs-parameters-and-parameterize.md)) |
| **6.13.1** | `textual-port?`, `binary-port?` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | テキスト/バイナリ識別述語 |
| **6.13.1** | `port-open?` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | ポート開放状態判定述語 |
| **6.13.1** | `input-port-open?`, `output-port-open?` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | 入力ポート / 出力ポートの個別開放状態判定述語 ([Issue #705](../../docs/issues/closed/705-implement-r7rs-base-remaining-procedures-and-features.md)) |
| **6.13.1** | `close-port`, `close-input-port`, `close-output-port` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | ポートクローズ |
| **6.13.1** | `current-input-port`, `current-output-port`, `current-error-port` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | 標準入力 (`fd 0`)・標準出力 (`fd 1`)・標準エラー出力 (`fd 2`) |
| **6.13.1** | `open-input-file`, `open-binary-input-file` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | POSIX `open` システムコールラッパー (読み取り) ([Issue #651](../../docs/issues/closed/651-implement-r7rs-scheme-file-high-level-ports-and-file-ops.md)) |
| **6.13.1** | `open-output-file`, `open-binary-output-file` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | POSIX `open` システムコールラッパー (4096B バッファ付き書き込み) ([Issue #651](../../docs/issues/closed/651-implement-r7rs-scheme-file-high-level-ports-and-file-ops.md)) |
| **6.13.1** | `call-with-input-file`, `call-with-output-file` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | ファイルオープン・手続き実行・例外安全自動クローズ ([Issue #651](../../docs/issues/closed/651-implement-r7rs-scheme-file-high-level-ports-and-file-ops.md)) |
| **6.13.1** | `with-input-from-file`, `with-output-to-file` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | カレントポート動的パラメータ一時付け替え実行 ([Issue #651](../../docs/issues/closed/651-implement-r7rs-scheme-file-high-level-ports-and-file-ops.md)) |
| **6.13.1** | `open-input-string`, `open-output-string`, `get-output-string` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | メモリ上文字列ポート ([Issue #534](../../docs/issues/closed/534-implement-r7rs-string-ports.md)) |
| **6.13.1** | `open-input-bytevector`, `open-output-bytevector`, `get-output-bytevector` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | メモリ上バイナリバイトベクタポート完全実装 ([Issue #660](../../docs/issues/closed/660-implement-r7rs-bytevector-ports-and-ready-predicates.md)) |

##### 6.13.2 入力手続き (Input Procedures)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.13.2** | `read` | **◎** | [ulisp/lib/reader.scm](../lib/reader.scm) | 自前完全再帰下降 S 式パーサ |
| **6.13.2** | `read-char`, `peek-char` | **◎** | [ulisp/lib/port.scm](../lib/port.scm)<br>[ulisp/lib/posix.scm](../lib/posix.scm) | 1文字先読み・消費 |
| **6.13.2** | `read-line` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | 行末改行までの 1 行文字列読み取り |
| **6.13.2** | `char-ready?` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | R7RS §6.13.2 準拠文字入力準備状態判定 ([Issue #660](../../docs/issues/closed/660-implement-r7rs-bytevector-ports-and-ready-predicates.md)) |
| **6.13.2** | `read-string` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | 指定文字数の文字列一括読み取り |
| **6.13.2** | `read-u8`, `peek-u8` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | 1 バイト先読み・消費 |
| **6.13.2** | `u8-ready?` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | R7RS §6.13.2 準拠バイト入力準備状態判定 ([Issue #660](../../docs/issues/closed/660-implement-r7rs-bytevector-ports-and-ready-predicates.md)) |
| **6.13.2** | `read-bytevector`, `read-bytevector!` | **◎** | [ulisp/lib/bytevector.scm](../lib/bytevector.scm) | バイナリデータの一括・バッファ直接読み出し |
| **6.13.2** | `eof-object?`, `eof-object` | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | EOF 即値タグ判定 (`0x4F`) |

##### 6.13.3 出力手続き (Output Procedures)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.13.3** | `write`, `display` | **◎** | [ulisp/lib/printer.scm](../lib/printer.scm) | S 式シリアライザおよび文字列表現出力（循環データ安全・datum label 対応、第一級手続き） |
| **6.13.3** | `write-char`, `write-string`, `newline` | **◎** | [ulisp/lib/port.scm](../lib/port.scm)<br>[ulisp/lib/posix.scm](../lib/posix.scm)<br>[ulisp/lib/printer.scm](../lib/printer.scm) | バッファ付きテキスト出力および改行手続き |
| **6.13.3** | `write-u8` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | 1 バイト生データ出力 |
| **6.13.3** | `write-bytevector` | **◎** | [ulisp/lib/bytevector.scm](../lib/bytevector.scm) | バイトベクタ一括出力 |
| **6.13.3** | `flush-output-port` | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | 出力バッファ強制フラッシュ |
| **6.13.3** | `write-shared`, `write-simple` | **◎** | [ulisp/lib/printer.scm](../lib/printer.scm) | 共有・循環参照表記（`#1=` / `#1#`）出力、木構造高速出力、第一級手続き ([Issue #656](../../docs/issues/closed/656-implement-r7rs-write-simple-and-write-shared.md)) |

#### 6.14 システムインターフェース (System Interface)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **6.14** | `exit`, `emergency-exit` | **◎** | [ulisp/lib/posix.scm](../lib/posix.scm) | POSIX `sys-exit` 終了コード返却 |
| **6.14** | `load` | **◎** | [ulisp/lib/eval.scm](../lib/eval.scm) | ソースファイル動的読み込み・評価手続き `(load <filename> [<environment-specifier>])` 完全実装 ([Issue #718](../../docs/issues/closed/718-implement-r7rs-scheme-load-repl-and-r5rs-full-compliance.md)) |
| **6.14** | `file-exists?`, `delete-file` | **◎** | [ulisp/lib/posix.scm](../lib/posix.scm) | POSIX `sys-access`(21) および `sys-unlink`(87) システムコール連携 ([Issue #651](../../docs/issues/closed/651-implement-r7rs-scheme-file-high-level-ports-and-file-ops.md)) |
| **6.14** | `command-line` | **◎** | [ulisp/lib/posix.scm](../lib/posix.scm)<br>[ulisp/lib/srfi/193.sld](../lib/srfi/193.sld) | POSIX `argc`/`argv` 直接取得および SRFI 193 パラメータ更新完全対応 ([Issue #706](../../docs/issues/closed/706-implement-r7rs-include-library-declarations-and-srfi-193-command-line.md)) |
| **6.14** | `get-environment-variable`, `get-environment-variables` | **◎** | [ulisp/lib/posix.scm](../lib/posix.scm) | POSIX `environ` 走査・連想リスト構築 ([Issue #611](../../docs/issues/closed/611-implement-r7rs-process-context-environment-variables.md)) |
| **6.14** | `current-second`, `current-jiffy`, `jiffies-per-second` | **◎** | [ulisp/lib/scheme/time.sld](../lib/scheme/time.sld)<br>[ulisp/lib/posix.scm](../lib/posix.scm) | POSIX clock_gettime (REALTIME / MONOTONIC) 直結ナノ秒精度時間取得・1M jiffies/sec ([Issue #661](../../docs/issues/closed/661-implement-r7rs-scheme-time-procedures.md)) |
| **6.14** | `features` | **◎** | [ulisp/lib/posix.scm](../lib/posix.scm) | `cond-expand` で有効な機能識別子シンボルリスト返却手続き ([Issue #705](../../docs/issues/closed/705-implement-r7rs-base-remaining-procedures-and-features.md)) |

---

### 1.4 R7RS-small 標準 16 ライブラリ別網羅表

| ライブラリ識別子 | 主な責務・内容 | サポート率 | 内部実装ファイル | 主なサポート機能 / 未サポート理由 |
| :--- | :--- | :--- | :--- | :--- |
| `(scheme base)` | コア構文、算術、リスト、ベクタ、継続、多値、ポート | **◎ 100%** | [ulisp/lib/scheme/base.sld](../lib/scheme/base.sld)<br>([ulisp/lib/*.scm](../lib/)) | 構文・`call/cc`・多値・ベクタ・GC・数値塔（整数・有理数・浮動小数点数・複素数）・多引数 map/for-each・`input/output-port-open?`・`features` 完備 ([Issue #562](../../docs/issues/562-implement-r7rs-standard-library-definitions-sld.md), [Issue #610](../../docs/issues/610-implement-r7rs-base-core-procedures.md), [Issue #705](../../docs/issues/closed/705-implement-r7rs-base-remaining-procedures-and-features.md), [Issue #711](../../docs/issues/closed/711-implement-r7rs-exact-rationals-rounding-and-rationalize.md)–[Issue #715](../../docs/issues/closed/715-implement-r7rs-numeric-tower-reader-printer-and-radix-formatting.md)) |
| `(scheme case-lambda)` | 可変個引数パターンマッチング | **◎ 100%** | [ulisp/lib/scheme/case-lambda.sld](../lib/scheme/case-lambda.sld)<br>[Pass 028](../frontend/028_desugar_bindings.scm) | `case-lambda` 構文の完全脱糖サポート（固定引数・可変個レスト引数・動的引数数ディスパッチ・引数不一致時例外 `raise`） ([Issue #609](../../docs/issues/closed/609-implement-r7rs-case-lambda-syntax.md)) |
| `(scheme char)` | 大文字小文字変換・分類・同一視比較 | **◎ 100% (ASCII)** | [ulisp/lib/scheme/char.sld](../lib/scheme/char.sld)<br>([ulisp/lib/char.scm](../lib/char.scm)<br>[ulisp/lib/string.scm](../lib/string.scm)) | 全 22 識別子完備（文字種判定 6 種、大小文字変換・フォールディング 3 種、`char-ci*` 5 種、文字列大小変換 3 種、`string-ci*` 5 種、Pass 030 連鎖比較脱糖対応） ([Issue #612](../../docs/issues/612-implement-r7rs-char-ascii-predicates-and-conversions.md)) |
| `(scheme complex)` | 複素数算術 | **◎ 100%** | [ulisp/lib/scheme/complex.sld](../lib/scheme/complex.sld)<br>([ulisp/lib/math.scm](../lib/math.scm)) | 全 6 識別子完備 (`make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle`) および複素数四則演算統合 ([Issue #714](../../docs/issues/closed/714-implement-r7rs-scheme-complex-arithmetic-library.md)) |
| `(scheme cxr)` | `caaa...r` 〜 `cddddr` (全 24 種) | **◎ 100%** | [ulisp/lib/scheme/cxr.sld](../lib/scheme/cxr.sld) | R7RS 規定の全 24 種合成ペアアクセサをライブラリ定義内で完備 |
| `(scheme eval)` | 動的評価 (`eval`, `environment`) | **◎ 100%** | [ulisp/lib/scheme/eval.sld](../lib/scheme/eval.sld)<br>([ulisp/lib/eval.scm](../lib/eval.scm)) | 全 2 識別子完備 (`eval`, `environment`) ([Issue #716](../../docs/issues/closed/716-implement-r7rs-environment-specifiers-and-library-import-environments.md), [Issue #717](../../docs/issues/closed/717-implement-r7rs-scheme-eval-embedded-metacircular-evaluator.md)) |
| `(scheme file)` | ファイル入出力 | **◎ 100%** | [ulisp/lib/scheme/file.sld](../lib/scheme/file.sld)<br>([ulisp/lib/posix.scm](../lib/posix.scm)<br>[ulisp/lib/port.scm](../lib/port.scm)) | 上位ファイルポート・動的カレントポート切り替え・例外安全自動クローズ・システムファイル操作完備 ([Issue #651](../../docs/issues/closed/651-implement-r7rs-scheme-file-high-level-ports-and-file-ops.md)) |
| `(scheme inexact)` | 浮動小数点数・超越関数 | **◎ 100%** | [ulisp/lib/scheme/inexact.sld](../lib/scheme/inexact.sld)<br>([ulisp/lib/math.scm](../lib/math.scm)<br>[ulisp/lib/predicates.scm](../lib/predicates.scm)) | 全 12 識別子完備 (`acos`, `asin`, `atan`, `cos`, `sin`, `tan`, `exp`, `log`, `sqrt`, `finite?`, `infinite?`, `nan?`) ([Issue #712](../../docs/issues/closed/712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates.md), [Issue #713](../../docs/issues/closed/713-implement-r7rs-scheme-inexact-transcendental-math-library.md)) |
| `(scheme lazy)` | 遅延評価 (`delay`, `force`) | **◎ 100%** | [ulisp/lib/scheme/lazy.sld](../lib/scheme/lazy.sld)<br>([ulisp/lib/promise.scm](../lib/promise.scm)) | SRFI-45 準拠プロミス完備 (`delay`, `force`, `delay-force`, `make-promise`) ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| `(scheme load)` | スクリプト動的ロード | **◎ 100%** | [ulisp/lib/scheme/load.sld](../lib/scheme/load.sld)<br>([ulisp/lib/eval.scm](../lib/eval.scm)) | 全 1 識別子完備 (`load`) ([Issue #718](../../docs/issues/closed/718-implement-r7rs-scheme-load-repl-and-r5rs-full-compliance.md)) |
| `(scheme process-context)` | プロセス環境 (`exit`, `command-line`, `get-environment-variable`) | **◎ 100%** | [ulisp/lib/scheme/process-context.sld](../lib/scheme/process-context.sld)<br>([ulisp/lib/posix.scm](../lib/posix.scm)) | `exit`, `emergency-exit`, `command-line`, `get-environment-variable`, `get-environment-variables` 完備 ([Issue #611](../../docs/issues/closed/611-implement-r7rs-process-context-environment-variables.md)) |
| `(scheme r5rs)` | R5RS 互換仕様シンボル群 | **◎ 100%** | [ulisp/lib/scheme/r5rs.sld](../lib/scheme/r5rs.sld)<br>([ulisp/lib/eval.scm](../lib/eval.scm)) | R5RS 標準全シンボル（動的評価・ロード・環境指定子・数値塔相互変換含む）の互換エクスポート完備 ([Issue #718](../../docs/issues/closed/718-implement-r7rs-scheme-load-repl-and-r5rs-full-compliance.md)) |
| `(scheme read)` | S 式リーダー (`read`) | **◎ 100%** | [ulisp/lib/scheme/read.sld](../lib/scheme/read.sld)<br>([ulisp/lib/reader.scm](../lib/reader.scm)) | 自前完全再帰下降パーサ完備 |
| `(scheme repl)` | 対話型 REPL | **◎ 100%** | [ulisp/lib/scheme/repl.sld](../lib/scheme/repl.sld)<br>([ulisp/lib/eval.scm](../lib/eval.scm)) | 全 1 識別子完備 (`interaction-environment`) ([Issue #716](../../docs/issues/closed/716-implement-r7rs-environment-specifiers-and-library-import-environments.md), [Issue #718](../../docs/issues/closed/718-implement-r7rs-scheme-load-repl-and-r5rs-full-compliance.md)) |
| `(scheme time)` | 時間計測 (`current-second`, `current-jiffy`, `jiffies-per-second`) | **◎ 100%** | [ulisp/lib/scheme/time.sld](../lib/scheme/time.sld)<br>[ulisp/lib/posix.scm](../lib/posix.scm) | POSIX clock_gettime システムコール直結、R7RS-small (scheme time) 全 3 手続き完全実装 ([Issue #661](../../docs/issues/closed/661-implement-r7rs-scheme-time-procedures.md)) |
| `(scheme write)` | S 式ライター (`write`, `display`, `write-shared`, `write-simple`) | **◎ 100%** | [ulisp/lib/scheme/write.sld](../lib/scheme/write.sld)<br>([ulisp/lib/printer.scm](../lib/printer.scm)) | `write`, `display`, `write-shared`, `write-simple` 完備。SRFI 38 / R7RS datum label 循環・共有表記対応 ([Issue #656](../../docs/issues/closed/656-implement-r7rs-write-simple-and-write-shared.md)) |

---

## 2. R7RS-large 言語仕様準拠状況

Scheme Working Group 2 (WG2) が主導する **R7RS-large** は、Scheme コミュニティで広く利用されている SRFI 群を機能グループ別に段階的に標準化（エディションおよびドケット策定）する仕様体系である。

### 2.1 Red Edition (データ構造・アルゴリズム: Data Structures & Algorithms)

2016 年に凍結投票を経て正式策定された最初の R7RS-large 仕様であり、データ構造・アルゴリズム関連の **全 17 ライブラリ** から構成される（R7RS-small 全ライブラリを含む）。

| 仕様番号 / SRFI | ライブラリ識別子 | 名称・対象機能 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **SRFI 1** | `(scheme list)` | Lists (高機能リスト処理: `fold`, `unfold`, `filter`, `take`, `drop` 等) | **◎** | [ulisp/lib/list.scm](../lib/list.scm)<br>[ulisp/lib/srfi/1.sld](../lib/srfi/1.sld)<br>[ulisp/lib/scheme/list.sld](../lib/scheme/list.sld) | Constructors, Predicates, Selectors, Fold/Unfold, Searching/Filtering, Alist 操作を完全実装・TCO 最適化済 ([Issue #648](../../docs/issues/closed/648-implement-srfi-1-higher-order-list-procedures.md)) |
| **SRFI 14** | `(scheme charset)` | Character Sets (文字集合 Char-Set) | **◎** | [ulisp/lib/charset.scm](../lib/charset.scm)<br>[ulisp/lib/srfi/14.sld](../lib/srfi/14.sld)<br>[ulisp/lib/scheme/charset.sld](../lib/scheme/charset.sld) | R7RS-large Red Edition / SRFI 14 文字集合完全準拠。256-bit ビットマップ表現、O(1) 集合代数演算、カーソル・反復、全 17 標準文字集合定数完備 ([Issue #708](../../docs/issues/closed/708-implement-srfi-14-character-sets.md)) |
| **SRFI 41** | `(scheme stream)` | Streams (遅延評価ストリーム) | **◎** | [ulisp/lib/stream.scm](../lib/stream.scm)<br>[ulisp/lib/srfi/41.sld](../lib/srfi/41.sld)<br>[ulisp/lib/scheme/stream.sld](../lib/scheme/stream.sld) | R7RS-large Red Edition / SRFI 41 遅延ストリーム完全準拠。`stream-cons`, `stream-lambda`, `define-stream`, `stream-let`, `stream-of` 内包表記、無限ストリーム走査完備 ([Issue #703](../../docs/issues/closed/703-implement-srfi-41-streams.md)) |
| **SRFI 101** | `(scheme rlist)` | Purely Functional Random-Access Lists (純粋関数型ランダムアクセスリスト) | **×** | - | O(log n) アクセス・更新時間を持つ平衡木ベース不変リスト（未実装） |
| **SRFI 111** | `(scheme box)` | Boxes (単一要素可変セル: `box`, `box?`, `unbox`, `set-box!`) | **◎** | [ulisp/lib/box.scm](../lib/box.scm)<br>[ulisp/lib/srfi/111.sld](../lib/srfi/111.sld)<br>[ulisp/lib/scheme/box.sld](../lib/scheme/box.sld) | R7RS-large Red Edition / SRFI 111 ボックス完全準拠。専用可変セル型・述語・アクセサ・ミューテータ完備 ([Issue #663](../../docs/issues/closed/663-implement-srfi-111-boxes.md)) |
| **SRFI 113** | `(scheme set)` | Sets and Bags (集合・マルチセット) | **◎** | [ulisp/lib/set.scm](../lib/set.scm)<br>[ulisp/lib/srfi/113.sld](../lib/srfi/113.sld)<br>[ulisp/lib/scheme/set.sld](../lib/scheme/set.sld) | R7RS-large Red Edition / SRFI 113 集合・マルチセット完全準拠。比較器駆動 `<set>` / `<bag>`、集合代数演算（和・積・差・対称差）、多重度管理完備 ([Issue #702](../../docs/issues/closed/702-implement-srfi-113-sets-and-bags.md)) |
| **SRFI 116** | `(scheme ilist)` | Immutable Pairs and Lists (不変ペア・不変リスト) | **◎** | [ulisp/lib/ilist.scm](../lib/ilist.scm)<br>[ulisp/lib/srfi/116.sld](../lib/srfi/116.sld)<br>[ulisp/lib/scheme/ilist.sld](../lib/scheme/ilist.sld) | R7RS-large Red Edition / SRFI 116 不変ペア・不変リスト完全準拠。`ipair`, `ilist`, 全 28 `ic*r`, 高階畳み込み・写像・探索・木変換・比較器統合完備 ([Issue #710](../../docs/issues/closed/710-implement-srfi-116-immutable-lists-and-srfi-134-immutable-deques.md)) |
| **SRFI 117** | `(scheme list-queue)` | Queues based on Lists (リストベースキュー / tconc) | **◎** | [ulisp/lib/list-queue.scm](../lib/list-queue.scm)<br>[ulisp/lib/srfi/117.sld](../lib/srfi/117.sld)<br>[ulisp/lib/scheme/list-queue.sld](../lib/scheme/list-queue.sld) | R7RS-large Red Edition / SRFI 117 リストキュー完全準拠。O(1) 両端追加・先頭削除、unfold、連結、写像完備 ([Issue #707](../../docs/issues/closed/707-implement-srfi-117-list-queues-and-srfi-127-lazy-sequences.md)) |
| **SRFI 121** | `(scheme generator)` | Generators (基本ジェネレータ・イテレータ) | **◎** | [ulisp/lib/generator.scm](../lib/generator.scm)<br>[ulisp/lib/srfi/121.sld](../lib/srfi/121.sld)<br>[ulisp/lib/scheme/generator.sld](../lib/scheme/generator.sld) | R7RS-large Red Edition / SRFI 121 ジェネレータ完全準拠。`make-coroutine-generator`, コンストラクタ, コンビネータ (`gmap`, `gfilter`, `gcombine` 等), コンシューマ完備 ([Issue #704](../../docs/issues/closed/704-implement-srfi-158-generators-and-accumulators.md)) |
| **SRFI 124** | `(scheme ephemeron)` | Ephemerons (弱参照ペア・GC 協調) | **×** | - | キーの到達可能性に連動して値の回収を決定する弱参照。コピー GC 構造上未実装 |
| **SRFI 125** | `(scheme hash-table)` | Intermediate Hash Tables (ハッシュテーブル) | **◎** | [ulisp/lib/hashtable.scm](../lib/hashtable.scm)<br>[ulisp/lib/srfi/125.sld](../lib/srfi/125.sld)<br>[ulisp/lib/scheme/hash-table.sld](../lib/scheme/hash-table.sld) | R7RS-large / SRFI 125 互換ハッシュテーブル。24-bit 決定論的素数モジュラス、動的リハッシュ、多値 pop!、述語・アクセサ・反復・比較完備 ([Issue #649](../../docs/issues/closed/649-implement-r7rs-hash-table-api.md)) |
| **SRFI 127** | `(scheme lseq)` | Lazy Sequences (遅延リスト lseq) | **◎** | [ulisp/lib/lseq.scm](../lib/lseq.scm)<br>[ulisp/lib/srfi/127.sld](../lib/srfi/127.sld)<br>[ulisp/lib/scheme/lseq.sld](../lib/scheme/lseq.sld) | R7RS-large Red Edition / SRFI 127 遅延リスト完全準拠。`generator->lseq`, オンデマンド実体化・メモ化、写像・フィルタ・探索完備 ([Issue #707](../../docs/issues/closed/707-implement-srfi-117-list-queues-and-srfi-127-lazy-sequences.md)) |
| **SRFI 128** | `(scheme comparator)` | Comparators (比較器) | **◎** | [ulisp/lib/comparator.scm](../lib/comparator.scm)<br>[ulisp/lib/srfi/128.sld](../lib/srfi/128.sld)<br>[ulisp/lib/scheme/comparator.sld](../lib/scheme/comparator.sld) | R7RS-large Red Edition / SRFI 128 第一級比較器完全準拠。標準型比較器、複合比較器 (`pair`/`list`/`vector`)、`default-comparator`、`=?`/`<?`/`comparator-if<=>` 完備 ([Issue #701](../../docs/issues/closed/701-implement-srfi-128-comparators.md)) |
| **SRFI 132** | `(scheme sort)` | Sort Libraries (ソート・マージアルゴリズム) | **◎** | [ulisp/lib/sort.scm](../lib/sort.scm)<br>[ulisp/lib/srfi/132.sld](../lib/srfi/132.sld)<br>[ulisp/lib/scheme/sort.sld](../lib/scheme/sort.sld) | R7RS-large / SRFI 132 安定ソート・マージ完全準拠。`list-sort`, `list-sort!`, `vector-sort`, `vector-sort!`, `list-merge`, `vector-merge`, `list-sorted?`, `vector-sorted?` ([Issue #655](../../docs/issues/closed/655-implement-r7rs-list-and-vector-sort-procedures.md)) |
| **SRFI 133** | `(scheme vector)` | Vectors (高機能ベクタ操作) | **◎** (準拠) | [ulisp/lib/vector.scm](../lib/vector.scm)<br>[Pass 030](../frontend/030_desugar.scm) | SRFI 43 改善版ベクタ操作。`vector-copy`, `vector-copy!`, `vector-append`, `vector-fill!`, `vector-map`, `vector-for-each` 等を網羅 |
| **SRFI 134** | `(scheme ideque)` | Immutable Deques (不変両端キュー) | **◎** | [ulisp/lib/ideque.scm](../lib/ideque.scm)<br>[ulisp/lib/srfi/134.sld](../lib/srfi/134.sld)<br>[ulisp/lib/scheme/ideque.sld](../lib/scheme/ideque.sld) | R7RS-large Red Edition / SRFI 134 不変両端キュー完全準拠。両端追加・削除、スライス、unfold、写像・畳み込み・ジェネレータ変換完備 ([Issue #710](../../docs/issues/closed/710-implement-srfi-116-immutable-lists-and-srfi-134-immutable-deques.md)) |
| **SRFI 135** | `(scheme text)` | Immutable Texts (不変テキスト) | **×** | - | O(1) ランダムアクセス時間を持つ不変文字シーケンス型（未実装） |

---

### 2.2 Tangerine Edition (数値計算・低レベル・データ構造: Numerics & Low-level)

2019 年に正式策定された第 2 の R7RS-large 仕様であり、数値計算・ビット演算・低レベル操作・拡張データ構造に関する **全 10 ライブラリ** および **完全な数値塔 (Numeric Tower)** 要件を規定する。

| 仕様番号 / SRFI | ライブラリ識別子 | 名称・対象機能 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **SRFI 115** | `(scheme regex)` | Scheme Regular Expressions (正規表現 SRE) | **×** | - | S 式ベースの正規表現 (SRE: Scheme Regular Expressions) パーサおよびマッチングエンジン（未実装） |
| **SRFI 141** | `(scheme division)` | Integer Division (6 モードの整数除算) | **◎** | [ulisp/lib/math.scm](../lib/math.scm)<br>[ulisp/lib/srfi/141.sld](../lib/srfi/141.sld)<br>[ulisp/lib/scheme/division.sld](../lib/scheme/division.sld) | R7RS-large Tangerine Edition / SRFI 141 整数除算全 6 モード完備 (floor, truncate, ceiling, round, euclidean, centered) の除算・剰余・多値除算 ([Issue #662](../../docs/issues/closed/662-implement-srfi-141-integer-division.md)) |
| **SRFI 143** | `(scheme fixnum)` | Fixnums (Fixnum 専用高速演算: `fx+`, `fx-`, `fxadd1` 等) | **◎** | [Pass 090](../frontend/090_rtyper.scm) | `fxadd1`, `fxsub1` 等コンパイラ内部プリミティブおよび AOT アンボクシング対応 |
| **SRFI 144** | `(scheme flonum)` | Flonums (浮動小数点数演算) | **×** | - | 浮動小数点型非対応のため未実装 |
| **SRFI 146** | `(scheme mapping)`<br>`(scheme mapping hash)` | Mappings (不変マップ: 順序付き & ハッシュベース) | **◎** | [ulisp/lib/mapping.scm](../lib/mapping.scm)<br>[ulisp/lib/srfi/146.sld](../lib/srfi/146.sld)<br>[ulisp/lib/srfi/146/hash.sld](../lib/srfi/146/hash.sld)<br>[ulisp/lib/scheme/mapping.sld](../lib/scheme/mapping.sld)<br>[ulisp/lib/scheme/mapping/hash.sld](../lib/scheme/mapping/hash.sld) | R7RS-large Tangerine Edition / SRFI 146 不変マッピング完全準拠。順序付き不変辞書 (`mapping`) およびハッシュベース不変辞書 (`hashmap`) の生成・検索・関数型更新・分割結合・範囲検索・集合演算・比較器統合完備 ([Issue #709](../../docs/issues/closed/709-implement-srfi-146-immutable-mappings.md)) |
| **SRFI 151** | `(scheme bitwise)` | Bitwise Operations (ビット演算) | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | `bitwise-and`, `bitwise-ior`, `bitwise-arithmetic-shift` 等 62-bit Fixnum ビット演算サポート |
| **SRFI 158** | `(scheme generator)` | Generators and Accumulators (ジェネレータ・アキュムレータ) | **◎** | [ulisp/lib/generator.scm](../lib/generator.scm)<br>[ulisp/lib/srfi/158.sld](../lib/srfi/158.sld)<br>[ulisp/lib/scheme/generator.sld](../lib/scheme/generator.sld) | R7RS-large Tangerine Edition / SRFI 158 ジェネレータ・アキュムレータ完全準拠。SRFI 121 全機能に加え `gflatten`, `ggroup`, `gmerge`, `generator-map->list`, 各種 Accumulator 完備 ([Issue #704](../../docs/issues/closed/704-implement-srfi-158-generators-and-accumulators.md)) |
| **SRFI 159** | `(scheme show)` | Combinator Formatting (コンビネータ書式化出力) | **×** | - | モナディックなコンビネータ型テキスト・数値・カラムレイアウト書式化エンジン（未実装） |
| **SRFI 160** | `(scheme vector @)` | Homogeneous numeric vectors (u8, s8, u16 等の型付きベクタ) | **△** | [ulisp/lib/bytevector.scm](../lib/bytevector.scm) | `@` は `base, u8, s8, u16, s16, u32, s32, u64, s64, f32, f64, c64, c128`。ULisp では `u8` (バイトベクタ) を完全サポート。他の固定幅数値ベクタは未実装 |
| **R6RS / WG2** | `(scheme bytevector)` | R6RS Bytevector Operations (包括的バイトベクタ操作) | **×** | - | R6RS 互換の包括的単数形 `(scheme bytevector)` ライブラリ（エンディアン指定数値デコード等、未実装） |
| **Tangerine Tower** | - | R6RS 準拠完全数値塔 (Full Numeric Tower) | **×** | - | Tangerine Edition で義務付けられる任意長整数 (Bignums)、任意長有理数、不正確実数、複素数（ULisp はスタンドアロン AOT 向け 62-bit Fixnum 設計のため非サポート） |
| **SRFI 138** | - | Compiling Scheme Programs (コンパイル規約) | **◎** | [compiler/driver.scm](../compiler/driver.scm) | AOT 静的コンパイル・バッチ処理に完全適合 |
| **SRFI 179** | - | Nonempty Intervals and Arrays (多次元配列) | **×** | - | 任意次元の多次元配列・間隔演算ライブラリ（未実装） |

---

### 2.3 Yellow Docket (マクロ・構文拡張・メタプログラミング: Macros & Syntax)

R7RS-large Yellow Docket は、高度なマクロ展開器、構文制御、多値構文、およびメタプログラミング機能の標準化を担うドケットである。

| 仕様番号 / SRFI | 名称・対象機能 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **SRFI 8** | RECEIVE (多値受け取り構文: `receive`) | **◎** | [Pass 030](../frontend/030_desugar.scm) | `call-with-values` への単純マクロ脱糖で完全動作 |
| **SRFI 26** | Notation for Specializing Parameters (`cut`, `cute`) | **◎** | [Pass 020](../frontend/020_macro_expander.scm) | スロット部分適用・即時評価部分適用マクロ展開器で完全動作 |
| **SRFI 31** | Special form REC for recursive evaluation (`rec`) | **◎** | [Pass 030](../frontend/030_desugar.scm) | 自己再帰式束縛構文 (`(rec (f x) ...)` / `(rec name val)`)。名前付き `letrec` への脱糖で動作 |
| **SRFI 61** | A more general `cond` clause (一般化 cond ガード) | **◎** | [Pass 030](../frontend/030_desugar.scm) | 任意個の戻り値を受け取る `(=> guard-proc receiver)` 構文サポート |
| **SRFI 139** | Syntax Parameters (`define-syntax-parameter`, `syntax-parameterize`) | **×** | - | レキシカルに再束縛可能な構文パラメータ（未実装） |
| **SRFI 188** | Splicing `let-syntax` and `letrec-syntax` | **×** | - | 定義文脈で内部定義をスプライシング展開する局所マクロ構文（未実装） |
| **SRFI 210** | Procedures and syntax for multiple values | **×** | - | `list/mv`, `coalesce`, `with-values`, `case-receive` 等の多値拡張手続き・構文群（未実装） |
| **SRFI 212** | Identifier Aliasing (`alias`) | **×** | - | 識別子エイリアス束縛構文（未実装） |
| **SRFI 213** | Identifier Properties | **×** | - | 識別子プロパティ登録・参照メタ構文（未実装） |
| **SRFI 219** | Define higher-order lambda (`(define ((f x) y) ...)`) | **◎** | [Pass 028](../frontend/028_desugar_bindings.scm)<br>[Pass 030](../frontend/030_desugar.scm) | カリー化手続き定義の短縮記法。Pass 028/030 で完全脱糖サポート済 ([Issue #592](../../docs/issues/592-implement-r7rs-internal-definition-desugaring.md)) |
| **R6RS Syntax** | `syntax-case` & `syntax` | **×** | - | 低レベルパターン照合・手続き型衛生マクロシステム（現行 ULisp は `syntax-rules` 完備型） |

---

### 2.4 Orange / Hypnos Docket (拡張データ型・フォーマット・入出力: Advanced Data Types, Formatting & I/O)

R7RS-large の Orange Docket および Hypnos Docket で審議・策定が進められているポータブルな高度データ型・フォーマット・入出力仕様である。

| 仕様番号 / SRFI | 名称・対象機能 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **SRFI 48** | Intermediate Format Strings (中級フォーマット: `format`) | **×** | - | `~a`, `~s`, `~%`, `~d`, `~x`, `~f`, `~?` 等の中級書式指定子（未実装） |
| **SRFI 166** | Monadic / Combinator Formatting | **×** | - | 高機能コンビネータ書式化出力エンジン（未実装） |
| **SRFI 175** | ASCII Character Library | **◎** | [ulisp/lib/char.scm](../lib/char.scm) | ASCII コードポイント検査・分類述語群完備 ([Issue #612](../../docs/issues/612-implement-r7rs-char-ascii-predicates-and-conversions.md)) |
| **SRFI 178** | Bitvectors (ビットベクタ) | **×** | - | 1 ビット単位の論理配列型およびビットフィールド走査演算（未実装） |
| **SRFI 180** | JSON (JSON パース・シリアライズ) | **×** | - | RFC 8259 準拠 JSON パーサおよびジェネレータ（未実装） |
| **SRFI 189** | Maybe and Either: optional values and error containers | **×** | - | 関数型オプショナル値 (`just`, `nothing`) および結果値 (`right`, `left`) モナド風コンテナ（未実装） |
| **SRFI 190** | Coroutine Generators | **△** | - | ファーストクラス継続を用いたコルーチンジェネレータ（`call/cc` で自前構築可能） |
| **SRFI 196** | Range Objects (範囲オブジェクト) | **×** | - | インデックス指定可能な計算可能遅延シーケンス（未実装） |
| **SRFI 207** | Bytestrings (バイト文字列) | **×** | - | ASCII 文字列互換のバイナリバイト列型（未実装） |
| **SRFI 209** | Enums and Enum Sets (列挙型・列挙集合) | **×** | - | シンボリック列挙型および効率的ビットマスク列挙集合（未実装） |
| **SRFI 214** | Flexvectors (可変長動的ベクタ) | **×** | - | 要素の動的追加・削除が可能な拡張ベクタ型（未実装） |
| **SRFI 217** | Integer Sets (整数集合) | **×** | - | 非負整数の高速ビットマップ集合（未実装） |
| **SRFI 222** | Compound Objects (複合オブジェクト) | **×** | - | 複数オブジェクトの直和的ラップ型（未実装） |
| **SRFI 223** | Generalized Binary Search (汎用二分探索) | **×** | - | シーケンスに対する汎用二分探索アルゴリズム（未実装） |
| **SRFI 224** | Integer Mappings (整数マップ) | **×** | - | 非負整数をキーとする高速 Trie マップ（未実装） |
| **SRFI 225** | Generic Dictionary Operations (汎用辞書インターフェース) | **×** | - | ハッシュテーブル・連想リスト・木マップに対する統一的ディクショナリアクセス（未実装） |
| **SRFI 228** | Composing Comparators (合成比較器) | **×** | - | 複数フィールドの辞書式比較器自動合成（未実装） |

---

### 2.5 実践的・基盤的 SRFI (システム連携・並行処理・テスト・互換性)

| 仕様番号 / SRFI | 名称・対象機能 | ステータス | 内部実装ファイル | 備考・技術仕様 |
| :--- | :--- | :---: | :--- | :--- |
| **SRFI 0** | Feature-based conditional expansion (`cond-expand`) | **◎** | [Pass 010](../frontend/010_library.scm) | R7RS-small §4.2.1 に正式採択。プラットフォーム機能判定 |
| **SRFI 2** | AND-LET* (条件付き束縛構文) | **◎** | [Pass 030](../frontend/030_desugar.scm) | `and` / `let*` へのマクロ展開で容易に実現可能 |
| **SRFI 6** | Basic String Ports | **◎** | [ulisp/lib/port.scm](../lib/port.scm) | R7RS-small §6.13.1 に正式採択。`open-input-string`, `open-output-string`, `get-output-string` 完備 |
| **SRFI 9** | Defining Record Types (`define-record-type`) | **◎** | [Pass 030](../frontend/030_desugar.scm) | R7RS-small §5.5 に正式採択。完全サポート ([Issue #549](../../docs/issues/closed/549-implement-r7rs-define-record-type-macro.md)) |
| **SRFI 11** | Syntax for multiple values (`let-values`, `let*-values`) | **◎** | [Pass 030](../frontend/030_desugar.scm) | R7RS-small §4.2.2 に正式採択。完全サポート ([Issue #538](../../docs/issues/closed/538-implement-r7rs-multiple-values-call-with-values.md)) |
| **SRFI 16** | Syntax for procedures of variable arity (`case-lambda`) | **◎** | [Pass 028](../frontend/028_desugar_bindings.scm) | R7RS-small §4.2.9 に正式採択。完全サポート ([Issue #609](../../docs/issues/closed/609-implement-r7rs-case-lambda-syntax.md)) |
| **SRFI 18 / 226**| Multithreading & Concurrency (スレッド・並行制御) | **△** | [ulisp/lib/ulisp/concurrency/](../lib/ulisp/concurrency/) | ULisp 自前の Synapse M:N 並行性ランタイム (Actor/CSP, Futex, io_uring) で高度にサポート |
| **SRFI 23** | Error reporting mechanism (`error`) | **◎** | [Pass 030](../frontend/030_desugar.scm) | R7RS-small §6.11 に正式採択。例外送出 |
| **SRFI 27** | Sources of Random Bits (擬似乱数生成器) | **×** | - | 乱数ビット生成器（未実装） |
| **SRFI 28** | Basic Format Strings (基本文字列フォーマット) | **◎** | [ulisp/lib/format.scm](../lib/format.scm)<br>[ulisp/lib/srfi/28.sld](../lib/srfi/28.sld)<br>[Pass 030](../frontend/030_desugar.scm) | 基本フォーマット文字列 API 完全準拠。`~a`/`~A` (display), `~s`/`~S` (write), `~%` (newline), `~~` (チルダ文字)。静的脱糖インライン展開および `case-lambda` による第一級オブジェクト・引数過不足厳格検証 ([Issue #654](../../docs/issues/closed/654-implement-srfi-28-basic-format-string.md)) |
| **SRFI 34** | Exception Handling for Programs (`with-exception-handler`, `raise`) | **◎** | [ulisp/lib/exception.scm](../lib/exception.scm) | R7RS-small §6.11 に正式採択。完全準拠 |
| **SRFI 35** | Exception Conditions | **×** | - | 構造化コンディションオブジェクト型階層（未実装） |
| **SRFI 38** | External Representation for Data With Shared Structure (`write/ss`) | **◎** | [ulisp/lib/printer.scm](../lib/printer.scm) | R7RS-small §6.13.3 (`write-shared`) に正式採択。循環・共有参照表記 (`#1=`, `#1#`) 完全対応 ([Issue #656](../../docs/issues/closed/656-implement-r7rs-write-simple-and-write-shared.md)) |
| **SRFI 39** | Parameter objects (`make-parameter`, `parameterize`) | **◎** | [ulisp/lib/parameter.scm](../lib/parameter.scm) | R7RS-small §4.2.6 に正式採択。完全サポート ([Issue #537](../../docs/issues/closed/537-implement-r7rs-parameters-and-parameterize.md)) |
| **SRFI 45** | Primitives for Expressing Iterative Lazy Algorithms | **◎** | [ulisp/lib/promise.scm](../lib/promise.scm) | R7RS-small §4.2.5 に正式採択。`delay`, `force`, `delay-force`, `make-promise` 完全準拠 ([Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md)) |
| **SRFI 60** | Integers as Bits (整数ビット表現・操作) | **◎** | [compiler/primitives.scm](../compiler/primitives.scm) | 62-bit Fixnum ビットマスク演算プリミティブ群 |
| **SRFI 64** | Test Suites API (ユニットテスト標準) | **◎** | [ulisp/lib/test.scm](../lib/test.scm)<br>[ulisp/lib/srfi/64.sld](../lib/srfi/64.sld) | SRFI 64 ユニットテスト標準 API 完全準拠。テストスイート・グループ・アサーションマクロ群、スキップ・XFAIL、拡張テストランナー完備 ([Issue #819](../../docs/issues/closed/819-implement-srfi-64-test-suites-library-and-custom-test-runners.md)) |
| **SRFI 78** | Lightweight Testing (軽量テストフレームワーク) | **◎** | [ulisp/lib/check.scm](../lib/check.scm)<br>[ulisp/lib/srfi/78.sld](../lib/srfi/78.sld) | SRFI 78 軽量テストフレームワーク完全準拠。`check`, `check-ec`、アロー記法 `(=>)`、カスタム等価述語、実行モード切替 (`off`, `summary`, `report-failed`, `report`)、ステータス問い合わせ (`check-passed?`, `check-report`, `check-reset!`)、SRFI 64 テストランナー透過的連携完備 ([Issue #820](../../docs/issues/closed/820-implement-srfi-78-lightweight-testing-library.md)) |
| **SRFI 69** | Basic Hash Tables (基本ハッシュテーブル) | **◎** | [ulisp/lib/hashtable.scm](../lib/hashtable.scm)<br>[ulisp/lib/srfi/69.sld](../lib/srfi/69.sld) | 基本ハッシュテーブル API 完全準拠。`make-hash-table`, `hash-table-ref/default`, `hash-table-walk` 等 ([Issue #649](../../docs/issues/closed/649-implement-r7rs-hash-table-api.md)) |
| **SRFI 88** | Keyword Objects (キーワードオブジェクト `:key`) | **×** | - | シンボルで代用 |
| **SRFI 89** | Optional Positional and Named Parameters | **×** | - | 未実装 |
| **SRFI 95** | Sorting and Merging (SLIB ソート・マージ) | **◎** | [ulisp/lib/sort.scm](../lib/sort.scm)<br>[ulisp/lib/srfi/95.sld](../lib/srfi/95.sld) | SLIB / SRFI 95 互換ソート・マージ API 完全準拠。`sort`, `sort!`, `sorted?`, `merge`, `merge!` ([Issue #655](../../docs/issues/closed/655-implement-r7rs-list-and-vector-sort-procedures.md)) |
| **SRFI 98** | Environment Variables (`get-environment-variable`) | **◎** | [ulisp/lib/posix.scm](../lib/posix.scm) | R7RS-small §6.14 に正式採択。POSIX `environ` 連携 ([Issue #611](../../docs/issues/closed/611-implement-r7rs-process-context-environment-variables.md)) |
| **SRFI 106** | Basic Socket Interface (POSIX TCP/IP) | **×** | - | 低レベル Berkeley ソケット通信（未実装） |
| **SRFI 145** | Assumptions (`assert`, `assume`) | **◎** | [Pass 020](../frontend/020_macro_expander.scm)<br>[Pass 030](../frontend/030_desugar.scm)<br>[ulisp/lib/srfi/145.sld](../lib/srfi/145.sld) | SRFI 145 前提表明構文完全準拠。述語真偽値返却、失敗時条件式付きエラー送出 ([Issue #664](../../docs/issues/closed/664-implement-srfi-145-assumptions.md)) |
| **SRFI 170** | POSIX API (低レベルシステムコール) | **◎** (一部) | [ulisp/lib/posix.scm](../lib/posix.scm) | `sys-read`, `sys-write`, `sys-mmap`, `sys-exit`, `%raw-syscall` を実装 |
| **SRFI 193** | Command line (コマンドライン情報) | **◎** | [ulisp/lib/posix.scm](../lib/posix.scm)<br>[ulisp/lib/srfi/193.sld](../lib/srfi/193.sld) | `command-line`, `command-name`, `command-args`, `script-file`, `script-directory` 完備 ([Issue #706](../../docs/issues/closed/706-implement-r7rs-include-library-declarations-and-srfi-193-command-line.md)) |
| **SRFI 194** | Random data generators (乱数ジェネレータ) | **×** | - | 未実装 |
| **SRFI 216** | SICP Prerequisites (SICP 演習前提機能) | **△** | [ulisp/lib/*.scm](../lib/) | `runtime`, `parallel-execute` 等の一部を除き主要プリミティブ完備 |
| **SRFI 252** | Property Testing (プロパティベーステスト) | **◎** | [ulisp/lib/property.scm](../lib/property.scm)<br>[ulisp/lib/srfi/252.sld](../lib/srfi/252.sld) | SRFI 252 プロパティテスト完全準拠。組み込み型ジェネレータ（boolean, char, string, symbol, bytevector, exact-integer, exact-rational, exact-complex, exact-real, exact-number, inexact-real, inexact-integer, inexact-rational, inexact-complex, inexact-number）、複合ジェネレータ（pair, list, vector, sexpr）、決定論的 PRNG シード制御 (`property-random-seed-set!`, `property-random-seed-get`)、`test-property`, `test-property-expect-fail`, `test-property-skip`, `test-property-error`, `test-property-error-type`、および SRFI 64 透過的テストランナー連携完備 ([Issue #821](../../docs/issues/closed/821-implement-srfi-252-property-based-testing-library.md)) |

---

## 3. R7RS 仕様トレーサビリティとライブラリメタデータ管理規約 (Issue #561)

ULisp における R7RS 標準準拠ライブラリおよびコンパイラモジュールの開発・保守においては、**「パターンB（ライブラリ宣言でのメタデータ集約）」と「セクションコメント（`;; §X.Y.Z`）」のハイブリッド方式** を公式規約として採用する。

### 3.1 ハイブリッド方式採択の理由
1. **R7RS 構文規則への完全適合**:
   `define-library` (§5.1) 配下の節は `export`, `import`, `begin`, `include`, `cond-expand` 等に限定されており、独自拡張構文を避けてコメント形式で仕様節を明記することで、コンパイラパーサ ([Pass 010](../frontend/010_library.scm)) を一切阻害せず、100% の規格ポータビリティを保証する。
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
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
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
マクロ展開器 ([Pass 020](../frontend/020_macro_expander.scm)) や構文脱糖器 ([Pass 030](../frontend/030_desugar.scm)) で構文エラーを検出した場合、エラーメッセージに仕様節タグを含める：
```scheme
(error "syntax-error [R7RS §5.3.3]: invalid formals in define-values" form)
```

---

## 4. まとめと今後のロードマップ

1. **R7RS-small コア言語としての達成度**:
   - 構文、第一級継続 (`call/cc` + `dynamic-wind`)、多値 (`values` / `call-with-values`)、完全ゼロアロケーション 2-Space GC、ベクタ、バイトベクタ、遅延評価 (`delay` / `force`)、衛生的マクロ展開器、自前 S 式パーサ/プリンタなど、スタンドアロンな Scheme ネイティブ実行系として **基盤機能の約 90% 以上を完備**。
2. **実装完了済みの主要機能 (Recently Closed Issues)**:
   - [Issue #550](../../docs/issues/closed/550-implement-r7rs-lazy-evaluation-delay-force.md): `delay`, `force`, `delay-force`, `promise?` (遅延評価)
   - [Issue #551](../../docs/issues/closed/551-expand-r7rs-standard-library-procedures.md): `list-copy`, `make-list`, `string-copy!`, `string-fill!` 等のシーケンス操作拡充
   - [Issue #555](../../docs/issues/closed/555-implement-r7rs-list-accessors-list-tail-ref-set.md): `list-tail`, `list-ref`, `list-set!` (リストインデックス操作)
   - [Issue #556](../../docs/issues/closed/556-implement-r7rs-character-comparison-predicates.md): `char<?`, `char>?`, `char<=?`, `char>=?` (文字順序比較)
   - [Issue #557](../../docs/issues/closed/557-implement-r7rs-string-vector-list-conversions-and-string-ordering.md): `string->list`, `list->string`, `string->vector`, `vector->string`, `string<?`, `string>?`, `string<=?`, `string>=?` (文字列・ベクタ・リスト相互変換および文字列順序比較述語)
   - [Issue #558](../../docs/issues/closed/558-implement-r7rs-elementary-integer-math-procedures.md): `square`, `gcd`, `lcm`, `expt`, `remainder` (基本整数算術)
   - [Issue #559](../../docs/issues/closed/559-implement-r7rs-do-loop-syntax.md): `do` (反復実行構文)
   - [Issue #560](../../docs/issues/closed/560-implement-r7rs-define-values-syntax.md): `define-values` (多値定義構文)
   - [Issue #592](../../docs/issues/592-implement-r7rs-internal-definition-desugaring.md): 内部定義（内部 define / 相互再帰）の脱糖
   - [Issue #647](../../docs/issues/closed/647-implement-r7rs-syntax-error-syntax.md): `syntax-error` (マクロ構文エラー報告構文)
   - [Issue #648](../../docs/issues/closed/648-implement-srfi-1-higher-order-list-procedures.md): SRFI 1 高階リスト操作手続き群 (`fold`, `filter`, `iota`, `partition`, `any`, `every` 等) の完全実装
   - [Issue #649](../../docs/issues/closed/649-implement-r7rs-hash-table-api.md): SRFI 69 / SRFI 125 / `(scheme hash-table)` 汎用ハッシュテーブル API の完全実装
   - [Issue #657](../../docs/issues/closed/657-implement-r7rs-let-syntax-and-letrec-syntax.md): `let-syntax` / `letrec-syntax` (局所マクロ束縛および局所相互再帰マクロ構文) の完全実装
   - [Issue #658](../../docs/issues/closed/658-expand-r7rs-cond-expand-feature-identifiers.md): `cond-expand` R7RS 標準機能識別子群の網羅的拡充
   - [Issue #659](../../docs/issues/closed/659-implement-r7rs-include-ci-syntax.md): `include-ci` 大小文字非区別ソース取り込み構文の完全実装
   - [Issue #660](../../docs/issues/closed/660-implement-r7rs-bytevector-ports-and-ready-predicates.md): `open-input-bytevector`, `open-output-bytevector`, `get-output-bytevector`, `char-ready?`, `u8-ready?` の完全実装
   - [Issue #661](../../docs/issues/closed/661-implement-r7rs-scheme-time-procedures.md): `(scheme time)` 時間計測手続き (`current-second`, `current-jiffy`, `jiffies-per-second`) の完全実装
   - [Issue #662](../../docs/issues/closed/662-implement-srfi-141-integer-division.md): SRFI 141 整数除算全 6 モード (`floor`, `truncate`, `ceiling`, `round`, `euclidean`, `centered`) の完全実装
   - [Issue #663](../../docs/issues/closed/663-implement-srfi-111-boxes.md): SRFI 111 / `(scheme box)` ボックス型 (`box`, `box?`, `unbox`, `set-box!`) の完全実装
   - [Issue #664](../../docs/issues/closed/664-implement-srfi-145-assumptions.md): SRFI 145 前提表明構文 (`assume`, `assert`) の完全実装
   - [Issue #665](../../docs/issues/closed/665-enforce-r7rs-specification-traceability-and-diagnostic-tags.md): R7RS 仕様トレーサビリティ管理規約の全ライブラリ適用および診断タグ自動検証の確立
   - [Issue #701](../../docs/issues/closed/701-implement-srfi-128-comparators.md): SRFI 128 / `(scheme comparator)` 第一級コンパレータ・ハッシュ関数の完全実装
   - [Issue #702](../../docs/issues/closed/702-implement-srfi-113-sets-and-bags.md): SRFI 113 / `(scheme set)` 集合 (Sets) および多重集合 (Bags) の完全実装
   - [Issue #703](../../docs/issues/closed/703-implement-srfi-41-streams.md): SRFI 41 / `(scheme stream)` 偶数型遅延ストリームおよび内包表記の完全実装
   - [Issue #704](../../docs/issues/closed/704-implement-srfi-158-generators-and-accumulators.md): SRFI 158 / `(scheme generator)` ジェネレータおよびアキュムレータの完全実装
   - [Issue #705](../../docs/issues/closed/705-implement-r7rs-base-remaining-procedures-and-features.md): R7RS-small `(scheme base)` 残余手続き群 (`features`, ポートオープン述語, 複数引数 map/for-each 等) の完全実装
   - [Issue #706](../../docs/issues/closed/706-implement-r7rs-include-library-declarations-and-srfi-193-command-line.md): R7RS-small `include` / `include-ci` ライブラリ宣言および SRFI 193 コマンドライン引数の完全実装
   - [Issue #707](../../docs/issues/closed/707-implement-srfi-117-list-queues-and-srfi-127-lazy-sequences.md): SRFI 117 / `(scheme list-queue)` および SRFI 127 / `(scheme lseq)` の完全実装
   - [Issue #708](../../docs/issues/closed/708-implement-srfi-14-character-sets.md): SRFI 14 / `(scheme charset)` 文字集合および集合代数演算の完全実装
   - [Issue #709](../../docs/issues/closed/709-implement-srfi-146-immutable-mappings.md): SRFI 146 / `(scheme mapping)` 永続的イミュータブル連想マッピングの完全実装
   - [Issue #710](../../docs/issues/closed/710-implement-srfi-116-immutable-lists-and-srfi-134-immutable-deques.md): SRFI 116 / `(scheme ilist)` および SRFI 134 / `(scheme ideque)` の完全実装
   - [Issue #711](../../docs/issues/closed/711-implement-r7rs-exact-rationals-rounding-and-rationalize.md): R7RS-small 完全数値塔 正確有理数 `<ratnum>`、丸め関数、`rationalize` の完全実装
   - [Issue #712](../../docs/issues/closed/712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates.md): R7RS-small 不正確浮動小数点数 `<flonum>`、正確性変換、IEEE 述語群の完全実装
   - [Issue #713](../../docs/issues/closed/713-implement-r7rs-scheme-inexact-transcendental-math-library.md): R7RS-small `(scheme inexact)` 超越関数数学ライブラリの完全実装
   - [Issue #714](../../docs/issues/closed/714-implement-r7rs-scheme-complex-arithmetic-library.md): R7RS-small `(scheme complex)` 複素数算術ライブラリの完全実装
   - [Issue #715](../../docs/issues/closed/715-implement-r7rs-numeric-tower-reader-printer-and-radix-formatting.md): R7RS-small 数値塔 S 式リーダー・プリンタ・基数フォーマットの完全実装
   - [Issue #716](../../docs/issues/closed/716-implement-r7rs-environment-specifiers-and-library-import-environments.md): R7RS-small §6.12 環境指定子およびライブラリインポート環境の完全実装
   - [Issue #717](../../docs/issues/closed/717-implement-r7rs-scheme-eval-embedded-metacircular-evaluator.md): R7RS-small `(scheme eval)` 組み込みメタサーキュラー評価器の完全実装
   - [Issue #718](../../docs/issues/closed/718-implement-r7rs-scheme-load-repl-and-r5rs-full-compliance.md): R7RS-small `(scheme load)`, `(scheme repl)`, `(scheme r5rs)` 完全準拠化と動的ロードの完全実装（**R7RS-small 全 16 標準ライブラリ 100% 完全準拠達成**）
   - [Issue #819](../../docs/issues/closed/819-implement-srfi-64-test-suites-library-and-custom-test-runners.md): SRFI 64 / `(srfi 64)` ユニットテスト標準 API・テストスイート階層化・拡張テストランナーの完全実装
   - [Issue #820](../../docs/issues/closed/820-implement-srfi-78-lightweight-testing-library.md): SRFI 78 / `(srfi 78)` 軽量テストライブラリ・アロー記法・SRFI 64 透過連携の完全実装
   - [Issue #821](../../docs/issues/closed/821-implement-srfi-252-property-based-testing-library.md): SRFI 252 / `(srfi 252)` プロパティベーステスト・決定論的 PRNG ジェネレータ群の完全実装
   - [Issue #822](../../docs/issues/822-unify-existing-test-suites-to-srfi-64-and-update-compliance-docs.md): 既存テストスイートの SRFI 64 統一・引数順序是正および Nanopass 共通ハーネスの統合
3. **アーキテクチャ特性に基づく設計の進化**:
   - `eval`, `load`, `repl` などの動的実行系は、メタサーキュラー評価器および `open-input-file` / `port-read` 動的ロード機構により、Issue #716-#718 にて **R7RS-small 全 16 標準ライブラリの 100% 完全準拠 (◎)** を達成。
   - 数値塔（Number Tower）は、62-bit 即値 Fixnum、ヒープ有理数 (`<ratnum>`)、倍精度浮動小数点数 (`<flonum>`)、および直交・極形式複素数 (`<compnum>`) を完備し、Issue #711-#715 にて完全準拠を達成。

---

## 5. 原典・仕様規格参照情報源 (Primary Sources & Official Specifications)

本リファレンスおよび ULisp の Scheme 言語準拠実装における公式一次情報源（Primary Sources）は以下の通りである。

### 5.1 R7RS-small 公式規格・リファレンス
- **R7RS-small 公式ポータル**: [Scheme Reports Official Website](https://www.scheme-reports.org/)
- **R7RS-small 正典仕様書 (PDF / Errata 適用版)**: [Revised^7 Report on the Algorithmic Language Scheme - Small Language (PDF)](https://github.com/johnwcowan/r7rs-spec/blob/errata/spec/r7rs.pdf)
- **R7RS-small LaTeX ソースリポジトリ**: [GitHub: johnwcowan/r7rs-spec](https://github.com/johnwcowan/r7rs-spec)
- **R7RS-small 策定作業・投票アーカイブ**: [R7RS-small Working Documents Archive](https://small.r7rs.org/)
- **R7RS-small 標準全 335 識別子アルファベット順索引**: [GitHub: johnwcowan/r7rs-work - SmallLanguageIdentifiers.md](https://github.com/johnwcowan/r7rs-work/blob/master/SmallLanguageIdentifiers.md)
- **R7RS-small エラッタ集**: [GitHub: johnwcowan/r7rs-work - R7RSSmallErrata.md](https://github.com/johnwcowan/r7rs-work/blob/master/R7RSSmallErrata.md)

### 5.2 R7RS-large (Working Group 2) 公式エディション・ドケット
- **R7RS ホームページ (WG2 作業リポジトリ)**: [GitHub: johnwcowan/r7rs-work - R7RSHomePage.md](https://github.com/johnwcowan/r7rs-work/blob/master/R7RSHomePage.md)
- **R7RS-large Red Edition 正典仕様 (2016)**: [GitHub: johnwcowan/r7rs-work - RedEdition.md](https://github.com/johnwcowan/r7rs-work/blob/master/RedEdition.md)
- **R7RS-large Tangerine Edition 正典仕様 (2019)**: [GitHub: johnwcowan/r7rs-work - TangerineEdition.md](https://github.com/johnwcowan/r7rs-work/blob/master/TangerineEdition.md)
- **R7RS-large カラー別ドケット一覧 (Color Dockets)**: [GitHub: johnwcowan/r7rs-work - ColorDockets.md](https://github.com/johnwcowan/r7rs-work/blob/master/ColorDockets.md)
- **R7RS-large 全ドケット索引 (WG2 Dockets)**: [GitHub: johnwcowan/r7rs-work - WG2Dockets.md](https://github.com/johnwcowan/r7rs-work/blob/master/WG2Dockets.md)
- **Yellow Docket (マクロ・構文審議仕様)**: [GitHub: johnwcowan/r7rs-work - YellowDocket.md](https://github.com/johnwcowan/r7rs-work/blob/master/YellowDocket.md)

### 5.3 SRFI (Scheme Requests for Implementation) 公式原典
- **SRFI 公式ディレクトリ・インデックス**: [Scheme Requests for Implementation (SRFI Home)](https://srfi.schemers.org/)
- **SRFI 1 (Lists)**: [SRFI 1: List Library](https://srfi.schemers.org/srfi-1/srfi-1.html)
- **SRFI 8 (RECEIVE)**: [SRFI 8: Binding to multiple values](https://srfi.schemers.org/srfi-8/srfi-8.html)
- **SRFI 9 (Record Types)**: [SRFI 9: Defining Record Types](https://srfi.schemers.org/srfi-9/srfi-9.html)
- **SRFI 11 (Multiple Values)**: [SRFI 11: Syntax for receiving multiple values](https://srfi.schemers.org/srfi-11/srfi-11.html)
- **SRFI 14 (Character Sets)**: [SRFI 14: Character-set Library](https://srfi.schemers.org/srfi-14/srfi-14.html)
- **SRFI 16 (Case-lambda)**: [SRFI 16: Syntax for procedures of variable arity](https://srfi.schemers.org/srfi-16/srfi-16.html)
- **SRFI 26 (Cut / Cute)**: [SRFI 26: Notation for Specializing Parameters without Currying](https://srfi.schemers.org/srfi-26/srfi-26.html)
- **SRFI 28 (Basic Format)**: [SRFI 28: Basic Format Strings](https://srfi.schemers.org/srfi-28/srfi-28.html)
- **SRFI 31 (REC)**: [SRFI 31: A special form rec for recursive evaluation](https://srfi.schemers.org/srfi-31/srfi-31.html)
- **SRFI 38 (Shared Structures)**: [SRFI 38: External Representation for Data With Shared Structure](https://srfi.schemers.org/srfi-38/srfi-38.html)
- **SRFI 39 (Parameters)**: [SRFI 39: Parameter objects](https://srfi.schemers.org/srfi-39/srfi-39.html)
- **SRFI 41 (Streams)**: [SRFI 41: Streams](https://srfi.schemers.org/srfi-41/srfi-41.html)
- **SRFI 45 (Iterative Lazy Algorithms)**: [SRFI 45: Primitives for Expressing Iterative Lazy Algorithms](https://srfi.schemers.org/srfi-45/srfi-45.html)
- **SRFI 60 (Integers as Bits)**: [SRFI 60: Integers as Bits](https://srfi.schemers.org/srfi-60/srfi-60.html)
- **SRFI 61 (General cond clause)**: [SRFI 61: A more general cond clause](https://srfi.schemers.org/srfi-61/srfi-61.html)
- **SRFI 64 (Test Suites)**: [SRFI 64: A Scheme API for Test Suites](https://srfi.schemers.org/srfi-64/srfi-64.html)
- **SRFI 78 (Lightweight Testing)**: [SRFI 78: Lightweight testing](https://srfi.schemers.org/srfi-78/srfi-78.html)
- **SRFI 69 (Basic Hash Tables)**: [SRFI 69: Basic Hash Tables](https://srfi.schemers.org/srfi-69/srfi-69.html)
- **SRFI 95 (Sorting & Merging)**: [SRFI 95: Sorting and Merging](https://srfi.schemers.org/srfi-95/srfi-95.html)
- **SRFI 101 (Random Access Lists)**: [SRFI 101: Purely Functional Random-Access Pairs and Lists](https://srfi.schemers.org/srfi-101/srfi-101.html)
- **SRFI 111 (Boxes)**: [SRFI 111: Boxes](https://srfi.schemers.org/srfi-111/srfi-111.html)
- **SRFI 113 (Sets and Bags)**: [SRFI 113: Sets and bags](https://srfi.schemers.org/srfi-113/srfi-113.html)
- **SRFI 115 (Regex)**: [SRFI 115: Scheme Regular Expressions](https://srfi.schemers.org/srfi-115/srfi-115.html)
- **SRFI 116 (Immutable Lists)**: [SRFI 116: Immutable Pairs and Lists](https://srfi.schemers.org/srfi-116/srfi-116.html)
- **SRFI 117 (List Queues)**: [SRFI 117: Queues based on lists](https://srfi.schemers.org/srfi-117/srfi-117.html)
- **SRFI 121 (Generators)**: [SRFI 121: Generators](https://srfi.schemers.org/srfi-121/srfi-121.html)
- **SRFI 124 (Ephemerons)**: [SRFI 124: Ephemerons](https://srfi.schemers.org/srfi-124/srfi-124.html)
- **SRFI 125 (Intermediate Hash Tables)**: [SRFI 125: Intermediate hash tables](https://srfi.schemers.org/srfi-125/srfi-125.html)
- **SRFI 127 (Lazy Sequences)**: [SRFI 127: Lazy Sequences](https://srfi.schemers.org/srfi-127/srfi-127.html)
- **SRFI 128 (Comparators)**: [SRFI 128: Comparators (reduced)](https://srfi.schemers.org/srfi-128/srfi-128.html)
- **SRFI 132 (Sort Libraries)**: [SRFI 132: Sort Libraries](https://srfi.schemers.org/srfi-132/srfi-132.html)
- **SRFI 133 (Vector Library)**: [SRFI 133: Vector Library (R7RS-compatible)](https://srfi.schemers.org/srfi-133/srfi-133.html)
- **SRFI 134 biological (Immutable Deques)**: [SRFI 134: Immutable Deques](https://srfi.schemers.org/srfi-134/srfi-134.html)
- **SRFI 135 (Immutable Texts)**: [SRFI 135: Immutable Texts](https://srfi.schemers.org/srfi-135/srfi-135.html)
- **SRFI 138 (Compiling Scheme)**: [SRFI 138: Compiling Scheme Programs](https://srfi.schemers.org/srfi-138/srfi-138.html)
- **SRFI 141 (Integer Division)**: [SRFI 141: Integer division](https://srfi.schemers.org/srfi-141/srfi-141.html)
- **SRFI 143 (Fixnums)**: [SRFI 143: Fixnums](https://srfi.schemers.org/srfi-143/srfi-143.html)
- **SRFI 144 (Flonums)**: [SRFI 144: Flonums](https://srfi.schemers.org/srfi-144/srfi-144.html)
- **SRFI 145 (Assumptions)**: [SRFI 145: Assumptions](https://srfi.schemers.org/srfi-145/srfi-145.html)
- **SRFI 146 (Mappings)**: [SRFI 146: Mappings](https://srfi.schemers.org/srfi-146/srfi-146.html)
- **SRFI 151 (Bitwise Operations)**: [SRFI 151: Bitwise Operations](https://srfi.schemers.org/srfi-151/srfi-151.html)
- **SRFI 158 (Generators and Accumulators)**: [SRFI 158: Generators and Accumulators](https://srfi.schemers.org/srfi-158/srfi-158.html)
- **SRFI 159 (Combinator Formatting)**: [SRFI 159: Combinator Formatting](https://srfi.schemers.org/srfi-159/srfi-159.html)
- **SRFI 160 (Homogeneous Numeric Vectors)**: [SRFI 160: Homogeneous numeric vectors](https://srfi.schemers.org/srfi-160/srfi-160.html)
- **SRFI 175 (ASCII Character Library)**: [SRFI 175: ASCII character library](https://srfi.schemers.org/srfi-175/srfi-175.html)
- **SRFI 178 (Bitvectors)**: [SRFI 178: Bitvector library](https://srfi.schemers.org/srfi-178/srfi-178.html)
- **SRFI 179 (Intervals & Arrays)**: [SRFI 179: Nonempty Intervals and Arrays](https://srfi.schemers.org/srfi-179/srfi-179.html)
- **SRFI 180 (JSON)**: [SRFI 180: JSON](https://srfi.schemers.org/srfi-180/srfi-180.html)
- **SRFI 189 (Maybe and Either)**: [SRFI 189: Maybe and Either: optional values and error containers](https://srfi.schemers.org/srfi-189/srfi-189.html)
- **SRFI 210 (Multiple Values Procedures & Syntax)**: [SRFI 210: Procedures and Syntax for Multiple Values](https://srfi.schemers.org/srfi-210/srfi-210.html)
- **SRFI 219 (Define higher-order lambda)**: [SRFI 219: Define higher-order lambda](https://srfi.schemers.org/srfi-219/srfi-219.html)
- **SRFI 252 (Property Testing)**: [SRFI 252: Property Testing](https://srfi.schemers.org/srfi-252/srfi-252.html)

### 5.4 Scheme コミュニティ規格・実装リファレンス
- **Scheme.org Standards Index**: [Scheme.org: Standards](https://standards.scheme.org/)
- **Gauche ユーザリファレンス (R7RS / R7RS-large モジュール一覧)**: [Gauche Users Reference: R7RS large](https://practical-scheme.net/gauche/man/gauche-refj/R7RS-large.html)
- **Sagittarius Scheme R7RS-large 実装マニュアル**: [Sagittarius Users' Reference: (scheme ...) libraries](https://ktakashi.github.io/sagittarius-online-ref/section6.html)
