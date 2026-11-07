---
ID: 772
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ULisp 標準ライブラリ (ULISP_STD_LIBS) の事前コンパイル済みオブジェクト化と分割静的リンクへの統一 (ID: 772)

## 1. 概要 / Summary

[ulisp/Makefile](../../ulisp/Makefile) の各ランタイム・並行処理・R7RS テストターゲット（`test_runtime`, `test_arena`, `test_scheduler`, `test_numeric_tower` 等）において、毎回 `cat $(ULISP_STD_LIBS) test_xxx.scm > build/test_xxx_input.scm` によって **28個の標準ライブラリファイルを結合し、ゼロから全 Nanopass パイプラインで再コンパイルしている問題** を解消する。
標準ライブラリを1回だけ事前コンパイルしたオブジェクトファイル（`build/ulisp_stdlib.o`）およびモジュールインターフェース（`.sbi`）としてキャッシュし、各テスト・アプリケーションは差分コードのみをコンパイルして `ld` で静的リンクする方式へ統一することで、コンパイル時間を劇的に短縮する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 依存関係:
  - 先行・関連 Issue: [Issue #607](closed/607-implement-modular-2-split-static-linking-for-ulisp-stdlib-and-compiler.md), [Issue #608](closed/608-implement-separate-compilation-and-incremental-build-for-ulisp.md), [Issue #771](771-optimize-ulisp-host-compiler-seed-and-batch-pass-test-runner.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [ulisp/stdlib_entry.scm](../../ulisp/stdlib_entry.scm)
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking`

1. **標準ライブラリオブジェクト（`build/ulisp_stdlib.o`）の共通依存化**:
   - `ULISP_STD_LIBS` に変更がない限り `build/ulisp_stdlib.o` を1度だけ生成して再利用する Make 依存ルールを確立する。
2. **各テストターゲットの差分コンパイル＋静的リンク移行**:
   - `test_runtime`, `test_arena`, `test_atomic` 等の各ターゲットで毎回 `ULISP_STD_LIBS` 全体をソース結合する方式から、テスト本体のみをコンパイルして `build/ulisp_stdlib.o` と `$(LD)` で静的リンクする方式に移行する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `ULISP_STD_LIBS` 未変更時に2回目以降のテストターゲットビルドで標準ライブラリの再コンパイルが発生しないこと。
- [ ] `make -C ulisp test` および `make -C ulisp test_concurrency` の全テストが 100% PASS し、トータルコンパイル時間が大幅に短縮されること。
- [ ] `make check` / `make verify_quality` がエラー 0 件で PASS すること。

