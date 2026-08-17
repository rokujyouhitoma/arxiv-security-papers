---
ID: 030
種別: Performance / Quality / Test
優先度: High
ステータス: Open (In Progress)
---

# [PERF/TEST] 4層ベクトルDBの重厚な性能・メモリプロファイリング評価およびSQL互換性テスト拡充 (ID: 030)

## 1. 概要 / Summary
SQLite型4層アーキテクチャ（VFS / Pager / VDBE / Compiler）に基づく純Python製ベクトルデータベースに対し、重厚なベンチマーク・メモリプロファイリング（tracemalloc / P50・P90・P99遅延 / スループット / メモリリーク検証）を実施します。
同時に、標準SQL（DDL / DQL / DML / DCL / TCL）および PEP 249 / SQLite3 クライアントとの100%互換性を検証する包括的テストケース群を大幅拡充し、プロファイリング結果に基づく最適化を行います。

---

## 2. 影響範囲と関連ファイル / Scope and Target Files
- `src/database/profiler.py` (新規: DB専用プロファイラ & 計測ユーティリティ)
- `src/database/pager.py`, `src/database/storage.py`, `src/database/vdbe.py`, `src/database/sql/` (プロファイル結果に基づく高速化)
- `tests/database/test_db_performance_and_memory.py` (新規: 性能・メモリ・レイテンシ・リーク検証テスト)
- `tests/database/test_sql_compatibility_matrix.py` (新規: SQL規格・互換性マトリクステスト)
- `outputs/evaluations/database_performance_benchmark_report.md` (新規: 性能評価レポート)

---

## 3. 完了条件 / Definition of Done (DoD)
- [ ] `src/database/profiler.py` を実装し、CPU時間、レイテンシ分布（P50/P90/P95/P99）、メモリ増減（tracemalloc）、キャッシュヒット率を精密計測できること。
- [ ] `tests/database/test_db_performance_and_memory.py` を作成し、以下を検証・合格すること:
  - 1,000〜5,000件規模の大量書き込み・バッチトランザクションスループット
  - 4KB PageCache のメモリ上限遵守および LRU Eviction の正常動作
  - 10,000回以上の連続クエリ実行におけるメモリリークゼロ（tracemalloc デルタ安定）
  - HNSW ANN 探索レイテンシ P95 $< 2.0\text{ ms}$、点照会 P95 $< 0.5\text{ ms}$
  - マルチスレッド並行読み出し・PosixVFS ロック整合性
- [ ] `tests/database/test_sql_compatibility_matrix.py` を作成し、以下を網羅すること:
  - DDL: 各種データ型、制約、複数テーブル定義、スキーマ検証
  - DQL: 複合条件（AND/OR/NOT/括弧ネスト）、比較演算子、LIKE、IN / NOT IN、NULL判定、ORDER BY、LIMIT / OFFSET、集約関数（COUNT/SUM/AVG/MIN/MAX）、GROUP BY
  - DML: カラム指定INSERT、複合式UPDATE、条件指定DELETE
  - TCL: SAVEPOINT、多段階トランザクション、ロールバックによる不整合防止
  - DCL: ロール権限制御（admin/analyst/guest）と不正操作拒絶
  - PEP 249 & SQLite3: プレースホルダー（`?`）、型変換、標準例外階層
- [ ] 全テストが PASS し、`make format`, `make static_analysis`, `make test` が 100% PASS すること。
- [ ] 性能評価レポートを生成すること。
