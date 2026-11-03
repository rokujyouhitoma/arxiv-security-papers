---
ID: 688
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Nanopass AOT コンパイラによるチャネル送受信ホットパスのネイティブ直接インライン展開 (ID: 688)

## 1. 概要 / Summary
Go 言語のチャネル送受信（`ch <- v` / `<-ch`）は、コンパイラによって直接ランタイムプリミティブ呼出しやインライン最適化コードへ直結される。
一方、現在の Synapse では Scheme の汎用関数呼出し（スタックフレーム生成、`case-lambda` 分岐、型検査）を経由している。
本 Issue では、[Issue #682](closed/682-implement-nanopass-concurrency-hotpath-inlining-and-type-check-elimination.md) で確立された Nanopass インライン化エンジン（`pass_inline_hotpath.scm`）を拡張し、静的に型が既知のチャネル操作（`channel-send!` / `channel-recv!`）を、関数呼出しを完全に排除したネイティブアセンブリ（5〜8 命令の `mov`, `and`, 境界チェック）に直接インライン展開する。
これにより、Go (34〜42 ns) を 2〜3 倍上回る 10〜18 ns / op の超極小チャネル遅延を達成する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: DSN-37 Section 4, 13.4 (Nanopass Native Direct Inlining)
- 関連 Issue: [Issue #682](closed/682-implement-nanopass-concurrency-hotpath-inlining-and-type-check-elimination.md), [Issue #684](684-implement-channel-power-of-two-bitmask-indexing.md), [Issue #687](687-implement-synapse-spsc-linear-channel-lock-free-ring.md)
- ベンチマーク基準: `docs/benchmarks/concurrency_evaluation.md` (Go 42ns 超過達成の実測立証)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm)
- [ ] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm)
- [ ] [docs/benchmarks/concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/688-nanopass-aot-channel-inlining`

1. **Nanopass インライン変換規則の追加**:
   - `(channel-send! ch val)` に対し、チャネルが静的型推論で既知の場合、SPSC フラットリングバッファへの直接書き込みコードへ展開。
   - `(channel-recv! ch)` に対し、リングバッファからの直接読み出しコードへ展開。
2. **スローパス（バッファ満杯 / 空時のサスペンド）への分岐生成**:
   - インラインコード内では Fast Path（空きあり/データあり）のみを数命令で実行し、ブロックが必要な場合のみ通常ランタイム関数へジャンプ。
3. **ベンチマーク実機検証とレポート更新**:
   - `make -C ulisp bench_concurrency` を実行し、Go (34〜42 ns) を明確に下回る遅延（< 25 ns/op）が達成されたことを実証し、`docs/benchmarks/concurrency_evaluation.md` を更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `pass_inline_hotpath.scm` により、チャネル送受信操作がインライン展開され、関数呼出しオーバーヘッドが完全排除されること。
- [ ] 全ての並行テストおよび単体テストが 100% PASS すること。
- [ ] 送受信ペア遅延が Go (42 ns) を下回り、10〜20 ns / op レベルに到達すること。
- [ ] 客観的ベンチマーク評価レポートが更新されること。
