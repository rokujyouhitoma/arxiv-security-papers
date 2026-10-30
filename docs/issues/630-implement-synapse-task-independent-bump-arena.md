---
ID: 630
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Synapse タスク独立バンプアリーナおよび O(1) 瞬時全破棄機構の実装 (ID: 630)

## 1. 概要 / Summary
[DSN-37] Phase 0 Task 0.1 に基づき、Synapse-Core 並列タスク用の極小独立バンプアリーナ（初期 2KB〜8KB）を Pure Scheme で実装する。
各タスクが OS スレッドスタックおよびグローバル GC ヒープから完全に隔離されたメモリ空間を保持し、タスク完了時にポインタのゼロリセットのみで全ローカルオブジェクトを一括破棄する $O(1)$ 瞬時解放を実現する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: Synapse 二層分離型並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#142-phase-0-メモリ--アトミック基底) (第 5 章 メモリモデル、第 14.2 節 Task 0.1)
- 関連仕様書: [DSN-36: Zero-libc Pure Scheme ベアメタルランタイム包括設計仕様書](../designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/runtime/synapse/arena.scm` (新規: タスク独立バンプアリーナ実装)
- [ ] `tests/synapse/test_arena.scm` (新規: アリーナ単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/630-synapse-task-bump-arena`

1. **アリーナ構造体定義**:
   - `(define-record-type <task-arena> ...)` により基底アドレス（`base`）、現在オフセット（`offset`）、容量（`capacity`）を保持。
2. **高速バンプ割り当て**:
   - `(arena-allocate! arena size)`: 8バイト境界アライメント（`bitwise-and (+ size 7) (bitwise-not 7)`）を行い、オフセットを加算。
3. **O(1) 瞬時解放**:
   - `(arena-reset! arena)`: オフセットを 0 にリセット。
4. **チャンク連鎖フォールバック**:
   - 初期容量超過時に備え、拡張 8KB チャンクのリンクリストを保持し、リセット時にまとめて回収。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(arena-allocate! arena size)` が 8 バイト境界で正しくアドレスを返却すること
- [ ] `(arena-reset! arena)` が $O(1)$ でメモリをゼロクリア／リセットすること
- [ ] 100 万回のアロケーションおよびリセットを反復実行し、メモリリークが 0 バイトであること
- [ ] すべての内部リンクが相対パスリンク規約に準拠していること

