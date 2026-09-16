---
ID: 308
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT] BibTeX/LaTeX 構文抽出および OKF Frontmatter (YAMLサブセット) の純粋 Packrat PEG 化 (ID: 308)

## 1. 概要 / Summary
現在、論文 PDF からの参考文献情報抽出（BibTeX/LaTeX）および OKF ドキュメントのフロントマター解釈において、一部残存している正規表現ヒューリスティクスや外部依存を完全排除し、DSN-25 仕様準拠の純粋 Python 製 Packrat PEG パーサーエンジンへ全面換装する。
これにより、ゼロ外部依存の保証、ReDoS 耐性の向上、およびパーサーインフラの一元化を達成する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [`DSN-25`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md), [`DSN-01`](../designs/DSN-01-core_architecture.md)
- 関連 Issue: [#303](closed/303-optimize-packrat-peg-parser-engine.md), [#304](closed/304-implement-left-recursion-and-cut-operator-in-peg.md), [#305](closed/305-implement-peg-aot-compiler-ast-optimizer-passes.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `grammars/yaml_frontmatter.peg` (OKF Frontmatter YAMLサブセット文法定義)
- [ ] `grammars/bibtex.peg` (BibTeX / LaTeX 引用・エントリ文法定義)
- [ ] `src/pipeline/transformer/generated_yaml_frontmatter_parser.py` (AOT 生成パーサー)
- [ ] `src/pipeline/transformer/yaml_parser.py` (OKF Frontmatter PEG ファサードおよび辞書変換)
- [ ] `src/ontology/extractor.py` (フロントマター抽出の PEG 統合)
- [ ] `src/database/storage/plain_text_storage.py` (フロントマター解析の PEG 統合)
- [ ] `src/pipeline/reporter/summary_generator.py` (フロントマター抽出の PEG 統合)
- [ ] `src/pdf_engine/generated_bibtex_parser.py` (AOT 生成パーサー)
- [ ] `src/pdf_engine/bibtex_extractor.py` (BibTeX / LaTeX 引用・書誌情報抽出エンジン)
- [ ] `Makefile` (`compile_grammars` ターゲット更新)
- [ ] `tests/pipeline/test_okf_peg_frontmatter.py` (YAML フロントマター PEG テストスイート)
- [ ] `tests/pdf_engine/test_bibtex_peg.py` (BibTeX / LaTeX 構文抽出 PEG テストスイート)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/308-pure-peg-conversion-bibtex-latex-and-okf-yaml`

### ステップ 1: OKF Frontmatter YAML-Subset PEG 文法設計 (`grammars/yaml_frontmatter.peg`)
1. Ford '04 仕様準拠の PEG 文法を定義:
   - ドキュメント境界: `^--- \n` から `\n---` または `\n...` までのブロック抽出。
   - スカラー型: ダブルクォート/シングルクォート文字列、アンクォート文字列、ブール値 (`true`/`false`)、整数・浮動小数点数、ISO 8601 日時文字列、null (`null`, `~`)。
   - リスト構造: `- item` 形式の箇条書きシーケンス、インライン配列 `[a, b, c]`。
   - マッピング構造: `key: value` 形式のペア、および 2/4 スペースインデントによるネスト辞書（`provenance:`, `trust:` 等）。
   - コメント: `#` から行末までのスキップ。
2. セマンティックアクションを定義し、構文木から直接 Python の `Dict[str, Any]` を安全に構築。

### ステップ 2: BibTeX / LaTeX 構文 PEG 文法設計 (`grammars/bibtex.peg`)
1. 学術論文における参考文献・引用構文を PEG 文法化:
   - エントリ形式: `@type{key, field1 = {val1}, field2 = "val2", ...}`
   - フィールド値: 波括弧 `{...}` ネスト文字列、クォート文字列、数値、マクロ識別子。
   - LaTeX コマンド・アクセント表記（`\"{a}`, `\'e`, `\textbf{...}` 等）の正規化処理。
   - インライン引用タグ: `\cite{...}`, `\citep{...}`, `\citet{...}`, `\bibitem{...}` の抽出ルール。
2. セマンティックアクションにより `BibTeXEntry(entry_type, key, fields)` のデータクラスへ変換。

### ステップ 3: AOT コンパイル & Makefile 統合
1. `Makefile` の `compile_grammars` ターゲットに `yaml_frontmatter.peg` と `bibtex.peg` のコンパイルコマンドを追加。
2. `src/pipeline/transformer/generated_yaml_frontmatter_parser.py` および `src/pdf_engine/generated_bibtex_parser.py` を自動生成。

### ステップ 4: 既存コードのパーサー換装 & ファサード実装
1. `src/pipeline/transformer/yaml_parser.py` を作成し、OKF フロントマターの解析 API `parse_okf_frontmatter(text: str) -> Dict[str, Any]` を提供。
2. `src/ontology/extractor.py` の `parse_okf_frontmatter` を上記ファサードへ委譲。
3. `src/database/storage/plain_text_storage.py` の `_parse_yaml_frontmatter_light` を上記ファサードへ換装。
4. `src/pipeline/reporter/summary_generator.py` の `_extract_frontmatter_field` を上記ファサードへ換装。
5. `src/pdf_engine/bibtex_extractor.py` を作成し、PDF 全文テキストからの BibTeX / 引用文献抽出 API を提供。

### ステップ 5: 品質検証 & セキュリティ評価 (DoD)
1. ReDoS 回避の検証（巨大・不整な YAML / BibTeX 入力に対する線形時間パース保証）。
2. 単体テストスイートの整備と 100% PASS。
3. `make check_format`, `xenon` ($CC \le 4$), `mypy --strict` の完全クリア。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `grammars/yaml_frontmatter.peg` および `grammars/bibtex.peg` が作成され、`make compile_grammars` で AOT Python コードが正常生成されること。
- [ ] OKF フロントマターパーサーがネスト辞書（`provenance`, `trust` 等）、リスト（`tags`, `authors` 等）、クォート文字列を正確に辞書構造化できること。
- [ ] 既存の OKF 生成・読み込み処理（`extractor.py`, `plain_text_storage.py`, `summary_generator.py`）が純粋 PEG パーサー経由で 100% 互換動作すること。
- [ ] BibTeX パーサーが多様なエントリ種別、ネスト波括弧、および LaTeX 引用コマンドを安全かつ正確にパースできること。
- [ ] 全ての新規関数・クラスが循環的複雑度 $CC \le 4$（Xenon Grade A）および `mypy --strict` をクリアすること。
- [ ] 単体テストが全件 PASS すること。
