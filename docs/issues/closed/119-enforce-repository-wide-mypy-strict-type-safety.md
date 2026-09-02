---
ID: 119
種別: Refactor
優先度: High
ステータス: Closed
---

# [FEAT/ENH] リポジトリ全体の完全型安全性確立（全341モジュールの mypy --strict 適合化と型アノテーション補完） (ID: 119)

## 1. 概要 / Summary
リポジトリ全体（`src/` 配下の全341ファイル）に対して `mypy --strict` を適用し、現在残存している27ファイル・58箇所の型不整合（未型付け関数の呼び出し、ジェネリクス型引数欠落、Union型不一致、暗黙のAny型返却、bytesフォーマット警告、None安全性ガード）を完全に解消し、プロジェクト全体の型安全性を 100% 達成する。

---

## 2. トレーサビリティ / Traceability
- [AGENTS.md: Antigravity IDE & Quality Gates Enforcement](../../.agents/AGENTS.md)
- [Makefile: make mypy](../../Makefile)

---

## 3. 脅威分析・制約事項 / Threat Analysis & Operational Constraints
1. **ランタイム型エラー・暗黙の型強制によるデータ破損リスク**:
   - *脅威*: `bytes`/`str` の混同や `None` アクセスにより、本番環境でのクラッシュやデータ破損が発生する。
   - *緩和策*: `mypy --strict` によるコンパイル時検査と明示的な型ガード・型キャストの徹底。
2. **リファクタリング時の既存挙動破壊**:
   - *脅威*: 型注釈修正時にランタイムロジックが意図せず変更される。
   - *緩和策*: 既存の全618テストケースの 100% PASS を維持し、ロジック変更を行わず型定義の整合のみを実施。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files (27 Files)
- [x] [src/security/sandbox/ast_guard.py](../../src/security/sandbox/ast_guard.py)
- [x] [src/search/ranking/proximity_graph.py](../../src/search/ranking/proximity_graph.py)
- [x] [src/search/core/analysis/token_filter.py](../../src/search/core/analysis/token_filter.py)
- [x] [src/search/vector_engine.py](../../src/search/vector_engine.py)
- [x] [src/database/engine/vectorized.py](../../src/database/engine/vectorized.py)
- [x] [src/database/storage/slotted_page.py](../../src/database/storage/slotted_page.py)
- [x] [src/database/storage/pager.py](../../src/database/storage/pager.py)
- [x] [src/database/distributed/gossip.py](../../src/database/distributed/gossip.py)
- [x] [src/database/transaction/mvcc.py](../../src/database/transaction/mvcc.py)
- [x] [src/database/transaction/lock_manager.py](../../src/database/transaction/lock_manager.py)
- [x] [src/database/transaction/wal.py](../../src/database/transaction/wal.py)
- [x] [src/database/pax/pax_page.py](../../src/database/pax/pax_page.py)
- [x] [src/database/pax/scanner.py](../../src/database/pax/scanner.py)
- [x] [src/database/compat/sqlite_engine.py](../../src/database/compat/sqlite_engine.py)
- [x] [src/database/compat/sqlite_bridge.py](../../src/database/compat/sqlite_bridge.py)
- [x] [src/database/index/index.py](../../src/database/index/index.py)
- [x] [src/database/lsm/sstable.py](../../src/database/lsm/sstable.py)
- [x] [src/database/planner/planner.py](../../src/database/planner/planner.py)
- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py)
- [x] [src/pdf_engine/interpreter.py](../../src/pdf_engine/interpreter.py)
- [x] [src/workflow/wal.py](../../src/workflow/wal.py)
- [x] [src/intelligence/analysis/hypothesis_engine.py](../../src/intelligence/analysis/hypothesis_engine.py)
- [x] [src/intelligence/pir/manager.py](../../src/intelligence/pir/manager.py)
- [x] [src/mcp/base.py](../../src/mcp/base.py)
- [x] [src/mcp/papers_server.py](../../src/mcp/papers_server.py)
- [x] [src/mcp/observability_server.py](../../src/mcp/observability_server.py)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `refactor/119-enforce-repository-wide-mypy-strict-type-safety`

### Step 1: Security, Search & PDF Engine Fixes
- `ast_guard.py`: bytes フォーマット文字列の修正 (`f"{x.decode()}"` または `f"{x!r}"`)
- `proximity_graph.py`, `token_filter.py`, `vector_engine.py`: 型注釈とキャストの補完
- `interpreter.py`: `TextInterpreter` の `Callable[[], None]` 型整合

### Step 2: Database Subsystem Fixes
- `slotted_page.py`, `pager.py`, `gossip.py`, `mvcc.py`, `lock_manager.py`, `wal.py`, `pax_page.py`, `scanner.py`, `sqlite_engine.py`, `sqlite_bridge.py`, `index.py`, `sstable.py`, `planner.py`, `executor.py`, `vectorized.py`
- ジェネリクス引数の補完 (`dict[str, Any]`, `list[Any]`, `tuple[Any, ...]`)、`MVCCManager` の key 型不一致解消、`WALWriter` の `None` チェック。

### Step 3: Intelligence, Workflow, MCP & Web Gateway Fixes
- `hypothesis_engine.py`, `pir.manager.py`: `open()` のパス型ガード (`isinstance(path, (str, bytes, os.PathLike))`)、`set[...]` 型引数付与
- `wal.py`, `base.py`, `papers_server.py`, `observability_server.py`, `handlers.py`: 戻り値キャストと `int()` 引数の型チェック強化

### Step 4: Verification & Quality Gates
- `make mypy` (`mypy --strict src`) 0 errors を達成
- `make check` (`check_format`, `static_analysis`, `test`) 100% PASS を確認

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `make mypy` (`mypy --strict src`) が 0 errors（全341ファイル合格）で完了すること
- [x] `make format`, `make static_analysis`, `make test` が 100% PASS すること
- [x] 循環的複雑度 Grade A を維持すること
