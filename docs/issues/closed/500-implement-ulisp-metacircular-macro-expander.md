---
ID: 500
種別: Feature
優先度: Medium
ステータス: Closed
完了日: 2026-10-10
---

# [FEAT] Implement Metacircular Macro Expander for ULisp (ID: 500)

## 1. 概要 / Summary
現在、ULisp の構文脱糖は `ulisp/passes/01_desugar.scm` 内でハードコードされた固定的な手続き（`desugar-cond` 等）に依存している。

本 Issue では、Scheme が持つ「コードとデータの同一性（ホモアイコニシティ）」とメタサーキュラー評価の利点を活かし、ホスト Scheme 環境およびセルフホストネイティブ環境の双方で動作する**「自律型メタサーキュラー・マクロ展開器（Metacircular Macro Expander: Pass 00b）」**を実装した。

コンパイル時に Scheme 式を評価する小型自己完結インタープリタ（`eval-macro-expr`）を ULisp 内部に備えることで、`define-macro` / `defmacro` 形式のユーザー定義マクロ構文を実現し、ホスト環境の `eval` や外部ランタイムに一切依存することなく、セルフホスティング（Stage 2 / Stage 3）においても決定論的な不動点（Bit-for-bit identical）を完全に保証した。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3.1 (Scheme コア構文), §4.1 (Nanopass コンパイラ直列段), §6.1 (セルフホスティングパイプライン)
- **DSN-31**: §3.1 (ILisp マクロ展開機構との連携), §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #497 (Serial Nanopass Pipeline), #502 (Introduce Low-Level IR), #505 (Migrate Test Runner)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/00b_macro_expander.scm](file:///workspace/arxiv-security-papers/ulisp/passes/00b_macro_expander.scm): 新設するメタサーキュラー評価器およびマクロ展開器パス
- [x] [ulisp/passes/08_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/08_driver.scm): トップレベル形式読み込み直後でのマクロ展開パス呼出統合
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): `PASSES_LIB` への `00b_macro_expander.scm` 追加
- [x] [ulisp/tests/test_passes.scm](file:///workspace/arxiv-security-papers/ulisp/tests/test_passes.scm): パス単体テストの追加
- [x] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): `define-macro` E2E テストの追加
- [x] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): セルフホスティング不動点検証
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. アーキテクチャ設計 / Architectural Design

### 4.1 メタサーキュラー評価器 (`eval-macro-expr`)
コンパイル時にマクロ本体式を評価して展開後 S 式を生成する軽量評価器。
外部の `eval` を呼ばず、以下の純粋な Scheme 構文および基本手続き群のみで自己完結して動作する。

1. **基本構文**:
   - リテラル（数値、真偽値、文字、文字列、空リスト `'()`）
   - 変数参照（局所変数環境 `env` からのルックアップ）
   - `(quote <datum>)`
   - `(if <test> <then> <else>)`
   - `(begin <e1> ...)`
   - `(let ((<var> <init>) ...) <body> ...)`
   - `(let* ((<var> <init>) ...) <body> ...)`
   - `(lambda (<params> ...) <body> ...)` および可変長引数 `(lambda (<p1> . <rest>) <body> ...)`
2. **プリミティブ関数 (Built-in Primitives)**:
   - リスト操作: `cons`, `car`, `cdr`, `pair?`, `null?`, `list`, `append`
   - 等価・判定: `eq?`, `equal?`, `not`
   - 数値比較・算術: `=`, `<`, `>`, `<=`, `>=`, `+`, `-`, `*`
   - 型述語: `symbol?`, `number?`, `boolean?`, `string?`

### 4.2 マクロ定義と展開パイプライン (`expand-macros-in-forms`)
トップレベル形式群 `forms` を入力とし、以下の形式でマクロを認識・環境へ登録する:
- `(define-macro (name . params) body ...)`
- `(define-macro name (lambda params body ...))`
- `(defmacro name params body ...)`

マクロ定義はコンパイル時環境 `*macro-env*` に `(name . closure)` として保持され、最終的な出力コードからは除去される。
一般の式中に `(name arg ...)` が現れた場合、`name` がマクロであれば引数を未評価のままクロージャに適用し、得られた式を再帰的にマクロ展開する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/500-implement-ulisp-metacircular-macro-expander`

1. **ステップ 1: メタサーキュラー評価器および展開パスの実装 (`ulisp/passes/00b_macro_expander.scm`)**:
   - 環境操作関数 (`macro-env-lookup`, `macro-env-extend`)
   - コア評価器 `eval-macro-expr` の実装
   - マクロ展開関数 `macro-expand-1`, `macro-expand-expr`, `expand-macros-in-forms` の実装
2. **ステップ 2: パイプライン結合 (`ulisp/passes/08_driver.scm`, `ulisp/Makefile`)**:
   - `08_driver.scm` の `read-all-forms` 直後に `expand-macros-in-forms` を呼び出し。
   - `ulisp/Makefile` の `PASSES_LIB` 先頭に `passes/00b_macro_expander.scm` を配置。
3. **ステップ 3: パス単体テストの拡充 (`ulisp/tests/test_passes.scm`)**:
   - `eval-macro-expr` の基本評価テスト
   - `define-macro` による `when`, `unless`, `my-or` 等の展開結果一致テスト
4. **ステップ 4: E2E テストとセルフホスティング検証 (`ulisp/test.sh`, `ulisp/bootstrap.sh`)**:
   - ネイティブコンパイラ経由での `define-macro` 実行テスト追加
   - 3段階ブートストラップ検証による完全ビット一致（不動点）確認
5. **ステップ 5: 品質ゲートおよび Issue クローズ**:
   - `make -C ulisp test_passes`, `make -C ulisp test`, `make -C ulisp bootstrap` PASS 確認
   - `make check_format`, `make py_compile` PASS 確認
   - Issue 台帳更新およびコミット

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `00b_macro_expander.scm` が追加され、ユーザー定義マクロがコンパイル時に展開されること。
- [x] `when`, `unless` などの典型的な構文マクロがネイティブバイナリで正しく動作すること。
- [x] `ulisp/tests/test_passes.scm` にマクロ展開器の単体テストが追加され、全テストが PASS すること。
- [x] `ulisp/test.sh` の全テストが 100% PASS すること。
- [x] `ulisp/bootstrap.sh` の不動点検証（`diff stage2.s stage3.s == 0`）が成立すること。
- [x] すべての品質ゲート（`make check_format`, `make py_compile`）を通過すること。

