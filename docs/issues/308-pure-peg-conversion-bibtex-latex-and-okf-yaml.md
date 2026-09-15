---
ID: 308
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] BibTeX/LaTeX 構文抽出および OKF Frontmatter (YAMLサブセット) の純粋 Packrat PEG 化 (ID: 308)


## 1. 概要 / Summary
現在、論文 PDF からの参考文献情報抽出（BibTeX/LaTeX）および OKF ドキュメントのフロントマター解釈において、一部残存している正規表現ヒューリスティクスや外部依存を完全排除し、DSN-25 仕様準拠の純粋 Python 製 Packrat PEG パーサーエンジンへ全面換装する。
これにより、ゼロ外部依存の保証、ReDoS 耐性の向上、およびパーサーインフラの一元化を達成する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [`DSN-25`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md), [`DSN-01`](../designs/DSN-01-core_architecture.md)
- 関連 Issue: [#303](closed/303-optimize-packrat-peg-parser-engine.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `grammars/bibtex.peg` (新規文法定義)
- [ ] `grammars/yaml_frontmatter.peg` (新規文法定義)
- [ ] `src/pipeline/transformer/okf_serializer.py`
- [ ] `src/pdf_engine/extractor.py`
- [ ] `Makefile` (`compile_grammars` 統合)
- [ ] `tests/pipeline/test_okf_peg_frontmatter.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/304-pure-peg-conversion-bibtex-latex-and-okf-yaml`

1. **BibTeX / 引用文献 PEG 文法設計 (`grammars/bibtex.peg`)**:
   - `@article`, `@inproceedings`, `@book` などの BibTeX エントリ構文、キー・バリュー属性、波括弧ネスト、LaTeX 特殊文字エスケープの PEG 化。
2. **OKF YAML-subset PEG 文法設計 (`grammars/yaml_frontmatter.peg`)**:
   - OKF v0.2 仕様で要求されるスカラー、リスト、ネスト辞書、複数行文字列（`|`, `>`）に特化したセキュアで高速な YAML パーサーの実装。
3. **AOT コンパイラ統合と既存コード換装**:
   - `make compile_grammars` で AOT コードを自動生成し、既存の正規表現処理を置換。
4. **回帰検証と品質ゲート**:
   - 全体テストおよび静的解析（Grade A $CC \le 4$, mypy --strict）のクリア。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `grammars/bibtex.peg` および `grammars/yaml_frontmatter.peg` が作成され、AOT コンパイル可能であること。
- [ ] 既存の OKF 生成・読み込み処理が純粋 PEG パーサー経由で 100% 互換動作すること。
- [ ] 悪意ある入力や不完全な構文に対する DoS 耐性が検証されていること。
- [ ] `make verify_quality` が 100% PASS すること。
