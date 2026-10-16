# ULisp 差分テスト (Differential Testing: brench 哲学) 検証レポート

- **測定日時**: `2026-10-16 16:43:55`
- **実行環境**: `Linux x86_64` (CPU: `x86_64`)
- **テストハーネス**: Mytkowicz 4KB 環境変数パディング適用 (`BENCHMARK_ENV_PAD`)
- **評価対象ランナー**: `ULisp-AOT`, `ULisp-JIT`, `ILisp`, `ChezScheme`, `ChibiScheme`

---

## 1. 差分テスト総合一致検証マトリクス

| ワークロード | カテゴリ | 期待値 | ULisp-AOT 出力 | ULisp-JIT 出力 | ILisp 出力 | ChezScheme 出力 | ChibiScheme 出力 | 一致判定 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Iterative Fibonacci (fib 20)** (`fib_loop`) | State Transition | `6765` | `6765` | `6765` | `6765` | `6765` | `6765` | **🟢 100% 一致** |
| **Iterative Factorial (fact 12)** (`fact_loop`) | 64-bit Arithmetic | `479001600` | `479001600` | `479001600` | `479001600` | `479001600` | `479001600` | **🟢 100% 一致** |
| **Accumulation Loop (5,000 iters)** (`sum_loop`) | Hot Loop | `12497500` | `12497500` | `12497500` | `12497500` | `12497500` | `12497500` | **🟢 100% 一致** |
| **Polynomial 3x^2+5x+7 (1,000 iters)** (`poly_loop`) | Pipeline Arithmetic | `1001005000` | ⚠️ `999002` | `1001005000` | `1001005000` | `1001005000` | `1001005000` | **🔴 不一致** |
| **Triangular Sum (tri 500)** (`tri_loop`) | Linear Recursion | `125250` | `125250` | `125250` | `125250` | `125250` | `125250` | **🟢 100% 一致** |
| **Gabriel Benchmark: Takeuchi Function (tak 18 12 6)** (`tak`) | Deep Recursion / Gabriel | `7` | `7` | *N/A (Loop-only JIT)* | `7` | `7` | `7` | **🟢 100% 一致** |
| **CPS Takeuchi Function (cpstak 16 12 8)** (`cpstak`) | Continuation / Closures | `9` | `9` | *N/A (Loop-only JIT)* | `9` | `9` | `9` | **🟢 100% 一致** |
| **Ackermann Function (ack 3 4)** (`ackermann`) | Hyper-exponential Recursion | `125` | ⚠️ `(` | *N/A (Loop-only JIT)* | `125` | `125` | `125` | **🔴 不一致** |
| **Division Iteration & Remainder Loop (diviter 10000)** (`diviter`) | Division / Remainder | `16665000` | ⚠️ `0` | `16665000` | `16665000` | `16665000` | `16665000` | **🔴 不一致** |
| **List Accumulator & Traversal (iota 100)** (`list_sum`) | Heap / Pairs / List | `5050` | `5050` | *N/A (Loop-only JIT)* | `5050` | `5050` | `5050` | **🟢 100% 一致** |

---

## 2. 実行レイテンシ比較 (Latency Comparison)

| ワークロード | ULisp-AOT (ms) | ULisp-JIT (ms) | ILisp (ms) | ChezScheme (ms) | ChibiScheme (ms) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Iterative Fibonacci (fib 20) | 0.77 | 1.68 | 74.91 | 64.63 | 254.17 |
| Iterative Factorial (fact 12) | 0.86 | 0.79 | 77.33 | 59.87 | 248.30 |
| Accumulation Loop (5,000 iters) | 0.81 | 11.18 | 113.59 | 49.83 | 235.22 |
| Polynomial 3x^2+5x+7 (1,000 iters) | 0.72 | 3.66 | 90.87 | 51.19 | 246.87 |
| Triangular Sum (tri 500) | 0.84 | 1.75 | 81.03 | 56.63 | 243.32 |
| Gabriel Benchmark: Takeuchi Function (tak 18 12 6) | 0.85 | 0.00 | 621.02 | 56.75 | 244.96 |
| CPS Takeuchi Function (cpstak 16 12 8) | 0.85 | 0.00 | 101.98 | 49.20 | 243.08 |
| Ackermann Function (ack 3 4) | 1.77 | 0.00 | 184.79 | 53.59 | 244.02 |
| Division Iteration & Remainder Loop (diviter 10000) | 0.76 | 21.10 | 186.18 | 54.03 | 249.24 |
| List Accumulator & Traversal (iota 100) | 0.75 | 0.00 | 79.11 | 57.28 | 258.73 |

---

## 3. 差分検証結論

> [!CAUTION]
> **差分テスト FAIL**: 出力値に不整合が検出されました。上記の不一致セルを確認してください。