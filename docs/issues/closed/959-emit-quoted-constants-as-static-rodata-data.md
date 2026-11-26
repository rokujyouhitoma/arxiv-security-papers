---
ID: 959
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-26
---

# [FEAT/ENH] quote 定数の静的データ化（`ulisp_mod_init_*` 実行時構築の廃止と `.rodata` 配置） (ID: 959)

## 1. 概要 / Summary

従来、[130_lir.scm](../../../ulisp/lir/130_lir.scm#L304-L327) の `(quote datum)` コンパイル処理が、ペア（リスト）およびベクタ定数を実行時の `(cons (quote car) (quote cdr))` や `(desugar-vector ...)` 呼び出しへと再帰展開していた。この結果、各モジュール初期化関数（`ulisp_mod_init_*`）および関数本体が quote 定数の 1 コンスセルあたり約 50 バイト以上のヒープ確保・タグ付け命令とスタックフレームを消費していた。

本 Issue では、`repr:scheme-64bit-tagged` モードにおける不変の静的 quote 定数（ペア・リスト・ベクタ・入れ子になったシンボル/文字列/即値）を、DAG 重複排除付きの静的定数プール `*static-constants*`（`intern-static-constant!`）および内容重複排除付き `intern-string` として `.rodata` へ直接配置し、実行時は `lea reg, [rip + .L_qpair_N + 9]` / `lea reg, [rip + .L_qvec_N + 13]`（および `lea reg, [rip + .L_str_N + 3]`）の単一命令のみで参照するようにした。結果として、主要 5 モジュール初期化関数の合計 `.text` サイズを **1,077,712 B → 183,792 B（-893,920 B / -82.95%）**、アセンブリ行数を **207,184 行 → 35,214 行（-83.00%）** へと削減し、全 ELF `.text` サイズも **-1,203,008 B（-1.15 MB / -15.12%）** 短縮した。

---

## 2. トレーサビリティ / Traceability

- 関連資料・Issue:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #890](890-integrate-freeze-serialized-rodata-into-elf-emitter.md)（`freeze-serialize-to-rodata` / ELF `.rodata` 実配線）
  - [Issue #944](944-unify-host-and-guest-value-representation-via-define-value-repr.md)（Host / Guest 値表現の単一情報源化 `define-value-repr`）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（ビルドプロファイル・計測基盤）
  - [Issue #957](957-share-arithmetic-and-compare-slow-path-stubs.md)（先行最適化：算術・比較 slow path の共有スタブ化）
  - [Issue #958](958-eliminate-unused-prologue-spills-and-inline-small-accessors.md)（先行最適化：未使用プロローグスピル削除と小アクセサインライン化）

---

## 3. 脅威モデリングと安全性要件 / Threat Model & Safety Requirements

1. **Exact / Copying / Generational GC のヒープ境界安全性（CWE-824 / フォワーディングポインタ誤書換防止）**:
   - **要件**: 静的セクション（`.rodata`）上のペア（タグ `9` = base + 9）およびベクタ（タグ `13` = base + 13）は、GC の `From` 空間および `Nursery` 空間のアドレス範囲外にあるため、GC がコピーやフォワーディングヘッダ上書きを試みてはならない（`.rodata` 書き込みによる SIGSEGV 防止）。
   - **既存実装との整合確認**:
     - [141_backend_x86_gc.scm](../../../ulisp/backend/141_backend_x86_gc.scm#L988-L994) の `.L_gc_copy_if_heap_dual`、同 `.L_gc_promote_if_nursery`（[L1051-L1057](../../../ulisp/backend/141_backend_x86_gc.scm#L1051-L1057)）、および `ulisp_gc_write_barrier`（[L41-L52](../../../ulisp/backend/141_backend_x86_gc.scm#L41-L52)）は、いずれも `untag` 済みアドレスが `[heap_base, heap_base + heap_size)` の範囲外である場合に即座に元のタグ付きポインタを無変更で返却する境界判定を備えている。
   - **ヘッダ互換性**: 実行時のヘッダ検査・サイズ取得（`vector-length`・等価性・プリンタ等）と完全に整合させるため、静的オブジェクトの先頭 8 バイトにもヒープ確保時と同一の 64-bit GC ヘッダを出力した：
     - **ペア（24 バイト, `.L_qpair_N`）**: `.quad 4196356`、`car`、`.cdr`。参照ポインタは `.L_qpair_N + 9`。
     - **ベクタ（16 + 8*len バイト, `.L_qvec_N`）**: `.quad ((((8 * len + 8) << 16) | 5) << 2)`、`.quad (len << 2)`、各要素。参照ポインタは `.L_qvec_N + 13`。
2. **Pluggable Value Representation 安全性（Issue #944 準拠 / CWE-843 型混同防止）**:
   - `can-emit-static-quoted-datum?` により `(eq? (value-repr-name (current-value-repr)) 'repr:scheme-64bit-tagged)` かつ再帰深さ 64 未満・ベクタ長 4096 以下で全葉要素が **61-bit fixnum (`[-2^60, 2^60-1]`) / boolean / char / `'()` / symbol / string / pair / vector** のみで構成される場合に限定して静的化し、それ以外は従来の実行時構築パスへフォールバックする。
3. **シンボルインターンと `--split-link` / モジュール境界整合性**:
   - `*static-const-counter*`・`*static-constants*`・`can-emit-static-quoted-datum?`・`intern-static-constant!`・`value-repr-name` を [helpers.scm](../../../ulisp/compiler/helpers.scm) の `*known-compiler-symbols*` および [module_header.scm](../../../ulisp/compiler/module_header.scm) / [c_driver_module_header.scm](../../../ulisp/compiler/c_driver_module_header.scm) に登録し、5 モジュール分割コンパイル時の名前解決を保証した。

---

## 4. 変更対象ファイル / Changed Files

- [x] [helpers.scm](../../../ulisp/compiler/helpers.scm)（`*string-table-buckets*` による文字列重複排除、`*static-constants*` / `*static-const-counter*` / DAG 重複排除ハッシュテーブル、`*known-compiler-symbols*` 登録）
- [x] [module_header.scm](../../../ulisp/compiler/module_header.scm) & [c_driver_module_header.scm](../../../ulisp/compiler/c_driver_module_header.scm)（静的定数テーブルおよびヘルパのモジュール外部公開宣言）
- [x] [130_lir.scm](../../../ulisp/lir/130_lir.scm)（`(quote datum)` の `(%code-ref %rax lbl)` ローワリング）
- [x] [lir_lang.scm](../../../ulisp/lir/lir_lang.scm) & [lir_verifier.scm](../../../ulisp/lir/lir_verifier.scm)（`%code-ref` / `%str-ref` における文字列ラベル許可）
- [x] [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm)（`*static-constants*` の `.section .rodata` `.quad` 出力、`.L_qpair_`/`+ 9`・`.L_qvec_`/`+ 13`・`%str-ref`/`+ 3` の単一 `lea` 最適化）
- [x] [150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm)（`.section .rodata` `.xword` 出力および `adrp`+`add :lo12:` + タグ加算）
- [x] [160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm)（`static uint64_t ulisp_L_qpair_*` / `ulisp_L_qvec_*` 配列出力、ポインタタグ計算、`scheme_entry` 冒頭でのポインタ再配置）
- [x] [lir_interpreter.scm](../../../ulisp/vm/lir_interpreter.scm)（`vm-lookup-code-addr` / `vm-lookup-string` の文字列キー対応、2 パス静的 quote 定数ロードとタグ付きアドレス登録）
- [x] [test_130_lir.scm](../../../ulisp/tests/passes/test_130_lir.scm)（Group 10: 静的ペア・ベクタ・DAG 重複排除・x86-64/C コード生成ユニットテスト追加）
- [x] [compiler.scm](../../../ulisp/compiler.scm)（`make -C ulisp compiler` による再生成）

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ulisp_mod_init_*`（`ulisp_stdlib_init` および主要モジュール初期化関数）の `.text` 合計サイズが 50% 以上削減されていること（実測 **-82.95%**）。
- [x] 起動時間および 5 回計測の自己コンパイル時間中央値を計測し、前後比較を記録していること。
- [x] `make -C ulisp lint_sexpr test_passes test_pass_manager test_backend test_c test_lir_suite test_bignum test_ieee754 test_gc_stress test_gc_hybrid test_split_link test_pure_bootstrap` が全 PASS すること。
- [x] `make check_format` / `make static_analysis` が全 PASS すること。
- [x] `./bootstrap.sh --full` で全 5 モジュールの Stage 2 → Stage 3 自己コンパイル不動点（SHA-256 一致）を維持していること。
- [x] 施策前後の計測（`ulisp_mod_init_*` 個別・合計サイズ、ELF/`.text`/`.rodata` サイズ、`objdump` 命令数、自己コンパイル時間中央値 5 回）を本 Issue に記録していること。
- [x] 相対リンクのみ・絶対パス 0 件であること。

---

## 6. 実装・検証結果 / Implementation & Verification Results

### 6.1 テスト・ブートストラップ検証
- `make -C ulisp lint_sexpr compiler test_passes test_pass_manager test_backend test_c test_lir_suite test_bignum test_ieee754 test_gc_stress test_gc_hybrid test_split_link test_pure_bootstrap`: **全 PASS**。
- `rm -f ulisp/build/meta/compiler_env.sbi ulisp/build/ulisp_stdlib.s ulisp/build/ulisp_stdlib.o ulisp/build/stage* && (cd ulisp && ./bootstrap.sh --full)`: **全 5 モジュールで Stage 2 == Stage 3 SHA-256 完全一致**:
  - `compiler_base`: `901e48f57d76953f...` (一致)
  - `frontend_passes`: `53e44afd6dfd0914...` (一致)
  - `lir_passes`: `8c043bc9c952ce9a...` (一致)
  - `backend_passes`: `948e430fb0e6b1fe...` (一致)
  - `compiler_driver`: `c40c0cd1081c2617...` (一致)
- 新規ブートストラップ後 `make -C ulisp test_c`: **143 / 143 テスト全 PASS（GCC `-Wall -Wextra -Werror` 警告 0 件）**。

### 6.2 `ulisp_mod_init_*` サイズ前後比較（`stage3-modular`）

| モジュール初期化関数 | Before (#957) 行数 / `.text` サイズ | After (#959) 行数 / `.text` サイズ | 削減率 (サイズ) |
| --- | :---: | :---: | :---: |
| `ulisp_stdlib_init` | 13,445 行 / 73,472 B | 7,316 行 / 39,280 B | -46.54% |
| `ulisp_mod_init_compiler_base` | 35,958 行 / 186,752 B | 11,229 行 / 57,696 B | -69.11% |
| `ulisp_mod_init_frontend_passes` | 61,187 行 / 307,344 B | 4,116 行 / 18,336 B | -94.03% |
| `ulisp_mod_init_lir_passes` | 55,265 行 / 289,792 B | 6,584 行 / 36,336 B | -87.46% |
| `ulisp_mod_init_backend_passes` | 41,329 行 / 220,352 B | 5,969 行 / 32,144 B | -85.41% |
| **合計（主要 5 初期化関数）** | **207,184 行 / 1,077,712 B** | **35,214 行 / 183,792 B** | **-82.95% (-893,920 B)** |

### 6.3 ELF セクション・命令数・コンパイル性能比較（`stage3-modular`）

| 指標 | Before (#957) | After (#959) | 差分 |
| --- | :---: | :---: | :---: |
| `.text` セクション (`objdump -h`) | 7,956,245 B | 6,753,237 B (`0x670bd5`) | **-1,203,008 B (-15.12%)** |
| `.rodata` セクション (`objdump -h`) | 1,121,084 B | 1,360,200 B (`0x14c148`) | +239,116 B (`+21.33%`, 9,804 個の静的定数配置) |
| `.data` セクション (`objdump -h`) | 422,048 B | 325,520 B (`0x4f790`) | **-96,528 B (-22.87%, 文字列重複排除効果)** |
| `size` 合計 `text` 列 | 9,150,033 B | 8,186,245 B | **-963,788 B (-10.53%)** |
| `objdump -d` 総命令数 | — | 1,612,197 命令 | — |
| 起動時間 (`(+ 1 2)` 5回中央値) | — | 5.45 ms (`[5.79, 5.45, 5.01, 5.63, 5.09]`) | — |
| 自己コンパイル時間 (`frontend_passes_in.scm`, 5回中央値) | 4.702 s | 5.052 s (`[5.107, 5.014, 5.19, 5.007, 5.052]`) | +0.350 s |
