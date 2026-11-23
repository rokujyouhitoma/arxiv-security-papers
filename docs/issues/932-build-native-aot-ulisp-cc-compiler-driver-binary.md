---
ID: 932
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C99 コンパイラドライバ (`ulisp-cc`) のネイティブ AOT バイナリ化と高速セルフホスト実行基盤の構築 (ID: 932)

## 1. 概要 / Summary

[Issue #924](closed/924-verify-sse2-xmm-abi-and-floating-point-differential-fuzzing.md) における 500 ケース（6,503 行 / 248 KB）浮動小数点差分ファジングのステージ別プロファイリングにより、C99 コンパイルパイプラインのレキサ・パーサ・Nanopass 検証・ELF ビルドのアルゴリズム的最適化後も、**コンパイラ自体をホストインタプリタ（`gosh` / Python `ilisp`）上で実行していることによるインタプリタ実行・起動オーバーヘッド**が最大の残存コストであることが判明した。

本 Issue では、ULisp C99 コンパイラドライバ一式（`compiler_passes.scm` + `vm/lir_interpreter.scm` + `peg/` + `frontend_c/` + `driver/c_driver.scm`）を **ULisp 自身（`ulisp-boot` / `stage2`）でネイティブ x86-64 AOT コンパイルし、スタンドアロン実行バイナリ `ulisp/bin/ulisp-cc` を構築**する。これにより、Lua 5.x 一括ビルド（[#925](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md)）・公式テスト完走（[#926](closed/926-verify-lua-5x-official-test-suite-e2e-selfhost-ci.md)）・PCH/mem2reg 高速化（[#927](927-implement-c-header-sbi-pch-and-iterative-mem2reg-optimization.md)）・CI テスト群のコンパイルスループットをさらに **5〜10 倍** 高速化し、インタプリタ起動ボトルネックを根本解消する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33-32](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md) (Lua C コードベースコンパイル・セルフホストアーキテクチャ)
  - [DSN-33-13](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md) (Typed Machine LIR & マルチターゲットバックエンド)
  - [DSN-33-12](../designs/DSN-33-12-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (パイプライン ＆ パス建築仕様)
- 関連 Issue:
  - [#917](closed/917-implement-c-compiler-driver-and-host-ld-integration.md) (C コンパイラドライバ `c_driver.scm` 基盤)
  - [#924](closed/924-verify-sse2-xmm-abi-and-floating-point-differential-fuzzing.md) (本改善の契機となった C99 パイプラインプロファイリング ＆ O(N^2) 解消)
  - [#925](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (Lua 5.x C コードベース一括ビルド)
  - [#927](927-implement-c-header-sbi-pch-and-iterative-mem2reg-optimization.md) (`.sbi` PCH ＆ mem2reg 最適化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [c_driver.scm](../../ulisp/driver/c_driver.scm) (CLI 引数・`process-exec`・ファイル I/O の ULisp ネイティブ `(cond-expand (ulisp ...))` 完全対応)
- [ ] [compiler_entry.scm](../../ulisp/compiler_entry.scm) / 新規ドライバエントリ（例: `ulisp/c_driver_entry.scm`）
- [ ] [peg.scm](../../ulisp/peg.scm) / [parser.scm](../../ulisp/frontend_c/parser.scm) (`tools/grammars/c99.peg` パス解決・プリキャッシュの AOT 互換性検証)
- [ ] [preprocessor.scm](../../ulisp/frontend_c/preprocessor.scm) (組み込みヘッダ・ローカル `set!` ゼロ・AOT ランタイム互換確認)
- [ ] [Makefile](../../ulisp/Makefile) (`bin/ulisp-cc` ビルドターゲットおよび C99 テストハーネスでの優先利用オプション追加)
- [ ] 新規検証スクリプト / テスト（`ulisp-cc` バイナリの `gosh`/`ilisp` 出力バイト一致確認・ベンチマーク計測）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/932-build-native-aot-ulisp-cc-binary`

1. （`polish-issue` フェーズにて、C99 フロントエンド・PEG・VM 全モジュールの ULisp AOT コンパイル適合性監査〔残存ローカル `set!`・可変長引数・`cond-expand (ulisp ...)`・`process-exec` システムコール実装・GC アリーナ設定〕および詳細手順を策定する。）

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `make -C ulisp bin/ulisp-cc`（または同等ターゲット）がエラー・警告なくネイティブ ELF64 実行バイナリを生成し、`ulisp/bin/ulisp-boot` と分離されたクリーンな生成物として再現可能であること。
- [ ] `ulisp-cc` ネイティブバイナリが全既存 C99 E2E テスト（`test_c99_e2e`, `test_c99_floating_point`, `test_sse2_xmm_abi`, `test_fuzz_xmm_float` 等）で `gosh`/`ilisp` 版と **100% 同一の出力・終了コード** を返すこと。
- [ ] 大規模入力（例: `FUZZ_COUNT=500`）に対して `gosh` / `ilisp` 実行比で顕著な高速化（目標 5〜10 倍以上）が実測確認されること。
- [ ] 全 `.scm` 変更ファイルでローカル `set!` ゼロ件・`verify_zero_gauche`・`lint_sexpr`・全回帰ゲートが PASS すること。
