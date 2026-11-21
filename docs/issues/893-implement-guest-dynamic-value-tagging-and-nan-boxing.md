---
ID: 893
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Implement Guest Dynamic Value Tagging and NaN-Boxing (ID: 893)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 2.3 節に基づき、ゲスト言語が動的型付き言語である場合に高速かつ省メモリに値を表現するための 3-bit Tagged Pointer および 64-bit NaN-boxing モジュールを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-04] ULisp 言語ワークベンチ設計書 (第2.3節 動的型タグ表現と NaN-boxing)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/workbench/value_tagging.scm](../../ulisp/workbench/value_tagging.scm)
- [ ] [ulisp/workbench/nan_boxing.scm](../../ulisp/workbench/nan_boxing.scm)
- [ ] [ulisp/compiler/value_repr.scm](../../ulisp/compiler/value_repr.scm)
- [ ] [ulisp/tests/test_workbench_tagging.scm](../../ulisp/tests/test_workbench_tagging.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/893-implement-guest-dynamic-value-tagging-and-nan-boxing`

1. 3-bit Tagging モジュールにおいて、Fixnum, Cons, Symbol, Closure, Vector, Instance, Flonum, 特殊値のパッキング/アンパッキングプリミティブを実装。
2. 64-bit IEEE-754 非正規化空間を利用した NaN-boxing モジュールを実装し、浮動小数点数演算をアンボックス化。
3. BTA（束縛時間解析）と連携し、静的に型が確定したタグ判定操作（`tag-check`）をコンパイル時条件分岐簡約で完全除去。
4. 単体テスト `test_workbench_tagging.scm` を作成し、ビット演算整合性と型アンボクシングを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Tagged Pointer および NaN-boxing の両表現系が Pure Scheme で正しく機能すること。
- [ ] 静的型推論によって不要なタグ付け・タグ検査命令が LIR 上で消去されること。
- [ ] `make -C ulisp test_workbench_tagging` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
