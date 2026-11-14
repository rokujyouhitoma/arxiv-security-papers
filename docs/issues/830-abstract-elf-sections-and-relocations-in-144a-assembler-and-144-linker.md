---
ID: 830
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 144a アセンブラおよび 144 ELF リンカにおける複数セクション (.rodata/.data/.bss) と再配置の抽象化 (ID: 830)

## 1. 概要 / Summary
自前のアセンブラ（`ulisp/backend/144a_assembler.scm`）および ELF リンカ（`ulisp/backend/144_linker.scm`）をリファクタリングし、単一コードセクション（`.text`）の出力前提から、複数セクション（`.text`, `.rodata`, `.data`, `.bss`）、シンボル属性（`global`, `local`, `weak`, `hidden`, `alias`）、および各種再配置型（`R_X86_64_64`, `R_X86_64_PC32`, `R_X86_64_PLT32` 等）を扱う汎用セクション・リンカエンジンへと進化させる。
これにより、Scheme プログラムにおける静的定数データ（文字列・ベクタ・シンボルテーブル）を `.rodata` に直接配置して AOT バイナリの起動速度とメモリフットプリントを大幅に改善するとともに、C 言語の大域変数・静的初期化子出力のための基盤を整備する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (C3: 大域変数と静的初期化, E7: データセクション, F1/F2: エンコードとシンボル, H2: リンカ選択)
- **関連 Issue**: #617 (Self-Contained Bootstrap Chain), #829 (Calling Conventions)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/144a_assembler.scm](../../ulisp/backend/144a_assembler.scm): データディレクティブ（`.quad`, `.long`, `.short`, `.byte`, `.string`, `.zero`）のエンコード
- [ ] [ulisp/backend/144_linker.scm](../../ulisp/backend/144_linker.scm): 複数 ELF セクションヘッダの配置と再配置テーブルの解決
- [ ] [ulisp/tests/test_elf_sections_and_reloc.scm](../../ulisp/tests/test_elf_sections_and_reloc.scm): セクション生成とシンボル再配置テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/830-elf-sections-and-relocations`

1. セクション表現の汎用データ構造化：
   - 各セクションを `(:name <string>)`, `(:type <progbits/nobits>)`, `(:flags <alloc/write/exec>)`, `(:align <int>)`, `(:bytes <bytevector>)`, `(:relocations <list>)` として抽象化。
2. データアセンブリ指令の追加：
   - `.section .rodata`, `.data`, `.bss` の切り替え。
   - ラベルシンボルへの再配置付きポインタ（`.quad sym + addend`）のサポート。
3. ELF 64 出力器の更新：
   - セクションヘッダテーブル（SHT）の正確なオフセット計算と `st_shndx` の整合性維持。
   - `R_X86_64_64`（絶対アドレス）および `R_X86_64_PC32`（PC相対）再配置の適用。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 生成された ELF オブジェクトファイル（`.o`）および実行可能ファイルが、Linux 標準の `readelf -a` および `objdump -d -s` でエラーなく正しくダンプされること。
- [ ] Scheme のリテラルデータが `.rodata` に正しく出力され、実行時に再初期化なしで参照できること。
- [ ] 静的大域変数の初期化と再配置がシステムリンカ（`ld`）または自前リンカ（144）の双方で正しく解決されること。
