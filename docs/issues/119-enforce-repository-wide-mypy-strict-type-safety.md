---
ID: 119
種別: Refactor
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] リポジトリ全体の完全型安全性確立（全340モジュールの mypy --strict 適合化と型アノテーション補完） (ID: 119)

## 1. 概要 / Summary
リポジトリ全体（`src/` 配下の全340ファイル）に対して `mypy --strict` を適用し、現在残存している約60箇所の型不整合（未型付け関数の呼び出し、ジェネリクス引数欠落、Union型不一致、暗黙のAny型返却）を完全に解消し、プロジェクト全体の型安全性を 100% 達成する。

---

## 2. トレーサビリティ / Traceability
- [AGENTS.md: Antigravity IDE & Quality Gates Enforcement](../../.agents/AGENTS.md)
- [Makefile: make mypy](../../Makefile)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/pdf_engine/interpreter.py](../../src/pdf_engine/interpreter.py)
- [ ] [src/database/transaction/mvcc.py](../../src/database/transaction/mvcc.py)
- [ ] [src/database/transaction/lock_manager.py](../../src/database/transaction/lock_manager.py)
- [ ] [src/database/storage/pager.py](../../src/database/storage/pager.py)
- [ ] [src/intelligence/analysis/hypothesis_engine.py](../../src/intelligence/analysis/hypothesis_engine.py)
- [ ] [src/intelligence/pir/manager.py](../../src/intelligence/pir/manager.py)
- [ ] [src/mcp/base.py](../../src/mcp/base.py) / [src/mcp/papers_server.py](../../src/mcp/papers_server.py)
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/119-enforce-repository-wide-mypy-strict-type-safety`

1. **Database & Storage Type Annotations**: `MVCCManager`, `LockManager`, `Pager`, `WALWriter` の型注釈補正（`dict[str, list[VersionedTuple]]`, `Optional` 型ガード）。
2. **Intelligence & PDF Engine Refinements**: `HypothesisEngine`, `PIRManager`, `TextInterpreter` の `open()` 型ガードおよび `Callable` 戻り値アノテーション。
3. **MCP & Web Gateway Type Hardening**: `handlers.py`, `papers_server.py` の型キャストおよび `int()` パラメータ検証の厳格化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `make mypy` (`mypy --strict src`) が 0 errors（全340ファイル合格）で完了すること
- [ ] `make format`, `make static_analysis`, `make test` が 100% PASS すること
