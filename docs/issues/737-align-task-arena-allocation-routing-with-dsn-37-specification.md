---
ID: 737
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Task Ephemeral Arena の割り当て経路接続または DSN-37 設計書記述の実態整合化 (ID: 737)

## 1. 概要 / Summary
現在、コンパイラは通常の値の割り当て（`cons`, `make-vector` 等）に Task Ephemeral Arena（`arena.scm`）を使っておらず、Escape Analysis（`120_alias_escape.scm`）によるスタック割り当て（`%stack-cons`）と GC ヒープ割り当てを使用している。そのため、DSN-37 の「タスクごとの arena で GC を不要にする」という記述と実態が乖離している。割り当て経路に Task Arena をつなぐか、DSN-37 設計書の記述を実態に合わせて正確に改訂する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 5)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- [ ] [arena.scm](../../ulisp/runtime/concurrency/arena.scm)
- [ ] [boundary.scm](../../ulisp/runtime/concurrency/boundary.scm)
- [ ] [120_alias_escape.scm](../../ulisp/frontend/120_alias_escape.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/737-align-task-arena-and-dsn37`

1. タスク内アロケーションにおけるスタックプロモーション（`%stack-cons`）、境界コピー用 Task Arena（`arena.scm` / `boundary.scm`）、および GC ヒープの役割分担を明確化する。
2. ASC カーネル・タスク実行時のアロケーション経路への Arena 接続、および DSN-37 設計書の記述を実態と完全に一致させる。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Task Arena の割り当て経路と DSN-37 設計書の記述に乖離がないこと。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

