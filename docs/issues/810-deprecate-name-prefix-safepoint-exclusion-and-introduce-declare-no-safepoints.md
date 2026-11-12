---
ID: 810
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] safepoint 挿入除外判定の名前プレフィックス廃止と declare no-safepoints 構文の導入 (ID: 810)

## 1. 概要 / Summary

現在の `pass-synapse-inject-safepoints` では、関数名の先頭文字列 (`*safepoint-excluded-prefixes*`: `make-`, `task-`, `channel-`, `sys-` 等) に基づいて safepoint 挿入を除外している。
この名前ヒューリスティックにより、ユーザーが定義した一般的な自己再帰関数（例: `(make-tree ...)` や `(task-worker ...)` など、named let を使わず自己再帰するもの）に関数先頭の poll が注入されず、外部から `kill` を発行しても安全に停止できない不具合・ゾンビプロセス化のリスクが存在する。
本Issueでは、名前プレフィックスによるブラックリスト方式を完全撤廃し、ランタイム側の除外対象関数に明示的な宣言 `(declare (no-safepoints))` を付与するホワイトリスト／属性ベースの方式へ刷新する。

---

## 2. トレーサビリティ / Traceability

- 関連Issue:
  - #796 (セーフポイント注入パスの本番パイプライン統合)
  - #792 (Affine 検査における変数名ヒント強制判定の廃止)
  - #797 (split-planes パスおよび ASC カーネルにおける変数名依存ヒューリスティックの完全撤廃)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [compiler/passes/pass_synapse_inject_safepoints.scm](../../compiler/passes/pass_synapse_inject_safepoints.scm)
- [ ] [runtime/preempt.scm](../../runtime/preempt.scm)
- [ ] [runtime/channel.scm](../../runtime/channel.scm)
- [ ] [runtime/task.scm](../../runtime/task.scm)
- [ ] [tests/test_pass_inject_safepoints.scm](../../tests/test_pass_inject_safepoints.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/810-deprecate-name-prefix-safepoint-exclusion`

1. **構文宣言・アノテーションのサポート**:
   - 関数定義メタデータまたは宣言部において `(declare (no-safepoints))` をパース・保持する機構を整備。
2. **ランタイム内部関数の注釈付与**:
   - safepoint の注入を避けるべきランタイム低レベル関数群に `(declare (no-safepoints))` を付与。
3. **名前プレフィックス判定の撤廃**:
   - `pass-synapse-inject-safepoints` から `*safepoint-excluded-prefixes*` を削除し、宣言属性ベースの判定のみに変更。
4. **テスト更新**:
   - `make-` 等の接頭辞を持つユーザー定義関数にも safepoint が正しく挿入されることをテスト。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `*safepoint-excluded-prefixes*` による関数名ベースの除外処理がコードベースから完全に削除されていること。
- [ ] `(declare (no-safepoints))` を明示指定した関数のみ safepoint 注入がスキップされること。
- [ ] `make-tree` などの自己再帰関数に正常に safepoint poll が挿入されること。

