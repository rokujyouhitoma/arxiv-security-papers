---
ID: 794
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/PERF] タスクテーブルの O(1) スロット配列化による Spawn 性能 $O(n^2)$ 劣化の根本解消 (ID: 794)

## 1. 概要 / Summary
Synapse 並行性ランタイムにおいて、コミット `b08864883` (#733) 以降、10万マイクロタスクの Spawn 時間が 29 ms から 3,831 ms へ約130倍遅化し、スループットが 4.5M tasks/s から 0.94M tasks/s（約 1/4.8）へ激減する性能リグレッションが発生している。
原因は `channel.scm` におけるタスクテーブルが「64バケット固定連想リスト」で構成されており、登録時のバケット内全件重複チェック走査（10万件で約 $7.8 \times 10^7$ ステップ走査）および削除時の非末尾再帰リストコピー＆CAS競合により実質 $O(n^2)$ の計算量となっているためである。
本 Issue では、TID が単調増加の整数であることを活かしてタスクテーブルを「TID 添字のスロット配列（2の冪マスク、CAS 1回での $O(1)$ 登録・削除）」へ刷新し、重複チェックを排除して元の高スループット（>3M tasks/s, Spawn <50 ms）を回復させる。

### 再現手順 / Steps to Reproduce
1. Linux x86-64 環境にて `make -C uLisp bench_concurrency` を実行する。
2. 10万タスクの Spawn 時間およびスループットを計測する。
3. Spawn に 3.8 秒以上要し、スループットが 1M tasks/s を下回る現象を確認する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / macOS arm64
- File: [channel.scm](../../ulisp/runtime/concurrency/channel.scm)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm) - タスクテーブル構造（`task-table-register!`, `unregister!`, `lookup-task-by-tid`, `task-table-count`, `clear!`）
- [ ] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm) - タスクテーブルの並行登録・削除・検索単体テスト
- [ ] [docs/benchmarks/concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md) - ベンチマーク評価レポート

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **登録パスの二乗オーダー走査 (`channel.scm:165-189`)**:
   - `allocate-task-id!` は単調増加の一意な TID を採番しているにもかかわらず、`task-table-register!` がバケットの連想リストの末尾まで重複確認走査を行っている。
   - バケット数が 64 に固定されているため、10万タスク投入時に 1 バケットあたりのリスト長が約 1,560 件に達し、総走査数が約 $100,000 \times 1,560 / 2 \approx 7.8 \times 10^7$ ステップとなる。
2. **削除パスの非末尾再帰と CAS 競合 (`channel.scm:191-209`)**:
   - 削除時にリストを末尾再帰でない再帰でコピーした上で CAS 更新を行っており、4 ワーカーが同時に同一バケットを奪い合うことで CAS 失敗と再コピーが頻発し、実行フェーズの遅延を招いている。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**:
  - `allocate-task-id!` 発行の新規タスク登録パス（`make-task-context` 経由）において重複チェック走査をバイパスし、バケット先頭へ即座に `cons` して CAS 登録する。
* **恒久対策 (Permanent Fix)**:
  - TID を添字とする伸長可能なスロット配列（容量は $2^n$、`slot = tid & (capacity - 1)`）を導入する。
  - 各スロットを atomic-box とし、登録・検索・削除をすべて $O(1)$ の単一 CAS / 単一読み出しで完結させる（削除時はスロットを `#f` に CAS）。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/794-optimize-task-table-to-o1-slot-array`

1. `ulisp/runtime/concurrency/channel.scm` のタスクテーブル内部実装をスロット配列構造にリファクタリング。
2. 既存の公開 API（`task-table-register!`, `unregister!`, `lookup-task-by-tid`, `task-table-count`, `clear!`）のシグネチャを完全維持。
3. `tests/concurrency/test_channel.scm` にて並行登録・削除の一貫性を検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 10万タスクの Spawn 時間が 50 ms 以下（>3M tasks/s）に回復すること。
- [ ] 実行時間が 30 ms 以下に回復すること。
- [ ] 並行タスク登録・検索・削除の単体テストが 100% PASS すること。

