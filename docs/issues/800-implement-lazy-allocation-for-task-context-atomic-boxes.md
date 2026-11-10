---
ID: 800
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/PERF] task-context における atomic-box の遅延初期化によるヒープ割り当てと GC 負荷の削減 (ID: 800)

## 1. 概要 / Summary
Synapse 並行性ランタイムにおいて、`channel.scm:249-256` の `%create-task-context-default` では、1つのタスクが生成されるたびに無条件で 11 個の `make-atomic-box` オブジェクトをヒープ上に割り当てている。
10万タスクの Spawn においては、これだけで **110万個以上のヒープオブジェクト** が生成されることになり、メモリ確保オーバーヘッドと GC への多大な圧力をもたらしている。
しかし実際には、生成されるマイクロタスクの大多数は `monitored-by`, `links`, `owned-channels` などの高度なフォールトトレランス構造を使用しない。
本 Issue では、これらの使用頻度の低い atomic-box を `#f` で初期化しておき、実際に link や monitor、チャネル登録が呼び出された初回にのみ CAS で初期化・確保する「遅延初期化（Lazy Allocation）」を導入し、Spawn 性能の向上とヒープメモリ消費の半減を実現する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md)
- 関連 Issue: [794-optimize-task-table-to-o1-slot-array-and-eliminate-quadratic-spawn-overhead.md](794-optimize-task-table-to-o1-slot-array-and-eliminate-quadratic-spawn-overhead.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm) - `%create-task-context-default` およびアクセサ
- [ ] [ulisp/runtime/concurrency/links.scm](../../ulisp/runtime/concurrency/links.scm) - `task-link!`, `task-monitor` 等の初回 box 取得ロジック
- [ ] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm) - タスクコンテキスト生成および遅延初期化単体テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/800-implement-lazy-allocation-for-task-context-atomic-boxes`

1. **遅延確保パターンの定義**:
   - `task-monitored-by-box`, `task-links-box`, `task-owned-channels-box` などの初期値を `#f` とする。
   - box が `#f` の場合、初回のアクセス手続（例: `ensure-task-links-box!`）において `make-atomic-box` を作成し、スロットへ CAS で格納する。
2. **既存アクセサの整合性維持**:
   - 外部・内部の既存コードが `(task-links-box task)` を呼び出した際にも、透過的に有効な atomic-box が返却されるヘルパーを整備。
3. **ベンチマークによるメモリ削減効果検証**:
   - 10万タスク生成時のヒープ割り当て量および Spawn 所要時間の短縮を実測。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 1タスク生成あたりの即時 atomic-box 割り当て数が大幅に削減（11個 $\to$ 2〜3個以下）されること。
- [ ] 遅延初期化時および並行アクセス時において、atomic-box の多重生成や競合破壊が発生しないこと。
- [ ] 既存のリンク・モニタ・チャネル機能の全テストが 100% PASS すること。

