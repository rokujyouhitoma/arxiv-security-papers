---
ID: 685
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] フラット Unboxed メモリバッファの導入とスロット間接ポインタ参照の完全排除 (ID: 685)

## 1. 概要 / Summary
現在の `channel.scm` のリングバッファは、`(make-vector capacity)` の各スロットに個別の `(make-atomic-box *ring-empty*)` を割り当てる二重ポインタ構造となっている。
この設計はスロットアクセス時に 2 回のポインタ間接参照（ポインタチェイス）を発生させ、CPU L1 データキャッシュのミスヒットやポインタ追跡のオーバーヘッドを招いている。
本 Issue では、連続した 64-bit ネイティブメモリブロック（フラット配列または bytevector）による Unboxed バッファ構造を導入し、間接参照を完全排除してメモリアクセスを局所化する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: DSN-37 Section 4.3.1 (Unboxed Ring Buffer Architecture)
- 関連 Issue: [Issue #680](closed/680-implement-synapse-channel-cacheline-padding-unboxed-fastpath.md), [Issue #684](684-implement-channel-power-of-two-bitmask-indexing.md)
- ベンチマーク基準: `docs/benchmarks/concurrency_evaluation.md` (メモリキャッシュ効率とチャネル送受信遅延)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [ulisp/lib/ulisp/concurrency/channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld)
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm)
- [ ] [ulisp/tests/concurrency/test_channel.scm](../../ulisp/tests/concurrency/test_channel.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/685-channel-flat-unboxed-buffer`

1. **フラットバッファ構造の設計**:
   - スロット配列をポインタのベクターではなく、連続したメモリブロック（`bytevector` またはアリーナ/ヒープ上のフラットワード配列）としてアロケーション。
   - スロット状態とペイロードをインライン（64-bit unboxed ワード、またはタグ付きスロット）として直接配置。
2. **スロットアクセスの直接化**:
   - `(vector-ref ring slot)` -> `(atomic-ref box)` の 2 段階アクセスを廃止し、ベースアドレス + オフセット計算による単一メモリアクセス命令に変換。
3. **CWE-119 / CWE-416 防御**:
   - フラットバッファ境界検証とライフサイクル解放時のゼロクリアを徹底。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `channel-ring-buffer` が各要素ごとの `atomic-box` ポインタを保持せず、フラットな連続メモリとして配置される。
- [ ] スロットの読み書きが直接メモリアクセス（単一オフセット命令）で行われる。
- [ ] 既存の型安全性・メッセージ整合性（ゼロロス）が 100% 維持される。
- [ ] 送受信ペア遅延がさらに短縮すること。
