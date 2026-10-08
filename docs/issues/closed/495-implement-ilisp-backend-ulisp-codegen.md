---
ID: 495
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ILisp と ULisp の公式 Native AOT バックエンド統合 (ilisp/backend/ulisp_codegen/) と ELF 生成パイプラインの実装 (ID: 495)

## 1. 概要 / Summary

[DSN-33: ULISP x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)（§12, §6.2, §9）および [DSN-31: ILISP アーキテクチャ設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md)（§3.2 Backend B）に基づき、ILisp の上位言語環境と ULisp の最底層ネイティブ AOT コンパイラを公式に接続する **`ilisp/backend/ulisp_codegen/`** を実装する。

本バックエンドにより、ILisp でマクロ展開・構文解析された S 式プログラムを ULisp が受容可能な純粋コア形式（`lambda`, `let`, `if`, `begin` 等）へと脱糖・コード生成し、ULisp コンパイラおよびホストの GCC/Clang ツールチェーンを自動駆動して、**Python 依存ゼロのスタンドアロン ELF 単一バイナリ**をワンストップで生成可能とする。

これにより、ILisp/ALisp で記述された高速バッチ推論やセキュリティ判定ルールを、起動時間 0.1ms 未満の超高速・セキュアなネイティブバイナリとして配布・実行可能となる。

---

## 2. トレーサビリティとセキュリティ・設計制約 / Traceability & Constraints

### 2.1 関連設計書・先行 Issue
- 関連仕様書:
  - [DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-31: ILISP (Intelligence LISP) R7RS コアアーキテクチャ設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md)
  - [DSN-32: ALisp (Agent LISP) 包括アーキテクチャ設計仕様書](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md)
- 先行 Issue:
  - [Issue 494: ULisp 標準ライブラリ (lib/) の独立分離と極小 C ランタイムへの刷新](closed/494-modularize-ulisp-stdlib-and-minimal-c-runtime.md)
  - [Issue 493: ULisp Phase 7 セルフホスティングブートストラップ連鎖と不動点検証](closed/493-implement-ulisp-phase7-self-hosting-bootstrap-and-fixed-point.md)
  - [Issue 451: Backend A: Python AST トランスパイラ (py_codegen) の実装](closed/451-implement-backend-a-python-ast-transpiler.md)

### 2.2 セキュリティ・頑健性要件（脅威モデル考慮）
- **コマンドインジェクション / シェルエスケープ防止**:
  GCC やアセンブラ、ULisp 呼び出しを行う際、`subprocess.run` において `shell=True` を一切禁止し、引数を配列リスト形式（`shell=False`）で安全に渡す。
- **一時ファイル・サンドボックス管理**:
  コンパイル中間ファイル（`.s`, `.o` 等）は Python の `tempfile.TemporaryDirectory` 内で排他的・安全に生成・破棄し、ファイルシステムへの残留や競合（Race Condition）を防ぐ。
- **入力サニタイズと AST 検証**:
  未定義の構文や悪意ある循環参照を含む入力に対し、適切な `UlispCodegenError` 例外を送出して安全にフェイルする。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ilisp/backend/ulisp_codegen/__init__.py](../../ilisp/backend/ulisp_codegen/__init__.py) (新規作成: パッケージ初期化および公開 API 定義)
- [x] [ilisp/backend/ulisp_codegen/transpiler.py](../../ilisp/backend/ulisp_codegen/transpiler.py) (新規作成: ILisp S 式 AST から ULisp コア構文への脱糖・フォーマッタ)
- [x] [ilisp/backend/ulisp_codegen/compiler.py](../../ilisp/backend/ulisp_codegen/compiler.py) (新規作成: ULisp AOT コンパイル・アセンブリ出力・GCC ELF リンクパイプライン)
- [x] [ilisp/backend/__init__.py](../../ilisp/backend/__init__.py) (更新: `ulisp_codegen` バックエンドのエクスポート)
- [x] [ilisp/repl.py](../../ilisp/repl.py) (更新: `--compile` / `-c` / `--backend native` / `-S` CLI オプション追加)
- [x] [tests/ilisp/test_ulisp_codegen.py](../../tests/ilisp/test_ulisp_codegen.py) (新規作成: E2E ネイティブ AOT コンパイル & ELF 実行テストスイート)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新: Issue 495 登録)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/495-implement-ilisp-backend-ulisp-codegen`

### Phase 1: `ilisp/backend/ulisp_codegen/transpiler.py` の設計と実装
1. **S 式 AST の受容と正規化**:
   - 文字列（Scheme ソースコード）または ILisp の Datum（`Cons`, `Symbol`, 数値, 文字, ベクタ等）を入力として受容。
   - `ilisp.reader.read_all` によりパース。
   - Scope Sets マクロ展開済みの構文木に対し、ULisp がサポートする基本構文へのマッピング・脱糖を行う。
2. **脱糖・プリミティブ変換**:
   - `define` 式の `letrec` 展開、またはトップレベルシーケンスの `begin` ラップ。
   - 多引数算術演算（`(+ a b c)` $\to$ `(+ (+ a b) c)`）の二項演算化。
   - ULisp 標準ライブラリ（`lib/string.scm`, `lib/printer.scm`）で提供される手続き呼び出しへのシームレスな解決。

### Phase 2: `ilisp/backend/ulisp_codegen/compiler.py` の実装
1. **AOT コンパイルパイプライン**:
   - `compile_to_assembly(code_or_ast: Union[str, Any]) -> str`:
     - 脱糖済み S 式を ULisp コンパイラ（`ulisp/compiler.scm` または `ulisp/build/ulisp_core.scm`）にパイプ供給し、GAS x86-64 アセンブリ文字列を取得。
   - `compile_to_elf(code_or_ast: Union[str, Any], output_path: str, opt_level: str = "-O2") -> str`:
     - 一時ディレクトリ上でアセンブリを出力し、`ulisp/runtime.c` と共に `gcc`（または `clang`）でコンパイル・リンク。
     - 指定された `output_path` に実行可能バイナリ（ELF）を生成し、パーミッションを設定。
2. **実行環境パスの自動解決**:
   - リポジトリルートを基準に `ulisp/` の各リソース（`compiler.scm`, `runtime.c`, `lib/`）を動的に探索・フォールバック。

### Phase 3: CLI 統合 (`ilisp/__main__.py`)
1. **コンパイルコマンドの追加**:
   - `python -m ilisp --compile <source.scm> -o <binary>`
   - `python -m ilisp -c '(display (+ 20 22))' -o <binary>`
   - オプション: `--assembly-only` / `-S`（アセンブリ `.s` のみ出力）

### Phase 4: E2E テストスイートと品質ゲート検証
1. **テストケース (`tests/core/ilisp/test_ulisp_codegen.py`)**:
   - 即値・数値演算・比較演算の ELF 実行確認
   - `let`, `if`, 条件分岐の ELF 実行確認
   - 再帰関数・高階関数・クロージャ（TCO 含む）の ELF 実行確認
   - リスト操作（`cons`, `car`, `cdr`）および文字列・表示（`display`, `newline`）の ELF 実行確認
2. **品質ゲート**:
   - `make py_compile`, `make static_analysis`, `pytest tests/core/ilisp/test_ulisp_codegen.py` 全件合格。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ilisp/backend/ulisp_codegen/` モジュールが正常に配置され、`compile_to_assembly` および `compile_to_elf` が提供されていること。
- [x] Python API 経由で任意の Scheme コードが x86-64 アセンブリおよびスタンドアロン ELF バイナリへコンパイルでき、実行結果が一致すること。
- [x] `python -m ilisp --compile` CLI コマンドにより外部シェルから ELF バイナリ生成が可能なこと。
- [x] `tests/ilisp/test_ulisp_codegen.py` が新規作成され、全テストが 100% PASS すること。
- [x] `make py_compile` および `make static_analysis`（mypy, xenon, flake8）で警告・エラーが 0 件であること。
- [x] 相対パス規則およびコミット規約を完全に遵守していること。
