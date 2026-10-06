---
ID: 487
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp x86-64 ネイティブ AOT コンパイラ基盤構築と Phase 1 (即値・単項演算) の実装 (ID: 487)

## 1. 概要 / Summary

[DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) に基づき、最底層（Underlying）ベアメタル x86-64 ネイティブ AOT コンパイラ **ULisp** の独立サンドボックス環境（`ulisp/`）を立ち上げ、Phase 1（即値・単項演算・述語: Step 1〜4）およびインクリメンタル自動テストパイプライン（*compilerbook* 準拠）を実装する。

将来的に ILisp (DSN-31) の「Backend B: Native AOT コンパイラ」として統合され、ILisp/ALisp で記述されたコードを外部依存ゼロのスタンドアロン x86-64 ELF 単一バイナリへと高速コンパイルするための最初の一歩となる。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 1 章, 第 2 章, 第 3.1 節, 第 4 章 Phase 1, 第 7 章)
  - [DSN-31: ILISP (Intelligence LISP) R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 3.2 節 Backend B)
  - [DSN-32: AILISP (ALisp + ILisp) 次世代AIコーディングエージェント実行環境包括的アーキテクチャ設計書](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) (第 1.2 節 二層分離)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (ULisp コンパイラ本体: Scheme -> x86-64 アセンブリ出力)
- [x] [ulisp/runtime.c](../../ulisp/runtime.c) (C言語製ミニマルランタイム: 16バイトスタック整列・Tagged Pointer 復元表示・終了コード制御)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (インクリメンタル自動テストランナー: assert 関数による実行検証)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (ビルド・テスト・クリーンアップ自動化)
- [x] [ulisp/README.md](../../ulisp/README.md) (ULisp クイックスタートおよびステップ進捗ログ)
- [x] [docs/issues/README.md](../../docs/issues/README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/487-initialize-ulisp-x86-native-aot-compiler-phase1`

1. **プロジェクト初期化 (`ulisp/`)**:
   - 既存の Python パイプラインや CI 品質ゲートから完全に隔離された独立サンドボックスとして `ulisp/` ディレクトリを整備。
   - `Makefile`, `runtime.c`, `test.sh`, `README.md` を作成。
2. **C ランタイム設計 (`runtime.c`)**:
   - System V AMD64 ABI 準拠の 16 バイトスタックアライメントを維持。
   - Tagged Pointer のデコード（Fixnum: `val >> 2`, Boolean: `#t` / `#f`, Char: `#\...`, Empty List: `'()`）と `printf` 表示。
3. **Step 1: 整数 1 個のコンパイル (`42`)**:
   - `42` -> `mov rax, 168` -> `ret`。`test.sh` で `assert "42" "42"` をパス。
4. **Step 2: 各種即値リテラル (`#t`, `#f`, `'()`, `#\a`)**:
   - Boolean (`0x2F` / `0x6F`), Character (`0x0E`), Empty List (`0x3F`) の定数出力。
5. **Step 3: 単項数値演算**:
   - `fxadd1`, `fxsub1`, `fixnum->char`, `char->fixnum` の RAX ビット演算コード生成。
6. **Step 4: 単項型述語**:
   - `fixnum?`, `boolean?`, `char?`, `null?`, `zero?` のビットマスク・比較と条件フラグによる `#t`/`#f` 出力。
7. **テスト実行と品質検証**:
   - `./test.sh` による全アサーションの完全 PASS を確認。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/` サンドボックスが整備され、既存の `make py_compile` や `make static_analysis` に影響を与えないこと。
- [x] `Step 1: 42` から `Step 4: 単項型述語` までの全テストケースが `./test.sh` でグリーンであること。
- [x] Tagged Pointer（Fixnum, Boolean, Char, Null）のビットマスクおよび C ランタイム表示が DSN-33 §2.1 仕様と完全に合致していること。
- [x] `ulisp/README.md` に動作方法および Phase 1 完了ログが記録されていること。
