---
ID: 655
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large (SRFI 132 / 95) リストおよびベクタソート手続きの実装 (ID: 655)

## 1. 概要 / Summary
R7RS-large (SRFI 132 Sort Libraries および SRFI 95 / SLIB 互換) に準拠した、リストおよびベクタのソート手続き群（`list-sort`, `vector-sort`, `vector-sort!`）を実装する。
安定ソート（マージソート等）アルゴリズムに基づき、任意の比較述語（`less?`）に従って要素列を整列可能にする。

---

## 2. トレーサビリティ / Traceability
- R7RS-large: Red Edition / SRFI 132 (Sort Libraries) および SRFI 95 (Sorting and Merging)
- 仕様リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1, §2.3
- 関連モジュール: [ulisp/lib/list.scm](../../ulisp/lib/list.scm), [ulisp/lib/vector.scm](../../ulisp/lib/vector.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/sort.scm](../../ulisp/lib/sort.scm) (新規モジュール)
- [ ] [ulisp/lib/srfi/132.sld](../../ulisp/lib/srfi/132.sld) (新規ライブラリ定義)
- [ ] [ulisp/lib/srfi/95.sld](../../ulisp/lib/srfi/95.sld) (新規ライブラリ定義)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)
- [ ] [ulisp/tests/test_sort.scm](../../ulisp/tests/test_sort.scm) (新規テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/655-implement-r7rs-list-and-vector-sort-procedures`

1. リストソート: 分割統治法に基づく再帰的ボトムアップまたはトップダウンの自然マージソート（O(N log N)、安定ソート）をピュア Scheme で実装。
2. ベクタソート: ベクタからリストへの変換を介さず、インプレース作業領域または一時バッファを用いたベクタソート（`vector-sort!`, `vector-sort`）を実装。
3. 等価要素の順序が保持される安定性を保証。
4. `(srfi 132)` および `(srfi 95)` モジュールとしてエクスポート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 数値リスト・文字列リスト・構造体ベクタ等が任意の比較述語で正しく安定ソートされること。
- [ ] 空リスト、要素数1、同一値多数などのエッジケースで正しく動作すること。
- [ ] `ref_r7rs_compliance.md` の SRFI 132 / 95 ステータスを更新すること。

