---
ID: 917
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-22
---

# [FEAT/ENH] C コンパイラドライバ (`c_driver.scm`) およびホストリンカ連携による整数 C E2E 開通 (ID: 917)

## 1. 概要 / Summary
`-I`, `-D`, `-U`, `-E`, `-S`, `-c`, `-o` 等の標準 C コンパイラオプションを解釈し、`preprocessor.scm`（#914）→ `parser.scm`（#915/#931）→ `sema.scm` / `lower_to_lir.scm`（#916）→ Pass 132 Braun SSA → Pass 140 x86-64 / Pass 144a（ELF `.o` 出力）およびシステム `ld` / `cc`（ホスト libc 連携）までを統合実行する C コンパイラドライバ（`ulisp/driver/c_driver.scm`）を実装する（Phase S2 / Task T5）。これにより、実ハードウェア上で動作するネイティブ ELF C バイナリの E2E 実行を開通させる。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §5.1, §6.1](../../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §2.1, §4.1](../../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §5.1, §5.2](../../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#829`: SysV ABI 呼出規約（[ulisp/compiler/calling_convention.scm](../../../ulisp/compiler/calling_convention.scm)）
  - `#830`: ELF セクション/再配置・Pass 140/144a（[ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm), [ulisp/backend/144a_x86_assembler.scm](../../../ulisp/backend/144a_x86_assembler.scm), [ulisp/backend/elf64_builder.scm](../../../ulisp/backend/elf64_builder.scm)）
  - `#831`: Pass 160 Portable C バックエンド（[ulisp/backend/160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm)）
  - `#914`: C99 CPP（[ulisp/frontend_c/preprocessor.scm](../../../ulisp/frontend_c/preprocessor.scm), [[#914]](914-implement-pure-scheme-c99-preprocessor-cpp.md)）
  - `#915`: C99 Parser ＆ `L_c_ast`（[[#915]](915-implement-c99-parser-and-nanopass-c-ast-definitions.md)）
  - `#916`: C99 Sema Core ＆ 整数 Lowering（[[#916]](916-implement-c99-sema-core-and-integer-subset-lir-lowering.md)）
- 後続連携 Issue:
  - [[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (Lua 一括ビルド), [[#928]](../928-compile-musl-libc-with-ulisp-and-migrate-to-pass-144-elf-linker.md) (Pass 144 静的リンク移行), [[#930]](../930-implement-c99-bounds-checking-sanitizer-mode.md) (`--sanitize-bounds`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/driver/c_driver.scm](../../../ulisp/driver/c_driver.scm) (新規: CLI 引数解析 `<c-driver-options>`・翻訳単位パイプライン統括・マルチ TU LIR マージ・CWE-78 引数検証)
- [x] [ulisp/tests/test_c99_e2e_hello.scm](../../../ulisp/tests/test_c99_e2e_hello.scm) (新規: CLI パース・CWE-78 / `C99-DRV-001..003`・Pass 144a 16-bit/movsx/movsxd・`--target=vm` 検証 28/28 PASS)
- [x] [ulisp/tests/test_c99_e2e_hello.sh](../../../ulisp/tests/test_c99_e2e_hello.sh) (新規: `printf("%d\n", 42)`・分割コンパイル `.c`→`.o`→ELF・3者一致検証 14/14 PASS)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`build/c_driver_runner.scm`, `test_c99_e2e` ターゲットおよび `test` 集約への登録)
- [x] [ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm) (`'c-tu` モード・`.init_array`・`.rodata` C 文字列・`.bss` グローバル・狭幅ロード/ストア拡張)
- [x] [ulisp/backend/144a_x86_assembler.scm](../../../ulisp/backend/144a_x86_assembler.scm) (16-bit レジスタ・`word ptr`・`movsx`・`movzx`・`movsxd` エンコード追加)
- [x] [ulisp/backend/160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm) (`'c-tu` モード対応・`%c-call` / `%direct-call` / 狭幅メモリアクセス対応)
- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm) / [ulisp/lir/133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm) / [ulisp/compiler.scm](../../../ulisp/compiler.scm) (`%store-typed` エイリアス検知・`%call-foreign` バリア対応)
- [x] [ulisp/frontend_c/parser.scm](../../../ulisp/frontend_c/parser.scm) / [ulisp/peg/runtime.scm](../../../ulisp/peg/runtime.scm) / [ulisp/peg/compiler/codegen.scm](../../../ulisp/peg/compiler/codegen.scm) / [ulisp/peg/compiler/parser.scm](../../../ulisp/peg/compiler/parser.scm) (C99 パーサー・PEG コード生成関連調整)
- [x] [ulisp/bin/ulisp-boot](../../../ulisp/bin/ulisp-boot) (3段モジュラーセルフホストブートストラップ再同期済みシードバイナリ)
- [x] [ilisp/env.py](../../../ilisp/env.py) / [ilisp/port.py](../../../ilisp/port.py) (`process-exec` プリミティブ追加・バイナリポートの `MutableString` ファイルパス対応)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/917-implement-c-compiler-driver-and-host-ld`

### 4.1 CLI 引数解析 ＆ パイプライン API (`ulisp/driver/c_driver.scm`)
1. **`<c-driver-options>` レコード ＆ フラグパーサ `(parse-c-driver-args argv)`**:
   - サポートフラグ: `-E`（CPP のみ・テキスト出力）, `-S`（x86-64 `.s` または `.c` 出力）, `-c`（Pass 144a による ELF `.o` 出力）, `-o <out>`, `-I <dir>` / `-I<dir>`, `-isystem <dir>`, `-D <macro>` / `-D<macro>`, `-U <macro>`, `-l<lib>`, `-L<dir>`, `-O0`/`-O1`/`-O2`, `--target=x86_64|c|vm`, `--sanitize-bounds`（将来の #930 接続用フック）。
2. **翻訳単位コンパイル関数 `(c-compile-translation-unit src-file out-obj opts)`**:
   - `make-default-cpp-context` へ `-I`/`-isystem`/`-D`/`-U` を設定 → `cpp-preprocess-file` → `parse-c99-tokens` → `c99-analyze-program` → `c99-lower-to-lir` → Pass 133 ピープホール（`-O1`/`-O2`）→ Pass 140/144a（ELF `.o` バイト列出力）または Pass 160（C 出力）。
3. **ホストリンカ連携 (Step S2〜S5 裁定規準 J2)**:
   - 最終実行可能バイナリ生成時、すべての `.o`（既存 `.o` 入力含む）、`-L`、`-l` をシステム `cc` / `ld` へ安全に引き渡してリンクする。

### 4.2 セキュリティ ＆ 堅牢性設計
1. **シェルインジェクション防止 (CWE-78)**:
   - `-o`, `-I`, 入力ファイルパス等をシステムリンカへ渡す際、シェルコマンド文字列連結ではなくエスケープ／引数配列または厳格な文字検証（制御文字・メタキャラクタ拒否）を通過させる。
2. **診断コード (`diagnostic.scm` #833)**:
   - `"C99-DRV-001"`（入力ファイル未指定・存在しないファイル）、`"C99-DRV-002"`（不正 CLI フラグまたは引数欠損）、`"C99-DRV-003"`（リンカ終了コード非 0 によるリンク失敗）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `printf("%d\n", 42)` や整数再帰関数を含む C99 プログラムを `c_driver.scm` でネイティブ ELF へコンパイル・リンクし、期待通りの標準出力・終了コードで実行できること。
- [x] 複数 `.c` ファイルの分割コンパイル（`-c` による `.o` 生成と `-o` リンク）および `-E` / `-S` / `--target=c` モードが正常動作すること。
- [x] Pass 140/144a ネイティブ実行結果と Pass 160 Portable C バックエンド出力結果が完全一致し、`ulisp/tests/test_c99_e2e_hello.sh` が全件 PASS すること。

### 検証結果サマリー (2026-11-22)
- `make -C ulisp test_c99_e2e`: 単体 28/28 PASS ＆ E2E 14/14 PASS
- `make -C ulisp build/ulisp-modular` / `bootstrap_verify_modular`: 5 モジュール `stage2 == stage3` ビット一致 PASS（`ulisp_gvar_set_excl` リンクエラー解消済み）
- `make -C ulisp test_c`: 143/143 PASS / `make -C ulisp test_builtin_as`: 6/6 PASS
- ULisp 回帰スイート（`verify_zero_gauche`, `test_lint_sexpr` 23/23, `test_differential_elf` 13/13, `test_elf_sections_and_reloc` 64/64, `test_sysv_abi_calls`, `test_lir`, `test_passes`, `test_peg`, `test_c99_lexer` 75/75, `test_c99_preprocessor`, `test_c99_parser` 21/21, `test_c99_int_lowering`, `test_aot` Phase 1〜7）: 全件 PASS
- Python 品質ゲート（`make check_format`, `make static_analysis`, `pytest` 450 passed）: 全件 PASS
