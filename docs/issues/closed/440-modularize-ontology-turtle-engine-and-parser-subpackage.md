---
ID: 440
種別: Refactoring
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] src/ontology 配下の Turtle エンジンおよびパーサーのサブパッケージ化 (ID: 440)

## 1. 概要 / Summary
`src/ontology/` 直下にフラットに置かれていた W3C Turtle 1.1 / RDF 関連のモジュール（`turtle_engine.py` (49KB)、`turtle_parser.py` (5.7KB)、`generated_turtle_parser.py` (13KB)）を、独立したモジュラーサブパッケージ `src/ontology/turtle/` に再編する。
既存のコードやスクリプトへの完全な後方互換性を保証するため、`src/ontology/turtle_engine.py`、`turtle_parser.py`、`generated_turtle_parser.py` には `# noqa` コメントを一切使用しない型安全な再エクスポート shim を配置する。

## 2. トレーサビリティ / Traceability
- 関連資料:
  - `src/ontology/turtle_engine.py`
  - `src/ontology/turtle_parser.py`
  - `src/ontology/generated_turtle_parser.py`
  - `grammars/turtle.peg`
  - [DSN-22: Security and Threat Ontology W3C Specification](../../docs/designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
  - [DSN-25: Pure-Python Packrat PEG Parser Engine](../../docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md)

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/ontology/turtle/__init__.py](file:///workspace/arxiv-security-papers/src/ontology/turtle/__init__.py)
- [x] [src/ontology/turtle/engine.py](file:///workspace/arxiv-security-papers/src/ontology/turtle/engine.py)
- [x] [src/ontology/turtle/parser.py](file:///workspace/arxiv-security-papers/src/ontology/turtle/parser.py)
- [x] [src/ontology/turtle/generated_parser.py](file:///workspace/arxiv-security-papers/src/ontology/turtle/generated_parser.py)
- [x] [src/ontology/turtle/__main__.py](file:///workspace/arxiv-security-papers/src/ontology/turtle/__main__.py)
- [x] [src/ontology/turtle_engine.py](file:///workspace/arxiv-security-papers/src/ontology/turtle_engine.py)
- [x] [src/ontology/turtle_parser.py](file:///workspace/arxiv-security-papers/src/ontology/turtle_parser.py)
- [x] [src/ontology/generated_turtle_parser.py](file:///workspace/arxiv-security-papers/src/ontology/generated_turtle_parser.py)
- [x] [src/ontology/__init__.py](file:///workspace/arxiv-security-papers/src/ontology/__init__.py)
- [x] [grammars/turtle.peg](file:///workspace/arxiv-security-papers/grammars/turtle.peg)
- [x] [Makefile](file:///workspace/arxiv-security-papers/Makefile)

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/440-modularize-ontology-turtle-engine-and-parser-subpackage`

1. `src/ontology/turtle/` ディレクトリ新設。
2. `turtle_engine.py` -> `src/ontology/turtle/engine.py`。
3. `turtle_parser.py` -> `src/ontology/turtle/parser.py`（内部の `core.structures.peg` 参照を `core.peg` に是正）。
4. `generated_turtle_parser.py` -> `src/ontology/turtle/generated_parser.py`。
5. `src/ontology/turtle/__init__.py` および `__main__.py` の作成。
6. `src/ontology/` 直下に透明な後方互換性 shim を配置（`__all__ = [...]` による明示的エクスポート、`# noqa` 禁止）。
7. `grammars/turtle.peg` および `Makefile` のグラマー生成ターゲットを新サブパッケージパスに更新。
8. `make compile_grammars` の実行、および `tests/ontology/` テストパス検証。
9. `make check_format` および `make static_analysis` (Xenon A, Mypy Strict) 検証。

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/ontology/turtle/` に Turtle エンジン・パーサーがモジュール分割配置されていること。
- [x] `src/ontology/` 直下の shim モジュールが `# noqa` なしで型安全にエクスポートされていること。
- [x] `make compile_grammars` が新パスでクリーンにパーサーを生成できること。
- [x] `pytest tests/ontology/` が全件合格すること。
- [x] `make check_format` および `make static_analysis` がエラー0件でパスすること。
- [x] Issue 台帳および Git 履歴の更新完了。
