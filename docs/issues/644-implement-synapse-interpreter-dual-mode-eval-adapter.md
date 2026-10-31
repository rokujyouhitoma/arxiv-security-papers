---
ID: 644
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] インタプリタ向け Dual-Mode 評価アダプタ (eval_adapter.scm) の実装 (ID: 644)

## 1. 概要 / Summary
[DSN-37] Phase 5 Task 5.3 および第 13 章に基づき、将来の Scheme インタプリタ環境（REPL / Tree-walk 評価器 / バイトコード VM）からアフィン部分言語コア（ASC）タスクを直接起動・解釈実行するための直交的評価アダプタを実装する。
AOT とインタプリタで同一の Scheme ランタイムライブラリを共有し、REPL 対話開発の俊敏性とリダクション方式セーフポイント注入によるプリエンプションの安全性を両立する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#13-将来のインタプリタ環境との統合と直交的拡張性) (第 13 章 将来のインタプリタ環境統合、第 14.7 節 Task 5.3)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/runtime/concurrency/eval_adapter.scm` (新規: インタプリタ向け評価アダプタ)
- [ ] `tests/concurrency/test_eval_adapter.scm` (新規: インタプリタ実行テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/644-interpreter-dual-mode`

1. **ステップ Reduction 減算ラッパー `(eval-in-task expr task)`**:
   - 評価ループ内で式の簡約ステップごとに `task-reductions` を 1 減算。
   - 0 到達時に `(scheduler-yield! task)` を呼び出し、協調的に別タスクへ切り替え。
2. **アリーナバインド動的環境 `(with-task-arena task thunk)`**:
   - `thunk` 実行中のメモリ確保先をグローバルヒープから `(task-arena task)` へ切り替え。
3. **軽量事前リント `(lint-affine-syntax expr)`**:
   - インタプリタ実行前に AST を走査し、`set!` や二重参照がないかを検査。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] インタプリタ評価ループ内で Reduction カウンタが正常にステップ減算されること
- [ ] REPL から無限ループ式を実行しても、REPL 自身が固まらず安全に中断できること
- [ ] インタプリタ実行されたタスクの完了時にアリーナが $O(1)$ で回収されること
