# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `2026-10-28T13:07:52.292363+00:00`
- **Environment**: `Linux x86_64 (6.18.54.1-microsoft-standard-WSL2)`, `GCC 13`
- **CPU**: `11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz` (4 cores)
- **Memory**: `12251728 kB`
- **Compiler Engine**: `ulisp/bin/ulisp-boot`
- **Conforms to**: DSN-33, Issue #620, Issue #622, Issue #623

## 1. 実行時間比較（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 対 Pure C 比率 (x86 / Pure) | 対 ULisp C 比率 (x86 / ULisp C) |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 7.39 ± 1.88 (min: 5.40) | 10.01 ± 0.53 (min: 9.45) | 2.56 ± 0.78 (min: 1.88) | **2.89x** | **0.74x** |
| **Tail-Recursive Loop (10M)** | 3.38 ± 0.18 (min: 3.16) | 0.52 ± 0.03 (min: 0.49) | 0.52 ± 0.06 (min: 0.47) | **6.44x** | **6.44x** |
| **Ackermann (ack 3 7)** | 4.03 ± 0.49 (min: 3.60) | 3.70 ± 0.19 (min: 3.48) | 1.02 ± 0.04 (min: 0.96) | **3.96x** | **1.09x** |
| **Higher-Order Closure (1M)** | 4.05 ± 1.49 (min: 3.40) | 4.96 ± 0.12 (min: 4.75) | 0.52 ± 0.03 (min: 0.48) | **7.76x** | **0.82x** |
| **List Alloc & Traverse (100k)** | 1.52 ± 0.06 (min: 1.45) | 1.79 ± 0.13 (min: 1.64) | 1.15 ± 0.10 (min: 1.00) | **1.33x** | **0.85x** |
| **Vector Indexing & Traverse (100k)** | 1.13 ± 0.05 (min: 1.07) | 2.85 ± 1.75 (min: 1.30) | 0.76 ± 0.04 (min: 0.72) | **1.49x** | **0.40x** |

## 2. バイナリフットプリント（Binary Size）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) |
|---|---|---|---|
| **Fibonacci (fib 30)** | 20,112 B | 17,160 B | 16,048 B |
| **Tail-Recursive Loop (10M)** | 19,928 B | 17,088 B | 16,016 B |
| **Ackermann (ack 3 7)** | 20,048 B | 17,168 B | 16,048 B |
| **Higher-Order Closure (1M)** | 19,984 B | 21,832 B | 16,024 B |
| **List Alloc & Traverse (100k)** | 20,048 B | 21,784 B | 16,104 B |
| **Vector Indexing & Traverse (100k)** | 20,128 B | 21,920 B | 16,104 B |

> **注記**:
> - x86-64 Native は `gcc -nostdlib -static` でリンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
> - IPC（Instructions Per Cycle）、Branch Miss %、Cache Miss % は Linux `perf stat` ハードウェアカウンタによる測定値です。
