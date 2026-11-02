---
ID: 670
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 構造化クラッシュレポート (SASL 相当) 生成と Layer 1 コントロールプレーン非同期転送・可観測性基盤の実装 (ID: 670)

## 1. 概要 / Summary
Erlang/OTP の SASL（System Architecture Support Libraries）および Crash Logger を参考に、Synapse 並行タスクのクラッシュ時に原因特定のための詳細な診断コンテキストを構造化レポートとして生成し、Layer 1（R7RS コントロールプレーン）へ非同期に安全転送する可観測性（Observability）基盤を構築する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](docs/designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連 Issue:
  - [Issue #641 (境界サニタイザ・ディープコピー)](docs/issues/closed/641-implement-synapse-boundary-sanitizer-and-deep-copy.md)
  - [Issue #666 (タスク間リンク・モニタ)](docs/issues/666-implement-synapse-task-links-and-monitors.md)
  - [Issue #668 (Fail-Fast パニック機構)](docs/issues/668-implement-synapse-fail-fast-let-it-crash-semantics.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/crash_logger.scm](ulisp/runtime/concurrency/crash_logger.scm)（新規作成予定）
- [ ] [ulisp/runtime/concurrency/boundary.scm](ulisp/runtime/concurrency/boundary.scm)
- [ ] [tests/test_synapse_crash_logger.py](tests/test_synapse_crash_logger.py)（新規作成予定）

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/670-synapse-structured-crash-reporting`

1. クラッシュレポートデータ構造 `<crash-report>` の定義:
   - `task-id`, `epoch`, `fuel-consumed`, `arena-allocated-bytes`, `reason`, `last-received-msg-summary`, `timestamp`.
2. 計算層（Layer 2）の実行を妨げないロックフリーなクラッシュリングバッファの確保。
3. 境界ガード（Boundary Guard）を介した Layer 1 側ロギングサービスへの安全なバッチ・非同期通知機構。
4. ホスト層（R7RS）におけるフォーマット出力およびメトリクス（障害頻度・原因分類カウンタ）の更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] タスククラッシュ時に構造化されたクラッシュレポートが欠損なく生成されること。
- [ ] ロギング処理自体が原因で計算層タスクのスケジューリングがブロックされないこと。
- [ ] Layer 1 側で人間可読なクラッシュ診断ログおよびメトリクスが集計・可視化できること。

