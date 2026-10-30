# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `2026-10-30T00:38:57.583650+00:00`
- **Environment**: `Linux x86_64 (6.18.54.1-microsoft-standard-WSL2)`, `GCC 13`
- **CPU**: `11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz` (4 cores)
- **Memory**: `12251728 kB`
- **Compiler Engine**: `ulisp/bin/ulisp-boot`
- **Conforms to**: DSN-33, Issue #620, Issue #622, Issue #623

## 1. 実行時間比較（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 対 Pure C 比率 (x86 / Pure) | 対 ULisp C 比率 (x86 / ULisp C) |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 4.17 ± 0.23 (min: 3.92) | 7.91 ± 0.37 (min: 7.49) | 1.81 ± 0.20 (min: 1.62) | **2.30x** | **0.53x** |
| **Tail-Recursive Loop (10M)** | 1.75 ± 0.16 (min: 1.59) | 0.50 ± 0.07 (min: 0.44) | 0.48 ± 0.09 (min: 0.43) | **3.67x** | **3.53x** |
| **Ackermann (ack 3 7)** | 2.92 ± 0.29 (min: 2.62) | 3.70 ± 0.26 (min: 3.33) | 0.98 ± 0.07 (min: 0.91) | **2.98x** | **0.79x** |
| **Higher-Order Closure (1M)** | 2.99 ± 0.21 (min: 2.60) | 4.89 ± 0.35 (min: 4.42) | 0.47 ± 0.05 (min: 0.42) | **6.39x** | **0.61x** |
| **List Alloc & Traverse (100k)** | 2.17 ± 0.61 (min: 1.48) | 1.60 ± 0.20 (min: 1.37) | 1.14 ± 0.15 (min: 0.95) | **1.90x** | **1.36x** |
| **Vector Indexing & Traverse (100k)** | 0.99 ± 0.11 (min: 0.88) | 1.47 ± 0.22 (min: 1.21) | 0.80 ± 0.10 (min: 0.70) | **1.25x** | **0.68x** |

## 2. バイナリフットプリント（Binary Size）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) |
|---|---|---|---|
| **Fibonacci (fib 30)** | 20,160 B | 17,192 B | 16,048 B |
| **Tail-Recursive Loop (10M)** | 19,968 B | 17,120 B | 16,016 B |
| **Ackermann (ack 3 7)** | 20,096 B | 17,232 B | 16,048 B |
| **Higher-Order Closure (1M)** | 20,032 B | 21,920 B | 16,024 B |
| **List Alloc & Traverse (100k)** | 20,096 B | 21,880 B | 16,104 B |
| **Vector Indexing & Traverse (100k)** | 20,176 B | 22,016 B | 16,104 B |

## 3. ハードウェア性能カウンタ（Hardware Performance Counters via Linux perf）

| ワークロード | x86-64 IPC | x86-64 Branch Miss % | x86-64 Cache Miss % | ULisp C IPC | Pure C IPC |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 2.68 | 0.03% | 58.55% | 1.90 | 4.06 |
| **Tail-Recursive Loop (10M)** | 3.31 | 0.12% | 30.34% | 0.67 | 0.56 |
| **Ackermann (ack 3 7)** | 1.05 | 14.21% | 58.03% | 1.13 | 1.82 |
| **Higher-Order Closure (1M)** | 3.12 | 0.03% | 64.91% | 2.16 | 0.75 |
| **List Alloc & Traverse (100k)** | 1.46 | 0.11% | 75.14% | 1.22 | 0.94 |
| **Vector Indexing & Traverse (100k)** | 2.95 | 0.12% | 78.57% | 1.78 | 0.98 |

> **注記**:
> - x86-64 Native は `gcc -nostdlib -static` でリンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
> - IPC（Instructions Per Cycle）、Branch Miss %、Cache Miss % は Linux `perf stat` ハードウェアカウンタによる測定値です。
