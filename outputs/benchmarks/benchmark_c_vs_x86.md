# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `2026-10-26T14:17:47.712636+00:00`
- **Environment**: `Linux x86_64`, `GCC 13`
- **Compiler Engine**: `ulisp/bin/ulisp-boot`
- **Conforms to**: DSN-33, Issue #620

## 1. 実行時間比較（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 対 Pure C 比率 (x86 / Pure) | 対 ULisp C 比率 (x86 / ULisp C) |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 8.20 ± 1.53 (min: 6.29) | 11.06 ± 0.94 (min: 10.14) | 2.35 ± 0.21 (min: 2.03) | **3.49x** | **0.74x** |
| **Tail-Recursive Loop (10M)** | 4.01 ± 0.21 (min: 3.82) | 0.65 ± 0.21 (min: 0.48) | 0.58 ± 0.11 (min: 0.46) | **6.86x** | **6.17x** |
| **Ackermann (ack 3 7)** | 4.60 ± 0.20 (min: 4.30) | 4.60 ± 0.22 (min: 4.38) | 1.26 ± 0.13 (min: 1.10) | **3.66x** | **1.00x** |
| **Higher-Order Closure (1M)** | 4.28 ± 0.31 (min: 3.83) | 6.33 ± 0.55 (min: 5.89) | 0.70 ± 0.22 (min: 0.49) | **6.08x** | **0.68x** |
| **List Alloc & Traverse (100k)** | 2.22 ± 0.46 (min: 1.85) | 2.84 ± 0.54 (min: 2.45) | 1.96 ± 0.28 (min: 1.52) | **1.13x** | **0.78x** |
| **Vector Indexing & Traverse (100k)** | 1.29 ± 0.19 (min: 1.15) | 2.59 ± 0.33 (min: 2.05) | 1.25 ± 0.22 (min: 0.97) | **1.03x** | **0.50x** |

## 2. バイナリフットプリント（Binary Size）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) |
|---|---|---|---|
| **Fibonacci (fib 30)** | 19,576 B | 16,960 B | 16,048 B |
| **Tail-Recursive Loop (10M)** | 19,392 B | 16,888 B | 16,016 B |
| **Ackermann (ack 3 7)** | 19,512 B | 16,960 B | 16,048 B |
| **Higher-Order Closure (1M)** | 19,456 B | 17,640 B | 16,024 B |
| **List Alloc & Traverse (100k)** | 19,512 B | 21,776 B | 16,104 B |
| **Vector Indexing & Traverse (100k)** | 19,600 B | 21,832 B | 16,104 B |

> **注記**:
> - x86-64 Native は `gcc -nostdlib -static` でリンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
