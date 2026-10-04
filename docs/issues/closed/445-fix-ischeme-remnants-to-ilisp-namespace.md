---
ID: 445
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG] ilisp 配下および設計書・エージェント定義における ischeme 残存名称の ilisp 名前空間統一 (ID: 445)

## 1. 概要 / Summary
言語仕様の名称策定プロセスにおいて、仮称 `ischeme` から正式名称 `ILISP (Intelligence LISP)` への移行が合意されたが、`ilisp/docs/` 配下、設計仕様書 `DSN-31`、および PLC エージェント定義内に独自拡張モジュール・ライブラリ名として `(ischeme ...)` 等の残存が確認された。
本 Issue では、すべての独自拡張ライブラリ名および参照を `(ilisp ...)` （例: `(ilisp python)`, `(ilisp condition)`, `(ilisp okf)`, `(ilisp pipeline)`, `(ilisp logic)`）へ完全統一し、不整合を解消する。

### 再現手順 / Steps to Reproduce
1. `ilisp/docs/SPEC_R7RS.md` を確認すると、`## 3. ILISP 独自拡張ライブラリ ((ischeme ...))` や `(ischeme python)` 等の記述が残存している。
2. `ilisp/docs/README.md` を確認すると、`(ischeme python)` の import 記述が残存している。
3. `docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md` を確認すると、`(ischeme python)` や `(ischeme ...)` の記述が残存している。
4. `.agents/agents/it-specialist-programming-languages-and-compilers.agent.md` を確認すると、`(ischeme python)` 等の記述が残存している。

### 再現環境 / Environment
- File: [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md), [ilisp/docs/README.md](../../ilisp/docs/README.md), [docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md](../designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md), [.agents/agents/it-specialist-programming-languages-and-compilers.agent.md](../../.agents/agents/it-specialist-programming-languages-and-compilers.agent.md)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md)
- [ ] [ilisp/docs/README.md](../../ilisp/docs/README.md)
- [ ] [docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md](../designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md)
- [ ] [.agents/agents/it-specialist-programming-languages-and-compilers.agent.md](../../.agents/agents/it-specialist-programming-languages-and-compilers.agent.md)
- [ ] [docs/issues/README.md](README.md)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- 名称決定（Issue #443）の際、タイトルやトップレベル概要は `ILISP` に更新されたが、詳細仕様部分で先行設計時のプレースホルダ `ischeme` ライブラリプレフィックスの置換漏れが発生していた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: なし（ドキュメント・仕様書修正のため即時恒久対策を実施）。
* **恒久対策 (Permanent Fix)**:
  - 独自拡張ライブラリのプレフィックスを `(ischeme <submodule>)` から `(ilisp <submodule>)` に置換。
  - ディレクトリ構造図中のコメントおよび説明文も `(ilisp ...)` 標準ライブラリ表記に更新。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/445-fix-ischeme-remnants-to-ilisp-namespace`

1. `ilisp/docs/SPEC_R7RS.md` 内の `(ischeme ...)` を `(ilisp ...)` に置換。
2. `ilisp/docs/README.md` 内の `(ischeme python)` を `(ilisp python)` に置換。
3. `DSN-31` 内の `(ischeme ...)` および `ischeme 拡張モジュール` を `(ilisp ...)` および `ILISP 拡張モジュール` に置換。
4. `.agents/agents/it-specialist-programming-languages-and-compilers.agent.md` 内の `(ischeme ...)` を `(ilisp ...)` に置換。
5. 全体 grep で `ischeme` の不要な残存が 0 件であることを確認（過去クローズド Issue 履歴を除く）。
6. 品質ゲート（`make check_format`, `make static_analysis`）を実行し、問題ないことを確認。

---

- [x] `ilisp/docs/SPEC_R7RS.md` 内で `ischeme` が 0 件であること
- [x] `ilisp/docs/README.md` 内で `ischeme` が 0 件であること
- [x] `DSN-31` 内で不要な `ischeme` が 0 件であること
- [x] `.agents/agents/it-specialist-programming-languages-and-compilers.agent.md` 内で `ischeme` が 0 件であること
- [x] `make check_format` および `make static_analysis` が 100% PASS すること
