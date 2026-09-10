---
ID: 231
種別: Performance / Architecture
優先度: High
ステータス: Closed
---

# [PERF] CLI・dbshell の超高速化およびテーブルスキーマデータ型の適正化 (ID: 231)

## 1. 概要 / Summary

本 Issue は、`manage.py` および対話型データベースシェル (`dbshell`) における**大幅なパフォーマンス改善（54.8秒 $\rightarrow$ サブ秒）**と、画一的 `TEXT` 型から実態データに即した**リッチな SQL データ型（`VARCHAR`, `TIMESTAMP`, `JSON`, `INTEGER`, `VECTOR`）へのスキーマ刷新**、および `.schema` による Prettify された DDL / インデックス定義（`CREATE INDEX`）の可視化を目的とする。

### コア対応項目
1. **O(1) 高速 `COUNT(*)` ショートサーキットの実装**:
   - 単一テーブルに対する集約（`WHERE` / `JOIN` なし）において、ストレージの `__len__` を O(1) で即座に返却。
2. **全文ファイル無差別 disk read の抑止**:
   - `_scan_all_table_rows` における `dict(meta)` の eager materialize を廃止し、`LazyRow` プロキシによって不要なファイル本文読み込み（13万回）を完全排除。
3. **`manage.py tables` の高速化**:
   - テーブル一覧表示時に `len(catalog.storage)` を直接参照し、0.9秒台で瞬時に全テーブルを表示。
4. **テーブルスキーマ定義の適正化**:
   - `okf_papers`, `processed_papers`, `raw_papers`, `pipeline_runs`, `cti_techniques`, `cisa_kev`, `threat_trends`, `vertices`, `edges`, `main` の DDL をリッチな型定義へ更新。
5. **DDL Prettify & インデックス確認機能**:
   - `.schema [table]` で列名幅に合わせた綺麗に整列・インデントされた複数行 DDL を出力。
   - テーブルに定義された PRIMARY KEY インデックス（UNIQUE BTREE）や HNSW ベクトルインデックスの DDL を併せて出力。
   - `.indexes [table]` / `.indices` メタコマンドによるインデックス一覧の ASCII 罫線テーブル表示。

---

## 2. 完了条件 / DoD

- [x] `python3 manage.py tables` が 1秒未満（実測: 0.929s、54.8s から約 60 倍高速化）で完了すること。
- [x] `python3 manage.py dbshell -c "SELECT COUNT(*) FROM okf_papers;"` が 15ms 未満（実測: 13.61ms）で完了すること。
- [x] `.schema okf_papers`, `.schema processed_papers`, `.schema raw_papers`, `.schema main` で適切な型（`VARCHAR`, `TIMESTAMP`, `JSON`, `INTEGER`, `VECTOR(4)`）が表示されること。
- [x] `.schema` で複数行の美しいインデント＆整列済み DDL および `CREATE INDEX` が出力されること。
- [x] `.indexes [table]` でインデックス一覧が確認できること。
- [x] `mypy --strict`, `xenon` Rank A (CC <= 5) 100% 準拠。
- [x] 全テストが PASS すること。
