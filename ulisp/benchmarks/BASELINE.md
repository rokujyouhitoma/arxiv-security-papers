# ULisp Canonical Performance Baseline Report (BASELINE.md)

- **Measurement Timestamp**: `2026-10-28T04:49:58.675987+00:00`
- **Execution Architecture**: `x86-64 Native (Freestanding / libc-free)` vs `ULisp C Backend (-O2)` vs `Pure C Baseline (-O2)`
- **System Platform**: `Linux x86_64 (6.18.54.1-microsoft-standard-WSL2)`
- **CPU Architecture**: `11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz` (4 Cores)
- **Total Physical Memory**: `12251728 kB`
- **C Toolchain**: `GCC 13` (`-O2 -Wall -Wextra`)
- **Statistical Parameters**: `30 反復試行 (Warmup: 5 回)` による平均値 (Mean) ± 標準偏差 (StdDev) および中央値 (Median)
- **Conforms to**: **DSN-33 (ULisp 統合仕様書)**, **Issue #620**, **Issue #622**, **Issue #623**

---

## 1. 概要と正典ベースラインの位置付け / Executive Summary

本ドキュメントは、ULisp の次世代最適化施策（Issue #618 関数間アンボックス特化、Issue #578 スタック配置最適化、Pass 132/133 SSA/ピープホール）に着手する前に確定された**「公式正典ベースライン数値（Canonical Baseline Metrics）」**である。

ULisp ネイティブコンパイラ（`ulisp/bin/ulisp-boot`）によって生成された Freestanding x86-64 ELF バイナリは、外部 C ライブラリ（glibc/musl）を一切リンクせず、Linux システムコール（`sys_write`, `sys_mmap`, `sys_clock_gettime`, `sys_exit`）を直接発行する完全自己完結型バイナリである。

---

## 2. 実行時間ベンチマーク結果（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | Chez Scheme (ms) | Gauche (ms) | 対 Pure C 比率 (x86/Pure) | 対 Chez 比率 (x86/Chez) |
|---|---|---|---|---|---|:---:|:---:|
| **Fibonacci (fib 30)** | 17.12 ± 4.63 (med: 17.55) | 12.09 ± 2.29 | 3.26 ± 0.68 | 73.96 ± 8.14 | 94.49 ± 10.06 | **5.26x** | **0.23x** |
| **Tail-Recursive Loop (10M)** | 3.54 ± 0.24 (med: 3.55) | 0.55 ± 0.08 | 0.55 ± 0.08 | 67.77 ± 3.03 | 254.83 ± 17.38 | **6.43x** | **0.05x** |
| **Ackermann (ack 3 7)** | 5.89 ± 0.78 (med: 5.64) | 4.85 ± 0.69 | 1.10 ± 0.19 | 53.08 ± 2.03 | 75.56 ± 10.11 | **5.36x** | **0.11x** |
| **Higher-Order Closure (1M)** | 5.22 ± 2.25 (med: 4.12) | 8.38 ± 2.51 | 0.86 ± 0.12 | 58.61 ± 4.13 | 73.13 ± 3.60 | **6.04x** | **0.09x** |
| **List Alloc & Traverse (100k)** | 2.74 ± 1.12 (med: 2.27) | 2.32 ± 0.24 | 1.19 ± 0.15 | 53.88 ± 2.89 | 53.81 ± 2.75 | **2.30x** | **0.05x** |
| **Vector Indexing & Traverse (100k)** | 1.95 ± 0.57 (med: 1.81) | 1.44 ± 0.24 | 0.87 ± 0.13 | 57.13 ± 5.22 | 58.00 ± 13.08 | **2.23x** | **0.03x** |

---

## 3. バイナリフットプリントと自己完結性（Binary Footprint & Self-Containment）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) | libc 依存 | リンカ構成 |
|---|---|---|---|:---:|---|
| **Fibonacci (fib 30)** | 20,112 B | 17,160 B | 16,048 B | **なし (Freestanding)** | `gcc -nostdlib -static` |
| **Tail-Recursive Loop (10M)** | 19,928 B | 17,088 B | 16,016 B | **なし (Freestanding)** | `gcc -nostdlib -static` |
| **Ackermann (ack 3 7)** | 20,048 B | 17,160 B | 16,048 B | **なし (Freestanding)** | `gcc -nostdlib -static` |
| **Higher-Order Closure (1M)** | 19,984 B | 21,832 B | 16,024 B | **なし (Freestanding)** | `gcc -nostdlib -static` |
| **List Alloc & Traverse (100k)** | 20,048 B | 21,872 B | 16,104 B | **なし (Freestanding)** | `gcc -nostdlib -static` |
| **Vector Indexing & Traverse (100k)** | 20,128 B | 21,920 B | 16,104 B | **なし (Freestanding)** | `gcc -nostdlib -static` |

---

## 4. ハードウェア性能カウンタ（Hardware Performance Counters via Linux perf）

| ワークロード | x86-64 IPC | x86-64 Branch Miss % | x86-64 Cache Miss % | ULisp C IPC | Pure C IPC |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 1.63 | 0.08% | 57.12% | 1.84 | 4.13 |
| **Tail-Recursive Loop (10M)** | 3.01 | 0.01% | 46.00% | 0.63 | 0.67 |
| **Ackermann (ack 3 7)** | 1.40 | 12.24% | 47.61% | 1.33 | 1.77 |
| **Higher-Order Closure (1M)** | 1.47 | 0.05% | 61.20% | 1.89 | 0.55 |
| **List Alloc & Traverse (100k)** | 1.84 | 0.10% | 71.42% | 1.70 | 0.98 |
| **Vector Indexing & Traverse (100k)** | 2.25 | 0.19% | 55.28% | 1.85 | 1.03 |

---

## 5. 実行時メモリ割当＆GC統計（Runtime Memory Allocation & GC Profile）

| ワークロード | 累積ヒープ割当量 | 生存コピー量 | GC 停止時間 (ms) | GC 回収回数 | 備考 |
|---|---|---|---|:---:|---|
| **Fibonacci (fib 30)** | 0 bytes | 0 bytes | 0 ms (0% of total) | 0) | バンプポインタ直結割当 |
| **Tail-Recursive Loop (10M)** | 0 bytes | 0 bytes | 0 ms (0% of total) | 0) | バンプポインタ直結割当 |
| **Ackermann (ack 3 7)** | 0 bytes | 0 bytes | 0 ms (0% of total) | 0) | バンプポインタ直結割当 |
| **Higher-Order Closure (1M)** | 24 bytes | 0 bytes | 0 ms (0% of total) | 0) | バンプポインタ直結割当 |
| **List Alloc & Traverse (100k)** | 2400000 bytes | 0 bytes | 0 ms (0% of total) | 0) | バンプポインタ直結割当 |
| **Vector Indexing & Traverse (100k)** | 800064 bytes | 0 bytes | 0 ms (0% of total) | 0) | バンプポインタ直結割当 |

---

## 7. Mermaid 可視化図表（Mermaid Visualizations）

### (1) 対 Pure C 相対実行速度比率（倍率: 1.0x が Pure C と同等）
```mermaid
graph LR
    subgraph "Execution Time Ratio (Lower is Faster, Pure C = 1.0x)"
        fib_30["Fibonacci (fib 30): 5.26x"]
        loop_10m["Tail-Recursive Loop (10M): 6.43x"]
        ack_3_7["Ackermann (ack 3 7): 5.36x"]
        closure_1m["Higher-Order Closure (1M): 6.04x"]
        list_100k["List Alloc & Traverse (100k): 2.30x"]
        vector_100k["Vector Indexing & Traverse (100k): 2.23x"]
    end
```

### (2) x86-64 ネイティブの IPC (Instructions Per Cycle) 特性
```mermaid
graph TD
    subgraph "CPU Pipeline Efficiency (IPC)"
        fib_30_ipc["Fibonacci (fib 30): 1.63 IPC"]
        loop_10m_ipc["Tail-Recursive Loop (10M): 3.01 IPC"]
        ack_3_7_ipc["Ackermann (ack 3 7): 1.40 IPC"]
        closure_1m_ipc["Higher-Order Closure (1M): 1.47 IPC"]
        list_100k_ipc["List Alloc & Traverse (100k): 1.84 IPC"]
        vector_100k_ipc["Vector Indexing & Traverse (100k): 2.25 IPC"]
    end
```

---

## 8. 次期最適化施策における改善目標（Optimization Roadmap）

| Issue ID | 最適化対象 | ボトルネック分析 | 目標性能向上 |
|:---:|---|---|:---:|
| **#618** | S-RTyper（Pass 090）アンボックス特化 | `fib 30`, `loop 10m` におけるタグ付け (`salq $3`, `orq $1`) および型タグ判定の完全撲滅 | **2.0x〜3.0x 高速化** (Pure C と完全同等の 1.0x 到達) |
| **#578** | スタック配置最適化 | `closure 1M` における非エスケープクロージャ・フレームのスタック化 | **1.5x 高速化** / ヒープ割当 0 B |
| **#547** | バックエンド末尾ループ回転・アンローリング | ループジャンプ先のアライメントおよびレジスタシャッフル最小化 | **1.3x 高速化** |

