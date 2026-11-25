---
ID: 949
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] `tools/grammars/c99.peg` の静的 `.scm` パーサー生成移行 (`generated_c99_parser.scm`) と C99 フック統合・CPS 全廃 (ID: 949)

## 1. 概要 / Summary

現行の [parser.scm](../../ulisp/frontend_c/parser.scm)（`compile-c99-rule-getter`）は起動時に [c99.peg](../../tools/grammars/c99.peg)（またはキャッシュ AST）を読み込み、`fast-leaf`・10 段 Pratt 式・`decorate-c99-rule`（約 900 行の AST 構築・`typedef_name` スコープ判定）と組み合わせて二重 CPS クロージャ網を動的構築している。

[#948](closed/948-implement-direct-style-static-scheme-peg-parser-generator-backend.md) の Direct-Style `.scm` 生成バックエンドに外部フック仕様（`#:overrides`, `#:decorators`, `#:extra-params '(env)`, ルール別メモ化制御）を導入し、`tools/grammars/c99.peg` から `ulisp/frontend_c/generated_c99_parser.scm` をビルド時 AOT 生成へ移行する。これにより C99 パース時の CPS クロージャ大量確保と `c99.peg` 実行時読込・構築コスト（[#932](932-build-native-aot-ulisp-cc-compiler-driver-binary.md) Gap 4）を根本解消し、`ulisp-cc` ネイティブ AOT の高速化・省ヒープ化を実現する（優先度・効果見込みは [#945](closed/945-profile-lua-547-c99-build-phase-breakdown-on-linux.md) の計測結果も踏まえて最終判断する）。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [DSN-33-11](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-32](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [Issue #931](closed/931-implement-c99-peg-grammar-specification-and-parser-synthesis.md)
  - [Issue #932](932-build-native-aot-ulisp-cc-compiler-driver-binary.md)
  - [Issue #945](closed/945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)
  - [Issue #948](closed/948-implement-direct-style-static-scheme-peg-parser-generator-backend.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] `ulisp/peg/compiler/emit_scheme.scm` (`overrides`/`decorators`/`extra-params`/選択メモ化フック対応)
- [ ] [parser.scm](../../ulisp/frontend_c/parser.scm) (動的 `compile-c99-rule-getter` からの移行・フック定義の分離)
- [ ] `ulisp/frontend_c/generated_c99_parser.scm` (新規: `c99.peg` からビルド時自動生成される静的 Direct-Style パーサー)
- [ ] [c99.peg](../../tools/grammars/c99.peg)
- [ ] [test_c99_peg_grammar.scm](../../ulisp/tests/test_c99_peg_grammar.scm)
- [ ] [Makefile](../../ulisp/Makefile) (`generated_c99_parser.scm` 生成ターゲット・鮮度検証)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/949-migrate-c99-parser-to-aot-generated-scheme`

1. `ulisp/peg/compiler/emit_scheme.scm` に `overrides`（`fast-leaf`・Pratt パーサー差し替え）、`decorators`（`decorate-c99-rule` ラップ）、`extra-params`（`env` 引数伝播）、およびルール単位のメモ化除外（`typedef_name` 等）フックを追加する。
2. `tools/grammars/c99.peg` から `ulisp/frontend_c/generated_c99_parser.scm` をビルド時生成し、`ulisp/frontend_c/parser.scm` の動的構築パスを置き換える。
3. C99 テストスイートおよび Lua 5.4.7 ビルド・`all.lua` の完全一致とパース時間・ヒープ改善を検証する（詳細手順は `polish-issue` にて精緻化する）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `generated_c99_parser.scm` を用いて C99 テストスイートおよび Lua 5.4.7 ビルド・`all.lua` が現行版と同一結果で完走すること。
- [ ] 実行時の `c99.peg` 読み込み・クロージャ網構築および CPS 継続確保が解消され、パース時間・ヒープ使用量の改善が確認できること（詳細ゲートは `polish-issue` 時に確定）。
