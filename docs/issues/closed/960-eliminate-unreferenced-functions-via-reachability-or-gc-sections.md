---
ID: 960
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-27
---

# [FEAT/ENH] 未参照関数の削除（関数・クロージャ毎セクション分割＋`--gc-sections` ＆ 到達可能性解析） (ID: 960)

## 1. 概要 / Summary

ULisp コンパイラにおける未参照関数・未使用静的クロージャ・`(!gc none)` 不要スタックマップエントリの残存を解消するため、以下を実装した：

1. **関数・クロージャ単位の ELF セクション分割（[140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm), [150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm)）**:
   - 各関数（`ulisp_fn_*` / `L_lambda_*`）を独立した `.section .text.<label>,"ax",@progbits` へ配置し、関数群末尾で `.text` を明示復帰させるようにした。
   - 各静的クロージャ（`.L_static_closure_*` + `ulisp_gvar_*`）を独立した `.section .data.<sc_lbl>,"aw",@progbits` へ配置し、後続ランタイムデータ前に `.data` を明示復帰させるようにした。
   - リンカ合成シンボルで参照される `ulisp_globals_sec` / `ulisp_symtab_sec` へ `SHF_GNU_RETAIN`（`"aR", @progbits`）を付与して `--gc-sections` からの誤削除を防止した。
   - `(!gc none)` モードモジュールの `__ulisp_stackmap_table` を `.section .rodata.__ulisp_stackmap_table,"a",@progbits` へ分離して要素数 `.quad 0`（AArch64 `.xword 0`）とし、未使用セーフポイント参照による関数ピン留めを解消した。
2. **フロントエンド到達可能性プルーニング（[110_closure_convert.scm](../../../ulisp/frontend/110_closure_convert.scm)）**:
   - 非モジュール単一プログラムモード（`(not (module-mode?))`, `(not (allow-extern-symbols?))`, 非空 `main-expr`）において、`closure-convert` 前にトップレベル関数コールグラフの推移的到達可能性解析を実行し、未到達な `%function` を削除する `prune-unreachable-top-level-defs`（暗黙 `num+`/`num-`/`num*`/`num/`/`num=`/`num<`/`num<=`/`num>`/`num>=`/`num-quotient`/`num-modulo`/`num-bitwise-and`/`num-bitwise-ior` の保持含む）を実装した。
3. **ビルド・自前静的リンカ対応（[elf64_builder.scm](../../../ulisp/backend/elf64_builder.scm), [Makefile](../../../ulisp/Makefile), [bootstrap.sh](../../../ulisp/bootstrap.sh)）**:
   - `elf64-parse-relocatable-object` の再配置収集 `loop-rela` を $O(S + R)$ 化し、`LDFLAGS` と `bootstrap.sh` のリンクコマンドへ `--gc-sections` を適用した。

結果として `stage3-modular` において、`ulisp_fn_*` を **3,832 → 2,367 個（-1,465 個 / -38.23%）**、`.text` セクションを **6,753,237 B → 5,230,601 B（-1,522,636 B / -22.55%）**、`.rodata` を **-995,840 B（-73.21%）**、`size` `text` 合計を **8,186,245 B → 5,667,993 B（-2,518,252 B / -30.76% / -2.40 MB）** へと削減し、起動時間 **-9.17%**・自己コンパイル時間中央値 **-6.47%** の高速化を達成した。

---

## 2. トレーサビリティ / Traceability

- 関連資料・Issue:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（計測・プロファイリング基盤）
  - [Issue #951](951-disable-safepoint-injection-in-single-threaded-compiler-modules.md)（コンパイラモジュールにおける safepoint 無効化）
  - [Issue #952](952-strip-release-binaries-and-split-debug-symbols.md)（リリースバイナリ strip とシンボル整理）
  - [Issue #957](957-share-arithmetic-and-compare-slow-path-stubs.md)（算術・比較 slow path の共有スタブ化）
  - [Issue #958](958-eliminate-unused-prologue-spills-and-inline-small-accessors.md)（未使用プロローグスピル削除・小アクセサインライン化）
  - [Issue #959](959-emit-quoted-constants-as-static-rodata-data.md)（quote 定数の静的 `.rodata` 化）

---

## 3. 脅威モデリングと安全性要件 / Threat Model & Safety Requirements

1. **孤立メタデータセクションの意図しない欠落防止（CWE-476 NULL 参照 / `SHF_GNU_RETAIN`）**:
   - `ulisp_globals_sec` および `ulisp_symtab_sec` へ `"aR", @progbits`（`SHF_GNU_RETAIN`）を付与し、`ld --gc-sections` による削除を防止した。
2. **関数・クロージャ毎セクション切替時のアセンブラセクション状態不変条件**:
   - 関数出力後に `    .text`、静的クロージャ出力後に `    .data` を明示復帰し、`emit-freestanding-runtime` 等やグローバル変数群が個別セクションへ誤配置されるのを防止した。
3. **Exact / Hybrid GC スタックマップの整合性保護**:
   - `(!gc none)` では `.section .rodata.__ulisp_stackmap_table,"a",@progbits` に `.quad 0` を出力し、GC 有効モード時は全 `safepoints` を出力して `test_gc_stress` / `test_gc_hybrid` の完全性を維持した。
4. **`eval`・第一級関数・暗黙的プリミティブ補助関数の保持**:
   - 非線形参照される `num+` 等 13 種の算術・比較・ビット演算 slow-path 補助関数と `%synapse-safepoint-poll!` を `cc-mark-implicit-prim!` / `prune-unreachable-top-level-defs` で確実にルート保持し、`test_c`（143/143）および `test_lir_suite` を完全通過させた。
5. **Pass 144 自前アセンブラ・静的リンカのスケーラビリティ**:
   - `elf64-parse-relocatable-object` の `loop-rela` を直積 `append` から $O(S + R)$ 蓄積へ改善し、`test_builtin_as` / `test_builtin_ld` / `test_differential_elf` を全通過させた。

---

## 4. 影響範囲と変更ファイル / Scope and Changed Files

- [x] [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm)（関数毎 `.text.<fn>`・クロージャ毎 `.data.<sc>` 分割出力、`.text`/`.data` 復帰、`"aR"` 付与、`(!gc none)` 空スタックマップテーブル分離）
- [x] [150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm)（AArch64 向けセクション分割・復帰・空スタックマップテーブル分離）
- [x] [110_closure_convert.scm](../../../ulisp/frontend/110_closure_convert.scm)（`prune-unreachable-top-level-defs` / `cc-mark-implicit-prim!` による単一プログラム到達可能性プルーニング）
- [x] [elf64_builder.scm](../../../ulisp/backend/elf64_builder.scm)（`loop-rela` の $O(S+R)$ 化）
- [x] [Makefile](../../../ulisp/Makefile) & [bootstrap.sh](../../../ulisp/bootstrap.sh)（`LDFLAGS` とブートストラップリンク工程への `--gc-sections` 適用）
- [x] [test_110_closure_convert.scm](../../../ulisp/tests/passes/test_110_closure_convert.scm), [test_140_backend_x86_64.scm](../../../ulisp/tests/passes/test_140_backend_x86_64.scm), [test_extern_symbols.scm](../../../ulisp/tests/passes/test_extern_symbols.scm)（ユニットテスト追加・整合更新）
- [x] [compiler.scm](../../../ulisp/compiler.scm)（`make -C ulisp compiler` による再生成）

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `stage3-modular` において未参照関数・未使用静的クロージャ・`(!gc none)` 不要スタックマップの除去により、ELF `.text` が **-22.55% (-1.45 MB)**、`size` `text` 合計が **-30.76% (-2.40 MB)** 削減されていること。
- [x] 単一バイナリ（`test_split_link` / `test_pure_bootstrap` / `test_c`）において未参照関数削除が機能し、かつ `eval` / 第一級関数 / 高階関数 / GC / 例外テストが全 PASS すること。
- [x] `make -C ulisp lint_sexpr compiler test_passes test_pass_manager test_backend test_c test_lir_suite test_bignum test_ieee754 test_gc_stress test_gc_hybrid test_split_link test_pure_bootstrap test_builtin_as test_builtin_ld test_differential_elf` が全 PASS すること。
- [x] `make check_format` および `make static_analysis` が全 PASS すること。
- [x] `./bootstrap.sh --full` で全 5 モジュールの Stage 2 → Stage 3 自己コンパイル不動点（SHA-256 一致）を維持していること。
- [x] 施策前後の計測（残存 `ulisp_fn_*` 数・`.text` / `.rodata` / `.data` サイズ・`objdump -d` 命令数・起動時間・5 回自己コンパイル中央値）を本 Issue に記録していること。
- [x] 相対リンクのみ・絶対パス 0 件であること。

---

## 6. 実装・検証結果 / Implementation & Verification Results

### 6.1 テスト・ブートストラップ検証
- `./bootstrap.sh --full`（クリーン 3-Stage 分割並列ブートストラップ）：全 5 モジュールで **Stage 2 == Stage 3 SHA-256 完全一致**：
  - `compiler_base`: `a50d8e27fad9c3c1...`（一致）
  - `frontend_passes`: `1656f1575f97c72d...`（一致）
  - `lir_passes`: `e253bb45f4c2496a...`（一致）
  - `backend_passes`: `c4239d9caab1a702...`（一致）
  - `compiler_driver`: `7df2f21e812affd4...`（一致）
- `make -C ulisp lint_sexpr test_passes test_pass_manager test_backend test_c test_lir_suite test_bignum test_ieee754 test_gc_stress test_gc_hybrid test_split_link test_pure_bootstrap test_builtin_as test_builtin_ld test_differential_elf`：**全 15 ターゲット PASS**（`test_c` 143/143、`test_pure_bootstrap` 10/10、`test_builtin_as` 6/6、`test_builtin_ld` 9/9、`test_differential_elf` 13/13）。

### 6.2 `stage3-modular` 施策前後比較

| 指標 (`stage3-modular`) | Before (#959) | After (#960) | 差分 |
| --- | :---: | :---: | :---: |
| 定義済み `ulisp_fn_*` シンボル数 (`nm`) | 3,832 個 | **2,367 個** | **-1,465 個 (-38.23%)** |
| ELF `.text` (`objdump -h`) | 6,753,237 B | **5,230,601 B** (`0x4fd009`) | **-1,522,636 B (-22.55%)** |
| ELF `.rodata` (`objdump -h`) | 1,360,200 B | **364,360 B** (`0x58f48`) | **-995,840 B (-73.21%)** |
| ELF `.data` (`objdump -h`) | 325,520 B | **204,912 B** (`0x32070`) | **-120,608 B (-37.05%)** |
| `size` 合計 `text` 列 | 8,186,245 B | **5,667,993 B** | **-2,518,252 B (-30.76%)** |
| `objdump -d` 総命令数 | 1,612,197 命令 | **1,247,741 命令** | **-364,456 命令 (-22.61%)** |
| 起動時間 (`(+ 1 2)`, 5回中央値) | 5.45 ms | **4.95 ms** (`[5.43, 4.95, 4.91, 5.1, 4.91]`) | **-0.50 ms (-9.17%)** |
| 自己コンパイル時間 (`frontend_passes_in.scm`, 5回中央値) | 5.052 s | **4.725 s** (`[4.859, 4.725, 4.828, 4.572, 4.518]`) | **-0.327 s (-6.47%)** |
