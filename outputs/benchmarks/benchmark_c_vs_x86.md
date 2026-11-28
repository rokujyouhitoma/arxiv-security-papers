# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `2026-11-28T10:57:06.271404+00:00`
- **Environment**: `Linux x86_64 (6.18.58.1-microsoft-standard-WSL2)`, `GCC 13`
- **CPU**: `11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz` (4 cores)
- **Memory**: `12251696 kB`
- **Compiler Engine**: `ulisp/bin/ulisp-boot`
- **Conforms to**: DSN-33, Issue #620, Issue #622, Issue #623

## 1. 実行時間比較（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 対 Pure C 比率 (x86 / Pure) | 対 ULisp C 比率 (x86 / ULisp C) |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 2.05 ± 0.25 (min: 1.79) | 2.38 ± 0.15 (min: 2.16) | 2.20 ± 0.34 (min: 1.89) | **0.93x** | **0.86x** |
| **Tail-Recursive Loop (10M)** | 0.35 ± 0.05 (min: 0.27) | 1.92 ± 5.70 (min: 0.54) | 0.56 ± 0.10 (min: 0.45) | **0.62x** | **0.18x** |
| **Ackermann (ack 3 7)** | 0.38 ± 0.08 (min: 0.27) | 0.60 ± 0.11 (min: 0.50) | 1.04 ± 0.09 (min: 0.92) | **0.37x** | **0.64x** |
| **Higher-Order Closure (1M)** | 0.40 ± 0.05 (min: 0.31) | 0.58 ± 0.10 (min: 0.48) | 0.50 ± 0.04 (min: 0.46) | **0.79x** | **0.68x** |
| **List Alloc & Traverse (100k)** | 1.50 ± 0.21 (min: 1.25) | 1.90 ± 0.31 (min: 1.61) | 1.22 ± 0.19 (min: 1.02) | **1.23x** | **0.79x** |
| **Vector Indexing & Traverse (100k)** | 1.40 ± 0.42 (min: 1.03) | 1.41 ± 0.15 (min: 1.21) | 0.82 ± 0.06 (min: 0.69) | **1.71x** | **0.99x** |

## 2. バイナリフットプリント（Binary Size）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) |
|---|---|---|---|
| **Fibonacci (fib 30)** | 11,400 B | 17,008 B | 16,048 B |
| **Tail-Recursive Loop (10M)** | 11,400 B | 16,832 B | 16,016 B |
| **Ackermann (ack 3 7)** | 11,400 B | 17,040 B | 16,048 B |
| **Higher-Order Closure (1M)** | 11,408 B | 16,832 B | 16,024 B |
| **List Alloc & Traverse (100k)** | 12,456 B | 17,208 B | 16,104 B |
| **Vector Indexing & Traverse (100k)** | 12,512 B | 17,304 B | 16,104 B |

> **注記**:
> - x86-64 Native は `as` / `ld -m elf_x86_64 -static` で直接アセンブル・リンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
> - IPC（Instructions Per Cycle）、Branch Miss %、Cache Miss % は Linux `perf stat` ハードウェアカウンタによる測定値です。
