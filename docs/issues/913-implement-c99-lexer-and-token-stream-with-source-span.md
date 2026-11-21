---
ID: 913
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C99 字句解析器 (Lexer) および Source Span 付きトークンストリームの実装 (ID: 913)

## 1. 概要 / Summary
C99 ソースコードおよびプリプロセッサマクロ展開前の前処理トークン列（pp-tokens）を正確に切り出し、すべてのトークンへ `DSN-33-11` §3.1 規定の `<source-span>` メタデータを付与する純粋 Scheme 製 C99 字句解析器（`ulisp/frontend_c/lexer.scm`）を実装する。Lua 5.x の C ソースコード群（Step S2 / T1）を処理するための最初段フロントエンドコンポーネントである。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 (Lua C コンパイル ＆ セルフホスト)](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 (多言語フロントエンド共通基盤)](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
- 前提基盤 Issue: #824 (Source Span), #833 (Diagnostic Reporter), #832 (純粋 Scheme 数値塔)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/lexer.scm` (新規: C99 トークナイザ & pp-token ストリーム)
- [ ] `ulisp/tests/test_c99_lexer.scm` (新規: 字句解析ユニットテスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (テストターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/913-implement-c99-lexer-and-token-stream`

1. C99 前処理トークンレコード `<c-token>`（`kind`, `lexeme`, `span`, `at-bol?`, `has-leading-space?`, `hide-set`）を定義する。
2. キーワード・識別子・数値定数（10進/8進/16進、整数サフィックス `U`/`L`/`LL`、10進/16進浮動小数点リテラル）、文字・文字列リテラル（エスケープシーケンス `\\x`, `\\u`, `\\U`, `\n` 等）、マルチバイト演算子（`<<=`, `>>=`, `->`, `##`, `...` 等）、および行継続（`\` + 改行）・コメント除去（`//`, `/* ... */`）を実装する。
3. すべてのトークンに `make-source-span` を付与し、構文エラー・不正文字検知時に `diagnostic.scm`（#833）へ正確な位置情報を渡せるようにする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/frontend_c/lexer.scm` が C99 全キーワード・演算子・整数/浮動小数点・文字列リテラルを正しくトークン化できること。
- [ ] プリプロセッサ向けの行頭フラグ (`at-bol?`) と空白前置フラグ (`has-leading-space?`) が正しく保持されること。
- [ ] `ulisp/tests/test_c99_lexer.scm` が全件 PASS し、既存テストに回帰がないこと。
