---
ID: 913
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] C99 字句解析器 (Lexer) および Source Span 付きトークンストリームの実装 (ID: 913)

## 1. 概要 / Summary
C99 ソースコードからプリプロセス用トークン列（pp-tokens）および構文解析用トークン列を切り出し、すべてのトークンへ `DSN-33-11` §3.1 規定の `<source-span>` メタデータを不可分に付与する純粋 Scheme 製 C99 字句解析器（`ulisp/frontend_c/lexer.scm`）を実装する。

本モジュールは、[[DSN-33-32] Lua (C言語実装) コンパイルロードマップ](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md) の **Phase S2（Task T1）** における最上流コンポーネントであり、後続の C99 プリプロセッサ（[[#914]](914-implement-pure-scheme-c99-preprocessor-cpp.md)）および PEG C99 パーサー（[[#931]](931-implement-c99-peg-grammar-specification-and-parser-synthesis.md) / [[#915]](915-implement-c99-parser-and-nanopass-c-ast-definitions.md)）の共通入力データ構造 `<c-token>` を規定する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §2, §6.1 (Lua C コンパイル ＆ セルフホスト)](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §3.1, §3.4, §3.5, §4.2 (多言語フロントエンド共通基盤)](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
- 前提基盤（実装済）:
  - `#824`: `<source-span>` 定義・操作 API（[ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm)）
  - `#833`: `<diagnostic>` 診断レポート（[ulisp/compiler/diagnostic.scm](../../ulisp/compiler/diagnostic.scm)）
  - `#832`: 純粋 Scheme 数値塔（[ulisp/lib/bignum.scm](../../ulisp/lib/bignum.scm), [ulisp/lib/ieee754.scm](../../ulisp/lib/ieee754.scm)）
- 後続連携 Issue:
  - [[#914]](914-implement-pure-scheme-c99-preprocessor-cpp.md) (C99 プリプロセッサ)
  - [[#931]](931-implement-c99-peg-grammar-specification-and-parser-synthesis.md) (C99 PEG 文法)
  - [[#915]](915-implement-c99-parser-and-nanopass-c-ast-definitions.md) (C99 パーサー ＆ C-AST)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/lexer.scm` (新規: `<c-token>` レコード、C99 字句解析エンジン、エラー診断連携)
- [ ] `ulisp/tests/test_c99_lexer.scm` (新規: 単体テスト・境界値・セキュリティ異常系テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_lexer` ターゲットおよび `test` 集約への登録)
- 既存連携先（参照のみ / 変更不要）:
  - [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (`make-source-span`, `next-source-span-id!`, `span-file`, `span-start-line`, `span-start-col`, `span-end-line`, `span-end-col`)
  - [ulisp/compiler/diagnostic.scm](../../ulisp/compiler/diagnostic.scm) (`make-diagnostic`, `report-diagnostic`, `emit-diagnostic-error`, `diagnostic-register-source-string!`)

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
   - `kind`: `'keyword`, `'ident`, `'int-lit`, `'float-lit`, `'char-lit`, `'string-lit`, `'punct`, `'eof`
   - `hide-set`: C プリプロセッサ（#914）の Blue-painted 再帰展開抑止用に初期値 `'()` を保持。
2. **公開手続き**:
   - `(c-tokenize-string src-text filename)` -> `<c-token>` のリスト（末尾は `'eof` トークン）
   - `(c-tokenize-file filepath)` -> ファイル読み込み＋`diagnostic-register-source-string!` 登録後にトークン化
   - `(c-token-is-keyword? tok kw-sym)` / `(c-token-is-punct? tok punct-str)`
   - `(c-token-clone-with-span tok new-span)` / `(c-token-clone-with-hide-set tok new-hide-set)`

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
1. **未終端リテラル・コメントによる無限ループ／過剰読み込み防止**:
   - ブロックコメント `/*` や文字・文字列リテラルが閉じる前に EOF（または文字列中の生の改行）に到達した場合、確実にループを中断し、`make-source-span` と `emit-diagnostic-error`（またはエラー結果）で明確な位置情報付きエラーを報告する。
2. **リソース枯渇・異常長入力への境界ガード**:
   - 極端に長いトークンや不正な制御文字・NUL バイト (`\0`) がソース文字列中に混入した場合も、文字列長境界チェック（`< len`）により範囲外参照を起こさず安全に字句エラーとして検出する。
3. **診断出力時のサニタイズ**:
   - ソースファイル名や不正文字を含む行の診断表示は `diagnostic.scm` のサニタイザ経由で行い、端末エスケープインジェクション等を防止する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/frontend_c/lexer.scm` が C99 全 37 キーワード、3/2/1文字演算子、10/8/16進整数リテラル＋サフィックス、10/16進浮動小数点リテラル、文字・文字列リテラルとエスケープを正確にトークン化できること。
- [ ] 行継続（`\\\n`）をまたぐトークンの物理行・列番号が `span` に正しく記録され、`at-bol?` および `has-leading-space?` が正確に識別されること。
- [ ] 未終端コメント `/*`、未終端文字列 `"abc`、不正文字に対して無限ループせず `diagnostic.scm` による Span 付きエラー報告を行うこと。
- [ ] `ulisp/tests/test_c99_lexer.scm` を作成し、`ulisp/Makefile` の `make test_c99_lexer` が全件 PASS すること（および既存の `make test` に回帰がないこと）。
