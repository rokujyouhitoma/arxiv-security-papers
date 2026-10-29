# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `2026-10-29T13:29:30.773937+00:00`
- **Environment**: `Linux x86_64 (6.18.54.1-microsoft-standard-WSL2)`, `GCC 13`
- **CPU**: `11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz` (4 cores)
- **Memory**: `12251728 kB`
- **Compiler Engine**: `ulisp/bin/ulisp-boot`
- **Conforms to**: DSN-33, Issue #620, Issue #622, Issue #623

## 1. 実行時間比較（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 対 Pure C 比率 (x86 / Pure) | 対 ULisp C 比率 (x86 / ULisp C) |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 5.59 ± 0.26 (min: 5.29) | 10.47 ± 0.22 (min: 10.08) | 1.83 ± 0.17 (min: 1.65) | **3.05x** | **0.53x** |
| **Tail-Recursive Loop (10M)** | 3.32 ± 0.14 (min: 3.16) | 0.60 ± 0.08 (min: 0.50) | 0.54 ± 0.06 (min: 0.48) | **6.14x** | **5.56x** |
| **Ackermann (ack 3 7)** | 4.17 ± 0.64 (min: 3.73) | 4.05 ± 0.21 (min: 3.77) | 1.03 ± 0.14 (min: 0.92) | **4.05x** | **1.03x** |
| **Higher-Order Closure (1M)** | 4.33 ± 0.67 (min: 3.63) | 5.56 ± 0.31 (min: 4.95) | 0.54 ± 0.07 (min: 0.47) | **8.01x** | **0.78x** |
| **List Alloc & Traverse (100k)** | 1.75 ± 0.21 (min: 1.50) | 1.88 ± 0.27 (min: 1.65) | 1.10 ± 0.07 (min: 0.99) | **1.59x** | **0.93x** |
| **Vector Indexing & Traverse (100k)** | 1.17 ± 0.06 (min: 1.10) | 1.54 ± 0.22 (min: 1.29) | 0.87 ± 0.10 (min: 0.77) | **1.34x** | **0.76x** |

## 2. バイナリフットプリント（Binary Size）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) |
|---|---|---|---|
| **Fibonacci (fib 30)** | 20,112 B | 17,192 B | 16,048 B |
| **Tail-Recursive Loop (10M)** | 19,928 B | 17,088 B | 16,016 B |
| **Ackermann (ack 3 7)** | 20,048 B | 17,232 B | 16,048 B |
| **Higher-Order Closure (1M)** | 19,984 B | 21,920 B | 16,024 B |
| **List Alloc & Traverse (100k)** | 20,048 B | 21,880 B | 16,104 B |
| **Vector Indexing & Traverse (100k)** | 20,128 B | 22,016 B | 16,104 B |

> **注記**:
> - x86-64 Native は `gcc -nostdlib -static` でリンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
> - IPC（Instructions Per Cycle）、Branch Miss %、Cache Miss % は Linux `perf stat` ハードウェアカウンタによる測定値です。
