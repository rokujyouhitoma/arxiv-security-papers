---
ID: 915
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] C99 構文解析器 (Parser) および Nanopass C-AST 言語定義・Lexer Hack 解消の実装 (ID: 915)

## 1. 概要 / Summary
[[#914]](closed/914-implement-pure-scheme-c99-preprocessor-cpp.md) で前処理された C99 `<c-token>` ストリーム（および文字列入力）を、[[#931]](closed/931-implement-c99-peg-grammar-specification-and-parser-synthesis.md) で構築済みの PEG 文法（[tools/grammars/c99.peg](../../tools/grammars/c99.peg)）＆構文解析器（[ulisp/frontend_c/parser.scm](../../ulisp/frontend_c/parser.scm)）を用いて構文解析し、正式な Nanopass 言語定義 `L_c_ast`（`ulisp/frontend_c/c_lang.scm`）へ正規化・適合検証するパイプラインを実装する（Phase S2 / Task T3）。Issue #837（Binding ID・統一スコープ管理）と協調して C 言語特有の `typedef` 曖昧性（Lexer Hack）をクリーンに解消し、後段の意味解析（`#916`）へ完全な `L_c_ast` を引き渡す。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §2, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §3.2, §4.2](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-22 §3 (PEG 構文解析自動合成)](../designs/DSN-33-22-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
- 前提基盤（実装済）:
  - `#837`: 統一束縛解決 `<binding-id>`（[ulisp/compiler/binding.scm](../../ulisp/compiler/binding.scm)）
  - `#824`: `<source-span>`（[ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm)）
  - `#833`: `<diagnostic>` 診断レポート（[ulisp/compiler/diagnostic.scm](../../ulisp/compiler/diagnostic.scm)）
  - `#913`: PEG 合成型 C99 Lexer（[ulisp/frontend_c/lexer.scm](../../ulisp/frontend_c/lexer.scm), [[#913]](closed/913-implement-c99-lexer-and-token-stream-with-source-span.md)）
  - `#914`: 純粋 Scheme C99 CPP（[ulisp/frontend_c/preprocessor.scm](../../ulisp/frontend_c/preprocessor.scm), [[#914]](closed/914-implement-pure-scheme-c99-preprocessor-cpp.md)）
  - `#931`: C99 PEG 文法 ＆ パーサー合成基盤（[tools/grammars/c99.peg](../../tools/grammars/c99.peg), [ulisp/frontend_c/parser.scm](../../ulisp/frontend_c/parser.scm), [[#931]](closed/931-implement-c99-peg-grammar-specification-and-parser-synthesis.md)）
- 後続連携 Issue:
  - [[#916]](916-implement-c99-sema-core-and-integer-subset-lir-lowering.md) (C99 Sema Core ＆ 整数 Lowering)
  - [[#917]](917-implement-c-compiler-driver-and-host-ld-integration.md) (`c_driver.scm`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/c_lang.scm` (新規: `define-language L_c_ast` および `L_c_typed` 用 `<c-type>` / `verify-c99-ast` スキーマ定義)
- [ ] [ulisp/frontend_c/parser.scm](../../ulisp/frontend_c/parser.scm) (拡張: `#931` 基盤を正式 `L_c_ast` 生成・`parse-c99-tokens`・`parse-c99-preprocessed-string`・`parse-c99-file` へ拡張)
- [ ] `ulisp/tests/test_c99_parser.scm` (新規: `L_c_ast` Nanopass 検証・CPP 連携・`typedef`/タグ/ラベル名前空間 ＆ シャドウイングテスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_parser` ターゲットおよび `test` 集約への登録)
- 既存連携先（参照のみ）:
  - [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (`define-language`, `define-pass`, `verify-language`)
  - [ulisp/compiler/binding.scm](../../ulisp/compiler/binding.scm) (`make-scope-manager`, `scope-manager-push!`, `scope-manager-define!`, `scope-manager-typedef-name?`)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/915-implement-c99-parser-and-c-ast`

### 4.1 Nanopass 言語定義 (`ulisp/frontend_c/c_lang.scm`)
1. **`define-language L_c_ast`**:
   - **Terminals**: `sym` (`symbol?`), `str` (`string?`), `int` (`integer?`), `flt` (`real?`), `bid` (`integer?` or `#f`), `span` (`source-span?`).
   - **Nonterminals ＆ 構文要素**:
     - `TranslationUnit`: `(c-translation-unit ExternalDecl ...)`
     - `ExternalDecl`: `(c-fn-def sym DeclSpec Declarator (param ...) Stmt)` | `(c-decl DeclSpec (InitDecl ...))` | `(c-typedef DeclSpec (InitDecl ...))`
     - `TypeSpec` / `DeclSpec`: `void`, `char`, `short`, `int`, `long`, `float`, `double`, `signed`, `unsigned`, `_Bool`, `_Complex`, `(c-struct sym FieldDecl ...)`, `(c-union sym FieldDecl ...)`, `(c-enum sym Enumerator ...)`, `(c-typedef-name sym bid)`
     - `Declarator`: `(c-decl-id sym bid)`, `(c-ptr-declarator quals inner)`, `(c-arr-declarator inner size-expr)`, `(c-fn-declarator inner params)`
     - `Stmt`: `(c-block BlockItem ...)`, `(c-if cond then else?)`, `(c-switch cond body)`, `(c-case val stmt)`, `(c-default stmt)`, `(c-while cond body)`, `(c-do-while body cond)`, `(c-for init cond step body)`, `(c-goto sym)`, `(c-label sym stmt)`, `(c-continue)`, `(c-break)`, `(c-return expr?)`, `(c-expr-stmt expr?)`
     - `Expr`: `(c-var-ref sym bid)`, `(c-const raw-str)`, `(c-str str)`, `(c-unop op expr)`, `(c-binop op lhs rhs)`, `(c-assign op lhs rhs)`, `(c-ternary cond t e)`, `(c-call fn args ...)`, `(c-index arr idx)`, `(c-member obj field arrow?)`, `(c-cast type expr)`, `(c-sizeof-type type)`, `(c-sizeof-expr expr)`, `(c-compound-lit type inits)`
2. **`verify-c99-ast`**:
   - 全ノードが `L_c_ast` の生成規則と `<source-span>`（#824）不変条件を満たすことを検証する。

### 4.2 パーサー公開インターフェース ＆ CPP/PEG 統合 ([ulisp/frontend_c/parser.scm](../../ulisp/frontend_c/parser.scm))
1. **既存 `#931` パーサーの正規化**:
   - `expr` / `postfix_expr` / `unary_expr` / `cast_expr` / `declaration` 等の構文アクションを統一し、生 CST 断片ではなく正規化された `L_c_ast` S式（演算子優先順位・左結合木、`c-for` の 4要素分解、`c-init-decl` 等）を出力する。
2. **公開 API**:
   - `(parse-c99-tokens tokens . maybe-filename)`: 前処理済み `<c-token>` 列（#913/#914）を `c-concat-adjacent-string-tokens` ＆ `c-tokens->source-string` 経由で構文解析する。
   - `(parse-c99-preprocessed-string src-text . rest)`: `cpp-preprocess-string`（#914）＋ `parse-c99-tokens` を一気通貫で実行。
   - `(parse-c99-file filepath . maybe-cpp-ctx)`: ファイル読込 → CPP → `L_c_ast` を構築。

### 4.3 `typedef` / タグ / ラベル名前空間とセキュリティ設計
1. **4 名前空間の厳密分離 (`binding.scm` #837)**:
   - 通常識別子・`typedef`（`ordinary`/`typedef`）、`struct`/`union`/`enum` タグ（`tag-struct`/`tag-union`/`tag-enum`）、`label`（関数スコープ）、メンバ空間を衝突なく管理し、`typedef int T; void f(int T) { T * 2; }` 等のシャドウイングを 100% 識別。
2. **診断コード体系 (`diagnostic.scm` #833)**:
   - `"C99-PARSE-001"`: 構文エラー（最長到達位置 `max-pos` と期待トークン表示）
   - `"C99-PARSE-002"`: `typedef` 再定義または無効な宣言指定子の組み合わせ
   - `"C99-PARSE-003"`: 再帰深度上限超過・`L_c_ast` 構造検証違反

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `L_c_ast` が `ulisp/frontend_c/c_lang.scm` で `define-language` 定義され、`verify-c99-ast` が全 AST ノードで `<source-span>` と `<binding-id>` の整合性を検証できること。
- [ ] `parse-c99-preprocessed-string` / `parse-c99-tokens` により、CPP（#914）展開済みの Lua 5.x C コード断片がそのまま正規 `L_c_ast` へ変換されること。
- [ ] `typedef` と同名ローカル変数/仮引数/タグのシャドウイングおよび複雑宣言子（`int (*(*fp)(int))[4]`, `sizeof(type)` vs `(type)x`）がエラーなく正規 AST 化されること。
- [ ] `ulisp/tests/test_c99_parser.scm` を作成し、`make -C ulisp test_c99_parser` が全件 PASS すること。
