---
ID: 913
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-21
---

# [FEAT/ENH] C99 字句解析器 (Lexer) および Source Span 付きトークンストリームの実装 (ID: 913)

## 1. 概要 / Summary
C99 ソースコードからプリプロセス用トークン列（pp-tokens）および構文解析用トークン列を切り出し、すべてのトークンへ `DSN-33-11` §3.1 規定の `<source-span>` メタデータを不可分に付与する純粋 Scheme 製 C99 字句解析器（`ulisp/frontend_c/lexer.scm`）を実装する。

本モジュールは、[[DSN-33-32] Lua (C言語実装) コンパイルロードマップ](../../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md) の **Phase S2（Task T1）** における最上流コンポーネントであり、後続の C99 プリプロセッサ（[[#914]](../914-implement-pure-scheme-c99-preprocessor-cpp.md)）および完了済みの PEG C99 パーサー基盤（[[#931]](931-implement-c99-peg-grammar-specification-and-parser-synthesis.md) / 後続 [[#915]](../915-implement-c99-parser-and-nanopass-c-ast-definitions.md)）の共通入力データ構造 `<c-token>` を規定する。なお、字句パターン本体は [tools/grammars/c99.peg](../../../tools/grammars/c99.peg) の `c99_raw_token` / `c99_punctuator` 規則として宣言的に定義し、`(c99-peg-parser 'c99_raw_token)` により PEG パーサージェネレータから自動合成する構成を採用した（【案1】）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §2, §6.1 (Lua C コンパイル ＆ セルフホスト)](../../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §3.1, §3.4, §3.5, §4.2 (多言語フロントエンド共通基盤)](../../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
- 前提基盤（実装済）:
  - `#824`: `<source-span>` 定義・操作 API（[ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm)）
  - `#833`: `<diagnostic>` 診断レポート（[ulisp/compiler/diagnostic.scm](../../../ulisp/compiler/diagnostic.scm)）
  - `#832`: 純粋 Scheme 数値塔（[ulisp/lib/bignum.scm](../../../ulisp/lib/bignum.scm), [ulisp/lib/ieee754.scm](../../../ulisp/lib/ieee754.scm)）
  - `#931`: C99 PEG 文法仕様 ＆ パーサー自動合成基盤（[tools/grammars/c99.peg](../../../tools/grammars/c99.peg), [ulisp/frontend_c/parser.scm](../../../ulisp/frontend_c/parser.scm), [[#931]](931-implement-c99-peg-grammar-specification-and-parser-synthesis.md)）
- 後続連携 Issue:
  - [[#914]](../914-implement-pure-scheme-c99-preprocessor-cpp.md) (C99 プリプロセッサ)
  - [[#915]](../915-implement-c99-parser-and-nanopass-c-ast-definitions.md) (C99 パーサー ＆ C-AST)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [tools/grammars/c99.peg](../../../tools/grammars/c99.peg) (`c99_punctuator`, `c99_raw_token` 規則および数値末尾 `!ident_cont` ガード追加 — 計 97 ルール)
- [x] [ulisp/frontend_c/lexer.scm](../../../ulisp/frontend_c/lexer.scm) (新規: `<c-token>` レコード、PEG 合成トークナイザ連携、リテラルデコード、CPP/PEG 連携ブリッジ、診断レポート)
- [x] [ulisp/tests/test_c99_lexer.scm](../../../ulisp/tests/test_c99_lexer.scm) (新規: 75 項目の単体テスト・境界値・セキュリティ異常系・#931 パーサー往復結合テスト)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`test_c99_lexer` ターゲットおよび `test` 集約への登録)
- 既存連携先（参照のみ / 変更不要）:
  - [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) (`make-source-span`, `next-source-span-id!`, `span-file`, `span-start-line`, `span-start-col`, `span-end-line`, `span-end-col`)
  - [ulisp/compiler/diagnostic.scm](../../../ulisp/compiler/diagnostic.scm) (`make-diagnostic`, `report-diagnostic`, `emit-diagnostic-error`, `diagnostic-register-source-string!`)
  - [ulisp/frontend_c/parser.scm](../../../ulisp/frontend_c/parser.scm) (`c99-peg-parser`, `parse-c99-string`, `parse-c99-expr-string` — #931 で実装済み)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/913-implement-c99-lexer-and-token-stream`

### 4.1 データ構造と公開インターフェース (`ulisp/frontend_c/lexer.scm`)
1. **`<c-token>` レコード定義**（SRFI 9 `define-record-type` 使用）:
   ```scheme
   (define-record-type <c-token>
     (make-c-token kind lexeme value span at-bol? has-leading-space? hide-set)
     c-token?
     (kind              c-token-kind)
     (lexeme            c-token-lexeme)
     (value             c-token-value)
     (span              c-token-span)
     (at-bol?           c-token-at-bol?)
     (has-leading-space? c-token-has-leading-space?)
     (hide-set          c-token-hide-set))
   ```
   - `kind` ごとの `value` 正規化仕様:
     - `'keyword` → シンボル（例: `'int`, `'typedef`, `'_Bool`）
     - `'ident` → シンボル（例: `'lua_State`）
     - `'int-lit` → 正確整数（exact integer、8/10/16進デコード結果）
     - `'float-lit` → 非正確実数（inexact flonum、または解析用表現）
     - `'char-lit` → 文字コード整数（integer char code、エスケープ・8/16進展開後）
     - `'string-lit` → デコード済み文字列（string、エスケープ・8/16進展開後）
     - `'punct` → 演算子/区切り子文字列（string、例: `"<<="`, `"->"`, `";"`）
     - `'eof` → `'eof`
   - `hide-set`: C プリプロセッサ（#914）の Blue-painted 再帰展開抑止用に初期値 `'()` を保持。
2. **公開手続き**:
   - `(c-tokenize-string src-text filename)` -> `<c-token>` のリスト（末尾は `'eof` トークン）
   - `(c-tokenize-file filepath)` -> ファイル読み込み＋`diagnostic-register-source-string!` 登録後にトークン化
   - `(c-token-is-keyword? tok kw-sym)` / `(c-token-is-punct? tok punct-str)`
   - `(c-token-clone-with-span tok new-span)` / `(c-token-clone-with-hide-set tok new-hide-set)`
3. **`#914` (CPP) ＆ `#931` / `#915` (`ulisp/frontend_c/parser.scm`) 連携ブリッジ**:
   - `(c-concat-adjacent-string-tokens tokens)`: Translation Phase 6 に従い隣接する `'string-lit` トークンを結合（`"a" "b"` -> `"ab"`）し、先頭トークンの開始位置から末尾トークンの終了位置を覆う統合 `<source-span>` を生成する。
   - `(c-tokens->source-string tokens)`: `<c-token>` リストから改行（`at-bol?`）・空白区切り（`has-leading-space?` や隣接識別子同士の接着回避）を保った正規化 C99 ソース文字列を再構築し、`ulisp/frontend_c/parser.scm`（#931）の `(parse-c99-string ...)` へシームレスに引き渡す。

### 4.2 字句解析パイプライン詳細（3 フェーズ構成）
1. **フェーズ 1（物理行結合 ＆ 位置追跡）**:
   - スキャンカーソルにおいて CRLF（`\r\n`）の正規化および行継続シーケンス（`\\\n` / `\\\r\n`）を透過的に結合しつつ、元の物理ファイル行・列番号を正確に維持して `make-source-span` を構築する。
2. **フェーズ 2（空白・コメント処理 ＆ CPP フラグ記録）**:
   - 空白（Space, Tab, FormFeed, VerticalTab）および改行（`\n`）を走査し、直前が改行であったかを `at-bol?`、直前に 1 文字以上の空白またはコメントが存在したかを `has-leading-space?` に記録する（`#define FOO(x)` と `#define FOO (x)` の識別に必須）。
   - `//` 単一行コメントおよび `/* ... */` ブロックコメントを 1 つの空白相当としてスキップする。
3. **フェーズ 3（トークン切り出し ＆ リテラル正規化）**:
   - **C99 全 37 キーワード判定**: `auto`, `break`, `case`, `char`, `const`, `continue`, `default`, `do`, `double`, `else`, `enum`, `extern`, `float`, `for`, `goto`, `if`, `inline`, `int`, `long`, `register`, `restrict`, `return`, `short`, `signed`, `sizeof`, `static`, `struct`, `switch`, `typedef`, `union`, `unsigned`, `void`, `volatile`, `while`, `_Bool`, `_Complex`, `_Imaginary` を `'keyword`（値はそのシンボル）へ分類。それ以外の `[A-Za-z_][A-Za-z0-9_]*` は `'ident` へ分類。
   - **演算子・区切り子 (`'punct`)**: 最長一致原則（Maximal Munch）で 3文字（`<<=`, `>>=`, `...`）、2文字（`->`, `++`, `--`, `<<`, `>>`, `<=`, `>=`, `==`, `!=`, `&&`, `||`, `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `##`, `<:`, `:>`, `<%`, `%>`, `%:`）、および 1文字演算子/記号を切り出す。
   - **整数・浮動小数点リテラル**:
     - `0x`/`0X`（16進）、`0` 先頭（8進）、10進整数、および型サフィックス（`u`/`U`, `l`/`L`, `ll`/`LL` の組み合わせ）を解析。
     - 10進浮動小数点（`.` または `e`/`E` 指数部付き）および C99 16進浮動小数点（`0x...p±...`）、`f`/`F`/`l`/`L` サフィックスを `'float-lit` として切り出す（前処理数値トークン `pp-number` の受理ルールにも対応）。
   - **文字・文字列リテラル**: `'...'` および `"..."`（`L"..."` ワイド文字リテラルプレフィックス含む）のエスケープシーケンス（`\n`, `\t`, `\r`, `\0`, `\'`, `\"`, `\\`, `\a`, `\b`, `\f`, `\v`, `\?`, 8進 `\OOO`, 16進 `\xHH`）をデコードして `value` へ格納する。

### 4.3 セキュリティ ＆ 堅牢性設計 (Threat Vectors & Mitigations)
1. **未終端リテラル・コメントによる無限ループ／過剰読み込み防止（診断コード標準化）**:
   - 診断コード体系を `diagnostic.scm`（#833）と統合し、以下の位置情報付き診断エラー（`make-diagnostic` ＋ `report-diagnostic` ＋ 例外送出）を報告して確実に走査を停止する：
     - `"C99-LEX-001"`: ブロックコメント `/*` が閉じる前に EOF に到達した場合
     - `"C99-LEX-002"`: 文字リテラル `'...'` または文字列リテラル `"..."` が閉じる前に EOF または生の改行に到達した場合
     - `"C99-LEX-003"`: 不正文字、NUL バイト (`\0`)、不正なエスケープ／数値リテラル形式（例: 不完全な `0x`、指数部欠損 `1e+` 等）を検出した場合
2. **リソース枯渇・異常長入力への境界ガード**:
   - 極端に長いトークンや不正な制御文字・NUL バイト (`\0`) がソース文字列中に混入した場合も、文字列長境界チェック（`< len`）により範囲外参照を起こさず安全に字句エラーとして検出する。
3. **診断出力時のサニタイズ**:
   - ソースファイル名や不正文字を含む行の診断表示は `diagnostic.scm` のサニタイザ経由で行い、端末エスケープインジェクション等を防止する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/frontend_c/lexer.scm` が C99 全 37 キーワード、3/2/1文字演算子、10/8/16進整数リテラル＋サフィックス、10/16進浮動小数点リテラル、文字・文字列リテラルとエスケープを仕様通りの `kind` / `value` へ正確にトークン化できること。
- [x] 行継続（`\\\n`）をまたぐトークンの物理行・列番号が `span` に正しく記録され、`at-bol?` および `has-leading-space?` が正確に識別されること。
- [x] `(c-concat-adjacent-string-tokens tokens)` による隣接文字列リテラル連結（Merged Span 付き）、および `(c-tokens->source-string tokens)` → `(parse-c99-string ...)`（#931）の往復結合パースが正常に動作すること。
- [x] 未終端コメント `/*`（`C99-LEX-001`）、未終端文字/文字列リテラル（`C99-LEX-002`）、不正文字・不正数値リテラル（`C99-LEX-003`）に対して無限ループせず `diagnostic.scm` による Span 付きエラー報告を行うこと。
- [x] `ulisp/tests/test_c99_lexer.scm` を作成し、`ulisp/Makefile` の `make test_c99_lexer` が全件 PASS すること（および既存の `make test` に回帰がないこと）。
