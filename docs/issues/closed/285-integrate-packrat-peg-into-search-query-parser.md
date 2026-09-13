---
ID: 285
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] 検索クエリパーサーの Packrat PEG 換装と括弧ネスト対応ブーリアンクエリ解析の実装 (DSN-25 Phase 1) (ID: 285)

## 1. 概要 / Summary
設計仕様書 [DSN-25](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第5.1節) に基づき、現在正規表現の線形走査 (`re.finditer`) で実装されている `src/search/query/query_parser.py` (`EnterpriseQueryParser`) を、新規開発された Packrat PEG コアランタイム (`src/core/structures/peg.py`) を用いて再構築する。
これにより、従来のフィールド指定（`title:malware`, `author:Nakatani`）、フレーズ検索（`"cyber attack"~2`）、プレフィックス（`term*`）、ファジー（`term~1`）、ブーリアン修飾子（`+` / `-` / `AND` / `OR` / `NOT`）の完全な互換性を維持しつつ、これまで構文解析が不可能であった**「括弧ネストによる複雑な論理式」**（例: `(title:ransomware OR title:malware) AND -(tag:crypto OR author:smith)` や `((A OR B) AND (C OR D))`）を深さ無制限で安全に AST 化できるようにする。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第1.1節、第5.1節、第6.1節 Phase 1)
- 検索エンジン仕様書: [DSN-04-search_engine_and_platform.md](../designs/DSN-04-search_engine_and_platform.md)
- 前提成果物: [src/core/structures/peg.py](../../src/core/structures/peg.py) (Issue 284)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/search/query/query_parser.py](../../src/search/query/query_parser.py) (`EnterpriseQueryParser` を PEG コンビネータで再構築)
- [x] [tests/search/test_query_parser_peg.py](../../tests/search/test_query_parser_peg.py) (括弧ネスト・ブーリアン複合式・フィールド修飾・フレーズスロップ・エラー処理の単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/285-peg-search-query-parser`

1. **AST / クエリ表現の拡張**:
   - 既存の `QueryClause`（フィールド、ターム、修飾子）を尊重しつつ、ネスト構造を表現できる `nested_clauses: List[QueryClause]` および `logical_op: Optional[str]` をサポート。
   - `flatten()` メソッドにより、親グループの修飾子（`is_required`, `is_prohibited`）およびフィールド指定（`author:(Alice OR Bob)`）を再帰的かつ安全に子孫ノードへ伝播。
2. **PEG 文法定義 (`_build_peg_query_grammar`)**:
   - `Query = opt_ws + Expr + opt_ws`
   - `Disjunction = Conjunction + ZeroOrMore(or_op + Conjunction)` (OR グループ生成)
   - `Conjunction = Factor + ZeroOrMore(sep_and + Factor)` (AND 結合)
   - `Factor = Opt(Modifier) + Primary`
   - `Primary = FieldExpr / Phrase / PlainTerm / NestedParens`
   - `NestedParens = "(" + opt_ws + Expr + opt_ws + ")"`
3. **セマンティックアクション (`.map()`)**:
   - PEG の各ノードを `QueryClause` へマッピング。
   - 下流の全検索サブシステム（102テスト）に対する完全な後方互換性を保証。
4. **耐障害性・フォールバック**:
   - 未完の括弧や壊れた構文が入力された場合も `PEGSyntaxError` を捕捉し、正規表現トークン走査へ自動フォールバック。
5. **品質ゲート遵守**:
   - 全関数 Xenon CC Rank A (<= 4)、`mypy --strict` エラー 0 件。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `EnterpriseQueryParser` が PEG エンジンを用いてクエリをパースすること
- [x] 単一ターム、フィールド指定、フレーズ、ファジー、プレフィックスが既存通り正しくパースされること
- [x] `(title:ransomware OR title:malware) AND -(tag:crypto OR author:smith)` などの括弧ネストクエリがエラーなくパースされ、適切な修飾子・フィールドが適用されること
- [x] `tests/search/test_query_parser_peg.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (mypy strict, Xenon Rank A) が 100% PASS すること

