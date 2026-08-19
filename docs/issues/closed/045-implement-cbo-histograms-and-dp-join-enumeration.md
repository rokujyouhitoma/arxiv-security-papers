---
ID: 045
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-08-20
---

# [FEAT] CBO 統計ヒストグラム（Equi-Depth / HyperLogLog）& 動的計画法結合順序探索（DP Join Enumeration）の実装 (ID: 045)

## 1. 概要 / Summary

[DSN-14 次世代データベースエンジン設計書](../../designs/DSN-14-database_engine_architecture.md) 第1.6節（クエリオプティマイザ）およびマイルストーン 13（CBO & Volcano Iterator）に基づき、高度なコストベースクエリオプティマイザ（CBO: Cost-Based Optimizer）を確立するため、**「Equi-Depth 統計ヒストグラム」**、**「HyperLogLog (HLL) NDV カーディナリティ推定」**、および **「動的計画法による結合順序探索（DP Join Enumeration / System R 方式）」** を `src/database/planner/` に実装した。

データ値の歪み（Skew）を捉える等深度ヒストグラムと、メモリ効率的な HLL アルゴリズムにより正確なセレクティビティを算出し、$N$ テーブル結合に対する指数関数的探索空間から最小コスト実行ツリーを動的計画法で高速特定した。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../../designs/DSN-14-database_engine_architecture.md)
  - 1.4 クエリ処理系（SQLパーサー・プランナー・実行エンジン）
  - 1.4.2 クエリオプティマイザ（RBO / CBO）
  - 1.6 現行エンジン対比と進化方針
  - 15. 次世代実装ロードマップ マイルストーン 13
- 関連クローズド Issue:
  - [Issue 044: PAX（Partition Attributes Across）ハイブリッド列指向フォーマット & 高速集計スキャナの実装](closed/044-implement-pax-columnar-storage-and-analytics-scanner.md)
  - [Issue 043: CoW (Copy-on-Write) B-Tree & mmap ゼロコピーリードエンジンの実装](closed/043-implement-cow-btree-and-mmap-zero-copy.md)
  - [Issue 042: LSM-Tree ストレージエンジン（MemTable, SSTable, Sparse Index, Bloom Filter）の実装](closed/042-implement-lsm-tree-storage-engine-and-bloom-filter.md)
  - [Issue 041: 2Q バッファプール（スキャン汚染防止）と Pin/Unpin ページライフサイクル管理の実装](closed/041-implement-2q-buffer-pool-and-page-pinning.md)
  - [Issue 040: MVCC（多版同時実行制御）と SS2PL ロックマネージャ・デッドロック検知の実装](closed/040-implement-mvcc-and-ss2pl-transaction-manager.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/planner/histogram.py](../../src/database/planner/histogram.py) (新規: Equi-Depth 統計ヒストグラム、歪み分布セレクティビティ算出)
- [x] [src/database/planner/hll.py](../../src/database/planner/hll.py) (新規: HyperLogLog 確率的カーディナリティ/NDV推定)
- [x] [src/database/planner/join_optimizer.py](../../src/database/planner/join_optimizer.py) (新規: 動的計画法結合順序探索、DP Join Enumeration、JoinCostModel)
- [x] [src/database/planner/stats.py](../../src/database/planner/stats.py) (拡張: ColumnStats への Histogram & HLL 統合)
- [x] [src/database/planner/planner.py](../../src/database/planner/planner.py) (拡張: plan_join API 追加、DP Join 統合)
- [x] [src/database/planner/__init__.py](../../src/database/planner/__init__.py) (エクスポート更新)
- [x] [src/database/__init__.py](../../src/database/__init__.py) (エクスポート更新: `EquiDepthHistogram`, `EquiDepthBucket`, `HyperLogLog`, `DPJoinOptimizer`, `JoinPhysicalOperator`, `JoinPlanNode`)
- [x] [tests/database/test_cbo_optimizer.py](../../tests/database/test_cbo_optimizer.py) (新規: ヒストグラムセレクティビティ検証、HLL 誤差検証、DP Join 順序最適化検証)

---

## 4. 実装成果 / Implementation Results

Target Branch: `feat/045-cbo-histograms-dp-join`

### 4.1 Equi-Depth 統計ヒストグラム (`src/database/planner/histogram.py`)
- **等深度バケット分割**: 連続・離散データの偏り（Skew）を捉える $K$ 個の等件数バケットを生成。
- **高精度セレクティビティ推定**: `=`, `<`, `>`, `BETWEEN` 演算子に対し、バケット境界の線形補間（Linear Interpolation）および離散度補正により正確なヒット率を算出。

### 4.2 HyperLogLog NDV 推定 (`src/database/planner/hll.py`)
- **確率的カーディナリティ計算**: 64-bit ハッシュ空間とレジスタ配列（$m = 256$）による、ゼロ依存・$O(1)$ メモリでの NDV 高速推定（標準誤差 < 7%）。
- **スケッチ結合 (`merge`)**: 分散ノードやバッチ単位の HLL レジスタを即座にマージ可能。

### 4.3 動的計画法 結合順序探索 (`src/database/planner/join_optimizer.py`)
- **Bottom-Up DP (System R 方式)**: テーブル集合の部分集合サイズ 1 から $N$ まで、全分割 $(S_1, S_2)$ の結合コストをメモ化探索。
- **物理結合アルゴリズム選択**: `NestedLoopJoin`, `HashJoin`, `IndexJoin` のコストモデルを比較し、全体最小コストの Left-Deep / Bushy Tree を決定。

---

## 5. 完了条件検証 (DoD Verification)

- [x] `EquiDepthHistogram` により、偏りのあるデータ分布でも範囲クエリのセレクティビティが正確に推定されること。
- [x] `HyperLogLog` により、一意値数（NDV）が標準誤差 10% 以内で高速推定されること。
- [x] `DPJoinOptimizer` により、3表以上の JOIN クエリにおいてフィルタ率の高いテーブルから結合する最小コスト結合順序が正しく選択されること。
- [x] `make check_format`, `make py_compile`, `make static_analysis` がエラー 0 件ですべて PASS すること。
- [x] 新規テストスイート（`tests/database/test_cbo_optimizer.py`）が 100% PASS すること。
