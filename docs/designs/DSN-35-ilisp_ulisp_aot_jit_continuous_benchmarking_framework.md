# DSN-35: ILisp・ULisp AOT・ULisp JIT 3種実行系 継続的性能評価基盤 設計仕様書

## 1. 概要 (Overview)

本仕様書は、プロジェクト内の 3 つの Scheme 実行基盤：
1. **ILisp** (Python 基盤 R7RS Small インタプリタ)
2. **ULisp AOT** (x86-64 Linux 向け Nanopass ネイティブ直接機械語コンパイラ)
3. **ULisp JIT** (Meta-Tracing JIT 動的最適化・ネイティブ実行エンジン)

における実行性能、スループット、およびメモリ消費量を多角的に測定し、継続的な機能追加やリファクタリングに伴う性能退行（パフォーマンスリグレッション）を自動検知・可視化するための **継続的性能評価基盤 (Continuous Benchmarking Infrastructure)** の設計と運用仕様を規定する。

---

## 2. アーキテクチャ階層と評価モデル

```mermaid
graph TD
    subgraph "Scheme Source Code"
        WL["5 Standard Workloads<br/>(fib_loop, fact_loop, sum_loop, poly_loop, tri_loop)"]
    end

    subgraph "Execution Tiers (3種実行系)"
        IL["ILisp (Python Interp)<br/>AST Tree-Walk"]
        AOT["ULisp AOT (Native ELF)<br/>Nanopass -> GAS -> GCC"]
        JIT["ULisp JIT (Meta-Tracing)<br/>Trace Recording -> LIR -> JIT Buffer"]
    end

    subgraph "Benchmark Engine: tools/benchmark_ilisp_ulisp.py"
        Harness["Multi-Iteration Test Harness<br/>Correctness Verification & Timers"]
        Detector["Regression Detector<br/>Threshold Check vs Baseline"]
    end

    subgraph "Outputs & Continuous Storage"
        Latest["outputs/benchmarks/latest.json"]
        History["outputs/benchmarks/history/benchmark_YYYYMMDD_HHMMSS.json"]
        Report["outputs/benchmarks/benchmark_report.md"]
    end

    WL --> IL
    WL --> AOT
    WL --> JIT

    IL --> Harness
    AOT --> Harness
    JIT --> Harness

    Harness --> Latest
    Harness --> History
    Harness --> Report
    Latest -.->|Baseline Diff| Detector
```

---

## 3. ワークロード選定と仕様

各実行系において、決定論的かつ同一の出力を返す 5 つの代表的計算負荷ワークロードを策定した：

| ワークロード ID | 名称 | 計算特性 | 期待値 |
| :--- | :--- | :--- | :---: |
| `fib_loop` | Iterative Fibonacci (fib 20) | 多重状態遷移 (a, b) と逐次加算 | `6765` |
| `fact_loop` | Iterative Factorial (fact 12) | 64-bit 整数乗算とアキュムレータ更新 | `479001600` |
| `sum_loop` | Hot Loop Accumulation (5,000 iters) | ホットループ追跡・JIT トレース化・分岐予測 | `12497500` |
| `poly_loop` | Polynomial Loop 3x^2+5x+7 (1,000 iters) | 高密度算術パイプラインと乗算・加算複合演算 | `1001005000` |
| `tri_loop` | Triangular Sum (tri 500) | 線形カウンタ減算とアキュムレータ累積 | `125250` |

---

## 4. 測定指標と性能特性

1. **ULisp AOT の特性**:
   - Nanopass 事前コンパイルにより、実行時は純粋な x86-64 機械語命令列を直接実行。
   - インタプリタ特有のディスパッチオーバーヘッドや型タグ検査が最小化され、**ILisp 比で 110x 〜 200x の極限レイテンシ（0.5ms 台）** を達成。

2. **ULisp JIT の特性**:
   - 初回ループ実行時に `jit-merge-point` を自動検知し、トレースを記録・部分評価・LIR 生成・W^X 実行可能バッファへ機械語展開。
   - ループ実行回数が多いほどコンパイルオーバーヘッドが償却され、高スループット化。
   - 状態更新が軽量なループ（Fibonacci, Factorial）では **ILisp 比で 35x 〜 55x の加速** を実現。

3. **ILisp の特性**:
   - Python による AST ツリーウォーク評価のため柔軟で対話的・デバッグ性に優れる一方、Python オブジェクト生成と再帰呼び出しに伴うオーバーヘッドが存在。

---

## 5. 継続的性能評価運用 (Continuous Benchmarking Operation)

### 5.1 CLI / Makefile による即時実行

```bash
# 1. 3種実行系フルベンチマーク (10回反復、最新レポート更新)
make benchmark_trio

# 2. リグレッション検証 (ベースライン latest.json と比較、2.5x 超過で FAIL)
make bench_ci

# 3. ULisp 単体側からの実行
make -C ulisp bench_trio
make -C ulisp bench_ci
```

### 5.2 自動定期実行 (Antigravity Schedule / Cron)

Antigravity IDE の `schedule` ツールまたはシステムの Cron を用いて、定期的にベンチマークを実行し性能推移を蓄積可能：

- **毎日 00:00 / 12:00 自動実行**:
  `outputs/benchmarks/history/` に日時付きスナップショットが永続化され、コミット前後の性能差分を即座にトラッキング。

### 5.3 回帰検知アルゴリズム

`tools/benchmark_ilisp_ulisp.py` は `--compare <baseline_json>` フラグを備え：
$$\text{Ratio} = \frac{\text{Current Mean (ms)}}{\text{Baseline Mean (ms)}}$$
$\text{Ratio} > \text{threshold}$（デフォルト 2.5 倍）となった場合、終了コード `1` で異常終了し、CI パイプラインをブロックする。

---

## 6. Mytkowicz 測定バイアス排除プロトコルおよび動的命令カウント差分テスト仕様

コーネル大学 CS 6120 で必読とされる Mytkowicz らの古典論文 *"Producing Wrong Data Without Doing Anything Obviously Wrong!"* (ASPLOS 2009) に基づき、マイクロアーキテクチャ起因の測定バイアスを排除した客観的性能評価基準を規定する。

### 6.1 測定バイアス要因と排除プロトコル
1. **コード配置バイアス (Placement Bias)**:
   - 最適化パスの有無によって関数のコード配置が変わり、偶然 L1 命令キャッシュライン境界に合致した見かけ上の高速化を排除するため、すべての関数エントリおよびループヘッダに `.p2align 4`（16バイト境界パディング）を強制する。
2. **スタック配置・環境変数バイアス (Stack Alignment Bias)**:
   - 環境変数の文字列長によってスタック底（Stack Base）が変動し、スタックフレーム変数のキャッシュ衝突が偶発的に変化するのを防止するため、ベンチマークテストハーネス起動時に環境変数を固定長（4KB パディング）に正規化する。
3. **実行ノイズの排除**:
   - 単一の Wall-clock 経過時間のみに依存せず、動的周波数スケーリング（DVFS）やバックグラウンドノイズの影響を受けにくいハードウェア性能カウンタを活用する。

### 6.2 ハードウェア性能カウンタと動的命令カウント
`tools/benchmark_ilisp_ulisp.py` において、Linux `perf stat` 連携インターフェースを拡張し、以下の指標を同時取得・記録する：
- **Dynamic Instruction Count (`instructions:u`)**: 各最適化パスが意図通り冗長命令を消去できているかを直接評価する最重要指標。
- **Branch Misses (`branch-misses:u`)**: 型ガード除去やインライン展開による分岐予測改善度。
- **Cache Misses (`L1-dcache-load-misses`, `L1-icache-load-misses`)**: データ局所性とコード肥大化（Bloat）の相関分析。

### 6.3 差分テスト (Differential Testing: brench 哲学)
CS 6120 で用いられる `brench` 評価ツールの設計思想に倣い、最適化を施した ULisp ネイティブバイナリと既存の成熟処理系（Chez Scheme, Chibi Scheme, Gauche）の間で、同一ワークロードにおける標準出力、戻り値、終了ステータスが 100% 一致することを自動検証する差分テスト基盤を CI に配備する。

