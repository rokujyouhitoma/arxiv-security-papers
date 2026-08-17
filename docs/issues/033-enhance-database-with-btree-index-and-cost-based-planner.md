---
ID: 033
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] `src/database/` の内部エンジン進化（B+Tree インデックスおよび Cost-Based Query Planner の分離・実装） (ID: 033)

## 1. 概要 / Summary

現在の純 Python 製ベクトルデータベース（`src/database/`）は、SQLite 型 4 層構造（VFS / Pager / VDBE / Compiler）と HNSW 近傍探索インデックスを備えています。

本 Issue では、さらなるクエリ処理能力の向上と大規模データ対応を目指し、**4KB 固定ページ上の B+Tree インデックス層** および **コストベースクエリプランナー（CBO / Query Planner）** を独立モジュールとして設計・実装します。これにより、ベクトル近傍探索とメタデータ（数値・日時・文字列）の複合フィルタリング（Hybrid Query）を最適化します。

```
src/database/
├── vfs/              # Posix / Memory VFS（OS抽象化）
├── pager/            # Page, PageCache, WAL（4KB固定ページ管理）
├── btree/            # [NEW] 4KB ページ対応 B+Tree（O(log N) 範囲・等値インデックス）
├── planner/          # [NEW] Cost-Based Query Planner（EXPLAIN QUERY PLAN, インデックス選択）
├── vdbe/             # レジスタベース バイトコード仮想マシン
├── compiler/         # AST Parser, Codegen
└── profiler/         # レイテンシ＆メモリプロファイラ
```

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [DSN-13-sqlite-vector-architecture.md](../designs/DSN-13-sqlite-vector-architecture.md)
  - [outputs/evaluations/database_performance_benchmark_report.md](../../outputs/evaluations/database_performance_benchmark_report.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] `src/database/btree/` (B+Tree ノード分割・走査・キーバリューストレージ)
- [ ] `src/database/planner/` (統計情報管理、コスト見積もり、実行計画選択、`EXPLAIN QUERY PLAN`)
- [ ] [src/database/vdbe.py](../../src/database/vdbe.py) (B-Tree 走査用オペコードの追加)
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py) (プランナー連携)
- [ ] `tests/database/test_btree_and_planner.py` (B+Tree 単体およびクエリプランナー検証)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/033-database-btree-and-query-planner`

1. **`src/database/btree/` の実装**:
   - `Pager` の 4096 バイト固定ページ上に B+Tree の内部ノード（Interior Cell）とリーフノード（Leaf Cell）をシリアライズ。
   - 等値検索および範囲走査（Range Scan: `>=`, `<=`, `BETWEEN`）を $O(\log N)$ で実現。
2. **`src/database/planner/` の実装**:
   - テーブル行数、インデックスカーディナリティ（統計情報）に基づくコスト計算モデルを構築。
   - ベクトル検索優先（ANN first -> Filter）と メタデータ絞り込み優先（BTree Filter first -> Vector Re-rank）の最適パスを動的判定。
   - `EXPLAIN QUERY PLAN SELECT ...` 構文のサポート。
3. **ベンチマークとテスト拡充**:
   - `DatabaseProfiler` を用いて、10,000 件規模における Full Table Scan と B+Tree インデックススキャンのレイテンシ改善率を実測。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 4KB ページ管理下で動作するゼロ依存 B+Tree インデックスが実装され、挿入・検索・範囲スキャンが正常動作すること
- [ ] `EXPLAIN QUERY PLAN` コマンドで選択された実行計画（Index Scan vs Table Scan vs Vector KNN）が可視化されること
- [ ] 複合 `WHERE` 句を伴うベクトル検索において、インデックス活用によるクエリレイテンシの短縮が確認できること
- [ ] `tests/database/` の全テストおよびワークスペース全テストが 100% PASS すること
