---
ID: 438
種別: Refactoring
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] tests/core 配下の対称的サブディレクトリ再編 (ID: 438)

## 1. 概要 / Summary
`src/core/` のパッケージ構造（`structures/`, `profiler/`, `hsm/`, `peg/`）に対し、`tests/core/` 配下に直接フラットに配置されていたテストファイルを各サブディレクトリに対称移動し、テストコードの保守性・可読性・ディレクトリ構造の一貫性を確保する。

- `tests/core/structures/`:
  - `test_arc_cache.py`
  - `test_bloom_filter.py`
  - `test_community.py`
  - `test_disjoint_set.py`
  - `test_probabilistic.py`
  - `test_radix_trie.py`
  - `test_roaring_bitmap.py`
  - `test_skip_list.py`
- `tests/core/profiler/`:
  - `test_pynytprof_asyncio.py`
  - `test_pynytprof_chart.py`
  - `test_pynytprof_cli_e2e.py`
  - `test_pynytprof_diff.py`
  - `test_pynytprof_engine.py`
  - `test_pynytprof_exporter_merge.py`
  - `test_pynytprof_flamegraph.py`
  - `test_pynytprof_reporter.py`
  - `test_pynytprof_sampling.py`
- `tests/core/hsm/`:
  - `test_hsm_engine.py`

## 2. トレーサビリティ / Traceability
- 関連資料:
  - `src/core/structures/`
  - `src/core/profiler/`
  - `src/core/hsm/`
  - `src/core/peg/`
  - [AGENTS.md](../../.agents/AGENTS.md) (Governance & QA Quality Gates)

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [tests/core/structures/](file:///workspace/arxiv-security-papers/tests/core/structures/)
- [ ] [tests/core/profiler/](file:///workspace/arxiv-security-papers/tests/core/profiler/)
- [ ] [tests/core/hsm/](file:///workspace/arxiv-security-papers/tests/core/hsm/)
- [ ] [tests/core/test_community.py](file:///workspace/arxiv-security-papers/tests/core/test_community.py)
- [ ] [tests/core/test_pynytprof_cli_e2e.py](file:///workspace/arxiv-security-papers/tests/core/test_pynytprof_cli_e2e.py)
- [ ] [tests/core/test_pynytprof_chart.py](file:///workspace/arxiv-security-papers/tests/core/test_pynytprof_chart.py)

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/438-symmetrical-restructuring-of-core-tests`

1. ディレクトリ作成:
   - `tests/core/structures/`
   - `tests/core/profiler/`
   - `tests/core/hsm/`
2. 各テストファイルを `git mv` にて移動。
3. 移動したテストファイル内の親ディレクトリ相対パス（`os.path.dirname(__file__)` や `Path(__file__).parents[...]`）を新階層（1階層深化）に合わせて調整。
4. `make format`, `make static_analysis`, `pytest tests/core/` による全テストパス検証。

## 5. 完了条件 / Success Criteria (DoD)
- [x] `tests/core/` 直下のテストがゼロになり、各ドメイン別サブディレクトリに対称配置されていること。
- [x] `pytest tests/core/` が全 188 件成功（PASS）すること。
- [x] `make format` および `make static_analysis` (Xenon A, Mypy Strict) がエラー0件で合格すること。
- [x] Issue台帳およびGitワークフローの完了。
