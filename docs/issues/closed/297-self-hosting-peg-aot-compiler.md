---
ID: 297
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-09-15
---

# [FEAT] PEG AOT コンパイラのセルフホスティング（自己完結ブートストラップ化）の実装と DSN-25 設計仕様書改定 (ID: 297)

## 1. 概要 / Summary
Packrat PEG ランタイムおよび事前コンパイラ（AOT Compiler: Issue #284, #293, #294）の集大成として、**PEG メタ文法パーサー自身を PEG 文法（`grammars/peg_meta.peg`）によって定義し、AOT コンパイラによって自己生成されたコード（`generated_meta_parser.py`）でパースする「セルフホスティング（自己完結ブートストラップ化）」** を実現する。

これにより、コンパイラの表現力と正当性を自ら証明する究極の受入テスト（Self-Hosting Golden Test）を確立し、将来的な文法構文の拡張性を最大化するとともに、起動時オーバヘッドを極小化する。

### 主な提供機能
1. **PEG メタ文法の形式的 `.peg` 定義 (`grammars/peg_meta.peg`)**:
   - 規則定義、チョイス (`/`, `|`)、連接、プレフィックス (`&`, `!`, `name:`ラベル)、サフィックス (`*`, `+`, `?`)、正規表現リテラル (`/.../`)、文字列リテラル、セマンティックアクション (`{ ... }`) の完全定義。
2. **AOT 自己生成メタパーサー (`generated_meta_parser.py`)**:
   - `compile_peg.py` により `grammars/peg_meta.peg` から生成された高パフォーマンス・独立 Python クラス。
3. **ブートストラップ統合ファサード (`meta_grammar.py`)**:
   - 生成済み AOT メタパーサーを優先使用し、高速パースを提供するシームレスな統合。
4. **自己再現性・ラウンドトリップ検証スイート (`tests/core/test_peg_bootstrap.py`)**:
   - 生成されたパーサーが自身の文法ファイル `peg_meta.peg` をパースして同一の AST を再生成できること（Fixpoint / 決定論的再現性）の自動検証。
5. **Makefile ビルドパイプライン統合**:
   - `make compile_grammars` への `peg_meta.peg` 組み込みおよび `make verify_peg_bootstrap` ターゲットの新設。
6. **DSN-25 設計仕様書の改定**:
   - `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` に Phase 3 セルフホスティング・ブートストラップ仕様を明文化。

---

## 2. トレーサビリティ / Traceability
- 発端: PEG AOT コンパイラのセルフホスティング有効性検討に基づく実装要求
- 関連標準・先行技術:
  - CPython `pegen` (PEP 617: New PEG parser for CPython) のブートストラップ方式
  - DSN-25: 純粋 Python 製汎用 Packrat PEG ランタイム基盤および構文解析エンジン統合設計仕様書
- 先行 Issue:
  - Issue #284: Packrat PEG コアランタイム基盤の実装
  - Issue #293: PEG 事前コンパイラ (AOT Compiler) 基盤の実装
  - Issue #294: W3C Turtle 1.1 パーサーの AOT 化と運用パイプライン統合

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [NEW] `grammars/peg_meta.peg` (PEG メタ文法自己定義仕様)
- [x] [NEW] `src/core/structures/peg_compiler/generated_meta_parser.py` (AOT 自己生成メタパーサー)
- [x] [MODIFY] `src/core/structures/peg_compiler/meta_grammar.py` (AOT メタパーサー優先ディスパッチ)
- [x] [MODIFY] `src/core/structures/peg_compiler/cli.py` (ブートストラップ自己コンパイル対応)
- [x] [NEW] `tests/core/test_peg_bootstrap.py` (セルフホスティング・Fixpoint ラウンドトリップテスト)
- [x] [MODIFY] `Makefile` (`compile_grammars` 更新 & `verify_peg_bootstrap` ターゲット新設)
- [x] [MODIFY] `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` (Phase 3 仕様策定)
- [x] [MODIFY] `docs/issues/README.md`
- [x] [MODIFY] `docs/README.md`
- [x] [MODIFY] `README.md`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/297-self-hosting-peg-aot-compiler`

1. **メタ文法定義の作成 (`grammars/peg_meta.peg`)**:
   - `src/core/structures/peg_compiler/meta_grammar.py` のコンビネータ定義と完全に等価な文法ルールを `.peg` 記法で記述。
   - アクションブロック `{ ... }` による `GrammarDef`, `RuleDef`, `ChoiceExpr` 等の AST 構築を実装。
2. **初回ブートストラップ・コード生成**:
   - `tools/peg_compiler/compile_peg.py` を実行し、`grammars/peg_meta.peg` から `src/core/structures/peg_compiler/generated_meta_parser.py` をコンパイル生成。
3. **コンパイラ基盤の統合**:
   - `meta_grammar.py` を更新し、生成された `GeneratedMetaGrammarParser` をデフォルトのパーサーとして透過的に利用。
4. **セルフホスティング検証テスト (`test_peg_bootstrap.py`)**:
   - 既存のすべての文法（`boolean_query.peg`, `calc.peg`, `turtle.peg`, `peg_meta.peg`）が `generated_meta_parser.py` で正常にパースでき、手書きコンビネータパーサーと同一の AST を出力することを検証。
   - 自身を再コンパイルした結果が完全一致する Fixpoint 不変性を検証。
5. **Makefile ターゲットの整備**:
   - `make compile_grammars` で `peg_meta.peg` も自動コンパイル・整形。
   - `make verify_peg_bootstrap` で差分ゼロ検証。
6. **DSN-25 設計書の改定**:
   - Phase 3 セルフホスティングアーキテクチャ、ブートストラップ循環依存解消法（Git管理下での決定論的生成）、および計算量・品質保証基準を追記。
7. **品質ゲートと Issue クローズ**:
   - `make format`, `make static_analysis` (xenon Grade A, mypy --strict, flake8 0 errors), `make test` を全件パスさせ、コミット・マージ。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `grammars/peg_meta.peg` が作成され、PEG メタ文法自身が完全記述されていること。
- [x] `src/core/structures/peg_compiler/generated_meta_parser.py` が自動生成され、Git 管理下に配置されていること。
- [x] `MetaGrammarParser` が自己生成された AOT メタパーサーを優先利用し、既存の全 `.peg` ファイルが透過的にコンパイル可能であること。
- [x] `tests/core/test_peg_bootstrap.py` において、手書きパーサーとの AST 等価性および自己再コンパイル Fixpoint が 100% PASS すること。
- [x] `Makefile` に `verify_peg_bootstrap` が追加され、`make compile_grammars` と共に正常動作すること。
- [x] `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` が改定され、Phase 3 セルフホスティング仕様が APPROVED ステータスで文書化されていること。
- [x] `make format`, `make static_analysis` (xenon Grade A, mypy --strict, flake8 0 errors, `# flake8: noqa` 追加なし) および `make test` に完全合格すること。
