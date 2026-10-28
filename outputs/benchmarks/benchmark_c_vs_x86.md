# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `2026-10-28T04:50:36.729420+00:00`
- **Environment**: `Linux x86_64 (6.18.54.1-microsoft-standard-WSL2)`, `GCC 13`
- **CPU**: `11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz` (4 cores)
- **Memory**: `12251728 kB`
- **Compiler Engine**: `ulisp/bin/ulisp-boot`
- **Conforms to**: DSN-33, Issue #620, Issue #622, Issue #623

## 1. 実行時間比較（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 対 Pure C 比率 (x86 / Pure) | 対 ULisp C 比率 (x86 / ULisp C) |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 5.57 ± 0.48 (min: 5.21) | 8.45 ± 0.17 (min: 8.22) | 2.11 ± 0.50 (min: 1.73) | **2.64x** | **0.66x** |
| **Tail-Recursive Loop (10M)** | 3.39 ± 0.21 (min: 3.09) | 0.53 ± 0.04 (min: 0.47) | 0.46 ± 0.02 (min: 0.44) | **7.40x** | **6.39x** |
| **Ackermann (ack 3 7)** | 3.73 ± 0.29 (min: 3.30) | 4.52 ± 0.43 (min: 4.10) | 1.05 ± 0.03 (min: 1.01) | **3.55x** | **0.82x** |
| **Higher-Order Closure (1M)** | 3.57 ± 0.26 (min: 3.23) | 4.52 ± 0.17 (min: 4.36) | 0.47 ± 0.01 (min: 0.45) | **7.64x** | **0.79x** |
| **List Alloc & Traverse (100k)** | 1.71 ± 0.12 (min: 1.57) | 2.16 ± 0.14 (min: 1.96) | 1.25 ± 0.11 (min: 1.11) | **1.37x** | **0.79x** |
| **Vector Indexing & Traverse (100k)** | 1.22 ± 0.11 (min: 1.13) | 3.51 ± 1.83 (min: 2.20) | 0.94 ± 0.10 (min: 0.79) | **1.30x** | **0.35x** |

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
| **Fibonacci (fib 30)** | 2.73 | 0.04% | 52.23% | 2.25 | 4.24 |
| **Tail-Recursive Loop (10M)** | 3.03 | 0.01% | 67.90% | 0.77 | 0.49 |
| **Ackermann (ack 3 7)** | 1.55 | 12.26% | 55.91% | 1.45 | 1.70 |
| **Higher-Order Closure (1M)** | 3.35 | 0.03% | 53.27% | 2.26 | 0.45 |
| **List Alloc & Traverse (100k)** | 1.71 | 0.13% | 61.04% | 1.64 | 0.94 |
| **Vector Indexing & Traverse (100k)** | 2.20 | 0.18% | 51.85% | 1.76 | 0.93 |

> **注記**:
> - x86-64 Native は `gcc -nostdlib -static` でリンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
> - IPC（Instructions Per Cycle）、Branch Miss %、Cache Miss % は Linux `perf stat` ハードウェアカウンタによる測定値です。
