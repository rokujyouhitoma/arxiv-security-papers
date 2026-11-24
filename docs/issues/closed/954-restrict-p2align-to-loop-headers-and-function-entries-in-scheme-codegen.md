---
ID: 954
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] Scheme コード生成における内部ラベル `.p2align` の削減（ループ先頭・関数入口限定） (ID: 954)

## 1. 概要 / Summary

`ulisp-boot`（#953 適用後・`main` `03b6693a9`・`.text` `8,869,861 B`）および `ulisp-cc`（`.text` `10,964,469 B`）における `nop` パディングの割合は依然として `.text` の約 6.8% を占めている。

| バイナリ | `.text` サイズ | `nop` 命令数 | `nop` バイト数 (占有率) |
|---|---:|---:|---:|
| `ulisp/bin/ulisp-boot` | 8,869,861 B | 113,879 | **601,768 B (587.7 KB, 6.78%)** |
| `ulisp/bin/ulisp-cc` | 10,964,469 B | 142,686 | **748,097 B (730.6 KB, 6.82%)** |

[140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm) は関数入口（L2412 / L2415 / L2801 の `.p2align 4`）に加え、L882-901 の `lower-lir-instruction` 内 `(%label)` / `(%block)` で、`c-tu` モード以外のすべての内部ラベルに無条件で `(%p2align 4)` を発行している（[#933](933-eliminate-intraprocedural-label-p2align-nop-bloat-and-enable-short-jumps.md) は `c-tu` モードのみ対応済み）。

### モジュール全体 `.p2align` 内訳（計 119,146 件）

`ulisp-boot` 構成 6 モジュール（`ulisp_stdlib` 21,828 / `compiler_base` 23,978 / `frontend_passes` 28,651 / `lir_passes` 18,371 / `backend_passes` 24,860 / `compiler_driver` 1,458）のアセンブリ実測:

- **非ループ内部ラベル（約 111,700 件以上、93.8% — すべて整列不要）**:
  - `.L_else_*` (35,604)、`.L_end_*` (35,604)、`.cmp_br_slow_*`/`.cmp_br_cont_*` (6,484)、`.add_slow_*`/`.add_done_*` (3,670)、`.sub_slow_*`/`.sub_done_*` (3,034)、`.cmp_slow_*`/`.cmp_done_*` (2,660)、`.L_cont_exit_*` (1,786)、`.mul_slow_*`/`.mul_done_*` (794)、`.mod_*` (699)、`.strlen_done_*`/`.vec_init_done_*`/`.bv_zero_done_*` (617)、`.quot_*` (340)、`.bitand_*` (178) など。
- **関数エントリ（約 4,338 件、3.6% — `.p2align 4` 維持）**:
  - `ulisp_fn_*` (3,702) + `.L_lambda_*` (636)。`select-instructions-function` (L2412/2415) および `emit-x86-function` (L2801) で出力。
- **ループ先頭・バックエッジ先ラベル（約 3,039 件、2.6% — `.p2align 4` 維持）**:
  - `.L_cont_entry_*` (1,786)、`.L_loop_head_*` (636)、`.strlen_loop_*` (295)、`.vec_init_loop_*` (267)、`.bv_zero_loop_*` (55)、`.L_loop_body_*`。

### GC・実行時安全性の確認

- [141_backend_x86_gc.scm](../../../ulisp/backend/141_backend_x86_gc.scm)（L178-199 `__ulisp_stackmap_table`）は `call` 直後の `__safepoint_N` 厳密アドレスを照合しており、`%label`/`%block` アラインメントには依存しない。
- クロージャとファーストクラス関数は関数エントリ（`ulisp_fn_*` / `.L_lambda_*`、L2412/2415 で 16B 整列済み）のみを参照するため、関数内ローカル分岐・合流・slow path ラベルの下位ビットを検査するコードは存在しない。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](../945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #933](933-eliminate-intraprocedural-label-p2align-nop-bloat-and-enable-short-jumps.md)（C-TU モードでの `.p2align` 削減）
  - [Issue #951](951-disable-safepoint-injection-in-single-threaded-compiler-modules.md)
  - [Issue #952](952-strip-release-binaries-and-split-debug-symbols.md)
  - [Issue #953](953-shorten-immediate-mov-encoding-in-x86-backend-and-assembler.md)（本施策のベースライン）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm)
  - ループ先頭ラベル判定ヘルパー `x86-loop-header-label?` を追加する（`(not (eq? (car *backend-gc-mode*) 'c-tu))` かつ `asm-label->str` が `".L_loop_head_"` / `"L_loop_head_"` / `".L_loop_body_"` / `"L_loop_body_"` / `".L_cont_entry_"` / `"L_cont_entry_"` / `".strlen_loop_"` / `"strlen_loop_"` / `".vec_init_loop_"` / `"vec_init_loop_"` / `".bv_zero_loop_"` / `"bv_zero_loop_"` で始まる場合に `#t`）。
  - `lower-lir-instruction` の `((%label)`（L882-887）と `((%block)`（L889-901）で、`(x86-loop-header-label? lbl)` が真のときのみ `(%p2align 4)` を前置し、それ以外の内部ラベルでは `(%p2align 4)` を省略する。
  - `select-instructions-function`（L2412/2415）および `emit-x86-function`（L2801）の関数エントリ `.p2align 4` は維持する。
- [x] [143_backend_x86_peephole.scm](../../../ulisp/backend/143_backend_x86_peephole.scm)
  - `rule-x86-jump-p2align-next-label`（ループ先頭ラベル用）と `rule-x86-jump-next-label`（非整列ラベルへ直接効くようになる）の併用を確認する（変更不要）。
- [x] [test_140_backend_x86_64.scm](../../../ulisp/tests/passes/test_140_backend_x86_64.scm)
  - テスト 7（#933）および #954 用アサーションを更新・追加し、managed モードではループ先頭ラベル（`.L_loop_head_fn_1`, `.L_cont_entry_1`）のみ `(%p2align 4)` を出し、非ループ内部ラベル（`.L_else_1`, `.add_slow_1`, `.L_test_managed`）では省略し、`c-tu` モードではすべて省略することを検証する。
- [x] [bin/ulisp-boot](../../../ulisp/bin/ulisp-boot)
  - 3 段モジュラーブートストラップ後の更新済みシードバイナリ。
- [x] [compiler.scm](../../../ulisp/compiler.scm)
  - `ulisp/Makefile` の `compiler` ターゲットで再生成される統合ソース。

### セキュリティ・正当性観点
- 関数エントリおよび GC セーフポイント・スタックマップのアドレス整合性は変更しない。
- 分岐命令ターゲット間の距離が縮まることで I-cache ヒット率が向上し、コードサイズと命令フェッチ帯域の両面で利点がある。

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/954-restrict-p2align-scheme-codegen`

1. **ベースライン確認**（`main` `03b6693a9`）:
   - `ulisp-boot`（10,452,272 B / `.text` 8,869,861 B / `nop` 113,879 命令・601,768 B）、`ulisp-cc`（12,994,728 B / `.text` 10,964,469 B / `nop` 142,686 命令・748,097 B）を記録。
2. **`140_backend_x86_64.scm` の `lower-lir-instruction` 更新**:
   - `x86-loop-header-label?` ヘルパーを `lower-lir-instruction` の直前に追加する。
   - `((%label)` および `((%block)` で `(if (x86-loop-header-label? lbl) ...)` に切り替え、非ループラベルへの `(%p2align 4)` 発行を止める。
3. **`test_140_backend_x86_64.scm` の更新と拡張**:
   - テスト 7 が `.L_test_managed` に対して `((%p2align 4) (%label ...))` を期待していた部分を Issue #954 の仕様（非ループラベル省略 + `.L_loop_head_fn_1` / `.L_cont_entry_1` で維持）に合わせて更新・拡張する。
4. **単体・機能テスト実行**:
   - `python3 ulisp/scripts/lint_sexpr.py` と `make -C ulisp test_passes`、`test_144a`、`test_differential_elf`、`test_builtin_as`、`test_gc_stress` 等を実行する。
5. **全モジュール・シード・`ulisp-cc` 再構築**:
   - `ulisp_stdlib.o`・3 段モジュラーブートストラップ（`bootstrap_verify_modular`）・`bin/ulisp-cc` を再ビルドし、5 モジュールすべての `stage2 == stage3` 不動点一致を確認する。
6. **事後計測と統合検証**:
   - `objdump` で `ulisp-boot` / `ulisp-cc` の `nop` 命令数・バイト数（601,768 B → 200 KB 以下達成確認）、`.text` / ファイルサイズ、5 回自己コンパイル中央値を計測し「6. 計測結果」に記録する。
   - `make -C ulisp test_ulisp_cc_native`（Lua 33 TU SHA-256 一致・`all.lua` 含む）および `make format check_format static_analysis py_compile test`・`verify-quality-gates` を全 PASS させてクローズ・マージする。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ulisp-boot` の `nop` バイト数が 601,768 B → 200 KB 以下に削減されている（**65,996 B = 64.4 KB, −89.0%**）
- [x] `ulisp-boot` の `.text` が 350 KB 以上削減されている（**−743,600 B = −726.2 KB**）
- [x] `test_140_backend_x86_64.scm` のループ先頭維持・非ループ省略・`c-tu` 省略テストおよび `make -C ulisp test_passes` が全 PASS
- [x] `make -C ulisp bootstrap_verify_modular` で 5 モジュールすべて stage2 == stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [x] 自己コンパイル時間（5 モジュール合計・中央値）が悪化しない（7 回交互実測: `real 13.46 s -> 13.21 s (−1.9%)`、`user 10.03 s -> 9.93 s (−1.0%)`）
- [x] `make -C ulisp test_ulisp_cc_native` / `test_differential_elf` / `test_gc_stress` が全 PASS
- [x] 施策前後の計測（自己コンパイル時間中央値・ELF/`.text` サイズ・`nop` 命令数とバイト数）を本 Issue「6. 計測結果」に記録
- [x] `make format` / `make check_format` / `make static_analysis` / `make py_compile` / `make test` が全 PASS
- [x] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）

---

## 6. 計測結果 / Measurements

ベースライン（#953 適用直後、`main` `03b6693a9`、Linux x86-64）と変更後を比較。

| 指標 | 変更前 (#953後) | 変更後 | 差分 |
|---|---:|---:|---:|
| `ulisp-boot` `nop` 命令数 | 113,879 | 15,425 | **−98,454 (−86.5%)** |
| `ulisp-boot` `nop` バイト数 | 601,768 B (587.7 KB) | 65,996 B (64.4 KB) | **−535,772 B (−523.2 KB, −89.0%)** |
| `ulisp-boot` `.text` | 8,869,861 B | 8,126,261 B | **−743,600 B (−726.2 KB)** |
| `ulisp-boot` ファイルサイズ | 10,452,272 B | 9,707,024 B | **−745,248 B (−727.8 KB)** |
| `ulisp-cc` `nop` バイト数 | 748,097 B (730.6 KB) | 89,755 B (20,885 命令) | **−658,342 B (−642.9 KB, −88.0%)** |
| `ulisp-cc` `.text` | 10,964,469 B | 10,053,989 B | **−910,480 B (−889.1 KB)** |
| `ulisp-cc` ファイルサイズ | 12,994,728 B | 12,089,736 B | **−904,992 B (−883.8 KB)** |
| 自己コンパイル時間（5 モジュール合計・7 回中央値 `real`） | 13.46 s | 13.21 s | **−0.25 s (−1.9%)** |
| 自己コンパイル時間（7 回中央値 `user` / `sys`） | 10.03 s / 3.38 s | 9.93 s / 3.48 s | −0.10 s / +0.10 s |

- `.text` の削減幅（743.6 KB）が `nop` 削減幅（535.8 KB）を上回る約 208 KB 分は、内部ラベル前の `.p2align 4` が外れたことで `rule-x86-jump-next-label` 等によるフォールスルー `jmp` 消去が連鎖的に発火した効果。
- 初回 5 回簡易計測ではホスト揺らぎを含む `real 12.88 s vs 13.32 s`（各回 `new`: `13.35 / 12.71 / 12.43 / 13.32 / 14.28 s`）となったため、`user` / `sys` を含む 7 回交互計測で再検証し、実 CPU 時間・中央値ともに悪化なし（`13.46 s -> 13.21 s`）を確認した。
- テスト: `make -C ulisp test_passes`（858/858 Nanopass + 165/165 Pass 1-7 PASS）、`make -C ulisp bootstrap_verify_modular`（5 モジュール不動点 PASS）、`make -C ulisp test_differential_elf`（13/13 PASS）、`make -C ulisp test_builtin_as`（6/6 PASS）、`make -C ulisp test_gc_stress`（16/16 + `(!gc stress)` PASS）、`make -C ulisp test_ulisp_cc_native`（C99/musl/Lua 33 TU SHA-256 パリティ + Lua 公式 `all.lua` 全 PASS）。
