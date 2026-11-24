---
ID: 948
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Direct-Style 静的 `.scm` PEG パーサージェネレータバックエンド (`emit_scheme.scm`) の実装と `peg_meta.peg` ソース自己ホスト不動点実証 (ID: 948)

## 1. 概要 / Summary

現行の ULisp PEG（[codegen.scm](../../ulisp/peg/compiler/codegen.scm) + [runtime.scm](../../ulisp/peg/runtime.scm)）は、実行時に二重 CPS クロージャ網を合成するインメモリ型であり、`peg:seq`/`peg:alt`/`peg:star` の各ステップで継続クロージャを大量確保するため、ULisp AOT コンパイラによる静的最適化（インライン展開・ループ化・直接関数呼出）の恩恵を受けられない。

本 Issue では、`.peg` 文法 AST から Direct-Style（非 CPS）・ゼロアロケーション呼び出し規約（`(parse-<rule> ctx [env] pos)` → 成功時は `next-pos` を返却し結果値は `ctx` の 1 スロットへ格納、失敗時は `#f`）の独立した `.scm` ソースコードを生成する AOT バックエンド `ulisp/peg/compiler/emit_scheme.scm` を実装する。静的左再帰解析（SCC）により、左再帰ルールのみ Warth シード成長ループ・非左再帰メモ化ルールは軽量メモ化・葉ルールは裸関数として出し分け、[peg_meta.peg](../../tools/grammars/peg_meta.peg) のソースレベル自己ホスト不動点（Stage 1 生成 `.scm` == Stage 2 生成 `.scm`）を実証する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [DSN-25](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [DSN-33-22](../designs/DSN-33-22-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [Issue #894](closed/894-implement-pure-scheme-compile-time-peg-parser-generator.md)
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] `ulisp/peg/compiler/emit_scheme.scm` (新規: Direct-Style 静的 `.scm` コード生成器・静的 SCC 左再帰解析)
- [ ] [runtime.scm](../../ulisp/peg/runtime.scm) (Direct-Style ランタイム補助・`res-val` スロット追加)
- [ ] [peg.scm](../../ulisp/peg.scm) (`.scm` 生成ファサード API 追加)
- [ ] [peg_meta.peg](../../tools/grammars/peg_meta.peg) (自己ホスト不動点検証対象)
- [ ] [test_peg_self_hosting.scm](../../ulisp/tests/test_peg_self_hosting.scm) (ソースレベル Stage 1 == Stage 2 不動点検証追加)
- [ ] [Makefile](../../ulisp/Makefile)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/948-implement-direct-style-static-scheme-peg-generator`

1. `ulisp/peg/runtime.scm` に Direct-Style 用の `res-val` 受け渡しスロットおよび非 CPS 補助プリミティブを追加する。
2. `ulisp/peg/compiler/emit_scheme.scm` を新設し、静的 SCC 解析で左再帰有無を判定しつつ `seq`/`alt`/`star`/`plus`/`gather`/`lit`/`rule-ref` を直接関数呼び出し・`let loop` の Direct-Style `.scm` へ展開する。
3. `peg_meta.peg` から Stage 1 / Stage 2 パーサー `.scm` を自己生成し、ソース一致（不動点）と既存 PEG テスト全件の PASS を検証する（詳細手順は `polish-issue` にて精緻化する）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `emit_scheme.scm` が `seq`/`alt`/`star`/`plus`/`gather`/`lit`/`rule-ref` をコンビネータ・CPS クロージャゼロの Direct-Style `.scm` 関数群として出力できること。
- [ ] `peg_meta.peg` から生成した Stage 1 / Stage 2 パーサー `.scm` ソースが完全一致（不動点）し、既存 PEG テスト全件が PASS すること（詳細ゲートは `polish-issue` 時に確定）。
