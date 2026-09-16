---
ID: 310
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] PDF ToUnicode CMap ストリーム構文解析の純粋 Packrat PEG 化 (ID: 310)

## 1. 概要 / Summary
現在、PDF エンジンにおける文字コードデコード処理（`src/pdf_engine/font.py` 内の `ToUnicodeParser`）は、PostScript 風の /ToUnicode CMap ストリームに対して複数の正規表現走査（`re.findall(r"beginbfchar(.*?)endbfchar", text, re.DOTALL)` や `re.finditer`）によって `bfchar` および `bfrange` マッピングを抽出している。
しかし、PostScript 構文特有のコメント（`%`）、空白・改行バリエーション、不完全なブロック、および配列形式の `bfrange`（`<start> <end> [ <dest1> <dest2> ... ]`）において、正規表現ベースのスライシングは構文解析の堅牢性に欠け、抽出漏れや ReDoS リスクの原因となり得る。

本タスクでは `grammars/pdf_cmap.peg` を新規作成し、DSN-25 Phase 2 仕様に準拠した AOT Packrat PEG 事前生成パーサーへ完全換装することで、PDF CMap デコード処理の堅牢性と保守性を大幅に強化する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [`DSN-25`](../../designs/DSN-25-pure_python_packrat_peg_parser_engine.md), [`DSN-04`](../../designs/DSN-04-pdf_extraction_pipeline.md)
- 関連 Issue: [#308](308-pure-peg-conversion-bibtex-latex-and-okf-yaml.md), [#309](309-deploy-aot-peg-sql-admin-and-tcl-parser.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `grammars/pdf_cmap.peg` (新規: CMap Packrat PEG 文法仕様)
- [x] `src/pdf_engine/generated_cmap_parser.py` (新規: AOT 生成パーサー)
- [x] `src/pdf_engine/cmap_helpers.py` (新規: CMap AST 構築・マッピングヘルパー)
- [x] `src/pdf_engine/font.py` (`ToUnicodeParser` を AOT PEG 委譲・正規表現スライシング完全撤廃)
- [x] `Makefile` (`compile_grammars` ターゲット更新)
- [x] `tests/pdf_engine/test_cmap_peg.py` (新規テストスイート)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/310-pure-peg-pdf-tounicode-cmap-parser`

1. **`grammars/pdf_cmap.peg` の文法定義**:
   - PostScript トークン（16進文字列 `<...>`, リテラル, 整数, コメント `%`）の厳密な定義。
   - `beginbfchar` ... `endbfchar` ブロックの解析（`<srcHex> <dstHex>` ペア）。
   - `beginbfrange` ... `endbfrange` ブロックの解析（単一インクリメント `<start> <end> <dstBase>` および配列 `<start> <end> [ <dst1> <dst2> ... ]`）。
   - スキップ規則による CMap ヘッダー・フッター（`/CIDInit`, `begincmap`, `endcmap` 等）の耐障害読み飛ばし。
2. **`src/pdf_engine/cmap_helpers.py` の実装**:
   - `_map_bfrange_char` などの UTF-16BE / CID デコードロジックを分離・カプセル化。
   - `ToUnicodeParser` 向けの辞書（`Dict[int, str]`）構築ヘルパー。
3. **`Makefile` 統合と AOT コンパイル**:
   - `Makefile` の `compile_grammars` に `pdf_cmap.peg` を追加し、`generated_cmap_parser.py` を生成。
4. **`src/pdf_engine/font.py` のリファクタリング**:
   - `ToUnicodeParser.parse(cmap_data: bytes)` を `generated_cmap_parser.PDFCMapParser` への委譲処理に置換。
5. **品質検証**:
   - `tests/pdf_engine/` の全テスト PASS、`make check_format`, `xenon` ($CC \le 4$), `mypy --strict` クリア。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `grammars/pdf_cmap.peg` が作成され、AOT コンパイルで `generated_cmap_parser.py` が生成されること。
- [x] `font.py` から CMap 解析の `re.findall` / `re.finditer` が撤廃され、純粋 PEG 化されること。
- [x] 単一値および配列形式の `bfrange`、`bfchar`、および未知トークンのスキップが正常に動作すること。
- [x] 全品質ゲート（check_format, xenon Grade A, mypy --strict, pytest）が 100% PASS すること。
