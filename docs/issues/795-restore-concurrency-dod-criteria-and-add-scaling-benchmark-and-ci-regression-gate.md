---
ID: 795
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 並行性 DoD 基準の復元・スケーリング測定追加および CI 性能リグレッション防止ゲートの確立 (ID: 795)

## 1. 概要 / Summary
コミット `b08864883` において、性能が 4.8 倍劣化していたにもかかわらず、DoD（Definition of Done）判定基準が勝手に緩和（スループット基準が >1M tasks/s から >500k tasks/s へ引き下げ）されたことで、評価レポート上で劣化が「PASS（堅牢化後も高水準維持）」と誤認・偽装されるモラルハザードが発生した。
本 Issue では、本来の DoD 基準（スループット >1M tasks/s、完了時間 <2,000 ms、単一タスクオーバーヘッド <1,000 ns/task）を復元するとともに、計算量の爆発（$O(n^2)$）を早期検知できるスケーリング測定（タスク数 1万 / 10万 / 100万、ワーカー数 $1 \to 2 \to 4$）をベンチマークに追加する。さらに、CI において前回計測値から 20% 以上の性能悪化を検知した際にビルドを失敗させるリグレッション防止品質ゲートを構築し、レポートの不整合記述を正す。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md)
- 関連 Issue: [794-optimize-task-table-to-o1-slot-array-and-eliminate-quadratic-spawn-overhead.md](794-optimize-task-table-to-o1-slot-array-and-eliminate-quadratic-spawn-overhead.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [docs/benchmarks/concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md) - DoD 基準表・評価結果記述の是正
- [ ] [ulisp/Makefile](../../ulisp/Makefile) - ベンチマーク実行ターゲットおよびリグレッション検証スクリプト
- [ ] [tests/concurrency/](../../tests/concurrency/) - スケーリング測定ベンチマークスクリプト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/795-restore-concurrency-dod-criteria-and-add-scaling-benchmark-and-ci-regression-gate`

1. **DoD 基準の厳格化・復元**:
   - スループット: `>1,000,000 tasks/s`（目標 `>3,000,000 tasks/s`）
   - Spawn + 実行時間: `<2,000 ms`（目標 `<100 ms`）
   - 単一タスクオーバーヘッド: `<1,000 ns/task`
2. **スケーリング測定の自動化**:
   - `bench_microtasks` においてタスク数を 10,000 / 100,000 / 1,000,000 件と変化させ、所要時間の増加が線形 $O(n)$ であるかを自動検証。
   - ワーカー数 1, 2, 4 の強スケーリング / 弱スケーリング測定を追加し、CAS 競合によるスケーリング劣化を検知可能にする。
3. **CI 性能リグレッション防止ゲート**:
   - 直近ベースライン記録と比較し、スループットが 20% 超低下した場合は CI を非ゼロ終了（FAILED）とする品質ゲートを Makefile に追加。
4. **評価レポート修正**:
   - `docs/benchmarks/concurrency_evaluation.md` の「堅牢化後も高水準維持」等の記述を実測データに基づく客観的な記述に修正。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] DoD 基準が本来の厳格な数値に復元されていること。
- [ ] タスク数 1万・10万・100万のスケーリング測定スクリプトが整備され、線形性が検証されること。
- [ ] CI 上で 20% 以上の性能悪化を自動検出してブロックするゲートが機能すること。
- [ ] `concurrency_evaluation.md` の虚偽・誤解を招く記述が完全に修正されていること。

