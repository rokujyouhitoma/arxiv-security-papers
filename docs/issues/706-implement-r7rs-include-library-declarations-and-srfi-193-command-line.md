---
ID: 706
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-small 残余構文 (include-library-declarations) および SRFI 193 (command-line) の完全実装 (ID: 706)

## 1. 概要 / Summary
ULisp の R7RS-small 言語仕様準拠率を最大化するため、セクション 5.6 (Libraries) で唯一未実装 (`×`) となっているライブラリ宣言分割取り込み構文 `(include-library-declarations <string1> ...)`、およびセクション 6.14 (System Interface) で部分サポート (`△`) となっている `(command-line)` ならびに **SRFI 193 (`(srfi 193)` Command line)** を完全実装し、両項目を **◎（完全サポート）** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§1.2, §1.3, §2.5)
  - R7RS-small §5.6.1 (Library Syntax: `include-library-declarations`)
  - R7RS-small §6.14 (System interface: `command-line`)
  - [SRFI 193: Command line](https://srfi.schemers.org/srfi-193/srfi-193.html)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [010_library.scm](../../ulisp/frontend/010_library.scm)
- [ ] [posix.scm](../../ulisp/lib/posix.scm)
- [ ] [process-context.sld](../../ulisp/lib/scheme/process-context.sld)
- [ ] [193.sld](../../ulisp/lib/srfi/193.sld) (新規)
- [ ] [helpers.scm](../../ulisp/compiler/helpers.scm)
- [ ] [Makefile](../../ulisp/Makefile)
- [ ] [test_r7rs_cond_expand.scm](../../ulisp/tests/test_r7rs_cond_expand.scm)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/706-implement-r7rs-include-library-declarations-and-srfi-193-command-line`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

