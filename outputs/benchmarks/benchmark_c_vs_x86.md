# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `2026-10-29T23:23:15.389497+00:00`
- **Environment**: `Linux x86_64 (6.18.54.1-microsoft-standard-WSL2)`, `GCC 13`
- **CPU**: `11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz` (4 cores)
- **Memory**: `12251728 kB`
- **Compiler Engine**: `ulisp/bin/ulisp-boot`
- **Conforms to**: DSN-33, Issue #620, Issue #622, Issue #623

## 1. 実行時間比較（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 対 Pure C 比率 (x86 / Pure) | 対 ULisp C 比率 (x86 / ULisp C) |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 4.12 ± 0.15 (min: 3.94) | 7.82 ± 0.44 (min: 7.29) | 1.80 ± 0.18 (min: 1.63) | **2.29x** | **0.53x** |
| **Tail-Recursive Loop (10M)** | 3.33 ± 0.20 (min: 3.15) | 0.57 ± 0.03 (min: 0.51) | 0.50 ± 0.03 (min: 0.45) | **6.63x** | **5.83x** |
| **Ackermann (ack 3 7)** | 2.95 ± 0.25 (min: 2.66) | 3.75 ± 0.30 (min: 3.41) | 1.05 ± 0.14 (min: 0.94) | **2.82x** | **0.79x** |
| **Higher-Order Closure (1M)** | 3.01 ± 0.50 (min: 2.59) | 4.60 ± 0.19 (min: 4.39) | 0.51 ± 0.03 (min: 0.46) | **5.95x** | **0.65x** |
| **List Alloc & Traverse (100k)** | 1.45 ± 0.21 (min: 1.26) | 4.27 ± 3.90 (min: 1.63) | 1.13 ± 0.10 (min: 1.04) | **1.28x** | **0.34x** |
| **Vector Indexing & Traverse (100k)** | 0.99 ± 0.03 (min: 0.95) | 1.44 ± 0.20 (min: 1.27) | 0.80 ± 0.07 (min: 0.74) | **1.23x** | **0.69x** |

## 2. バイナリフットプリント（Binary Size）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) |
|---|---|---|---|
| **Fibonacci (fib 30)** | 20,160 B | 17,192 B | 16,048 B |
| **Tail-Recursive Loop (10M)** | 19,968 B | 17,088 B | 16,016 B |
| **Ackermann (ack 3 7)** | 20,096 B | 17,232 B | 16,048 B |
| **Higher-Order Closure (1M)** | 20,032 B | 21,920 B | 16,024 B |
| **List Alloc & Traverse (100k)** | 20,096 B | 21,880 B | 16,104 B |
| **Vector Indexing & Traverse (100k)** | 20,176 B | 22,016 B | 16,104 B |

> **注記**:
> - x86-64 Native は `gcc -nostdlib -static` でリンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
> - IPC（Instructions Per Cycle）、Branch Miss %、Cache Miss % は Linux `perf stat` ハードウェアカウンタによる測定値です。
