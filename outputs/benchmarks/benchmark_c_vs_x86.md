# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `2026-10-31T06:52:41.465503+00:00`
- **Environment**: `Linux x86_64 (6.18.54.1-microsoft-standard-WSL2)`, `GCC 13`
- **CPU**: `11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz` (4 cores)
- **Memory**: `12251728 kB`
- **Compiler Engine**: `ulisp/bin/ulisp-boot`
- **Conforms to**: DSN-33, Issue #620, Issue #622, Issue #623

## 1. 実行時間比較（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 対 Pure C 比率 (x86 / Pure) | 対 ULisp C 比率 (x86 / ULisp C) |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 6.21 ± 0.26 (min: 5.77) | 14.94 ± 1.26 (min: 12.73) | 2.72 ± 0.25 (min: 2.27) | **2.29x** | **0.42x** |
| **Tail-Recursive Loop (10M)** | 2.88 ± 0.19 (min: 2.64) | 1.14 ± 0.16 (min: 0.91) | 0.76 ± 0.15 (min: 0.65) | **3.78x** | **2.54x** |
| **Ackermann (ack 3 7)** | 6.04 ± 1.15 (min: 5.10) | 5.46 ± 0.38 (min: 5.08) | 2.20 ± 0.40 (min: 1.65) | **2.75x** | **1.11x** |
| **Higher-Order Closure (1M)** | 4.65 ± 1.08 (min: 3.42) | 6.81 ± 0.18 (min: 6.49) | 0.67 ± 0.08 (min: 0.59) | **6.97x** | **0.68x** |
| **List Alloc & Traverse (100k)** | 1.91 ± 0.27 (min: 1.66) | 2.95 ± 0.50 (min: 2.16) | 1.76 ± 0.32 (min: 1.45) | **1.09x** | **0.65x** |
| **Vector Indexing & Traverse (100k)** | 1.68 ± 0.54 (min: 1.31) | 2.10 ± 0.23 (min: 1.77) | 1.10 ± 0.10 (min: 1.00) | **1.52x** | **0.80x** |

## 2. バイナリフットプリント（Binary Size）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) |
|---|---|---|---|
| **Fibonacci (fib 30)** | 20,264 B | 16,992 B | 16,048 B |
| **Tail-Recursive Loop (10M)** | 20,080 B | 16,920 B | 16,016 B |
| **Ackermann (ack 3 7)** | 20,200 B | 17,024 B | 16,048 B |
| **Higher-Order Closure (1M)** | 20,144 B | 21,720 B | 16,024 B |
| **List Alloc & Traverse (100k)** | 20,208 B | 21,680 B | 16,104 B |
| **Vector Indexing & Traverse (100k)** | 20,288 B | 21,816 B | 16,104 B |

> **注記**:
> - x86-64 Native は `as` / `ld -m elf_x86_64 -static` で直接アセンブル・リンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
> - IPC（Instructions Per Cycle）、Branch Miss %、Cache Miss % は Linux `perf stat` ハードウェアカウンタによる測定値です。
