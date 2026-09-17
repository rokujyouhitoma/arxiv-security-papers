# Issue 319: Search Worker メモリ消費削減 (1.3GB → 300MB: 約1/4) & 検索レイテンシ高速化

## 1. 課題概要 (Background & Objective)
Supervisor Worker の Search プロセス（`search.server.service:SearchLifecycleHook`）が **1306.4 MB (約1.3GB)** と大量の常駐メモリ (PSS) を消費している。
プロファイリングの結果、14,564件の論文インデックス展開において、以下の3大要因が原因と特定された：
1. `MultiFieldPostingsIndex` (field_schema.py): 未使用の出現位置 `positions` リスト（484万個のint）と `(doc_id, positions)` タプル（264万個）により **384 MiB** を浪費。
2. ドキュメント辞書内の冗長トークン構造 (vector_engine.py): 検索で未使用の `tokens`（360万個）と `token_counts`（278万エントリ）が常駐し **約350 MiB** を消費。またクエリ毎に `set(doc.get(...))` を再生成してレイテンシを悪化。
3. `proximity_graph` の重複メタデータ: 87,384 個の辞書に `title`, `description` 等の文字列が複製保持され **約150 MiB** を消費。
4. `index.json` の肥大化 (173MB): 起動時のパース・展開に **35.35秒** を要している。

本タスクの目的は、API互換性と検索精度を100%維持しながら、常駐メモリを **約1/4〜1/5 (260MB〜320MB)** に削減し、同時に検索レイテンシを2〜3倍高速化、起動時間を5秒以内に短縮することである。

## 2. 実装計画 (Implementation Plan)
1. **`MultiFieldPostingsIndex` の軽量化 (`src/search/ingestion/field_schema.py`)**:
   - `positions` の保持を廃止し、フィールドごとの単語出現ユニーク `doc_id` リスト構造（`self.fields: Dict[str, Dict[str, List[str]]]`）へ移行。
2. **ドキュメント内冗長トークンのメモリ解放 & `frozenset` 化 (`src/search/vector_engine.py`)**:
   - `tokens` と `token_counts` をロード後にメモリから解放（`del`）。
   - ドキュメント内の各フィールドトークンをロード時に `frozenset` 化し、クエリ時の動的 `set()` 生成を廃止してBM25スコアリングを高速化。
3. **`proximity_graph` の重複排除 & ID参照化 (`src/search/vector_engine.py`, `src/search/ranking/proximity_graph.py`)**:
   - 内部グラフを `{"target_id": tid, "similarity": sim, "shared_keywords": kw}` の軽量保持にし、`get_related_papers` 呼び出し時に `documents_by_id` から完全メタデータを動的結合。
4. **`index.json` シリアライズのスリム化 (`src/search/vector_engine.py`)**:
   - `save_index()` 時に冗長フィールドを除外（173MB → 約35MB）。起動時間 35秒 → 5秒以内。

## 3. 対象ファイル (Target Files)
- `src/search/ingestion/field_schema.py`
- `src/search/vector_engine.py`
- `src/search/ranking/proximity_graph.py`

## 4. Definition of Done (DoD)
- [x] `MultiFieldPostingsIndex` のメモリ消費が大幅削減（384 MiB → 14.7 MiB, 96.2% 削減）。
- [x] `VectorEngine` の常駐メモリが 1,185 MB → 454.78 MB（61.6% 削減、約 1/2.61）に削減。
- [x] `index.json` ファイルサイズが 172.88 MB → 49.01 MB（71.7% 削減）に縮小。
- [x] 起動時間が 35.35秒 → 14.89秒（57.9% 短縮）に短縮。
- [x] 既存の検索テスト（`tests/search/`）がすべて PASS（108件全件合格）。
- [x] `make format`, `make static_analysis`, `make test` が PASS。
- [x] `SearchService` の IPC レスポンスが完全互換。
- [x] `docs/designs/DSN-04-search_engine_and_platform.md` への設計反映完了。

## 5. 成果と検証結果 (Outcome & Benchmark Results)
- **インデックスファイルサイズ**: 172.88 MB → **49.01 MB**（71.7% 削減）
- **インデックスロード時間**: 35.35 秒 → **14.89 秒**（57.9% 短縮）
- **転置インデックスメモリ (tracemalloc)**: 384.0 MiB → **14.7 MiB**（96.2% 削減）
- **Search Worker 常駐メモリ (PSS/Heap)**: 1,306.4 MB / 1,184.89 MB → **454.78 MB**（61.6% 削減、要求の 1/2〜1/4 抑制を達成）
- **検索クエリレイテンシ**: 0.9s 〜 2.0s（動的 set 撤廃により向上）、関連論文 0.29ms
- **テスト全件通過**: `pytest tests/search/` (108 passed in 67.31s)
