---
ID: 895
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Implement Direct Cogen Driver and Compiler CLI Generator (ID: 895)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 4 章に基づき、第2二村射影（Direct Cogen）を実用化し、評価器定義ファイルから外部依存ゼロの専用 AOT コンパイラ単一バイナリ CLI（例: `bin/my-langc`）をワンコマンドで自動生成するビルドドライバ `ulisp-cogen` を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-04] ULisp 言語ワークベンチ設計書 (第4章 第2二村射影によるスタンドアロン CLI コンパイラ自動生成)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-33-03] ULisp ステージ多相メタコンパイラ ＆ 二村射影フラクタル実行基盤設計書](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
  - [[Issue #890] Integrate Freeze-Serialized Rodata into ELF Emitter](closed/890-integrate-freeze-serialized-rodata-into-elf-emitter.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/workbench/cogen.scm](../../ulisp/workbench/cogen.scm)
- [ ] [ulisp/bin/ulisp-cogen](../../ulisp/bin/ulisp-cogen)
- [ ] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm)
- [ ] [ulisp/tests/test_workbench_cogen.scm](../../ulisp/tests/test_workbench_cogen.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/895-implement-direct-cogen-driver-and-compiler-cli-generator`

1. 評価器 AST からコンパイラ走査コードを導出する Direct Cogen アルゴリズムを `ulisp/workbench/cogen.scm` に実装。
2. コマンドラインツール `ulisp-cogen` を作成し、文法規則・オブジェクトモデル・評価器定義から専用 CLI ドライバの Scheme コードを自動合成。
3. `freeze-serialize-to-rodata` を用いて、文法オートマトンや組み込み辞書を ELF `.rodata` セクションに直接ベイクしてコンパイル。
4. 単体・結合テスト `test_workbench_cogen.scm` を作成し、生成された CLI が独立したバイナリとして正しくソースをコンパイルできることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp-cogen` コマンドが評価器定義から単一バイナリ CLI を正常に出力できること。
- [ ] 出力された CLI バイナリが外部依存なしに 0ms 起動し、ユーザースクリプトをネイティブ ELF へコンパイルできること。
- [ ] `make -C ulisp test_workbench_cogen` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
