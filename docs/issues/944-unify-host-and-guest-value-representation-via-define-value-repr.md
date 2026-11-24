---
ID: 944
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Host / Guest 値表現の単一情報源化 (`define-value-repr` によるタグ操作・GC・プリンタの統一生成) (ID: 944)

## 1. 概要 / Summary

現行コードベースでは値表現（タグ定義）が以下の 3 系統に分裂し、互いに食い違っている：

1. [value_repr.scm](../../ulisp/compiler/value_repr.scm)（`define-value-repr` DSL）：`ulisp/backend/`・`ulisp/runtime/` からの参照が 0 件
2. [printer.scm](../../ulisp/runtime/printer.scm)：`pair=1, string=3, vector=5, bytevector=7`
3. [value_tagging.scm](../../ulisp/workbench/value_tagging.scm)：`Fixnum=000, Pair=001, Symbol=010(2), Closure=011(3), Vector=100(4), Instance=101(5), Flonum=110(6), Special=111(7)`

タグの不整合はメモリ安全性を直接破壊する要因となる。ULisp 自身のランタイム（Host）もワークベンチ上のゲスト言語のランタイム（Guest）も「値表現仕様 → タグ操作 → GC → プリンタ」という同一の自己相似構造を持つため、双方を `define-value-repr` から統一生成することで単一情報源（SSOT）化し、ULisp 自身がワークベンチで作られた言語の 1 つとなるフラクタル構造（DSN-33-22 の目標）を実現する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [DSN-33-22](../designs/DSN-33-22-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [Issue #836](closed/836-plugin-value-representation-and-boxing-scheme.md)
  - [Issue #893](closed/893-implement-guest-dynamic-value-tagging-and-nan-boxing.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [value_repr.scm](../../ulisp/compiler/value_repr.scm) (`define-value-repr` 仕様およびコード生成基盤)
- [ ] [printer.scm](../../ulisp/runtime/printer.scm) (ハードコードされたタグ定数の統一生成化)
- [ ] [value_tagging.scm](../../ulisp/workbench/value_tagging.scm) (ゲスト側タグ定義の `define-value-repr` 統合)
- [ ] [backend/](../../ulisp/backend) (タグ参照箇所の `define-value-repr` 統合)
- [ ] [test_value_representation.scm](../../ulisp/tests/test_value_representation.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/944-unify-host-and-guest-value-representation`

1. `ulisp/compiler/value_repr.scm`・`ulisp/runtime/printer.scm`・`ulisp/workbench/value_tagging.scm`・`ulisp/backend/` 間のタグ定義・GC・プリンタの対応関係を棚卸しし、Host / Guest 共通の `define-value-repr` スキーマへ統合する。
2. タグ操作・GC・プリンタの生成物を Host / Guest 双方に配線し、直書き定数による食い違いを排除する（詳細設計は `polish-issue` にて精緻化する）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] Host（`runtime/`・`backend/`）と Guest（`workbench/`）の値表現・タグ定義が `define-value-repr` を単一情報源として一致していること。
- [ ] `test_value_representation` を含む既存テストおよびセルフホストブートストラップが PASS すること（詳細ゲートは `polish-issue` 時に確定）。
