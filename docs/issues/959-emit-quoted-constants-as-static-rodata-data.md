---
ID: 959
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] quote 定数の静的データ化（`ulisp_mod_init_*` 実行時構築の廃止と `.rodata` / `.data` 配置） (ID: 959)

## 1. 概要 / Summary

現在、[130_lir.scm](../../ulisp/lir/130_lir.scm#L304-L323) の `(quote datum)` コンパイル処理が、ペア（リスト）およびベクタ定数を実行時の `(cons (quote car) (quote cdr))` や `(desugar-vector ...)` 呼び出しへと再帰展開している。この結果、各モジュール初期化関数（`ulisp_mod_init_*`）および関数本体が quote 定数の 1 コンスセルあたり約 50 バイト以上のヒープ確保・タグ付け命令と 16 バイトのスタックフレームを消費している。

### 現行 `stage3-modular` における `ulisp_mod_init_*` 実測サイズ（Issue #957 完了時点）

| モジュール初期化関数 | アセンブリ行数 | `.text` 占有サイズ |
| --- | :---: | :---: |
| `ulisp_stdlib_init` | 13,445 行 | 73,472 B (71.8 KB) |
| `ulisp_mod_init_compiler_base` | 35,958 行 | 186,752 B (182.4 KB) |
| `ulisp_mod_init_frontend_passes` | 61,187 行 | 307,344 B (300.1 KB) |
| `ulisp_mod_init_lir_passes` | 55,265 行 | 289,792 B (283.0 KB) |
| `ulisp_mod_init_backend_passes` | 41,329 行 | 220,352 B (215.2 KB) |
| `ulisp_mod_init_compiler_driver` | 3,879 行 | — |
| **合計（主要 5 初期化関数）** | **211,063 行** | **1,077,712 B (1.03 MB)** |

本 Issue では、`repr:scheme-64bit-tagged` モードにおける不変の静的 quote 定数（ペア・リスト・ベクタ・入れ子になったシンボル/文字列/即値）を、DAG 重複排除付きの静的定数プール `*static-constants*` として `.rodata`（または静的参照テーブル）へ直接配置し、実行時は `lea rax, [rip + .L_qconst_N + <tag>]` の 1 命令（LIR 上は `%code-ref` + `%add`）のみで参照できるようにする。これにより `ulisp_mod_init_*` および `.text` セクションの劇的な縮小、スタックフレーム削減、および起動・自己コンパイル時間の高速化を実現する。

---

## 2. トレーサビリティ / Traceability

- 関連資料・Issue:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #890](closed/890-integrate-freeze-serialized-rodata-into-elf-emitter.md)（`freeze-serialize-to-rodata` / ELF `.rodata` 実配線）
  - [Issue #944](closed/944-unify-host-and-guest-value-representation-via-define-value-repr.md)（Host / Guest 値表現の単一情報源化 `define-value-repr`）
  - [Issue #945](closed/945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（ビルドプロファイル・計測基盤）
  - [Issue #957](closed/957-share-arithmetic-and-compare-slow-path-stubs.md)（先行最適化：算術・比較 slow path の共有スタブ化）
  - [Issue #958](closed/958-eliminate-unused-prologue-spills-and-inline-small-accessors.md)（先行最適化：未使用プロローグスピル削除と小アクセサインライン化）

---

## 3. 脅威モデリングと安全性要件 / Threat Model & Safety Requirements

1. **Exact / Copying / Generational GC のヒープ境界安全性（CWE-824 / フォワーディングポインタ誤書換防止）**:
   - **要件**: 静的セクション（`.rodata` / `.data`）上のペア（タグ `9` = base + 9）およびベクタ（タグ `13` = base + 13）は、GC の `From` 空間および `Nursery` 空間のアドレス範囲外にあるため、GC がコピーやフォワーディングヘッダ上書きを試みてはならない（`.rodata` 書き込みによる SIGSEGV 防止）。
   - **既存実装との整合確認**:
     - [141_backend_x86_gc.scm](../../ulisp/backend/141_backend_x86_gc.scm#L988-L994) の `.L_gc_copy_if_heap_dual`、同 `.L_gc_promote_if_nursery`（[L1051-L1057](../../ulisp/backend/141_backend_x86_gc.scm#L1051-L1057)）、および `ulisp_gc_write_barrier`（[L41-L52](../../ulisp/backend/141_backend_x86_gc.scm#L41-L52)）は、いずれも `untag` 済みアドレスが `[heap_base, heap_base + heap_size)` の範囲外である場合に即座に元のタグ付きポインタを無変更で返却する境界判定を既に備えている。
   - **ヘッダ互換性**: 実行時のヘッダ検査・サイズ取得（`vector-length`・等価性・プリンタ等）と完全に整合させるため、静的オブジェクトの先頭 8 バイトにもヒープ確保時と同一の 64-bit GC ヘッダを出力する：
     - **ペア（24 バイト）**: `.quad 4196356`（`(((16 << 16) | 1) << 2)`）、`.quad <car_expr>`、`.quad <cdr_expr>`。参照ポインタは `.L_qconst_N + 9`（ヘッダ 8 バイト分＋ペアタグ `1`）。
     - **ベクタ（16 + 8*len バイト）**: `.quad ((((8 * len + 8) << 16) | 5) << 2)`、`.quad (len << 2)`（fixnum 化要素数）、各要素 `.quad <elem_expr>`。参照ポインタは `.L_qconst_N + 13`（ヘッダ 8 バイト分＋ベクタタグ `5`）。
2. **Pluggable Value Representation 安全性（Issue #944 準拠 / CWE-843 型混同防止）**:
   - `with-value-repr` で `repr:guest-3bit-tagged` や `repr:nan-boxing-64bit` 等の非標準値表現が選択されている場合、タグ値・ヘッダレイアウトが異なるため静的データ表現を適用してはならない。
   - `can-emit-static-quoted-datum?` 述語を導入し、`(eq? (value-repr-name (current-value-repr)) 'repr:scheme-64bit-tagged)` かつ再帰的に全葉要素が **61-bit fixnum / boolean / char / `'()` / symbol / string / pair / vector** のみで構成される場合に限定して静的化し、それ以外（bignum / flonum / 非標準値表現等）は従来の実行時構築パスへ安全にフォールバックする。
   - 空文字列または同一文字列リテラルの重複を抑制するため、文字列プール `intern-string` の再利用や非 `.rodata` リテラルの整合性も維持する。
3. **シンボルインターンと `--split-link` / `ulisp_symtab_sec` 整合性**:
   - 静的定数内で参照されるすべてのシンボルについて、コンパイル時に必ず `(intern-symbol sym)` を呼び出して 64-bit シンボル即値 ID と共に `ulisp_symtab_sec` / `__ulisp_symbol_table` へ登録し、分割リンク時のシンボル印字・解決欠落を防止する。
4. **R7RS リテラル不変性**:
   - R7RS 準拠プログラムにおいて quote リテラルへの破壊的変更（`set-car!` 等）は未定義（不変データ）であり、`.rodata`（または不変領域）配置で安全である。ただし万一書き込みが発生した場合に備え、テストスイート（`test_srfi1.scm` 等）でリテラルと `cons` 結果の区別が保たれていることを回帰検証する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [helpers.scm](../../ulisp/compiler/helpers.scm)（`*static-constants*` / `*static-const-counter*` / DAG 重複排除ヘルパ / `*known-compiler-symbols*`）
- [ ] [string.scm](../../ulisp/lib/string.scm)（AOT コンパイラ側の対応 `*known-compiler-symbols*` 登録同期）
- [ ] [130_lir.scm](../../ulisp/lir/130_lir.scm)（`(quote datum)` の静的データ登録および `(%code-ref %rax lbl)` + `(%add %rax offset)` ローワリング）
- [ ] [lir_lang.scm](../../ulisp/lir/lir_lang.scm) & [lir_verifier.scm](../../ulisp/lir/lir_verifier.scm)（`%code-ref` / `%str-ref` におけるラベル参照形式のスキーマ整合確認）
- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)（`*static-constants*` の `.rodata` `.quad` 出力および `lea reg, [rip + lbl + off]` 単一命令最適化）
- [ ] [150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm)（`*static-constants*` の `.rodata` `.xword` 出力および `adrp`+`add` オフセット計算）
- [ ] [160_backend_c.scm](../../ulisp/backend/160_backend_c.scm)（`static uint64_t` 配列出力と `scheme_entry` 冒頭でのポインタ・シンボル再配置）
- [ ] [lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm)（LIR 参照 VM の静的データ領域における quote 定数実体化対応）
- [ ] [test_130_lir.scm](../../ulisp/tests/passes/test_130_lir.scm)（ペア・ネストリスト・ベクタ・シンボル・文字列・DAG 重複排除ユニットテスト追加）
- [ ] [compiler.scm](../../ulisp/compiler.scm)（`make -C ulisp compiler` による再生成）

---

## 5. 実装方針 / Implementation Plan

Target Branch: `perf/959-static-quoted-constants`

### Phase 1: 静的定数プールと DAG 重複排除基盤 (`ulisp/compiler/helpers.scm` / `lib/string.scm`)
1. `*static-const-counter*`・`*static-constants*`（リセット用 `reset-static-constants!` 含む）および DAG 重複排除用ハッシュテーブル（同一構造のクォート部分木や空リスト・ベクタの共有化）を `helpers.scm` に追加する。
2. `can-emit-static-quoted-datum?` を実装し、`repr:scheme-64bit-tagged` かつ循環なし（または深さ/サイズ上限内）の静的リテラル（pair / vector / symbol / string / 61-bit fixnum / boolean / char / null）であることを判定する。
3. 要素エンコード表現（`(imm <int>)`, `(str-ref <lbl>)`, `(const-ref <lbl> <tag-off>)`）を生成する `intern-static-constant!` を実装し、ペアなら `(+ off 9)`、ベクタなら `(+ off 13)`、文字列なら `(list 'str-ref (intern-string s) 3)`、シンボルなら `(intern-symbol sym)` の即値へと再帰変換する。
4. `intern-string` に内容ベースの重複排除テーブルを導入し、同一文字列リテラルの `.L_str_N` 重複出力も削減する（必要に応じて文字列も `.L_str_N` 1 箇所へ集約）。

### Phase 2: `(quote datum)` の静的ローワリング (`130_lir.scm` / `lir_lang.scm` / `lir_verifier.scm`)
1. [130_lir.scm](../../ulisp/lir/130_lir.scm#L304-L323) の `(eq? op 'quote)` 節で、`pair?` または `vector?` かつ `(can-emit-static-quoted-datum? datum)` が真の場合に、`intern-static-constant!` で `(cons lbl tag-off)` を取得し、`(%code-ref %rax lbl)`（またはオフセット付き参照）＋`(%add %rax tag-off)` を出力する。
2. `generate-lir` のプログラムヘッダ `(reset-static-constants!)` と `%lir-program` へのデータ登録（あるいは既存の `data` / `static-consts` 句への格納）を整備し、LIR シリアライザ（`sbi.scm`）・`lir_verifier.scm`（`L_lir_core` / `L_lir_canonical`）・`131_lower_managed_dialect.scm`・`133_lir_peephole.scm` と整合させる。

### Phase 3: マルチバックエンド静的出力と単一命令化 (`140` / `150` / `160` / `lir_interpreter.scm`)
1. **x86-64 ([140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm))**:
   - `(%code-ref dst lbl)` の直後に `(%add dst offset)` が続くパターンを命令選択段階で `lea dst, [rip + lbl + offset]` の **1 命令（7 バイト）** に融合する（`144a_x86_assembler.scm` の `parse-mem-operand-str` L714-723 は既に `[rip + sym + disp]` をネイティブサポート済み）。
   - `.rodata` セクションに `*static-constants*` の全エントリ（`.p2align 3`、オブジェクトヘッダ `.quad`、および即値・`.L_str_N + 3`・`.L_qconst_M + 9/13`）を出力する。
2. **AArch64 ([150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm))**:
   - `.rodata` に `.p2align 3` + `.xword` で同一の静的オブジェクトを出力する（`add dst, dst, #tag` を維持）。
3. **Portable C ([160_backend_c.scm](../../ulisp/backend/160_backend_c.scm))**:
   - `static uint64_t ulisp_qconst_N[words] ULISP_UNUSED` を出力し、`scheme_entry` の冒頭で文字列・ネスト定数・再配置スロットを初期化する（`static const char` 文字列ポインタ等の `uintptr_t` 変換）。
4. **LIR 参照 VM ([lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm))**:
   - `lir-vm-load!` で静的定数エントリを VM の静的データ領域へ配置し、`%code-ref` / `%load` 等が正しく解決されるようにする。

### Phase 4: 検証・ブートストラップ・前後計測
1. [test_130_lir.scm](../../ulisp/tests/passes/test_130_lir.scm) に静的 quote ペア・リスト・ベクタ・ネスト構造・DAG 重複排除のユニットテストを追加する。
2. `make -C ulisp compiler` で `ulisp/compiler.scm` を再生成し、`make -C ulisp lint_sexpr test_passes test_pass_manager test_backend test_c test_lir_suite test_bignum test_ieee754 test_gc_stress test_gc_hybrid test_split_link test_pure_bootstrap` を実行する。
3. クリーン 3-Stage ブートストラップ（`./bootstrap.sh --full`）を実行し、全 5 モジュールの Stage 2 → Stage 3 ビット完全一致（SHA-256 一致）を確認する。
4. `ulisp_mod_init_*` 各関数サイズ・ELF `.text` / `.rodata` サイズ・起動時間・5 回自己コンパイル中央値・`objdump` 命令数を計測して本 Issue に記録する。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp_mod_init_*`（`ulisp_stdlib_init` および 5 モジュール初期化関数）の `.text` 合計サイズが 50% 以上削減されていること。
- [ ] 起動時間および 5 回計測の自己コンパイル時間中央値を計測し、前後比較を記録していること。
- [ ] `make -C ulisp lint_sexpr test_passes test_pass_manager test_backend test_c test_lir_suite test_bignum test_ieee754 test_gc_stress test_gc_hybrid test_split_link test_pure_bootstrap` が全 PASS すること。
- [ ] `make check_format` / `make static_analysis` が全 PASS すること。
- [ ] `./bootstrap.sh --full` で全 5 モジュールの Stage 2 → Stage 3 自己コンパイル不動点（SHA-256 一致）を維持していること。
- [ ] 施策前後の計測（`ulisp_mod_init_*` 個別・合計サイズ、ELF/`.text`/`.rodata` サイズ、`objdump` 命令数、自己コンパイル時間中央値 5 回）を本 Issue に記録していること。
- [ ] 相対リンクのみ・絶対パス 0 件であること。
