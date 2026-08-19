---
ID: 049
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-08-20
---

# [FEAT] Quorum レプリケーション（$W + R > N$ 強整合性）& Read Repair（読み取り時自動修復）の実装 (ID: 049)

## 1. 概要 / Summary

[DSN-14 次世代データベースエンジン設計書](../../designs/DSN-14-database_engine_architecture.md) 第11章（クォーラムと結果整合性）およびマイルストーン 14（分散協調・レプリケーション）に基づき、リーダーレス分散アーキテクチャにおける厳格なクォーラム合意（Strict Quorum: $W + R > N$）と、読み取り時に古いレプリカを最新版へ自動同期する **「Read Repair（読み取り時自動修復）」** および **「Hinted Handoff（ヒント付きハンドオフ）」** を `src/database/distributed/` に実装した。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../../designs/DSN-14-database_engine_architecture.md)
  - 11. レプリケーション・モデルとクォーラム
  - 11.2 クォーラムと結果整合性（厳格 vs スロッピークォーラム・ヒント付きハンドオフ）
  - 11.3 調整とバージョンベクトル（LWW・CRDT・Read Repair）
  - 15. 次世代実装ロードマップ マイルストーン 14
- 関連クローズド Issue:
  - [Issue 048: $\Phi$ Accrual 障害検知器 & Gossip プロトコル（ハートビート分散伝播）の実装](closed/048-implement-phi-accrual-and-gossip-protocol.md)
  - [Issue 047: Vector Clock（論理時計因果追跡）& Version Vector 競合検知エンジンの実装](closed/047-implement-vector-clock-and-version-vector.md)
  - [Issue 046: Volcano 型ストリーミングイテレータ & ベクトル化バッチ実行エンジン（Vectorized Batch Execution）の実装](closed/046-implement-volcano-iterator-and-vectorized-execution.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/distributed/quorum.py](../../src/database/distributed/quorum.py) (新規: QuorumReplica, QuorumCoordinator, W/R Quorum 合意、Read Repair 自動修復)
- [x] [src/database/distributed/hinted_handoff.py](../../src/database/distributed/hinted_handoff.py) (新規: Hint, HintedHandoffManager, 一時代行保管と復帰時フラッシュ同期)
- [x] [src/database/distributed/__init__.py](../../src/database/distributed/__init__.py) (エクスポート更新)
- [x] [src/database/__init__.py](../../src/database/__init__.py) (エクスポート更新)
- [x] [tests/database/test_quorum_and_read_repair.py](../../tests/database/test_quorum_and_read_repair.py) (新規: Strict Quorum 読み書き検証、陳腐化レプリカの Read Repair 検証、Hinted Handoff 復帰同期検証)

---

## 4. 実装成果 / Implementation Results

Target Branch: `feat/049-quorum-read-repair`

### 4.1 Quorum レプリケーション & Read Repair (`src/database/distributed/quorum.py`)
- **`QuorumCoordinator`**:
  - $N$ 台のレプリカに対し、書き込み $W$、読み取り $R$ の合意判定を実施。
  - `is_strict_quorum()`: $W + R > N$（鳩の巣原理による強整合性保証）。
  - `write(key, value)`: 各オンラインレプリカへ VectorClock 付きで書き込み、$W$ 台以上の成功でコミット。
  - `read(key, enable_read_repair=True)`: $R$ 台から読み取り、最新因果バージョンを抽出。古い値を持つレプリカを特定し、バックグラウンド/同期で最新値を上書き（Read Repair）。

### 4.2 Hinted Handoff (`src/database/distributed/hinted_handoff.py`)
- **`HintedHandoffManager`**:
  - レプリカダウン時に、本来の宛先ノード向けの書き込みをヒント（`Hint`）として代行ノードに一時バッファリング。
  - 対象レプリカが復帰（`is_online = True`）した際に `flush_hints_for_node()` で一括転送・同期。

---

## 5. 完了条件検証 (DoD Verification)

- [x] $N=3, W=2, R=2$ の Strict Quorum 環境で、1ノードダウン時でも最新データが 100% 正確に読み書きできること（鳩の巣原理）。
- [x] 読み取り時に古い値を持つレプリカが検出された場合、Read Repair により自動的に最新値へと更新・修復されること。
- [x] 一時障害ノード宛の書き込みが Hinted Handoff に保存され、復帰後に正常に転送・反映されること。
- [x] `make check_format`, `make py_compile`, `make static_analysis` がエラー 0 件ですべて PASS すること。
- [x] 新規テストスイート（`tests/database/test_quorum_and_read_repair.py`）が 100% PASS すること。
