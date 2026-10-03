---
ID: 420
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 検索窓における Lucene PEG リアルタイム構文検証・エラーハイライト・オートコンプリートの実装 (ID: 420)

## 1. 概要 / Summary

本リポジトリのフロントエンドには、Packrat PEG エンジンと Lucene 文法規則を備えた `site/js/frameworks/query-validator.js` が実装されているが、Web コンソール（`site/app.js`）の検索ボックス（`#searchInput`, `#globalSearchInput`）では Enter キー押下時にバックエンド API を呼び出すのみで、入力中のリアルタイムな構文診断・エラーハイライト・オートコンプリートが連動していない。

本 Issue では、ユーザーのタイピング時（`input` イベント）に `QueryValidator.validate()` をデバウンス実行し、PEG パーサーの最大到達位置（`calcLineCol`）と Levenshtein 診断情報を利用して、未終了引用符（`"..."`）や括弧の不整合（`(...)`）、不正な演算子（`AND`, `OR`, `NOT` の連続）をリアルタイムに視覚的フィードバック（赤い波線やヒントバッジ）として表示し、構文補完候補をインタラクティブに提示する UI 基盤を構築する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第7.2節 検索クエリパーサー、第13節 Phase 6 JavaScript コードジェネレータ基盤)
  - [`docs/designs/DSN-04-search_engine_and_platform.md`](../designs/DSN-04-search_engine_and_platform.md) (検索エンジン構文解析仕様)
- **関連 Issue**:
  - Issue #299: 検索クエリパーサーの宣言的 AOT 換装
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/query-validator.js`](../../site/js/frameworks/query-validator.js)（構文補完・トークン推薦用ヘルパーの公開）
- [ ] [`site/app.js`](../../site/app.js)（検索入力イベントリスナー、デバウンス診断、ポップオーバー・ツールチップ描画）
- [ ] [`site/css/style.css`](../../site/css/style.css)（構文エラー表示、補完候補ドロップダウン用スタイル）
- [ ] [`site/app-min.js`](../../site/app-min.js)（Closure Compiler ビルド成果物）
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py)（リアルタイム構文検証統合テスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/420-search-input-realtime-peg-validation-and-autocomplete`

1. **`query-validator.js` の診断 API 拡充**:
   - `validate(text)` の返り値に、エラー位置（行・列）、期待されるトークン群（`expectedTokens`）、およびタイポ修正候補を構造化して提供。
2. **`site/app.js` でのデバウンス監視**:
   - ユーザー入力から 150ms 後に `QueryValidator.validate()` を実行。入力が空または有効な場合はエラー状態をクリア。
3. **視覚的フィードバック UI**:
   - 入力欄下部にインラインヒントバッジ、未終了クォートや括弧の閉じ忘れに対するガイドを表示。
   - 不正なキーワード（例: `AUTHR:` → `author:`）に対する Levenshtein 推薦候補のクリック適用。
4. **ビルド & テスト**:
   - Closure Compiler 型定義（`externs/`）の整合性を保ち、ビルドおよび自動テストを検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `#searchInput` および `#globalSearchInput` 入力時に `QueryValidator.validate()` がデバウンス実行されること。
- [ ] 構文エラー（未終了クォート、括弧不整合等）発生時に視覚的警告とガイダンスが表示されること。
- [ ] タイポ時に Levenshtein 診断による修正候補が提示されること。
- [ ] `make build_js` が 0 エラーで完了すること。
- [ ] 自動テストが 100% PASS すること。
