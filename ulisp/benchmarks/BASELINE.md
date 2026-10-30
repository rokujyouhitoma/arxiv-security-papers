# ULisp Canonical Performance Baseline Report (BASELINE.md)

- **Measurement Timestamp**: `2026-10-30T00:38:57.583650+00:00`
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

## 2. 実行時間ベンチマーク結果（Execution Latency — Phase 4 完了時点）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | Chez Scheme (ms) | Gauche (ms) | 対 Pure C 比率 (x86/Pure) | 対 Chez 比率 (x86/Chez) |
|---|---|---|---|---|---|:---:|:---:|
| **Fibonacci (fib 30)** | 4.17 ± 0.23 (med: 4.10) | 7.91 ± 0.37 | 1.81 ± 0.20 | 50.82 ± 1.92 | 80.61 ± 3.51 | **2.30x** | **0.08x** |
| **Tail-Recursive Loop (10M)** | 1.75 ± 0.16 (med: 1.68) | 0.50 ± 0.07 | 0.48 ± 0.09 | 61.36 ± 2.31 | 200.96 ± 7.70 | **3.67x** | **0.03x** |
| **Ackermann (ack 3 7)** | 2.92 ± 0.29 (med: 2.81) | 3.70 ± 0.26 | 0.98 ± 0.07 | 49.17 ± 4.82 | 59.64 ± 2.08 | **2.98x** | **0.06x** |
| **Higher-Order Closure (1M)** | 2.99 ± 0.21 (med: 2.99) | 4.89 ± 0.35 | 0.47 ± 0.05 | 52.64 ± 6.09 | 59.41 ± 2.10 | **6.39x** | **0.06x** |
| **List Alloc & Traverse (100k)** | 2.17 ± 0.61 (med: 1.97) | 1.60 ± 0.20 | 1.14 ± 0.15 | 48.02 ± 1.40 | 45.37 ± 1.52 | **1.90x** | **0.05x** |
| **Vector Indexing & Traverse (100k)** | 0.99 ± 0.11 (med: 0.96) | 1.47 ± 0.22 | 0.80 ± 0.10 | 52.45 ± 3.10 | 47.90 ± 5.45 | **1.25x** | **0.02x** |

### 各最適化フェーズ（Phase 1〜4）における性能推移

| ワークロード | Initial (ms) | Phase 1: Direct Call (ms) | Phase 2: SysV Reg ABI (ms) | Phase 3: Interproc Unbox (ms) | Phase 4: Loop Opt & JMP (ms) | 対 Initial 改善率 |
|---|---|---|---|---|---|:---:|
| **Fibonacci (fib 30)** | 17.12 ± 4.63 | 7.39 ± 0.35 | 5.59 ± 0.26 | 4.12 ± 0.15 | **4.17 ± 0.23 (med: 4.10)** | **-75.6% (< 4.3ms DoD 達成)** |
| **Tail-Recursive Loop (10M)** | 3.54 ± 0.24 | 3.41 ± 0.18 | 3.32 ± 0.14 | 3.33 ± 0.20 | **1.75 ± 0.16 (med: 1.68)** | **-50.6% (< 2.0ms DoD 達成)** |
| **Ackermann (ack 3 7)** | 5.89 ± 0.78 | 4.03 ± 0.31 | 4.17 ± 0.64 | 2.95 ± 0.25 | **2.92 ± 0.29 (med: 2.81)** | **-50.4% (< 5.1ms DoD 達成)** |
| **Higher-Order Closure (1M)** | 5.22 ± 2.25 | 4.88 ± 0.42 | 4.33 ± 0.67 | 3.01 ± 0.50 | **2.99 ± 0.21 (med: 2.99)** | **-42.7%** |
| **List Alloc & Traverse (100k)** | 2.74 ± 1.12 | 2.12 ± 0.25 | 1.75 ± 0.21 | 1.45 ± 0.21 | **2.17 ± 0.61 (med: 1.97)** | **-20.8%** |
| **Vector Indexing & Traverse (100k)** | 1.95 ± 0.57 | 1.52 ± 0.19 | 1.17 ± 0.06 | 0.99 ± 0.03 | **0.99 ± 0.11 (med: 0.96)** | **-49.2%** |

---

## 3. バイナリフットプリントと自己完結性（Binary Footprint & Self-Containment）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) | libc 依存 | リンカ構成 |
|---|---|---|---|:---:|---|
| **Fibonacci (fib 30)** | 20,160 B | 17,192 B | 16,048 B | **なし (Freestanding)** | `gcc -nostdlib -static` |
| **Tail-Recursive Loop (10M)** | 19,968 B | 17,120 B | 16,016 B | **なし (Freestanding)** | `gcc -nostdlib -static` |
| **Ackermann (ack 3 7)** | 20,096 B | 17,232 B | 16,048 B | **なし (Freestanding)** | `gcc -nostdlib -static` |
| **Higher-Order Closure (1M)** | 20,032 B | 21,920 B | 16,024 B | **なし (Freestanding)** | `gcc -nostdlib -static` |
| **List Alloc & Traverse (100k)** | 20,096 B | 21,880 B | 16,104 B | **なし (Freestanding)** | `gcc -nostdlib -static` |
| **Vector Indexing & Traverse (100k)** | 20,176 B | 22,016 B | 16,104 B | **なし (Freestanding)** | `gcc -nostdlib -static` |

---

## 4. ハードウェア性能カウンタ（Hardware Performance Counters via Linux perf）

| ワークロード | x86-64 IPC | x86-64 Branch Miss % | x86-64 Cache Miss % | ULisp C IPC | Pure C IPC |
|---|---|---|---|---|---|
| **Fibonacci (fib 30)** | 2.68 | 0.03% | 58.55% | 1.90 | 4.06 |
| **Tail-Recursive Loop (10M)** | 3.31 | 0.12% | 30.34% | 0.67 | 0.56 |
| **Ackermann (ack 3 7)** | 1.05 | 14.21% | 58.03% | 1.13 | 1.82 |
| **Higher-Order Closure (1M)** | 3.12 | 0.03% | 64.91% | 2.16 | 0.75 |
| **List Alloc & Traverse (100k)** | 1.46 | 0.11% | 75.14% | 1.22 | 0.94 |
| **Vector Indexing & Traverse (100k)** | 2.95 | 0.12% | 78.57% | 1.78 | 0.98 |

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
        fib_30["Fibonacci (fib 30): 2.30x"]
        loop_10m["Tail-Recursive Loop (10M): 3.67x"]
        ack_3_7["Ackermann (ack 3 7): 2.98x"]
        closure_1m["Higher-Order Closure (1M): 6.39x"]
        list_100k["List Alloc & Traverse (100k): 1.90x"]
        vector_100k["Vector Indexing & Traverse (100k): 1.25x"]
    end
```

### (2) x86-64 ネイティブの IPC (Instructions Per Cycle) 特性
```mermaid
graph TD
    subgraph "CPU Pipeline Efficiency (IPC)"
        fib_30_ipc["Fibonacci (fib 30): 2.68 IPC"]
        loop_10m_ipc["Tail-Recursive Loop (10M): 3.31 IPC"]
        ack_3_7_ipc["Ackermann (ack 3 7): 1.05 IPC"]
        closure_1m_ipc["Higher-Order Closure (1M): 3.12 IPC"]
        list_100k_ipc["List Alloc & Traverse (100k): 1.46 IPC"]
        vector_100k_ipc["Vector Indexing & Traverse (100k): 2.95 IPC"]
    end
```

---

## 8. 次期最適化施策における改善目標（Optimization Roadmap）

| Issue ID | 最適化対象 | ボトルネック分析 | 目標性能向上 |
|:---:|---|---|:---:|
| **#618** | S-RTyper（Pass 090）アンボックス特化 | `fib 30`, `loop 10m` におけるタグ付け (`salq $3`, `orq $1`) および型タグ判定の完全撲滅 | **2.0x〜3.0x 高速化** (Pure C と完全同等の 1.0x 到達) |
| **#578** | スタック配置最適化 | `closure 1M` における非エスケープクロージャ・フレームのスタック化 | **1.5x 高速化** / ヒープ割当 0 B |
| **#547** | バックエンド末尾ループ回転・アンローリング | ループジャンプ先のアライメントおよびレジスタシャッフル最小化 | **1.3x 高速化** |

