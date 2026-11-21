---
ID: 917
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C コンパイラドライバ (`c_driver.scm`) およびホストリンカ連携による整数 C E2E 開通 (ID: 917)

## 1. 概要 / Summary
`-I`, `-D`, `-U`, `-E`, `-S`, `-c`, `-o` 等の標準 C コンパイラオプションを解釈し、`preprocessor.scm` $\to$ `parser.scm` $\to$ `sema.scm` $\to$ `lower_to_lir.scm` $\to$ Pass 132/140/144a（ELF `.o` 出力）およびシステム `ld`（ホスト libc / musl リンク）までを統合実行する C コンパイラドライバ（`ulisp/driver/c_driver.scm`）を実装する（Step S2 / T5）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §5.1, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §2.1, §4.1](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §5.1, §5.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #829 (SysV ABI), #830 (ELF セクション/再配置), #914, #915, #916

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/driver/c_driver.scm` (新規: CLI 引数解析 ＆ 翻訳単位パイプライン統括)
- [ ] `ulisp/Makefile` (C コンパイルテストターゲット統合)
- [ ] `ulisp/tests/test_c99_e2e_hello.sh` (新規: `printf("%d\n", 42)` 等のネイティブ ELF E2E テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/917-implement-c-compiler-driver-and-host-ld`

1. `c_driver.scm` において複数 `.c` ソース入力、`-c`（再配置可能 ELF `.o` 生成）、`-o <out>`、`-I<dir>`、`-D<name>[=val]`、`-E`（プリプロセス出力）をサポートする。
2. 4大裁定規準（`DSN-33-32` §5.1）に基づき、Step S2〜S5 では Pass 144a で生成した `.o` ファイルをシステムの `ld` / `cc` と組み合わせてホスト libc（または musl）へリンクし、実行可能バイナリを出力する。
3. Pass 160 Portable C バックエンド経由の出力とネイティブ x86-64 バイナリの実行結果を比較検証する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `printf("%d\n", ...)` を含む整数 C プログラムを ULisp でコンパイル・リンクしたネイティブバイナリが正常終了すること。
- [ ] 複数 `.c` ファイルの分割コンパイル（`-c` による `.o` 生成とリンク）が動作すること。
- [ ] Phase S2 の完了条件（整数 C パイプライン開通）がテストで証明されること。
