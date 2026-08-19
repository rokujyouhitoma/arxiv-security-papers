---
ID: 048
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-08-20
---

# [FEAT] $\Phi$ Accrual 障害検知器 & Gossip プロトコル（ハートビート分散伝播）の実装 (ID: 048)

## 1. 概要 / Summary

[DSN-14 次世代データベースエンジン設計書](../../designs/DSN-14-database_engine_architecture.md) 第9章（障害検出・Phi Accrual 確率的検出器）およびマイルストーン 14（分散協調）に基づき、二値（UP/DOWN）ではなく確率的疑わしさ（Suspicion Level: $\Phi$）を出力する適応型障害検知器 **「$\Phi$ Accrual Failure Detector」** と、全ノード間でメンバーシップ・生存状態を自律伝播する **「Gossip Protocol」** を `src/database/distributed/` に実装した。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../../designs/DSN-14-database_engine_architecture.md)
  - 9. 障害検出（ハートビート・Ping-Ack・Phi Accrual 確率的検出器）
  - 9.2 Phi Accrual 障害検出器の数学モデルと適応制御
  - 15. 次世代実装ロードマップ マイルストーン 14
- 関連クローズド Issue:
  - [Issue 047: Vector Clock（論理時計因果追跡）& Version Vector 競合検知エンジンの実装](closed/047-implement-vector-clock-and-version-vector.md)
  - [Issue 046: Volcano 型ストリーミングイテレータ & ベクトル化バッチ実行エンジン（Vectorized Batch Execution）の実装](closed/046-implement-volcano-iterator-and-vectorized-execution.md)
  - [Issue 040: MVCC（多版同時実行制御）と SS2PL ロックマネージャ・デッドロック検知の実装](closed/040-implement-mvcc-and-ss2pl-transaction-manager.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/distributed/phi_accrual.py](../../src/database/distributed/phi_accrual.py) (新規: PhiAccrualDetector、到着間隔スライディングウィンドウ、正規/指数分布確率計算、Phi 値算出)
- [x] [src/database/distributed/gossip.py](../../src/database/distributed/gossip.py) (新規: NodeStatus, NodeState, GossipNode, ダイジェスト生成, ピア状態更新, 障害検知統合)
- [x] [src/database/distributed/__init__.py](../../src/database/distributed/__init__.py) (エクスポート更新)
- [x] [src/database/__init__.py](../../src/database/__init__.py) (エクスポート更新)
- [x] [tests/database/test_phi_accrual_and_gossip.py](../../tests/database/test_phi_accrual_and_gossip.py) (新規: Phi 値の連続推移検証、ネットワークジッター耐性、Gossip 分散伝播・障害検知検証)

---

## 4. 実装成果 / Implementation Results

Target Branch: `feat/048-phi-accrual-gossip`

### 4.1 $\Phi$ Accrual 障害検知器 (`src/database/distributed/phi_accrual.py`)
- **数学モデル**:
  - 直近 $W$ 件（1000件）の到着間隔 $\Delta t$ の平均 $\mu$・標準偏差 $\sigma$ をスライディングウィンドウで追跡。
  - 経過時間 $t$ に対する遅延確率 $P_{\text{later}}(t) = \frac{1}{2} \text{erfc}\left(\frac{t - \mu}{\sigma \sqrt{2}}\right)$ を算出。大きな $y$ に対する漸近展開近似によりアンダーフローを完全防止。
  - 疑わしさ尺度 $\Phi = -\log_{10}(P_{\text{later}}(t))$ を連続値として提供。
- **適応的判定**:
  - $\Phi < 8$: `ALIVE`（正常）
  - $8 \le \Phi < 12$: `SUSPECT`（一時的遅延・警戒）
  - $\Phi \ge 12$: `DEAD`（完全障害・フェイルオーバー対象）

### 4.2 Gossip プロトコル (`src/database/distributed/gossip.py`)
- **`NodeState`**: 各ノードの世代番号（generation）、シーケンス番号（heartbeat_seq）、状態（ALIVE/SUSPECT/DEAD）、メタデータ、および `PhiAccrualDetector` を内包。
- **`GossipNode`**:
  - 定期的に自ノードのシーケンス番号を更新し、ピアへダイジェストを送信。
  - 受信メッセージをマージし、世代・シーケンス番号の比較により最新状態へ自律収束。
  - `check_failure_states()` で各ピアの $\Phi$ 値に基づき状態を自動遷移。

---

## 5. 完了条件検証 (DoD Verification)

- [x] 定常的なハートビート受信時は $\Phi$ が低く維持され、受信途絶時に時間経過とともに $\Phi$ が単調増加すること。
- [x] ネットワークジッター（一時的な遅延）発生時でも誤判定せず、持続的な無応答のみを $\Phi \ge 12$（DEAD）として検出すること。
- [x] 3ノード以上の Gossip ネットワークで、1ノードの更新や障害状態が全ノードへ確実に伝播されること。
- [x] `make check_format`, `make py_compile`, `make static_analysis` がエラー 0 件ですべて PASS すること。
- [x] 新規テストスイート（`tests/database/test_phi_accrual_and_gossip.py`）が 100% PASS すること。
