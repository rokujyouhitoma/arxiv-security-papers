---
ID: 683
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Linux io_uring カーネルポーリング (SQPOLL) と登録バッファによるゼロシステムコール I/O の統合 (ID: 683)

## 1. 概要 / Summary
Synapse 並行処理基盤（[DSN-37](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)）において、Issue #677 により Linux `io_uring` 非同期イベントループが導入された。
現在の実装では、I/O 投入時に `SYS_io_uring_enter` (syscall 426) を発行してカーネルへ通知している。
本 Issue では、カーネル空間ポーリングスレッドを活用する `IORING_SETUP_SQPOLL` フラグのサポートと、事前メモリピン留めを行う登録バッファ機構（`io_uring_register_buffers`）を統合する。これにより、ユーザー空間から共有メモリリングへの書き込みのみで I/O を発行・完了させる「完全ゼロシステムコール非同期 I/O」を実現する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Phase 7 / Phase 8)
- 関連評価書: [Synapse Concurrency Benchmark Suite](../benchmarks/concurrency_evaluation.md)
- 先行 Issue: [Issue #677: Linux io_uring イベントループ統合](closed/677-integrate-synapse-io-uring-event-loop.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/io_uring.s](../../ulisp/runtime/concurrency/io_uring.s) (`SYS_io_uring_register` (427) アセンブリハンドラ、`IORING_SETUP_SQPOLL` 定義)
- [ ] [ulisp/runtime/concurrency/io_uring.scm](../../ulisp/runtime/concurrency/io_uring.scm) (`make-io-uring` 拡張引数、バッファ登録 API、SQPOLL 対応)
- [ ] [ulisp/lib/ulisp/concurrency/io_uring.sld](../../ulisp/lib/ulisp/concurrency/io_uring.sld)
- [ ] [tests/concurrency/test_io_uring.scm](../../tests/concurrency/test_io_uring.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/683-synapse-io-uring-sqpoll-and-registered-buffers`

1. **`io_uring_register` システムコールバインディングの実装**:
   - `io_uring.s` に Linux syscall 427 (`SYS_io_uring_register`) のラッパー関数 `%sys-io-uring-register` を実装。
2. **SQPOLL モードの有効化とフォールバック**:
   - `make-io-uring` のオプションに `sqpoll?` フラグを追加。
   - `IORING_SETUP_SQPOLL`（カーネルポーリングスレッド）が利用可能な環境では、`SYS_io_uring_enter` 発行を省略し、共有メモリ SQ tail のアトミック更新のみで I/O を即時キック。
   - 権限不足（`CAP_SYS_ADMIN` 不足等）やコンテナ環境では自動的に従来の `enter` 発行モードに安全フォールバック。
3. **固定バッファ登録 (Registered Buffers)**:
   - `io-uring-register-buffers!` 手続きにより、タスクアリーナや I/O バッファを事前登録し、I/O ごとのページピン留め/アンピンオーバーヘッドを排除。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `io_uring.s` に `SYS_io_uring_register` (427) のネイティブバインディングが実装されていること。
- [ ] SQPOLL オプション指定時に、カーネルポーリングを活用したゼロシステムコール I/O が機能すること（非対応環境では透過的フォールバック）。
- [ ] 既存の 61 アサーションの `test_io_uring.scm` が 100% PASS し、SQPOLL および登録バッファのテストケースが追加されること。
- [ ] セキュリティ境界（CWE-119, CWE-400, CWE-843）が維持されていること。
- [ ] 絶対パスリンクが 0 件であり、全内部リンクが相対パスであること。

