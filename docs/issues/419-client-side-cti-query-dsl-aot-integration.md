---
ID: 419
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] クライアントサイド CTI グラフクエリ DSL の AOT 生成とダッシュボード統合 (ID: 419)

## 1. 概要 / Summary

本リポジトリでは、CTI ナレッジグラフ検索用の Cypher ライクなクエリ言語仕様が `grammars/cti_query.peg`（Issue #300）として策定されているが、Web ダッシュボード（`site/js/dashboard.js`）は固定的な UI フィルタ関数群（LCC、Research Gap、関係性タイプ、信頼度など）のみに依存しており、高度な複合グラフ検索（例: `node.type == 'Vulnerability' AND degree >= 3`）をブラウザ上で柔軟に実行できない。

本 Issue では、Issue #417 で実装した PEG AOT コンパイラ（`--target js`）を活用し、`grammars/cti_query.peg` からブラウザ用パーサー `site/js/frameworks/cti-query-parser.js` を生成する。さらに、`dashboard.js` にクライアントサイドクエリ評価エンジンを組み込み、ダッシュボード上で Cypher / DSL ライクなクエリによる高速なグラフ探索・フィルタリング・ハイライトを実現する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第7.3節 CTI ナレッジグラフ クエリ DSL、第13節 Phase 6 JavaScript コードジェネレータ基盤)
  - [`docs/designs/DSN-18-property_graph_database_engine.md`](../designs/DSN-18-property_graph_database_engine.md) (CTI ナレッジグラフ クエリ仕様)
- **関連 Issue**:
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #300: CTI ナレッジグラフ クエリ DSL の宣言的 AOT 換装 (`grammars/cti_query.peg`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`grammars/cti_query.peg`](../../grammars/cti_query.peg)（JS 生成互換性の検証と必要に応じた文法調整）
- [ ] [`site/js/frameworks/cti-query-parser.js`](../../site/js/frameworks/cti-query-parser.js)（AOT 生成パーサー）
- [ ] [`site/js/dashboard.js`](../../site/js/dashboard.js)（クエリパーサー呼び出しと AST に基づくグラフフィルタリング）
- [ ] [`site/dashboard.html`](../../site/dashboard.html)（CTI クエリ入力 UI の設置または連動）
- [ ] [`Makefile`](../../Makefile)（`cti-query-parser.js` のビルド自動化ルール追加）
- [ ] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)（CTI クエリ JS AOT コンパイルテスト）
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py)（ダッシュボード CTI クエリ実行テスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/419-client-side-cti-query-dsl-aot-integration`

1. **AOT コンパイラによる JS 出力**:
   - `python -m src.core.structures.peg_compiler grammars/cti_query.peg -o site/js/frameworks/cti-query-parser.js --target js --class-name CTIQueryParser` を実行し、ブラウザで動作する構文解析器を生成。
2. **クライアント側 AST 評価器 (Evaluator)**:
   - パースされた AST（ノード条件、エッジ条件、属性フィルタ）を受け取り、ブラウザ内の `ctiRawNodes` / `ctiRawEdges` に対して条件合致を判定する純粋関数を実装。
3. **ダッシュボード UI 統合**:
   - CTI グラフヘッダーの検索入力または専用クエリバーからクエリを入力可能とし、合致するノード・エッジの強調表示とリアルタイムカウント更新を実装。
4. **ビルド & テスト**:
   - `Makefile` に `build_cti_query_parser` ターゲットを追加し、`make build_js` の前提として自動生成。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `grammars/cti_query.peg` から `site/js/frameworks/cti-query-parser.js` が決定論的に生成されること。
- [ ] 生成されたパーサーが Node.js およびブラウザ双方でエラーなく動作すること。
- [ ] `site/js/dashboard.js` において CTI クエリ DSL のフィルタリングが機能し、条件合致ノード・エッジが正常に描画されること。
- [ ] `make build_js` が 0 エラーでパスすること。
- [ ] 自動テストが 100% PASS すること。
