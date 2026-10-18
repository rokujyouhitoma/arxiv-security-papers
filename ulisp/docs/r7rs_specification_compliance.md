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

| R7RS 仕様番号 | 構文 / 手続き名 | 形式・記法 | ステータス | 内部実装ファイル / 備考 |
| :--- | :--- | :--- | :---: | :--- |
| **4.1.1** | 変数参照 (Variable references) | `<variable>` | **◎** | 静的スコープ解決・レキシカル環境 (`ulisp/passes/040_analysis.scm`) |
| **4.1.2** | リテラル式 (Literal expressions) | `(quote <datum>)`, `'<datum>` | **◎** | 即値・S 式定数化 (`ulisp/compiler/primitives.scm`, `Pass 030`) |
| **4.1.3** | 手続き呼び出し (Procedure calls) | `(<operator> <operand> ...)` | **◎** | TCO (末尾呼び出し最適化) 完全保証 (`ulisp/passes/130_lir.scm`) |
| **4.1.4** | ラムダ式 (Procedures) | `(lambda <formals> <body>)` | **◎** | 固定引数およびレスト引数 `(lambda (x . rest) ...)` 対応 (`Pass 110`) |
| **4.1.5** | 条件式 (Conditionals) | `(if <test> <consequent> <alternate>)` | **◎** | 2分岐・3分岐条件ジャンプ展開 (`ulisp/passes/030_desugar.scm`) |
| **4.1.6** | 代入 (Assignments) | `(set! <variable> <expression>)` | **◎** | 局所・大域変数の破壊的再束縛 (`Pass 030`, `Pass 130`) |
| **4.1.7** | ファイル包含 (Inclusion) | `(include <string1> ...)` | **△** | ビルド時静的ファイル結合で対応 |
| **4.1.7** | ファイル包含 (大文字小文字無視) | `(include-ci <string1> ...)` | **×** | 未実装 |
| **4.2.1** | 条件分岐 (Conditionals) | `(cond <clause1> ...)` | **◎** | `else` 節およびパイプライン構文 `(=> <proc>)` 完全脱糖 (`Pass 030`) |
| **4.2.1** | メンバマッチング分岐 | `(case <key> <clause1> ...)` | **◎** | `memq` 比較連鎖に脱糖 (`Pass 030`) |
| **4.2.1** | 短絡論理積 | `(and <test1> ...)` | **◎** | ネストした `if` に脱糖 (`Pass 030`) |
| **4.2.1** | 短絡論理和 | `(or <test1> ...)` | **◎** | 一時束縛付き `if` に脱糖 (`Pass 030`) |
| **4.2.1** | 1方向真分岐 | `(when <test> <body>)` | **◎** | マクロ展開 (`Pass 020`, `Pass 030`) |
| **4.2.1** | 1方向偽分岐 | `(unless <test> <body>)` | **◎** | マクロ展開 (`Pass 020`, `Pass 030`) |
| **4.2.1** | 条件付き機能展開 | `(cond-expand <ce-clause> ...)` | **△** | プラットフォーム基本識別のみ |
| **4.2.2** | 並列束縛 (Binding constructs) | `(let (<binding> ...) <body>)` | **◎** | 局所変数フレーム・即時適用ラムダ脱糖 (`Pass 030`) |
| **4.2.2** | 名前付き let (Named let) | `(let <variable> (<binding> ...) <body>)` | **◎** | 局所末尾再帰ループ `letrec` に脱糖 (`Pass 030`) |
| **4.2.2** | 直列束縛 | `(let* (<binding> ...) <body>)` | **◎** | ネストした `let` に脱糖 (`Pass 030`) |
| **4.2.2** | 相互再帰束縛 | `(letrec (<binding> ...) <body>)` | **◎** | 相互再帰クロージャ束縛 (`Pass 030`, `Pass 110`) |
| **4.2.2** | 評価順序保証相互再帰 | `(letrec* (<binding> ...) <body>)` | **△** | `letrec` と同等として処理 |
| **4.2.2** | 多値束縛 | `(let-values (<mv-binding> ...) <body>)` | **◎** | `call-with-values` に脱糖 (`Pass 030`, Issue #538) |
| **4.2.2** | 直列多値束縛 | `(let*-values (<mv-binding> ...) <body>)` | **◎** | ネストした `let-values` に脱糖 (`Pass 030`, Issue #538) |
| **4.2.3** | 順序実行 (Sequencing) | `(begin <expression1> ...)` | **◎** | 直列実行ブロック (`Pass 030`, `Pass 070`) |
| **4.2.4** | 反復実行 (Iteration) | `(do ((<var> <init> <step>) ...) ...)` | **×** | 未実装 (named-let への書き換えで代替可能) |
| **4.2.5** | 遅延評価 (Delayed evaluation) | `(delay <expression>)` | **×** (△) | [Issue #550](../../docs/issues/550-implement-r7rs-lazy-evaluation-delay-force.md) で実装予定 |
| **4.2.5** | プロミス強制評価 | `(force <promise>)` | **×** (△) | 同上 |
| **4.2.5** | 末尾遅延評価 | `(delay-force <expression>)` | **×** (△) | トランポリン平坦化メモ化構造として実装予定 (Issue #550) |
| **4.2.5** | プロミス生成 | `(make-promise <obj>)` | **×** (△) | 同上 |
| **4.2.5** | プロミス述語 | `(promise? <obj>)` | **×** (△) | 同上 |
| **4.2.6** | 動的パラメータ (Dynamic bindings)| `(make-parameter <init> [<conv>])` | **◎** | 動的環境セル生成 (`ulisp/lib/parameter.scm`, Issue #539) |
| **4.2.6** | パラメータ一時束縛 | `(parameterize ((<param> <val>) ...) <body>)` | **◎** | `dynamic-wind` と連携する復元保証脱糖 (`Pass 030`) |
| **4.2.7** | 例外処理 (Exception handling) | `(guard (<var> <clause1> ...) <body>)` | **◎** | 動的例外スタック脱糖 (`Pass 030`, Issue #531) |
| **4.2.8** | 準引用 (Quasiquotation) | `` `<qq-template> ``, `,`, `,@` | **◎** | リスト構築 `cons`/`append` へのマクロ脱糖 |
| **4.3.1** | 局所マクロ束縛 | `(let-syntax (<binding> ...) <body>)` | **×** | トップレベルマクロ優先のため未実装 |
| **4.3.1** | 局所再帰マクロ束縛 | `(letrec-syntax (<binding> ...) <body>)` | **×** | 同上 |
| **4.3.2** | 衛生的マクロ (Pattern language)| `(syntax-rules (<literal> ...) <syntax-rule> ...)` | **◎** | パターン変数・省略記号 `...`・リテラル完全照合 (`Pass 020`, Issue #533) |
| **4.3.3** | マクロ構文エラー | `(syntax-error <message> <args> ...)` | **×** | 未実装 |

---

### 1.2 プログラム構造とモジュール (Section 5: Program Structure)

| R7RS 仕様番号 | 構文 / 項目 | 形式・記法 | ステータス | 内部実装ファイル / 備考 |
| :--- | :--- | :--- | :---: | :--- |
| **5.1** | プログラム (Programs) | トップレベル式および定義の並び | **◎** | `%program` ノードによる全体構造化 (`Pass 030`) |
| **5.2 / 5.6** | モジュールインポート | `(import <import-set> ...)` | **◎** | ライブラリ依存解決・シンボル修飾 (`Pass 010`, Issue #548) |
| **5.3.1** | トップレベル変数定義 | `(define <variable> <expression>)` | **◎** | グローバルシンボル束縛 (`Pass 030`) |
| **5.3.1** | 手続き定義短縮構文 | `(define (<variable> <formals>) <body>)` | **◎** | `lambda` 束縛への自動脱糖 (`Pass 030`) |
| **5.3.2** | 内部定義 (Internal definitions) | ブロック先頭の `(define ...)` | **◎** | `letrec*` 構造への自動巻き直し (`Pass 030`) |
| **5.3.3** | 多値定義 | `(define-values <formals> <expression>)` | **×** | 未実装 |
| **5.4** | マクロ定義 (Syntax definitions)| `(define-syntax <keyword> <transformer>)` | **◎** | コンパイル時マクロテーブル登録 (`Pass 020`) |
| **5.5** | レコード型定義 (Record-types) | `(define-record-type <name> (<ctor> ...) <pred> ...)` | **◎** | 固定長ベクタ脱糖マクロ・型述語・アクセサ・ミューテータ完備 (`Pass 030`, Issue #549) |
| **5.6** | ライブラリ定義 (Libraries) | `(define-library (<name> ...) <lib-decl> ...)` | **◎** | R7RS-small モジュール宣言・フラット展開 (`Pass 010`, Issue #548) |
| **5.6** | シンボルエクスポート | `(export <export-spec> ...)` | **◎** | 名前空間公開設定・`rename` 対応 (`Pass 010`) |

---

### 1.3 標準手続き・データ型 (Section 6: Standard Procedures)

#### 6.1 等価性述語 (Equivalence Predicates)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.1** | `(eq? x y)` | **◎** | ポインタ同一性および即値タグの一致判定 (`compiler/primitives.scm`) |
| **6.1** | `(eqv? x y)` | **◎** | 数値・文字の同一性を含む R7RS 完全準拠判定 (`ulisp/lib/equality.scm`, Issue #532) |
| **6.1** | `(equal? x y)` | **◎** | ペア・ベクタ・文字列・バイトベクタの再帰的同値比較 (`ulisp/lib/equality.scm`) |

#### 6.2 数値演算 (Numbers: 63-bit Tagged Fixnum Architecture)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.2.6** | `number?`, `integer?`, `exact?`, `exact-integer?` | **◎** | 最下位 3-bit タグ (`000b`) による Fixnum 判定 (`ulisp/lib/predicates.scm`) |
| **6.2.6** | `real?`, `rational?`, `complex?` | **△** | 整数塔のみサポートのため `integer?` のエイリアスとして実装 |
| **6.2.6** | `inexact?` | **△** | 常に `#f` を返却 (浮動小数点数非サポート) |
| **6.2.6** | `zero?`, `positive?`, `negative?` | **◎** | 符号・ゼロ判定プリミティブ (`compiler/primitives.scm`) |
| **6.2.6** | `odd?`, `even?` | **◎** | LSB ビット判定 |
| **6.2.6** | `+`, `-`, `*` | **◎** | 63-bit 加減乗算、定数畳み込み、x86/C バックエンド直結 |
| **6.2.6** | `/`, `quotient`, `modulo` | **◎** | 整数除算・剰余、ゼロ除算トラップ保護 (`compiler/primitives.scm`) |
| **6.2.6** | `=`, `<`, `>`, `<=`, `>=` | **◎** | 整数比較、分岐融合 (Branch Fusion) 最適化 (`Pass 130`) |
| **6.2.6** | `max`, `min`, `abs` | **△** | 2引数固定で基本演算を提供 |
| **6.2.6** | `floor/`, `floor-quotient`, `floor-remainder` | **×** | 未実装 |
| **6.2.6** | `truncate/`, `truncate-quotient`, `truncate-remainder` | **×** | 未実装 |
| **6.2.6** | `remainder`, `gcd`, `lcm`, `square`, `expt` | **×** | 未実装 |
| **6.2.6** | `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `exp`, `log`, `sqrt` | **×** | 超越関数 (浮動小数点非サポートのため未実装) |

#### 6.3 真偽値 (Booleans)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.3** | `not` | **◎** | `#f` 判定 (Scheme の偽値は `#f` のみ) (`compiler/primitives.scm`) |
| **6.3** | `boolean?` | **◎** | 即値ブールタグ (`00101111b`, `01101111b`) 判定 (`compiler/primitives.scm`) |
| **6.3** | `boolean=?` | **◎** | 真偽値同値判定 (`ulisp/lib/equality.scm`) |

#### 6.4 ペアとリスト (Pairs and Lists)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.4** | `pair?`, `null?` | **◎** | ヒープペア型タグ判定・空リスト (`'()`) 判定 (`compiler/primitives.scm`) |
| **6.4** | `cons`, `car`, `cdr` | **◎** | ペア生成・要素取得、LVN / 純粋アクセサ最適化 (`Pass 060`, `Pass 130`) |
| **6.4** | `set-car!`, `set-cdr!` | **◎** | 破壊的代入、世代別 GC ライトバリア・リメンバーセット記録 (`ulisp/lib/gc.scm`) |
| **6.4** | `caar`, `cadr`, `cdar`, `cddr`, `caddr`, `cdddr`, `cadddr` | **◎** | リスト短縮アクセサ (`Pass 030`) |
| **6.4** | `list?`, `list`, `length`, `reverse`, `append` | **◎** | 基本リスト操作 (`ulisp/lib/predicates.scm`, `ulisp/lib/string.scm`) |
| **6.4** | `memq`, `memv`, `member` | **◎** | 要素探索 (`compiler/primitives.scm`) |
| **6.4** | `assq`, `assv`, `assoc` | **◎** | 連想リストキー探索 (`compiler/primitives.scm`) |
| **6.4** | `make-list`, `list-tail`, `list-ref`, `list-set!`, `list-copy` | **×** (△) | 拡張リスト操作 ([Issue #551](../../docs/issues/551-expand-r7rs-standard-library-procedures.md) で追加予定) |

#### 6.5 シンボル (Symbols)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.5** | `symbol?` | **◎** | シンボル型タグ判定 (`compiler/primitives.scm`) |
| **6.5** | `symbol=?` | **◎** | シンボル一意比較 (`ulisp/lib/equality.scm`) |
| **6.5** | `symbol->string`, `string->symbol` | **◎** | グローバルシンボルレジストリ・インターン (`ulisp/lib/string.scm`, Issue #528) |

#### 6.6 文字 (Characters)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.6** | `char?`, `char=?` | **◎** | 即値文字タグ判定・比較 (`compiler/primitives.scm`) |
| **6.6** | `char->integer`, `integer->char` | **◎** | コードポイント相互変換 (`compiler/primitives.scm`) |
| **6.6** | `char<?`, `char>?`, `char<=?`, `char>=?` | **×** | 文字の順序比較 (未実装) |
| **6.6** | `char-ci=?`, `char-alphabetic?`, `char-numeric?` 等 | **×** | Unicode 特性判定 (未実装) |

#### 6.7 文字列 (Strings)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.7** | `string?`, `make-string`, `string-length` | **◎** | ヒープ文字列アロケーション・長さ取得 (`compiler/primitives.scm`) |
| **6.7** | `string-ref`, `string-set!` | **◎** | インデックスアクセスおよびインプレース更新 (`compiler/primitives.scm`) |
| **6.7** | `string=?` | **◎** | 文字列内容比較 (`ulisp/lib/string.scm`) |
| **6.7** | `substring`, `string-append` | **◎** | スライシング・2分木分割結合脱糖 (`Pass 030`, `ulisp/lib/string.scm`) |
| **6.7** | `string`, `string<?`, `string>?`, `string<=?`, `string>=?` | **×** | 辞書順比較 (未実装) |
| **6.7** | `string->list`, `list->string`, `string-copy!`, `string-fill!` | **×** (△) | 相互変換・破壊的充填 ([Issue #551](../../docs/issues/551-expand-r7rs-standard-library-procedures.md) で追加予定) |

#### 6.8 ベクタ (Vectors)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.8** | `vector?`, `make-vector`, `vector` | **◎** | 連続ヒープベクタ型 (`ulisp/lib/vector.scm`, Issue #536) |
| **6.8** | `vector-length`, `vector-ref`, `vector-set!` | **◎** | O(1) ランダムアクセス・更新 (`compiler/primitives.scm`) |
| **6.8** | `vector-copy`, `vector-copy!`, `vector-append`, `vector-fill!` | **◎** | スライス複製・破壊的転送・充填 (`ulisp/lib/vector.scm`, `Pass 030`) |
| **6.8** | `vector->list`, `list->vector` | **◎** | リスト・ベクタ相互変換 (`ulisp/lib/vector.scm`, `Pass 030`) |
| **6.8** | `vector-map`, `vector-for-each` | **◎** | ベクタ要素マッピング・走査 (`ulisp/lib/vector.scm`) |
| **6.8** | `vector->string`, `string->vector` | **×** | 直接相互変換 (未実装) |

#### 6.9 バイトベクタ (Bytevectors)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.9** | `bytevector?`, `make-bytevector`, `bytevector` | **◎** | 8-bit 生バイト配列型 (`ulisp/lib/bytevector.scm`, Issue #535) |
| **6.9** | `bytevector-length`, `bytevector-u8-ref`, `bytevector-u8-set!` | **◎** | バイト単位の読み書き (`compiler/primitives.scm`) |
| **6.9** | `bytevector-copy`, `bytevector-copy!`, `bytevector-append`, `bytevector=?`| **◎** | メモリブロック高速コピー・比較 (`ulisp/lib/bytevector.scm`, `Pass 030`) |
| **6.9** | `utf8->string`, `string->utf8` | **◎** | UTF-8 エンコード / デコード変換 (`ulisp/lib/bytevector.scm`, `Pass 030`) |

#### 6.10 制御機能・継続・多値 (Control Features)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.10** | `procedure?` | **◎** | 手続き型タグ判定 (`compiler/primitives.scm`) |
| **6.10** | `apply` | **◎** | クロージャへの可変長引数アンパック呼び出し (`Pass 110`, `Pass 130`) |
| **6.10** | `call-with-current-continuation`, `call/cc` | **◎** | スタックセグメントコピー方式ファーストクラス継続 ([continuations_and_unwind.md](continuations_and_unwind.md), Issue #540) |
| **6.10** | `dynamic-wind` | **◎** | LCA (Lowest Common Ancestor) による unwind/rewind 遷移 (`ulisp/lib/continuation.scm`) |
| **6.10** | `values`, `call-with-values` | **◎** | ゼロアロケーション多値返却・受け渡し ABI (`ulisp/lib/values.scm`, Issue #538) |
| **6.10** | `map`, `for-each` (複数引数リスト版) | **△** | 単一リストおよびベクタ版は提供。多変数リスト版は未対応 |

#### 6.11 例外機構 (Exceptions)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.11** | `with-exception-handler` | **◎** | 動的例外ハンドラ登録 (`ulisp/lib/exception.scm`, Issue #531) |
| **6.11** | `raise`, `raise-continuable` | **◎** | 脱出型・復帰型例外送出 (`ulisp/lib/exception.scm`) |
| **6.11** | `error` | **◎** | エラーオブジェクト生成・送出マクロ (`Pass 030`) |
| **6.11** | `error-object?`, `error-object-message`, `error-object-irritants` | **◎** | エラー情報抽出アクセサ (`ulisp/lib/exception.scm`) |
| **6.11** | `read-error?`, `file-error?` | **◎** | エラーカテゴリ型判定 (`ulisp/lib/exception.scm`) |

#### 6.12 環境と動的評価 (Environments and Evaluation)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.12** | `eval`, `environment` | **✕\*** | 純粋 AOT ネイティブコンパイラのため実行時動的 eval は除外 (マクロ展開で完結) |

#### 6.13 入出力とポート (Input and Output)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.13.1** | `port?`, `input-port?`, `output-port?` | **◎** | ポート型述語 (`ulisp/lib/port.scm`, Issue #537) |
| **6.13.1** | `textual-port?`, `binary-port?`, `port-open?` | **◎** | テキスト/バイナリ識別および状態判定 (`ulisp/lib/port.scm`) |
| **6.13.1** | `close-port`, `close-input-port`, `close-output-port` | **◎** | ポートクローズ (`ulisp/lib/port.scm`) |
| **6.13.1** | `current-input-port`, `current-output-port` | **◎** | 標準入力 (`*stdin-port*`)・標準出力 (`*stdout-port*`) |
| **6.13.1** | `open-input-string`, `open-output-string`, `get-output-string` | **◎** | メモリ上文字列ポート (`ulisp/lib/port.scm`, Issue #534) |
| **6.13.2** | `read` | **◎** | 自前完全再帰下降 S 式パーサ (`ulisp/lib/reader.scm`) |
| **6.13.2** | `read-char`, `peek-char` | **◎** | 1文字先読み・消費 (`ulisp/lib/port.scm`, `ulisp/lib/posix.scm`) |
| **6.13.2** | `eof-object?`, `eof-object` | **◎** | EOF 即値タグ判定 (`compiler/primitives.scm`) |
| **6.13.3** | `write`, `display` | **◎** | S 式シリアライザおよび文字列表現出力 (`ulisp/lib/printer.scm`) |
| **6.13.3** | `write-char`, `write-string`, `newline`, `flush-output-port` | **◎** | バッファ付きテキスト出力 (`ulisp/lib/port.scm`, `ulisp/lib/posix.scm`) |
| **6.13.3** | `write-shared`, `write-simple` | **×** | 循環参照出力 (未実装) |

#### 6.14 システムインターフェース (System Interface)
| R7RS 仕様番号 | 手続き名 | ステータス | 内部実装 / 技術仕様 |
| :--- | :--- | :---: | :--- |
| **6.14** | `exit`, `emergency-exit` | **◎** | POSIX `sys-exit` 終了コード返却 (`ulisp/lib/posix.scm`) |
| **6.14** | `load` | **✕\*** | 動的コードロード (AOT のためビルド時静的リンクで代替) |
| **6.14** | `file-exists?`, `delete-file` | **△** | 低レベル syscall で可能。ポート API 未整備 |
| **6.14** | `command-line` | **△** | ランタイム引数渡しで基本対応 |
| **6.14** | `get-environment-variable`, `get-environment-variables` | **×** | 環境変数取得 (未実装) |
| **6.14** | `current-second`, `current-jiffy`, `jiffies-per-second` | **×** | 高精度タイマー (未実装) |

---

### 1.4 R7RS-small 標準 16 ライブラリ別網羅表

| ライブラリ識別子 | 主な責務・内容 | サポート率 | 主なサポート機能 / 未サポート理由 |
| :--- | :--- | :---: | :--- |
| `(scheme base)` | コア構文、算術、リスト、ベクタ、継続、多値、ポート | **約 85%** | 構文・`call/cc`・多値・ベクタ・GC 完備。有理数・複素数・浮動小数演算のみ非サポート |
| `(scheme case-lambda)` | 可変個引数パターンマッチング | **× 0%** | `case-lambda` 未実装（レスト引数 `(lambda (x . rest) ...)` で代替可能） |
| `(scheme char)` | Unicode 大文字小文字変換・判定 | **約 20%** | `char=?`, `char->integer` のみ。Unicode 大小比較・Case-folding 未実装 |
| `(scheme complex)` | 複素数算術 | **× 0%** | 非サポート（Fixnum 優先アーキテクチャ） |
| `(scheme cxr)` | `caaa...r` 〜 `cdddr` (全24種) | **約 30%** | `caar`, `cadr`, `cdar`, `cddr`, `caddr`, `cdddr`, `cadddr` をサポート |
| `(scheme eval)` | 動的評価 (`eval`, `environment`) | **✕\* 0%** | AOT の性質上除外（事前コンパイル時マクロ展開で完結） |
| `(scheme file)` | ファイル入出力 | **△ 約 40%** | POSIX `sys-read`/`sys-write` 実装済み。上位ストリーム関数は未整備 |
| `(scheme inexact)` | 浮動小数点数・超越関数 | **× 0%** | 非サポート（整数・Tagged Pointer 設計） |
| `(scheme lazy)` | 遅延評価 (`delay`, `force`) | **× 0%** | [Issue #550](../../docs/issues/550-implement-r7rs-lazy-evaluation-delay-force.md) にて実装予定 |
| `(scheme load)` | スクリプト動的ロード | **✕\* 0%** | AOT の性質上除外（`import` またはビルド時結合で代替） |
| `(scheme process-context)` | プロセス環境 (`exit`, `command-line`) | **約 50%** | `exit`, `emergency-exit` 完備。`get-environment-variable` は未実装 |
| `(scheme read)` | S 式リーダー (`read`) | **◎ 100%** | 自前完全再帰下降パーサ (`ulisp/lib/reader.scm`) 完備 |
| `(scheme repl)` | 対話型 REPL | **✕\* 0%** | AOT コンパイラのため静的バイナリ出力が正典 |
| `(scheme time)` | 時間計測 (`current-second`) | **× 0%** | POSIX `clock_gettime` ラッパー未提供 |
| `(scheme write)` | S 式ライター (`write`, `display`) | **約 70%** | `write`, `display` 完備。`write-shared` は未実装 |

---

## 2. R7RS-large 言語仕様準拠状況

R7RS-large は、Scheme コミュニティの SRFI 群を「エディション (Editions)」として標準化した仕様です。

### 2.1 Red Edition (データ構造・アルゴリズム)

| 仕様番号 (SRFI) | 名称・対象機能 | ステータス | ULisp での対応状況・代替手段 |
| :--- | :--- | :---: | :--- |
| **SRFI 1** | Lists (高機能リスト処理: `fold`, `unfold`, `filter`, `take`, `drop` 等) | **△** | 基本関数（`append`, `reverse`, `length`, `memq`, `assq`）のみ。高階畳み込み系は未提供 |
| **SRFI 9** | Records (`define-record-type`) | **◎** | 完全サポート (`Pass 030`, Issue #549) |
| **SRFI 11** | Syntax for multiple values (`let-values`, `let*-values`) | **◎** | 完全サポート (`Pass 030`, Issue #538) |
| **SRFI 39** | Parameter objects (`make-parameter`, `parameterize`) | **◎** | 完全サポート (`ulisp/lib/parameter.scm`, Issue #539) |
| **SRFI 111** | Boxes (単一要素可変セル: `box`, `unbox`, `set-box!`) | **△** | 1要素ベクタまたはペア `(cons val '())` で代用可能（専用関数は未提供） |
| **SRFI 113** | Sets and Bags (集合・マルチセット) | **×** | 未実装 |
| **SRFI 116** | Immutable Pairs and Lists (不変リスト・ペア) | **×** | 未実装 |
| **SRFI 117** | Queues based on Lists (リストベースキュー) | **×** | 未実装 |
| **SRFI 121** | Generators (ジェネレータ・イテレータ) | **△** | ファーストクラス継続 (`call/cc`) によるコルーチンジェネレータ作成可能 |
| **SRFI 125** | Intermediate Hash Tables (ハッシュテーブル) | **△** | `*symbol-registry*` で内部ハッシュ探索あり。ユーザ向け汎用テーブル API は未提供 |
| **SRFI 128** | Comparators (比較器) | **×** | 未実装 |
| **SRFI 132** | Sort Libraries (ソート・マージアルゴリズム) | **×** | 未実装 |
| **SRFI 133** | Vectors (高機能ベクタ操作) | **◎** (準拠) | `vector-copy`, `vector-copy!`, `vector-append`, `vector-fill!`, `vector-map`, `vector-for-each` 等を網羅 (`ulisp/lib/vector.scm`) |
| **SRFI 134** | Immutable Deques (不変両端キュー) | **×** | 未実装 |
| **SRFI 135** | Immutable Texts (不変テキスト) | **×** | 未実装 |
| **SRFI 146** | Mappings (赤黒木 / AVL 木マップ) | **×** | 未実装 |

---

### 2.2 Tangerine Edition (数値・ビット演算・低レベル)

| 仕様番号 (SRFI) | 名称・対象機能 | ステータス | ULisp での対応状況・代替手段 |
| :--- | :--- | :---: | :--- |
| **SRFI 141** | Integer Division (6モードの整数除算) | **△** | `quotient`, `modulo`, `/` のみサポート |
| **SRFI 143** | Fixnums (Fixnum 専用高速演算: `fx+`, `fx-`, `fxadd1` 等) | **◎** | `fxadd1`, `fxsub1` 等コンパイラ内部プリミティブおよび AOT アンボクシング対応 (`Pass 090`) |
| **SRFI 144** | Flonums (浮動小数点数演算) | **×** | 浮動小数点型非対応のため未実装 |
| **SRFI 151** | Bitwise Operations (ビット演算) | **◎** | `bitwise-and`, `bitwise-ior`, `bitwise-arithmetic-shift` サポート (`compiler/primitives.scm`) |
| **SRFI 160** | Homogeneous numeric vectors (u8, s8, u16 等の型付きベクタ) | **△** | `u8` (バイトベクタ) を完全サポート。16/32/64bit 型付きベクタは未実装 |
| **SRFI 179** | Nonempty Intervals and Arrays (多次元配列) | **×** | 未実装 |

---

### 2.3 その他主要 SRFI (システム・メタプログラミング)

| 仕様番号 (SRFI) | 名称・対象機能 | ステータス | ULisp での対応状況・代替手段 |
| :--- | :--- | :---: | :--- |
| **SRFI 170** | POSIX API (低レベルシステムコール) | **◎** (一部) | `sys-read`, `sys-write`, `sys-mmap`, `sys-exit`, `%raw-syscall` を実装 (`ulisp/lib/posix.scm`) |
| **SRFI 64** | Test Suites API (ユニットテスト) | **△** | 自前アサーション・テストドライバ (`ulisp/test.sh`, `ulisp/test_c.sh`) で運用 |
| **SRFI 18 / 226**| Multithreading (スレッド並行処理) | **×** | シングルスレッドモデル |
| **SRFI 115** | Regular Expressions (正規表現) | **×** | 未実装 |
| **SRFI 145** | Assumptions (`assert`, `assume`) | **△** | `guard` / `raise` / `error` で代用可能 |

---

## 3. まとめと今後のロードマップ

1. **R7RS-small コア言語としての達成度**:
   - 構文、第一級継続 (`call/cc` + `dynamic-wind`)、多値 (`values` / `call-with-values`)、完全ゼロアロケーション 2-Space GC、ベクタ、バイトベクタ、衛生的マクロ展開器、自前 S 式パーサ/プリンタなど、スタンドアロンな Scheme ネイティブ実行系として **基盤機能の約 85% を完備**。
2. **直近の実装予定 (Open Issues)**:
   - [Issue #550](../../docs/issues/550-implement-r7rs-lazy-evaluation-delay-force.md): `delay`, `force`, `delay-force`, `promise?` (遅延評価)
   - [Issue #551](../../docs/issues/551-expand-r7rs-standard-library-procedures.md): `list-copy`, `make-list`, `string-copy!`, `string-fill!` 等のシーケンス操作拡充
3. **アーキテクチャ特性に基づく設計トレードオフ**:
   - `eval`, `load`, `repl` などの動的実行系は、AOT コンパイラのバイナリ独立性・フットプリント最小化を優先して意図的に除外。
   - 数値塔（Number Tower）は 63-bit 即値 Fixnum を基本とし、ポインタタグの最小化と高速実行を優先。
