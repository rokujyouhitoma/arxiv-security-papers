---
ID: 783
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ULisp における GNU as 互換コマンドラインオプション (--as / -c) と ELF64 再配置可能オブジェクト (.o) 出力の実装 (ID: 783)

## 1. 概要 / Summary

現在、ULisp は内蔵 2-pass x86-64 アセンブラ（[ulisp/backend/144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm)）および ELF64 ビルダー（[ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm)）を備えているが、これらは単一翻訳単位から直接実行可能バイナリ（`ET_EXEC`）を生成する `--target-elf` 用途に限定されている。
そのため、分割ビルド（`build/ulisp_stdlib.o` + `build/ulisp_compiler.o`）や 5 モジュール並列ビルド（`build/ulisp-modular`）においては、依然として外部の GNU Assembler（`as --64`）をサブプロセス起動して `.s` から `.o`（ELF64 再配置可能オブジェクト `ET_REL`）を生成している。

本 Issue では、ULisp コンパイラドライバ（`ulisp/compiler/driver.scm`）に `as` 相当のコマンドラインオプション（`--as` および `-c`）を実装し、外部の `as` バイナリなしに ULisp 単体でアセンブリファイル（`.s`）または Scheme ソース（`.scm`）から ELF64 再配置可能オブジェクトファイル（`.o`, `ET_REL`）を生成できるようにする：

1. **`--as`（スタンドアロン・アセンブラモード）**:
   - `ulisp --as input.s -o output.o`（`--64` オプション互換フラグも許容）として呼び出された際、入力 `.s` アセンブリテキストを Pass 144a でアセンブルし、セクションテーブル（`.text`, `.rodata`, `.data`, `.bss`, `.init_array`, `ulisp_globals_sec`）、シンボルテーブル（`.symtab`, `.strtab`：`STB_GLOBAL`, `STB_WEAK`, `STB_LOCAL`, `SHN_UNDEF`）、および再配置テーブル（`.rela.text`, `.rela.data`, `.rela.init_array`, `.rela.ulisp_globals_sec`）を備えた標準 ELF64 `ET_REL` オブジェクトファイル（`.o`）を出力する。
2. **`-c`（コンパイル＆アセンブル直接 `.o` 出力モード）**:
   - `ulisp -c input.scm -o output.o` として呼び出された際、`.s` テキストのファイル書き出しを介さず、メモリ内で直接 ELF64 `ET_REL` オブジェクトファイル（`.o`）を出力する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 4 章「バックエンド・コード生成およびゼロ libc ELF ビルダー」
- 依存・関連 Issue:
  - [Issue #616](closed/616-implement-zero-libc-direct-elf-emitter-and-assembler.md): ゼロ libc ネイティブ 2-pass アセンブラおよび ELF64 スタティックバイナリビルダーの実装
  - [Issue #617](617-establish-self-contained-bootstrap-chain-free-from-external-toolchains.md): 外部ツール完全非依存な自給自足 3-Stage セルフホスティングブートストラップの確立
  - [Issue #777](closed/777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #778](closed/778-implement-modular-parallel-incremental-bootstrap.md): モジュール分割増分コンパイルと make -j 並列実行
  - [Issue #779](779-optimize-bootstrap-heap-allocation-and-direct-elf-codegen.md): コンパイラ初期アリーナヒープ一括確保およびダイレクト ELF 出力によるブートストラップ I/O 高速化
  - [Issue #784](784-support-builtin-ld-static-linker-cli-option-for-elf64-objects.md): ULisp における GNU ld 互換コマンドラインオプション (--ld) と複数 ELF64 オブジェクト (.o) 静的リンカの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (`--as`, `--64`, `-c` コマンドラインオプション解析とディスパッチ)
- [ ] [ulisp/backend/144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm) (未解決外部シンボルおよび再配置エントリ `R_X86_64_*`、カスタムセクション `.init_array` / `ulisp_globals_sec`、`.weak` / `.globl` 属性の抽出)
- [ ] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm) (ELF64 `ET_REL` 再配置可能オブジェクトファイル生成器の追加)
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) (`emit-x86-64-elf-obj` および `assemble-file-to-elf-obj` エントリポイント)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`AS` ツール切り替えおよび単体検証ターゲット)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/783-support-builtin-as-assembler-cli-option-and-elf64-relocatable-object-emission`

1. `polish-issue` フェーズにて詳細設計・セクションヘッダレイアウト・再配置型仕様を策定する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp --as input.s -o output.o` により `.s` アセンブリファイルから標準 ELF64 `ET_REL` オブジェクトファイル（`.o`）が生成され、`readelf -h -S -s -r` で正当性が確認できること。
- [ ] `ulisp -c input.scm -o output.o` により `.scm` から直接 `.o` が生成されること。
- [ ] 生成された `.o` ファイルが GNU `ld` および ULisp 内蔵 `--ld`（Issue #784）の双方でリンク可能であり、実行結果が GNU `as` 生成オブジェクトと 100% 一致すること。

