---
ID: 636
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] リダクション方式セーフポイント注入と協調的・強制的プリエンプション機構の実装 (ID: 636)

## 1. 概要 / Summary
[DSN-37] Phase 2 Task 2.3 に基づき、CPU バウンドな無限ループタスクによるコア占有を阻止する Erlang BEAM Reduction 方式のリダクション方式セーフポイント注入（プリエンプション機構）を実装する。
各タスクに計算予算（初期値 4096）を付与し、予算枯渇時に確実に CPU コアを解放・再スケジューリングさせる。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#144-phase-2-mn-スケジューラ--強プリエンプション) (第 7.2 節 リダクション方式セーフポイント注入による決定論的プリエンプション、第 14.4 節 Task 2.3)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/runtime/concurrency/preempt.scm` (新規: リダクション管理および yield 処理)
- [ ] `tests/concurrency/test_preemption.scm` (新規: 無限ループ並行実行テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/636-reduction-preemption`

1. **リダクション枯渇ハンドラ `scheduler-yield!`**:
   - `task-reductions` を初期値（4096）へリセット。
   - `task-reduction-exhaustions` カウンタをインクリメント。
   - タスクの状態を `TASK_READY` に設定し、ローカルランキューの末尾へ再投入。
   - コンテキストスイッチにより次タスクへ CPU を譲渡。
2. **スタベーション防止**:
   - 協調的 yield を一切呼ばないビジーループタスクであっても、約 4000 反復で強制的に yield が発生することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 無限ループ `(let loop () (loop))` を含むタスクが他タスクを餓死させずに並行実行できること
- [ ] `task-reduction-exhaustions` がプリエンプションの回数と厳密に一致して増加すること
- [ ] プリエンプションによるコンテキストスイッチオーバーヘッドが数マイクロ秒以下であること
