---
ID: 784
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] ULisp における GNU ld 互換コマンドラインオプション (--ld) と複数 ELF64 オブジェクト (.o) 静的リンカの実装 (ID: 784)

## 1. 概要 / Summary

現在、ULisp の分割ビルド（`build/ulisp-fast`）および 5 モジュール並列ビルド（`build/ulisp-modular`）、ならびに分割リンク方式の 3-Stage ブートストラップ（[Issue #777](closed/777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md), [Issue #778](closed/778-implement-modular-parallel-incremental-bootstrap.md)）では、事前コンパイル済みの `build/ulisp_stdlib.o` と各モジュール `.o` を結合するために外部の GNU Linker（`ld -m elf_x86_64 -static`）を呼び出している。
先行する [Issue #783](closed/783-support-builtin-as-assembler-cli-option-and-elf64-relocatable-object-emission.md) で内蔵アセンブラ（`ulisp --as` / `-c`）による ELF64 再配置可能オブジェクト（`ET_REL`, `.o`）の直接出力が確立されたことにより、残る外部ツール依存は GNU `ld` のみとなった。

本 Issue では、ULisp コンパイラドライバ（[ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm)）に GNU `ld` 互換のコマンドラインオプション（`--ld`）を実装し、複数の ELF64 再配置可能オブジェクトファイル（`.o`, `ET_REL`）を直接読み込んでシンボル解決・セクション統合・リンカシンボル合成・再配置パッチ適用を行い、外部の `ld` バイナリなしに ULisp 単体で静的リンク済み ELF64 実行可能バイナリ（`ET_EXEC`）を生成できるようにする：

1. **`--ld`（スタンドアロン静的リンカモード）**:
   - `ulisp --ld obj1.o obj2.o ... -o output_bin`（`-m elf_x86_64`, `-static`, `-s`, `-e <entry>` 等の互換フラグも受理）として呼び出された際、複数の ELF64 `ET_REL` オブジェクトファイルをパースする。
2. **複数オブジェクトのセクション結合とリンカシンボル合成**:
   - 各 `.o` の `.text`, `.rodata` を Segment 1（RX）に集約配置し、`.init_array`, `.data`, `ulisp_globals_sec`, `.bss` を Segment 2（RW）にアライメント規約（16/8 バイト境界）に従って結合する。
   - モジュラー初期化配列 `.init_array` 向けの合成境界シンボル `__init_array_start` / `__init_array_end`、およびグローバル変数テーブル向けの `__start_ulisp_globals_sec` / `__stop_ulisp_globals_sec` を自動算出して注入する。
3. **グローバル / ウィークシンボル解決と x86-64 再配置適用**:
   - `STB_GLOBAL` と `STB_WEAK`（`ulisp_stdlib_init` 等のウィーク定義・優先上書き規則、未定義ウィークシンボルの NULL アドレス解決）を正しく解決する。
   - `R_X86_64_64`, `R_X86_64_PC32`, `R_X86_64_PLT32`, `R_X86_64_32`, `R_X86_64_32S` 等の再配置エントリ（`.rela.*`）を計算・パッチし、`PT_GNU_STACK`（W^X スタック）を備えた標準 `ET_EXEC` 実行可能ファイルを出力し、`sys-chmod` で実行権限（`0755`）を付与する。

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
  - [Issue #783](closed/783-support-builtin-as-assembler-cli-option-and-elf64-relocatable-object-emission.md): ULisp における GNU as 互換コマンドラインオプション (--as / -c) と ELF64 再配置可能オブジェクト (.o) 出力の実装
  - [Issue #785](closed/785-fix-compiler-error-output-redirection-and-unlink-on-failure.md): コンパイルエラー時の -o 出力先へのログ混入防止および失敗時の中途成果物即時削除

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (`--ld` モード、複数入力オブジェクトファイルリスト解析、`-m`, `-static`, `-s`, `-e` フラグハンドリング)
- [ ] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm) (`elf64-read-relocatable-object`, `elf64-merge-sections-and-layout`, `elf64-resolve-symbols`, `elf64-apply-relocations`, `link-elf64-relocatable-objects`)
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) (`link-elf64-objects-to-file` 公開エントリポイント)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_builtin_ld` 検証ターゲット、`LD ?= ld` 切り替え検証)
- [ ] [ulisp/tests/test_builtin_ld.sh](../../ulisp/tests/test_builtin_ld.sh) (`--ld` と GNU `ld` の等価性・差分・分割リンク・モジュラーリンク総合テスト)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳)

---

## 4. セキュリティ・信頼性脅威分析 / Threat Model & Boundary Analysis

| 脅威 / リスク | 分類 | 影響度 | 発生要因 | 緩和策 / 防御メカニズム |
| :--- | :---: | :---: | :--- | :--- |
| **不正 ELF64 ファイル入力によるバッファ外読み出し** | CWE-125 | 高 | 不正な `e_shoff`, `e_shnum`, `sh_offset` を含む `.o` ファイルを読み込んだ際に範囲外アクセスが発生する | ファイルサイズ・ヘッダマジック（`\x7fELF`）、`e_type == ET_REL`（1）、各セクションオフセットとサイズの整合性を検証し、不整合時は即時安全にエラー終了する |
| **未定義強シンボル（Undefined Reference）の解決漏れ** | CWE-476 / CWE-824 | 高 | リンク対象 `.o` に未解決の `STB_GLOBAL` シンボルが存在するにもかかわらず、0 アドレスを書き込んでバイナリを生成すると実行時 SIGSEGV / 不正ジャンプが発生する | 再配置適用前に全未解決シンボルを走査し、`STB_WEAK` 以外の未定義シンボルが存在する場合は詳細な未解決シンボル名一覧を出力してリンカを `exit 1` で中断し、不完全な成果物を残さない |
| **Weak シンボルと Strong シンボルの優先順位逆転** | CWE-682 | 中 | `ulisp_stdlib_init` や `_start` 等の `.weak` シンボルが後から読み込まれた場合に、先に読み込まれた `STB_GLOBAL` を上書きしてしまう | シンボル解決ハッシュテーブルにおいて「`STB_GLOBAL` は既存の `STB_WEAK` を上書き」「既存の `STB_GLOBAL` は新たな `STB_WEAK` を無視」「`STB_GLOBAL` 同士の重複定義はエラー」の規則を厳密に適用する |
| **`R_X86_64_PC32` / `PLT32` の相対変位オーバーフロー** | CWE-190 | 高 | セグメント配置やセクションサイズが過大で、PC 相対変位が 32-bit 符号付き整数の表現範囲（$\pm 2\text{GB}$）を超過した場合にアドレス破壊が生じる | 再配置計算時に `disp = (S + A) - P` を算出し、`-2147483648 <= disp <= 2147483647` の範囲内であることをアサーション検証する |
| **スタック実行可能化（Non-W^X Stack）の混入** | CWE-250 / CWE-732 | 中 | 出力 `ET_EXEC` に `PT_GNU_STACK` プログラムヘッダが存在しない場合、Linux カーネルがレガシー互換として実行可能スタック（NX 無効）を割り当ててしまう | プログラムヘッダテーブルに `PT_GNU_STACK`（`p_type = 0x6474e551`, `p_flags = 6 (PF_R | PF_W)`) を常に明示的に含め、完全な W^X 規約を強制する |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/784-support-builtin-ld-static-linker-cli-option-for-elf64-objects`

```
  +-------------------------------------------------------------------------------+
  |                             ulisp --ld CLI 入力                               |
  |  ulisp --ld [-m elf_x86_64] [-static] [-e _start] -o bin obj1.o obj2.o ...    |
  +-------------------------------------------------------------------------------+
                                         |
                                         v
  +-------------------------------------------------------------------------------+
  | Step 1: ELF64 ET_REL オブジェクト解析 (elf64-read-relocatable-object)         |
  |  - ELF Header, Section Headers, .shstrtab, .symtab, .strtab, .rela.* の抽出    |
  |  - セクション別データ bytevector, シンボル一覧, 再配置レコード一覧の構造化     |
  +-------------------------------------------------------------------------------+
                                         |
                                         v
  +-------------------------------------------------------------------------------+
  | Step 2: セクション統合 & 仮想アドレス割り当て (elf64-merge-sections-and-layout) |
  |  - Segment 1 (RX: 0x400000): .text (align 16), .rodata (align 8)             |
  |  - Segment 2 (RW: 0x600000): .init_array, .data, ulisp_globals_sec, .bss      |
  |  - 各オブジェクトのセクション内オフセットおよびベース仮想アドレスの確定         |
  +-------------------------------------------------------------------------------+
                                         |
                                         v
  +-------------------------------------------------------------------------------+
  | Step 3: リンカ合成シンボル注入 & 大域シンボル解決 (elf64-resolve-symbols)       |
  |  - __init_array_start / __init_array_end                                      |
  |  - __start_ulisp_globals_sec / __stop_ulisp_globals_sec                       |
  |  - STB_GLOBAL vs STB_WEAK 優先順位解決 & 未定義シンボル（Undefined Ref）検査  |
  +-------------------------------------------------------------------------------+
                                         |
                                         v
  +-------------------------------------------------------------------------------+
  | Step 4: x86-64 再配置適用エンジン (elf64-apply-relocations)                    |
  |  - R_X86_64_64: S + A (64-bit absolute)                                       |
  |  - R_X86_64_PC32 / PLT32: (S + A) - P (32-bit signed PC-relative)            |
  |  - R_X86_64_32 / 32S: S + A (32-bit absolute)                                |
  +-------------------------------------------------------------------------------+
                                         |
                                         v
  +-------------------------------------------------------------------------------+
  | Step 5: ET_EXEC バイナリ出力 & 権限付与                                        |
  |  - PT_LOAD (RX, RW) + PT_GNU_STACK (flags 6)                                  |
  |  - sys-open, write-bytevector, sys-chmod (0755)                               |
  +-------------------------------------------------------------------------------+
```

### Step 1: ELF64 `ET_REL` オブジェクトパーサの実装 (`ulisp/backend/elf64_builder.scm`)
1. [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm) にバイナリ読み込みおよび ELF64 `ET_REL` パーサ関数群を追加する：
   - `(read-binary-file-to-bytevector path)`:
     - `sys-open`（O_RDONLY）でファイルを開き、`sys-lseek(fd, 0, 2)`（SEEK_END）で正確なファイルサイズを取得。
     - `sys-lseek(fd, 0, 0)`（SEEK_SET）で先頭に巻き戻し、`make-bytevector` で確保した領域に `sys-read`（またはチャンクループ）で一括読み込みを行う。
   - `(elf64-parse-relocatable-object bv path)`:
     - ヘッダ検証: Magic `\x7fELF`, `EI_CLASS == 2`（64-bit）, `EI_DATA == 1`（LSB）, `e_type == 1`（ET_REL）, `e_machine == 62`（EM_X86_64）。
     - セクションヘッダテーブル（`e_shoff`, `e_shentsize = 64`, `e_shnum`）の走査。
     - `.shstrtab`（`e_shstrndx`）からセクション名文字列テーブルを抽出。
     - セクションヘッダの分類:
       - `.text`, `.rodata`, `.data`, `.bss`, `.init_array`, `ulisp_globals_sec` 等の割り当て可能セクション（`SHF_ALLOC`）。
       - `.symtab`（`SHT_SYMTAB`）および対応する `.strtab`（`sh_link`）。
       - `.rela.*`（`SHT_RELA`）：対象セクション（`sh_info`）およびシンボルテーブル（`sh_link`）。
     - シンボルテーブルの抽出:
       - 各 24 バイトエントリ（`st_name`, `st_info`, `st_other`, `st_shndx`, `st_value`, `st_size`）。
       - `st_name` を `.strtab` から文字列化。
       - `bind = st_info >> 4`（`STB_LOCAL = 0`, `STB_GLOBAL = 1`, `STB_WEAK = 2`）。
       - `type = st_info & 0xf`（`STT_NOTYPE = 0`, `STT_OBJECT = 1`, `STT_FUNC = 2`, `STT_SECTION = 3`）。
     - 再配置テーブルの抽出:
       - 各 24 バイトエントリ（`r_offset`, `r_info`, `r_addend`）。
       - `sym_idx = r_info >> 32`, `r_type = r_info & 0xffffffff`。

### Step 2: セクション統合とメモリセグメント配置 (`ulisp/backend/elf64_builder.scm`)
1. 複数オブジェクトファイルから収集された各セクションを統合バッファへ結合する：
   - **Segment 1 (RX: Base `0x400000`, File Offset `176` / Page-Aligned)**:
     - 全オブジェクトの `.text` セクションを 16 バイトアライメントで連結。
     - 全オブジェクトの `.rodata` セクションを 8 バイトアライメントで連結。
     - 各オブジェクトのセクション先頭オフセットおよび仮想アドレス（`vaddr`）を記録。
     - セグメント 1 のファイルサイズおよびメモリサイズを 4096 バイト境界へアライメント。
   - **Segment 2 (RW: Base `0x600000` / Aligned VAddr, File Offset = `text-segment-filesz`)**:
     - 全オブジェクトの `.init_array` を 8 バイトアライメントで連結。
     - 全オブジェクトの `.data` を 8 バイトアライメントで連結。
     - 全オブジェクトの `ulisp_globals_sec` を 8 バイトアライメントで連結。
     - 全オブジェクトの `.bss` を 8 バイトアライメントで集計（サイズのみ加算、ファイルデータなし）。
     - セグメント 2 のファイルサイズ（初期化済みデータ長）とメモリサイズ（ファイルサイズ + BSS長）を確定。

### Step 3: リンカ合成境界シンボルとグローバルシンボル解決 (`ulisp/backend/elf64_builder.scm`)
1. **リンカ合成シンボルの自動注入**:
   - `__init_array_start`: 統合 `.init_array` の先頭仮想アドレス。
   - `__init_array_end`: 統合 `.init_array` の末尾仮想アドレス（存在しない場合は `start == end`）。
   - `__start_ulisp_globals_sec`: 統合 `ulisp_globals_sec` の先頭仮想アドレス。
   - `__stop_ulisp_globals_sec`: 統合 `ulisp_globals_sec` の末尾仮想アドレス。
2. **大域シンボル辞書の構築**:
   - 定義済みシンボルの登録: `sym_vaddr = obj_sec_base_vaddr + st_value`。
   - 解決規則:
     - 新規シンボルの場合: 登録。
     - 既存シンボルが `STB_WEAK` で新規が `STB_GLOBAL` の場合: 新規で上書き。
     - 既存シンボルが `STB_GLOBAL` で新規が `STB_WEAK` の場合: 新規を無視。
     - 既存・新規ともに `STB_GLOBAL` の場合: 多重定義エラーを出力して中断。
3. **未定義参照の検査**:
   - 再配置から参照されるすべての未定義シンボル（`st_shndx == SHN_UNDEF`）を照合。
   - 大域辞書に存在しない場合：
     - `STB_WEAK` ならばアドレス `0` に解決（GNU `ld` 互換の安全なウィーク参照）。
     - `STB_GLOBAL` ならば未定義参照エラーを出力して中断。

### Step 4: x86-64 再配置パッチエンジンの実装 (`ulisp/backend/elf64_builder.scm`)
1. 各オブジェクトの `.rela.*` 再配置エントリに対してメモリ内パッチを適用する：
   - 対象セクションの bytevector 内オフセット `r_offset`、およびパッチ適用箇所の実行時仮想アドレス `P = sec_vaddr + r_offset` を算出。
   - シンボル値 `S` の導出:
     - `STT_SECTION`: 対象オブジェクトの対応セクションのベース仮想アドレス。
     - `STB_LOCAL`: 対象オブジェクトの対応セクションベース + `st_value`。
     - `STB_GLOBAL` / `STB_WEAK` / 合成シンボル: 大域辞書から解決された仮想アドレス。
   - 加数 `A = r_addend`。
   - 再配置タイプの計算と書き込み:
     - `R_X86_64_64 (1)`: `val = S + A` $\to$ 64-bit 符号なし整数（`elf64-set-u64-le!`）。
     - `R_X86_64_PC32 (2)` / `R_X86_64_PLT32 (4)`: `disp = (S + A) - P` $\to$ 32-bit 符号付き整数（`elf64-set-s32-le!`）。
     - `R_X86_64_32 (10)`: `val = S + A` $\to$ 32-bit 符号なし整数（`elf64-set-u32-le!`）。
     - `R_X86_64_32S (11)`: `val = S + A` $\to$ 32-bit 符号付き整数（`elf64-set-s32-le!`）。

### Step 5: `144_backend_x86_elf.scm` および `driver.scm` への `--ld` モード統合
1. [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) に公開エントリポイントを追加：
   - `(link-elf64-objects-to-file obj-paths out-path entry-sym)`
2. [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) を更新：
   - `parse-cli-arguments` において、`--ld` フラグが指定された場合にリンカモード（`ld-mode`）を有効化し、複数の非オプション引数を `in-files` リストとして収集する。
   - `-m elf_x86_64`, `-static`, `-s`, `-e <entry>`, `--entry=<entry>` を解釈。
   - エントリポイントにおいて `ld-mode` の場合：
     - `link-elf64-objects-to-file` を呼び出して出力先バイナリへ直接書き込み。
     - `sys-chmod` で実行権限（`0755`）を付与して `(exit 0)`。

### Step 6: テストスイート (`test_builtin_ld.sh`) と `ulisp/Makefile` の整備
1. `ulisp/tests/test_builtin_ld.sh` を新規作成し、以下を検証：
   - 単体 `.o`（関数・分岐・クロージャ）に対する `ulisp --ld` と GNU `ld` の完全一致検証。
   - 2分割構成（`build/ulisp_stdlib.o` + Scheme 直接出力 `.o`）の静的リンクと実行結果の一致。
   - 5モジュール構成（`.init_array` および `ulisp_globals_sec` を含む）の静的リンクと実行。
   - 内蔵 `--as` と内蔵 `--ld` を連鎖させた外部ツール（`as`, `ld`）完全非依存パイプラインの動作検証。
2. `ulisp/Makefile` に `test_builtin_ld` ターゲットを追加し、`make test_builtin_ld` で単体実行可能にする。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp --ld [-m elf_x86_64] [-static] obj1.o [obj2.o ...] -o out_bin` により、GNU `ld` を一切呼び出さずに ELF64 `ET_EXEC` 実行可能ファイルが生成され、`sys-chmod` により `0755` 権限が付与されること。
- [ ] 2分割オブジェクト構成（`build/ulisp_stdlib.o` + `build/ulisp_compiler.o`）を `ulisp --ld` でリンクしたバイナリが正常に動作し、`make -C ulisp test_split_link` 相当の検証に合格すること。
- [ ] 5モジュール並列構成（`MODULAR_COMPILER_OBJS`：`.init_array` および `ulisp_globals_sec` の合成境界シンボル `__init_array_start/end`, `__start/stop_ulisp_globals_sec` を含む）が `ulisp --ld` で正常にリンクされ、実行可能であること。
- [ ] 先行 Issue #783 の `ulisp --as` と本 Issue の `ulisp --ld` を組み合わせたパイプライン（`ulisp --as input.s -o input.o && ulisp --ld input.o ulisp_stdlib.o -o bin`）が、外部の `as` および `ld` なしに完走すること。
- [ ] テストスクリプト `ulisp/tests/test_builtin_ld.sh`（`make -C ulisp test_builtin_ld`）の全検証項目が 100% PASS すること。
- [ ] ルート品質ゲート（`make check_format static_analysis py_compile`）がエラー 0 件で通過すること。
- [ ] 全ドキュメント内の内部リンクが相対パス規則に 100% 準拠していること。
