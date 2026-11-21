---
ID: 917
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] C コンパイラドライバ (`c_driver.scm`) およびホストリンカ連携による整数 C E2E 開通 (ID: 917)

## 1. 概要 / Summary
`-I`, `-D`, `-U`, `-E`, `-S`, `-c`, `-o` 等の標準 C コンパイラオプションを解釈し、`preprocessor.scm`（#914）→ `parser.scm`（#915/#931）→ `sema.scm` / `lower_to_lir.scm`（#916）→ Pass 132 Braun SSA → Pass 140 x86-64 / Pass 144a（ELF `.o` 出力）およびシステム `ld` / `cc`（ホスト libc 連携）までを統合実行する C コンパイラドライバ（`ulisp/driver/c_driver.scm`）を実装する（Phase S2 / Task T5）。これにより、実ハードウェア上で動作するネイティブ ELF C バイナリの E2E 実行を開通させる。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §5.1, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §2.1, §4.1](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §5.1, §5.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#829`: SysV ABI 呼出規約（[ulisp/compiler/calling_convention.scm](../../ulisp/compiler/calling_convention.scm)）
  - `#830`: ELF セクション/再配置・Pass 140/144a（[ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm), [ulisp/backend/144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm), [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm)）
  - `#831`: Pass 160 Portable C バックエンド（[ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm)）
  - `#914`: C99 CPP（[ulisp/frontend_c/preprocessor.scm](../../ulisp/frontend_c/preprocessor.scm), [[#914]](closed/914-implement-pure-scheme-c99-preprocessor-cpp.md)）
  - `#915`: C99 Parser ＆ `L_c_ast`（[[#915]](915-implement-c99-parser-and-nanopass-c-ast-definitions.md)）
  - `#916`: C99 Sema Core ＆ 整数 Lowering（[[#916]](916-implement-c99-sema-core-and-integer-subset-lir-lowering.md)）
- 後続連携 Issue:
  - [[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (Lua 一括ビルド), [[#928]](928-compile-musl-libc-with-ulisp-and-migrate-to-pass-144-elf-linker.md) (Pass 144 静的リンク移行), [[#930]](930-implement-c99-bounds-checking-sanitizer-mode.md) (`--sanitize-bounds`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/driver/c_driver.scm` (新規: CLI 引数解析 `<c-driver-options>` ＆ 翻訳単位パイプライン統括)
- [ ] `ulisp/tests/test_c99_e2e_hello.sh` (新規: `printf("%d\n", 42)`・分割コンパイル `.c`→`.o`→ELF の E2E 検証スクリプト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_e2e` ターゲットおよび `test` 集約への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/917-implement-c-compiler-driver-and-host-ld`

### 4.1 CLI 引数解析 ＆ パイプライン API (`ulisp/driver/c_driver.scm`)
1. **`<c-driver-options>` レコード ＆ フラグパーサ `(parse-c-driver-args argv)`**:
   - サポートフラグ: `-E`（CPP のみ・テキスト出力）, `-S`（x86-64 `.s` または `.c` 出力）, `-c`（Pass 144a による ELF `.o` 出力）, `-o <out>`, `-I <dir>` / `-I<dir>`, `-isystem <dir>`, `-D <macro>` / `-D<macro>`, `-U <macro>`, `-l<lib>`, `-L<dir>`, `-O0`/`-O1`/`-O2`, `--target=x86_64|c|vm`, `--sanitize-bounds`（将来の #930 接続用フック）。
2. **翻訳単位コンパイル関数 `(c-compile-translation-unit src-file out-obj opts)`**:
   - `make-default-cpp-context` へ `-I`/`-isystem`/`-D`/`-U` を設定 → `cpp-preprocess-file` → `parse-c99-tokens` → `c99-analyze-program` → `c99-lower-to-lir` → Pass 132 Braun SSA → Pass 140/144a（ELF `.o` バイト列出力）または Pass 160（C 出力）。
3. **ホストリンカ連携 (Step S2〜S5 裁定規準 J2)**:
   - 最終実行可能バイナリ生成時、すべての `.o`（既存 `.o` 入力含む）、`-L`、`-l` をシステム `cc` / `ld` へ安全に引き渡してリンクする。

### 4.2 セキュリティ ＆ 堅牢性設計
1. **シェルインジェクション防止 (CWE-78)**:
   - `-o`, `-I`, 入力ファイルパス等をシステムリンカへ渡す際、シェルコマンド文字列連結ではなくエスケープ／引数配列または厳格な文字検証（制御文字・メタキャラクタ拒否）を通過させる。
2. **診断コード (`diagnostic.scm` #833)**:
   - `"C99-DRV-001"`（入力ファイル未指定・存在しないファイル）、`"C99-DRV-002"`（不正 CLI フラグまたは引数欠損）、`"C99-DRV-003"`（リンカ終了コード非 0 によるリンク失敗）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `printf("%d\n", 42)` や整数再帰関数を含む C99 プログラムを `c_driver.scm` でネイティブ ELF へコンパイル・リンクし、期待通りの標準出力・終了コードで実行できること。
- [ ] 複数 `.c` ファイルの分割コンパイル（`-c` による `.o` 生成と `-o` リンク）および `-E` / `-S` / `--target=c` モードが正常動作すること。
- [ ] Pass 140/144a ネイティブ実行結果と Pass 160 Portable C バックエンド出力結果が完全一致し、`ulisp/tests/test_c99_e2e_hello.sh` が全件 PASS すること。
