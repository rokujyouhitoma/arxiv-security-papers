---
ID: 784
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ULisp における GNU ld 互換コマンドラインオプション (--ld) と複数 ELF64 オブジェクト (.o) 静的リンカの実装 (ID: 784)

## 1. 概要 / Summary

現在、ULisp の分割ビルド（`build/ulisp-fast`）および 5 モジュール並列ビルド（`build/ulisp-modular`）、ならびに分割リンク方式の 3-Stage ブートストラップ（[Issue #777](closed/777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md), [Issue #778](closed/778-implement-modular-parallel-incremental-bootstrap.md)）では、事前コンパイル済みの `build/ulisp_stdlib.o` と各モジュール `.o` を結合するために外部の GNU Linker（`ld -m elf_x86_64 -static`）を呼び出している。

本 Issue では、ULisp コンパイラドライバ（`ulisp/compiler/driver.scm`）に `ld` 相当のコマンドラインオプション（`--ld`）を実装し、複数の ELF64 再配置可能オブジェクトファイル（`.o`, `ET_REL`）を読み込んでシンボル解決・セクション統合・再配置パッチ適用を行い、外部の `ld` バイナリなしに単体で静的リンク済み ELF64 実行可能バイナリ（`ET_EXEC`）を生成できるようにする：

1. **`--ld`（スタンドアロン静的リンカモード）**:
   - `ulisp --ld obj1.o obj2.o ... -o output_bin`（`-m elf_x86_64` や `-static` 等の互換フラグも許容）として呼び出された際、複数の ELF64 `ET_REL` オブジェクトファイルをパースする。
2. **複数オブジェクトのセクション結合とリンカシンボル合成**:
   - 各 `.o` の `.text`, `.rodata`, `.data`, `.bss` に加え、モジュラー初期化配列 `.init_array`（および合成境界シンボル `__init_array_start` / `__init_array_end`）やグローバル変数ルートテーブル `ulisp_globals_sec` をアライメント規約に従って結合する。
3. **グローバル / ウィークシンボル解決と x86-64 再配置適用**:
   - `STB_GLOBAL` と `STB_WEAK`（`ulisp_stdlib_init` 等のウィーク定義・優先上書き規則）を正しく解決し、`R_X86_64_64`, `R_X86_64_PC32`, `R_X86_64_PLT32`, `R_X86_64_32`, `R_X86_64_32S` 等の再配置エントリ（`.rela.*`）を計算して W^X 準拠の `ET_EXEC` バイナリを出力する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 4 章「バックエンド・コード生成およびゼロ libc ELF ビルダー」
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 5 章「3段階セルフホスティングブートストラップ連鎖と不動点検証」
- 依存・関連 Issue:
  - [Issue #607](closed/607-support-extern-symbols-and-split-stdlib-compiler-linking.md): 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入
  - [Issue #608](closed/608-implement-modular-separate-compilation-and-incremental-build.md): Nanopass・モジュール単位の完全分割コンパイルおよび増分ビルド基盤の実装
  - [Issue #616](closed/616-implement-zero-libc-direct-elf-emitter-and-assembler.md): ゼロ libc ネイティブ 2-pass アセンブラおよび ELF64 スタティックバイナリビルダーの実装
  - [Issue #617](617-establish-self-contained-bootstrap-chain-free-from-external-toolchains.md): 外部ツール完全非依存な自給自足 3-Stage セルフホスティングブートストラップの確立
  - [Issue #777](closed/777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #778](closed/778-implement-modular-parallel-incremental-bootstrap.md): モジュール分割増分コンパイルと make -j 並列実行
  - [Issue #779](closed/779-optimize-bootstrap-heap-allocation-and-direct-elf-codegen.md): コンパイラ初期アリーナヒープ一括確保およびダイレクト ELF 出力によるブートストラップ I/O 高速化
  - [Issue #783](783-support-builtin-as-assembler-cli-option-and-elf64-relocatable-object-emission.md): ULisp における GNU as 互換コマンドラインオプション (--as / -c) と ELF64 再配置可能オブジェクト (.o) 出力の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (`--ld`, `-m`, `-static` 等のリンカ CLI オプション解析と複数入力ファイル受け渡し)
- [ ] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm) (ELF64 `ET_REL` リーダー、セクション結合器、シンボル解決・再配置パッチエンジン)
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) (`link-elf64-objects` エントリポイント)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`LD` ツール切り替えおよび `build/ulisp-fast` / `build/ulisp-modular` リンク検証ターゲット)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (内蔵 `--as` / `--ld` による外部 binutils 非依存ブートストラップ連携)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/784-support-builtin-ld-static-linker-cli-option-for-elf64-objects`

1. `polish-issue` フェーズにて ELF64 `ET_REL` パーサ仕様、セクションマージ順序、ウィークシンボル解決規則、および再配置計算式を詳細策定する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp --ld build/ulisp_stdlib.o build/ulisp_compiler.o -o build/ulisp-fast` により 2 分割オブジェクトが正常に静的リンクされ、`test_split_link` が PASS すること。
- [ ] `ulisp --ld` を用いて 5 モジュール構成の `build/ulisp-modular`（`.init_array` および `ulisp_globals_sec` を含む）が正常に静的リンクされ、動作すること。
- [ ] Issue #783 の `ulisp --as` と組み合わせることで、外部の `as` / `ld` を一切呼び出さずに分割・モジュラーブートストラップが完走すること。

