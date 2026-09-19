---
ID: 347
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] QueryValidator: src/core/structures/peg.py クエリ構文の JS 移植と構文検証 (ID: 347)

## 1. 概要 / Summary

バックエンド `src/core/structures/peg.py` で定義されている Lucene 風ブーリアン検索クエリ文法（`term`, `"phrase"`, `field:value`, `AND`, `OR`, `NOT`, 括弧グループ等）のサブセットを解析する軽量 Packrat PEG パーサーエンジンを、Web フロントエンド向け純粋 JavaScript モジュール `site/js/frameworks/query-validator.js` に移植・実装する。

ユーザーが検索バーに入力する過程で、クォーテーションの閉じ忘れ、括弧の不一致、不正な演算子配置（例: `AND OR`, 末尾 `AND`）をリアルタイム（入力時）に構文解析し、エラーの発生位置（文字オフセット）と修正ガイダンスを即座に提示する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 6.5, 8)
  - [DSN-25: Pure-Python Packrat PEG 構文解析エンジン設計書](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [DSN-04: 2層検索エンジン & プラットフォーム設計書](../designs/DSN-04-search_engine_and_platform.md)
  - [DSN-21: エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_unified_console.md)
- 移植元コード:
  - `src/core/structures/peg.py`
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/query-validator.js`](../../site/js/frameworks/query-validator.js) (新規)
- [ ] [`site/externs.js`](../../site/externs.js) (`QueryValidatorInterface` 型定義追加)
- [ ] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [ ] [`site/app.js`](../../site/app.js) (検索バー構文エラー表示 UI との連動)
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (テストケース追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/347-port-peg-query-validator-to-frontend-search-input`

1. **`QueryValidator` クラスの設計と実装**:
   - PEG 文法規則:
     - `Query <- Expression`
     - `Expression <- OrTerm (OR OrTerm)*`
     - `OrTerm <- AndTerm (AND? AndTerm)*`
     - `AndTerm <- (NOT)? Primary`
     - `Primary <- Group / FieldQuery / Phrase / Word`
     - `FieldQuery <- [a-zA-Z_]+ ':' (Phrase / Word)`
   - メソッド: `validate(queryString)`, `parse(queryString)`
   - 戻り値: `{ valid: boolean, error: string|null, offset: number|null, expected: string[] }`
   - メモ化テーブルによる線形時間 $O(N)$ パース
2. **Closure Compiler 適合**:
   - `site/externs.js` に `QueryValidator` の型定義を追加
3. **UI フィードバック連動**:
   - 構文エラー発生時に検索バー下部へ非侵襲的なインラインヒントを表示

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/query-validator.js` が実装され、JSDoc 型アノテーションが付与されていること
- [ ] `src/core/structures/peg.py` のクエリ文法と整合した検証結果を返すこと
- [ ] 不正クエリに対して正確なエラー位置（offset）が特定されること
- [ ] `site/externs.js` に型定義が追加され、`make build_js` で警告 0 件であること
- [ ] `tests/web/test_frontend_frameworks.py` にテストが追加され 100% PASS すること
- [ ] `make verify_quality` が完全通過すること
