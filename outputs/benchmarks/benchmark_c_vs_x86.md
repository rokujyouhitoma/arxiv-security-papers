# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `2026-10-28T01:11:14.910322+00:00`
- **Environment**: `Linux x86_64`, `GCC 13`
- **Compiler Engine**: `ulisp/bin/ulisp-boot`
- **Conforms to**: DSN-33, Issue #620, Issue #622

## 1. 実行時間比較（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 対 Pure C 比率 (x86 / Pure) | 対 ULisp C 比率 (x86 / ULisp C) |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 5.77 ± 0.73 (min: 5.07) | 8.39 ± 0.50 (min: 7.75) | 1.96 ± 0.19 (min: 1.77) | **2.95x** | **0.69x** |
| **Tail-Recursive Loop (10M)** | 3.41 ± 0.30 (min: 3.13) | 0.47 ± 0.02 (min: 0.44) | 0.55 ± 0.05 (min: 0.49) | **6.17x** | **7.32x** |
| **Ackermann (ack 3 7)** | 4.26 ± 0.40 (min: 3.60) | 3.73 ± 0.32 (min: 3.30) | 0.98 ± 0.03 (min: 0.92) | **4.36x** | **1.14x** |
| **Higher-Order Closure (1M)** | 3.36 ± 0.33 (min: 2.93) | 4.57 ± 0.25 (min: 4.22) | 0.53 ± 0.06 (min: 0.46) | **6.37x** | **0.74x** |
| **List Alloc & Traverse (100k)** | 1.58 ± 0.11 (min: 1.43) | 2.18 ± 0.26 (min: 1.77) | 1.20 ± 0.03 (min: 1.13) | **1.31x** | **0.73x** |
| **Vector Indexing & Traverse (100k)** | 1.07 ± 0.01 (min: 1.05) | 1.35 ± 0.15 (min: 1.13) | 0.95 ± 0.14 (min: 0.73) | **1.13x** | **0.80x** |

## 2. バイナリフットプリント（Binary Size）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) |
|---|---|---|---|
| **Fibonacci (fib 30)** | 20,112 B | 17,160 B | 16,048 B |
| **Tail-Recursive Loop (10M)** | 19,928 B | 17,088 B | 16,016 B |
| **Ackermann (ack 3 7)** | 20,048 B | 17,160 B | 16,048 B |
| **Higher-Order Closure (1M)** | 19,984 B | 21,832 B | 16,024 B |
| **List Alloc & Traverse (100k)** | 20,048 B | 21,872 B | 16,104 B |
| **Vector Indexing & Traverse (100k)** | 20,128 B | 21,920 B | 16,104 B |

## 3. ハードウェア性能カウンタ（Hardware Performance Counters via Linux perf）

| ワークロード | x86-64 IPC | x86-64 Branch Miss % | x86-64 Cache Miss % | ULisp C IPC | Pure C IPC |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 3.48 | 0.04% | 51.53% | 2.24 | 4.21 |
| **Tail-Recursive Loop (10M)** | 3.01 | 0.01% | 21.38% | 0.48 | 0.68 |
| **Ackermann (ack 3 7)** | 1.57 | 12.19% | 23.58% | 1.44 | 1.73 |
| **Higher-Order Closure (1M)** | 2.63 | 0.05% | 67.92% | 2.26 | 0.69 |
| **List Alloc & Traverse (100k)** | 1.87 | 0.11% | 67.99% | 1.66 | 0.98 |
| **Vector Indexing & Traverse (100k)** | 3.01 | 0.12% | 62.12% | 1.81 | 0.99 |

> **注記**:
> - x86-64 Native は `gcc -nostdlib -static` でリンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
> - IPC（Instructions Per Cycle）、Branch Miss %、Cache Miss % は Linux `perf stat` ハードウェアカウンタによる測定値です。
