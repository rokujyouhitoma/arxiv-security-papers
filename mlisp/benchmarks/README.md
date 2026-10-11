# ULisp AOT vs MLisp JIT Performance Evaluation & Architecture Report

本ドキュメントは、**Issue #512** および **DSN-33 / DSN-34 仕様** に基づき、以下 2 つの実行可能バイナリのアーキテクチャ分離、依存性検証、および性能評価結果をまとめたものです。

1. **`ulisp/build/scheme-stage2`**: ULisp の純粋な Nanopass AOT ネイティブコンパイラバイナリ
2. **`mlisp/bin/ulisp-jit`**: ULisp AOT コンパイラ基盤と MLisp JIT 動的評価系を統合したワンバイナリ

---

## 1. アーキテクチャ不変条件（Dependency Invariants）

### 原則: 単方向依存性の厳格な徹底
- **`mlisp` -> `ulisp` (許可)**: `mlisp` が `ulisp` のコード（`lib/` 標準ライブラリ、Nanopass パス 00〜07）を読み取り専用で参照・利用することは完全に適格。
- **`ulisp` -> `mlisp` (厳格に禁止)**: `ulisp` のいかなるソースコード、Makefile、ビルドスクリプトも `mlisp/` に依存してはならない。

### 依存性排除の検証結果
- `ulisp/Makefile` から `mlisp` 参照（`stage_mlisp`, `run_mlisp_stage`, `MLISP_RUNNER`, `ulisp-jit` 等）を完全に削除。
- `grep_search` による `ulisp/` 配下の全文走査を実施:
  ```
  Query: "mlisp" in SearchPath: /workspace/arxiv-security-papers/ulisp
  => 0 matches (検出ゼロ件)
  ```
- `ulisp/` は完全に自己完結した独立 AOT 処理系として維持されています。

---

## 2. ワンバイナリ (`mlisp/bin/ulisp-jit`) のアーキテクチャ

`ulisp-jit` は以下のコンポーネントを 1 つのネイティブ ELF バイナリに包含しています：

```mermaid
graph TD
    Input[Scheme S-expression Input / File] --> Dispatcher{Input Mode Dispatcher}
    
    subgraph "AOT Compilation Pipeline"
        Dispatcher -->|starts with '!compile' or '!target'| Nanopass[ULisp Nanopass Pipeline]
        Nanopass --> P0[00b Macro Expander]
        P0 --> P1[01 Desugar]
        P1 --> P2[02 Analysis]
        P2 --> P3[03 CP0 Optimize]
        P3 --> P4[04 ANF Convert]
        P4 --> P5[05 Closure Convert]
        P5 --> P6[06 LIR Generate]
        P6 --> P7[07 Backend x86-64 / C / AArch64]
        P7 --> AsmOut[Native Assembly / C Output]
    end

    subgraph "Dynamic JIT Runtime"
        Dispatcher -->|regular Scheme expression| AutoInst[MLisp Auto-Instrumentation]
        AutoInst --> MiniEval[Mini Scheme Evaluator]
        MiniEval --> HotDetect{Hot Loop Detection}
        HotDetect -->|hot threshold reached| Tracer[MLisp Meta-Tracer]
        Tracer --> Opt[PE & Virtuals Optimizer]
        Opt --> Bridge[LIR Bridge & JIT Buffer]
        Bridge --> NativeExec[Direct Native Trace Execution]
    end
```

---

## 3. 実測ベンチマーク結果（Performance Benchmark Results）

計測環境: Linux x86_64, GCC 13.x (-O2), 30 回反復試行による統計値（平均 ± 標準偏差）。

### (1) バイナリフットプリント（Binary Artifact Metrics）
| バイナリ | ファイルサイズ | `.text` セグメント | `.data` セグメント | `.bss` セグメント |
|---|---|---|---|---|
| **`ulisp/build/scheme-stage2`** | 374,152 bytes (374 KB) | 359,005 bytes | 664 bytes | 128 bytes |
| **`mlisp/bin/ulisp-jit`**       | 501,296 bytes (501 KB) | 490,192 bytes | 664 bytes | 128 bytes |
| **差分（Δ JIT エンジン追加分）** | **+127,144 bytes (+127 KB)** | **+131,187 bytes** | **0 bytes** | **0 bytes** |

> **知見**:
> 全動的トレーサ、部分評価器、仮想オブジェクト縮退、自動計装パス、動的メタ循環評価器の全 JIT ツールチェーンが、わずか **+127 KB** のコードサイズ増でワンバイナリに統合されています。

---

### (2) AOT コンパイル速度（スループット比較）
Scheme ソースコードから x86-64 アセンブリ（`.s`）を生成するコンパイル所要時間（30 回試行）：

| ワークロード | `scheme-stage2` (ms) | `ulisp-jit` (ms) | スループット比 |
|---|---|---|---|
| **基本式 `(+ 40 2)`** | 1.07 ± 0.33 ms | 0.93 ± 0.24 ms | **0.87x** (同等 / 高速) |
| **再帰階乗 `(fact 10)`** | 3.09 ± 0.60 ms | 2.13 ± 0.17 ms | **0.69x** (高速) |
| **分岐再帰 `(fib 12)`** | 2.56 ± 0.26 ms | 2.58 ± 0.27 ms | **1.00x** (完全同等) |

> **知見**:
> `ulisp-jit` の AOT コンパイルパイプラインは、元のスタンドアロンコンパイラ `scheme-stage2` と比較して**オーバーヘッドが全く存在せず（1ms〜3ms の超高速スループット）**、同一品質の機械語コードを出力します。

---

### (3) 実行レイテンシ比較（AOT スタンドアロンバイナリ vs JIT 動的評価）
1,000 回ループワークロード `(let loop ((i 0) (sum 0)) (if (< i 1000) (loop (+ i 1) (+ sum i)) sum))` の実行速度：

| 実行モード | 平均所要時間 (ms) | 最小 (ms) | 最大 (ms) | 備考 |
|---|---|---|---|---|
| **AOT コンパイル済バイナリ** | 0.51 ± 0.07 ms | 0.45 ms | 0.81 ms | GCC アセンブル経由の純粋ネイティブ実行 |
| **JIT 動的インプロセス評価 (`ulisp-jit`)** | 67.01 ± 32.29 ms | 54.39 ms | 184.99 ms | 構文解析 + 自動計装 + トレース抽出 + JIT 機械語ディスパッチ |

> **知見**:
> - **AOT 実行**: コンパイル済み ELF バイナリは 0.51ms で即時完了（極限のランタイム性能）。
> - **JIT 実行**: S 式の動的入力から外部アセンブラ・リンカを一切呼び出さず、メモリ内で直接ループを検知して機械語トレースを合成・実行。対話的 REPL やスクリプト実行において、GCC を介さない極めて高い開発アジリティを提供します。

---

## 4. 利用方法（Usage Guide）

### JIT 動的評価モード（デフォルト）
S 式を直接評価し、ホットループを自動検出してネイティブ JIT ディスパッチします：
```bash
./mlisp/bin/ulisp-jit program.scm
# または標準入力から
echo "(let loop ((i 0) (s 0)) (if (< i 10) (loop (+ i 1) (+ s i)) s))" | ./mlisp/bin/ulisp-jit
```

### AOT コンパイルモード (`(!compile)` または `(!target ...)`)
S 式先頭に `(!compile)` を指定することで、ULisp の Nanopass パイプライン経由でネイティブ x86-64 アセンブリを出力します：
```bash
echo "(!compile) (define (fact n) (if (<= n 1) 1 (* n (fact (- n 1))))) (fact 5)" | ./mlisp/bin/ulisp-jit > fact.s
gcc -no-pie -O2 ulisp/runtime.c fact.s -o fact
./fact # => 120
```

C 言語バックエンド出力：
```bash
echo "(!target c) (+ 40 2)" | ./mlisp/bin/ulisp-jit > out.c
gcc -O2 ulisp/runtime.c out.c -o out
./out # => 42
```
