---
ID: 824
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Nanopass AST ノードにおけるソース位置情報 (Source Span) とメタデータの第一級サポート (ID: 824)

## 1. 概要 / Summary
Nanopass フレームワーク（`define-language` / `define-pass`）の AST 構築・走査基盤を拡張し、元のソースコード位置情報（ファイルパス、行、列、Span、マクロ展開履歴、Node ID）を各 AST ノードに第一級メタデータとして不可分に付与・透過的に伝播させる仕組みを導入する。
これにより、コンパイルエラー・警告の精密化、デバッグ情報（DWARF）の生成、および将来の C 言語フロントエンドにおける正確な字句・構文エラー報告の基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §1 (コンパイラ内部の基盤), §2 (B5: 型付き C の IR 言語定義)
- **関連 Issue**: #756 (Picopass/Femtopass DSL), #815 (Nanopass Catamorphism Optimization), #833 (Unified Pretty Diagnostic Reporter)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm): AST ノード構造体への Span メタデータ埋め込みおよび透過伝播マクロ
- [ ] [ulisp/compiler/syntax.scm](../../ulisp/compiler/syntax.scm): `syntax-object` 相当の位置情報ラッパーおよびアクセサ
- [ ] [ulisp/compiler/020_parse.scm](../../ulisp/compiler/020_parse.scm): Scheme 構文解析器での初期 Span 付与
- [ ] [ulisp/tests/test_nanopass_source_span.scm](../../ulisp/tests/test_nanopass_source_span.scm): パス通過時の位置情報保持に関する単体テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/824-nanopass-source-span-metadata`

1. AST 表現の拡張：
   - 全 AST レコードにオプショナルな `source-span` フィールド（`#(<path> <start-line> <start-col> <end-line> <end-col> <macro-origin>)`）を導入。
   - Nanopass の `define-pass` 出力生成子において、入力ノードの位置情報を自動的に出力ノードへコピーする透過伝播フック（デフォルト・コピー）を整備。
2. 構文脱糖および Picopass 最適化パスにおける位置情報脱落防止機構の組み込み。
3. 位置情報抽出ユーティリティ `(ast-source-span node)` の標準化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] パス 020 から 120 (AST to LIR) に至る全 Nanopass パスを通過しても、終端ノードの元のソース位置情報が消失しないこと。
- [ ] メタデータ付加によるコンパイル時間およびヒープ消費のオーバーヘッドが 5% 未満に抑制されていること。
- [ ] 単体テスト `test_nanopass_source_span.scm` がパスすること。
