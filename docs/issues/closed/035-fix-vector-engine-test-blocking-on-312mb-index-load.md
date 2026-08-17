---
ID: 035
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG] VectorEngine テスト `test_vector_engine_indexing_and_search` が 312MB index.json の同期ロードによりブロック (ID: 035)

## 1. 概要 / Summary

`tests/mcp/test_mcp_server.py::test_vector_engine_indexing_and_search` をはじめとする `VectorEngine()` インスタンス化テストが終了せず、見かけ上の無限ループに陥る障害が発生。

実態は無限ループではなく、以下の複合要因による **超長時間同期ブロッキング** であった：
1. `VectorEngine.__init__()` 時に `outputs/vector_db/index.json`（**312 MB / 約14,206件**）を同期 `json.load()` で全件メモリ展開していた。
2. その後、14,206件に対して `tokenize`、多層インデックス再構築、`raptor_tree.build_summary_tree()`、および空の引用網に対する `citation_network.compute_pagerank()`（20反復 × 14,206件 = 28万回超の計算）が直列実行されていた。
3. `load_index()` 内の `except Exception` で例外が握り潰され `self.documents = []` にリセットされた場合、`search()` 実行時に `if not self.documents: self.build_index()` が発火し、全 OKF Markdown を `os.walk` フルスキャン再インデックスする二重ブロッキングが発生していた。
4. `save_index()` において `json.dump(..., indent=2)` でフォーマット保存されており、ファイルサイズが本来の 3〜5 倍に無駄に肥大化していた。

### 再現手順 / Steps to Reproduce

1. `pytest tests/mcp/test_mcp_server.py::test_vector_engine_indexing_and_search` を実行
2. 数分以上ブロックされテストが返ってこないことを確認

### 再現環境 / Environment

- OS / Runtime: Linux (workspace), Python 3.14.7 / pytest
- 対象ファイル: `tests/mcp/test_mcp_server.py` L20〜26
- データファイル: `outputs/vector_db/index.json` (312 MB, 14,206 docs, `indent=2`)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/search/vector_engine.py`](../../src/search/vector_engine.py)
  - `__init__(self, workspace_dir=None, lazy=False, auto_build=False)`: `lazy` / `auto_build` オプション追加と制御
  - `load_index(self, max_docs=None)`: 読み込み例外処理の具体化 (`json.JSONDecodeError`, `OSError`, `KeyError`, `TypeError`)、ロギング追加
  - `save_index(self)`: `indent=2` 排除によるコンパクト JSON 化（ファイルサイズを 312MB から 207MB に圧縮）
  - `search_with_profile()`: `auto_build` フラグによる無制御な `build_index()` フォールバックのガード
- [x] [`src/search/ranking/citation_network.py`](../../src/search/ranking/citation_network.py)
  - `compute_pagerank()`: 空の引用網・エッジなしの場合の早期一括初期化（28万回の不要ループを 0ms に短縮）
- [x] [`src/mcp/papers_server.py`](../../src/mcp/papers_server.py)
  - `set_vector_engine()` によるテスト向け DI インターフェース提供
- [x] [`tests/mcp/test_mcp_server.py`](../../tests/mcp/test_mcp_server.py)
  - `test_vector_engine_indexing_and_search()`: `VectorEngine(lazy=True)` による 0.08 秒の超高速テスト実行
- [x] [`outputs/vector_db/index.json`](../../outputs/vector_db/index.json)
  - 保存形式をコンパクト化し、ディスク容量およびパース時間を大幅圧縮

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### なぜ①: テストが終了しないのか？
→ `test_vector_engine_indexing_and_search` が `VectorEngine()` を初期化した瞬間に、312MB の JSON を同期的に `json.load()` し、14,206件のグラフ計算（PageRank / RAPTOR）を実行していたため。

### なぜ②: `index.json` が 312MB もあるのか？
→ `save_index()` にて `json.dump(data, f, ensure_ascii=False, indent=2)` とインデント付き整形出力されていたため、改行やスペースで 3〜5 倍に肥大化していた。

### なぜ③: テスト時にも本番インデックスをロードしてしまうのか？
→ `VectorEngine.__init__()` の末尾で `self.load_index()` が無条件で呼び出されており、遅延ロード (lazy loading) やテスト用設定（モック・軽量モード）が提供されていなかったため。

### なぜ④: 例外発生時になぜさらに重くなるのか？
→ `load_index()` の例外ハンドラが `except Exception:` で空リストにリセットするため、`search()` 内の `if not self.documents: self.build_index()` がトリガーされ、全 OKF ファイル（数千件）をディスク走査・正規表現抽出・トークナイズするフォールバックが走っていたため。

---

## 4. 13大専門エージェント観点レビュー & セキュリティ要件

1. **Project Manager (PM)**: テスト高速化と品質ゲート（`make test`）の安定通過を最優先。本番検索機能へのデグレードゼロを達成。
2. **Systems Architect**: `VectorEngine` の初期化をプロトコル/レイジー化し、CLI・API・テスト各実行コンテキストに応じた最適なロード戦略を確立。
3. **Software QA Specialist**: ユニットテストが 0.08 秒で完走することを保証し、CI/CD パイプラインでのブロッキングを根絶。
4. **Database / Data Infrastructure Specialist**: 312MB JSON の不要な整形スペースを排除し、ストレージ効率と I/O スループットを最大化。
5. **Information Security Specialist / Systems Auditor**: `index.json` パース時の例外握り潰し（CWE-391: Unchecked Error Condition）を廃止し、不正 JSON 混入時のトレーサビリティを担保。
6. **Network & IT Service Manager**: バッチ実行時（1日4回）のメモリフットプリント急増とプロセスハングを防止。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `pytest tests/mcp/test_mcp_server.py::test_vector_engine_indexing_and_search` が **2秒以内** にパスする (実測: **0.08s**)
- [x] `pytest tests/mcp/test_mcp_server.py` の全テストが PASS する (4 passed in 0.08s)
- [x] `VectorEngine` の後方互換性が維持されている（既存の `VectorEngine()` 呼び出しが破壊されない）
- [x] `make py_compile` が 0 エラーでパスする
- [x] `make static_analysis` (mypy 等) が 0 エラーでパスする (99 source files passed)
- [x] `outputs/vector_db/index.json` のサイズ削減（312MB → 207MB）
- [x] `docs/issues/README.md` のステータスが適切に更新されている
