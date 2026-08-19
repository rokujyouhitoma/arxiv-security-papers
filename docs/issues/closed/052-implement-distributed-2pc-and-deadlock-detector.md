---
ID: 052
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-08-20
---

# [FEAT] 分散 2相コミット（Distributed 2PC）& 分散デッドロック検知の実装 (ID: 052)

## 1. 概要 / Summary

[DSN-14 次世代データベースエンジン設計書](../../designs/DSN-14-database_engine_architecture.md) 第13.2節（2フェーズコミット 2PC）およびマイルストーン 15（分散合意 & 分散トランザクション）に基づき、複数ノードにまたがるアトミックトランザクションコミットを保証する **「Distributed 2PC (Coordinator / Participant, Prepare / Commit / Abort)」** および分散ロック待ちグラフ（Wait-For Graph）による **「Distributed Deadlock Detector」** を `src/database/distributed/two_pc/` に実装した。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../../designs/DSN-14-database_engine_architecture.md)
  - 13. 分散トランザクション（アトミックコミット・2PC・3PC・Sagaパターン）
  - 13.2 2フェーズコミット（2PC）とブロッキング課題
  - 15. 次世代実装ロードマップ マイルストーン 15
- 関連クローズド Issue:
  - [Issue 051: Raft SMR（ステートマシンレプリケーション）合意アルゴリズムの実装](closed/051-implement-raft-consensus-and-smr.md)
  - [Issue 050: Merkle Tree（ハッシュツリー差分同期）& CRDT（無衝突レプリケーションデータ型）アンチエントロピー同期の実装](closed/050-implement-merkle-tree-and-crdt-anti-entropy.md)
  - [Issue 049: Quorum レプリケーション（$W + R > N$ 強整合性）& Read Repair（読み取り時自動修復）の実装](closed/049-implement-quorum-replication-and-read-repair.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/distributed/two_pc/types.py](../../src/database/distributed/two_pc/types.py) (新規: TwoPCState, VoteType, GlobalDecision, TxRecord)
- [x] [src/database/distributed/two_pc/participant.py](../../src/database/distributed/two_pc/participant.py) (新規: TwoPCParticipant, Prepare時リソースロック, Commit/Abort処理)
- [x] [src/database/distributed/two_pc/coordinator.py](../../src/database/distributed/two_pc/coordinator.py) (新規: TwoPCCoordinator, Phase 1 Prepare投票集約, Phase 2 Commit/Abortブロードキャスト)
- [x] [src/database/distributed/two_pc/deadlock.py](../../src/database/distributed/two_pc/deadlock.py) (新規: DistributedDeadlockDetector, Wait-For Graph サイクル検知)
- [x] [src/database/distributed/two_pc/__init__.py](../../src/database/distributed/two_pc/__init__.py) (新規: 2PC サブシステムエクスポート)
- [x] [src/database/distributed/__init__.py](../../src/database/distributed/__init__.py) (エクスポート更新)
- [x] [src/database/__init__.py](../../src/database/__init__.py) (エクスポート更新)
- [x] [tests/database/test_two_phase_commit.py](../../tests/database/test_two_phase_commit.py) (新規: 正常コミット、一部Participantアボート時の全ノードロールバック、分散デッドロック検知テスト)

---

## 4. 実装成果 / Implementation Results

Target Branch: `feat/052-distributed-2pc-and-deadlock`

### 4.1 2PC 状態・メッセージ型 (`src/database/distributed/two_pc/types.py`)
- `TwoPCState`: `INITIAL`, `PREPARED`, `COMMITTED`, `ABORTED`。
- `VoteType`: `VOTE_COMMIT`, `VOTE_ABORT`。
- `GlobalDecision`: `GLOBAL_COMMIT`, `GLOBAL_ABORT`。
- `TxRecord`: トランザクションID、参加者リスト、現在のグローバル状態、ペイロード。

### 4.2 Participant (`src/database/distributed/two_pc/participant.py`)
- **`TwoPCParticipant`**:
  - `prepare()`: リソースロックを排他的に確保し、`PREPARED` 状態へ遷移。競合時は `VOTE_ABORT`。
  - `commit()`: トランザクションを確定しロックを解放、`COMMITTED` へ遷移。
  - `abort()`: トランザクションを破棄しロックを解放、`ABORTED` へ遷移。

### 4.3 Coordinator (`src/database/distributed/two_pc/coordinator.py`)
- **`TwoPCCoordinator`**:
  - Phase 1 (Prepare): 各参加者へ `prepare()` を送信。全員 `VOTE_COMMIT` なら `GLOBAL_COMMIT`、1つでも `VOTE_ABORT` またはエラーなら `GLOBAL_ABORT`。
  - Phase 2 (Commit/Abort): 決定内容を全参加者へブロードキャストし、ローカル状態を確定。

### 4.4 分散デッドロック検知 (`src/database/distributed/two_pc/deadlock.py`)
- **`DistributedDeadlockDetector`**:
  - トランザクション間の待ち関係を有向グラフ（Wait-For Graph）として追跡。
  - 深さ優先探索（DFS）による循環待ち（Cycle）検知と被害者選出（Victim Selection）。

---

## 5. 完了条件検証 (DoD Verification)

- [x] 全参加者がコミット可能な場合、全ノードがアトミックに `COMMITTED` となりロックが解放されること。
- [x] 1つの参加者でもアボート（リソースロック失敗等）を返した場合、全参加者が一律に `ABORTED`（ロールバック）されること。
- [x] トランザクション間の相互待ち（$T_1 \to T_2 \to T_1$ 等）が発生した際、デッドロックが正確に検知されること。
- [x] `make check_format`, `make py_compile`, `make static_analysis` がエラー 0 件ですべて PASS すること。
- [x] 新規テストスイート（`tests/database/test_two_phase_commit.py`）が 100% PASS すること。
