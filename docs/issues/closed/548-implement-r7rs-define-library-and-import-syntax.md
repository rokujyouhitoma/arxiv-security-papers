---
ID: 548
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] R7RS ライブラリ構文 (define-library / import) の静的脱糖・フラット名前空間インクルード機構の実装 (ID: 548)

## 1. 概要 / Summary
R7RS-small (Section 5.6) に規定されているモジュール化仕様 `define-library` および `import` / `export` のサポートを ULisp AOT / JIT パイプラインに導入する。
ULisp はベアメタル AOT ネイティブ生成およびメタコンパイルを行うため、動的モジュールローダーではなく、マクロ展開の前段（Pass 0b / Pass 1）においてライブラリ定義を静的解析し、宣言要素（`export`, `import`, `begin`, `include`）を名前変更（`prefix`, `rename`, `only`, `except`）規則に従って単一のフラットな S 式構造体へと静的に脱糖・インライン結合する。これにより、R7RS 準拠で書かれたライブラリコードおよびそれを `import` するプログラムを無修正のまま ULisp でネイティブコンパイル・高速実行可能とする。

---

## 2. トレーサビリティ / Traceability
- **規格仕様**: R7RS-small (Revised^7 Report on the Algorithmic Language Scheme - small) Section 5.6 "Libraries"
- **設計仕様書**: [DSN-33 (ULISP 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 1 章、第 7 章 (S式マイクロインタプリタ ＆ メタコンパイラ基盤)
- **関連Issue**:
  - Issue #533 (syntax-rules 衛生的マクロ展開器)
  - Issue #534 (R7RS 文字列ポート)
  - Issue #549 (define-record-type マクロ)
  - Issue #551 (R7RS 標準ライブラリプロシージャ拡充)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] Target Branch: `feat/548-r7rs-define-library-import`
- [x] [ulisp/passes/00a_library.scm](../../ulisp/passes/00a_library.scm) (新規 Pass 0a: R7RS define-library & import 脱糖エンジン)
- [x] [ulisp/passes/08_driver.scm](../../ulisp/passes/08_driver.scm) (パイプライン最前段への Pass 0a 組み込み)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (`make compiler` による自動同期)
- [x] [ulisp/tests/passes/test_library.scm](../../ulisp/tests/passes/test_library.scm) (ユニットテスト・E2E x86/C テスト新規作成)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`test_library` ターゲットの追加と全自動テスト連携)

---

## 4. 詳細実装仕様 / Technical Architecture & Implementation Plan

### 4.1 R7RS Section 5.6 構文サブセット
1. **ライブラリ定義 (`define-library`)**:
   ```scheme
   (define-library <library-name>
     <library-declaration> ...)
   ```
   `<library-name>` はシンボルまたは小整数のリスト（例: `(math utils)`, `(example core 1)`）。

2. **ライブラリ宣言 (`<library-declaration>`)**:
   - `(export <export-spec> ...)`:
     - `<export-spec>` ::= `<identifier>` | `(rename <identifier1> <identifier2>)`
   - `(import <import-set> ...)`:
     - `<import-set>` ::= `<library-name>`
                       | `(only <import-set> <identifier> ...)`
                       | `(except <import-set> <identifier> ...)`
                       | `(prefix <import-set> <identifier>)`
                       | `(rename <import-set> (<identifier1> <identifier2>) ...)`
   - `(begin <command-or-definition> ...)`:
     - 内部の式・定義列を順序を保持して展開。
   - `(include <string1> <string2> ...)`:
     - 外部 Scheme ソースファイルを読み込み、`begin` 内に展開。

### 4.2 静的名前空間・脱糖パイプライン設計
- **ライブラリレジストリ**:
  `(define-library (name ...) decl ...)` を検知した際、ライブラリ名とエクスポート束縛辞書（内部識別子 $\rightarrow$ 外部公開名）、内部定義列（`define`, `define-syntax`）、初期化式列を記録。
- **組み込みライブラリの吸収**:
  `(scheme base)`, `(scheme write)`, `(scheme read)`, `(ulisp base)` などの標準ライブラリは、ULisp の基底環境（組み込みプリミティブ群）にマッピングされ、no-op または基底エクスポートとして安全に受理。
- **インポートセット（`import-set`）変換アルゴリズム**:
  - `only`: 指定識別子のみを通過。
  - `except`: 指定識別子を除外。
  - `prefix`: 識別子の先頭にプレフィックス文字列を付加（例: `(prefix (foo) p:)` $\rightarrow$ `bar` は `p:bar`）。
  - `rename`: `((orig new) ...)` に基づいて識別子をリネーム。
- **コード生成結果**:
  ライブラリ内部のローカル変数にはマクロ展開器の `hygiene-gensym` を適用して名前衝突を防ぎ、エクスポートされた名前（またはリネーム・プレフィックス後の名前）に対するトップレベル `define` / 式列へとフラット化して後続の Pass 01 (Desugar) / Pass 04 (ANF) に引き渡す。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(define-library ...)` および `(import ...)` 構文が正しく認識され、構文エラーなくフラットなトップレベル定義へと脱糖されること
- [x] `only`, `except`, `prefix`, `rename` の各 `import-set` モディファイアが期待通りに名前を解決・マッピングすること
- [x] ライブラリ内で定義された関数が、`import` 側のトップレベルから正しく呼び出せること
- [x] `ulisp/tests/passes/test_library.scm` を作成し、全 27 項目（10 項目以上）の機能テストが 100% PASS すること
- [x] x86-64 Linux および Portable C バックエンドでコンパイル・実行が成功すること (出力 260 一致)
- [x] 既存の `make -C ulisp test_passes`, `make -C ulisp test_c` がリグレッションなく 100% PASS すること
- [x] `make py_compile && make static_analysis` が警告・エラー 0 件で通過すること

