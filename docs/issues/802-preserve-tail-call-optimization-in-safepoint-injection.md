---
ID: 802
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/COMPILER] セーフポイント注入時における末尾呼び出し最適化 (TCO) の保護とスタックオーバーフロー防止 (ID: 802)

## 1. 概要 / Summary
Issue #796 にてセーフポイント挿入パス（`pass_inject_safepoints.scm`）を本番コンパイラ（`ulisp/compiler.scm` の `PASSES`）に結合するにあたり、Scheme (R7RS) の言語仕様における最重要基盤である「末尾呼び出し最適化（Tail-Call Optimization / TCO）」が破壊される重大なリスクが存在する。
Scheme ではループ構造が末尾再帰関数によって表現されるため、関数の末尾位置（Tail Position）に不用意に `synapse-safepoint-poll!` 式を挿入したり、末尾呼出しの戻り値をラップするような変換が行われると、呼び出しが末尾呼出しでなくなり、1 ループごとにスタックフレームが累積して致命的なスタックオーバーフロー（CWE-400: リソース枯渇）が発生する。
本 Issue では、セーフポイント注入パスにおいて末尾位置コンテキストを厳密に判定・保存し、末尾再帰の性質を 100% 損なうことなくループ戻り辺および手続先頭に非破壊的なポーリング命令を注入できる設計を検証・確立する。

### 再現手順 / Steps to Reproduce
1. 末尾再帰を用いた無限ループタスク（例: `(let loop ((n 0)) (loop (+ n 1)))`）をセーフポイント有効化状態でコンパイルする。
2. タスクを実行し、スタックフレームが一定の上限（例: 64KB）を超えずに一定メモリ空間で無限に回るか確認する。
3. TCO が無効化されている場合、数万回の反復でスタック枯渇エラーが発生する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / macOS arm64
- File: [compiler.scm](../../ulisp/compiler.scm), [test_pass_inject_safepoints.scm](../../tests/concurrency/test_pass_inject_safepoints.scm)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) - 中間パス定義
- [ ] [tests/concurrency/test_pass_inject_safepoints.scm](../../tests/concurrency/test_pass_inject_safepoints.scm) - TCO 保証およびスタックサイズ上限検証テスト

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- AST/HIR レベルでのナイーブな式挿入（例: `(begin (synapse-safepoint-poll!) (expr ...))`）では、式の評価順序や構文形式によってはコンパイラバックエンドが当該呼び出しを末尾位置と認識できず、スタックフレームの再利用（`jmp` 命令への置換）が行われなくなる危険性がある。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**:
  - なし（TCO 破壊はクラッシュに直結するため、コンパイラパス側での保証が必須）。
* **恒久対策 (Permanent Fix)**:
  - 注入器において末尾位置（Tail Position）フラグを伝播させ、末尾呼び出しの直前に poll を配置する構造を生成するか、LIR / アセンブリ生成フェーズにおけるループバックエッジ（後方ジャンプ）直前に専用のポーリング命令を直接埋め込む。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/802-preserve-tail-call-optimization-in-safepoint-injection`

1. セーフポイント挿入パスにおける末尾位置判別ロジックの形式検証。
2. 生成された x86-64 / aarch64 アセンブリにおいて、末尾再帰呼出しが `call` ではなく `jmp`（またはレジスタ更新＋ループ先頭ジャンプ）として出力されていることを確認。
3. 1,000,000 回以上の末尾再帰反復テストを行い、スタック使用量が一定であることを検証するテストケースを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] セーフポイントが注入された状態でも、末尾再帰関数が固定スタックサイズ（スタック増加なし）で動作すること。
- [ ] 生成コードのアセンブリ検査において TCO（`jmp` への変換）が維持されていることが自動テストで確認されること。
- [ ] 100万回反復テストがスタックオーバーフローなく完了すること。

