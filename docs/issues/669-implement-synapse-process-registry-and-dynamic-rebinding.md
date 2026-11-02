---
ID: 669
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 動的タスク再起動を透過化する Synapse プロセス名レジストリ (Registry) と透過的チャネル再バインド機構の実装 (ID: 669)

## 1. 概要 / Summary
Erlang のプロセス名登録機能（Process Registry / `register/2`, `whereis/1`）を参考に、Synapse 並行ランタイムにタスク・チャネルの論理名レジストリを導入する。
スーパーバイザによってタスクがクラッシュから再起動された際、物理的な Task ID や内部チャネルアドレスが変更されても、通信クライアントが論理名経由で最新の通信チャネルを透過的に取得・再バインドできるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](docs/designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連 Issue:
  - [Issue #633 (線形所有権移譲チャネル)](docs/issues/closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #666 (タスク間リンク・モニタ)](docs/issues/666-implement-synapse-task-links-and-monitors.md)
  - [Issue #667 (スーパービジョンツリー)](docs/issues/667-implement-synapse-supervision-tree-and-restart-strategies.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/registry.scm](ulisp/runtime/concurrency/registry.scm)（新規作成予定）
- [ ] [ulisp/runtime/concurrency/channel.scm](ulisp/runtime/concurrency/channel.scm)
- [ ] [tests/test_synapse_registry.py](tests/test_synapse_registry.py)（新規作成予定）

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/669-synapse-process-registry`

1. ロックフリーかつスレッドセーフな論理名レジストリ（シンボル名 $\to$ チャネル / Task Context）の実装。
2. プリミティブ API:
   - `(synapse-register! name ch-or-task)`: 名前の登録。
   - `(synapse-unregister! name)`: 名前の登録解除。
   - `(synapse-whereis name)`: 現在の有効な通信先チャネルの高速ルックアップ。
   - `(synapse-send-named! name msg)`: 名前解決を行いながら自動フォールバック送信する高レベル通信ユーティリティ。
3. タスク終了/再起動フックとの連動による、古い死んだタスクの自動 unregister または新タスクへのアトミックな差し替え。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 登録タスクがクラッシュ＆再起動した際、`whereis` により即座に新タスクのチャネルが取得できること。
- [ ] マルチコア環境（複数ワーカー）からの並行ルックアップ・登録がデータ競合なく実行できること。
- [ ] 未登録・終了済みタスクへの `synapse-send-named!` が適切なエラーコードを返し、デッドロックしないこと。

