---
ID: 418
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Webフロントエンド構文解析基盤の全面PEG刷新 (ID: 418)

## 1. 概要 / Summary

本 Issue は、Web フロントエンド（`site/js/`）に点在する手書き正規表現・文字列分割による脆弱なパース処理を排除し、プロジェクト標準の Packrat PEG パーサーエンジンおよび AOT JavaScript コードジェネレータ（`--target js`）を活用した高信頼・堅牢な構文解析基盤へ全面刷新することを目的とする。

以下の 5 つの領域を段階的かつ体系的に刷新する：
1. **マークダウン・ブロック構文解析の PEG 化 (`site/js/lexer.js`)**:
   - 行単位の正規表現と `split('|')` に依存する現行トークナイザーを刷新。エスケープパイプ `\|` やインラインコード内の `|` に頑健なテーブルパーサー、ネスト引用・リストを正確に解析するブロック構文 PEG 化。
2. **クライアントサイド CTI グラフクエリ DSL エンジンの導入 (`site/js/dashboard.js`)**:
   - バックエンドの `grammars/cti_query.peg` から `--target js` によりクライアント向けパーサー `site/js/frameworks/cti-query-parser.js` を生成。ダッシュボード上で Cypher / DSL ライクなグラフクエリをブラウザ内で直接実行・可視化フィルタリング。
3. **検索入力のリアルタイム構文検証・ハイライト・オートコンプリート統合 (`site/app.js` × `query-validator.js`)**:
   - 既存の Lucene PEG パーサー（`query-validator.js`）の Packrat キャッシュ、最大エラー到達位置（`calcLineCol`）、Levenshtein 診断を検索入力 UI に直結。未終了クォートや不整合括弧のリアルタイム警告・オートコンプリート提示。
4. **クライアントサイドルーターの URL パス＆クエリ構文解析 (`site/js/frameworks/router.js`)**:
   - 正規表現の文字列合成や `split('&')` を廃止し、RFC 3986 準拠の URL / Route 構文解析パーサーを導入。型付きパラメータ抽出と複合クエリのデコードを安全化。
5. **Mermaid ダイアグラムの事前構文検証・サニタイザー (`site/js/markdown_compiler.js`)**:
   - レンダリング前に Mermaid（mindmap / flowchart）の構文を軽量 PEG で事前検証し、構文不正時のブラウザ赤文字エラーを抑止・安全にフォールバック。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第13節 Phase 6: Web フロントエンド連携 ＆ JavaScript コードジェネレータ基盤仕様)
  - [`docs/designs/DSN-18-property_graph_database_engine.md`](../designs/DSN-18-property_graph_database_engine.md) (CTI ナレッジグラフ クエリ仕様)
  - [`docs/designs/DSN-04-search_engine_and_platform.md`](../designs/DSN-04-search_engine_and_platform.md) (検索エンジン構文解析仕様)
- **関連 Issue**:
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #300: CTI ナレッジグラフ クエリ DSL の宣言的 AOT 換装 (`grammars/cti_query.peg`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### フロントエンドコア & フレームワーク
- [ ] [`site/js/lexer.js`](../../site/js/lexer.js)（ブロックレベルマークダウンパーサーの PEG 化）
- [ ] [`site/js/parser.js`](../../site/js/parser.js)（AST 構築の整合性維持・拡充）
- [ ] [`site/js/markdown_compiler.js`](../../site/js/markdown_compiler.js)（Mermaid 事前検証およびパイプライン統合）
- [ ] [`site/js/frameworks/cti-query-parser.js`](../../site/js/frameworks/cti-query-parser.js)（新規生成: CTI グラフクエリ JS AOT パーサー）
- [ ] [`site/js/dashboard.js`](../../site/js/dashboard.js)（CTI クエリ DSL 実行エンジンの統合）
- [ ] [`site/app.js`](../../site/app.js)（検索ボックスのリアルタイム構文検証・UI フィードバック）
- [ ] [`site/js/frameworks/router.js`](../../site/js/frameworks/router.js)（URL パス＆クエリ構文解析の PEG 化）
- [ ] [`site/js/frameworks/query-validator.js`](../../site/js/frameworks/query-validator.js)（コンビネータ追加・診断ヘルパー公開）

### 文法定義 & コンパイラ
- [ ] [`grammars/markdown_block.peg`](../../grammars/markdown_block.peg)（新規作成: マークダウンブロック文法定義）
- [ ] [`grammars/cti_query.peg`](../../grammars/cti_query.peg)（JS 生成互換性の確認・必要に応じた微調整）
- [ ] [`src/core/structures/peg_compiler/`](../../src/core/structures/peg_compiler/)（AOT コンパイラ出力の検証）

### ビルド成果物 & テスト
- [ ] [`site/app-min.js`](../../site/app-min.js)（Closure Compiler ビルド成果物）
- [ ] [`site/dashboard-min.js`](../../site/dashboard-min.js)（Closure Compiler ビルド成果物）
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py)（フロントエンド単体・統合テストの追加）
- [ ] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)（JS コードジェネレータ統合テストの拡充）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/418-web-frontend-comprehensive-peg-parser-migration`

1. **Phase 1: マークダウン・ブロック構文解析の PEG 化 (`site/js/lexer.js`)**
   - テーブル（エスケープ対応）、コードブロック、見出し、引用、リスト、段落を PEG コンビネータ（または AOT 生成コード）で厳密にパース。
   - `evaluator.js`（インライン）とシームレスに結合する 2 パス AST 構築。

2. **Phase 2: クライアントサイド CTI グラフクエリ DSL の AOT 生成・統合 (`site/js/dashboard.js`)**
   - `python -m src.core.structures.peg_compiler grammars/cti_query.peg -o site/js/frameworks/cti-query-parser.js --target js` をビルドパイプラインへ統合。
   - `dashboard.js` にクエリ入力フィールドを増設、または既存検索窓と連動し、クライアントサイドでグラフノード・エッジの条件判定・ハイライトを実行。

3. **Phase 3: 検索窓のリアルタイム構文検証・ハイライト・オートコンプリート (`site/app.js`)**
   - `#searchInput` および `#globalSearchInput` の `input` イベントで `QueryValidator.validate()` をデバウンス実行。
   - 構文エラー発生時に入力枠のエラー強調、未終了クォートや括弧不整合のエラーメッセージおよびタイポ修正候補のポップオーバー提示。

4. **Phase 4: クライアントサイドルーターの URL パス＆クエリ PEG 化 (`site/js/frameworks/router.js`)**
   - パスセグメント、パラメータ（`:id`）、ワイルドカード（`*`）、およびクエリ文字列（`?key=val&key2=val2`）を PEG コンビネータで決定論的にパース。

5. **Phase 5: Mermaid 構文のクライアント側事前検証・サニタイザー (`site/js/markdown_compiler.js`)**
   - Mermaid ブロック（mindmap / flowchart）の文法を簡易検証し、エラー時は安全に警告表示しクラッシュを防ぐ。

6. **Phase 6: ビルド・品質ゲート・テストの完備**
   - `make build_js` による Closure Compiler 最適化ビルド（0 エラー）。
   - Python & JS 双方の品質検証、回帰テストの実行。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/lexer.js` が PEG ベースに刷新され、テーブルエスケープやコードスパンを含むブロック解析が正確に行われること。
- [ ] `grammars/cti_query.peg` から生成された `cti-query-parser.js` が `site/js/dashboard.js` に統合され、ブラウザ内で CTI クエリが実行可能であること。
- [ ] `site/app.js` において、検索入力中のリアルタイム構文検証・エラー表示・オートコンプリートが動作すること。
- [ ] `site/js/frameworks/router.js` の URL パス＆クエリパースが PEG ベースに刷新されること。
- [ ] `site/js/markdown_compiler.js` において Mermaid 構文事前検証が機能し、不正構文でのクラッシュが防止されること。
- [ ] `make build_js` が成功し、`app-min.js` および `dashboard-min.js` が正常に出力されること。
- [ ] `tests/web/test_frontend_frameworks.py` および関連テストが 100% PASS すること。
- [ ] `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` が更新され、設計内容と整合していること。
