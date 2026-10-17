---
ID: 548
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS ライブラリ構文 (define-library / import) の静的脱糖・フラット名前空間インクルード機構の実装 (ID: 548)

## 1. 概要 / Summary
R7RS-small (Section 5.6) に規定されているモジュール化仕様 `define-library` および `import` / `export` の簡易サポートを ULisp AOT パイプラインに導入する。
ULisp はベアメタル AOT ネイティブ生成を行うため、完全な動的環境リンクではなく、コンパイル前段（Pass 0 / Pass 1）においてライブラリ定義を解析し、宣言された宣言要素（`include`, `begin`）を単一のフラットな S 式構造体へと静的に脱糖・インライン展開する。これにより、R7RS 準拠で書かれたライブラリコードを無修正のまま ULisp でネイティブコンパイル可能とする。

---

## 2. トレーサビリティ / Traceability
- **規格仕様**: R7RS-small (Revised^7 Report on the Algorithmic Language Scheme - small) Section 5.6 "Libraries"
- **設計仕様書**: [DSN-33 (ULISP 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連Issue**: Issue #533 (syntax-rules 衛生的マクロ展開器), Issue #534 (R7RS 文字列ポート)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (Pass 0 / Pass 1 脱糖パイプライン)
- [ ] [ulisp/passes/00b_macro_expander.scm](../../ulisp/passes/00b_macro_expander.scm) (マクロ・ライブラリフォームの前処理)
- [ ] [ulisp/lib/](../../ulisp/lib/) (標準ライブラリ群のライブラリ宣言化)
- [ ] [ulisp/tests/test_library.scm](../../ulisp/tests/test_library.scm) (ライブラリ構文テストスイート新規作成)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (テストターゲット統合)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/548-r7rs-define-library-import`

1. **構文認識とパーサ拡張**:
   - `(define-library <library-name> <library-declaration> ...)` の構文定義を追加。
   - `<library-declaration>` として `(export <export-spec> ...)`, `(import <import-set> ...)`, `(begin <command-or-definition> ...)`, `(include <filename> ...)` を受理。
2. **静的インクルードと脱糖**:
   - `(import (scheme base))` などの組み込み指定はノーオペレーションとして吸収。
   - `(include "path.scm")` を検知した場合は相対パス解決を行い、ファイルを読み込んで `begin` 内部にインライン結合。
   - `export` のシンボルリストを検証し、最終的にプログラムのトップレベル `begin` または定義列へと展開。
3. **回帰検証とテスト**:
   - サンプルライブラリを定義し、それを `import` して関数呼び出しを行うテストケースを作成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(define-library ...)` および `(import ...)` を含む Scheme コードが構文エラーなくパースされ、適切に脱糖されること
- [ ] `(include ...)` による外部ファイル取り込みが動作すること
- [ ] x86-64 Linux および Portable C バックエンドでコンパイル・実行が成功すること
- [ ] 既存の `make test`, `make test_c`, `make bootstrap` が 100% PASS すること
