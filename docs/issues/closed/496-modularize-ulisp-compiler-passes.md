---
ID: 496
種別: Refactoring
優先度: High
ステータス: Closed
---

# [REFACTOR] Modularize ULisp Compiler into Pipeline Passes (ID: 496)

## 1. 概要 / Summary
現在、ULisp コンパイラ（`ulisp/compiler.scm`）は約 900 行の単一ファイルに脱糖（Desugar）、自由変数解析（Scope / Free-Var Analysis）、コード生成（Codegen）、およびアセンブリ出力（Emitter）が密結合した Monolithic な Single-Pass 構成となっている。
本 Issue では、DSN-33 仕様に基づき、ULisp のコンパイラパイプラインを明確なパス（Pass）ごとにモジュール分割・リファクタリングする。
これにより、ステップごとの単体検証性、可読性、および今後の機能追加（Vector型や最適化パス）の拡張性を担保する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §2 (タグ付けアーキテクチャ・ABI), §3 (言語機能と低レイヤコード生成仕様), §6.1 (セルフホスティングパイプライン)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #494 (ULisp Stdlib Modularization), #495 (ILisp Native Backend Integration)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `ulisp/passes/` (新規ディレクトリ作成)
  - `ulisp/passes/00_helpers.scm`: 共通述語・リスト操作・エラー処理
  - `ulisp/passes/01_desugar.scm`: 構文脱糖（`desugar-list`, `cond`, `and`, `or` 等）
  - `ulisp/passes/02_analysis.scm`: 静的スコープ解析・自由変数解析（`free-vars`）
  - `ulisp/passes/03_emitter.scm`: ラベル/シンボル/文字列テーブル管理、アセンブリ命令エミッタ
  - `ulisp/passes/04_codegen.scm`: 式・関数・トップレベルの x86-64 コード生成（`compile-expr`, `compile-top-level`）
  - `ulisp/passes/05_driver.scm`: 入力パース・パイプライン起動ドライバ
- [x] `ulisp/compiler.scm`: `passes/` から決定論的に結合生成、またはパイプライン結合
- [x] `ulisp/Makefile`: `passes/` の依存関係とビルドルールの更新
- [x] `ulisp/bootstrap.sh`: `build/ulisp_core.scm` 生成ルールの同期
- [x] `ulisp/test.sh`: 既存テストスイート（全件 PASS 保証）
- [x] `tests/ilisp/test_ulisp_codegen.py`: ILisp AOT バックエンド統合テスト（全件 PASS 保証）
- [x] `docs/issues/README.md`: Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/496-modularize-ulisp-compiler-passes`

1. **ブランチ作成**: `refactor/496-modularize-ulisp-compiler-passes` を作成しチェックアウト。
2. **パス分離の設計と実装**:
   - `ulisp/compiler.scm` を機能・パスごとに 6 つのファイルに分解：
     - `passes/00_helpers.scm`: `safe-car`, `cadr`, `memq`, `assq`, `reverse`, `error` 等
     - `passes/01_desugar.scm`: `desugar-list` 等の構文脱糖ロジック
     - `passes/02_analysis.scm`: `free-vars` 等の自由変数解析
     - `passes/03_emitter.scm`: `*label-counter*`, `*symbol-table*`, `intern-symbol`, `emit-string-literal` 等
     - `passes/04_codegen.scm`: `compile-expr`, `compile-top-level`, 末尾呼び出し最適化 (TCO)
     - `passes/05_driver.scm`: 標準入力からの読み込みとアセンブリ出力ドライバ
3. **ビルド & 結合ルールの整備**:
   - `ulisp/Makefile` に `compiler.scm: passes/*.scm` の生成ルールを追加。
   - `ulisp/bootstrap.sh` の `build/ulisp_core.scm` 連結に `passes/*.scm` を反映。
4. **検証と品質ゲート**:
   - `cd ulisp && ./test.sh`: 既存の全テストケースが 100% PASS することを確認。
   - `cd ulisp && ./bootstrap.sh`: Stage 1 $\to$ Stage 2 $\to$ Stage 3 の bit-for-bit 不動点自己ホスティングが PASS することを確認。
   - `tests/ilisp/test_ulisp_codegen.py`: ILisp 連携テスト全 18 件 PASS。
   - `make format`, `make py_compile`, `make static_analysis`: 静的解析 100% PASS。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/passes/` に各コンパイラパスがモジュールとして独立して配置されていること。
- [x] `compiler.scm` が `passes/` から再現可能にビルドできること。
- [x] `ulisp/test.sh` の全テストが PASS すること。
- [x] `ulisp/bootstrap.sh` の不動点（fixed-point）セルフホスティング検証が成功すること。
- [x] ILisp 側の `tests/ilisp/test_ulisp_codegen.py` が全件 PASS すること。
- [x] すべての品質ゲート（`make format`, `make py_compile`, `make static_analysis`）を通過すること。
