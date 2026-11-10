---
ID: 795
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 並行性 DoD 基準の復元・スケーリング測定追加および CI 性能リグレッション防止ゲートの確立 (ID: 795)

## 1. 概要 / Summary
コミット `b08864883` において、タスクテーブルの二乗オーダー劣化（Issue #794）により性能が 4.8 倍悪化していたにもかかわらず、DoD（Definition of Done）判定基準が勝手に緩和（スループット基準が >1M tasks/s から >500k tasks/s へ引き下げ）されたことで、評価レポート上で劣化が「PASS（堅牢化後も高水準維持）」と誤認・偽装されるガバナンス上のモラルハザードが発生した。
さらに、現状の `bench_microtasks.scm` は 100,000 タスク・4 ワーカーの単一測定しか行っておらず、合否判定も完了タスク数の一致（データ欠損ゼロ）のみで、スループットや所要時間の閾値判定が行われていなかった。
本 Issue では、以下の 4 本柱によって並行処理基盤の性能ガバナンスを抜本的に再構築する：
1. **本来の DoD 基準の復元**: スループット `>1,000,000 tasks/sec`、完了実行時間 `<2,000 ms`、単一タスク平均遅延 `<1,000 ns/task` を厳格に義務化。
2. **多次元スケーリング測定の導入**: タスク数（10,000 / 100,000 / 1,000,000）による計算量線形性判定と、ワーカー数（1 / 2 / 4）による強・弱スケーリング効率測定を追加。
3. **CI 性能リグレッション防止ゲート**: 直近ベースライン記録と比較し、スループットが 20% 超低下、または Spawn 時間が 50% 超悪化した際に CI を自動失敗させる検証スクリプトを導入。
4. **評価レポート・台帳の整合性是正**: 客観的な測定データに基づく継続的監視体制を確立。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md)
- 関連 Issue: [794-optimize-task-table-to-o1-slot-array-and-eliminate-quadratic-spawn-overhead.md](closed/794-optimize-task-table-to-o1-slot-array-and-eliminate-quadratic-spawn-overhead.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm) - スケーリング測定および DoD 厳格判定ロジックの実装
- [x] [scripts/verify_concurrency_regression.py](../../scripts/verify_concurrency_regression.py) - CI 向け性能リグレッション自動検出スクリプト（新規作成）
- [x] [docs/benchmarks/baseline_concurrency.json](../../docs/benchmarks/baseline_concurrency.json) - 性能ベースライン JSON 定義（新規作成）
- [x] [ulisp/Makefile](../../ulisp/Makefile) - `bench_scaling` および `bench_concurrency_gate` ターゲットの追加
- [x] [docs/benchmarks/concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md) - スケーリング評価セクションおよび DoD 厳格基準の追記

---

## 4. 性能 & 堅牢性要求 (Amdahl / CWE 分析)
- **Amdahl の法則と強スケーリング効率**:
  - 並行ワーカー数を $1 \to 2 \to 4$ と増加させた際、共有データ構造（Chase-Lev デックやタスクテーブル、Futex）の同期競合が激しいと並列化効率が低下する。ワーカー数ごとの Speedup Ratio を算出し、並列化効率 $\ge 60\%$ を維持する。
- **計算量線形性 ($O(n)$ Guard)**:
  - タスク数を 10,000 $\to$ 100,000 $\to$ 1,000,000 と 10 倍ずつ増加させた際、所要時間の増加比率が $10\times$（線形）から逸脱して $100\times$（二乗オーダー）へ跳ね上がる兆候を早期検出する。
- **CWE-400 (リソース枯渇 / 性能劣化の隠蔽防止)**:
  - 基準未達やリグレッション発生時にプロセスを終了コード `1`（FAIL）で落とし、問題が CI をすり抜けるのを防止する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/795-restore-concurrency-dod-and-add-scaling-benchmark-gate`

### Step 1: `bench_microtasks.scm` におけるスケーリング測定と DoD 判定の強化
1. **スケーリング測定関数の実装**:
   - `(run-scaling-benchmark)`:
     - タスク数別スループット: 10,000件、100,000件、1,000,000件
     - ワーカー数別スケーリング: 1 worker、2 workers、4 workers
2. **DoD 基準判定の組み込み**:
   - スループット: `>= 1,000,000 tasks/sec`
   - Spawn 時間: `<= 200 ms`（10万タスク）
   - 完了実行時間: `<= 200 ms`
   - 基準を満たさない場合は `[STATUS]: FAIL (Throughput < 1.0M tasks/sec)` を出力し、`exit 1`（非ゼロ終了）。
3. **JSON メトリクス出力オプション**:
   - 環境変数 `ULISP_BENCH_JSON_OUT=path/to/metrics.json` が指定された場合、全測定結果を構造化 JSON で自動出力。

### Step 2: CI 性能リグレッション検出スクリプト (`scripts/verify_concurrency_regression.py`)
1. 直近の実行結果 JSON と基準ベースライン `docs/benchmarks/baseline_concurrency.json` をロード。
2. 以下の許容マージン（閾値）で回帰を検査：
   - スループット低下: 直近ベースライン比 `-20%` 以内
   - Spawn 時間増加: 直近ベースライン比 `+50%` 以内
   - 実行時間増加: 直近ベースライン比 `+30%` 以内
3. 閾値を超えた悪化を検知した場合は詳細差分テーブルを表示し、リターンコード `1` でビルドを失敗させる。

### Step 3: `ulisp/Makefile` へのゲートターゲット統合
1. `bench_scaling`: スケーリング測定の単独実行ターゲット。
2. `bench_concurrency_gate`:
   - `bench_microtasks` を実行して JSON を出力。
   - `verify_concurrency_regression.py` を呼び出してリグレッション判定を行う。
   - CI の `test_concurrency_ci` または専用ジョブから実行可能にする。

### Step 4: レポート・ドキュメントの更新
1. `docs/benchmarks/concurrency_evaluation.md` にスケーリング分析（タスク数 1万〜100万、ワーカー数 1〜4）およびリグレッション防止ゲートの仕様を追記。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] **DoD 厳格基準の自動検証**:
  - `bench_microtasks` がスループット `>1,000,000 tasks/sec` および Spawn 時間 `<200 ms` を自動検査し、基準割れ時に FAILED となることを検証。
- [x] **多次元スケーリング測定**:
  - タスク数（1万、10万、100万）およびワーカー数（1, 2, 4）のスケーリング測定が動作し、10k $\to$ 100k $\to$ 1M での完全 $O(n)$ 線形性を実証。
- [x] **CI リグレッション防止ゲート**:
  - `make -C ulisp bench_concurrency_gate` が整備され、意図的な性能劣化（20%超低下）を与えた際に CI を停止できることを検証。
- [x] **ベースライン JSON & レポート整合性**:
  - `docs/benchmarks/baseline_concurrency.json` が作成され、`concurrency_evaluation.md` の基準が本来の厳格な数値に統一されていること。
- [x] **品質ゲート**:
  - `make py_compile` および `make static_analysis` が 0 エラーで PASS。
  - 相対パスリンクのみで記述されていること。
