# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `2026-11-28T08:35:08.517871+00:00`
- **Environment**: `Linux x86_64 (6.18.58.1-microsoft-standard-WSL2)`, `GCC 13`
- **CPU**: `11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz` (4 cores)
- **Memory**: `12251696 kB`
- **Compiler Engine**: `ulisp/bin/ulisp-boot`
- **Conforms to**: DSN-33, Issue #620, Issue #622, Issue #623

## 1. 実行時間比較（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 対 Pure C 比率 (x86 / Pure) | 対 ULisp C 比率 (x86 / ULisp C) |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 5.48 ± 0.45 (min: 5.09) | 7.86 ± 0.65 (min: 7.42) | 1.86 ± 0.20 (min: 1.66) | **2.94x** | **0.70x** |
| **Tail-Recursive Loop (10M)** | 11.52 ± 0.49 (min: 10.88) | 23.18 ± 3.07 (min: 20.52) | 0.56 ± 0.06 (min: 0.46) | **20.48x** | **0.50x** |
| **Ackermann (ack 3 7)** | 3.68 ± 0.14 (min: 3.51) | 4.59 ± 0.16 (min: 4.34) | 0.99 ± 0.09 (min: 0.85) | **3.74x** | **0.80x** |
| **Higher-Order Closure (1M)** | 1.42 ± 0.10 (min: 1.30) | 2.69 ± 0.12 (min: 2.50) | 0.55 ± 0.06 (min: 0.49) | **2.57x** | **0.53x** |
| **List Alloc & Traverse (100k)** | 1.35 ± 0.15 (min: 1.16) | 1.70 ± 0.16 (min: 1.48) | 1.43 ± 0.38 (min: 1.09) | **0.95x** | **0.80x** |
| **Vector Indexing & Traverse (100k)** | 1.49 ± 0.30 (min: 1.21) | 1.53 ± 0.19 (min: 1.32) | 0.84 ± 0.07 (min: 0.73) | **1.76x** | **0.98x** |

## 2. バイナリフットプリント（Binary Size）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) |
|---|---|---|---|
| **Fibonacci (fib 30)** | 28,128 B | 17,280 B | 16,048 B |
| **Tail-Recursive Loop (10M)** | 27,384 B | 16,896 B | 16,016 B |
| **Ackermann (ack 3 7)** | 28,368 B | 17,312 B | 16,048 B |
| **Higher-Order Closure (1M)** | 27,384 B | 16,904 B | 16,024 B |
| **List Alloc & Traverse (100k)** | 27,928 B | 17,208 B | 16,104 B |
| **Vector Indexing & Traverse (100k)** | 28,304 B | 17,480 B | 16,104 B |

> **注記**:
> - x86-64 Native は `as` / `ld -m elf_x86_64 -static` で直接アセンブル・リンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
> - IPC（Instructions Per Cycle）、Branch Miss %、Cache Miss % は Linux `perf stat` ハードウェアカウンタによる測定値です。
