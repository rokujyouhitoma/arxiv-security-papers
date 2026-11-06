---
ID: 751
種別: Bug
優先度: Low
ステータス: Open (In Progress)
---

# [BUG/SEC] Supervisor 受信ループにおける非 DOWN シグナル (EXIT, io_complete 等) の破棄防止 (ID: 751)

## 1. 概要 / Summary
Supervisor のシグナル取得処理 `supervisor-poll-down-signals!` において、受信メッセージのうち `DOWN` 以外のメッセージ（`EXIT` や `io_complete` 等）が無条件に捨てられている。
これにより、Supervisor が将来的に外部プロセスと Link した場合や非同期 I/O を実行した際に、受信した正当な通知メッセージがロストする不具合・設計不備が存在する。

### 再現手順 / Steps to Reproduce
1. Supervisor のタスクメールボックス宛てに `(EXIT <from> <reason>)` または `io_complete` メッセージを送信する。
2. Supervisor のポーリング関数 `supervisor-poll-down-signals!` を実行する。
3. `DOWN` 以外のメッセージがフィルタリングによって破棄され、メールボックスから完全に消失する。

### 再現環境 / Environment
- OS / Env: All Platforms
- File: `ulisp/runtime/concurrency/supervisor.scm`
- 関連 Issue: Follow-up of #727

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/runtime/concurrency/supervisor.scm`](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [`ulisp/tests/test_supervisor.scm`](../../ulisp/tests/test_supervisor.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
Supervisor のシグナル処理関数が `DOWN` メッセージの処理のみに特化して書かれており、マッチしなかったメッセージを保持（未読キューに戻すか別ハンドラへ転送）する機構を持たず、単に無視して discard していたため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: Supervisor 宛てには `DOWN` シグナル以外を送信しない運用にする。
* **恒久対策 (Permanent Fix)**: メッセージ種別ごとのディスパッチテーブルを導入し、未対応メッセージは破棄せずメールボックス内に保持（保留）するか、Supervisor の汎用メッセージハンドラへ渡す。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/751-preserve-non-down-signals-in-supervisor-inbox`

1. `ulisp/runtime/concurrency/supervisor.scm`:
   - `supervisor-poll-down-signals!` をリファクタリングし、`DOWN` 以外のメッセージを未処理メッセージキューに退避するか、種別判定して適切なコールバック（`supervisor-handle-exit!`, `supervisor-handle-custom-msg!` 等）へ振り分ける。
2. `ulisp/tests/test_supervisor.scm`:
   - 異種メッセージが混在するメールボックスから `DOWN` のみを抽出処理した後も、その他のメッセージがロストせず保持されていることを検証するテストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] Supervisor 受信処理で `DOWN` 以外の有効なメッセージが意図せず破棄されないこと
- [ ] 未処理メッセージが安全に保持またはディスパッチされること
- [ ] `ulisp/tests/test_supervisor.scm` が PASS すること

