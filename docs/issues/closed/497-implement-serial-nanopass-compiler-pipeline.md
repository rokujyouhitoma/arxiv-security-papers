---
ID: 497
種別: Refactoring
優先度: High
ステータス: Closed
---

# [REFACTOR] Implement Serial Nanopass Compiler Pipeline for ULisp (ID: 497)

## 1. 概要 / Summary
Issue #496 によるモジュール分割によりコードの物理的分離は達成されたが、依然としてコード生成（Codegen）や解析（Analysis）の再帰下降中に構文脱糖（`desugar-cond` 等）をオンデマンドで呼び出す「名ばかりのパス（Single-Pass の共依存構造）」が残存していた。

本 Issue では、Chez Scheme や Ghuloum の Nanopass 思想に基づき、ULisp を**「直列 Nanopass 型コンパイラパイプライン（Serial Nanopass Architecture）」**へと根本的に再設計・リファクタリングした。
前のパスが AST 全体を完全に変換した正規化表現（Canonical AST）を生成し、次のパスへと一方通行で受け渡す直列データフローを確立した。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3 (言語機能と低レイヤコード生成仕様), §4 (フェーズ別コンパイラ設計), §6.1 (セルフホスティングパイプライン)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #496 (Modularize ULisp Compiler Passes)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/01_desugar.scm](file:///workspace/arxiv-security-papers/ulisp/passes/01_desugar.scm): AST 全体を一括変換し、すべての糖衣構文を展開しきる `desugar-all` パスの新設
- [x] [ulisp/passes/02_analysis.scm](file:///workspace/arxiv-security-papers/ulisp/passes/02_analysis.scm): コア AST（`if`, `let`, `letrec`, `lambda`, `begin`, プリミティブ）のみを対象とした静的解析の純化（脱糖依存の全廃）
- [x] [ulisp/passes/04_codegen.scm](file:///workspace/arxiv-security-papers/ulisp/passes/04_codegen.scm): 糖衣構文処理を完全撤廃し、正規化コア AST のみに特化した直截な機械語コード生成エンジンの純化
- [x] [ulisp/passes/05_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/05_driver.scm): 直列パイプライン結合（`forms` $\to$ `rewrite-top-level` $\to$ `desugar-all` $\to$ `compile-program`）の実装
- [x] [ulisp/compiler.scm](file:///workspace/arxiv-security-papers/ulisp/compiler.scm): パス群からの決定論的再生成
- [x] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): セルフホスティング不動点検証（`diff stage2.s stage3.s == 0`）
- [x] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): 既存テストスイート 100% PASS 保証
- [x] [tests/ilisp/test_ulisp_codegen.py](file:///workspace/arxiv-security-papers/tests/ilisp/test_ulisp_codegen.py): ILisp AOT バックエンド統合テスト 100% PASS 保証
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/497-implement-serial-nanopass-compiler-pipeline`

1. **Pass 1 の完全正規化パス化 (`desugar-all`)**:
   - 入力 AST を再帰走査し、`cond`, `case`, `let*`, `named-let`, `and`, `or`, `string-append` をすべてプリミティブ構文（`if`, `let`, `letrec`, `lambda`, `begin`）へ完全に展開する。
   - `desugar-all` 通過後の AST から糖衣構文を 100% 根絶する。

2. **Pass 2 の純化 (`02_analysis.scm`)**:
   - `free-vars` 内に存在する `(case ...)`, `(cond ...)`, `(let* ...)`, `(and ...)`, `(or ...)` 等の脱糖呼出しハンドラを全削除。
   - コア構文のみを走査する極めて軽量かつ堅牢な解析器へスリム化。

3. **Pass 4 の純化 (`04_codegen.scm`)**:
   - `compile-expr` から `cond`, `case`, `let*`, `and`, `or` のパターンマッチおよび脱糖呼出しを全削除。
   - コード生成エンジンが糖衣構文を意識しないクリーンなバックエンドへ移行。

4. **Pass 5 Driver での直列パイプライン駆動 (`05_driver.scm`)**:
   ```scheme
   (let* ((forms (read-all-forms))
          (ast0  (rewrite-top-level forms))
          (ast1  (desugar-all ast0)))
     (compile-program ast1))
   ```

5. **厳格な品質検証**:
   - `cd ulisp && ./test.sh`: 全フェーズ単体テスト 100% PASS。
   - `cd ulisp && ./bootstrap.sh`: Stage 1 $\to$ Stage 2 $\to$ Stage 3 の不動点検証（`cmp stage2.s stage3.s` 差分ゼロ）。
   - `.venv/bin/pytest tests/ilisp/test_ulisp_codegen.py`: ILisp AOT 連携テスト全 18 件 PASS。
   - `make check_format` & `make static_analysis`: 静的解析 0 エラー PASS。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `desugar-all` が実装され、Pass 1 完了時点で全糖衣構文が展開されていること。
- [x] `02_analysis.scm` および `04_codegen.scm` から構文糖衣関連コード・脱糖関数呼出しが完全排除されていること。
- [x] `05_driver.scm` が前のパスの出力を次のパスへ直列に受け渡すパイプライン構造になっていること。
- [x] `ulisp/test.sh` の全テストが 100% PASS すること。
- [x] `ulisp/bootstrap.sh` のセルフホスティング固定点（Stage 2 と Stage 3 の bit-for-bit 完全一致）が成立すること。
- [x] `tests/ilisp/test_ulisp_codegen.py` が全件 PASS すること。
- [x] すべての品質ゲート（`make check_format`, `make static_analysis`）を通過すること。
