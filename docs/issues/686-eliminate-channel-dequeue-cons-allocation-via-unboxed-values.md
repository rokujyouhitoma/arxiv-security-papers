---
ID: 686
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 多値レジスタ渡しによるチャネルデキュー時のタプル (cons) 動的割り当てゼロ化 (ID: 686)

## 1. 概要 / Summary
現在の `channel-recv!` および `%channel-ring-try-dequeue!` では、取得成功時に `(cons #t msg)` というヒープペア（cons セル）を動的生成して返却している。
このタプルアロケーションは、メッセージ送受信ごとにヒープまたはアリーナへのメモリアロケーションと GC プレッシャーを発生させ、ナノ秒単位の遅延を悪化させる一因となっている。
本 Issue では、uLisp AOT コンパイラの呼び出し規約を活用し、ステータス（成功/空）とペイロードを CPU レジスタペア（`%rax` / `%rdx`）により直接返却する Unboxed 多値（Multiple Values）返却機構を確立し、デキュー時の動的アロケーションを完全ゼロ化（0 bytes）する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: DSN-37 Section 4.3.1 (Zero-Allocation Receive Protocol)
- 関連 Issue: [Issue #625](closed/625-phase2-system-v-register-based-calling-convention.md), [Issue #685](685-implement-channel-flat-unboxed-memory-buffer.md)
- ベンチマーク基準: `docs/benchmarks/concurrency_evaluation.md` (デキュー時アロケーション 0B および遅延短縮)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [ulisp/lib/ulisp/concurrency/channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld)
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm)
- [ ] [ulisp/tests/concurrency/test_channel.scm](../../ulisp/tests/concurrency/test_channel.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/686-eliminate-channel-dequeue-cons`

1. **Unboxed 多値デキュー API (`%channel-try-dequeue-unboxed!`) の導入**:
   - `(cons #t msg)` の生成を廃止。
   - 呼び出し規約において、第 1 戻り値（成功フラグ）を `%rax`、第 2 戻り値（値）を `%rdx` に格納して返却するか、あるいは直接値のみを返し空状態をセンチネル値（`#f` または未束縛トークン）で表すゼロアロケーションインターフェースを導入。
2. **`channel-recv!` 受信ホットパスのゼロアロケーション化**:
   - `channel-recv!` においてペア分解（`car`, `cdr`）のオーバーヘッドを撤廃。
3. **後方互換性と安全性**:
   - 従来の Scheme API 互換レイヤを維持しつつ、コンパイラ最適化パスがゼロアロケーション版を自動選択可能にする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `%channel-ring-try-dequeue!` の実行において `cons` ペアのアロケーションがゼロ（0 bytes）になること。
- [ ] デキュー処理におけるレジスタ直接返却またはセンチネル返却が正しく機能すること。
- [ ] 既存の並行性テスト・メッセージ順序検証が 100% PASS すること。
