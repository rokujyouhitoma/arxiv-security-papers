---
ID: 287
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] W3C Turtle 1.1 / RDF インジェストパーサーの Packrat PEG による実装 (DSN-25 / Issue 199 連携) (ID: 287)

## 1. 概要 / Summary
設計仕様書 [DSN-25](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第5.4節) および Issue 199 (W3C Turtle エクスポート) の双方向連携として、W3C RDF 1.1 Turtle 規格に準拠した **純粋 Python 製 Packrat PEG Turtle インジェストパーサー (`src/ontology/turtle_parser.py`)** を新規実装した。
外部ライブラリ（rdflib 等）に一切依存せず、`src/core/structures/peg.py` の Packrat PEG パーサーコンビネータ基盤を用いて以下の W3C Turtle 1.1 構文を線形時間 $O(N)$ かつ厳密にパースし、RDF トリプル (`s, p, o`) およびプレフィックス辞書を抽出する。

- ディレクティブ構文: `@prefix prefix: <iri> .` および SPARQL 形式 `PREFIX prefix: <iri>`、`@base` / `BASE`
- 主語 (Subject): IRI (`<http://...>`, `urn:...`)、プレフィックス名 (`ex:Vulnerability`, `owl:Class`)、ブランクノード (`_:b1`, `[ ... ]`)
- 述語 (Predicate): IRI、プレフィックス名、および短縮キーワード `a` (`rdf:type`)
- 目的語 (Object): IRI、プレフィックス名、ブランクノード、リテラル（文字列 `"..."`, 言語タグ `"..."@en`, 型付き `"..."^^xsd:string`, 数値 `42`, `3.14`, 真偽値 `true`, `false`）
- 省略構文: セミコロン `;` による同一主語の述語目的語リスト、カンマ `,` による同一述語の目的語リスト
- コメント構文: `#` から行末までのコメントの自動スキップ

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第5.4節)
- 関連 Issue: [Issue 199](199-implement-multi-format-graph-export-ttl-jsonld-stix.md)
- 前提成果物: [src/core/structures/peg.py](../../src/core/structures/peg.py) (Issue 284)
- 関連モジュール: [src/ontology/turtle_engine.py](../../src/ontology/turtle_engine.py) (エクスポートエンジン)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/ontology/turtle_parser.py](../../src/ontology/turtle_parser.py) (新規: Packrat PEG W3C Turtle 1.1 インジェストパーサー)
- [x] [src/ontology/__init__.py](../../src/ontology/__init__.py) (公開エクスポートの追加)
- [x] [tests/ontology/test_turtle_parser.py](../../tests/ontology/test_turtle_parser.py) (新規: W3C Turtle 構文網羅テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/287-packrat-peg-turtle-parser`

1. **データモデル定義 (`src/ontology/turtle_parser.py`)**:
   - `TurtleTerm`: `value: Any`, `term_type: str`, `datatype: Optional[str]`, `language: Optional[str]`
   - `TurtleTriple`: `subject: str`, `predicate: str`, `object: Any`, `term: Optional[TurtleTerm]`
   - `TurtleDocument`: `prefixes: Dict[str, str]`, `base_uri: Optional[str]`, `triples: List[TurtleTriple]`
2. **PEG 文法定義 (`TurtlePEGParser`)**:
   - 空白・コメントスキッパー (`# ... \n`, `\s+`)
   - ディレクティブ: `@prefix` / `PREFIX`, `@base` / `BASE`
   - IRI: `<[^>]+>`
   - PrefixedName: `[a-zA-Z0-9_-]*:[a-zA-Z0-9_.-]+`
   - Literal: `\"([^\"\\]|\\.)*\"` (言語タグ `@lang` または型注記 `^^iri`)
   - トリプル文: `Subject PredicateObjectList (";" PredicateObjectList)* "."`
   - カンマ展開: `Predicate Object ("," Object)*`
3. **拡張とユーティリティ**:
   - `parse_turtle(text: str) -> TurtleDocument`: 高レベルパース関数
   - `TurtleDocument.to_triples() -> List[Tuple[str, str, Any]]`
   - `TurtleDocument.resolve_iri(prefixed_or_iri: str) -> str`: プレフィックスの完全 IRI 展開
4. **品質ゲート遵守**:
   - 全関数 Xenon CC Rank A (<= 4)、`mypy --strict` エラー 0 件。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/ontology/turtle_parser.py` に Packrat PEG ベースの Turtle 1.1 パーサーが実装されていること
- [x] `@prefix` および `PREFIX` ディレクティブが解析され、プレフィックス解決が行われること
- [x] セミコロン `;` およびカンマ `,` の述語・目的語省略記法がフラットなトリプル列へ正確に展開されること
- [x] キーワード `a` が `http://www.w3.org/1999/02/22-rdf-syntax-ns#type` へ展開されること
- [x] 文字列リテラル、言語タグ、データ型指定、ブール値、数値が正しくパースされること
- [x] `tests/ontology/test_turtle_parser.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (xenon A, mypy strict) が 100% PASS すること
