---
ID: 709
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large Tangerine Edition / SRFI 146 (scheme mapping) 不変マッピングライブラリの実装 (ID: 709)

## 1. 概要 / Summary
R7RS-large Tangerine Edition の最重要純粋関数型データ構造である **SRFI 146 (`(scheme mapping)` / `(srfi 146)` および `(scheme mapping hash)` / `(srfi 146 hash)`)** を実装する。先行実装した SRFI 128 (`(scheme comparator)`) の順序比較述語およびハッシュ関数を基盤として、順序付き不変辞書 (`mapping`) とハッシュベース不変辞書 (`hashmap`) の生成・検索・関数型更新・走査・分割結合・集合演算・比較器統合を完全サポートする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§2.2 Tangerine Edition)
  - [SRFI 146: Mappings](https://srfi.schemers.org/srfi-146/srfi-146.html)
  - 先行依存: [Issue #701 (SRFI 128 Comparators)](closed/701-implement-srfi-128-comparators.md), [Issue #704 (SRFI 121/158 Generators)](closed/704-implement-srfi-158-generators-and-accumulators.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [mapping.scm](../../ulisp/lib/mapping.scm) (新規)
- [ ] [mapping.sld](../../ulisp/lib/scheme/mapping.sld) (新規)
- [ ] [hash.sld](../../ulisp/lib/scheme/mapping/hash.sld) (新規)
- [ ] [146.sld](../../ulisp/lib/srfi/146.sld) (新規)
- [ ] [hash.sld](../../ulisp/lib/srfi/146/hash.sld) (新規)
- [ ] [helpers.scm](../../ulisp/compiler/helpers.scm)
- [ ] [Makefile](../../ulisp/Makefile)
- [ ] [test_mapping.scm](../../ulisp/tests/test_mapping.scm) (新規)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/709-implement-srfi-146-immutable-mappings`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

