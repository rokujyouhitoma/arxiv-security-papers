---
ID: 251
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/DATABASE] Lehman-Yao 型 B-link Tree によるラッチフリー並行走査およびスプリット追随インデックスエンジンの実装 (ID: 251)

## 1. 概要 / Summary

本 Issue では、自作 DBMS のインデックスエンジン [`src/database/btree/`](../../src/database/btree) において、並行読み書き性能と走査のスケーラビリティを向上させるため、Lehman & Yao (1981) のアルゴリズムに基づく **B-link Tree（High Key + Right Pointer）ラッチフリー並行走査機構** を実装する。

現状の B+Tree（[`src/database/btree/tree.py`](../../src/database/btree/tree.py)）は 4KB ページ単位の構造を持つが、ノード分割（Split）時に親ノードへの排他ロックが不可避であり、読み取り処理と書き込み処理の競合が発生する。B-link Tree を導入することで、各内部・リーフノードに「High Key（ノードが保持するキーの上限）」と「右兄弟ポインタ（Right Sibling Link）」を保持させ、ノード分割の最中でもリーダー（Reader）が右ポインタを辿って正しいキーを探索できるラッチフリー / 細粒度並行走査を実現する。

---

## 2. トレーサビリティ / Traceability

- **設計書**:
  - [`docs/designs/DSN-05-database_engine_architecture.md`](../designs/DSN-05-database_engine_architecture.md) (7.1 B-link Tree & Concurrency Control)
  - [`docs/designs/DSN-02-low_level_design.md`](../designs/DSN-02-low_level_design.md) (Database Engine & Storage Components)
- **先行 Issue**:
  - [Issue #033: Enhance Database with BTree Index and Cost-Based Planner](closed/033-enhance-database-with-btree-index-and-cost-based-planner.md)
  - [Issue #043: Implement COW-BTree and MMAP Zero-Copy](closed/043-implement-cow-btree-and-mmap-zero-copy.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/database/btree/node.py`](../../src/database/btree/node.py) (High Key フィールドおよびシリアライズ/デシリアライズの拡張)
- [ ] [`src/database/btree/tree.py`](../../src/database/btree/tree.py) (B-link 走査・右ポインタ追随 Split アルゴリズムの統合)
- [ ] [`tests/database/test_blink_tree.py`](../../tests/database/test_blink_tree.py) (新規: B-link Tree 並行分割・走査単体/結合テスト)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/251-implement-lehman-yao-b-link-tree-concurrent-index`

1. **ノード仕様の拡張 (`src/database/btree/node.py`)**:
   - `BTreeNode` に `high_key: Optional[ScalarKey]`（ノード内に格納可能なキーの上限）を導入。
   - 既存の `next_leaf`（リーフのみ）を内部ノードにも拡張し、`right_sibling_page_id: Optional[int]` として統一。
   - 4096 バイトのバイナリページヘッダに `high_key` 長・エンコード値、および右ポインタの永続化フォーマットを統合。
2. **B-link 探索・分割アルゴリズムの実装 (`src/database/btree/tree.py`)**:
   - **並行走査 (Search / Scan)**: 現在のノードの `high_key` を確認し、探索キー $k > \text{high\_key}$ であれば右兄弟ポインタを辿って（Right Drift）走査を継続（親ノードのラッチを保持せずに分割中のノードを安全にスキップ）。
   - **非同期親更新 (Atomic Half-Split)**: 右側ノードを割り当ててキーを移動し、右ポインタと High Key を設定した時点で新ノードを公開。親ノードへのポインタ挿入は後続のボトムアップ処理として非同期/遅延実行可能にする。
3. **テストスイートの作成**:
   - マルチスレッド並行環境下での大量挿入・範囲スキャン整合性テスト。
   - スプリット発生中のリーダーによるデータロスト・不整合ゼロの検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/database/btree/node.py` で `high_key` および右兄弟ポインタのシリアライズ/デシリアライズが動作すること。
- [ ] 分割発生中のノード探索において、リーダーが右リンクを辿って最新データを正しく取得できること。
- [ ] `tests/database/test_blink_tree.py` を含む B-Tree 関連テストが全件 PASS すること。
- [ ] `make py_compile` および `make static_analysis` がエラー 0 件で通過すること。
