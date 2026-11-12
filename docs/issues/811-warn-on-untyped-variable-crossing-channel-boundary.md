---
ID: 811
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 型推論不能な変数のチャネル境界通過時における静的コンパイル警告の導入 (ID: 811)

## 1. 概要 / Summary

Issue #797 により、split-planes パスおよびチャネル境界処理における変数名依存ヒューリスティックが撤廃され、型推論できない変数については安全側に倒して暗黙的に `deep-copy` として扱われる設計となった。
しかし、開発者がチャネルに型注釈を付け忘れた場合でも、エラーや警告が一切出力されずに通過するため、意図しない `deep-copy` の乱発による大幅な性能低下や、設計ミスの潜伏に気付きにくい課題が生じている。
本Issueでは、プロセス／チャネル境界をまたぐ変数において型推論が確定せず `deep-copy` にフォールバックするケースに対し、コンパイル時診断警告（Warning）を出力する機構を導入する。

---

## 2. トレーサビリティ / Traceability

- 関連Issue:
  - #797 (split-planes パスおよび ASC カーネルにおける変数名依存ヒューリスティックの完全撤廃)
  - #792 (Affine 検査における変数名ヒント強制判定の廃止)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [compiler/passes/pass_split_planes.scm](../../compiler/passes/pass_split_planes.scm)
- [ ] [compiler/frontend/diagnostics.scm](../../compiler/frontend/diagnostics.scm)
- [ ] [tests/test_split_planes.scm](../../tests/test_split_planes.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/811-warn-on-untyped-variable-crossing-channel-boundary`

1. **フォールバック検出箇所での Diagnostics 発行**:
   - `pass_split_planes.scm` において、チャネル経由で渡される変数の型が未解決（`unknown` / `untyped`）のまま `deep-copy` ルールが適用されるポイントを特定。
   - ソースコード位置（ファイル・行・列・変数名）を含むコンパイラ警告（Diagnostic Warning）を出力。
2. **警告抑制・許容オプションの設計**:
   - 意図的に型なしで `deep-copy` させたい場合に警告を抑止できるアノテーションやコンパイラフラグを検討。
3. **診断テストの追加**:
   - 型注釈のないチャネル送受信に対して警告が出力されること、型注釈がある場合には警告が抑制されることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 型推論が効かない変数がチャネル境界をまたぐ際に、コンパイル時に分かりやすい Warning メッセージが表示されること。
- [ ] 既存の正しく型付けされた並行処理コードで偽陽性の警告が発生しないこと。
- [ ] 警告の発生・抑制を検証するテストケースが追加され、PASS すること。

