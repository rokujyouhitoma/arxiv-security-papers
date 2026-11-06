---
ID: 750
種別: Feature
優先度: Low
ステータス: Open (In Progress)
---

# [FEAT/ENH] タスクメールボックスの O(1) FIFO キュー化および上限設定 (CWE-400 対策) (ID: 750)

## 1. 概要 / Summary
現在タスクのメッセージ受信メールボックスには保持メッセージ数の上限が設定されておらず、大量メッセージ送信によるメモリ枯渇脆弱性（Uncontrolled Resource Consumption: CWE-400）が存在する。
さらに、メッセージの追加が単方向リストの末尾への append で行われているため、メッセージが蓄積するたびに $O(n)$ の走査コストが発生しスループットが大幅に低下する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue: Follow-up of #726
- 関連 CWE: CWE-400 (Uncontrolled Resource Consumption)
- 関連資料: Synapse メールボックス設計仕様、リングバッファアルゴリズム

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/runtime/concurrency/queue.scm`](../../ulisp/runtime/concurrency/queue.scm)
- [ ] [`ulisp/runtime/concurrency/scheduler.scm`](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [`ulisp/tests/test_list_queue_lseq.scm`](../../ulisp/tests/test_list_queue_lseq.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/750-implement-bounded-fifo-task-mailbox-queue`

1. `ulisp/runtime/concurrency/queue.scm`:
   - 先頭・末尾ポインタを持つ双方向キューまたはリングバッファ構造を採用し、エンキュー／デキュー操作をともに $O(1)$ で実行できるように刷新。
   - メールボックスにキャパシティ（最大メッセージ数）プロパティを追加。デフォルト上限値を設定可能にする。
2. `ulisp/runtime/concurrency/scheduler.scm`:
   - メールボックス上限超過時のポリシー（送信側ブロック / バックプレッシャー、またはエラー返却）を実装。
3. `ulisp/tests/`:
   - 大量メッセージを連続送信した際の計算量が線形劣化しないことのベンチマーク検証、および上限到達時の安全な防御動作を検証するテストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] メールボックスへのエンキュー処理が $O(1)$ 時間で完了すること
- [ ] メッセージ上限設定が機能し、無制限なメモリ消費 (CWE-400) が防止されること
- [ ] `ulisp/tests/test_list_queue_lseq.scm` が PASS すること

