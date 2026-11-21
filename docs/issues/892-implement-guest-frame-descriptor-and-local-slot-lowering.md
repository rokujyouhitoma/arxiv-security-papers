---
ID: 892
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Implement Guest Frame Descriptor and Local Slot Lowering (ID: 892)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 2 章に基づき、言語ワークベンチにおいてゲスト言語の変数環境を Scheme ネイティブの連想リスト探索から静的スタックフレーム記述子（`FrameDescriptor`）および固定オフセット（Local Slots）へコンパイル時降格するメカニズムを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-04] ULisp 言語ワークベンチ・インタプリタ自動生成 ＆ ゲスト言語ランタイムアーキテクチャ設計書 (第2章)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-33-03] ULisp ステージ多相メタコンパイラ ＆ 二村射影フラクタル実行基盤設計書](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/workbench/frame.scm](../../ulisp/workbench/frame.scm)
- [ ] [ulisp/compiler/scope.scm](../../ulisp/compiler/scope.scm)
- [ ] [ulisp/compiler/stage_poly_lower.scm](../../ulisp/compiler/stage_poly_lower.scm)
- [ ] [ulisp/tests/test_workbench_frame.scm](../../ulisp/tests/test_workbench_frame.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/892-implement-guest-frame-descriptor-and-local-slot-lowering`

1. `<guest-frame-descriptor>` レコード型およびスロット管理コンビネータを `ulisp/workbench/frame.scm` に実装。
2. ゲスト言語スコープ解析器において、変数参照を連想リスト探索から静的インデックス解決 `frame-ref(frame, slot_idx)` へ降格。
3. エスケープ解析と連携し、クロージャに捕獲されないローカル変数を LIR の仮想レジスタへ直接バインド。
4. 単体テスト `test_workbench_frame.scm` を作成し、LIR レベルで動的アロケーションが完全に消滅することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `<guest-frame-descriptor>` が定義され、静的スロット割り当てが正しく動作すること。
- [ ] ゲスト言語の変数探索が $O(1)$ の配列参照またはレジスタ参照へ 100% 降格されること。
- [ ] `make -C ulisp test_workbench_frame` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
