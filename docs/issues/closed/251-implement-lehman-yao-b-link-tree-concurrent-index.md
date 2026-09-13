---
ID: 251
種別: Feature
優先度: Low
ステータス: Closed
---

# [FEAT/DATABASE] Lehman-Yao 型 B-link Tree によるラッチフリー並行走査およびスプリット追随インデックスエンジンの実装 (ID: 251)

## 1. 概要 / Summary

本 Issue では、自作 DBMS のインデックスエンジン [`src/database/btree/`](../../src/database/btree) において、並行読み書き性能と走査のスケーラビリティを向上させるため、Lehman & Yao (1981) の古典的・標準的アルゴリズムに基づく **B-link Tree（High Key + Right Pointer）ラッチフリー並行走査機構** を実装する。

現状の B+Tree（[`src/database/btree/tree.py`](../../src/database/btree/tree.py)）は 4KB ページ単位の構造を持つが、ノード分割（Split）時に親ノードへの排他ロックが不可避であり、読み取り処理と書き込み処理の競合が発生する。B-link Tree を導入することで、各内部ノードおよびリーフノードに「High Key（ノードが保持するキーの上限）」と「右兄弟ポインタ（Right Link / Sibling Pointer）」を保持させ、ノード分割の最中でもリーダー（Reader）が親ノードのラッチを再獲得することなく右ポインタを辿って（Right Drift）正しいキーを探索できるラッチフリー / 細粒度並行走査を実現する。

---

## 2. トレーサビリティ & セキュリティ脅威分析 / Traceability & STRIDE Threat Model

- **学術論文・仕様標準**:
  - P. L. Lehman and S. B. Yao, *"Efficient Locking for Concurrent Operations on B-Trees"*, ACM Transactions on Database Systems (TODS), Vol. 6, No. 4, pp. 650–670, 1981.
- **関連設計書**:
  - [`docs/designs/DSN-05-database_engine_architecture.md`](../designs/DSN-05-database_engine_architecture.md) (4.4 並行性制御とラッチ Latch Crabbing & B-link / 4.5 Bツリー実装要約)
  - [`docs/designs/DSN-02-low_level_design.md`](../designs/DSN-02-low_level_design.md) (Database Engine & Storage Components)
- **先行 Issue**:
  - [Issue #033: Enhance Database with BTree Index and Cost-Based Planner](033-enhance-database-with-btree-index-and-cost-based-planner.md)
  - [Issue #043: Implement COW-BTree and MMAP Zero-Copy](043-implement-cow-btree-and-mmap-zero-copy.md)
- **セキュリティ脅威分析 (STRIDE)**:
  - **Denial of Service (DoS / 無限ループ・デッドロック)**:
    - *脅威*: 破損ページや右ポインタの循環参照による `move_right` 探索の無限ループ、または親子ノード間のラッチ競合によるデッドロック。
    - *対策*: `move_right` 走査時の循環検知（訪問済み Page ID の追跡、またはツリー総ページ数に基づく最大ホップ数制限 `max_hops = max(1024, len(_nodes))`）の実装。下方向および右方向への一方向ラッチ順序付けによるデッドロック完全排除。
  - **Tampering (データ改ざん・不整合)**:
    - *脅威*: マルチスレッド書き込み中に、ノード分割（Half-Split）が途中で中断・競合し、High Key と実際の格納キーの順序不整合が発生する。
    - *対策*: Split 操作における厳密な 2 段階コミット順序（新ノード作成・書き込み $\to$ 元ノードの High Key & Right Link 更新・書き込み $\to$ 親ノードへの伝播）の順序保証。不変条件検証アサーションの追加。
  - **Information Disclosure (情報漏洩)**:
    - *対策*: ページシリアライズ時の残余バイト（パディング）における未初期化メモリ漏洩防止（`\x00` 埋めの徹底）。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/database/btree/node.py`](../../src/database/btree/node.py): `BTreeNode` への `high_key` および `right_link` フィールド追加、シリアライズ/デシリアライズの拡張、B-link 型 Split メソッドの実装
- [x] [`src/database/btree/tree.py`](../../src/database/btree/tree.py): Lehman-Yao B-link 下降走査 (`_move_right`)、アトミック Half-Split、親ノード非同期伝播、および並行ラッチ機構の統合
- [x] [`src/database/btree/__init__.py`](../../src/database/btree/__init__.py): エクスポートシンボルの整備
- [x] [`tests/database/btree/test_blink_tree.py`](../../tests/database/btree/test_blink_tree.py) (新規): B-link Tree の High Key 境界検証、Half-Split 走査テスト、マルチスレッド並行読み書きストレステスト

---

## 4. 技術仕様 & アルゴリズム詳細 / Technical Specification

### 4.1 B-link Tree の数学的不変条件 (Invariants)
任意のノード $u$ において：
1. **High Key Invariant**:
   $$k \le \text{high\_key}(u) \quad (\forall k \in \text{keys}(u))$$
   最右端ノード（`right_link is None`）の場合、$\text{high\_key}(u) = \infty$ (`None`)。
2. **Right Link Invariant**:
   ノード $u$ の右隣ノード $v = \text{read\_node}(u.\text{right\_link})$ に対し：
   $$\text{high\_key}(u) < k \quad (\forall k \in \text{keys}(v))$$
3. **Right Drift Invariant**:
   探索キー $k$ に対し、もし $\text{high\_key}(u) \ne \text{None} \land k > \text{high\_key}(u)$ であれば、ターゲットキーは必ず $u.\text{right\_link}$ から到達可能な右兄弟ノード群に存在する。

### 4.2 Lehman-Yao 探索 (Search / Scan) アルゴリズム
```python
def _move_right(self, node: BTreeNode, key: ScalarKey) -> BTreeNode:
    curr = node
    hops = 0
    visited = {curr.page_id}
    while curr.high_key is not None and compare_keys(key, curr.high_key) > 0:
        if curr.right_link is None:
            break
        curr, hops = self._step_right(curr, visited, hops)
    return curr
```

### 4.3 2 段階ノード分割 (Atomic Half-Split) アルゴリズム
1. **フェーズ 1 (新右ノードの先行永続化)**:
   - 新ページ $B$ を割り当て。
   - $A$ のキー・値（または子ポインタ）の後半を $B$ に移動。
   - $B.\text{high\_key} \leftarrow A.\text{high\_key}$
   - $B.\text{right\_link} \leftarrow A.\text{right\_link}$
   - $B$ をページャ / メモリに書き込み（この時点で $B$ は孤立しており誰も参照不可）。
2. **フェーズ 2 (元ノードのリンク切替)**:
   - $A.\text{high\_key} \leftarrow \text{promoted\_key}$ ($A$ の最大キー)
   - $A.\text{right\_link} \leftarrow B.\text{page\_id}$
   - $A$ を書き込み。**この時点でスプリットが成立**し、親ノードが未更新でもリーダーは $A \to B$ を辿れる。
3. **フェーズ 3 (親ノードへの伝播)**:
   - 親ノードへ $(A.\text{high\_key}, B.\text{page\_id})$ を挿入。親が満杯なら同様に B-link 分割をボトムアップに適用。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/251-implement-lehman-yao-b-link-tree-concurrent-index`

1. **`src/database/btree/node.py` の改修**:
   - `BTreeNode.__init__` に `high_key: Optional[ScalarKey] = None` および `right_link: Optional[int] = None` を追加。
   - 既存の `next_leaf` との相互互換性を確保（`right_link` をプライマリとし、`next_leaf` をプロパティまたはエイリアスとして維持）。
   - `serialize()` / `deserialize()` に `high_key` と `right_link` を含め、4096 バイト制限内で正しく JSON エンコード。
   - `split(new_page_id: int)` を B-link 仕様に改修：
     - リーフ分割および内部ノード分割の双方で High Key を厳密計算。
     - $B.\text{right\_link} = A.\text{right\_link}$, $A.\text{right\_link} = B.\text{page\_id}$ のリンク付け。
     - 戻り値として `(promoted_key, sibling)` を返却。
2. **`src/database/btree/tree.py` の改修**:
   - `_move_right(node: BTreeNode, key: ScalarKey) -> BTreeNode` の実装。
   - `_find_leaf(key: ScalarKey)` において、内部ノード下降時およびリーフ到達時に `_move_right` を適用。
   - 細粒度ページラッチ機構（`_page_latches: Dict[int, threading.RLock]`）を導入し、スプリット書き込み時のみ対象ノードをロック。
   - `insert` における Half-Split 順序の厳密化（新ノード永続化 $\to$ 旧ノード永続化 $\to$ 親更新）。
   - `range_scan` において `right_link` を走査し、ノード境界を跨ぐ連続スキャンを保証。
3. **テストスイートの作成 (`tests/database/btree/test_blink_tree.py`)**:
   - `test_blink_node_high_key_split()`: ノード単体での High Key および Right Link の整合性検証。
   - `test_blink_tree_half_split_reader_drift()`: 親ノード未更新状態で分割されたノードに対し、リーダーが `right_link` を辿ってデータを正常取得できることの単体検証。
   - `test_blink_tree_multithreaded_concurrent_crud()`: 10 本以上のスレッドによる同時 INSERT および連続 RANGE SCAN/POINT LOOKUP のストレステスト（データロスト 0 件、例外 0 件）。
   - 既存 `tests/database/btree/test_btree.py` のリグレッションなし（全 PASS）。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `BTreeNode` で `high_key` および `right_link` が内部・リーフ問わず正しくシリアライズ/デシリアライズできること。
- [x] 分割中（親未更新状態）のノード探索において、リーダーが右リンクを辿って最新データを正しく取得できること（Right Drift の実証）。
- [x] 1000 件以上のデータ挿入およびマルチスレッド並行実行テストで競合エラーやデータ欠損が発生しないこと。
- [x] 新設テスト `tests/database/btree/test_blink_tree.py` および既存 `tests/database/btree/test_btree.py` が全件 PASS すること。
- [x] `make check_format` および `make static_analysis` (radon, xenon Grade A, mypy strict) がエラー 0 件で通過すること。

---

## 7. 検証手順 / Verification Procedure

1. **単体テスト実行**:
   ```bash
   .venv/bin/pytest tests/database/btree/ -v
   ```
2. **静的解析・型チェック**:
   ```bash
   make check_format
   make static_analysis
   ```
