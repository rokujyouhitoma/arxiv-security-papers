---
ID: 958
種別: Feature
優先度: Medium
ステータス: Closed
完了日: 2026-11-26
---

# [FEAT/ENH] 関数入口の未使用 `r10` / `argc` スピル削除と小さなアクセサのインライン化（Scheme モード） (ID: 958)

## 1. 概要 / Summary

コードベース精査の結果、Scheme コンパイル時の関数プロローグおよびアクセサ呼び出しに以下の 3 つの過剰コストが特定された：

1. **未使用 `r10`（`%self`）の無条件スピル**:
   - `ulisp/backend/140_backend_x86_64.scm`（`select-instructions-function` / `emit-x86-function`）、`ulisp/backend/150_backend_aarch64.scm`（`emit-arm-function`）、および `ulisp/backend/160_backend_c.scm`（`emit-c-function`）が Scheme モードで全関数入口で無条件に `[rsp - 8]` 等へ `r10` を出力し、`ulisp/lir/130_lir.scm` も全関数で `%self` をスロット `-8` に割り当てていたため、クロージャ環境を参照しない大多数の直接呼び出し関数でも毎回 `[rsp - 8]` への書き出しが発生していた（#936 では C-TU モードのみ分離済み）。
2. **未使用 `rax`（`argc` / `%num-args`）の無条件スピル**:
   - `ulisp/lir/130_lir.scm` が全関数で `(%store %rsp -16 %rax)` を無条件発行していたが、`[rsp - 16]` を実際に読み出すのは可変長引数／`%num-args`（`ulisp/lir/129_lir_primitives.scm`）を使う関数のみである。
3. **レコード・AST アクセサの小関数呼び出しコスト**:
   - `scope-node-children`（`ulisp/compiler/scope.scm`：`scope-node-children-cell` 呼び出し→`car`）のような 1〜2 プリミティブ程度のアクセサが、インライン展開されず 1 呼出あたり約 20 命令を消費していた。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #936](936-hoist-c-tu-function-stack-frame-allocation-and-omit-managed-gc-call-setup.md)（C-TU モードでのプロローグ最適化）
  - [130_lir.scm](../../../ulisp/lir/130_lir.scm)
  - [131_lir_safepoint.scm](../../../ulisp/lir/131_lir_safepoint.scm)
  - [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm)
  - [150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm)
  - [160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm)
  - [050_cp0.scm](../../../ulisp/frontend/050_cp0.scm)

---

## 3. 脅威モデリングと安全性要件 / Threat Model & Safety Requirements

1. **GC スタックマップとの整合性（未初期化スロット走査防止 / CWE-457・CWE-824）**:
   - `ulisp/lir/131_lir_safepoint.scm` の `compute-stackmap-bitmap` で無条件 `(= slot-offset -8) -> #t` を撤廃し、`env` 内に `(%self . (self . -8))`（または `-8` スロットのポインタ束縛）が存在する場合のみ GC ルートビットを立てるように修正。
   - `%main` や `%self` 非参照関数で `[rsp - 8]` への保存を省略しても、GC が未初期化スタックゴミをポインタとして誤走査しないことを保証。
2. **クロージャ環境・可変長引数・`apply` の保存保証**:
   - `lir-body-uses-symbol?`（`quote` 内部を除外）により本体が `%self` または `%num-args` を参照する場合のみ、`L_loop_head_*` の直前に `(%store %rsp -8 %r10)` / `(%store %rsp -16 %rax)` を出力し、自己末尾再帰時はスキップする既存動作を維持。
3. **インライン展開時の評価順序・副作用保持・ハイジーン（CWE-843 / セマンティクス破壊防止）**:
   - `050_cp0.scm` の `cp0-inline-accessors` は、`set!` で再代入されず重複定義・自己再帰のない 1〜2 引数の葉アクセサ／述語（`car`, `cdr`, `vector-ref`, `eq?`, `pair?`, `fixnum?` 等、コスト ≦ 2）のみを展開し、非アトム引数は新鮮な `let` 束縛で単一評価・左から右の順序を保持し、レキシカル環境で基本演算子がシャドーイングされている場合は展開を抑止する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [130_lir.scm](../../../ulisp/lir/130_lir.scm) (`lir-body-uses-symbol?` 追加、条件付き `self-env` 構築および `(%store %rsp -8 %r10)` / `(%store %rsp -16 %rax)` 発行)
- [x] [131_lir_safepoint.scm](../../../ulisp/lir/131_lir_safepoint.scm) (`compute-stackmap-bitmap` の `-8` ハードコード撤廃、`self` 種別に基づく正確な GC ルート判定)
- [x] [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm) (`select-instructions-function` / `emit-x86-function` の無条件 `mov [rsp - 8], r10` 削除)
- [x] [150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm) (`emit-arm-function` で先頭の任意 `-8` / `-16` スピルに対応し無条件 `str x10, [sp, #-8]` を削除)
- [x] [160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm) (`emit-c-function` の無条件 `*(uint64_t *)(reg_rsp - 8) = reg_r10;` を削除)
- [x] [050_cp0.scm](../../../ulisp/frontend/050_cp0.scm) (`cp0-inline-accessors` 実装：2 パス合成アクセサ抽出、一時 `let` 束縛、シャドーイング保護、`eq?` 構造共有維持)
- [x] [test_050_cp0.scm](../../../ulisp/tests/passes/test_050_cp0.scm), [test_130_lir.scm](../../../ulisp/tests/passes/test_130_lir.scm), [test_131_lir_safepoint.scm](../../../ulisp/tests/passes/test_131_lir_safepoint.scm), [test_141_backend_x86_gc.scm](../../../ulisp/tests/passes/test_141_backend_x86_gc.scm), [test_stackmap.scm](../../../ulisp/tests/passes/test_stackmap.scm)
- [x] [compiler.scm](../../../ulisp/compiler.scm) (`make -C ulisp compiler` により再生成)

---

## 5. 実測結果と検証 / Measured Results & Verification

Target Branch: `perf/958-prologue-spills-and-accessor-inlining`

### 前後比較 (2026-11-26, Linux x86-64)

| 指標 | Before (`ulisp-boot` ベースライン) | After (`stage3-modular`) | 差分 / 改善率 |
| :--- | :---: | :---: | :---: |
| `.text` セクションサイズ | `9,420,441` bytes | `9,388,705` bytes | **-31,736 bytes (-31.0 KB)** |
| `mov QWORD PTR [rsp-0x8],r10` 命令数 | `4,516` | `437` | **-4,079 命令 (-90.3%)** |
| `mov QWORD PTR [rsp-0x10],rax` 命令数 | `3,761` | `892` | **-2,869 命令 (-76.3%)** |
| 自己コンパイル時間 (`frontend_passes_in.scm`, 5回中央値) | `5.2584 s` `[4.8642, 4.9257, 5.2584, 6.4353, 5.4139]` | `4.9981 s` `[4.9192, 4.8697, 5.4590, 5.6837, 4.9981]` | **-0.2603 s (-4.95%)** |

### テスト・ブートストラップ検証

- `make -C ulisp lint_sexpr`: 全ファイル S 式括弧バランス PASS。
- `make -C ulisp test_passes test_pass_manager test_nanopass test_backend test_c test_lir_suite test_lir_verifier test_lir_dialect_separation`: 全 PASS（Pass 050/130/131/140/141, 39 パス単体スイート, Pass Manager 138/138, LIR Verifier 51/51, Portable C 143/143 `-Werror` ゼロ警告, LIR VM Dialect Separation 等）。
- `make -C ulisp test_call_cc test_case_lambda test_record test_values test_gc_stress test_scope test_aarch64_env`: 全 PASS（GC stress ネイティブ・ディレクティブ・C ストレス各 16/16 含む）。
- `cd ulisp && ./bootstrap.sh --full`: クリーン `ulisp_stdlib.o` 再ビルドを含め Stage 2 == Stage 3 全 5 モジュールで SHA-256 完全一致・スモークテスト (`output: 42`) PASS。
- `make check_format && make static_analysis`: 全 PASS（`mypy --strict src` 618 ファイル 0 件エラー）。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] 未使用関数の入口から `mov [rsp - 8], r10` および `mov [rsp - 16], rax` が除去され、自己コンパイル時間・命令数・`.text` サイズの改善が実測確認されていること。
- [x] 可変長引数・クロージャ・`apply`・GC スタックマップ関連テスト（`test_case_lambda`, `test_call_cc`, `test_record`, `test_values`, `test_gc_stress`, `test_141_backend_x86_gc`）が全 PASS すること。
- [x] `make -C ulisp test_passes` / `make check_format` / `make static_analysis` が全 PASS すること。
- [x] `make -C ulisp bootstrap`（`./bootstrap.sh --full`）で Stage 2 → Stage 3 の自己コンパイル不動点（SHA-256 一致）を維持していること。
- [x] 施策前後の計測値（自己コンパイル時間中央値 5 回・`.text` サイズ・`objdump` `[rsp]` 命令数）を本 Issue に記録していること。
- [x] 品質ゲート全 PASS（相対リンクのみ・絶対パス 0 件）。
