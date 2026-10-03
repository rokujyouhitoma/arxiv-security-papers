---
ID: 421
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] クライアントサイドルーターの URL パス＆クエリ構文解析の PEG 化 (ID: 421)

## 1. 概要 / Summary

Web クライアントのシングルページアプリケーション（SPA）ルーティングを司る `site/js/frameworks/router.js` は、現在 `register(pattern, callback)` において正規表現文字列の連結（`"^\\/?" + pattern.replace(...)`）を構築し、クエリ文字列は `split('&')` と `split('=')` で単純分割している。
この実装は、パスパラメータ（`:id`、`:category`）、ワイルドカード（`*`）、および配列形式のクエリ（`?tags=zero-trust&tags=crypto`）や特殊文字エンコードのエッジケースでパース破綻や脆弱性を生じやすい。

本 Issue では、RFC 3986 および URL テンプレート構文に準拠した小型 PEG パーサーを導入し、ルーティングパターンのコンパイル、パスパラメータの型安全な抽出、および複合クエリ文字列の決定論的なデコードを実現する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第13節 Phase 6: Web フロントエンド連携 ＆ JavaScript コードジェネレータ基盤仕様)
- **関連 Issue**:
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/router.js`](../../site/js/frameworks/router.js)（URL パス＆クエリ PEG パースエンジンの統合）
- [ ] [`site/js/frameworks/query-validator.js`](../../site/js/frameworks/query-validator.js)（共通 PEG コンビネータの共有）
- [ ] [`site/app-min.js`](../../site/app-min.js)（Closure Compiler ビルド成果物）
- [ ] [`site/dashboard-min.js`](../../site/dashboard-min.js)（Closure Compiler ビルド成果物）
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py)（ルーター単体・統合テスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/421-client-router-url-path-query-peg-parser`

1. **Route Pattern PEG 文法**:
   - `Segment <- Param / Wildcard / Literal`
   - `Param <- ':' [a-zA-Z_][a-zA-Z0-9_]*`
   - `Wildcard <- '*'`
   - `Literal <- [^/:*?#]+`
2. **Query String PEG 文法**:
   - `QueryString <- '?'? Pair ('&' Pair)*`
   - `Pair <- Key ('=' Value)?`
   - `Key / Value <- [^&=#]+`
   - 同一キーの重複出現（例: `?tag=a&tag=b`）を自動的に配列化するセマンティックアクション。
3. **`router.js` 内部のリファクタリング**:
   - 正規表現生成処理を PEG ルートコンパイラに置換。
   - `resolve(hash)` 実行時に抽出パラメータとクエリオブジェクトをコールバックへ安全に注入。
4. **テスト & ビルド**:
   - パスパラメータ・配列クエリ・エスケープ文字を含むテストケースを作成し、`make build_js` を実行。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/router.js` のルートマッチングおよびクエリパースが PEG ベースで動作すること。
- [ ] パスパラメータ（`:id`）および重複クエリキー（配列化）が正確に抽出されること。
- [ ] 既存のハッシュナビゲーション（`#search`, `#summary`, `#trends`, `#evaluator` など）が回帰なく動作すること。
- [ ] `make build_js` が 0 エラーで完了すること。
- [ ] 自動テストが 100% PASS すること。
