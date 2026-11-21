---
ID: 896
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Implement Dual Source Span and Guest DWARF Debug Line Emitter (ID: 896)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 5 章に基づき、評価器実装のソース位置とユーザースクリプトのソース位置を二重管理する Dual Source Span を導入し、生成される ELF バイナリの DWARF `.debug_line` にユーザースクリプトのファイル名・行番号を自動バインドして、GDB/LLDB による透過的デバッグを可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-04] ULisp 言語ワークベンチ設計書 (第5章 ゲスト言語レベルのデバッグ透過性)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/diagnostic.scm](../../ulisp/compiler/diagnostic.scm)
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm)
- [ ] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm)
- [ ] [ulisp/tests/test_workbench_dwarf.scm](../../ulisp/tests/test_workbench_dwarf.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/896-implement-dual-source-span-and-guest-dwarf-debug-line-emitter`

1. `<dual-source-span>` レコード（`guest-file`, `guest-line`, `guest-col`, `interp-file`, `interp-line`, `interp-col`）を AST および LIR 命令に付与するプロトコルを確立。
2. ステージ多相簡約・残余化フェーズにおいて、評価器の Scheme 位置ではなくゲストスクリプト位置を優先して伝播。
3. `144_backend_x86_elf.scm` の DWARF `.debug_line` ステートマシンエミッタにおいて、ゲストスクリプトのファイルテーブルおよびディレクトリエントリを出力。
4. 単体テスト `test_workbench_dwarf.scm` を作成し、`readelf --debug-dump=decodedline` でゲスト言語の行番号が正確に反映されていることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Dual Source Span が LIR から ELF DWARF `.debug_line` まで欠損なく伝播すること。
- [ ] GDB で生成バイナリを実行した際に、ユーザースクリプトの行単位でブレークポイントやステップ実行ができること。
- [ ] `make -C ulisp test_workbench_dwarf` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
