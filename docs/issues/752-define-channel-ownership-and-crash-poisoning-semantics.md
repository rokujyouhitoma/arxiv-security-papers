---
ID: 752
種別: Feature
優先度: Low
ステータス: Open (In Progress)
---

# [FEAT/ENH] チャネル所有権セマンティクスおよびクラッシュ時自動汚染範囲の仕様策定・実装 (ID: 752)

## 1. 概要 / Summary
あるタスクが作成したチャネルを他タスクに渡して利用している場合であっても、チャネルを生成した側のタスクがクラッシュすると、そのチャネルが自動的に異常状態として汚染（poisoned / closed）されてしまう。
これは Erlang/OTP のメッセージパッシングの振る舞い（受信箱やパイプラインの独立性）と異なっており、パイプライン処理やプロデューサー・コンシューマー構成において意図しない波及クラッシュを引き起こす。
チャネルの「所有権（Ownership）の移転」を導入するか、あるいは「生成タスク死亡時の自動汚染対象から外す」か、設計方針を明確化し実装する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue: Follow-up of #731
- 関連資料: Erlang/OTP ポート設計原則、Rust mpsc 所有権セマンティクス、DSN-11 並行性設計書

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/runtime/concurrency/channel.scm`](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [`ulisp/runtime/concurrency/links.scm`](../../ulisp/runtime/concurrency/links.scm)
- [ ] [`ulisp/tests/test_channel.scm`](../../ulisp/tests/test_channel.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/752-define-channel-ownership-and-crash-poisoning-semantics`

1. 設計策定:
   - チャネルの端点（送信端・受信端）の所有権モデルを策定。
   - 方式A（明示的所有権移転 `channel-transfer!`）または 方式B（チャネル自体を独立リソースとし、生成タスクの生存期間に縛られないモデル）の採否を決定。
2. `ulisp/runtime/concurrency/channel.scm`:
   - 決定した設計に従い、タスク終了時のリソース解放フック（`task-cleanup-resources!`）において、他タスクに引き渡されたチャネルを不要にクローズ・汚染しないロジックを実装。
3. `ulisp/tests/test_channel.scm`:
   - 生成元タスクがクラッシュ・終了した後も、受領側タスクがチャネル内の残存データを安全に読み取れること（EOF または正常ドレイン）を検証するテストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] チャネル所有権およびクラッシュ時の汚染範囲に関する設計ドキュメントが整理されること
- [ ] 生成元タスクの終了によって生存中のコンシューマ側が不当に道連れクラッシュしないこと
- [ ] `ulisp/tests/test_channel.scm` が PASS すること

