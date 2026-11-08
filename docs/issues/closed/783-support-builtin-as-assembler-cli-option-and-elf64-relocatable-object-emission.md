---
ID: 783
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] ULisp における GNU as 互換コマンドラインオプション (--as / -c) と ELF64 再配置可能オブジェクト (.o) 出力の実装 (ID: 783)

## 1. 概要 / Summary

現在、ULisp は内蔵 2-pass x86-64 アセンブラ（[ulisp/backend/144a_x86_assembler.scm](../../../ulisp/backend/144a_x86_assembler.scm)）および ELF64 ビルダー（[ulisp/backend/elf64_builder.scm](../../../ulisp/backend/elf64_builder.scm)）を備えているが、これらは単一翻訳単位から直接実行可能バイナリ（`ET_EXEC`）を生成する `--target-elf` 用途に限定されている。
そのため、分割ビルド（`build/ulisp_stdlib.o` + `build/ulisp_compiler.o`）や 5 モジュール並列ビルド（`build/ulisp-modular`）においては、依然として外部の GNU Assembler（`as --64`）をサブプロセス起動して `.s` から `.o`（ELF64 再配置可能オブジェクト `ET_REL`）を生成している。

本 Issue では、ULisp コンパイラドライバ（[ulisp/compiler/driver.scm](../../../ulisp/compiler/driver.scm)）に GNU `as` 相当のコマンドラインオプション（`--as` および `-c`）を実装し、外部の `as` バイナリなしに ULisp 単体でアセンブリファイル（`.s`）または Scheme ソース（`.scm`）から ELF64 再配置可能オブジェクトファイル（`.o`, `ET_REL`）を生成できるようにする：

1. **`--as`（スタンドアロン・アセンブラモード）**:
   - `ulisp --as [--64] input.s -o output.o` として呼び出された際、入力 `.s` アセンブリテキストを Pass 144a でアセンブルし、セクションテーブル（`.text`, `.rodata`, `.data`, `.bss`, `.init_array`, `ulisp_globals_sec`）、シンボルテーブル（`.symtab`, `.strtab`：`STB_LOCAL`, `STB_GLOBAL`, `STB_WEAK`, `SHN_UNDEF`）、および再配置テーブル（`.rela.text`, `.rela.rodata`, `.rela.data`, `.rela.init_array`, `.rela.ulisp_globals_sec`）を備えた標準 ELF64 `ET_REL` オブジェクトファイル（`.o`）を出力する。
2. **`-c`（コンパイル＆アセンブル直接 `.o` 出力モード）**:
   - `ulisp -c input.scm -o output.o`（または `-b obj` / `--target-obj`）として呼び出された際、`.s` テキストのファイル書き出しを介さず、メモリ内で直接 ELF64 `ET_REL` オブジェクトファイル（`.o`）を出力する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 4 章「バックエンド・コード生成およびゼロ libc ELF ビルダー」
- 依存・関連 Issue:
  - [Issue #616](616-implement-zero-libc-direct-elf-emitter-and-assembler.md): ゼロ libc ネイティブ 2-pass アセンブラおよび ELF64 スタティックバイナリビルダーの実装
  - [Issue #617](../617-establish-self-contained-bootstrap-chain-free-from-external-toolchains.md): 外部ツール完全非依存な自給自足 3-Stage セルフホスティングブートストラップの確立
  - [Issue #777](777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #778](778-implement-modular-parallel-incremental-bootstrap.md): モジュール分割増分コンパイルと make -j 並列実行
  - [Issue #779](779-optimize-bootstrap-heap-allocation-and-direct-elf-codegen.md): コンパイラ初期アリーナヒープ一括確保およびダイレクト ELF 出力によるブートストラップ I/O 高速化
  - [Issue #784](../784-support-builtin-ld-static-linker-cli-option-for-elf64-objects.md): ULisp における GNU ld 互換コマンドラインオプション (--ld) と複数 ELF64 オブジェクト (.o) 静的リンカの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/driver.scm](../../../ulisp/compiler/driver.scm) (`--as`, `--64`, `-c`, `--target-obj`, `-b obj` コマンドラインオプション解析・ヘルプ表記・ディスパッチ)
- [x] [ulisp/backend/144a_x86_assembler.scm](../../../ulisp/backend/144a_x86_assembler.scm) (`assemble-x86-relocatable`：`.globl` / `.weak` / `.type` 属性追跡、`.init_array` / `ulisp_globals_sec` 分離、未定義外部シンボルおよび `R_X86_64_*` 再配置エントリ抽出)
- [x] [ulisp/backend/elf64_builder.scm](../../../ulisp/backend/elf64_builder.scm) (`build-elf64-relocatable`：`ET_REL` ヘッダ、`SHT_RELA` 再配置セクション、`STB_LOCAL` 先行ソート済み `.symtab` / `.strtab` 生成)
- [x] [ulisp/backend/144_backend_x86_elf.scm](../../../ulisp/backend/144_backend_x86_elf.scm) (`emit-x86-64-elf-obj` および `assemble-and-build-elf-obj` / `assemble-stream-to-elf-obj` エントリポイント)
- [x] [ulisp/backend/142_backend_x86_freestanding.scm](../../../ulisp/backend/142_backend_x86_freestanding.scm) (`ulisp_continuation_invoke` 内の数値ローカルラベル `1:` / `2:` の名前付きラベル化)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`test_builtin_as` 検証ターゲット追加)
- [x] [ulisp/tests/test_builtin_as.sh](../../../ulisp/tests/test_builtin_as.sh) (`--as` および `-c` と GNU `as` + GNU `ld` の相互運用・差分検証スクリプト)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳)

---

## 4. セキュリティ・信頼性脅威分析 / Threat Model & Boundary Analysis

| 脅威 / リスク | 分類 | 影響度 | 発生要因 | 緩和策 / 防御メカニズム |
| :--- | :---: | :---: | :--- | :--- |
| **ELF64 `.symtab` のローカル/グローバル境界違反** | CWE-440 | 高 | System V ELF64 仕様では `.symtab` 内の全 `STB_LOCAL` シンボルが `STB_GLOBAL` / `STB_WEAK` より前に配置され、`sh_info` が最初の非ローカルシンボルインデックスを指す必要がある。これに違反すると GNU `ld` がリンクエラーで拒否する | `.symtab` 構築時に `[0: STN_UNDEF] -> [1..K: STB_LOCAL (セクションシンボル等)] -> [K+1..N: STB_GLOBAL / STB_WEAK (定義済み + SHN_UNDEF)]` の順で厳密にソートし、`.symtab` セクションヘッダの `sh_info` に `K + 1` を設定する |
| **`R_X86_64_PC32` / `R_X86_64_PLT32` の Addend ズレ** | CWE-682 | 高 | x86-64 RIP 相対アドレッシングや `call`/`jmp` 命令では、CPU が命令末尾（次命令先頭 `RIP`）を基準に相対変位を計算するため、Addend 補正（`-4` または `- (4 + imm_bytes)`）が誤っていると実行時に不正アドレスへジャンプし SIGSEGV が発生する | `rel32`（`call`/`jmp`/`jcc`）では `r_addend = addend - 4`、`rip_disp32`（`[rip + sym + addend]`）では後続即値バイト長 `adj` を考慮した `r_addend = addend - 4 - adj` を `Elf64_Rela` に設定し、命令内の disp32 フィールド自体は `0` で初期化する |
| **Weak シンボル（`.weak`）の早期解決によるリンク衝突** | CWE-704 | 中 | `142_backend_x86_freestanding.scm` 等が出力する `.weak ulisp_*` 関数を同一 `.o` 内で静的解決してしまうと、リンク時に他オブジェクトの強シンボル（`STB_GLOBAL`）によるオーバーライドが機能しない | `.weak` 指定されたシンボルは `STB_WEAK`（`2`）として `.symtab` に登録し、それに対する `call` / RIP 参照は同一 `.o` 内に定義があっても `.rela.text` に再配置エントリを残してリンカに解決を委ねる |
| **空ファイル・不正アセンブリ入力時のクラッシュ** | CWE-20 | 低 | `--as` に存在しないファイルや未知ディレクティブが渡された際に未処理例外が発生する | ファイルオープン検査（`sys-open` 失敗時はエラーメッセージ出力と `exit 1`）および未知ディレクティブの安全なスキップ・診断を行う |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/783-support-builtin-as-assembler-cli-option-and-elf64-relocatable-object-emission`

### Step 1: Pass 144a における `ET_REL` 向けセクション・シンボル属性・再配置収集の拡張 (`ulisp/backend/144a_x86_assembler.scm`)
1. [ulisp/backend/144a_x86_assembler.scm](../../../ulisp/backend/144a_x86_assembler.scm) に `assemble-x86-relocatable` 関数を追加する（既存の `ET_EXEC` 用 `assemble-x86-lines` の動作は 100% 維持する）：
   - **対象データセクションの分離**:
     - `.text` (`SHT_PROGBITS = 1`, `SHF_ALLOC | SHF_EXECINSTR = 6`, align 16)
     - `.rodata` (`SHT_PROGBITS = 1`, `SHF_ALLOC = 2`, align 8)
     - `.data` (`SHT_PROGBITS = 1`, `SHF_WRITE | SHF_ALLOC = 3`, align 8)
     - `.bss` (`SHT_NOBITS = 8`, `SHF_WRITE | SHF_ALLOC = 3`, align 8)
     - `.init_array` (`SHT_INIT_ARRAY = 14`, `SHF_WRITE | SHF_ALLOC = 3`, align 8)
     - `ulisp_globals_sec` (`SHT_PROGBITS = 1`, `SHF_WRITE | SHF_ALLOC = 3`, align 8)
   - **シンボル属性ディレクティブの追跡**:
     - `.globl <sym>` / `.global <sym>` $\to$ `globl-syms` リストへ登録（`STB_GLOBAL = 1`）。
     - `.weak <sym>` $\to$ `weak-syms` リストへ登録（`STB_WEAK = 2`）。
     - `.type <sym>, @function` / `@object` $\to$ `sym-types` へ登録（`@function` $\to$ `STT_FUNC = 2`、`@object` $\to$ `STT_OBJECT = 1`、未指定 $\to$ `STT_NOTYPE = 0`）。
   - **Pass 2 における局所解決と `Elf64_Rela` 抽出**:
     - 同一セクション（`.text`）内の定義済みローカルラベル（`.L_*` 等、`globl-syms` にも `weak-syms` にも含まれないもの）への `rel32` 分岐・呼び出しは、Pass 2 で直接相対オフセット `target_off - (patch_off + 4)` を `text-bv` にパッチして再配置エントリ生成を省略する（`.rela.text` サイズとリンク時間の大幅削減）。
     - 以下の参照はすべて `Elf64_Rela` 再配置レコード `(list sec patch-off sym-name r-type r-addend)` として出力し、対象セクション内のパッチ箇所は `0` のままとする：
       - 未定義外部シンボル（`sym-table` に未登録 $\to$ `SHN_UNDEF`）への参照
       - グローバルまたは Weak シンボルへの参照
       - セクション間参照（例：`.text` から `.rodata` / `.data` / `.bss` / `ulisp_globals_sec` 内の `.L_*` またはグローバル変数への `rip_disp32` 参照、および `.rodata` / `.data` / `.init_array` / `ulisp_globals_sec` 内の `.quad sym + addend`）
     - 再配置タイプ定数（System V AMD64 ABI）：
       - `R_X86_64_64 = 1`（`.quad sym + addend`：`r_addend = addend`）
       - `R_X86_64_PC32 = 2`（`rip_disp32`：`r_addend = addend - 4 - adj`、または非関数 `rel32`：`r_addend = addend - 4`）
       - `R_X86_64_PLT32 = 4`（または `R_X86_64_PC32 = 2`、`call` / `jmp` による外部・グローバル関数参照：`r_addend = addend - 4`）

### Step 2: `elf64_builder.scm` における ELF64 `ET_REL` オブジェクトビルダの実装 (`ulisp/backend/elf64_builder.scm`)
1. [ulisp/backend/elf64_builder.scm](../../../ulisp/backend/elf64_builder.scm) に `build-elf64-relocatable` 関数を実装する：
   - **ELF64 Header (`64 bytes`)**:
     - `e_type = 1` (`ET_REL`), `e_machine = 62` (`EM_X86_64`), `e_version = 1`
     - `e_entry = 0`, `e_phoff = 0`, `e_phnum = 0`, `e_phentsize = 0`
     - `e_shentsize = 64`, `e_shnum`, `e_shstrndx`
   - **Section Layout**:
     - `[0]` `NULL` (`SHT_NULL = 0`)
     - `[1]` `.text` (`SHT_PROGBITS = 1`, `SHF_ALLOC | SHF_EXECINSTR = 6`)
     - `[2]` `.rodata` (`SHT_PROGBITS = 1`, `SHF_ALLOC = 2`)
     - `[3]` `.data` (`SHT_PROGBITS = 1`, `SHF_WRITE | SHF_ALLOC = 3`)
     - `[4]` `.bss` (`SHT_NOBITS = 8`, `SHF_WRITE | SHF_ALLOC = 3`)
     - `[5]` `.init_array` (`SHT_INIT_ARRAY = 14`, `SHF_WRITE | SHF_ALLOC = 3`)
     - `[6]` `ulisp_globals_sec` (`SHT_PROGBITS = 1`, `SHF_WRITE | SHF_ALLOC = 3`)
     - `[7]` `.rela.text` (`SHT_RELA = 4`, `sh_flags = 0x40 (SHF_INFO_LINK)`, `sh_link = symtab_shndx (13)`, `sh_info = 1 (.text)`, `sh_entsize = 24`)
     - `[8]` `.rela.rodata` (`SHT_RELA = 4`, `sh_link = 13`, `sh_info = 2 (.rodata)`, `sh_entsize = 24`)
     - `[9]` `.rela.data` (`SHT_RELA = 4`, `sh_link = 13`, `sh_info = 3 (.data)`, `sh_entsize = 24`)
     - `[10]` `.rela.init_array` (`SHT_RELA = 4`, `sh_link = 13`, `sh_info = 5 (.init_array)`, `sh_entsize = 24`)
     - `[11]` `.rela.ulisp_globals_sec` (`SHT_RELA = 4`, `sh_link = 13`, `sh_info = 6 (ulisp_globals_sec)`, `sh_entsize = 24`)
     - `[12]` `.note.GNU-stack` (`SHT_PROGBITS = 1`, `sh_flags = 0`)
     - `[13]` `.symtab` (`SHT_SYMTAB = 2`, `sh_link = 14 (.strtab)`, `sh_info = first_global_sym_idx`, `sh_entsize = 24`)
     - `[14]` `.strtab` (`SHT_STRTAB = 3`)
     - `[15]` `.shstrtab` (`SHT_STRTAB = 3`)
   - **Symbol Table (`.symtab`) の構築と再配置インデックス付け**:
     - インデックス `0`: `STN_UNDEF`
     - インデックス `1..6`: 各セクション `.text`, `.rodata`, `.data`, `.bss`, `.init_array`, `ulisp_globals_sec` に対応する `STB_LOCAL | STT_SECTION` (`st_info = 3`) シンボル！
       これにより、ローカルラベル（`.L_*`）に対するセクション間参照（例：`.text` から `.rodata` の `.L_str_*` 参照や `.rodata` 内の `.quad .L_sym_name_*`）を、個別の `.L_*` シンボルを `.symtab` に大量登録することなく **セクションシンボル + セクション内オフセット（`r_addend = sym_sec_offset + addend`）** に正規化でき、GNU `as` と同様に `.symtab` サイズを劇的に縮小・高速化できる！
     - インデックス `7..N`: `STB_GLOBAL` / `STB_WEAK` シンボル（定義済みシンボルおよび未定義外部参照シンボル `SHN_UNDEF = 0`）。
     - これにより、`sh_info` は常に固定値 `7`（`1 + 6` 個のローカルセクションシンボル）となり、ローカル/グローバル境界が恒等的に保証される。

### Step 3: Pass 144 および `compiler/driver.scm` への `--as` / `-c` オプション統合 (`ulisp/backend/144_backend_x86_elf.scm`, `ulisp/compiler/driver.scm`)
1. [ulisp/backend/144_backend_x86_elf.scm](../../../ulisp/backend/144_backend_x86_elf.scm) に以下を追加する：
   - `(assemble-and-build-elf-obj lines)`: `assemble-x86-relocatable` と `build-elf64-relocatable` を呼び出して `ET_REL` bytevector を返す。
   - `(emit-x86-64-elf-obj prog gc-mode)`: `emit-x86-64` の出力行をキャプチャして `ET_REL` bytevector を生成し、`write-elf64-bytevector` で一括出力する。
   - `(assemble-stream-to-elf-obj)`: 標準入力から `.s` アセンブリ行を読み取り（`port-read-char` ループ）、`assemble-and-build-elf-obj` で `ET_REL` bytevector を生成して `write-elf64-bytevector` で一括出力する。
2. [ulisp/compiler/driver.scm](../../../ulisp/compiler/driver.scm) の `compile-backend` に `((or (eq? target 'obj) (eq? target 'elf-obj)) (emit-x86-64-elf-obj valid-lir gc-mode))` を追加し、`parse-cli-arguments` およびエントリポイントを更新する：
   - `--as` が指定された場合：アセンブラモード（`as-mode = #t`）を有効化し、`--64` オプションも無害に受理する。入力 `.s` ファイル（または標準入力）から直接 `assemble-stream-to-elf-obj` を呼び出して `.o` を出力して終了する。
   - `-c` または `--target-obj` または `-b obj` が指定された場合：`target = 'obj` に設定し、Scheme ソース（`.scm`）をコンパイルして直接 `.o`（`ET_REL`）を出力する。

### Step 4: 検証テストスイート (`ulisp/tests/test_builtin_as.sh`) と `ulisp/Makefile` ターゲットの追加
1. `ulisp/tests/test_builtin_as.sh` を作成し、以下を自動検証する：
   - 単体アセンブリ（`.s`）に対する `ulisp --as --64 input.s -o output.o` の生成、`readelf -h -S -s -r` による `ET_REL` フォーマット検証。
   - GNU `ld` を用いたリンク（`ld -m elf_x86_64 -static output.o -o bin`）および実行結果の一致検証。
   - Scheme ソースに対する `ulisp -c input.scm -o output.o` の直接 `.o` 生成、および `build/ulisp_stdlib.o` との分割静的リンク（`(!allow-extern #t)` + `ulisp_stdlib.o`）の実行検証。
   - モジュール単位（`.init_array` および `ulisp_globals_sec` を含む `.s`）の `--as` アセンブルと GNU `ld` リンク検証。
2. `ulisp/Makefile` に `test_builtin_as` ターゲットを追加する。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp --as [--64] input.s -o output.o` により `.s` アセンブリファイルから標準 ELF64 `ET_REL` オブジェクトファイル（`.o`）が生成され、`file` および `readelf -h -S -s -r` で正当な `ELF 64-bit LSB relocatable` であることが確認できること。
- [x] `ulisp -c input.scm -o output.o` により `.scm` から `.s` ファイルを介さず直接 `.o` が生成されること。
- [x] 生成された `.o` ファイル（単体プログラム、外部シンボル参照プログラム、`ulisp_globals_sec` / `.init_array` を持つモジュール）が GNU `ld` でエラーなくリンクでき、実行結果が GNU `as` 生成オブジェクトと 100% 一致すること（`make -C ulisp test_builtin_as` が 100% PASS）。
- [x] 3-Stage ブートストラップ（`make -C ulisp bootstrap_modular` および `make -C ulisp bootstrap`）がビット完全一致（`0 bytes diff`）で収束すること。
- [x] ルート品質ゲート（`make check_format static_analysis py_compile`）がエラー 0 件で通過すること。
