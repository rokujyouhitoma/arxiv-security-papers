---
ID: 733
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] Task ID (TID) からタスクコンテキストを O(1) 解決するロックフリータスク表の実装 (ID: 733)

## 1. 概要 / Summary
Synapse 並行性ランタイムにおいて、プロセス ID（`tid`）から `<task-context>` を O(1) かつスレッドセーフに逆引き解決する共通機構が存在せず、Supervisor やシグナル配信（DOWN / EXIT）、リンク監視における TID ベースの配送処理が局所的な探索に依存していた（設計項目 B2）。
本改修では、64 バケットのアトミック・ハッシュテーブルによる Lock-Free Task Table（`synapse-lookup-task-by-tid`）を実装し、タスク生成時（`make-task-context`）の自動登録、およびタスク終了時（`task-handle-termination!`）の自動登録解除を統合した。

---

## 2. トレーサビリティ / Traceability
- **DSN-37**:
  - Section 6.1: タスクライフサイクルと識別子（Task Identifier / Allocation Table）
  - Section 8.4.1: モニターおよびリンク通知における TID 逆引き解決
- **関連 Issue**:
  - [Issue #668: Fail-Fast Let-It-Crash Semantics](../closed/668-concurrency-let-it-crash-semantics.md)
  - [Issue #730: Fix Registry Send Named Delivery](../closed/730-fix-registry-send-named-delivery-and-auto-unregister-terminated-tasks.md)
  - [Issue #734: Unify Task Context Representation](../closed/734-unify-four-task-representations-into-single-task-context.md)

---

## 3. セキュリティ考慮事項・脅威分析 / Security & Threat Analysis
- **CWE-362 (Concurrent Race Condition / Lock Contention Bottleneck)**:
  - 複数ワーカースレッドが同時に数万の軽量タスクを並行生成・破棄する際、単一ミューテックスで保護されたタスク表は重大なスレッド競合と性能崩壊を引き起こす。
  - **対策**: 64 バケットに分散させた `make-atomic-box` の連想リストを採用し、バケット単位の CAS（Compare-And-Swap）ループによる完全 Lock-Free 実装を行った。
- **CWE-416 (Use-After-Free / Ghost Task Reference)**:
  - 終了済みタスクがタスク表に残留すると、再利用された TID 宛てのシグナルが古い終了済みタスクに誤配されるリスクが生じる。
  - **対策**: `task-handle-termination!` 内で `synapse-unregister-task!` を確実に呼び出し、テーブルから即座に破棄する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [channel.scm](../../ulisp/runtime/concurrency/channel.scm): 64 バケット Lock-Free Task Table 定義、`synapse-register-task!`, `synapse-unregister-task!`, `synapse-lookup-task-by-tid` 実装
- [x] [channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld): 新規エクスポートシンボルの追加
- [x] [test_channel.scm](../../tests/concurrency/test_channel.scm): TID 逆引き・並行登録解除の単体テスト
- [x] [test_links_monitors.scm](../../tests/concurrency/test_links_monitors.scm): リンク・モニター結合での TID 解決テスト

---

## 5. 根本原因分析 (RCA) / Root Cause Analysis
- 初期設計ではタスク参照を直接 `<task-context>` ポインタで受け渡す前提だったため、プロセス間通信や Supervisor 再起動管理で TID（整数）のみが渡された際に、対応するタスクをグローバルに解決する基盤が未整備であった。

---

## 6. 実装方針と恒久対策 / Implementation Plan
Target Branch: `feat/733-implement-task-table`

1. 64 要素のベクタ `*active-synapse-tasks-table*` を定義し、各スロットを空リストを保持する `make-atomic-box` で初期化。
2. ハッシュ関数 `(%task-table-hash-slot tid)`: `(modulo tid 64)` によりバケットを分散。
3. `synapse-register-task! task`: `task-id` をキーとして CAS ループでアトミック登録。
4. `synapse-unregister-task! tid`: CAS ループで対象 TID エントリをリストから削除。
5. `synapse-lookup-task-by-tid tid`: バケットをアトミック読み出しし、`assv` 探索で対応する `<task-context>` を O(1) 返却。
6. `make-task-context` 末尾で自動登録、`task-handle-termination!` 先頭で自動解除。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `(synapse-lookup-task-by-tid tid)` により、生存タスクを O(1) で解決できること。
- [x] タスク終了後に検索すると `#f` が返り、ゾンビエントリが残留しないこと。
- [x] `make -C ulisp test_channel` (350 passed) および `test_links_monitors` (85 passed) が 100% PASS すること。

