---
ID: 050
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-08-20
---

# [FEAT] Merkle Tree（ハッシュツリー差分同期）& CRDT（無衝突レプリケーションデータ型）アンチエントロピー同期の実装 (ID: 050)

## 1. 概要 / Summary

[DSN-14 次世代データベースエンジン設計書](../../designs/DSN-14-database_engine_architecture.md) 第11.3節（CRDT）および第12章（アンチエントロピーと Merkle Tree）に基づき、ノード間のデータ不整合を $O(\log N)$ の通信量で高速検知・修復する **「Merkle Tree」** と、並行書き込みでも数学的に自律収束（半順序集合 Join-Semilattice）する **「CRDT（PN-Counter, OR-Set）」**、およびバックグラウンド自己修復を行う **「Anti-Entropy Synchronizer」** を `src/database/distributed/` に実装し、Phase 4 を完遂した。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../../designs/DSN-14-database_engine_architecture.md)
  - 11.3 調整とバージョンベクトル（LWW・CRDT・Read Repair）
  - 12. アンチエントロピーと Merkle Tree
  - 12.2 Merkle ツリー（ハッシュ木）と高速差分検出
  - 15. 次世代実装ロードマップ マイルストーン 14
- 関連クローズド Issue:
  - [Issue 049: Quorum レプリケーション（$W + R > N$ 強整合性）& Read Repair（読み取り時自動修復）の実装](closed/049-implement-quorum-replication-and-read-repair.md)
  - [Issue 048: $\Phi$ Accrual 障害検知器 & Gossip プロトコル（ハートビート分散伝播）の実装](closed/048-implement-phi-accrual-and-gossip-protocol.md)
  - [Issue 047: Vector Clock（論理時計因果追跡）& Version Vector 競合検知エンジンの実装](closed/047-implement-vector-clock-and-version-vector.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/distributed/merkle_tree.py](../../src/database/distributed/merkle_tree.py) (新規: MerkleNode, MerkleTree, 階層SHA-256ハッシュ計算, O(log N) 差分キー探索)
- [x] [src/database/distributed/crdt.py](../../src/database/distributed/crdt.py) (新規: PNCounter, ORSet, Join-Semilattice 自律マージ)
- [x] [src/database/distributed/anti_entropy.py](../../src/database/distributed/anti_entropy.py) (新規: AntiEntropySynchronizer, Merkle 差分抽出とレプリカ間データ同期)
- [x] [src/database/distributed/__init__.py](../../src/database/distributed/__init__.py) (エクスポート更新)
- [x] [src/database/__init__.py](../../src/database/__init__.py) (エクスポート更新)
- [x] [tests/database/test_merkle_and_crdt.py](../../tests/database/test_merkle_and_crdt.py) (新規: Merkle 差分検出、CRDT カウンタ・集合の可換・結合・冪等マージ検証、Anti-Entropy 同期検証)

---

## 4. 実装成果 / Implementation Results

Target Branch: `feat/050-merkle-crdt-anti-entropy`

### 4.1 Merkle Tree (`src/database/distributed/merkle_tree.py`)
- **階層ハッシュ木構造**:
  - レコード（キー＋値）の SHA-256 ハッシュをソート済みリーフとして完全二分木を構築。
  - 親ノードは $H_{\text{parent}} = \text{Hash}(H_{\text{left}} \mathbin{\Vert} H_{\text{right}})$ で算出。
  - `find_diff_keys(other)`: ルートハッシュが一致すれば即座に差分なし（0 I/O）で終了し、不一致時は不一致ブランチのみを $O(\log N)$ で下降走査して差分キー一覧を特定。

### 4.2 CRDT (無衝突レプリケーションデータ型) (`src/database/distributed/crdt.py`)
- **`PNCounter`**: 各ノードごとの加算カウンタ $P$ と減算カウンタ $N$ を管理し、$\max(P_1, P_2), \max(N_1, N_2)$ による結合半束（Join-Semilattice）マージで自律収束。
- **`ORSet[T]`**: 要素追加時に一意な UUID タグを生成し、削除時に観察済みタグを Remove-Set へ移動する Add-Wins 集合。並行追加・削除時でも安全に収束。

### 4.3 Anti-Entropy 同期 (`src/database/distributed/anti_entropy.py`)
- **`AntiEntropySynchronizer`**:
  - レプリカペアから Merkle Tree を構築・比較し、差分レコードのみを抽出して最新因果バージョンを双方向同期。

---

## 5. 完了条件検証 (DoD Verification)

- [x] 完全同一のデータセットでは Merkle Tree のルートハッシュが一致し、差分検出数が 0 件であること。
- [x] 1件のみ値が異なる大規模データセット（100件等）において、Merkle Tree 比較により該当キーのみが $O(\log N)$ でピンポイント特定されること。
- [x] CRDT（PN-Counter, OR-Set）が並行分散書き込みにおいて、マージ順序に依存せず同一状態へ自律収束すること（可換性・結合性・冪等性）。
- [x] `make check_format`, `make py_compile`, `make static_analysis` がエラー 0 件ですべて PASS すること。
- [x] 新規テストスイート（`tests/database/test_merkle_and_crdt.py`）が 100% PASS すること。
