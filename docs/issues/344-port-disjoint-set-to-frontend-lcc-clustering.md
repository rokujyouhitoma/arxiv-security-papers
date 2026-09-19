---
ID: 344
種別: Feature
優先度: Medium
ステータス: Open (New)
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

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/disjoint-set.js`](../../site/js/frameworks/disjoint-set.js) (新規)
- [ ] [`site/externs.js`](../../site/externs.js) (`DisjointSetInterface` 型定義追加)
- [ ] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (テストケース追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/344-port-disjoint-set-to-frontend-lcc-clustering`

1. **`DisjointSet` クラスの設計と実装**:
   - `constructor(elements = [])`
   - メソッド: `find(x)`, `union(x, y)`, `connected(x, y)`, `getComponentCount()`, `getComponents()`, `getLargestComponent()`
   - 経路圧縮（Path Compression）およびランク結合（Union by Rank）の完全実装
   - `Map` を用いた任意の識別子（論文 ID / タグ文字列）の効率的マッピング
2. **Closure Compiler 適合**:
   - `site/externs.js` に `DisjointSet` の型定義を追加
3. **グラフキャンバス連携**:
   - グラフ描画時の LCC 強調表示トグルおよび孤立クラスタ抽出フィルターへの適用準備

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/disjoint-set.js` が実装され、JSDoc 型アノテーションが付与されていること
- [ ] 経路圧縮およびランク結合による計算量 $O(\alpha(N))$ が実現されていること
- [ ] `site/externs.js` に型定義が追加され、`make build_js` で警告 0 件であること
- [ ] 10,000 要素規模の連結成分テストがミリ秒単位で完了すること
- [ ] `tests/web/test_frontend_frameworks.py` にテストが追加され 100% PASS すること
- [ ] `make verify_quality` が完全通過すること
