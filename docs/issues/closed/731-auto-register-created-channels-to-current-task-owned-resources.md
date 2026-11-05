---
ID: 731
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] make-channel 実行時における現在タスク所有チャネル一覧への自動登録 (ID: 731)

## 1. 概要 / Summary
`<task-context>` には所有チャネル一覧 `owned-channels-box` と `task-register-channel!` / `task-unregister-channel!` が定義されているが、`make-channel`（および `make-spsc-channel`）生成時に呼び出し元タスクへ自動登録されておらず、手動登録に依存していた（設計項目 A6）。
タスク境界内でチャネルを生成した場合、`current-synapse-task` が存在すれば自動で `task-register-channel!` を実行し、また `channel-close!` 時には所有リストから自動解除するよう改修した。これにより、タスクパニック発生時の自動チャネル毒化（Channel Poisoning）が漏れなく作動し、通信相手タスクの永久待機（デッドロック）を完全に防止する。

---

## 2. トレーサビリティ / Traceability
- **DSN-37**:
  - Section 8.4.2: 自動チャネル毒化（Automatic Channel Poisoning & RAII Drop）
  - Section 8.4.4: タスククラッシュ時のリソース一括解放（Zero-Leak Cleanup）
- **関連 Issue**:
  - [Issue #668: Fail-Fast "Let It Crash" Semantics](../closed/668-concurrency-let-it-crash-semantics.md)
  - [Issue #730: Fix Registry Send Named Delivery](../closed/730-fix-registry-send-named-delivery-and-auto-unregister-terminated-tasks.md)
  - [Issue #733: Implement Lock-Free Task Table](../closed/733-implement-lock-free-task-table-for-tid-lookup.md)

---

## 3. セキュリティ考慮事項・脅威分析 / Security & Threat Analysis
- **CWE-833 (Deadlock / Indefinite Wait)**:
  - 送信元タスクがパニック・異常終了した際、チャネルがタスク所有リソースとして登録されていないと、終了フックによるチャネル毒化（Poisoning）がスキップされる。結果として受信側タスクが `channel-recv!` で永久ブロックに陥る。
  - **対策**: チャネル生成関数 `%make-channel-instance` の末尾で `current-synapse-task` を検出し、アトミック CAS による Lock-Free リスト追加（`task-register-channel!`）を自動実行する。
- **CWE-400 (Uncontrolled Resource Consumption / Memory Leak)**:
  - 生成されたチャネルがクローズされた後も `owned-channels-box` に残り続けると、タスク終了までメモリが解放されない。
  - **対策**: `channel-close!` 実行時に `current-synapse-task` の所有リストから対象チャネルを自動解除（`task-unregister-channel!`）する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [channel.scm](../../ulisp/runtime/concurrency/channel.scm): `%make-channel-instance` での自動登録および `channel-close!` での自動解除
- [x] [panic.scm](../../ulisp/runtime/concurrency/panic.scm): タスク終了クリーンアップでの毒化整合性確認
- [x] [test_channel.scm](../../tests/concurrency/test_channel.scm): 自動登録・クローズ時自動解除の検証テスト追加

---

## 5. 根本原因分析 (RCA) / Root Cause Analysis
- `task-register-channel!` は提供されていたものの、`make-channel` のインスタンス生成ルーチンと `current-synapse-task` TLS/グローバルフックの接続が未配線だったため、アプリケーションプログラマが手動登録を忘れた場合にリソース追跡が漏れていた。

---

## 6. 実装方針と恒久対策 / Implementation Plan
Target Branch: `feat/731-auto-register-channel-on-creation`

1. `channel.scm` の `%make-channel-instance` において、`let ((t (current-synapse-task)))` を評価し、タスクが存在すれば `task-register-channel! t ch` を呼び出す。
2. `channel-close!` 処理内で、`let ((t (current-synapse-task)))` が存在する場合は `task-unregister-channel! t ch` を呼び出す。
3. `test_channel.scm` に Group 13 としてタスク内チャネル生成時の自動追跡テストを追加。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] タスク境界内で `make-channel` を呼ぶだけで、手動登録なしに `(task-owned-channels (current-synapse-task))` に含まれること。
- [x] `channel-close!` 後には所有チャネルリストから正常に除去されること。
- [x] `make -C ulisp test_channel` (339 passed) および `test_concurrency_ci` が 100% PASS すること。

