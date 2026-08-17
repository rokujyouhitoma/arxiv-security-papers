---
ID: 029
種別: Refactor / Architecture
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-08-17
---

# [REFACTOR] `tests/` ディレクトリの `src/` パッケージ階層に合わせたパッケージ別再編 (ID: 029)

## 1. 概要 / Summary
`src/` 配下のパッケージ構造（`src/database/`, `src/mcp/`, `src/search/`, `src/fetcher/`, `src/web/`）と 1:1 に対応するよう、`tests/` 配下のテストファイルをパッケージ単位（`tests/database/`, `tests/mcp/`, `tests/search/`, `tests/fetcher/`, `tests/web/`）で階層化・再編しました。

---

## 2. ディレクトリ対応マップ / Directory Mapping

```text
src/                                      tests/
├── __init__.py                           ├── __init__.py
├── fetcher/                              ├── fetcher/
│   ├── __init__.py                       │   ├── __init__.py
│   └── arxiv_okf_fetcher.py       ───>   │   └── test_fetcher.py
├── web/                                  ├── web/
│   ├── __init__.py                       │   ├── __init__.py
│   └── web_server.py              ───>   │   └── test_web_server.py
├── database/                             ├── database/
│   ├── storage.py, index.py, ...  ───>   │   ├── test_vector_storage.py
│   ├── sql/, driver.py, ...       ───>   │   ├── test_sql_engine.py
│   └── vfs.py, pager.py, vdbe.py  ───>   │   └── test_vdbe_engine.py
├── mcp/                                  ├── mcp/
│   ├── papers_server.py           ───>   │   ├── test_mcp_server.py
│   ├── threat_defense_server.py   ───>   │   ├── test_mcp_strategic_ecosystem.py
│   ├── observability_server.py    ───>   │   ├── test_observability_mcp_server.py
│   └── security_guard             ───>   │   └── test_security_hardening.py
└── search/                               └── search/
    ├── vector_engine.py, core/    ───>       ├── test_vector_engine.py
    ├── ranking/, utils/profiler   ───>       ├── test_performance_optimizations.py
    └── eval/                      ───>       └── test_search_evaluation.py
```

---

## 3. 完了条件 (DoD) の検証結果 / Verification Results
- [x] 各テストファイルが対応するパッケージディレクトリ（`database/`, `mcp/`, `search/`, `fetcher/`, `web/`）に移動・配置完了。
- [x] 各テストディレクトリに `__init__.py` を配置。
- [x] `src/__init__.py`, `src/fetcher/__init__.py`, `src/web/__init__.py` を整備。
- [x] `Makefile` の `PYTHON_SRCS` を更新。
- [x] 全 100 テストが 100% PASS。
- [x] `make format`, `make static_analysis` (mypy 0エラー) が 100% PASS。
