---
ID: 419
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] クライアントサイド CTI グラフクエリ DSL の AOT 生成とダッシュボード統合 (ID: 419)

## 1. 概要 / Summary

本リポジトリでは、CTI ナレッジグラフ検索用の Cypher ライクなクエリ言語仕様が `grammars/graph_query.peg`（Issue #300）として策定され、バックエンドでは AOT 生成されたパーサーおよびクエリエグゼキュータが稼働している。
一方、Web ダッシュボード（`site/js/dashboard.js`）では、ユーザーがクエリ入力バー（`#graphQueryInput`）から入力したクエリをサーバーサイド API（`/api/graph/query?q=...`）に丸ごと送信しており、クライアントサイドでの入力中のリアルタイム事前構文検証（プレバリデーション）や、すでにブラウザ内に読み込まれているインメモリメッシュ（`ctiRawNodes`, `ctiRawEdges`）に対するオフライン・低遅延のローカルグラフ探索・フィルタリング機能が存在しない。

本 Issue では、Issue #417〜#427 で完成した PEG AOT コンパイラ（`--target js`, `--ast-only`, `--no-runtime`, 共有 `peg-runtime.js`）を活用し、`grammars/graph_query.peg` からブラウザ用パーサー `site/js/frameworks/cti-query-parser.js` を自動生成する。さらに、パースされた AST を受け取りインメモリグラフに対して高速に条件合致ノード・エッジを抽出する軽量評価エンジン `site/js/frameworks/cti-query-evaluator.js`（または UMD モジュール）を実装し、`dashboard.js` と連動させることで、即時フィードバックとオフライン耐性を備えたハイブリッド CTI グラフ探索基盤を実現する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第7.3節 CTI ナレッジグラフ クエリ DSL、第13節 Phase 6 JavaScript コードジェネレータ基盤、第13.7節 parseWithDiagnostics、第13.8節 モジュール化ランタイム共有)
  - [`docs/designs/DSN-18-property_graph_database_engine.md`](../designs/DSN-18-property_graph_database_engine.md) (CTI ナレッジグラフ クエリ仕様)
- **関連 Issue**:
  - Issue #300: CTI ナレッジグラフ クエリ DSL の宣言的 AOT 換装 (`grammars/graph_query.peg`)
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #423: PEG AOT コンパイラにおける --ast-only 汎用構文木生成とアクション抽象化の実装
  - Issue #425: JS コードジェネレータにおける CharClass の文字コード範囲判定化と ReDoS 根絶
  - Issue #426: JS 生成パーサーにおける PEGSyntaxError 診断情報拡充と parseWithDiagnostics API の実装
  - Issue #427: PEG AOT コンパイラにおける --no-runtime モジュール化と外部ランタイム共有の導入

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 文法およびコンパイラ・ビルド基盤
- [ ] [`grammars/graph_query.peg`](../../grammars/graph_query.peg)（AOT コンパイル互換性検証）
- [ ] [`site/js/frameworks/cti-query-parser.js`](../../site/js/frameworks/cti-query-parser.js)（AOT 生成パーサー: `--target js --ast-only --no-runtime`）
- [ ] [`site/js/frameworks/cti-query-evaluator.js`](../../site/js/frameworks/cti-query-evaluator.js)（新規作成: AST 評価・インメモリグラフマッチングエンジン）
- [ ] [`Makefile`](../../Makefile)（`build_cti_query_parser` ビルドターゲットおよび `build_js` 前提連携）

### フロントエンド統合
- [ ] [`site/js/dashboard.js`](../../site/js/dashboard.js)（クエリ入力時のリアルタイム診断・ローカル高速フィルタフォールバック統合）
- [ ] [`site/dashboard.html`](../../site/dashboard.html)（スクリプトタグ読み込み順序の整合）
- [ ] [`site/app-min.js`](../../site/app-min.js) & [`site/dashboard-min.js`](../../site/dashboard-min.js)（Closure Compiler ビルド成果物）

### テストスイート
- [ ] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)（CTI グラフクエリの JS AOT 生成・Node.js 実行テスト）
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py)（クライアントサイド CTI 評価器の単体・統合テスト）

---

## 4. セキュリティ分析 (STRIDE Threat Model) と防御策

| 脅威分類 | 潜在的リスク | 防御策 |
| :---: | --- | --- |
| **Spoofing** | クエリを偽装して想定外の内部オブジェクトにアクセス | AST 評価器において `Object.prototype` や `__proto__` へのプロパティアクセスを拒否するホワイトリストプロパティ参照を採用。 |
| **Tampering** | クエリ入力値によるグラフ描画ステートの破壊 | 評価器は純粋関数として設計し、`ctiRawNodes` / `ctiRawEdges` を一切破壊・変更せず、マッチしたノード ID / エッジ ID の `Set` のみを返却。 |
| **Repudiation** | 構文エラー発生時の不透明性 | `parseWithDiagnostics` による正確な構文エラー位置・期待トークン表示を行い、不正入力を確実に可視化。 |
| **Information Disclosure** | エラーオブジェクトによる内部スタック漏洩 | パース失敗時はサニタイズされた `PEGSyntaxError` メッセージと行桁情報のみを UI 表示。 |
| **Denial of Service (ReDoS)** | 悪意ある入力によるブラウザメインスレッドの凍結 | Issue #425 で達成した文字コード直接比較（`CharClass`）および Packrat PEG の線形時間 $O(N)$ パース保証により ReDoS を根絶。評価器もノード数・エッジ数に比例する $O(V + E)$ 線形探索を保証。 |
| **Elevation of Privilege** | XSS 脆弱性（クエリ文字列の HTML インジェクション） | 診断メッセージおよびバッジへのテキスト描画時は `textContent` または `escapeHtml` を厳格に適用。 |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/419-client-side-cti-query-dsl-aot-integration`

### 5.1 AOT コンパイラによるパーサー自動生成
1. `python -m src.core.structures.peg_compiler grammars/graph_query.peg -o site/js/frameworks/cti-query-parser.js --target js --ast-only --no-runtime --class-name CTIQueryParser` を実行。
2. 生成された `CTIQueryParser` は独立した共有ランタイム `site/js/frameworks/peg-runtime.js` を参照し、UMD 形式（`window.CTIQueryParser` / `Application.frameworks.CTIQueryParser`）としてグローバルに公開。

### 5.2 クライアントサイド AST 評価器 (`site/js/frameworks/cti-query-evaluator.js`)
1. **データ構造**:
   - `CTIQueryEvaluator` クラスを提供。
   - `evaluate(ast, nodes, edges)`: AST の `kind`（`filter` または `path`）に応じてマッチ判定を実行。
2. **Filter Query 評価 (`kind === 'filter'`)**:
   - 各ノードの属性（`id`, `type`, `label`, `severity`, `title` 等）に対して、キー・値条件（例: `type:Vulnerability`, `cve:CVE-2024`）の合致を判定。
   - 複数条件（`AND`）をサポート。
3. **Path Query 評価 (`kind === 'path'`)**:
   - ノードパターン（`(p:Paper) -> (c:CVE)` 等）のマッチング。
   - ノードのラベル・タイプ条件とエッジの向き（`->`, `<-`, `--`）およびエッジラベルをインメモリ走査して合致するパスを抽出。
4. **返却値**:
   - `{ matchedNodeIds: Set<string>, matchedEdgeKeys: Set<string>, count: number }`

### 5.3 ダッシュボード UI 統合 (`site/js/dashboard.js` & `site/dashboard.html`)
1. `#graphQueryInput` の入力時に `CTIQueryParser.prototype.parseWithDiagnostics` を呼び出し、リアルタイム構文フィードバックを提供（エラー時はバッジに親切な構文エラーを表示）。
2. クエリ実行時（Enter キー押下または「探索」ボタンクリック時）:
   - まずローカルの `CTIQueryEvaluator` で高速インメモリマッチングを試行。
   - オフライン時またはローカルメッシュ探索時は即時ローカルハイライトを適用。
   - サーバー通信が有効な場合は `/api/graph/query` を呼び出し、サーバーサイドの大規模グラフ展開とシームレスに同期。

### 5.4 ビルド自動化と品質ゲート (`Makefile` & テスト)
1. `Makefile` に `build_cti_query_parser` ターゲットを追加し、`make build_js` の依存関係に設定。
2. `tests/test_peg_compiler_js.py` に `test_cti_query_parser_compilation_and_execution` を追加。
3. `tests/web/test_frontend_frameworks.py` に `CTIQueryEvaluator` のフィルタ・パスマッチテストを追加。
4. `make check`（フォーマット、静的解析、全テスト）の 100% PASS を確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `grammars/graph_query.peg` から `site/js/frameworks/cti-query-parser.js` が `--target js --ast-only --no-runtime` で決定論的に生成されること。
- [ ] 生成パーサーが `peg-runtime.js` を外部解決し、Node.js およびブラウザ双方で例外なくロード・パース可能であること。
- [ ] `site/js/frameworks/cti-query-evaluator.js` が実装され、フィルタクエリおよびパスクエリの双方がインメモリメッシュに対して $O(V + E)$ で正確に合致判定できること。
- [ ] `site/js/dashboard.js` にてクエリ入力の事前検証とローカル評価が連動し、オフライン・即時プレビューが機能すること。
- [ ] `Makefile` にビルドルールが追加され、`make build_js` が 0 エラーで完了すること。
- [ ] `tests/test_peg_compiler_js.py` および `tests/web/test_frontend_frameworks.py` の全テストが PASS すること。
- [ ] Xenon Rank A、flake8、mypy --strict src を 100% パスすること。

