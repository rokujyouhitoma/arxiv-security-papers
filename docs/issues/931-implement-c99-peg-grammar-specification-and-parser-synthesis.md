---
ID: 931
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] PEG による C99 文法仕様 (`tools/grammars/c99.peg`) の定義およびパーサー自動合成の実装 (ID: 931)

## 1. 概要 / Summary
[[DSN-25]](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) および [[DSN-33-22]](../designs/DSN-33-22-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) §3（PEG / Packrat 構文解析フロントエンドのゼロコスト自動合成 / 基盤 Issue #894, #907, #908）に基づき、ISO/IEC 9899:1999 (C99) の完全な構文規則を CPython PEG 構文（PEP 617 準拠）で記述した文法定義ファイル `tools/grammars/c99.peg` を新設し、Pure Scheme Packrat PEG パーサージェネレータ（`ulisp/peg/`）および Python 側コンパイラ（`src/core/peg/`）の双方から C99 構文解析器を自動合成可能にする。

これにより、[[Issue #915]](915-implement-c99-parser-and-nanopass-c-ast-definitions.md) の C99 パーサー実装における手書きのボイラープレートを排除し、C 言語特有の左再帰演算子・`typedef` 文脈曖昧性（Lexer Hack）・宣言子構文を宣言的な PEG 規則と順序付き選択（Ordered Choice `|`）＋セマンティック述語として単一ソースで厳密に保守できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-11 §3.1, §3.2, §4.2 (C99 構文解析 ＆ Binding ID)](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-22 §3 (PEG 構文解析フロントエンド自動合成)](../designs/DSN-33-22-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [DSN-33-32 §2, §6.1 (Lua C コンパイルロードマップ)](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-25 (Pure Python Packrat PEG Parser Engine)](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
- 前提基盤（実装済）:
  - `#894`: Pure Scheme Packrat PEG ジェネレータ（[ulisp/peg/runtime.scm](../../ulisp/peg/runtime.scm), [ulisp/peg/compiler/parser.scm](../../ulisp/peg/compiler/parser.scm), [ulisp/peg/compiler/codegen.scm](../../ulisp/peg/compiler/codegen.scm)）
  - `#907`, `#908`: CPython PEG / PEP 617 仕様統合 ＆ `tools/grammars/*.peg` 統一
  - `#837`: 統一束縛解決 `<binding-id>`（[ulisp/compiler/binding.scm](../../ulisp/compiler/binding.scm)）
  - `#824`: `<source-span>`（[ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm)）
- 連携 Issue:
  - [[#913]](913-implement-c99-lexer-and-token-stream-with-source-span.md) (C99 Lexer ＆ `<c-token>` ストリーム)
  - [[#915]](915-implement-c99-parser-and-nanopass-c-ast-definitions.md) (C99 パーサー ＆ Nanopass `L_c_ast` 構築)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `tools/grammars/c99.peg` (新規: CPython PEG / PEP 617 準拠の C99 完全文法仕様)
- [ ] [ulisp/peg/runtime.scm](../../ulisp/peg/runtime.scm) ＆ [ulisp/peg/compiler/codegen.scm](../../ulisp/peg/compiler/codegen.scm) (必要に応じトークンストリーム入力アダプタ／外部述語フックおよび左再帰メモ化の C99 要件検証)
- [ ] `ulisp/frontend_c/parser.scm` (`c99.peg` コンパイル済みパーサー統合・`L_c_ast` 生成アダプタ)
- [ ] [ulisp/tests/test_peg_grammars.scm](../../ulisp/tests/test_peg_grammars.scm) (全文法ビルド対象リストへ `c99.peg` を追加)
- [ ] `ulisp/tests/test_c99_peg_grammar.scm` (新規: C99 左再帰式・宣言子・`typedef` 曖昧性・Lua 抜粋パーステスト)
- [ ] `tests/core/peg/compiler/test_c99_grammar.py` (新規: `src/core/peg/` 側での `c99.peg` メタ文法構文解析・生成検証)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/931-implement-c99-peg-grammar`

### 4.1 `tools/grammars/c99.peg` の文法設計（CPython PEG / PEP 617 記法）
`tools/grammars/peg_meta.peg` の仕様に従い、`rule: alt1 | alt2`、`name=expr`、`[expr]`、`sep.rule+` 形式で ISO C99 文法を以下の 4 層で定義する：
1. **Lexical ＆ Primary Rules**:
   - `identifier`（キーワード除外述語 `!keyword` 付き）、`constant`（整数・浮動小数点・文字）、`string_literal`（隣接文字列リテラル連結 `STRING+`）、`primary_expr`。
2. **Left-Recursive Expressions & 15段演算子優先順位**:
   - `postfix_expr`: 左再帰ルールとして `postfix_expr '[' expr ']'`、`postfix_expr '(' [arg_expr_list] ')'`、`postfix_expr '.' identifier`、`postfix_expr '->' identifier`、`postfix_expr ('++' | '--')`、および C99 複合リテラル `'(' type_name ')' '{' initializer_list [','] '}'` を記述。`ulisp/peg/runtime.scm` の Warth 左再帰シード成長（`parse-ctx-lr-detected?`, `parse-ctx-clear-lr-dependent-memo!`）により左結合を $O(N)$ で解析。
   - `unary_expr`: `'sizeof' '(' type_name ')'` を `'sizeof' unary_expr` より先に置く順序付き選択（Ordered Choice）で曖昧性を解決。
   - `cast_expr`（`'(' type_name ')' cast_expr | unary_expr`）、`multiplicative_expr` 〜 `assignment_expr` 〜 `expr`（カンマ式）。
3. **Declarations, Struct/Union/Enum ＆ Declarators**:
   - `declaration_specifiers`: 記憶域クラス（`typedef`, `extern`, `static`, `auto`, `register`）、型指定子（`void`, `char`, ..., `struct_or_union_specifier`, `enum_specifier`, `typedef_name`）、型修飾子（`const`, `restrict`, `volatile`）、`inline`。
   - `declarator`, `direct_declarator`, `abstract_declarator`: ポインタ `*` 修飾子、配列 `[static ...]`、関数引数リスト `(parameter_type_list)`、関数ポインタ `(*name)(args)` をサポート。
   - `initializer`, `designation`: C99 指示付き初期化子（`.field = val`, `[index] = val`）。
4. **Statements & Translation Unit**:
   - `compound_stmt`: C99 のブロック内「宣言と文の任意混在」（`block_item*`）。
   - `selection_stmt`: `'if' '(' expr ')' stmt ['else' stmt]`（PEG の貪欲最長一致により Dangling-else を内側の `if` へ自動結合）、`'switch' '(' expr ')' stmt`。
   - `iteration_stmt`: `'while'`, `'do' ... 'while'`, `'for' '(' (declaration | [expr] ';') [expr] ';' [expr] ')' stmt`（C99 `for`-init 宣言対応）。
   - `jump_stmt`: `'goto'`, `'continue'`, `'break'`, `'return'`。
   - `translation_unit`: `external_declaration+`（関数定義および大域宣言）。

### 4.2 `typedef` 文脈曖昧性 (Lexer Hack) の PEG 解決プロトコル
- `typedef` 宣言をパースした際、`binding.scm`（#837）およびスコープ表へ該当識別子を `typedef` 名として登録する。
- `typedef_name` ルールはセマンティック述語（コンテキストの現行スコープ表を参照し、該当識別子が `typedef` として束縛されているか判定）を通じてのみ成功する。
- 逆に、宣言指定子の構文内では「既に型指定子が1つ出現済みで、かつ識別子が `typedef` かつ宣言子名として再定義（シャドウイング）されるケース（例: `typedef int T; void f(int T);`）」を正しく識別できるよう PEG 順序付き選択を設計する。

### 4.3 `ulisp/peg/` 統合と `L_c_ast` 構築アダプタ
- `parse-peg-grammar` および `compile-peg-grammar` / `compile-peg-file` で `tools/grammars/c99.peg` をロードし、Pure Scheme 二重継続（CPS）パーサーを生成する。
- 生成パーサーが構築する具象構文結果へ `#913` の `<c-token>` から取得した `<source-span>` を伝播させ、#915 の `L_c_ast` S式ノードへマッピングする。

### 4.4 セキュリティ ＆ 堅牢性設計 (Security & Robustness)
1. **再帰深度によるスタック枯渇防御 (DoS Mitigation)**:
   - 極端に深くネストされた括弧・ポインタ宣言・三項演算子入力に対し、`ulisp/peg/runtime.scm` の `<parse-context>` が持つ `max-depth` 上限（`parse-ctx-max-depth`, デフォルト 10000 等）を厳守し、超過時は安全に失敗・診断報告してプロセス強制終了を防止する。
2. **バックトラック爆発の排除**:
   - 宣言 vs 式文（`statement`）やキャスト `(T)x` vs 関数呼出 `(f)(x)` で指数的バックトラックが起きないよう、共通プレフィックスの括り出しとカット演算子 `~`・Packrat メモ化を適用する。
3. **不正構文の正確な位置報告**:
   - パース失敗時には `<parse-context>` の `max-pos` および `expected` トークン集合から最も進んだ誤り位置の `<source-span>` を復元し、`diagnostic.scm`（#833）経由で報告する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `tools/grammars/c99.peg` が `parse-peg-grammar` / `compile-peg-grammar`（Pure Scheme `ulisp/peg/`）および `src/core/peg/`（Python 側コンパイラ）の両方でエラーなくコンパイル・パーサー合成できること。
- [ ] `ulisp/tests/test_peg_grammars.scm` の対象文法リストに `c99.peg` が含まれ、ビルド検証が PASS すること。
- [ ] C99 の左再帰式、複雑な関数ポインタ宣言子（`int (*(*signal(int, void (*)(int)))(int))` 相当）、`typedef` シャドウイング、`sizeof(type)` vs `sizeof expr`、C99 指示付き初期化子、`for (int i=0; ...)` が正しく構文解析されること。
- [ ] プリプロセス済みの Lua 5.x C ソースコード抜粋（`TValue` 構造体、`luaV_execute` 相当 `switch`/`goto`、`lua_CFunction`）を `c99.peg` 合成パーサーで構文解析できること。
- [ ] `ulisp/tests/test_c99_peg_grammar.scm` および `tests/core/peg/compiler/test_c99_grammar.py` が全件 PASS すること。
