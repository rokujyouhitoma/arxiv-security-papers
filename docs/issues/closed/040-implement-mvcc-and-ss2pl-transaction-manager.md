---
ID: 040
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-08-20
---

# [FEAT] MVCC（多版同時実行制御）と SS2PL ロックマネージャ・デッドロック検知の実装 (ID: 040)

## 1. 概要 / Summary

[DSN-14 第5.4節 同時実行制御と分離レベル（SS2PL / MVCC / SSI）](../../designs/DSN-14-database_engine_architecture.md#54-同時実行制御と分離レベルss2pl--mvcc--ssi) および マイルストーン3 に基づき、`src/database/` における超高並行性トランザクション処理基盤となる **「MVCC（多版同時実行制御）エンジンおよび SS2PL（Strict 2-Phase Locking）ロックマネージャ・待機グラフ（Wait-For Graph）デッドロック検知機構」** をゼロ依存（Python 標準ライブラリ）で実装した。

「読み取りは書き込みをブロックせず、書き込みは読み取りをブロックしない」スナップショット分離（Snapshot Isolation: SI）と、更新トランザクション間の厳格な2相ロック・DFS閉路検出によるデッドロック自動解消を実現した。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../../designs/DSN-14-database_engine_architecture.md)
  - 5.4 同時実行制御と分離レベル（SS2PL / MVCC / SSI）
  - 15. 次世代実装ロードマップ マイルストーン 3
- 関連クローズド Issue:
  - [Issue 039: 追記型永続WALファイルとARIESクラッシュリカバリマネージャの実装](039-implement-disk-persistent-wal-and-aries-recovery.md)
  - [Issue 038: スロット化ページ（Slotted-Page）バイナリストレージエンジンの実装](038-implement-slotted-page-binary-storage-engine.md)
  - [Issue 027: ゼロ依存 / 純Python製 5大SQLコマンド体系エンジンおよび接続インターフェースの実装](closed/027-pure-python-sql-engine-support.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/mvcc.py](../../src/database/mvcc.py) (新規: xmin/xmax 多版タプル管理、TransactionSnapshot、Snapshot Isolation 可視性チェッカー、VACUUM)
- [x] [src/database/lock_manager.py](../../src/database/lock_manager.py) (新規: Shared(S)/Exclusive(X)/Intent(IS/IX) ロックテーブル、SS2PL ライフサイクル、Wait-For Graph DFS デッドロック検知)
- [x] [src/database/sql/transaction.py](../../src/database/sql/transaction.py) (変更: MVCC Snapshot & SS2PL LockManager 統合)
- [x] [src/database/__init__.py](../../src/database/__init__.py) (エクスポート更新)
- [x] [tests/database/test_mvcc_and_ss2pl.py](../../tests/database/test_mvcc_and_ss2pl.py) (新規: MVCC 可視性、スナップショット分離、SS2PL 並行ロック競合、デッドロック検知・Victim アボート網羅テスト)

---

## 4. 実装成果 / Implementation Results

Target Branch: `feat/040-mvcc-and-ss2pl`

### 4.1 MVCC（多版同時実行制御）エンジン (`src/database/mvcc.py`)
- **多版タプル (`VersionedTuple`)**: `xmin`（作成TxID）、`xmax`（削除/更新TxID、0なら現行有効）、`data`、`created_at` を保持。
- **スナップショット分離 (`TransactionSnapshot`)**: トランザクション開始時のアクティブTx群（`active_tx_ids`）およびコミット済みTx群（`committed_tx_ids`）を不変スナップショットとして固定。
- **可視性判定 (`is_visible`)**:
  - 自身が作成したタプルは可視。
  - スナップショット開始時点で未コミットまたは未来のTxが作成したタプルは不可視。
  - スナップショット開始以降に削除されたタプルは依然として可視（Repeatable Read 保証）。
- **First-Committer-Wins 競合検知**: 未コミットの並行トランザクションが同一タプルを変更しようとした場合に即座に競合エラーを送出。
- **VACUUM ゴミ回収 (`vacuum()`)**: 最古のアクティブトランザクションより前に削除コミットされた不要バージョンを安全にパージ。

### 4.2 SS2PL ロックマネージャ & 待機グラフ (`src/database/lock_manager.py`)
- **ロックモード (`LockMode`)**: `SHARED (S)`, `EXCLUSIVE (X)`, `INTENT_SHARED (IS)`, `INTENT_EXCLUSIVE (IX)`。
- **互換性マトリクス (`_COMPATIBILITY_MATRIX`)**: S-S, S-IS, IS-IS, IS-IX を許可し、X-Lock の完全排他性を保証。
- **待機グラフ (`WaitForGraph`)**: トランザクション間の待機依存関係を有向辺（$T_{waiter} \to T_{holder}$）として管理。
- **デッドロック検知 & 被害者選定**: DFS による閉路検出アルゴリズムを実装し、相互待機発生時に `DeadlockError` を送出して被害者 Tx をアボート。
- **SS2PL（Strict 2-Phase Locking）**: トランザクション完了時（コミットまたはロールバック）に全ロックを一括解放（`release_all_locks`）し、後続の待機トランザクションを `notify_all` で安全に起床。

### 4.3 TransactionManager 統合 (`src/database/sql/transaction.py`)
- `begin()` 時に MVCC スナップショットを自動取得。
- `acquire_lock()` によるリソース単位の SS2PL ロック獲得。
- `commit()` / `rollback()` 時に MVCC 状態遷移と SS2PL ロック一括解放をシームレスに連動。

---

## 5. 完了条件検証 (DoD Verification)

- [x] MVCC 多版タプル管理と Snapshot Isolation（SI）により、書き込み中でも読み取りが一貫した過去スナップショットをノンブロッキングで取得できること。
- [x] SS2PL ロックマネージャにより、共有(S)／排他(X)ロックの競合制御およびコミット・ロールバック時の一括解放が正常動作すること。
- [x] 2つ以上のトランザクションによる相互待機（デッドロック）が Wait-For Graph の閉路検知によって即座に検出され、Victim がアボートされること。
- [x] `make check_format`, `make py_compile`, `make static_analysis` がエラー 0 件ですべて PASS すること。
- [x] 新規テストスイート（`tests/database/test_mvcc_and_ss2pl.py`）が 100% PASS すること。
