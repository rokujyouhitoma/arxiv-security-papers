# [Issue 060] 後方互換性機能・シム・レガシーエイリアスの完全削除

- **Status**: Open
- **Assignee**: All 13 Multi-Agent Specialists
- **Created**: 2026-08-22
- **Branch**: `refactor/060-remove-legacy-backward-compatibility`

---

## 1. 概要 (Overview)

現在アクティブな開発フェーズにおいて不要となったすべての後方互換性維持コード（`src/compat/` パッケージ、`src/*.py` のルート直下シムファイル、`src/search/__init__.py` の `sys.modules` エイリアス注入等）を完全削除し、最新のクリーンアーキテクチャにコードベースを一本化・スリム化する。

---

## 2. 完了定義 (Definition of Done)

- [x] **互換パッケージ・シムファイルの削除**:
  - `src/compat/` (`__init__.py`, `arxiv_okf_fetcher.py`, `vector_engine.py`, `web_server.py`) の完全削除
  - `src/arxiv_okf_fetcher.py`, `src/vector_engine.py`, `src/web_server.py` の完全削除
- [x] **コアパッケージからの互換コード排除**:
  - `src/__init__.py` からの `compat` 除去
  - `src/search/__init__.py` からのレガシーエイリアス注入コードの完全削除
- [x] **Makefile & ドキュメントの正規化**:
  - 正規のエントリーポイント（`src/pipeline/arxiv_okf_fetcher.py`, `src/web/server.py` 等）への一本化
- [x] **テスト & 品質管理ゲート**:
  - `make check_format` 0 エラー (PASS)
  - `make static_analysis` (radon, xenon, mypy --strict) 100% PASS
  - `make test` 全テスト 100% PASS (345/345 passed, coverage 82.20%)
