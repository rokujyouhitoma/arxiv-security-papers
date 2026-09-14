---
ID: 293
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT] DSN-25 Phase 2: Packrat PEG 事前コンパイラ (AOT Compiler) 基盤の実装 (ID: 293)

## 1. 概要 / Summary
DSN-25「Pure Python Packrat PEG Parser Engine」第6節に規定された進化ロードマップに基づき、`.peg` 構文定義ファイルから最適化された静的 Python パーサーコードを自動生成する**事前コンパイラ（Ahead-of-Time Compiler）基盤**を実装した。
`src/core/structures/peg.py` の Packrat PEG コアランタイムエンジン自身を用いて `.peg` メタ文法をパースする**セルフホスティング（ブートストラップ）**を実現し、コードエミッターによって完全型安全・ゼロ外部依存の Python パーサークラスを出力する。

---

## 2. トレーサビリティ / Traceability
- 設計文書: [docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第6節 事前コード生成型パーサージェネレータ進化ロードマップ)
- 先行 Issue:
  - [Issue #284 (Closed)](closed/284-implement-pure-python-packrat-peg-parser-core.md): 純粋 Python Packrat PEG コアランタイム
  - [Issue #285-#292 (Closed)](closed/292-eliminate-legacy-regex-where-helpers-with-pure-peg.md): 検索・グラフ・オントロジー・SQL 全層の PEG 適用

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] 新規モジュール: `src/core/structures/peg_compiler/`
  - `src/core/structures/peg_compiler/__init__.py`: 公開 API エクスポート
  - `src/core/structures/peg_compiler/ast_nodes.py`: PEG 文法 AST ノード定義
  - `src/core/structures/peg_compiler/meta_grammar.py`: `.peg` 文法解析用 Packrat PEG パーサー（ブートストラップ）
  - `src/core/structures/peg_compiler/codegen.py`: Python ソースコード生成エミッター
  - `src/core/structures/peg_compiler/cli.py`: コマンドラインインターフェース
- [x] CLI ラッパー: `tools/peg_compiler/compile_peg.py`
- [x] サンプル文法定義:
  - `grammars/calc.peg`: 四則演算・括弧・セマンティックアクション
  - `grammars/boolean_query.peg`: ブーリアン検索式文法
- [x] テストコード: `tests/core/test_peg_compiler.py`
- [x] ドキュメント: `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` の Phase 2 更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/293-implement-dsn25-phase2-peg-ahead-of-time-compiler`

1. **AST 設計 (`ast_nodes.py`)**:
   - `GrammarDef(name, rules)`
   - `RuleDef(name, expression)`
   - `Expression` 階層: `LitExpr`, `RegexExpr`, `RuleRefExpr`, `SeqExpr`, `ChoiceExpr`, `RepeatExpr`, `OptExpr`, `PredExpr`, `ActionExpr`, `NamedExpr`
2. **メタ文法パーサー (`meta_grammar.py`)**:
   - `src/core/structures/peg.py` のコンビネータ (`Lit`, `Reg`, `Seq`, `Choice`, `ZeroOrMore`, `OneOrMore`, `Opt`, `RuleRef`, `NotPred`) を組み合わせて `.peg` 記法を解釈。
   - `ActionBlockParser` による中括弧ネストと文字列エスケープの完全走査。
   - ルール定義先読み否定述語による連続識別子の貪欲消費防止。
3. **コードエミッター (`codegen.py`)**:
   - ディスパッチテーブルによる AST 式の Python コード化（Xenon Rank A $CC \le 4$）。
   - 変数バインドの自動アンパックと `textwrap.dedent` によるインデント正規化。
4. **CLI 実装 (`cli.py`, `compile_peg.py`)**:
   - 引数パース（`argparse`）、ファイル入力/出力、標準エラー出力へのエラーレポート。
5. **品質ゲートとテスト**:
   - 単体テスト網羅率、`make check_format`、`make static_analysis` (Xenon A, mypy --strict)。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/core/structures/peg_compiler/` にコンパイラモジュール一式が配置されていること。
- [x] `.peg` 文法定義ファイル（`grammars/calc.peg`, `grammars/boolean_query.peg` 等）から Python パーサーコードが生成されること。
- [x] 生成された Python パーサーを実行し、正しく構文解析およびセマンティックアクションが動作すること。
- [x] `tests/core/test_peg_compiler.py` のテストが 100% PASS すること。
- [x] `xenon`（全関数 $CC \le 4$ / Rank A）、`mypy --strict`、`py_compile` が 0 エラーであること。
- [x] `make check_format` が 100% PASS すること。
