---
ID: 938
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] `make -C ulisp bootstrap` における Pass 128 二次計算量ループおよび `memq` ヒープ肥大化・メモリ超過スラッシングの修正 (ID: 938)

## 1. 概要 / Summary & 計測ベースライン

`make -C ulisp bootstrap`（[bootstrap.sh](../../../ulisp/bootstrap.sh)）の実行時に特定のケースできわめて遅くなる問題を調査し、`bin/ulisp-boot --time-passes` および `/usr/bin/time` で全 6 コンパイラモジュールの実機プロファイリングを実施した。結果、直近の [#927](927-implement-c-header-sbi-pch-and-iterative-mem2reg-optimization.md) / [#935](935-optimize-variable-bit-shift-cl-codegen-and-redundant-sign-zero-extension-folding.md) 等で顕在化した計算量バグとクォートリストの毎回ヒープ確保、および並列時のメモリ超過スラッシングが複合的に発生していることを特定し、全て解消した。

### ベースライン実測値（修正前・単一プロセス計測）
実行環境: Linux (4 vCPU i7-1165G7 @ 2.80GHz, 物理 RAM 11 GiB / 空き約 7.4 GiB, Swap 8.0 GiB)

| モジュール | 入力行数 | 総時間 (Wall) | `pass-128` 時間 (占有率) | `pass-133` 時間 (占有率) | `pass-133` Heap (占有率) | **MaxRSS** |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| `frontend_passes` | 7,701 | **40.61 s** | **27.02 s (67.2%)** | 5.22 s (12.9%) | **3,247 MB (51.6%)** | **6.31 GB** |
| `lir_passes` | 8,137 | **16.40 s** | **10.77 s (67.1%)** | 1.62 s (10.1%) | **1,993 MB (47.9%)** | **4.17 GB** |
| `backend_passes` | 14,695 | **13.87 s** | **8.40 s (62.7%)** | 1.29 s (9.6%) | **2,023 MB (48.8%)** | **4.18 GB** |
| `compiler_base` | 18,389 | **13.36 s** | 2.78 s (21.6%) | **4.55 s (35.4%)** | **2,114 MB (57.2%)** | **3.73 GB** |
| `stdlib` | 46 (include) | **4.00 s** | 0.72 s (18.9%) | 1.06 s (27.7%) | **1,738 MB (59.8%)** | **2.91 GB** |
| `compiler_driver` | 997 | **0.40 s** | 0.12 s (31.9%) | 0.09 s (24.2%) | **128 MB (58.1%)** | **0.23 GB** |

### 切り分けベンチマーク（`build/frontend_passes_in.scm`・修正前）

| 実行条件 | Wall 時間 | User / Sys | MaxRSS | ベースライン比較 |
| :--- | ---: | ---: | ---: | :--- |
| 現行（全パス有効） | **40.61 s** | 35.61 s / 4.98 s | **6,305 MB** | 1.00× |
| `pass-128` 無効化 | **10.81 s** | 7.73 s / 3.06 s | 6,284 MB | **3.76× 高速化** |
| `pass-128` + `pass-133` 無効化 | **8.77 s** | 6.30 s / 2.45 s | **3,054 MB** | **4.63× 高速化 / RSS 半減** |

---

## 2. トレーサビリティ / Traceability
- 関連・起因 Issue:
  - [#927](927-implement-c-header-sbi-pch-and-iterative-mem2reg-optimization.md) (`128_lir_branch_fusion.scm` への C99 分岐融合追加)
  - [#935](935-optimize-variable-bit-shift-cl-codegen-and-redundant-sign-zero-extension-folding.md) (`133_lir_peephole.scm` への拡張畳み込み追加)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### RCA 1: `pass-128-lir-branch-fusion` の壊滅的 $O(N^2)$ ループ ([128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm))
1. **毎命令で残リスト長 `(length xs)` を 2 回呼び出し**:
   - `frontend_passes` の LIR 総命令数 396,340 のうち上位関数だけで `.L_lambda_467` (76,294 命令), `main` (59,965 命令), `.L_lambda_449` (35,678 命令) が存在し、1 回走査のみで約 107 億回の `cdr` 走査が発生していた。
   - さらに Scheme 関数でも B3/B4（直後ラベルへの不要ジャンプ削除）が発火すると 2 周目が再実行され $O(N^2)$ が 2 倍化していた。
2. **`%bf-c99-count-label-refs` / `lbl-map` の $O(N \cdot L)$ 線形探索**:
   - 全命令中の全シンボルに対して `(memq x def-lbls)`（ラベル全件走査 $O(L)$）と `(assq lbl ...)` を実行しており、C99 専用の `(%cmp %rax 0)` が一切無い Scheme 関数に対しても毎回構築・走査していた。

### RCA 2: クォートリストリテラル `'(...)` の毎回ヒープ確保 × `(!gc none)` ([Makefile](../../../ulisp/Makefile), [133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm))
ULisp は `(memq op '(...))` 等のクォートリストを呼び出しごとに要素数 × 24 バイトずつバンプヒープに毎回動的確保する一方、ブートストラップ全モジュールが `(!gc none)` でコンパイルされるためプロセス終了まで回収されない。
1. **`lir-ext-safe-intra-block-op?`**: 72 要素の `memq` リストを 1 回呼び出すごとに `1,728 B` を確保。`frontend_passes` 単体で `pass-133` の 3.25 GB の大半を消費していた。
2. **コンパイラ全体の同種箇所**: `020_macro_expander.scm` (`core-form-or-primitive?`: 156 要素 = 3,744 B/回)、`primitives.scm`、`helpers.scm`、`140_backend_x86_64.scm` 等。また `desugar-case-test` が `(or (eqv? ...) ...)` を展開する際、各分岐ごとに `or_tmp_N` の `let` ラッパを生成していた。

### RCA 3: `make -j$(nproc)` 並列実行時の 18.39 GB RAM 超過によるスワップ・スラッシング ([bootstrap.sh](../../../ulisp/bootstrap.sh))
`bootstrap.sh` は `JOBS=$(nproc)` (= 4) で Stage 2・Stage 3 の 5 モジュールを同時に走らせるため、4 プロセス同時稼働時の理論ピーク RSS が `18.39 GB` に達し、物理 RAM 11 GiB（空き約 7.4 GiB）を大幅に超過して約 11 GB 分のスワップ・スラッシングが発生していた。

### 副次的ボトルネック
- `*nanopass-window-step-limit*` ([nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm)) が `1024` と小さく、巨大関数で途中打ち切り → 先頭再走査が繰り返されていた。
- `BOOTSTRAP_MODULAR=1` でも `bootstrap.sh` が不要な `make compiler build/ulisp_stdlib.o` を毎回直列チェックしていた。

---

## 4. 実装内容 / Implemented Fixes
**Target Branch**: `fix/938-eliminate-bootstrap-quadratic-branch-fusion-and-memq-heap-bloat`

- **WP1 ([128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm))**: 純粋 R7RS 1024 バケットハッシュ表 (`symbol->hash-idx` 活用)、`%bf-c99-has-cmp-rax-zero?` 事前スキャン＋非該当関数向け高速パス `%bf-c99-drop-adjacent-jumps`、Pattern B1/B2 の $O(1)$ `pair?` ルックアヘッド化、`changed?` 追跡。
- **WP2 ([027_desugar_conditionals.scm](../../../ulisp/frontend/027_desugar_conditionals.scm), [050_cp0.scm](../../../ulisp/frontend/050_cp0.scm), ホット述語群)**: `desugar-case-test` の直接ネスト `if` 化、`rule-cp0-memq-quoted-bool` による真偽値位置（`if`/`not`）の非アロケーション `eq?` チェーン展開・定数畳み込み、主要ホット述語群の `case` 式化。
- **WP3 ([133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm))**: `lir-fold-redundant-extensions` への `%trunc/%zext/%sext` ゼロ確保プレチェック、`lir-eliminate-dead-stack-stores` への `neg-store` プレチェック、`%lir-map-keep-eq` / `%lir-transform-ir-bodies` による `eq?` 不変時ゼロコピー化と `L_lir_canonical?` 検証整合、`%lir-program-bodies-unchanged?` による O(F) 収束判定。
- **WP4 ([bootstrap.sh](../../../ulisp/bootstrap.sh), [nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm), 単体テスト)**: `MemAvailable` に基づく安全な並列度決定（2.5 GB/ジョブ、実機 `make -j3`）、不要な直列ターゲットスキップ、`*nanopass-window-step-limit*` を `1024 → 16384` に拡大、[test_050_cp0.scm](../../../ulisp/tests/passes/test_050_cp0.scm) ＆ [test_128_lir_branch_fusion.scm](../../../ulisp/tests/passes/test_128_lir_branch_fusion.scm) テスト追加。

---

## 5. 検証結果 / Before & After 実測ベンチマーク

### 修正前後 Single-Module & Clean 3-Stage Bootstrap 実測比較（最終コード）

| モジュール / 計測対象 | Wall (Before → **After**) | `pass-128` (Before → **After**) | `pass-133` Heap (Before → **After**) | MaxRSS (Before → **After**) |
| :--- | ---: | ---: | ---: | ---: |
| `frontend_passes` | 40.61 s → **7.53 s (5.39×)** | 27,023.90 ms → **30.03 ms (900×)** | 3,247 MB → **366 MB (8.9×)** | 6.31 GB → **2.09 GB (-66.9%)** |
| `lir_passes` | 16.40 s → **3.06 s (5.36×)** | 10,768.07 ms → **30.66 ms (351×)** | 1,993 MB → **205 MB (9.7×)** | 4.17 GB → **1.26 GB (-69.8%)** |
| `backend_passes` | 13.87 s → **3.77 s (3.68×)** | 8,400.51 ms → **35.95 ms (234×)** | 2,023 MB → **213 MB (9.5×)** | 4.18 GB → **1.27 GB (-69.6%)** |
| `compiler_base` | 13.36 s → **3.32 s (4.02×)** | 2,779.19 ms → **25.36 ms (110×)** | 2,114 MB → **219 MB (9.7×)** | 3.73 GB → **1.05 GB (-71.8%)** |
| `stdlib` | 4.00 s → **2.18 s (1.83×)** | 724.84 ms → **20.88 ms (35×)** | 1,738 MB → **178 MB (9.8×)** | 2.91 GB → **0.80 GB (-72.5%)** |
| `compiler_driver` | 0.40 s → **0.22 s (1.82×)** | 116.31 ms → **0.63 ms (185×)** | 128 MB → **13.6 MB (9.4×)** | 0.23 GB → **0.07 GB (-70.8%)** |
| **Clean 3-Stage Bootstrap (`bootstrap.sh`, `make -j3`)** | **Wall 31.45 s** (User 66.06 s / Sys 10.43 s) | 全5モジュール Stage2==Stage3 一致 | スワップ・スラッシング 0 | **MaxRSS 2.09 GB** |

### 回帰検証スイート実行結果
- `make -C ulisp test_passes`: PASS (855/855 Nanopass Unit Tests + 165/165 Per-Pass Tests)
- `make -C ulisp test_c99_int_lowering`: PASS (61/61)
- `make -C ulisp test_ir_serialization`: PASS (70/70, PCH Speedup 5.93×)
- `make -C ulisp bootstrap`: PASS (Stage 2 == Stage 3 全5モジュール完全ビット一致、シード `bin/ulisp-boot` 更新)
- `make -C ulisp test`: PASS
- `make -C ulisp test_c99_pch_opt`: PASS
- `LUA_FULL_BIG=1 make -C ulisp test_lua_e2e`: PASS
- `make py_compile && make static_analysis`: PASS (617 files)

---

## 6. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lir/128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm)
- [x] [ulisp/lir/133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm)
- [x] [ulisp/frontend/027_desugar_conditionals.scm](../../../ulisp/frontend/027_desugar_conditionals.scm)
- [x] [ulisp/frontend/050_cp0.scm](../../../ulisp/frontend/050_cp0.scm)
- [x] [ulisp/frontend/020_macro_expander.scm](../../../ulisp/frontend/020_macro_expander.scm)
- [x] [ulisp/compiler/primitives.scm](../../../ulisp/compiler/primitives.scm)
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm)
- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm)
- [x] [ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm)
- [x] [ulisp/lir/132_lir_braun_ssa.scm](../../../ulisp/lir/132_lir_braun_ssa.scm)
- [x] [ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh)
- [x] [ulisp/tests/passes/test_050_cp0.scm](../../../ulisp/tests/passes/test_050_cp0.scm)
- [x] [ulisp/tests/passes/test_128_lir_branch_fusion.scm](../../../ulisp/tests/passes/test_128_lir_branch_fusion.scm)

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `make -C ulisp compiler`（`scripts/lint_sexpr.py` 含む）および `make -C ulisp test_passes` が全件 PASS すること。
- [x] `make -C ulisp bootstrap` が完走し、全 5 モジュールで Stage 2 == Stage 3 のビット一致不動点が確認されること。
- [x] **性能・メモリ達成基準**:
  - `frontend_passes` の `pass-128` 時間が 27.02 s → 1.0 s 未満（実績 **30.03 ms**）へ短縮されること。
  - `frontend_passes` の MaxRSS が 6.31 GB → 2.5 GB 以下（実績 **2.09 GB**）へ削減され、クリーンからの全 3 ステージ `make -C ulisp bootstrap` がスワップ・スラッシングなしで高速完走（実績 **31.45 s**）すること。
- [x] `make -C ulisp test`, `make -C ulisp test_c99_pch_opt`, `make -C ulisp test_lua_e2e`, およびルート `make py_compile && make static_analysis` が全て PASS すること。
