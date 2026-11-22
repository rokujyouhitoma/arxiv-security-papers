---
ID: 914
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-21
---

# [FEAT/ENH] 純粋 Scheme 製 C99 プリプロセッサ (CPP: #include / #define / ## / #if CTFE) の実装 (ID: 914)

## 1. 概要 / Summary
外部 `cc -E` に依存せず、純粋 Scheme で ISO/IEC 9899:1999 (C99) 準拠のプリプロセッサ（`ulisp/frontend_c/preprocessor.scm`）を実装する（Phase S2 / Task T2）。[[#913]](913-implement-c99-lexer-and-token-stream-with-source-span.md) で構築した PEG 合成 C99 Lexer（`<c-token>` ストリーム）を入力として受け取り、Lua 5.x の `luaconf.h` や `lobject.h` で多用されるネストした関数形式マクロ、可変長マクロ（`...` / `__VA_ARGS__`）、文字列化（`#`）、トークン連結（`##`）、Dave Prosser の青塗りアルゴリズム（Blue-painted `hide-set`）による再帰展開抑止、`#include` 探索とインクルードガード高速バイパス、および CTFE（`#825`）連携 `#if` 定数整数式評価を完遂する。

前処理済みの `<c-token>` 列は、`c-concat-adjacent-string-tokens` ＆ `c-tokens->source-string` 経由でシームレスに [[#931]](931-implement-c99-peg-grammar-specification-and-parser-synthesis.md) の `parse-c99-string` へ引き渡せる。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §3.1, §5.1 (Lua C コンパイル ＆ CPP 要件)](../../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §3.3, §4.1 (多言語フロントエンド CPP ＆ CTFE)](../../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
- 前提基盤（実装済）:
  - `#824`: `<source-span>` ＆ `span-macro-origin` 追跡（[ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm)）
  - `#825`: CTFE 定数式評価基盤（[ulisp/compiler/eval_in_language.scm](../../../ulisp/compiler/eval_in_language.scm)）
  - `#832`: 純粋 Scheme 64-bit / Bignum 整数演算（[ulisp/lib/bignum.scm](../../../ulisp/lib/bignum.scm)）
  - `#833`: 統合 Pretty Diagnostic Reporter（[ulisp/compiler/diagnostic.scm](../../../ulisp/compiler/diagnostic.scm)）
  - `#913`: PEG 合成型 C99 Lexer ＆ `<c-token>` ストリーム（[ulisp/frontend_c/lexer.scm](../../../ulisp/frontend_c/lexer.scm), [[#913]](913-implement-c99-lexer-and-token-stream-with-source-span.md)）
  - `#931`: C99 PEG 文法 ＆ パーサー合成基盤（[tools/grammars/c99.peg](../../../tools/grammars/c99.peg), [ulisp/frontend_c/parser.scm](../../../ulisp/frontend_c/parser.scm), [[#931]](931-implement-c99-peg-grammar-specification-and-parser-synthesis.md)）
- 後続連携 Issue:
  - [[#915]](../915-implement-c99-parser-and-nanopass-c-ast-definitions.md) (C99 パーサー ＆ Nanopass `L_c_ast` 統合)
  - [[#917]](917-implement-c-compiler-driver-and-host-ld-integration.md) (`c_driver.scm` `-I`/`-D`/`-U` フラグ連携)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/frontend_c/preprocessor.scm](../../../ulisp/frontend_c/preprocessor.scm) (新規: `<cpp-macro>`, `<cpp-context>`, ディレクティブ処理, `#include` リゾルバ, Blue-painted 展開エンジン, `#if` 定数式評価器)
- [x] [ulisp/tests/test_c99_preprocessor.scm](../../../ulisp/tests/test_c99_preprocessor.scm) (新規: 単体テスト・境界テスト・セキュリティ異常系テスト・`cc -E` 突合＆`#931` パース往復テスト全32項目)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`test_c99_preprocessor` ターゲットおよび `test` 集約への登録)
- 既存連携先（参照のみ / 変更不要）:
  - [ulisp/frontend_c/lexer.scm](../../../ulisp/frontend_c/lexer.scm) (`c-tokenize-string`, `c-tokenize-file`, `c-token-*`, `c-concat-adjacent-string-tokens`, `c-tokens->source-string`)
  - [ulisp/frontend_c/parser.scm](../../../ulisp/frontend_c/parser.scm) (`parse-c99-string`)
  - [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) (`make-source-span`, `next-source-span-id!`, `span-macro-origin`)
  - [ulisp/compiler/eval_in_language.scm](../../../ulisp/compiler/eval_in_language.scm) (`ctfe-bitwise-*`, `ctfe-arithmetic-shift` 等定数式評価基盤)
  - [ulisp/compiler/diagnostic.scm](../../../ulisp/compiler/diagnostic.scm) (`make-diagnostic`, `report-diagnostic`, `diagnostic-register-source-string!`)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/914-implement-pure-scheme-c99-preprocessor`

### 4.1 データ構造と公開インターフェース (`ulisp/frontend_c/preprocessor.scm`)
1. **`<cpp-macro>` レコード定義**:
   ```scheme
   (define-record-type <cpp-macro>
     (make-cpp-macro name function-like? params variadic? body def-span builtin-proc)
     cpp-macro?
     (name          cpp-macro-name)
     (function-like? cpp-macro-function-like?)
     (params        cpp-macro-params)
     (variadic?     cpp-macro-variadic?)
     (body          cpp-macro-body)
     (def-span      cpp-macro-def-span)
     (builtin-proc  cpp-macro-builtin-proc))
   ```
2. **`<cpp-context>` レコード定義**:
   ```scheme
   (define-record-type <cpp-context>
     (make-cpp-context include-paths system-include-paths macros
                       pragma-once-files include-guard-cache
                       include-depth max-include-depth
                       expansion-steps max-expansion-steps)
     cpp-context?
     (include-paths        cpp-ctx-include-paths        cpp-ctx-include-paths-set!)
     (system-include-paths cpp-ctx-system-include-paths cpp-ctx-system-include-paths-set!)
     (macros               cpp-ctx-macros               cpp-ctx-macros-set!)
     (pragma-once-files    cpp-ctx-pragma-once-files    cpp-ctx-pragma-once-files-set!)
     (include-guard-cache  cpp-ctx-include-guard-cache  cpp-ctx-include-guard-cache-set!)
     (include-depth        cpp-ctx-include-depth        cpp-ctx-include-depth-set!)
     (max-include-depth    cpp-ctx-max-include-depth)
     (expansion-steps      cpp-ctx-expansion-steps      cpp-ctx-expansion-steps-set!)
     (max-expansion-steps  cpp-ctx-max-expansion-steps))
   ```
3. **公開 API**:
   - `(make-default-cpp-context . maybe-include-paths)` -> 標準組み込みマクロ登録済みコンテキスト生成
   - `(cpp-define-object! ctx name-sym body-tokens)` / `(cpp-define-string! ctx name-str val-str)` (`-D` フラグ互換)
   - `(cpp-undef! ctx name-sym)` (`-U` フラグ互換)
   - `(cpp-add-include-path! ctx dir-path . maybe-system?)` (`-I` / `-isystem` 対応)
   - `(cpp-preprocess-tokens ctx tokens)` -> 前処理済み `<c-token>` リスト
   - `(cpp-preprocess-string src-text . maybe-filename-and-ctx)` -> 前処理済み `<c-token>` リスト（`parse-c99-string` 連携に直結）
   - `(cpp-preprocess-file filepath . maybe-ctx)` -> ファイル読込後前処理

### 4.2 ディレクティブ処理と `#include` 解決
1. **行頭ディレクティブ切り出し**:
   - `c-token-at-bol?` が `#t` かつ `'punct "#"` で始まるトークン列を論理行末尾（次の `c-token-at-bol?` が `#t` のトークンまたは `'eof` 手前）まで切り出してディレクティブ種別を判定する（空ディレクティブ `#` は無視）。
2. **`#define` / `#undef` / `#error` / `#pragma` / `#line`**:
   - マクロ名直後に空白なし `(`（`(and (c-token-is-punct? lparen "(") (not (c-token-has-leading-space? lparen)))`）が続く場合は **関数形式マクロ**、空白ありまたは `(` 以外は **オブジェクト形式マクロ** と厳密に区別する。
   - 仮引数末尾の `...` により可変長フラグ `variadic?` を設定し、`__VA_ARGS__` へ実引数の残り（カンマ含み）を束縛する。
   - `#pragma once` は解決済み正規パスを `pragma-once-files` へ登録して2回目以降の再読込を即座にスキップする。
3. **`#include` 探索 ＆ インクルードガード最適化**:
   - `#include "header.h"` は「現在ファイルの親ディレクトリ → `include-paths` → `system-include-paths`」の順で探索する。
   - `#include <header.h>` は「`system-include-paths` → `include-paths`」の順で探索する（ヘッダ名は `<` ... `>` 内トークンから復元、またはマクロ展開後に再解釈する Computed `#include` にも対応）。
   - `#ifndef GUARD ... #define GUARD ... #endif` 構造を持つヘッダは `include-guard-cache` に `(filepath . GUARD)` をキャッシュし、`GUARD` が定義済みの場合はファイルオープンや再字句解析を行わずバイパスする。

### 4.3 Dave Prosser の青塗り (`hide-set`) マクロ展開エンジン
1. **再帰展開抑止 (`hide-set` アルゴリズム)**:
   - マクロ名 `M` を展開する際、展開本体トークンおよび終端括弧との共通部分 `HS = intersect(hide-set(M), hide-set(rparen)) ∪ {M}` を算出し、`c-token-clone-with-hide-set`（#913）を用いて各トークンへ伝播する。`hide-set` に `M` を含む識別子トークンは再展開しない。
   - 展開後トークンの `<source-span>` には展開呼び出し元のスパンまたは `span-macro-origin` を記録し、診断時のマクロ呼び出し元トレーサビリティを保持する。
2. **`#` 文字列化 ＆ `##` トークン連結**:
   - `#param`: 該当実引数トークン列を未展開のまま連結（内部連続空白は単一スペースに正規化、`"` と `\` はエスケープ）して `'string-lit` `<c-token>` を生成する。
   - `lhs ## rhs`: 両辺トークンの `lexeme` を連結した文字列を `c-tokenize-string` へ通して単一トークンへ再字句解析し、`union(hide-set(lhs), hide-set(rhs))` を設定する（空引数との連結や不正貼り合わせは `C99-CPP-005` で報告）。
   - 関数形式マクロの実引数内で括弧 `(...)` がネストしていてもバランスを追跡し、トップレベルカンマ `,` のみを引数区切りとして扱う。
3. **組み込み定義済みマクロ**:
   - `__FILE__`（現スパンのファイル名文字列）、`__LINE__`（現スパンの物理行番号）、`__STDC__` (`1`)、`__STDC_HOSTED__` (`1`)、`__STDC_VERSION__` (`199901`)、`__x86_64__` (`1`)、`__LP64__` (`1`)。

### 4.4 `#if` / `#elif` コンパイル時定数整数式評価器 (CTFE #825 / 64-bit #832)
1. **前処理ルール (ISO C99 §6.10.1)**:
   - `#if` / `#elif` 条件式トークン列に対し、まず `defined ident` および `defined ( ident )` をマクロ定義有無に応じて `1` / `0` に置換する。
   - 続いて条件式残余トークン列へマクロ展開を実行し、最後に残った未定義の識別子トークン（`true` を除く `ident` / 未定義キーワード）をすべて `'int-lit 0` へ置換する。
2. **定数整数式パーサ ＆ 評価器**:
   - 優先順位順に `? :`（遅延分岐評価）、`||`・`&&`（短絡評価）、`|`・`^`・`&`（`eval_in_language.scm` の `ctfe-bitwise-*` 活用）、`==`/`!=`、`<`/`<=`/`>`/`>=`、`<<`/`>>`、`+`/`-`、`*`/`/`/`%`、単項 `+`/`-`/`~`/`!`、括弧式および整数・文字リテラルを 64bit / 任意精度整数で評価する（条件が偽のスキップ中ネストブロックは条件式を評価せず `#if`/`#endif` 深度のみカウント）。

### 4.5 セキュリティ ＆ 堅牢性設計 (Threat Vectors & Mitigations)
`diagnostic.scm`（#833）と統合した以下の診断コード体系で DoS（CWE-400）や無限ループ・ディレクトリ不正展開を防止する：
- `"C99-CPP-001"`: `#include` ネスト深度が上限（デフォルト `64`）を超過した場合（自己インクルードループ防御）、または対象ヘッダファイルが存在しない場合
- `"C99-CPP-002"`: `#error` ディレクティブに到達した場合（指定メッセージを整形表示）
- `"C99-CPP-003"`: 未閉じ `#if`/`#ifdef`/`#ifndef` ブロック、または対応する `#if` のない孤立 `#elif`/`#else`/`#endif` が検出された場合
- `"C99-CPP-004"`: `#if`/`#elif` の定数式構文エラー、またはアクティブ分岐内での 0 除算・0 剰余（`/ 0`, `% 0`）が発生した場合
- `"C99-CPP-005"`: `##` トークン連結で単一有効トークンを形成できなかった場合、またはマクロ展開ステップ総数が上限（`max-expansion-steps`, デフォルト `200000`）を超過した場合

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `#include "..."` / `#include <...>`、`#pragma once`・インクルードガード高速バイパス、`#define`（オブジェクト／関数／可変長 `...` ＆ `__VA_ARGS__`）、`#undef`、`#if`/`#elif`/`#ifdef`/`#ifndef`/`#else`/`#endif`/`defined(...)`、`#error`、`#pragma`、`#line` が ISO C99 仕様通り動作すること。
- [x] Dave Prosser の青塗り（`hide-set`）による自己参照／相互再帰マクロ抑止、`#` 文字列化、`##` トークン連結、および `__FILE__` / `__LINE__` / `__STDC_VERSION__` が正確に動作すること。
- [x] `#if` 定数式内の 64bit 演算・`? :` / `||` / `&&` 短絡評価・未定義識別子の `0` 置換・0 除算エラー検出が正常に機能すること。
- [x] Lua 5.x スタイルのネストマクロを含む C ヘッダ・ソース群の前処理結果をホストの `cc -E` オラクル出力および `#931` の `parse-c99-string` 出力と突合し、構文解析が 100% 一致・成功すること。
- [x] `ulisp/tests/test_c99_preprocessor.scm` を作成し、`make -C ulisp test_c99_preprocessor` が全件 PASS すること（および既存テストに回帰がないこと）。
