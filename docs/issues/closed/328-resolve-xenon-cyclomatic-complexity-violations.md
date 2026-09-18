---
ID: 328
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG/QA] xenon 循環的複雑度(CC)違反の解消 (SearchClient, SearchService, FacetedIndex) (ID: 328)

## 1. 概要 / Summary

静的解析ツール `xenon`（閾値: `--max-absolute A --max-modules A --max-average A`）による検証において、以下の3箇所で循環的複雑度（Cyclomatic Complexity）の許容上限（Rank A: CC <= 5）を超過する違反が検出された：

1. `ERROR:xenon:block "src/search/client.py:153 _fallback_search" has a rank of B` (CC = 6)
2. `ERROR:xenon:block "src/search/server/service.py:59 _handle_search" has a rank of B` (CC = 6)
3. `ERROR:xenon:block "src/search/ingestion/faceted_index.py:128 resolve_category_candidates" has a rank of C` (CC = 12)

本改修では、これらのメソッドを責務ごとにヘルパーメソッドへ分割・集約し、可読性と保守性を高め、すべてのブロックで Cyclomatic Complexity を Rank A (CC <= 5) に収めて `make static_analysis` (xenon) を 100% PASS させた。

### 再現手順 / Steps to Reproduce
1. `.venv/bin/xenon --max-absolute A --max-modules A --max-average A src` を実行する。
2. 上記3件の Rank B / Rank C エラーにより終了コード 1 で失敗する。

### 再現環境 / Environment
- Python: 3.14+
- xenon: 0.9.3
- Target Files:
  - `src/search/client.py`
  - `src/search/server/service.py`
  - `src/search/ingestion/faceted_index.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/search/client.py](../../src/search/client.py): `SearchClient._fallback_search` のモード別検索ディスパッチおよび空結果生成ヘルパーへの分割 (CC: 6 -> <= 4)
- [x] [src/search/server/service.py](../../src/search/server/service.py): `SearchService._handle_search` のモード別検索ディスパッチおよび空結果生成ヘルパーへの分割 (CC: 6 -> <= 4)
- [x] [src/search/ingestion/faceted_index.py](../../src/search/ingestion/faceted_index.py): `FacetedIndex.resolve_category_candidates` の完全一致ファセット検索、エイリアス検索、部分一致ドメイン検索への責務分割 (CC: 12 -> <= 3)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **`_fallback_search` および `_handle_search`**:
   - 入力クエリ検証 (`query or (category or "")`)、空結果早期リターン、`mode == "vector"`, `elif mode == "rrf"`, `else (hybrid)` の3分岐、およびプロファイル/ページネーション計算が1つの巨大なメソッド内にフラットに配置されており、デシジョンポイントが 5 を超過 (CC=6) していた。
2. **`resolve_category_candidates`**:
   - `category_val` の初期空チェック、カテゴリ/タグ/ドメインの存在確認（3分岐）、エイリアスリストの走査と各ファセットへの存在確認（4分岐）、マッチしなかった場合のドメイン部分一致走査（2分岐）が単一ループ/分岐群として積み重なり、合計11の判定が存在 (CC=12) していた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: なし（CI/品質ゲートで静的解析がブロッキングされるため即時修正が必要）。
* **恒久対策 (Permanent Fix)**:
  - `_fallback_search` / `_handle_search`: 検索モード実行ロジックを `_dispatch_search_mode`, `_search_vector_mode`, `_search_rrf_mode` へと分割し、空結果生成を `_empty_search_response` へ抽出。
  - `resolve_category_candidates`: `_lookup_exact_facets` (ファセット辞書横断取得)、`_collect_alias_matches` (エイリアス展開)、`_fallback_domain_matches` (ドメイン部分一致) に責務分割。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/328-resolve-xenon-cyclomatic-complexity-violations`

1. **`src/search/ingestion/faceted_index.py` のリファクタリング**:
   - `_lookup_exact_facets(term: str) -> Set[str]`
   - `_collect_alias_matches(clean_val: str) -> Set[str]`
   - `_fallback_domain_matches(clean_val: str) -> Set[str]`
   - `resolve_category_candidates` を上記ヘルパーを呼ぶ簡潔なフロー（CC <= 3）に整理。
2. **`src/search/client.py` のリファクタリング**:
   - `_empty_search_result(offset: int, top_k: int) -> Dict[str, Any]`
   - `_search_vector_mode`, `_search_rrf_mode`, `_dispatch_search_mode` への責務分離。
   - `_fallback_search` を CC <= 4 に抑制。
3. **`src/search/server/service.py` のリファクタリング**:
   - 同様に `_empty_search_response`, `_search_vector_mode`, `_search_rrf_mode`, `_dispatch_search_mode` への責務分離。
   - `_handle_search` を CC <= 4 に抑制。
4. **品質検証**:
   - `xenon --max-absolute A --max-modules A --max-average A src`
   - `radon cc src/search/client.py src/search/server/service.py src/search/ingestion/faceted_index.py -s`
   - `make check_format`
   - `pytest tests/search/`

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `src/search/client.py` の全メソッドが Radon CC <= 5 (Rank A) を達成
- [x] `src/search/server/service.py` の全メソッドが Radon CC <= 5 (Rank A) を達成
- [x] `src/search/ingestion/faceted_index.py` の全メソッドが Radon CC <= 5 (Rank A) を達成
- [x] `xenon --max-absolute A --max-modules A --max-average A src` がエラー 0 件 (code 0) で成功
- [x] 既存の検索関連テスト (`tests/search/`) が 100% PASS
- [x] `isort`, `black`, `flake8` が PASS
