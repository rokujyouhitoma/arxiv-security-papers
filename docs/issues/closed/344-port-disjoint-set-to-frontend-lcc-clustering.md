---
ID: 344
種別: Feature
優先度: Medium
ステータス: Closed (完了)
完了日: 2026-09-19
---

# [FEAT] DisjointSet: src/core/structures/disjoint_set.py の JS 移植と LCC 計算 (ID: 344)

## 1. 概要 / Summary

バックエンド `src/core/structures/disjoint_set.py` で実装されている素集合データ構造（Union-Find）を、Web フロントエンド向け純粋 JavaScript モジュール `site/js/frameworks/disjoint-set.js` に忠実に移植する。

ナレッジグラフ画面（`site/dashboard.html` / `site/app.js`）において、数千件規模の論文ノードおよび引用・共起エッジから「最大連結成分（Largest Connected Component, LCC）」および「孤立ノード群（Research Gaps / Isolates）」をブラウザ上でミリ秒オーダー（ほぼ $O(E \cdot \alpha(V))$）で即座に特定・クラスタリングする機能を提供する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 6.2, 8)
  - [DSN-02: 全体低位アーキテクチャ設計書 (共通データ構造基盤)](../designs/DSN-02-low_level_design.md)
  - [DSN-14: 論文・脅威ナレッジグラフ & エンジニアリングダッシュボード設計書](../designs/DSN-14-graph_engineering_dashboard.md)
- 移植元コード:
  - `src/core/structures/disjoint_set.py`
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)
  - [Issue 348: GraphCanvasEngine: site/dashboard.html からの力学モデル・Canvas 描画の完全分離](348-extract-graph-canvas-engine-from-dashboard.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`site/js/frameworks/disjoint-set.js`](../../site/js/frameworks/disjoint-set.js) (新規作成)
- [x] [`site/externs.js`](../../site/externs.js) (`DisjointSetInterface` 型定義追加)
- [x] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [x] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (テストケース追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/344-port-disjoint-set-to-frontend-lcc-clustering`

1. **`DisjointSet` クラスの設計と実装 (`site/js/frameworks/disjoint-set.js`)**:
   - 内部データ構造:
     - `_parent`: `Map<*, *>`（要素ごとの親参照マップ）
     - `_rank`: `Map<*, number>`（ランク木深さの境界値）
     - `_size`: `Map<*, number>`（各根ノード配下の連結成分サイズ）
     - `_componentsCount`: `number`（独立した素集合の総数）
   - メソッド群:
     - `add(x)`: 要素登録（$O(1)$）
     - `find(x)`: 反復的経路圧縮（Iterative Path Compression）による根ノード探索（逆アッカーマン関数 $O(\alpha(N))$）
     - `union(x, y)`: ランク結合（Union by Rank）による部分木統合と成分数デクリメント
     - `connected(x, y)`: 同一連結成分判定
     - `componentSize(x)`: $x$ が属する成分サイズの取得
     - `componentCount()` / `getComponentCount()`: 独立集合総数
     - `getComponents()`: 各代表元をキーとするグループマップ
     - `getLargestComponent()`: 最大連結成分（LCC）の要素リスト
     - `getIsolates()`: 次数 0 またはサイズ 1 の孤立要素リスト
     - `clear()`: リセット
   - セキュリティ & 堅牢性:
     - 循環参照やスタックオーバーフローを避けるため再帰ではなく反復ループで経路圧縮を実施
     - `Map` キーとして文字列、数値、オブジェクト参照を安全に受容
2. **Google Closure Compiler 適合 (`site/externs.js`)**:
   - `DisjointSetInterface` を定義し、全公開メソッドの JSDoc シグネチャを宣言
3. **ビルドパイプライン登録 (`Makefile`)**:
   - `JS_SRCS` に `site/js/frameworks/disjoint-set.js` を追加
4. **統合テスト作成 (`tests/web/test_frontend_frameworks.py`)**:
   - `EXPECTED_MODULES`, `required_interfaces`, `core_framework_symbols` に登録
   - Node.js 連携テストにより、10,000 要素の Union-Find 操作、LCC 抽出、孤立ノード判定がミリ秒オーダーで完了することを実機検証

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `site/js/frameworks/disjoint-set.js` が実装され、JSDoc 型アノテーションが付与されていること
- [x] 経路圧縮およびランク結合による計算量 $O(\alpha(N))$ が実現されていること
- [x] `site/externs.js` に型定義が追加され、`make build_js` で警告 0 件であること
- [x] 10,000 要素規模の連結成分テストがミリ秒単位で完了すること
- [x] `tests/web/test_frontend_frameworks.py` にテストが追加され 100% PASS すること
- [x] `make check_format` および `make static_analysis` が完全通過すること


