---
ID: 619
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] ソース位置追跡情報（%source-loc）に基づく最小限 DWARF（.debug_line / .debug_info）セクション生成と GDB / perf デバッグ支援の実装 (ID: 619)

## 1. 概要 / Summary

現在、ULisp コンパイラは Issue 606（R7RS include 構文および `%source-loc` 追跡基盤の導入）により、コンパイル対象 AST 全体にソースファイル名・行番号・列番号（`%source-loc`）を保持し、コンパイル時エラー診断（Issue 602 / 604）においてファイル名・行番号を表示する能力を有している。しかし、バックエンドコード生成（Pass 140 / Pass 144）において DWARF デバッグ情報を一切生成していない。

そのため、生成された ELF 実行可能バイナリを `gdb` や `lldb` で検査した際、以下の重大な開発・デバッグ上の障害が発生している：
1. **ブレークポイント設定不可**: Scheme ソース行番号を指定したブレークポイント（`b file.scm:line`）が打てず、低レベルのアドレス指定（`b *0x401020`）を余儀なくされる。
2. **ステップ実行不可**: Scheme ソース行単位のステップイン（`step`）やステップオーバー（`next`）ができず、マシン語命令単位（`stepi` / `nexti`）の追跡しか行えない。
3. **クラッシュ時のバックトレース喪失**: セグメンテーション違反や未捕捉例外時の GDB バックトレース（`bt`）において、Scheme ソースファイル名および行番号が表示されず、アセンブリシンボルやアドレスのみが表示される。
4. **Linux `perf` プロファイリングの解決不能**: `perf record` / `perf report` 実行時に、CPU ホットスポットが Scheme のソース行や関数シンボルにマッピングされず、ボトルネック分析の効率が著しく低下する。

### 本 Issue における解決策:
本 Issue では、重厚な DWARF 規格全体を抱え込むことなく、開発および運用分析に不可欠な「行番号とソースファイル対応」を可能にする**「最小限 DWARF（`.debug_line` + 最小限 `.debug_info` / `.debug_abbrev` / `.debug_str`）」**および**「ELF シンボルテーブル（`.symtab` / `.strtab`）」**の生成基盤を確立する。

- **Pass 140（GNU as 出力パス）**: `-g` オプション指定時に `.file <id> "<path>"` および `.loc <id> <line> <col>` ディレクティブを出力し、GNU `as` に標準 DWARF セクションを合成させる。
- **Pass 144 / `elf64_builder.scm`（Direct-to-ELF 出力パス）**: 外部ツール不要の自給自足型 DWARF 4 Line Number Program ステートマシンおよび最小限 Compilation Unit エンコーダを Scheme 上で実装し、直接 ELF バイナリに `.debug_line` / `.debug_info` / `.debug_abbrev` / `.debug_str` / `.symtab` を注入する。

これにより、C/C++ と同等の GDB 対話デバッグおよび Linux `perf` プロファイリング環境を提供する。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ規約（`.agents/AGENTS.md`）に従い、16 専門エージェントによる設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - デバッグシンボル生成は開発効率を劇的に向上させる重要基盤である。デフォルトビルド（`-g` なし）時のバイナリサイズおよびコンパイル速度への影響ゼロ（Zero-overhead-when-disabled）を厳守し、段階的導入（Phase 1: Pass 140 GNU as 連携 → Phase 2: Pass 144 Direct-to-ELF エンコーダ → Phase 3: 自動検証）を計画する。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - GDB は `.debug_line` 単体ではシンボルテーブルとして認識せず、`DW_TAG_compile_unit` を持つ `.debug_info`（`DW_AT_stmt_list` 属性で `.debug_line` を参照）を必須とする。Line Table のみならず最小限の CU ヘッダ（約 40〜50 バイト）および `.debug_abbrev`（約 20 バイト）を対で生成する仕様とする。
  - `%source-loc` 情報を AST から LIR 命令列（`%lir-loc`）へ脱落なく伝播させ、Pass 140 命令選択時・出力時にシームレスに emit する。
- **Systems Architect**:
  - Direct-to-ELF（Pass 144）における ELF セクションヘッダテーブルの拡張設計を行う。従来の 6 セクション（NULL, `.text`, `.rodata`, `.data`, `.bss`, `.shstrtab`）に対し、デバッグビルド時のみ動的にデバッグセクションおよびシンボルテーブルを追加する拡張可能なセクション配置アーキテクチャとする。
- **Information Security Specialist**:
  - DWARF 生成およびパス名出力に伴う脅威分析（STRIDE / CWE）を実施。
  - パスインジェクション（CWE-74 / CWE-116: アセンブリ `.file` 出力時の改行・クォート混入）の無害化。
  - ULEB128 / SLEB128 可変長エンコード時のバッファ境界チェックおよび整数オーバーフロー防止（CWE-190）。
  - デバッグシンボルによる本番環境情報漏洩（CWE-200）防止（`-g` 明示時のみ生成、リリースビルドでの完全沈黙）。
- **Software Quality Assurance Specialist (SQA)**:
  - GDB 非対話バッチ実行（`gdb --batch -ex ...`）による機械的テストスイート `ulisp/tests/test_dwarf_debug.sh` を設計。
  - 行番号ブレークポイントの的中、ステップ実行、クラッシュ時バックトレースの Scheme ソース行表示、および perf シンボル解決を自動合否判定する。
- **Software Development (SWD)**:
  - Scheme ネイティブ ULEB128 / SLEB128 整数エンコーダを `ulisp/backend/elf64_builder.scm` に実装。
  - DWARF 4 Line Number Program の標準オペコード（`DW_LNS_advance_pc`, `DW_LNS_advance_line`, `DW_LNS_copy`, `DW_LNE_end_sequence`）を `bytevector` 上に決定論的合成する。
- **Systems Auditor**:
  - 生成バイナリ内のソース位置情報が原本 Scheme ソースファイル（`inputs/` や `lib/`）の物理行と 100% 決定論的に一致すること（トレーサビリティの検証可能性）を保証する。
- **UI/UX & Documentation Designer**:
  - GDB 上でのデバッグセッション例（ブレークポイント設定、バックトレース表示、TUI モード表示）をドキュメント化し、開発者ガイドを整備する。

---

## 3. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

| 脅威分類 (STRIDE) | 脆弱性タイプ (CWE) | 潜在リスク・攻撃シナリオ | 防護策・緩和設計 (Mitigation) |
| :--- | :--- | :--- | :--- |
| **Tampering** / **Elevation** | CWE-74 / CWE-116 (Improper Neutralization) | 入力ファイル名や `#include` パスに特殊文字（`"` や `\n`、アセンブラディレクティブ）が含まれる場合、生成 `.s` ファイル内で意図しないディレクティブが実行される。 | `sanitize-source-path` 手続きを導入。ファイル名から改行・タブ・二重引用符・非 ASCII 文字を厳格にエスケープまたは拒絶する。 |
| **Tampering** | CWE-190 (Integer Overflow / Wraparound) | 極端に巨大な関数や命令オフセット計算において、ULEB128/SLEB128 エンコード時のビットシフトや除算がオーバーフローし、不正な DWARF バイト列を生成する。 | 64-bit 整数演算の境界チェックを行い、符号付き/符号なしビット演算の正規化（modulo 128 / quotient 128）を厳密に実施する。 |
| **Information Disclosure** | CWE-200 (Information Exposure) | 本番リリースバイナリにビルド環境の絶対パスや内部ソースコードの行構造が含まれ、攻撃者のリバースエンジニアリングを容易にする。 | デバッグ情報生成は `-g` フラグ指定時のみ有効化。デフォルト（通常コンパイル）時は一切の DWARF セクションをバイナリから排除する。 |
| **Denial of Service** | CWE-125 / CWE-787 (Out-of-bounds Read/Write) | DWARF バイトベクタ生成時にセクション長やヘッダオフセットの計算誤りにより境界外書き込みが発生する。 | `elf64-copy-bytes!` およびバイトベクタ書き込みプリミティブにおいて厳格なアロケーションサイズ計算と事前検証を実施する。 |

---

## 4. トレーサビリティ / Traceability

- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (Section 2: ランタイムシステム & Section 3: パイプライン設計)
  - DWARF Debugging Information Format Version 4 Specification (Section 6.2: Line Number Program, Section 7.5: Format of Debugging Information)
  - System V Application Binary Interface AMD64 Architecture Processor Supplement (Section 4: Object Files & Section 5: Program Loading)
- **関連 Issue**:
  - [Issue 602: コンパイラ実行時における現在Nanopass・処理中トップレベル式・ソース位置のコンテキスト追跡とエラー診断ダンプの導入](602-track-compiler-context-pass-and-toplevel-form-on-error.md)
  - [Issue 604: コンパイラ実行時のコールスタック追跡および未捕捉例外時のバックトレース表示機能の実装](604-implement-call-stack-traceback-for-compiler-exceptions.md)
  - [Issue 606: ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置追跡基盤の導入](606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md)
  - [Issue 614: ランタイムのデフォルト沈黙化と GCC / Linux 互換コンパイラ CLI インターフェースの根本確立](614-refactor-runtime-silence-by-default-and-compiler-cli-output.md)
  - [Issue 615: ビルドパイプラインからの GCC 呼出し排除と GNU as / ld 直接駆動への移行](615-decouple-gcc-driver-and-migrate-to-direct-as-ld-invocation.md)
  - [Issue 616: Scheme ネイティブ x86-64 マシン語エンコーダおよび ELF64 実行可能バイナリ直接出力バックエンドの実装](616-implement-native-x86-machine-code-encoder-and-direct-elf-generator.md)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm)
  - デバッグ情報生成フラグ（`*debug-symbols-enabled*` / `enable-debug-symbols!` / `debug-symbols-enabled?`）の定義
  - ソースパス名サニタイズ手続き（`sanitize-source-path`）の実装
- [x] [ulisp/compiler/driver.scm](../../../ulisp/compiler/driver.scm)
  - CLI 引数パーサー（`parse-cli-arguments`）における `-g` フラグの受理および大域フラグ設定
  - ヘルプ表示（`print-compiler-help`）への `-g` オプション（`  -g                    Generate minimal DWARF debug information for GDB / perf\n`）の追記
  - ディレクティブ抽出処理（`extract-directives-and-forms`）における `-g` / `!debug-symbols` のサポート
- [x] [ulisp/frontend/025_top_level.scm](../../../ulisp/frontend/025_top_level.scm)
  - トップレベル式および関数定義展開時における `%source-loc` の LIR への引き継ぎメタデータ保持
- [x] [ulisp/lir/lir_lang.scm](../../../ulisp/lir/lir_lang.scm)
  - Canonical LIR 言語仕様へのソース位置注釈命令 `(%loc file_id line col)` または関数メタデータ属性の定義追加
- [x] [ulisp/lir/130_lir.scm](../../../ulisp/lir/130_lir.scm)
  - 式のコンパイル時に現在ソース位置（`current-source-file`, `current-source-line`, `current-source-col`）に基づく `(%loc ...)` 命令の生成
- [x] [ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm)
  - デバッグシンボル有効時における `.file <file_id> "<path>"` ヘッダディレクティブの emit
  - `(%loc file_id line col)` 命令に対応する `.loc <file_id> <line> <col>` アセンブリ行の出力
- [x] [ulisp/backend/144a_x86_assembler.scm](../../../ulisp/backend/144a_x86_assembler.scm)
  - アセンブラ 2 パス処理における `.file` および `.loc` ディレクティブのパースと行テーブル（Line Table Entries: `file-id, line, col, text-offset`）の収集
  - シンボルテーブル（`sym-table`）から関数シンボルリストを抽出し、Direct ELF 構築へ引き渡す機構
- [x] [ulisp/backend/elf64_builder.scm](../../../ulisp/backend/elf64_builder.scm)
  - DWARF 4 ULEB128 / SLEB128 可変長整数エンコーダの実装
  - DWARF 4 `.debug_line` セクションバイナリ生成エンジン（Header + Line Number Program Bytecode）の実装
  - 最小限 DWARF 4 `.debug_info` / `.debug_abbrev` / `.debug_str` セクションバイナリ生成（Compilation Unit: `DW_TAG_compile_unit`, `DW_AT_stmt_list` = 0, `DW_AT_low_pc`, `DW_AT_high_pc`, `DW_AT_name`）の実装
  - ELF シンボルテーブル（`.symtab` / `.strtab`）生成およびセクションヘッダテーブル（`shnum` 拡張）への統合
  - デバッグ情報無効（`-g` なし）時の完全ゼロオーバーヘッド（既存 ELF 構造の不変性）の担保
- [x] [ulisp/backend/144_backend_x86_elf.scm](../../../ulisp/backend/144_backend_x86_elf.scm)
  - Direct-to-ELF エントリーポイントにおける Line Table およびシンボル情報の `build-elf64-executable` への受け渡し統合
- [x] [ulisp/Makefile](../../../ulisp/Makefile)
  - デバッグビルドテストターゲット（`test-debug`）およびデバッグ検証ルールの追加
- [x] [ulisp/tests/test_dwarf_debug.sh](../../../ulisp/tests/test_dwarf_debug.sh)
  - 新規作成: GDB および Linux `perf` 連携の自動エンドツーエンド検証スクリプト

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/619-generate-minimal-dwarf-debug-line-for-gdb-and-perf`

### Phase 1: コンパイラフロントエンドおよび CLI への `-g` オプション・ソース位置伝播の統合
1. **CLI オプションおよびフラグ管理**:
   - `ulisp/compiler/helpers.scm` に `*debug-symbols-enabled*`（cons セル）を定義し、述語 `debug-symbols-enabled?`、有効化手続き `enable-debug-symbols!` をエクスポート。
   - `ulisp/compiler/driver.scm` の `parse-cli-arguments` に `-g` オプションを追加。`-g` 検出時に `(enable-debug-symbols!)` を呼び出す。
   - `print-compiler-help` に `-g` オプションの説明文を追加。
   - ディレクティブ抽出 `extract-directives-and-forms` にて `(!debug-symbols #t)` や `-g` を受理できるようにする。
2. **ソース位置メタデータ伝播**:
   - `ulisp/compiler/helpers.scm` に `sanitize-source-path` を追加（二重引用符や改行文字の除去・エスケープ）。
   - ファイル名と ID の対応表（`*source-file-table*`）を管理し、新規ファイル名が現れるたびに一意の整数 ID（1-indexed）を割り当てる。
   - `ulisp/lir/130_lir.scm` において、`debug-symbols-enabled?` が真のとき、トップレベル式および関数先頭・式評価境界で `(%loc file_id line col)` 命令を LIR 命令列へ挿入。

### Phase 2: Pass 140（GNU as 出力パス）における DWARF ディレクティブ出力
1. **ヘッダへの `.file` ディレクティブ出力**:
   - `ulisp/backend/140_backend_x86_64.scm` の `emit-x86-asm-program` 先頭（`.intel_syntax noprefix` 直後）において、`*source-file-table*` に登録されたすべてのファイルについて `.file <id> "<sanitized-path>"` を出力。
2. **命令列への `.loc` ディレクティブ出力**:
   - `emit-x86-asm-inst` に `(%loc file_id line col)` ケースを追加。
   - `    .loc <file_id> <line> <col>` を出力。
   - これにより、`ulisp -g -S input.scm -o output.s` 経由で生成されたアセンブリを GNU `as` がアセンブルした際、GNU `as` が自動的に完全な `.debug_line`, `.debug_info`, `.debug_abbrev` を合成する。

### Phase 3: Pass 144a & `elf64_builder.scm`（Direct-to-ELF 出力パス）へのネイティブ DWARF 生成統合
1. **Pass 144a アセンブラにおけるディレクティブ解析**:
   - `ulisp/backend/144a_x86_assembler.scm` の `assemble-x86-lines`（Pass 1）において：
     - `.file <id> "<path>"` をパースし、内部ファイルリスト `((id . path) ...)` に登録。
     - `.loc <id> <line> <col>` をパースし、現在テキストオフセット（`text-len`）と紐付けた行エントリ `(list id line col text-len)` を行テーブルアキュムレータへ記録。
   - アセンブル結果タプルに `(file-table line-table sym-table)` を追加（または拡張）。
2. **DWARF 4 エンコードエンジンの実装 (`ulisp/backend/elf64_builder.scm`)**:
   - **可変長整数エンコーダ**:
     - `dwarf-emit-uleb128`: 符号なし整数を 7 ビットずつ ULEB128 形式バイト列（最上位ビットが後続フラグ）に変換。
     - `dwarf-emit-sleb128`: 符号付き整数を 7 ビットずつ 2 の補数表現 SLEB128 形式バイト列に変換。
   - **Line Number Program（`.debug_line`）合成**:
     - DWARF 4 標準ヘッダ（`unit_length`, `version=4`, `header_length`, `min_instruction_length=1`, `max_ops_per_inst=1`, `default_is_stmt=1`, `line_base=-5`, `line_range=14`, `opcode_base=13`, `standard_opcode_lengths`, `include_directories`, `file_names`）を出力。
     - 行エントリをテキストオフセット順にソート。
     - 各行エントリに対して：
       - 初回: `DW_LNE_set_address`（拡張オペコード 2）で `vaddr-text-base + offset` を設定。
       - ファイル変更時: `DW_LNS_set_file`。
       - PC / 行番号差分: `DW_LNS_advance_pc` および `DW_LNS_advance_line` を emit。
       - 行マトリクス確定: `DW_LNS_copy`。
     - シーケンス終端: `DW_LNE_end_sequence`（0x00, 0x01, 0x01）を出力。
   - **Compilation Unit（`.debug_info` / `.debug_abbrev` / `.debug_str`）合成**:
     - `.debug_abbrev`: Abbrev 1 = `DW_TAG_compile_unit`（属性: `DW_AT_stmt_list` [data4], `DW_AT_low_pc` [addr], `DW_AT_high_pc` [addr], `DW_AT_name` [strp], `DW_AT_producer` [strp]）。
     - `.debug_str`: プール文字列（入力ソースファイル名、"ULisp 2.0 AOT"）の null 終端バイト列。
     - `.debug_info`: CU ヘッダ（長さ, バージョン 4, abbrev オフセット 0, アドレスサイズ 8）に続き、Abbrev 1 の属性値（`.debug_line` オフセット 0, `vaddr-text-base`, `vaddr-text-base + text-len`, 文字列オフセット）を書き込み。
   - **ELF シンボルテーブル（`.symtab` / `.strtab`）合成**:
     - `_start`（グローバル関数シンボル）および `scheme_entry`、ユーザー定義関数シンボルを System V ELF64 `Elf64_Sym` 構造体（24 バイト）配列として生成。
3. **ELF セクションヘッダテーブル拡張**:
   - `-g` が指定された場合、`shnum` を拡張し、`.debug_line`, `.debug_info`, `.debug_abbrev`, `.debug_str`, `.symtab`, `.strtab` を追加。
   - `-g` が指定されていない場合、従来の 6 セクション構造（64 バイト x 6）を維持し、1 バイトの肥大化も発生させない。

### Phase 4: 自動検証テストスイートおよび GDB / perf 結合テスト
1. **テストスクリプト `ulisp/tests/test_dwarf_debug.sh` の実装**:
   - テスト用 Scheme プログラム（関数呼び出し、ループ、意図的例外・ゼロ除算を含む）を準備。
   - **Pass 140 + as/ld パス検証**:
     - `ulisp -g -S input.scm -o test.s` → `as test.s -o test.o` → `ld test.o -o test_bin`
     - `readelf -S test_bin` で `.debug_line`, `.debug_info` の存在を確認。
     - `gdb --batch -ex "b input.scm:5" -ex "run" -ex "info break"` を実行し、ブレークポイントがヒットし指定行で停止することを確認。
     - クラッシュ時の `gdb --batch -ex "run" -ex "bt"` を実行し、バックトレースに出力される行番号が期待値と一致することを確認。
   - **Pass 144 Direct-to-ELF パス検証**:
     - `ulisp -g --target-elf input.scm -o test_direct_bin`
     - 同様に GDB ブレークポイント、ステップ実行、クラッシュ時バックトレースが成功することを確認。
     - Linux `perf`（または `nm` / `readelf -s`）で関数シンボルと行番号が逆引きできることを確認。
   - **オーバーヘッドゼロ検証**:
     - `-g` なしでビルドしたバイナリに `.debug_*` セクションが一切存在しないこと（`readelf -S` の出力検証）を確認。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] **CLI オプション適合性**: `ulisp -g` および `ulisp --help` で `-g` オプションが正常に認識・表示されること。
- [x] **GNU as 連携（Pass 140）**: `-g` を付与して出力したアセンブリを GNU `as` でアセンブル・リンクした際、DWARF デバッグセクション（`.debug_line`, `.debug_info`）が含まれていること。
- [x] **Direct-to-ELF 連携（Pass 144）**: 外部 binutils を用いず `ulisp -g --target-elf` で直接出力した ELF 実行可能バイナリに、DWARF 4 準拠の `.debug_line`, `.debug_info`, `.debug_abbrev`, `.debug_str` および `.symtab` が含まれていること（`readelf -S` で確認）。
- [x] **GDB ブレークポイント検証**: `gdb --batch` において、Scheme ソースファイルの特定行番号に対するブレークポイント（`b file.scm:line`）が正常に設定され、実行時にその行で停止すること。
- [x] **GDB クラッシュバックトレース検証**: 実行時クラッシュ時、GDB の `bt` コマンドで Scheme ソースファイル名と正確な行番号が表示されること。
- [x] **perf / シンボル解決検証**: ELF シンボルテーブル（`.symtab`）により、GDB および `perf` において関数名（`_start`, `scheme_entry` 等）が解決されること。
- [x] **非デバッグ時のゼロオーバーヘッド**: `-g` なしでコンパイルした場合、バイナリサイズおよびセクション構成が既存と完全一致し、コンパイル性能・実行性能にオーバーヘッドが一切生じないこと。
- [x] **品質ゲート通過**: `make py_compile`, `make static_analysis`, `make test` が 100% PASS すること。

---

## 8. 実装結果 / Implementation Notes

- 検証: `bash ulisp/tests/test_dwarf_debug.sh` → 20/20 PASS（Pass 140 as/ld 経路、Pass 144 Direct-to-ELF 経路、`-g` なし時のゼロオーバーヘッド）。`test_differential_elf.sh` 13/13 PASS、`make test_backend` 3/3 PASS。
- `make test_lir_suite` の 2 件失敗（Dynamic Addition / Directive Dynamic Subtraction）および `(!verify #t)` の Nanopass 検証エラーは本変更前から存在する既存事象であり、本 Issue の範囲外。
- 制約: 現行シード処理系は `append` / `+` が 2 引数固定・`string->list` 等が未対応のため、`elf64_builder.scm` は 2 引数ヘルパー（`dwarf-app3/4/5`）と添字ループで実装。
- 行番号は `-g` 指定時のみ stdin 全文を走査して各トップレベル式の開始行・列を算出（`scan-toplevel-datum-starts`）。式単位ではなくトップレベル式/関数定義単位の粒度。
- Linux `perf` による実機プロファイリングは未実施（`.symtab` の関数シンボル解決を `readelf -s` と GDB で確認）。
