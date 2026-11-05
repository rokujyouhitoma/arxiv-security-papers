---
ID: 737
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] Task Ephemeral Arena の割り当て経路接続または DSN-37 設計書記述の実態整合化 (ID: 737)

## 1. 概要 / Summary
現在、コンパイラは通常の値の割り当て（`cons`, `make-vector` 等）に Task Ephemeral Arena（`arena.scm`）を使っておらず、Escape Analysis（`120_alias_escape.scm`）によるスタック割り当て（`%stack-cons`）と GC ヒープ割り当てを使用している。そのため、DSN-37 の「タスクごとの arena で GC を不要にする」という記述と実態が乖離している。割り当て経路に Task Arena をつなぐか、DSN-37 設計書の記述を実態に合わせて正確に改訂する。

---

## 2. セキュリティ脅威・脆弱性分析 / Security Threat Analysis
- **CWE-400**: 制御不能なリソース消費 (Uncontrolled Resource Consumption / Premature OOM)
  - タスク内での一過性の一時アロケーション（短命オブジェクト）がすべてグローバル GC ヒープに流入した場合、GC プレッシャーが急増し、Stop-the-World によるレイテンシスパイクやスループット低下を引き起こす。
- **CWE-590**: 不適切なメモリ空間の解放 (Free of Memory not on the Heap)
  - Task Arena（バンプポインタ領域）から確保されたオブジェクトが GC ヒープオブジェクトと混同され、誤ったトレーサーやフリーリストで追跡・解放された場合、メモリ破壊やセグメンテーション違反を招く。エスケープ解析に基づくスタック昇格、Arena による境界内アロケーション、GC ヒープの役割分担を明確に分離・整合させる必要がある。

---

## 3. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 5: Memory Architecture & Task Arenas)
- 関連コード:
  - `ulisp/runtime/concurrency/arena.scm` (バンプポインタ式アロケータ)
  - `ulisp/runtime/concurrency/boundary.scm` (タスク間境界コピー・Arena 連携)
  - `ulisp/frontend/120_alias_escape.scm` (スタックプロモーション・エスケープ解析)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- [x] [arena.scm](../../ulisp/runtime/concurrency/arena.scm)
- [x] [boundary.scm](../../ulisp/runtime/concurrency/boundary.scm)
- [x] [120_alias_escape.scm](../../ulisp/frontend/120_alias_escape.scm)

---

## 5. 根本原因分析 (RCA) / Root Cause Analysis
設計初期（DSN-37 策定時）に想定していた「すべてのタスク内アロケーションを Task Arena で行い GC を完全にバイパスする」という構想に対し、コンパイラフロントエンドでは高精度なエスケープ解析（`120_alias_escape.scm`）によるスタック割り当て（`%stack-cons`）と、長期生存オブジェクト向けの共通 GC ヒープという 2 層ハイブリッドモデルが先行実装されていた。Task Arena は `boundary.scm` におけるタスク間メッセージのディープコピーやタスクローカルな一括回収バッファとして設計・実装されたため、設計書記述（全オブジェクトが Arena 経由）とコンパイラコードジェネレータの実態に差異が生じていた。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/737-align-task-arena-and-dsn37`

1. DSN-37 Section 5 を改訂し、3層ハイブリッドメモリモデル（スタックプロモーション `%stack-cons`、メッセージ境界コピー用 Task Arena、共有/長期生存オブジェクト用 GC ヒープ）の協調構造を明文化する。
2. Task Arena（`arena.scm`）がメッセージディープコピー境界（`boundary.scm`）および短命な境界バッファ割り当てにおいてセーフティかつ決定論的に機能していることを確認する。
3. ドキュメントとコードのトレーサビリティを 100% 整合させる。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] Task Arena の割り当て経路と DSN-37 設計書の記述に乖離がなく、3層メモリモデルが正確に文書化されていること。
- [x] `make -C ulisp test_concurrency_ci` が 100% PASS すること。
- [x] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

