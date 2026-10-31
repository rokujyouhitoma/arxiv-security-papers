---
ID: 631
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Scheme 低レベルアトミック命令 (atomic-cas! / atomic-box) の提供 (ID: 631)

## 1. 概要 / Summary
[DSN-37] Phase 0 Task 0.2 に基づき、Michael-Scott ロックフリーキューや M:N スケジューラの同期基盤となる Scheme 低レベルアトミック操作プリミティブを実装する。
x86-64 の `lock cmpxchg` 命令に直結する Compare-And-Swap（CAS）および順序保証付きメモリバリア操作を Pure Scheme / uLisp LIR プリミティブとして提供する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#142-phase-0-メモリ--アトミック基底) (第 6 章 排他制御、第 14.2 節 Task 0.2)
- 関連仕様書: [DSN-33: uLisp x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/runtime/concurrency/atomic.scm` (新規: アトミックプリミティブ Scheme ラッパー)
- [ ] `ulisp/backend/140_backend_x86_64.scm` (変更: `atomic-cas!` の x86-64 LIR / 命令選択)
- [ ] `tests/concurrency/test_atomic.scm` (新規: アトミック並行テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/631-atomic-primitives`

1. **アトミック参照セル**:
   - `(define-record-type <atomic-box> (make-atomic-box val) atomic-box? (val atomic-box-ref atomic-box-set!))`
2. **CAS 命令の LIR 展開**:
   - `(atomic-cas! box expected new)` を uLisp バックエンドで `lock cmpxchg [rdi], rsi` 命令へマッピング。
   - 成功時に `#t`、失敗時に `#f` を ZF フラグから `sete` で獲得。
3. **アトミック読み書き**:
   - `atomic-ref`, `atomic-set!` にメモリバリア（acquire/release セマンティクス）を付与。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `atomic-cas!` が期待値一致時のみ値を置換して `#t` を返却すること
- [ ] 期待値不一致時に置換を行わず `#f` を返却すること
- [ ] 複数スレッド／タスク競合下で厳密に 1 勝者のみが確定する単体テスト PASS
- [ ] すべての内部リンクが相対パスリンク規約に準拠していること
