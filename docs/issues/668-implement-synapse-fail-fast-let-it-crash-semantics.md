---
ID: 668
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] エフェメラルアリーナ O(1) 即時破棄と融合した Fail-Fast "Let It Crash" セマンティクスおよびパニック機構の確立 (ID: 668)

## 1. 概要 / Summary
Erlang の "Let It Crash" 哲学（不正な入力や不変条件違反に直面した際、中途半端な防御的コードで握りつぶさず即座に死ぬ）を、Synapse のプロセスローカル・エフェメラルアリーナ（Shared-Nothing）および AOT コード生成と統合する。
タスクローカルなパニック機構（`panic!`）を整備し、タスク終了時にメモリを $O(1)$ でバンプリセットして新品状態でスーパーバイザに委ねることで、コードの簡潔化と状態汚染の完全遮断を両立する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](docs/designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連 Issue:
  - [Issue #630 (独立バンプアリーナ)](docs/issues/closed/630-implement-synapse-task-independent-bump-arena.md)
  - [Issue #638 (アフィン型検査とRAII Drop)](docs/issues/closed/638-implement-nanopass-check-affine-types-and-raii-drop.md)
  - [Issue #642 (世代管理型投機タスク破棄・アリーナ即時リセット)](docs/issues/closed/642-implement-synapse-epoch-fencing-distributed-rollback.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/arena.scm](ulisp/runtime/concurrency/arena.scm)
- [ ] [ulisp/runtime/concurrency/context.scm](ulisp/runtime/concurrency/context.scm)
- [ ] [ulisp/runtime/concurrency/panic.scm](ulisp/runtime/concurrency/panic.scm)（新規作成予定）
- [ ] [tests/test_synapse_let_it_crash.py](tests/test_synapse_let_it_crash.py)（新規作成予定）

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/668-synapse-fail-fast-let-it-crash`

1. タスク専用の脱出プリミティブ `(synapse-panic! reason)` の実装（AOT ネイティブスタック巻き戻し / 長ジャンプと連動）。
2. パニック発生時のフック処理:
   - タスクのアリーナのバンプオフセットを $O(1)$ で 0 リセット。
   - 保有中の外部線形チャネルの安全な Drop（RAII 保証）。
   - タスク終了理由を `<task-context>` に記録し、リンク/モニタシステムへ通知。
3. 表明構文（`synapse-assert`）の提供による、ASC 内の事前条件・事後条件違反の Fail-Fast 検知。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `synapse-panic!` 呼び出し時に、他タスクのヒープやスタックを汚染することなく単一タスクのみがクリーンに停止すること。
- [ ] パニック時にアリーナが即時 $O(1)$ 解放され、GC や走査コストを一切発生させないこと。
- [ ] リンク先タスクやスーパーバイザにパニック理由が正確に伝達されること。

